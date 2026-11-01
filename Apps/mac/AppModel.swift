import SwiftUI
import AppKit
import Combine
import HyperCore

// 탭 이름 등 UI 문자열은 영어 키(LocalizedStringKey) + Apps/mac/Localizable.xcstrings 의 한국어 번역으로 표시한다.
enum RibbonTab: String, CaseIterable, Identifiable {
    case home, edit, layout, advanced, window
    var id: String { rawValue }
    /// 실행 인자(`--ribbon <key>`)용 영문 키
    var key: String {
        switch self { case .home: "home"; case .edit: "edit"; case .layout: "layout"; case .advanced: "advanced"; case .window: "window" }
    }
    /// 탭 제목
    var label: LocalizedStringKey {
        switch self { case .home: "Home"; case .edit: "Edit"; case .layout: "Layout"; case .advanced: "Advanced"; case .window: "Window" }
    }
    /// 보기 메뉴의 "리본: …" 항목
    var menuLabel: LocalizedStringKey {
        switch self { case .home: "Ribbon: Home"; case .edit: "Ribbon: Edit"; case .layout: "Ribbon: Layout"; case .advanced: "Ribbon: Advanced"; case .window: "Ribbon: Window" }
    }
}

enum BottomTab: String, CaseIterable, Identifiable {
    case findResults, bookmarks, output
    var id: String { rawValue }
    var key: String { switch self { case .findResults: "find"; case .bookmarks: "bookmarks"; case .output: "output" } }
    var label: LocalizedStringKey {
        switch self { case .findResults: "Find Results"; case .bookmarks: "Bookmarks"; case .output: "Output" }
    }
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
    /// 즉석 계산(⌃⌘=) · 열 맞춤(⌃⌘T)
    case calculate, alignColumns
    /// 주석 토글(⌘/)
    case toggleComment   // comment
    /// JSON 정리(⌃⌘J) · 한 줄로
    case formatJSON, minifyJSON   // json
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
    case setSyntaxHighlighting(Bool)
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
    /// 접기: 캐럿 영역 접기/펼치기, 전체 접기/펼치기, 특정 줄 토글(거터·실행 인자)   // fold
    case fold, unfold, foldAll, unfoldAll
    case toggleFold(line: Int)
}

enum LeftTab: String, CaseIterable, Identifiable {
    case fileView, outline, timeline
    var id: String { rawValue }
    var key: String { switch self { case .fileView: "files"; case .outline: "outline"; case .timeline: "timeline" } }
    var label: LocalizedStringKey {
        switch self { case .fileView: "Files"; case .outline: "Outline"; case .timeline: "Timeline" }
    }
    var systemImage: String {
        switch self { case .fileView: "folder"; case .outline: "list.bullet.indent"; case .timeline: "calendar" }
    }
}

enum FindScope: String, CaseIterable, Identifiable {
    case document, files
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self { case .document: "Document"; case .files: "In Files" }
    }
}

struct OutputLine: Identifiable {
    let id = UUID()
    let time: Date
    let text: String
    /// 출력 패널에서 빨간색으로 표시 (문서 오류)
    var isError = false
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
    /// 편집기에 보이는 첫 줄(1-based). 스크롤마다 ~60 ms 스로틀로 갱신 — 마크다운 미리보기가 따라간다
    @Published var firstVisibleLine = 1
}

@MainActor
final class AppModel: ObservableObject {
    let themes = ThemeStore()
    @Published var font: FontSettings { didSet { font.save() } }
    @Published private(set) var document: MemoDocument
    @Published private(set) var bookmarks: BookmarkStore

    /// 종료 처리(AppDelegate)가 동기 저장을 요청할 수 있도록
    nonisolated(unsafe) static weak var current: AppModel?
    /// `--show-settings` 가 띄운 캡처용 설정 창 (유지용)
    nonisolated(unsafe) static var snapshotSettingsWindow: NSWindow?

