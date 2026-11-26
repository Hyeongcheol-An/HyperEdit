import AppKit

// MARK: - 줄바꿈 끔 (가로 스크롤)
// 줄바꿈을 끄면 텍스트 컨테이너의 폭을 무한으로 두고(`widthTracksTextView = false`) 텍스트 뷰를 가장 긴 줄만큼 넓혀 가로로 스크롤한다. TextKit 2 의 NSTextView 에
// 그 일을 맡기면(`isHorizontallyResizable = true`) 두 가지가 깨진다 (macOS 27 실측, 실사용 하네스 2026-11-25):
//
//  1. **문서 전체 배치.** 컨테이너가 뷰의 폭을 따르지 않으면 `-[NSTextView textContainerOrigin]` 이 부를 때마다 `ensureLayoutForRange:` 로 문서 전체를 배치한다
//     (가로로 크기를 맞추든 아니든, 컨테이너 폭이 무한이든 유한이든 같다). 그 getter 는 뷰포트 배치(`_viewportBoundsForTextViewportLayoutController:`),
//     프레임 변경(`renewGState`), 캐럿 깜빡임, 스크롤 준비(`prepareContentInRect:`), 그리고 이 앱의 캐럿 사각형 계산이 걸음마다 부른다 — 이미 배치돼 있어도
//     1.3 MB 문서에서 한 번에 22~26 ms(줄바꿈 끔의 타이핑이 키당 13~16 ms 였던 까닭), 전체 속성 재적용(줄바꿈 전환·글자 크기·테마) 직후에는 2.1~2.4 s,
//     4 MB 로그에서는 조각 2,000개 상한 때문에 배치가 걸음마다 버려져 휠 한 걸음이 13~17 s 였다. 그런데 그 계산의 결과는 늘 위·왼쪽 여백(`textContainerInset`)
//     그대로다 — 줄바꿈 끔에서는 getter 를 재정의해 여백을 바로 돌려준다.
//  2. **엉뚱한 폭.** AppKit 의 가로 자동 크기(`_updateContentSizeIfNeeded`)는 문서에 따라 폭을 넓히지 않거나(3,000줄 문서: 가장 긴 줄 17,334 pt 인데 텍스트 뷰는
//     편집기 폭 740 pt 그대로 — 가로 막대가 없고, 줄 끝으로 가도 따라가지 않고, 멀리 있는 긴 줄에서 ⌘→ 를 누르면 화면이 문서 맨 위로 튄다) 내용과 상관없는 폭을
//     준다(가장 긴 줄 867 pt 인 메모에 1,644 pt). 그래서 폭은 이 뷰가 정한다: **편집기 폭과 지금까지 배치해 본 줄 가운데 가장 넓은 것 중 큰 쪽.**
//     화면 밖의 더 긴 줄은 거기까지 스크롤해 배치되는 순간 폭이 넓어진다(가로 막대의 범위가 커진다). 좁아지지는 않는다 — 긴 줄에서 가로로 밀어 둔 채 세로로
//     움직여도 내용이 옆으로 튀지 않게. 다시 재는 것은 다른 문서로 바뀔 때(열기·탭 전환)와 줄바꿈을 껐다 켤 때뿐이고, 글꼴이 바뀌면 글자 폭의 비율만큼 고친다.
//     밖에서 바뀐 파일을 다시 읽을 때는 그대로 둔다 — 덧붙여지는 로그를 가로로 밀어 놓고 보는 중에 읽을 때마다 처음 열로 돌아가지 않게.
//
// 컨테이너 폭은 무한 그대로 둔다: 유한한 폭을 주면 오른쪽→왼쪽 문단(아랍어·히브리어)이 그 폭의 오른쪽 끝에 붙어 화면 밖으로 나간다 (무한일 때는 왼쪽 여백에서 시작한다).
extension HyperTextView {
    /// 줄바꿈 끔에서는 AppKit 의 계산(문서 전체 배치)을 건너뛴다 — 값은 같다 (위 1)
    override var textContainerOrigin: NSPoint {
        isNoWrap ? NSPoint(x: textContainerInset.width, y: textContainerInset.height) : super.textContainerOrigin
    }

    /// 뷰포트가 배치될 때마다(배치 패스든, 보던 곳을 되찾느라 직접 부른 `layoutViewport()` 든): 방금 놓인 줄이 지금까지의 폭보다 넓으면 텍스트 뷰를 넓힌다
    override func textViewportLayoutControllerDidLayout(_ controller: NSTextViewportLayoutController) {
        super.textViewportLayoutControllerDidLayout(controller)
        if isNoWrap { fitNoWrapWidth() }
    }

    /// 줄바꿈을 끈다: 이제부터 폭은 이 뷰가 정한다. 컨테이너·스크롤 뷰 설정은 부르는 쪽(EditorView.Coordinator.setWordWrap)이 이어서 한다
    func beginNoWrap() {
        guard !isNoWrap else { return }
        isNoWrap = true
        noWrapContentWidth = 0
    }

