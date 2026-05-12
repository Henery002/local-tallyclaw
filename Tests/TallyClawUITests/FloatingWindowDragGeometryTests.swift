import CoreGraphics
import Foundation
import Testing
@testable import TallyClawUI

@Suite("Pet animation cadence")
struct PetAnimationCadenceTests {
  @Test("uses low frequency cadence when idle and collapsed")
  func usesLowFrequencyCadenceWhenIdleAndCollapsed() {
    let cadence = PetAnimationCadence.resolve(
      state: .idle,
      isExpanded: false,
      isHovered: false,
      isPressed: false,
      hasParticles: false
    )

    #expect(cadence.minimumInterval == 0)
  }

  @Test("uses interactive cadence only while interaction or activity is visible")
  func usesInteractiveCadenceOnlyWhileNeeded() {
    #expect(
      PetAnimationCadence.resolve(
        state: .idle,
        isExpanded: false,
        isHovered: true,
        isPressed: false,
        hasParticles: false
      ).minimumInterval == 1.0 / 12.0
    )
    #expect(
      PetAnimationCadence.resolve(
        state: .highActivity,
        isExpanded: false,
        isHovered: false,
        isPressed: false,
        hasParticles: false
      ).minimumInterval == 1.0 / 2.0
    )
    #expect(
      PetAnimationCadence.resolve(
        state: .warning,
        isExpanded: false,
        isHovered: false,
        isPressed: false,
        hasParticles: false
      ).minimumInterval == 0
    )
    #expect(
      PetAnimationCadence.resolve(
        state: .idle,
        isExpanded: true,
        isHovered: false,
        isPressed: false,
        hasParticles: false
      ).minimumInterval == 0
    )
    #expect(
      PetAnimationCadence.resolve(
        state: .idle,
        isExpanded: false,
        isHovered: false,
        isPressed: true,
        hasParticles: false
      ).minimumInterval == 1.0 / 30.0
    )
    #expect(
      PetAnimationCadence.resolve(
        state: .idle,
        isExpanded: false,
        isHovered: false,
        isPressed: false,
        hasParticles: true
      ).minimumInterval == 1.0 / 30.0
    )
  }
}

@Suite("Floating window drag geometry")
struct FloatingWindowDragGeometryTests {
  @Test("clamps pet frame top to visible screen while allowing transparent window overflow")
  func clampsPetFrameTopToVisibleScreen() {
    let windowSize = FloatingWindowDragGeometry.collapsedWindowSize
    let petFrame = FloatingWindowDragGeometry.defaultPetStageFrame(windowSize: windowSize)
    let visibleFrame = CGRect(x: 0, y: 94, width: 1_512, height: 855)

    let origin = FloatingWindowDragGeometry.clampedOrigin(
      proposedOrigin: CGPoint(x: 72, y: 10_000),
      windowSize: windowSize,
      petFrameInWindow: petFrame,
      bounds: visibleFrame
    )

    #expect(origin.y == visibleFrame.maxY - (windowSize.height - petFrame.minY))
    #expect(origin.y + windowSize.height - petFrame.minY == visibleFrame.maxY)
  }

  @Test("clamps pet frame bottom to visible screen while allowing transparent window overflow")
  func clampsPetFrameBottomToVisibleScreen() {
    let windowSize = FloatingWindowDragGeometry.collapsedWindowSize
    let petFrame = FloatingWindowDragGeometry.defaultPetStageFrame(windowSize: windowSize)
    let visibleFrame = CGRect(x: 0, y: 94, width: 1_512, height: 855)

    let origin = FloatingWindowDragGeometry.clampedOrigin(
      proposedOrigin: CGPoint(x: 72, y: -10_000),
      windowSize: windowSize,
      petFrameInWindow: petFrame,
      bounds: visibleFrame
    )

    #expect(origin.y + windowSize.height - petFrame.maxY == visibleFrame.minY)
  }

