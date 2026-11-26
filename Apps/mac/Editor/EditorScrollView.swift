import AppKit
import HyperCore

// 편집기의 세로 스크롤바: 손잡이를 좌표가 아니라 **줄(문단) 기준**으로 놓는다.
//
// NSScrollView 는 손잡이를 "스크롤 위치 ÷ (문서 높이 − 화면 높이)"로 놓는다. 그런데 TextKit 2 의 문서 높이는 어림이고, 뷰포트를 배치할 때마다 다시 잡힌다 —
// 한 번도 안 본 곳으로 한 화면 넘게 뛰면 걸음마다 ±10~20 % 가 흔들린다(실측 2026-11-25, 1.3 MB 메모: 847,845 … 1,157,051 pt, 실제는 약 70만. 세션 초반,
// 배치해 본 문단이 적을수록 크다). 그래서 휠을 800 pt 씩 250번 굴리는 동안 손잡이가 95번 거꾸로 갔고(최대 14.6 pt / 382 pt 트랙), 줄로 이동한 뒤의 손잡이는
// 그 줄의 자리와 2~4 % 어긋났다(문서의 절반인 줄에서 0.472). 조각 캐시가 버려지는 걸음(2,000 문단마다)에는 스크롤 닻이 좌표를 고치며 12 pt 를 건너뛰었다.
//
// 줄 수는 정확히 안다(MemoDocument.liveLineIndex). 손잡이의 값을 "화면 위로 지나간 문단 수 ÷ (그것 + 화면 아래에 남은 문단 수)"로 놓으면 문서 높이가 어떻게
// 어림되든 같은 화면에는 같은 값이 나오고, 스크롤하면 그 방향으로만 움직이며, 처음에서 0 · 끝에서 1 이다. 오른쪽 띠의 표식(ScrollMarkerView — 검색 결과·북마크·
// 캐럿 줄을 줄 비율로 찍는다)과도 같은 기준이 된다: 화면에 보이는 줄의 표식은 손잡이 안에 온다.
// 대가: 여러 줄로 감긴 문단도 한 줄로 센다 — 긴 문단이 몰린 곳을 지날 때 손잡이가 느리게 간다(좌표로는 한 문단이 여러 줄 높이다).
//
// 손잡이를 끌면 같은 기준으로 거꾸로 푼다: 손잡이 값에 해당하는 문단을 화면 맨 위에 놓는다(EditorScroller 가 동작을 보내기 전에 가로챈다). 좌표로 풀면
// (AppKit 기본) 놓는 순간 손잡이가 줄 기준 자리로 튄다. 트랙을 눌러 한 쪽씩 넘기는 것은 AppKit 그대로다.
// 줄바꿈을 끈 문서와 접힌 문단이 있는 문서에서는 쓰지 않는다(AppKit 의 좌표 기준 그대로): 접힌 줄은 높이가 0 이라 줄 수와 화면이 비례하지 않는다.

/// 손잡이를 끄는 동안을 알고, 끌기 동작을 스크롤 뷰가 줄 기준으로 처리하게 넘기는 스크롤러
final class EditorScroller: NSScroller {
    /// 하위 클래스는 기본으로 겹침(overlay) 스타일에서 빠진다 — 트랙패드의 기본 스타일을 그대로 쓴다
    override class var isCompatibleWithOverlayScrollers: Bool { self == EditorScroller.self }

    /// 손잡이를 끄는 중인가 (추적 루프 안)
    private(set) var isTrackingKnob = false
    /// 끄는 동안 마우스가 정한 값. 스크롤 뷰는 스크롤을 반영할 때마다 손잡이를 다시 놓는데, 끄는 중에는 이 값(마우스 아래)에 둔다
    fileprivate var draggedValue: Double?

    override func trackKnob(with event: NSEvent) {
        isTrackingKnob = true
        super.trackKnob(with: event)
        isTrackingKnob = false
        draggedValue = nil
        owner?.syncLineScroller()
    }

    /// 이 스크롤러를 가진 스크롤 뷰 (스크롤러의 enclosingScrollView 는 nil 이다 — 스크롤 뷰의 문서 쪽 자식이 아니라서)
    private var owner: EditorScrollView? { superview as? EditorScrollView }

    override func sendAction(_ action: Selector?, to target: Any?) -> Bool {
        // 손잡이 끌기(와 '누른 자리로 이동' 설정에서의 트랙 클릭): 값이 곧 가고 싶은 자리다
        if hitPart == .knob || hitPart == .knobSlot, let sv = owner, sv.scrollerMoved(self) { return true }
        return super.sendAction(action, to: target)
    }
}

final class EditorScrollView: NSScrollView {
    /// 지금 문서의 줄 인덱스 (편집마다 갱신되는 것) — Coordinator 가 꽂는다
    var lineIndex: (() -> LineIndex?)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        hasVerticalScroller = true
        verticalScroller = EditorScroller()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var editor: HyperTextView? { documentView as? HyperTextView }
    /// 마지막으로 놓은 줄 기준 값 — 화면이 아직 배치되지 않아 계산할 수 없는 동안(큰 점프 직후) 이 값에 둔다
    private var lastLineValue: Double?

