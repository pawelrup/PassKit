// swift-tools-version:5.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Dependencies declare other packages that this package depends on.
let dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/vapor/vapor.git", from: "4.8.0"),
    .package(url: "https://github.com/vapor/fluent.git", from: "4.0.0-rc.3.1"),
    .package(url: "https://github.com/vapor/apns.git", from: "1.0.0-rc.1.1"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.2.0"),
    .package(url: "https://github.com/pawelrup/PassGenerator.git", .exact("0.11.2"))
]

// Targets are the basic building blocks of a package. A target can define a module or a test suite.
// Targets can depend on other targets in this package, and on products in packages which this package depends on.
let targets: [Target] = [
    .target(name: "PassKit", dependencies: [
        .product(name: "Vapor", package: "vapor"),
        .product(name: "Fluent", package: "fluent"),
        .product(name: "APNS", package: "apns"),
        .product(name: "Logging", package: "swift-log"),
        "PassGenerator"
    ]),
    .testTarget(name: "PassKitTests", dependencies: ["PassKit"])
]

// Products define the executables and libraries produced by a package, and make them visible to other packages.
let products: [Product] = [
    .library(name: "PassKit", targets: ["PassKit"])
]

let package = Package(name: "PassKit", platforms: [.macOS(.v10_15)], products: products, dependencies: dependencies, targets: targets)
