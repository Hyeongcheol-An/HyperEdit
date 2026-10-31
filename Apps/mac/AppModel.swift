import SwiftUI
import AppKit
import Combine
import HyperCore

enum RibbonTab: String, CaseIterable, Identifiable {
    case home = "홈", edit = "편집", layout = "레이아웃", advanced = "고급", window = "창"
    var id: String { rawValue }
    /// 실행 인자(`--ribbon <key>`)용 영문 키
    var key: String {
        switch self { case .home: "home"; case .edit: "edit"; case .layout: "layout"; case .advanced: "advanced"; case .window: "window" }
    }
}

enum BottomTab: String, CaseIterable, Identifiable {
    case findResults = "찾기 결과", bookmarks = "북마크", output = "출력"
    var id: String { rawValue }
    var key: String { switch self { case .findResults: "find"; case .bookmarks: "bookmarks"; case .output: "output" } }
    var systemImage: String {
        switch self { case .findResults: "magnifyingglass"; case .bookmarks: "bookmark"; case .output: "terminal" }
    }
}

/// UltraEdit 편집 도구 (줄/선택 단위)
enum TextTool: String, CaseIterable {
    case deleteLine, duplicateLine, moveLineUp, moveLineDown, joinLines, reverseLines, numberLines
    case upper, lower, capitalize, invertCase
    case sortAsc, sortDesc, sortNumeric, dedupe, removeBlank
    case trimTrailing, trimBoth, tabsToSpaces, spacesToTabs
}

struct Replacement { let range: NSRange; let string: String }

enum EditorCommand {
    case selectRange(NSRange)
    case goToLine(Int)
    case goToEnd
    case insertTimestamp
    case focus
    case textTool(TextTool)
    case setWordWrap(Bool)
    case setLineNumbers(Bool)
    case undo, redo, selectAll, cut, copy, paste
    case setColumnMode(Bool)
    case insertColumnNumbers(start: Int, step: Int, zeroPad: Bool)
    case selectRanges([NSRange])
    case addNextOccurrence
    case replaceRanges([Replacement])
    /// 파일 전환 직전: 현재 파일의 캐럿·스크롤 위치를 저장
    case saveViewState
    /// 개발·셀프테스트용: 텍스트 뷰에 직접 접근
    case perform((HyperTextView) -> Void)
}

enum LeftTab: String, CaseIterable, Identifiable {
    case fileView = "파일", outline = "아웃라인", timeline = "타임라인"
    var id: String { rawValue }
    var key: String { switch self { case .fileView: "files"; case .outline: "outline"; case .timeline: "timeline" } }
    var systemImage: String {
        switch self { case .fileView: "folder"; case .outline: "list.bullet.indent"; case .timeline: "calendar" }
    }
}

enum FindScope: String, CaseIterable, Identifiable {
    case document = "현재 문서", files = "파일에서"
    var id: String { rawValue }
}

struct OutputLine: Identifiable {
    let id = UUID()
    let time: Date
    let text: String
}

/// 키 입력마다 바뀌는 상태만 따로 발행 — 상태바·아웃라인·타임라인만 구독하고 리본/패널은 다시 그리지 않는다
@MainActor
final class EditorCaret: ObservableObject {
    @Published var line = 1
    @Published var column = 1
    @Published var offset = 0
    @Published var selectionLength = 0
    @Published var multiCaretCount = 0
    @Published var columnBlockActive = false
}

@MainActor
final class AppModel: ObservableObject {
    let themes = ThemeStore()
    @Published var font: FontSettings { didSet { font.save() } }
    @Published private(set) var document: MemoDocument
    @Published private(set) var bookmarks: BookmarkStore

    /// 종료 처리(AppDelegate)가 동기 저장을 요청할 수 있도록
    nonisolated(unsafe) static weak var current: AppModel?

