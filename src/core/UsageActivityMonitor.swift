import Foundation

public enum UsageActivityState: Equatable, Sendable {
  case idle
  case active
  case warning
}

public struct UsageActivityMonitor: Equatable, Sendable {
  private let activityDuration: TimeInterval
  private var lastLifetimeTokens: Int64?
  private var lastLifetimeRequests: Int?
  private var activeUntil: Date?

  public init(activityDuration: TimeInterval = 6) {
    self.activityDuration = activityDuration
  }

  public mutating func ingest(_ snapshot: UsageSnapshot, at date: Date) -> UsageActivityState {
    let lifetimeTokens = snapshot.lifetime.tokens.total
    let lifetimeRequests = snapshot.lifetime.requests.total
    defer {
      lastLifetimeTokens = lifetimeTokens
      lastLifetimeRequests = lifetimeRequests
    }

    if snapshot.syncHealth == .warning {
      return .warning
    }

    guard let previousTokens = lastLifetimeTokens, let previousRequests = lastLifetimeRequests else {
      return state(for: snapshot, at: date)
    }

    if lifetimeTokens > previousTokens || lifetimeRequests > previousRequests {
      activeUntil = date.addingTimeInterval(activityDuration)
    }

    return state(for: snapshot, at: date)
  }

  public func state(for snapshot: UsageSnapshot, at date: Date) -> UsageActivityState {
    if snapshot.syncHealth == .warning {
      return .warning
    }

    if let activeUntil, date < activeUntil {
      return .active
    }

    return .idle
  }
}
