import SwiftUI
import AppKit
import Combine
import HyperCore

/// 렌더링 문제 격리용 실행 인자 (개발 전용)
enum DebugFlags {
    static let args = CommandLine.arguments
    static let noApply = args.contains("--debug-no-apply")     // 테마/폰트 속성 적용 안 함
    static let noSwap = args.contains("--debug-no-swap")       // 문서 스토리지 교체 대신 텍스트 복사
}

/// NSScrollView + HyperTextView(TextKit 2) 를 SwiftUI 에 올린다. 문서의 NSTextStorage 를 직접 공유.
struct EditorView: NSViewRepresentable {
    @EnvironmentObject var model: AppModel
    @ObservedObject var document: MemoDocument
    let theme: Theme
    let font: FontSettings

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> EditorContainerView {
        let c = context.coordinator
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
            Perf.measure("  restoreViewState") { c.restoreViewStateIfNeeded() }
            c.textView?.isEditable = document.isLoaded          // 읽지 못한 파일은 편집해도 저장되지 않으므로 편집 자체를 막는다
            c.updateMatchHighlights(model.searchHits, color: theme.selection.nsColor.withAlphaComponent(0.45))
            c.updateWindowTitle()
            c.gutter?.needsDisplay = true
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        let model: AppModel
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

        init(model: AppModel) {
            self.model = model
            self.document = model.document
            super.init()
        }

        // MARK: 구성

        func makeTextView(for doc: MemoDocument, width: CGFloat) -> HyperTextView {
            // NSTextView 가 자체 TextKit 2 스택(뷰포트 레이아웃 delegate 포함)을 구성하게 한 뒤, 문서의 NSTextStorage 로 교체한다.
            let tv = HyperTextView(usingTextLayoutManager: true)
            if DebugFlags.noSwap {
                tv.textStorage?.setAttributedString(NSAttributedString(string: doc.textStorage.string))
            } else {
                tv.textContentStorage?.textStorage = doc.textStorage
            }
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
            return tv
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
            textView.onMultiChange = { [weak self] m in
                guard let c = self?.model.caret else { return }
                let n = m?.ranges.count ?? 0
                if c.multiCaretCount != n { c.multiCaretCount = n }
                let b = m?.block != nil
                if c.columnBlockActive != b { c.columnBlockActive = b }
            }
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
            document.$url
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.saveStateTask?.cancel()
                    self.textView?.undoManager?.removeAllActions()
                    self.restored = false
                    self.lastCaretRect = nil
                }
                .store(in: &docCancellables)
        }

        func rebind(document newDoc: MemoDocument) {
            saveViewStateNow()
            document = newDoc
            Perf.measure("  rebind.swapStorage") { textView?.textContentStorage?.textStorage = newDoc.textStorage }
            textView?.undoManager?.removeAllActions()
            lastReloadGeneration = newDoc.reloadGeneration
            restored = false
            appliedThemeID = nil
            bindDocument()
            if let t = lastTheme, let f = lastFont { apply(theme: t, font: f, force: true) }
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
            document.hangulFont = hangul

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

            let ts = tv.textStorage ?? document.textStorage
            let full = NSRange(location: 0, length: ts.length)
            ts.beginEditing()
            Perf.measure("  apply.setAttributes len=\(full.length)") { ts.setAttributes(attrs, range: full) }
            if let h = hangul { Perf.measure("  apply.hangul") { HangulFontFixer.apply(font: h, to: ts, in: full) } }
            Perf.measure("  apply.endEditing") { ts.endEditing() }

            tv.backgroundColor = theme.background.nsColor
            tv.drawsBackground = true
            tv.insertionPointColor = theme.cursor.nsColor
            tv.textColor = theme.foreground.nsColor
            tv.selectedTextAttributes = [.backgroundColor: theme.selection.nsColor]
            tv.currentLineColor = theme.lineHighlight.nsColor
            scrollView?.backgroundColor = theme.background.nsColor
            gutter?.apply(theme: theme, baseFont: base)
            container?.layer?.backgroundColor = theme.background.nsColor.cgColor
            tv.needsDisplay = true
            highlightKey = ""   // 전체 속성 재적용으로 매치 강조가 지워졌으니 다음 update 에서 다시 칠한다
            highlightedRanges = []
        }

        func handleReload(generation: Int) {
            guard generation != lastReloadGeneration else { return }
            lastReloadGeneration = generation
            textView?.undoManager?.removeAllActions()
            if let t = lastTheme, let f = lastFont { apply(theme: t, font: f, force: true) }
            // 외부 변경 반영 뒤 캐럿이 문서 끝으로 튀지 않도록 직전 위치(클램프)를 복원 — 같은 파일을 다른 도구로 덧붙여 쓰는 흐름에서 읽던 자리를 잃지 않는다
            if restored, let tv = textView, let keep = lastSelection {
                let len = document.textStorage.length
                let loc = min(keep.location, len)
                tv.setSelectedRange(NSRange(location: loc, length: 0))
                tv.scrollRangeToVisible(NSRange(location: loc, length: 0))
            }
        }

