import Foundation

public enum UsageActivityState: Equatable, Sendable {
  case idle
  case active
  case warning
}

public struct UsageActivityMonitor: Equatable, Sendable {
  /// How long the pet remains in 'active' state after the last detected
  /// token / request increase. Must be substantially longer than the
  /// polling interval to avoid flickering during natural pauses in model
  /// interaction (tool calls, file writes, context reads).
  private let activityDuration: TimeInterval

  /// Extra cooldown added to the first transition away from active. This
  /// prevents a brief "idle flash" when the generation pipeline pauses
  /// momentarily (e.g. between streaming chunks or during tool execution).
  private let cooldownExtension: TimeInterval

  private var lastLifetimeTokens: Int64?
  private var lastLifetimeRequests: Int?
  private var activeUntil: Date?

  /// Number of consecutive polls that showed increasing usage. Used to
  /// scale the active window: sustained activity earns a longer tail so
  /// short mid-generation pauses don't trigger a visible state change.
  private var consecutiveIncreases: Int = 0

  public init(activityDuration: TimeInterval = 8, cooldownExtension: TimeInterval = 8) {
    self.activityDuration = activityDuration
    self.cooldownExtension = cooldownExtension
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
      consecutiveIncreases += 1
      // Sustained activity earns progressively longer tail, capped at 2×.
      let scaledDuration = activityDuration + cooldownExtension * min(Double(consecutiveIncreases) / 3.0, 1.0)
      let proposedDeadline = date.addingTimeInterval(scaledDuration)
      // Never shrink the existing deadline – only extend it.
      if let existing = activeUntil {
        activeUntil = max(existing, proposedDeadline)
      } else {
        activeUntil = proposedDeadline
      }
    } else {
      consecutiveIncreases = 0
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