    // UI 상태 (리본 레이아웃)
    @Published var ribbonTab: RibbonTab = .home
    @Published var showFileView: Bool { didSet { AppDefaults.store.set(showFileView, forKey: "ui.showFileView") } }
    @Published var showBottomPanel: Bool { didSet { AppDefaults.store.set(showBottomPanel, forKey: "ui.showBottomPanel") } }
    /// 마크다운 분할 미리보기 (⇧⌘P). 파일 확장자에 따라 자동으로 켜지 않는다 — 사용자가 마지막으로 둔 상태(기본 꺼짐)를 유지한다.
    @Published var showMarkdownPreview: Bool {
        didSet {
            AppDefaults.store.set(showMarkdownPreview, forKey: "ui.markdownPreview")
            log(showMarkdownPreview ? String(localized: "Markdown preview on") : String(localized: "Markdown preview off"))
        }
    }
    @Published var bottomTab: BottomTab = .findResults
    @Published var leftTab: LeftTab = .fileView
    @Published var columnMode = false { didSet { editorCommands.send(.setColumnMode(columnMode)); log(columnMode ? String(localized: "Column mode on (⇧arrows / drag to select a block)") : String(localized: "Column mode off")) } }
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
    /// 구문 색 (파일 종류별 토큰 색). 렌더링 속성만 바꾸므로 문서·undo 에는 영향 없음
    @Published var syntaxHighlighting: Bool {
        didSet {
            guard syntaxHighlighting != oldValue else { return }
            AppDefaults.store.set(syntaxHighlighting, forKey: "ui.syntaxHighlighting")
            editorCommands.send(.setSyntaxHighlighting(syntaxHighlighting))
            log(syntaxHighlighting ? String(localized: "Syntax colors on · \(languageName)") : String(localized: "Syntax colors off"))
        }
    }
    /// 현재 문서의 구문 언어 이름 (상태바) — 확장자로 결정
    var languageName: String { GrammarRegistry.languageName(for: document.url) }
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
    /// 스크롤바 마커 — 편집기 오른쪽 가장자리에 검색 매치·북마크·캐럿 줄·접힌 머리 줄 (markers)
    @Published var showScrollMarkers: Bool {
        didSet {
            guard showScrollMarkers != oldValue else { return }
            AppDefaults.store.set(showScrollMarkers, forKey: "ui.scrollMarkers")
            log(showScrollMarkers ? String(localized: "Scrollbar markers on") : String(localized: "Scrollbar markers off"))
        }
    }

    /// 인터페이스 언어 (설정 › Language). AppleLanguages 에 저장되고 재실행 뒤 적용된다 (AppLanguage 참고)
    @Published var language: AppLanguage = AppLanguage.stored {
        didSet {
            guard language != oldValue else { return }
            AppLanguage.store(language)
            if AppLanguage.needsRelaunch(for: language) {
                log(String(localized: "Interface language: \(language.nativeName) — relaunch HyperEdit to apply"))
            } else {
                log(String(localized: "Interface language: \(language.nativeName)"))
            }
        }
    }
    /// 선택한 언어가 지금 보이는 언어와 다른가 (설정 화면의 '지금 재실행' 버튼)
    var languageNeedsRelaunch: Bool { AppLanguage.needsRelaunch(for: language) }
    /// 저장 → 종료 → 같은 앱 재실행 (언어 적용)
    func relaunch() { AppLanguage.relaunch() }
    /// 지금 보이는 언어의 사용자 가이드(GitHub)를 브라우저로
    func openUserGuide() { NSWorkspace.shared.open(AppLanguage.running.guideURL) }

    let editorCommands = PassthroughSubject<EditorCommand, Never>()
    private var cancellables = Set<AnyCancellable>()
    private var searchTask: Task<Void, Never>?
    let macros = MacroRecorder()   // macro

    // snippets
    let snippets = SnippetStore(directory: SnippetStore.launchDirectory)
    @Published var showSnippetPicker = false

