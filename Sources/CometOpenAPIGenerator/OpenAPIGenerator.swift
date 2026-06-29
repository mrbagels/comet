import Foundation
import Yams

/// Configuration for generated Comet request source.
public struct OpenAPIGeneratorConfiguration: Sendable, Hashable {
  public var accessModifier: String
  public var imports: [String]
  public var includeHeaderComment: Bool

  public init(
    accessModifier: String = "public",
    imports: [String] = ["Foundation", "HTTPTypes", "Comet"],
    includeHeaderComment: Bool = true
  ) {
    self.accessModifier = accessModifier
    self.imports = imports
    self.includeHeaderComment = includeHeaderComment
  }
}

/// A focused JSON and YAML OpenAPI generator for Comet request types.
public struct OpenAPIGenerator: Sendable {
  public init() {}

  public func generate(
    data: Data,
    configuration: OpenAPIGeneratorConfiguration = OpenAPIGeneratorConfiguration()
  ) throws -> String {
    do {
      let document = try JSONDecoder().decode(OpenAPIDocument.self, from: data)
      return try self.generate(document: document, configuration: configuration)
    } catch let error as OpenAPIGeneratorError {
      throw error
    } catch let jsonError {
      do {
        let document = try self.decodeYAMLDocument(data: data)
        return try self.generate(document: document, configuration: configuration)
      } catch let error as OpenAPIGeneratorError {
        throw error
      } catch {
        throw OpenAPIGeneratorError.invalidDocument(
          "Unable to decode OpenAPI JSON or YAML. JSON error: \(jsonError). YAML error: \(error)"
        )
      }
    }
  }

  public func generate(
    jsonString: String,
    configuration: OpenAPIGeneratorConfiguration = OpenAPIGeneratorConfiguration()
  ) throws -> String {
    guard let data = jsonString.data(using: .utf8) else {
      throw OpenAPIGeneratorError.invalidDocument("Unable to encode input as UTF-8.")
    }
    return try self.generate(data: data, configuration: configuration)
  }

  public func generate(
    yamlString: String,
    configuration: OpenAPIGeneratorConfiguration = OpenAPIGeneratorConfiguration()
  ) throws -> String {
    guard let data = yamlString.data(using: .utf8) else {
      throw OpenAPIGeneratorError.invalidDocument("Unable to encode input as UTF-8.")
    }
    return try self.generate(data: data, configuration: configuration)
  }

  private func decodeYAMLDocument(data: Data) throws -> OpenAPIDocument {
    guard let string = String(data: data, encoding: .utf8) else {
      throw OpenAPIGeneratorError.invalidDocument("Unable to decode input as UTF-8.")
    }
    guard let object = try Yams.load(yaml: string) else {
      throw OpenAPIGeneratorError.invalidDocument("The OpenAPI YAML document was empty.")
    }
    guard JSONSerialization.isValidJSONObject(object) else {
      throw OpenAPIGeneratorError.invalidDocument("The OpenAPI YAML document could not be represented as JSON.")
    }
    let data = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(OpenAPIDocument.self, from: data)
  }

  private func generate(
    document: OpenAPIDocument,
    configuration: OpenAPIGeneratorConfiguration
  ) throws -> String {
    let components = document.components ?? OpenAPIComponents()
    let componentSchemas = components.schemas
    let models = try componentSchemas.keys.sorted().map { name in
      try GeneratedSchemaModel(
        name: name,
        schema: componentSchemas[name]!,
        components: componentSchemas,
        accessModifier: configuration.accessModifier
      )
    }
    var operations: [GeneratedOperation] = []

    for path in document.paths.keys.sorted() {
      guard let item = document.paths[path] else { continue }
      for method in HTTPMethodName.allCases {
        guard let operation = item.operation(for: method) else { continue }
        operations.append(
          try GeneratedOperation(
            path: path,
            method: method,
            operation: operation,
            documentSecurity: document.security,
            inheritedParameters: item.parameters,
            components: components,
            accessModifier: configuration.accessModifier
          )
        )
      }
    }

    guard !operations.isEmpty else {
      throw OpenAPIGeneratorError.invalidDocument("The OpenAPI document did not contain any supported path operations.")
    }

    let duplicateTypeNames = Dictionary(grouping: operations, by: \.typeName)
      .filter { $0.value.count > 1 }
      .map(\.key)
      .sorted()
    guard duplicateTypeNames.isEmpty else {
      throw OpenAPIGeneratorError.invalidDocument(
        "Multiple operations generate duplicate request type names: \(duplicateTypeNames.joined(separator: ", "))."
      )
    }
    let duplicateModelNames = Dictionary(grouping: models, by: \.typeName)
      .filter { $0.value.count > 1 }
      .map(\.key)
      .sorted()
    guard duplicateModelNames.isEmpty else {
      throw OpenAPIGeneratorError.invalidDocument(
        "Multiple component schemas generate duplicate Swift type names: \(duplicateModelNames.joined(separator: ", "))."
      )
    }
    let collidingNames = Set(models.map(\.typeName))
      .intersection(Set(operations.map(\.typeName)))
      .sorted()
    guard collidingNames.isEmpty else {
      throw OpenAPIGeneratorError.invalidDocument(
        "Component schemas and operations generate duplicate Swift type names: \(collidingNames.joined(separator: ", "))."
      )
    }

    var lines: [String] = []
    if configuration.includeHeaderComment {
      lines.append("// Generated by comet-openapi-generate. Edit the OpenAPI source instead of this file.")
      lines.append("")
    }

    for module in configuration.imports {
      lines.append("import \(module)")
    }
    lines.append("")

    let generatedBlocks = try models.map { try $0.renderedLines() } + operations.map { $0.renderedLines() }
    if generatedBlocks.contains(where: { block in
      block.contains { $0.contains("CometOpenAPIJSONValue") }
    }) {
      lines.append(contentsOf: Self.jsonValueLines(accessModifier: configuration.accessModifier))
      lines.append("")
    }
    for (index, block) in generatedBlocks.enumerated() {
      if index > 0 {
        lines.append("")
      }
      lines.append(contentsOf: block)
    }

    return lines.joined(separator: "\n") + "\n"
  }

  private static func jsonValueLines(accessModifier: String) -> [String] {
    [
      "\(accessModifier) enum CometOpenAPIJSONValue: Codable, Sendable, Equatable {",
      "  case null",
      "  case bool(Bool)",
      "  case number(Double)",
      "  case string(String)",
      "  case array([CometOpenAPIJSONValue])",
      "  case object([String: CometOpenAPIJSONValue])",
      "",
      "  \(accessModifier) init(from decoder: any Decoder) throws {",
      "    let container = try decoder.singleValueContainer()",
      "    if container.decodeNil() {",
      "      self = .null",
      "    } else if let value = try? container.decode(Bool.self) {",
      "      self = .bool(value)",
      "    } else if let value = try? container.decode(Double.self) {",
      "      self = .number(value)",
      "    } else if let value = try? container.decode(String.self) {",
      "      self = .string(value)",
      "    } else if let value = try? container.decode([CometOpenAPIJSONValue].self) {",
      "      self = .array(value)",
      "    } else {",
      "      self = .object(try container.decode([String: CometOpenAPIJSONValue].self))",
      "    }",
      "  }",
      "",
      "  \(accessModifier) func encode(to encoder: any Encoder) throws {",
      "    var container = encoder.singleValueContainer()",
      "    switch self {",
      "    case .null:",
      "      try container.encodeNil()",
      "    case .bool(let value):",
      "      try container.encode(value)",
      "    case .number(let value):",
      "      try container.encode(value)",
      "    case .string(let value):",
      "      try container.encode(value)",
      "    case .array(let value):",
      "      try container.encode(value)",
      "    case .object(let value):",
      "      try container.encode(value)",
      "    }",
      "  }",
      "}"
    ]
  }
}

/// Errors emitted by the OpenAPI generator.
public struct OpenAPIGeneratorError: Error, Sendable, CustomStringConvertible, Equatable {
  public var message: String

  public init(_ message: String) {
    self.message = message
  }

  public static func invalidDocument(_ message: String) -> Self {
    Self(message)
  }

  public static func unsupported(_ message: String) -> Self {
    Self("Unsupported OpenAPI feature: \(message)")
  }

  public var description: String {
    self.message
  }
}

private struct GeneratedResponseSerialization {
  let type: String
  let serializer: String
}

private enum GeneratedRequestBody {
  case none
  case json(payloadType: String?, required: Bool)
  case text(required: Bool)
  case form(fields: [GeneratedFormField], required: Bool)
  case multipart(fields: [GeneratedFormField], required: Bool)

  var genericBodyType: Bool {
    guard case .json(nil, _) = self else { return false }
    return true
  }

  var hasBody: Bool {
    guard case .none = self else { return true }
    return false
  }

