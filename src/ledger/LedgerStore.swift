import Foundation
import SQLite3
import TallyClawCore

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public protocol LedgerStore: Sendable {
  func latestSnapshot() async -> UsageSnapshot
  func record(_ snapshot: UsageSnapshot, sourceID: String) async throws
  func recordSourceStatuses(_ statuses: [SourceReadStatus]) async throws
}

public actor InMemoryLedgerStore: LedgerStore {
  private var snapshotsBySource: [String: UsageSnapshot] = [:]

  public init(snapshot: UsageSnapshot = .preview) {
    snapshotsBySource["preview"] = snapshot
  }

  public func latestSnapshot() -> UsageSnapshot {
    UsageSnapshot.merged(Array(snapshotsBySource.values))
  }

  public func record(_ snapshot: UsageSnapshot, sourceID: String) {
    snapshotsBySource[sourceID] = snapshot
  }

  public func recordSourceStatuses(_ statuses: [SourceReadStatus]) {}
}

public actor SQLiteLedgerStore: LedgerStore {
  private let databaseURL: URL
  private let calendar: Calendar
  private let now: @Sendable () -> Date

  public init(
    databaseURL: URL = SQLiteLedgerStore.defaultDatabaseURL(),
    calendar: Calendar = .current,
    now: @escaping @Sendable () -> Date = Date.init
  ) throws {
    self.databaseURL = databaseURL
    self.calendar = calendar
    self.now = now

    try FileManager.default.createDirectory(
      at: databaseURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let database = try SQLiteLedgerDatabase.open(at: databaseURL)
    defer { database.close() }
    try database.migrate()
  }

  public func latestSnapshot() async -> UsageSnapshot {
    do {
      let database = try SQLiteLedgerDatabase.open(at: databaseURL)
      defer { database.close() }

      let observedAt = now()
      let observationSummary = try database.observationSummary(
        since: calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: observedAt))
      )
      let lifetimeStart = try database.preferredLifetimeStartedAt()

      return UsageSnapshot(
        today: try database.aggregate(period: .today, key: periodKey(for: .today, at: observedAt)),
        week: try database.aggregate(period: .week, key: periodKey(for: .week, at: observedAt)),
        month: try database.aggregate(period: .month, key: periodKey(for: .month, at: observedAt)),
        lifetime: try database.aggregate(period: .lifetime, key: PeriodKind.lifetime.staticKey),
        topSources: try database.topSources(),
        syncHealth: .idle,
        observedAt: try database.latestObservedAt() ?? observedAt,
        lifetimeStartedAt: lifetimeStart?.date ?? UsageSnapshot.unknownLifetimeStartDate,
        lifetimeStartedAtLabel: lifetimeStart?.label,
        sourceStatuses: try database.readSourceStatuses(),
        observationFacets: observationSummary.usageFacets,
        dailyTokenTrend: try database.dailyTokenTrend(daysEndingAt: observedAt, calendar: calendar),
        hourlyTokenTrend: try database.halfHourTokenTrend(hoursEndingAt: observedAt, calendar: calendar)
      )
    } catch {
      return UsageSnapshot(
        today: .empty,
        week: .empty,
        month: .empty,
        lifetime: .empty,
        topSources: [],
        syncHealth: .warning,
        observedAt: now()
      )
    }
  }

  public func record(_ snapshot: UsageSnapshot, sourceID: String) async throws {
    let database = try SQLiteLedgerDatabase.open(at: databaseURL)
    defer { database.close() }

    let recordedAt = now()
    try database.recordObservation(
      StoredUsageObservation(
        sourceID: sourceID,
        observedAt: snapshot.observedAt,
        recordedAt: recordedAt,
        stats: snapshot.lifetime
      )
    )
    let todayKey = periodKey(for: .today, at: recordedAt)
    let weekKey = periodKey(for: .week, at: recordedAt)
    let monthKey = periodKey(for: .month, at: recordedAt)
    let lifetimeKey = PeriodKind.lifetime.staticKey
    let previousLifetimeRaw = try database.storedStats(
      sourceID: sourceID,
      period: .lifetime,
      key: lifetimeKey
    )?.rawPeriodStats
    let lifetimeDelta = previousLifetimeRaw.flatMap { snapshot.lifetime.nonRegressingPositiveDelta(from: $0) }

    try database.upsert(
      sourceID: sourceID,
      period: .today,
      key: todayKey,
      stats: try currentWindowStats(
        incoming: snapshot.today,
        sourceID: sourceID,
        period: .today,
        key: todayKey,
        lifetimeDelta: lifetimeDelta,
        database: database
      ),
      observedAt: snapshot.observedAt,
      lifetimeStartedAt: snapshot.lifetimeStartedAt
    )
    try database.upsert(
      sourceID: sourceID,
      period: .week,
      key: weekKey,
      stats: try currentWindowStats(
        incoming: snapshot.week,
        sourceID: sourceID,
        period: .week,
        key: weekKey,
        lifetimeDelta: lifetimeDelta,
        database: database
      ),
      observedAt: snapshot.observedAt,
      lifetimeStartedAt: snapshot.lifetimeStartedAt
    )
    try database.upsert(
      sourceID: sourceID,
      period: .month,
      key: monthKey,
      stats: try currentWindowStats(
        incoming: snapshot.month,
        sourceID: sourceID,
        period: .month,
        key: monthKey,
        lifetimeDelta: lifetimeDelta,
        database: database
      ),
      observedAt: snapshot.observedAt,
      lifetimeStartedAt: snapshot.lifetimeStartedAt
    )
    if let lifetimeDelta, !lifetimeDelta.isEmptyForLedger {
      try database.appendDelta(
        sourceID: sourceID,
        period: .halfHour,
        key: periodKey(for: .halfHour, at: recordedAt),
        delta: lifetimeDelta,
        observedAt: snapshot.observedAt,
        lifetimeStartedAt: snapshot.lifetimeStartedAt
      )
    }
    try database.upsert(
      sourceID: sourceID,
      period: .lifetime,
      key: lifetimeKey,
      stats: snapshot.lifetime,
      observedAt: snapshot.observedAt,
      lifetimeStartedAt: snapshot.lifetimeStartedAt
    )
  }

  public func recordSourceStatuses(_ statuses: [SourceReadStatus]) async throws {
    let database = try SQLiteLedgerDatabase.open(at: databaseURL)
    defer { database.close() }
    try database.replaceSourceStatuses(statuses)
  }

  public func recordObservations(_ observations: [UsageObservation]) async throws {
    guard !observations.isEmpty else { return }

    let database = try SQLiteLedgerDatabase.open(at: databaseURL)
    defer { database.close() }

    let recordedAt = now()
    for observation in observations {
      try database.recordObservation(
        StoredUsageObservation(observation: observation, recordedAt: recordedAt)
      )
    }
  }

  public func latestObservationDate(sourceID: String, confidence: String) async throws -> Date? {
    let database = try SQLiteLedgerDatabase.open(at: databaseURL)
    defer { database.close() }
    return try database.latestObservationDate(sourceID: sourceID, confidence: confidence)
  }

  public func observationSummary() async throws -> LedgerObservationSummary {
    let database = try SQLiteLedgerDatabase.open(at: databaseURL)
    defer { database.close() }
    return try database.observationSummary()
  }

  public static func defaultDatabaseURL() -> URL {
    URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent("Library/Application Support/TallyClaw/ledger.sqlite")
  }

  private func periodKey(for period: PeriodKind, at date: Date) -> String {
    switch period {
    case .today:
      let components = calendar.dateComponents([.year, .month, .day], from: date)
      return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    case .week:
      let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
      return String(format: "%04d-W%02d", components.yearForWeekOfYear ?? 0, components.weekOfYear ?? 0)
    case .month:
      let components = calendar.dateComponents([.year, .month], from: date)
      return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    case .halfHour:
      let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
      let minute = calendar.component(.minute, from: date) < 30 ? 0 : 30
      return String(format: "%04d-%02d-%02d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0, components.hour ?? 0, minute)
    case .lifetime:
      return period.staticKey
    }
  }

  private func currentWindowStats(
    incoming: UsagePeriodStats,
    sourceID: String,
    period: PeriodKind,
    key: String,
    lifetimeDelta: UsagePeriodStats?,
    database: SQLiteLedgerDatabase
  ) throws -> UsagePeriodStats {
    let candidate: UsagePeriodStats
    if sourceID == "cockpit-codex-stats",
       incoming.isEmptyForLedger,
       let lifetimeDelta,
       !lifetimeDelta.isEmptyForLedger {
      let previousRaw = try database.storedStats(sourceID: sourceID, period: period, key: key)?.rawPeriodStats ?? .empty
      candidate = previousRaw.adding(lifetimeDelta)
    } else {
      candidate = incoming
    }

    return candidate
  }
}

