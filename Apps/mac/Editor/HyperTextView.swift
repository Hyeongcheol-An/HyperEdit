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

    override func becomeFirstResponder() -> Bool {   // split
        let ok = super.becomeFirstResponder()
        if ok { onBecomeActive?() }
        return ok
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { DispatchQueue.main.async { [weak self] in self?.onDidMoveToWindow?() } }
    }

    // MARK: - 그리기

    override func drawBackground(in rect: NSRect) {
        Perf.measure("HyperTextView.drawBackground", threshold: 2) {
            super.drawBackground(in: rect)
            drawCurrentLineHighlight()
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
    // 모든 편집 — 입력·붙여넣기·텍스트 도구·멀티 편집, 그리고 undo/redo(AppKit 이 범위마다 shouldChangeText(in:) 를 다시 부른다) — 가 이 길을 지난다.
    // AppKit 의 shouldChangeText(in:) 는 안에서 shouldChangeText(inRanges:) 를 부르므로 depth 로 한 번만 알린다.

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        lineChangeDepth += 1
        defer { lineChangeDepth -= 1 }
        guard super.shouldChangeText(in: affectedCharRange, replacementString: replacementString) else { return false }
        if lineChangeDepth == 1, let s = replacementString { notifyLineChanges([(affectedCharRange, s)]); snippetTextWillChange([(affectedCharRange, s)]) }
        return true
    }

    override func shouldChangeText(inRanges affectedRanges: [NSValue], replacementStrings: [String]?) -> Bool {
        lineChangeDepth += 1
        defer { lineChangeDepth -= 1 }
        guard super.shouldChangeText(inRanges: affectedRanges, replacementStrings: replacementStrings) else { return false }
        if lineChangeDepth == 1, let strs = replacementStrings, strs.count == affectedRanges.count {
            notifyLineChanges(Array(zip(affectedRanges.map(\.rangeValue), strs)))
            snippetTextWillChange(Array(zip(affectedRanges.map(\.rangeValue), strs)))
        }
        return true
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
        guard shouldChangeText(inRanges: sorted.map { NSValue(range: $0.range) }, replacementStrings: sorted.map(\.string)) else { return [] }
        settingSelectionProgrammatically = true
        defer { settingSelectionProgrammatically = false }
        ts.beginEditing()
        for p in sorted.reversed() { ts.replaceCharacters(in: p.range, with: p.string) }
        ts.endEditing()
        didChangeText()
        var delta = 0
        var out: [NSRange] = []
        for p in sorted {
            let len = (p.string as NSString).length
            out.append(NSRange(location: p.range.location + delta + len, length: 0))
            delta += len - p.range.length
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