        // MARK: 검색 매치 강조 (문서 속성에 배경색만 얹는다 — 저장되는 문자열·undo 에는 영향 없음)

        private var highlightedRanges: [NSRange] = []
        private var highlightKey = ""

        func updateMatchHighlights(_ hits: [SearchHit], color: NSColor) {
            guard let ts = textView?.textStorage else { return }
            let key = "\(hits.count):\(hits.first?.range.location ?? -1):\(hits.last?.range.location ?? -1):\(ts.length)"
            guard key != highlightKey else { return }
            highlightKey = key
            let len = ts.length
            ts.beginEditing()
            for r in highlightedRanges where NSMaxRange(r) <= len { ts.removeAttribute(.backgroundColor, range: r) }
            highlightedRanges = hits.prefix(3000).map(\.range).filter { $0.location >= 0 && NSMaxRange($0) <= len }
            for r in highlightedRanges { ts.addAttribute(.backgroundColor, value: color, range: r) }
            ts.endEditing()
        }

        /// 편집으로 범위가 낡으면 전부 걷어낸다 (다음 검색에서 다시 칠한다)
        private func clearMatchHighlights() {
            guard !highlightedRanges.isEmpty, let ts = textView?.textStorage else { return }
            ts.beginEditing()
            ts.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: ts.length))
            ts.endEditing()
            highlightedRanges = []
            highlightKey = ""
        }

        /// 보이는 영역의 첫 레이아웃 조각이 속한 줄(1-based)을 EditorCaret 에 발행한다 — 거터와 같은 TextKit 2 질의
        func publishFirstVisibleLine() {
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
            if let st = ViewStateStore.load(for: document.url) {
                select(NSRange(location: min(st.cursor, len), length: 0), center: true, indicator: false)
            } else {
                select(NSRange(location: len, length: 0), center: false, indicator: false)
            }
            _ = tv
        }

        private func scheduleSaveViewState() {
            saveStateTask?.cancel()
            saveStateTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                guard !Task.isCancelled else { return }
                self?.saveViewStateNow()
            }
        }

        private func saveViewStateNow() {
            guard let tv = textView, document.isLoaded else { return }
            ViewStateStore.save(EditorViewState(cursor: tv.selectedRange().location, scrollY: Double(tv.visibleRect.minY)), for: document.url)
        }

        // MARK: 명령

        func handle(_ cmd: EditorCommand) {
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
                action(tv)
                document.textDidChange()
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
            let ns = tv.string as NSString
            let sel = tv.selectedRange()
            var cur = ns.lineRange(for: sel)          // 선택을 포함하는 줄 범위(개행 포함)
            if tool == .joinLines, sel.length == 0, NSMaxRange(cur) < ns.length {
                // 선택이 없으면 현재 줄 + 다음 줄을 합친다 (한 줄만으로는 합칠 대상이 없다)
                cur = NSUnionRange(cur, ns.lineRange(for: NSRange(location: NSMaxRange(cur), length: 0)))
            }
            tv.window?.makeFirstResponder(tv)
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
            }
            document.textDidChange()
            gutter?.needsDisplay = true
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

        private func select(_ range: NSRange, center: Bool, indicator: Bool) {
            guard let tv = textView else { return }
            let len = document.textStorage.length
            let loc = min(range.location, len)
            let r = NSRange(location: loc, length: min(range.length, len - loc))
            Perf.measure("  select.setSelectedRange") { tv.setSelectedRange(r) }
            Perf.measure("  select.scrollRangeToVisible loc=\(loc)") { tv.scrollRangeToVisible(r) }
            tv.window?.makeFirstResponder(tv)
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
            clearMatchHighlights()
            gutter?.needsDisplay = true
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
            model.updateCaret(range: sel)
            // 현재 줄 하이라이트: 이전/현재 줄 영역만 다시 그림 (전체 needsDisplay 는 TextKit 2 서피스 재합성을 유발)
            let newRect = tv.caretRect(at: sel.location)
            if let r = newRect { tv.setNeedsDisplay(NSRect(x: 0, y: r.minY - 2, width: tv.bounds.width, height: r.height + 4)) }
            if let old = lastCaretRect { tv.setNeedsDisplay(NSRect(x: 0, y: old.minY - 2, width: tv.bounds.width, height: old.height + 4)) }
            lastCaretRect = newRect
            let line = model.caretLine
            if line != lastCaretLine { lastCaretLine = line; gutter?.needsDisplay = true }
            scheduleSaveViewState()
        }
    }
}