private enum PeriodKind: String {
  case today
  case week
  case month
  case halfHour
  case lifetime

  var staticKey: String { "all" }
}

public struct LedgerObservationSummary: Equatable, Sendable {
  public var totalCount: Int
  public var sourceCount: Int
  public var latestObservedAt: Date?
  public var providerLeaders: [LedgerObservationFacet]
  public var modelLeaders: [LedgerObservationFacet]
  public var sourceNameLeaders: [LedgerObservationFacet]

  public init(
    totalCount: Int,
    sourceCount: Int,
    latestObservedAt: Date?,
    providerLeaders: [LedgerObservationFacet] = [],
    modelLeaders: [LedgerObservationFacet] = [],
    sourceNameLeaders: [LedgerObservationFacet] = []
  ) {
    self.totalCount = totalCount
    self.sourceCount = sourceCount
    self.latestObservedAt = latestObservedAt
    self.providerLeaders = providerLeaders
    self.modelLeaders = modelLeaders
    self.sourceNameLeaders = sourceNameLeaders
  }
}

public struct LedgerObservationFacet: Equatable, Sendable {
  public var name: String
  public var count: Int
  public var tokens: Int64

  public init(name: String, count: Int, tokens: Int64) {
    self.name = name
    self.count = count
    self.tokens = tokens
  }
}

private extension LedgerObservationSummary {
  var usageFacets: UsageObservationFacets {
    UsageObservationFacets(
      providerLeaders: providerLeaders.map(\.usageFacet),
      modelLeaders: modelLeaders.map(\.usageFacet),
      sourceNameLeaders: sourceNameLeaders.map(\.usageFacet)
    )
  }
}

private extension LedgerObservationFacet {
  var usageFacet: UsageObservationFacet {
    UsageObservationFacet(name: name, count: count, tokens: tokens)
  }
}

private final class SQLiteLedgerDatabase {
  private var handle: OpaquePointer?

  private init(handle: OpaquePointer?) {
    self.handle = handle
  }

  static func open(at url: URL) throws -> SQLiteLedgerDatabase {
    var handle: OpaquePointer?
    let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
    guard result == SQLITE_OK else {
      defer {
        if handle != nil {
          sqlite3_close(handle)
        }
      }
      throw SQLiteLedgerStoreError.openFailed(message: String(cString: sqlite3_errmsg(handle)))
    }
    return SQLiteLedgerDatabase(handle: handle)
  }

  func close() {
    if handle != nil {
      sqlite3_close(handle)
      handle = nil
    }
  }