  var storedPropertyLines: [String] {
    switch self {
    case .none:
      return []
    case let .json(payloadType, required):
      let type = payloadType ?? "Body"
      return ["bodyPayload: \(required ? type : "\(type)?")"]
    case let .text(required):
      return ["bodyText: \(required ? "String" : "String?")"]
    case let .form(fields, _):
      return fields.map { "\($0.swiftName): \($0.swiftType)" }
    case let .multipart(fields, _):
      return fields.map { "\($0.swiftName): \($0.swiftType)" }
    }
  }

  var initArguments: [String] {
    switch self {
    case .none:
      return []
    case let .json(payloadType, required):
      let type = payloadType ?? "Body"
      return ["bodyPayload: \(required ? type : "\(type)? = nil")"]
    case let .text(required):
      return ["bodyText: \(required ? "String" : "String? = nil")"]
    case let .form(fields, _):
      return fields.map(\.initArgument)
    case let .multipart(fields, _):
      return fields.map(\.initArgument)
    }
  }

  var initAssignments: [String] {
    switch self {
    case .none:
      return []
    case .json:
      return ["    self.bodyPayload = bodyPayload"]
    case .text:
      return ["    self.bodyText = bodyText"]
    case let .form(fields, _):
      return fields.map { "    self.\($0.swiftName) = \($0.swiftName)" }
    case let .multipart(fields, _):
      return fields.map { "    self.\($0.swiftName) = \($0.swiftName)" }
    }
  }

  func bodyLines(accessModifier: String) -> [String] {
    switch self {
    case .none:
      return []
    case let .json(_, required):
      if required {
        return [
          "  \(accessModifier) var body: HTTPBody {",
          "    .json(self.bodyPayload)",
          "  }"
        ]
      }
      return [
        "  \(accessModifier) var body: HTTPBody {",
        "    guard let bodyPayload = self.bodyPayload else { return .none }",
        "    return .json(bodyPayload)",
        "  }"
      ]
    case let .text(required):
      if required {
        return [
          "  \(accessModifier) var body: HTTPBody {",
          "    .text(self.bodyText)",
          "  }"
        ]
      }
      return [
        "  \(accessModifier) var body: HTTPBody {",
        "    guard let bodyText = self.bodyText else { return .none }",
        "    return .text(bodyText)",
        "  }"
      ]
    case let .form(fields, required):
      var lines = [
        "  \(accessModifier) var body: HTTPBody {",
        "    var items: [QueryItem] = []"
      ]
      for field in fields {
        lines.append(contentsOf: field.formItemLines())
      }
      if !required {
        lines.append("    guard !items.isEmpty else { return .none }")
      }
      lines.append("    return .formURLEncoded(items)")
      lines.append("  }")
      return lines
    case let .multipart(fields, required):
      var lines = [
        "  \(accessModifier) var body: HTTPBody {",
        "    var parts: [HTTPBody.MultipartPart] = []"
      ]
      for field in fields {
        lines.append(contentsOf: field.multipartPartLines())
      }
      if !required {
        lines.append("    guard !parts.isEmpty else { return .none }")
      }
      lines.append("    return .multipartFormData(parts)")
      lines.append("  }")
      return lines
    }
  }
}

private struct GeneratedFormField {
  let originalName: String
  let swiftName: String
  let swiftType: String
  let isRequired: Bool
  let isBinary: Bool

  init(
    entry: OpenAPIObjectPropertyEntry,
    requestBodyRequired: Bool,
    components: [String: OpenAPISchema]
  ) throws {
    self.originalName = entry.name
    self.swiftName = entry.name.swiftIdentifier()
    self.isRequired = requestBodyRequired && entry.isRequired && !entry.schema.nullable
    let baseType = try entry.schema.swiftType(
      components: components,
      inlineObjectFallback: nil
    ) ?? "String"
    let resolvedSchema = try entry.schema.resolved(components: components)
    self.isBinary = resolvedSchema.type == "string" && resolvedSchema.format == "binary"
    self.swiftType = self.isRequired ? baseType : "\(baseType)?"
  }

  var initArgument: String {
    "\(self.swiftName): \(self.swiftType)\(self.isRequired ? "" : " = nil")"
  }

  func formItemLines() -> [String] {
    if self.isRequired {
      return ["    items.append(QueryItem(\(self.originalName.swiftLiteral), self.\(self.swiftName)))"]
    }
    return [
      "    if let \(self.swiftName) = self.\(self.swiftName) {",
      "      items.append(QueryItem(\(self.originalName.swiftLiteral), \(self.swiftName)))",
      "    }"
    ]
  }

  func multipartPartLines() -> [String] {
    let partExpression: String
    if self.isBinary {
      partExpression = ".data(name: \(self.originalName.swiftLiteral), data: \(self.isRequired ? "self.\(self.swiftName)" : self.swiftName), filename: \(self.originalName.swiftLiteral), contentType: \"application/octet-stream\")"
    } else {
      partExpression = ".text(name: \(self.originalName.swiftLiteral), value: String(describing: \(self.isRequired ? "self.\(self.swiftName)" : self.swiftName)))"
    }

    if self.isRequired {
      return ["    parts.append(\(partExpression))"]
    }
    return [
      "    if let \(self.swiftName) = self.\(self.swiftName) {",
      "      parts.append(\(partExpression))",
      "    }"
    ]
  }
}

private struct GeneratedOperation {
  let accessModifier: String
  let typeName: String
  let requestBody: GeneratedRequestBody
  let method: HTTPMethodName
  let pathExpression: String
  let parameters: [GeneratedParameter]
  let queryParameters: [GeneratedParameter]
  let headerParameters: [GeneratedParameter]
  let responseType: String
  let responseSerializer: String
  let errorResponse: GeneratedResponseSerialization?
  let operationID: String
  let securityTags: [String]

  init(
    path: String,
    method: HTTPMethodName,
    operation: OpenAPIOperation,
    documentSecurity: [OpenAPISecurityRequirement],
    inheritedParameters: [OpenAPIParameter],
    components: OpenAPIComponents,
    accessModifier: String
  ) throws {
    self.accessModifier = accessModifier
    self.method = method
    self.operationID = operation.operationID ?? "\(method.rawValue)-\(path)"
    self.typeName = Self.typeName(operationID: operation.operationID, method: method, path: path)
    self.securityTags = try Self.securityTags(
      operationSecurity: operation.security,
      documentSecurity: documentSecurity,
      securitySchemes: components.securitySchemes
    )

    let mergedParameters = Self.mergedParameters(
      try inheritedParameters.map { try $0.resolved(components: components) },
      overridingWith: try operation.parameters.map { try $0.resolved(components: components) }
    )
    let parameters = try mergedParameters.map { try GeneratedParameter($0, components: components.schemas) }
    let duplicateSwiftParameterNames = Dictionary(grouping: parameters, by: \.swiftName)
      .filter { $0.value.count > 1 }
      .map(\.key)
      .sorted()
    guard duplicateSwiftParameterNames.isEmpty else {
      throw OpenAPIGeneratorError.invalidDocument(
        "\(self.operationID) has parameters that generate duplicate Swift names: \(duplicateSwiftParameterNames.joined(separator: ", "))."
      )
    }
    self.parameters = parameters
    self.queryParameters = parameters.filter { $0.location == .query }
    self.headerParameters = parameters.filter { $0.location == .header }
    self.pathExpression = try Self.pathExpression(path: path, parameters: parameters)

    if let requestBody = operation.requestBody {
      self.requestBody = try Self.generatedRequestBody(
        from: requestBody.resolved(components: components),
        components: components.schemas,
        operationID: self.operationID
      )
    } else {
      self.requestBody = .none
    }

    let responses = try operation.responses.mapValues { try $0.resolved(components: components) }
    let response = try Self.successResponse(from: responses, components: components.schemas)
    self.responseType = response.type
    self.responseSerializer = response.serializer
    self.errorResponse = try Self.errorResponse(from: responses, components: components.schemas)
  }

