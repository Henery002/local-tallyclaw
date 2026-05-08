import AppKit
import Foundation

public final class FloatingWindowPreferences: ObservableObject {
  private enum Keys {
    static let isAlwaysOnTop = "floatingWindow.isAlwaysOnTop"
    static let frameX = "floatingWindow.frame.x"
    static let frameY = "floatingWindow.frame.y"
    static let frameWidth = "floatingWindow.frame.width"
    static let frameHeight = "floatingWindow.frame.height"
  }

  private let defaults: UserDefaults

  @Published public var isAlwaysOnTop: Bool {
    didSet {
      defaults.set(isAlwaysOnTop, forKey: Keys.isAlwaysOnTop)
    }
  }

  public init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if defaults.object(forKey: Keys.isAlwaysOnTop) == nil {
      defaults.set(true, forKey: Keys.isAlwaysOnTop)
    }
    isAlwaysOnTop = defaults.bool(forKey: Keys.isAlwaysOnTop)
  }

  public func restoredFrame(defaultSize: NSSize) -> CGRect? {
    guard
      defaults.object(forKey: Keys.frameX) != nil,
      defaults.object(forKey: Keys.frameY) != nil
    else { return nil }

    let width = defaults.object(forKey: Keys.frameWidth) == nil
      ? defaultSize.width
      : defaults.double(forKey: Keys.frameWidth)
    let height = defaults.object(forKey: Keys.frameHeight) == nil
      ? defaultSize.height
      : defaults.double(forKey: Keys.frameHeight)

    let frame = CGRect(
      x: defaults.double(forKey: Keys.frameX),
      y: defaults.double(forKey: Keys.frameY),
      width: max(width, 1),
      height: max(height, 1)
    )

    return isUsable(frame) ? frame : nil
  }

  public func saveFrame(_ frame: CGRect) {
    guard isUsable(frame) else { return }
    defaults.set(frame.origin.x, forKey: Keys.frameX)
    defaults.set(frame.origin.y, forKey: Keys.frameY)
    defaults.set(frame.width, forKey: Keys.frameWidth)
    defaults.set(frame.height, forKey: Keys.frameHeight)
  }

  public func resetSavedFrame() {
    defaults.removeObject(forKey: Keys.frameX)
    defaults.removeObject(forKey: Keys.frameY)
    defaults.removeObject(forKey: Keys.frameWidth)
    defaults.removeObject(forKey: Keys.frameHeight)
  }

  private func isUsable(_ frame: CGRect) -> Bool {
    let center = CGPoint(x: frame.midX, y: frame.midY)
    return NSScreen.screens.contains { screen in
      screen.frame.insetBy(dx: -80, dy: -80).contains(center)
    }
  }
}
