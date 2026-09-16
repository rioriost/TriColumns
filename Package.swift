// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "TriColumns",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "TriColumns", targets: ["TriColumns"])
    ],
    targets: [
        .executableTarget(
            name: "TriColumns",
            path: "Sources/TriColumns",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit")
            ]
        ),
        .testTarget(
            name: "TriColumnsTests",
            dependencies: ["TriColumns"],
            path: "Tests/TriColumnsTests"
        )
    ]
)
