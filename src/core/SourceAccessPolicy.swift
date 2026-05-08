public enum SourceAccessMode: Equatable, Sendable {
  case readOnly
}

public struct SourceAccessPolicy: Equatable, Sendable {
  public var mode: SourceAccessMode
  public var allowsCredentialRefresh: Bool
  public var allowsSourceMutation: Bool

  public init(
    mode: SourceAccessMode,
    allowsCredentialRefresh: Bool,
    allowsSourceMutation: Bool
  ) {
    self.mode = mode
    self.allowsCredentialRefresh = allowsCredentialRefresh
    self.allowsSourceMutation = allowsSourceMutation
  }

  public static let `default` = SourceAccessPolicy(
    mode: .readOnly,
    allowsCredentialRefresh: false,
    allowsSourceMutation: false
  )
}

