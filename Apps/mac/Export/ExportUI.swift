import SwiftUI
import HyperCore

// export: 파일 메뉴 항목 + 저장 패널 액세서리(테마 · 줄 번호). 로직은 Exporter.swift.
// UI 문자열은 영어 키(LocalizedStringKey) + Localizable.xcstrings 의 한국어 번역 (l10n/export.ko.json).

/// 파일 메뉴 끝(가져오기/내보내기 자리)에 "Export as HTML…" / "Export as PDF…" — 단축키 없음
struct ExportCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Divider()
            Button("Export as HTML…") { model.presentExportPanel(format: .html) }
            Button("Export as PDF…") { model.presentExportPanel(format: .pdf) }
        }
    }
}

/// 저장 패널이 열려 있는 동안 액세서리와 공유하는 선택값
@MainActor
final class ExportPanelSettings: ObservableObject {
    @Published var options: ExportOptions
    init(options: ExportOptions) { self.options = options }
}

/// NSSavePanel.accessoryView: Picker "Theme"(Current / Hyper Light / Hyper Dark) + Toggle "Line numbers"(코드·메모용, 마크다운이면 비활성)
struct ExportAccessoryView: View {
    @ObservedObject var settings: ExportPanelSettings
    let isMarkdown: Bool

    var body: some View {
        HStack(spacing: 16) {
            Picker("Theme", selection: $settings.options.theme) {
                Text("Current").tag(ExportTheme.current)
                Text(verbatim: "Hyper Light").tag(ExportTheme.light)   // 테마 이름은 고유명사 — 번역하지 않는다
                Text(verbatim: "Hyper Dark").tag(ExportTheme.dark)
            }
            .fixedSize()
            .help("Colors of the exported file — the theme you are using now, or a fixed light / dark palette")
            Toggle("Line numbers", isOn: $settings.options.lineNumbers)
                .disabled(isMarkdown)
                .help(isMarkdown ? "Line numbers apply to notes and code files, not to rendered Markdown" : "Add a line-number column to the exported code or notes")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
