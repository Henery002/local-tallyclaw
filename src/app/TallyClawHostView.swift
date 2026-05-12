import SwiftUI
import TallyClawCore
import TallyClawDataSources
import TallyClawLedger
import TallyClawUI

struct TallyClawHostView: View {
  @ObservedObject private var floatingPreferences: FloatingWindowPreferences
  @State private var snapshot = UsageSnapshot(
    today: .empty,
    week: .empty,
    month: .empty,
    lifetime: .empty,
    topSources: [],
    syncHealth: .syncing,
    observedAt: Date(timeIntervalSince1970: 0)
  )
  @State private var ledgerInitializationFailed = false
  @State private var refreshCadence = UsageRefreshCadence()

  private let sources: [any UsageDataSource] = [
    CockpitCodexStatsDataSource(),
    LocalAIGatewayUsageDataSource(),
    OpenClawUsageDataSource(),
    HermesUsageDataSource()
  ]
  private let ledger: SQLiteLedgerStore?

  init(floatingPreferences: FloatingWindowPreferences = FloatingWindowPreferences()) {
    _floatingPreferences = ObservedObject(wrappedValue: floatingPreferences)
    do {
      ledger = try SQLiteLedgerStore()
    } catch {
      ledger = nil
      _ledgerInitializationFailed = State(initialValue: true)
    }
  }

  var body: some View {
    TallyClawRootView(snapshot: snapshot, preferences: floatingPreferences)
      .task {
        while !Task.isCancelled {
          let nextDelay = await refreshSnapshot()
          try? await Task.sleep(for: .seconds(Int(nextDelay)))
        }
      }
  }

  private func refreshSnapshot() async -> TimeInterval {
    var snapshots: [UsageSnapshot] = []
    var sourceStatuses: [SourceReadStatus] = []
    var readFailed = ledgerInitializationFailed

    for result in await readSourceSnapshots() {
      let source = sources[result.index]
      switch result.outcome {
      case let .available(sourceSnapshot):
          snapshots.append(sourceSnapshot)
          sourceStatuses.append(
            SourceReadStatus(
              sourceID: source.id,
              displayName: source.displayName,
              state: .available,
              lastReadAt: result.lastReadAt,
              lastObservedAt: sourceSnapshot.observedAt,
              readDurationMilliseconds: result.readDurationMilliseconds
            )
          )
          do {
            try await ledger?.record(sourceSnapshot, sourceID: source.id)
            if let observationSource = source as? any UsageObservationDataSource,
               let ledger {
              let since = try await ledger.latestObservationDate(sourceID: source.id, confidence: "exact")
              let observations = try await observationSource.readObservations(since: since)
              try await ledger.recordObservations(observations)
            }
          } catch {
            readFailed = true
          }
      case .missing:
          sourceStatuses.append(
            SourceReadStatus(
              sourceID: source.id,
              displayName: source.displayName,
              state: .missing,
              lastReadAt: result.lastReadAt,
              readDurationMilliseconds: result.readDurationMilliseconds
            )
          )
      case let .failed(errorSummary):
        sourceStatuses.append(
          SourceReadStatus(
            sourceID: source.id,
            displayName: source.displayName,
            state: .failed,
            lastReadAt: result.lastReadAt,
            errorSummary: errorSummary,
            readDurationMilliseconds: result.readDurationMilliseconds
          )
        )
        readFailed = true
      }
    }

    if let ledger {
      do {
        try await ledger.recordSourceStatuses(sourceStatuses)
      } catch {
        readFailed = true
      }
      snapshot = await ledger.latestSnapshot()
      snapshot.syncHealth = readFailed ? .warning : sourceStatuses.syncHealth
    } else if !snapshots.isEmpty {
      snapshot = UsageSnapshot.merged(snapshots)
      snapshot.sourceStatuses = sourceStatuses
      snapshot.syncHealth = readFailed ? .warning : sourceStatuses.syncHealth
    }

    return refreshCadence.record(snapshot: snapshot, readFailed: readFailed)
  }

  private func readSourceSnapshots() async -> [SourceReadResult] {
    await withTaskGroup(of: SourceReadResult.self) { group in
      for (index, source) in sources.enumerated() {
        group.addTask {
          let lastReadAt = Date()
          let sourceReadStartedAt = Date()
          do {
            let snapshot = try await source.readSnapshot()
            return SourceReadResult(
              index: index,
              lastReadAt: lastReadAt,
              readDurationMilliseconds: Self.durationMilliseconds(since: sourceReadStartedAt),
              outcome: snapshot.map(SourceReadOutcome.available) ?? .missing
            )
          } catch {
            return SourceReadResult(
              index: index,
              lastReadAt: lastReadAt,
              readDurationMilliseconds: Self.durationMilliseconds(since: sourceReadStartedAt),
              outcome: .failed(Self.errorSummary(error))
            )
          }
        }
      }

      var results: [SourceReadResult] = []
      for await result in group {
        results.append(result)
      }
      return results.sorted { $0.index < $1.index }
    }
  }

  nonisolated private static func errorSummary(_ error: any Error) -> String {
    String(describing: error)
      .replacingOccurrences(of: "\n", with: " ")
      .prefix(160)
      .description
  }

  nonisolated private static func durationMilliseconds(since start: Date) -> Int {
    max(0, Int(Date().timeIntervalSince(start) * 1_000))
  }
}

private struct SourceReadResult: Sendable {
  let index: Int
  let lastReadAt: Date
  let readDurationMilliseconds: Int
  let outcome: SourceReadOutcome
}

private enum SourceReadOutcome: Sendable {
  case available(UsageSnapshot)
  case missing
  case failed(String)
}
