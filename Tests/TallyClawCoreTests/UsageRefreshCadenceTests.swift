import Foundation
import Testing
import TallyClawCore

@Suite("Usage refresh cadence")
struct UsageRefreshCadenceTests {
  @Test("starts with quick polling while usage is changing")
  func startsWithQuickPollingWhileUsageIsChanging() {
    var cadence = UsageRefreshCadence()

    let firstDelay = cadence.record(snapshot: snapshot(total: 100), readFailed: false)
    let changedDelay = cadence.record(snapshot: snapshot(total: 120), readFailed: false)

    #expect(firstDelay == 5)
    #expect(changedDelay == 5)
  }

  @Test("backs off after repeated idle reads and resets on usage growth")
  func backsOffAfterRepeatedIdleReadsAndResetsOnUsageGrowth() {
    var cadence = UsageRefreshCadence()
    _ = cadence.record(snapshot: snapshot(total: 100), readFailed: false)

    var delay: TimeInterval = 0
    for _ in 0..<3 {
      delay = cadence.record(snapshot: snapshot(total: 100), readFailed: false)
    }
    #expect(delay == 15)

    for _ in 0..<4 {
      delay = cadence.record(snapshot: snapshot(total: 100), readFailed: false)
    }
    #expect(delay == 30)

    delay = cadence.record(snapshot: snapshot(total: 130), readFailed: false)
    #expect(delay == 5)
  }

  @Test("uses moderate polling after read failures")
  func usesModeratePollingAfterReadFailures() {
    var cadence = UsageRefreshCadence()

    let delay = cadence.record(snapshot: snapshot(total: 100), readFailed: true)

    #expect(delay == 10)
  }
}

private func snapshot(total: Int64) -> UsageSnapshot {
  UsageSnapshot(
    today: stats(total: total),
    week: stats(total: total),
    month: stats(total: total),
    lifetime: stats(total: total),
    topSources: [],
    syncHealth: .idle,
    observedAt: Date(timeIntervalSince1970: Double(total))
  )
}

private func stats(total: Int64) -> UsagePeriodStats {
  UsagePeriodStats(
    tokens: TokenBreakdown(input: total, output: 0),
    requests: RequestStats(total: Int(total / 10), succeeded: Int(total / 10), failed: 0)
  )
}
