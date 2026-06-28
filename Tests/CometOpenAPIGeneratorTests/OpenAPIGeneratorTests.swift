import Foundation
import Testing
import CometOpenAPIGenerator

@Test func openAPIGeneratorCreatesRequestTypesForParametersAndErrors() throws {
  let output = try OpenAPIGenerator().generate(
    jsonString: """
    {
      "openapi": "3.1.0",
      "paths": {
        "/pets/{petId}": {
          "get": {
            "operationId": "getPet",
            "parameters": [
              {
                "name": "petId",
                "in": "path",
                "required": true,
                "schema": { "type": "integer", "format": "int64" }
              },
              {
                "name": "includeOwner",
                "in": "query",
                "schema": { "type": "boolean" }
              },
              {
                "name": "X-Request-ID",
                "in": "header",
                "schema": { "type": "string" }
              }
            ],
            "responses": {
              "200": {
                "description": "OK",
                "content": {
                  "application/json": {
                    "schema": { "type": "object" }
                  }
                }
              },
              "404": {
                "description": "Missing",
                "content": {
                  "application/json": {
                    "schema": { "type": "object" }
                  }
                }
              }
            }
          }
        }
      }
    }
    """
  )

  #expect(output.contains("public struct GetPetRequest: APIRequestWithErrorResponse"))
  #expect(output.contains("public let petId: Int64"))
  #expect(output.contains("public let includeOwner: Bool?"))
  #expect(output.contains("public let xRequestId: String?"))
  #expect(output.contains(#""pets" / self.petId"#))
  #expect(output.contains(#"items.append(QueryItem("includeOwner", includeOwner))"#))
  #expect(output.contains(#"headers[HTTPField.Name("X-Request-ID")!] = String(describing: xRequestId)"#))
  #expect(output.contains("RequestMetadata(operationID: \"getPet\")"))
  #expect(output.contains("public let errorResponseSerializer: ErrorResponseSerializer<Data> = .data"))
}

@Test func openAPIGeneratorCreatesJSONBodyRequests() throws {
  let output = try OpenAPIGenerator().generate(
    jsonString: """
    {
      "openapi": "3.0.3",
      "paths": {
        "/pets": {
          "post": {
            "operationId": "createPet",
            "requestBody": {
              "required": true,
              "content": {
                "application/json": {
                  "schema": { "type": "object" }
                }
              }
            },
            "responses": {
              "201": {
                "description": "Created",
                "content": {
                  "text/plain": {
                    "schema": { "type": "string" }
                  }
                }
              }
            }
          }
        }
      }
    }
    """
  )

  #expect(output.contains("public struct CreatePetRequest<Body: Encodable & Sendable>: APIRequest"))
  #expect(output.contains("public let bodyPayload: Body"))
  #expect(output.contains("public var body: HTTPBody"))
  #expect(output.contains(".json(self.bodyPayload)"))
  #expect(output.contains("public typealias Response = String"))
  #expect(output.contains("public let responseSerializer: ResponseSerializer<String> = .string()"))
}

@Test func openAPIGeneratorInheritsAndOverridesPathItemParameters() throws {
  let output = try OpenAPIGenerator().generate(
    jsonString: """
    {
      "openapi": "3.1.0",
      "paths": {
        "/teams/{teamId}/members": {
          "parameters": [
            {
              "name": "teamId",
              "in": "path",
              "required": true,
              "schema": { "type": "integer" }
            },
            {
              "name": "includeInactive",
              "in": "query",
              "schema": { "type": "boolean" }
            }
          ],
          "get": {
            "operationId": "listMembers",
            "parameters": [
              {
                "name": "includeInactive",
                "in": "query",
                "required": true,
                "schema": { "type": "boolean" }
              }
            ],
            "responses": {
              "200": {
                "description": "OK",
                "content": {
                  "application/json": {
                    "schema": { "type": "array" }
                  }
                }
              }
            }
          }
        }
      }
    }
    """
  )

  #expect(output.contains("public let teamId: Int"))
  #expect(output.contains("public let includeInactive: Bool"))
  #expect(output.contains(#""teams" / self.teamId / "members""#))
  #expect(output.contains(#"items.append(QueryItem("includeInactive", self.includeInactive))"#))
}

@Test func openAPIGeneratorRejectsUnsupportedCookieParameters() throws {
  #expect(throws: OpenAPIGeneratorError.self) {
    _ = try OpenAPIGenerator().generate(
      jsonString: """
      {
        "openapi": "3.1.0",
        "paths": {
          "/session": {
            "get": {
              "operationId": "getSession",
              "parameters": [
                {
                  "name": "session",
                  "in": "cookie",
                  "schema": { "type": "string" }
                }
              ],
              "responses": {
                "204": { "description": "No Content" }
              }
            }
          }
        }
      }
      """
    )
  }
}
