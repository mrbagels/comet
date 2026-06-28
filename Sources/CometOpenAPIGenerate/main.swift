import Foundation
import CometOpenAPIGenerator

@main
struct CometOpenAPIGenerate {
  static func main() {
    do {
      let arguments = try CLIArguments(CommandLine.arguments.dropFirst())
      let input = try arguments.inputData()
      let output = try OpenAPIGenerator().generate(data: input)
      try arguments.write(output)
    } catch {
      FileHandle.standardError.write(Data("error: \(error)\n".utf8))
      Foundation.exit(1)
    }
  }
}

private struct CLIArguments {
  var inputURL: URL?
  var outputURL: URL?

  init(_ arguments: ArraySlice<String>) throws {
    var iterator = arguments.makeIterator()
    while let argument = iterator.next() {
      switch argument {
      case "--input", "-i":
        guard let value = iterator.next() else {
          throw CLIError("--input requires a path.")
        }
        self.inputURL = URL(fileURLWithPath: value)

      case "--output", "-o":
        guard let value = iterator.next() else {
          throw CLIError("--output requires a path.")
        }
        self.outputURL = URL(fileURLWithPath: value)

      case "--help", "-h":
        throw CLIError(Self.help)

      default:
        if self.inputURL == nil {
          self.inputURL = URL(fileURLWithPath: argument)
        } else if self.outputURL == nil {
          self.outputURL = URL(fileURLWithPath: argument)
        } else {
          throw CLIError("Unexpected argument: \(argument)")
        }
      }
    }
  }

  func inputData() throws -> Data {
    if let inputURL {
      return try Data(contentsOf: inputURL)
    }
    return FileHandle.standardInput.readDataToEndOfFile()
  }

  func write(_ output: String) throws {
    let data = Data(output.utf8)
    if let outputURL {
      try data.write(to: outputURL, options: .atomic)
    } else {
      FileHandle.standardOutput.write(data)
    }
  }

  private static let help = """
  Usage: comet-openapi-generate --input openapi.json --output GeneratedAPI.swift

  Omit --input to read JSON from stdin. Omit --output to write Swift to stdout.
  """
}

private struct CLIError: Error, CustomStringConvertible {
  var description: String

  init(_ description: String) {
    self.description = description
  }
}