    /// 줄바꿈을 켠다: 가로로 밀어 둔 위치를 처음 열로 되돌린다. 폭은 부르는 쪽이 편집기 폭으로 맞추고, 그 뒤로는 컨테이너가 뷰의 폭을 따른다
    func endNoWrap(in scrollView: NSScrollView) {
        guard isNoWrap else { return }
        isNoWrap = false
        noWrapContentWidth = 0
        let clip = scrollView.contentView
        if clip.bounds.minX != 0 {
            clip.scroll(to: NSPoint(x: 0, y: clip.bounds.minY))
            scrollView.reflectScrolledClipView(clip)
        }
    }

    /// 지금까지 잰 내용의 폭을 버린다 (다른 문서로 바뀐다). 다음 뷰포트 배치가 화면의 줄로 다시 잰다
    func resetNoWrapWidth() {
        guard isNoWrap, noWrapContentWidth > 0 else { return }
        noWrapContentWidth = 0
        needsLayout = true
    }

    /// 글꼴이 바뀌어 모든 줄의 폭이 `ratio` 배가 된다 (새 글자 폭 ÷ 옛 글자 폭): 잰 폭과 가로 스크롤 위치를 그만큼 고친다 — 긴 줄의 끝을 보던 중에 글자 크기를
    /// 바꿔도 같은 글자들이 보이게. 버리고 다시 재면 그사이 폭이 편집기 폭으로 줄어 가로 위치가 처음 열로 돌아간다. 어림이 모자라면 다음 뷰포트 배치가 넓힌다
    func rescaleNoWrapWidth(by ratio: CGFloat) {
        guard isNoWrap, noWrapContentWidth > 0, ratio.isFinite, ratio > 0, abs(ratio - 1) > 0.001 else { return }
        let padding = textContainer?.lineFragmentPadding ?? 0, originX = textContainerOrigin.x
        let margins = padding + 2 * textContainerInset.width
        // 가로 위치는 폭을 고치기 전에 읽는다 — 폭이 줄면 클립 뷰가 먼저 위치를 끌어당긴다
        let clip = enclosingScrollView.flatMap { $0.documentView === self ? $0.contentView : nil }
        let x0 = clip?.bounds.minX ?? 0, visibleWidth = clip?.bounds.width ?? 0
        // 캐럿이 보이는 열에 있었으면 바꾼 뒤에도 보이게 한다 (아직 옛 글꼴의 배치다 — 새 자리는 같은 비율로 어림한다)
        let caret = caretRect(at: selectedRange().location).flatMap { $0.minX >= x0 && $0.maxX <= x0 + visibleWidth ? $0 : nil }
        noWrapContentWidth = ceil(max(0, noWrapContentWidth - margins) * ratio + margins)
        let width = noWrapFrameWidth
        if abs(frame.width - width) > 0.5 { setFrameSize(NSSize(width: width, height: frame.height)) }
        guard let clip, let sv = enclosingScrollView else { return }
        var x = x0 * ratio
        if let caret {
            let caretX = (caret.minX - originX) * ratio + originX
            if caretX + padding + 2 > x + visibleWidth { x = caretX + padding + 2 - visibleWidth } else if caretX < x { x = caretX - padding - 2 }
        }
        x = min(max(0, x.rounded()), max(0, frame.width - clip.bounds.width))
        if abs(x - clip.bounds.minX) > 0.5 { clip.scroll(to: NSPoint(x: x, y: clip.bounds.minY)); sv.reflectScrolledClipView(clip) }
    }

    /// 줄바꿈 끔에서의 텍스트 뷰 폭: 편집기(클립 뷰) 폭과 지금까지 잰 내용의 폭 가운데 큰 쪽
    var noWrapFrameWidth: CGFloat {
        max(enclosingScrollView?.contentView.bounds.width ?? frame.width, noWrapContentWidth)
    }

    /// 뷰포트에 놓인 줄 가운데 가장 넓은 것이 지금까지의 폭을 넘으면 텍스트 뷰를 넓힌다. 읽기만 한다 (배치를 강제하지 않는다)
    func fitNoWrapWidth() {
        guard isNoWrap, let lm = textLayoutManager else { return }
        var maxX: CGFloat = 0
        if let viewport = lm.textViewportLayoutController.viewportRange, !viewport.isEmpty {
            var visited = 0
            lm.enumerateTextLayoutFragments(from: viewport.location, options: []) { fragment in
                if fragment.rangeInElement.location.compare(viewport.endLocation) != .orderedAscending { return false }
                if fragment.state == .layoutAvailable { maxX = max(maxX, fragment.layoutFragmentFrame.maxX) }
                visited += 1
                return visited < 400
            }
        }
        noteNoWrapContent(maxX: maxX)
    }

