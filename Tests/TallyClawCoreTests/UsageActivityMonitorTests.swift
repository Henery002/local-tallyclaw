import Foundation
import Testing
import TallyClawCore

@Suite("Usage activity monitor")
struct UsageActivityMonitorTests {
  @Test("starts idle even when existing lifetime usage is nonzero")
  func startsIdleForExistingUsage() {
    var monitor = UsageActivityMonitor(activityDuration: 8, cooldownExtension: 8)
    let now = Date(timeIntervalSince1970: 100)

    let state = monitor.ingest(snapshot(tokens: 1_000, health: .syncing), at: now)

    #expect(state == .idle)
    #expect(monitor.state(for: snapshot(tokens: 1_000, health: .syncing), at: now.addingTimeInterval(1)) == .idle)
  }

  @Test("becomes active on usage increase and remains active during activity duration")
  func becomesActiveOnlyForIncreases() {
    var monitor = UsageActivityMonitor(activityDuration: 8, cooldownExtension: 8)
    let now = Date(timeIntervalSince1970: 100)

    _ = monitor.ingest(snapshot(tokens: 1_000), at: now)
    let active = monitor.ingest(snapshot(tokens: 1_250), at: now.addingTimeInterval(5))

    #expect(active == .active)
    // Still active within the 8s base window
    #expect(monitor.state(for: snapshot(tokens: 1_250), at: now.addingTimeInterval(10)) == .active)
    // Returns idle after the full duration expires (8 + 8 * 1/3 = 10.6s). 5 + 10.6 = 15.6s
    #expect(monitor.state(for: snapshot(tokens: 1_250), at: now.addingTimeInterval(16)) == .idle)
  }

  @Test("sustained activity extends the active window progressively")
  func sustainedActivityExtendsWindow() {
    var monitor = UsageActivityMonitor(activityDuration: 8, cooldownExtension: 8)
    let now = Date(timeIntervalSince1970: 100)

    _ = monitor.ingest(snapshot(tokens: 1_000), at: now)
    // Three consecutive increases to reach full cooldown extension
    _ = monitor.ingest(snapshot(tokens: 1_100), at: now.addingTimeInterval(5))
    _ = monitor.ingest(snapshot(tokens: 1_200), at: now.addingTimeInterval(10))
    _ = monitor.ingest(snapshot(tokens: 1_300), at: now.addingTimeInterval(15))

    // At t+15, activeUntil should be t+15 + 8 + 8 = t+31
    #expect(monitor.state(for: snapshot(tokens: 1_300), at: now.addingTimeInterval(30)) == .active)
    #expect(monitor.state(for: snapshot(tokens: 1_300), at: now.addingTimeInterval(32)) == .idle)
  }

  @Test("warning health overrides activity")
  func warningOverridesActivity() {
    var monitor = UsageActivityMonitor(activityDuration: 8, cooldownExtension: 8)
    let now = Date(timeIntervalSince1970: 100)

    _ = monitor.ingest(snapshot(tokens: 1_000), at: now)
    let state = monitor.ingest(snapshot(tokens: 1_200, health: .warning), at: now.addingTimeInterval(5))

    #expect(state == .warning)
    #expect(monitor.state(for: snapshot(tokens: 1_200, health: .warning), at: now.addingTimeInterval(10)) == .warning)
  }

  @Test("no flickering during short pauses within active session")
  func noFlickeringDuringShortPauses() {
    var monitor = UsageActivityMonitor(activityDuration: 8, cooldownExtension: 8)
    let now = Date(timeIntervalSince1970: 100)

    _ = monitor.ingest(snapshot(tokens: 1_000), at: now)
    _ = monitor.ingest(snapshot(tokens: 1_100), at: now.addingTimeInterval(5))
    _ = monitor.ingest(snapshot(tokens: 1_200), at: now.addingTimeInterval(10))
    // Simulate a 12-second pause
    let stateAfterPause = monitor.state(
      for: snapshot(tokens: 1_200),
      at: now.addingTimeInterval(22)
    )
    #expect(stateAfterPause == .active)
  }

