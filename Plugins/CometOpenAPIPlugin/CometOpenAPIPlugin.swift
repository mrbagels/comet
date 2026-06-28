import Foundation
import PackagePlugin

@main
struct CometOpenAPIPlugin: CommandPlugin {
  func performCommand(context: PluginContext, arguments: [String]) async throws {
    if arguments.contains("--help") || arguments.contains("-h") {
      print(Self.help)
      return
    }

    let options = try PluginOptions(
      arguments: arguments,
      packageDirectory: context.package.directoryURL
    )
    if let outputURL = options.outputURL {
      try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      Diagnostics.progress("Generating \(outputURL.path)")
    }

    let toolURL = try self.generatorToolURL()
    let process = Process()
    process.executableURL = toolURL
    process.arguments = options.toolArguments
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    try process.run()
    process.waitUntilExit()

    guard process.terminationReason == .exit && process.terminationStatus == 0 else {
      throw PluginError("comet-openapi-generate failed with exit code \(process.terminationStatus).")
    }
  }

  private func generatorToolURL() throws -> URL {
    let result = try self.packageManager.build(
      .product("comet-openapi-generate"),
      parameters: PackageManager.BuildParameters(configuration: .debug, logging: .concise)
    )
    guard result.succeeded else {
      throw PluginError(
        """
        Unable to build comet-openapi-generate.
        \(result.logText)
        """
      )
    }
    guard let executable = result.builtArtifacts.first(where: { artifact in
      artifact.kind == .executable && artifact.url.lastPathComponent == "comet-openapi-generate"
    }) else {
      throw PluginError("Built comet-openapi-generate, but no executable artifact was returned.")
    }
    return executable.url
  }

  private static let help = """
  Usage: swift package --allow-writing-to-package-directory comet-openapi-generate --input openapi.yaml --output Sources/API/GeneratedAPI.swift

  Input can be JSON or YAML. Paths are resolved from the package root unless absolute.
  Omit --output to print generated Swift to stdout.
  """
}

private struct PluginOptions {
  var inputURL: URL?
  var outputURL: URL?

  init(arguments: [String], packageDirectory: URL) throws {
    var positionalArguments: [String] = []
    var iterator = arguments.makeIterator()

    while let argument = iterator.next() {
      switch argument {
      case "--input", "-i":
        guard let value = iterator.next() else {
          throw PluginError("--input requires a path.")
        }
        self.inputURL = Self.resolve(value, relativeTo: packageDirectory)

      case "--output", "-o":
        guard let value = iterator.next() else {
          throw PluginError("--output requires a path.")
        }
        self.outputURL = Self.resolve(value, relativeTo: packageDirectory)

      default:
        if argument.hasPrefix("-") {
          throw PluginError("Unexpected option: \(argument)")
        }
        positionalArguments.append(argument)
      }
    }

    if self.inputURL == nil, let input = positionalArguments.first {
      self.inputURL = Self.resolve(input, relativeTo: packageDirectory)
    }
    if self.outputURL == nil, positionalArguments.count > 1 {
      self.outputURL = Self.resolve(positionalArguments[1], relativeTo: packageDirectory)
    }
    if positionalArguments.count > 2 {
      throw PluginError("Unexpected argument: \(positionalArguments[2])")
    }
    guard self.inputURL != nil else {
      throw PluginError("Missing required --input path.")
    }
  }

  var toolArguments: [String] {
    var arguments: [String] = []
    if let inputURL {
      arguments += ["--input", inputURL.path]
    }
    if let outputURL {
      arguments += ["--output", outputURL.path]
    }
    return arguments
  }

  private static func resolve(_ path: String, relativeTo packageDirectory: URL) -> URL {
    let expandedPath = (path as NSString).expandingTildeInPath
    return URL(
      fileURLWithPath: expandedPath,
      relativeTo: expandedPath.hasPrefix("/") ? nil : packageDirectory
    )
    .standardizedFileURL
  }
}

private struct PluginError: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}