    private enum LineValue { case unused, pending, value(Double) }

    /// 지금 화면의 줄 기준 손잡이 값. `.unused`: 줄 기준을 쓰지 않는 상태(AppKit 의 값 그대로) · `.pending`: 화면이 아직 배치되지 않았다
    private func lineValue() -> LineValue {
        guard let tv = editor, tv.usesLineScroller, let index = lineIndex?(), index.lineCount > 1 else { return .unused }
        let clip = contentView
        guard abs(clip.constrainBoundsRect(clip.bounds).minY - clip.bounds.minY) < 0.5 else { return .unused }   // 끝을 넘겨 당기는 중: AppKit 이 손잡이를 줄여 보인다
        let height = tv.frame.height
        guard height > clip.bounds.height + 1 else { return .unused }   // 스크롤할 것이 없다
        if clip.bounds.minY <= 0.5 { return .value(0) }
        if clip.bounds.maxY >= height - 0.5 { return .value(1) }
        guard let span = tv.visibleLineSpan(index) else { return .pending }
        let below = max(0, Double(index.lineCount) - span.bottom)
        return .value(span.top + below > 0 ? min(1, max(0, span.top / (span.top + below))) : 0)
    }

    /// 손잡이를 줄 기준 자리에 놓는다. 스크롤이 반영될 때마다, 그리고 텍스트 뷰의 배치가 끝날 때마다(HyperTextView.layout) 부른다
    func syncLineScroller() {
        guard let scroller = verticalScroller else { return }
        if let s = scroller as? EditorScroller, s.isTrackingKnob { if let v = s.draggedValue, abs(s.doubleValue - v) > 1e-9 { s.doubleValue = v }; return }
        switch lineValue() {
        case .unused: lastLineValue = nil
        case .pending: if let v = lastLineValue, abs(scroller.doubleValue - v) > 1e-9 { scroller.doubleValue = v }
        case .value(let v):
            lastLineValue = v
            if abs(scroller.doubleValue - v) > 1e-9 { scroller.doubleValue = v }
        }
    }

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        if cView === contentView { syncLineScroller() }
    }

    /// 손잡이를 끌었다: 손잡이 값(0…1)에 해당하는 자리를 화면 맨 위에 놓는다. 반환: 처리했는가 (false 면 AppKit 이 좌표 기준으로 스크롤한다)
    fileprivate func scrollerMoved(_ scroller: EditorScroller) -> Bool {
        guard let tv = editor, tv.usesLineScroller, let index = lineIndex?(), index.lineCount > 1, index.utf16Count == (tv.textStorage?.length ?? -1),
              tv.frame.height > contentView.bounds.height + 1 else { return false }
        let value = min(1, max(0, scroller.doubleValue))
        scroller.draggedValue = value
        tv.scrollToLineValue(value, index: index)
        return true
    }
}

extension HyperTextView {
    /// 손잡이를 줄 기준으로 놓는 상태인가: 자동 줄바꿈 + 접힌 문단 없음 (파일 머리말)
    var usesLineScroller: Bool { textContainer?.widthTracksTextView == true && hasFolds?() != true }

    /// 화면의 위·아래 가장자리가 문서의 어느 문단에 걸쳐 있는가 — 0 부터 세는 문단 번호에 그 문단 안에서의 비율을 더한 값(맨 위 문단의 절반이 화면 위로 나갔으면 n + 0.5).
    /// 그려 둔 뷰포트의 조각을 읽기만 한다(배치를 일으키지 않는다). 그 조각들이 화면을 덮지 못하면(큰 점프 직후, 배치 전) nil
    func visibleLineSpan(_ index: LineIndex) -> (top: Double, bottom: Double)? {
        guard let lm = textLayoutManager, let cs = textContentStorage, let clip = enclosingScrollView?.contentView, let length = textStorage?.length,
              index.utf16Count == length, let vr = lm.textViewportLayoutController.viewportRange, !vr.isEmpty else { return nil }
        let originY = textContainerOrigin.y
        let top = clip.bounds.minY, bottom = clip.bounds.maxY
        var first: (offset: Int, frame: CGRect)?, last: (offset: Int, end: Int, frame: CGRect)?
        lm.enumerateTextLayoutFragments(from: vr.location, options: []) { f in
            if f.rangeInElement.location.compare(vr.endLocation) != .orderedAscending { return false }
            let frame = f.layoutFragmentFrame.offsetBy(dx: 0, dy: originY)
            guard frame.height > 0 else { return true }
            if frame.minY >= bottom, first != nil { return false }
            let offset = cs.offset(from: cs.documentRange.location, to: f.rangeInElement.location)
            if first == nil, frame.maxY > top + 0.01 { first = (offset, frame) }
            if first != nil { last = (offset, cs.offset(from: cs.documentRange.location, to: f.rangeInElement.endLocation), frame) }
            return true
        }
        guard let first, let last, first.frame.minY <= top + 1 || first.offset == 0, last.frame.maxY >= bottom - 1 || last.end >= length else { return nil }
        func inside(_ y: CGFloat, _ frame: CGRect) -> Double { Double(min(1, max(0, (y - frame.minY) / frame.height))) }
        let topLine = index.lineNumber(forUTF16Offset: first.offset) - 1
        let bottomLine = index.lineNumber(forUTF16Offset: last.offset) - 1
        // 문서가 개행으로 끝나면 마지막 빈 줄은 제 조각 없이 마지막 문단 조각에 덧줄로 놓인다 — 그 조각은 두 줄 몫이다
        let linesInLast = last.end >= length ? Double(max(1, index.lineCount - bottomLine)) : 1
        return (Double(topLine) + inside(top, first.frame), Double(bottomLine) + inside(bottom, last.frame) * linesInLast)
    }

