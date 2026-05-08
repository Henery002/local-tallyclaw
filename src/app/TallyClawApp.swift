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
      Button(mainWindowVisible ? "隐藏主界面" : "显示主界面") {
        toggleMainWindow()
      }

      Divider()

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

      Divider()

      Button("退出 TallyClaw") {
        appDelegate.allowRealTerminate = true
        NSApp.terminate(nil)
      }
    }
  }

  private var mainWindowVisible: Bool {
    NSApp.windows.contains { window in
      window.isVisible
    }
  }

  private func toggleMainWindow() {
    if mainWindowVisible {
      NSApp.windows.forEach { window in
        window.orderOut(nil)
      }
    } else {
      NSApp.activate(ignoringOtherApps: true)
      NSApp.windows.forEach { window in
        window.orderFrontRegardless()
      }
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  var allowRealTerminate = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    NSApp.activate(ignoringOtherApps: true)
  }

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if allowRealTerminate {
      return .terminateNow
    }
    sender.windows.forEach { window in
      window.orderOut(nil)
    }
    return .terminateCancel
  }
}
