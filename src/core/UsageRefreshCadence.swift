import Foundation

public struct UsageRefreshCadence: Equatable, Sendable {
  private var previousUsageScore: Int64?
  private var idleReadCount = 0

  public init() {}

  public mutating func record(snapshot: UsageSnapshot, readFailed: Bool) -> TimeInterval {
    let usageScore = snapshot.lifetime.tokens.total + Int64(snapshot.lifetime.requests.total)

    defer {
      previousUsageScore = usageScore
    }

    if readFailed {
      idleReadCount = 0
      return 10
    }

    guard previousUsageScore == usageScore else {
      idleReadCount = 0
      return 5
    }

    idleReadCount += 1
    if idleReadCount >= 7 {
      return 30
    }
    if idleReadCount >= 3 {
      return 15
    }
    return 5
  }
}
