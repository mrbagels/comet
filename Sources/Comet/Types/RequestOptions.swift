import Foundation

public struct RequestOptions: Sendable {
  public var apiVersion: String?
  public var absoluteURL: URL?
  public var timeout: Duration?
  public var idempotencyKey: String?
  public var deduplicationKey: String?
  public var statusValidation: StatusValidation
  public var middleware: [any Middleware]

  public init(
    apiVersion: String? = nil,
    absoluteURL: URL? = nil,
    timeout: Duration? = nil,
    idempotencyKey: String? = nil,
    deduplicationKey: String? = nil,
    statusValidation: StatusValidation = .successCodes,
    middleware: [any Middleware] = []
  ) {
    self.apiVersion = apiVersion
    self.absoluteURL = absoluteURL
    self.timeout = timeout
    self.idempotencyKey = idempotencyKey
    self.deduplicationKey = deduplicationKey
    self.statusValidation = statusValidation
    self.middleware = middleware
  }
}
