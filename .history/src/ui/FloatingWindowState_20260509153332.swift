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
    guard
      let window,
      let dragOrigin,
      let dragMouseLocation
    else { return }

    let current = NSEvent.mouseLocation
    let deltaX = current.x - dragMouseLocation.x
    let deltaY = current.y - dragMouseLocation.y
    var newOrigin = CGPoint(x: dragOrigin.x + deltaX, y: dragOrigin.y + deltaY)

    // Convert petAnchor from SwiftUI coordinates (top-left origin, y-down)
    // to AppKit window coordinates (bottom-left origin, y-up)
    let petYFromBottom = window.frame.height - petAnchor.y

    // Use visibleFrame to respect menu bar and dock
    let bounds = visibleFrame

    // Calculate clamping bounds so the pet anchor stays within visible screen
    let clampMinX = bounds.minX - petAnchor.x
    let clampMaxX = bounds.maxX - petAnchor.x
    let clampMinY = bounds.minY - petYFromBottom
    let clampMaxY = bounds.maxY - petYFromBottom

    newOrigin.x = min(max(newOrigin.x, clampMinX), clampMaxX)
    newOrigin.y = min(max(newOrigin.y, clampMinY), clampMaxY)

    window.setFrameOrigin(newOrigin)

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