    init() {
        let d = AppDefaults.store
        font = FontSettings.load()
        showFileView = d.object(forKey: "ui.showFileView") as? Bool ?? true
        showBottomPanel = d.object(forKey: "ui.showBottomPanel") as? Bool ?? true
        wordWrap = d.object(forKey: "ui.wordWrap") as? Bool ?? true
        showLineNumbers = d.object(forKey: "ui.lineNumbers") as? Bool ?? true
        showMarkdownPreview = d.object(forKey: "ui.markdownPreview") as? Bool ?? false
        syntaxHighlighting = LaunchOptions.has("--no-highlight") ? false : (d.object(forKey: "ui.syntaxHighlighting") as? Bool ?? true)
        showScrollMarkers = d.object(forKey: "ui.scrollMarkers") as? Bool ?? true   // markers
        let url = MemoLocation.resolveDefault()
        let doc = MemoDocument(url: url)
        document = doc
        bookmarks = BookmarkStore(fileURL: doc.url)
        fileSearchDirectory = doc.url.deletingLastPathComponent()
        doc.load()
        bind()
        Self.current = self
        log(String(localized: "HyperEdit started · \(doc.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))"))
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
        session.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)   // split: 메뉴·상태바·리본 토글
        document.$status.removeDuplicates().filter { !$0.isEmpty }
            .sink { [weak self] s in self?.log(s) }.store(in: &cancellables)
        document.$errorMessage.compactMap { $0 }.removeDuplicates()
            .sink { [weak self] e in self?.log(String(localized: "Error: \(e)"), isError: true) }.store(in: &cancellables)
        document.$lineIndex
            .debounce(for: .milliseconds(1200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.rescanStructure()
                // 편집으로 낡아진 검색 결과(범위·줄 번호)를 자동 갱신 — 결과가 떠 있을 때만
                if self.findScope == .document, !self.searchQuery.isEmpty, !self.searchHits.isEmpty { self.runSearch() }
            }.store(in: &cancellables)
    }

    /// 아웃라인·타임라인 재계산 (백그라운드, 텍스트 스냅샷 기준)
    func rescanStructure() {
        scanTask?.cancel()
        let raw = document.textStorage.string
        let isMD = document.url.pathExtension.lowercased() == "md"
        let maskSecrets = secrets.maskEnabled   // secrets: 비밀 줄은 마스크로 바꾼 텍스트에서 스캔 → 아웃라인·타임라인에 비밀 줄이 오르지 않는다 (줄 수는 같다)
        scanTask = Task { [weak self] in
            let (o, t) = await Task.detached(priority: .utility) { () -> ([OutlineItem], [TimelineItem]) in
                let text = maskSecrets ? SecretScanner.redacted(raw) : raw   // secrets
                let idx = LineIndex(text: text)
                return (OutlineScanner.outline(text, index: idx, isMarkdown: isMD), OutlineScanner.timeline(text, index: idx))
            }.value
            guard let self, !Task.isCancelled else { return }
            if o != self.outline { self.outline = o }
            if t != self.timeline { self.timeline = t }
        }
    }

    func log(_ text: String, isError: Bool = false) {
        output.append(OutputLine(time: Date(), text: text, isError: isError))
        if output.count > 500 { output.removeFirst(output.count - 500) }
    }

    var rootDirectory: URL { document.url.deletingLastPathComponent() }
    var zoomPercent: Int { Int((font.size / 14 * 100).rounded()) }

    // MARK: 파일