  func renderedLines() -> [String] {
    var lines: [String] = []
    let protocolName = self.errorResponse == nil ? "APIRequest" : "APIRequestWithErrorResponse"
    let generic = self.requestBody.genericBodyType ? "<Body: Encodable & Sendable>" : ""
    lines.append("\(self.accessModifier) struct \(self.typeName)\(generic): \(protocolName) {")
    lines.append("  \(self.accessModifier) typealias Response = \(self.responseType)")
    if let errorResponse {
      lines.append("  \(self.accessModifier) typealias ErrorResponse = \(errorResponse.type)")
    }
    lines.append("")

    for parameter in self.parameters {
      lines.append("  \(self.accessModifier) let \(parameter.swiftName): \(parameter.swiftType)")
    }
    for bodyProperty in self.requestBody.storedPropertyLines {
      lines.append("  \(self.accessModifier) let \(bodyProperty)")
    }

    if !self.parameters.isEmpty || self.requestBody.hasBody {
      lines.append("")
      lines.append(contentsOf: self.initLines())
    } else {
      lines.append("")
      lines.append("  \(self.accessModifier) init() {}")
    }

    lines.append("")
    lines.append("  \(self.accessModifier) var path: Path {")
    lines.append("    \(self.pathExpression)")
    lines.append("  }")
    lines.append("")
    lines.append("  \(self.accessModifier) let method: HTTPMethod = \(self.method.swiftExpression)")

    if !self.queryParameters.isEmpty {
      lines.append("")
      lines.append("  \(self.accessModifier) var queryItems: [QueryItem] {")
      lines.append("    var items: [QueryItem] = []")
      for parameter in self.queryParameters {
        lines.append(contentsOf: parameter.queryItemLines())
      }
      lines.append("    return items")
      lines.append("  }")
    }

    if !self.headerParameters.isEmpty {
      lines.append("")
      lines.append("  \(self.accessModifier) var headers: HTTPFields {")
      lines.append("    var headers = HTTPFields()")
      for parameter in self.headerParameters {
        lines.append(contentsOf: parameter.headerLines())
      }
      lines.append("    return headers")
      lines.append("  }")
    }

    let bodyLines = self.requestBody.bodyLines(accessModifier: self.accessModifier)
    if !bodyLines.isEmpty {
      lines.append("")
      lines.append(contentsOf: bodyLines)
    }

    lines.append("")
    lines.append("  \(self.accessModifier) var options: RequestOptions {")
    lines.append("    RequestOptions(")
    lines.append("      metadata: \(self.metadataExpression)")
    lines.append("    )")
    lines.append("  }")
    lines.append("")
    lines.append("  \(self.accessModifier) let responseSerializer: ResponseSerializer<\(self.responseType)> = \(self.responseSerializer)")

    if let errorResponse {
      lines.append("  \(self.accessModifier) let errorResponseSerializer: ErrorResponseSerializer<\(errorResponse.type)> = \(errorResponse.serializer)")
    }

    lines.append("}")
    return lines
  }

  private var metadataExpression: String {
    guard !self.securityTags.isEmpty else {
      return "RequestMetadata(operationID: \(self.operationID.swiftLiteral))"
    }
    let tags = "[" + self.securityTags.map(\.swiftLiteral).joined(separator: ", ") + "]"
    return "RequestMetadata(tags: \(tags), operationID: \(self.operationID.swiftLiteral))"
  }

  private func initLines() -> [String] {
    var lines: [String] = []
    lines.append("  \(self.accessModifier) init(")
    var arguments = self.parameters.map { parameter in
      "\(parameter.swiftName): \(parameter.swiftType)"
    }
    arguments.append(contentsOf: self.requestBody.initArguments)
    for index in arguments.indices {
      lines.append("    " + arguments[index] + (index == arguments.indices.last ? "" : ","))
    }
    lines.append("  ) {")
    for parameter in self.parameters {
      lines.append("    self.\(parameter.swiftName) = \(parameter.swiftName)")
    }
    lines.append(contentsOf: self.requestBody.initAssignments)
    lines.append("  }")
    return lines
  }

  private static func typeName(
    operationID: String?,
    method: HTTPMethodName,
    path: String
  ) -> String {
    let raw = operationID ?? "\(method.rawValue) \(path)"
    let name = raw.identifierWords().map(\.swiftTypeWord).joined()
    guard !name.isEmpty else { return "GeneratedRequest" }
    return "\(name.prefixedIfNeededForSwiftIdentifier(prefix: "Generated"))Request"
  }

  private static func pathExpression(
    path: String,
    parameters: [GeneratedParameter]
  ) throws -> String {
    let pathParameters = Dictionary(uniqueKeysWithValues: parameters.filter { $0.location == .path }.map { ($0.originalName, $0) })
    let segments = path
      .split(separator: "/")
      .map(String.init)
      .filter { !$0.isEmpty }

    guard !segments.isEmpty else { return "Path(\"\")" }

    var expressions: [String] = []
    for segment in segments {
      if segment.hasPrefix("{"), segment.hasSuffix("}") {
        let rawName = String(segment.dropFirst().dropLast())
        guard let parameter = pathParameters[rawName] else {
          throw OpenAPIGeneratorError.invalidDocument("Path parameter {\(rawName)} is missing from the operation parameters.")
        }
        expressions.append("self.\(parameter.swiftName)")
      } else {
        expressions.append(segment.swiftLiteral)
      }
    }

    let first = expressions.removeFirst()
    let base = first.hasPrefix("\"") ? first : "Path(\"\") / \(first)"
    guard !expressions.isEmpty else { return first.hasPrefix("\"") ? base : base }
    return ([base] + expressions).joined(separator: " / ")
  }

  private static func successResponse(
    from responses: [String: OpenAPIResponse],
    components: [String: OpenAPISchema]
  ) throws -> GeneratedResponseSerialization {
    let success = responses
      .compactMap { status, response -> (Int, OpenAPIResponse)? in
        guard let code = Int(status), (200..<300).contains(code) else { return nil }
        return (code, response)
      }
      .sorted { $0.0 < $1.0 }
      .first

    guard let success else {
      return GeneratedResponseSerialization(type: "Data", serializer: ".data")
    }

    if success.0 == 204 || success.1.content.isEmpty {
      return GeneratedResponseSerialization(type: "EmptyResponse", serializer: ".empty")
    }

    return try Self.responseSerialization(from: success.1, components: components)
  }

  private static func errorResponse(
    from responses: [String: OpenAPIResponse],
    components: [String: OpenAPISchema]
  ) throws -> GeneratedResponseSerialization? {
    let failure = responses
      .compactMap { status, response -> (Int, OpenAPIResponse)? in
        guard let code = Int(status), !(200..<300).contains(code) else { return nil }
        return (code, response)
      }
      .sorted { $0.0 < $1.0 }
      .first
      .map(\.1) ?? responses["default"]

    guard let failure else { return nil }
    return try Self.responseSerialization(from: failure, components: components)
  }

  private static func responseSerialization(
    from response: OpenAPIResponse,
    components: [String: OpenAPISchema]
  ) throws -> GeneratedResponseSerialization {
    if response.content.keys.contains("text/plain") {
      return GeneratedResponseSerialization(type: "String", serializer: ".string()")
    }

    if let schema = response.content["application/json"]?.schema,
       let type = try schema.swiftType(components: components, inlineObjectFallback: nil) {
      return GeneratedResponseSerialization(type: type, serializer: ".json(\(type).self)")
    }

    return GeneratedResponseSerialization(type: "Data", serializer: ".data")
  }

  private static func generatedRequestBody(
    from requestBody: OpenAPIRequestBody,
    components: [String: OpenAPISchema],
    operationID: String
  ) throws -> GeneratedRequestBody {
    if let mediaType = requestBody.content["application/json"] {
      return .json(
        payloadType: try mediaType.schema?.swiftType(components: components, inlineObjectFallback: nil),
        required: requestBody.required
      )
    }

    if requestBody.content.keys.contains("text/plain") {
      return .text(required: requestBody.required)
    }

    if let schema = requestBody.content["application/x-www-form-urlencoded"]?.schema {
      let resolvedSchema = try schema.resolved(components: components)
      guard resolvedSchema.isObjectLike else {
        throw OpenAPIGeneratorError.unsupported(
          "\(operationID) form URL-encoded request bodies must use object schemas."
        )
      }
      guard try resolvedSchema.dictionarySwiftType(components: components, inlineObjectFallback: nil) == nil else {
        throw OpenAPIGeneratorError.unsupported(
          "\(operationID) form URL-encoded dictionary request bodies are not generated yet."
        )
      }
      let fields = try resolvedSchema.objectPropertyEntries(components: components).map { entry in
        try GeneratedFormField(
          entry: entry,
          requestBodyRequired: requestBody.required,
          components: components
        )
      }
      let duplicateFieldNames = Dictionary(grouping: fields, by: \.swiftName)
        .filter { $0.value.count > 1 }
        .map(\.key)
        .sorted()
      guard duplicateFieldNames.isEmpty else {
        throw OpenAPIGeneratorError.invalidDocument(
          "\(operationID) has form fields that generate duplicate Swift names: \(duplicateFieldNames.joined(separator: ", "))."
        )
      }
      return .form(fields: fields, required: requestBody.required)
    }

    if let schema = requestBody.content["multipart/form-data"]?.schema {
      let resolvedSchema = try schema.resolved(components: components)
      guard resolvedSchema.isObjectLike else {
        throw OpenAPIGeneratorError.unsupported(
          "\(operationID) multipart form-data request bodies must use object schemas."
        )
      }
      guard try resolvedSchema.dictionarySwiftType(components: components, inlineObjectFallback: nil) == nil else {
        throw OpenAPIGeneratorError.unsupported(
          "\(operationID) multipart form-data dictionary request bodies are not generated yet."
        )
      }
      let fields = try resolvedSchema.objectPropertyEntries(components: components).map { entry in
        try GeneratedFormField(
          entry: entry,
          requestBodyRequired: requestBody.required,
          components: components
        )
      }
      let duplicateFieldNames = Dictionary(grouping: fields, by: \.swiftName)
        .filter { $0.value.count > 1 }
        .map(\.key)
        .sorted()
      guard duplicateFieldNames.isEmpty else {
        throw OpenAPIGeneratorError.invalidDocument(
          "\(operationID) has multipart form fields that generate duplicate Swift names: \(duplicateFieldNames.joined(separator: ", "))."
        )
      }
      return .multipart(fields: fields, required: requestBody.required)
    }

    throw OpenAPIGeneratorError.unsupported(
      "\(operationID) uses a request body content type that is not generated yet."
    )
  }

