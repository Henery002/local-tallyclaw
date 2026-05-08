import Foundation
import ServiceManagement

@MainActor
final class AppPreferences: ObservableObject {
  @Published private(set) var launchAtLogin: Bool
  @Published private(set) var launchAtLoginError: String?

  init() {
    launchAtLogin = SMAppService.mainApp.status == .enabled
  }

  func setLaunchAtLogin(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
      launchAtLogin = enabled
      launchAtLoginError = nil
    } catch {
      launchAtLogin = SMAppService.mainApp.status == .enabled
      launchAtLoginError = String(describing: error)
    }
  }
}
