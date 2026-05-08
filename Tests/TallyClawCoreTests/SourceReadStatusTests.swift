import Foundation
import Testing
import TallyClawCore

@Suite("Source read status")
struct SourceReadStatusTests {
  @Test("summarizes failed sources as warning")
  func summarizesFailedSourcesAsWarning() {
    let statuses = [
      SourceReadStatus(
        sourceID: "cockpit",
        displayName: "cockpit tools",
        state: .available,
        lastReadAt: Date(timeIntervalSince1970: 100),
        lastObservedAt: Date(timeIntervalSince1970: 90)
      ),
      SourceReadStatus(
        sourceID: "gateway",
        displayName: "local-ai-gateway",
        state: .failed,
        lastReadAt: Date(timeIntervalSince1970: 100),
        errorSummary: "database locked"
      )
    ]

    #expect(statuses.syncHealth == .warning)
    #expect(statuses.availableCount == 1)
    #expect(statuses.failedCount == 1)
  }

  @Test("treats missing optional sources as idle when another source is available")
  func treatsMissingOptionalSourcesAsIdle() {
    let statuses = [
      SourceReadStatus(
        sourceID: "cockpit",
        displayName: "cockpit tools",
        state: .missing,
        lastReadAt: Date(timeIntervalSince1970: 100)
      ),
      SourceReadStatus(
        sourceID: "gateway",
        displayName: "local-ai-gateway",
        state: .available,
        lastReadAt: Date(timeIntervalSince1970: 100),
        lastObservedAt: Date(timeIntervalSince1970: 90)
      )
    ]

    #expect(statuses.syncHealth == .idle)
    #expect(statuses.missingCount == 1)
  }
}
