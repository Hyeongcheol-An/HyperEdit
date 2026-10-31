import SwiftUI
import HyperCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Form {
            Section("폰트") {
                TextField("영문 폰트", text: $model.font.family)
                Slider(value: $model.font.size, in: 8...40, step: 1) { Text("크기 \(Int(model.font.size))pt") }
                Toggle("리거처 (-> => != …)", isOn: $model.font.ligatures)
                Slider(value: $model.font.lineHeightMultiple, in: 1.0...2.0, step: 0.05) {
                    Text("줄 높이 ×\(model.font.lineHeightMultiple, specifier: "%.2f")")
                }
            }
            Section("한글") {
                TextField("한글 폰트", text: $model.font.hangulFamily)
                Toggle("한글 폭 2:1 보정 (한글 런에 한글 폰트를 직접 적용)", isOn: $model.font.hangulFix)
                Slider(value: $model.font.hangulScale, in: 1.0...1.5, step: 0.05) {
                    Text("한글 배율 ×\(model.font.hangulScale, specifier: "%.2f")")
                }
                Text(FontCascade.isInstalled(family: model.font.hangulFamily) ? "설치됨" : "설치되지 않음 — 시스템 폴백 사용")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("테마") {
                Toggle("시스템 외형 따르기 — 라이트는 Hyper Light, 다크는 Hyper Dark",
                       isOn: Binding(get: { model.themes.followsSystem }, set: { model.themes.setFollowsSystem($0) }))
                Picker("테마", selection: Binding(get: { model.themes.current.id }, set: { model.themes.select(id: $0) })) {
                    Section("라이트") { ForEach(model.themes.lightThemes) { Text($0.name).tag($0.id) } }
                    Section("다크") { ForEach(model.themes.darkThemes) { Text($0.name).tag($0.id) } }
                }
                Text("테마를 직접 고르면 시스템 따르기가 꺼집니다. ⌥⌘] / ⌥⌘[ 로 순환.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("파일") {
                LabeledContent("현재 파일", value: model.document.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                LabeledContent("기본 문서", value: MemoLocation.defaultLocalURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                LabeledContent("스냅샷", value: MemoDocument.snapshotDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                HStack {
                    Button("기본 문서 열기") { model.openDefaultDocument() }
                    Button("스냅샷 폴더 열기") { model.openSnapshotFolder() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 520)
    }
}