  private static func securityTags(
    operationSecurity: [OpenAPISecurityRequirement]?,
    documentSecurity: [OpenAPISecurityRequirement],
    securitySchemes: [String: OpenAPISecurityScheme]
  ) throws -> [String] {
    let requirements = operationSecurity ?? documentSecurity
    var tags: [String] = []
    var seen: Set<String> = []

    for requirement in requirements {
      for schemeName in requirement.keys.sorted() {
        guard securitySchemes[schemeName] != nil else {
          throw OpenAPIGeneratorError.invalidDocument("Security requirement references missing scheme: \(schemeName).")
        }
        let scopes = requirement[schemeName] ?? []
        let rawTags: [String]
        if scopes.isEmpty {
          rawTags = ["security:\(schemeName)"]
        } else {
          rawTags = scopes.sorted().map { "security:\(schemeName):\($0)" }
        }
        for tag in rawTags where seen.insert(tag).inserted {
          tags.append(tag)
        }
      }
    }

    return tags
  }

  private static func mergedParameters(
    _ inherited: [OpenAPIParameter],
    overridingWith operationParameters: [OpenAPIParameter]
  ) -> [OpenAPIParameter] {
    var parameters = inherited
    for operationParameter in operationParameters {
      if let index = parameters.firstIndex(where: {
        $0.name == operationParameter.name && $0.location == operationParameter.location
      }) {
        parameters[index] = operationParameter
      } else {
        parameters.append(operationParameter)
      }
    }
    return parameters
  }
}

private struct GeneratedSchemaModel {
  let accessModifier: String
  let originalName: String
  let typeName: String
  let schema: OpenAPISchema
  let components: [String: OpenAPISchema]

  init(
    name: String,
    schema: OpenAPISchema,
    components: [String: OpenAPISchema],
    accessModifier: String
  ) throws {
    self.accessModifier = accessModifier
    self.originalName = name
    self.typeName = name.swiftTypeName()
    self.schema = schema
    self.components = components
  }

  func renderedLines() throws -> [String] {
    if self.schema.ref != nil,
       let aliasedType = try self.schema.swiftType(components: self.components, inlineObjectFallback: nil) {
      return [
        "\(self.accessModifier) typealias \(self.typeName) = \(aliasedType)"
      ]
    }
    if self.schema.isUnion {
      return try self.renderedUnionLines()
    }
    if let dictionaryType = try self.schema.dictionarySwiftType(
      components: self.components,
      inlineObjectFallback: nil
    ) {
      return [
        "\(self.accessModifier) typealias \(self.typeName) = \(dictionaryType)"
      ]
    }
    if let enumValues = self.schema.enumValues, self.schema.type == "string" {
      return try self.renderedEnumLines(enumValues)
    }
    if self.schema.isObjectLike {
      return try GeneratedObjectSchemaRenderer(
        accessModifier: self.accessModifier,
        originalName: self.originalName,
        typeName: self.typeName,
        schema: self.schema,
        components: self.components
      )
      .renderedLines()
    }
    if self.schema.type == "array", let items = self.schema.items {
      let elementType = try items.swiftType(components: self.components, inlineObjectFallback: nil)
        ?? "Data"
      return [
        "\(self.accessModifier) typealias \(self.typeName) = [\(elementType)]"
      ]
    }

    let aliasedType = try self.schema.swiftType(
      components: self.components,
      inlineObjectFallback: "Data"
    ) ?? "Data"
    return [
      "\(self.accessModifier) typealias \(self.typeName) = \(aliasedType)"
    ]
  }

  private func renderedEnumLines(_ values: [String]) throws -> [String] {
    var cases: [(name: String, value: String)] = []
    for value in values {
      cases.append((name: value.swiftIdentifier(), value: value))
    }
    let duplicateCaseNames = Dictionary(grouping: cases, by: \.name)
      .filter { $0.value.count > 1 }
      .map(\.key)
      .sorted()
    guard duplicateCaseNames.isEmpty else {
      throw OpenAPIGeneratorError.invalidDocument(
        "\(self.originalName) has enum values that generate duplicate Swift case names: \(duplicateCaseNames.joined(separator: ", "))."
      )
    }

    var lines: [String] = []
    lines.append("\(self.accessModifier) enum \(self.typeName): String, Codable, Sendable {")
    for item in cases {
      lines.append("  case \(item.name) = \(item.value.swiftLiteral)")
    }
    lines.append("}")
    return lines
  }

  private func renderedUnionLines() throws -> [String] {
    let variants = self.schema.unionVariants
    var cases: [GeneratedUnionCase] = []
    for (index, variant) in variants.enumerated() {
      cases.append(
        try GeneratedUnionCase(
          schema: variant,
          index: index,
          components: self.components
        )
      )
    }

    let duplicateCaseNames = Dictionary(grouping: cases, by: \.caseName)
      .filter { $0.value.count > 1 }
      .map(\.key)
      .sorted()
    guard duplicateCaseNames.isEmpty else {
      throw OpenAPIGeneratorError.invalidDocument(
        "\(self.originalName) has union entries that generate duplicate Swift case names: \(duplicateCaseNames.joined(separator: ", "))."
      )
    }

    if let discriminator = self.schema.discriminator {
      return try self.renderedDiscriminatorUnionLines(
        cases: cases,
        discriminator: discriminator
      )
    }

    var lines: [String] = []
    lines.append("\(self.accessModifier) enum \(self.typeName): Codable, Sendable {")
    for item in cases {
      lines.append("  case \(item.caseName)(\(item.swiftType))")
    }

    lines.append("")
    lines.append("  \(self.accessModifier) init(from decoder: any Decoder) throws {")
    lines.append("    let container = try decoder.singleValueContainer()")
    for item in cases {
      lines.append("    if let value = try? container.decode(\(item.swiftType).self) {")
      lines.append("      self = .\(item.caseName)(value)")
      lines.append("      return")
      lines.append("    }")
    }
    lines.append("    throw DecodingError.dataCorruptedError(")
    lines.append("      in: container,")
    let debugDescription = "Unable to decode \(self.typeName) from any supported schema.".swiftLiteral
    lines.append("      debugDescription: \(debugDescription)")
    lines.append("    )")
    lines.append("  }")

    lines.append("")
    lines.append("  \(self.accessModifier) func encode(to encoder: any Encoder) throws {")
    lines.append("    var container = encoder.singleValueContainer()")
    lines.append("    switch self {")
    for item in cases {
      lines.append("    case .\(item.caseName)(let value):")
      lines.append("      try container.encode(value)")
    }
    lines.append("    }")
    lines.append("  }")
    lines.append("}")
    return lines
  }

