// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "appattest-integrator",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.92.0"),
    ],
    targets: [
        .executableTarget(
            name: "AppAttestIntegrator",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
            ]
        ),
        .testTarget(
            name: "AppAttestIntegratorTests",
            dependencies: [
                .target(name: "AppAttestIntegrator"),
                .product(name: "XCTVapor", package: "vapor"),
            ]
        ),
    ]
)
