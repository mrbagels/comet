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

@Test func openAPIGeneratorAcceptsYAMLDocuments() throws {
  let output = try OpenAPIGenerator().generate(
    yamlString: """
    openapi: 3.1.0
    components:
      schemas:
        Ping:
          type: object
          required:
            - message
          properties:
            message:
              type: string
    paths:
      /ping:
        get:
          operationId: ping
          responses:
            "200":
              description: OK
              content:
                application/json:
                  schema:
                    $ref: "#/components/schemas/Ping"
    """
  )

  #expect(output.contains("public struct Ping: Codable, Sendable"))
  #expect(output.contains("public struct PingRequest: APIRequest"))
  #expect(output.contains("public typealias Response = Ping"))
  #expect(output.contains("public let responseSerializer: ResponseSerializer<Ping> = .json(Ping.self)"))
}

@Test func openAPIGeneratorCreatesComponentModelsAndTypedJSONRequests() throws {
  let output = try OpenAPIGenerator().generate(
    jsonString: """
    {
      "openapi": "3.1.0",
      "components": {
        "schemas": {
          "CreatePet": {
            "type": "object",
            "required": ["name"],
            "properties": {
              "name": { "type": "string" },
              "tag": { "type": ["string", "null"] }
            }
          },
          "Pet": {
            "type": "object",
            "required": ["id", "name"],
            "properties": {
              "id": { "type": "integer", "format": "int64" },
              "name": { "type": "string" },
              "status": { "$ref": "#/components/schemas/PetStatus" },
              "tag": { "type": ["string", "null"] }
            }
          },
          "PetStatus": {
            "type": "string",
            "enum": ["available", "pending-review"]
          }
        }
      },
      "paths": {
        "/pets": {
          "post": {
            "operationId": "createPet",
            "requestBody": {
              "content": {
                "application/json": {
                  "schema": { "$ref": "#/components/schemas/CreatePet" }
                }
              }
            },
            "responses": {
              "201": {
                "description": "Created",
                "content": {
                  "application/json": {
                    "schema": { "$ref": "#/components/schemas/Pet" }
                  }
                }
              }
            }
          },
          "get": {
            "operationId": "listPets",
            "responses": {
              "200": {
                "description": "OK",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "array",
                      "items": { "$ref": "#/components/schemas/Pet" }
                    }
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

  #expect(output.contains("public struct CreatePet: Codable, Sendable"))
  #expect(output.contains("public let name: String"))
  #expect(output.contains("public let tag: String?"))
  #expect(output.contains("public init("))
  #expect(output.contains("tag: String? = nil"))
  #expect(output.contains("public struct Pet: Codable, Sendable"))
  #expect(output.contains("public let id: Int64"))
  #expect(output.contains("public let status: PetStatus?"))
  #expect(output.contains("public enum PetStatus: String, Codable, Sendable"))
  #expect(output.contains(#"case pendingReview = "pending-review""#))
  #expect(output.contains("public struct CreatePetRequest: APIRequest"))
  #expect(output.contains("public let bodyPayload: CreatePet"))
  #expect(output.contains("public typealias Response = Pet"))
  #expect(output.contains("public let responseSerializer: ResponseSerializer<Pet> = .json(Pet.self)"))
  #expect(output.contains("public struct ListPetsRequest: APIRequest"))
  #expect(output.contains("public typealias Response = [Pet]"))
  #expect(output.contains("public let responseSerializer: ResponseSerializer<[Pet]> = .json([Pet].self)"))
  #expect(!output.contains("CreatePetRequest<Body"))
}

@Test func openAPIGeneratorCreatesComponentAliasesToReferences() throws {
  let output = try OpenAPIGenerator().generate(
    jsonString: """
    {
      "openapi": "3.1.0",
      "components": {
        "schemas": {
          "Pet": {
            "type": "object",
            "required": ["id"],
            "properties": {
              "id": { "type": "integer" }
            }
          },
          "pet-alias": {
            "$ref": "#/components/schemas/Pet"
          }
        }
      },
      "paths": {
        "/pets/{petId}": {
          "get": {
            "operationId": "getPetAlias",
            "parameters": [
              {
                "name": "petId",
                "in": "path",
                "required": true,
                "schema": { "type": "integer" }
              }
            ],
            "responses": {
              "200": {
                "description": "OK",
                "content": {
                  "application/json": {
                    "schema": { "$ref": "#/components/schemas/pet-alias" }
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

  #expect(output.contains("public struct Pet: Codable, Sendable"))
  #expect(output.contains("public typealias PetAlias = Pet"))
  #expect(output.contains("public typealias Response = PetAlias"))
  #expect(output.contains("public let responseSerializer: ResponseSerializer<PetAlias> = .json(PetAlias.self)"))
}

@Test func openAPIGeneratorCreatesNestedInlineObjectComponentModels() throws {
  let output = try OpenAPIGenerator().generate(
    jsonString: """
    {
      "openapi": "3.1.0",
      "components": {
        "schemas": {
          "Pet": {
            "type": "object",
            "required": ["id", "owner"],
            "properties": {
              "id": { "type": "integer" },
              "owner": {
                "type": "object",
                "required": ["id"],
                "properties": {
                  "id": { "type": "string" },
                  "display-name": { "type": "string" },
                  "preferences": {
                    "type": "object",
                    "properties": {
                      "email-opt-in": { "type": "boolean" }
                    }
                  }
                }
              },
              "visit-history": {
                "type": "array",
                "items": {
                  "type": "object",
                  "required": ["date"],
                  "properties": {
                    "date": { "type": "string", "format": "date" },
                    "notes": { "type": "string" }
                  }
                }
              }
            }
          }
        }
      },
      "paths": {
        "/pets": {
          "get": {
            "operationId": "listPets",
            "responses": {
              "200": {
                "description": "OK",
                "content": {
                  "application/json": {
                    "schema": {
                      "type": "array",
                      "items": { "$ref": "#/components/schemas/Pet" }
                    }
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

  #expect(output.contains("public struct Pet: Codable, Sendable"))
  #expect(output.contains("public struct Owner: Codable, Sendable"))
  #expect(output.contains("public struct Preferences: Codable, Sendable"))
  #expect(output.contains("public struct VisitHistoryItem: Codable, Sendable"))
  #expect(output.contains("public let owner: Owner"))
  #expect(output.contains("public let visitHistory: [VisitHistoryItem]?"))
  #expect(output.contains("public let displayName: String?"))
  #expect(output.contains("public let preferences: Preferences?"))
  #expect(output.contains("public let emailOptIn: Bool?"))
  #expect(output.contains("public let date: Date"))
  #expect(output.contains("public let notes: String?"))
  #expect(output.contains(#"case displayName = "display-name""#))
  #expect(output.contains(#"case emailOptIn = "email-opt-in""#))
  #expect(output.contains(#"case visitHistory = "visit-history""#))
  #expect(output.contains("public typealias Response = [Pet]"))
}

@Test func openAPIGeneratorCreatesDictionarySchemaModels() throws {
  let output = try OpenAPIGenerator().generate(
    jsonString: """
    {
      "openapi": "3.1.0",
      "components": {
        "schemas": {
          "MetadataMap": {
            "type": "object",
            "additionalProperties": { "type": "string" }
          },
          "ScoreMap": {
            "type": "object",
            "additionalProperties": { "type": "integer" }
          },
          "Owner": {
            "type": "object",
            "required": ["id"],
            "properties": {
              "id": { "type": "string" }
            }
          },
          "Pet": {
            "type": "object",
            "properties": {
              "labels": {
                "type": "object",
                "additionalProperties": { "type": "string" }
              },
              "ownersByRole": {
                "type": "object",
                "additionalProperties": { "$ref": "#/components/schemas/Owner" }
              },
              "scores": { "$ref": "#/components/schemas/ScoreMap" }
            }
          }
        }
      },
      "paths": {
        "/pets/{petId}": {
          "get": {
            "operationId": "getPet",
            "parameters": [
              {
                "name": "petId",
                "in": "path",
                "required": true,
                "schema": { "type": "integer" }
              }
            ],
            "responses": {
              "200": {
                "description": "OK",
                "content": {
                  "application/json": {
                    "schema": { "$ref": "#/components/schemas/Pet" }
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

  #expect(output.contains("public typealias MetadataMap = [String: String]"))
  #expect(output.contains("public typealias ScoreMap = [String: Int]"))
  #expect(output.contains("public struct Owner: Codable, Sendable"))
  #expect(output.contains("public let labels: [String: String]?"))
  #expect(output.contains("public let ownersByRole: [String: Owner]?"))
  #expect(output.contains("public let scores: ScoreMap?"))
  #expect(output.contains("public typealias Response = Pet"))
}

@Test func openAPIGeneratorCreatesAllOfComponentModels() throws {
  let output = try OpenAPIGenerator().generate(
    jsonString: """
    {
      "openapi": "3.1.0",
      "components": {
        "schemas": {
          "User": {
            "type": "object",
            "required": ["id"],
            "properties": {
              "id": { "type": "string" },
              "name": { "type": "string" }
            }
          },
          "Audited": {
            "type": "object",
            "properties": {
              "createdAt": { "type": "string", "format": "date-time" }
            }
          },
          "AdminUser": {
            "allOf": [
              { "$ref": "#/components/schemas/User" },
              { "$ref": "#/components/schemas/Audited" },
              {
                "type": "object",
                "required": ["role"],
                "properties": {
                  "role": { "type": "string" },
                  "permissions": {
                    "type": "array",
                    "items": { "type": "string" }
                  }
                }
              }
            ]
          }
        }
      },
      "paths": {
        "/admin/me": {
          "get": {
            "operationId": "getAdminUser",
            "responses": {
              "200": {
                "description": "OK",
                "content": {
                  "application/json": {
                    "schema": { "$ref": "#/components/schemas/AdminUser" }
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

  #expect(output.contains("public struct AdminUser: Codable, Sendable"))
  #expect(output.contains("public let id: String"))
  #expect(output.contains("public let name: String?"))
  #expect(output.contains("public let createdAt: Date?"))
  #expect(output.contains("public let permissions: [String]?"))
  #expect(output.contains("public let role: String"))
  #expect(output.contains("role: String"))
  #expect(output.contains("permissions: [String]? = nil"))
  #expect(output.contains("public typealias Response = AdminUser"))
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

@Test func openAPIGeneratorRejectsDuplicateGeneratedTypeNames() throws {
  #expect(throws: OpenAPIGeneratorError.self) {
    _ = try OpenAPIGenerator().generate(
      jsonString: """
      {
        "openapi": "3.1.0",
        "paths": {
          "/pets": {
            "get": {
              "operationId": "listPets",
              "responses": {
                "204": { "description": "No Content" }
              }
            }
          },
          "/animals": {
            "get": {
              "operationId": "listPets",
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

@Test func openAPIGeneratorRejectsDuplicateComponentModelNames() throws {
  #expect(throws: OpenAPIGeneratorError.self) {
    _ = try OpenAPIGenerator().generate(
      jsonString: """
      {
        "openapi": "3.1.0",
        "components": {
          "schemas": {
            "pet-status": { "type": "string" },
            "pet_status": { "type": "string" }
          }
        },
        "paths": {
          "/pets": {
            "get": {
              "operationId": "listPets",
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

@Test func openAPIGeneratorRejectsUnsupportedAdditionalPropertiesShapes() throws {
  #expect(throws: OpenAPIGeneratorError.self) {
    _ = try OpenAPIGenerator().generate(
      jsonString: """
      {
        "openapi": "3.1.0",
        "components": {
          "schemas": {
            "FreeForm": {
              "type": "object",
              "additionalProperties": true
            }
          }
        },
        "paths": {
          "/free-form": {
            "get": {
              "operationId": "getFreeForm",
              "responses": {
                "200": {
                  "description": "OK",
                  "content": {
                    "application/json": {
                      "schema": { "$ref": "#/components/schemas/FreeForm" }
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
  }

  #expect(throws: OpenAPIGeneratorError.self) {
    _ = try OpenAPIGenerator().generate(
      jsonString: """
      {
        "openapi": "3.1.0",
        "components": {
          "schemas": {
            "Mixed": {
              "type": "object",
              "properties": {
                "id": { "type": "string" }
              },
              "additionalProperties": { "type": "string" }
            }
          }
        },
        "paths": {
          "/mixed": {
            "get": {
              "operationId": "getMixed",
              "responses": {
                "200": {
                  "description": "OK",
                  "content": {
                    "application/json": {
                      "schema": { "$ref": "#/components/schemas/Mixed" }
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
  }
}

@Test func openAPIGeneratorRejectsDuplicateSwiftParameterNames() throws {
  #expect(throws: OpenAPIGeneratorError.self) {
    _ = try OpenAPIGenerator().generate(
      jsonString: """
      {
        "openapi": "3.1.0",
        "paths": {
          "/search": {
            "get": {
              "operationId": "search",
              "parameters": [
                {
                  "name": "user-id",
                  "in": "query",
                  "schema": { "type": "string" }
                },
                {
                  "name": "user_id",
                  "in": "query",
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

@Test func openAPIGeneratorRejectsInvalidHeaderNames() throws {
  #expect(throws: OpenAPIGeneratorError.self) {
    _ = try OpenAPIGenerator().generate(
      jsonString: """
      {
        "openapi": "3.1.0",
        "paths": {
          "/search": {
            "get": {
              "operationId": "search",
              "parameters": [
                {
                  "name": "Bad Header",
                  "in": "header",
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

@Test func openAPIGeneratorEscapesKeywordsAndPrefixesDigitIdentifiers() throws {
  let output = try OpenAPIGenerator().generate(
    jsonString: """
    {
      "openapi": "3.1.0",
      "paths": {
        "/tokens/{self}": {
          "get": {
            "operationId": "3dSecure",
            "parameters": [
              {
                "name": "self",
                "in": "path",
                "required": true,
                "schema": { "type": "string" }
              },
              {
                "name": "123-sort",
                "in": "query",
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

  #expect(output.contains("public struct Generated3DSecureRequest: APIRequest"))
  #expect(output.contains("public let selfValue: String"))
  #expect(output.contains("public let value123Sort: String?"))
  #expect(output.contains(#""tokens" / self.selfValue"#))
}
