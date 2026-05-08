import Foundation
import TallyClawCore

public struct CockpitCodexStatsDataSource: UsageDataSource {
  public let id = "cockpit-codex-stats"
  public let displayName = "cockpit tools"
  public let accessPolicy = SourceAccessPolicy.default

  private let statsURL: URL

  public init(
    statsURL: URL = URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent(".antigravity_cockpit/codex_local_access_stats.json")
  ) {
    self.statsURL = statsURL
  }

  public func readSnapshot() async throws -> UsageSnapshot? {
    guard FileManager.default.fileExists(atPath: statsURL.path) else {
      return nil
    }

    let data = try Data(contentsOf: statsURL, options: [.mappedIfSafe])
    let file = try JSONDecoder().decode(CockpitStatsFile.self, from: data)
    let observedAt = Date(timeIntervalSince1970: Double(file.updatedAt ?? file.since ?? 0) / 1_000)

    return UsageSnapshot(
      today: file.daily?.totals.periodStats ?? .empty,
      week: file.weekly?.totals.periodStats ?? .empty,
      month: file.monthly?.totals.periodStats ?? .empty,
      lifetime: file.totals.periodStats,
      topSources: file.daily?.totals.requestCount ?? 0 > 0 ? [SourceShare(name: "cockpit", percent: 100)] : [],
      syncHealth: .syncing,
      observedAt: observedAt
    )
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
