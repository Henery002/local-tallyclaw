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
