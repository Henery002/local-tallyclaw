import Foundation
import Testing
import TallyClawCore
import TallyClawDataSources

@Suite("openclaw usage data source")
struct OpenClawUsageDataSourceTests {
  @Test("aggregates usage ledger and trajectory events while excluding gateway-backed providers")
  func aggregatesUsageLedgerAndTrajectoryEventsExcludingGatewayProviders() async throws {
    let rootURL = try makeOpenClawFixture()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let dataSource = OpenClawUsageDataSource(rootURL: rootURL, now: { now })

    let snapshot = try #require(await dataSource.readSnapshot())

    // Ledger (scnet): input=120, output=45, total=165 (session-a:msg-1 and msg-2)
    // Trajectory (mimo): input=5000, output=200, cache=1000, total=5200 (cache not in total)
    // Total for today: input=5120, output=245, cache=1000, total=5365
    #expect(snapshot.today.tokens.total == 5365)
    #expect(snapshot.today.tokens.input == 5120)
    #expect(snapshot.today.tokens.output == 245)
    #expect(snapshot.today.tokens.cache == 1000)
    
    // Ledger month total = 325
    // Trajectory month total = 5200 (only today)
    // Combined month total = 5525
    #expect(snapshot.month.tokens.total == 5525)
    #expect(snapshot.lifetime.tokens.total == 5525)
    
    // Ledger requests = 2
    // Trajectory requests = 1
    #expect(snapshot.today.requests.total == 3)
    
    #expect(snapshot.lifetimeStartedAt == Date(timeIntervalSince1970: 1_699_222_400))
    #expect(snapshot.syncHealth == .idle)
  }

  @Test("reads event-level observations from ledger and trajectory records")
  func readsEventLevelObservationsFromLedgerAndTrajectoryRecords() async throws {
    let rootURL = try makeOpenClawFixture()
    let dataSource = OpenClawUsageDataSource(rootURL: rootURL)

    let observations = try await dataSource.readObservations(since: nil)

    #expect(observations.count == 5)
    #expect(observations.first?.sourceID == "openclaw-usage")
    #expect(observations.first?.sourceEventID == "traj:test-trace:test-run:5:model")
    #expect(observations.first?.sourceName == "main")
    #expect(observations.first?.provider == "mimo")
    #expect(observations.first?.model == "mimo-pro")
    #expect(observations.first?.tokens.input == 5000)
    #expect(observations.first?.tokens.output == 200)
    #expect(observations.first?.tokens.cache == 1000)
    #expect(observations.first?.requests.total == 1)
    #expect(observations.allSatisfy { !$0.sourceEventID.contains("@") })
    #expect(observations.allSatisfy { $0.provider != "codex-default" })
  }

  @Test("skips malformed legacy ledger events while keeping valid records")
  func skipsMalformedLegacyLedgerEventsWhileKeepingValidRecords() async throws {
    let rootURL = try makeOpenClawFixtureWithMalformedLedgerEvent()
    let dataSource = OpenClawUsageDataSource(rootURL: rootURL)

    let snapshot = try #require(await dataSource.readSnapshot())
    let observations = try await dataSource.readObservations(since: nil)

    #expect(snapshot.lifetime.tokens.total == 25)
    #expect(snapshot.lifetime.requests.total == 1)
    #expect(observations.count == 1)
    #expect(observations.first?.sourceEventID == "ledger:good-event")
  }
}

