import SwiftUI
import HyperCore

/// 찾기 결과 창 (UltraEdit Find/Replace/Find in Files 계승)
struct SearchPanel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var caret: EditorCaret
    let theme: Theme
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1행: 범위 · 검색어 · 옵션 · 동작
            HStack(spacing: 6) {
                Picker("", selection: $model.findScope) {
                    ForEach(FindScope.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 150)
                Image(systemName: "magnifyingglass").foregroundStyle(theme.foregroundMuted.color)
                // 320 → 240: 영어 버튼 제목(Next/Prev/Select All)이 기본 창 폭에서 눌려 잘리지 않도록
                TextField("Find (Enter)", text: $model.searchQuery)
                    .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                    .focused($focused)
                    .onSubmit { model.runCurrentSearch() }
                    .frame(width: 240)
                optionToggle(".*", $model.searchOptions.regex, "Regular expression (^ $ match per line; $1 works in Replace)")
                optionToggle("Aa", $model.searchOptions.caseSensitive, "Match case")
                optionToggle("W", $model.searchOptions.wholeWord, "Whole word")
                if model.findScope == .document {
                    smallButton("Next", "F3") { model.findNext() }
                    smallButton("Prev", "⇧F3") { model.findPrevious() }
                    smallButton("Select All", "⌥⌘A — turn the matches into carets") { model.selectAllMatches() }.disabled(model.searchHits.isEmpty)
                    Toggle(isOn: $model.replaceVisible) { Image(systemName: "arrow.left.arrow.right") }
                        .toggleStyle(.button).controlSize(.small).help("Replace (⌘R)")
                } else {
                    smallButton("Find", "Search the whole folder") { model.runFindInFiles() }
                }
                if model.isSearching || model.isFileSearching { ProgressView().controlSize(.small) }
                Text(model.findScope == .document ? (model.searchHits.isEmpty ? "" : String(localized: "\(model.searchHits.count) hits")) : model.fileSearchSummary)
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.foregroundMuted.color).lineLimit(1)
                if let e = model.searchError { Text(e).font(.system(size: 11)).foregroundStyle(theme.errorColor.color).lineLimit(1) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).frame(height: 28)

            // 2행: 바꾸기 (문서 범위) 또는 폴더·마스크 (파일 범위)
            if model.findScope == .document, model.replaceVisible {
                HStack(spacing: 6) {
                    Color.clear.frame(width: 150)
                    Image(systemName: "arrow.left.arrow.right").foregroundStyle(theme.foregroundMuted.color)
                    TextField("Replace with", text: $model.replaceText)
                        .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                        .onSubmit { model.replaceCurrent() }
                        .frame(width: 240)
                    smallButton("Replace", "Replace the selected match and move to the next") { model.replaceCurrent() }
                    smallButton("Replace All", "Whole document (a single ⌘Z undoes it)") { model.replaceAll() }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).frame(height: 26)
            } else if model.findScope == .files {
                HStack(spacing: 6) {
                    Color.clear.frame(width: 150)
                    Button { model.chooseFileSearchDirectory() } label: { Label("Choose Folder…", systemImage: "folder") }
                        .controlSize(.small).font(.system(size: 11)).help("Choose the folder to search (subfolders included)")
                    Text(shortPath(model.fileSearchDirectory))
                        .font(.system(size: 11)).lineLimit(1).truncationMode(.middle).frame(maxWidth: 260, alignment: .leading)
                        .help(model.fileSearchDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    smallButton("Current Folder", "Search the folder of the current document") { model.fileSearchDirectory = model.rootDirectory }
                    // 자리표시자는 prompt(Text(String)) 로 — LocalizedStringKey 는 마크다운으로 해석돼 `*.md;*.txt` 의 * 가 사라진다
                    TextField("", text: $model.fileMask, prompt: Text(String(localized: "Mask: *.md;*.txt (empty = all)")))
                        .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).frame(width: 200)
                        .onSubmit { model.runFindInFiles() }
                        .help("File name patterns separated by ; (case-insensitive)")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).frame(height: 26)
            }
            theme.border.color.frame(height: 1)

            if model.findScope == .document {
                List(model.searchHits) { hit in
                    SearchHitRow(line: hit.line, text: hit.lineText, match: hit.matchInLine, file: nil, theme: theme,
                                 isCurrent: hit.range.location == caret.offset && hit.range.length == caret.selectionLength)
                        .contentShape(Rectangle())
                        .onTapGesture { model.jump(to: hit) }
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            } else {
                List(model.fileHits) { hit in
                    SearchHitRow(line: hit.line, text: hit.lineText, match: hit.matchInLine, file: hit.fileName, theme: theme, isCurrent: false)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { model.open(hit: hit) }
                        .onTapGesture { model.open(hit: hit) }
                        .help(hit.url.path)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
            }
        }
        .tint(theme.accent.color)   // 네이티브 컨트롤(세그먼트·토글 버튼)도 시스템 강조색 대신 테마 악센트를 쓴다
        .onChange(of: model.searchFocusToken) { _, _ in focused = true }
        .onChange(of: model.searchOptions) { _, _ in model.runCurrentSearch() }
    }

    /// 긴 경로는 마지막 두 구성 요소만 (전체 경로는 툴팁)
    private func shortPath(_ u: URL) -> String {
        let parts = u.pathComponents
        if parts.count <= 2 { return u.path.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
        return "…/" + parts.suffix(2).joined(separator: "/")
    }

    /// label 은 기호(.* Aa W)라 번역하지 않는다 — help 만 현지화
    private func optionToggle(_ label: String, _ binding: Binding<Bool>, _ help: LocalizedStringKey) -> some View {
        Toggle(label, isOn: binding).toggleStyle(.button).controlSize(.small)
            .font(.system(size: 10, design: .monospaced)).help(help)
    }

    private func smallButton(_ title: LocalizedStringKey, _ help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(title, action: action).controlSize(.small).font(.system(size: 11)).help(help)
    }
}

struct SearchHitRow: View {
    let line: Int
    let text: String
    let match: NSRange
    let file: String?
    let theme: Theme
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let file {
                Text(file).font(.system(size: 11, design: .monospaced)).foregroundStyle(theme.accent.color)
                    .frame(width: 140, alignment: .leading).lineLimit(1).truncationMode(.middle)
            }
            Text(verbatim: "\(line)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isCurrent ? theme.accent.color : theme.foregroundDim.color)
                .frame(width: 56, alignment: .trailing)
            Text(attributed)
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(theme.foreground.color)
                .lineLimit(1)
        }
        .padding(.vertical, 1)
        .background(isCurrent ? theme.selection.color.opacity(0.5) : Color.clear)
    }

    private var attributed: AttributedString {
        var a = AttributedString(text)
        if let r = Range(match, in: text),
           let lo = AttributedString.Index(r.lowerBound, within: a),
           let hi = AttributedString.Index(r.upperBound, within: a) {
            a[lo..<hi].backgroundColor = theme.selection.color
            a[lo..<hi].font = .system(size: 11.5, weight: .bold, design: .monospaced)
        }
        return a
    }
}
