// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Dependencies declare other packages that this package depends on.
let dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0-beta"),
    .package(url: "https://github.com/vapor/fluent.git", from: "4.0.0-beta"),
    .package(url: "https://github.com/vapor/apns.git", from: "1.0.0-beta"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
    .package(url: "https://github.com/pawelrup/PassGenerator.git", .exact("0.8.5"))
]

// Targets are the basic building blocks of a package. A target can define a module or a test suite.
// Targets can depend on other targets in this package, and on products in packages which this package depends on.
let targets: [Target] = [
    .target(name: "PassKit", dependencies: ["Fluent", "Vapor", "APNS", "Logging", "PassGenerator"]),
    .testTarget(name: "PassKitTests", dependencies: ["PassKit"])
]

// Products define the executables and libraries produced by a package, and make them visible to other packages.
let products: [Product] = [
    .library(name: "PassKit", targets: ["PassKit"])
]

let package = Package(name: "PassKit", platforms: [.macOS(.v10_15)], products: products, dependencies: dependencies, targets: targets)