    /// 보이게 스크롤할 범위의 끝이 지금의 폭 밖이면 먼저 넓힌다. 좁은 채로 AppKit 에 맡기면 가로로는 가지 못하고 세로 위치까지 틀어진다
    /// (실측: 폭 740 pt 인 뷰에서 x 17,350 의 캐럿을 보이게 하라고 하자 화면이 y 0 으로 갔다). 타이핑으로 가장 긴 줄이 더 길어지는 순간도 이 경로다
    func widenNoWrap(toShow range: NSRange) {
        guard isNoWrap, let length = textStorage?.length else { return }
        let originX = textContainerOrigin.x
        var maxX: CGFloat = 0
        for offset in Set([range.location, NSMaxRange(range)]) where offset <= length {
            if let caret = caretRect(at: offset) { maxX = max(maxX, caret.maxX - originX) }   // 거대 문단(2만 자 넘는 한 줄)은 재지 않는다 — 배치 패스가 잰다
        }
        if maxX > 0 { noteNoWrapContent(maxX: maxX) }
    }

    /// AppKit 이 보이게 스크롤한 뒤에도 캐럿이 보이는 열 밖에 있으면 캐럿이 들어올 만큼만 가로로 민다. AppKit 은 왼쪽으로 한 글자씩 가다 가장자리를 넘는 걸음에서
    /// 한 번 늦는다 (실측: 캐럿이 왼쪽 가장자리 밖 6.3 pt 에 가려진 채 한 걸음을 보내고, 다음 걸음에 반 화면을 민다)
    func revealNoWrapCaretColumn(_ range: NSRange) {
        guard isNoWrap, range.length == 0, multi == nil, let sv = enclosingScrollView, sv.documentView === self, let caret = caretRect(at: range.location) else { return }
        let clip = sv.contentView
        let margin = (textContainer?.lineFragmentPadding ?? 0) + 2   // 캐럿이 가장자리에 붙지 않게
        var x = clip.bounds.minX
        if caret.minX < clip.bounds.minX { x = caret.minX - margin } else if caret.maxX > clip.bounds.maxX { x = caret.maxX + margin - clip.bounds.width }
        if x < textContainerOrigin.x + margin { x = 0 }   // 줄 머리 근처면 왼쪽 여백까지
        x = min(max(0, x), max(0, frame.width - clip.bounds.width))
        guard abs(x - clip.bounds.minX) > 0.5 else { return }
        clip.scroll(to: NSPoint(x: x, y: clip.bounds.minY))
        sv.reflectScrolledClipView(clip)
    }

    /// 열 블록을 놓은 뒤의 '보이게 스크롤'을 블록의 머리 칸으로 돌린다 (줄바꿈 끔에서만). 머리 줄이 블록의 열보다 짧으면 그 줄의 선택 범위는 줄 끝에 있는 빈 범위라,
    /// 그것을 보이게 하면 가로로 밀어 둔 화면이 줄 끝(왼쪽 멀리)으로 튄다 — 끌어 고르는 중이면 마우스 아래의 열이 바뀌어 블록이 엉뚱한 열로 넓어진다
    /// (실측: x 600 에서 6자짜리 줄을 지나가자 x 169 로, 90…102 열을 고르려던 블록이 52…90 열). 머리 칸은 줄 끝 너머의 빈 칸(가상 공백)까지 센 자리다
    func prepareNoWrapBlockHeadReveal() {
        guard isNoWrap, let block = multi?.block else { return }
        let lines = block.lines(in: string as NSString)
        guard let line = block.headIsBottom ? lines.last : lines.first,
              let cell = caretCell(at: line.lineStart + min(block.headCol, line.contentLength), padding: max(0, block.headCol - line.contentLength)) else { return }
        let padding = textContainer?.lineFragmentPadding ?? 0
        noteNoWrapContent(maxX: cell.maxX - textContainerOrigin.x)   // 빈 칸이 지금의 폭 밖이면 넓힌다
        noWrapRevealRect = NSRect(x: cell.minX - padding, y: cell.minY, width: cell.width + 2 * padding, height: cell.height)
    }

    /// `maxX`: 컨테이너 좌표에서 본 줄의 오른쪽 끝. 내용 폭은 거기에 오른쪽 줄 여백과 양쪽 뷰 여백을 더한 것이다 (줄 끝의 캐럿이 가장자리에 붙지 않는다)
    private func noteNoWrapContent(maxX: CGFloat) {
        let needed = ceil(maxX + (textContainer?.lineFragmentPadding ?? 0) + 2 * textContainerInset.width)
        if maxX > 0, needed > noWrapContentWidth { noWrapContentWidth = needed }
        let width = noWrapFrameWidth
        if abs(frame.width - width) > 0.5 { setFrameSize(NSSize(width: width, height: frame.height)) }
    }
}
