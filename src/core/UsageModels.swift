import Foundation

public struct TokenBreakdown: Equatable, Sendable {
  public var input: Int64
  public var output: Int64
  public var cache: Int64
  public var thinking: Int64

  public init(input: Int64, output: Int64, cache: Int64 = 0, thinking: Int64 = 0) {
    self.input = input
    self.output = output
    self.cache = cache
    self.thinking = thinking
  }

  public var total: Int64 {
    input + output + thinking
  }
}

public struct RequestStats: Equatable, Sendable {
  public var total: Int
  public var succeeded: Int
  public var failed: Int
  public var averageLatencyMilliseconds: Int

  public init(
    total: Int,
    succeeded: Int,
    failed: Int,
    averageLatencyMilliseconds: Int = 0
  ) {
    self.total = total
    self.succeeded = succeeded
    self.failed = failed
    self.averageLatencyMilliseconds = averageLatencyMilliseconds
  }

  public var successRatePercent: Int {
    guard total > 0 else { return 0 }
    return Int((Double(succeeded) / Double(total) * 100).rounded())
  }

  public var averageLatencyText: String {
    guard averageLatencyMilliseconds > 0 else { return "--" }
    let seconds = Double(averageLatencyMilliseconds) / 1_000
    return String(format: "%.1fs", seconds)
  }
}

public struct UsagePeriodStats: Equatable, Sendable {
  public var tokens: TokenBreakdown
  public var requests: RequestStats

  public init(tokens: TokenBreakdown, requests: RequestStats) {
    self.tokens = tokens
    self.requests = requests
  }
}

public struct SourceShare: Identifiable, Equatable, Sendable {
  public var id: String { name }
  public var name: String
  public var percent: Int

  public init(name: String, percent: Int) {
    self.name = name
    self.percent = percent
  }
}

public enum SyncHealth: String, Equatable, Sendable {
  case idle
  case syncing
  case warning
}

public struct UsageSnapshot: Equatable, Sendable {
  public var today: UsagePeriodStats
  public var week: UsagePeriodStats
  public var month: UsagePeriodStats
  public var lifetime: UsagePeriodStats
  public var topSources: [SourceShare]
  public var syncHealth: SyncHealth
  public var observedAt: Date
  public var sourceStatuses: [SourceReadStatus]

  public init(
    today: UsagePeriodStats,
    week: UsagePeriodStats,
    month: UsagePeriodStats,
    lifetime: UsagePeriodStats,
    topSources: [SourceShare],
    syncHealth: SyncHealth,
    observedAt: Date
  ) {
    self.init(
      today: today,
      week: week,
      month: month,
      lifetime: lifetime,
      topSources: topSources,
      syncHealth: syncHealth,
      observedAt: observedAt,
      sourceStatuses: []
    )
  }

  public init(
    today: UsagePeriodStats,
    week: UsagePeriodStats,
    month: UsagePeriodStats,
    lifetime: UsagePeriodStats,
    topSources: [SourceShare],
    syncHealth: SyncHealth,
    observedAt: Date,
    sourceStatuses: [SourceReadStatus]
  ) {
    self.today = today
    self.week = week
    self.month = month
    self.lifetime = lifetime
    self.topSources = topSources
    self.syncHealth = syncHealth
    self.observedAt = observedAt
    self.sourceStatuses = sourceStatuses
  }

  public static let preview = UsageSnapshot(
    today: UsagePeriodStats(
      tokens: TokenBreakdown(input: 1_020_000, output: 260_000),
      requests: RequestStats(total: 580, succeeded: 568, failed: 12, averageLatencyMilliseconds: 1_350)
    ),
    week: UsagePeriodStats(
      tokens: TokenBreakdown(input: 6_840_000, output: 1_420_000, cache: 380_000),
      requests: RequestStats(total: 3_200, succeeded: 3_136, failed: 64, averageLatencyMilliseconds: 1_410)
    ),
    month: UsagePeriodStats(
      tokens: TokenBreakdown(input: 24_100_000, output: 6_300_000, cache: 1_900_000, thinking: 880_000),
      requests: RequestStats(total: 12_450, succeeded: 12_026, failed: 424, averageLatencyMilliseconds: 1_620)
    ),
    lifetime: UsagePeriodStats(
      tokens: TokenBreakdown(input: 211_000_000, output: 58_500_000, cache: 19_400_000, thinking: 4_800_000),
      requests: RequestStats(total: 88_210, succeeded: 85_732, failed: 2_478, averageLatencyMilliseconds: 1_780)
    ),
    topSources: [
      SourceShare(name: "cockpit", percent: 52),
      SourceShare(name: "gateway", percent: 41)
    ],
    syncHealth: .idle,
    observedAt: Date(timeIntervalSince1970: 1_778_227_200)
  )
}

public extension Int64 {
  var formattedCompact: String {
    let absolute = Swift.abs(self)
    let sign = self < 0 ? "-" : ""

    switch absolute {
    case 1_000_000_000...:
      return sign + Self.format(Double(absolute) / 1_000_000_000, suffix: "B")
    case 1_000_000...:
      return sign + Self.format(Double(absolute) / 1_000_000, suffix: "M")
    case 1_000...:
      return sign + Self.format(Double(absolute) / 1_000, suffix: "K")
    default:
      return "\(self)"
    }
  }

  private static func format(_ value: Double, suffix: String) -> String {
    let formatted = String(format: "%.2f", value)
      .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    return formatted + suffix
  }
}
