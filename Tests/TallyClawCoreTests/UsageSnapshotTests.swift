import Foundation
import Testing
import TallyClawCore

@Suite("Usage snapshot display")
struct UsageSnapshotTests {
  @Test("formats token totals for compact pet UI")
  func formatsTokenTotalsForCompactPetUI() {
    let snapshot = UsageSnapshot.preview

    #expect(snapshot.today.tokens.total.formattedCompact == "1.28M")
    #expect(snapshot.week.tokens.total.formattedCompact == "8.26M")
  }

  @Test("reports success rate as a rounded percentage")
  func reportsSuccessRateAsRoundedPercentage() {
    let stats = RequestStats(total: 3_200, succeeded: 3_136, failed: 64)

    #expect(stats.successRatePercent == 98)
  }

  @Test("summarizes request details for the success strip")
  func summarizesRequestDetailsForSuccessStrip() {
    let stats = RequestStats(total: 3_200, succeeded: 3_136, failed: 64, averageLatencyMilliseconds: 1_410)

    #expect(stats.successSummaryText == "3.2k req · 64 fail · 1.4s")
  }

  @Test("keeps read only source policy explicit")
  func keepsReadOnlySourcePolicyExplicit() {
    #expect(SourceAccessPolicy.default.mode == .readOnly)
    #expect(SourceAccessPolicy.default.allowsCredentialRefresh == false)
    #expect(SourceAccessPolicy.default.allowsSourceMutation == false)
  }

  @Test("summarizes today usage against seven day average and top source")
  func summarizesTodayUsageAgainstSevenDayAverageAndTopSource() {
    let snapshot = UsageSnapshot(
      today: stats(tokens: 30_000, requests: 30),
      week: stats(tokens: 70_000, requests: 70),
      month: stats(tokens: 120_000, requests: 120),
      lifetime: stats(tokens: 300_000, requests: 300),
      topSources: [SourceShare(name: "cockpit-codex-stats", percent: 82)],
      syncHealth: .idle,
      observedAt: Date(timeIntervalSince1970: 100)
    )

    #expect(snapshot.todayDigest.title == "今日 30K tokens")
    #expect(snapshot.todayDigest.detail == "约为 7 日均值 3x · 主要来源 cockpit 82%")
  }

  @Test("summarizes quiet days without source data")
  func summarizesQuietDaysWithoutSourceData() {
    let snapshot = UsageSnapshot(
      today: stats(tokens: 0, requests: 0),
      week: stats(tokens: 0, requests: 0),
      month: stats(tokens: 0, requests: 0),
      lifetime: stats(tokens: 0, requests: 0),
      topSources: [],
      syncHealth: .idle,
      observedAt: Date(timeIntervalSince1970: 100)
    )

    #expect(snapshot.todayDigest.title == "今日 0 tokens")
    #expect(snapshot.todayDigest.detail == "暂无 7 日均值 · 主要来源 暂无")
  }

  @Test("explains exact event facets when cockpit is the leading snapshot source")
  func explainsExactEventFacetsWhenCockpitIsLeadingSnapshotSource() {
    let snapshot = UsageSnapshot(
      today: stats(tokens: 30_000, requests: 30),
      week: stats(tokens: 70_000, requests: 70),
      month: stats(tokens: 120_000, requests: 120),
      lifetime: stats(tokens: 300_000, requests: 300),
      topSources: [SourceShare(name: "cockpit-codex-stats", percent: 92)],
      syncHealth: .idle,
      observedAt: Date(timeIntervalSince1970: 100),
      sourceStatuses: [],
      observationFacets: UsageObservationFacets(
        providerLeaders: [UsageObservationFacet(name: "openai-codex", count: 3, tokens: 6_000)]
      )
    )

    #expect(snapshot.traceExplanation == "近 7 天 exact 事件；cockpit 为聚合快照，暂不进入逐请求榜单")
  }

  @Test("omits trace explanation when exact facets match a non cockpit leading source")
  func omitsTraceExplanationForNonCockpitLeader() {
    let snapshot = UsageSnapshot(
      today: stats(tokens: 30_000, requests: 30),
      week: stats(tokens: 70_000, requests: 70),
      month: stats(tokens: 120_000, requests: 120),
      lifetime: stats(tokens: 300_000, requests: 300),
      topSources: [SourceShare(name: "openclaw", percent: 92)],
      syncHealth: .idle,
      observedAt: Date(timeIntervalSince1970: 100),
      sourceStatuses: [],
      observationFacets: UsageObservationFacets(
        providerLeaders: [UsageObservationFacet(name: "openai-codex", count: 3, tokens: 6_000)]
      )
    )

    #expect(snapshot.traceExplanation == nil)
  }

  @Test("explains display window semantics")
  func explainsDisplayWindowSemantics() {
    #expect(UsageSnapshot.windowSemanticsText == "今日=本地自然日 · 7/30天=滚动窗口 · 总计=长期累计")
  }

  @Test("explains lifetime persistence scope")
  func explainsLifetimePersistenceScope() {
    let start = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 12, hour: 12))!
    let snapshot = UsageSnapshot(
      today: stats(tokens: 30_000, requests: 30),
      week: stats(tokens: 70_000, requests: 70),
      month: stats(tokens: 120_000, requests: 120),
      lifetime: stats(tokens: 300_000, requests: 300),
      topSources: [],
      syncHealth: .idle,
      observedAt: start,
      lifetimeStartedAt: start,
      lifetimeStartedAtLabel: "cockpit"
    )

    #expect(snapshot.lifetimeScopeText == "总计含已读到的上游历史累计；cockpit 起点约 2026-05-12；ledger 持久化防回退")
  }

  @Test("explains lifetime scope when upstream start is unavailable")
  func explainsLifetimeScopeWhenUpstreamStartIsUnavailable() {
    let snapshot = UsageSnapshot(
      today: stats(tokens: 30_000, requests: 30),
      week: stats(tokens: 70_000, requests: 70),
      month: stats(tokens: 120_000, requests: 120),
      lifetime: stats(tokens: 300_000, requests: 300),
      topSources: [],
      syncHealth: .idle,
      observedAt: Date(timeIntervalSince1970: 100)
    )

    #expect(snapshot.lifetimeScopeText == "总计含已读到的上游历史累计；未读到上游起点；ledger 持久化防回退")
  }
}

private func stats(tokens: Int64, requests: Int) -> UsagePeriodStats {
  UsagePeriodStats(
    tokens: TokenBreakdown(input: tokens, output: 0),
    requests: RequestStats(total: requests, succeeded: requests, failed: 0)
  )
}
