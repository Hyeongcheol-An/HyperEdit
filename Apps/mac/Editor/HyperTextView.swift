import AppKit
import HyperCore

/// 멀티 커서 / 열(블록) 선택 상태
struct MultiSelection: Equatable {
    var ranges: [NSRange]        // 문서 기준, 정렬됨
    var block: ColumnBlock?      // 열 모드 블록이면 설정
    var isColumn: Bool { block != nil }
}

/// TextKit 2 기반 NSTextView + 현재 줄 하이라이트 + UltraEdit 열 모드 + 멀티 커서.
/// 멀티 편집은 shouldChangeText(inRanges:) → replaceCharacters → didChangeText 경로라 ⌘Z 한 번으로 되돌려진다.
final class HyperTextView: NSTextView {
    var currentLineColor: NSColor?
    var onDidMoveToWindow: (() -> Void)?
    var onMultiChange: ((MultiSelection?) -> Void)?
    /// 북마크 줄 추적: 편집으로 줄 수가 바뀌기 직전에 (기준 줄, 증감) 을 알린다 — 기준 줄보다 뒤의 줄이 delta 만큼 이동한다.
    /// 줄 머리에서 시작하는 편집(줄 앞 Enter, 줄 삭제)은 기준 줄을 하나 앞당겨 그 줄 자체도 밀리거나 지워지게 한다.
    var onLinesWillChange: ((_ atLine: Int, _ delta: Int) -> Void)?
    /// false 를 돌려주면(북마크 없음) 줄 번호 계산을 건너뛴다
    var needsLineTracking: (() -> Bool)?
    /// 분할 보기: 이 뷰가 포커스를 받거나 클릭되면 알린다 — 명령·상태바가 이 뷰 기준이 된다
    var onBecomeActive: (() -> Void)?   // split
    private var lineChangeDepth = 0

    // MARK: 접기 훅 (FoldController 가 설치 — 이 뷰는 접힘 상태를 모른다. 그리기·이동 구현은 FoldController.swift 의 extension)   // fold
    /// 모든 편집(줄 수 변화 여부와 무관)을 편집 전 좌표로 알린다 — 접힘 오프셋 추적용. 보통 저장소 변경 직전(alreadyApplied == false)이고,
    /// shouldChangeText 를 거치지 않는 undo/redo 는 저장소가 바뀐 직후 사후 통지된다(alreadyApplied == true)
    var onTextWillChange: ((_ edits: [(NSRange, String)], _ alreadyApplied: Bool) -> Void)?
    /// 접힘이 하나라도 있는가 — 없으면 그리기에서 레이아웃 질의를 건너뛴다
    var hasFolds: (() -> Bool)?
    var isOffsetHidden: ((Int) -> Bool)?
    /// 오프셋을 숨기고 있는 (겹침을 합친) 구간 [hiddenStart, hiddenEnd)
    var foldedSpan: ((Int) -> NSRange?)?
    var foldPills: ((_ visibleRange: NSRange) -> [FoldPill])?
    var onFoldPillClick: ((_ hiddenStart: Int) -> Void)?
    var foldPillTextColor = NSColor.secondaryLabelColor
    var foldPillFillColor = NSColor.controlBackgroundColor
    var foldPillRects: [(NSRect, Int)] = []

    /// 열 모드 (UltraEdit Alt+C): 켜져 있으면 드래그와 ⇧방향키가 사각형 블록을 만든다
    var columnModeEnabled = false {
        didSet {
            if !columnModeEnabled, multi?.isColumn == true { collapseToHead() }
            needsDisplay = true
        }
    }

    private(set) var multi: MultiSelection? {
        didSet { if multi != oldValue { onMultiChange?(multi); needsDisplay = true } }
    }
    private var settingSelectionProgrammatically = false
    /// 매크로 기록 싱크(MacroRecorder.install). 재생·텍스트 도구·doCommand 내부 편집 중에는 depth > 0 으로 기록을 끈다 — 구현은 MacroRecorder.swift   // macro
    var macroSink: ((MacroStep) -> Void)?   // macro
    var macroSuppressDepth = 0   // macro

