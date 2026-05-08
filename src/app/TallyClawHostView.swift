import SwiftUI
import TallyClawCore
import TallyClawDataSources
import TallyClawLedger
import TallyClawUI

struct TallyClawHostView: View {
  @State private var snapshot = UsageSnapshot.preview
  @State private var ledgerInitializationFailed = false

  private let sources: [any UsageDataSource] = [
    CockpitCodexStatsDataSource(),
    LocalAIGatewayUsageDataSource()
  ]
  private let ledger: SQLiteLedgerStore?

  init() {
    do {
      ledger = try SQLiteLedgerStore()
    } catch {
      ledger = nil
      _ledgerInitializationFailed = State(initialValue: true)
    }
  }

  var body: some View {
    TallyClawRootView(snapshot: snapshot)
      .task {
        while !Task.isCancelled {
          await refreshSnapshot()
          try? await Task.sleep(for: .seconds(5))
        }
      }
  }

  private func refreshSnapshot() async {
    var snapshots: [UsageSnapshot] = []
    var readFailed = ledgerInitializationFailed

    for source in sources {
      do {
        if let snapshot = try await source.readSnapshot() {
          snapshots.append(snapshot)
          try await ledger?.record(snapshot, sourceID: source.id)
        }
      } catch {
        readFailed = true
        continue
      }
    }

    if let ledger {
      snapshot = await ledger.latestSnapshot()
      if readFailed {
        snapshot.syncHealth = .warning
      }
    } else if !snapshots.isEmpty {
      snapshot = UsageSnapshot.merged(snapshots)
    }
  }
}