  private func renderedDiscriminatorUnionLines(
    cases: [GeneratedUnionCase],
    discriminator: OpenAPIDiscriminator
  ) throws -> [String] {
    let mappedComponentNames = try discriminator.mapping.mapValues {
      try OpenAPIDiscriminator.componentName(forMappingValue: $0)
    }
    let caseComponentNames = Set(cases.compactMap(\.componentName))
    for componentName in mappedComponentNames.values where !caseComponentNames.contains(componentName) {
      throw OpenAPIGeneratorError.invalidDocument(
        "\(self.originalName) discriminator mapping references a schema that is not part of the union: \(componentName)."
      )
    }

    var valuesByCase: [(GeneratedUnionCase, [String])] = []
    var allValues: [String: String] = [:]
    for item in cases {
      guard let componentName = item.componentName else {
        throw OpenAPIGeneratorError.unsupported(
          "\(self.originalName) discriminator unions must reference component schemas."
        )
      }

      var rawValues = [componentName]
      for discriminatorValue in discriminator.mapping.keys.sorted()
      where mappedComponentNames[discriminatorValue] == componentName {
        rawValues.append(discriminatorValue)
      }

      var values: [String] = []
      var seenValues: Set<String> = []
      for value in rawValues where seenValues.insert(value).inserted {
        values.append(value)
      }
      for value in values {
        if let existingCase = allValues[value], existingCase != item.caseName {
          throw OpenAPIGeneratorError.invalidDocument(
            "\(self.originalName) discriminator value maps to multiple union cases: \(value)."
          )
        }
        allValues[value] = item.caseName
      }
      valuesByCase.append((item, values))
    }

    var lines: [String] = []
    lines.append("\(self.accessModifier) enum \(self.typeName): Codable, Sendable {")
    for item in cases {
      lines.append("  case \(item.caseName)(\(item.swiftType))")
    }

    lines.append("")
    lines.append("  private enum DiscriminatorCodingKeys: String, CodingKey {")
    lines.append("    case discriminator = \(discriminator.propertyName.swiftLiteral)")
    lines.append("  }")

    lines.append("")
    lines.append("  \(self.accessModifier) init(from decoder: any Decoder) throws {")
    lines.append("    let discriminatorContainer = try decoder.container(keyedBy: DiscriminatorCodingKeys.self)")
    lines.append("    let discriminatorValue = try discriminatorContainer.decode(String.self, forKey: .discriminator)")
    lines.append("    switch discriminatorValue {")
    for (item, values) in valuesByCase {
      lines.append("    case \(values.map(\.swiftLiteral).joined(separator: ", ")):")
      lines.append("      self = .\(item.caseName)(try \(item.swiftType)(from: decoder))")
    }
    lines.append("    default:")
    lines.append("      throw DecodingError.dataCorruptedError(")
    lines.append("        forKey: .discriminator,")
    lines.append("        in: discriminatorContainer,")
    let debugDescription = "Unsupported \(self.typeName) discriminator value.".swiftLiteral
    lines.append("        debugDescription: \(debugDescription)")
    lines.append("      )")
    lines.append("    }")
    lines.append("  }")

    lines.append("")
    lines.append("  \(self.accessModifier) func encode(to encoder: any Encoder) throws {")
    lines.append("    var container = encoder.singleValueContainer()")
    lines.append("    switch self {")
    for item in cases {
      lines.append("    case .\(item.caseName)(let value):")
      lines.append("      try container.encode(value)")
    }
    lines.append("    }")
    lines.append("  }")
    lines.append("}")
    return lines
  }

}

private struct GeneratedUnionCase {
  let caseName: String
  let swiftType: String
  let componentName: String?

  init(
    schema: OpenAPISchema,
    index: Int,
    components: [String: OpenAPISchema]
  ) throws {
    guard let swiftType = try schema.swiftType(components: components, inlineObjectFallback: nil) else {
      throw OpenAPIGeneratorError.unsupported("Inline object union entries are not generated yet.")
    }
    let componentName: String?
    if let ref = schema.ref {
      componentName = try OpenAPIReference.componentName(
        forReference: ref,
        prefix: "#/components/schemas/",
        kind: "schema"
      )
    } else {
      componentName = nil
    }
    self.swiftType = swiftType
    self.componentName = componentName
    self.caseName = Self.caseName(
      componentName: componentName,
      swiftType: swiftType,
      index: index
    )
  }

  private static func caseName(
    componentName: String?,
    swiftType: String,
    index: Int
  ) -> String {
    if let componentName {
      return componentName.swiftIdentifier()
    }

    switch swiftType {
    case "String":
      return "string"
    case "Int":
      return "int"
    case "Int64":
      return "int64"
    case "Double":
      return "double"
    case "Float":
      return "float"
    case "Bool":
      return "bool"
    case "Data":
      return "data"
    case "Date":
      return "date"
    case "UUID":
      return "uuid"
    default:
      let name = swiftType
        .replacingOccurrences(of: "[", with: "")
        .replacingOccurrences(of: "]", with: "")
        .replacingOccurrences(of: ":", with: " ")
      let caseName = name.swiftIdentifier()
      return caseName == "value" ? "value\(index + 1)" : caseName
    }
  }
}

private struct GeneratedObjectSchemaRenderer {
  let accessModifier: String
  let originalName: String
  let typeName: String
  let schema: OpenAPISchema
  let components: [String: OpenAPISchema]
  var indentation = ""

  func renderedLines() throws -> [String] {
    let properties = try self.schema.objectPropertyEntries(components: self.components).map { entry in
      try GeneratedSchemaProperty(
        name: entry.name,
        schema: entry.schema,
        isRequired: entry.isRequired,
        accessModifier: self.accessModifier,
        components: self.components
      )
    }
    let duplicatePropertyNames = Dictionary(grouping: properties, by: \.swiftName)
      .filter { $0.value.count > 1 }
      .map(\.key)
      .sorted()
    guard duplicatePropertyNames.isEmpty else {
      throw OpenAPIGeneratorError.invalidDocument(
        "\(self.originalName) has properties that generate duplicate Swift names: \(duplicatePropertyNames.joined(separator: ", "))."
      )
    }
    let nestedModels = properties.flatMap(\.nestedModels)
    let duplicateNestedTypeNames = Dictionary(grouping: nestedModels, by: \.typeName)
      .filter { $0.value.count > 1 }
      .map(\.key)
      .sorted()
    guard duplicateNestedTypeNames.isEmpty else {
      throw OpenAPIGeneratorError.invalidDocument(
        "\(self.originalName) has nested schemas that generate duplicate Swift type names: \(duplicateNestedTypeNames.joined(separator: ", "))."
      )
    }

    var lines: [String] = []
    lines.append("\(self.indentation)\(self.accessModifier) struct \(self.typeName): Codable, Sendable {")
    if properties.isEmpty {
      lines.append("\(self.indentation)  \(self.accessModifier) init() {}")
      lines.append("\(self.indentation)}")
      return lines
    }

    for nestedModel in nestedModels {
      lines.append(contentsOf: try nestedModel.renderedLines(indentation: "\(self.indentation)  "))
      lines.append("")
    }

    for property in properties {
      lines.append("\(self.indentation)  \(self.accessModifier) let \(property.swiftName): \(property.swiftType)")
    }

    lines.append("")
    lines.append("\(self.indentation)  \(self.accessModifier) init(")
    for index in properties.indices {
      lines.append(properties[index].initArgument(indentation: self.indentation) + (index == properties.indices.last ? "" : ","))
    }
    lines.append("\(self.indentation)  ) {")
    for property in properties {
      lines.append("\(self.indentation)    self.\(property.swiftName) = \(property.swiftName)")
    }
    lines.append("\(self.indentation)  }")

    if properties.contains(where: { $0.swiftName.unescapedSwiftIdentifier != $0.originalName }) {
      lines.append("")
      lines.append("\(self.indentation)  private enum CodingKeys: String, CodingKey {")
      for property in properties {
        if property.swiftName.unescapedSwiftIdentifier == property.originalName {
          lines.append("\(self.indentation)    case \(property.swiftName)")
        } else {
          lines.append("\(self.indentation)    case \(property.swiftName) = \(property.originalName.swiftLiteral)")
        }
      }
      lines.append("\(self.indentation)  }")
    }

    lines.append("\(self.indentation)}")
    return lines
  }
}

private struct GeneratedSchemaProperty {
  let originalName: String
  let swiftName: String
  let swiftType: String
  let isRequired: Bool
  let nestedModels: [GeneratedNestedSchemaModel]

  init(
    name: String,
    schema: OpenAPISchema,
    isRequired: Bool,
    accessModifier: String,
    components: [String: OpenAPISchema]
  ) throws {
    self.originalName = name
    self.swiftName = name.swiftIdentifier()
    self.isRequired = isRequired && !schema.nullable
    let baseType: String
    if let type = try schema.swiftType(components: components, inlineObjectFallback: nil) {
      baseType = type
      self.nestedModels = []
    } else if schema.isInlineObject {
      let nestedModel = GeneratedNestedSchemaModel(
        accessModifier: accessModifier,
        originalName: name,
        typeName: name.swiftTypeName(),
        schema: schema,
        components: components
      )
      baseType = nestedModel.typeName
      self.nestedModels = [nestedModel]
    } else if schema.type == "array", let items = schema.items, items.isInlineObject {
      let nestedModel = GeneratedNestedSchemaModel(
        accessModifier: accessModifier,
        originalName: name,
        typeName: "\(name.swiftTypeName())Item",
        schema: items,
        components: components
      )
      baseType = "[\(nestedModel.typeName)]"
      self.nestedModels = [nestedModel]
    } else {
      throw OpenAPIGeneratorError.unsupported("Nested inline object schemas are not generated yet: \(name).")
    }
    self.swiftType = self.isRequired ? baseType : "\(baseType)?"
  }

  func initArgument(indentation: String) -> String {
    "\(indentation)    \(self.swiftName): \(self.swiftType)\(self.isRequired ? "" : " = nil")"
  }
}

private struct GeneratedNestedSchemaModel {
  let accessModifier: String
  let originalName: String
  let typeName: String
  let schema: OpenAPISchema
  let components: [String: OpenAPISchema]

