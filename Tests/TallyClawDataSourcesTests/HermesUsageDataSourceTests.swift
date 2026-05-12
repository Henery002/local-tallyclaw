import Foundation
import Testing
import TallyClawCore
import TallyClawDataSources

@Suite("hermes usage data source")
struct HermesUsageDataSourceTests {
  @Test("aggregates session token totals while excluding gateway-backed sessions")
  func aggregatesSessionTokenTotalsExcludingGatewaySessions() async throws {
    let rootURL = try makeHermesFixture()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let dataSource = HermesUsageDataSource(rootURL: rootURL, now: { now })

    let snapshot = try #require(await dataSource.readSnapshot())

    #expect(snapshot.today.tokens.total == 167)
    #expect(snapshot.today.tokens.input == 120)
    #expect(snapshot.today.tokens.output == 40)
    #expect(snapshot.today.tokens.cache == 10)
    #expect(snapshot.today.tokens.thinking == 7)
    #expect(snapshot.week.tokens.total == 282)
    #expect(snapshot.month.tokens.total == 282)
    #expect(snapshot.lifetime.tokens.total == 402)
    #expect(snapshot.today.requests.total == 3)
    #expect(snapshot.topSources.first?.name == "openai")
    #expect(snapshot.lifetimeStartedAt == Date(timeIntervalSince1970: 1_680_000_000))
    #expect(snapshot.syncHealth == .idle)
  }

  @Test("reads event-level observations from non-gateway sessions")
  func readsEventLevelObservationsFromNonGatewaySessions() async throws {
    let rootURL = try makeHermesFixture()
    let dataSource = HermesUsageDataSource(rootURL: rootURL)

    let observations = try await dataSource.readObservations(since: nil)

    #expect(observations.count == 3)
    #expect(observations.first?.sourceID == "hermes-usage")
    #expect(observations.first?.sourceEventID == "s1")
    #expect(observations.first?.sourceName == "cli")
    #expect(observations.first?.provider == "openai")
    #expect(observations.first?.model == "gpt-5.4")
    #expect(observations.first?.tokens.input == 120)
    #expect(observations.first?.tokens.output == 40)
    #expect(observations.first?.tokens.cache == 10)
    #expect(observations.first?.tokens.thinking == 7)
    #expect(observations.first?.requests.total == 3)
    #expect(observations.allSatisfy { !$0.sourceEventID.contains("@") })
    #expect(observations.allSatisfy { $0.model != "codex-default" })
  }

  @Test("reports missing required schema columns explicitly")
  func reportsMissingRequiredSchemaColumnsExplicitly() async throws {
    let rootURL = try makeHermesBrokenSchemaFixture()
    let dataSource = HermesUsageDataSource(rootURL: rootURL)

    do {
      _ = try await dataSource.readSnapshot()
      Issue.record("Expected schema mismatch error.")
    } catch HermesUsageDataSourceError.queryFailed(let message) {
      #expect(message.contains("missing required columns"))
      #expect(message.contains("input_tokens"))
      #expect(message.contains("output_tokens"))
    }
  }
}

private func makeHermesFixture() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let configURL = directory.appendingPathComponent("config.yaml")
  let databaseURL = directory.appendingPathComponent("state.db")

  let config = """
  custom_providers:
  - name: codex-default
    base_url: http://127.0.0.1:56267/v1
    api_key: lagw_hermes_redacted
    model: codex-default
    api_mode: chat_completions
  - name: scnet
    base_url: https://api.scnet.cn/api/llm/v1
    api_key: ''
    api_mode: chat_completions
  """

  try config.write(to: configURL, atomically: true, encoding: .utf8)

  let sql = """
  CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    source TEXT NOT NULL,
    user_id TEXT,
    model TEXT,
    model_config TEXT,
    system_prompt TEXT,
    parent_session_id TEXT,
    started_at REAL NOT NULL,
    ended_at REAL,
    end_reason TEXT,
    message_count INTEGER DEFAULT 0,
    tool_call_count INTEGER DEFAULT 0,
    input_tokens INTEGER DEFAULT 0,
    output_tokens INTEGER DEFAULT 0,
    cache_read_tokens INTEGER DEFAULT 0,
    cache_write_tokens INTEGER DEFAULT 0,
    reasoning_tokens INTEGER DEFAULT 0,
    billing_provider TEXT,
    billing_base_url TEXT,
    billing_mode TEXT,
    estimated_cost_usd REAL,
    actual_cost_usd REAL,
    cost_status TEXT,
    cost_source TEXT,
    pricing_version TEXT,
    title TEXT,
    api_call_count INTEGER DEFAULT 0
  );

  INSERT INTO sessions (
    id, source, model, started_at, ended_at,
    input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, reasoning_tokens,
    billing_provider, billing_base_url, api_call_count
  ) VALUES
  ('s1', 'cli', 'gpt-5.4', 1699999900, 1699999950, 120, 40, 10, 0, 7, 'openai', 'https://api.openai.com/v1', 3),
  ('s2', 'cli', 'qwen', 1699827200, 1699827250, 90, 20, 0, 0, 5, 'scnet', 'https://api.scnet.cn/api/llm/v1', 2),
  ('s3', 'cli', 'codex-default', 1699222400, 1699222450, 150, 30, 0, 0, 0, 'custom', 'http://127.0.0.1:56267/v1', 4),
  ('s4', 'cli', 'glm-4.7', 1680000000, 1680000050, 110, 10, 0, 0, 0, 'zai', 'https://open.bigmodel.cn/api/paas/v4', 1);
  """

  try runHermesSQLite(databaseURL: databaseURL, sql: sql)
  return directory
}

private func runHermesSQLite(databaseURL: URL, sql: String) throws {
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

private func makeHermesBrokenSchemaFixture() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let databaseURL = directory.appendingPathComponent("state.db")

  let sql = """
  CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    source TEXT NOT NULL,
    model TEXT,
    started_at REAL NOT NULL,
    ended_at REAL,
    billing_provider TEXT,
    billing_base_url TEXT,
    api_call_count INTEGER DEFAULT 0
  );
  """

  try runHermesSQLite(databaseURL: databaseURL, sql: sql)
  return directory
}
