import Foundation
import HTTPTypes

public enum JSONCodingPreset: Sendable {
  case standard
  case snakeCaseISO8601
}

public struct ClientConfiguration: Sendable {
  public var baseURL: URL
  public var defaultHeaders: HTTPFields
  public var timeout: Duration
  public var middleware: [any Middleware]

  public var makeJSONEncoder: @Sendable () -> JSONEncoder
  public var makeJSONDecoder: @Sendable () -> JSONDecoder
  public var now: @Sendable () -> ContinuousClock.Instant
  public var sleep: @Sendable (Duration) async throws -> Void
  public var makeRequestID: @Sendable () -> UUID
  public var randomDouble: @Sendable (ClosedRange<Double>) -> Double

  public init(
    baseURL: URL,
    defaultHeaders: HTTPFields = .init(),
    timeout: Duration = .seconds(30),
    middleware: [any Middleware] = [],
    makeJSONEncoder: @escaping @Sendable () -> JSONEncoder = Self.defaultJSONEncoder,
    makeJSONDecoder: @escaping @Sendable () -> JSONDecoder = Self.defaultJSONDecoder,
    now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock().now },
    sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
      try await Task.sleep(for: duration)
    },
    makeRequestID: @escaping @Sendable () -> UUID = UUID.init,
    randomDouble: @escaping @Sendable (ClosedRange<Double>) -> Double = { Double.random(in: $0) }
  ) {
    self.baseURL = baseURL
    self.defaultHeaders = defaultHeaders
    self.timeout = timeout
    self.middleware = middleware
    self.makeJSONEncoder = makeJSONEncoder
    self.makeJSONDecoder = makeJSONDecoder
    self.now = now
    self.sleep = sleep
    self.makeRequestID = makeRequestID
    self.randomDouble = randomDouble
  }

  public static func `default`(
    baseURL: URL,
    jsonPreset: JSONCodingPreset = .standard
  ) -> Self {
    Self(
      baseURL: baseURL,
      makeJSONEncoder: { Self.jsonEncoder(preset: jsonPreset) },
      makeJSONDecoder: { Self.jsonDecoder(preset: jsonPreset) }
    )
  }

  public static func defaultJSONEncoder() -> JSONEncoder {
    Self.jsonEncoder()
  }

  public static func defaultJSONDecoder() -> JSONDecoder {
    Self.jsonDecoder()
  }

  public static func snakeCaseJSONEncoder() -> JSONEncoder {
    Self.jsonEncoder(preset: .snakeCaseISO8601)
  }

  public static func snakeCaseJSONDecoder() -> JSONDecoder {
    Self.jsonDecoder(preset: .snakeCaseISO8601)
  }

  public static func jsonEncoder(
    preset: JSONCodingPreset = .standard
  ) -> JSONEncoder {
    let encoder = JSONEncoder()
    switch preset {
    case .standard:
      break
    case .snakeCaseISO8601:
      encoder.keyEncodingStrategy = .convertToSnakeCase
      encoder.dateEncodingStrategy = .iso8601
    }
    return encoder
  }

  public static func jsonDecoder(
    preset: JSONCodingPreset = .standard
  ) -> JSONDecoder {
    let decoder = JSONDecoder()
    switch preset {
    case .standard:
      break
    case .snakeCaseISO8601:
      decoder.keyDecodingStrategy = .convertFromSnakeCase
      decoder.dateDecodingStrategy = .iso8601
    }
    return decoder
  }
}