  @Test("fallback pet frame tracks the visible pet stage instead of the transparent window center point")
  func fallbackPetFrameTracksVisiblePetStage() {
    let frame = FloatingWindowDragGeometry.defaultPetStageFrame(windowSize: FloatingWindowDragGeometry.collapsedWindowSize)

    #expect(frame == CGRect(x: 69, y: 0, width: 170, height: 94))
  }

  @Test("horizontal clamping uses visible pet body so it can touch screen edges")
  func horizontalClampingUsesVisiblePetBody() {
    let windowSize = FloatingWindowDragGeometry.collapsedWindowSize
    let stageFrame = FloatingWindowDragGeometry.defaultPetStageFrame(windowSize: windowSize)
    let dragFrame = FloatingWindowDragGeometry.petDragFrame(stageFrame: stageFrame)
    let visibleFrame = CGRect(x: 0, y: 94, width: 1_512, height: 855)

    let leftOrigin = FloatingWindowDragGeometry.clampedOrigin(
      proposedOrigin: CGPoint(x: -10_000, y: 200),
      windowSize: windowSize,
      petFrameInWindow: dragFrame,
      bounds: visibleFrame
    )
    let rightOrigin = FloatingWindowDragGeometry.clampedOrigin(
      proposedOrigin: CGPoint(x: 10_000, y: 200),
      windowSize: windowSize,
      petFrameInWindow: dragFrame,
      bounds: visibleFrame
    )

    #expect(dragFrame == CGRect(x: 122, y: 0, width: 64, height: 94))
    #expect(leftOrigin.x + dragFrame.minX == visibleFrame.minX)
    #expect(rightOrigin.x + dragFrame.maxX == visibleFrame.maxX)
  }

  @Test("edge snap peeks half-hidden and reveal returns visible body to screen edge")
  func edgeSnapPeekAndRevealOrigins() {
    let windowSize = FloatingWindowDragGeometry.collapsedWindowSize
    let stageFrame = FloatingWindowDragGeometry.defaultPetStageFrame(windowSize: windowSize)
    let dragFrame = FloatingWindowDragGeometry.petDragFrame(stageFrame: stageFrame)
    let visibleFrame = CGRect(x: 0, y: 94, width: 1_512, height: 855)
    let origin = CGPoint(x: 20, y: 200)

    let leftPeek = FloatingWindowDragGeometry.edgeOrigin(
      currentOrigin: origin,
      petFrameInWindow: dragFrame,
      bounds: visibleFrame,
      attachment: .left,
      visibility: .peek
    )
    let leftReveal = FloatingWindowDragGeometry.edgeOrigin(
      currentOrigin: leftPeek,
      petFrameInWindow: dragFrame,
      bounds: visibleFrame,
      attachment: .left,
      visibility: .revealed
    )
    let rightPeek = FloatingWindowDragGeometry.edgeOrigin(
      currentOrigin: origin,
      petFrameInWindow: dragFrame,
      bounds: visibleFrame,
      attachment: .right,
      visibility: .peek
    )
    let rightReveal = FloatingWindowDragGeometry.edgeOrigin(
      currentOrigin: rightPeek,
      petFrameInWindow: dragFrame,
      bounds: visibleFrame,
      attachment: .right,
      visibility: .revealed
    )

    #expect(leftPeek.x + dragFrame.minX == -36)
    #expect(leftReveal.x + dragFrame.minX == visibleFrame.minX)
    #expect(rightPeek.x + dragFrame.maxX == visibleFrame.maxX + 36)
    #expect(rightReveal.x + dragFrame.maxX == visibleFrame.maxX)
  }

  @Test("edge expansion reveals the whole panel inside the visible screen")
  func edgeExpansionRevealsWholePanelInsideVisibleScreen() {
    let windowSize = FloatingWindowDragGeometry.expandedWindowSize
    let visibleFrame = CGRect(x: 0, y: 94, width: 1_512, height: 855)

    let left = FloatingWindowDragGeometry.edgeExpansionOrigin(
      currentOrigin: CGPoint(x: -158, y: 200),
      windowSize: windowSize,
      bounds: visibleFrame,
      attachment: .left
    )
    let right = FloatingWindowDragGeometry.edgeExpansionOrigin(
      currentOrigin: CGPoint(x: 1_362, y: 200),
      windowSize: windowSize,
      bounds: visibleFrame,
      attachment: .right
    )

    #expect(left.x == visibleFrame.minX)
    #expect(right.x + windowSize.width == visibleFrame.maxX)
  }

