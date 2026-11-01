import SwiftUI
import HyperCore

// applock: 메뉴 "Lock HyperEdit" ⌃⌘L — 앱 메뉴의 Settings… 아래. 잠금 기능 설정이 꺼져 있어도 수동 잠금은 동작한다.
// 설정 섹션은 Apps/mac/AppLockSettings.swift, 상태 머신은 AppLockController.swift, 오버레이는 LockOverlay.swift.

struct AppLockCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("Lock HyperEdit") { model.appLock.lock() }
                .keyboardShortcut("l", modifiers: [.control, .command])
        }
    }
}
