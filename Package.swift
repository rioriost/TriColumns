// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PseudoTweetDeck",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PseudoTweetDeck", targets: ["PseudoTweetDeck"])
    ],
    targets: [
        .executableTarget(
            name: "PseudoTweetDeck",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("WebKit")
            ]
        )
    ]
)