  @Test("stays idle when only request count increases")
  func staysIdleWhenOnlyRequestCountIncreases() {
    var monitor = UsageActivityMonitor(activityDuration: 8, cooldownExtension: 8)
    let now = Date(timeIntervalSince1970: 100)

    _ = monitor.ingest(snapshot(tokens: 1_000, requests: 10), at: now)
    let state = monitor.ingest(snapshot(tokens: 1_000, requests: 11), at: now.addingTimeInterval(5))

    #expect(state == .idle)
  }

  @Test("classifies recent token increases into visual intensity levels")
  func classifiesRecentTokenIncreasesIntoVisualIntensityLevels() {
    var monitor = UsageActivityMonitor(activityDuration: 8, cooldownExtension: 8)
    let now = Date(timeIntervalSince1970: 100)

    _ = monitor.ingest(snapshot(tokens: 1_000), at: now)
    #expect(monitor.intensity(for: snapshot(tokens: 1_000), at: now.addingTimeInterval(1)) == .none)

    _ = monitor.ingest(snapshot(tokens: 2_000), at: now.addingTimeInterval(2))
    #expect(monitor.intensity(for: snapshot(tokens: 2_000), at: now.addingTimeInterval(3)) == .low)

    _ = monitor.ingest(snapshot(tokens: 52_000), at: now.addingTimeInterval(4))
    #expect(monitor.intensity(for: snapshot(tokens: 52_000), at: now.addingTimeInterval(5)) == .medium)

    _ = monitor.ingest(snapshot(tokens: 252_000), at: now.addingTimeInterval(6))
    #expect(monitor.intensity(for: snapshot(tokens: 252_000), at: now.addingTimeInterval(7)) == .high)
  }

  @Test("visual intensity expires with the active window")
  func visualIntensityExpiresWithActiveWindow() {
    var monitor = UsageActivityMonitor(activityDuration: 8, cooldownExtension: 0)
    let now = Date(timeIntervalSince1970: 100)

    _ = monitor.ingest(snapshot(tokens: 1_000), at: now)
    _ = monitor.ingest(snapshot(tokens: 201_000), at: now.addingTimeInterval(1))

    #expect(monitor.intensity(for: snapshot(tokens: 201_000), at: now.addingTimeInterval(2)) == .high)
    #expect(monitor.intensity(for: snapshot(tokens: 201_000), at: now.addingTimeInterval(10)) == .none)
  }

  @Test("remembers cockpit as the active source while recent usage is active")
  func remembersCockpitActiveSource() {
    var monitor = UsageActivityMonitor(activityDuration: 8, cooldownExtension: 0)
    let now = Date(timeIntervalSince1970: 100)

    _ = monitor.ingest(snapshot(tokens: 1_000, topSource: "cockpit-codex-stats"), at: now)
    _ = monitor.ingest(snapshot(tokens: 2_000, topSource: "cockpit-codex-stats"), at: now.addingTimeInterval(1))

    #expect(
      monitor.activeSource(for: snapshot(tokens: 2_000, topSource: "cockpit-codex-stats"), at: now.addingTimeInterval(2)) == .cockpit
    )
    #expect(
      monitor.activeSource(for: snapshot(tokens: 2_000, topSource: "cockpit-codex-stats"), at: now.addingTimeInterval(10)) == .none
    )
  }
}

private func snapshot(
  tokens: Int64,
  requests: Int? = nil,
  health: SyncHealth = .syncing,
  topSource: String? = nil
) -> UsageSnapshot {
  let requestCount = requests ?? Int(tokens / 100)
  let stats = UsagePeriodStats(
    tokens: TokenBreakdown(input: tokens, output: 0),
    requests: RequestStats(total: requestCount, succeeded: requestCount, failed: 0)
  )

  return UsageSnapshot(
    today: stats,
    week: stats,
    month: stats,
    lifetime: stats,
    topSources: topSource.map { [SourceShare(name: $0, percent: 100)] } ?? [],
    syncHealth: health,
    observedAt: Date(timeIntervalSince1970: 100)
  )
}
