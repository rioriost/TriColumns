import Foundation
import XCTest
@testable import TriColumns

final class DownloadTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        let workingDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let base = fileManager.isWritableFile(atPath: workingDirectory.path)
            ? workingDirectory
            : try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        root = base.appendingPathComponent(".download-tests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        if let root { try fileManager.removeItem(at: root) }
        root = nil
    }

    func testDownloadDestinationDoesNotExistUntilWebKitWritesIt() throws {
        let destination = root.appendingPathComponent("saved.txt")
        let transaction = try makeTransaction(to: destination)

        XCTAssertFalse(fileManager.fileExists(atPath: transaction.downloadURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: transaction.downloadURL.deletingLastPathComponent().path))
        XCTAssertFalse(fileManager.fileExists(atPath: destination.path))
        XCTAssertNotEqual(transaction.downloadURL, destination)

        try transaction.cancel()
        XCTAssertFalse(fileManager.fileExists(atPath: transaction.downloadURL.deletingLastPathComponent().path))
    }

    func testSuccessfulNewFileIsCommittedOnlyAfterFinalization() throws {
        let destination = root.appendingPathComponent("saved.txt")
        let transaction = try makeTransaction(to: destination)
        try Data("new contents".utf8).write(to: transaction.downloadURL)
        XCTAssertFalse(fileManager.fileExists(atPath: destination.path))

        try transaction.finalize()

        XCTAssertEqual(try Data(contentsOf: destination), Data("new contents".utf8))
        XCTAssertFalse(fileManager.fileExists(atPath: transaction.downloadURL.deletingLastPathComponent().path))
    }

    func testSuccessfulReplacementPreservesOriginalUntilFinalization() throws {
        let destination = root.appendingPathComponent("existing.txt")
        let original = Data("original contents".utf8)
        try original.write(to: destination)
        let transaction = try makeTransaction(to: destination)
        XCTAssertEqual(try Data(contentsOf: destination), original)
        try Data("replacement contents".utf8).write(to: transaction.downloadURL)
        XCTAssertEqual(try Data(contentsOf: destination), original)

        try transaction.finalize()

        XCTAssertEqual(try Data(contentsOf: destination), Data("replacement contents".utf8))
        XCTAssertFalse(fileManager.fileExists(atPath: transaction.downloadURL.deletingLastPathComponent().path))
        try transaction.cancel()
        XCTAssertEqual(try Data(contentsOf: destination), Data("replacement contents".utf8))
    }

    func testReplacementDoesNotBroadenExistingFilePermissions() throws {
        let destination = root.appendingPathComponent("private.txt")
        try Data("private original".utf8).write(to: destination)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        let transaction = try makeTransaction(to: destination)
        try Data("replacement".utf8).write(to: transaction.downloadURL)
        try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: transaction.downloadURL.path)

        try transaction.finalize()

        let attributes = try fileManager.attributesOfItem(atPath: destination.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testCancellationPreservesOriginalAndCannotLaterCommit() throws {
        let destination = root.appendingPathComponent("existing.txt")
        let original = Data("do not lose me".utf8)
        try original.write(to: destination)
        let transaction = try makeTransaction(to: destination)
        try Data("partial download".utf8).write(to: transaction.downloadURL)

        try transaction.cancel()
        try transaction.cancel()

        XCTAssertThrowsError(try transaction.finalize()) { error in
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
            XCTAssertEqual((error as NSError).code, NSUserCancelledError)
        }
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertFalse(fileManager.fileExists(atPath: transaction.downloadURL.deletingLastPathComponent().path))
    }

    func testCancelledNewDownloadDoesNotCreateDestination() throws {
        let destination = root.appendingPathComponent("never-created.txt")
        let transaction = try makeTransaction(to: destination)
        try Data("partial".utf8).write(to: transaction.downloadURL)

        try transaction.cancel()

        XCTAssertFalse(fileManager.fileExists(atPath: destination.path))
        XCTAssertFalse(fileManager.fileExists(atPath: transaction.downloadURL.deletingLastPathComponent().path))
    }

    func testCancellationWhilePreparingReplacementPreservesOriginal() async throws {
        let destination = root.appendingPathComponent("existing.txt")
        let original = Data("original".utf8)
        try original.write(to: destination)
        let blockingManager = BlockingCopyFileManager()
        let transaction = try DownloadFileTransaction(
            destinationURL: destination,
            temporaryDirectory: root,
            fileManager: blockingManager
        )
        try Data("complete".utf8).write(to: transaction.downloadURL)
        let finalization = Task.detached { () -> Error? in
            do { try transaction.finalize(); return nil } catch { return error }
        }
        defer { blockingManager.resumeCopy.signal() }
        XCTAssertEqual(blockingManager.copyStarted.wait(timeout: .now() + 5), .success)

        try transaction.cancel()
        XCTAssertEqual(try Data(contentsOf: destination), original)
        blockingManager.resumeCopy.signal()
        let error = await finalization.value

        XCTAssertEqual((error as NSError?)?.code, NSUserCancelledError)
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertFalse(fileManager.fileExists(atPath: transaction.downloadURL.deletingLastPathComponent().path))
    }

    func testMissingDownloadFailsWithoutChangingOriginal() throws {
        let destination = root.appendingPathComponent("existing.txt")
        let original = Data("original".utf8)
        try original.write(to: destination)
        let transaction = try makeTransaction(to: destination)

        XCTAssertThrowsError(try transaction.finalize())

        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertFalse(fileManager.fileExists(atPath: transaction.downloadURL.deletingLastPathComponent().path))
    }

    func testFailedCommitPreservesExistingDirectoryAndItsContents() throws {
        let destination = root.appendingPathComponent("existing", isDirectory: true)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: false)
        let original = destination.appendingPathComponent("keep.txt")
        try Data("original".utf8).write(to: original)
        let transaction = try makeTransaction(to: destination)
        try Data("complete download".utf8).write(to: transaction.downloadURL)

        XCTAssertThrowsError(try transaction.finalize())

        XCTAssertEqual(try Data(contentsOf: original), Data("original".utf8))
        XCTAssertFalse(fileManager.fileExists(atPath: transaction.downloadURL.deletingLastPathComponent().path))
    }

    func testFailedCommitPreservesExistingImmutableFile() throws {
        let destination = root.appendingPathComponent("locked.txt")
        let original = Data("original immutable contents".utf8)
        try original.write(to: destination)
        do {
            try fileManager.setAttributes([.immutable: true], ofItemAtPath: destination.path)
        } catch {
            throw XCTSkip("The test filesystem does not support immutable files: \(error)")
        }
        defer { try? fileManager.setAttributes([.immutable: false], ofItemAtPath: destination.path) }
        let transaction = try makeTransaction(to: destination)
        try Data("complete download".utf8).write(to: transaction.downloadURL)

        XCTAssertThrowsError(try transaction.finalize())

        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertFalse(fileManager.fileExists(atPath: transaction.downloadURL.deletingLastPathComponent().path))
    }

    func testMissingDestinationDirectoryDoesNotRemoveUnrelatedFiles() throws {
        let unrelated = root.appendingPathComponent("keep.txt")
        try Data("unrelated".utf8).write(to: unrelated)
        let destination = root.appendingPathComponent("missing/saved.txt")
        let transaction = try makeTransaction(to: destination)
        try Data("complete download".utf8).write(to: transaction.downloadURL)

        XCTAssertThrowsError(try transaction.finalize())

        XCTAssertEqual(try Data(contentsOf: unrelated), Data("unrelated".utf8))
        XCTAssertFalse(fileManager.fileExists(atPath: destination.path))
        XCTAssertFalse(fileManager.fileExists(atPath: transaction.downloadURL.deletingLastPathComponent().path))
    }

    func testIndependentDownloadsWithTheSameFilenameDoNotShareStaging() throws {
        let firstDestination = root.appendingPathComponent("first.txt")
        let secondDestination = root.appendingPathComponent("second.txt")
        try Data("first original".utf8).write(to: firstDestination)
        let first = try makeTransaction(to: firstDestination)
        let second = try makeTransaction(to: secondDestination)
        XCTAssertNotEqual(first.downloadURL, second.downloadURL)
        XCTAssertNotEqual(first.downloadURL.deletingLastPathComponent(), second.downloadURL.deletingLastPathComponent())
        try Data("first partial".utf8).write(to: first.downloadURL)
        try Data("second complete".utf8).write(to: second.downloadURL)

        try first.cancel()
        XCTAssertEqual(try Data(contentsOf: second.downloadURL), Data("second complete".utf8))
        try second.finalize()

        XCTAssertEqual(try Data(contentsOf: firstDestination), Data("first original".utf8))
        XCTAssertEqual(try Data(contentsOf: secondDestination), Data("second complete".utf8))
    }

    func testFailedDownloadDoesNotInterfereWithAnotherDownloadToSameDestination() throws {
        let destination = root.appendingPathComponent("same.txt")
        try Data("original".utf8).write(to: destination)
        let failed = try makeTransaction(to: destination)
        let successful = try makeTransaction(to: destination)
        try Data("successful".utf8).write(to: successful.downloadURL)

        XCTAssertThrowsError(try failed.finalize())
        XCTAssertEqual(try Data(contentsOf: destination), Data("original".utf8))
        try successful.finalize()

        XCTAssertEqual(try Data(contentsOf: destination), Data("successful".utf8))
    }

    func testDeinitializationRemovesOnlyItsOwnPartialDownload() throws {
        let destination = root.appendingPathComponent("existing.txt")
        try Data("original".utf8).write(to: destination)
        var transaction: DownloadFileTransaction? = try makeTransaction(to: destination)
        let downloadURL = try XCTUnwrap(transaction?.downloadURL)
        try Data("partial".utf8).write(to: downloadURL)

        transaction = nil

        XCTAssertFalse(fileManager.fileExists(atPath: downloadURL.deletingLastPathComponent().path))
        XCTAssertEqual(try Data(contentsOf: destination), Data("original".utf8))
    }

    private func makeTransaction(to destination: URL) throws -> DownloadFileTransaction {
        try DownloadFileTransaction(destinationURL: destination, temporaryDirectory: root)
    }
}

private final class BlockingCopyFileManager: FileManager, @unchecked Sendable {
    let copyStarted = DispatchSemaphore(value: 0)
    let resumeCopy = DispatchSemaphore(value: 0)

    override func copyItem(at source: URL, to destination: URL) throws {
        try super.copyItem(at: source, to: destination)
        copyStarted.signal()
        guard resumeCopy.wait(timeout: .now() + 10) == .success else {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
