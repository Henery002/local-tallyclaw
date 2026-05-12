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
    #expect(latest.lifetimeStartedAt == UsageSnapshot.unknownLifetimeStartDate)
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

  @Test("prefers cockpit lifetime start for display across reopen")
  func prefersCockpitLifetimeStartForDisplayAcrossReopen() async throws {
    let url = temporaryDatabaseURL()
    let earliestStart = referenceDate.addingTimeInterval(-30 * 24 * 60 * 60)
    let cockpitStart = referenceDate.addingTimeInterval(-3 * 24 * 60 * 60)
    let store = try SQLiteLedgerStore(databaseURL: url, now: { referenceDate })

    try await store.record(
      snapshot(input: 100, output: 20, requests: 4, lifetimeStartedAt: earliestStart),
      sourceID: "gateway"
    )
    try await store.record(
      snapshot(input: 30, output: 10, requests: 2, lifetimeStartedAt: cockpitStart),
      sourceID: "cockpit-codex-stats"
    )
    try await store.record(
      snapshot(input: 10, output: 5, requests: 1),
      sourceID: "openclaw"
    )

    let reopened = try SQLiteLedgerStore(databaseURL: url, now: { referenceDate })
    let latest = await reopened.latestSnapshot()

    #expect(latest.lifetimeStartedAt == cockpitStart)
    #expect(latest.lifetimeStartedAtLabel == "cockpit")
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
        lastObservedAt: referenceDate,
        readDurationMilliseconds: 42
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
    #expect(latest.sourceStatuses.first(where: { $0.sourceID == "gateway" })?.readDurationMilliseconds == 42)
    #expect(latest.sourceStatuses.first(where: { $0.sourceID == "cockpit" })?.state == .missing)
  }

  @Test("keeps current window high water when a source snapshot resets lower")
  func keepsCurrentWindowHighWaterWhenSourceSnapshotResetsLower() async throws {
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

    #expect(latest.today.tokens.total == 500)
    #expect(latest.week.tokens.total == 900)
    #expect(latest.month.tokens.total == 1_300)
    #expect(latest.lifetime.tokens.total == 2_000)
  }

  @Test("accumulates new usage after a source snapshot counter reset")
  func accumulatesNewUsageAfterSourceSnapshotCounterReset() async throws {
    let url = temporaryDatabaseURL()
    let store = try SQLiteLedgerStore(databaseURL: url, now: { referenceDate })

    try await store.record(
      snapshot(today: 1_000, week: 2_000, month: 3_000, lifetime: 4_000),
      sourceID: "cockpit-codex-stats"
    )
    try await store.record(
      snapshot(today: 100, week: 200, month: 300, lifetime: 400),
      sourceID: "cockpit-codex-stats"
    )

    var latest = await store.latestSnapshot()
    #expect(latest.today.tokens.total == 1_000)
    #expect(latest.week.tokens.total == 2_000)
    #expect(latest.month.tokens.total == 3_000)
    #expect(latest.lifetime.tokens.total == 4_000)
    #expect(latest.week.requests.total == 20)

    try await store.record(
      snapshot(today: 250, week: 450, month: 650, lifetime: 850),
      sourceID: "cockpit-codex-stats"
    )

    latest = await store.latestSnapshot()
    #expect(latest.today.tokens.total == 1_150)
    #expect(latest.week.tokens.total == 2_250)
    #expect(latest.month.tokens.total == 3_350)
    #expect(latest.lifetime.tokens.total == 4_450)
    #expect(latest.week.requests.total == 22)
    #expect(latest.dailyTokenTrend.last?.tokens == 1_150)
  }

  @Test("records recent six hour token trend in half hour buckets")
  func recordsRecentSixHourTokenTrendInHalfHourBuckets() async throws {
    let url = temporaryDatabaseURL()
    let store = try SQLiteLedgerStore(databaseURL: url, now: { referenceDate })
    let shiftedURL = temporaryDatabaseURL()
    let shiftedStore = try SQLiteLedgerStore(
      databaseURL: shiftedURL,
      now: { referenceDate.addingTimeInterval(45 * 60) }
    )

    try await store.record(
      snapshot(today: 1_000, week: 1_000, month: 1_000, lifetime: 4_000),
      sourceID: "cockpit-codex-stats"
    )

    var latest = await store.latestSnapshot()
    #expect(latest.hourlyTokenTrend.count == 12)
    #expect(latest.hourlyTokenTrend.first?.label == "02:30")
    #expect(latest.hourlyTokenTrend.last?.label == "08:00")
    #expect(latest.hourlyTokenTrend.last?.tokens == 0)

    try await store.record(
      snapshot(today: 1_120, week: 1_120, month: 1_120, lifetime: 4_120),
      sourceID: "cockpit-codex-stats"
    )
    try await store.record(
      snapshot(today: 10, week: 10, month: 10, lifetime: 10),
      sourceID: "cockpit-codex-stats"
    )
    try await store.record(
      snapshot(today: 45, week: 45, month: 45, lifetime: 45),
      sourceID: "cockpit-codex-stats"
    )

    latest = await store.latestSnapshot()
    #expect(latest.hourlyTokenTrend.last?.tokens == 155)

    try await shiftedStore.record(
      snapshot(today: 1_000, week: 1_000, month: 1_000, lifetime: 4_000),
      sourceID: "cockpit-codex-stats"
    )
    let shiftedLatest = await shiftedStore.latestSnapshot()
    #expect(shiftedLatest.hourlyTokenTrend.first?.label == "03:00")
    #expect(shiftedLatest.hourlyTokenTrend.last?.label == "08:30")
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

  @Test("records stable snapshot observations without duplicating identical polls")
  func recordsStableSnapshotObservationsWithoutDuplicatingIdenticalPolls() async throws {
    let url = temporaryDatabaseURL()
    let store = try SQLiteLedgerStore(databaseURL: url, now: { referenceDate })

    try await store.record(snapshot(input: 100, output: 20, requests: 4), sourceID: "gateway")
    try await store.record(snapshot(input: 100, output: 20, requests: 4), sourceID: "gateway")
    try await store.record(snapshot(input: 120, output: 25, requests: 5), sourceID: "gateway")
    try await store.record(snapshot(input: 30, output: 10, requests: 2), sourceID: "cockpit")

    let summary = try await store.observationSummary()

    #expect(summary.totalCount == 3)
    #expect(summary.sourceCount == 2)
    #expect(summary.latestObservedAt == referenceDate)
  }

  @Test("records exact observations with provider and model facets without duplicating polls")
  func recordsExactObservationsWithProviderAndModelFacets() async throws {
    let url = temporaryDatabaseURL()
    let store = try SQLiteLedgerStore(databaseURL: url, now: { referenceDate })
    let observedAt = referenceDate.addingTimeInterval(-60)
    let observation = UsageObservation(
      sourceID: "local-ai-gateway",
      sourceEventID: "event-a",
      sourceName: "codex",
      provider: "openai",
      model: "gpt-5",
      observedAt: observedAt,
      tokens: TokenBreakdown(input: 100, output: 50, cache: 10, thinking: 5),
      requests: RequestStats(total: 1, succeeded: 1, failed: 0, averageLatencyMilliseconds: 200)
    )

    try await store.recordObservations([observation, observation])

    let summary = try await store.observationSummary()
    let latestExact = try await store.latestObservationDate(sourceID: "local-ai-gateway", confidence: "exact")

    #expect(summary.totalCount == 1)
    #expect(summary.sourceCount == 1)
    #expect(summary.latestObservedAt == observedAt)
    #expect(summary.providerLeaders == [LedgerObservationFacet(name: "openai", count: 1, tokens: 155)])
    #expect(summary.modelLeaders == [LedgerObservationFacet(name: "gpt-5", count: 1, tokens: 155)])
    #expect(summary.sourceNameLeaders == [LedgerObservationFacet(name: "codex", count: 1, tokens: 155)])
    #expect(latestExact == observedAt)

    let latest = await store.latestSnapshot()
    #expect(latest.observationFacets.providerLeaders == [UsageObservationFacet(name: "openai", count: 1, tokens: 155)])
    #expect(latest.observationFacets.modelLeaders == [UsageObservationFacet(name: "gpt-5", count: 1, tokens: 155)])
  }

  @Test("keeps exact observations when upstream event ids are reused after reset")
  func keepsExactObservationsWhenUpstreamEventIDsAreReusedAfterReset() async throws {
    let url = temporaryDatabaseURL()
    let store = try SQLiteLedgerStore(databaseURL: url, now: { referenceDate })
    let first = UsageObservation(
      sourceID: "local-ai-gateway",
      sourceEventID: "1",
      sourceName: "codex",
      provider: "openai",
      model: "gpt-5",
      observedAt: referenceDate.addingTimeInterval(-120),
      tokens: TokenBreakdown(input: 100, output: 20),
      requests: RequestStats(total: 1, succeeded: 1, failed: 0)
    )
    let reusedID = UsageObservation(
      sourceID: "local-ai-gateway",
      sourceEventID: "1",
      sourceName: "codex",
      provider: "openai",
      model: "gpt-5",
      observedAt: referenceDate.addingTimeInterval(-60),
      tokens: TokenBreakdown(input: 50, output: 10),
      requests: RequestStats(total: 1, succeeded: 1, failed: 0)
    )

    try await store.recordObservations([first, reusedID])

    let summary = try await store.observationSummary()
    #expect(summary.totalCount == 2)
    #expect(summary.providerLeaders == [LedgerObservationFacet(name: "openai", count: 2, tokens: 180)])
  }

  @Test("latest snapshot exposes seven local calendar days and recent exact facets")
  func latestSnapshotExposesSevenLocalCalendarDaysAndRecentExactFacets() async throws {
    let calendar = Calendar(identifier: .gregorian)
    let url = temporaryDatabaseURL()
    let today = referenceDate
    let yesterday = referenceDate.addingTimeInterval(-24 * 60 * 60)
    let oldOpenClawDate = referenceDate.addingTimeInterval(-14 * 24 * 60 * 60)
    let store = try SQLiteLedgerStore(databaseURL: url, calendar: calendar, now: { today })

    try await store.record(snapshot(today: 300, week: 300, month: 300, lifetime: 300), sourceID: "cockpit")

    let yesterdayStore = try SQLiteLedgerStore(databaseURL: url, calendar: calendar, now: { yesterday })
    try await yesterdayStore.record(snapshot(today: 120, week: 120, month: 120, lifetime: 120), sourceID: "cockpit")

    try await store.recordObservations([
      UsageObservation(
        sourceID: "openclaw",
        sourceEventID: "old-openclaw",
        sourceName: "openclaw",
        provider: "old-provider",
        model: "old-model",
        observedAt: oldOpenClawDate,
        tokens: TokenBreakdown(input: 1_000_000, output: 0),
        requests: RequestStats(total: 1, succeeded: 1, failed: 0)
      ),
      UsageObservation(
        sourceID: "local-ai-gateway",
        sourceEventID: "recent-codex",
        sourceName: "codex",
        provider: "recent-provider",
        model: "recent-model",
        observedAt: today.addingTimeInterval(-60),
        tokens: TokenBreakdown(input: 100, output: 20),
        requests: RequestStats(total: 1, succeeded: 1, failed: 0)
      )
    ])

    let latest = await store.latestSnapshot()

    #expect(latest.dailyTokenTrend.count == 7)
    #expect(latest.dailyTokenTrend.suffix(2).map(\.tokens) == [120, 300])
    #expect(latest.observationFacets.providerLeaders == [UsageObservationFacet(name: "recent-provider", count: 1, tokens: 120)])
  }
}

