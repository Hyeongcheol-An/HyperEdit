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
                    ForEach(FindScope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 150)
                Image(systemName: "magnifyingglass").foregroundStyle(theme.foregroundMuted.color)
                TextField("찾을 내용 (Enter)", text: $model.searchQuery)
                    .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                    .focused($focused)
                    .onSubmit { model.runCurrentSearch() }
                    .frame(width: 320)
                optionToggle(".*", $model.searchOptions.regex, "정규식 (^ $ 는 줄 단위, 바꾸기에 $1 사용 가능)")
                optionToggle("Aa", $model.searchOptions.caseSensitive, "대소문자 구분")
                optionToggle("W", $model.searchOptions.wholeWord, "단어 단위")
                if model.findScope == .document {
                    smallButton("다음", "F3") { model.findNext() }
                    smallButton("이전", "⇧F3") { model.findPrevious() }
                    smallButton("모두 선택", "⌥⌘A — 매치를 멀티 커서로") { model.selectAllMatches() }.disabled(model.searchHits.isEmpty)
                    Toggle(isOn: $model.replaceVisible) { Image(systemName: "arrow.left.arrow.right") }
                        .toggleStyle(.button).controlSize(.small).help("바꾸기 (⌘R)")
                } else {
                    smallButton("찾기", "폴더 전체 검색") { model.runFindInFiles() }
                }
                if model.isSearching || model.isFileSearching { ProgressView().controlSize(.small) }
                Text(model.findScope == .document ? (model.searchHits.isEmpty ? "" : "\(model.searchHits.count)건") : model.fileSearchSummary)
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
                    TextField("바꿀 내용", text: $model.replaceText)
                        .textFieldStyle(.plain).font(.system(size: 12, design: .monospaced))
                        .onSubmit { model.replaceCurrent() }
                        .frame(width: 320)
                    smallButton("바꾸기", "선택된 매치를 바꾸고 다음으로") { model.replaceCurrent() }
                    smallButton("모두 바꾸기", "문서 전체 (⌘Z 한 번으로 되돌림)") { model.replaceAll() }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).frame(height: 26)
            } else if model.findScope == .files {
                HStack(spacing: 6) {
                    Color.clear.frame(width: 150)
                    Button { model.chooseFileSearchDirectory() } label: { Label("폴더 선택…", systemImage: "folder") }
                        .controlSize(.small).font(.system(size: 11)).help("검색할 폴더를 고릅니다 (하위 폴더 포함)")
                    Text(shortPath(model.fileSearchDirectory))
                        .font(.system(size: 11)).lineLimit(1).truncationMode(.middle).frame(maxWidth: 260, alignment: .leading)
                        .help(model.fileSearchDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    smallButton("현재 문서 폴더", "검색 폴더를 현재 문서가 있는 폴더로") { model.fileSearchDirectory = model.rootDirectory }
                    TextField("마스크: *.md;*.txt (비우면 전체)", text: $model.fileMask)
                        .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced)).frame(width: 200)
                        .onSubmit { model.runFindInFiles() }
                        .help("파일 이름 패턴, ; 로 여러 개 (대소문자 무시)")
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

    private func optionToggle(_ label: String, _ binding: Binding<Bool>, _ help: String) -> some View {
        Toggle(label, isOn: binding).toggleStyle(.button).controlSize(.small)
            .font(.system(size: 10, design: .monospaced)).help(help)
    }

    private func smallButton(_ title: String, _ help: String, action: @escaping () -> Void) -> some View {
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
            Text("\(line)")
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
