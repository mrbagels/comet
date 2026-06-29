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
- path, query, and header parameters, including reusable component parameters
- component schema structs, nested inline object structs, typed and free-form `additionalProperties` dictionaries, simple `allOf` object composition, `oneOf` and `anyOf` union enums, discriminator decoding for component unions, string enums, aliases, arrays, and local schema `$ref`s
- reusable request bodies and JSON, plain-text, form URL-encoded, and multipart form-data request bodies
- reusable responses and typed JSON or string success response serializers
- typed JSON, string, or raw data error response hooks using `APIRequestWithErrorResponse`
- request metadata populated from `operationId` and OpenAPI security requirements

Unsupported features fail with ``OpenAPIGeneratorError`` so generated clients do
not silently drift from the source contract.

## Topics

### Generation

- ``OpenAPIGenerator``
- ``OpenAPIGeneratorConfiguration``
- ``OpenAPIGeneratorError``
