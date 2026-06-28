import Foundation
import HTTPTypes

/// A credential that can authenticate a prepared request.
public struct AuthenticationCredential: Sendable {
  public let headerName: HTTPField.Name
  public let headerValue: String

  /// Creates a credential that writes a concrete HTTP header.
  public init(
    headerName: HTTPField.Name,
    headerValue: String
  ) {
    self.headerName = headerName
    self.headerValue = headerValue
  }

  /// Creates a bearer-token credential for the `Authorization` header.
  public static func bearer(_ token: String) -> Self {
    Self(headerName: .authorization, headerValue: "Bearer \(token)")
  }

  func apply(to request: PreparedRequest) -> PreparedRequest {
    var headers = request.headers
    headers[self.headerName] = self.headerValue
    return PreparedRequest(
      url: request.url,
      method: request.method,
      headers: headers,
      body: request.body,
      timeout: request.timeout,
      metadata: request.metadata,
      redactionPolicy: request.redactionPolicy,
      retryPolicy: request.retryPolicy
    )
  }
}

/// Coordinates authentication credential reads and refresh de-duplication.
public actor AuthenticationCoordinator {
  private let credentialProvider: @Sendable () async throws -> AuthenticationCredential?
  private let refreshProvider: @Sendable () async throws -> AuthenticationCredential?
  private var refreshTask: Task<AuthenticationCredential?, any Error>?

  /// Creates a coordinator from credential and refresh providers.
  public init(
    credential: @escaping @Sendable () async throws -> AuthenticationCredential?,
    refresh: @escaping @Sendable () async throws -> AuthenticationCredential?
  ) {
    self.credentialProvider = credential
    self.refreshProvider = refresh
  }

  /// Creates a bearer-token coordinator from token and refresh providers.
  public static func bearer(
    token: @escaping @Sendable () async throws -> String?,
    refresh: @escaping @Sendable () async throws -> String?
  ) -> Self {
    Self(
      credential: {
        try await token().map(AuthenticationCredential.bearer)
      },
      refresh: {
        try await refresh().map(AuthenticationCredential.bearer)
      }
    )
  }

  /// Reads the current credential without refreshing it.
  public func credential() async throws -> AuthenticationCredential? {
    try await self.credentialProvider()
  }

  /// Refreshes the credential, coalescing concurrent refresh callers onto one in-flight refresh.
  public func refreshCredential() async throws -> AuthenticationCredential? {
    if let refreshTask {
      return try await refreshTask.value
    }

    let refreshProvider = self.refreshProvider
    let task = Task {
      try await refreshProvider()
    }
    self.refreshTask = task

    do {
      let credential = try await task.value
      self.refreshTask = nil
      return credential
    } catch {
      self.refreshTask = nil
      throw error
    }
  }
}

/// Adds authentication headers and can refresh credentials once after authentication challenges.
public struct AuthenticationMiddleware: Middleware {
  private let coordinator: AuthenticationCoordinator
  private let challengeStatusCodes: Set<Int>
  private let replayPolicy: RequestRetryPolicy
  private let replayTracker = AuthenticationReplayTracker()

  /// Creates authentication middleware backed by an ``AuthenticationCoordinator``.
  public init(
    coordinator: AuthenticationCoordinator,
    challengeStatusCodes: Set<Int> = [401],
    replayPolicy: RequestRetryPolicy = .automatic
  ) {
    self.coordinator = coordinator
    self.challengeStatusCodes = challengeStatusCodes
    self.replayPolicy = replayPolicy
  }

  /// Adds the current credential to outgoing requests when one is available.
  public func prepare(
    _ request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> PreparedRequest {
    do {
      guard let credential = try await self.coordinator.credential() else { return request }
      return credential.apply(to: request)
    } catch {
      throw .from(error)
    }
  }

  /// Refreshes the credential and replays the request after configured authentication challenges.
  public func process(
    result: Result<RawResponse, NetworkError>,
    request: PreparedRequest,
    context: MiddlewareContext
  ) async throws(NetworkError) -> MiddlewareResult {
    guard case .success(let response) = result else {
      await self.replayTracker.finish(for: context.requestID)
      return .proceed(result)
    }
    guard self.challengeStatusCodes.contains(response.statusCode) else {
      await self.replayTracker.finish(for: context.requestID)
      return .proceed(result)
    }
    guard (request.retryPolicy ?? self.replayPolicy).allowsRetry(for: request) else {
      await self.replayTracker.finish(for: context.requestID)
      return .proceed(result)
    }
    guard await self.replayTracker.markReplayNeeded(for: context.requestID) else {
      return .proceed(result)
    }

    do {
      guard let credential = try await self.coordinator.refreshCredential() else {
        await self.replayTracker.finish(for: context.requestID)
        return .proceed(result)
      }
      return .retry(credential.apply(to: request), after: .zero)
    } catch {
      await self.replayTracker.finish(for: context.requestID)
      throw .from(error)
    }
  }
}

private actor AuthenticationReplayTracker {
  private var replayedRequestIDs: Set<UUID> = []

  func markReplayNeeded(for requestID: UUID) -> Bool {
    self.replayedRequestIDs.insert(requestID).inserted
  }

  func finish(for requestID: UUID) {
    self.replayedRequestIDs.remove(requestID)
  }
}
