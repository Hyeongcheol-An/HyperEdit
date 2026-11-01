import SwiftUI
import HyperCore

// applock: 설정 › "App Lock" 섹션 (SettingsView 에 한 줄로 붙는다). 값은 AppLockController 가 applock.* 키로 저장한다.
struct AppLockSettingsSection: View {
    @ObservedObject var controller: AppLockController

    var body: some View {
        Section("App Lock") {
            Toggle("Require Touch ID or password to open HyperEdit", isOn: $controller.requireOnLaunch)
            if let w = controller.settingsWarning {
                Text(w).font(.caption).foregroundStyle(Color.red)
            }
            Picker("Lock after inactivity", selection: $controller.idleMinutes) {
                Text("Never").tag(0)
                Text("1 minute").tag(1)
                Text("5 minutes").tag(5)
                Text("15 minutes").tag(15)
                Text("30 minutes").tag(30)
            }
            Toggle("Lock when the Mac sleeps or the screen locks", isOn: $controller.lockOnSleep)
                .disabled(!controller.requireOnLaunch)
            Text(controller.availabilityDescription)
                .font(.caption).foregroundStyle(.secondary)
            Text("Locking covers the window with an opaque screen and blocks Quick Append until you authenticate; it does not encrypt your files. ⌃⌘L locks at any time, even with these options off.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