  func renderedLines(indentation: String) throws -> [String] {
    try GeneratedObjectSchemaRenderer(
      accessModifier: self.accessModifier,
      originalName: self.originalName,
      typeName: self.typeName,
      schema: self.schema,
      components: self.components,
      indentation: indentation
    )
    .renderedLines()
  }
}

private struct GeneratedParameter {
  let originalName: String
  let swiftName: String
  let location: OpenAPIParameterLocation
  let isRequired: Bool
  let baseType: String
  let swiftType: String

  init(_ parameter: OpenAPIParameter, components: [String: OpenAPISchema]) throws {
    guard let name = parameter.name, let location = parameter.location else {
      throw OpenAPIGeneratorError.invalidDocument("Parameter is missing a required name or location.")
    }
    guard location != .cookie else {
      throw OpenAPIGeneratorError.unsupported("Cookie parameters are not generated yet: \(name).")
    }
    guard location != .header || name.isValidHTTPFieldName else {
      throw OpenAPIGeneratorError.invalidDocument("Header parameter has an invalid HTTP field name: \(name).")
    }

    self.originalName = name
    self.swiftName = name.swiftIdentifier()
    self.location = location
    self.isRequired = parameter.required || location == .path
    self.baseType = try parameter.schema.swiftType(
      components: components,
      inlineObjectFallback: "String"
    ) ?? "String"
    self.swiftType = self.isRequired ? self.baseType : "\(self.baseType)?"
  }

  func queryItemLines() -> [String] {
    if self.isRequired {
      return ["    items.append(QueryItem(\(self.originalName.swiftLiteral), self.\(self.swiftName)))"]
    }
    return [
      "    if let \(self.swiftName) = self.\(self.swiftName) {",
      "      items.append(QueryItem(\(self.originalName.swiftLiteral), \(self.swiftName)))",
      "    }"
    ]
  }

  func headerLines() -> [String] {
    let headerName = "HTTPField.Name(\(self.originalName.swiftLiteral))!"
    if self.isRequired {
      return ["    headers[\(headerName)] = String(describing: self.\(self.swiftName))"]
    }
    return [
      "    if let \(self.swiftName) = self.\(self.swiftName) {",
      "      headers[\(headerName)] = String(describing: \(self.swiftName))",
      "    }"
    ]
  }
}

private struct OpenAPIDocument: Decodable {
  let openapi: String?
  let components: OpenAPIComponents?
  let security: [OpenAPISecurityRequirement]
  let paths: [String: OpenAPIPathItem]

  private enum CodingKeys: String, CodingKey {
    case openapi
    case components
    case security
    case paths
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.openapi = try container.decodeIfPresent(String.self, forKey: .openapi)
    self.components = try container.decodeIfPresent(OpenAPIComponents.self, forKey: .components)
    self.security = try container.decodeIfPresent([OpenAPISecurityRequirement].self, forKey: .security) ?? []
    self.paths = try container.decode([String: OpenAPIPathItem].self, forKey: .paths)
  }
}

private struct OpenAPIComponents: Decodable {
  let schemas: [String: OpenAPISchema]
  let parameters: [String: OpenAPIParameter]
  let requestBodies: [String: OpenAPIRequestBody]
  let responses: [String: OpenAPIResponse]
  let securitySchemes: [String: OpenAPISecurityScheme]

  private enum CodingKeys: String, CodingKey {
    case schemas
    case parameters
    case requestBodies
    case responses
    case securitySchemes
  }

  init(
    schemas: [String: OpenAPISchema] = [:],
    parameters: [String: OpenAPIParameter] = [:],
    requestBodies: [String: OpenAPIRequestBody] = [:],
    responses: [String: OpenAPIResponse] = [:],
    securitySchemes: [String: OpenAPISecurityScheme] = [:]
  ) {
    self.schemas = schemas
    self.parameters = parameters
    self.requestBodies = requestBodies
    self.responses = responses
    self.securitySchemes = securitySchemes
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.schemas = try container.decodeIfPresent([String: OpenAPISchema].self, forKey: .schemas) ?? [:]
    self.parameters = try container.decodeIfPresent([String: OpenAPIParameter].self, forKey: .parameters) ?? [:]
    self.requestBodies = try container.decodeIfPresent([String: OpenAPIRequestBody].self, forKey: .requestBodies) ?? [:]
    self.responses = try container.decodeIfPresent([String: OpenAPIResponse].self, forKey: .responses) ?? [:]
    self.securitySchemes = try container.decodeIfPresent(
      [String: OpenAPISecurityScheme].self,
      forKey: .securitySchemes
    ) ?? [:]
  }
}

private typealias OpenAPISecurityRequirement = [String: [String]]

private struct OpenAPISecurityScheme: Decodable {}

private enum OpenAPIReference {
  static func componentName(
    forReference ref: String,
    prefix: String,
    kind: String
  ) throws -> String {
    guard let encodedName = ref.split(separator: "/").last.map(String.init), !encodedName.isEmpty else {
      throw OpenAPIGeneratorError.invalidDocument("Unsupported \(kind) reference: \(ref).")
    }
    guard ref.hasPrefix(prefix) else {
      throw OpenAPIGeneratorError.unsupported("Only local component \(kind) references are generated: \(ref).")
    }
    return encodedName
      .replacingOccurrences(of: "~1", with: "/")
      .replacingOccurrences(of: "~0", with: "~")
  }
}

private struct OpenAPIPathItem: Decodable {
  let parameters: [OpenAPIParameter]
  let get: OpenAPIOperation?
  let post: OpenAPIOperation?
  let put: OpenAPIOperation?
  let patch: OpenAPIOperation?
  let delete: OpenAPIOperation?
  let head: OpenAPIOperation?
  let options: OpenAPIOperation?

  private enum CodingKeys: String, CodingKey {
    case parameters
    case get
    case post
    case put
    case patch
    case delete
    case head
    case options
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.parameters = try container.decodeIfPresent([OpenAPIParameter].self, forKey: .parameters) ?? []
    self.get = try container.decodeIfPresent(OpenAPIOperation.self, forKey: .get)
    self.post = try container.decodeIfPresent(OpenAPIOperation.self, forKey: .post)
    self.put = try container.decodeIfPresent(OpenAPIOperation.self, forKey: .put)
    self.patch = try container.decodeIfPresent(OpenAPIOperation.self, forKey: .patch)
    self.delete = try container.decodeIfPresent(OpenAPIOperation.self, forKey: .delete)
    self.head = try container.decodeIfPresent(OpenAPIOperation.self, forKey: .head)
    self.options = try container.decodeIfPresent(OpenAPIOperation.self, forKey: .options)
  }

  func operation(for method: HTTPMethodName) -> OpenAPIOperation? {
    switch method {
    case .get:
      return self.get
    case .post:
      return self.post
    case .put:
      return self.put
    case .patch:
      return self.patch
    case .delete:
      return self.delete
    case .head:
      return self.head
    case .options:
      return self.options
    }
  }
}

private struct OpenAPIOperation: Decodable {
  let operationID: String?
  let parameters: [OpenAPIParameter]
  let requestBody: OpenAPIRequestBody?
  let responses: [String: OpenAPIResponse]
  let security: [OpenAPISecurityRequirement]?

  private enum CodingKeys: String, CodingKey {
    case operationID = "operationId"
    case parameters
    case requestBody
    case responses
    case security
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.operationID = try container.decodeIfPresent(String.self, forKey: .operationID)
    self.parameters = try container.decodeIfPresent([OpenAPIParameter].self, forKey: .parameters) ?? []
    self.requestBody = try container.decodeIfPresent(OpenAPIRequestBody.self, forKey: .requestBody)
    self.responses = try container.decodeIfPresent([String: OpenAPIResponse].self, forKey: .responses) ?? [:]
    self.security = try container.decodeIfPresent([OpenAPISecurityRequirement].self, forKey: .security)
  }
}

private struct OpenAPIParameter: Decodable {
  let ref: String?
  let name: String?
  let location: OpenAPIParameterLocation?
  let required: Bool
  let schema: OpenAPISchema

  private enum CodingKeys: String, CodingKey {
    case ref = "$ref"
    case name
    case location = "in"
    case required
    case schema
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.ref = try container.decodeIfPresent(String.self, forKey: .ref)
    self.name = try container.decodeIfPresent(String.self, forKey: .name)
    self.location = try container.decodeIfPresent(OpenAPIParameterLocation.self, forKey: .location)
    self.required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
    self.schema = try container.decodeIfPresent(OpenAPISchema.self, forKey: .schema) ?? OpenAPISchema()
  }

