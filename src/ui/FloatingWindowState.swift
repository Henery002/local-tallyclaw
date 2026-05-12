import AppKit
import Foundation

@MainActor
final class FloatingWindowState: ObservableObject {
  @Published private(set) var frame: CGRect = .zero
  @Published private(set) var visibleFrame: CGRect = .zero
  @Published private(set) var screenFrame: CGRect = .zero
  @Published private(set) var edgeAttachment: FloatingWindowEdgeAttachment = .none

  private weak var window: NSWindow?
  private var dragOrigin: CGPoint?
  private var dragMouseLocation: CGPoint?
  private var edgeRevealCheckID = UUID()
  private var expansionKeepsEdgeRevealed = false

  func capture(window: NSWindow) {
    self.window = window
    refresh()
  }

  func refresh() {
    guard let window else { return }
    let nextFrame = window.frame
    let nextVisibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    let nextScreenFrame = window.screen?.frame ?? NSScreen.main?.frame ?? .zero
    let bounds = nextVisibleFrame == .zero ? nextScreenFrame : nextVisibleFrame
    let detectedAttachment = FloatingWindowDragGeometry.edgeAttachment(
      windowOrigin: nextFrame.origin,
      petFrameInWindow: FloatingWindowDragGeometry.petDragFrame(
        stageFrame: FloatingWindowDragGeometry.defaultPetStageFrame(windowSize: nextFrame.size)
      ),
      bounds: bounds
    )

    if frame != nextFrame {
      frame = nextFrame
    }
    if visibleFrame != nextVisibleFrame {
      visibleFrame = nextVisibleFrame
    }
    if screenFrame != nextScreenFrame {
      screenFrame = nextScreenFrame
    }
    if !expansionKeepsEdgeRevealed || edgeAttachment == .none {
      if edgeAttachment != detectedAttachment {
        edgeAttachment = detectedAttachment
      }
    }
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

  func endDrag(petFrameInWindow: CGRect? = nil, saveFrame: ((CGRect) -> Void)? = nil) {
    if let window {
      expansionKeepsEdgeRevealed = false
      if let petFrameInWindow {
        snapToEdgeIfNeeded(petFrameInWindow: petFrameInWindow, animate: true)
      }
      saveFrame?(window.frame)
    }
    dragOrigin = nil
    dragMouseLocation = nil
    refresh()
  }

  func revealEdgeAttachment(petFrameInWindow: CGRect) {
    moveEdgeAttachment(to: .revealed, petFrameInWindow: petFrameInWindow, animate: true)
    scheduleEdgeConcealCheck(petFrameInWindow: petFrameInWindow)
  }

  func concealEdgeAttachment(petFrameInWindow: CGRect) {
    guard !expansionKeepsEdgeRevealed else { return }
    edgeRevealCheckID = UUID()
    moveEdgeAttachment(to: .peek, petFrameInWindow: petFrameInWindow, animate: true)
  }

  func revealForExpansion(
    petFrameInWindow _: CGRect,
    targetWindowSize: CGSize
  ) {
    guard let window, edgeAttachment != .none else { return }
    let bounds = visibleFrame == .zero ? screenFrame : visibleFrame
    edgeRevealCheckID = UUID()
    expansionKeepsEdgeRevealed = true
    let origin = FloatingWindowDragGeometry.edgeExpansionOrigin(
      currentOrigin: window.frame.origin,
      windowSize: targetWindowSize,
      bounds: bounds,
      attachment: edgeAttachment
    )
    setWindowOrigin(origin, animate: false)
  }

  func restoreAfterExpansionCollapse(petFrameInWindow: CGRect) {
    guard edgeAttachment != .none else { return }
    Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(260))
      await MainActor.run {
        self?.expansionKeepsEdgeRevealed = false
        self?.concealEdgeAttachment(petFrameInWindow: petFrameInWindow)
      }
    }
  }

  private func snapToEdgeIfNeeded(petFrameInWindow: CGRect, animate: Bool) {
    guard let window else { return }
    expansionKeepsEdgeRevealed = false
    let bounds = visibleFrame == .zero ? screenFrame : visibleFrame
    let attachment = FloatingWindowDragGeometry.nearEdgeAttachment(
      windowOrigin: window.frame.origin,
      petFrameInWindow: petFrameInWindow,
      bounds: bounds
    )
    guard attachment != .none else {
      edgeAttachment = .none
      return
    }
    edgeAttachment = attachment
    setWindowOrigin(
      FloatingWindowDragGeometry.edgeOrigin(
        currentOrigin: window.frame.origin,
        petFrameInWindow: petFrameInWindow,
        bounds: bounds,
        attachment: attachment,
        visibility: .peek
      ),
      animate: animate
    )
  }

  private func moveEdgeAttachment(
    to visibility: FloatingWindowEdgeVisibility,
    petFrameInWindow: CGRect,
    animate: Bool
  ) {
    guard let window, edgeAttachment != .none else { return }
    let bounds = visibleFrame == .zero ? screenFrame : visibleFrame
    setWindowOrigin(
      FloatingWindowDragGeometry.edgeOrigin(
        currentOrigin: window.frame.origin,
        petFrameInWindow: petFrameInWindow,
        bounds: bounds,
        attachment: edgeAttachment,
        visibility: visibility
      ),
      animate: animate
    )
  }

  private func setWindowOrigin(_ origin: CGPoint, animate: Bool) {
    guard let window else { return }
    let frame = NSRect(origin: origin, size: window.frame.size)
    window.setFrame(frame, display: true, animate: animate)
    refresh()
  }

  private func scheduleEdgeConcealCheck(petFrameInWindow: CGRect) {
    let checkID = UUID()
    edgeRevealCheckID = checkID

    Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(900))
      await MainActor.run {
        self?.concealEdgeAttachmentIfMouseOutside(
          checkID: checkID,
          petFrameInWindow: petFrameInWindow
        )
      }
    }
  }

  private func concealEdgeAttachmentIfMouseOutside(
    checkID: UUID,
    petFrameInWindow: CGRect
  ) {
    guard checkID == edgeRevealCheckID, edgeAttachment != .none, !expansionKeepsEdgeRevealed else { return }
    if mouseIsInsidePetFrame(petFrameInWindow) {
      scheduleEdgeConcealCheck(petFrameInWindow: petFrameInWindow)
    } else {
      concealEdgeAttachment(petFrameInWindow: petFrameInWindow)
    }
  }

  private func mouseIsInsidePetFrame(_ petFrameInWindow: CGRect) -> Bool {
    guard let window else { return false }
    let petScreenFrame = CGRect(
      x: window.frame.minX + petFrameInWindow.minX,
      y: window.frame.minY + window.frame.height - petFrameInWindow.maxY,
      width: petFrameInWindow.width,
      height: petFrameInWindow.height
    ).insetBy(dx: -10, dy: -10)
    return petScreenFrame.contains(NSEvent.mouseLocation)
  }
}

