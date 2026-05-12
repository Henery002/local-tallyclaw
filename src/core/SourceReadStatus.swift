import Foundation

public enum SourceReadState: String, Equatable, Sendable {
  case available
  case missing
  case failed
}

public struct SourceReadStatus: Identifiable, Equatable, Sendable {
  public var id: String { sourceID }
  public var sourceID: String
  public var displayName: String
  public var state: SourceReadState
  public var lastReadAt: Date
  public var lastObservedAt: Date?
  public var errorSummary: String?
  public var readDurationMilliseconds: Int?

  public init(
    sourceID: String,
    displayName: String,
    state: SourceReadState,
    lastReadAt: Date,
    lastObservedAt: Date? = nil,
    errorSummary: String? = nil,
    readDurationMilliseconds: Int? = nil
  ) {
    self.sourceID = sourceID
    self.displayName = displayName
    self.state = state
    self.lastReadAt = lastReadAt
    self.lastObservedAt = lastObservedAt
    self.errorSummary = errorSummary
    self.readDurationMilliseconds = readDurationMilliseconds
  }
}

public extension Array where Element == SourceReadStatus {
  var availableCount: Int {
    count { $0.state == .available }
  }

  var missingCount: Int {
    count { $0.state == .missing }
  }

  var failedCount: Int {
    count { $0.state == .failed }
  }

  var syncHealth: SyncHealth {
    failedCount > 0 ? .warning : .idle
  }
}
