import Foundation
import HTTPTypes

enum RequestBuilder {
  static func build<R: APIRequest>(
    _ request: R,
    configuration: ClientConfiguration
  ) throws(NetworkError) -> PreparedRequest {
    let body = try request.body.resolved(using: configuration)
    var headers = configuration.defaultHeaders
    headers.merge(body.headers)
    headers.merge(request.headers)

    if let idempotencyKey = request.options.idempotencyKey {
      headers[HTTPField.Name("Idempotency-Key")!] = idempotencyKey
    }

    let url = try resolveURL(for: request, configuration: configuration)
    let timeout = request.options.timeout ?? configuration.timeout

    return PreparedRequest(
      url: url,
      method: request.method,
      headers: headers,
      body: body.data,
      timeout: timeout,
      metadata: request.options.metadata,
      redactionPolicy: request.options.redactionPolicy ?? configuration.redactionPolicy,
      retryPolicy: request.options.retryPolicy
    )
  }

  private static func resolveURL<R: APIRequest>(
    for request: R,
    configuration: ClientConfiguration
  ) throws(NetworkError) -> URL {
    let baseURL = request.options.absoluteURL ?? configuration.baseURL
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw .invalidRequest("Unable to create URL components from base URL.")
    }

    if request.options.absoluteURL == nil {
      var segments = components.percentEncodedPath
        .split(separator: "/")
        .map(String.init)
        .filter { !$0.isEmpty }

      if let apiVersion = request.options.apiVersion, !apiVersion.isEmpty {
        segments.append(Self.percentEncodedPathSegment(apiVersion))
      }

      let requestPath = request.path.rawValue
        .split(separator: "/")
        .map(String.init)
        .filter { !$0.isEmpty }
      segments.append(contentsOf: requestPath)

      components.percentEncodedPath = "/" + segments.joined(separator: "/")
    }

    let queryItems = request.queryItems.map { URLQueryItem(name: $0.name, value: $0.value) }
    if !queryItems.isEmpty {
      var existingItems = components.queryItems ?? []
      existingItems.append(contentsOf: queryItems)
      components.queryItems = existingItems
    }

    guard let url = components.url else {
      throw .invalidRequest("Unable to create a final URL for request \(request.path.rawValue).")
    }
    return url
  }

  private static func percentEncodedPathSegment(_ segment: String) -> String {
    let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
    return segment.addingPercentEncoding(withAllowedCharacters: allowed) ?? segment
  }
}
