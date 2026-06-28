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
    .library(name: "CometSQLiteData", type: .static, targets: ["CometSQLiteData"]),
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
    .package(url: "https://github.com/groue/GRDB.swift", from: "7.11.1"),
    .package(url: "https://github.com/pointfreeco/swift-structured-queries", from: "0.32.0"),
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
        .product(name: "GRDB", package: "GRDB.swift"),
        .product(name: "SQLiteData", package: "sqlite-data"),
        .product(name: "StructuredQueries", package: "swift-structured-queries"),
        .product(name: "StructuredQueriesCore", package: "swift-structured-queries"),
        .product(name: "StructuredQueriesSQLite", package: "swift-structured-queries"),
        .product(name: "StructuredQueriesSQLiteCore", package: "swift-structured-queries"),
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
