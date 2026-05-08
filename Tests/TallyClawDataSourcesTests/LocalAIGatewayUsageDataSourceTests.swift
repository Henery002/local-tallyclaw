import Foundation
import Testing
import TallyClawDataSources

@Suite("local-ai-gateway usage data source")
struct LocalAIGatewayUsageDataSourceTests {
  @Test("aggregates inference usage events from a read-only SQLite database")
  func aggregatesInferenceUsageEventsFromReadOnlySQLiteDatabase() async throws {
    let databaseURL = try makeFixtureDatabase()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let dataSource = LocalAIGatewayUsageDataSource(databaseURL: databaseURL, now: { now })

    let snapshot = try #require(try await dataSource.readSnapshot())

    #expect(dataSource.accessPolicy.allowsSourceMutation == false)
    #expect(dataSource.accessPolicy.allowsCredentialRefresh == false)
    #expect(snapshot.today.requests.total == 2)
    #expect(snapshot.today.requests.succeeded == 1)
    #expect(snapshot.today.requests.failed == 1)
    #expect(snapshot.today.requests.averageLatencyMilliseconds == 300)
    #expect(snapshot.today.tokens.input == 300)
    #expect(snapshot.today.tokens.output == 90)
    #expect(snapshot.today.tokens.cache == 15)
    #expect(snapshot.today.tokens.thinking == 7)
    #expect(snapshot.week.requests.total == 3)
    #expect(snapshot.month.requests.total == 4)
    #expect(snapshot.lifetime.requests.total == 5)
    #expect(snapshot.topSources.first?.name == "codex")
    #expect(snapshot.topSources.first?.percent == 100)
  }
}

private func makeFixtureDatabase() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let databaseURL = directory.appendingPathComponent("gateway.db")

  let sql = """
  CREATE TABLE inference_usage_events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp INTEGER NOT NULL,
    session_id TEXT,
    account_id TEXT,
    email TEXT,
    client_tag TEXT,
    provider_id TEXT NOT NULL,
    model_alias TEXT NOT NULL,
    upstream_model_id TEXT,
    ok INTEGER NOT NULL,
    stream INTEGER NOT NULL,
    latency_ms INTEGER NOT NULL,
    input_tokens INTEGER NOT NULL,
    output_tokens INTEGER NOT NULL,
    total_tokens INTEGER NOT NULL,
    cached_tokens INTEGER NOT NULL,
    reasoning_tokens INTEGER NOT NULL,
    cached_tokens_present INTEGER NOT NULL DEFAULT 0,
    reasoning_tokens_present INTEGER NOT NULL DEFAULT 0,
    source_kind TEXT,
    source_event_key TEXT
  );

  INSERT INTO inference_usage_events (
    timestamp, client_tag, provider_id, model_alias, ok, stream, latency_ms,
    input_tokens, output_tokens, total_tokens, cached_tokens, reasoning_tokens,
    cached_tokens_present, reasoning_tokens_present, source_event_key
  ) VALUES
  (1699999900000, 'codex', 'openai', 'gpt-5', 1, 1, 200, 100, 50, 150, 10, 5, 1, 1, 'a'),
  (1699999800000, 'codex', 'openai', 'gpt-5', 0, 0, 400, 200, 40, 240, 5, 2, 1, 1, 'b'),
  (1699827200000, 'gateway', 'anthropic', 'claude', 1, 0, 600, 300, 70, 370, 0, 0, 0, 0, 'c'),
  (1699222400000, 'gateway', 'openai', 'gpt-4', 1, 0, 800, 400, 80, 480, 0, 0, 0, 0, 'd'),
  (1680000000000, 'legacy', 'openai', 'gpt-4', 1, 0, 1000, 500, 90, 590, 0, 0, 0, 0, 'e');
  """

  try runSQLite(databaseURL: databaseURL, sql: sql)
  return databaseURL
}

private func runSQLite(databaseURL: URL, sql: String) throws {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
  process.arguments = [databaseURL.path]

  let input = Pipe()
  process.standardInput = input
  try process.run()
  input.fileHandleForWriting.write(Data(sql.utf8))
  try input.fileHandleForWriting.close()
  process.waitUntilExit()

  if process.terminationStatus != 0 {
    throw CocoaError(.fileWriteUnknown)
  }
}