  func resolved(
    components: OpenAPIComponents,
    visitedReferences: Set<String> = []
  ) throws -> OpenAPIParameter {
    guard let ref else { return self }
    guard !visitedReferences.contains(ref) else {
      throw OpenAPIGeneratorError.invalidDocument("Recursive parameter reference was found: \(ref).")
    }
    let componentName = try OpenAPIReference.componentName(
      forReference: ref,
      prefix: "#/components/parameters/",
      kind: "parameter"
    )
    guard let parameter = components.parameters[componentName] else {
      throw OpenAPIGeneratorError.invalidDocument("Parameter reference was not found: \(ref).")
    }
    return try parameter.resolved(
      components: components,
      visitedReferences: visitedReferences.union([ref])
    )
  }
}

private enum OpenAPIParameterLocation: String, Decodable {
  case path
  case query
  case header
  case cookie
}

private struct OpenAPIRequestBody: Decodable {
  let ref: String?
  let required: Bool
  let content: [String: OpenAPIMediaType]

  private enum CodingKeys: String, CodingKey {
    case ref = "$ref"
    case required
    case content
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.ref = try container.decodeIfPresent(String.self, forKey: .ref)
    self.required = try container.decodeIfPresent(Bool.self, forKey: .required) ?? false
    self.content = try container.decodeIfPresent([String: OpenAPIMediaType].self, forKey: .content) ?? [:]
  }

  func resolved(
    components: OpenAPIComponents,
    visitedReferences: Set<String> = []
  ) throws -> OpenAPIRequestBody {
    guard let ref else { return self }
    guard !visitedReferences.contains(ref) else {
      throw OpenAPIGeneratorError.invalidDocument("Recursive request body reference was found: \(ref).")
    }
    let componentName = try OpenAPIReference.componentName(
      forReference: ref,
      prefix: "#/components/requestBodies/",
      kind: "request body"
    )
    guard let requestBody = components.requestBodies[componentName] else {
      throw OpenAPIGeneratorError.invalidDocument("Request body reference was not found: \(ref).")
    }
    return try requestBody.resolved(
      components: components,
      visitedReferences: visitedReferences.union([ref])
    )
  }
}

private struct OpenAPIResponse: Decodable {
  let ref: String?
  let content: [String: OpenAPIMediaType]

  private enum CodingKeys: String, CodingKey {
    case ref = "$ref"
    case content
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.ref = try container.decodeIfPresent(String.self, forKey: .ref)
    self.content = try container.decodeIfPresent([String: OpenAPIMediaType].self, forKey: .content) ?? [:]
  }

  func resolved(
    components: OpenAPIComponents,
    visitedReferences: Set<String> = []
  ) throws -> OpenAPIResponse {
    guard let ref else { return self }
    guard !visitedReferences.contains(ref) else {
      throw OpenAPIGeneratorError.invalidDocument("Recursive response reference was found: \(ref).")
    }
    let componentName = try OpenAPIReference.componentName(
      forReference: ref,
      prefix: "#/components/responses/",
      kind: "response"
    )
    guard let response = components.responses[componentName] else {
      throw OpenAPIGeneratorError.invalidDocument("Response reference was not found: \(ref).")
    }
    return try response.resolved(
      components: components,
      visitedReferences: visitedReferences.union([ref])
    )
  }
}

private struct OpenAPIMediaType: Decodable {
  let schema: OpenAPISchema?
}

private struct OpenAPIDiscriminator: Decodable {
  let propertyName: String
  let mapping: [String: String]

  private enum CodingKeys: String, CodingKey {
    case propertyName
    case mapping
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.propertyName = try container.decode(String.self, forKey: .propertyName)
    self.mapping = try container.decodeIfPresent([String: String].self, forKey: .mapping) ?? [:]
  }

  static func componentName(forMappingValue value: String) throws -> String {
    if value.hasPrefix("#/components/schemas/") {
      return try OpenAPIReference.componentName(
        forReference: value,
        prefix: "#/components/schemas/",
        kind: "schema"
      )
    }
    guard !value.contains("/") else {
      throw OpenAPIGeneratorError.unsupported(
        "Only local discriminator mapping references are generated: \(value)."
      )
    }
    return value
  }
}

private enum OpenAPIAdditionalProperties: Decodable {
  case allowed
  case disallowed
  case schema(OpenAPISchema)

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let allowed = try? container.decode(Bool.self) {
      self = allowed ? .allowed : .disallowed
    } else {
      self = .schema(try container.decode(OpenAPISchema.self))
    }
  }
}

private struct OpenAPIObjectPropertyEntry {
  let name: String
  let schema: OpenAPISchema
  let isRequired: Bool
}

private final class OpenAPISchema: Decodable {
  let ref: String?
  let type: String?
  let format: String?
  let nullable: Bool
  let enumValues: [String]?
  let items: OpenAPISchema?
  let properties: [String: OpenAPISchema]
  let required: Set<String>
  let additionalProperties: OpenAPIAdditionalProperties?
  let allOf: [OpenAPISchema]
  let oneOf: [OpenAPISchema]
  let anyOf: [OpenAPISchema]
  let discriminator: OpenAPIDiscriminator?

  init(
    ref: String? = nil,
    type: String? = nil,
    format: String? = nil,
    nullable: Bool = false,
    enumValues: [String]? = nil,
    items: OpenAPISchema? = nil,
    properties: [String: OpenAPISchema] = [:],
    required: Set<String> = [],
    additionalProperties: OpenAPIAdditionalProperties? = nil,
    allOf: [OpenAPISchema] = [],
    oneOf: [OpenAPISchema] = [],
    anyOf: [OpenAPISchema] = [],
    discriminator: OpenAPIDiscriminator? = nil
  ) {
    self.ref = ref
    self.type = type
    self.format = format
    self.nullable = nullable
    self.enumValues = enumValues
    self.items = items
    self.properties = properties
    self.required = required
    self.additionalProperties = additionalProperties
    self.allOf = allOf
    self.oneOf = oneOf
    self.anyOf = anyOf
    self.discriminator = discriminator
  }

  private enum CodingKeys: String, CodingKey {
    case ref = "$ref"
    case type
    case format
    case nullable
    case enumValues = "enum"
    case items
    case properties
    case required
    case additionalProperties
    case allOf
    case oneOf
    case anyOf
    case discriminator
  }

  convenience init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let decodedType: String?
    let nullableFromType: Bool
    if let type = try? container.decode(String.self, forKey: .type) {
      decodedType = type
      nullableFromType = false
    } else if let types = try? container.decode([String].self, forKey: .type) {
      decodedType = types.first { $0 != "null" }
      nullableFromType = types.contains("null")
    } else {
      decodedType = nil
      nullableFromType = false
    }

