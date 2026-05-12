import Foundation
import TallyClawCore

public struct OpenClawUsageDataSource: UsageObservationDataSource {
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

    let events = try collectUsageEvents()

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
      observedAt: observedAt,
      lifetimeStartedAt: Self.earliestValidEventDate(events),
      lifetimeStartedAtLabel: "openclaw"
    )
  }

  public func readObservations(since startDate: Date?) async throws -> [UsageObservation] {
    guard FileManager.default.fileExists(atPath: rootURL.path) else {
      return []
    }

    return try collectUsageEvents()
      .filter { event in
        event.totalTokens > 0 && (startDate.map { event.observedAt >= $0 } ?? true)
      }
      .sorted {
        if $0.observedAt == $1.observedAt {
          return $0.sourceEventID > $1.sourceEventID
        }
        return $0.observedAt > $1.observedAt
      }
      .map { event in
        UsageObservation(
          sourceID: id,
          sourceEventID: event.sourceEventID,
          sourceName: event.observationSourceName,
          provider: event.provider,
          model: event.model,
          observedAt: event.observedAt,
          tokens: TokenBreakdown(
            input: event.inputTokens,
            output: event.outputTokens,
            cache: event.cacheTokens,
            thinking: event.reasoningTokens
          ),
          requests: RequestStats(total: 1, succeeded: 1, failed: 0)
        )
      }
  }

  private func collectUsageEvents() throws -> [OpenClawUsageEvent] {
    let gatewayBackedProviders = try readGatewayBackedProviders()
    var dedupeKeys = Set<String>()
    var events: [OpenClawUsageEvent] = []

    let ledgerURLs = try findUsageLedgerURLs()
    for url in ledgerURLs {
      let ledgerEvents = try readLedgerEvents(from: url, excludingProviders: gatewayBackedProviders)
      for event in ledgerEvents where dedupeKeys.insert(event.dedupeKey).inserted {
        events.append(event)
      }
    }

    let trajectoryEvents = try readTrajectoryEvents(excludingProviders: gatewayBackedProviders)
    for event in trajectoryEvents where dedupeKeys.insert(event.dedupeKey).inserted {
      events.append(event)
    }

    return events
  }

  private static func earliestValidEventDate(_ events: [OpenClawUsageEvent]) -> Date {
    events
      .map(\.observedAt)
      .filter { $0 > UsageSnapshot.unknownLifetimeStartDate }
      .min() ?? UsageSnapshot.unknownLifetimeStartDate
  }

  // MARK: - Legacy usage-ledger.json

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

  private func readLedgerEvents(from ledgerURL: URL, excludingProviders: Set<String>) throws -> [OpenClawUsageEvent] {
    let data = try Data(contentsOf: ledgerURL, options: [.mappedIfSafe])
    let ledger = try JSONDecoder().decode(OpenClawUsageLedger.self, from: data)
    return ledger.events.compactMap { key, event in
      guard let provider = event.provider, !excludingProviders.contains(provider) else { return nil }
      guard event.usage.total > 0 else { return nil }
      let agentName = agentName(forLedgerURL: ledgerURL)
      let model = event.model ?? provider
      let dedupeKey = "ledger:\(key)"
      return OpenClawUsageEvent(
        sourceEventID: dedupeKey,
        dedupeKey: dedupeKey,
        observedAt: Date(timeIntervalSince1970: Double(event.ts) / 1_000),
        sourceName: model,
        observationSourceName: agentName,
        provider: provider,
        model: model,
        requestCount: 1,
        inputTokens: event.usage.input,
        outputTokens: event.usage.output,
        cacheTokens: event.usage.cacheRead + event.usage.cacheWrite,
        reasoningTokens: 0
      )
    }
  }

  private func agentName(forLedgerURL ledgerURL: URL) -> String {
    let components = ledgerURL.pathComponents
    guard let sessionsIndex = components.lastIndex(of: "sessions"),
          sessionsIndex >= 1
    else {
      return "openclaw"
    }
    return components[sessionsIndex - 1]
  }

  // MARK: - Trajectory .jsonl files

  private func readTrajectoryEvents(excludingProviders: Set<String>) throws -> [OpenClawUsageEvent] {
    let agentsURL = rootURL.appendingPathComponent("agents")
    guard FileManager.default.fileExists(atPath: agentsURL.path) else {
      return []
    }

    let agentDirs = try FileManager.default.contentsOfDirectory(
      at: agentsURL,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    var events: [OpenClawUsageEvent] = []

    for agentDir in agentDirs {
      // Read from both active sessions/ and any sessions.bak.* directories
      // so that historical data from session rotations is not lost.
      let sessionsDirs = try sessionsDirectories(in: agentDir)
      for sessionsDir in sessionsDirs {
        let trajectoryFiles = try findTrajectoryFiles(in: sessionsDir)
        for trajectoryURL in trajectoryFiles {
          let fileEvents = try readTrajectoryFile(
            at: trajectoryURL,
            agentName: agentDir.lastPathComponent,
            excludingProviders: excludingProviders
          )
          events.append(contentsOf: fileEvents)
        }
      }
    }

    return events
  }

  private func sessionsDirectories(in agentDir: URL) throws -> [URL] {
    let contents = try FileManager.default.contentsOfDirectory(
      at: agentDir,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    return contents.filter { url in
      let name = url.lastPathComponent
      guard name == "sessions" || name.hasPrefix("sessions.bak.") else { return false }
      return (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
  }

  private func findTrajectoryFiles(in sessionsDir: URL) throws -> [URL] {
    let contents = try FileManager.default.contentsOfDirectory(
      at: sessionsDir,
      includingPropertiesForKeys: nil,
      options: [.skipsHiddenFiles]
    )

    return contents.filter { $0.lastPathComponent.hasSuffix(".trajectory.jsonl") }
  }

  private func readTrajectoryFile(
    at url: URL,
    agentName: String,
    excludingProviders: Set<String>
  ) throws -> [OpenClawUsageEvent] {
    let data = try Data(contentsOf: url, options: [.mappedIfSafe])
    guard let content = String(data: data, encoding: .utf8) else { return [] }

    var events: [OpenClawUsageEvent] = []

    for line in content.split(separator: "\n") where !line.isEmpty {
      guard let lineData = line.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
            let type = obj["type"] as? String,
            type == "model.completed" || type == "prompt.submitted"
      else { continue }

      let provider = obj["provider"] as? String ?? "unknown"
      guard !excludingProviders.contains(provider) else { continue }

      let isPrompt = (type == "prompt.submitted")
      
      let input: Int64
      let output: Int64
      let cacheRead: Int64
      let requestCount: Int
      
      if isPrompt {
        input = 0
        output = 0
        cacheRead = 0
        requestCount = 1
      } else {
        // Extract usage from data.usage (primary) or top-level usage (fallback)
        let usage: [String: Any]?
        if let dataDict = obj["data"] as? [String: Any] {
          usage = dataDict["usage"] as? [String: Any]
        } else {
          usage = obj["usage"] as? [String: Any]
        }
  
        guard let usage,
              let total = usage["total"] as? Int64, total > 0
        else { continue }
        
        input = usage["input"] as? Int64 ?? 0
        output = usage["output"] as? Int64 ?? 0
        cacheRead = usage["cacheRead"] as? Int64 ?? 0
        requestCount = 0
      }

      // Build a stable deduplication key.
      let traceId = obj["traceId"] as? String ?? url.deletingPathExtension().lastPathComponent
      let seq = obj["seq"] as? Int ?? 0
      let runId = obj["runId"] as? String ?? "\(obj["ts"] ?? "")"
      let suffix = isPrompt ? "prompt" : "model"
      let dedupeKey = "traj:\(traceId):\(runId):\(seq):\(suffix)"

      // Parse timestamp – trajectory uses ISO 8601 string
      let observedAt: Date
      if let tsString = obj["ts"] as? String {
        observedAt = Self.parseISO8601(tsString) ?? Date(timeIntervalSince1970: 0)
      } else if let tsNumber = obj["ts"] as? Double {
        observedAt = Date(timeIntervalSince1970: tsNumber / 1_000)
      } else {
        observedAt = Date(timeIntervalSince1970: 0)
      }

      let modelId = obj["modelId"] as? String ?? provider

      events.append(OpenClawUsageEvent(
        sourceEventID: dedupeKey,
        dedupeKey: dedupeKey,
        observedAt: observedAt,
        sourceName: modelId,
        observationSourceName: agentName,
        provider: provider,
        model: modelId,
        requestCount: requestCount,
        inputTokens: input,
        outputTokens: output,
        cacheTokens: cacheRead,
        reasoningTokens: 0
      ))
    }

    return events
  }

  // MARK: - Gateway provider detection

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

  // MARK: - ISO 8601 parsing

  nonisolated(unsafe) private static let iso8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  nonisolated(unsafe) private static let iso8601FormatterNoFraction: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()

  private static func parseISO8601(_ string: String) -> Date? {
    iso8601Formatter.date(from: string) ?? iso8601FormatterNoFraction.date(from: string)
  }
}

// MARK: - Decodable models (legacy usage-ledger)

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
  let provider: String?
  let model: String?
}

private struct OpenClawUsageCounters: Decodable {
  let input: Int64
  let output: Int64
  let cacheRead: Int64
  let cacheWrite: Int64
  let total: Int64
}

// MARK: - Unified event model

private struct OpenClawUsageEvent: UsageEventLike {
  let sourceEventID: String
  let dedupeKey: String
  let observedAt: Date
  let sourceName: String
  let observationSourceName: String
  let provider: String
  let model: String
  let requestCount: Int
  let inputTokens: Int64
  let outputTokens: Int64
  let cacheTokens: Int64
  let reasoningTokens: Int64

  var totalTokens: Int64 {
    inputTokens + outputTokens + cacheTokens + reasoningTokens
  }
}