  func migrate() throws {
    try execute("""
      CREATE TABLE IF NOT EXISTS source_period_stats (
        source_id TEXT NOT NULL,
        period_kind TEXT NOT NULL,
        period_key TEXT NOT NULL,
        observed_at_ms INTEGER NOT NULL,
        input_tokens INTEGER NOT NULL,
        output_tokens INTEGER NOT NULL,
        cache_tokens INTEGER NOT NULL,
        thinking_tokens INTEGER NOT NULL,
        request_total INTEGER NOT NULL,
        request_succeeded INTEGER NOT NULL,
        request_failed INTEGER NOT NULL,
        average_latency_ms INTEGER NOT NULL,
        raw_input_tokens INTEGER,
        raw_output_tokens INTEGER,
        raw_cache_tokens INTEGER,
        raw_thinking_tokens INTEGER,
        raw_request_total INTEGER,
        raw_request_succeeded INTEGER,
        raw_request_failed INTEGER,
        raw_average_latency_ms INTEGER,
        lifetime_started_at_ms INTEGER,
        PRIMARY KEY (source_id, period_kind, period_key)
      );
      """)
    try addColumnIfMissing(table: "source_period_stats", column: "raw_input_tokens", definition: "INTEGER")
    try addColumnIfMissing(table: "source_period_stats", column: "raw_output_tokens", definition: "INTEGER")
    try addColumnIfMissing(table: "source_period_stats", column: "raw_cache_tokens", definition: "INTEGER")
    try addColumnIfMissing(table: "source_period_stats", column: "raw_thinking_tokens", definition: "INTEGER")
    try addColumnIfMissing(table: "source_period_stats", column: "raw_request_total", definition: "INTEGER")
    try addColumnIfMissing(table: "source_period_stats", column: "raw_request_succeeded", definition: "INTEGER")
    try addColumnIfMissing(table: "source_period_stats", column: "raw_request_failed", definition: "INTEGER")
    try addColumnIfMissing(table: "source_period_stats", column: "raw_average_latency_ms", definition: "INTEGER")
    try addColumnIfMissing(table: "source_period_stats", column: "lifetime_started_at_ms", definition: "INTEGER")
    try execute("""
      CREATE INDEX IF NOT EXISTS idx_source_period_stats_period
      ON source_period_stats (period_kind, period_key);
      """)
    try execute("""
      CREATE TABLE IF NOT EXISTS source_read_statuses (
        source_id TEXT NOT NULL PRIMARY KEY,
        display_name TEXT NOT NULL,
        state TEXT NOT NULL,
        last_read_at_ms INTEGER NOT NULL,
        last_observed_at_ms INTEGER,
        error_summary TEXT,
        read_duration_ms INTEGER
      );
      """)
    try addColumnIfMissing(table: "source_read_statuses", column: "read_duration_ms", definition: "INTEGER")
    try execute("""
      CREATE TABLE IF NOT EXISTS usage_observations (
        fingerprint TEXT NOT NULL PRIMARY KEY,
        source_id TEXT NOT NULL,
        source_event_id TEXT NOT NULL DEFAULT '',
        source_name TEXT NOT NULL DEFAULT '',
        provider TEXT NOT NULL DEFAULT '',
        model TEXT NOT NULL DEFAULT '',
        observed_at_ms INTEGER NOT NULL,
        recorded_at_ms INTEGER NOT NULL,
        confidence TEXT NOT NULL,
        input_tokens INTEGER NOT NULL,
        output_tokens INTEGER NOT NULL,
        cache_tokens INTEGER NOT NULL,
        thinking_tokens INTEGER NOT NULL,
        request_total INTEGER NOT NULL,
        request_succeeded INTEGER NOT NULL,
        request_failed INTEGER NOT NULL,
        average_latency_ms INTEGER NOT NULL
      );
      """)
    try execute("""
      CREATE INDEX IF NOT EXISTS idx_usage_observations_source_observed
      ON usage_observations (source_id, observed_at_ms);
      """)
    try addColumnIfMissing(table: "usage_observations", column: "source_event_id", definition: "TEXT NOT NULL DEFAULT ''")
    try addColumnIfMissing(table: "usage_observations", column: "source_name", definition: "TEXT NOT NULL DEFAULT ''")
    try addColumnIfMissing(table: "usage_observations", column: "provider", definition: "TEXT NOT NULL DEFAULT ''")
    try addColumnIfMissing(table: "usage_observations", column: "model", definition: "TEXT NOT NULL DEFAULT ''")
  }

  func recordObservation(_ observation: StoredUsageObservation) throws {
    let fingerprint = try resolvedFingerprint(for: observation)
    let sql = """
      INSERT INTO usage_observations (
        fingerprint, source_id, source_event_id, source_name, provider, model,
        observed_at_ms, recorded_at_ms, confidence,
        input_tokens, output_tokens, cache_tokens, thinking_tokens,
        request_total, request_succeeded, request_failed, average_latency_ms
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17)
      ON CONFLICT(fingerprint) DO UPDATE SET
        source_event_id = excluded.source_event_id,
        source_name = excluded.source_name,
        provider = excluded.provider,
        model = excluded.model,
        observed_at_ms = MAX(usage_observations.observed_at_ms, excluded.observed_at_ms),
        recorded_at_ms = MAX(usage_observations.recorded_at_ms, excluded.recorded_at_ms),
        confidence = excluded.confidence,
        input_tokens = MAX(usage_observations.input_tokens, excluded.input_tokens),
        output_tokens = MAX(usage_observations.output_tokens, excluded.output_tokens),
        cache_tokens = MAX(usage_observations.cache_tokens, excluded.cache_tokens),
        thinking_tokens = MAX(usage_observations.thinking_tokens, excluded.thinking_tokens),
        request_total = MAX(usage_observations.request_total, excluded.request_total),
        request_succeeded = MAX(usage_observations.request_succeeded, excluded.request_succeeded),
        request_failed = MAX(usage_observations.request_failed, excluded.request_failed),
        average_latency_ms = MAX(usage_observations.average_latency_ms, excluded.average_latency_ms);
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }

    bindText(fingerprint, to: statement, index: 1)
    bindText(observation.sourceID, to: statement, index: 2)
    bindText(observation.sourceEventID, to: statement, index: 3)
    bindText(observation.sourceName, to: statement, index: 4)
    bindText(observation.provider, to: statement, index: 5)
    bindText(observation.model, to: statement, index: 6)
    sqlite3_bind_int64(statement, 7, Int64(observation.observedAt.timeIntervalSince1970 * 1_000))
    sqlite3_bind_int64(statement, 8, Int64(observation.recordedAt.timeIntervalSince1970 * 1_000))
    bindText(observation.confidence, to: statement, index: 9)
    sqlite3_bind_int64(statement, 10, observation.stats.tokens.input)
    sqlite3_bind_int64(statement, 11, observation.stats.tokens.output)
    sqlite3_bind_int64(statement, 12, observation.stats.tokens.cache)
    sqlite3_bind_int64(statement, 13, observation.stats.tokens.thinking)
    sqlite3_bind_int(statement, 14, Int32(observation.stats.requests.total))
    sqlite3_bind_int(statement, 15, Int32(observation.stats.requests.succeeded))
    sqlite3_bind_int(statement, 16, Int32(observation.stats.requests.failed))
    sqlite3_bind_int(statement, 17, Int32(observation.stats.requests.averageLatencyMilliseconds))

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw error("Failed to record usage observation.")
    }
  }

  private func resolvedFingerprint(for observation: StoredUsageObservation) throws -> String {
    guard let legacyFingerprint = observation.legacyExactFingerprint else {
      return observation.fingerprint
    }

    let sql = """
      SELECT observed_at_ms
      FROM usage_observations
      WHERE fingerprint = ?1
        AND source_id = ?2
        AND source_event_id = ?3;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    bindText(legacyFingerprint, to: statement, index: 1)
    bindText(observation.sourceID, to: statement, index: 2)
    bindText(observation.sourceEventID, to: statement, index: 3)

    guard sqlite3_step(statement) == SQLITE_ROW else {
      return observation.fingerprint
    }

    let observedAtMilliseconds = sqlite3_column_int64(statement, 0)
    return observedAtMilliseconds == observation.observedAtMilliseconds ? legacyFingerprint : observation.fingerprint
  }

