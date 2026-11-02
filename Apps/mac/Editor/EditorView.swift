import SwiftUI
import AppKit
import Combine
import HyperCore

/// 렌더링 문제 격리용 실행 인자 (개발 전용)
enum DebugFlags {
    static let args = CommandLine.arguments
    static let noApply = args.contains("--debug-no-apply")     // 테마/폰트 속성 적용 안 함
}

/// NSScrollView + HyperTextView(TextKit 2) 를 SwiftUI 에 올린다. 문서의 NSTextStorage 를 직접 공유.
/// 분할 보기(split): 뷰마다 레이아웃 매니저를 만들고 `EditorSession.contentStorage` 하나에 붙인다 — 두 뷰가 같은 스토리지·undo 스택을 쓴다.
struct EditorView: NSViewRepresentable {
    @EnvironmentObject var model: AppModel
    @ObservedObject var document: MemoDocument
    let theme: Theme
    let font: FontSettings
    var role: EditorRole = .primary   // split

    func makeCoordinator() -> Coordinator { Coordinator(model: model, role: role) }

    func makeNSView(context: Context) -> EditorContainerView {
        let c = context.coordinator
        Perf.log("EditorView.makeNSView role=\(role)")   // split: 분할 토글이 주 편집기를 다시 만들지 않는지 --debug-perf 로 확인
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        let tv = c.makeTextView(for: document, width: 800)
        scroll.documentView = tv
        scroll.contentView.postsBoundsChangedNotifications = true
        let gutter = GutterView(textView: tv, scrollView: scroll) { [weak c] in c?.document }
        let container = EditorContainerView(gutter: gutter, scrollView: scroll)
        c.attach(container: container, scrollView: scroll, textView: tv, gutter: gutter)
        c.apply(theme: theme, font: font, force: true)
        return container
    }

    func updateNSView(_ container: EditorContainerView, context: Context) {
        let c = context.coordinator
        Perf.measure("EditorView.updateNSView", threshold: 0.5) {
            if c.document !== document { Perf.measure("  rebind") { c.rebind(document: document) } }
            c.apply(theme: theme, font: font, force: false)
            c.handleReload(generation: document.reloadGeneration)
            c.applySurfaceOpacity(force: false)   // appearance: 배경 투명도 (값 비교만)
            c.applyCursor()                        // appearance: 커서 스타일·깜빡임 (값 비교만)
            Perf.measure("  restoreViewState") { c.restoreViewStateIfNeeded() }
            c.textView?.isEditable = document.isLoaded          // 읽지 못한 파일은 편집해도 저장되지 않으므로 편집 자체를 막는다
            c.updateMatchHighlights(model.searchHits, generation: model.searchGeneration, color: theme.selection.nsColor.withAlphaComponent(0.45))   // 뷰마다 그린다 (분할 보기 포함)
            if c.role == .primary { c.updateWindowTitle() }   // split: 창 제목은 주 편집기만
            c.gutter?.needsDisplay = true
        }
    }

