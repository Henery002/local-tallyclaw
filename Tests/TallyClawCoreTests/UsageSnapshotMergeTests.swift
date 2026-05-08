import Foundation
import Testing
import TallyClawCore

@Suite("Usage snapshot merge")
struct UsageSnapshotMergeTests {
  @Test("combines token windows and request counters across sources")
  func combinesTokenWindowsAndRequestCountersAcrossSources() {
    let first = UsageSnapshot.preview
    let second = UsageSnapshot(
      today: UsagePeriodStats(
        tokens: TokenBreakdown(input: 100, output: 50, cache: 25, thinking: 5),
        requests: RequestStats(total: 2, succeeded: 1, failed: 1, averageLatencyMilliseconds: 500)
      ),
      week: UsagePeriodStats(
        tokens: TokenBreakdown(input: 200, output: 70),
        requests: RequestStats(total: 3, succeeded: 2, failed: 1, averageLatencyMilliseconds: 700)
      ),
      month: UsagePeriodStats(
        tokens: TokenBreakdown(input: 300, output: 80),
        requests: RequestStats(total: 4, succeeded: 4, failed: 0, averageLatencyMilliseconds: 900)
      ),
      lifetime: UsagePeriodStats(
        tokens: TokenBreakdown(input: 400, output: 90),
        requests: RequestStats(total: 5, succeeded: 5, failed: 0, averageLatencyMilliseconds: 1_100)
      ),
      topSources: [SourceShare(name: "gateway", percent: 100)],
      syncHealth: .syncing,
      observedAt: Date(timeIntervalSince1970: 1_700_000_100)
    )

    let merged = UsageSnapshot.merged([first, second])

    #expect(merged.today.tokens.input == 1_020_100)
    #expect(merged.today.tokens.output == 260_050)
    #expect(merged.today.tokens.cache == 25)
    #expect(merged.today.tokens.thinking == 5)
    #expect(merged.today.requests.total == 582)
    #expect(merged.today.requests.succeeded == 569)
    #expect(merged.today.requests.failed == 13)
    #expect(merged.today.requests.averageLatencyMilliseconds == 1_347)
    #expect(merged.observedAt == max(first.observedAt, second.observedAt))
  }

  @Test("marks merged successful snapshots idle unless a source reports warning")
  func marksSuccessfulMergedSnapshotsIdle() {
    let first = makeSnapshot(health: .idle)
    let second = makeSnapshot(health: .idle)

    let merged = UsageSnapshot.merged([first, second])

    #expect(merged.syncHealth == .idle)
  }

  @Test("keeps warning when any merged source reports warning")
  func keepsWarningWhenAnySourceWarns() {
    let first = makeSnapshot(health: .idle)
    let second = makeSnapshot(health: .warning)

    let merged = UsageSnapshot.merged([first, second])

    #expect(merged.syncHealth == .warning)
  }
}

private func makeSnapshot(health: SyncHealth) -> UsageSnapshot {
  UsageSnapshot(
    today: .empty,
    week: .empty,
    month: .empty,
    lifetime: .empty,
    topSources: [],
    syncHealth: health,
    observedAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
}