  func observationSummary(since: Date? = nil) throws -> LedgerObservationSummary {
    let whereClause = since == nil ? "" : "WHERE observed_at_ms >= ?1"
    let statement = try prepare("""
      SELECT COUNT(1), COUNT(DISTINCT source_id), MAX(observed_at_ms)
      FROM usage_observations
      \(whereClause);
      """)
    defer { sqlite3_finalize(statement) }
    if let since {
      sqlite3_bind_int64(statement, 1, Int64(since.timeIntervalSince1970 * 1_000))
    }

    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw error("Failed to summarize usage observations.")
    }

    let latestMillis = sqlite3_column_int64(statement, 2)
    return LedgerObservationSummary(
      totalCount: Int(sqlite3_column_int64(statement, 0)),
      sourceCount: Int(sqlite3_column_int64(statement, 1)),
      latestObservedAt: latestMillis > 0 ? Date(timeIntervalSince1970: Double(latestMillis) / 1_000) : nil,
      providerLeaders: try observationLeaders(column: "provider", since: since),
      modelLeaders: try observationLeaders(column: "model", since: since),
      sourceNameLeaders: try observationLeaders(column: "source_name", since: since)
    )
  }

  func latestObservationDate(sourceID: String, confidence: String) throws -> Date? {
    let sql = """
      SELECT MAX(observed_at_ms)
      FROM usage_observations
      WHERE source_id = ?1 AND confidence = ?2;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    bindText(sourceID, to: statement, index: 1)
    bindText(confidence, to: statement, index: 2)

    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw error("Failed to read latest usage observation date.")
    }
    let milliseconds = sqlite3_column_int64(statement, 0)
    guard milliseconds > 0 else { return nil }
    return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
  }

  func firstLedgerRecordedAt() throws -> Date? {
    let observationStatement = try prepare("SELECT MIN(recorded_at_ms) FROM usage_observations WHERE recorded_at_ms > 0;")
    defer { sqlite3_finalize(observationStatement) }

    guard sqlite3_step(observationStatement) == SQLITE_ROW else {
      throw error("Failed to read first ledger record timestamp.")
    }

    let observationMilliseconds = sqlite3_column_int64(observationStatement, 0)
    if observationMilliseconds > 0 {
      return Date(timeIntervalSince1970: Double(observationMilliseconds) / 1_000)
    }

    let periodStatement = try prepare("SELECT MIN(observed_at_ms) FROM source_period_stats WHERE observed_at_ms > 0;")
    defer { sqlite3_finalize(periodStatement) }

    guard sqlite3_step(periodStatement) == SQLITE_ROW else {
      throw error("Failed to read first ledger period timestamp.")
    }

    let periodMilliseconds = sqlite3_column_int64(periodStatement, 0)
    guard periodMilliseconds > 0 else { return nil }
    return Date(timeIntervalSince1970: Double(periodMilliseconds) / 1_000)
  }

  func earliestLifetimeStartedAt() throws -> Date? {
    let sql = """
      SELECT MIN(lifetime_started_at_ms)
      FROM source_period_stats
      WHERE period_kind = ?1
        AND period_key = ?2
        AND lifetime_started_at_ms > 0;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    bindText(PeriodKind.lifetime.rawValue, to: statement, index: 1)
    bindText(PeriodKind.lifetime.staticKey, to: statement, index: 2)

    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw error("Failed to read earliest upstream lifetime start.")
    }

    let milliseconds = sqlite3_column_int64(statement, 0)
    guard milliseconds > 0 else { return nil }
    return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
  }

  func preferredLifetimeStartedAt() throws -> LifetimeStartCandidate? {
    if let cockpitStartedAt = try lifetimeStartedAt(sourceID: "cockpit-codex-stats") {
      return LifetimeStartCandidate(date: cockpitStartedAt, label: "cockpit")
    }

    return try earliestLifetimeStartedAt().map {
      LifetimeStartCandidate(date: $0, label: nil)
    }
  }

  private func lifetimeStartedAt(sourceID: String) throws -> Date? {
    let sql = """
      SELECT MIN(lifetime_started_at_ms)
      FROM source_period_stats
      WHERE source_id = ?1
        AND period_kind = ?2
        AND period_key = ?3
        AND lifetime_started_at_ms > 0;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    bindText(sourceID, to: statement, index: 1)
    bindText(PeriodKind.lifetime.rawValue, to: statement, index: 2)
    bindText(PeriodKind.lifetime.staticKey, to: statement, index: 3)

    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw error("Failed to read source lifetime start.")
    }

    let milliseconds = sqlite3_column_int64(statement, 0)
    guard milliseconds > 0 else { return nil }
    return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
  }

  func dailyTokenTrend(daysEndingAt endDate: Date, calendar: Calendar) throws -> [DailyTokenUsage] {
    let startOfToday = calendar.startOfDay(for: endDate)
    let days = (0..<7).compactMap { offset -> Date? in
      calendar.date(byAdding: .day, value: offset - 6, to: startOfToday)
    }
    let keys = days.map { Self.dayKey(for: $0, calendar: calendar) }
    guard !keys.isEmpty else { return [] }

    let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ", ")
    let sql = """
      SELECT period_key, COALESCE(SUM(input_tokens + output_tokens + thinking_tokens), 0)
      FROM source_period_stats
      WHERE period_kind = ?1 AND period_key IN (\(placeholders))
      GROUP BY period_key;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    bindText(PeriodKind.today.rawValue, to: statement, index: 1)
    for (index, key) in keys.enumerated() {
      bindText(key, to: statement, index: Int32(index + 2))
    }

    var tokensByKey: [String: Int64] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
      let key = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
      tokensByKey[key] = sqlite3_column_int64(statement, 1)
    }

    return zip(days, keys).map { day, key in
      DailyTokenUsage(
        dayKey: key,
        label: Self.dayLabel(for: day, calendar: calendar),
        tokens: tokensByKey[key] ?? 0
      )
    }
  }

  func halfHourTokenTrend(hoursEndingAt endDate: Date, calendar: Calendar) throws -> [HourlyTokenUsage] {
    let currentBucketStart = Self.halfHourBucketStart(for: endDate, calendar: calendar)
    let bucketStarts = (0..<12).compactMap { offset -> Date? in
      calendar.date(byAdding: .minute, value: (offset - 11) * 30, to: currentBucketStart)
    }
    let keys = bucketStarts.map { Self.halfHourKey(for: $0, calendar: calendar) }
    guard !keys.isEmpty else { return [] }

    let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ", ")
    let sql = """
      SELECT period_key, COALESCE(SUM(input_tokens + output_tokens + thinking_tokens), 0)
      FROM source_period_stats
      WHERE period_kind = ?1 AND period_key IN (\(placeholders))
      GROUP BY period_key;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    bindText(PeriodKind.halfHour.rawValue, to: statement, index: 1)
    for (index, key) in keys.enumerated() {
      bindText(key, to: statement, index: Int32(index + 2))
    }

    var tokensByKey: [String: Int64] = [:]
    while sqlite3_step(statement) == SQLITE_ROW {
      let key = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
      tokensByKey[key] = sqlite3_column_int64(statement, 1)
    }

    return zip(bucketStarts, keys).map { bucketStart, key in
      HourlyTokenUsage(
        bucketKey: key,
        label: Self.halfHourLabel(for: bucketStart, calendar: calendar),
        tokens: tokensByKey[key] ?? 0
      )
    }
  }

  private func observationLeaders(column: String, since: Date? = nil) throws -> [LedgerObservationFacet] {
    let sinceClause = since == nil ? "" : "AND observed_at_ms >= ?1"
    let sql = """
      SELECT \(column), COUNT(1), COALESCE(SUM(input_tokens + output_tokens + thinking_tokens), 0)
      FROM usage_observations
      WHERE confidence = 'exact' AND \(column) <> '' \(sinceClause)
      GROUP BY \(column)
      ORDER BY SUM(input_tokens + output_tokens + thinking_tokens) DESC, COUNT(1) DESC, \(column) ASC
      LIMIT 3;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    if let since {
      sqlite3_bind_int64(statement, 1, Int64(since.timeIntervalSince1970 * 1_000))
    }

    var leaders: [LedgerObservationFacet] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      let name = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "unknown"
      leaders.append(
        LedgerObservationFacet(
          name: name,
          count: Int(sqlite3_column_int64(statement, 1)),
          tokens: sqlite3_column_int64(statement, 2)
        )
      )
    }
    return leaders
  }

  private static func dayKey(for date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
  }

  private static func dayLabel(for date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.month, .day], from: date)
    return String(format: "%d/%d", components.month ?? 0, components.day ?? 0)
  }

  private static func halfHourBucketStart(for date: Date, calendar: Calendar) -> Date {
    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    components.minute = (components.minute ?? 0) < 30 ? 0 : 30
    components.second = 0
    components.nanosecond = 0
    return calendar.date(from: components) ?? date
  }

  private static func halfHourKey(for date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    return String(
      format: "%04d-%02d-%02d-%02d-%02d",
      components.year ?? 0,
      components.month ?? 0,
      components.day ?? 0,
      components.hour ?? 0,
      components.minute ?? 0
    )
  }

  private static func halfHourLabel(for date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.hour, .minute], from: date)
    return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
  }

  func upsert(
    sourceID: String,
    period: PeriodKind,
    key: String,
    stats: UsagePeriodStats,
    observedAt: Date,
    lifetimeStartedAt: Date
  ) throws {
    let existing = try storedStats(sourceID: sourceID, period: period, key: key)
    let persistedStats = existing.map { Self.accumulatedStats(existing: $0, incoming: stats) } ?? stats

    let sql = """
      INSERT INTO source_period_stats (
        source_id, period_kind, period_key, observed_at_ms,
        input_tokens, output_tokens, cache_tokens, thinking_tokens,
        request_total, request_succeeded, request_failed, average_latency_ms,
        raw_input_tokens, raw_output_tokens, raw_cache_tokens, raw_thinking_tokens,
        raw_request_total, raw_request_succeeded, raw_request_failed, raw_average_latency_ms,
        lifetime_started_at_ms
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21)
      ON CONFLICT(source_id, period_kind, period_key) DO UPDATE SET
        observed_at_ms = excluded.observed_at_ms,
        input_tokens = excluded.input_tokens,
        output_tokens = excluded.output_tokens,
        cache_tokens = excluded.cache_tokens,
        thinking_tokens = excluded.thinking_tokens,
        request_total = excluded.request_total,
        request_succeeded = excluded.request_succeeded,
        request_failed = excluded.request_failed,
        average_latency_ms = excluded.average_latency_ms,
        raw_input_tokens = excluded.raw_input_tokens,
        raw_output_tokens = excluded.raw_output_tokens,
        raw_cache_tokens = excluded.raw_cache_tokens,
        raw_thinking_tokens = excluded.raw_thinking_tokens,
        raw_request_total = excluded.raw_request_total,
        raw_request_succeeded = excluded.raw_request_succeeded,
        raw_request_failed = excluded.raw_request_failed,
        raw_average_latency_ms = excluded.raw_average_latency_ms,
        lifetime_started_at_ms = CASE
          WHEN excluded.lifetime_started_at_ms IS NULL OR excluded.lifetime_started_at_ms <= 0
            THEN source_period_stats.lifetime_started_at_ms
          WHEN source_period_stats.lifetime_started_at_ms IS NULL OR source_period_stats.lifetime_started_at_ms <= 0
            THEN excluded.lifetime_started_at_ms
          ELSE MIN(source_period_stats.lifetime_started_at_ms, excluded.lifetime_started_at_ms)
        END;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }

    bindText(sourceID, to: statement, index: 1)
    bindText(period.rawValue, to: statement, index: 2)
    bindText(key, to: statement, index: 3)
    sqlite3_bind_int64(statement, 4, Int64(observedAt.timeIntervalSince1970 * 1_000))
    sqlite3_bind_int64(statement, 5, persistedStats.tokens.input)
    sqlite3_bind_int64(statement, 6, persistedStats.tokens.output)
    sqlite3_bind_int64(statement, 7, persistedStats.tokens.cache)
    sqlite3_bind_int64(statement, 8, persistedStats.tokens.thinking)
    sqlite3_bind_int(statement, 9, Int32(persistedStats.requests.total))
    sqlite3_bind_int(statement, 10, Int32(persistedStats.requests.succeeded))
    sqlite3_bind_int(statement, 11, Int32(persistedStats.requests.failed))
    sqlite3_bind_int(statement, 12, Int32(persistedStats.requests.averageLatencyMilliseconds))
    sqlite3_bind_int64(statement, 13, stats.tokens.input)
    sqlite3_bind_int64(statement, 14, stats.tokens.output)
    sqlite3_bind_int64(statement, 15, stats.tokens.cache)
    sqlite3_bind_int64(statement, 16, stats.tokens.thinking)
    sqlite3_bind_int(statement, 17, Int32(stats.requests.total))
    sqlite3_bind_int(statement, 18, Int32(stats.requests.succeeded))
    sqlite3_bind_int(statement, 19, Int32(stats.requests.failed))
    sqlite3_bind_int(statement, 20, Int32(stats.requests.averageLatencyMilliseconds))
    if let lifetimeStartedAtMilliseconds = Self.validLifetimeStartedAtMilliseconds(lifetimeStartedAt) {
      sqlite3_bind_int64(statement, 21, lifetimeStartedAtMilliseconds)
    } else {
      sqlite3_bind_null(statement, 21)
    }

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw error("Failed to upsert ledger period stats.")
    }
  }

  func appendDelta(
    sourceID: String,
    period: PeriodKind,
    key: String,
    delta: UsagePeriodStats,
    observedAt: Date,
    lifetimeStartedAt: Date
  ) throws {
    let existingRaw = try storedStats(sourceID: sourceID, period: period, key: key)?.rawPeriodStats ?? .empty
    try upsert(
      sourceID: sourceID,
      period: period,
      key: key,
      stats: existingRaw.adding(delta),
      observedAt: observedAt,
      lifetimeStartedAt: lifetimeStartedAt
    )
  }

  private static func validLifetimeStartedAtMilliseconds(_ date: Date) -> Int64? {
    guard date > UsageSnapshot.unknownLifetimeStartDate else { return nil }
    let milliseconds = Int64(date.timeIntervalSince1970 * 1_000)
    return milliseconds > 0 ? milliseconds : nil
  }

  private static func accumulatedStats(existing: StoredPeriodStats, incoming: UsagePeriodStats) -> UsagePeriodStats {
    let previousRaw = existing.rawPeriodStats
    guard !incoming.hasCounterRegression(comparedTo: previousRaw) else {
      return existing.periodStats
    }
    return existing.periodStats.adding(.positiveDelta(from: previousRaw, to: incoming))
  }

  func aggregate(period: PeriodKind, key: String) throws -> UsagePeriodStats {
    let sql = """
      SELECT
        COALESCE(SUM(input_tokens), 0),
        COALESCE(SUM(output_tokens), 0),
        COALESCE(SUM(cache_tokens), 0),
        COALESCE(SUM(thinking_tokens), 0),
        COALESCE(SUM(request_total), 0),
        COALESCE(SUM(request_succeeded), 0),
        COALESCE(SUM(request_failed), 0),
        COALESCE(SUM(request_total * average_latency_ms), 0)
      FROM source_period_stats
      WHERE period_kind = ?1 AND period_key = ?2;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    bindText(period.rawValue, to: statement, index: 1)
    bindText(key, to: statement, index: 2)

    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw error("Failed to aggregate ledger period stats.")
    }

    let requestTotal = Int(sqlite3_column_int64(statement, 4))
    let weightedLatency = Int(sqlite3_column_int64(statement, 7))
    return UsagePeriodStats(
      tokens: TokenBreakdown(
        input: sqlite3_column_int64(statement, 0),
        output: sqlite3_column_int64(statement, 1),
        cache: sqlite3_column_int64(statement, 2),
        thinking: sqlite3_column_int64(statement, 3)
      ),
      requests: RequestStats(
        total: requestTotal,
        succeeded: Int(sqlite3_column_int64(statement, 5)),
        failed: Int(sqlite3_column_int64(statement, 6)),
        averageLatencyMilliseconds: requestTotal > 0 ? weightedLatency / requestTotal : 0
      )
    )
  }

  func topSources() throws -> [SourceShare] {
    let sql = """
      SELECT source_id, input_tokens + output_tokens + cache_tokens + thinking_tokens
      FROM source_period_stats
      WHERE period_kind = ?1 AND period_key = ?2
      ORDER BY input_tokens + output_tokens + cache_tokens + thinking_tokens DESC
      LIMIT 3;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    bindText(PeriodKind.lifetime.rawValue, to: statement, index: 1)
    bindText(PeriodKind.lifetime.staticKey, to: statement, index: 2)

    var rows: [(sourceID: String, tokens: Int64)] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      let sourceID = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "unknown"
      rows.append((sourceID: sourceID, tokens: sqlite3_column_int64(statement, 1)))
    }

    let total = rows.reduce(Int64(0)) { $0 + $1.tokens }
    guard total > 0 else { return [] }

    return rows.map { row in
      SourceShare(name: row.sourceID, percent: Int((Double(row.tokens) / Double(total) * 100).rounded()))
    }
  }

  func latestObservedAt() throws -> Date? {
    let statement = try prepare("SELECT MAX(observed_at_ms) FROM source_period_stats;")
    defer { sqlite3_finalize(statement) }

    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw error("Failed to read latest observed timestamp.")
    }
    let milliseconds = sqlite3_column_int64(statement, 0)
    guard milliseconds > 0 else { return nil }
    return Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
  }

  func replaceSourceStatuses(_ statuses: [SourceReadStatus]) throws {
    try execute("DELETE FROM source_read_statuses;")
    guard !statuses.isEmpty else { return }

    let sql = """
      INSERT INTO source_read_statuses (
        source_id, display_name, state, last_read_at_ms, last_observed_at_ms, error_summary, read_duration_ms
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7);
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }

    for status in statuses {
      sqlite3_reset(statement)
      sqlite3_clear_bindings(statement)
      bindText(status.sourceID, to: statement, index: 1)
      bindText(status.displayName, to: statement, index: 2)
      bindText(status.state.rawValue, to: statement, index: 3)
      sqlite3_bind_int64(statement, 4, Int64(status.lastReadAt.timeIntervalSince1970 * 1_000))
      if let lastObservedAt = status.lastObservedAt {
        sqlite3_bind_int64(statement, 5, Int64(lastObservedAt.timeIntervalSince1970 * 1_000))
      } else {
        sqlite3_bind_null(statement, 5)
      }
      if let errorSummary = status.errorSummary {
        bindText(errorSummary, to: statement, index: 6)
      } else {
        sqlite3_bind_null(statement, 6)
      }
      if let readDurationMilliseconds = status.readDurationMilliseconds {
        sqlite3_bind_int(statement, 7, Int32(readDurationMilliseconds))
      } else {
        sqlite3_bind_null(statement, 7)
      }

      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw error("Failed to persist source read statuses.")
      }
    }
  }

  func readSourceStatuses() throws -> [SourceReadStatus] {
    let sql = """
      SELECT source_id, display_name, state, last_read_at_ms, last_observed_at_ms, error_summary, read_duration_ms
      FROM source_read_statuses
      ORDER BY source_id ASC;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }

    var statuses: [SourceReadStatus] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      let sourceID = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "unknown"
      let displayName = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? sourceID
      let rawState = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? SourceReadState.failed.rawValue
      let state = SourceReadState(rawValue: rawState) ?? .failed
      let lastReadAt = Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 3)) / 1_000)
      let lastObservedMillis = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, 4)
      let lastObservedAt = lastObservedMillis.map { Date(timeIntervalSince1970: Double($0) / 1_000) }
      let errorSummary = sqlite3_column_text(statement, 5).map { String(cString: $0) }
      let readDurationMilliseconds = sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : Int(sqlite3_column_int(statement, 6))

      statuses.append(
        SourceReadStatus(
          sourceID: sourceID,
          displayName: displayName,
          state: state,
          lastReadAt: lastReadAt,
          lastObservedAt: lastObservedAt,
          errorSummary: errorSummary,
          readDurationMilliseconds: readDurationMilliseconds
        )
      )
    }
    return statuses
  }

  func storedStats(sourceID: String, period: PeriodKind, key: String) throws -> StoredPeriodStats? {
    let sql = """
      SELECT observed_at_ms, input_tokens, output_tokens, cache_tokens, thinking_tokens,
        request_total, request_succeeded, request_failed, average_latency_ms,
        COALESCE(raw_input_tokens, input_tokens),
        COALESCE(raw_output_tokens, output_tokens),
        COALESCE(raw_cache_tokens, cache_tokens),
        COALESCE(raw_thinking_tokens, thinking_tokens),
        COALESCE(raw_request_total, request_total),
        COALESCE(raw_request_succeeded, request_succeeded),
        COALESCE(raw_request_failed, request_failed),
        COALESCE(raw_average_latency_ms, average_latency_ms)
      FROM source_period_stats
      WHERE source_id = ?1 AND period_kind = ?2 AND period_key = ?3;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    bindText(sourceID, to: statement, index: 1)
    bindText(period.rawValue, to: statement, index: 2)
    bindText(key, to: statement, index: 3)

    guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
    return StoredPeriodStats(
      sourceID: sourceID,
      period: period.rawValue,
      key: key,
      observedAt: Date(timeIntervalSince1970: Double(sqlite3_column_int64(statement, 0)) / 1_000),
      input: sqlite3_column_int64(statement, 1),
      output: sqlite3_column_int64(statement, 2),
      cache: sqlite3_column_int64(statement, 3),
      thinking: sqlite3_column_int64(statement, 4),
      totalRequests: Int(sqlite3_column_int64(statement, 5)),
      succeededRequests: Int(sqlite3_column_int64(statement, 6)),
      failedRequests: Int(sqlite3_column_int64(statement, 7)),
      averageLatencyMilliseconds: Int(sqlite3_column_int64(statement, 8)),
      rawInput: sqlite3_column_int64(statement, 9),
      rawOutput: sqlite3_column_int64(statement, 10),
      rawCache: sqlite3_column_int64(statement, 11),
      rawThinking: sqlite3_column_int64(statement, 12),
      rawTotalRequests: Int(sqlite3_column_int64(statement, 13)),
      rawSucceededRequests: Int(sqlite3_column_int64(statement, 14)),
      rawFailedRequests: Int(sqlite3_column_int64(statement, 15)),
      rawAverageLatencyMilliseconds: Int(sqlite3_column_int64(statement, 16))
    )
  }

  private func execute(_ sql: String) throws {
    guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
      throw error("Failed to execute SQLite statement.")
    }
  }

  private func addColumnIfMissing(table: String, column: String, definition: String) throws {
    guard try !columnExists(table: table, column: column) else { return }
    try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
  }

  private func columnExists(table: String, column: String) throws -> Bool {
    let statement = try prepare("PRAGMA table_info(\(table));")
    defer { sqlite3_finalize(statement) }

    while sqlite3_step(statement) == SQLITE_ROW {
      let existingColumn = sqlite3_column_text(statement, 1).map { String(cString: $0) }
      if existingColumn == column {
        return true
      }
    }
    return false
  }

  private func prepare(_ sql: String) throws -> OpaquePointer? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
      throw error("Failed to prepare SQLite statement.")
    }
    return statement
  }

  private func bindText(_ text: String, to statement: OpaquePointer?, index: Int32) {
    sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
  }

  private func error(_ fallback: String) -> SQLiteLedgerStoreError {
    let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? fallback
    return .queryFailed(message: message)
  }
}

