import AppKit
import Darwin
import WebKit

/// Owns only its private staging directories, never the user's destination.
final class DownloadFileTransaction: @unchecked Sendable {
    let downloadURL: URL
    let destinationURL: URL

    private enum Phase {
        case downloading, finalizing, finished
    }

    private let directory: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var phase = Phase.downloading
    private var cancelled = false
    private var securityScopeIsActive: Bool
    private var ownsDirectory = false

    init(
        destinationURL: URL,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        fileManager: FileManager = .default
    ) throws {
        self.destinationURL = destinationURL
        self.fileManager = fileManager
        directory = temporaryDirectory.appendingPathComponent("TriColumns-download-\(UUID().uuidString)", isDirectory: true)
        downloadURL = directory.appendingPathComponent("download")
        securityScopeIsActive = destinationURL.startAccessingSecurityScopedResource()

        // mkdir, unlike createDirectory, fails if the directory already exists.
        let result = directory.withUnsafeFileSystemRepresentation { path in
            path.map { Darwin.mkdir($0, 0o700) } ?? -1
        }
        guard result == 0 else {
            let error = Self.fileError(at: directory)
            releaseSecurityScope()
            throw error
        }
        ownsDirectory = true
    }

    deinit {
        if ownsDirectory {
            do { try removeOwnedDirectory(directory) }
            catch { NSLog("Download cleanup: %@", error.localizedDescription) }
        }
        releaseSecurityScope()
    }

    /// May run off the main actor. Cancellation and the final rename are serialized.
    func finalize() throws {
        try lock.withLock {
            guard phase == .downloading, !cancelled else {
                throw CocoaError(.userCancelled)
            }
            phase = .finalizing
        }

        var replacementDirectory: URL?
        var operationError: Error?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: destinationURL, options: .forReplacing, error: &coordinationError) { destination in
            do {
                try checkCancellation()
                let attributes = try fileManager.attributesOfItem(atPath: downloadURL.path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw CocoaError(.fileReadCorruptFile, userInfo: [NSURLErrorKey: downloadURL])
                }

                // This OS-provided directory is writable under App Sandbox and is on
                // the destination volume, even when the download was on another disk.
                let staging = try fileManager.url(
                    for: .itemReplacementDirectory,
                    in: .userDomainMask,
                    appropriateFor: destination,
                    create: true
                )
                replacementDirectory = staging
                let preparedFile = staging.appendingPathComponent("download")
                try fileManager.copyItem(at: downloadURL, to: preparedFile)
                do {
                    let original = try fileManager.attributesOfItem(atPath: destination.path)
                    if original[.type] as? FileAttributeType == .typeRegular,
                       let permissions = original[.posixPermissions] as? NSNumber {
                        try fileManager.setAttributes(
                            [.posixPermissions: permissions.intValue & 0o777],
                            ofItemAtPath: preparedFile.path
                        )
                    }
                } catch CocoaError.fileReadNoSuchFile {
                    // A new destination has no permissions to preserve.
                } catch CocoaError.fileNoSuchFile {
                    // FileManager can use either missing-file error code.
                }

                try lock.withLock {
                    guard !cancelled else { throw CocoaError(.userCancelled) }
                    // A single same-volume rename leaves the old pathname intact on
                    // failure. replaceItemAt can instead relocate it on failure.
                    let result = preparedFile.withUnsafeFileSystemRepresentation { source in
                        destination.withUnsafeFileSystemRepresentation { target in
                            guard let source, let target else { return Int32(-1) }
                            return Darwin.rename(source, target)
                        }
                    }
                    guard result == 0 else { throw Self.fileError(at: destination) }
                }
            } catch {
                operationError = error
            }
        }