    // UI 상태 (리본 레이아웃)
    @Published var ribbonTab: RibbonTab = .home
    @Published var showFileView: Bool { didSet { AppDefaults.store.set(showFileView, forKey: "ui.showFileView") } }
    @Published var showBottomPanel: Bool { didSet { AppDefaults.store.set(showBottomPanel, forKey: "ui.showBottomPanel") } }
    @Published var bottomTab: BottomTab = .findResults
    @Published var leftTab: LeftTab = .fileView
    @Published var columnMode = false { didSet { editorCommands.send(.setColumnMode(columnMode)); log(columnMode ? "열 모드 켬 (⇧방향키/드래그로 블록 선택)" : "열 모드 끔") } }
    @Published var showInsertNumber = false
    @Published var insertNumberStart = "1"
    @Published var insertNumberStep = "1"

    // 바꾸기 / 파일에서 찾기
    @Published var findScope: FindScope = .document
    @Published var replaceVisible = false
    @Published var replaceText = ""
    @Published var fileSearchDirectory: URL
    @Published var fileMask = ""
    @Published var fileHits: [FileSearchHit] = []
    @Published var fileSearchSummary = ""
    @Published var isFileSearching = false

    // 아웃라인 / 타임라인
    @Published private(set) var outline: [OutlineItem] = []
    @Published private(set) var timeline: [TimelineItem] = []
    private var scanTask: Task<Void, Never>?
    private var fileSearchTask: Task<Void, Never>?
    @Published var wordWrap: Bool { didSet { AppDefaults.store.set(wordWrap, forKey: "ui.wordWrap"); editorCommands.send(.setWordWrap(wordWrap)) } }
    @Published var showLineNumbers: Bool { didSet { AppDefaults.store.set(showLineNumbers, forKey: "ui.lineNumbers"); editorCommands.send(.setLineNumbers(showLineNumbers)) } }
    @Published private(set) var output: [OutputLine] = []

    // 검색
    @Published var searchQuery = ""
    @Published var searchOptions = SearchOptions()
    @Published var searchHits: [SearchHit] = []
    @Published var searchError: String?
    @Published var isSearching = false
    @Published var searchFocusToken = 0

    // 캐럿 (별도 객체, 키 입력마다 발행)
    let caret = EditorCaret()
    var caretLine: Int { caret.line }
    var caretColumn: Int { caret.column }
    var caretOffset: Int { caret.offset }
    var selectionLength: Int { caret.selectionLength }
    var multiCaretCount: Int { caret.multiCaretCount }
    var columnBlockActive: Bool { caret.columnBlockActive }
    @Published var showGoToLine = false
    @Published var goToLineText = ""

    let editorCommands = PassthroughSubject<EditorCommand, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?

