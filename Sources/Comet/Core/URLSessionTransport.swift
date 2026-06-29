import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HTTPTypes

/// The shipped live transport backed by ``Foundation/URLSession``.
public struct URLSessionTransport: HTTPStreamingTransport, Sendable {
  private let session: URLSession

  /// Creates a live transport backed by a new ``URLSession`` with the provided configuration.
  public init(configuration: URLSessionConfiguration = .default) {
    self.session = URLSession(configuration: configuration)
  }

  /// Creates a live transport backed by an existing ``URLSession``.
  public init(session: URLSession) {
    self.session = session
  }

  /// Sends a prepared request through ``URLSession`` and converts the result to ``RawResponse``.
  public func send(_ request: PreparedRequest) async throws(NetworkError) -> RawResponse {
    do {
      #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
      let (data, response) = try await self.session.data(for: request.urlRequest)
      #else
      let (data, response) = try await self.data(for: request.urlRequest)
      #endif
      guard let response = response as? HTTPURLResponse else {
        throw NetworkError.invalidRequest("Expected an HTTPURLResponse from transport.")
      }
      return RawResponse(
        data: data,
        statusCode: response.statusCode,
        headers: HTTPFields(response.allHeaderFields)
      )
    } catch {
      throw .from(error)
    }
  }

  /// Streams a prepared request through ``URLSession`` and yields response metadata followed by byte chunks.
  public func stream(
    _ request: PreparedRequest,
    chunkSize: Int = 16_384
  ) -> AsyncThrowingStream<HTTPStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
          let (bytes, response) = try await self.session.bytes(for: request.urlRequest)
          guard let response = response as? HTTPURLResponse else {
            throw NetworkError.invalidRequest("Expected an HTTPURLResponse from streaming transport.")
          }

          continuation.yield(
            .response(
              HTTPStreamResponse(
                statusCode: response.statusCode,
                headers: HTTPFields(response.allHeaderFields)
              )
            )
          )

          var chunk = Data()
          chunk.reserveCapacity(max(1, chunkSize))

          for try await byte in bytes {
            chunk.append(byte)
            if chunk.count >= chunkSize {
              continuation.yield(.bytes(chunk))
              chunk.removeAll(keepingCapacity: true)
            }
          }

          if !chunk.isEmpty {
            continuation.yield(.bytes(chunk))
          }
          continuation.yield(.complete)
          continuation.finish()
          #else
          let response = try await self.send(request)
          Self.yieldBufferedStream(
            response,
            chunkSize: chunkSize,
            continuation: continuation
          )
          #endif
        } catch {
          continuation.finish(throwing: NetworkError.from(error))
        }
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  private static func yieldBufferedStream(
    _ response: RawResponse,
    chunkSize: Int,
    continuation: AsyncThrowingStream<HTTPStreamEvent, Error>.Continuation
  ) {
    continuation.yield(
      .response(
        HTTPStreamResponse(
          statusCode: response.statusCode,
          headers: response.headers
        )
      )
    )

    let resolvedChunkSize = max(1, chunkSize)
    var offset = 0
    while offset < response.data.count {
      let end = min(offset + resolvedChunkSize, response.data.count)
      continuation.yield(.bytes(response.data.subdata(in: offset..<end)))
      offset = end
    }

    continuation.yield(.complete)
    continuation.finish()
  }

  #if !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS))
  private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    try await withCheckedThrowingContinuation { continuation in
      let task = self.session.dataTask(with: request) { data, response, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }

        guard let data, let response else {
          continuation.resume(throwing: URLError(.badServerResponse))
          return
        }

        continuation.resume(returning: (data, response))
      }
      task.resume()
    }
  }
  #endif
}
