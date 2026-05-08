import Foundation
import Testing
import TallyClawCore
import TallyClawDataSources

@Suite("openclaw usage data source")
struct OpenClawUsageDataSourceTests {
  @Test("aggregates usage ledger events while excluding gateway-backed providers")
  func aggregatesUsageLedgerEventsExcludingGatewayProviders() async throws {
    let rootURL = try makeOpenClawFixture()
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let dataSource = OpenClawUsageDataSource(rootURL: rootURL, now: { now })

    let snapshot = try #require(await dataSource.readSnapshot())

    #expect(snapshot.today.tokens.total == 165)
    #expect(snapshot.today.tokens.input == 120)
    #expect(snapshot.today.tokens.output == 45)
    #expect(snapshot.week.tokens.total == 257)
    #expect(snapshot.month.tokens.total == 325)
    #expect(snapshot.lifetime.tokens.total == 325)
    #expect(snapshot.today.requests.total == 2)
    #expect(snapshot.topSources.first?.name == "scnet")
    #expect(snapshot.syncHealth == .idle)
  }
}

private func makeOpenClawFixture() throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  try FileManager.default.createDirectory(
    at: directory.appendingPathComponent("agents/main/sessions", isDirectory: true),
    withIntermediateDirectories: true
  )

  let configURL = directory.appendingPathComponent("openclaw.json")
  let ledgerURL = directory.appendingPathComponent("agents/main/sessions/.usage-ledger.json")

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

  try config.write(to: configURL, atomically: true, encoding: .utf8)
  try ledger.write(to: ledgerURL, atomically: true, encoding: .utf8)
  return directory
}