    /// 파일 열기. MemoDocument/BookmarkStore 객체와 NSTextStorage 는 그대로 두고 내용만 바꾼다
    /// (스토리지 교체 반복 시 TextKit 2 가 퇴화하는 문제 + 창 전체 재구성을 피함).
    func open(url: URL) {
        guard TextFileDetector.isLikelyText(url) else {
            log(String(localized: "Not a text file — opening in its default app · \(url.lastPathComponent)"))
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
            log(String(localized: "Opened · \(document.url.path)"))
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
        p.message = String(localized: "Choose a text file to open")
        if p.runModal() == .OK, let u = p.url { open(url: u) }
    }

    /// 새 문서(⌘N): 위치·이름을 고르면 빈 파일을 만들어 연다. 기본 폴더는 현재 문서의 폴더.
    func newDocument() {
        let p = NSSavePanel()
        p.directoryURL = rootDirectory
        p.nameFieldStringValue = "untitled.md"
        p.title = String(localized: "New Document")
        p.message = String(localized: "Name and location of the new text file")
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
    func reloadFromDisk() { document.reloadFromDisk(); log(String(localized: "Reloaded from disk")) }

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
        let maskSecrets = secrets.maskEnabled   // secrets: 비밀 줄의 결과 미리보기는 마스크로 (매치·줄 번호는 그대로)
        isSearching = true
        searchTask = Task { [weak self] in
            // 줄 인덱스는 같은 스냅샷에서 새로 만든다 — 편집 직후 250ms 안에는 document.lineIndex 가 낡아 범위 밖 접근으로 크래시할 수 있다
            let outcome: ([SearchHit], String?) = await Task.detached(priority: .userInitiated) {
                do {
                    let hits = try SearchEngine.search(q, in: text, index: LineIndex(text: text), options: opts)
                    return (maskSecrets ? SecretScanner.redacting(hits: hits, in: text) : hits, nil)   // secrets
                }
                catch SearchError.invalidRegex(let m) { return ([], String(localized: "Regex error: \(m)")) }
                catch { return ([], error.localizedDescription) }
            }.value
            guard let self, !Task.isCancelled else { return }
            self.isSearching = false
            self.searchHits = outcome.0
            self.searchError = outcome.1
            self.log(String(localized: "Find '\(q)' · \(outcome.0.count) hits") + (outcome.1.map { " · " + $0 } ?? ""))
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
        p.message = String(localized: "Folder to search")
        if p.runModal() == .OK, let u = p.url { fileSearchDirectory = u }
    }

    func runFindInFiles() {
        fileSearchTask?.cancel()
        let q = searchQuery, opts = searchOptions, dir = fileSearchDirectory, mask = fileMask
        guard !q.isEmpty else { fileHits = []; fileSearchSummary = ""; return }
        isFileSearching = true
        fileSearchSummary = String(localized: "Searching…")
        fileSearchTask = Task { [weak self] in
            // detached 작업 안의 Task.isCancelled 는 바깥 작업의 취소를 모른다 → 플래그로 전달해 폴더 순회를 실제로 멈춘다
            let flag = CancelFlag()
            let outcome: (FileSearchResult?, String?) = await withTaskCancellationHandler {
                await Task.detached(priority: .userInitiated) {
                    do { return (try FileSearch.search(q, in: dir, mask: mask, options: opts, isCancelled: { flag.isSet }), nil) }
                    catch SearchError.invalidRegex(let m) { return (nil, String(localized: "Regex error: \(m)")) }
                    catch { return (nil, error.localizedDescription) }
                }.value
            } onCancel: { flag.set() }
            guard let self, !Task.isCancelled else { return }
            self.isFileSearching = false
            if let r = outcome.0 {
                self.fileHits = r.hits
                let summary = String(localized: "\(r.hits.count) hits · \(r.filesMatched)/\(r.filesScanned) files")
                self.fileSearchSummary = r.truncated ? String(localized: "\(summary) · partial results") : summary
                self.searchError = nil
            } else {
                self.fileHits = []
                self.fileSearchSummary = ""
                self.searchError = outcome.1
            }
            let maskPart = mask.isEmpty ? "" : " [\(mask)]"
            self.log(String(localized: "Find in files '\(q)' @ \(dir.lastPathComponent)\(maskPart) · \(self.fileSearchSummary)"))
        }
    }

    /// 현재 범위의 검색/바꾸기 실행 (Enter)
    func runCurrentSearch() {
        if findScope == .files { runFindInFiles() } else { runSearch() }
    }

    func findNext() {
        macros.recordFind(searchQuery)   // macro
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
        log(String(localized: "Replace · line \(caretLine)"))
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
            log(String(localized: "Replace all · no matches")); return
        }
        let reps = hits.map { Replacement(range: $0.range, string: SearchEngine.replacement(for: $0.range, in: text, query: searchQuery, options: searchOptions, template: replaceText)) }
        editorCommands.send(.replaceRanges(reps))
        log(String(localized: "Replace all '\(searchQuery)' → '\(replaceText)' · \(reps.count) hits"))
        Task { [weak self] in try? await Task.sleep(nanoseconds: 400_000_000); self?.runSearch() }
    }

    /// 모든 매치를 멀티 커서로 선택
    func selectAllMatches() {
        guard !searchHits.isEmpty else { return }
        editorCommands.send(.selectRanges(searchHits.map(\.range)))
        log(String(localized: "Selected \(searchHits.count) matches as multiple carets"))
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
        log(added ? String(localized: "Bookmark added · line \(line)") : String(localized: "Bookmark removed · line \(line)"))
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
    /// `--column` `--goto <line>` `--preview` `--show-settings` `--show-macro-recording` `--no-highlight` (구문 색 끄기 — 스크린샷 비교용, init 에서 처리)
    /// `--fold <line>` `--fold-all` (접기 — 영역 스캔이 끝난 뒤 적용, 스크린샷용) `--no-fold` (접기 delegate 설치 안 함)
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
        if LaunchOptions.has("--preview") { showMarkdownPreview = true }
        if LaunchOptions.has("--show-settings") {   // 스크린샷용: 설정 뷰를 별도 창에 띄운다 (`--snapshot-settings <png>` 로 따로 찍는다)
            // SwiftUI 의 Settings 장면(showSettingsWindow:)은 앱이 활성 상태여야 열리므로, 포커스를 뺏지 않고 같은 뷰를 일반 창에 담아 보여 준다
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self else { return }
                let w = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environmentObject(self)))
                w.title = String(localized: "Settings")
                w.styleMask = [.titled, .closable]
                w.setContentSize(NSSize(width: 560, height: 800))
                w.center()
                w.orderFront(nil)
                Self.snapshotSettingsWindow = w
            }
        }
        if LaunchOptions.has("--show-macro-recording") {   // 스크린샷용: 매크로 기록 상태(리본 빨간 기록 버튼 · 상태바 ● REC). 편집기가 기록기를 연결한 뒤에
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.toggleMacroRecording() }
        }
        if let g = LaunchOptions.value("--goto"), let n = Int(g) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.jump(toLine: n) }
        }
        applySplitLaunchOptions()         // split: `--split [vertical|horizontal]`
        applyQuickAppendLaunchOptions()   // quick append: `--quick-append` + 전역 단축키 등록
        if let f = LaunchOptions.value("--fold"), let n = Int(f) {   // fold: 스크린샷용 — 영역 스캔 뒤 해당 줄 접기 토글
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.send(.toggleFold(line: n)) }
        }
        if LaunchOptions.has("--fold-all") {   // fold
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.send(.foldAll) }
        }
    }

    // split: 분할 보기 세션 (공유 콘텐츠 스토리지·undo 스택·활성 편집기). 명령은 Editor/EditorSession.swift 의 extension AppModel
    let session = EditorSession()
    // quick append: 떠 있는 입력 창 + 전역 단축키 — QuickAppend/QuickAppendController.swift
    lazy var quickAppend = QuickAppendController(model: self)
    // secrets: 비밀 블록 설정·Reveal Secrets(⌥⌘S)·클립보드 소거 — SecretsUI.swift (편집기별 가림은 Editor/SecretController.swift)
    lazy var secrets = SecretsStore(model: self)
}

/// 스레드 안전 취소 플래그 — 부모 Task 의 취소를 detached 작업에 전달할 때 사용
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
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
