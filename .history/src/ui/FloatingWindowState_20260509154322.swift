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

    // Use screenFrame for full screen coverage, but respect menu bar
    // visibleFrame.maxY gives us the bottom of the menu bar
    let bounds = screenFrame
    let menuBarHeight = screenFrame.maxY - visibleFrame.maxY

    // Calculate clamping bounds so the pet anchor stays within screen
    let clampMinX = bounds.minX - petAnchor.x
    let clampMaxX = bounds.maxX - petAnchor.x
    let clampMinY = bounds.minY - petYFromBottom
    // Allow dragging to the top, but leave space for menu bar
    let clampMaxY = bounds.maxY - petYFromBottom - menuBarHeight

    print("DEBUG: petAnchor=\(petAnchor), petYFromBottom=\(petYFromBottom)")
    print("DEBUG: window.frame.height=\(window.frame.height)")
    print("DEBUG: screenFrame=\(screenFrame)")
    print("DEBUG: visibleFrame=\(visibleFrame)")
    print("DEBUG: menuBarHeight=\(menuBarHeight)")
    print("DEBUG: clampMaxY=\(clampMaxY), newOrigin.y before clamp=\(newOrigin.y)")

    newOrigin.x = min(max(newOrigin.x, clampMinX), clampMaxX)
    newOrigin.y = min(max(newOrigin.y, clampMinY), clampMaxY)

    print("DEBUG: newOrigin.y after clamp=\(newOrigin.y)")

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
