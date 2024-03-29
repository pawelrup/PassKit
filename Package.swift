// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// Dependencies declare other packages that this package depends on.
let dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/vapor/vapor.git", .upToNextMinor(from: "4.65.1")),
    .package(url: "https://github.com/vapor/fluent.git", .upToNextMinor(from: "4.5.0")),
    .package(url: "https://github.com/vapor/apns.git", .upToNextMinor(from: "3.0.0")),
    .package(url: "https://github.com/apple/swift-log.git", .upToNextMinor(from: "1.4.4")),
    .package(url: "https://github.com/pawelrup/PassGenerator.git", .upToNextMinor(from: "1.3.0"))
]

// Targets are the basic building blocks of a package. A target can define a module or a test suite.
// Targets can depend on other targets in this package, and on products in packages which this package depends on.
let targets: [Target] = [
    .target(name: "PassKit", dependencies: [
        .product(name: "Vapor", package: "vapor"),
        .product(name: "Fluent", package: "fluent"),
        .product(name: "APNS", package: "apns"),
        .product(name: "Logging", package: "swift-log"),
		.product(name: "PassGenerator", package: "PassGenerator")
    ]),
    .testTarget(name: "PassKitTests", dependencies: [
        "PassKit",
        .product(name: "XCTVapor", package: "vapor")
    ])
]

// Products define the executables and libraries produced by a package, and make them visible to other packages.
let products: [Product] = [
    .library(name: "PassKit", targets: ["PassKit"])
]

let package = Package(
	name: "PassKit",
	platforms: [.macOS(.v12)],
	products: products,
	dependencies: dependencies,
	targets: targets,
	swiftLanguageVersions: [.v5]
)