    init() {
        let d = AppDefaults.store
        font = FontSettings.load()
        showFileView = d.object(forKey: "ui.showFileView") as? Bool ?? true
        showBottomPanel = d.object(forKey: "ui.showBottomPanel") as? Bool ?? true
        wordWrap = d.object(forKey: "ui.wordWrap") as? Bool ?? true
        showLineNumbers = d.object(forKey: "ui.lineNumbers") as? Bool ?? true
        let url = MemoLocation.resolveDefault()
        let doc = MemoDocument(url: url)
        document = doc
        bookmarks = BookmarkStore(fileURL: doc.url)
        fileSearchDirectory = doc.url.deletingLastPathComponent()
        doc.load()
        bind()
        Self.current = self
        log("HyperEdit 시작 · \(doc.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
        applyLaunchOptions()
    }

    private func bind() {
        cancellables.removeAll()
        // 문서(상태·dirty·줄 인덱스)는 전달하지 않는다 — 필요한 뷰가 @ObservedObject 로 직접 구독
        bookmarks.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        themes.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        // 시스템 라이트/다크 전환 → 테마 저장소에 알림 (시스템 따르기 모드면 Hyper Light/Dark 자동 전환)
        NSApplication.shared.publisher(for: \.effectiveAppearance)
            .map { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
            .removeDuplicates()
            .sink { [weak self] dark in self?.themes.systemAppearanceChanged(isDark: dark) }
            .store(in: &cancellables)
        document.$status.removeDuplicates().filter { !$0.isEmpty }
            .sink { [weak self] s in self?.log(s) }.store(in: &cancellables)
        document.$errorMessage.compactMap { $0 }.removeDuplicates()
            .sink { [weak self] e in self?.log("오류: " + e) }.store(in: &cancellables)
        document.$lineIndex
            .debounce(for: .milliseconds(1200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rescanStructure() }.store(in: &cancellables)
    }

    /// 아웃라인·타임라인 재계산 (백그라운드, 텍스트 스냅샷 기준)
    func rescanStructure() {
        scanTask?.cancel()
        let text = document.textStorage.string
        let isMD = document.url.pathExtension.lowercased() == "md"
        scanTask = Task { [weak self] in
            let (o, t) = await Task.detached(priority: .utility) { () -> ([OutlineItem], [TimelineItem]) in
                let idx = LineIndex(text: text)
                return (OutlineScanner.outline(text, index: idx, isMarkdown: isMD), OutlineScanner.timeline(text, index: idx))
            }.value
            guard let self, !Task.isCancelled else { return }
            if o != self.outline { self.outline = o }
            if t != self.timeline { self.timeline = t }
        }
    }

    func log(_ text: String) {
        output.append(OutputLine(time: Date(), text: text))
        if output.count > 500 { output.removeFirst(output.count - 500) }
    }

    var rootDirectory: URL { document.url.deletingLastPathComponent() }
    var zoomPercent: Int { Int((font.size / 14 * 100).rounded()) }

    // MARK: 파일

    /// 파일 열기. MemoDocument/BookmarkStore 객체와 NSTextStorage 는 그대로 두고 내용만 바꾼다
    /// (스토리지 교체 반복 시 TextKit 2 가 퇴화하는 문제 + 창 전체 재구성을 피함).
    func open(url: URL) {
        guard TextFileDetector.isLikelyText(url) else {
            log("텍스트 파일이 아니라 기본 앱으로 엽니다 · \(url.lastPathComponent)")
            NSWorkspace.shared.open(url)
            return
        }
        Perf.measure("AppModel.open total") {
            editorCommands.send(.saveViewState)
            // 이전 파일의 미저장 편집은 switchTo 가 동기로 저장한다 (비동기 저장과의 경쟁 없음)
            Perf.measure("MemoDocument.switchTo") { document.switchTo(url: url) }
            bookmarks.switchTo(fileURL: document.url)
            MemoLocation.remember(document.url)
            if !searchHits.isEmpty { searchHits = [] }
            if searchError != nil { searchError = nil }
            rescanStructure()
            log("열기 · \(document.url.path)")
        }
    }

    /// 파일 검색 결과에서 열기: 로드 후 해당 줄로 (에디터 재바인딩 뒤에 점프)
    func open(hit: FileSearchHit) {
        if hit.url.standardizedFileURL != document.url.standardizedFileURL { open(url: hit.url) }
        let line = hit.line
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.jump(toLine: line) }
    }

    func presentOpenPanel() {
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = false; p.allowsMultipleSelection = false
        p.directoryURL = rootDirectory
        p.message = "열 텍스트 파일을 고르세요"
        if p.runModal() == .OK, let u = p.url { open(url: u) }
    }

    /// 새 문서(⌘N): 위치·이름을 고르면 빈 파일을 만들어 연다. 기본 폴더는 현재 문서의 폴더.
    func newDocument() {
        let p = NSSavePanel()
        p.directoryURL = rootDirectory
        p.nameFieldStringValue = "untitled.md"
        p.title = "새 문서"
        p.message = "새 텍스트 파일의 이름과 위치"
        p.canCreateDirectories = true
        guard p.runModal() == .OK, let u = p.url else { return }
        if !FileManager.default.fileExists(atPath: u.path) { FileManager.default.createFile(atPath: u.path, contents: Data()) }
        open(url: u)
    }

    func revealInFinder() { NSWorkspace.shared.activateFileViewerSelecting([document.url]) }
    func openSnapshotFolder() {
        let dir = MemoDocument.snapshotDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }
    func saveNow() { document.save() }
    func reloadFromDisk() { document.reloadFromDisk(); log("디스크에서 다시 읽음") }

    // MARK: 검색

    func findInEditor() {
        showBottomPanel = true
        bottomTab = .findResults
        searchFocusToken += 1
    }

    func runSearch() {
        searchTask?.cancel()
        let q = searchQuery, opts = searchOptions
        guard !q.isEmpty else { searchHits = []; searchError = nil; return }
        let text = document.textStorage.string
        isSearching = true
        searchTask = Task { [weak self] in
            // 줄 인덱스는 같은 스냅샷에서 새로 만든다 — 편집 직후 250ms 안에는 document.lineIndex 가 낡아 범위 밖 접근으로 크래시할 수 있다
            let outcome: ([SearchHit], String?) = await Task.detached(priority: .userInitiated) {
                do { return (try SearchEngine.search(q, in: text, index: LineIndex(text: text), options: opts), nil) }
                catch SearchError.invalidRegex(let m) { return ([], "정규식 오류: \(m)") }
                catch { return ([], error.localizedDescription) }
            }.value
            guard let self, !Task.isCancelled else { return }
            self.isSearching = false
            self.searchHits = outcome.0
            self.searchError = outcome.1
            self.log("찾기 '\(q)' · \(outcome.0.count)건" + (outcome.1.map { " · " + $0 } ?? ""))
        }
    }

    func showReplace() {
        findScope = .document
        replaceVisible = true
        findInEditor()
    }

    func showFindInFiles() {
        findScope = .files
        showBottomPanel = true
        bottomTab = .findResults
        searchFocusToken += 1
    }

    func chooseFileSearchDirectory() {
        let p = NSOpenPanel()
        p.canChooseFiles = false; p.canChooseDirectories = true; p.allowsMultipleSelection = false
        p.directoryURL = fileSearchDirectory
        p.message = "검색할 폴더"
        if p.runModal() == .OK, let u = p.url { fileSearchDirectory = u }
    }

    func runFindInFiles() {
        fileSearchTask?.cancel()
        let q = searchQuery, opts = searchOptions, dir = fileSearchDirectory, mask = fileMask
        guard !q.isEmpty else { fileHits = []; fileSearchSummary = ""; return }
        isFileSearching = true
        fileSearchSummary = "검색 중…"
        fileSearchTask = Task { [weak self] in
            let outcome: (FileSearchResult?, String?) = await Task.detached(priority: .userInitiated) {
                do { return (try FileSearch.search(q, in: dir, mask: mask, options: opts, isCancelled: { Task.isCancelled }), nil) }
                catch SearchError.invalidRegex(let m) { return (nil, "정규식 오류: \(m)") }
                catch { return (nil, error.localizedDescription) }
            }.value
            guard let self, !Task.isCancelled else { return }
            self.isFileSearching = false
            if let r = outcome.0 {
                self.fileHits = r.hits
                self.fileSearchSummary = "\(r.hits.count)건 · \(r.filesMatched)/\(r.filesScanned) 파일" + (r.truncated ? " · 일부만 표시" : "")
                self.searchError = nil
            } else {
                self.fileHits = []
                self.fileSearchSummary = ""
                self.searchError = outcome.1
            }
            self.log("파일에서 찾기 '\(q)' @ \(dir.lastPathComponent)\(mask.isEmpty ? "" : " [\(mask)]") · \(self.fileSearchSummary)")
        }
    }

    /// 현재 범위의 검색/바꾸기 실행 (Enter)
    func runCurrentSearch() {
        if findScope == .files { runFindInFiles() } else { runSearch() }
    }

    func findNext() {
        guard !searchHits.isEmpty else { runSearch(); return }
        let from = caretOffset + (selectionLength > 0 ? 1 : 0)
        if let h = searchHits.first(where: { $0.range.location >= from }) ?? searchHits.first { jump(to: h) }
    }

    func findPrevious() {
        guard !searchHits.isEmpty else { runSearch(); return }
        if let h = searchHits.last(where: { $0.range.location < caretOffset }) ?? searchHits.last { jump(to: h) }
    }

    /// 선택된 매치 하나를 바꾸고 다음으로. 선택이 매치가 아니면 다음 매치로만 이동.
    func replaceCurrent() {
        let text = document.textStorage.string
        let sel = NSRange(location: caretOffset, length: selectionLength)
        // 선택이 정확히 매치여야 바꾼다. 투명 경계 옵션이 없으면 \b·^·$ 가 선택 가장자리에서 맞아 'concat' 안의 'cat' 도 바뀐다
        guard sel.length > 0, let re = try? SearchEngine.makeRegex(searchQuery, options: searchOptions),
              let m = re.firstMatch(in: text, options: [.anchored, .withTransparentBounds, .withoutAnchoringBounds], range: sel), m.range == sel else { findNext(); return }
        let repl = SearchEngine.replacement(for: sel, in: text, query: searchQuery, options: searchOptions, template: replaceText)
        editorCommands.send(.replaceRanges([Replacement(range: sel, string: repl)]))
        log("바꾸기 · \(caretLine)줄")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self else { return }
            self.runSearch()
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.findNext()
        }
    }

    func replaceAll() {
        let text = document.textStorage.string
        guard let hits = try? SearchEngine.search(searchQuery, in: text, index: LineIndex(text: text), options: searchOptions, limit: 1_000_000), !hits.isEmpty else {
            log("모두 바꾸기 · 매치 없음"); return
        }
        let reps = hits.map { Replacement(range: $0.range, string: SearchEngine.replacement(for: $0.range, in: text, query: searchQuery, options: searchOptions, template: replaceText)) }
        editorCommands.send(.replaceRanges(reps))
        log("모두 바꾸기 '\(searchQuery)' → '\(replaceText)' · \(reps.count)건")
        Task { [weak self] in try? await Task.sleep(nanoseconds: 400_000_000); self?.runSearch() }
    }

    /// 모든 매치를 멀티 커서로 선택
    func selectAllMatches() {
        guard !searchHits.isEmpty else { return }
        editorCommands.send(.selectRanges(searchHits.map(\.range)))
        log("매치 \(searchHits.count)개를 멀티 선택")
    }

    func insertColumnNumbers() {
        let start = Int(insertNumberStart.trimmingCharacters(in: .whitespaces)) ?? 1
        let step = Int(insertNumberStep.trimmingCharacters(in: .whitespaces)) ?? 1
        editorCommands.send(.insertColumnNumbers(start: start, step: step, zeroPad: true))
        showInsertNumber = false
    }

    func showOutline() { leftTab = .outline; showFileView = true }
    func showTimeline() { leftTab = .timeline; showFileView = true }

    func jump(to hit: SearchHit) { editorCommands.send(.selectRange(hit.range)) }
    func jump(toLine n: Int) { editorCommands.send(.goToLine(max(1, min(n, document.lineIndex.lineCount)))) }
    func jump(to bookmark: Bookmark) { jump(toLine: bookmark.line) }
    func goToEnd() { editorCommands.send(.goToEnd) }
    func insertTimestamp() { editorCommands.send(.insertTimestamp) }
    func focusEditor() { editorCommands.send(.focus) }
    func textTool(_ tool: TextTool) { editorCommands.send(.textTool(tool)) }
    func send(_ cmd: EditorCommand) { editorCommands.send(cmd) }

    func submitGoToLine() {
        if let n = Int(goToLineText.trimmingCharacters(in: .whitespaces)) { jump(toLine: n) }
        showGoToLine = false
    }

    // MARK: 캐럿 / 북마크

    func updateCaret(range: NSRange) {
        let idx = document.lineIndex
        let line = idx.lineNumber(forUTF16Offset: range.location)
        let col = idx.column(forUTF16Offset: range.location)
        if caret.offset != range.location { caret.offset = range.location }
        if caret.selectionLength != range.length { caret.selectionLength = range.length }
        if caret.line != line { caret.line = line }
        if caret.column != col { caret.column = col }
    }

    func toggleBookmarkAtCaret() {
        let line = caretLine
        let r = document.lineIndex.range(ofLine: line)
        let ns = document.textStorage.string as NSString
        let safe = NSIntersectionRange(r, NSRange(location: 0, length: ns.length))
        let preview = String(ns.substring(with: safe).trimmingCharacters(in: .whitespaces).prefix(60))
        let added = bookmarks.toggle(line: line, preview: preview)
        log(added ? "북마크 추가 · \(line)줄" : "북마크 제거 · \(line)줄")
    }

    func nextBookmark() {
        let lines = bookmarks.bookmarks.map(\.line)
        guard !lines.isEmpty else { return }
        jump(toLine: lines.first { $0 > caretLine } ?? lines[0])
    }

    func previousBookmark() {
        let lines = bookmarks.bookmarks.map(\.line)
        guard !lines.isEmpty else { return }
        jump(toLine: lines.last { $0 < caretLine } ?? lines[lines.count - 1])
    }

    // MARK: 외관

    func adjustFontSize(_ delta: Double) { font.size = min(40, max(8, font.size + delta)) }
    func resetFontSize() { font.size = 14 }
    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    func toggleFullScreen() { NSApp.keyWindow?.toggleFullScreen(nil) }

    /// 기본 문서(~/Documents/HyperEdit/notes.md) 열기 — 없으면 환영 문서로 생성
    func openDefaultDocument() {
        MemoLocation.ensureDefaultDocument()
        open(url: MemoLocation.defaultLocalURL)
    }

    // MARK: 실행 인자 (개발·스크린샷 자동화)

    /// `--theme <id>` `--follow-system-theme` `--ribbon <home|edit|layout|advanced|window>` `--left <files|outline|timeline>`
    /// `--bottom <find|bookmarks|output>` `--hide-left` `--hide-bottom` `--search <q>` `--replace [--replace-with <s>]` `--find-in-files`
    /// `--column` `--goto <line>`
    private func applyLaunchOptions() {
        if let t = LaunchOptions.value("--theme") { themes.select(id: t) }
        if LaunchOptions.has("--follow-system-theme") { themes.setFollowsSystem(true) }
        if let r = LaunchOptions.value("--ribbon"), let tab = RibbonTab.allCases.first(where: { $0.key == r }) { ribbonTab = tab }
        if let l = LaunchOptions.value("--left"), let tab = LeftTab.allCases.first(where: { $0.key == l }) { leftTab = tab; showFileView = true }
        if let b = LaunchOptions.value("--bottom"), let tab = BottomTab.allCases.first(where: { $0.key == b }) { bottomTab = tab; showBottomPanel = true }
        if LaunchOptions.has("--hide-left") { showFileView = false }
        if LaunchOptions.has("--hide-bottom") { showBottomPanel = false }
        if LaunchOptions.has("--find-in-files") { findScope = .files; showBottomPanel = true; bottomTab = .findResults }
        if LaunchOptions.has("--replace") { replaceVisible = true; replaceText = LaunchOptions.value("--replace-with") ?? "" }
        if let q = LaunchOptions.value("--search") {
            searchQuery = q; showBottomPanel = true; bottomTab = .findResults
            if findScope == .files { runFindInFiles() } else { runSearch() }
        }
        if LaunchOptions.has("--column") { columnMode = true }
        if let g = LaunchOptions.value("--goto"), let n = Int(g) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.jump(toLine: n) }
        }
    }
}

/// 명령줄 인자 조회 도우미 (개발·셀프테스트·스크린샷용)
enum LaunchOptions {
    static func has(_ flag: String) -> Bool { CommandLine.arguments.contains(flag) }
    static func value(_ flag: String) -> String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: flag), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
}