  @Test("near edge attachment detects candidate side within threshold")
  func nearEdgeAttachmentDetectsCandidateSide() {
    let windowSize = FloatingWindowDragGeometry.collapsedWindowSize
    let stageFrame = FloatingWindowDragGeometry.defaultPetStageFrame(windowSize: windowSize)
    let dragFrame = FloatingWindowDragGeometry.petDragFrame(stageFrame: stageFrame)
    let visibleFrame = CGRect(x: 0, y: 94, width: 1_512, height: 855)

    #expect(
      FloatingWindowDragGeometry.nearEdgeAttachment(
        windowOrigin: CGPoint(x: -100, y: 200),
        petFrameInWindow: dragFrame,
        bounds: visibleFrame
      ) == .left
    )
    #expect(
      FloatingWindowDragGeometry.nearEdgeAttachment(
        windowOrigin: CGPoint(x: 1_300, y: 200),
        petFrameInWindow: dragFrame,
        bounds: visibleFrame
      ) == .right
    )
    #expect(
      FloatingWindowDragGeometry.nearEdgeAttachment(
        windowOrigin: CGPoint(x: 300, y: 200),
        petFrameInWindow: dragFrame,
        bounds: visibleFrame
      ) == .none
    )
  }

  @Test("edge attachment recognizes both peek and fully revealed legacy edge positions")
  func edgeAttachmentRecognizesPeekAndRevealedPositions() {
    let windowSize = FloatingWindowDragGeometry.collapsedWindowSize
    let stageFrame = FloatingWindowDragGeometry.defaultPetStageFrame(windowSize: windowSize)
    let dragFrame = FloatingWindowDragGeometry.petDragFrame(stageFrame: stageFrame)
    let visibleFrame = CGRect(x: 0, y: 94, width: 1_512, height: 855)

    #expect(
      FloatingWindowDragGeometry.edgeAttachment(
        windowOrigin: CGPoint(x: -158, y: 200),
        petFrameInWindow: dragFrame,
        bounds: visibleFrame
      ) == .left
    )
    #expect(
      FloatingWindowDragGeometry.edgeAttachment(
        windowOrigin: CGPoint(x: -122, y: 200),
        petFrameInWindow: dragFrame,
        bounds: visibleFrame
      ) == .left
    )
    #expect(
      FloatingWindowDragGeometry.edgeAttachment(
        windowOrigin: CGPoint(x: 1_362, y: 200),
        petFrameInWindow: dragFrame,
        bounds: visibleFrame
      ) == .right
    )
    #expect(
      FloatingWindowDragGeometry.edgeAttachment(
        windowOrigin: CGPoint(x: 1_326, y: 200),
        petFrameInWindow: dragFrame,
        bounds: visibleFrame
      ) == .right
    )
  }

  @Test("restored legacy 420pt frames keep their visual top while adopting compact size")
  func restoredLegacyFrameKeepsTopWithCompactSize() {
    let suiteName = "TallyClawUITests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    defaults.set(72.0, forKey: "floatingWindow.frame.x")
    defaults.set(529.0, forKey: "floatingWindow.frame.y")
    defaults.set(308.0, forKey: "floatingWindow.frame.width")
    defaults.set(420.0, forKey: "floatingWindow.frame.height")

    let preferences = FloatingWindowPreferences(defaults: defaults)
    let restored = preferences.restoredFrame(defaultSize: FloatingWindowDragGeometry.collapsedWindowSize)

    #expect(restored?.origin.y == 839)
    #expect(restored?.height == FloatingWindowDragGeometry.collapsedWindowSize.height)
    #expect(restored?.maxY == 949)
  }
}
