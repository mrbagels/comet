#!/usr/bin/env bash
set -euo pipefail

package_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workdir="$(mktemp -d "${TMPDIR:-/tmp}/comet-fresh-client.XXXXXX")"
trap 'rm -rf "$workdir"' EXIT

escaped_root="${package_root//\\/\\\\}"
escaped_root="${escaped_root//\"/\\\"}"

mkdir -p "$workdir/Sources/FreshClient"

cat > "$workdir/Package.swift" <<SWIFT
// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "FreshClient",
  platforms: [
    .iOS(.v18),
    .macOS(.v15),
    .visionOS(.v2),
  ],
  dependencies: [
    .package(path: "$escaped_root"),
  ],
  targets: [
    .executableTarget(
      name: "FreshClient",
      dependencies: [
        .product(name: "Comet", package: "comet"),
        .product(name: "CometTesting", package: "comet"),
      ]
    ),
  ]
)
SWIFT

cat > "$workdir/Sources/FreshClient/main.swift" <<'SWIFT'
import Comet
import CometTesting
import Foundation

struct SmokeRequest: APIRequest {
  let path: Path = "smoke"
  let method: HTTPMethod = .get
  let responseSerializer: ResponseSerializer<String> = .string()

  var options: RequestOptions {
    RequestOptions(metadata: RequestMetadata(name: "FreshClientSmoke"))
  }
}

@main
struct Smoke {
  static func main() async throws {
    let client = HTTPClient.mock(
      baseURL: URL(string: "https://comet.local")!
    ) { (request: PreparedRequest) throws(NetworkError) -> RawResponse in
      guard request.url.path == "/smoke" else {
        throw NetworkError.invalidRequest("Unexpected path: \(request.url.path)")
      }
      return RawResponse(data: Data("ok".utf8), statusCode: 200)
    }

    let response = try await client.send(SmokeRequest())
    guard response == "ok" else {
      throw NetworkError.invalidRequest("Unexpected response: \(response)")
    }

    print("fresh-client smoke passed")
  }
}
SWIFT

swift run --package-path "$workdir" FreshClient