private let referenceDate = Date(timeIntervalSince1970: 1_778_284_800)

private func temporaryDatabaseURL() -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("tallyclaw-ledger-tests-\(UUID().uuidString)", isDirectory: true)
  try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  return directory.appendingPathComponent("ledger.sqlite")
}

private func snapshot(
  input: Int64,
  output: Int64,
  requests: Int,
  lifetimeStartedAt: Date = UsageSnapshot.unknownLifetimeStartDate
) -> UsageSnapshot {
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
    observedAt: referenceDate,
    lifetimeStartedAt: lifetimeStartedAt
  )
}

private func snapshot(
  today: Int64,
  week: Int64,
  month: Int64,
  lifetime: Int64,
  observedAt: Date = referenceDate,
  lifetimeStartedAt: Date = UsageSnapshot.unknownLifetimeStartDate
) -> UsageSnapshot {
  UsageSnapshot(
    today: period(tokens: today),
    week: period(tokens: week),
    month: period(tokens: month),
    lifetime: period(tokens: lifetime),
    topSources: [],
    syncHealth: .syncing,
    observedAt: observedAt,
    lifetimeStartedAt: lifetimeStartedAt
  )
}

private func period(tokens: Int64) -> UsagePeriodStats {
  UsagePeriodStats(
    tokens: TokenBreakdown(input: tokens, output: 0),
    requests: RequestStats(total: Int(tokens / 100), succeeded: Int(tokens / 100), failed: 0)
  )
}
