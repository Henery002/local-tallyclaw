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

    let lifetimeStart = preferredLifetimeStart(snapshots)

    return UsageSnapshot(
      today: UsagePeriodStats.merged(snapshots.map(\.today)),
      week: UsagePeriodStats.merged(snapshots.map(\.week)),
      month: UsagePeriodStats.merged(snapshots.map(\.month)),
      lifetime: UsagePeriodStats.merged(snapshots.map(\.lifetime)),
      topSources: mergeSourceShares(snapshots.flatMap(\.topSources)),
      syncHealth: snapshots.contains { $0.syncHealth == .warning } ? .warning : .idle,
      observedAt: snapshots.map(\.observedAt).max() ?? first.observedAt,
      lifetimeStartedAt: lifetimeStart?.date ?? UsageSnapshot.unknownLifetimeStartDate,
      lifetimeStartedAtLabel: lifetimeStart?.label,
      sourceStatuses: snapshots.flatMap(\.sourceStatuses),
      hourlyTokenTrend: mergeHourlyTrend(snapshots.map(\.hourlyTokenTrend))
    )
  }

  private static func preferredLifetimeStart(_ snapshots: [UsageSnapshot]) -> (date: Date, label: String?)? {
    let validSnapshots = snapshots.filter { $0.lifetimeStartedAt > UsageSnapshot.unknownLifetimeStartDate }
    if let cockpit = validSnapshots
      .filter({ $0.lifetimeStartedAtLabel == "cockpit" })
      .min(by: { $0.lifetimeStartedAt < $1.lifetimeStartedAt }) {
      return (cockpit.lifetimeStartedAt, cockpit.lifetimeStartedAtLabel)
    }

    return validSnapshots
      .min(by: { $0.lifetimeStartedAt < $1.lifetimeStartedAt })
      .map { ($0.lifetimeStartedAt, $0.lifetimeStartedAtLabel) }
  }

  private static func mergeSourceShares(_ shares: [SourceShare]) -> [SourceShare] {
    let names = Array(Set(shares.map(\.name))).sorted()
    guard !names.isEmpty else { return [] }
    let percent = max(1, 100 / names.count)
    return names.prefix(3).map { SourceShare(name: $0, percent: percent) }
  }

  private static func mergeHourlyTrend(_ trends: [[HourlyTokenUsage]]) -> [HourlyTokenUsage] {
    let flattened = trends.flatMap { $0 }
    let keys = Array(Set(flattened.map(\.bucketKey))).sorted()
    return keys.map { key in
      let matching = flattened.filter { $0.bucketKey == key }
      return HourlyTokenUsage(
        bucketKey: key,
        label: matching.first?.label ?? key,
        tokens: matching.reduce(Int64(0)) { $0 + $1.tokens }
      )
    }
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
