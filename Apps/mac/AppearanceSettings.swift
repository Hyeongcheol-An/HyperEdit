import SwiftUI
import HyperCore

/// 설정 › Appearance: 커서 스타일·깜빡임, 창 투명도·블러 (appearance). SettingsView 에 한 줄로 들어간다
struct AppearanceSettingsSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Section("Appearance") {
            Picker("Cursor style", selection: $model.cursorStyle) {
                ForEach(CursorStyle.allCases) { Text($0.label).tag($0) }
            }
            Toggle("Blink", isOn: $model.cursorBlink)
            Text("Block and Underline carets are drawn under the glyph in the theme's cursor color; extra carets (multi-caret, column mode) use the same style and do not blink.")
                .font(.caption).foregroundStyle(.secondary)
            Slider(value: $model.backgroundOpacity, in: BackgroundOpacity.range, step: 0.05) {
                Text("Window opacity") + Text(verbatim: " \(Int((model.backgroundOpacity * 100).rounded()))%")
            }
            Toggle("Blur behind window", isOn: $model.backgroundBlur).disabled(!model.isTranslucentWindow)
            Text("Below 100% the window, editor and panels show what is behind them; text, icons and borders stay opaque. Blur applies only while the window is translucent.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
