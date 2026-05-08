import SwiftUI
import TallyClawUI

struct TallyClawSettingsView: View {
  @ObservedObject var floatingPreferences: FloatingWindowPreferences
  @ObservedObject var appPreferences: AppPreferences

  var body: some View {
    Form {
      Section("桌面体验") {
        Toggle("常驻顶层", isOn: $floatingPreferences.isAlwaysOnTop)
        Toggle(
          "开机启动",
          isOn: Binding(
            get: { appPreferences.launchAtLogin },
            set: { appPreferences.setLaunchAtLogin($0) }
          )
        )

        if let error = appPreferences.launchAtLoginError {
          Text("开机启动设置失败：\(error)")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 360, height: 180)
    .padding(12)
  }
}
