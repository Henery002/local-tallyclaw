import SwiftUI
import TallyClawUI

@main
struct TallyClawApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var floatingPreferences = FloatingWindowPreferences()
  @StateObject private var appPreferences = AppPreferences()

  var body: some Scene {
    WindowGroup("TallyClaw") {
      TallyClawHostView(floatingPreferences: floatingPreferences)
        .frame(width: 308, height: 420, alignment: .top)
        .background(Color.clear)
        .containerBackground(.clear, for: .window)
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .defaultSize(width: 308, height: 420)

    Settings {
      TallyClawSettingsView(
        floatingPreferences: floatingPreferences,
        appPreferences: appPreferences
      )
    }

    MenuBarExtra("TallyClaw", systemImage: "pawprint.fill") {
      Toggle("常驻顶层", isOn: $floatingPreferences.isAlwaysOnTop)

      Button(appPreferences.launchAtLogin ? "关闭开机启动" : "开启开机启动") {
        appPreferences.setLaunchAtLogin(!appPreferences.launchAtLogin)
      }

      if let error = appPreferences.launchAtLoginError {
        Text("开机启动设置失败")
        Text(error)
      }

      Divider()

      SettingsLink {
        Text("设置...")
      }

      Button("退出 TallyClaw") {
        NSApp.terminate(nil)
      }
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
}