    self.init(
      ref: try container.decodeIfPresent(String.self, forKey: .ref),
      type: decodedType,
      format: try container.decodeIfPresent(String.self, forKey: .format),
      nullable: (try container.decodeIfPresent(Bool.self, forKey: .nullable) ?? false) || nullableFromType,
      enumValues: try container.decodeIfPresent([String].self, forKey: .enumValues),
      items: try container.decodeIfPresent(OpenAPISchema.self, forKey: .items),
      properties: try container.decodeIfPresent([String: OpenAPISchema].self, forKey: .properties) ?? [:],
      required: Set(try container.decodeIfPresent([String].self, forKey: .required) ?? []),
      additionalProperties: try container.decodeIfPresent(
        OpenAPIAdditionalProperties.self,
        forKey: .additionalProperties
      ),
      allOf: try container.decodeIfPresent([OpenAPISchema].self, forKey: .allOf) ?? [],
      oneOf: try container.decodeIfPresent([OpenAPISchema].self, forKey: .oneOf) ?? [],
      anyOf: try container.decodeIfPresent([OpenAPISchema].self, forKey: .anyOf) ?? [],
      discriminator: try container.decodeIfPresent(OpenAPIDiscriminator.self, forKey: .discriminator)
    )
  }

  func swiftType(
    components: [String: OpenAPISchema],
    inlineObjectFallback: String?
  ) throws -> String? {
    if let ref {
      let componentName = try Self.componentName(forReference: ref)
      guard components[componentName] != nil else {
        throw OpenAPIGeneratorError.invalidDocument("Schema reference was not found: \(ref).")
      }
      return componentName.swiftTypeName()
    }
    if self.isUnion {
      return inlineObjectFallback
    }
    if let enumValues, !enumValues.isEmpty, self.type == "string" {
      return "String"
    }
    if self.type == "array" {
      guard let items else { return "[String]" }
      guard let itemType = try items.swiftType(components: components, inlineObjectFallback: inlineObjectFallback) else {
        return nil
      }
      return "[\(itemType)]"
    }
    if let dictionaryType = try self.dictionarySwiftType(
      components: components,
      inlineObjectFallback: inlineObjectFallback
    ) {
      return dictionaryType
    }
    if self.isInlineObject {
      return inlineObjectFallback
    }

    switch (self.type, self.format) {
    case ("string", "binary"):
      return "Data"
    case ("string", "date"), ("string", "date-time"):
      return "Date"
    case ("string", "uuid"):
      return "UUID"
    case ("integer", "int64"):
      return "Int64"
    case ("integer", _):
      return "Int"
    case ("number", "float"):
      return "Float"
    case ("number", _):
      return "Double"
    case ("boolean", _):
      return "Bool"
    case ("string", _):
      return "String"
    default:
      return inlineObjectFallback ?? "String"
    }
  }

  private static func componentName(forReference ref: String) throws -> String {
    try OpenAPIReference.componentName(
      forReference: ref,
      prefix: "#/components/schemas/",
      kind: "schema"
    )
  }

  func dictionarySwiftType(
    components: [String: OpenAPISchema],
    inlineObjectFallback: String?
  ) throws -> String? {
    guard let additionalProperties else { return nil }
    let hasNamedShape = !self.properties.isEmpty || !self.allOf.isEmpty
    switch additionalProperties {
    case .disallowed:
      return nil
    case .allowed:
      guard hasNamedShape else {
        return "[String: CometOpenAPIJSONValue]"
      }
      throw OpenAPIGeneratorError.unsupported(
        "Object schemas that combine named properties and additionalProperties are not generated yet."
      )
    case let .schema(valueSchema):
      guard !hasNamedShape else {
        throw OpenAPIGeneratorError.unsupported(
          "Object schemas that combine named properties and additionalProperties are not generated yet."
        )
      }
      guard let valueType = try valueSchema.swiftType(
        components: components,
        inlineObjectFallback: inlineObjectFallback
      ) else {
        throw OpenAPIGeneratorError.unsupported(
          "Dictionary schemas with inline object values are not generated yet."
        )
      }
      return "[String: \(valueType)]"
    }
  }

  func objectPropertyEntries(components: [String: OpenAPISchema]) throws -> [OpenAPIObjectPropertyEntry] {
    if case .schema = self.additionalProperties, !self.properties.isEmpty || !self.allOf.isEmpty {
      throw OpenAPIGeneratorError.unsupported(
        "Object schemas that combine named properties and additionalProperties are not generated yet."
      )
    }
    if case .allowed = self.additionalProperties, !self.properties.isEmpty || !self.allOf.isEmpty {
      throw OpenAPIGeneratorError.unsupported(
        "Object schemas that combine named properties and additionalProperties are not generated yet."
      )
    }

    var entries: [OpenAPIObjectPropertyEntry] = []
    for schema in self.allOf {
      let resolvedSchema = try schema.resolved(components: components)
      guard resolvedSchema.isObjectLike else {
        throw OpenAPIGeneratorError.unsupported("allOf entries must resolve to object schemas.")
      }
      if try resolvedSchema.dictionarySwiftType(components: components, inlineObjectFallback: nil) != nil {
        throw OpenAPIGeneratorError.unsupported(
          "Dictionary schemas inside allOf object composition are not generated yet."
        )
      }
      entries.append(contentsOf: try resolvedSchema.objectPropertyEntries(components: components))
    }
    entries.append(
      contentsOf: self.properties.keys.sorted().map { name in
        OpenAPIObjectPropertyEntry(
          name: name,
          schema: self.properties[name]!,
          isRequired: self.required.contains(name)
        )
      }
    )
    return entries
  }

  func resolved(
    components: [String: OpenAPISchema],
    visitedReferences: Set<String> = []
  ) throws -> OpenAPISchema {
    guard let ref else { return self }
    guard !visitedReferences.contains(ref) else {
      throw OpenAPIGeneratorError.invalidDocument("Recursive schema reference was found: \(ref).")
    }
    let componentName = try Self.componentName(forReference: ref)
    guard let schema = components[componentName] else {
      throw OpenAPIGeneratorError.invalidDocument("Schema reference was not found: \(ref).")
    }
    return try schema.resolved(
      components: components,
      visitedReferences: visitedReferences.union([ref])
    )
  }

  var isObjectLike: Bool {
    self.type == "object"
      || !self.properties.isEmpty
      || !self.allOf.isEmpty
      || self.additionalProperties != nil
  }

  var isInlineObject: Bool {
    self.ref == nil && self.isObjectLike
  }

  var isUnion: Bool {
    !self.oneOf.isEmpty || !self.anyOf.isEmpty
  }

  var unionVariants: [OpenAPISchema] {
    self.oneOf.isEmpty ? self.anyOf : self.oneOf
  }
}

private enum HTTPMethodName: String, CaseIterable {
  case get
  case post
  case put
  case patch
  case delete
  case head
  case options

  var swiftExpression: String {
    switch self {
    case .get:
      return ".get"
    case .post:
      return ".post"
    case .put:
      return ".put"
    case .patch:
      return ".patch"
    case .delete:
      return ".delete"
    case .head:
      return ".head"
    case .options:
      return ".options"
    }
  }
}

private extension String {
  var swiftLiteral: String {
    String(reflecting: self)
  }

  func swiftIdentifier() -> String {
    let words = self.identifierWords()
    guard let first = words.first else { return "value" }
    let name = ([first.lowercased()] + words.dropFirst().map(\.capitalized)).joined()
    let prefixedName = name.prefixedIfNeededForSwiftIdentifier(prefix: "value")
    guard prefixedName != "self" else { return "selfValue" }
    return SwiftKeywords.escaped(prefixedName)
  }

  func swiftTypeName() -> String {
    let name = self.identifierWords().map(\.swiftTypeWord).joined()
    guard !name.isEmpty else { return "GeneratedValue" }
    return SwiftKeywords.escapedTypeName(name.prefixedIfNeededForSwiftIdentifier(prefix: "Generated"))
  }

  var swiftTypeWord: String {
    let scalars = Array(self.unicodeScalars)
    if scalars.count > 1, scalars.allSatisfy({ CharacterSet.uppercaseLetters.contains($0) }) {
      return self
    }
    return self.capitalized
  }

  var unescapedSwiftIdentifier: String {
    if self.hasPrefix("`"), self.hasSuffix("`") {
      return String(self.dropFirst().dropLast())
    }
    return self
  }

  func identifierWords() -> [String] {
    var words: [String] = []
    var current = ""
    let scalars = Array(self.unicodeScalars)

    func flushCurrent() {
      guard !current.isEmpty else { return }
      words.append(current)
      current = ""
    }

    for index in scalars.indices {
      let scalar = scalars[index]
      guard CharacterSet.alphanumerics.contains(scalar) else {
        flushCurrent()
        continue
      }

      let isUppercase = CharacterSet.uppercaseLetters.contains(scalar)
      let previous = index > scalars.startIndex ? scalars[scalars.index(before: index)] : nil
      let next = index < scalars.index(before: scalars.endIndex) ? scalars[scalars.index(after: index)] : nil
      let previousWasLowercaseOrNumber = previous.map {
        CharacterSet.lowercaseLetters.contains($0) || CharacterSet.decimalDigits.contains($0)
      } ?? false
      let previousWasUppercase = previous.map { CharacterSet.uppercaseLetters.contains($0) } ?? false
      let nextIsLowercase = next.map { CharacterSet.lowercaseLetters.contains($0) } ?? false

      if isUppercase,
         !current.isEmpty,
         previousWasLowercaseOrNumber || (previousWasUppercase && nextIsLowercase) {
        flushCurrent()
      }

      current.append(Character(scalar))
    }

    flushCurrent()
    return words
  }

  func prefixedIfNeededForSwiftIdentifier(prefix: String) -> String {
    guard let first = self.unicodeScalars.first else { return prefix }
    guard !CharacterSet.decimalDigits.contains(first) else {
      return "\(prefix)\(self)"
    }
    return self
  }

  var isValidHTTPFieldName: Bool {
    guard !self.isEmpty else { return false }
    return self.utf8.allSatisfy { byte in
      switch byte {
      case 33, 35...39, 42, 43, 45, 46, 48...57, 65...90, 94...122, 124, 126:
        return true
      default:
        return false
      }
    }
  }
}

private enum SwiftKeywords {
  private static let values: Set<String> = [
    "associatedtype",
    "class",
    "deinit",
    "enum",
    "extension",
    "fileprivate",
    "func",
    "import",
    "init",
    "inout",
    "internal",
    "let",
    "open",
    "operator",
    "private",
    "precedencegroup",
    "protocol",
    "public",
    "rethrows",
    "static",
    "struct",
    "subscript",
    "typealias",
    "var",
    "break",
    "case",
    "continue",
    "default",
    "defer",
    "do",
    "else",
    "fallthrough",
    "for",
    "guard",
    "if",
    "in",
    "repeat",
    "return",
    "switch",
    "where",
    "while",
  ]

  static func escaped(_ name: String) -> String {
    self.values.contains(name) ? "`\(name)`" : name
  }

  static func escapedTypeName(_ name: String) -> String {
    self.values.contains(name) ? "`\(name)`" : name
  }
}
