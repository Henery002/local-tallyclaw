import Foundation
import TallyClawCore

public struct CockpitCodexStatsDataSource: UsageDataSource {
  public let id = "cockpit-codex-stats"
  public let displayName = "cockpit tools"
  public let accessPolicy = SourceAccessPolicy.default

  private let statsURL: URL
  private let now: @Sendable () -> Date
  private let calendar: Calendar

  public init(
    statsURL: URL = URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent(".antigravity_cockpit/codex_local_access_stats.json"),
    calendar: Calendar = .current,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.statsURL = statsURL
    self.calendar = calendar
    self.now = now
  }

  public func readSnapshot() async throws -> UsageSnapshot? {
    guard FileManager.default.fileExists(atPath: statsURL.path) else {
      return nil
    }

    let data = try Data(contentsOf: statsURL, options: [.mappedIfSafe])
    let file = try JSONDecoder().decode(CockpitStatsFile.self, from: data)
    let observedAt = Date(timeIntervalSince1970: Double(file.updatedAt ?? file.since ?? 0) / 1_000)
    let currentTime = now()

    // Cockpit uses rolling time windows (e.g. "daily" = last 24h from updatedAt),
    // NOT calendar-aligned windows. We must validate each window's `since`
    // timestamp against the calendar boundary TallyClaw expects, and discard
    // windows whose `since` falls before the expected boundary.
    let todayStart = calendar.startOfDay(for: currentTime)
    let trailing7DaysStart = currentTime.addingTimeInterval(-7 * 24 * 60 * 60)
    let trailing30DaysStart = currentTime.addingTimeInterval(-30 * 24 * 60 * 60)

    let todayStats = validatedPeriodStats(
      window: file.daily,
      expectedStart: todayStart,
      windowLabel: "daily"
    )
    let weekStats = validatedPeriodStats(
      window: file.weekly,
      expectedStart: trailing7DaysStart,
      windowLabel: "weekly"
    )
    let monthStats = validatedPeriodStats(
      window: file.monthly,
      expectedStart: trailing30DaysStart,
      windowLabel: "monthly"
    )

    return UsageSnapshot(
      today: todayStats,
      week: weekStats,
      month: monthStats,
      lifetime: file.totals.periodStats,
      topSources: todayStats.requests.total > 0 ? [SourceShare(name: "cockpit", percent: 100)] : [],
      syncHealth: .idle,
      observedAt: observedAt
    )
  }

  /// Return the window's stats only if the window's `since` timestamp falls
  /// on or after `expectedStart`. Otherwise the cockpit window spans a
  /// longer period than TallyClaw's calendar boundary – return `.empty` so
  /// the ledger doesn't record inflated data under a wrong period key.
  private func validatedPeriodStats(
    window: CockpitUsageWindow?,
    expectedStart: Date,
    windowLabel: String
  ) -> UsagePeriodStats {
    guard let window else { return .empty }
    guard let since = window.since else {
      // No since timestamp – trust cautiously.
      return window.totals.periodStats
    }
    let windowStart = Date(timeIntervalSince1970: Double(since) / 1_000)
    if windowStart >= expectedStart {
      return window.totals.periodStats
    }
    // The cockpit window started before our expected boundary, meaning its
    // totals include data from outside the calendar period. Return empty
    // rather than recording inflated numbers.
    return .empty
  }
}

private struct CockpitStatsFile: Decodable {
  var since: Int64?
  var updatedAt: Int64?
  var totals: CockpitUsageCounters
  var daily: CockpitUsageWindow?
  var weekly: CockpitUsageWindow?
  var monthly: CockpitUsageWindow?
}

private struct CockpitUsageWindow: Decodable {
  var since: Int64?
  var updatedAt: Int64?
  var totals: CockpitUsageCounters
}

private struct CockpitUsageCounters: Decodable {
  var requestCount: Int
  var successCount: Int
  var failureCount: Int
  var totalLatencyMs: Int
  var inputTokens: Int64
  var outputTokens: Int64
  var totalTokens: Int64
  var cachedTokens: Int64
  var reasoningTokens: Int64

  var periodStats: UsagePeriodStats {
    UsagePeriodStats(
      tokens: TokenBreakdown(
        input: inputTokens,
        output: outputTokens,
        cache: cachedTokens,
        thinking: reasoningTokens
      ),
      requests: RequestStats(
        total: requestCount,
        succeeded: successCount,
        failed: failureCount,
        averageLatencyMilliseconds: requestCount > 0 ? totalLatencyMs / requestCount : 0
      )
    )
  }
}
