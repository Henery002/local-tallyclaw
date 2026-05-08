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
      return UsageSnapshot(
        today: try database.aggregate(period: .today, key: periodKey(for: .today, at: observedAt)),
        week: try database.aggregate(period: .week, key: periodKey(for: .week, at: observedAt)),
        month: try database.aggregate(period: .month, key: periodKey(for: .month, at: observedAt)),
        lifetime: try database.aggregate(period: .lifetime, key: PeriodKind.lifetime.staticKey),
        topSources: try database.topSources(),
        syncHealth: .idle,
        observedAt: try database.latestObservedAt() ?? observedAt,
        sourceStatuses: try database.readSourceStatuses()
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

    try database.upsert(
      sourceID: sourceID,
      period: .today,
      key: periodKey(for: .today, at: snapshot.observedAt),
      stats: snapshot.today,
      observedAt: snapshot.observedAt
    )
    try database.upsert(
      sourceID: sourceID,
      period: .week,
      key: periodKey(for: .week, at: snapshot.observedAt),
      stats: snapshot.week,
      observedAt: snapshot.observedAt
    )
    try database.upsert(
      sourceID: sourceID,
      period: .month,
      key: periodKey(for: .month, at: snapshot.observedAt),
      stats: snapshot.month,
      observedAt: snapshot.observedAt
    )
    try database.upsert(
      sourceID: sourceID,
      period: .lifetime,
      key: PeriodKind.lifetime.staticKey,
      stats: snapshot.lifetime,
      observedAt: snapshot.observedAt
    )
  }

  public func recordSourceStatuses(_ statuses: [SourceReadStatus]) async throws {
    let database = try SQLiteLedgerDatabase.open(at: databaseURL)
    defer { database.close() }
    try database.replaceSourceStatuses(statuses)
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
    case .lifetime:
      return period.staticKey
    }
  }
}

private enum PeriodKind: String {
  case today
  case week
  case month
  case lifetime

  var staticKey: String { "all" }
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
        PRIMARY KEY (source_id, period_kind, period_key)
      );
      """)
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
        error_summary TEXT
      );
      """)
  }

  func upsert(
    sourceID: String,
    period: PeriodKind,
    key: String,
    stats: UsagePeriodStats,
    observedAt: Date
  ) throws {
    let incoming = StoredPeriodStats(sourceID: sourceID, period: period.rawValue, key: key, stats: stats, observedAt: observedAt)
    if let existing = try storedStats(sourceID: sourceID, period: period, key: key),
       existing.usageScore > incoming.usageScore {
      return
    }

    let sql = """
      INSERT INTO source_period_stats (
        source_id, period_kind, period_key, observed_at_ms,
        input_tokens, output_tokens, cache_tokens, thinking_tokens,
        request_total, request_succeeded, request_failed, average_latency_ms
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)
      ON CONFLICT(source_id, period_kind, period_key) DO UPDATE SET
        observed_at_ms = excluded.observed_at_ms,
        input_tokens = excluded.input_tokens,
        output_tokens = excluded.output_tokens,
        cache_tokens = excluded.cache_tokens,
        thinking_tokens = excluded.thinking_tokens,
        request_total = excluded.request_total,
        request_succeeded = excluded.request_succeeded,
        request_failed = excluded.request_failed,
        average_latency_ms = excluded.average_latency_ms;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }

    bindText(sourceID, to: statement, index: 1)
    bindText(period.rawValue, to: statement, index: 2)
    bindText(key, to: statement, index: 3)
    sqlite3_bind_int64(statement, 4, Int64(observedAt.timeIntervalSince1970 * 1_000))
    sqlite3_bind_int64(statement, 5, stats.tokens.input)
    sqlite3_bind_int64(statement, 6, stats.tokens.output)
    sqlite3_bind_int64(statement, 7, stats.tokens.cache)
    sqlite3_bind_int64(statement, 8, stats.tokens.thinking)
    sqlite3_bind_int(statement, 9, Int32(stats.requests.total))
    sqlite3_bind_int(statement, 10, Int32(stats.requests.succeeded))
    sqlite3_bind_int(statement, 11, Int32(stats.requests.failed))
    sqlite3_bind_int(statement, 12, Int32(stats.requests.averageLatencyMilliseconds))

    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw error("Failed to upsert ledger period stats.")
    }
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
        source_id, display_name, state, last_read_at_ms, last_observed_at_ms, error_summary
      ) VALUES (?1, ?2, ?3, ?4, ?5, ?6);
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

      guard sqlite3_step(statement) == SQLITE_DONE else {
        throw error("Failed to persist source read statuses.")
      }
    }
  }

  func readSourceStatuses() throws -> [SourceReadStatus] {
    let sql = """
      SELECT source_id, display_name, state, last_read_at_ms, last_observed_at_ms, error_summary
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

      statuses.append(
        SourceReadStatus(
          sourceID: sourceID,
          displayName: displayName,
          state: state,
          lastReadAt: lastReadAt,
          lastObservedAt: lastObservedAt,
          errorSummary: errorSummary
        )
      )
    }
    return statuses
  }

  private func storedStats(sourceID: String, period: PeriodKind, key: String) throws -> StoredPeriodStats? {
    let sql = """
      SELECT observed_at_ms, input_tokens, output_tokens, cache_tokens, thinking_tokens,
        request_total, request_succeeded, request_failed, average_latency_ms
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
      averageLatencyMilliseconds: Int(sqlite3_column_int64(statement, 8))
    )
  }

  private func execute(_ sql: String) throws {
    guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
      throw error("Failed to execute SQLite statement.")
    }
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

  init(sourceID: String, period: String, key: String, stats: UsagePeriodStats, observedAt: Date) {
    self.sourceID = sourceID
    self.period = period
    self.key = key
    self.observedAt = observedAt
    input = stats.tokens.input
    output = stats.tokens.output
    cache = stats.tokens.cache
    thinking = stats.tokens.thinking
    totalRequests = stats.requests.total
    succeededRequests = stats.requests.succeeded
    failedRequests = stats.requests.failed
    averageLatencyMilliseconds = stats.requests.averageLatencyMilliseconds
  }

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
    averageLatencyMilliseconds: Int
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
  }

  var usageScore: Int64 {
    input + output + cache + thinking + Int64(totalRequests)
  }
}

public enum SQLiteLedgerStoreError: Error, Equatable {
  case openFailed(message: String)
  case queryFailed(message: String)
}
