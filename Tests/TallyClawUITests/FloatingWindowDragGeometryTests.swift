import CoreGraphics
import Foundation
import Testing
@testable import TallyClawUI

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
