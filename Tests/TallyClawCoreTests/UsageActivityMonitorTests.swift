import Foundation
import Testing
import TallyClawCore

@Suite("Usage activity monitor")
struct UsageActivityMonitorTests {
  @Test("starts idle even when existing lifetime usage is nonzero")
  func startsIdleForExistingUsage() {
    var monitor = UsageActivityMonitor(activityDuration: 5)
    let now = Date(timeIntervalSince1970: 100)

    let state = monitor.ingest(snapshot(tokens: 1_000, health: .syncing), at: now)

    #expect(state == .idle)
    #expect(monitor.state(for: snapshot(tokens: 1_000, health: .syncing), at: now.addingTimeInterval(1)) == .idle)
  }

  @Test("becomes active only when usage increases and then returns idle")
  func becomesActiveOnlyForIncreases() {
    var monitor = UsageActivityMonitor(activityDuration: 5)
    let now = Date(timeIntervalSince1970: 100)

    _ = monitor.ingest(snapshot(tokens: 1_000), at: now)
    let active = monitor.ingest(snapshot(tokens: 1_250), at: now.addingTimeInterval(1))

    #expect(active == .active)
    #expect(monitor.state(for: snapshot(tokens: 1_250), at: now.addingTimeInterval(4)) == .active)
    #expect(monitor.state(for: snapshot(tokens: 1_250), at: now.addingTimeInterval(7)) == .idle)
  }

  @Test("warning health overrides activity")
  func warningOverridesActivity() {
    var monitor = UsageActivityMonitor(activityDuration: 5)
    let now = Date(timeIntervalSince1970: 100)

    _ = monitor.ingest(snapshot(tokens: 1_000), at: now)
    let state = monitor.ingest(snapshot(tokens: 1_200, health: .warning), at: now.addingTimeInterval(1))

    #expect(state == .warning)
    #expect(monitor.state(for: snapshot(tokens: 1_200, health: .warning), at: now.addingTimeInterval(2)) == .warning)
  }
}

private func snapshot(tokens: Int64, health: SyncHealth = .syncing) -> UsageSnapshot {
  let stats = UsagePeriodStats(
    tokens: TokenBreakdown(input: tokens, output: 0),
    requests: RequestStats(total: Int(tokens / 100), succeeded: Int(tokens / 100), failed: 0)
  )

  return UsageSnapshot(
    today: stats,
    week: stats,
    month: stats,
    lifetime: stats,
    topSources: [],
    syncHealth: health,
    observedAt: Date(timeIntervalSince1970: 100)
  )
}
