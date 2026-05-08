import Foundation
import SQLite3
import TallyClawCore

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct LocalAIGatewayUsageDataSource: UsageDataSource {
  public let id = "local-ai-gateway"
  public let displayName = "local-ai-gateway"
  public let accessPolicy = SourceAccessPolicy.default

  private let databaseURL: URL
  private let now: @Sendable () -> Date
  private let calendar: Calendar

  public init(
    databaseURL: URL = URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent("Library/Application Support/local-ai-gateway/gateway.db"),
    calendar: Calendar = .current,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.databaseURL = databaseURL
    self.calendar = calendar
    self.now = now
  }

  public func readSnapshot() async throws -> UsageSnapshot? {
    guard FileManager.default.fileExists(atPath: databaseURL.path) else {
      return nil
    }

    let database = try SQLiteDatabase.readOnly(at: databaseURL)
    defer { database.close() }

    guard try database.tableExists("inference_usage_events") else {
      return nil
    }

    let observedAt = now()
    let todayStart = calendar.startOfDay(for: observedAt)
    let weekStart = observedAt.addingTimeInterval(-7 * 24 * 60 * 60)
    let monthStart = observedAt.addingTimeInterval(-30 * 24 * 60 * 60)

    let today = try database.aggregate(since: todayStart)
    let week = try database.aggregate(since: weekStart)
    let month = try database.aggregate(since: monthStart)
    let lifetime = try database.aggregate(since: nil)
    let topSources = try database.topSources(since: todayStart)

    return UsageSnapshot(
      today: today,
      week: week,
      month: month,
      lifetime: lifetime,
      topSources: topSources,
      syncHealth: .idle,
      observedAt: observedAt
    )
  }
}

private final class SQLiteDatabase {
  private var handle: OpaquePointer?

  private init(handle: OpaquePointer?) {
    self.handle = handle
  }

  static func readOnly(at url: URL) throws -> SQLiteDatabase {
    var handle: OpaquePointer?
    let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil)
    guard result == SQLITE_OK else {
      defer {
        if handle != nil {
          sqlite3_close(handle)
        }
      }
      throw LocalAIGatewayUsageDataSourceError.openFailed(message: String(cString: sqlite3_errmsg(handle)))
    }
    return SQLiteDatabase(handle: handle)
  }

  func close() {
    if handle != nil {
      sqlite3_close(handle)
      handle = nil
    }
  }

  func tableExists(_ name: String) throws -> Bool {
    let sql = "SELECT COUNT(1) FROM sqlite_master WHERE type = 'table' AND name = ?;"
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_text(statement, 1, name, -1, sqliteTransient)
    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw error("Failed to inspect SQLite tables.")
    }
    return sqlite3_column_int64(statement, 0) > 0
  }

  func aggregate(since startDate: Date?) throws -> UsagePeriodStats {
    let sql = """
      SELECT
        COUNT(1),
        SUM(CASE WHEN ok = 1 THEN 1 ELSE 0 END),
        SUM(CASE WHEN ok = 0 THEN 1 ELSE 0 END),
        COALESCE(SUM(latency_ms), 0),
        COALESCE(SUM(input_tokens), 0),
        COALESCE(SUM(output_tokens), 0),
        COALESCE(SUM(cached_tokens), 0),
        COALESCE(SUM(reasoning_tokens), 0)
      FROM inference_usage_events
      WHERE (?1 IS NULL OR timestamp >= ?1);
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    bindTimestamp(startDate, to: statement)

    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw error("Failed to aggregate local-ai-gateway usage.")
    }

    let requestCount = Int(sqlite3_column_int64(statement, 0))
    let succeeded = Int(sqlite3_column_int64(statement, 1))
    let failed = Int(sqlite3_column_int64(statement, 2))
    let totalLatency = Int(sqlite3_column_int64(statement, 3))

    return UsagePeriodStats(
      tokens: TokenBreakdown(
        input: sqlite3_column_int64(statement, 4),
        output: sqlite3_column_int64(statement, 5),
        cache: sqlite3_column_int64(statement, 6),
        thinking: sqlite3_column_int64(statement, 7)
      ),
      requests: RequestStats(
        total: requestCount,
        succeeded: succeeded,
        failed: failed,
        averageLatencyMilliseconds: requestCount > 0 ? totalLatency / requestCount : 0
      )
    )
  }

  func topSources(since startDate: Date) throws -> [SourceShare] {
    let sql = """
      SELECT COALESCE(NULLIF(client_tag, ''), provider_id), COALESCE(SUM(total_tokens), 0)
      FROM inference_usage_events
      WHERE timestamp >= ?1
      GROUP BY COALESCE(NULLIF(client_tag, ''), provider_id)
      ORDER BY SUM(total_tokens) DESC
      LIMIT 3;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    bindTimestamp(startDate, to: statement)

    var rows: [(name: String, tokens: Int64)] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      let name = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? "unknown"
      rows.append((name: name, tokens: sqlite3_column_int64(statement, 1)))
    }

    let total = rows.reduce(Int64(0)) { $0 + $1.tokens }
    guard total > 0 else { return [] }

    return rows.map { row in
      SourceShare(
        name: row.name,
        percent: Int((Double(row.tokens) / Double(total) * 100).rounded())
      )
    }
  }

  private func prepare(_ sql: String) throws -> OpaquePointer? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
      throw error("Failed to prepare SQLite statement.")
    }
    return statement
  }

  private func bindTimestamp(_ date: Date?, to statement: OpaquePointer?) {
    guard let date else {
      sqlite3_bind_null(statement, 1)
      return
    }
    sqlite3_bind_int64(statement, 1, Int64(date.timeIntervalSince1970 * 1_000))
  }

  private func error(_ fallback: String) -> LocalAIGatewayUsageDataSourceError {
    let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? fallback
    return .queryFailed(message: message)
  }
}

public enum LocalAIGatewayUsageDataSourceError: Error, Equatable {
  case openFailed(message: String)
  case queryFailed(message: String)
}
