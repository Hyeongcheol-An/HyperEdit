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

    deinit {
        blinkTimer?.invalidate()   // appearance
        windowKeyObservers.forEach { NotificationCenter.default.removeObserver($0) }   // appearance
        removeEditObservers()   // fold: 저장소·undo 알림 구독 해제 (이 뷰가 건 것만)
        Perf.log("HyperTextView deinit")                   // split: 닫힌 보조 뷰 해제 추적 (--debug-perf)
    }

    override func becomeFirstResponder() -> Bool {   // split
        let ok = super.becomeFirstResponder()
        if ok { onBecomeActive?(); caretVisibilityChanged() }   // appearance
        return ok
    }
    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok { caretVisibilityChanged() }   // appearance
        return ok
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindowKeyState()   // appearance: 키 창 전환에 맞춰 직접 그리는 캐럿을 보이고 숨긴다
        caretVisibilityChanged()  // appearance: 창에서 떨어지면 깜빡임 타이머 정지
        if window != nil { installEditObservers() }
        if window != nil { DispatchQueue.main.async { [weak self] in self?.onDidMoveToWindow?() } }
    }

    // MARK: - 그리기

    override func drawBackground(in rect: NSRect) {
        Perf.measure("HyperTextView.drawBackground", threshold: 2) {
            super.drawBackground(in: rect)
            drawCurrentLineHighlight()
            drawCarets()      // appearance: Block·Underline 머리 캐럿 + 보조 캐럿 (글자 아래 레이어)
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

    // MARK: - 커서 스타일 (appearance)
    // macOS 14+ 의 NSTextView 는 머리 캐럿을 NSTextInsertionIndicator 하위 뷰로 그리고 drawInsertionPoint(in:color:turnedOn:) 는 부르지 않는다
    // (macOS 27 실측: 키 창·첫 응답자 상태에서도 0회 — 예전의 멀티 캐럿 오버라이드는 그려지지 않았다). AppKit 은 표시기를 보일 때
    // displayMode=.automatic·isHidden=false, 숨길 때(선택 있음·포커스 없음·비활성) displayMode=.hidden·isHidden=true 로 둔다.
    // Bar: 네이티브 표시기를 그대로 쓰고 깜빡임 끄기는 displayMode=.visible. Block·Underline: 표시기를 .hidden 으로 두고(KVO 로 AppKit 이
    // 되돌릴 때마다 다시) drawBackground 에서 직접 그린다 — 글자 아래 레이어라 글자가 가려지지 않는다. 표시 여부는 AppKit 과 같은 규칙
    // (키 창 + 첫 응답자 + 선택 없음)으로 직접 판단하고(headCaretVisible), 깜빡임은 0.5 s 타이머(입력 직후 0.5 s 는 켜 둠).
    // 보조 캐럿(멀티 커서·열 모드 가상 공백)은 세 스타일 모두 직접 그리며 깜빡이지 않는다. 캐럿색은 insertionPointColor(테마 cursor).
    var cursorStyle: CursorStyle = .bar { didSet { guard cursorStyle != oldValue else { return }; cursorConfigChanged() } }
    var cursorBlinks = true { didSet { guard cursorBlinks != oldValue else { return }; cursorConfigChanged() } }
    private var blinkTimer: Timer?
    private var blinkOn = true
    private var blinkRestartedAt: CFAbsoluteTime = 0
    private var indicatorObservations: [NSKeyValueObservation] = []
    private var windowKeyObservers: [NSObjectProtocol] = []
    /// 마지막으로 그린 머리 캐럿 칸 — 캐럿이 옮겨 가면 이전 자리를 지우기 위해 함께 무효화한다
    private var lastDrawnHeadCell: NSRect?
    var isBlinkTimerRunning: Bool { blinkTimer != nil }

    /// 네이티브 삽입점 표시기 (창이 한 번이라도 키가 된 뒤에 생긴다)
    var insertionIndicator: NSTextInsertionIndicator? { subviews.lazy.compactMap { $0 as? NSTextInsertionIndicator }.first }

    private func cursorConfigChanged() {
        applyInsertionIndicatorMode()
        updateBlinkTimer()
        needsDisplay = true
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        guard let ind = subview as? NSTextInsertionIndicator else { return }
        indicatorObservations = [
            ind.observe(\.displayMode) { [weak self] _, _ in self?.scheduleIndicatorUpdate() },
            ind.observe(\.isHidden) { [weak self] _, _ in self?.scheduleIndicatorUpdate() },
        ]
        scheduleIndicatorUpdate()
    }

    private var indicatorUpdateScheduled = false
    private var applyingIndicatorMode = false
    /// KVO 알림 안에서 표시기를 다시 설정하면 AppKit 의 setter 와 재진입해 무한 재귀가 된다
    /// (실측: setDisplayMode: 가 값을 저장하기 전에 setHidden: 을 불러 isHidden 관찰자가 먼저 깨어난다) → 다음 런루프 턴에 한 번만 처리
    private func scheduleIndicatorUpdate() {
        guard !applyingIndicatorMode, !indicatorUpdateScheduled else { return }
        indicatorUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.indicatorUpdateScheduled = false
            self.indicatorStateChanged()
        }
    }

    override func willRemoveSubview(_ subview: NSView) {
        if subview is NSTextInsertionIndicator { indicatorObservations.removeAll() }
        super.willRemoveSubview(subview)
    }

    private func indicatorStateChanged() {
        applyInsertionIndicatorMode()
    }

    /// 키 창 전환 알림 — 이 뷰가 건 토큰만 보관·해제한다 (removeObserver(self) 로 통째로 지우면 AppKit 내부 구독까지 사라진다)
    private func observeWindowKeyState() {
        let nc = NotificationCenter.default
        windowKeyObservers.forEach { nc.removeObserver($0) }
        windowKeyObservers.removeAll()
        guard let w = window else { return }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            windowKeyObservers.append(nc.addObserver(forName: name, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.caretVisibilityChanged() }
            })
        }
    }

    /// 첫 응답자·키 창·선택이 바뀌었다 — 깜빡임 타이머를 맞추고 직접 그리는 캐럿 자리를 다시 그린다 (멀티 캐럿은 보조 캐럿까지 모두)
    private func caretVisibilityChanged() {
        updateBlinkTimer()
        if cursorStyle != .bar || multi != nil { invalidateHeadCaret() }
    }

    /// 보조 캐럿(멀티 커서)도 네이티브 머리 캐럿처럼 키 창 + 첫 응답자일 때만 보인다
    private var caretsActive: Bool {
        guard let w = window else { return false }
        return w.isKeyWindow && w.firstResponder === self
    }

    /// 표시기 모드 강제: Bar → .automatic(깜빡임) / .visible(깜빡임 끔) — AppKit 이 숨긴(isHidden) 동안은 건드리지 않는다. Block·Underline → 항상 .hidden
    func applyInsertionIndicatorMode() {
        guard let ind = insertionIndicator, !applyingIndicatorMode else { return }
        applyingIndicatorMode = true
        defer { applyingIndicatorMode = false }
        switch cursorStyle {
        case .bar:
            let wanted: NSTextInsertionIndicator.DisplayMode = cursorBlinks ? .automatic : .visible
            if !ind.isHidden, ind.displayMode != wanted { ind.displayMode = wanted }
        case .block, .underline:
            if ind.displayMode != .hidden { ind.displayMode = .hidden }
        }
    }

    /// 머리 캐럿을 보여야 하는가 — AppKit 과 같은 규칙: 키 창 + 첫 응답자 + (머리) 선택 길이 0.
    /// (표시기의 isHidden 은 displayMode=.hidden 과 묶여 있어 우리가 숨긴 뒤에는 읽을 수 없다 — 실측)
    var headCaretVisible: Bool {
        guard let w = window, w.isKeyWindow, w.firstResponder === self, isSelectable else { return false }
        if let m = multi {
            let headIndex = m.block.map { $0.headIsBottom ? m.ranges.count - 1 : 0 } ?? (m.ranges.count - 1)
            return m.ranges.indices.contains(headIndex) && m.ranges[headIndex].length == 0
        }
        return selectedRange().length == 0
    }

    private func updateBlinkTimer() {
        let wants = cursorStyle != .bar && cursorBlinks && headCaretVisible
        if wants {
            guard blinkTimer == nil else { return }
            blinkOn = true
            blinkRestartedAt = CFAbsoluteTimeGetCurrent()
            let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.blinkTick() }
            RunLoop.main.add(t, forMode: .common)
            blinkTimer = t
        } else if let t = blinkTimer {
            t.invalidate()
            blinkTimer = nil
            if !blinkOn { blinkOn = true; invalidateHeadCaret() }
        }
    }

    private func blinkTick() {
        // 입력·이동 직후 0.5 s 동안은 켜 둔다 (네이티브처럼 타이핑 중에는 깜빡이지 않는다)
        if CFAbsoluteTimeGetCurrent() - blinkRestartedAt < 0.5 {
            if !blinkOn { blinkOn = true; invalidateHeadCaret() }
            return
        }
        blinkOn.toggle()
        invalidateHeadCaret()
    }

    /// 선택 변경·입력: 켜진 상태로 되돌리고 깜빡임 주기를 다시 시작
    private func restartBlink() {
        guard cursorStyle != .bar else { return }
        blinkRestartedAt = CFAbsoluteTimeGetCurrent()
        if !blinkOn { blinkOn = true; invalidateHeadCaret() }
    }

    private func invalidateHeadCaret() {
        if multi != nil { needsDisplay = true; return }   // 보조 캐럿까지 모두 다시 (멀티 상태는 드물다)
        if let old = lastDrawnHeadCell { setNeedsDisplay(old.insetBy(dx: -2, dy: -2)) }
        if let r = headCaretCell() { setNeedsDisplay(r.insetBy(dx: -2, dy: -2)) } else if lastDrawnHeadCell == nil { needsDisplay = true }
    }

    /// 머리 캐럿의 글자 칸 (선택이 있으면 nil). 멀티 상태면 머리 범위(열 블록은 가상 공백 포함), 아니면 selectedRange
    private func headCaretCell() -> NSRect? {
        if let m = multi {
            let headIndex = m.block.map { $0.headIsBottom ? m.ranges.count - 1 : 0 } ?? (m.ranges.count - 1)
            guard m.ranges.indices.contains(headIndex), m.ranges[headIndex].length == 0 else { return nil }
            var padding = 0
            if let block = m.block {
                let lines = block.lines(in: string as NSString)
                if headIndex < lines.count { padding = lines[headIndex].padding }
            }
            return caretCell(at: m.ranges[headIndex].location, padding: padding)
        }
        let r = selectedRange()
        guard r.length == 0 else { return nil }
        return caretCell(at: r.location)
    }

    /// 오프셋의 글자 칸: x 는 캐럿 위치(열 모드 가상 공백은 padding 칸만큼 오른쪽), 폭은 그 글자의 실제 폭(한글·탭 포함; 줄 끝·빈 줄·가상 공백은 공백 한 칸), 높이는 줄 높이
    func caretCell(at offset: Int, padding: Int = 0) -> NSRect? {
        guard var cell = caretRect(at: offset) else { return nil }
        let cw = charWidth
        cell.origin.x += CGFloat(padding) * cw
        var width = cw
        let ns = string as NSString
        if padding == 0, offset < ns.length {
            let ch = ns.character(at: offset)
            if ch != 0x0A && ch != 0x0D {
                let next = NSMaxRange(ns.rangeOfComposedCharacterSequence(at: offset))
                if let nr = caretRect(at: next), abs(nr.minY - cell.minY) < 0.5, nr.minX - cell.minX > 0.5 { width = nr.minX - cell.minX }
            }
        }
        cell.size.width = width
        return cell
    }

    /// Block·Underline 머리 캐럿(표시기가 보일 때, 깜빡임 켜짐 상태)과 세 스타일 모두의 보조 캐럿을 글자 아래 레이어에 그린다
    private func drawCarets() {
        let style = cursorStyle
        if style != .bar { applyInsertionIndicatorMode() }   // KVO 처리는 다음 턴이므로 그리기 직전에도 표시기를 숨겨 둔다
        let color = insertionPointColor ?? NSColor.textColor
        if let m = multi {
            guard caretsActive else { return }
            let ns = string as NSString
            let headIndex = m.block.map { $0.headIsBottom ? m.ranges.count - 1 : 0 } ?? (m.ranges.count - 1)
            let paddings = m.block?.lines(in: ns).map(\.padding) ?? []
            let showHead = style != .bar && headCaretVisible && blinkOn
            for (i, r) in m.ranges.enumerated() where r.length == 0 {
                if i == headIndex, !showHead { continue }   // Bar 의 머리는 네이티브 표시기가 그린다
                guard let cell = caretCell(at: r.location, padding: i < paddings.count ? paddings[i] : 0) else { continue }
                drawCaret(cell, style: style, color: color)
                if i == headIndex { lastDrawnHeadCell = cell }
            }
        } else if style != .bar, headCaretVisible, blinkOn, let cell = headCaretCell() {
            drawCaret(cell, style: style, color: color)
            lastDrawnHeadCell = cell
        }
    }

    private func drawCaret(_ cell: NSRect, style: CursorStyle, color: NSColor) {
        switch style {
        case .bar:
            color.setFill()
            NSRect(x: cell.minX, y: cell.minY, width: 2, height: cell.height).fill(using: .sourceOver)
        case .block:
            color.withAlphaComponent(color.alphaComponent * 0.55).setFill()
            cell.fill(using: .sourceOver)
        case .underline:
            color.setFill()
            NSRect(x: cell.minX, y: cell.maxY - 2, width: cell.width, height: 2).fill(using: .sourceOver)
        }
    }

    /// appearance: 배경이 투명(clear)하면 불투명 뷰로 취급되지 않게 — 반투명 창에서 검게 깔리는 것을 막는다
    override var isOpaque: Bool { drawsBackground && backgroundColor.alphaComponent >= 1 }

    override func didChangeText() {
        super.didChangeText()
        restartBlink()   // appearance
    }

    var charWidth: CGFloat {
        let f = (typingAttributes[.font] as? NSFont) ?? font ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        return FontCascade.advance(of: f)
    }

    /// 문서 오프셋의 캐럿 사각형 (텍스트 뷰 좌표)
    /// 이보다 긴 문단(한 줄)에서는 캐럿 사각형을 구하지 않는다 — TextKit 2 는 세그먼트 하나를 얻으려고 문단 전체를 배치하므로
    /// 1.6M 자짜리 한 줄(압축 JSON)에서는 캐럿을 옮길 때마다 수십 초가 걸린다. 현재 줄 강조·멀티 캐럿 그리기만 빠질 뿐 편집은 그대로다.
    static let hugeParagraphLength = 20_000

    /// `offset` 이 든 문단이 `hugeParagraphLength` 보다 긴가 (문단 경계 탐색은 memchr 수준이라 싸다)
    func isInHugeParagraph(_ offset: Int) -> Bool {
        let ns = string as NSString
        guard ns.length > Self.hugeParagraphLength else { return false }
        return ns.paragraphRange(for: NSRange(location: min(offset, ns.length), length: 0)).length > Self.hugeParagraphLength
    }

    func caretRect(at offset: Int) -> NSRect? {
        guard !isInHugeParagraph(offset) else { return nil }
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
        restartBlink(); caretVisibilityChanged()   // appearance: 선택 유무에 따라 보이고 숨기며, 이전 자리를 지운다
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
    /// 어떤 뷰가 shouldChangeText 로 추적 중인 편집의 저장소 (분할 보기: 다른 뷰는 같은 저장소 알림을 '추적되지 않은' 편집으로 보지만,
    /// 북마크·dirty 는 추적한 뷰가 이미 처리했으므로 접힘만 통지해야 한다 — 보조 편집기의 performReplacements 를 되돌릴 때 북마크가 두 번 밀리던 문제)
    private static var storagesWithTrackedEdit = Set<ObjectIdentifier>()
    private var editObserversInstalled = false
    /// 이 뷰가 직접 등록한 알림 구독. `NotificationCenter.removeObserver(self)` 로 통째로 지우면 AppKit 이 NSTextView 내부에 건 구독까지
    /// 사라져 보관 중인 뷰의 레이아웃 매니저가 편집마다 문서 전체를 다시 배치하는 것이 실측됐다 → 반드시 이것만 해제한다.
    private var editObserverNames: [Notification.Name] = []
    /// undo/redo 직전의 전체 개행 수 (그룹 안의 편집마다 갱신) — 북마크 증감 계산용
    private var undoNewlineCount: Int?
    /// 분할 보기: 두 뷰가 같은 저장소 알림을 받으므로, 추적되지 않은 편집(undo/redo)의 북마크 이동·문서 dirty 통지는 주 편집기 한 곳만 한다
    /// (접힘 통지는 뷰마다 자기 상태를 맞춰야 하므로 모두 받는다)
    var tracksUntrackedLineChanges = true

    private func trackedEdits(_ edits: [(NSRange, String)]) {
        expectingTrackedEdit = true
        let storageID = textStorage.map { ObjectIdentifier($0) }
        if let id = storageID { Self.storagesWithTrackedEdit.insert(id) }
        DispatchQueue.main.async { [weak self] in   // 편집이 취소돼 저장소 알림이 안 오면 다음 턴에 해제
            self?.expectingTrackedEdit = false
            if let id = storageID { Self.storagesWithTrackedEdit.remove(id) }
        }
        onTextWillChange?(edits, false)   // fold
        notifyLineChanges(edits)
        snippetTextWillChange(edits)      // snippets: 탭스톱 범위 보정 (편집 전 좌표)
    }

    /// 분할을 닫은 뒤 undo 항목 때문에 보관만 되는 뷰: 저장소·undo 알림 구독과 모든 훅을 끊어 편집마다 일하지 않게 한다
    /// (보관 뷰 20개가 각각 개행 수를 세면 타이핑이 5배 느려지는 것이 실측됐다). undo 재생은 AppKit 이 뷰의 textStorage 로 직접 수행하므로 영향 없다.
    func retireFromEditing() {
        blinkTimer?.invalidate(); blinkTimer = nil; indicatorObservations.removeAll()   // appearance
        windowKeyObservers.forEach { NotificationCenter.default.removeObserver($0) }; windowKeyObservers.removeAll()   // appearance
        removeEditObservers()
        editObserversInstalled = true   // 다시 설치되지 않게
        onTextWillChange = nil; onLinesWillChange = nil; needsLineTracking = { false }
        tracksUntrackedLineChanges = false
        hasFolds = nil; isOffsetHidden = nil; foldedSpan = nil; foldPills = nil; onFoldPillClick = nil
        snippetProvider = nil; macroSink = nil
        onBecomeActive = nil; onMultiChange = nil; onDidMoveToWindow = nil
    }

    /// 저장소 변경 알림(undo/redo 포함)과 undo 관리자 알림 구독. 창에 붙을 때 한 번.
    private func installEditObservers() {
        guard !editObserversInstalled else { return }
        editObserversInstalled = true
        let nc = NotificationCenter.default
        let pairs: [(Notification.Name, Selector)] = [
            (NSTextStorage.didProcessEditingNotification, #selector(storageDidProcessEditing(_:))),
            (.NSUndoManagerWillUndoChange, #selector(undoWillChange(_:))),
            (.NSUndoManagerWillRedoChange, #selector(undoWillChange(_:))),
            (.NSUndoManagerDidUndoChange, #selector(undoDidChange(_:))),
            (.NSUndoManagerDidRedoChange, #selector(undoDidChange(_:))),
        ]
        for (name, sel) in pairs { nc.addObserver(self, selector: sel, name: name, object: nil) }
        editObserverNames = pairs.map(\.0)
    }

    /// installEditObservers 가 건 구독만 해제한다 (이름 단위 — AppKit 내부 구독은 건드리지 않는다)
    private func removeEditObservers() {
        let nc = NotificationCenter.default
        for name in editObserverNames { nc.removeObserver(self, name: name, object: nil) }
        editObserverNames.removeAll()
    }

    /// undo/redo 가 진행 중인가 (저장소 알림이 어떤 편집에서 왔는지 구분하는 데 쓴다)
    private var undoInProgress = false

    @objc private func undoWillChange(_ n: Notification) {
        guard (n.object as? UndoManager) === undoManager else { return }
        undoInProgress = true
        guard onLinesWillChange != nil, needsLineTracking?() ?? true else { undoNewlineCount = nil; return }
        let ns = string as NSString
        undoNewlineCount = LineIndex.countNewlines(in: ns, range: NSRange(location: 0, length: ns.length))
    }

    @objc private func undoDidChange(_ n: Notification) {
        guard (n.object as? UndoManager) === undoManager else { return }
        undoInProgress = false
        undoNewlineCount = nil
        endSnippetSession()   // snippets: undo/redo 는 shouldChangeText 를 거치지 않아 탭스톱 범위가 낡는다 → 세션 종료
    }

    /// shouldChangeText 를 거치지 않은 문자 편집(undo/redo)을 사후에 통지한다. editedRange 는 편집 후 범위, changeInLength 로 편집 전 범위를 되짚는다.
    @objc private func storageDidProcessEditing(_ n: Notification) {
        guard let ts = n.object as? NSTextStorage, ts === textStorage, ts.editedMask.contains(.editedCharacters) else { return }
        if expectingTrackedEdit { expectingTrackedEdit = false; return }
        // 추적되지 않은 편집은 undo/redo 이거나 프로그램적 전체 교체(파일 열기·다시 읽기)다. 접힘이 없고 undo 도 아니면 할 일이 없다 —
        // 여기서 교체 문자열을 복사하면 8 MB 문서를 열 때마다 8 MB 를 복사하게 된다.
        let foldsActive = hasFolds?() ?? false
        guard foldsActive || undoInProgress else { return }
        let edited = ts.editedRange
        guard edited.location != NSNotFound else { return }
        let ns = ts.string as NSString
        let pre = NSRange(location: edited.location, length: max(0, edited.length - ts.changeInLength))
        if foldsActive {
            let replacement = ns.substring(with: NSIntersectionRange(edited, NSRange(location: 0, length: ns.length)))
            onTextWillChange?([(pre, replacement)], true)   // fold: 사후 통지 (뷰마다)
        }
        // split: 아래는 주 편집기만, 그리고 다른 뷰가 shouldChangeText 로 추적한 편집(그 뷰의 undo 클로저가 재생한 performReplacements 등)은 그 뷰가 처리했으므로 제외
        guard undoInProgress, tracksUntrackedLineChanges, !Self.storagesWithTrackedEdit.contains(ObjectIdentifier(ts)) else { return }
        // undo/redo 는 didChangeText 도 부르지 않는다 — 저장소 편집 처리가 끝난 뒤 직접 불러 뷰 상태(입력 합치기 등)를 정리한다.
        // 이 호출을 빼면 undo 뒤 모든 입력이 5배쯤 느려지는 것이 실측됐다. 문서 dirty 는 MemoDocument 가 저장소 알림으로 직접 관리하며,
        // load/reload 의 전체 교체 뒤에 오는 이 호출은 MemoDocument.textDidChange() 가 (문자 편집이 없었으므로) 무시한다.
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