    /// 손잡이 값(0…1)에 해당하는 자리를 화면 맨 위에 놓는다 (visibleLineSpan 의 역). 먼 곳의 좌표는 어림이므로 보던 곳을 되돌릴 때와 같은 방법으로 —
    /// 실제로 배치된 뷰포트를 확인하며 — 그 문단을 맨 위에 놓고(restoreReadingAnchor), 문단 안에서의 비율만큼 더 내린다
    func scrollToLineValue(_ value: Double, index: LineIndex) {
        guard let sv = enclosingScrollView, let lm = textLayoutManager, let cs = textContentStorage, let length = textStorage?.length, length > 0 else { return }
        let clip = sv.contentView
        func scroll(to y: CGFloat) {
            let legal = clip.constrainBoundsRect(NSRect(x: clip.bounds.minX, y: y, width: clip.bounds.width, height: clip.bounds.height))
            guard abs(legal.minY - clip.bounds.minY) > 0.25 else { return }
            clip.scroll(to: legal.origin)
            sv.reflectScrolledClipView(clip)
        }
        if value <= 0 {   // 문서 처음: 위 여백까지
            restoreReadingAnchor(.init(offset: 0, delta: -textContainerOrigin.y, lineHeight: 0, pinnedToEnd: false, fraction: 0))
            return
        }
        if value >= 1 {   // 문서 끝: 끝 부분을 배치하면 높이가 다시 잡힌다 — 가라앉을 때까지
            for _ in 0..<4 {
                scroll(to: frame.height - clip.bounds.height)
                lm.textViewportLayoutController.layoutViewport()
                if clip.bounds.maxY >= frame.height - 0.5 { break }
            }
            return
        }
        let lines = Double(index.lineCount)
        // 화면에 들어오는 문단 수는 자리마다 다르다(감긴 문단) — 놓아 보고 그 자리의 수로 한두 번 고친다. 줄이 많은 문서는 한 번에 맞는다
        var onScreen = visibleLineSpan(index).map { $0.bottom - $0.top } ?? Double(clip.bounds.height / 24)
        for _ in 0..<3 {
            let position = value * max(0, lines - onScreen)   // 화면 맨 위에 올 자리: 문단 번호 + 그 문단 안에서의 비율
            let line = min(index.lineCount - 1, Int(position))
            let offset = min(length, index.range(ofLine: line + 1).location)
            restoreReadingAnchor(.init(offset: offset, delta: 0, lineHeight: 0, pinnedToEnd: false, fraction: CGFloat(value)))
            // 문단 안에서의 비율: 줄이 수천을 넘는 문서에서는 문단 하나가 손잡이의 1 pt 에도 못 미친다 — 문단 머리에 두고 배치를 한 번 아낀다
            let inside = lines - onScreen > 4_000 ? 0 : position - Double(line)
            if inside > 0.001, let location = cs.location(cs.documentRange.location, offsetBy: offset) {
                var paragraph: CGRect?
                lm.enumerateTextLayoutFragments(from: location, options: []) { f in
                    if f.state == .layoutAvailable, f.rangeInElement.location.compare(location) == .orderedSame { paragraph = f.layoutFragmentFrame }
                    return false
                }
                if let paragraph, paragraph.height > 0 {
                    let before = clip.bounds.minY
                    scroll(to: paragraph.minY + textContainerOrigin.y + CGFloat(inside) * paragraph.height)
                    if abs(clip.bounds.minY - before) > 0.25 { lm.textViewportLayoutController.layoutViewport() }
                }
            }
            guard let span = visibleLineSpan(index) else { break }
            let below = max(0, lines - span.bottom)
            let now = span.top + below > 0 ? span.top / (span.top + below) : 0
            if abs(now - value) < 0.0015 || abs((span.bottom - span.top) - onScreen) < 0.05 { break }
            onScreen = span.bottom - span.top
        }
    }
}