    static func dismantleNSView(_ container: EditorContainerView, coordinator: Coordinator) {
        coordinator.tearDown()   // split: 보조 편집기 닫힘
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: AppModel
        let id = UUID()                  // split: 활성 편집기 식별
        let role: EditorRole             // split
        var session: EditorSession { model.session }
        private(set) var document: MemoDocument
        weak var scrollView: NSScrollView?
        weak var textView: HyperTextView?
        weak var container: EditorContainerView?
        weak var gutter: GutterView?

        private var cancellables = Set<AnyCancellable>()
        private var docCancellables = Set<AnyCancellable>()
        private var appliedThemeID: String?
        private var appliedFont: FontSettings?
        private var lastTheme: Theme?
        private var lastFont: FontSettings?
        private var restored = false
        private var lastReloadGeneration = 0
        private var saveStateTask: Task<Void, Never>?

        // 구문 하이라이트 상태 (렌더링은 아래 MARK 참조). 문법과 줄별 진입 상태는 문서(`document.grammar` / `document.lineStates`)가 든다 — grammar
        private var syntaxColors: [TokenKind: NSColor] = [:]
        private(set) var highlightEnabled: Bool
        private var pendingStateLines: Range<Int>?      // grammar: 다음 런루프 턴에 다시 칠할 줄 범위 (1-based)
        private var foldController: FoldController?    // fold
        private var secretController: SecretController?   // secrets
        private var markerView: ScrollMarkerView?      // markers

        init(model: AppModel, role: EditorRole = .primary) {
            self.model = model
            self.role = role
            self.document = model.document
            self.highlightEnabled = model.syntaxHighlighting
            super.init()
            model.session.register(self)
        }

        deinit { Perf.log("EditorView.Coordinator deinit role=\(role)") }   // split: 보조 편집기 해제 추적 (--debug-perf)

        /// 보조 편집기가 사라질 때 (SwiftUI dismantle). 세션에서 빼고 구독을 끊는다 — 텍스트 뷰는 공유 undo 항목이 참조할 수 있어 세션이 보관한다.
        func tearDown() {
            saveStateTask?.cancel()
            cancellables.removeAll()
            docCancellables.removeAll()
            foldController?.unbind()   // fold: 보관 코디네이터가 줄 인덱스 발행마다 재스캔하지 않게
            secretController?.unbind()   // secrets
            markerView?.unbind()       // markers
            session.retire(self)
        }

        // MARK: 구성

        func makeTextView(for doc: MemoDocument, width: CGFloat) -> HyperTextView {
            // NSTextView 가 자체 TextKit 2 스택(뷰포트 레이아웃 delegate 포함)을 구성하게 한 뒤, 레이아웃 매니저를 세션의 공유 콘텐츠 스토리지로 옮긴다.
            // 문서의 NSTextStorage 에는 콘텐츠 스토리지가 하나만 붙을 수 있으므로(TextKit 2 관찰자 1개) 분할된 두 뷰는 레이아웃 매니저만 따로 가진다.
            let tv = HyperTextView(usingTextLayoutManager: true)
            session.bind(textStorage: doc.textStorage)
            tv.textLayoutManager?.replace(session.contentStorage)
            tv.frame = NSRect(x: 0, y: 0, width: width, height: 100)
            if let container = tv.textContainer {
                container.widthTracksTextView = true
                container.lineFragmentPadding = 6
                container.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            }
            tv.minSize = NSSize(width: 0, height: 0)
            tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            tv.isVerticallyResizable = true
            tv.isHorizontallyResizable = false
            tv.autoresizingMask = [.width]
            tv.isRichText = false
            tv.importsGraphics = false
            tv.allowsUndo = true
            tv.usesFindBar = true
            tv.isIncrementalSearchingEnabled = true
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticTextReplacementEnabled = false
            tv.isAutomaticSpellingCorrectionEnabled = false
            tv.isAutomaticLinkDetectionEnabled = false
            tv.isAutomaticDataDetectionEnabled = false
            tv.isAutomaticTextCompletionEnabled = false
            tv.isContinuousSpellCheckingEnabled = false
            tv.isGrammarCheckingEnabled = false
            tv.smartInsertDeleteEnabled = false
            tv.usesAdaptiveColorMappingForDarkAppearance = false
            tv.textContainerInset = NSSize(width: 10, height: 12)
            tv.delegate = self
            tv.onDidMoveToWindow = { [weak self] in self?.restoreViewStateIfNeeded() }
            tv.onBecomeActive = { [weak self] in guard let self else { return }; self.session.activate(self) }   // split
            installHighlighter(on: tv)
            return tv
        }

        /// 공유 undo 스택 (NSTextViewDelegate) — 분할된 두 뷰가 같은 NSUndoManager 를 쓴다
        func undoManager(for view: NSTextView) -> UndoManager? { session.undoManager }

        // MARK: 구문 하이라이트 — TextKit 2 렌더링 속성
        // 색을 NSTextStorage 에 쓰지 않는다 (테마 전체 적용·undo·한글 폰트 런·검색 강조와 충돌). 대신 레이아웃 매니저의
        // renderingAttributesValidator 가 레이아웃 프래그먼트(= 문단 = 줄)마다 호출될 때 그 줄만 토큰화해 foregroundColor 렌더링 속성을 얹는다.
        // 보이는 줄만 계산되므로 문서 크기와 무관하고, 줄 하나는 수 µs 다.

        private func installHighlighter(on tv: HyperTextView) {
            tv.textLayoutManager?.renderingAttributesValidator = { [weak self] lm, fragment in
                self?.validateRenderingAttributes(lm, fragment)
            }
        }

        private func validateRenderingAttributes(_ lm: NSTextLayoutManager, _ fragment: NSTextLayoutFragment) {
            guard let cs = lm.textContentManager as? NSTextContentStorage else { return }
            let tr = fragment.rangeInElement
            Perf.measure("highlight.fragment", threshold: 0.2) {
                guard let ts = cs.textStorage else { return }
                let start = cs.offset(from: cs.documentRange.location, to: tr.location)
                let length = cs.offset(from: tr.location, to: tr.endLocation)
                guard length > 0 else { return }
                let ns = ts.string as NSString
                // 이전 검증의 색은 걷어낸다 (편집으로 토큰 경계가 바뀌었을 수 있음). 끝의 개행은 빼고 — 실측(macOS 27 TextKit 2, 2026-11-02):
                // 개행까지 포함한 범위로 걷어내면 바로 다음 문단 머리에서 시작하는 런(제목·번호)까지 지워진다(빈 줄을 다시 만들면 그 아래 `[제목]` 색이
                // 사라졌다). 토큰은 개행을 포함하지 않으므로 빼도 남는 색이 없다
                let removeLength = length - (ns.character(at: start + length - 1) == 10 ? 1 : 0)
                if removeLength > 0, let removeEnd = cs.location(tr.location, offsetBy: removeLength), let rr = NSTextRange(location: tr.location, end: removeEnd) {
                    lm.removeRenderingAttribute(.foregroundColor, for: rr)
                }
                guard highlightEnabled else { return }
                // grammar: 이 문단(= 줄)의 진입 상태(블록 주석·여러 줄 문자열·펜스 안인가)를 문서의 줄 상태 표에서 받아 이어서 칠한다
                let entering = document.lineState(atUTF16Offset: start)
                for token in document.grammar.scanLine(in: ns, range: NSRange(location: start, length: length), entering: entering) {
                    guard let color = syntaxColors[token.kind],
                          let a = cs.location(cs.documentRange.location, offsetBy: token.range.location),
                          let b = cs.location(a, offsetBy: token.range.length),
                          let r = NSTextRange(location: a, end: b) else { continue }
                    lm.addRenderingAttribute(.foregroundColor, value: color, for: r)
                }
            }
        }

        /// 테마 색 → 토큰 종류별 NSColor (테마에 없는 키는 본문 색 = 칠하지 않음)
        private func rebuildSyntaxColors(_ theme: Theme) {
            var table: [TokenKind: NSColor] = [:]
            for kind in TokenKind.allCases {
                if let c = theme.syntax[kind.themeKey], c != theme.foreground { table[kind] = c.nsColor }
            }
            syntaxColors = table
        }

        /// 보이는 줄의 색을 다시 계산하게 한다 (켜기/끄기).
        /// 실측(macOS 27 TextKit 2): `invalidateLayout(for:)`·`invalidateRenderingAttributes(for:)` 는 뷰포트든 문서 전체든
        /// 이미 레이아웃된 프래그먼트의 validator 를 다시 부르지 않는다. 스토리지에 속성 편집을 알리면(테마 적용의 setAttributes 와 같은 경로)
        /// 보이는 프래그먼트가 재생성되며 validator 가 즉시 다시 계산한다. 편집된 문단은 TextKit 2 가 편집 처리 중에 다시 검증하지만 그 뒤 렌더링 속성
        /// 런을 옮겨 색이 어긋나므로 `scheduleParagraphRevalidation` 이 다음 턴에 그 문단만 한 번 더 만든다.
        private func invalidateHighlight() {
            guard let tv = textView, let lm = tv.textLayoutManager, let ts = tv.textStorage else { return }
            Perf.measure("highlight.invalidate len=\(ts.length)", threshold: 1) {
                if !highlightEnabled { lm.removeRenderingAttribute(.foregroundColor, for: lm.documentRange) }
                ts.beginEditing()
                ts.edited(.editedAttributes, range: NSRange(location: 0, length: ts.length), changeInLength: 0)
                ts.endEditing()
            }
            tv.needsDisplay = true
        }

        func setSyntaxHighlighting(_ on: Bool) {
            guard on != highlightEnabled else { return }
            highlightEnabled = on
            invalidateHighlight()
        }

        // grammar: 편집으로 아래 줄들의 진입 상태가 바뀜(`/*` 열기·닫기, 펜스) — 그 줄들은 TextKit 2 가 스스로 다시 배치하지 않으므로 프래그먼트를 다시 만들게 한다.
        // 문서가 저장소 편집 알림 안에서 보내므로 편집 처리가 끝난 다음 턴에 한 번에 처리한다 (여러 통지는 합친다). 스토리지 속성 편집은 모든 레이아웃 매니저에
        // 전달되므로 주 편집기 한 곳만 한다. 바뀐 줄이 수만 개여도(`/*` 를 문서 첫 줄에 열기) 보이는 프래그먼트만 재생성되므로 수 ms.
        private func scheduleLineStateInvalidation(_ lines: Range<Int>) {
            guard role == .primary, !lines.isEmpty else { return }
            if let p = pendingStateLines { pendingStateLines = min(p.lowerBound, lines.lowerBound)..<max(p.upperBound, lines.upperBound) } else { pendingStateLines = lines }
            DispatchQueue.main.async { [weak self] in self?.flushLineStateInvalidation() }
        }

        private func flushLineStateInvalidation() {
            guard let lines = pendingStateLines else { return }
            pendingStateLines = nil
            guard highlightEnabled, let tv = textView, let ts = tv.textStorage else { return }
            let idx = document.liveLineIndex
            let len = ts.length
            let a = min(idx.range(ofLine: lines.lowerBound).location, len)
            let b = min(NSMaxRange(idx.range(ofLine: lines.upperBound - 1)) + 1, len)   // 마지막 줄의 개행까지
            guard b > a else { return }
            Perf.measure("grammar.invalidate lines=\(lines.count) len=\(b - a)", threshold: 1) {
                ts.beginEditing()
                ts.edited(.editedAttributes, range: NSRange(location: a, length: b - a), changeInLength: 0)
                ts.endEditing()
            }
            tv.needsDisplay = true
        }

        // 편집된 문단의 구문 색 재검증. 실측(macOS 27 TextKit 2, `--selftest-probe` 로 확인, 2026-11-02): 편집된 프래그먼트의 validator 는 편집 처리 중에
        // 불리고 토큰도 맞지만, 그 뒤 TextKit 2 가 편집 위치 뒤의 렌더링 속성 런을 delta 만큼 옮겨 방금 칠한 색이 어긋난다(줄 끝에 입력한 URL 의 색이
        // 밀리고, undo 뒤 다음 줄 머리에 링크색이 남는다). 검색 강조가 스토리지 속성이던 때는 결과가 떠 있는 동안 키 입력마다 문서 전체가 다시 만들어져
        // 이를 가렸다. 다음 턴에 그 문단(들)만 속성 편집 통지로 다시 만들게 한다 — 문단 하나라 수십 µs. 밀린 런은 최대 delta 만큼 뒤까지 갈 수 있어 그만큼 넓힌다.
        private var pendingRevalidation: NSRange?

        private func scheduleParagraphRevalidation(_ edited: NSRange, delta: Int) {
            guard role == .primary, highlightEnabled, edited.location != NSNotFound else { return }   // 스토리지 속성 편집은 모든 레이아웃 매니저에 전달된다
            let span = NSRange(location: edited.location, length: edited.length + max(0, delta))
            pendingRevalidation = pendingRevalidation.map { NSUnionRange($0, span) } ?? span
            DispatchQueue.main.async { [weak self] in self?.flushParagraphRevalidation() }
        }

        private func flushParagraphRevalidation() {
            guard let span = pendingRevalidation else { return }
            pendingRevalidation = nil
            guard highlightEnabled, let tv = textView, let ts = tv.textStorage else { return }
            let len = ts.length
            let loc = min(span.location, len), end = min(NSMaxRange(span), len)
            let para = (ts.string as NSString).paragraphRange(for: NSRange(location: loc, length: max(0, end - loc)))
            guard para.length > 0 else { return }
            Perf.measure("highlight.revalidate len=\(para.length)", threshold: 1) {
                ts.beginEditing()
                ts.edited(.editedAttributes, range: para, changeInLength: 0)
                ts.endEditing()
            }
        }

        func attach(container: EditorContainerView, scrollView: NSScrollView, textView: HyperTextView, gutter: GutterView) {
            self.container = container
            self.scrollView = scrollView
            self.textView = textView
            self.gutter = gutter
            lastReloadGeneration = document.reloadGeneration

            model.editorCommands
                .sink { [weak self] cmd in self?.handle(cmd) }
                .store(in: &cancellables)
            NotificationCenter.default.publisher(for: NSView.boundsDidChangeNotification, object: scrollView.contentView)
                .sink { [weak self] _ in self?.gutter?.needsDisplay = true }
                .store(in: &cancellables)
            // 보이는 첫 줄 → EditorCaret.firstVisibleLine (마크다운 미리보기 스크롤 동기화). 스크롤 이벤트는 초당 수백 번이라 60 ms 로 묶는다
            NotificationCenter.default.publisher(for: NSView.boundsDidChangeNotification, object: scrollView.contentView)
                .throttle(for: .milliseconds(60), scheduler: RunLoop.main, latest: true)
                .sink { [weak self] _ in self?.publishFirstVisibleLine() }
                .store(in: &cancellables)
            NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
                .sink { [weak self] _ in self?.saveViewStateNow() }
                .store(in: &cancellables)
            bindDocument()
            setWordWrap(model.wordWrap)
            gutter.isHidden = !model.showLineNumbers
            textView.columnModeEnabled = model.columnMode
            // 북마크 줄 추적: 줄 수가 바뀌는 편집(입력·붙여넣기·도구·undo/redo 모두 shouldChangeText 경유) 직전에 북마크를 옮긴다
            textView.needsLineTracking = { [weak self] in !(self?.model.bookmarks.bookmarks.isEmpty ?? true) }
            textView.onLinesWillChange = { [weak self] line, delta in self?.model.bookmarks.shift(fromLine: line, delta: delta) }
            textView.tracksUntrackedLineChanges = role == .primary   // split: undo/redo 의 사후 북마크 이동은 주 편집기만 (두 뷰가 같은 저장소 알림을 받는다)
            textView.onMultiChange = { [weak self] m in
                guard let self, self.session.isActive(self) else { return }   // split: 상태바 커서 수는 활성 편집기 기준
                let c = self.model.caret
                let n = m?.ranges.count ?? 0
                if c.multiCaretCount != n { c.multiCaretCount = n }
                let b = m?.block != nil
                if c.columnBlockActive != b { c.columnBlockActive = b }
            }
            installSnippets(on: textView)   // EditorView+EditTools.swift
            model.macros.install(on: textView, model: model)   // macro
            // fold / markers: 텍스트 뷰마다 하나씩 (분할 편집기는 편집기별로 만든다)
            let fold = FoldController(textView: textView, gutter: gutter, log: { [weak self] in self?.model.log($0) })   // fold
            fold.bind(document: document)                                                                                   // fold
            foldController = fold                                                                                           // fold
            let secret = SecretController(textView: textView, fold: fold, store: model.secrets, log: { [weak self] in self?.model.log($0) })   // secrets: 비밀 블록 마스킹 (같은 layout delegate)
            secret.bind(document: document)                                                                                 // secrets
            secretController = secret                                                                                       // secrets
            let markers = ScrollMarkerView(model: model, scrollView: scrollView, documentProvider: { [weak self] in self?.document })   // markers
            markers.foldLines = { [weak fold] in fold?.foldedHeaderLines ?? [] }                                           // markers
            markers.bind(document: document)                                                                                // markers
            container.markerView = markers                                                                                  // markers
            markerView = markers                                                                                            // markers
            fold.onChange = { [weak markers] in markers?.needsDisplay = true }                                              // markers
        }

        private func bindDocument() {
            docCancellables.removeAll()
            document.$lineIndex
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in
                    self?.gutter?.updateThickness()
                    self?.gutter?.needsDisplay = true
                    self?.publishFirstVisibleLine()   // 편집으로 줄 번호가 밀렸을 수 있다
                }
                .store(in: &docCancellables)
            // 같은 문서 객체가 다른 파일로 전환됨: 이전 파일의 위치 저장 예약 취소, undo 비우기, 새 파일 위치 복원 준비
            // (@Published 는 willSet 시점에 발행하므로 document.url 은 아직 이전 값 — 전달된 newURL 을 쓴다)
            document.$url
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.saveStateTask?.cancel()
                    self.session.clearUndo()
                    self.textView?.endSnippetSession()
                    self.restored = false
                    self.lastCaretRect = nil
                    // grammar: 문법은 문서가 내용 교체(switchTo → load) 전에 바꿔 둔다 (MemoDocument.grammar) — 교체로 재생성되는 프래그먼트가 새 문법으로 칠해진다
                }
                .store(in: &docCancellables)
            // grammar: 편집 줄 밖에서 줄 상태가 바뀐 범위 → 다시 칠하기 · 문법 교체(사용자 문법 리로드) → 보이는 줄 전부 다시 칠하기
            document.lineStatesChanged
                .sink { [weak self] lines in self?.scheduleLineStateInvalidation(lines) }
                .store(in: &docCancellables)
            document.characterEdits
                .sink { [weak self] edit in self?.scheduleParagraphRevalidation(edit.range, delta: edit.delta) }
                .store(in: &docCancellables)
            document.$grammarGeneration
                .dropFirst()
                .sink { [weak self] _ in
                    guard let self, self.role == .primary else { return }   // 스토리지 속성 편집은 모든 레이아웃 매니저에 전달된다
                    DispatchQueue.main.async { [weak self] in self?.invalidateHighlight() }   // @Published 는 willSet 발행 — 문법·상태 표가 갖춰진 뒤
                }
                .store(in: &docCancellables)
        }

        func rebind(document newDoc: MemoDocument) {
            saveViewStateNow()
            document = newDoc
            Perf.measure("  rebind.swapStorage") { session.bind(textStorage: newDoc.textStorage) }   // 두 번째 편집기는 이미 연결돼 있어 건너뛴다
            session.clearUndo()
            lastReloadGeneration = newDoc.reloadGeneration
            restored = false
            appliedThemeID = nil
            appliedHighlightGeneration = -1; textView?.matchHighlights = []   // search: 새 문서의 결과는 다음 update 가 다시 넘긴다
            bindDocument()
            foldController?.bind(document: newDoc)   // fold
            secretController?.bind(document: newDoc)   // secrets
            markerView?.bind(document: newDoc)       // markers
            if let t = lastTheme, let f = lastFont { apply(theme: t, font: f, force: true) } else { invalidateHighlight() }
        }

        // MARK: 테마 / 폰트

        func apply(theme: Theme, font: FontSettings, force: Bool) {
            guard let tv = textView, !DebugFlags.noApply else { return }
            let changed = force || appliedThemeID != theme.id || appliedFont != font
            guard changed else { return }
            appliedThemeID = theme.id
            appliedFont = font
            lastTheme = theme
            lastFont = font

            let base = FontCascade.baseFont(font)
            let hangul = FontCascade.hangulFont(font)

            let para = NSMutableParagraphStyle()
            let lh = FontCascade.lineHeight(for: base, multiple: font.lineHeightMultiple)
            para.minimumLineHeight = lh
            para.maximumLineHeight = lh
            para.lineBreakMode = .byWordWrapping
            para.tabStops = []
            para.defaultTabInterval = FontCascade.advance(of: base) * 4

            let attrs: [NSAttributedString.Key: Any] = [
                .font: base,
                .foregroundColor: theme.foreground.nsColor,
                .paragraphStyle: para,
            ]
            tv.typingAttributes = attrs
            tv.defaultParagraphStyle = para

            rebuildSyntaxColors(theme)   // 아래 전체 속성 적용이 프래그먼트를 다시 만들며 validator 를 부르므로 색 표를 먼저 바꾼다
            if role == .primary {
                // 스토리지 속성(폰트·색·문단·한글 런)은 공유되므로 주 편집기가 테마 변경당 한 번만 입힌다 (1.3 MB 전체 setAttributes)
                document.hangulFont = hangul
                let ts = tv.textStorage ?? document.textStorage
                let full = NSRange(location: 0, length: ts.length)
                ts.beginEditing()
                Perf.measure("  apply.setAttributes len=\(full.length)") { ts.setAttributes(attrs, range: full) }
                if let h = hangul { Perf.measure("  apply.hangul") { HangulFontFixer.apply(font: h, to: ts, in: full) } }
                Perf.measure("  apply.endEditing") { ts.endEditing() }
                tv.textColor = theme.foreground.nsColor   // NSText.textColor 는 스토리지 전체에 색을 입힌다 — 주 편집기만
            } else {
                // 보조 편집기: 이 뷰의 레이아웃 매니저만 새 색 표로 다시 칠하게 한다 (보이는 프래그먼트만 재생성 — 수 ms)
                invalidateHighlight()
            }

            tv.backgroundColor = theme.background.nsColor
            tv.drawsBackground = true
            tv.insertionPointColor = theme.cursor.nsColor
            tv.selectedTextAttributes = [.backgroundColor: theme.selection.nsColor]
            tv.currentLineColor = theme.lineHighlight.nsColor
            scrollView?.backgroundColor = theme.background.nsColor
            gutter?.apply(theme: theme, baseFont: base)
            foldController?.apply(theme: theme)   // fold
            secretController?.apply(theme: theme)   // secrets: 가림막 색·글꼴
            markerView?.apply(theme: theme)       // markers
            container?.layer?.backgroundColor = theme.background.nsColor.cgColor
            applySurfaceOpacity(force: true)   // appearance: 투명도 < 1 이면 위 불투명 배경을 α 배경으로 바꾼다
            tv.needsDisplay = true
            // 구문 색: 위 전체 setAttributes 가 프래그먼트를 다시 만들며 validator 가 새 색 표(rebuildSyntaxColors)로 칠한다 — 추가 무효화 불필요
        }

        // MARK: 외형 (appearance)

        /// 커서 스타일·깜빡임 → 텍스트 뷰 (분할 편집기도 각자 받는다)
        func applyCursor() {
            guard let tv = textView else { return }
            if tv.cursorStyle != model.cursorStyle { tv.cursorStyle = model.cursorStyle }
            if tv.cursorBlinks != model.cursorBlink { tv.cursorBlinks = model.cursorBlink }
        }

        private var appliedOpacity = -1.0
        /// 배경 투명도. 반투명이면 컨테이너 레이어 하나만 테마 배경을 α 로 칠하고 그 위의 스크롤뷰·텍스트뷰·거터 배경은 비운다 —
        /// 겹쳐 칠하면 (1-α)² 만 비쳐 패널보다 불투명해 보인다. 현재 줄 강조도 같은 α. 글자·캐럿·선택·접기 표식은 그대로.
        func applySurfaceOpacity(force: Bool) {
            let alpha = model.backgroundOpacity
            guard force || alpha != appliedOpacity, let tv = textView, let theme = lastTheme else { return }
            appliedOpacity = alpha
            let translucent = BackgroundOpacity.isTranslucent(alpha)
            let bg = theme.background.nsColor
            container?.layer?.backgroundColor = (translucent ? bg.withAlphaComponent(alpha) : bg).cgColor
            scrollView?.drawsBackground = !translucent
            tv.backgroundColor = translucent ? .clear : bg
            tv.currentLineColor = translucent ? theme.lineHighlight.nsColor.withAlphaComponent(alpha) : theme.lineHighlight.nsColor
            gutter?.surfaceAlpha = translucent ? alpha : 1
            tv.needsDisplay = true
        }

        func handleReload(generation: Int) {
            guard generation != lastReloadGeneration else { return }
            lastReloadGeneration = generation
            session.clearUndo()
            // 디스크에서 다시 읽은 내용은 shouldChangeText 를 거치지 않으므로 줄 수만 맞춘다
            model.bookmarks.clamp(toLineCount: document.lineIndex.lineCount)
            if let t = lastTheme, let f = lastFont { apply(theme: t, font: f, force: true) }
            // 외부 변경 반영 뒤 캐럿이 문서 끝으로 튀지 않도록 직전 위치(클램프)를 복원 — 같은 파일을 다른 도구로 덧붙여 쓰는 흐름에서 읽던 자리를 잃지 않는다
            if restored, let tv = textView, let keep = lastSelection {
                let len = document.textStorage.length
                let loc = min(keep.location, len)
                tv.setSelectedRange(NSRange(location: loc, length: 0))
                tv.scrollRangeToVisible(NSRange(location: loc, length: 0))
            }
        }

        // MARK: 검색 매치 강조 — 텍스트 뷰가 직접 그린다 (HyperTextView.matchHighlights)
        // 예전에는 스토리지에 .backgroundColor 속성을 얹었다. TextKit 2 는 속성 편집 범위의 레이아웃을 무효화하므로 1.3 MB 문서에서는 편집마다
        // (문서 전체 걷어내기)·지연 재검색마다(첫 매치~끝 매치) 뷰포트가 문서 맨 위로 튀었다(2026-11-02 보고). 이제 스토리지는 건드리지 않고,
        // 편집 중 범위 이동은 뷰가 저장소 알림으로 스스로 처리하므로 걷어낼 일도 없다. 검색이 끝날 때마다(generation) 새 범위를 넘긴다 — 같은 결과라도
        // 편집 뒤 재검색이면 범위가 달라졌을 수 있다.

        private var appliedHighlightGeneration = -1

        func updateMatchHighlights(_ hits: [SearchHit], generation: Int, color: NSColor) {
            guard let tv = textView else { return }
            if tv.matchHighlightColor != color { tv.matchHighlightColor = color }
            guard generation != appliedHighlightGeneration else { return }
            appliedHighlightGeneration = generation
            tv.matchHighlights = hits.map(\.range)   // 검색 엔진이 문서 순서로 돌려준다
            tv.needsDisplay = true
        }

        /// 보이는 영역의 첫 레이아웃 조각이 속한 줄(1-based)을 EditorCaret 에 발행한다 — 거터와 같은 TextKit 2 질의
        func publishFirstVisibleLine() {
            guard session.isActive(self) else { return }   // split: 미리보기는 활성 편집기를 따라간다
            guard let tv = textView, let lm = tv.textLayoutManager, let cs = tv.textContentStorage else { return }
            let visible = tv.visibleRect
            let origin = tv.textContainerOrigin
            let point = CGPoint(x: 0, y: max(0, visible.minY - origin.y))
            let location = lm.textLayoutFragment(for: point)?.rangeInElement.location ?? lm.documentRange.location
            let offset = cs.offset(from: cs.documentRange.location, to: location)
            let line = document.lineIndex.lineNumber(forUTF16Offset: offset)
            if model.caret.firstVisibleLine != line { model.caret.firstVisibleLine = line }
        }

        /// Dock·Mission Control 에 문서 이름이 보이도록 (제목 표시줄은 숨겨져 있어도 창 제목은 쓰인다)
        func updateWindowTitle() {
            guard let w = textView?.window else { return }
            if w.title != document.url.lastPathComponent { w.title = document.url.lastPathComponent }
            w.representedURL = document.isLoaded ? document.url : nil
        }

        // MARK: 위치 복원 / 저장

        func restoreViewStateIfNeeded() {
            guard !restored, let tv = textView, let sv = scrollView, sv.window != nil, sv.bounds.height > 0, document.isLoaded else { return }
            restored = true
            let len = document.textStorage.length
            if role == .secondary {
                // split: 보조 편집기는 저장된 위치를 쓰지 않고 주 편집기의 캐럿 줄에서 시작한다 (가운데, 포커스는 주 편집기에 둔다)
                let loc = session.primary?.textView?.selectedRange().location ?? len
                select(NSRange(location: min(loc, len), length: 0), center: true, indicator: false, focus: false)
                return
            }
            if let st = ViewStateStore.load(for: document.url) {
                select(NSRange(location: min(st.cursor, len), length: 0), center: true, indicator: false)
            } else {
                select(NSRange(location: len, length: 0), center: false, indicator: false)
            }
            _ = tv
        }

        private func scheduleSaveViewState() {
            guard role == .primary else { return }   // split: 보기 위치는 주 편집기만 저장
            saveStateTask?.cancel()
            saveStateTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled else { return }
                self?.saveViewStateNow()
            }
        }

        private func saveViewStateNow() {
            guard role == .primary, let tv = textView, document.isLoaded else { return }
            ViewStateStore.save(EditorViewState(cursor: tv.selectedRange().location, scrollY: Double(tv.visibleRect.minY)), for: document.url)
        }

        // MARK: 명령

        func handle(_ cmd: EditorCommand) {
            // split: 뷰 설정은 모든 편집기에, 위치 저장은 주 편집기에, 그 밖의 편집·이동 명령은 활성 편집기에만
            switch cmd {
            case .setWordWrap, .setLineNumbers, .setSyntaxHighlighting, .setColumnMode: break
            case .saveViewState: guard role == .primary else { return }
            default: guard session.isActive(self) else { return }
            }
            guard let tv = textView else { return }
            switch cmd {
            case .selectRange(let r):
                select(r, center: true, indicator: true)
            case .goToLine(let n):
                let r = document.lineIndex.range(ofLine: n)
                select(NSRange(location: r.location, length: 0), center: true, indicator: true)
            case .goToEnd:
                select(NSRange(location: document.textStorage.length, length: 0), center: false, indicator: false)
            case .insertTimestamp:
                insertTimestamp(in: tv)
            case .focus:
                tv.window?.makeFirstResponder(tv)
            case .textTool(let tool):
                applyTextTool(tool, in: tv)
            case .setWordWrap(let on):
                setWordWrap(on)
            case .setLineNumbers(let on):
                gutter?.isHidden = !on
                container?.needsLayout = true
            case .setSyntaxHighlighting(let on):
                setSyntaxHighlighting(on)
            case .saveViewState:
                saveViewStateNow()
            case .undo: tv.undoManager?.undo()
            case .redo: tv.undoManager?.redo()
            case .selectAll: tv.selectAll(nil)
            case .cut: tv.cut(nil)
            case .copy: tv.copy(nil)
            case .paste: tv.paste(nil)
            case .setColumnMode(let on):
                tv.columnModeEnabled = on
            case .insertColumnNumbers(let start, let step, let zeroPad):
                tv.insertColumnNumbers(start: start, step: step, zeroPad: zeroPad)
                document.textDidChange()
            case .selectRanges(let ranges):
                tv.setMulti(ranges)
                tv.window?.makeFirstResponder(tv)
            case .addNextOccurrence:
                tv.addNextOccurrence()
                tv.window?.makeFirstResponder(tv)
            case .replaceRanges(let reps):
                let carets = tv.performReplacements(reps.map { ($0.range, $0.string) })
                if let last = carets.last, reps.count == 1 { tv.setSelectedRange(NSRange(location: last.location - (reps[0].string as NSString).length, length: (reps[0].string as NSString).length)) }
                document.textDidChange()
                gutter?.needsDisplay = true
            case .perform(let action):
                action(tv)   // 문자 변경이 있었다면 MemoDocument.didProcessEditing 이 dirty·자동 저장을 건다 (읽기 전용 perform 은 문서를 더럽히지 않는다)
            case .fold, .unfold, .foldAll, .unfoldAll, .toggleFold:   // fold
                foldController?.handle(cmd)
            }
        }

        // MARK: 자동 줄바꿈

        func setWordWrap(_ on: Bool) {
            guard let tv = textView, let sv = scrollView, let container = tv.textContainer else { return }
            if on {
                container.widthTracksTextView = true
                container.size = NSSize(width: sv.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
                tv.isHorizontallyResizable = false
                tv.frame.size.width = sv.contentSize.width
                sv.hasHorizontalScroller = false
            } else {
                container.widthTracksTextView = false
                container.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
                tv.isHorizontallyResizable = true
                sv.hasHorizontalScroller = true
            }
            tv.needsLayout = true
            tv.needsDisplay = true
            gutter?.needsDisplay = true
        }

        // MARK: 텍스트 도구 (UltraEdit 편집 메뉴 계승) — 모두 insertText 경유라 ⌘Z 로 되돌릴 수 있음

        private func applyTextTool(_ tool: TextTool, in tv: HyperTextView) {
            tv.clearMulti()                           // 줄 도구는 단일 캐럿 기준 — 멀티 캐럿이 남아 있으면 insertText 가 엉뚱한 곳에 삽입한다
            tv.breakUndoCoalescing()                  // 도구 한 번 = undo 한 단계 (앞선 타이핑 그룹에 합쳐지지 않게)
            let ns = tv.string as NSString
            let sel = tv.selectedRange()
            var cur = ns.lineRange(for: sel)          // 선택을 포함하는 줄 범위(개행 포함)
            if tool == .joinLines, sel.length == 0, NSMaxRange(cur) < ns.length {
                // 선택이 없으면 현재 줄 + 다음 줄을 합친다 (한 줄만으로는 합칠 대상이 없다)
                cur = NSUnionRange(cur, ns.lineRange(for: NSRange(location: NSMaxRange(cur), length: 0)))
            }
            tv.window?.makeFirstResponder(tv)
            tv.macroWillApplyTool(tool.rawValue); defer { tv.macroDidApplyTool() }   // macro
            switch tool {
            case .deleteLine:
                tv.insertText("", replacementRange: cur)
            case .duplicateLine:
                var t = ns.substring(with: cur)
                if t.hasSuffix("\n") {
                    tv.insertText(t, replacementRange: NSRange(location: NSMaxRange(cur), length: 0))
                } else {
                    t = "\n" + t
                    tv.insertText(t, replacementRange: NSRange(location: NSMaxRange(cur), length: 0))
                }
                tv.setSelectedRange(NSRange(location: NSMaxRange(cur), length: 0))
            case .moveLineUp:
                guard cur.location > 0 else { return }
                let prev = ns.lineRange(for: NSRange(location: cur.location - 1, length: 0))
                var curText = ns.substring(with: cur), prevText = ns.substring(with: prev)
                if !curText.hasSuffix("\n") { curText += "\n"; if prevText.hasSuffix("\n") { prevText.removeLast() } }
                let combined = NSRange(location: prev.location, length: prev.length + cur.length)
                tv.insertText(curText + prevText, replacementRange: combined)
                tv.setSelectedRange(NSRange(location: prev.location + (sel.location - cur.location), length: sel.length))
            case .moveLineDown:
                guard NSMaxRange(cur) < ns.length else { return }
                let next = ns.lineRange(for: NSRange(location: NSMaxRange(cur), length: 0))
                var curText = ns.substring(with: cur), nextText = ns.substring(with: next)
                if !nextText.hasSuffix("\n") { nextText += "\n"; if curText.hasSuffix("\n") { curText.removeLast() } }
                let combined = NSRange(location: cur.location, length: cur.length + next.length)
                tv.insertText(nextText + curText, replacementRange: combined)
                tv.setSelectedRange(NSRange(location: cur.location + (nextText as NSString).length + (sel.location - cur.location), length: sel.length))
            case .joinLines: applyLines(tv, cur) { TextTools.joinLines($0) }
            case .reverseLines: applyLines(tv, cur) { TextTools.reverseLines($0) }
            case .numberLines: applyLines(tv, cur) { TextTools.numberLines($0) }
            case .sortAsc: applyLines(tv, cur) { TextTools.sortLines($0) }
            case .sortDesc: applyLines(tv, cur) { TextTools.sortLines($0, ascending: false) }
            case .sortNumeric: applyLines(tv, cur) { TextTools.sortLines($0, numeric: true) }
            case .dedupe: applyLines(tv, cur) { TextTools.dedupeLines($0) }
            case .removeBlank: applyLines(tv, cur) { TextTools.removeBlankLines($0) }
            case .trimTrailing: applyLines(tv, cur) { TextTools.trimTrailing($0) }
            case .trimBoth: applyLines(tv, cur) { TextTools.trimBoth($0) }
            case .tabsToSpaces: applyLines(tv, cur) { TextTools.tabsToSpaces($0) }
            case .spacesToTabs: applyLines(tv, cur) { TextTools.spacesToTabs($0) }
            case .upper: applySelection(tv, sel, cur) { TextTools.upper($0) }
            case .lower: applySelection(tv, sel, cur) { TextTools.lower($0) }
            case .capitalize: applySelection(tv, sel, cur) { TextTools.capitalize($0) }
            case .invertCase: applySelection(tv, sel, cur) { TextTools.invertCase($0) }
            case .calculate: calculate(tv, sel, cur)
            case .alignColumns: alignColumns(tv, sel, cur)
            case .toggleComment: toggleComment(tv, sel, cur)                 // EditorView+EditTools.swift
            case .formatJSON: formatJSON(tv, sel, minify: false)
            case .minifyJSON: formatJSON(tv, sel, minify: true)
            }
            // dirty·자동 저장·줄 인덱스는 MemoDocument.textStorage(_:didProcessEditing:) 가 실제 문자 변경에서만 건다 —
            // 여기서 무조건 걸면 아무것도 바꾸지 못한 도구(JSON 문법 오류, 수식 아님)도 문서를 dirty 로 만들어 같은 내용을 다시 저장한다
            gutter?.needsDisplay = true
        }

        /// 즉석 계산(⌃⌘=): 선택이 있으면 선택을, 없으면 현재 줄(마지막 `=`/`⇒` 뒤)을 평가해 줄 끝에 ` ⇒ 결과` 를 붙인다.
        /// 이미 `⇒ 옛 결과` 가 있으면 결과만 바꾼다. 수식이 아니면 출력 패널에 알리고 아무것도 바꾸지 않는다.
        private func calculate(_ tv: HyperTextView, _ sel: NSRange, _ line: NSRange) {
            let ns = tv.string as NSString
            var lr = line
            var selected: String?
            var selEnd = 0
            if sel.length > 0 {
                selected = ns.substring(with: sel)
                lr = ns.lineRange(for: NSRange(location: NSMaxRange(sel) - 1, length: 0))   // 선택이 끝나는 줄
                selEnd = NSMaxRange(sel) - lr.location
            }
            if lr.length > 0, ns.character(at: NSMaxRange(lr) - 1) == 10 { lr.length -= 1 }
            let text = ns.substring(with: lr)
            guard let r = TextTools.calculateLine(text, selectedExpression: selected, selectionEnd: min(max(0, selEnd), lr.length)) else {
                model.log(String(localized: "Not a valid expression") + " · " + (selected ?? text).trimmingCharacters(in: .whitespacesAndNewlines))
                return
            }
            if r.line != text { tv.insertText(r.line, replacementRange: lr) }
            tv.setSelectedRange(NSRange(location: lr.location + (r.line as NSString).length, length: 0))
            model.log(String(localized: "Calculate") + " · \(r.expression) ⇒ \(r.result)")
        }

        /// 열 맞춤(⌃⌘T): 선택한 줄들(없으면 캐럿 줄과 같은 구분자를 가진 인접 줄 묶음)의 탭/파이프 열을 표시 폭 기준으로 맞춘다.
        private func alignColumns(_ tv: HyperTextView, _ sel: NSRange, _ lineRange: NSRange) {
            let ns = tv.string as NSString
            func content(_ r: NSRange) -> String {
                var c = r
                if c.length > 0, ns.character(at: NSMaxRange(c) - 1) == 10 { c.length -= 1 }
                return ns.substring(with: c)
            }
            var range = lineRange
            if sel.length == 0 {
                guard let sep = TextTools.columnSeparator(for: [content(lineRange)]) else {
                    model.log(String(localized: "No tab- or pipe-separated columns to align")); return
                }
                var start = range.location
                while start > 0 {
                    let prev = ns.lineRange(for: NSRange(location: start - 1, length: 0))
                    guard content(prev).contains(sep) else { break }
                    start = prev.location
                }
                var end = NSMaxRange(range)
                while end < ns.length {
                    let next = ns.lineRange(for: NSRange(location: end, length: 0))
                    guard content(next).contains(sep) else { break }
                    end = NSMaxRange(next)
                }
                range = NSRange(location: start, length: end - start)
            }
            let original = ns.substring(with: range)
            var text = original
            let hadNewline = text.hasSuffix("\n")
            if hadNewline { text.removeLast() }
            let lines = text.components(separatedBy: "\n")
            guard let sep = TextTools.columnSeparator(for: lines) else {
                model.log(String(localized: "No tab- or pipe-separated columns to align")); return
            }
            var result = TextTools.alignColumns(lines, separator: sep).joined(separator: "\n")
            if hadNewline { result += "\n" }
            guard result != original else { return }
            tv.insertText(result, replacementRange: range)
            tv.setSelectedRange(NSRange(location: range.location, length: (result as NSString).length))
            model.log(String(localized: "Aligned \(lines.count) lines"))
        }

        /// 줄 범위 변환 (선택이 없으면 현재 줄)
        private func applyLines(_ tv: HyperTextView, _ range: NSRange, _ f: ([String]) -> [String]) {
            let ns = tv.string as NSString
            var text = ns.substring(with: range)
            let hadNewline = text.hasSuffix("\n")
            if hadNewline { text.removeLast() }
            let out = f(text.components(separatedBy: "\n"))
            var result = out.joined(separator: "\n")
            if hadNewline && !result.isEmpty { result += "\n" }
            tv.insertText(result, replacementRange: range)
            tv.setSelectedRange(NSRange(location: range.location, length: (result as NSString).length))
        }

        /// 선택 변환 (선택이 없으면 현재 줄 내용)
        private func applySelection(_ tv: HyperTextView, _ sel: NSRange, _ line: NSRange, _ f: (String) -> String) {
            let ns = tv.string as NSString
            var r = sel
            if r.length == 0 {
                r = line
                if ns.substring(with: r).hasSuffix("\n") { r.length -= 1 }
            }
            let result = f(ns.substring(with: r))
            tv.insertText(result, replacementRange: r)
            tv.setSelectedRange(NSRange(location: r.location, length: (result as NSString).length))
        }

        private func select(_ range: NSRange, center: Bool, indicator: Bool, focus: Bool = true) {
            guard let tv = textView else { return }
            let len = document.textStorage.length
            let loc = min(range.location, len)
            let r = NSRange(location: loc, length: min(range.length, len - loc))
            foldController?.reveal(range: r)   // fold: 목적지가 접힌 안이면 먼저 펼친다 (검색 매치처럼 길이 있는 선택은 selectionDidChange 가 펼치지 않는다)
            Perf.measure("  select.setSelectedRange") { tv.setSelectedRange(r) }
            Perf.measure("  select.scrollRangeToVisible loc=\(loc)") { tv.scrollRangeToVisible(r) }
            if focus { tv.window?.makeFirstResponder(tv) }
            if center {
                DispatchQueue.main.async { [weak self] in
                    self?.centerCaret()
                    if indicator { tv.showFindIndicator(for: r) }
                }
            } else if indicator {
                tv.showFindIndicator(for: r)
            }
        }

        private func centerCaret() {
            Perf.measure("  centerCaret") { centerCaretImpl() }
        }

        private func centerCaretImpl() {
            guard let tv = textView, let sv = scrollView, let lm = tv.textLayoutManager, let cs = tv.textContentStorage else { return }
            let loc = tv.selectedRange().location
            guard !tv.isInHugeParagraph(loc) else { return }   // 거대 한 줄: 세그먼트 계산이 문단 전체 배치라 건너뛴다 (scrollRangeToVisible 만으로 충분)
            guard let tl = cs.location(cs.documentRange.location, offsetBy: loc) else { return }
            var rect: CGRect?
            lm.enumerateTextSegments(in: NSTextRange(location: tl), type: .standard, options: [.rangeNotRequired]) { _, f, _, _ in
                rect = f
                return false
            }
            guard let r = rect else { return }
            let visibleH = sv.contentView.bounds.height
            let targetY = r.minY + tv.textContainerOrigin.y - visibleH / 3
            let maxY = max(0, tv.bounds.height - visibleH)
            sv.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, targetY), maxY)))
            sv.reflectScrolledClipView(sv.contentView)
        }

        private func insertTimestamp(in tv: HyperTextView) {
            let ns = tv.string as NSString
            let caret = tv.selectedRange().location
            let lineRange = ns.lineRange(for: NSRange(location: caret, length: 0))
            let lineContent = ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let heading = Timestamp.heading()
            var text = heading + "\n"
            if lineContent.isEmpty {
                // 빈 줄에 삽입: 바로 위 줄이 비어 있지 않으면 빈 줄 하나를 띄운다 (문단 구분)
                if lineRange.location >= 2, ns.character(at: lineRange.location - 1) == 10, ns.character(at: lineRange.location - 2) != 10 {
                    text = "\n" + text
                }
            } else {
                var end = NSMaxRange(lineRange)
                if lineRange.length > 0, ns.character(at: end - 1) == 10 { end -= 1 }
                tv.setSelectedRange(NSRange(location: end, length: 0))
                text = "\n\n" + heading + "\n"
            }
            tv.insertText(text, replacementRange: tv.selectedRange())
            tv.scrollRangeToVisible(tv.selectedRange())
        }

        // MARK: NSTextViewDelegate

        func textDidChange(_ notification: Notification) {
            document.textDidChange()
            gutter?.needsDisplay = true
            session.didEdit(from: self)   // split: 다른 편집기의 거터 갱신
        }

        private var lastCaretLine = 0
        private var lastCaretRect: NSRect?
        private var lastSelection: NSRange?

        func textViewDidChangeSelection(_ notification: Notification) {
            Perf.measure("textViewDidChangeSelection", threshold: 2) { selectionDidChangeImpl() }
        }

        private func selectionDidChangeImpl() {
            guard let tv = textView else { return }
            let sel = tv.selectedRange()
            lastSelection = sel
            let isActive = session.isActive(self)   // split: 상태바·미리보기·위치 저장은 활성 편집기만
            if isActive { model.updateCaret(range: sel) }
            // 현재 줄 하이라이트: 이전/현재 줄 영역만 다시 그림 (전체 needsDisplay 는 TextKit 2 서피스 재합성을 유발)
            let newRect = tv.caretRect(at: sel.location)
            if let r = newRect { tv.setNeedsDisplay(NSRect(x: 0, y: r.minY - 2, width: tv.bounds.width, height: r.height + 4)) }
            if let old = lastCaretRect { tv.setNeedsDisplay(NSRect(x: 0, y: old.minY - 2, width: tv.bounds.width, height: old.height + 4)) }
            lastCaretRect = newRect
            let line = isActive ? model.caretLine : document.lineIndex.lineNumber(forUTF16Offset: sel.location)
            if line != lastCaretLine { lastCaretLine = line; gutter?.needsDisplay = true }
            if isActive { scheduleSaveViewState() }
            foldController?.selectionDidChange()   // fold: 캐럿이 숨은 줄로 들어가면 펼친다 (뷰마다)
            secretController?.selectionDidChange()   // secrets: 캐럿이 든 비밀 블록을 드러내고, 떠난 블록을 다시 가린다 (뷰마다)
        }
    }
}
