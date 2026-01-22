// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PRUUF",
    platforms: [
        .iOS(.v15),
        .macOS(.v10_15)  // Required by Supabase SDK for command line builds
    ],
    products: [
        .library(
            name: "PRUUF",
            targets: ["PRUUF"]
        ),
    ],
    dependencies: [
        // Supabase Swift SDK
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.0.0"),
        // KeychainSwift for secure token storage
        .package(url: "https://github.com/evgenyneu/keychain-swift.git", from: "24.0.0"),
    ],
    targets: [
        .target(
            name: "PRUUF",
            dependencies: [
                .product(name: "Supabase", package: "supabase-swift"),
                .product(name: "KeychainSwift", package: "keychain-swift"),
            ],
            path: "PRUUF"
        ),
        .testTarget(
            name: "PRUUFTests",
            dependencies: ["PRUUF"],
            path: "Tests/PRUUFTests"
        ),
    ]
)
