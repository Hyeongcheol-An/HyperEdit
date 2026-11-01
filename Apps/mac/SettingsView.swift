import SwiftUI
import HyperCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("Language") {
                Picker("Interface language", selection: $model.language) {
                    Text("System Default · \(AppLanguage.systemResolved.nativeName)").tag(AppLanguage.system)
                    Divider()
                    ForEach(AppLanguage.supported) { Text(verbatim: $0.nativeName).tag($0) }   // 언어 이름은 그 언어로 (번역하지 않음)
                }
                if model.languageNeedsRelaunch {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Applied after HyperEdit relaunches — the document is saved first.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Relaunch Now") { model.relaunch() }
                    }
                } else {
                    Text("Shared with System Settings › General › Language & Region › Applications.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                HStack(alignment: .firstTextBaseline) {
                    Button("Open User Guide") { model.openUserGuide() }
                    Text("Opens the guide for the current language on GitHub.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Font") {
                TextField("Latin font", text: $model.font.family)
                Slider(value: $model.font.size, in: 8...40, step: 1) { Text("Size \(Int(model.font.size))pt") }
                Toggle("Ligatures (-> => != …)", isOn: $model.font.ligatures)
                Slider(value: $model.font.lineHeightMultiple, in: 1.0...2.0, step: 0.05) {
                    Text("Line height ×\(model.font.lineHeightMultiple, specifier: "%.2f")")
                }
            }
            Section("Hangul") {
                TextField("Hangul font", text: $model.font.hangulFamily)
                Toggle("Hangul 2:1 width fix (apply the Hangul font to Hangul runs)", isOn: $model.font.hangulFix)
                Slider(value: $model.font.hangulScale, in: 1.0...1.5, step: 0.05) {
                    Text("Hangul scale ×\(model.font.hangulScale, specifier: "%.2f")")
                }
                Text(FontCascade.isInstalled(family: model.font.hangulFamily) ? "Installed" : "Not installed — using the system fallback")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Theme") {
                Toggle("Follow system appearance — Hyper Light for light, Hyper Dark for dark",
                       isOn: Binding(get: { model.themes.followsSystem }, set: { model.themes.setFollowsSystem($0) }))
                Picker("Theme", selection: Binding(get: { model.themes.current.id }, set: { model.themes.select(id: $0) })) {
                    Section("Light") { ForEach(model.themes.lightThemes) { Text($0.name).tag($0.id) } }
                    Section("Dark") { ForEach(model.themes.darkThemes) { Text($0.name).tag($0.id) } }
                }
                Text("Choosing a theme turns off Follow System. ⌥⌘] / ⌥⌘[ cycle through themes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Files") {
                LabeledContent("Current file", value: model.document.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                LabeledContent("Default document", value: MemoLocation.defaultLocalURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                LabeledContent("Snapshots", value: MemoDocument.snapshotDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                HStack {
                    Button("Open Default Document") { model.openDefaultDocument() }
                    Button("Open Snapshot Folder") { model.openSnapshotFolder() }
                }
            }
            QuickAppendSettingsSection(controller: model.quickAppend)   // quick append: 전역 단축키
            AppLockSettingsSection(controller: model.appLock)   // applock: Touch ID 잠금
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 800)
    }
}