private struct LifetimeStartCandidate {
  let date: Date
  let label: String?
}

private struct StoredPeriodStats {
  let sourceID: String
  let period: String
  let key: String
  let observedAt: Date
  let input: Int64
  let output: Int64
  let cache: Int64
  let thinking: Int64
  let totalRequests: Int
  let succeededRequests: Int
  let failedRequests: Int
  let averageLatencyMilliseconds: Int
  let rawInput: Int64
  let rawOutput: Int64
  let rawCache: Int64
  let rawThinking: Int64
  let rawTotalRequests: Int
  let rawSucceededRequests: Int
  let rawFailedRequests: Int
  let rawAverageLatencyMilliseconds: Int

  init(
    sourceID: String,
    period: String,
    key: String,
    observedAt: Date,
    input: Int64,
    output: Int64,
    cache: Int64,
    thinking: Int64,
    totalRequests: Int,
    succeededRequests: Int,
    failedRequests: Int,
    averageLatencyMilliseconds: Int,
    rawInput: Int64,
    rawOutput: Int64,
    rawCache: Int64,
    rawThinking: Int64,
    rawTotalRequests: Int,
    rawSucceededRequests: Int,
    rawFailedRequests: Int,
    rawAverageLatencyMilliseconds: Int
  ) {
    self.sourceID = sourceID
    self.period = period
    self.key = key
    self.observedAt = observedAt
    self.input = input
    self.output = output
    self.cache = cache
    self.thinking = thinking
    self.totalRequests = totalRequests
    self.succeededRequests = succeededRequests
    self.failedRequests = failedRequests
    self.averageLatencyMilliseconds = averageLatencyMilliseconds
    self.rawInput = rawInput
    self.rawOutput = rawOutput
    self.rawCache = rawCache
    self.rawThinking = rawThinking
    self.rawTotalRequests = rawTotalRequests
    self.rawSucceededRequests = rawSucceededRequests
    self.rawFailedRequests = rawFailedRequests
    self.rawAverageLatencyMilliseconds = rawAverageLatencyMilliseconds
  }

