import AppKit
import SwiftUI

struct FloatingWindowConfigurator: NSViewRepresentable {
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

    window.level = .floating
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = false
    window.titleVisibility = .hidden
    window.titlebarAppearsTransparent = true
    window.titlebarSeparatorStyle = .none
    window.isMovableByWindowBackground = true
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
    if !Self.positionedWindows.contains(identifier) {
      position(window)
      Self.positionedWindows.insert(identifier)
    }

    window.orderFrontRegardless()
  }

  private func position(_ window: NSWindow) {
    let size = NSSize(width: 296, height: 352)
    let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    let origin = NSPoint(
      x: screenFrame.minX + 72,
      y: screenFrame.maxY - size.height - 72
    )
    window.setFrame(NSRect(origin: origin, size: size), display: true)
  }
}
