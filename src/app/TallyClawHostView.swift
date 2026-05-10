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
          await refreshSnapshot()
          try? await Task.sleep(for: .seconds(5))
        }
      }
  }

  private func refreshSnapshot() async {
    var snapshots: [UsageSnapshot] = []
    var sourceStatuses: [SourceReadStatus] = []
    var readFailed = ledgerInitializationFailed

    for source in sources {
      let lastReadAt = Date()
      do {
        if let sourceSnapshot = try await source.readSnapshot() {
          snapshots.append(sourceSnapshot)
          sourceStatuses.append(
            SourceReadStatus(
              sourceID: source.id,
              displayName: source.displayName,
              state: .available,
              lastReadAt: lastReadAt,
              lastObservedAt: sourceSnapshot.observedAt
            )
          )
          do {
            try await ledger?.record(sourceSnapshot, sourceID: source.id)
          } catch {
            readFailed = true
          }
        } else {
          sourceStatuses.append(
            SourceReadStatus(
              sourceID: source.id,
              displayName: source.displayName,
              state: .missing,
              lastReadAt: lastReadAt
            )
          )
        }
      } catch {
        sourceStatuses.append(
          SourceReadStatus(
            sourceID: source.id,
            displayName: source.displayName,
            state: .failed,
            lastReadAt: lastReadAt,
            errorSummary: Self.errorSummary(error)
          )
        )
        readFailed = true
        continue
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
  }

  private static func errorSummary(_ error: any Error) -> String {
    String(describing: error)
      .replacingOccurrences(of: "\n", with: " ")
      .prefix(160)
      .description
  }
}
