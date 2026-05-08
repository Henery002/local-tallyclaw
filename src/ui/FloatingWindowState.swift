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

    let minX = screenFrame.minX - petAnchor.x
    let maxX = screenFrame.maxX - petAnchor.x
    let minY = screenFrame.minY - petAnchor.y
    let maxY = screenFrame.maxY - petAnchor.y

    newOrigin.x = min(max(newOrigin.x, minX), maxX)
    newOrigin.y = min(max(newOrigin.y, minY), maxY)

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