    // 스니펫 (SnippetSession.swift): 트리거 단어 → 펼침 결과 (nil 이면 일반 Tab). 저장소는 뷰가 모른다 — Coordinator 가 공급자를 꽂는다
    var snippetProvider: ((String) -> SnippetExpansion?)?
    var onSnippetExpanded: ((String) -> Void)?
    var snippetSession: SnippetSession?

    override var acceptsFirstResponder: Bool { true }

    deinit { Perf.log("HyperTextView deinit") }   // split: 닫힌 보조 뷰 해제 추적 (--debug-perf)

    override func becomeFirstResponder() -> Bool {   // split
        let ok = super.becomeFirstResponder()
        if ok { onBecomeActive?() }
        return ok
    }
    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { installEditObservers() }
        if window != nil { DispatchQueue.main.async { [weak self] in self?.onDidMoveToWindow?() } }
    }

    // MARK: - 그리기

    override func drawBackground(in rect: NSRect) {
        Perf.measure("HyperTextView.drawBackground", threshold: 2) {
            super.drawBackground(in: rect)
            drawCurrentLineHighlight()
            drawFoldPills()   // fold
        }
    }

    private func drawCurrentLineHighlight() {
        guard multi == nil, let color = currentLineColor, selectedRange().length == 0,
              let r = caretRect(at: selectedRange().location) else { return }
        var line = r
        line.origin.x = 0
        line.size.width = bounds.width
        color.setFill()
        line.fill()
    }

    /// 머리 캐럿은 네이티브가, 나머지 캐럿은 직접 그린다 (가상 공백 위치 포함)
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        super.drawInsertionPoint(in: rect, color: color, turnedOn: flag)
        guard flag, let m = multi else { return }
        let ns = string as NSString
        let headIndex = m.block.map { $0.headIsBottom ? m.ranges.count - 1 : 0 } ?? (m.ranges.count - 1)
        let paddings = m.block?.lines(in: ns).map(\.padding) ?? []
        color.setFill()
        for (i, r) in m.ranges.enumerated() where r.length == 0 && i != headIndex {
            guard var cr = caretRect(at: r.location) else { continue }
            if i < paddings.count { cr.origin.x += CGFloat(paddings[i]) * charWidth }
            cr.size.width = max(1, rect.width)
            cr.fill()
        }
    }

    private var charWidth: CGFloat {
        let f = (typingAttributes[.font] as? NSFont) ?? font ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        return FontCascade.advance(of: f)
    }

    /// 문서 오프셋의 캐럿 사각형 (텍스트 뷰 좌표)
    func caretRect(at offset: Int) -> NSRect? {
        guard let lm = textLayoutManager, let cs = textContentStorage,
              let loc = cs.location(cs.documentRange.location, offsetBy: min(offset, (textStorage?.length ?? 0))) else { return nil }
        var rect: CGRect?
        lm.enumerateTextSegments(in: NSTextRange(location: loc), type: .standard, options: [.rangeNotRequired]) { _, f, _, _ in
            rect = f; return false
        }
        if rect == nil, let frag = lm.textLayoutFragment(for: loc) { rect = frag.layoutFragmentFrame }
        guard var r = rect else { return nil }
        r.origin.x += textContainerOrigin.x
        r.origin.y += textContainerOrigin.y
        return r
    }

    // MARK: - 선택 변경 감시 (사용자 조작이면 멀티 해제)

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if !settingSelectionProgrammatically, multi != nil { multi = nil }
    }

    // MARK: - 멀티 상태 설정

    func setBlock(_ b: ColumnBlock) {
        let ns = string as NSString
        let lines = b.lines(in: ns)
        guard !lines.isEmpty else { clearMulti(); return }
        let ranges = lines.map(\.range)
        multi = MultiSelection(ranges: ranges, block: b)
        applyNativeSelection(ranges, primary: b.headIsBottom ? ranges.count - 1 : 0)
    }

    func setMulti(_ ranges: [NSRange]) {
        // 낡은 검색 결과 등 문서 밖 범위는 버린다
        let len = (string as NSString).length
        let sorted = ranges.filter { $0.location >= 0 && NSMaxRange($0) <= len }.sorted { $0.location < $1.location }
        guard sorted.count > 1 else {
            clearMulti()
            if let r = sorted.first { setSelectedRange(r) }
            return
        }
        multi = MultiSelection(ranges: sorted, block: nil)
        applyNativeSelection(sorted, primary: sorted.count - 1)
    }

    func clearMulti() {
        guard multi != nil else { return }
        multi = nil
        needsDisplay = true
    }

    /// 머리 위치의 단일 캐럿으로
    func collapseToHead() {
        let ns = string as NSString
        let off = multi?.block?.headOffset(in: ns) ?? multi?.ranges.last?.location ?? selectedRange().location
        clearMulti()
        setSelectedRange(NSRange(location: min(off, ns.length), length: 0))
    }

    private func applyNativeSelection(_ ranges: [NSRange], primary: Int) {
        settingSelectionProgrammatically = true
        defer { settingSelectionProgrammatically = false }
        let p = max(0, min(primary, ranges.count - 1))
        if ranges.allSatisfy({ $0.length == 0 }) {
            // 길이 0 다중 캐럿은 네이티브가 하나로 합치므로 머리만 네이티브에 두고 나머지는 직접 그린다
            super.setSelectedRange(ranges[p])
        } else {
            super.setSelectedRanges(ranges.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
        }
        scrollRangeToVisible(ranges[p])
        needsDisplay = true
    }

    // MARK: - 줄 수 변화 통지
    // 입력·붙여넣기·텍스트 도구·멀티 편집은 shouldChangeText 를 지나므로 저장소가 바뀌기 직전(편집 전 좌표)에 알린다.
    // AppKit 의 shouldChangeText(in:) 는 안에서 shouldChangeText(inRanges:) 를 부르므로 depth 로 한 번만 알린다.
    // undo/redo 는 macOS 27 에서 shouldChangeText 를 거치지 않고 저장소를 직접 바꾼다(실측, 0.5.1 에서도 동일) — NSTextStorage 의
    // didProcessEditing 알림으로 그런 '추적되지 않은' 편집을 잡아 같은 훅을 사후에 부른다 (installEditObservers).

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        lineChangeDepth += 1
        defer { lineChangeDepth -= 1 }
        guard super.shouldChangeText(in: affectedCharRange, replacementString: replacementString) else { return false }
        if lineChangeDepth == 1, let s = replacementString { trackedEdits([(affectedCharRange, s)]) }
        return true
    }

    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        lineChangeDepth += 1
        defer { lineChangeDepth -= 1 }
        guard super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings) else { return false }
        if lineChangeDepth == 1, let strs = replacementStrings, strs.count == affectedRanges.count {
            trackedEdits(Array(zip(affectedRanges.map(\.rangeValue), strs)))
        }
        return true
    }

    private var expectingTrackedEdit = false
    private var editObserversInstalled = false
    /// undo/redo 직전의 전체 개행 수 (그룹 안의 편집마다 갱신) — 북마크 증감 계산용
    private var undoNewlineCount: Int?
    /// 분할 보기: 두 뷰가 같은 저장소 알림을 받으므로, 추적되지 않은 편집(undo/redo)의 북마크 이동·문서 dirty 통지는 주 편집기 한 곳만 한다
    /// (접힘 통지는 뷰마다 자기 상태를 맞춰야 하므로 모두 받는다)
    var tracksUntrackedLineChanges = true

    private func trackedEdits(_ edits: [(NSRange, String)]) {
        expectingTrackedEdit = true
        DispatchQueue.main.async { [weak self] in self?.expectingTrackedEdit = false }   // 편집이 취소돼 저장소 알림이 안 오면 다음 턴에 해제
        onTextWillChange?(edits, false)   // fold
        notifyLineChanges(edits)
        snippetTextWillChange(edits)      // snippets: 탭스톱 범위 보정 (편집 전 좌표)
    }

    /// 저장소 변경 알림(undo/redo 포함)과 undo 관리자 알림 구독. 창에 붙을 때 한 번.
    private func installEditObservers() {
        guard !editObserversInstalled else { return }
        editObserversInstalled = true
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(storageDidProcessEditing(_:)), name: NSTextStorage.didProcessEditingNotification, object: nil)
        nc.addObserver(self, selector: #selector(undoWillChange(_:)), name: .NSUndoManagerWillUndoChange, object: nil)
        nc.addObserver(self, selector: #selector(undoWillChange(_:)), name: .NSUndoManagerWillRedoChange, object: nil)
        nc.addObserver(self, selector: #selector(undoDidChange(_:)), name: .NSUndoManagerDidUndoChange, object: nil)
        nc.addObserver(self, selector: #selector(undoDidChange(_:)), name: .NSUndoManagerDidRedoChange, object: nil)
    }

    @objc private func undoWillChange(_ n: Notification) {
        guard (n.object as? UndoManager) === undoManager, onLinesWillChange != nil, needsLineTracking?() ?? true else { undoNewlineCount = nil; return }
        let ns = string as NSString
        undoNewlineCount = LineIndex.countNewlines(in: ns, range: NSRange(location: 0, length: ns.length))
    }

    @objc private func undoDidChange(_ n: Notification) {
        guard (n.object as? UndoManager) === undoManager else { return }
        undoNewlineCount = nil
        endSnippetSession()   // snippets: undo/redo 는 shouldChangeText 를 거치지 않아 탭스톱 범위가 낡는다 → 세션 종료
    }

    /// shouldChangeText 를 거치지 않은 문자 편집(undo/redo)을 사후에 통지한다. editedRange 는 편집 후 범위, changeInLength 로 편집 전 범위를 되짚는다.
    @objc private func storageDidProcessEditing(_ n: Notification) {
        guard let ts = n.object as? NSTextStorage, ts === textStorage, ts.editedMask.contains(.editedCharacters) else { return }
        if expectingTrackedEdit { expectingTrackedEdit = false; return }
        let edited = ts.editedRange
        guard edited.location != NSNotFound else { return }
        let ns = ts.string as NSString
        let pre = NSRange(location: edited.location, length: max(0, edited.length - ts.changeInLength))
        let replacement = ns.substring(with: NSIntersectionRange(edited, NSRange(location: 0, length: ns.length)))
        onTextWillChange?([(pre, replacement)], true)   // fold: 사후 통지 (뷰마다)
        guard tracksUntrackedLineChanges else { return }   // split: 아래는 주 편집기만
        // 같은 이유로 didChangeText(→ delegate textDidChange → 문서 dirty·자동 저장·줄 인덱스) 도 오지 않는다 — 저장소 편집 처리가 끝난 뒤 직접 부른다
        DispatchQueue.main.async { [weak self] in self?.didChangeText() }
        // 북마크: 개행 증감은 undo 직전에 세어 둔 전체 개행 수와 비교한다 (undo 한 그룹 안의 연속 편집도 각각 제 몫만큼)
        guard let hook = onLinesWillChange, needsLineTracking?() ?? true, let before = undoNewlineCount else { return }
        let total = LineIndex.countNewlines(in: ns, range: NSRange(location: 0, length: ns.length))
        undoNewlineCount = total
        let delta = total - before
        guard delta != 0 else { return }
        var pivot = LineIndex.countNewlines(in: ns, range: NSRange(location: 0, length: pre.location)) + 1
        if pre.location == 0 || ns.character(at: pre.location - 1) == 10 { pivot -= 1 }
        hook(pivot, delta)
    }

    /// 편집 전 텍스트 기준으로 범위별 개행 증감을 계산해 뒤 범위부터 알린다 (앞 범위의 이동이 뒤 범위의 줄 번호를 흔들지 않도록).
    /// 줄 번호는 문서 인덱스(250 ms 지연 갱신) 대신 현재 문자열을 직접 세어 구한다 — 개행이 바뀌는 편집에서만 드는 비용.
    private func notifyLineChanges(_ edits: [(NSRange, String)]) {
        guard let hook = onLinesWillChange, needsLineTracking?() ?? true else { return }
        let ns = string as NSString
        for (range, str) in edits.sorted(by: { $0.0.location > $1.0.location }) {
            guard range.location != NSNotFound, NSMaxRange(range) <= ns.length else { continue }
            let oldNL = LineIndex.countNewlines(in: ns, range: range)
            let newNL = str.utf16.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
            let delta = newNL - oldNL
            guard delta != 0 else { continue }
            var pivot = LineIndex.countNewlines(in: ns, range: NSRange(location: 0, length: range.location)) + 1
            if range.location == 0 || ns.character(at: range.location - 1) == 10 { pivot -= 1 }
            hook(pivot, delta)
        }
    }

    // MARK: - 멀티 편집

    /// 여러 범위를 한 번에 교체 (undo 1그룹). 반환: 각 치환 문자열 끝의 새 캐럿 위치 (문서 순서)
    @discardableResult
    func performReplacements(_ pairs: [(range: NSRange, string: String)]) -> [NSRange] {
        guard !pairs.isEmpty, let ts = textStorage else { return [] }
        let sorted = pairs.sorted { $0.range.location < $1.range.location }
        let ns = ts.string as NSString
        // 되돌리기는 직접 등록한다 (perf): AppKit 이 shouldChangeText(inRanges:) 에서 등록하는 undo 는 범위마다 replaceCharacters 를 따로 재생해
        // 속성 런 배열(한글 폰트 런)을 매번 memmove 한다 — 1.3 MB 문서에서 5,000건 모두 바꾸기의 ⌘Z 가 1.7 s. 편집 전 문자열을 모아 한 번의
        // 일괄 편집으로 되돌리면(redo 도 같은 경로) 수십 ms 다. AppKit 의 등록만 끄고 delegate 확인·IME 정리·줄 추적 훅은 그대로 거친다.
        let originals = sorted.map { ns.substring(with: $0.range) }
        let um = undoManager
        breakUndoCoalescing()
        um?.disableUndoRegistration()
        let allowed = shouldChangeText(inRanges: sorted.map { NSValue(range: $0.range) }, replacementStrings: sorted.map(\.string))
        um?.enableUndoRegistration()
        guard allowed else { return [] }
        settingSelectionProgrammatically = true
        defer { settingSelectionProgrammatically = false }
        ts.beginEditing()
        for p in sorted.reversed() { ts.replaceCharacters(in: p.range, with: p.string) }
        ts.endEditing()
        didChangeText()
        var delta = 0
        var out: [NSRange] = []
        var inverse: [(range: NSRange, string: String)] = []
        for (i, p) in sorted.enumerated() {
            let len = (p.string as NSString).length
            inverse.append((NSRange(location: p.range.location + delta, length: len), originals[i]))
            out.append(NSRange(location: p.range.location + delta + len, length: 0))
            delta += len - p.range.length
        }
        if let um {
            um.registerUndo(withTarget: self) { tv in
                tv.clearMulti()
                let carets = tv.performReplacements(inverse)
                if let first = carets.first { tv.setSelectedRange(NSRange(location: first.location - (inverse[0].string as NSString).length, length: 0)) }
            }
            um.setActionName(String(localized: "Replace"))
            breakUndoCoalescing()
        }
        return out
    }

    private func multiInsert(_ str: String) {
        guard let m = multi else { return }
        let ns = string as NSString
        if let block = m.block {
            performReplacements(block.replacements(in: ns, with: [str]).map { ($0.range, $0.string) })
            setBlock(block.afterInsert(width: (str as NSString).length))
        } else {
            let carets = performReplacements(m.ranges.map { ($0, str) })
            setMulti(carets)
        }
    }

    private func multiDelete(backward: Bool) {
        guard let m = multi else { return }
        let ns = string as NSString
        var pairs: [(NSRange, String)] = []
        if let block = m.block {
            for l in block.lines(in: ns) {
                if l.range.length > 0 { pairs.append((l.range, "")) }
                else if backward, block.colLo <= l.contentLength, l.range.location > l.lineStart { pairs.append((NSRange(location: l.range.location - 1, length: 1), "")) }
                else if !backward, l.range.location < l.lineStart + l.contentLength { pairs.append((NSRange(location: l.range.location, length: 1), "")) }
            }
            if !pairs.isEmpty { performReplacements(pairs) }
            setBlock(block.afterDelete(backward: backward))
        } else {
            for r in m.ranges {
                if r.length > 0 { pairs.append((r, "")) }
                else if backward, r.location > 0 { pairs.append((NSRange(location: r.location - 1, length: 1), "")) }
                else if !backward, r.location < ns.length { pairs.append((NSRange(location: r.location, length: 1), "")) }
            }
            guard !pairs.isEmpty else { return }
            setMulti(performReplacements(pairs))
        }
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        macroRecordInsert(string, replacementRange: replacementRange)   // macro
        guard let m = multi, m.ranges.count > 1 || m.isColumn else {
            super.insertText(string, replacementRange: replacementRange); return
        }
        // 명시적 교체 범위(텍스트 도구·IME 확정 등)는 멀티 편집이 아니다 → 멀티를 접고 그대로 수행 (안 그러면 머리 캐럿에 삽입되고 원문이 남는다)
        if replacementRange.location != NSNotFound, replacementRange != selectedRange() {
            clearMulti()
            super.insertText(string, replacementRange: replacementRange); return
        }
        let str = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        if str.contains("\n") || str.contains("\r") {
            collapseToHead()
            super.insertText(string, replacementRange: selectedRange())
            return
        }
        multiInsert(str)
    }

    /// 한글 등 조합 입력(IME)은 머리 캐럿에서만 이뤄진다 — 멀티 캐럿·열 블록은 명시적으로 머리 위치로 접는다
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if multi != nil { collapseToHead() }
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
    }

    override func doCommand(by selector: Selector) {
        macroRecordCommand(selector); macroSuppressDepth += 1; defer { macroSuppressDepth -= 1 }   // macro
        let hasMulti = multi != nil
        let columnish = columnModeEnabled || multi?.isColumn == true
        // fold: ↑/↓ 가 접힌 줄에 닿으면 접힌 구간을 건너뛴다 (그 밖의 이동은 선택 변경 감시가 자동으로 펼친다)
        if !hasMulti, selector == #selector(NSResponder.moveDown(_:)) || selector == #selector(NSResponder.moveUp(_:)),
           moveAcrossFold(down: selector == #selector(NSResponder.moveDown(_:))) { return }
        switch selector {
        // 스니펫 탭스톱 세션 중에는 Tab/⇧Tab 이 탭스톱 이동, Esc 가 종료 (멀티 캐럿으로 펼친 같은 번호 탭스톱보다 먼저)
        case #selector(NSResponder.insertTab(_:)) where snippetSession != nil: snippetTabForward(); return
        case #selector(NSResponder.insertBacktab(_:)) where snippetSession != nil: snippetTabBackward(); return
        case #selector(NSResponder.cancelOperation(_:)) where snippetSession != nil: endSnippetSession(); if hasMulti { collapseToHead() }; return
        case #selector(NSResponder.moveLeftAndModifySelection(_:)) where columnish: extendBlock(dx: -1, dy: 0); return
        case #selector(NSResponder.moveRightAndModifySelection(_:)) where columnish: extendBlock(dx: 1, dy: 0); return
        case #selector(NSResponder.moveUpAndModifySelection(_:)) where columnish: extendBlock(dx: 0, dy: -1); return
        case #selector(NSResponder.moveDownAndModifySelection(_:)) where columnish: extendBlock(dx: 0, dy: 1); return
        case #selector(NSResponder.deleteBackward(_:)) where hasMulti: multiDelete(backward: true); return
        case #selector(NSResponder.deleteForward(_:)) where hasMulti: multiDelete(backward: false); return
        case #selector(NSResponder.insertTab(_:)) where hasMulti: multiInsert("\t"); return
        case #selector(NSResponder.cancelOperation(_:)) where hasMulti: collapseToHead(); return
        case #selector(NSResponder.insertNewline(_:)) where hasMulti: collapseToHead()
        default: break
        }
        if hasMulti, selector.description.hasPrefix("move") {
            if columnish { collapseToHead() } else { clearMulti() }
        }
        // 단일 캐럿 Tab: 캐럿 앞 단어가 스니펫 트리거면 펼친다 (아니면 일반 Tab)
        if selector == #selector(NSResponder.insertTab(_:)), !hasMulti, expandSnippetAtCaret() { return }
        super.doCommand(by: selector)
        if snippetSession != nil, selector.description.hasPrefix("move") { snippetCaretMoved() }
    }

    /// ⇧방향키로 블록 확장 (블록이 없으면 현재 캐럿에서 시작)
    func extendBlock(dx: Int, dy: Int) {
        let ns = string as NSString
        let block: ColumnBlock
        if let b = multi?.block {
            block = b.extended(dx: dx, dy: dy, in: ns)
        } else {
            let caret = selectedRange().location
            let lr = ns.lineRange(for: NSRange(location: caret, length: 0))
            let col = caret - lr.location
            block = ColumnBlock(topLineStart: lr.location, lineCount: 1, anchorCol: col, headCol: col).extended(dx: dx, dy: dy, in: ns)
        }
        setBlock(block)
    }

    // MARK: - 마우스: ⌘클릭 캐럿 추가, 열 모드/⌥ 드래그 블록 선택

    override func mouseDown(with event: NSEvent) {
        onBecomeActive?()   // split
        endSnippetSession()   // 클릭은 탭스톱 세션을 끝낸다
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let point = convert(event.locationInWindow, from: nil)
        if let hit = foldPillRects.first(where: { $0.0.contains(point) }) { onFoldPillClick?(hit.1); return }   // fold: ⋯ N lines 표식 클릭 → 펼침
        if flags.contains(.command), !flags.contains(.shift) {
            addCaret(at: characterIndexForInsertion(at: point)); return
        }
        if columnModeEnabled || flags.contains(.option) {
            columnDrag(from: point); return
        }
        if multi != nil { clearMulti() }
        super.mouseDown(with: event)
    }

    private func addCaret(at idx: Int) {
        var ranges = multi?.ranges ?? [selectedRange()]
        if let i = ranges.firstIndex(where: { $0.location == idx && $0.length == 0 }), ranges.count > 1 { ranges.remove(at: i) }
        else { ranges.append(NSRange(location: idx, length: 0)) }
        window?.makeFirstResponder(self)
        setMulti(ranges)
    }

    /// 점 → (줄 시작, 열). 줄 끝 너머는 x 로 가상 열을 추정
    private func position(at p: NSPoint) -> (lineStart: Int, col: Int) {
        let ns = string as NSString
        let idx = min(characterIndexForInsertion(at: p), ns.length)
        let lr = ns.lineRange(for: NSRange(location: idx, length: 0))
        var content = lr.length
        if content > 0, ns.character(at: NSMaxRange(lr) - 1) == 10 { content -= 1 }
        var col = idx - lr.location
        if col >= content, let endRect = caretRect(at: lr.location + content) {
            let extra = (p.x - endRect.minX) / max(1, charWidth)
            if extra > 0.5 { col = content + Int(extra.rounded()) }
        }
        return (lr.location, col)
    }

    private func lineCount(from top: Int, to bottom: Int) -> Int {
        let ns = string as NSString
        var count = 1, cursor = top
        while cursor < bottom {
            let lr = ns.lineRange(for: NSRange(location: cursor, length: 0))
            let next = NSMaxRange(lr)
            if next > bottom || next >= ns.length || lr.length == 0 { break }
            count += 1; cursor = next
        }
        return count
    }

    private func columnDrag(from start: NSPoint) {
        window?.makeFirstResponder(self)
        let a = position(at: start)
        setBlock(ColumnBlock(topLineStart: a.lineStart, lineCount: 1, anchorCol: a.col, headCol: a.col))
        while let e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let h = position(at: convert(e.locationInWindow, from: nil))
            let top = min(a.lineStart, h.lineStart), bottom = max(a.lineStart, h.lineStart)
            setBlock(ColumnBlock(topLineStart: top, lineCount: lineCount(from: top, to: bottom),
                                 anchorCol: a.col, headCol: h.col, headIsBottom: h.lineStart >= a.lineStart))
            autoscroll(with: e)
            if e.type == .leftMouseUp { break }
        }
    }

    // MARK: - 클립보드 (열 블록은 줄 단위)

    override func copy(_ sender: Any?) {
        guard let m = multi, m.ranges.contains(where: { $0.length > 0 }) else { super.copy(sender); return }
        let ns = string as NSString
        let text = m.ranges.map { ns.substring(with: $0) }.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    override func cut(_ sender: Any?) {
        guard let m = multi else { super.cut(sender); return }
        guard m.ranges.contains(where: { $0.length > 0 }) else { return }   // 길이 0 캐럿뿐이면 지울 선택이 없다 (앞 글자를 지우면 안 됨)
        copy(sender)
        multiDelete(backward: false)
    }

    override func paste(_ sender: Any?) {
        macroRecordPaste(); macroSuppressDepth += 1; defer { macroSuppressDepth -= 1 }   // macro
        guard let m = multi, let s = NSPasteboard.general.string(forType: .string) else { super.paste(sender); return }
        var lines = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        if lines.count == 1 { multiInsert(lines[0]); return }
        if lines.count == m.ranges.count {
            let ns = string as NSString
            if let block = m.block {
                performReplacements(block.replacements(in: ns, with: lines).map { ($0.range, $0.string) })
                setBlock(block.afterInsert(width: lines.map { ($0 as NSString).length }.max() ?? 0))
            } else {
                setMulti(performReplacements(Array(zip(m.ranges, lines))))
            }
            return
        }
        collapseToHead()
        super.paste(sender)
    }

    // MARK: - 열 도구

    /// Insert Number: 각 줄(캐럿)에 start 부터 step 씩
    func insertColumnNumbers(start: Int, step: Int, zeroPad: Bool) {
        guard let m = multi else { return }
        let strings = ColumnBlock.numberStrings(count: m.ranges.count, start: start, step: step, zeroPad: zeroPad)
        let ns = string as NSString
        if let block = m.block {
            performReplacements(block.replacements(in: ns, with: strings).map { ($0.range, $0.string) })
            setBlock(block.afterInsert(width: strings.map { ($0 as NSString).length }.max() ?? 0))
        } else {
            setMulti(performReplacements(Array(zip(m.ranges, strings))))
        }
    }

    /// ⌘D: 선택이 없으면 단어 선택, 있으면 같은 문자열의 다음 등장을 선택에 추가
    func addNextOccurrence() {
        let ns = string as NSString
        var ranges = multi?.ranges ?? [selectedRange()]
        guard let last = ranges.last else { return }
        if last.length == 0 {
            let word = selectionRange(forProposedRange: last, granularity: .selectByWord)
            guard word.length > 0 else { return }
            if ranges.count == 1 { setSelectedRange(word) } else { ranges[ranges.count - 1] = word; setMulti(ranges) }
            return
        }
        let needle = ns.substring(with: last)
        let searchFrom = ranges.map { NSMaxRange($0) }.max() ?? 0
        var found = ns.range(of: needle, options: [], range: NSRange(location: searchFrom, length: ns.length - searchFrom))
        if found.location == NSNotFound {
            found = ns.range(of: needle, options: [], range: NSRange(location: 0, length: ranges.map(\.location).min() ?? 0))
        }
        guard found.location != NSNotFound, !ranges.contains(where: { $0 == found }) else { return }
        ranges.append(found)
        setMulti(ranges)
    }
}
