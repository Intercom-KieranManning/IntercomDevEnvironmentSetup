// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ClientiOS",
    platforms: [
        // .v15 to support older test devices (e.g. an iPhone still on iOS 15.8.3) being
        // repurposed as a dedicated CCTV camera — see README's "known limitations" section for
        // which SwiftUI APIs this constrains.
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "ClientiOS",
            targets: ["ClientiOS"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC.git", from: "132.0.0"),
    ],
    targets: [
        // Pure Foundation logic (models, HTTP/WS clients, token status math) with no
        // SwiftUI/WebRTC/Security dependency, so it builds and tests on plain Linux Swift —
        // there's no iOS simulator or Xcode host available here, so this is the only layer
        // we can actually run automated tests against on this machine.
        .target(
            name: "ClientiOSCore"
        ),
        .testTarget(
            name: "ClientiOSCoreTests",
            dependencies: ["ClientiOSCore"]
        ),
        // The app target: SwiftUI, WebRTC, Keychain — only buildable for iOS via `xtool dev build`.
        .target(
            name: "ClientiOS",
            dependencies: [
                "ClientiOSCore",
                .product(name: "WebRTC", package: "WebRTC"),
            ]
        ),
    ]
)
