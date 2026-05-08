import Foundation
import SQLite3
import TallyClawCore

private let hermesSqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct HermesUsageDataSource: UsageDataSource {
  public let id = "hermes-usage"
  public let displayName = "hermes"
  public let accessPolicy = SourceAccessPolicy.default

  private let rootURL: URL
  private let now: @Sendable () -> Date
  private let calendar: Calendar

  public init(
    rootURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".hermes"),
    calendar: Calendar = .current,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.rootURL = rootURL
    self.calendar = calendar
    self.now = now
  }

  public func readSnapshot() async throws -> UsageSnapshot? {
    let databaseURL = rootURL.appendingPathComponent("state.db")
    guard FileManager.default.fileExists(atPath: databaseURL.path) else {
      return nil
    }

    let database = try HermesSQLiteDatabase.readOnly(at: databaseURL)
    defer { database.close() }

    guard try database.tableExists("sessions") else {
      return nil
    }

    let events = try database.readSessionUsageEvents().filter { !isLocalAIGatewayURL($0.billingBaseURL) && $0.totalTokens > 0 }
    guard !events.isEmpty else {
      return nil
    }

    let support = UsageWindowSupport(now: now(), calendar: calendar)
    let observedAt = events.map(\.observedAt).max() ?? support.todayStart

    return UsageSnapshot(
      today: support.periodStats(for: events, since: support.todayStart),
      week: support.periodStats(for: events, since: support.trailing7DaysStart),
      month: support.periodStats(for: events, since: support.trailing30DaysStart),
      lifetime: support.periodStats(for: events, since: nil),
      topSources: support.topSources(for: events, since: support.todayStart),
      syncHealth: .idle,
      observedAt: observedAt
    )
  }
}

private final class HermesSQLiteDatabase {
  private var handle: OpaquePointer?

  private init(handle: OpaquePointer?) {
    self.handle = handle
  }

  static func readOnly(at url: URL) throws -> HermesSQLiteDatabase {
    var handle: OpaquePointer?
    let uri = "\(url.absoluteString)?mode=ro&immutable=1"
    let result = sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
    guard result == SQLITE_OK else {
      defer {
        if handle != nil {
          sqlite3_close(handle)
        }
      }
      throw HermesUsageDataSourceError.openFailed(message: String(cString: sqlite3_errmsg(handle)))
    }
    return HermesSQLiteDatabase(handle: handle)
  }

  func close() {
    if handle != nil {
      sqlite3_close(handle)
      handle = nil
    }
  }

  func tableExists(_ name: String) throws -> Bool {
    let sql = "SELECT COUNT(1) FROM sqlite_master WHERE type = 'table' AND name = ?1;"
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_text(statement, 1, name, -1, hermesSqliteTransient)
    guard sqlite3_step(statement) == SQLITE_ROW else {
      throw error("Failed to inspect Hermes tables.")
    }
    return sqlite3_column_int64(statement, 0) > 0
  }

  func readSessionUsageEvents() throws -> [HermesSessionUsageEvent] {
    let sql = """
      SELECT
        COALESCE(ended_at, started_at),
        billing_provider,
        billing_base_url,
        input_tokens,
        output_tokens,
        cache_read_tokens,
        reasoning_tokens,
        api_call_count
      FROM sessions
      WHERE COALESCE(input_tokens, 0) + COALESCE(output_tokens, 0) + COALESCE(cache_read_tokens, 0) + COALESCE(reasoning_tokens, 0) > 0;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }

    var events: [HermesSessionUsageEvent] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      let ts = sqlite3_column_double(statement, 0)
      let provider = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? "unknown"
      let baseURL = sqlite3_column_text(statement, 2).map { String(cString: $0) }
      events.append(
        HermesSessionUsageEvent(
          observedAt: Date(timeIntervalSince1970: ts),
          sourceName: provider,
          inputTokens: sqlite3_column_int64(statement, 3),
          outputTokens: sqlite3_column_int64(statement, 4),
          cacheTokens: sqlite3_column_int64(statement, 5),
          reasoningTokens: sqlite3_column_int64(statement, 6),
          requestCount: Int(sqlite3_column_int64(statement, 7)),
          billingBaseURL: baseURL
        )
      )
    }
    return events
  }

  private func prepare(_ sql: String) throws -> OpaquePointer? {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
      throw error("Failed to prepare Hermes SQLite statement.")
    }
    return statement
  }

  private func error(_ fallback: String) -> HermesUsageDataSourceError {
    let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? fallback
    return .queryFailed(message: message)
  }
}

private struct HermesSessionUsageEvent: UsageEventLike {
  let observedAt: Date
  let sourceName: String
  let inputTokens: Int64
  let outputTokens: Int64
  let cacheTokens: Int64
  let reasoningTokens: Int64
  let requestCount: Int
  let billingBaseURL: String?

  var totalTokens: Int64 {
    inputTokens + outputTokens + cacheTokens + reasoningTokens
  }
}

public enum HermesUsageDataSourceError: Error, Equatable {
  case openFailed(message: String)
  case queryFailed(message: String)
}
