import Foundation
import Testing
import TallyClawCore
import TallyClawLedger

@Suite("SQLite ledger store")
struct SQLiteLedgerStoreTests {
  @Test("deduplicates repeated source snapshots while aggregating different sources")
  func deduplicatesRepeatedSnapshotsWhileAggregatingSources() async throws {
    let url = temporaryDatabaseURL()
    let store = try SQLiteLedgerStore(databaseURL: url, now: { referenceDate })

    try await store.record(snapshot(input: 100, output: 20, requests: 4), sourceID: "gateway")
    try await store.record(snapshot(input: 100, output: 20, requests: 4), sourceID: "gateway")
    try await store.record(snapshot(input: 30, output: 10, requests: 2), sourceID: "cockpit")

    let latest = await store.latestSnapshot()

    #expect(latest.today.tokens.input == 130)
    #expect(latest.today.tokens.output == 30)
    #expect(latest.today.requests.total == 6)
    #expect(latest.lifetime.tokens.total == 160)
    #expect(latest.topSources.map { $0.name }.contains("gateway"))
    #expect(latest.topSources.map { $0.name }.contains("cockpit"))
    #expect(latest.syncHealth == .idle)
  }

  @Test("keeps permanent lifetime totals when a later source snapshot resets lower")
  func keepsPermanentLifetimeTotalsWhenSourceSnapshotResetsLower() async throws {
    let url = temporaryDatabaseURL()
    let store = try SQLiteLedgerStore(databaseURL: url, now: { referenceDate })

    try await store.record(snapshot(input: 1_000, output: 400, requests: 12), sourceID: "gateway")
    try await store.record(snapshot(input: 10, output: 5, requests: 1), sourceID: "gateway")

    let reopened = try SQLiteLedgerStore(databaseURL: url, now: { referenceDate })
    let latest = await reopened.latestSnapshot()

    #expect(latest.lifetime.tokens.input == 1_000)
    #expect(latest.lifetime.tokens.output == 400)
    #expect(latest.lifetime.requests.total == 12)
  }

  @Test("persists latest source read statuses across reopen")
  func persistsLatestSourceReadStatusesAcrossReopen() async throws {
    let url = temporaryDatabaseURL()
    let store = try SQLiteLedgerStore(databaseURL: url, now: { referenceDate })

    try await store.record(snapshot(input: 100, output: 20, requests: 4), sourceID: "gateway")
    try await store.recordSourceStatuses([
      SourceReadStatus(
        sourceID: "gateway",
        displayName: "local-ai-gateway",
        state: .available,
        lastReadAt: referenceDate,
        lastObservedAt: referenceDate
      ),
      SourceReadStatus(
        sourceID: "cockpit",
        displayName: "cockpit tools",
        state: .missing,
        lastReadAt: referenceDate
      )
    ])

    let reopened = try SQLiteLedgerStore(databaseURL: url, now: { referenceDate })
    let latest = await reopened.latestSnapshot()

    #expect(latest.sourceStatuses.count == 2)
    #expect(latest.sourceStatuses.first(where: { $0.sourceID == "gateway" })?.state == .available)
    #expect(latest.sourceStatuses.first(where: { $0.sourceID == "cockpit" })?.state == .missing)
  }

  @Test("updates current rolling windows downward while preserving lifetime high water")
  func updatesCurrentRollingWindowsDownwardWhilePreservingLifetimeHighWater() async throws {
    let url = temporaryDatabaseURL()
    let store = try SQLiteLedgerStore(databaseURL: url, now: { referenceDate })

    try await store.record(
      snapshot(today: 500, week: 900, month: 1_300, lifetime: 2_000),
      sourceID: "rolling-source"
    )
    try await store.record(
      snapshot(today: 100, week: 300, month: 600, lifetime: 1_500),
      sourceID: "rolling-source"
    )

    let latest = await store.latestSnapshot()

    #expect(latest.today.tokens.total == 100)
    #expect(latest.week.tokens.total == 300)
    #expect(latest.month.tokens.total == 600)
    #expect(latest.lifetime.tokens.total == 2_000)
  }

  @Test("keys current windows by ledger read time instead of source observed time")
  func keysCurrentWindowsByLedgerReadTime() async throws {
    let url = temporaryDatabaseURL()
    let store = try SQLiteLedgerStore(databaseURL: url, now: { referenceDate })
    let olderSourceObservation = referenceDate.addingTimeInterval(-9 * 24 * 60 * 60)

    try await store.record(
      snapshot(today: 0, week: 321, month: 654, lifetime: 987, observedAt: olderSourceObservation),
      sourceID: "openclaw"
    )

    let latest = await store.latestSnapshot()

    #expect(latest.week.tokens.total == 321)
    #expect(latest.month.tokens.total == 654)
  }

  @Test("synthesizes current window deltas when source period is unavailable")
  func synthesizesCurrentWindowDeltasWhenSourcePeriodIsUnavailable() async throws {
    let url = temporaryDatabaseURL()
    let store = try SQLiteLedgerStore(databaseURL: url, now: { referenceDate })

    try await store.record(
      snapshot(today: 0, week: 0, month: 0, lifetime: 1_000),
      sourceID: "cockpit-codex-stats"
    )
    try await store.record(
      snapshot(today: 0, week: 0, month: 0, lifetime: 1_060),
      sourceID: "cockpit-codex-stats"
    )
    try await store.record(
      snapshot(today: 0, week: 0, month: 0, lifetime: 1_060),
      sourceID: "cockpit-codex-stats"
    )

    let latest = await store.latestSnapshot()

    #expect(latest.today.tokens.total == 60)
    #expect(latest.week.tokens.total == 60)
    #expect(latest.month.tokens.total == 60)
  }
}

private let referenceDate = Date(timeIntervalSince1970: 1_778_284_800)

private func temporaryDatabaseURL() -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("tallyclaw-ledger-tests-\(UUID().uuidString)", isDirectory: true)
  try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("ledger.sqlite")
}

private func snapshot(input: Int64, output: Int64, requests: Int) -> UsageSnapshot {
  let tokens = TokenBreakdown(input: input, output: output)
  let stats = UsagePeriodStats(
    tokens: tokens,
    requests: RequestStats(total: requests, succeeded: requests, failed: 0, averageLatencyMilliseconds: 100)
  )

  return UsageSnapshot(
    today: stats,
    week: stats,
    month: stats,
    lifetime: stats,
    topSources: [],
    syncHealth: .syncing,
    observedAt: referenceDate
  )
}

private func snapshot(
  today: Int64,
  week: Int64,
  month: Int64,
  lifetime: Int64,
  observedAt: Date = referenceDate
) -> UsageSnapshot {
  UsageSnapshot(
    today: period(tokens: today),
    week: period(tokens: week),
    month: period(tokens: month),
    lifetime: period(tokens: lifetime),
    topSources: [],
    syncHealth: .syncing,
    observedAt: observedAt
  )
}

private func period(tokens: Int64) -> UsagePeriodStats {
  UsagePeriodStats(
    tokens: TokenBreakdown(input: tokens, output: 0),
    requests: RequestStats(total: Int(tokens / 100), succeeded: Int(tokens / 100), failed: 0)
  )
}
