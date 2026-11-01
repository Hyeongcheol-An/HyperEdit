import SwiftUI
import HyperCore

/// 설정 › Secrets: 가리기 켜고 끔 · 자동 재마스킹 지연 · 클립보드 소거 지연
struct SecretsSettingsSection: View {
    @ObservedObject var store: SecretsStore

    var body: some View {
        Section("Secrets") {
            Toggle("Mask secret blocks", isOn: $store.maskEnabled)
            Picker("Re-mask after", selection: $store.remaskSeconds) {
                ForEach(SecretsStore.remaskOptions, id: \.self) { s in
                    if s == 0 { Text("Never").tag(s) } else { Text("\(s) s").tag(s) }
                }
            }
            .disabled(!store.maskEnabled)
            Picker("Clear clipboard after copying a secret", selection: $store.clipboardClearSeconds) {
                ForEach(SecretsStore.clipboardOptions, id: \.self) { s in
                    if s == 0 { Text("Off").tag(s) } else { Text("\(s) s").tag(s) }
                }
            }
            .disabled(!store.maskEnabled)
            // String(localized:) → Text(String): LocalizedStringKey 는 마크다운으로 해석돼 ```secret 의 백틱이 사라진다
            Text(String(localized: "Lines inside a fenced block whose info string starts with `secret` (```secret, ```secret bank) are drawn as •••••••• in the editor, the find results, the outline and the Markdown preview. Moving the caret into a block reveals it; ⌥⌘S reveals all blocks until they are masked again. The file itself is saved as plain text — this hides, it does not encrypt."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
