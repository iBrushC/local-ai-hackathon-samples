// swift-tools-version: 5.10
//
// Meeting Scribe (native): Argmax Pro SDK example for macOS (Apple Silicon).
//
// Before `swift build`, log in to Argmax's private Swift package registry once:
//   swift package-registry set --global --scope argmaxinc https://api.argmaxinc.com/v1/sdk
//   swift package-registry login https://api.argmaxinc.com/v1/sdk/login --token <ARGMAX_SECRET_TOKEN>
//
import PackageDescription

let package = Package(
    name: "MeetingScribe",
    platforms: [
        // Pro SDK minimum: macOS 15 on M1 or newer (Intel Macs are not supported).
        .macOS(.v15),
    ],
    products: [
        .executable(name: "meeting-scribe", targets: ["MeetingScribe"]),
    ],
    dependencies: [
        // Pro SDK from the Argmax registry (not GitHub). `from:` == up to next major.
        // The install guide lists 3.0.6. Check the current version with:
        //   curl https://api.argmaxinc.com/v1/sdk/argmaxinc/argmax-sdk-swift -H "Authorization: Bearer $ARGMAX_SECRET_TOKEN"
        .package(id: "argmaxinc.argmax-sdk-swift", from: "3.0.6"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "MeetingScribe",
            dependencies: [
                .product(name: "Argmax", package: "argmaxinc.argmax-sdk-swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
    ]
)