  var usageScore: Int64 {
    input + output + cache + thinking + Int64(totalRequests)
  }

  var periodStats: UsagePeriodStats {
    UsagePeriodStats(
      tokens: TokenBreakdown(input: input, output: output, cache: cache, thinking: thinking),
      requests: RequestStats(
        total: totalRequests,
        succeeded: succeededRequests,
        failed: failedRequests,
        averageLatencyMilliseconds: averageLatencyMilliseconds
      )
    )
  }

  var rawPeriodStats: UsagePeriodStats {
    UsagePeriodStats(
      tokens: TokenBreakdown(input: rawInput, output: rawOutput, cache: rawCache, thinking: rawThinking),
      requests: RequestStats(
        total: rawTotalRequests,
        succeeded: rawSucceededRequests,
        failed: rawFailedRequests,
        averageLatencyMilliseconds: rawAverageLatencyMilliseconds
      )
    )
  }
}

private struct StoredUsageObservation {
  let sourceID: String
  let sourceEventID: String
  let sourceName: String
  let provider: String
  let model: String
  let observedAt: Date
  let recordedAt: Date
  let stats: UsagePeriodStats
  let confidence: String

  init(sourceID: String, observedAt: Date, recordedAt: Date, stats: UsagePeriodStats) {
    self.sourceID = sourceID
    sourceEventID = ""
    sourceName = ""
    provider = ""
    model = ""
    self.observedAt = observedAt
    self.recordedAt = recordedAt
    self.stats = stats
    confidence = "snapshot"
  }

