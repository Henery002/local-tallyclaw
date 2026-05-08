import Foundation
import TallyClawCore

struct UsageWindowSupport {
  let now: Date
  let calendar: Calendar

  var todayStart: Date {
    calendar.startOfDay(for: now)
  }

  var trailing7DaysStart: Date {
    now.addingTimeInterval(-7 * 24 * 60 * 60)
  }

  var trailing30DaysStart: Date {
    now.addingTimeInterval(-30 * 24 * 60 * 60)
  }

  func periodStats(for events: [UsageEventLike], since start: Date?) -> UsagePeriodStats {
    let filtered = events.filter { event in
      guard let start else { return true }
      return event.observedAt >= start
    }

    let total = filtered.reduce(into: TokenBreakdown(input: 0, output: 0, cache: 0, thinking: 0)) { result, event in
      result.input += event.inputTokens
      result.output += event.outputTokens
      result.cache += event.cacheTokens
      result.thinking += event.reasoningTokens
    }

    let requests = filtered.reduce(0) { $0 + $1.requestCount }
    return UsagePeriodStats(
      tokens: total,
      requests: RequestStats(total: requests, succeeded: requests, failed: 0, averageLatencyMilliseconds: 0)
    )
  }

  func topSources(for events: [UsageEventLike], since start: Date?) -> [SourceShare] {
    let filtered = events.filter { event in
      guard let start else { return true }
      return event.observedAt >= start
    }

    let totals = filtered.reduce(into: [String: Int64]()) { result, event in
      result[event.sourceName, default: 0] += event.totalTokens
    }

    let ranked = totals.sorted { lhs, rhs in
      if lhs.value == rhs.value { return lhs.key < rhs.key }
      return lhs.value > rhs.value
    }.prefix(3)

    let total = ranked.reduce(Int64(0)) { $0 + $1.value }
    guard total > 0 else { return [] }

    return ranked.map { item in
      SourceShare(name: item.key, percent: Int((Double(item.value) / Double(total) * 100).rounded()))
    }
  }
}

protocol UsageEventLike {
  var observedAt: Date { get }
  var sourceName: String { get }
  var requestCount: Int { get }
  var inputTokens: Int64 { get }
  var outputTokens: Int64 { get }
  var cacheTokens: Int64 { get }
  var reasoningTokens: Int64 { get }
  var totalTokens: Int64 { get }
}

func isLocalAIGatewayURL(_ rawURL: String?) -> Bool {
  guard let rawURL, let url = URL(string: rawURL), let host = url.host?.lowercased() else {
    return false
  }
  let port = url.port ?? (url.scheme == "https" ? 443 : 80)
  return (host == "127.0.0.1" || host == "localhost") && [8787, 56267].contains(port)
}
