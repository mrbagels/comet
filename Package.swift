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
    .library(name: "CometOpenAPIGenerator", targets: ["CometOpenAPIGenerator"]),
    .library(name: "CometSQLiteData", targets: ["CometSQLiteData"]),
    .library(name: "CometTCA", targets: ["CometTCA"]),
    .library(name: "CometTesting", targets: ["CometTesting"]),
    .executable(name: "comet-openapi-generate", targets: ["CometOpenAPIGenerate"]),
  ],
  dependencies: [
    .package(url: "https://github.com/jpsim/Yams.git", from: "6.2.2"),
    .package(url: "https://github.com/apple/swift-http-types", from: "1.3.0"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies", from: "1.9.2"),
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.20.0"),
    .package(url: "https://github.com/pointfreeco/sqlite-data", from: "1.6.6"),
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
      name: "CometSQLiteData",
      dependencies: [
        "Comet",
        .product(name: "Dependencies", package: "swift-dependencies"),
        .product(name: "SQLiteData", package: "sqlite-data"),
      ]
    ),
    .target(
      name: "CometTesting",
      dependencies: [
        "Comet",
        .product(name: "HTTPTypes", package: "swift-http-types")
      ]
    ),
    .target(
      name: "CometOpenAPIGenerator",
      dependencies: [
        .product(name: "Yams", package: "Yams")
      ]
    ),
    .executableTarget(
      name: "CometOpenAPIGenerate",
      dependencies: [
        "CometOpenAPIGenerator"
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
      name: "CometSQLiteDataTests",
      dependencies: [
        "CometSQLiteData",
        .product(name: "DependenciesTestSupport", package: "swift-dependencies")
      ]
    ),
    .testTarget(
      name: "CometTestingTests",
      dependencies: [
        "CometTesting"
      ]
    ),
    .testTarget(
      name: "CometOpenAPIGeneratorTests",
      dependencies: [
        "CometOpenAPIGenerator"
      ]
    ),
  ]
)
