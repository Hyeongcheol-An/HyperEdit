import SwiftUI
import HyperCore

/// 찾기 결과 창 (UltraEdit Find/Replace/Find in Files 계승)
struct SearchPanel: View {
    @EnvironmentObject var model: AppModel
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
                // 입력창은 FindFields 만 구독한다 — 글자마다 창 전체가 다시 평가되지 않게 (perf). Enter 가 확정하고 검색한다
                // 빠른 찾기(UltraEdit Quick Find 식): 글자를 치면 150 ms 뒤 검색해 첫 매치를 선택, Enter 다음 / ⇧Enter 이전 (포커스 유지), Esc 닫기 + 강조 제거
                FindTextField(fields: model.findFields, keyPath: \.query, title: String(localized: "Find (Enter)"), focus: $focused,
                              onChange: { _ in if focused { model.quickFindTextChanged() } }, onSubmit: { model.submitFind() })   // 포커스 없이 바뀐 값은 모델이 밀어 넣은 것
                    .onKeyPress(keys: [.return]) { press in
                        guard press.modifiers.contains(.shift), !Self.isComposingIME else { return .ignored }   // 보통 Enter 는 onSubmit
                        model.findPrevious(focusEditor: false); return .handled
                    }
                    .onKeyPress(.escape) {
                        if Self.isComposingIME { return .ignored }   // 일본어·중국어 변환 취소용 Esc 는 입력기에게
                        model.closeQuickFind(); return .handled
                    }
                    .font(.system(size: 12, design: .monospaced))
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
                // 결과가 지금 검색어의 것이면 0건도 "0 hits" 로 — 아직 검색 전과 구분 (UltraEdit 은 입력란을 빨갛게)
                Text(model.findScope == .document
                     ? (model.searchHits.isEmpty && !(model.hitsQuery != nil && model.hitsQuery == model.searchQuery && !model.searchQuery.isEmpty) ? "" : String(localized: "\(model.searchHits.count) hits"))
                     : model.fileSearchSummary)
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
                    FindTextField(fields: model.findFields, keyPath: \.replacement, title: String(localized: "Replace with"), onSubmit: { model.replaceCurrent() })
                        .font(.system(size: 12, design: .monospaced))
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
                    // 자리표시자는 String 으로 — LocalizedStringKey 는 마크다운으로 해석돼 `*.md;*.txt` 의 * 가 사라진다
                    FindTextField(fields: model.findFields, keyPath: \.mask, title: String(localized: "Mask: *.md;*.txt (empty = all)"), onSubmit: { model.runFindInFiles() })
                        .font(.system(size: 11, design: .monospaced)).frame(width: 200)
                        .help("File name patterns separated by ; (case-insensitive)")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8).frame(height: 26)
            }
            theme.border.color.frame(height: 1)

            // 결과 목록은 NSTableView (SearchResultsTable) — SwiftUI List 는 1만 건 재발행에 230 ms, 캐럿 추적에 키 입력당 ~10 ms 를 썼다 (perf)
            if model.findScope == .document {
                SearchResultsTable(items: model.searchHits, generation: model.searchGeneration, resetScrollToken: model.searchRequestGeneration, theme: theme,
                                   caret: model.caret, onSelect: { model.jump(to: $0) }, tooltip: nil)
            } else {
                SearchResultsTable(items: model.fileHits, generation: model.fileSearchGeneration, resetScrollToken: model.fileSearchGeneration, theme: theme,
                                   caret: nil, onSelect: { model.open(hit: $0) }, tooltip: { $0.url.path })
            }
        }
        .tint(theme.accent.color)   // 네이티브 컨트롤(세그먼트·토글 버튼)도 시스템 강조색 대신 테마 악센트를 쓴다
        .onChange(of: model.searchFocusToken) { _, _ in model.pendingFindFocus = false; focused = true }
        .onChange(of: focused) { _, f in if f { model.quickFindFocusGained() } else { model.quickFindFocusLost() } }   // 앵커는 포커스와 함께
        .onAppear {   // ⌘F 가 패널을 새로 만든 경우: 새 뷰의 onChange(searchFocusToken) 은 발화하지 않는다
            if model.pendingFindFocus { model.pendingFindFocus = false; DispatchQueue.main.async { focused = true } }
        }
        .onChange(of: model.searchOptions) { _, _ in model.runCurrentSearch() }
    }

    /// 입력기가 글자를 조합 중인가 (일본어·중국어 변환 중 Esc·⇧Enter 는 입력기가 처리해야 한다)
    private static var isComposingIME: Bool { (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true }

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

/// 찾기 패널의 입력창 하나 — `FindFields` 만 구독하므로 글자를 쳐도 이 뷰만 다시 그려진다 (perf: 모델 바인딩이면 창 전체가 키 입력당 20 ms 이상)
struct FindTextField: View {
    @ObservedObject var fields: FindFields
    let keyPath: ReferenceWritableKeyPath<FindFields, String>
    let title: String                          // 자리표시자 (이미 현지화된 String — 마크다운 해석 없음)
    var focus: FocusState<Bool>.Binding? = nil
    var onChange: ((String) -> Void)? = nil    // 글자가 바뀔 때 (빠른 찾기)
    let onSubmit: () -> Void

    private var text: Binding<String> { Binding(get: { fields[keyPath: keyPath] }, set: { fields[keyPath: keyPath] = $0 }) }

    var body: some View {
        Group {
            if let focus {
                TextField(title, text: text).textFieldStyle(.plain).focused(focus).onSubmit(onSubmit)
            } else {
                TextField(title, text: text).textFieldStyle(.plain).onSubmit(onSubmit)
            }
        }
        .onChange(of: fields[keyPath: keyPath]) { _, v in onChange?(v) }
    }
}