  init(observation: UsageObservation, recordedAt: Date) {
    sourceID = PrivacySafeText.label(observation.sourceID, fallback: "unknown")
    sourceEventID = PrivacySafeText.eventID(observation.sourceEventID, sourceID: sourceID)
    sourceName = PrivacySafeText.label(observation.sourceName, fallback: "unknown")
    provider = PrivacySafeText.label(observation.provider, fallback: "unknown")
    model = PrivacySafeText.label(observation.model, fallback: "unknown")
    observedAt = observation.observedAt
    self.recordedAt = recordedAt
    stats = UsagePeriodStats(tokens: observation.tokens, requests: observation.requests)
    confidence = PrivacySafeText.label(observation.confidence, fallback: "exact")
  }

  var fingerprint: String {
    if confidence == "exact", !sourceEventID.isEmpty {
      return StableFingerprint.make([sourceID, confidence, sourceEventID, "\(observedAtMilliseconds)"])
    }

    return StableFingerprint.make([
      sourceID,
      "\(stats.tokens.input)",
      "\(stats.tokens.output)",
      "\(stats.tokens.cache)",
      "\(stats.tokens.thinking)",
      "\(stats.requests.total)",
      "\(stats.requests.succeeded)",
      "\(stats.requests.failed)",
      "\(stats.requests.averageLatencyMilliseconds)"
    ])
  }

