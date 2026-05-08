import Testing
import TallyClawCore

@Suite("Usage snapshot display")
struct UsageSnapshotTests {
  @Test("formats token totals for compact pet UI")
  func formatsTokenTotalsForCompactPetUI() {
    let snapshot = UsageSnapshot.preview

    #expect(snapshot.today.tokens.total.formattedCompact == "1.28M")
    #expect(snapshot.week.tokens.total.formattedCompact == "8.26M")
  }

  @Test("reports success rate as a rounded percentage")
  func reportsSuccessRateAsRoundedPercentage() {
    let stats = RequestStats(total: 3_200, succeeded: 3_136, failed: 64)

    #expect(stats.successRatePercent == 98)
  }

  @Test("keeps read only source policy explicit")
  func keepsReadOnlySourcePolicyExplicit() {
    #expect(SourceAccessPolicy.default.mode == .readOnly)
    #expect(SourceAccessPolicy.default.allowsCredentialRefresh == false)
    #expect(SourceAccessPolicy.default.allowsSourceMutation == false)
  }
}
