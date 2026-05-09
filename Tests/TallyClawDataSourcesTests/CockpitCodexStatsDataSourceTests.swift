import Foundation
import Testing
import TallyClawCore
import TallyClawDataSources

@Suite("cockpit codex stats data source")
struct CockpitCodexStatsDataSourceTests {
  @Test("reads aggregate totals without exposing account identity")
  func readsAggregateTotalsWithoutExposingAccountIdentity() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_200)
    let statsURL = try makeFixtureStatsFile(dailySince: 1_700_000_000_000)
    let dataSource = CockpitCodexStatsDataSource(statsURL: statsURL, now: { now })

    let snapshot = try #require(try await dataSource.readSnapshot())

    #expect(dataSource.accessPolicy.allowsSourceMutation == false)
    #expect(snapshot.today.requests.total == 10)
    #expect(snapshot.today.requests.succeeded == 9)
    #expect(snapshot.today.requests.failed == 1)
    #expect(snapshot.today.requests.averageLatencyMilliseconds == 120)
    #expect(snapshot.today.tokens.input == 1_000)
    #expect(snapshot.today.tokens.output == 200)
    #expect(snapshot.today.tokens.cache == 300)
    #expect(snapshot.today.tokens.thinking == 40)
    #expect(snapshot.week.tokens.total == 2_580)
    #expect(snapshot.month.requests.total == 40)
    #expect(snapshot.lifetime.requests.total == 100)
    #expect(snapshot.topSources == [SourceShare(name: "cockpit", percent: 100)])
    #expect(snapshot.syncHealth == .idle)
  }

  @Test("discards daily window when cockpit since is before start of today")
  func discardsStaleDailyWindow() async throws {
    // dailySince is 48 hours before `now` – a stale rolling window
    let now = Date(timeIntervalSince1970: 1_700_172_800)  // ~2 days later
    let statsURL = try makeFixtureStatsFile(dailySince: 1_700_000_000_000)
    let dataSource = CockpitCodexStatsDataSource(
      statsURL: statsURL,
      calendar: {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return c
      }(),
      now: { now }
    )

    let snapshot = try #require(try await dataSource.readSnapshot())

    // Daily window spans before today so should be discarded
    #expect(snapshot.today.tokens.input == 0)
    #expect(snapshot.today.requests.total == 0)
    // Lifetime is always available regardless of window validation
    #expect(snapshot.lifetime.requests.total == 100)
  }
}

private func makeFixtureStatsFile(dailySince: Int64 = 1_700_000_000_000) throws -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let statsURL = directory.appendingPathComponent("codex_local_access_stats.json")

  let json = """
  {
    "since": 1700000000000,
    "updatedAt": 1700000100000,
    "daily": {
      "since": \(dailySince),
      "updatedAt": 1700000100000,
      "totals": {
        "requestCount": 10,
        "successCount": 9,
        "failureCount": 1,
        "totalLatencyMs": 1200,
        "inputTokens": 1000,
        "outputTokens": 200,
        "totalTokens": 1200,
        "cachedTokens": 300,
        "reasoningTokens": 40
      }
    },
    "weekly": {
      "since": 1699500000000,
      "totals": {
        "requestCount": 20,
        "successCount": 18,
        "failureCount": 2,
        "totalLatencyMs": 2600,
        "inputTokens": 2000,
        "outputTokens": 500,
        "totalTokens": 2500,
        "cachedTokens": 500,
        "reasoningTokens": 80
      }
    },
    "monthly": {
      "since": 1697500000000,
      "totals": {
        "requestCount": 40,
        "successCount": 37,
        "failureCount": 3,
        "totalLatencyMs": 5400,
        "inputTokens": 4000,
        "outputTokens": 900,
        "totalTokens": 4900,
        "cachedTokens": 800,
        "reasoningTokens": 120
      }
    },
    "totals": {
      "requestCount": 100,
      "successCount": 95,
      "failureCount": 5,
      "totalLatencyMs": 10000,
      "inputTokens": 9000,
      "outputTokens": 1500,
      "totalTokens": 10500,
      "cachedTokens": 1200,
      "reasoningTokens": 200
    },
    "accounts": [
      {
        "accountId": "secret-id",
        "email": "private@example.test",
        "usage": {
          "requestCount": 100,
          "successCount": 95,
          "failureCount": 5,
          "totalLatencyMs": 10000,
          "inputTokens": 9000,
          "outputTokens": 1500,
          "totalTokens": 10500,
          "cachedTokens": 1200,
          "reasoningTokens": 200
        }
      }
    ]
  }
  """

  try json.write(to: statsURL, atomically: true, encoding: .utf8)
  return statsURL
}