  var legacyExactFingerprint: String? {
    guard confidence == "exact", !sourceEventID.isEmpty else { return nil }
    return StableFingerprint.make([sourceID, confidence, sourceEventID])
  }

  var observedAtMilliseconds: Int64 {
    Int64(observedAt.timeIntervalSince1970 * 1_000)
  }
}

private enum PrivacySafeText {
  static func label(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return fallback }
    guard !looksSensitive(trimmed) else { return "redacted" }
    return String(trimmed.prefix(120))
  }

  static func eventID(_ value: String, sourceID: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "unknown" }
    guard !looksSensitive(trimmed) else {
      return "redacted-\(StableFingerprint.make([sourceID, trimmed]))"
    }
    return String(trimmed.prefix(160))
  }

  private static func looksSensitive(_ value: String) -> Bool {
    let lowercased = value.lowercased()
    return value.contains("@") ||
      lowercased.contains("sk-") ||
      lowercased.contains("api_key") ||
      lowercased.contains("apikey") ||
      lowercased.contains("bearer ")
  }
}

private enum StableFingerprint {
  static func make(_ parts: [String]) -> String {
    let input = parts.joined(separator: "\u{1F}")
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in input.utf8 {
      hash ^= UInt64(byte)
      hash &*= 0x100000001b3
    }
    return String(format: "%016llx", hash)
  }
}

private extension UsagePeriodStats {
  var usageScore: Int64 {
    tokens.input + tokens.output + tokens.cache + tokens.thinking + Int64(requests.total)
  }

  func hasCounterRegression(comparedTo previous: UsagePeriodStats) -> Bool {
    tokens.input < previous.tokens.input ||
      tokens.output < previous.tokens.output ||
      tokens.cache < previous.tokens.cache ||
      tokens.thinking < previous.tokens.thinking ||
      requests.total < previous.requests.total ||
      requests.succeeded < previous.requests.succeeded ||
      requests.failed < previous.requests.failed
  }

  var isEmptyForLedger: Bool {
    tokens.input == 0 &&
      tokens.output == 0 &&
      tokens.cache == 0 &&
      tokens.thinking == 0 &&
      requests.total == 0 &&
      requests.succeeded == 0 &&
      requests.failed == 0
  }

  func adding(_ other: UsagePeriodStats) -> UsagePeriodStats {
    UsagePeriodStats(
      tokens: TokenBreakdown(
        input: tokens.input + other.tokens.input,
        output: tokens.output + other.tokens.output,
        cache: tokens.cache + other.tokens.cache,
        thinking: tokens.thinking + other.tokens.thinking
      ),
      requests: RequestStats(
        total: requests.total + other.requests.total,
        succeeded: requests.succeeded + other.requests.succeeded,
        failed: requests.failed + other.requests.failed,
        averageLatencyMilliseconds: weightedLatency(lhs: requests, rhs: other.requests)
      )
    )
  }

  static func positiveDelta(from previous: UsagePeriodStats, to current: UsagePeriodStats) -> UsagePeriodStats {
    UsagePeriodStats(
      tokens: TokenBreakdown(
        input: max(0, current.tokens.input - previous.tokens.input),
        output: max(0, current.tokens.output - previous.tokens.output),
        cache: max(0, current.tokens.cache - previous.tokens.cache),
        thinking: max(0, current.tokens.thinking - previous.tokens.thinking)
      ),
      requests: RequestStats(
        total: max(0, current.requests.total - previous.requests.total),
        succeeded: max(0, current.requests.succeeded - previous.requests.succeeded),
        failed: max(0, current.requests.failed - previous.requests.failed),
        averageLatencyMilliseconds: current.requests.averageLatencyMilliseconds
      )
    )
  }

  func nonRegressingPositiveDelta(from previous: UsagePeriodStats) -> UsagePeriodStats? {
    guard !hasCounterRegression(comparedTo: previous) else { return nil }
    return .positiveDelta(from: previous, to: self)
  }

  private func weightedLatency(lhs: RequestStats, rhs: RequestStats) -> Int {
    let total = lhs.total + rhs.total
    guard total > 0 else { return 0 }
    return ((lhs.total * lhs.averageLatencyMilliseconds) + (rhs.total * rhs.averageLatencyMilliseconds)) / total
  }
}

public enum SQLiteLedgerStoreError: Error, Equatable {
  case openFailed(message: String)
  case queryFailed(message: String)
}
