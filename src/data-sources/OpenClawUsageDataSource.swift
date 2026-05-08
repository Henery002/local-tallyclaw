import Foundation
import TallyClawCore

public struct OpenClawUsageDataSource: UsageDataSource {
  public let id = "openclaw-usage"
  public let displayName = "openclaw"
  public let accessPolicy = SourceAccessPolicy.default

  private let rootURL: URL
  private let now: @Sendable () -> Date
  private let calendar: Calendar

  public init(
    rootURL: URL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".openclaw"),
    calendar: Calendar = .current,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.rootURL = rootURL
    self.calendar = calendar
    self.now = now
  }

  public func readSnapshot() async throws -> UsageSnapshot? {
    guard FileManager.default.fileExists(atPath: rootURL.path) else {
      return nil
    }

    let ledgerURLs = try findUsageLedgerURLs()
    guard !ledgerURLs.isEmpty else {
      return nil
    }

    let gatewayBackedProviders = try readGatewayBackedProviders()
    let events = try ledgerURLs.flatMap { try readEvents(from: $0, excludingProviders: gatewayBackedProviders) }
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

  private func findUsageLedgerURLs() throws -> [URL] {
    let agentsURL = rootURL.appendingPathComponent("agents")
    guard FileManager.default.fileExists(atPath: agentsURL.path) else {
      return []
    }

    let childURLs = try FileManager.default.contentsOfDirectory(
      at: agentsURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    return childURLs.map {
      $0.appendingPathComponent("sessions/.usage-ledger.json")
    }.filter {
      FileManager.default.fileExists(atPath: $0.path)
    }
  }

  private func readGatewayBackedProviders() throws -> Set<String> {
    let configURL = rootURL.appendingPathComponent("openclaw.json")
    guard FileManager.default.fileExists(atPath: configURL.path) else {
      return []
    }

    let data = try Data(contentsOf: configURL, options: [.mappedIfSafe])
    let config = try JSONDecoder().decode(OpenClawConfigFile.self, from: data)
    return Set(config.models.providers.compactMap { key, provider in
      isLocalAIGatewayURL(provider.baseURL) ? key : nil
    })
  }

  private func readEvents(from ledgerURL: URL, excludingProviders: Set<String>) throws -> [OpenClawUsageEvent] {
    let data = try Data(contentsOf: ledgerURL, options: [.mappedIfSafe])
    let ledger = try JSONDecoder().decode(OpenClawUsageLedger.self, from: data)
    return ledger.events.compactMap { key, event in
      guard !excludingProviders.contains(event.provider) else { return nil }
      guard event.usage.total > 0 else { return nil }
      return OpenClawUsageEvent(
        dedupeKey: key,
        observedAt: Date(timeIntervalSince1970: Double(event.ts) / 1_000),
        sourceName: event.provider,
        inputTokens: event.usage.input,
        outputTokens: event.usage.output,
        cacheTokens: event.usage.cacheRead + event.usage.cacheWrite,
        reasoningTokens: 0
      )
    }
  }
}

private struct OpenClawConfigFile: Decodable {
  let models: OpenClawModelsConfig
}

private struct OpenClawModelsConfig: Decodable {
  let providers: [String: OpenClawProviderConfig]
}

private struct OpenClawProviderConfig: Decodable {
  let baseURL: String?

  enum CodingKeys: String, CodingKey {
    case baseURL = "baseUrl"
  }
}

private struct OpenClawUsageLedger: Decodable {
  let events: [String: OpenClawLedgerEvent]
}

private struct OpenClawLedgerEvent: Decodable {
  let ts: Int64
  let usage: OpenClawUsageCounters
  let provider: String
}

private struct OpenClawUsageCounters: Decodable {
  let input: Int64
  let output: Int64
  let cacheRead: Int64
  let cacheWrite: Int64
  let total: Int64
}

private struct OpenClawUsageEvent: UsageEventLike {
  let dedupeKey: String
  let observedAt: Date
  let sourceName: String
  let requestCount: Int = 1
  let inputTokens: Int64
  let outputTokens: Int64
  let cacheTokens: Int64
  let reasoningTokens: Int64

  var totalTokens: Int64 {
    inputTokens + outputTokens + cacheTokens + reasoningTokens
  }
}
