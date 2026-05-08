import Foundation

public extension UsageSnapshot {
  static func merged(_ snapshots: [UsageSnapshot]) -> UsageSnapshot {
    guard let first = snapshots.first else {
      return UsageSnapshot(
        today: .empty,
        week: .empty,
        month: .empty,
        lifetime: .empty,
        topSources: [],
        syncHealth: .idle,
        observedAt: Date(timeIntervalSince1970: 0)
      )
    }

    return UsageSnapshot(
      today: UsagePeriodStats.merged(snapshots.map(\.today)),
      week: UsagePeriodStats.merged(snapshots.map(\.week)),
      month: UsagePeriodStats.merged(snapshots.map(\.month)),
      lifetime: UsagePeriodStats.merged(snapshots.map(\.lifetime)),
      topSources: mergeSourceShares(snapshots.flatMap(\.topSources)),
      syncHealth: snapshots.contains { $0.syncHealth == .warning } ? .warning : .idle,
      observedAt: snapshots.map(\.observedAt).max() ?? first.observedAt,
      sourceStatuses: snapshots.flatMap(\.sourceStatuses)
    )
  }

  private static func mergeSourceShares(_ shares: [SourceShare]) -> [SourceShare] {
    let names = Array(Set(shares.map(\.name))).sorted()
    guard !names.isEmpty else { return [] }
    let percent = max(1, 100 / names.count)
    return names.prefix(3).map { SourceShare(name: $0, percent: percent) }
  }
}

public extension UsagePeriodStats {
  static func merged(_ periods: [UsagePeriodStats]) -> UsagePeriodStats {
    UsagePeriodStats(
      tokens: TokenBreakdown(
        input: periods.reduce(Int64(0)) { $0 + $1.tokens.input },
        output: periods.reduce(Int64(0)) { $0 + $1.tokens.output },
        cache: periods.reduce(Int64(0)) { $0 + $1.tokens.cache },
        thinking: periods.reduce(Int64(0)) { $0 + $1.tokens.thinking }
      ),
      requests: RequestStats.merged(periods.map(\.requests))
    )
  }

  static let empty = UsagePeriodStats(
    tokens: TokenBreakdown(input: 0, output: 0),
    requests: RequestStats(total: 0, succeeded: 0, failed: 0)
  )
}

public extension RequestStats {
  static func merged(_ stats: [RequestStats]) -> RequestStats {
    let total = stats.reduce(0) { $0 + $1.total }
    let weightedLatency = stats.reduce(0) { $0 + ($1.total * $1.averageLatencyMilliseconds) }

    return RequestStats(
      total: total,
      succeeded: stats.reduce(0) { $0 + $1.succeeded },
      failed: stats.reduce(0) { $0 + $1.failed },
      averageLatencyMilliseconds: total > 0 ? weightedLatency / total : 0
    )
  }
}