        var errors = [operationError, coordinationError].compactMap { $0 }
        if let replacementDirectory {
            do { try removeOwnedDirectory(replacementDirectory) } catch { errors.append(error) }
        }
        do { try removeDownloadDirectory() } catch { errors.append(error) }
        lock.withLock { phase = .finished }
        releaseSecurityScope()
        try Self.throwErrors(errors)
    }

    /// Call after WebKit has stopped writing, or while finalize() owns the file.
    func cancel() throws {
        let shouldCleanUp = lock.withLock {
            cancelled = true
            guard phase == .downloading else { return false }
            phase = .finished
            return true
        }
        guard shouldCleanUp else { return }
        defer { releaseSecurityScope() }
        try removeDownloadDirectory()
    }

    private func checkCancellation() throws {
        try lock.withLock {
            if cancelled { throw CocoaError(.userCancelled) }
        }
    }

    private func releaseSecurityScope() {
        let shouldStop = lock.withLock {
            let active = securityScopeIsActive
            securityScopeIsActive = false
            return active
        }
        if shouldStop { destinationURL.stopAccessingSecurityScopedResource() }
    }

    private func removeOwnedDirectory(_ url: URL) throws {
        do {
            try fileManager.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    private func removeDownloadDirectory() throws {
        try removeOwnedDirectory(directory)
        ownsDirectory = false
    }

    private static func fileError(at url: URL) -> Error {
        let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        return CocoaError(.fileWriteUnknown, userInfo: [
            NSFilePathErrorKey: url.path,
            NSUnderlyingErrorKey: underlying
        ])
    }

    private static func throwErrors(_ errors: [Error]) throws {
        guard let first = errors.first else { return }
        guard errors.count > 1 else { throw first }
        let error = first as NSError
        var userInfo = error.userInfo
        userInfo[NSMultipleUnderlyingErrorsKey] = errors
        throw NSError(domain: error.domain, code: error.code, userInfo: userInfo)
    }
}

@MainActor
final class DownloadCoordinator: NSObject, WKDownloadDelegate {
    @MainActor
    private final class DownloadState {
        let download: WKDownload
        weak var origin: WKWebView?
        var panel: NSSavePanel?
        var decision: (@MainActor @Sendable (URL?) -> Void)?
        var transaction: DownloadFileTransaction?
        var isFinalizing = false

        init(download: WKDownload, origin: WKWebView) {
            self.download = download
            self.origin = origin
        }

        func resolveDestination(_ url: URL?) {
            let completion = decision
            decision = nil
            completion?(url)
        }
    }

    private let presentPanel: (NSSavePanel, WKWebView, @escaping (NSApplication.ModalResponse) -> Void) -> Void
    private let reportError: (Error, WKWebView?) -> Void
    private var downloads: [ObjectIdentifier: DownloadState] = [:]

    init(
        presentPanel: @escaping (NSSavePanel, WKWebView, @escaping (NSApplication.ModalResponse) -> Void) -> Void,
        reportError: @escaping (Error, WKWebView?) -> Void
    ) {
        self.presentPanel = presentPanel
        self.reportError = reportError
        super.init()
    }

    deinit {
        let states = Array(downloads.values)
        Task { @MainActor in
            for state in states { Self.stopDownload(state) }
        }
    }

    func start(_ download: WKDownload, from origin: WKWebView) {
        let key = ObjectIdentifier(download)
        guard downloads[key] == nil else { return }
        downloads[key] = DownloadState(download: download, origin: origin)
        download.delegate = self
    }

    func cancelDownloads(from origin: WKWebView) {
        for state in Array(downloads.values) where state.origin === origin {
            cancel(state)
        }
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        guard let state = downloads[ObjectIdentifier(download)] else {
            completionHandler(nil)
            return
        }
        guard let origin = state.origin, state.decision == nil, state.transaction == nil else {
            cancel(state)
            completionHandler(nil)
            return
        }
        state.decision = completionHandler
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFilename
        panel.canCreateDirectories = true
        state.panel = panel
        presentPanel(panel, origin) { [weak self, weak state, weak panel] response in
            guard let self, let state,
                  self.downloads[ObjectIdentifier(state.download)] === state,
                  state.decision != nil else { return }
            let destination = panel?.url
            state.panel = nil
            guard response == .OK, let destination, state.origin != nil else {
                self.cancel(state)
                return
            }
            do {
                let transaction = try DownloadFileTransaction(destinationURL: destination)
                state.transaction = transaction
                state.resolveDestination(transaction.downloadURL)
            } catch {
                let origin = state.origin
                self.cancel(state)
                self.reportError(error, origin)
            }
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        guard let state = downloads[key], !state.isFinalizing else { return }
        guard state.origin != nil else {
            cancel(state)
            return
        }
        guard let transaction = state.transaction else {
            cancel(state)
            reportError(CocoaError(.fileWriteUnknown), state.origin)
            return
        }
        state.isFinalizing = true
        download.delegate = nil
        Task { [weak self, state] in
            let error = await Task.detached {
                do {
                    try transaction.finalize()
                    return nil as Error?
                } catch {
                    return error
                }
            }.value
            guard let self, self.downloads[key] === state else {
                if let error, !Self.isCancellation(error) { Self.logCleanupError(error) }
                return
            }
            self.downloads.removeValue(forKey: key)
            if let error, !Self.isCancellation(error) {
                self.reportError(error, state.origin)
            }
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let state = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        download.delegate = nil
        state.resolveDestination(nil)
        state.panel?.cancel(nil)
        state.panel = nil
        do { try state.transaction?.cancel() } catch { Self.logCleanupError(error) }
        if !Self.isCancellation(error) { reportError(error, state.origin) }
    }

    private func cancel(_ state: DownloadState) {
        downloads.removeValue(forKey: ObjectIdentifier(state.download))
        Self.stopDownload(state)
    }

    private static func stopDownload(_ state: DownloadState) {
        state.download.delegate = nil
        state.resolveDestination(nil)
        state.panel?.cancel(nil)
        state.panel = nil
        if state.isFinalizing {
            do { try state.transaction?.cancel() } catch { Self.logCleanupError(error) }
        } else {
            // Keep staging and its security scope alive until WebKit acknowledges
            // cancellation; a queued writer must not recreate a deleted partial file.
            let transaction = state.transaction
            state.download.cancel { _ in
                do { try transaction?.cancel() } catch { Self.logCleanupError(error) }
            }
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let error = error as NSError
        return (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled)
            || (error.domain == NSCocoaErrorDomain && error.code == NSUserCancelledError)
    }

    private static func logCleanupError(_ error: Error) {
        NSLog("Download cleanup: %@", error.localizedDescription)
    }
}
