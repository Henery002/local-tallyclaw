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

    // petAnchor is in SwiftUI coordinates (top-left origin, y-down)
    // We need to convert it to screen coordinates for clamping
    
    // In AppKit, window.frame.origin is bottom-left of the window
    // petAnchor.y is distance from top of window in SwiftUI coords
    // So pet's Y position in screen coords = window.origin.y + (window.height - petAnchor.y)
    let petScreenY = newOrigin.y + (window.frame.height - petAnchor.y)
    let petScreenX = newOrigin.x + petAnchor.x
    
    // Clamp the pet anchor position to visible screen bounds
    let clampedPetY = min(max(petScreenY, visibleFrame.minY), visibleFrame.maxY)
    let clampedPetX = min(max(petScreenX, visibleFrame.minX), visibleFrame.maxX)
    
    // Convert back to window origin
    newOrigin.y = clampedPetY - (window.frame.height - petAnchor.y)
    newOrigin.x = clampedPetX - petAnchor.x

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