private func makeOpenClawFixture() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  
  let sessionsDir = directory.appendingPathComponent("agents/main/sessions", isDirectory: true)
  let opsSessionsDir = directory.appendingPathComponent("agents/ops/sessions.bak.1", isDirectory: true)
  try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(at: opsSessionsDir, withIntermediateDirectories: true)

  let configURL = directory.appendingPathComponent("openclaw.json")
  let ledgerURL = sessionsDir.appendingPathComponent(".usage-ledger.json")
  let trajectoryURL = sessionsDir.appendingPathComponent("test-session.trajectory.jsonl")
  let excludedTrajectoryURL = opsSessionsDir.appendingPathComponent("excluded.trajectory.jsonl")

  let config = """
  {
    "models": {
      "providers": {
        "scnet": {
          "baseUrl": "https://api.scnet.cn/api/llm/v1",
          "models": [{ "id": "Qwen3-235B-A22B", "name": "Qwen3-235B-A22B" }]
        },
        "codex-default": {
          "baseUrl": "http://127.0.0.1:56267/v1",
          "models": [{ "id": "codex-default", "name": "codex-default (Codex Gateway)" }]
        }
      }
    }
  }
  """

  let ledger = """
  {
    "version": 1,
    "updatedAt": 1700000000000,
    "events": {
      "session-a:msg-1": {
        "sessionId": "session-a",
        "messageId": "msg-1",
        "ts": 1699999900000,
        "usage": { "input": 100, "output": 40, "cacheRead": 0, "cacheWrite": 0, "total": 140 },
        "provider": "scnet",
        "model": "Qwen3-235B-A22B"
      },
      "session-a:msg-2": {
        "sessionId": "session-a",
        "messageId": "msg-2",
        "ts": 1699999800000,
        "usage": { "input": 20, "output": 5, "cacheRead": 0, "cacheWrite": 0, "total": 25 },
        "provider": "scnet",
        "model": "Qwen3-235B-A22B"
      },
      "session-a:msg-3": {
        "sessionId": "session-a",
        "messageId": "msg-3",
        "ts": 1699827200000,
        "usage": { "input": 80, "output": 12, "cacheRead": 0, "cacheWrite": 0, "total": 92 },
        "provider": "scnet",
        "model": "Qwen3-235B-A22B"
      },
      "session-b:msg-1": {
        "sessionId": "session-b",
        "messageId": "msg-1",
        "ts": 1699222400000,
        "usage": { "input": 60, "output": 8, "cacheRead": 0, "cacheWrite": 0, "total": 68 },
        "provider": "scnet",
        "model": "Qwen3-235B-A22B"
      },
      "session-c:msg-1": {
        "sessionId": "session-c",
        "messageId": "msg-1",
        "ts": 1699999700000,
        "usage": { "input": 999, "output": 1, "cacheRead": 0, "cacheWrite": 0, "total": 1000 },
        "provider": "codex-default",
        "model": "codex-default"
      }
    }
  }
  """

  let trajectory = """
  {"type":"session.started","ts":"2023-11-14T22:13:00Z"}
  {"type":"prompt.submitted","ts":"2023-11-14T22:13:02Z","traceId":"test-trace","seq":5,"runId":"test-run"}
  {"type":"model.completed","ts":"2023-11-14T22:13:20.000Z","provider":"mimo","modelId":"mimo-pro","traceId":"test-trace","seq":5,"runId":"test-run","data":{"usage":{"input":5000,"output":200,"cacheRead":1000,"total":6200}}}
  {"type":"trace.artifacts","ts":"2023-11-14T22:13:20.000Z","usage":{"input":5000,"output":200,"cacheRead":1000,"total":6200}}
  """
  
  let excludedTrajectory = """
  {"type":"model.completed","ts":"2023-11-14T22:13:20.000Z","provider":"codex-default","modelId":"codex","traceId":"exc-trace","seq":1,"data":{"usage":{"input":100,"output":10,"total":110}}}
  """

  try config.write(to: configURL, atomically: true, encoding: .utf8)
  try ledger.write(to: ledgerURL, atomically: true, encoding: .utf8)
  try trajectory.write(to: trajectoryURL, atomically: true, encoding: .utf8)
  try excludedTrajectory.write(to: excludedTrajectoryURL, atomically: true, encoding: .utf8)
  return directory
}

private func makeOpenClawFixtureWithMalformedLedgerEvent() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

  let sessionsDir = directory.appendingPathComponent("agents/main/sessions", isDirectory: true)
  try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
  let ledgerURL = sessionsDir.appendingPathComponent(".usage-ledger.json")

  let ledger = """
  {
    "version": 1,
    "updatedAt": 1700000000000,
    "events": {
      "bad-event": {
        "ts": 1699999900000,
        "usage": { "input": 900, "output": 100, "cacheRead": 0, "cacheWrite": 0, "total": 1000 }
      },
      "good-event": {
        "ts": 1699999800000,
        "usage": { "input": 20, "output": 5, "cacheRead": 0, "cacheWrite": 0, "total": 25 },
        "provider": "scnet",
        "model": "Qwen3-235B-A22B"
      }
    }
  }
  """

  try ledger.write(to: ledgerURL, atomically: true, encoding: .utf8)
  return directory
}
