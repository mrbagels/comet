// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "Comet",
  platforms: [
    .iOS(.v18),
    .macOS(.v15),
    .visionOS(.v2),
  ],
  products: [
    .library(name: "Comet", targets: ["Comet"]),
    .library(name: "CometTCA", targets: ["CometTCA"]),
    .library(name: "CometTesting", targets: ["CometTesting"]),
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-http-types", from: "1.3.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.2"),
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.20.0"),
  ],
  targets: [
    .target(
      name: "Comet",
      dependencies: [
        .product(name: "HTTPTypes", package: "swift-http-types")
      ]
    ),
    .target(
      name: "CometTCA",
      dependencies: [
        "Comet",
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
      ]
    ),
    .target(
      name: "CometTesting",
      dependencies: [
        "Comet",
        .product(name: "HTTPTypes", package: "swift-http-types")
      ]
    ),
    .testTarget(
      name: "CometTests",
      dependencies: [
        "Comet",
        .product(name: "HTTPTypes", package: "swift-http-types")
      ]
    ),
    .testTarget(
      name: "CometTCATests",
      dependencies: [
        "CometTCA",
        "CometTesting"
      ]
    ),
    .testTarget(
      name: "CometTestingTests",
      dependencies: [
        "CometTesting"
      ]
    ),
  ]
)
