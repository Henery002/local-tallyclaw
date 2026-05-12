import Foundation
import TallyClawCore

public protocol UsageDataSource: Sendable {
  var id: String { get }
  var displayName: String { get }
  var accessPolicy: SourceAccessPolicy { get }

  func readSnapshot() async throws -> UsageSnapshot?
}

public protocol UsageObservationDataSource: UsageDataSource {
  func readObservations(since startDate: Date?) async throws -> [UsageObservation]
}

public struct PreviewUsageDataSource: UsageDataSource {
  public let id = "preview"
  public let displayName = "预览数据源"
  public let accessPolicy = SourceAccessPolicy.default

  public init() {}

  public func readSnapshot() async throws -> UsageSnapshot? {
    UsageSnapshot.preview
  }
}
