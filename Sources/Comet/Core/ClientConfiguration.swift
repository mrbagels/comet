import Foundation
import HTTPTypes

/// Selects the built-in JSON encoder and decoder presets used by ``ClientConfiguration``.
public enum JSONCodingPreset: Sendable {
  case standard
  case snakeCaseISO8601
}

/// Holds the shared behavior for a family of requests executed by an ``HTTPClient``.
public struct ClientConfiguration: Sendable {
  public var baseURL: URL
  public var defaultHeaders: HTTPFields
  public var timeout: Duration
  public var middleware: [any Middleware]
  public var activityBufferingPolicy: EventBroadcaster<NetworkEvent>.BufferingPolicy

  public var makeJSONEncoder: @Sendable () -> JSONEncoder
  public var makeJSONDecoder: @Sendable () -> JSONDecoder
  public var now: @Sendable () -> ContinuousClock.Instant
  public var sleep: @Sendable (Duration) async throws -> Void
  public var makeRequestID: @Sendable () -> UUID
  public var randomDouble: @Sendable (ClosedRange<Double>) -> Double

  /// Creates a client configuration with injectable defaults for headers, middleware, time, and randomness.
  public init(
    baseURL: URL,
    defaultHeaders: HTTPFields = .init(),
    timeout: Duration = .seconds(30),
    middleware: [any Middleware] = [],
    activityBufferingPolicy: EventBroadcaster<NetworkEvent>.BufferingPolicy = .bufferingNewest(100),
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
    self.activityBufferingPolicy = activityBufferingPolicy
    self.makeJSONEncoder = makeJSONEncoder
    self.makeJSONDecoder = makeJSONDecoder
    self.now = now
    self.sleep = sleep
    self.makeRequestID = makeRequestID
    self.randomDouble = randomDouble
  }

  /// Creates an app-friendly configuration using Comet's standard JSON defaults.
  public static func `default`(
    baseURL: URL,
    jsonPreset: JSONCodingPreset = .standard
  ) -> Self {
    Self(
      baseURL: baseURL,
      activityBufferingPolicy: .bufferingNewest(100),
      makeJSONEncoder: { Self.jsonEncoder(preset: jsonPreset) },
      makeJSONDecoder: { Self.jsonDecoder(preset: jsonPreset) }
    )
  }

  /// Returns the standard JSON encoder used by Comet.
  public static func defaultJSONEncoder() -> JSONEncoder {
    Self.jsonEncoder()
  }

  /// Returns the standard JSON decoder used by Comet.
  public static func defaultJSONDecoder() -> JSONDecoder {
    Self.jsonDecoder()
  }

  /// Returns the snake_case plus ISO-8601 encoder preset used by Comet.
  public static func snakeCaseJSONEncoder() -> JSONEncoder {
    Self.jsonEncoder(preset: .snakeCaseISO8601)
  }

  /// Returns the snake_case plus ISO-8601 decoder preset used by Comet.
  public static func snakeCaseJSONDecoder() -> JSONDecoder {
    Self.jsonDecoder(preset: .snakeCaseISO8601)
  }

  /// Builds a JSON encoder for the requested preset.
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

  /// Builds a JSON decoder for the requested preset.
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
