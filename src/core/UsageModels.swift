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

  public var successSummaryText: String {
    "\(total.formattedCompact.lowercased()) req · \(failed.formattedCompact.lowercased()) fail · \(averageLatencyText)"
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

public struct UsageObservation: Equatable, Sendable {
  public var sourceID: String
  public var sourceEventID: String
  public var sourceName: String
  public var provider: String
  public var model: String
  public var observedAt: Date
  public var tokens: TokenBreakdown
  public var requests: RequestStats
  public var confidence: String

  public init(
    sourceID: String,
    sourceEventID: String,
    sourceName: String,
    provider: String,
    model: String,
    observedAt: Date,
    tokens: TokenBreakdown,
    requests: RequestStats,
    confidence: String = "exact"
  ) {
    self.sourceID = sourceID
    self.sourceEventID = sourceEventID
    self.sourceName = sourceName
    self.provider = provider
    self.model = model
    self.observedAt = observedAt
    self.tokens = tokens
    self.requests = requests
    self.confidence = confidence
  }
}

public struct UsageObservationFacet: Equatable, Sendable {
  public var name: String
  public var count: Int
  public var tokens: Int64

  public init(name: String, count: Int, tokens: Int64) {
    self.name = name
    self.count = count
    self.tokens = tokens
  }
}

public struct UsageObservationFacets: Equatable, Sendable {
  public var providerLeaders: [UsageObservationFacet]
  public var modelLeaders: [UsageObservationFacet]
  public var sourceNameLeaders: [UsageObservationFacet]

  public init(
    providerLeaders: [UsageObservationFacet] = [],
    modelLeaders: [UsageObservationFacet] = [],
    sourceNameLeaders: [UsageObservationFacet] = []
  ) {
    self.providerLeaders = providerLeaders
    self.modelLeaders = modelLeaders
    self.sourceNameLeaders = sourceNameLeaders
  }

  public static let empty = UsageObservationFacets()

  public var hasLeaders: Bool {
    !providerLeaders.isEmpty || !modelLeaders.isEmpty || !sourceNameLeaders.isEmpty
  }
}

public struct DailyTokenUsage: Identifiable, Equatable, Sendable {
  public var id: String { dayKey }
  public var dayKey: String
  public var label: String
  public var tokens: Int64

  public init(dayKey: String, label: String, tokens: Int64) {
    self.dayKey = dayKey
    self.label = label
    self.tokens = tokens
  }
}

public struct HourlyTokenUsage: Identifiable, Equatable, Sendable {
  public var id: String { bucketKey }
  public var bucketKey: String
  public var label: String
  public var tokens: Int64

  public init(bucketKey: String, label: String, tokens: Int64) {
    self.bucketKey = bucketKey
    self.label = label
    self.tokens = tokens
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
  public var lifetimeStartedAt: Date
  public var lifetimeStartedAtLabel: String?
  public var topSources: [SourceShare]
  public var syncHealth: SyncHealth
  public var observedAt: Date
  public var sourceStatuses: [SourceReadStatus]
  public var observationFacets: UsageObservationFacets
  public var dailyTokenTrend: [DailyTokenUsage]
  public var hourlyTokenTrend: [HourlyTokenUsage]

  public init(
    today: UsagePeriodStats,
    week: UsagePeriodStats,
    month: UsagePeriodStats,
    lifetime: UsagePeriodStats,
    topSources: [SourceShare],
    syncHealth: SyncHealth,
    observedAt: Date,
    lifetimeStartedAt: Date = UsageSnapshot.unknownLifetimeStartDate,
    lifetimeStartedAtLabel: String? = nil
  ) {
    self.init(
      today: today,
      week: week,
      month: month,
      lifetime: lifetime,
      topSources: topSources,
      syncHealth: syncHealth,
      observedAt: observedAt,
      lifetimeStartedAt: lifetimeStartedAt,
      lifetimeStartedAtLabel: lifetimeStartedAtLabel,
      sourceStatuses: [],
      observationFacets: .empty,
      dailyTokenTrend: [],
      hourlyTokenTrend: []
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
    lifetimeStartedAt: Date = UsageSnapshot.unknownLifetimeStartDate,
    lifetimeStartedAtLabel: String? = nil,
    sourceStatuses: [SourceReadStatus],
    observationFacets: UsageObservationFacets = .empty,
    dailyTokenTrend: [DailyTokenUsage] = [],
    hourlyTokenTrend: [HourlyTokenUsage] = []
  ) {
    self.today = today
    self.week = week
    self.month = month
    self.lifetime = lifetime
    self.lifetimeStartedAt = lifetimeStartedAt
    self.lifetimeStartedAtLabel = lifetimeStartedAtLabel
    self.topSources = topSources
    self.syncHealth = syncHealth
    self.observedAt = observedAt
    self.sourceStatuses = sourceStatuses
    self.observationFacets = observationFacets
    self.dailyTokenTrend = dailyTokenTrend
    self.hourlyTokenTrend = hourlyTokenTrend
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
    observedAt: Date(timeIntervalSince1970: 1_778_227_200),
    lifetimeStartedAt: Date(timeIntervalSince1970: 1_777_622_400),
    sourceStatuses: [],
    observationFacets: .empty,
    dailyTokenTrend: [
      DailyTokenUsage(dayKey: "2026-05-05", label: "5/5", tokens: 920_000),
      DailyTokenUsage(dayKey: "2026-05-06", label: "5/6", tokens: 1_120_000),
      DailyTokenUsage(dayKey: "2026-05-07", label: "5/7", tokens: 860_000),
      DailyTokenUsage(dayKey: "2026-05-08", label: "5/8", tokens: 1_430_000),
      DailyTokenUsage(dayKey: "2026-05-09", label: "5/9", tokens: 1_080_000),
      DailyTokenUsage(dayKey: "2026-05-10", label: "5/10", tokens: 1_240_000),
      DailyTokenUsage(dayKey: "2026-05-11", label: "5/11", tokens: 1_280_000)
    ],
    hourlyTokenTrend: [
      HourlyTokenUsage(bucketKey: "2026-05-11-18-30", label: "18:30", tokens: 10_000),
      HourlyTokenUsage(bucketKey: "2026-05-11-19-00", label: "19:00", tokens: 18_000),
      HourlyTokenUsage(bucketKey: "2026-05-11-19-30", label: "19:30", tokens: 44_000),
      HourlyTokenUsage(bucketKey: "2026-05-11-20-00", label: "20:00", tokens: 62_000),
      HourlyTokenUsage(bucketKey: "2026-05-11-20-30", label: "20:30", tokens: 36_000),
      HourlyTokenUsage(bucketKey: "2026-05-11-21-00", label: "21:00", tokens: 44_000),
      HourlyTokenUsage(bucketKey: "2026-05-11-21-30", label: "21:30", tokens: 78_000),
      HourlyTokenUsage(bucketKey: "2026-05-11-22-00", label: "22:00", tokens: 132_000),
      HourlyTokenUsage(bucketKey: "2026-05-11-22-30", label: "22:30", tokens: 104_000),
      HourlyTokenUsage(bucketKey: "2026-05-11-23-00", label: "23:00", tokens: 96_000),
      HourlyTokenUsage(bucketKey: "2026-05-11-23-30", label: "23:30", tokens: 48_000),
      HourlyTokenUsage(bucketKey: "2026-05-12-00-00", label: "00:00", tokens: 78_000)
    ]
  )
}

public struct UsageDailyDigest: Equatable, Sendable {
  public var title: String
  public var detail: String

  public init(title: String, detail: String) {
    self.title = title
    self.detail = detail
  }
}

public extension UsageSnapshot {
  static let windowSemanticsText = "今日=本地自然日 · 7/30天=滚动窗口 · 总计=长期累计"
  static let unknownLifetimeStartDate = Date(timeIntervalSince1970: 0)

  var lifetimeScopeText: String {
    if lifetimeStartedAt > Self.unknownLifetimeStartDate {
      let startLabel = lifetimeStartedAtLabel.map { "\($0) 起点" } ?? "上游起点"
      return "总计含已读到的上游历史累计；\(startLabel)约 \(Self.dayStamp(for: lifetimeStartedAt))；ledger 持久化防回退"
    }
    return "总计含已读到的上游历史累计；未读到上游起点；ledger 持久化防回退"
  }

  var todayDigest: UsageDailyDigest {
    let todayTokens = today.tokens.total
    let weeklyAverage = week.tokens.total / 7
    let comparison: String

    if weeklyAverage <= 0 {
      comparison = "暂无 7 日均值"
    } else {
      let ratio = Double(todayTokens) / Double(weeklyAverage)
      if ratio >= 1.05 {
        comparison = "约为 7 日均值 \(Self.formatRatio(ratio))"
      } else if ratio <= 0.95 {
        comparison = "约为 7 日均值 \(Int((ratio * 100).rounded()))%"
      } else {
        comparison = "接近 7 日均值"
      }
    }

    let source = topSources.first.map { "\(Self.digestSourceName($0.name)) \($0.percent)%" } ?? "暂无"
    return UsageDailyDigest(
      title: "今日 \(todayTokens.formattedCompact) tokens",
      detail: "\(comparison) · 主要来源 \(source)"
    )
  }

  var traceExplanation: String? {
    guard observationFacets.hasLeaders else { return nil }
    guard let leadingSource = topSources.first?.name else { return nil }
    guard Self.digestSourceName(leadingSource) == "cockpit" else { return nil }
    return "近 7 天 exact 事件；cockpit 为聚合快照，暂不进入逐请求榜单"
  }

  private static func formatRatio(_ ratio: Double) -> String {
    let formatted = String(format: "%.1f", ratio)
      .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    return "\(formatted)x"
  }

  private static func digestSourceName(_ name: String) -> String {
    switch name {
    case "cockpit-codex-stats":
      return "cockpit"
    case "local-ai-gateway":
      return "gateway"
    default:
      return name
    }
  }

  private static func dayStamp(for date: Date) -> String {
    let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(
      format: "%04d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0
    )
  }
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

public extension Int {
  var formattedCompact: String {
    Int64(self).formattedCompact
  }
}
