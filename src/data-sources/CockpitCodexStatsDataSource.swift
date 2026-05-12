import Foundation
import TallyClawCore

public struct CockpitCodexStatsDataSource: UsageObservationDataSource {
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

    let file = try readStatsFile()
    let observedAt = Date(timeIntervalSince1970: Double(file.updatedAt ?? file.since ?? 0) / 1_000)
    let currentTime = now()

    // Cockpit uses rolling time windows (e.g. "daily" = last 24h from updatedAt),
    // NOT calendar-aligned windows. We must validate each window's `since`
    // timestamp against the calendar boundary TallyClaw expects, and discard
    // windows whose `since` falls before the expected boundary.
    let todayStart = calendar.startOfDay(for: currentTime)
    let statsUpdatedAt = file.updatedAt.map(Self.dateFromMilliseconds) ?? observedAt
    let weeklyUpdatedAt = file.weekly?.updatedAt.map(Self.dateFromMilliseconds) ?? statsUpdatedAt
    let monthlyUpdatedAt = file.monthly?.updatedAt.map(Self.dateFromMilliseconds) ?? statsUpdatedAt
    let trailing7DaysStart = weeklyUpdatedAt.addingTimeInterval(-7 * 24 * 60 * 60)
    let trailing30DaysStart = monthlyUpdatedAt.addingTimeInterval(-30 * 24 * 60 * 60)

    let todayStats = validatedPeriodStats(
      window: file.daily,
      expectedStart: todayStart,
      windowLabel: "daily",
      tolerance: 0
    )
    let weekStats = validatedPeriodStats(
      window: file.weekly,
      expectedStart: trailing7DaysStart,
      windowLabel: "weekly",
      tolerance: 60
    )
    let monthStats = validatedPeriodStats(
      window: file.monthly,
      expectedStart: trailing30DaysStart,
      windowLabel: "monthly",
      tolerance: 60
    )

    return UsageSnapshot(
      today: todayStats,
      week: weekStats,
      month: monthStats,
      lifetime: file.totals.periodStats,
      topSources: todayStats.requests.total > 0 ? [SourceShare(name: "cockpit", percent: 100)] : [],
      syncHealth: .idle,
      observedAt: observedAt,
      lifetimeStartedAt: file.since.map(Self.dateFromMilliseconds) ?? UsageSnapshot.unknownLifetimeStartDate,
      lifetimeStartedAtLabel: "cockpit"
    )
  }

  public func readObservations(since startDate: Date?) async throws -> [UsageObservation] {
    guard FileManager.default.fileExists(atPath: statsURL.path) else {
      return []
    }

    let file = try readStatsFile()
    let observedAt = Date(timeIntervalSince1970: Double(file.updatedAt ?? file.since ?? 0) / 1_000)
    if let startDate, observedAt < startDate {
      return []
    }

    return [
      UsageObservation(
        sourceID: id,
        sourceEventID: "\(id):\(file.updatedAt ?? file.since ?? 0):totals",
        sourceName: "cockpit",
        provider: "cockpit",
        model: "codex",
        observedAt: observedAt,
        tokens: file.totals.periodStats.tokens,
        requests: file.totals.periodStats.requests,
        confidence: "snapshot"
      )
    ]
  }

  private func readStatsFile() throws -> CockpitStatsFile {
    let data = try Data(contentsOf: statsURL, options: [.mappedIfSafe])
    do {
      return try JSONDecoder().decode(CockpitStatsFile.self, from: data)
    } catch let error as DecodingError {
      throw CockpitCodexStatsDataSourceError.schemaMismatch(
        message: "Cockpit schema mismatch: \(Self.decodingSummary(error))"
      )
    }
  }

  /// Return the window's stats only if the window's `since` timestamp falls
  /// on or after `expectedStart`. Otherwise the cockpit window spans a
  /// longer period than TallyClaw's calendar boundary – return `.empty` so
  /// the ledger doesn't record inflated data under a wrong period key.
  private func validatedPeriodStats(
    window: CockpitUsageWindow?,
    expectedStart: Date,
    windowLabel: String,
    tolerance: TimeInterval
  ) -> UsagePeriodStats {
    guard let window else { return .empty }
    guard let since = window.since else {
      // No since timestamp – trust cautiously.
      return window.totals.periodStats
    }
    let windowStart = Date(timeIntervalSince1970: Double(since) / 1_000)
    if windowStart.addingTimeInterval(tolerance) >= expectedStart {
      return window.totals.periodStats
    }
    // The cockpit window started before our expected boundary, meaning its
    // totals include data from outside the calendar period. Return empty
    // rather than recording inflated numbers.
    return .empty
  }

  private static func dateFromMilliseconds(_ milliseconds: Int64) -> Date {
    Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
  }

  private static func decodingSummary(_ error: DecodingError) -> String {
    switch error {
    case .keyNotFound(let key, let context):
      let path = (context.codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: ".")
      return "missing required field \(path)"
    case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
      let path = context.codingPath.map(\.stringValue).joined(separator: ".")
      return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
    @unknown default:
      return String(describing: error)
    }
  }
}

public enum CockpitCodexStatsDataSourceError: Error, Equatable {
  case schemaMismatch(message: String)
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
