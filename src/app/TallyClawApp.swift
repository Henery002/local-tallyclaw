import SwiftUI
import TallyClawUI

@main
struct TallyClawApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  @StateObject private var floatingPreferences = FloatingWindowPreferences()
  @StateObject private var appPreferences = AppPreferences()

  var body: some Scene {
    Window("TallyClaw", id: "main") {
      TallyClawHostView(floatingPreferences: floatingPreferences)
        .background(Color.clear)
        .containerBackground(.clear, for: .window)
    }
    .windowStyle(.hiddenTitleBar)
    .windowResizability(.contentSize)
    .defaultSize(
      width: FloatingWindowDragGeometry.collapsedWindowSize.width,
      height: FloatingWindowDragGeometry.collapsedWindowSize.height
    )

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
    mainWindow?.isVisible ?? false
  }

  /// Find the single main pet window, excluding MenuBarExtra helper windows
  /// and settings panels.
  private var mainWindow: NSWindow? {
    NSApp.windows.first { window in
      // MenuBarExtra creates small utility panels; settings window has its own identifier.
      // The main pet window carries the "TallyClaw" title or the "main" identifier.
      guard window.level != .statusBar else { return false }
      guard !window.className.contains("MenuBarExtraWindow") else { return false }
      guard window.identifier?.rawValue != "com_apple_SwiftUI_Settings_window" else { return false }
      return window.contentView != nil
    }
  }

  private func toggleMainWindow() {
    if let window = mainWindow, window.isVisible {
      window.orderOut(nil)
    } else {
      NSApp.activate(ignoringOtherApps: true)
      if let window = mainWindow {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
      } else {
        // Window not yet created – open the Window scene by its identifier.
        if let url = URL(string: "tallyclaw://main") {
          NSWorkspace.shared.open(url)
        }
      }
    }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  var allowRealTerminate = false

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Prevent macOS from re-opening the app a second time on login
    // (SMAppService already handles launch-at-login).
    NSApp.disableRelaunchOnLogin()
    NSApp.setActivationPolicy(.accessory)

    // Small delay so the Window scene has time to materialise its NSWindow,
    // then bring it to front.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
      NSApp.activate(ignoringOtherApps: true)
      NSApp.windows.forEach { window in
        if window.contentView != nil, !window.className.contains("MenuBarExtraWindow") {
          window.makeKeyAndOrderFront(nil)
          window.orderFrontRegardless()
        }
      }
    }
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
