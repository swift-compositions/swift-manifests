// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "swift-manifests",
    platforms: [
        .macOS(.v27),
        .iOS(.v27),
        .tvOS(.v27),
        .watchOS(.v27),
        .visionOS(.v27)
    ],
    products: [
        .library(name: "Manifest Loader", targets: ["Manifest Loader"]),
        .library(name: "Manifest Resolver", targets: ["Manifest Resolver"]),
        .library(name: "Manifest Executable", targets: ["Manifest Executable"]),
        .library(name: "Manifests Test Support", targets: ["Manifests Test Support"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swift-atoms/swift-manifest.git", branch: "main", traits: ["Parser"]),
        .package(url: "https://github.com/swift-atoms/swift-package.git", branch: "main"),
        .package(url: "https://github.com/swift-standards/swift-spm-standard.git", branch: "main"),
        .package(url: "https://github.com/swift-standards/swift-uri-standard.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-environment.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-file-system.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-json.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-process.git", branch: "main"),
        .package(url: "https://github.com/swift-compositions/swift-strings.git", branch: "main"),
    ],
    targets: [

        .target(
            name: "Manifest Loader",
            dependencies: [
                .product(name: "Manifest", package: "swift-manifest"),
                .product(name: "Environment", package: "swift-environment"),
                .product(name: "File System", package: "swift-file-system"),
                .product(name: "JSON", package: "swift-json"),
                .product(name: "Process", package: "swift-process"),
                .product(name: "Strings", package: "swift-strings"),
            ]
        ),

        .target(
            name: "Manifest Resolver",
            dependencies: [
                .product(name: "Manifest", package: "swift-manifest"),
                "Manifest Loader",
                .product(name: "File System", package: "swift-file-system"),
                .product(name: "Process", package: "swift-process"),
                .product(name: "URI Standard", package: "swift-uri-standard"),
            ]
        ),

        .target(
            name: "Manifest Executable",
            dependencies: [
                .product(name: "Manifest", package: "swift-manifest"),
                .product(name: "Package", package: "swift-package"),
                .product(name: "SPM Standard", package: "swift-spm-standard"),
                .product(name: "File System", package: "swift-file-system"),
                .product(name: "Process", package: "swift-process"),
            ]
        ),

        .target(
            name: "Manifests Test Support",
            dependencies: [
                "Manifest Loader",
                "Manifest Resolver",
                .product(name: "Manifest Test Support", package: "swift-manifest"),
            ],
            path: "Tests/Support"
        ),

        .testTarget(
            name: "Manifest Loader Tests",
            dependencies: [
                "Manifest Loader",
                "Manifests Test Support",
                .product(name: "File System", package: "swift-file-system"),
            ]
        ),
        .testTarget(
            name: "Manifest Resolver Tests",
            dependencies: [
                "Manifest Resolver",
                "Manifests Test Support",
                .product(name: "File System", package: "swift-file-system"),
                .product(name: "URI Standard", package: "swift-uri-standard"),
            ]
        ),
        .testTarget(
            name: "Manifest Executable Tests",
            dependencies: [
                "Manifest Executable",
                "Manifests Test Support",
                .product(name: "File System", package: "swift-file-system"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)

for target in package.targets where ![.system, .binary, .plugin, .macro].contains(target.type) {
    let ecosystem: [SwiftSetting] = [
        .strictMemorySafety(),
        .enableUpcomingFeature("ExistentialAny"),
        .enableUpcomingFeature("InternalImportsByDefault"),
        .enableUpcomingFeature("MemberImportVisibility"),
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
        .enableExperimentalFeature("Lifetimes"),
        .enableUpcomingFeature("InferIsolatedConformances"),
    ]

    let package: [SwiftSetting] = []

    target.swiftSettings = (target.swiftSettings ?? []) + ecosystem + package
}
