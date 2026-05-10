import AppKit
import Foundation

@MainActor
final class FloatingWindowState: ObservableObject {
  @Published private(set) var frame: CGRect = .zero
  @Published private(set) var visibleFrame: CGRect = .zero
  @Published private(set) var screenFrame: CGRect = .zero

  private weak var window: NSWindow?
  private var dragOrigin: CGPoint?
  private var dragMouseLocation: CGPoint?

  func capture(window: NSWindow) {
    self.window = window
    refresh()
  }

  func refresh() {
    guard let window else { return }
    frame = window.frame
    visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    screenFrame = window.screen?.frame ?? NSScreen.main?.frame ?? .zero
  }

  func beginDragIfNeeded() {
    guard dragOrigin == nil, let window else { return }
    dragOrigin = window.frame.origin
    dragMouseLocation = NSEvent.mouseLocation
  }

  func updateDrag(petAnchor: CGPoint) {
    updateDrag(
      petFrameInWindow: CGRect(
        x: petAnchor.x - 0.5,
        y: petAnchor.y - 0.5,
        width: 1,
        height: 1
      )
    )
  }

  func updateDrag(petFrameInWindow: CGRect) {
    guard
      let window,
      let dragOrigin,
      let dragMouseLocation
    else { return }

    let current = NSEvent.mouseLocation
    let deltaX = current.x - dragMouseLocation.x
    let deltaY = current.y - dragMouseLocation.y
    let proposedOrigin = CGPoint(x: dragOrigin.x + deltaX, y: dragOrigin.y + deltaY)
    let bounds = visibleFrame == .zero ? screenFrame : visibleFrame
    let newOrigin = FloatingWindowDragGeometry.clampedOrigin(
      proposedOrigin: proposedOrigin,
      windowSize: window.frame.size,
      petFrameInWindow: petFrameInWindow,
      bounds: bounds
    )

    window.setFrame(NSRect(origin: newOrigin, size: window.frame.size), display: false)

    refresh()
  }

  func endDrag(saveFrame: ((CGRect) -> Void)? = nil) {
    if let window {
      saveFrame?(window.frame)
    }
    dragOrigin = nil
    dragMouseLocation = nil
    refresh()
  }
}

public struct FloatingWindowDragGeometry {
  public static let collapsedWindowSize = CGSize(width: 308, height: 110)
  public static let expandedWindowSize = CGSize(width: 308, height: 300)
  public static let rootContentWidth: CGFloat = 292
  public static let petStageSize = CGSize(width: 170, height: 94)
  public static let petVisibleBodySize = CGSize(width: 64, height: 64)

  public static func defaultPetStageFrame(windowSize: CGSize) -> CGRect {
    CGRect(
      x: (windowSize.width - petStageSize.width) / 2,
      y: 0,
      width: petStageSize.width,
      height: petStageSize.height
    )
  }

  public static func petDragFrame(stageFrame: CGRect) -> CGRect {
    CGRect(
      x: stageFrame.midX - petVisibleBodySize.width / 2,
      y: stageFrame.minY,
      width: petVisibleBodySize.width,
      height: stageFrame.height
    )
  }

  public static func clampedOrigin(
    proposedOrigin: CGPoint,
    windowSize: CGSize,
    petFrameInWindow: CGRect,
    bounds: CGRect
  ) -> CGPoint {
    guard windowSize.width > 0, windowSize.height > 0, !petFrameInWindow.isEmpty, !bounds.isEmpty else {
      return proposedOrigin
    }

    let minX = bounds.minX - petFrameInWindow.minX
    let maxX = bounds.maxX - petFrameInWindow.maxX
    let minY = bounds.minY - (windowSize.height - petFrameInWindow.maxY)
    let maxY = bounds.maxY - (windowSize.height - petFrameInWindow.minY)

    return CGPoint(
      x: clamp(proposedOrigin.x, min: minX, max: maxX),
      y: clamp(proposedOrigin.y, min: minY, max: maxY)
    )
  }

  private static func clamp(_ value: CGFloat, min minimum: CGFloat, max maximum: CGFloat) -> CGFloat {
    guard minimum <= maximum else {
      return (minimum + maximum) / 2
    }
    return Swift.min(Swift.max(value, minimum), maximum)
  }
}
