import SwiftUI

@main
struct TallyClawApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup("TallyClaw") {
      TallyClawHostView()
        .frame(width: 300, height: 240)
        .background(Color.clear)
        .containerBackground(.clear, for: .window)
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .defaultSize(width: 300, height: 240)

    Settings {
      Text("TallyClaw 设置将在后续接入。")
        .padding()
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
}
