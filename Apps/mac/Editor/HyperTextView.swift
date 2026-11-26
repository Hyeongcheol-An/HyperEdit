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
    // MARK: 검색 매치 강조 (search) — 스토리지 속성이 아니라 뷰가 그린다
    // NSTextStorage 에 .backgroundColor 를 쓰면 TextKit 2 가 그 범위의 레이아웃을 무효화한다: 1.3 MB 문서에서 편집마다(문서 전체 걷어내기)·
    // 지연 재검색마다(첫 매치~끝 매치) 뷰포트 위쪽의 추정 높이가 바뀌어 스크롤이 문서 맨 위로 튀었다(2026-11-02 보고). 보이는 매치만 drawBackground 에서 칠한다.
    /// 문서 기준 매치 범위(문서 순서로 정렬 — 그리기의 이진 탐색 전제). 편집이 일어나면 범위를 옮기고(입력은 shouldChangeText 의 편집 전 좌표로 정확히,
    /// undo/redo 등 추적되지 않은 편집은 저장소 알림의 범위로) 편집에 걸친 범위는 지운다 — 지연 재검색이 다시 채운다.
    /// 바꿔도 스스로 다시 그리지 않는다: 이동은 보이는 자리를 바꾸지 않고(편집된 문단은 AppKit 이 어차피 다시 그린다) 새 결과는 Coordinator 가 needsDisplay 를 건다
    var matchHighlights: [NSRange] = []
    var matchHighlightColor = NSColor.selectedTextBackgroundColor.withAlphaComponent(0.45) { didSet { if !matchHighlights.isEmpty { needsDisplay = true } } }
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

    // MARK: 줄바꿈 끔 (가로 스크롤) — 구현과 까닭은 HyperTextView+NoWrap.swift
    /// 줄바꿈을 끈 상태인가. `beginNoWrap`/`endNoWrap`(EditorView.Coordinator.setWordWrap)만 바꾼다
    var isNoWrap = false
    /// 줄바꿈 끔에서 지금까지 잰 내용의 폭(가장 넓었던 줄 + 여백). 커지기만 한다 — 버리는 것은 `resetNoWrapWidth`, 글꼴에 맞춰 고치는 것은 `rescaleNoWrapWidth`
    var noWrapContentWidth: CGFloat = 0
    /// 다음 `scrollRangeToVisible` 이 범위 대신 보이게 할 칸 (줄바꿈 끔의 열 블록 머리 — `prepareNoWrapBlockHeadReveal`)
    var noWrapRevealRect: NSRect?

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

    // MARK: 비밀 블록 훅 (SecretController 가 설치 — 이 뷰는 비밀 범위를 모른다)   // secrets
    /// 가릴 줄이 하나라도 있는가 — 접힘처럼 undo/redo 의 사후 편집 통지가 필요하다
    var hasMasks: (() -> Bool)?   // secrets
    /// 문단 시작 오프셋이 지금 가려져 있는가 (셀프테스트용)
    var isOffsetMasked: ((Int) -> Bool)?   // secrets
    /// 복사·잘라내기가 끝난 뒤 복사된 범위를 알린다 — 비밀 줄이 섞였으면 클립보드 자동 소거
    /// secrets: 복사·잘라내기 범위가 비밀 줄과 겹치는지 — 편집 **전에** 판정한다(잘라낸 뒤에는 비밀 구간이 이미 옮겨져 블록 전체를 잘라내면 길이 0 이 된다)
    var secretHitTest: ((_ ranges: [NSRange]) -> Bool)?
    /// secrets: 비밀이 섞인 복사가 페이스트보드에 쓰인 뒤 호출 — 클립보드 소거 예약 (changeCount 는 이 시점 것을 잡는다)
    var onDidCopySecret: (() -> Void)?

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

    /// applock: 잠긴 동안 첫 응답자를 거절한다 — 시작 잠금은 창이 생기기 전이라 lock() 의 makeFirstResponder(nil) 이 닿지 않고, EditorView 가 창에 붙을 때 포커스를 되찾기 때문
    nonisolated(unsafe) static var refusesFirstResponder: (() -> Bool)?
    override var acceptsFirstResponder: Bool { !(Self.refusesFirstResponder?() ?? false) }

    deinit {
        blinkTimer?.invalidate()   // appearance
        windowKeyObservers.forEach { NotificationCenter.default.removeObserver($0) }   // appearance
        removeEditObservers()   // fold: 저장소·undo 알림 구독 해제 (이 뷰가 건 것만)
        Perf.log("HyperTextView deinit")                   // split: 닫힌 보조 뷰 해제 추적 (--debug-perf)
    }

    override func becomeFirstResponder() -> Bool {   // split
        if Self.refusesFirstResponder?() == true { return false }   // applock: makeFirstResponder 는 acceptsFirstResponder 를 묻지 않으므로 여기서 거절한다
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

    // MARK: - 문서 끝을 넘긴 스크롤 위치 바로잡기
    // TextKit 2 는 끝으로 점프할 때(⌘↓·문서 끝으로·마지막 줄로 이동) 먼저 추정 높이 기준의 끝으로 스크롤하고, 뷰포트를 배치하며 추정 → 실측 차이만큼 문서 높이와
    // 스크롤 위치를 다시 맞춘다. 그 과정이 끝났을 때 스크롤 위치가 줄어든 문서 높이를 넘긴 채 남는 경우가 있다(macOS 27 실측, 실사용 하네스 2026-11-24:
    // layout() 한 번 안에서 높이 +93412 → −48, 위치는 −48 을 반영했다가 되돌림) — 마지막 줄 아래에 수십~수백 pt 의 빈 띠가 보이고, 다음 휠 이벤트에서야
    // 그만큼 튀며 돌아온다. 배치가 끝난 뒤 클립 뷰가 허용하는 범위로 되돌린다. 트랙패드로 끝을 넘겨 당기는 중(탄성 스크롤)에는 손대지 않는다
    /// 스크롤 제스처(트랙패드 탄성·관성 포함)의 마지막 움직임 시각, 제스처가 아니면 0 — Coordinator 가 스크롤 뷰의 live scroll 알림(시작·움직임·끝)으로 갱신한다.
    /// 끝 알림이 빠져도(실측: 합성한 제스처 이벤트) 되돌리기가 영영 꺼지지 않도록 마지막 움직임에서 1초가 지나면 제스처가 아닌 것으로 본다
    var liveScrollTick: CFAbsoluteTime = 0
    private var isLiveScrolling: Bool { liveScrollTick > 0 && CFAbsoluteTimeGetCurrent() - liveScrollTick < 1 }
    private var constrainBudget = 4   // 한 런루프 턴 안에서 되돌리기 횟수 상한 (배치 ↔ 되돌리기 핑퐁 방지)
    private var constrainRetryArmed = false

    /// 반환: 스크롤 위치를 되돌렸는가
    @discardableResult
    func constrainScrollToDocumentEnd() -> Bool {
        guard constrainBudget > 0, let sv = enclosingScrollView, sv.documentView === self else { return false }
        let clip = sv.contentView
        let legal = clip.constrainBoundsRect(clip.bounds)
        // 문서 처음 쪽도 본다: 위쪽의 추정 높이를 실측으로 바꾸며 올라오다 맨 위에 닿는 패스에서 AppKit 이 위치를 0 아래로 맞춰 둘 때가 있다 (실측 y = -1.0)
        guard abs(clip.bounds.minY - legal.minY) > 0.5, frame.height > clip.bounds.height else { return false }
        if isLiveScrolling {
            // 제스처 중: 끝 알림이 오면 Coordinator 가 다시 부른다. 그 알림이 빠지는 경우에 대비해 제스처 판정이 풀릴 때 한 번 더 본다
            if !constrainRetryArmed {
                constrainRetryArmed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in self?.constrainRetryArmed = false; self?.constrainScrollToDocumentEnd() }
            }
            return false
        }
        if constrainBudget == 4 { DispatchQueue.main.async { [weak self] in self?.constrainBudget = 4 } }
        constrainBudget -= 1
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: legal.minY))
        sv.reflectScrolledClipView(clip)
        return true
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        if isNoWrap { widenNoWrap(toShow: range) }   // 줄바꿈 끔: 대상이 지금의 폭 밖이면 먼저 넓힌다
        if let cell = noWrapRevealRect { noWrapRevealRect = nil; scrollToVisible(cell) }   // 줄바꿈 끔의 열 블록: 범위(짧은 줄에서는 줄 끝) 대신 머리 칸을 보이게
        else if !(caretStepDepth > 0 && revealCaretStep(range)) { super.scrollRangeToVisible(range) }
        if isNoWrap { revealNoWrapCaretColumn(range) }   // AppKit 이 가장자리에서 한 걸음 늦게 따라올 때 캐럿이 가려지지 않게
        blockLayoutAnchor(dropRecord: false)   // 보이게 스크롤은 글을 옮기는 것이 목적이다 — AppKit 이 다음 배치 패스 안으로 미뤄 수행할 수도 있다
        // 멀리 뛰는 스크롤은 추정 좌표로 간다. 뒤따르는 배치 패스가 그 자리의 문단을 실측하며 문서 높이와 스크롤 위치를 다시 맞추는 사이, 조각은 맞추기 전의
        // 자리에 놓인 채 패스가 끝날 수 있다 (실측: 9,997줄 파일을 끝에서 열자 조각이 화면 위 −230…178 pt 에만 놓여 아래 204 pt 가 다음 스크롤까지 비었다 —
        // 그 패스 안에서는 스크롤 위치가 그대로라 layout() 의 '옮겨졌으면 확인'에 걸리지 않는다). 그 패스가 끝나면 뷰포트가 화면을 덮었는지 본다
        checkViewportAfterEdit = true
        // macOS 27 실측: 대상이 이미 보여 스크롤이 일어나지 않으면 AppKit 은 뷰포트 컨트롤러를 '옮겨 놓기만' 한 채 둔다 — viewportRange 가 빈 범위가 되고
        // viewportBounds 는 화면과 어긋난다(다음 배치 때까지). 방향키로 캐럿만 옮겨도 그렇게 돼, viewportRange 로 보이는 범위를 정하는 검색 강조가
        // 다시 그려지는 줄마다 지워졌다(실사용 하네스 2026-11-24). 이번 표시 주기에 뷰포트를 다시 배치하게 한다 (조각은 이미 배치돼 있어 값싸다)
        if viewportNeedsLayout { needsLayout = true }
        constrainScrollToDocumentEnd()
    }

    override func layout() {
        let anchor = captureLayoutAnchor()
        let cache = fragmentCacheState()
        if let cache { trimFragmentCacheLimit(cache) }
        let clipY = enclosingScrollView?.contentView.bounds.minY
        super.layout()
        if let cache, cache.count > cache.limit { retuneFragmentCacheLimit() }
        settleViewportAfterLayout()
        if restoreLayoutAnchor(anchor) { settleViewportAfterLayout() }
        // 패스 안에서 스크롤 위치가 옮겨졌으면(AppKit 이 위쪽 문단의 추정 → 실측 차이만큼 맞췄거나, 위에서 닻을 되돌렸다) 뷰포트는 옮기기 전 자리에 맞춰 배치된 채다 —
        // 새로 드러난 위·아래 띠의 줄이 번호만 있고 글자가 없다(실측: 버려진 구간으로 올라가며 339 pt 를 맞춘 패스에서 맨 위 두 줄이 다음 스크롤까지 비었다)
        if let clipY, let now = enclosingScrollView?.contentView.bounds.minY, abs(now - clipY) > 0.5 { checkViewportAfterEdit = true }
        coverViewportAfterEdit()
        layoutAnchorBlocked = false
        layoutRecord = makeLayoutRecord()
        if cache != nil { fragmentCountAfterLayout = fragmentCacheState()?.count }
    }

    /// 배치 패스 안에서 옮긴 위치는 다시 배치되지 않는다(needsLayout 이 서지 않는다) — 되돌렸으면 그 자리의 뷰포트를 한 번 더 배치한다.
    /// AppKit 이 배치 패스 안에서 미뤄 둔 '보이게 스크롤'을 수행해 뷰포트를 옮겨 놓기만 한 경우(viewportRange 가 빔)도 마찬가지다
    private func settleViewportAfterLayout() {
        var passes = 0
        while passes < 3, constrainScrollToDocumentEnd() || viewportNeedsLayout { super.layout(); passes += 1 }
    }

    // MARK: - 방향키로 화면 가장자리를 넘을 때: 필요한 만큼만 민다
    // AppKit(TextKit 2)의 scrollRangeToVisible 은 대상이 화면 밖이면 그 줄을 화면 가운데쯤으로 데려간다 — 방향키로 맨 아랫줄을 넘는 순간마다 화면이 반 화면씩 튀고
    // (실측: 460 pt 화면에서 약 220 pt), 아직 배치하지 않은 위쪽으로 올라갈 때는 추정 높이 때문에 착지 높이도 걸음마다 달랐다(y 25…268). 캐럿을 한 줄·한 글자·한 단어·
    // 줄 끝으로 옮기는 키 명령에서는 캐럿 줄이 화면에 다 들어올 만큼만 직접 민다. 문서 처음·끝으로 가기, Page Up/Down, 줄로 이동, 입력 중의 따라가기는 AppKit 그대로다.
    private static let caretStepCommands: Set<Selector> = {
        let moves = ["moveUp", "moveDown", "moveLeft", "moveRight", "moveForward", "moveBackward", "moveWordLeft", "moveWordRight", "moveWordForward", "moveWordBackward",
                     "moveToLeftEndOfLine", "moveToRightEndOfLine", "moveToBeginningOfLine", "moveToEndOfLine", "moveToBeginningOfParagraph", "moveToEndOfParagraph"]
        let names = moves.flatMap { [$0 + ":", $0 + "AndModifySelection:"] } + ["moveParagraphBackwardAndModifySelection:", "moveParagraphForwardAndModifySelection:"]
        return Set(names.map { NSSelectorFromString($0) })
    }()
    private var caretStepDepth = 0
    private var selectionBeforeCaretStep = NSRange(location: 0, length: 0)

    /// 캐럿(선택을 늘리는 중이면 움직인 쪽 끝)의 줄이 화면에 다 들어오게 가장 적게 스크롤한다. 반환: 처리했는가 (false 면 AppKit 에 맡긴다)
    private func revealCaretStep(_ range: NSRange) -> Bool {
        // 조합 중인 글자는 입력기가 다룬다 · 줄바꿈 끔은 가로 스크롤까지 AppKit 이 맡는다
        guard !hasMarkedText(), !isNoWrap, let sv = enclosingScrollView, sv.documentView === self, let lm = textLayoutManager else { return false }
        let clip = sv.contentView
        guard abs(clip.constrainBoundsRect(clip.bounds).minY - clip.bounds.minY) < 0.5 else { return false }   // 끝을 넘겨 당기는 중
        let sel = selectedRange()
        var head = range.location
        if sel.length > 0 { head = sel.location != selectionBeforeCaretStep.location ? sel.location : NSMaxRange(sel) }
        let height = clip.bounds.height
        // 위쪽의 아직 배치하지 않은 문단으로 올라갈 때, 캐럿 줄을 재는 질의는 그 문단을 배치하지만 조각의 자리는 추정 높이로 잡아 둔 채다(다음 뷰포트 배치에서야
        // 아래 조각들과 맞물린다 — 실측: 두 줄로 추정된 한 줄 문단의 캐럿 줄이 실제보다 25.9 pt 위로 나왔다). 그래서 밀고 → 뷰포트를 배치하고 → 다시 재서
        // 캐럿 줄이 넘어온 쪽 가장자리에 정확히 붙을 때까지 맞춘다 (보통 한 번, 추정이 틀렸으면 두 번)
        var edge = 0   // -1: 위 가장자리로 넘어왔다, 1: 아래
        for pass in 0..<3 {
            guard let line = caretRect(at: head) else { return pass > 0 }   // 거대 문단
            let top = clip.bounds.minY
            if pass == 0 {
                edge = line.minY < top - 0.25 ? -1 : (line.maxY > top + height + 0.25 ? 1 : 0)
                if edge == 0 { return true }   // 이미 다 보인다
            }
            var y = edge < 0 ? line.minY : line.maxY - height
            if edge < 0, line.minY <= textContainerOrigin.y + 0.5 { y = 0 }   // 첫 줄이면 위 여백까지
            if edge > 0, line.maxY >= bounds.height - textContainerInset.height - 4 { y = bounds.height - height }   // 마지막 줄이면 아래 여백까지
            if pass == 0, abs(y - top) > height { return false }   // 한 화면 넘게 떨어진 곳(휠로 멀리 보던 중의 방향키)은 AppKit 이 데려간다
            let legal = clip.constrainBoundsRect(NSRect(x: clip.bounds.minX, y: y, width: clip.bounds.width, height: height))
            guard abs(legal.minY - top) > 0.25 else { break }
            clip.scroll(to: legal.origin)
            sv.reflectScrolledClipView(clip)
            lm.textViewportLayoutController.layoutViewport()
        }
        return true
    }

    // MARK: - 배치 패스가 화면의 글을 옮기지 않게 (스크롤 닻)
    // TextKit 2 의 레이아웃 관리자는 배치한 조각을 2,000개까지만 붙들고(비공개 `maximumNumberOfCachedTextLayoutFragments`), 넘으면 뷰포트 배치
    // (`-[NSTextViewportLayoutController layoutViewport]` → `flushTextLayoutFragmentsFromLocation:direction:`) 때 뷰포트 밖의 조각을 전부 버린다.
    // 버려진 문단의 높이는 추정값으로 돌아가는데 그 추정이 실제와 크게 다르다(macOS 27 실측: Fira Code 에서는 글자 폭을 실제의 두 배로 어림해, 한 줄에 82자가
    // 들어가는데도 42자 넘는 문단을 두 줄로 본다 — 1.3 MB 메모의 문서 높이를 실제 70만 pt 대신 110만 pt 로 본다). 그런데 NSTextView 는 스크롤 위치를 맞추지 않는다:
    //   · 한 문서에서 2,000 문단쯤 훑으면(휠·Page Down 으로 100 화면) 그 걸음에 화면이 수백 줄 떨어진 곳으로 튄다 (실측: 300 pt 휠 161 걸음째에 맨 윗줄 1772 → 1129).
    //   · 조각 표는 문단 요소를 약한 참조로 든 NSMapTable 이라, 문단이 통째로 사라지면(탭 전환·파일 다시 읽기의 전체 교체, 글꼴·테마의 전체 속성 적용) 죽은 항목이
    //     항목 수에 남는다. 죽은 항목이 2,000 을 넘기면 **모든** 배치 패스가 조각을 버린다 — 화면 위로 지나간 줄이 걸음마다 추정 높이로 돌아가 휠 75 pt 에 화면이
    //     51 / 27 / 0.3 pt 만 움직이거나 거꾸로 간다. 앱을 다시 띄울 때까지 어느 문서에서나 그렇다 (실사용 하네스 scroll-jump-end → scroll-edit-then-scroll, 2026-11-24).
    // 조각이 버려진 패스에서는 화면이 멀쩡하고, 좌표는 그 뒤에(다음 질의·다음 패스에서) 옮겨진다 — 그래서 한 패스의 앞뒤가 아니라 패스와 패스 사이를 본다:
    // (1) 배치 패스가 끝날 때마다 뷰포트의 맨 위·맨 아래 조각의 자리를 적어 두고, 다음 패스가 끝났을 때 그 조각이 (그 사이의 스크롤만큼을 빼고) 화면에서 움직였으면
    // 그만큼 스크롤 위치를 옮겨 다시 배치한다 — 편집도, 보이게 스크롤도 없었던 패스는 화면의 글을 옮길 이유가 없다. (2) 죽은 항목 때문에 버리기가 패스마다
    // 되풀이되지 않게 상한을 "지금 항목 수 + 2,000" 으로 다시 잡는다. 비공개 값이라 없으면 건너뛴다 — 그러면 (1)이 2,000 문단째의 튐은 막지만, 죽은 항목이
    // 상한을 넘긴 상태는 남는다((1)만으로는 못 푼다: 걸음마다 버려지면 AppKit 이 스크롤 위치를 엉뚱하게 당긴다 — 실측 75 pt 휠 6걸음에 5번 어긋남).

    private struct LayoutMark { let location: NSTextLocation; let minY: CGFloat; let maxY: CGFloat }
    /// 배치 패스가 끝났을 때 화면에 놓인 글의 자리
    private struct LayoutRecord {
        let marks: [LayoutMark]             // 뷰포트의 맨 아래·맨 위 조각
        let neighbors: [NSTextLocation]     // 뷰포트 바로 밖의, 배치가 살아 있는 조각 — 배치를 잃으면 조각이 버려진 것이다
        let containerWidth: CGFloat
    }
    private struct LayoutAnchor {
        let record: LayoutRecord
        let onScreen: LayoutMark?           // 이번 패스 뒤에도 화면에 있어야 할 조각 (사용자가 보고 있던 글)
        let disturbed: Bool                 // 앞선 패스 뒤로 조각이 버려졌거나 자리가 옮겨졌다
        let clipY: CGFloat
    }
    private var layoutRecord: LayoutRecord?
    /// 다음 배치 패스는 글이 움직이는 것이 정상이다 (저장소 편집, 보이게 스크롤)
    private var layoutAnchorBlocked = false
    private var layoutAnchorUnblockScheduled = false

    /// `dropRecord`: 적어 둔 자리도 버린다 (편집은 조각의 자리를 옮긴다 — 보이게 스크롤은 옮기지 않는다)
    private func blockLayoutAnchor(dropRecord: Bool) {
        layoutAnchorBlocked = true
        if dropRecord { layoutRecord = nil }
        // 배치 패스가 뒤따르지 않으면(이미 보이는 자리, 화면 밖의 속성 편집) 다음 턴에 푼다 — 안 그러면 한참 뒤의 스크롤 패스가 보정 없이 지나간다
        guard !layoutAnchorUnblockScheduled else { return }
        layoutAnchorUnblockScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.layoutAnchorUnblockScheduled = false
            if !self.needsLayout { self.layoutAnchorBlocked = false }
        }
    }

    /// 그 위치에서 시작하는 조각의 틀. `forcing` 이 아니면 읽기만 하고(배치를 강제하지 않는다) 배치가 살아 있지 않으면 nil
    private func fragmentFrame(at location: NSTextLocation, in lm: NSTextLayoutManager, forcing: Bool = false) -> CGRect? {
        var frame: CGRect?
        lm.enumerateTextLayoutFragments(from: location, options: forcing ? [.ensuresLayout] : []) { f in
            if f.state == .layoutAvailable, f.rangeInElement.location.compare(location) == .orderedSame { frame = f.layoutFragmentFrame }
            return false
        }
        return frame
    }

    /// 지금 뷰포트에 놓인 글의 자리를 적는다 (읽기만 한다)
    private func makeLayoutRecord() -> LayoutRecord? {
        guard let lm = textLayoutManager, let vr = lm.textViewportLayoutController.viewportRange, !vr.isEmpty else { return nil }
        var marks: [LayoutMark] = [], neighbors: [NSTextLocation] = []
        func mark(_ f: NSTextLayoutFragment) {
            guard f.state == .layoutAvailable else { return }
            let fr = f.layoutFragmentFrame
            marks.append(LayoutMark(location: f.rangeInElement.location, minY: fr.minY, maxY: fr.maxY))
        }
        lm.enumerateTextLayoutFragments(from: vr.endLocation, options: [.reverse]) { f in mark(f); return false }
        lm.enumerateTextLayoutFragments(from: vr.location, options: []) { f in mark(f); return false }
        guard !marks.isEmpty else { return nil }
        lm.enumerateTextLayoutFragments(from: vr.location, options: [.reverse]) { f in if f.state == .layoutAvailable { neighbors.append(f.rangeInElement.location) }; return false }
        lm.enumerateTextLayoutFragments(from: vr.endLocation, options: []) { f in if f.state == .layoutAvailable { neighbors.append(f.rangeInElement.location) }; return false }
        return LayoutRecord(marks: marks, neighbors: neighbors, containerWidth: textContainer?.size.width ?? 0)
    }

    /// 배치 패스 앞에서: 앞선 패스가 놓은 글 가운데 이번 패스 뒤에도 화면에 있어야 할 조각을 고른다 (스크롤로 옮겨진 클립 원점 기준)
    private func captureLayoutAnchor() -> LayoutAnchor? {
        guard !layoutAnchorBlocked, let record = layoutRecord, let sv = enclosingScrollView, sv.documentView === self, let lm = textLayoutManager,
              (textContainer?.size.width ?? 0) == record.containerWidth else { return nil }
        let clip = sv.contentView
        let legal = clip.constrainBoundsRect(clip.bounds)
        guard abs(legal.minY - clip.bounds.minY) < 0.5 else { return nil }   // 끝을 넘겨 당기는 중(탄성 스크롤)에는 손대지 않는다
        let originY = textContainerOrigin.y
        let visible = visibleRect
        var disturbed = record.neighbors.contains { fragmentFrame(at: $0, in: lm) == nil }
        var onScreen: LayoutMark?
        for m in record.marks {
            if let now = fragmentFrame(at: m.location, in: lm) { if abs(now.minY - m.minY) > 0.5 { disturbed = true } } else { disturbed = true }
            if onScreen == nil, m.maxY + originY > visible.minY + 1, m.minY + originY < visible.maxY - 1 { onScreen = m }
        }
        return LayoutAnchor(record: record, onScreen: onScreen, disturbed: disturbed, clipY: clip.bounds.minY)
    }

    /// 배치 패스 뒤에서: 닻 조각이 화면에서 움직였으면 그만큼 스크롤 위치를 옮기고 다시 배치한다. 반환: 옮겼는가
    private func restoreLayoutAnchor(_ anchor: LayoutAnchor?) -> Bool {
        guard let anchor, !layoutAnchorBlocked, let sv = enclosingScrollView, let lm = textLayoutManager,
              (textContainer?.size.width ?? 0) == anchor.record.containerWidth else { return false }
        // 화면에 남아 있어야 할 조각이 있으면 그것으로 잰다. 없으면(한 화면 넘는 걸음) 조각이 버려졌거나 자리가 옮겨진 때에만 바로잡는다 —
        // 멀쩡한 패스의 큰 걸음은 AppKit 이 추정 좌표로 자리를 잡는 대로 둔다
        var mark = anchor.onScreen
        if mark == nil, anchor.disturbed || (anchor.record.marks.map(\.location) + anchor.record.neighbors).contains(where: { fragmentFrame(at: $0, in: lm) == nil }) {
            mark = anchor.record.marks.first
        }
        guard let mark else { return false }
        let clip = sv.contentView
        let wanted = mark.minY - anchor.clipY   // 닻 조각이 있어야 할 화면 높이 (클립 원점으로부터)
        var moved = false
        for _ in 0..<4 {
            // 조각이 버려졌으면(배치를 잃었다) 그 문단만 배치해 지금 좌표에서의 자리를 얻는다
            guard let frame = fragmentFrame(at: mark.location, in: lm) ?? fragmentFrame(at: mark.location, in: lm, forcing: true) else { break }
            let drift = (frame.minY - clip.bounds.minY) - wanted
            guard abs(drift) > 0.5 else { break }
            let legal = clip.constrainBoundsRect(NSRect(x: clip.bounds.minX, y: clip.bounds.minY + drift, width: clip.bounds.width, height: clip.bounds.height))
            guard abs(legal.minY - clip.bounds.minY) > 0.5 else { break }
            if Perf.enabled { Perf.log("HyperTextView.layout: the text moved by \(drift) pt on screen without a scroll or an edit — scrolling by that much and laying out again") }
            clip.scroll(to: legal.origin)
            sv.reflectScrolledClipView(clip)
            moved = true
            super.layout()
        }
        return moved
    }

    // MARK: 조각 캐시 상한 (TextKit 2 비공개 값 — 위 '스크롤 닻'의 (2))
    nonisolated(unsafe) private static let fragmentTableIvar = class_getInstanceVariable(NSTextLayoutManager.self, "_textLayoutFragmentTable")
    private static let fragmentLimitKey = "maximumNumberOfCachedTextLayoutFragments"
    private static let fragmentLimitAdjustable: Bool = fragmentTableIvar != nil
        && NSTextLayoutManager.instancesRespond(to: NSSelectorFromString("maximumNumberOfCachedTextLayoutFragments"))
        && NSTextLayoutManager.instancesRespond(to: NSSelectorFromString("setMaximumNumberOfCachedTextLayoutFragments:"))
    /// 죽은 항목이 없을 때 붙들어 둘 조각 수 — TextKit 2 의 기본값과 같다 (많이 붙들수록 그 위쪽에서의 입력이 느려진다: 실측 조각당 약 5 µs/키)
    private static let fragmentCacheHeadroom = 2_000

    /// 실사용 하네스: 끄면 상한을 건드리지 않는다 — 비공개 값이 없는 OS 에서처럼 '스크롤 닻'만으로 화면이 맞는지 본다
    nonisolated(unsafe) static var adjustsFragmentCacheLimit = true
    /// 앞선 배치 패스가 끝났을 때의 항목 수
    private var fragmentCountAfterLayout: Int?

    /// 조각 표의 항목 수(죽은 항목 포함)와 지금의 상한. 비공개 값을 읽을 수 없으면 nil
    private func fragmentCacheState() -> (count: Int, limit: Int)? {
        guard Self.fragmentLimitAdjustable, Self.adjustsFragmentCacheLimit, let lm = textLayoutManager, let iv = Self.fragmentTableIvar,
              let table = object_getIvar(lm, iv) as? NSMapTable<AnyObject, AnyObject>,
              let limit = lm.value(forKey: Self.fragmentLimitKey) as? Int else { return nil }
        return (table.count, limit)
    }

    /// 배치 패스 앞에서: 패스 사이에 항목이 뭉텅이로 줄었으면(죽은 항목이 표의 재해시로 걷혔거나, 큰 편집이 조각을 무효화했다) 상한도 그만큼 내린다 —
    /// 올려 둔 상한이 그대로 남아 살아 있는 조각을 2,000개 넘게 붙들지 않게. 기본값 아래로는 내리지 않고, 입력 한 번에 한두 개씩 줄었다 다시 느는 것은 세지 않는다
    /// (셌다면 입력하는 동안 상한이 조금씩 내려가 편집 패스에서 조각이 버려진다 — 편집 패스는 닻으로 바로잡지 않는다)
    private func trimFragmentCacheLimit(_ now: (count: Int, limit: Int)) {
        guard let last = fragmentCountAfterLayout, last - now.count >= 256, now.limit > Self.fragmentCacheHeadroom, let lm = textLayoutManager else { return }
        lm.setValue(max(Self.fragmentCacheHeadroom, now.limit - (last - now.count)), forKey: Self.fragmentLimitKey)
    }

    /// 조각을 버린 패스 뒤에 부른다: 버리고도 남은 항목(뷰포트의 조각 + 죽은 항목) 위로 2,000개를 더 붙들 수 있게 상한을 다시 잡는다
    private func retuneFragmentCacheLimit() {
        guard let now = fragmentCacheState(), let lm = textLayoutManager else { return }
        let limit = now.count + Self.fragmentCacheHeadroom
        guard limit != now.limit else { return }
        if Perf.enabled { Perf.log("HyperTextView.layout: fragment table holds \(now.count) entries after a flush — cache limit \(now.limit) → \(limit)") }
        lm.setValue(limit, forKey: Self.fragmentLimitKey)
    }

    /// 보이는 글이 있는데 뷰포트 컨트롤러의 배치 범위가 비어 있는가 (scrollRangeToVisible 주석의 '옮겨 놓기만 한' 상태)
    private var viewportNeedsLayout: Bool {
        guard let lm = textLayoutManager, (textStorage?.length ?? 0) > 0, !visibleRect.isEmpty else { return false }
        return lm.textViewportLayoutController.viewportRange?.isEmpty ?? true
    }

    // MARK: - 그리기

    override func drawBackground(in rect: NSRect) {
        Perf.measure("HyperTextView.drawBackground", threshold: 2) {
            super.drawBackground(in: rect)
            guardingViewport {
                drawCurrentLineHighlight()
                if Self.trackBandForRealUse { trackBandDraw() }
                drawMatchHighlights(in: rect)   // search: 현재 줄 띠 위, 글자 아래
                drawCarets()      // appearance: Block·Underline 머리 캐럿 + 보조 캐럿 (글자 아래 레이어)
                drawFoldPills()   // fold
            }
        }
    }

    // MARK: 뷰포트 지킴이
    // 그리는 동안의 레이아웃 질의(거터의 조각 열거, 접기 표식·캐럿 사각형)가 뷰포트 위쪽의 아직 배치되지 않은 문단을 배치하면 TextKit 2 는 그 아래 조각들의 프레임을
    // 통째로 옮긴다. 그런데 이미 화면에 올린 조각 뷰는 다시 놓지 않는다(macOS 27 실측: 모두 접기 뒤 뷰포트 조각 20개가 +8.8 pt, 조각 뷰는 제자리) — 글자는 옛 자리에
    // 보이고 줄 번호·접기 표식·클릭 위치는 새 자리를 따라 어긋난 채로 다음 스크롤까지 남는다. 질의 앞뒤로 뷰포트 마지막 조각의 y 를 견줘 움직였으면 다음 턴에
    // needsLayout 을 건다 — NSTextView.layout() 이 뷰포트를 다시 배치해 조각 뷰를 새 프레임에 놓는다(실측). 평소에는 조각 하나를 두 번 읽는 비용뿐이다.
    private var viewportRelayoutScheduled = false
    private var viewportRelayoutBurst = 0   // 연달아 다시 배치한 횟수 (질의가 매번 프레임을 옮기는 경우에도 끝없이 돌지 않게)

    /// 뷰포트에 배치된 마지막 조각의 (위치, y). 그 앞 어디서든 프레임이 바뀌면 이 값이 움직인다. 읽기만 한다 (배치를 강제하지 않는다)
    private func viewportTail() -> (location: NSTextLocation, y: CGFloat)? {
        guard let lm = textLayoutManager, let vr = lm.textViewportLayoutController.viewportRange, !vr.isEmpty else { return nil }
        var out: (location: NSTextLocation, y: CGFloat)?
        lm.enumerateTextLayoutFragments(from: vr.endLocation, options: [.reverse]) { f in
            out = (f.rangeInElement.location, f.layoutFragmentFrame.minY)
            return false
        }
        return out
    }

    /// `body` 의 레이아웃 질의가 뷰포트 조각의 자리를 옮겼으면 뷰포트를 다시 배치하게 한다. `onShift` 는 그 뒤 다시 그릴 것이 있는 쪽(거터)이 준다
    func guardingViewport(onShift: (() -> Void)? = nil, _ body: () -> Void) {
        let before = viewportTail()
        body()
        guard let b = before, !viewportRelayoutScheduled, viewportRelayoutBurst < 4,
              let a = viewportTail(), a.location.compare(b.location) == .orderedSame, abs(a.y - b.y) > 0.5 else { return }
        Perf.log("viewport guard: a draw-time layout query moved the viewport fragments by \(a.y - b.y) pt — laying the viewport out again")
        viewportRelayoutScheduled = true
        viewportRelayoutBurst += 1
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.viewportRelayoutScheduled = false
            self.needsLayout = true
            self.needsDisplay = true
            onShift?()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.viewportRelayoutBurst = 0 }
        }
    }

    private func drawCurrentLineHighlight() {
        let band = currentLineBandRect()
        // 그리는 지금(배치가 끝난 뒤)의 띠 자리가 장부와 다르면, 이번에 다시 칠해지는 구역에 새 자리가 안 들어 있거나 옛 자리가 안 지워질 수 있다 → 다음 턴에 맞춘다
        if !Self.sameRow(band, lineBandRect), !lineBandFixScheduled {
            lineBandFixScheduled = true
            DispatchQueue.main.async { [weak self] in self?.lineBandFixScheduled = false; self?.invalidateCurrentLineBand() }
        }
        guard let band, let color = currentLineColor else { return }
        color.setFill()
        band.fill()
    }

    // 현재 줄 띠의 자리 장부. 띠는 이 뷰의 배경에 칠하므로(글자는 조각 뷰가 따로 그린다) 캐럿이 옮겨 가면 옛 자리와 새 자리를 직접 다시 그리게 해야 한다.
    // 선택이 바뀌는 순간의 캐럿 사각형만 믿으면 안 된다 — 여러 문단이 바뀐 편집(되돌리기·줄 도구·날짜 삽입·여러 줄 붙여넣기) 직후 TextKit 2 는 아직 배치하지 않은
    // 문단 아래의 조각 위치를 틀리게 답한다(실측: 줄 삭제를 되돌린 직후 7줄 어긋남). 그 값을 옛 자리로 적어 두면 다음에 캐럿이 옮겨 갈 때 엉뚱한 줄을 지워
    // 옛 띠가 화면에 남는다(띠가 두 줄). 그래서 띠가 화면에 있다고 보는 자리를 여기 적어 두고, 그릴 때마다 실제 자리와 견줘 어긋났으면 다시 맞춘다.
    private var lineBandRect: NSRect?
    private var lineBandFixScheduled = false

    private static func sameRow(_ a: NSRect?, _ b: NSRect?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.minY - b.minY) < 0.5 && abs(a.height - b.height) < 0.5 && abs(a.width - b.width) < 0.5
    }

    /// 지금 현재 줄 띠가 있어야 할 자리 (멀티 캐럿·선택이 있으면 없음, 거대 문단은 캐럿 사각형을 구하지 않으므로 없음)
    private func currentLineBandRect() -> NSRect? {
        guard multi == nil, currentLineColor != nil, selectedRange().length == 0, let r = caretRect(at: selectedRange().location) else { return nil }
        return NSRect(x: 0, y: r.minY, width: bounds.width, height: r.height)
    }

    /// 띠의 자리가 장부와 다르면 옛 자리와 새 자리를 다시 그리게 하고 장부를 고친다 (선택이 바뀔 때, 그리다가 어긋남을 발견했을 때)
    private func invalidateCurrentLineBand() {
        let want = currentLineBandRect()
        guard !Self.sameRow(want, lineBandRect) else { return }
        if let old = lineBandRect { setNeedsDisplay(old.insetBy(dx: 0, dy: -2)) }
        if let new = want { setNeedsDisplay(new.insetBy(dx: 0, dy: -2)) }
        lineBandRect = want
    }

    // 실사용 하네스(--realuse): 현재 줄 띠가 **화면의 뒷저장소** 어느 높이에 칠해져 있는지를 흉내 낸다. 하네스의 스냅샷은 cacheDisplay 로 새로 그린 그림이라
    // 다시 그리기가 빠져 화면에 남은 낡은 띠(또는 안 칠해진 띠)를 보여 주지 못한다. 실제 그리기마다 "다시 칠해진 구역의 띠를 지우고, 지금 띠와 겹치는 만큼 더한다"
    // 를 따라가면 뒷저장소의 띠 자리가 된다 (왼쪽 여백 x = 3 pt 열 기준, 텍스트 뷰 좌표의 y 구간). 화면 밖 비트맵으로 그리는 중(cacheDisplay)은 세지 않는다
    nonisolated(unsafe) static var trackBandForRealUse = false
    private(set) var debugBandOnScreen: [ClosedRange<CGFloat>] = []
    /// 호출 경로(되돌아갈 주소들)별로 "cacheDisplay 안인가" 를 한 번만 기호로 풀어 적어 둔다 — callStackSymbols 는 한 번에 수 ms 라 그리기마다 부르면
    /// 큰 문서의 줄바꿈 전환처럼 그리기가 몰릴 때 하네스가 스스로 수 초의 정지를 만든다
    nonisolated(unsafe) private static var offscreenDrawPaths: [Int: Bool] = [:]
    private static func drawingOffscreen() -> Bool {
        var hasher = Hasher()
        for a in Thread.callStackReturnAddresses.prefix(48) { hasher.combine(a) }
        let key = hasher.finalize()
        if let known = offscreenDrawPaths[key] { return known }
        let offscreen = Thread.callStackSymbols.contains { $0.contains("cacheDisplayInRect") }
        offscreenDrawPaths[key] = offscreen
        return offscreen
    }

    private func trackBandDraw() {
        if Self.drawingOffscreen() { return }
        var rects: UnsafePointer<NSRect>?
        var count = 0
        getRectsBeingDrawn(&rects, count: &count)
        let band = currentLineBandRect().map { $0.minY...$0.maxY }
        var painted = debugBandOnScreen
        for i in 0..<count {
            guard let d = rects?[i], d.minX <= 3, d.maxX > 3, d.height > 0 else { continue }
            var next: [ClosedRange<CGFloat>] = []
            for p in painted {   // 다시 칠해진 구역은 배경으로 돌아간다
                if p.upperBound <= d.minY || p.lowerBound >= d.maxY { next.append(p); continue }
                if p.lowerBound < d.minY { next.append(p.lowerBound...d.minY) }
                if p.upperBound > d.maxY { next.append(d.maxY...p.upperBound) }
            }
            if let b = band, b.upperBound > d.minY, b.lowerBound < d.maxY { next.append(max(b.lowerBound, d.minY)...min(b.upperBound, d.maxY)) }
            painted = next
        }
        // 맞닿은 구간은 합친다
        var merged: [ClosedRange<CGFloat>] = []
        for p in painted.sorted(by: { $0.lowerBound < $1.lowerBound }) where p.upperBound - p.lowerBound > 0.25 {
            if let last = merged.last, p.lowerBound <= last.upperBound + 0.25 { merged[merged.count - 1] = last.lowerBound...max(last.upperBound, p.upperBound) } else { merged.append(p) }
        }
        debugBandOnScreen = merged
    }

    /// 보이는 매치만 칠한다. 범위는 뷰포트 레이아웃 컨트롤러가 실제로 배치한 `viewportRange` 로 한정한다 — 점 질의 폴백으로 문서 전체를 훑으면
    /// 안 보이는 문단의 세그먼트 계산이 레이아웃을 강제해(추정 높이 → 실측) 뷰포트가 다시 튄다. 정렬된 범위를 이진 탐색해 뷰포트 안의 매치만 돈다.
    /// 건너뛰는 것: 선택과 겹치는 매치(선택 색이 보이도록), 비밀 가림막 줄(위치가 드러나지 않도록), 접힌 줄(접힌 프래그먼트의 세그먼트는 접힌 자리에
    /// 유령 띠를 그린다), 거대 문단(세그먼트 계산이 문단 전체 배치 — 그 문단의 매치를 한꺼번에 건너뛴다)
    private func drawMatchHighlights(in rect: NSRect) {
        guard !matchHighlights.isEmpty, let lm = textLayoutManager, let cs = textContentStorage, let ts = textStorage,
              let shown = laidOutCharacterRange() else { return }
        let start = shown.location, end = NSMaxRange(shown)
        guard end > start else { return }
        var lo = 0, hi = matchHighlights.count   // 끝이 start 뒤인 첫 매치
        while lo < hi { let m = (lo + hi) / 2; if NSMaxRange(matchHighlights[m]) <= start { lo = m + 1 } else { hi = m } }
        guard lo < matchHighlights.count else { return }
        let origin = textContainerOrigin
        let length = ts.length
        let ns = ts.string as NSString
        let selected = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        let folds = hasFolds?() == true   // fold
        var para = NSRange(location: NSNotFound, length: 0)   // 직전 매치의 문단 — 같은 문단의 매치는 다시 재지 않는다
        matchHighlightColor.setFill()
        var i = lo
        while i < matchHighlights.count, matchHighlights[i].location < end {
            let r = matchHighlights[i]; i += 1
            guard r.length > 0, NSMaxRange(r) <= length else { continue }
            if !NSLocationInRange(r.location, para) { para = ns.paragraphRange(for: NSRange(location: r.location, length: 0)) }
            if para.length > Self.hugeParagraphLength {
                while i < matchHighlights.count, matchHighlights[i].location < NSMaxRange(para) { i += 1 }
                continue
            }
            if isOffsetMasked?(para.location) == true { continue }           // secrets
            if folds, isOffsetHidden?(para.location) == true { continue }    // fold
            if selected.contains(where: { NSIntersectionRange($0, r).length > 0 }) { continue }
            guard let a = cs.location(cs.documentRange.location, offsetBy: r.location), let b = cs.location(a, offsetBy: r.length),
                  let tr = NSTextRange(location: a, end: b) else { continue }
            lm.enumerateTextSegments(in: tr, type: .highlight, options: [.rangeNotRequired]) { _, f, _, _ in
                var cell = f; cell.origin.x += origin.x; cell.origin.y += origin.y
                if cell.intersects(rect) { cell.fill() }
                return true
            }
        }
    }

    /// 지금 화면에 놓인 문자 범위 (문단 경계). 뷰포트 레이아웃 컨트롤러의 `viewportRange` 를 쓰되, 그 범위가 비어 있으면 보이는 영역의 위·아래 끝에 놓인 문단으로 구한다.
    /// 실측(2026-11-24, macOS 27): 캐럿을 키보드로 옮기면(화살표·Tab 이동 — AppKit 이 scrollRangeToVisible 안에서 뷰포트를 캐럿 줄로 '재배치'만 하고 다시 배치하지
    /// 않는다) `viewportRange` 가 길이 0 인 범위로 바뀌어 다음 스크롤·편집까지 그대로다. 화면은 앞선 배치대로 멀쩡하지만 이 범위만 믿고 그리는 것(검색 매치 강조)은
    /// 화살표 키 한 번에 전부 사라졌다. 폴백의 점 질의는 화면에 있는(이미 배치된) 문단만 건드리므로 뷰포트 밖의 배치를 강제하지 않는다
    func laidOutCharacterRange() -> NSRange? {
        guard let lm = textLayoutManager, let cs = textContentStorage else { return nil }
        if let viewport = lm.textViewportLayoutController.viewportRange, !viewport.isEmpty {
            let start = cs.offset(from: cs.documentRange.location, to: viewport.location)
            return NSRange(location: start, length: cs.offset(from: viewport.location, to: viewport.endLocation))
        }
        let visible = visibleRect
        guard visible.height > 1 else { return nil }
        let originY = textContainerOrigin.y
        guard let first = lm.textLayoutFragment(for: CGPoint(x: 0, y: max(0, visible.minY - originY))) else { return nil }
        let last = lm.textLayoutFragment(for: CGPoint(x: 0, y: max(0, visible.maxY - originY)))
        let start = cs.offset(from: cs.documentRange.location, to: first.rangeInElement.location)
        let end = last.map { cs.offset(from: cs.documentRange.location, to: $0.rangeInElement.endLocation) } ?? (textStorage?.length ?? start)   // 보이는 영역이 문서 끝을 지나면 끝까지
        return end > start ? NSRange(location: start, length: end - start) : nil
    }

    /// 편집 뒤 매치 범위를 옮긴다 (editedRange 는 편집 후 범위, delta 로 편집 전 구간을 되짚는다): 편집 앞은 그대로, 편집 전 구간 뒤는 delta 만큼,
    /// 걸친 것은 지운다 — 지연 재검색이 다시 채운다. 파일 열기·다시 읽기의 전체 교체는 모든 범위를 지운다
    private func shiftMatchHighlights(edited: NSRange, delta: Int) {
        let preEnd = edited.location + max(0, edited.length - delta)
        var out: [NSRange] = []
        out.reserveCapacity(matchHighlights.count)
        var changed = false
        for r in matchHighlights {
            if NSMaxRange(r) <= edited.location { out.append(r) }
            else if r.location >= preEnd { out.append(NSRange(location: r.location + delta, length: r.length)); if delta != 0 { changed = true } }
            else { changed = true }
        }
        if changed { matchHighlights = out }
    }

    /// shouldChangeText 가 준 편집 전 좌표의 편집들(멀티 캐럿이면 여러 개)을 뒤에서부터 적용한다 — 앞 편집의 좌표가 그대로 유효하다.
    /// 저장소 알림의 editedRange 는 didProcessEditing 안에서 한글 폭 보정이 문단 전체에 폰트 속성을 얹으면 문단으로 넓어져 같은 줄의 매치를 지워 버리므로,
    /// 입력은 이 정확한 경로로 옮기고 저장소 알림은 추적되지 않은 편집(undo/redo·프로그램 교체)에만 쓴다
    private func shiftMatchHighlights(preEdits edits: [(NSRange, String)]) {
        for (r, s) in edits.sorted(by: { $0.0.location > $1.0.location }) where r.location != NSNotFound {
            let newLength = (s as NSString).length
            shiftMatchHighlights(edited: NSRange(location: r.location, length: newLength), delta: newLength - r.length)
        }
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
    /// 네이티브 표시기를 우리가 .hidden 으로 숨겼는가 (AppKit 이 숨긴 것과 구분 — 되돌리기는 우리 것만)
    private var indicatorHiddenByUs = false
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
        let native: NSTextInsertionIndicator.DisplayMode = cursorBlinks ? .automatic : .visible
        // AppKit 도 displayMode 를 바꾼다(숨길 때 .hidden, 다시 보일 때 .automatic). AppKit 이 숨긴 상태와 싸우면 KVO 가 턴마다 핑퐁하며 런루프를 점유한다
        // (실측: 타이핑 2 → 20 ms, 큰 편집 4배). 그래서 "우리가 숨겼다" 는 플래그로만 되돌린다.
        // 우리가 숨긴 것을 되돌릴 때 캐럿이 보여야 할 상황이 아니면(비활성 창·선택 있음) .visible 을 강요하지 않고 .automatic 으로 AppKit 에 맡긴다
        let restore: NSTextInsertionIndicator.DisplayMode = headCaretVisible ? native : .automatic
        switch cursorStyle {
        case .bar:
            if indicatorHiddenByUs {
                if ind.displayMode != restore { ind.displayMode = restore }
                indicatorHiddenByUs = false
            } else if !ind.isHidden, ind.displayMode != native {
                ind.displayMode = native
            }
        case .block, .underline:
            if isInHugeParagraph(selectedRange().location) {
                // 2만 자 넘는 문단에서는 caretRect 를 구하지 않아 블록/밑줄 캐럿을 그릴 수 없다 → 시스템 막대 캐럿으로 대신한다 (QA: 캐럿이 아예 사라졌었다)
                if indicatorHiddenByUs { if ind.displayMode != restore { ind.displayMode = restore }; indicatorHiddenByUs = false }
            } else {
                if ind.displayMode != .hidden { ind.displayMode = .hidden }
                indicatorHiddenByUs = true
            }
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

    /// 캐럿(선택의 시작)이 지금 보이는 영역에 걸쳐 있는가
    var isCaretVisible: Bool {
        guard let caret = caretRect(at: selectedRange().location) else { return false }
        let visible = visibleRect
        return caret.maxY > visible.minY && caret.minY < visible.maxY
    }

    /// 배치가 통째로 바뀌는 일 뒤에 캐럿을 다시 보이게 한다 — 되돌리기로 큰 범위가 돌아왔을 때(추정 위치로 스크롤돼 1.3 MB 를 되살리면 캐럿이 화면 아래로 한 줄 반
    /// 벗어났다), 거터 폭이 바뀌어 본문이 다시 감길 때(GutterView.updateThickness). 그 배치를 끝낸 다음 턴에 캐럿이 정말 보이는지 보고, 아니면 그리로 스크롤한다
    func revealCaretAfterRelayout() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            for _ in 0..<2 {   // 스크롤한 자리의 추정 높이가 실측으로 바뀌며 한 번 더 어긋날 수 있다
                window.layoutIfNeeded()
                let sel = self.selectedRange()
                guard let caret = self.caretRect(at: sel.location) else { return }
                let visible = self.visibleRect
                guard caret.minY < visible.minY || caret.maxY > visible.maxY else { return }
                self.scrollRangeToVisible(sel)
            }
        }
    }

    // MARK: - 뷰포트 레이아웃 보정
    // TextKit 2 는 아직 배치하지 않은 문단의 높이를 추정한다. 편집으로 넓은 범위의 배치가 무효가 된 뒤의 배치 패스는 뷰포트를 채우는 동안 위쪽 문단의 추정 높이가
    // 실측으로 바뀌어 방금 놓은 조각들이 통째로 밀리고, 보이는 영역의 아래(또는 위)가 빈 채로 끝날 수 있다 — 다시 배치할 일이 생기지 않으므로 다음 스크롤·편집까지
    // 그 줄들은 번호만 있고 글자가 없다 (실측 2026-11-24: 문서 끝의 선택 위에 300줄을 붙여넣은 다음 턴에 구문 색 재검증이 붙여넣은 범위 전체를 무효화하자
    // 조각이 177 pt 위로 밀려 마지막 다섯 줄이 비었다 — 그 무효화는 EditorView.flushParagraphRevalidation 이 화면 범위로 줄였다). 편집 뒤의 배치가 끝났는데
    // 조각들이 보이는 영역을 덮지 못하면 바로 다시 배치한다 (최대 두 번). 실측은 두 가지뿐이다: 위의 붙여넣기는 한 번에 수렴했고, 문서 전체가 무효화된 경우
    // (모두 선택 뒤 입력의 되돌리기 — 재검증 범위를 줄이기 전)는 두 번으로도 수렴하지 않았다. 그러니 이것은 안전망이지 보장이 아니다.
    // 스크롤만으로 도는 배치 패스는 건드리지 않는다
    private var checkViewportAfterEdit = false

    /// `layout()` 의 끝에서 부른다 (위의 '뷰포트 레이아웃 보정'). 편집 뒤의 패스와, 패스 안에서 스크롤 위치가 옮겨진 패스에서 본다
    private func coverViewportAfterEdit() {
        guard checkViewportAfterEdit else { return }
        checkViewportAfterEdit = false
        var passes = 0
        while passes < 2, !viewportCoversVisibleRect() {
            passes += 1
            textLayoutManager?.textViewportLayoutController.layoutViewport()
        }
        if passes > 0, Perf.enabled { Perf.log("HyperTextView.layout: viewport did not cover the visible rect after an edit → \(passes) extra pass(es)") }
    }

    /// 뷰포트 레이아웃이 놓은 조각들이 보이는 영역의 위·아래 끝까지 닿는가 (문서의 처음·끝이면 닿지 않아도 된다). 조각 두 개만 본다
    private func viewportCoversVisibleRect() -> Bool {
        guard window != nil, let lm = textLayoutManager, let range = lm.textViewportLayoutController.viewportRange else { return true }
        let visible = visibleRect
        guard visible.height > 1 else { return true }
        let originY = textContainerOrigin.y
        var top: CGFloat?, bottom: CGFloat?
        lm.enumerateTextLayoutFragments(from: range.location, options: []) { f in top = f.layoutFragmentFrame.minY + originY; return false }
        lm.enumerateTextLayoutFragments(from: range.endLocation, options: [.reverse]) { f in bottom = f.layoutFragmentFrame.maxY + originY; return false }
        guard let top, let bottom else { return true }
        let document = lm.documentRange
        if top > visible.minY + 1, range.location.compare(document.location) == .orderedDescending { return false }
        if bottom < visible.maxY - 1, range.endLocation.compare(document.endLocation) == .orderedAscending { return false }
        return true
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

    // MARK: - 보던 곳 유지 (문서 전체의 레이아웃이 바뀌는 변화의 전후)
    // 줄바꿈 폭(창 크기·사이드바·분할·줄 번호·미리보기)·글자 크기·테마(전체 속성 재적용)·줄바꿈 켬/끔은 문서 전체의 레이아웃을 무효화한다. TextKit 2 는 아직
    // 배치하지 않은 문단의 높이를 추정하므로 스크롤 좌표를 그대로 두면 전혀 다른 줄이 보인다 (실측: 1.3 MB 메모 가운데에서 ⌘= 한 번에 1,000 줄, 줄바꿈을
    // 끄면 9,500 줄 떨어진 곳 또는 빈 화면). 바꾸기 전에 뷰포트 맨 위 줄의 첫 글자를 잡아 두고, 바꾼 뒤 그 글자가 든 줄을 같은 높이에 되돌린다.

    /// 뷰포트 맨 위에 걸친 줄의 첫 글자(`offset`)와, 그 줄 상자의 위 가장자리가 뷰포트 위 가장자리보다 얼마나 위에 있었는가(`delta`, 줄 높이 `lineHeight` 기준)
    /// `fraction`: 그 줄이 문서 높이의 어디쯤이었는가(0…1) — 되돌릴 때의 첫 어림. 모르면 nil(글자 오프셋의 비율로 어림한다)
    struct ReadingAnchor { var offset: Int; var delta: CGFloat; var lineHeight: CGFloat; var pinnedToEnd: Bool; var fraction: CGFloat? = nil }

    /// 0 보다 크면 폭 변화에 따른 자동 유지(setFrameSize)를 쉰다 — 바깥에서 이미 닻을 잡고 있다
    private var readingAnchorDepth = 0

    /// 텍스트 뷰가 지금 배치해 그려 둔 조각들(뷰포트 범위) 가운데 `y`(텍스트 뷰 좌표) 아래로 처음 걸치는 것, 그리고 그 범위의 문서 오프셋과 위·아래 끝.
    /// 점 질의(`textLayoutFragment(for: CGPoint)`)는 쓰지 않는다 — 전체 무효화나 먼 점프 직후에는 그 질의가 뷰포트 바로 위 문단을 새로 배치하며(추정 높이 →
    /// 실측) 뷰포트 조각의 프레임을 통째로 옮겨(실측 −34…+10 pt), 그려진 화면과 다른 좌표를 돌려준다. 뷰포트 범위의 조각은 화면에 그려진 것 그대로다
    private func laidOutViewport(firstBelow y: CGFloat) -> (fragment: NSTextLayoutFragment?, start: Int, end: Int, top: CGFloat, bottom: CGFloat)? {
        guard let lm = textLayoutManager, let cs = textContentStorage, let vr = lm.textViewportLayoutController.viewportRange else { return nil }
        let originY = textContainerOrigin.y
        var found: NSTextLayoutFragment?
        var top = CGFloat.greatestFiniteMagnitude, bottom = -CGFloat.greatestFiniteMagnitude
        lm.enumerateTextLayoutFragments(from: vr.location, options: []) { f in
            if f.rangeInElement.location.compare(vr.endLocation) != .orderedAscending { return false }
            let fr = f.layoutFragmentFrame
            guard fr.height > 0 else { return true }   // 접힌 문단
            top = min(top, fr.minY + originY); bottom = max(bottom, fr.maxY + originY)
            if found == nil, fr.maxY + originY > y + 0.5 { found = f }
            return true
        }
        guard bottom > top else { return nil }
        return (found, cs.offset(from: cs.documentRange.location, to: vr.location), cs.offset(from: cs.documentRange.location, to: vr.endLocation), top, bottom)
    }

    /// 그려 둔 뷰포트가 보이는 영역을 덮고 있는 보통의 경우(자동 줄바꿈)에만 그것을 돌려준다. 그렇지 않을 때 — 줄바꿈을 끈 문서(긴 줄이 섞이면 TextKit 이
    /// 스크롤하다 엉뚱한 곳을 배치해 화면이 빈다 — 이 변경 전에도 같았다, 실측), 화면 일부가 비어 있을 때, 클립 뷰가 문서 끝 너머를 비출 때, 편집 직후 범위가
    /// 끊겨 있을 때 — 는 nil: 그려 둔 범위를 믿을 수 없으니 부르는 쪽이 예전 경로(점 질의)를 그대로 쓴다
    private func coveringViewport() -> (fragment: NSTextLayoutFragment, start: Int, end: Int)? {
        guard textContainer?.widthTracksTextView == true, let clip = enclosingScrollView?.contentView, let length = textStorage?.length,
              let v = laidOutViewport(firstBelow: clip.bounds.minY), let frag = v.fragment else { return nil }
        let covers = (v.top <= clip.bounds.minY + 1 || v.start == 0) && (v.bottom >= clip.bounds.maxY - 1 || v.end >= length) && clip.bounds.maxY <= frame.height + 1
        return covers ? (frag, v.start, v.end) : nil
    }

    /// 그려 둔 뷰포트의 범위 (보이는 영역을 덮고 있을 때만 — coveringViewport). 거터가 번호를 붙일 조각을 여기서 얻는다
    func coveringViewportRange() -> NSTextRange? {
        guard coveringViewport() != nil else { return nil }
        return textLayoutManager?.textViewportLayoutController.viewportRange
    }

    /// 그려 둔 범위의 문서 오프셋 (coveringViewport 가 아니면 nil) — 레이아웃을 건드리지 않고 답한다
    func laidOutViewportRange() -> NSRange? {
        coveringViewport().map { NSRange(location: $0.start, length: max(0, $0.end - $0.start)) }
    }

    /// 화면 맨 위에 걸쳐 보이는 문단의 시작 오프셋 — 레이아웃을 건드리지 않고, 그려 둔 뷰포트에서 답한다 (자동 줄바꿈일 때만; 아니면 nil).
    /// 스크롤 알림 안에서 불리므로(텍스트 뷰가 새 위치를 배치하기 전) 뷰포트가 화면 아래쪽을 아직 덮지 못해도 맨 위 문단만 있으면 된다 — 여기서 점 질의를
    /// 하면 스크롤할 때마다 조각 프레임이 옮겨져, 전체 무효화 뒤의 첫 스크롤이 그만큼 튄다 (실측: 휠 90 pt 가 72.6 pt)
    func firstVisibleParagraphOffset() -> Int? {
        guard textContainer?.widthTracksTextView == true, let clip = enclosingScrollView?.contentView, let cs = textContentStorage,
              let frag = laidOutViewport(firstBelow: clip.bounds.minY)?.fragment else { return nil }
        return cs.offset(from: cs.documentRange.location, to: frag.rangeInElement.location)
    }

    /// 화면 맨 위에 걸친 문단의 시작 오프셋과, 그 문단의 위 가장자리가 화면 위 가장자리보다 얼마나 위에 있는가(`inset`) — 레이아웃을 건드리지 않고 그려 둔
    /// 뷰포트에서 답한다. 자동 줄바꿈이 아니거나 그려 둔 조각이 화면 위 가장자리에 닿지 않으면(위쪽이 빈 상태) nil — 부르는 쪽이 점 질의를 쓴다.
    /// 보기 위치 저장(EditorView.topAnchor)이 쓴다: 그 저장은 캐럿이 움직인 0.8초 뒤에 돌므로 테마·글자 크기·폭을 바꾼 직후와 겹치기 쉽고, 그때의 점 질의는
    /// 화면의 글자는 그대로 둔 채 조각 프레임만 옮겨(실측: 1.3 MB 메모에서 −102.7 pt, 여러 번 감기는 문서에서 +16.0 pt) 줄 번호·클릭 위치가 글자와 어긋났다
    func firstVisibleParagraphAnchor() -> (offset: Int, inset: CGFloat)? {
        guard textContainer?.widthTracksTextView == true, let cs = textContentStorage else { return nil }
        let top = visibleRect.minY
        guard let frag = laidOutViewport(firstBelow: top)?.fragment else { return nil }
        let offset = cs.offset(from: cs.documentRange.location, to: frag.rangeInElement.location)
        let inset = top - textContainerOrigin.y - frag.layoutFragmentFrame.minY
        guard inset > -0.5 || offset == 0 else { return nil }   // 문서 맨 위에서는 위쪽 여백 때문에 음수가 정상이다
        return (offset, inset)
    }

    /// 캐럿(선택이 있으면 그 시작, 시작이 안 보이면 끝)이 놓인 줄이 화면에 보이고 있으면 그 글자 오프셋과 줄 상자(텍스트 뷰 좌표). 그려 둔 뷰포트에서만 찾는다 —
    /// 화면 밖의 캐럿을 재면(caretRect) 그 문단이 새로 배치되며 뷰포트 조각의 프레임이 옮겨진다
    private func caretLineOnScreen() -> (offset: Int, top: CGFloat, height: CGFloat)? {
        guard let lm = textLayoutManager, let cs = textContentStorage, let clip = enclosingScrollView?.contentView, let length = textStorage?.length,
              let vr = lm.textViewportLayoutController.viewportRange, !vr.isEmpty else { return nil }
        let originY = textContainerOrigin.y, sel = selectedRange()
        let start = cs.offset(from: cs.documentRange.location, to: vr.location), end = cs.offset(from: cs.documentRange.location, to: vr.endLocation)
        for offset in sel.length > 0 ? [sel.location, NSMaxRange(sel)] : [sel.location] where offset >= start && offset <= end {
            var hit: (offset: Int, top: CGFloat, height: CGFloat)?
            lm.enumerateTextLayoutFragments(from: vr.location, options: []) { f in
                let from = cs.offset(from: cs.documentRange.location, to: f.rangeInElement.location)
                guard from <= offset, from < end else { return false }
                let to = cs.offset(from: cs.documentRange.location, to: f.rangeInElement.endLocation)
                guard offset < to || (offset == to && to >= length) else { return true }   // 캐럿은 뒤쪽 문단에 있다
                let frame = f.layoutFragmentFrame
                guard f.state == .layoutAvailable, frame.height > 0 else { return false }   // 접힌 문단
                let lines = f.textLineFragments
                guard let line = lines.first(where: { NSLocationInRange(offset - from, $0.characterRange) }) ?? lines.last else { return false }
                hit = (offset, frame.minY + line.typographicBounds.minY + originY, line.typographicBounds.height)
                return false
            }
            if let hit, hit.top < clip.bounds.maxY - 1, hit.top + hit.height > clip.bounds.minY + 1 { return hit }
        }
        return nil
    }

    /// `preferCaret`: 캐럿 줄이 화면에 보이고 있으면 맨 위 줄 대신 그 줄을 닻으로 삼는다. 캐럿 근처에서 일하던 중에 맨 위 줄을 지키면, 다시 감기며 그 사이의
    /// 줄 수가 달라져 캐럿이 화면 밖으로 밀려난다 (실측: 긴 문단 문서에서 줄바꿈을 켜자 캐럿이 화면 아래 1,135 pt). 캐럿이 화면 밖이면(읽는 중) 맨 위 줄을 지킨다.
    /// 접기·펴기는 맨 위(머리) 줄을 기준으로 하므로 끈다
    func captureReadingAnchor(preferCaret: Bool = true) -> ReadingAnchor? {
        guard window != nil, let clip = enclosingScrollView?.contentView, let cs = textContentStorage, let length = textStorage?.length, length > 0 else { return nil }
        let top = clip.bounds.minY, originY = textContainerOrigin.y
        var found = laidOutViewport(firstBelow: top)?.fragment
        if found == nil {   // 편집 직후 등 뷰포트 범위가 비어 있을 수 있다 — 레이아웃이 아직 옛 것일 때(바꾸기 전) 한 번 배치해 채운다
            textLayoutManager?.textViewportLayoutController.layoutViewport()
            found = laidOutViewport(firstBelow: top)?.fragment
        }
        guard let frag = found else { return nil }
        let fragFrame = frag.layoutFragmentFrame
        var offset = cs.offset(from: cs.documentRange.location, to: frag.rangeInElement.location)
        var lineTop = fragFrame.minY, lineHeight = fragFrame.height
        // 감긴 문단이면 위 가장자리에 걸친 줄 조각의 첫 글자를 잡는다 — 폭이 바뀌어 다시 감겨도 같은 글자가 맨 위에 온다
        let yInFragment = top - originY - fragFrame.minY
        if let line = frag.textLineFragments.last(where: { $0.typographicBounds.minY <= yInFragment + 0.5 }) {
            offset += line.characterRange.location
            lineTop = fragFrame.minY + line.typographicBounds.minY
            lineHeight = line.typographicBounds.height
        }
        // 문서의 마지막 줄이 화면에 보이고 있었으면(끝에서 쓰는 중) 끝에 붙여 둔다 — 맨 위 줄을 지키면 글자가 커질 때 마지막 줄(캐럿)이 화면 아래로 밀려난다
        let pinned = top > 1 && (clip.bounds.maxY >= frame.height - 1
            || laidOutViewport(firstBelow: top).map { $0.end >= length && $0.bottom <= clip.bounds.maxY + 1 } ?? false)
        if preferCaret, !pinned, let caret = caretLineOnScreen() {
            return ReadingAnchor(offset: min(caret.offset, length), delta: top - caret.top, lineHeight: caret.height, pinnedToEnd: false, fraction: frame.height > 1 ? caret.top / frame.height : nil)
        }
        // 맨 위 조각이 뷰포트보다 아래에서 시작하면(배치가 어긋나 위쪽이 비어 있던 상태) 그 빈 틈까지 되살리지 않는다 — 그 줄을 맨 위에 둔다
        let delta = max(top - (lineTop + originY), -clip.bounds.height / 2)
        return ReadingAnchor(offset: min(offset, length), delta: delta, lineHeight: lineHeight, pinnedToEnd: pinned, fraction: frame.height > 1 ? (lineTop + originY) / frame.height : nil)
    }

    /// 닻 글자가 든 줄 상자의 (위 가장자리 y, 높이) — 텍스트 뷰 좌표
    private func lineBox(atOffset offset: Int) -> (y: CGFloat, height: CGFloat)? {
        guard let lm = textLayoutManager, let cs = textContentStorage, let length = textStorage?.length,
              let loc = cs.location(cs.documentRange.location, offsetBy: min(offset, length)) else { return nil }
        let originY = textContainerOrigin.y
        if isInHugeParagraph(offset) {   // 거대 한 줄: 세그먼트 계산이 문단 전체 배치라 문단 프레임으로 대신한다
            return lm.textLayoutFragment(for: loc).map { ($0.layoutFragmentFrame.minY + originY, $0.layoutFragmentFrame.height) }
        }
        // 한 글자 범위로 묻는다 — 길이 0 이면 감긴 줄의 경계에서 앞줄 끝이 나올 수 있다
        let end = offset < length ? cs.location(loc, offsetBy: 1) : nil
        var rect: CGRect?
        lm.enumerateTextSegments(in: end.flatMap { NSTextRange(location: loc, end: $0) } ?? NSTextRange(location: loc), type: .standard, options: [.rangeNotRequired]) { _, f, _, _ in
            rect = f; return false
        }
        if rect == nil, let frag = lm.textLayoutFragment(for: loc) { rect = frag.layoutFragmentFrame }
        return rect.map { ($0.minY + originY, $0.height) }
    }

    /// 닻을 같은 높이로 되돌린다. 멀리 있는 문단의 좌표는 추정이고 추정끼리도 서로 맞지 않으므로(실측: 조각의 프레임이 가리키는 곳으로 가면 다른 문단이 배치된다),
    /// 믿는 것은 **실제로 배치된 뷰포트**뿐이다: 뷰포트를 배치하고 → 닻이 그 범위 안에 있으면 정확히 맞추고, 밖이면 (처음엔 레이아웃 매니저의 추정으로,
    /// 그다음엔 바꾸기 전의 상대 위치·뷰포트의 글자 밀도로 거리를 어림해) 다가간 뒤 다시 배치한다
    func restoreReadingAnchor(_ a: ReadingAnchor) {
        guard let sv = enclosingScrollView, let lm = textLayoutManager, let length = textStorage?.length, length > 0 else { return }
        let clip = sv.contentView, vlc = lm.textViewportLayoutController
        let offset = min(a.offset, length)
        readingAnchorDepth += 1
        // 여기서 맞춘 자리가 새 기준이다 — 스크롤 닻(layout)에 그 자리를 적어 주고, 편집 때문에 쉬고 있었으면 다시 지키게 한다.
        //  · 적어 둔 자리가 이 함수가 스크롤하기 전의 것이면 다음 배치 패스가 그 사이에 옮겨진 좌표만큼을 '까닭 없이 움직인 것'으로 보고 되돌린다
        //    (실측: 줄 이동이 화면 1/3 높이 127.3 pt 에 맞춘 줄을 다음 패스가 164.1 pt 로 옮겼다).
        //  · 전체 속성 재적용(글자 크기·테마)·폭 변화는 저장소 편집으로 통지되므로 닻이 다음 패스를 쉰다. 그런데 그 패스가 위쪽 문단을 실측하며 좌표를 옮기면
        //    방금 맞춘 줄이 화면에서 사라진다 (실측: 접힌 1.3 MB 메모에서 ⌘= 뒤의 패스가 좌표를 46,011 pt 옮겨 맨 위 줄이 12707 → 11595 번째 줄로 바뀌었다)
        // 접힌 문서에서는 넘기지 않는다: 접힌 문단은 배치되기 전까지 보통 줄 높이로 어림되므로 패스마다 좌표가 수만 pt 씩 바뀌고, 닻이 그것을 따라 되돌리는 동안
        // 뷰포트를 거듭 배치해 정지가 길어진다 (실측, 전체 묶음: 접힌 메모의 글자 크기·사이드바 걸음 네 개의 정지 행 44 → 106, 그러고도 캐럿 줄이 36.5 pt 어긋났다)
        defer {
            readingAnchorDepth -= 1
            if hasFolds?() != true { layoutRecord = makeLayoutRecord(); layoutAnchorBlocked = false }
        }
        func scroll(to y: CGFloat) { clip.scroll(to: NSPoint(x: clip.bounds.minX, y: y)); sv.reflectScrolledClipView(clip) }
        var usedEstimate = false, usedProportion = false, exactMoves = 0
        var below: CGFloat = 0, above = CGFloat.greatestFiniteMagnitude   // 닻이 있는 구간: 스크롤 위치 below 보다는 아래, above 보다는 위 (뷰포트로 확인한 것)
        var bracketReset = false
        for pass in 0..<20 {
            // 뷰포트 배치가 문서 높이를 줄여 클립 뷰가 스크롤 위치를 끌어당기면(줄바꿈 끄기·모두 접기) 방금 배치한 것은 옛 위치의 것이다 — 위치가 그대로일 때까지 다시
            for _ in 0..<3 {
                let before = clip.bounds.minY
                vlc.layoutViewport()
                if abs(clip.bounds.minY - before) < 0.5 { break }
            }
            let maxY = max(0, frame.height - clip.bounds.height)
            if a.pinnedToEnd {
                // 끝에 붙이는 동안에도 배치할 때마다 문서 높이 어림이 조금씩 바뀐다 — 몇 번만 따라가고 나머지는 keepPinnedToEnd 가 다음 턴들에 맞춘다
                if abs(clip.bounds.minY - maxY) < 0.5 || pass >= 5 { keepPinnedToEnd(checks: 4); break }
                scroll(to: maxY); continue
            }
            // 지금 보이는 곳을 덮고 있는 배치만 믿는다
            let v = laidOutViewport(firstBelow: clip.bounds.minY).flatMap { $0.bottom > clip.bounds.minY && $0.top < clip.bounds.maxY ? $0 : nil }
            var target: CGFloat
            if let v, offset >= v.start && (offset < v.end || v.end >= length) {
                // 닻이 배치된 범위 안 — 줄 상자의 위치가 정확하다. 글자 크기가 바뀌었으면 줄 안에서의 위치도 같은 비율로
                guard let box = lineBox(atOffset: offset) else { return }
                let delta = a.delta > 0 && a.lineHeight > 0 ? a.delta * box.height / a.lineHeight : a.delta
                target = min(max(0, box.y + delta), maxY)
                if abs(clip.bounds.minY - target) < 0.5 { break }
                exactMoves += 1
                if exactMoves > 3 { break }   // 맞춘 자리를 다시 배치하면 닻이 범위 밖으로 나가는 경우(추정이 계속 바뀜) — 오가지 말고 여기서 멈춘다
            } else {
                // 닻이 뷰포트 밖: 레이아웃 매니저의 추정 위치(문서 안을 가리킬 때만) → 바꾸기 전의 상대 위치(없으면 글자 오프셋의 비율) → 뷰포트의 글자 밀도로 거리를 어림
                let chars = CGFloat(max(1, (v?.end ?? 1) - (v?.start ?? 0)))
                // 닻이 그려 둔 범위 바로 곁이면 멀리 어림하지 않고 그 범위의 글자 밀도로 다가간다. 위 가장자리에 2 pt 쯤만 걸친 줄은 TextKit 의 뷰포트 범위에서 빠져
                // 닻이 '범위 밖'이 되는데, 그때 레이아웃 매니저의 추정 위치를 쓰면(전체 무효화 직후에는 절반쯤 틀린다 — 실측: 209,977 pt 에 있는 줄을 105,000 pt 로 답했다)
                // 먼 곳을 배치하는 동안 좌표가 다시 어림돼 아래의 구간이 낡는다
                let near = v.map { CGFloat(offset < $0.start ? $0.start - offset : offset - $0.end) <= chars * 4 } ?? false
                if !near, !usedEstimate, let box = lineBox(atOffset: offset), box.y >= 0, box.y <= frame.height {
                    usedEstimate = true
                    target = box.y + a.delta
                } else if !near, !usedProportion, v == nil || CGFloat(abs(offset - v!.start)) > chars * 40 {
                    usedProportion = true
                    target = (a.fraction ?? CGFloat(offset) / CGFloat(length)) * frame.height
                } else if let v {
                    let height = max(1, v.bottom - v.top)
                    target = (offset < v.start ? v.top - CGFloat(v.start - offset) * height / chars : v.bottom + CGFloat(offset - v.end) * height / chars) - clip.bounds.height / 3
                } else { break }
                // 뷰포트로 확인한 구간을 좁혀 간다 — 어림(글자 밀도)이 그 구간을 벗어나면 가운데로 (접힌 문서처럼 밀도가 고르지 않아도 반드시 줄어든다)
                if let v { if offset < v.start { above = min(above, clip.bounds.minY) } else { below = max(below, clip.bounds.minY) } }
                target = min(max(0, target), maxY)
                let upper = min(above, maxY)
                if upper > below, target <= below || target >= upper { target = (below + upper) / 2 }
                if abs(clip.bounds.minY - target) < 0.5 {
                    // 구간이 닫혔는데 닻은 여전히 범위 밖이고 문서 처음·끝에 막힌 것도 아니다: 구간을 적은 뒤의 배치가 좌표를 다시 어림해 닻이 구간 밖으로 나갔다
                    // (실측: 위쪽 끝으로 적어 둔 210,000.1 pt 로 수렴했는데 그 자리에는 33줄 앞의 문단이 있었다). 한 번은 구간을 버리고 다시 찾는다
                    if !bracketReset, v != nil, upper - below < 2, target > 0.5, target < maxY - 0.5 {
                        bracketReset = true; below = 0; above = .greatestFiniteMagnitude
                        continue
                    }
                    break   // 더 갈 곳이 없다 (문서 처음·끝에 막힘)
                }
            }
            scroll(to: target)
        }
    }

    /// 끝에 붙인 뒤에도 이어지는 배치가 문서 높이를 조금씩 늘린다(추정 → 실측, 거터 폭이 바뀌며 한 번 더 감김) — 잠깐 동안(다음 턴, 그리고 60 ms 간격으로
    /// 몇 번) 끝에서 조금 떨어졌으면 다시 붙인다. 그사이 사용자가 멀리 스크롤했으면(반 화면 넘게) 그만둔다
    private func keepPinnedToEnd(checks: Int) {
        guard checks > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + (checks == 4 ? 0 : 0.06)) { [weak self] in
            guard let self, let sv = self.enclosingScrollView else { return }
            let clip = sv.contentView, gap = self.frame.height - clip.bounds.maxY
            guard gap < clip.bounds.height / 2 else { return }
            if gap > 0.5 { clip.scroll(to: NSPoint(x: clip.bounds.minX, y: max(0, self.frame.height - clip.bounds.height))); sv.reflectScrolledClipView(clip) }
            self.keepPinnedToEnd(checks: checks - 1)
        }
    }

    /// 문서 전체의 레이아웃을 무효화하는 변화의 앞뒤에 짝으로 부른다: 닻을 잡고(그 사이의 폭 변화는 따로 처리하지 않는다) → 되돌린다
    func beginPreservingReadingPosition() -> ReadingAnchor? {
        let anchor = captureReadingAnchor(preferCaret: false)   // 접기·펴기: 맨 위(머리) 줄 기준
        readingAnchorDepth += 1
        return anchor
    }

    func endPreservingReadingPosition(_ anchor: ReadingAnchor?) {
        readingAnchorDepth -= 1
        if let anchor { restoreReadingAnchor(anchor) }
    }

    func preservingReadingPosition(_ body: () -> Void) {
        let anchor = beginPreservingReadingPosition()
        body()
        endPreservingReadingPosition(anchor)
    }

    // 줄바꿈 폭이 바뀌는 변화 (창·사이드바·분할·줄 번호·미리보기의 폭, 자동 줄바꿈 켬/끔). 보던 곳을 지키는 것에 더해 한 가지가 더 필요하다:
    // TextKit 2 는 폭이 바뀐 뒤에도 다시 배치하지 않은 문단의 높이를 **옛 폭에서 잰 값**으로 어림한다. 폭이 크게 바뀌면(미리보기를 닫아 465 → 1010 pt) 그 어림이
    // 두 배쯤 틀려, 문서 가운데가 전체 높이의 68% 지점에 놓인다. 그대로 두면 스크롤하는 동안 높이가 실측으로 줄어들다가 스크롤 위치가 문서 끝을 넘는 순간
    // 화면이 문서 끝으로 날아간다(실측: 휠 두 번에 2,000 줄). `invalidateLayout(for:)` 로는 어림이 버려지지 않았고(실측), 저장소에 속성 편집을 알려 조각을
    // 새로 만들게 하면 버려진다 — 구문 색 켬/끔이 쓰는 것과 같은 통지다. 그 통지는 같은 문서를 보여 주는 다른 편집기(분할)의 레이아웃도 무효화하므로
    // 형제 뷰의 닻도 함께 잡았다가 되돌린다

    /// 같은 문서를 보여 주는 다른 편집기 (분할 보기 — 콘텐츠 스토리지를 함께 쓴다)
    private var siblingViews: [HyperTextView] {
        (textContentStorage?.textLayoutManagers ?? []).compactMap { $0.textContainer?.textView as? HyperTextView }.filter { $0 !== self }
    }

    struct ReflowToken { fileprivate let views: [HyperTextView]; fileprivate let anchors: [ReadingAnchor?] }

    func beginReflow() -> ReflowToken {
        let views = [self] + siblingViews
        let token = ReflowToken(views: views, anchors: views.map { $0.captureReadingAnchor() })
        views.forEach { $0.readingAnchorDepth += 1 }
        return token
    }

    func endReflow(_ token: ReflowToken) {
        token.views.forEach { $0.readingAnchorDepth -= 1 }
        settleReflow(token)
    }

    /// 옛 폭에서 잰 높이 어림을 버리게 하고 닻을 되돌린다. 같은 닻으로 다시 불러도 된다 (줄바꿈을 켠 다음 턴 — EditorView.setWordWrap)
    func settleReflow(_ token: ReflowToken) {
        if window != nil, let ts = textStorage, ts.length > 0 {
            token.views.forEach { $0.readingAnchorDepth += 1 }   // 통지가 부르는 배치 중의 폭 변화는 따로 처리하지 않는다
            ts.beginEditing()
            ts.edited(.editedAttributes, range: NSRange(location: 0, length: ts.length), changeInLength: 0)
            ts.endEditing()
            token.views.forEach { $0.readingAnchorDepth -= 1 }
        }
        for (view, anchor) in zip(token.views, token.anchors) { if let anchor { view.restoreReadingAnchor(anchor) } }
    }

    /// 자동 줄바꿈 상태에서 폭이 바뀌면(창·사이드바·분할·줄 번호·미리보기) 모든 문단이 다시 감긴다 — 보던 곳을 지킨다 (위의 beginReflow/endReflow).
    /// 줄바꿈이 꺼져 있으면 폭은 내용이 정하는 것이라(가장 긴 줄) 건드리지 않는다
    override func setFrameSize(_ newSize: NSSize) {
        var newSize = newSize
        if isNoWrap { newSize.width = noWrapFrameWidth }   // 줄바꿈 끔: 폭은 이 뷰가 정한다 — AppKit(배치 뒤의 크기 맞춤·클립 뷰를 따르는 autoresizing)이 주는 폭은 쓰지 않는다
        guard readingAnchorDepth == 0, abs(newSize.width - frame.width) > 0.5, textContainer?.widthTracksTextView == true, window != nil else {
            super.setFrameSize(newSize)   // 높이가 줄어 스크롤 위치가 문서 끝을 넘겼으면 layout() 의 constrainScrollToDocumentEnd 가 되돌린다
            return
        }
        let token = beginReflow()
        super.setFrameSize(newSize)
        endReflow(token)
    }


    // MARK: - 선택 변경 감시 (사용자 조작이면 멀티 해제)

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if undoInProgress { selectionMovedByUndo = true }
        if !settingSelectionProgrammatically, multi != nil { multi = nil }
        invalidateCurrentLineBand()   // 현재 줄 띠: 옛 자리(장부)와 새 자리를 다시 그린다
        restartBlink(); caretVisibilityChanged()   // appearance: 선택 유무에 따라 보이고 숨기며, 이전 자리를 지운다
        if cursorStyle != .bar { applyInsertionIndicatorMode() }   // appearance: 거대 문단 안팎을 오갈 때 시스템 캐럿 폴백을 켜고 끈다
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
            // 길이 0 범위는 빼고 넘긴다 (그 줄의 캐럿은 drawCarets 가 직접 그린다). 실측(macOS 27): 첫 범위가 길이 0 이면 — 열 블록의 맨 윗줄이 블록의 왼쪽 열보다
            // 짧을 때 — NSTextView 가 selectedRanges 로는 전부 돌려주면서도 선택 강조를 한 줄도 그리지 않아, 고른 블록이 화면에 보이지 않는 채로 입력이 블록을 바꿨다
            super.setSelectedRanges(ranges.filter { $0.length > 0 }.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
        }
        prepareNoWrapBlockHeadReveal()   // 줄바꿈 끔의 열 블록이면 아래의 스크롤이 머리 칸을 향한다
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
        if !matchHighlights.isEmpty { shiftMatchHighlights(preEdits: edits) }   // search: 편집 전 좌표로 정확히 (저장소 알림은 이 편집을 건너뛴다)
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
        matchHighlights = []   // search
        hasFolds = nil; isOffsetHidden = nil; foldedSpan = nil; foldPills = nil; onFoldPillClick = nil
        hasMasks = nil; isOffsetMasked = nil; secretHitTest = nil; onDidCopySecret = nil   // secrets
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
    /// 진행 중인 undo/redo 가 이 뷰의 선택을 옮겼는가 — 끝난 뒤 그 자리를 보여 준다 (undoDidChange)
    private var selectionMovedByUndo = false

    @objc private func undoWillChange(_ n: Notification) {
        guard (n.object as? UndoManager) === undoManager else { return }
        undoInProgress = true
        selectionMovedByUndo = false
        guard onLinesWillChange != nil, needsLineTracking?() ?? true else { undoNewlineCount = nil; return }
        let ns = string as NSString
        undoNewlineCount = LineIndex.countNewlines(in: ns, range: NSRange(location: 0, length: ns.length))
    }

    @objc private func undoDidChange(_ n: Notification) {
        guard (n.object as? UndoManager) === undoManager else { return }
        undoInProgress = false
        undoNewlineCount = nil
        endSnippetSession()   // snippets: undo/redo 는 shouldChangeText 를 거치지 않아 탭스톱 범위가 낡는다 → 세션 종료
        // 되돌린 자리를 보여 준다. AppKit(TextKit 2)의 undo/redo 는 선택만 그 자리로 옮기고 스크롤하지 않는다 — 화면 밖의 편집(큰 붙여넣기, 모두 선택 뒤 입력,
        // 스크롤해 둔 채 ⌘Z)을 되돌리면 캐럿은 그 자리로 갔는데 화면은 상관없는 곳을 보여 줬다. 분할 보기에서는 포커스를 가진 뷰만 따라간다
        // (다른 뷰의 선택도 편집에 맞춰 옮겨지지만 그 뷰가 보던 자리는 그대로 둔다); 포커스가 편집기 밖(찾기 입력창 + 리본의 되돌리기)이면 선택이 옮겨진 뷰가 따라간다
        if selectionMovedByUndo {
            selectionMovedByUndo = false
            let responder = window?.firstResponder
            if responder === self || !(responder is HyperTextView) {
                scrollRangeToVisible(selectedRange())
                revealCaretAfterRelayout()   // 통째로 되살아난 텍스트는 아직 배치되지 않아 위 스크롤이 추정 위치로 간다
            }
        }
    }

    /// shouldChangeText 를 거치지 않은 문자 편집(undo/redo)을 사후에 통지한다. editedRange 는 편집 후 범위, changeInLength 로 편집 전 범위를 되짚는다.
    @objc private func storageDidProcessEditing(_ n: Notification) {
        guard let ts = n.object as? NSTextStorage, ts === textStorage else { return }
        checkViewportAfterEdit = true   // 문자·속성 편집 모두 배치를 무효화한다 — 다음 배치 패스 뒤에 뷰포트 덮임을 본다 (layout)
        blockLayoutAnchor(dropRecord: true)   // 편집 뒤의 배치는 글을 옮긴다 (스크롤 닻)
        guard ts.editedMask.contains(.editedCharacters) else { return }
        if expectingTrackedEdit { expectingTrackedEdit = false; return }
        // search: 추적되지 않은 문자 편집(undo/redo·파일 열기의 전체 교체·다른 뷰의 편집)만 저장소 범위로 옮긴다 — 입력은 trackedEdits 가 정확히 옮겼다
        if !matchHighlights.isEmpty, ts.editedRange.location != NSNotFound { shiftMatchHighlights(edited: ts.editedRange, delta: ts.changeInLength) }
        // 추적되지 않은 편집은 undo/redo 이거나 프로그램적 전체 교체(파일 열기·다시 읽기)다. 접힘이 없고 undo 도 아니면 할 일이 없다 —
        // 여기서 교체 문자열을 복사하면 8 MB 문서를 열 때마다 8 MB 를 복사하게 된다.
        let foldsActive = (hasFolds?() ?? false) || (hasMasks?() ?? false)   // secrets: 비밀 범위도 undo/redo 뒤 옮겨야 한다
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
        let caretStep = Self.caretStepCommands.contains(selector)   // 가장자리를 넘으면 필요한 만큼만 민다 (revealCaretStep)
        if caretStep { caretStepDepth += 1; selectionBeforeCaretStep = selectedRange() }
        super.doCommand(by: selector)
        if caretStep { caretStepDepth -= 1 }
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
        guard let m = multi, m.ranges.contains(where: { $0.length > 0 }) else {
            let hit = secretHitTest?(selectedRanges.map(\.rangeValue)) ?? false   // secrets
            super.copy(sender)
            if hit { onDidCopySecret?() }
            return
        }
        let ns = string as NSString
        let text = m.ranges.map { ns.substring(with: $0) }.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        let hit = secretHitTest?(m.ranges) ?? false   // secrets: 멀티 캐럿·열 블록 복사
        pb.setString(text, forType: .string)
        if hit { onDidCopySecret?() }
    }

    override func cut(_ sender: Any?) {
        guard let m = multi else {
            let hit = secretHitTest?(selectedRanges.map(\.rangeValue)) ?? false   // secrets: 잘라내기 전에 판정 (super.cut 이 copy 를 거쳐도 그쪽 판정은 편집 전이라 같다)
            super.cut(sender)
            if hit { onDidCopySecret?() }
            return
        }
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
