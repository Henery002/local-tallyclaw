import Foundation
@testable import TallyClawDataSources
@testable import TallyClawCore

Task {
  let src = OpenClawUsageDataSource(now: { Date() })
  do {
    if let snapshot = try await src.readSnapshot() {
      print("Success. Latest observed: \(snapshot.observedAt), today tokens: \(snapshot.today.tokens.total)")
    } else {
      print("Returned nil")
    }
  } catch {
    print("Threw error: \(error)")
  }
  exit(0)
}
RunLoop.main.run()
