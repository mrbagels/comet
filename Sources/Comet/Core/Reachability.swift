import Foundation

/// A coarse reachability hint for UI and retry ergonomics.
public enum ReachabilityStatus: String, Sendable, Hashable {
  case unknown
  case reachable
  case unreachable
}

/// A point-in-time reachability hint.
///
/// Reachability is not a correctness boundary. A reachable snapshot can still
/// fail at transport time, and an unreachable snapshot can become stale quickly.
public struct ReachabilitySnapshot: Sendable, Hashable {
  public var status: ReachabilityStatus
  public var isExpensive: Bool?
  public var isConstrained: Bool?
  public var checkedAt: Date

  public init(
    status: ReachabilityStatus = .unknown,
    isExpensive: Bool? = nil,
    isConstrained: Bool? = nil,
    checkedAt: Date = Date()
  ) {
    self.status = status
    self.isExpensive = isExpensive
    self.isConstrained = isConstrained
    self.checkedAt = checkedAt
  }
}

/// Provides reachability snapshots without coupling Comet to a platform monitor.
public protocol ReachabilityHintProvider: Sendable {
  func currentSnapshot() async -> ReachabilitySnapshot
}

/// A deterministic reachability provider for tests, previews, and app-owned monitors.
public struct StaticReachabilityHintProvider: ReachabilityHintProvider {
  private let snapshot: ReachabilitySnapshot

  public init(_ snapshot: ReachabilitySnapshot = ReachabilitySnapshot()) {
    self.snapshot = snapshot
  }

  public func currentSnapshot() async -> ReachabilitySnapshot {
    self.snapshot
  }
}
