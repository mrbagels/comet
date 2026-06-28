# ``CometOpenAPIGenerator``

Generate Comet request types from focused JSON or YAML OpenAPI documents.

## Overview

`CometOpenAPIGenerator` accepts JSON directly and uses Yams for YAML input. It
is designed to prove generated Comet clients without hiding unsupported OpenAPI
features.

Use the executable from SwiftPM:

```sh
swift run comet-openapi-generate --input openapi.yaml --output GeneratedAPI.swift
```

Use the command plugin from a package checkout when generated sources should be
written relative to the package root:

```sh
swift package --allow-writing-to-package-directory comet-openapi-generate \
  --input openapi.yaml \
  --output Sources/API/GeneratedAPI.swift
```

Or call the generator core directly:

```swift
let source = try OpenAPIGenerator().generate(data: openAPIData)
```

The generator supports:

- OpenAPI 3.0 and 3.1 JSON or YAML documents
- path, query, and header parameters
- component schema structs, string enums, aliases, arrays, and local schema `$ref`s
- JSON request bodies
- typed JSON success response serializers
- typed error response hooks using `APIRequestWithErrorResponse`
- request metadata populated from `operationId`

Unsupported features fail with ``OpenAPIGeneratorError`` so generated clients do
not silently drift from the source contract.

## Topics

### Generation

- ``OpenAPIGenerator``
- ``OpenAPIGeneratorConfiguration``
- ``OpenAPIGeneratorError``
