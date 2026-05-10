import AppKit
import SwiftUI

struct FloatingWindowConfigurator: NSViewRepresentable {
  @ObservedObject var windowState: FloatingWindowState
  @ObservedObject var preferences: FloatingWindowPreferences
  let desiredSize: CGSize
  private static var positionedWindows = Set<ObjectIdentifier>()

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      configure(view.window)
    }
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      configure(nsView.window)
    }
  }

  private func configure(_ window: NSWindow?) {
    guard let window else { return }

    windowState.capture(window: window)
    window.level = preferences.isAlwaysOnTop ? .floating : .normal
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .none
    window.isMovableByWindowBackground = false
    window.collectionBehavior.insert(.canJoinAllSpaces)
    window.collectionBehavior.insert(.fullScreenAuxiliary)

    window.styleMask.remove(.titled)
    window.styleMask.insert(.borderless)
    window.styleMask.insert(.fullSizeContentView)

    window.contentView?.wantsLayer = true
    window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    window.contentView?.superview?.wantsLayer = true
    window.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor

    window.standardWindowButton(.closeButton)?.isHidden = true
    window.standardWindowButton(.miniaturizeButton)?.isHidden = true
    window.standardWindowButton(.zoomButton)?.isHidden = true

    let identifier = ObjectIdentifier(window)
    let isFirstConfiguration = !Self.positionedWindows.contains(identifier)
    if isFirstConfiguration {
      position(window)
      Self.positionedWindows.insert(identifier)
    } else {
      resize(window)
    }

    if isFirstConfiguration || preferences.isAlwaysOnTop {
      window.orderFrontRegardless()
    }
    windowState.refresh()
  }

  private func position(_ window: NSWindow) {
    let size = NSSize(width: desiredSize.width, height: desiredSize.height)
    if let restoredFrame = preferences.restoredFrame(defaultSize: size) {
      window.setFrame(restoredFrame, display: true)
      return
    }

    let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    let origin = NSPoint(
      x: screenFrame.minX + 72,
      y: screenFrame.maxY - size.height - 72
    )
    window.setFrame(NSRect(origin: origin, size: size), display: true)
  }

  private func resize(_ window: NSWindow) {
    let size = NSSize(width: desiredSize.width, height: desiredSize.height)
    guard abs(window.frame.width - size.width) > 0.5 || abs(window.frame.height - size.height) > 0.5 else {
      return
    }

    let top = window.frame.maxY
    let resizedFrame = NSRect(
      x: window.frame.minX,
      y: top - size.height,
      width: size.width,
      height: size.height
    )
    window.setFrame(resizedFrame, display: true, animate: true)
  }
}