public enum FloatingWindowEdgeAttachment: Equatable {
  case none
  case left
  case right
}

public enum FloatingWindowEdgeVisibility {
  case peek
  case revealed
}

public struct FloatingWindowDragGeometry {
  public static let collapsedWindowSize = CGSize(width: 308, height: 110)
  public static let expandedWindowSize = CGSize(width: 308, height: 570)
  public static let rootContentWidth: CGFloat = 292
  public static let petStageSize = CGSize(width: 170, height: 94)
  public static let petVisibleBodySize = CGSize(width: 64, height: 64)
  public static let edgeSnapThreshold: CGFloat = 36
  public static let edgePeekVisibleWidth: CGFloat = 28

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

  public static func nearEdgeAttachment(
    windowOrigin: CGPoint,
    petFrameInWindow: CGRect,
    bounds: CGRect
  ) -> FloatingWindowEdgeAttachment {
    guard !petFrameInWindow.isEmpty, !bounds.isEmpty else { return .none }

    let petLeft = windowOrigin.x + petFrameInWindow.minX
    let petRight = windowOrigin.x + petFrameInWindow.maxX
    let leftDistance = abs(petLeft - bounds.minX)
    let rightDistance = abs(bounds.maxX - petRight)

    if leftDistance <= edgeSnapThreshold, leftDistance <= rightDistance {
      return .left
    }
    if rightDistance <= edgeSnapThreshold {
      return .right
    }
    return .none
  }

  public static func edgeAttachment(
    windowOrigin: CGPoint,
    petFrameInWindow: CGRect,
    bounds: CGRect
  ) -> FloatingWindowEdgeAttachment {
    guard !petFrameInWindow.isEmpty, !bounds.isEmpty else { return .none }

    let hiddenWidth = petVisibleBodySize.width - edgePeekVisibleWidth
    let petLeft = windowOrigin.x + petFrameInWindow.minX
    let petRight = windowOrigin.x + petFrameInWindow.maxX
    let tolerance: CGFloat = 4

    if abs(petLeft - (bounds.minX - hiddenWidth)) <= tolerance {
      return .left
    }
    if abs(petLeft - bounds.minX) <= tolerance {
      return .left
    }
    if abs(petRight - (bounds.maxX + hiddenWidth)) <= tolerance {
      return .right
    }
    if abs(petRight - bounds.maxX) <= tolerance {
      return .right
    }
    return .none
  }

  public static func edgeOrigin(
    currentOrigin: CGPoint,
    petFrameInWindow: CGRect,
    bounds: CGRect,
    attachment: FloatingWindowEdgeAttachment,
    visibility: FloatingWindowEdgeVisibility
  ) -> CGPoint {
    guard !petFrameInWindow.isEmpty, !bounds.isEmpty else { return currentOrigin }

    let hiddenWidth = visibility == .peek
      ? petVisibleBodySize.width - edgePeekVisibleWidth
      : 0

    switch attachment {
    case .none:
      return currentOrigin
    case .left:
      return CGPoint(
        x: bounds.minX - hiddenWidth - petFrameInWindow.minX,
        y: currentOrigin.y
      )
    case .right:
      return CGPoint(
        x: bounds.maxX + hiddenWidth - petFrameInWindow.maxX,
        y: currentOrigin.y
      )
    }
  }

  public static func edgeExpansionOrigin(
    currentOrigin: CGPoint,
    windowSize: CGSize,
    bounds: CGRect,
    attachment: FloatingWindowEdgeAttachment
  ) -> CGPoint {
    guard windowSize.width > 0, !bounds.isEmpty else { return currentOrigin }

    switch attachment {
    case .none:
      return currentOrigin
    case .left:
      return CGPoint(x: bounds.minX, y: currentOrigin.y)
    case .right:
      return CGPoint(x: bounds.maxX - windowSize.width, y: currentOrigin.y)
    }
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
