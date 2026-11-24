import AppKit
import HyperCore

// 실사용 시뮬레이션 — 레이아웃 변화: 줄바꿈·줄 번호·확대/축소·테마·사이드바·하단 패널·분할·창 크기를 문서 가운데에서 바꿔도 보던 곳이 유지되는가

// MARK: - 도우미 (찾기·레이아웃 시나리오 공용)

extension RealUseContext {
    /// 지금 화면에서 보고 있는 곳 — 레이아웃이 바뀌는 동작 전후에 "같은 곳을 보고 있는가"를 재는 기준
    struct Place {
        let topLine: Int          // 뷰포트 위 가장자리에 걸친 문단의 줄 번호
        let topOffset: Int        // 그 문단의 시작 오프셋
        let topDelta: CGFloat     // 그 문단의 시작이 위 가장자리에서 떨어진 거리 (≤ 0: 위로 걸쳐 있다)
        let midLine: Int          // 화면 가운데쯤의 문단
        let midOffset: Int
        let midY: CGFloat
        let viewHeight: CGFloat
        let caretY: CGFloat?      // 캐럿 줄이 화면에 보이면 그 위 가장자리의 화면 높이 (문서 끝에 붙어 보고 있을 때는 nil — 그때는 끝에 붙는 것이 규칙이다)
    }

    /// 캐럿(선택이 있으면 그 시작, 시작이 안 보이면 끝) 줄이 화면에 보이면 그 위 가장자리의 화면 높이. 배치된 뷰포트 안의 캐럿만 잰다 —
    /// 화면 밖의 캐럿을 재면 그 문단이 새로 배치되며 조각 프레임이 옮겨져 검사가 상태를 바꾼다
    func caretLineScreenY() -> CGFloat? {
        let v = visible, frags = viewportFragments(), sel = tv.selectedRange()
        guard let first = frags.first, let last = frags.last else { return nil }
        for offset in sel.length > 0 ? [sel.location, NSMaxRange(sel)] : [sel.location] where offset >= first.offset && offset <= last.offset + last.length {
            if let r = tv.caretRect(at: offset), r.minY < v.maxY - 1, r.maxY > v.minY + 1 { return r.minY - v.minY }
        }
        return nil
    }

    func place() -> Place? {
        let v = visible
        let frags = viewportFragments()
        guard let top = frags.first(where: { $0.maxY > v.minY + 1 }) else { return nil }
        let inside = frags.filter { $0.minY >= v.minY && $0.maxY <= v.maxY }
        let mid = inside.dropFirst(inside.count / 2).first ?? top
        let idx = LineIndex(nsString: text)
        let atEnd = v.minY > 1 && (v.maxY >= tv.frame.height - 1 || (frags.last.map { $0.offset + $0.length >= length && $0.maxY <= v.maxY + 1 } ?? false))
        return Place(topLine: idx.lineNumber(forUTF16Offset: top.offset), topOffset: top.offset, topDelta: top.minY - v.minY,
                     midLine: idx.lineNumber(forUTF16Offset: mid.offset), midOffset: mid.offset, midY: mid.minY - v.minY, viewHeight: v.height,
                     caretY: atEnd ? nil : caretLineScreenY())
    }

    /// 레이아웃이 바뀌는 동작 뒤에도 같은 곳을 보고 있는가.
    /// - `tolLines`: 맨 위 줄이 달라져도 되는 줄 수. 줄바꿈 폭·글자 크기가 바뀌면 위 가장자리에 걸쳐 있던 문단이 통째로 화면 밖으로 나갈 수 있어 1 줄은 허용한다
    /// - `strictPt`: 다시 감기지 않는 변화(테마·구문 색·하단 패널)는 내용이 화면에서 이만큼도 움직이면 안 된다
    func checkSamePlace(_ before: Place?, _ why: String, tolLines: Int = 1, strictPt: CGFloat? = nil) {
        guard let b = before else { issue("other", "\(why): could not measure the place before the change"); return }
        guard let n = place() else { issue("coverage", "\(why): nothing is laid out in the viewport after the change"); return }
        let y = screenY(ofFragmentAt: b.topOffset)
        let where_ = y.map { String(format: "at y %+.1f (was %+.1f)", $0, b.topDelta) } ?? "off screen"
        note("\(why): top line \(b.topLine) → \(n.topLine), middle line \(b.midLine) → \(n.midLine); the paragraph that was at the top is now \(where_)")
        // 다시 감기는 변화에서 캐럿 줄이 화면에 보이고 있었으면 지킬 것은 그 줄이다 (HyperTextView.captureReadingAnchor): 같은 높이에 남아야 한다. 맨 위 줄은
        // 그 사이의 문단이 다시 감기는 만큼 달라지는 것이 정상이다. 다시 감기지 않는 변화(strictPt)는 아무것도 움직이지 않아야 하므로 아래의 맨 위 줄 검사로 본다
        if strictPt == nil, let c = b.caretY {
            let atEdge = visible.minY < 1 || visible.maxY > tv.frame.height - 1   // 문서 처음·끝에 걸려 그 높이에 둘 수 없다
            if let y = caretLineScreenY() {
                note("\(why): the caret line was at y \(String(format: "%.1f", c)), now at y \(String(format: "%.1f", y))")
                if abs(y - c) > 2, !atEdge { issue("viewport-jump", "\(why): the caret line was on screen at y \(String(format: "%.1f", c)) and should stay there, but it is now at y \(String(format: "%.1f", y)) (top line \(b.topLine) → \(n.topLine))") }
            } else {
                issue("viewport-jump", "\(why): the caret line was on screen at y \(String(format: "%.1f", c)), now it is off screen (top line \(b.topLine) → \(n.topLine))")
            }
            return
        }
        let d = n.topLine - b.topLine
        if abs(d) > tolLines {
            issue("viewport-jump", "\(why): was looking at line \(b.topLine) (top) / \(b.midLine) (middle), now the top line is \(n.topLine) (\(d > 0 ? "+" : "")\(d) lines); the old top paragraph is \(where_)")
            return
        }
        guard let s = strictPt else { return }
        if let y, abs(y - b.topDelta) > s {
            issue("viewport-jump", "\(why): nothing should reflow, but the content moved \(String(format: "%+.1f", y - b.topDelta)) pt on screen (top line \(b.topLine))")
        } else if y == nil {
            issue("viewport-jump", "\(why): nothing should reflow, but the top paragraph (line \(b.topLine)) left the screen")
        }
    }

    /// 진단 기록: 레이아웃 매니저가 아는 뷰포트 범위와 그 조각들의 상태 (뷰포트에 배치된 조각이 없다고 나올 때 무엇이 어긋났는지 보려고)
    func dumpViewportState(_ tag: String) {
        guard let lm = tv.textLayoutManager, let cs = tv.textContentStorage else { return }
        let v = visible
        guard let vr = lm.textViewportLayoutController.viewportRange else { log("    [viewport] \(tag): viewportRange nil · visible \(Int(v.minY))…\(Int(v.maxY)) docH \(Int(tv.frame.height)) needsLayout \(tv.needsLayout)"); return }
        let a = cs.offset(from: cs.documentRange.location, to: vr.location), b = cs.offset(from: cs.documentRange.location, to: vr.endLocation)
        var states: [String] = []
        lm.enumerateTextLayoutFragments(from: vr.location, options: []) { f in
            if f.rangeInElement.location.compare(vr.endLocation) != .orderedAscending { return false }
            let fr = f.layoutFragmentFrame
            states.append(String(format: "%d@%.0f h%.0f s%d", cs.offset(from: cs.documentRange.location, to: f.rangeInElement.location), fr.minY + tv.textContainerOrigin.y - v.minY, fr.height, f.state.rawValue))
            return states.count < 8
        }
        log("    [viewport] \(tag): range \(a)..<\(b) · visible \(Int(v.minY))…\(Int(v.maxY)) docH \(Int(tv.frame.height)) needsLayout \(tv.needsLayout) caret \(caret) · \(states.joined(separator: " "))")
    }

    /// 문서 가운데를 보는 상태를 만든다: 줄 이동 → (휠로 더 내려 캐럿을 화면 밖에 둠) → (보이는 문단을 클릭해 캐럿을 화면 안에 둠)
    func look(atLine n: Int, wheel: CGFloat = 0, click: Bool = false) async {
        model.jump(toLine: n)
        await settle(400)
        // 줄 이동은 그 줄을 화면 위에서 1/3 높이에 둔다 (EditorView.centerCaretImpl). 문서 처음·끝에 걸리면 그 높이에 둘 수 없다
        let v = visible
        if v.minY > 1, v.maxY < tv.frame.height - 1 {
            if let y = caretLineScreenY() {
                if abs(y - v.height / 3) > 3 { issue("viewport-jump", "go to line \(n): the line should be a third of the way down the screen (y \(String(format: "%.1f", v.height / 3))), but it is at y \(String(format: "%.1f", y))") }
            } else { issue("caret-hidden", "go to line \(n): the line is not on screen (visible \(Int(v.minY))…\(Int(v.maxY)))") }
        }
        if wheel != 0 { await scrollBy(wheel); await settle(150) }
        if click, let a = anchor() { await self.click(offset: a.offset); await settle(100) }
    }

    /// 변화 직후 바로 스크롤: 휠 한 번이 그만큼만 움직이는가 (레이아웃이 덜 끝난 상태에서 튀지 않는가)
    func scrollProbe(_ why: String, by amount: CGFloat = 90) async {
        // 문서 끝에 붙어 있으면 아래로는 갈 곳이 없다 — 위로 먼저 간다. 위아래 모두 여유가 없으면(짧은 문서) 잴 수 없다
        let v = visible
        let roomBelow = tv.frame.height - v.maxY, roomAbove = v.minY
        guard roomBelow >= amount + 2 || roomAbove >= amount + 2 else { note("\(why): no room to scroll \(Int(amount)) pt either way — scroll probe skipped"); return }
        let points = roomBelow >= amount + 2 ? amount : -amount
        let p0 = place()
        let a = anchor()
        await scrollBy(points); await settle(60)
        checkContentMoved(anchor: a, expected: points, tolerance: 3, "\(why) → wheel \(Int(points))")
        checkAll("\(why) → wheel \(Int(points))")
        let b = anchor()
        await scrollBy(-points); await settle(60)
        checkContentMoved(anchor: b, expected: -points, tolerance: 3, "\(why) → wheel \(Int(-points))")
        checkAll("\(why) → wheel \(Int(-points))")
        // 내렸다가 같은 만큼 올리면 제자리여야 한다 (닻 문단이 화면 밖으로 나가 위의 두 검사가 건너뛰어도 이것은 잰다). 화면 가운데 문단으로 잰다 —
        // 맨 위 문단은 위 가장자리에 1~2 pt 만 걸쳐 있으면 다시 배치할 때 뷰포트 범위에서 빠질 수 있다
        if let p0, let y = screenY(ofFragmentAt: p0.midOffset) {
            if abs(y - p0.midY) > 3 { issue("scroll-delta", "\(why): wheel \(Int(points)) then \(Int(-points)) did not come back — the middle paragraph (line \(p0.midLine)) is \(String(format: "%+.1f", y - p0.midY)) pt from where it was") }
        } else if let p0 { issue("scroll-delta", "\(why): wheel \(Int(points)) then \(Int(-points)) did not come back — the middle paragraph (line \(p0.midLine)) is no longer on screen (top line now \(topLine()))") }
    }

    /// 변화 직후 바로 타이핑: 캐럿이 보이고, 캐럿 문단이 화면에서 움직이지 않는가. 캐럿이 화면 밖이면 입력이 캐럿으로 스크롤하는 것이 정상이라 가시성만 본다
    func typeProbe(_ why: String) async {
        let para = text.paragraphRange(for: NSRange(location: min(caret, length), length: 0)).location
        let y0 = screenY(ofFragmentAt: para)
        let onScreen = tv.caretRect(at: caret).map { visible.intersects($0) } ?? false
        await type("가x")
        await settle(60)
        if viewportFragments().isEmpty {   // 진단: 입력 뒤 뷰포트에 배치된 조각이 없다 — 무엇이 남아 있는지, 뷰포트를 다시 배치하면 돌아오는지
            dumpViewportState("\(why) → type: empty")
            await settle(300); dumpViewportState("  after another 300 ms")
            tv.textLayoutManager?.textViewportLayoutController.layoutViewport(); dumpViewportState("  after layoutViewport()")
        }
        checkCaretVisible("\(why) → type")
        if onScreen, let y0 {
            if let y1 = screenY(ofFragmentAt: para) {
                if abs(y1 - y0) > 2 { issue("viewport-jump", "\(why) → type: the caret was on screen, but typing moved its paragraph \(String(format: "%+.1f", y1 - y0)) pt") }
            } else { issue("viewport-jump", "\(why) → type: the caret was on screen, but after typing its paragraph is not laid out in the viewport") }
        }
        checkLayout("\(why) → type"); checkInk("\(why) → type")
        await key(.delete, count: 2)
        await settle(60)
        if viewportFragments().isEmpty {   // 진단: 지운 뒤 뷰포트에 배치된 조각이 없다
            dumpViewportState("\(why) → delete: empty")
            await settle(300); dumpViewportState("  after another 300 ms")
            tv.needsLayout = true; window.layoutIfNeeded(); dumpViewportState("  after needsLayout + layoutIfNeeded")
            tv.textLayoutManager?.textViewportLayoutController.layoutViewport(); dumpViewportState("  after layoutViewport()")
        }
        checkCaretVisible("\(why) → delete")
        // 줄 번호는 문서의 줄 인덱스(편집 250 ms 뒤 갱신)로 그려진다 — 그 사이에는 캐럿 아래의 짧은 줄 번호가 잠깐 어긋난다(입력 영역의 문제로 보고).
        // 여기서는 레이아웃 변화가 남긴 거터 어긋남만 보도록 인덱스가 갱신된 뒤에 비교한다
        await settle(350)
        checkGutter("\(why) → type, delete")
    }

    /// 편집기를 품은 분할 뷰(SwiftUI HSplitView·VSplitView 가 만든 NSSplitView)와, 편집기 쪽 칸 바로 앞(왼쪽·위)의 구분선 번호. `sideBySide`: 좌우로 나뉜 것
    func editorSplit(sideBySide: Bool, dividerAfterEditor: Bool) -> (split: NSSplitView, divider: Int)? {
        var child: NSView = scroll
        var view = scroll.superview
        while let cur = view {
            if let sp = cur as? NSSplitView, sp.isVertical == sideBySide, sp.arrangedSubviews.count > 1, let i = sp.arrangedSubviews.firstIndex(where: { child.isDescendant(of: $0) }) {
                let d = dividerAfterEditor ? i : i - 1
                if d >= 0, d < sp.arrangedSubviews.count - 1 { return (sp, d) }
            }
            child = cur; view = cur.superview
        }
        return nil
    }

    /// 구분선을 끌 듯이 여러 걸음으로 옮긴다 (delta 양수 = 오른쪽·아래로)
    func dragDivider(_ s: (split: NSSplitView, divider: Int), by delta: CGFloat, steps: Int = 10) async {
        let pane = s.split.arrangedSubviews[s.divider].frame
        let start = s.split.isVertical ? pane.maxX : pane.maxY
        for i in 1...steps {
            s.split.setPosition(start + delta * CGFloat(i) / CGFloat(steps), ofDividerAt: s.divider)
            await turn()
        }
    }

    enum After { case nothing, scroll, type }

    /// 레이아웃을 바꾸는 동작 하나: 전후로 보던 곳·조각·거터·잉크를 검사하고, 바로 이어서 스크롤하거나 타이핑한다
    func change(_ label: String, tolLines: Int = 1, strictPt: CGFloat? = nil, settleMs: UInt64 = 350, then after: After = .scroll, _ action: () -> Void) async {
        at(label)
        // 앞 걸음이 화면을 깨진 상태(배치된 조각이 없거나 위쪽이 빈 상태 — 그 걸음에서 이미 기록됐다)로 남겼으면 여기서 재는 것은 의미가 없다: 줄 이동으로 다시 자리를 잡는다
        if let p = place(), p.topDelta > lineHeight * 2 || p.topDelta < -visible.height * 4 {
            note("the previous step left a hole at the top of the viewport (first paragraph at \(Int(p.topDelta)) pt) — re-anchoring at line \(p.topLine) before this change")
            await look(atLine: p.topLine)
        }
        let before = place()
        if before == nil { dumpViewportState("\(label): nothing laid out before the change") }
        action()
        await settle(settleMs)
        checkSamePlace(before, label, tolLines: tolLines, strictPt: strictPt)
        checkAll(label); checkInk(label)
        switch after {
        case .nothing: break
        case .scroll: await scrollProbe(label)
        case .type: await typeProbe(label)
        }
    }
}

extension RealUse {
    /// 시나리오가 바꾼 보기 설정을 처음 상태로 되돌린다 (다음 시나리오가 같은 조건에서 시작하도록)
    @MainActor
    struct ViewDefaults {
        let wrap: Bool, numbers: Bool, syntax: Bool, sidebar: Bool, bottom: Bool, preview: Bool
        let fontSize: Double, themeID: String, followsSystem: Bool, frame: NSRect

        init(_ ctx: RealUseContext) {
            let m = ctx.model
            wrap = m.wordWrap; numbers = m.showLineNumbers; syntax = m.syntaxHighlighting; sidebar = m.showFileView; bottom = m.showBottomPanel
            preview = m.showMarkdownPreview; fontSize = m.font.size; themeID = m.themes.current.id; followsSystem = m.themes.followsSystem; frame = ctx.window.frame
        }

        func restore(_ ctx: RealUseContext) async {
            let m = ctx.model
            if m.session.splitMode != .none { m.setSplit(.none) }
            if m.wordWrap != wrap { m.wordWrap = wrap }
            if m.showLineNumbers != numbers { m.showLineNumbers = numbers }
            if m.syntaxHighlighting != syntax { m.syntaxHighlighting = syntax }
            if m.showFileView != sidebar { m.showFileView = sidebar }
            if m.showBottomPanel != bottom { m.showBottomPanel = bottom }
            if m.showMarkdownPreview != preview { m.showMarkdownPreview = preview }
            if m.font.size != fontSize { m.font.size = fontSize }
            if m.themes.current.id != themeID { m.themes.select(id: themeID) }
            if m.themes.followsSystem != followsSystem { m.themes.setFollowsSystem(followsSystem) }
            if ctx.window.frame != frame { ctx.window.setFrame(frame, display: true) }
            await ctx.settle(300)
        }
    }

    /// 말뭉치의 가운데쯤 줄
    @MainActor static func middleLine(_ ctx: RealUseContext) -> Int { max(1, ctx.doc.lineIndex.lineCount / 2) }

    @MainActor static let layoutScenarios: [Scenario] = [
        // 자동 줄바꿈 켬/끔 — 긴 문단이 여러 번 감기는 문서의 가운데에서. 줄 높이가 통째로 바뀌므로 스크롤 좌표를 그대로 두면 전혀 다른 곳이 보인다
        Scenario(name: "layout-wrap") { ctx in
            let saved = ViewDefaults(ctx)
            await ctx.withRelaxedStalls { await ctx.open(.wide) }
            await ctx.look(atLine: middleLine(ctx), wheel: 700)
            ctx.at("middle"); ctx.checkAll("middle of the wide document"); ctx.snap("before")
            await ctx.change("wrap off (caret off screen)") { ctx.model.wordWrap = false }
            ctx.snap("wrap-off")
            await ctx.change("wrap on (caret off screen)") { ctx.model.wordWrap = true }
            ctx.snap("wrap-on")
            // 캐럿이 화면 안에 있을 때: 바꾼 직후 바로 타이핑
            if let a = ctx.anchor() { await ctx.click(offset: a.offset); await ctx.settle(100) }
            await ctx.change("wrap off (caret on screen)", then: .type) { ctx.model.wordWrap = false }
            await ctx.change("wrap on (caret on screen)", then: .type) { ctx.model.wordWrap = true }
            ctx.snap("end")
            // 짧은 줄 위주의 메모(1.3 MB) 가운데에서
            await ctx.withRelaxedStalls { await ctx.open(.notes) }
            await ctx.look(atLine: middleLine(ctx), wheel: 500)
            await ctx.change("notes: wrap off") { ctx.model.wordWrap = false }
            await ctx.change("notes: wrap on") { ctx.model.wordWrap = true }
            ctx.snap("notes-end")
            await saved.restore(ctx)
        },
        // 줄바꿈을 끈 채 쓰기: 긴 줄이 섞인 문서의 가운데에서 휠·쓸기·페이지 키로 움직여도 화면이 비지 않는가 (줄바꿈을 끄고 나서 줄 이동으로 자리를 잡는다 — 끄는 순간의 위치 유지와는 별개)
        Scenario(name: "layout-nowrap") { ctx in
            let saved = ViewDefaults(ctx)
            await ctx.withRelaxedStalls {
                await ctx.open(.wide)
                ctx.model.wordWrap = false
                await ctx.settle(400)
                await ctx.look(atLine: middleLine(ctx))
            }
            ctx.at("no wrap, middle"); ctx.checkAll("no wrap: middle of the wide document"); ctx.checkInk("no wrap: middle"); ctx.snap("middle")
            for d in [90, -90, 400, -400, 150, 150, 150, -450, 2000, -2000] {
                ctx.at("no wrap: wheel \(d)")
                let a = ctx.anchor()
                await ctx.scrollBy(CGFloat(d)); await ctx.settle(60)
                ctx.checkContentMoved(anchor: a, expected: CGFloat(d), tolerance: 3, "no wrap: wheel \(d)")
                ctx.checkAll("no wrap: wheel \(d)"); ctx.checkInk("no wrap: wheel \(d)")
                if d == 90 || d == -400 { ctx.snap("wheel-\(d)") }
            }
            ctx.at("no wrap: flick")
            await ctx.flick(total: 1500); ctx.checkAll("no wrap: flick 1500"); ctx.checkInk("no wrap: flick 1500")
            await ctx.flick(total: -1500); ctx.checkAll("no wrap: flick -1500"); ctx.checkInk("no wrap: flick -1500")
            ctx.at("no wrap: page keys")
            await ctx.key(.pageDown); await ctx.settle(80); ctx.checkAll("no wrap: page down"); ctx.checkInk("no wrap: page down")
            await ctx.key(.pageUp); await ctx.settle(80); ctx.checkAll("no wrap: page up"); ctx.checkInk("no wrap: page up")
            ctx.snap("end")
            await ctx.withRelaxedStalls { await saved.restore(ctx) }
        },
        // 줄 번호 켬/끔 — 거터 폭만큼 본문 폭이 바뀌어 감긴 문단이 다시 감긴다
        Scenario(name: "layout-linenumbers") { ctx in
            let saved = ViewDefaults(ctx)
            await ctx.withRelaxedStalls { await ctx.open(.wide) }
            await ctx.look(atLine: middleLine(ctx), wheel: 700)
            await ctx.change("line numbers off") { ctx.model.showLineNumbers = false }
            ctx.snap("numbers-off")
            await ctx.change("line numbers on") { ctx.model.showLineNumbers = true }
            ctx.snap("numbers-on")
            if let a = ctx.anchor() { await ctx.click(offset: a.offset); await ctx.settle(100) }
            await ctx.change("line numbers off (caret on screen)", then: .type) { ctx.model.showLineNumbers = false }
            await ctx.change("line numbers on (caret on screen)", then: .type) { ctx.model.showLineNumbers = true }
            await saved.restore(ctx)
        },
        // 글자 크기 ⌘= / ⌘- / ⌘0 — 전체 속성을 다시 입히므로 모든 줄 높이가 바뀐다
        Scenario(name: "layout-zoom") { ctx in
            let saved = ViewDefaults(ctx)
            for corpus in [RealUseContext.Corpus.notes, .wide] {
                let tag = corpus == .notes ? "notes" : "wide"
                await ctx.withRelaxedStalls { await ctx.open(corpus) }
                await ctx.look(atLine: middleLine(ctx), wheel: 600)
                ctx.at("\(tag): middle"); ctx.snap("\(tag)-before")
                for i in 1...3 { await ctx.change("\(tag): larger text #\(i) (\(Int(ctx.model.font.size)) → \(Int(ctx.model.font.size) + 1))") { ctx.model.adjustFontSize(1) } }
                ctx.snap("\(tag)-larger")
                for i in 1...5 { await ctx.change("\(tag): smaller text #\(i) (\(Int(ctx.model.font.size)) → \(Int(ctx.model.font.size) - 1))") { ctx.model.adjustFontSize(-1) } }
                ctx.snap("\(tag)-smaller")
                await ctx.change("\(tag): default text size") { ctx.model.font.size = saved.fontSize }
                if let a = ctx.anchor() { await ctx.click(offset: a.offset); await ctx.settle(100) }
                await ctx.change("\(tag): larger text (caret on screen)", then: .type) { ctx.model.adjustFontSize(2) }
                await ctx.change("\(tag): default text size (caret on screen)", then: .type) { ctx.model.font.size = saved.fontSize }
                ctx.snap("\(tag)-end")
            }
            await saved.restore(ctx)
        },
        // 맨 위 줄이 위 가장자리에 한두 pt 만 걸친 채로 다시 감긴다. 그런 줄은 TextKit 2 의 뷰포트 범위에서 빠져 있어서, 보던 곳을 되찾을 때 닻을 '범위 밖'으로
        // 보고 멀리 찾으러 가기 쉽다 (전체 묶음의 layout-zoom 에서만 33줄 튀던 것 — 앞선 시나리오가 남긴 위치 때문에 그 걸음에서 맨 위 줄이 2 pt 만 보였다)
        Scenario(name: "layout-sliver") { ctx in
            let saved = ViewDefaults(ctx)
            for corpus in [RealUseContext.Corpus.wide, .notes] {
                let tag = corpus == .notes ? "notes" : "wide"
                await ctx.withRelaxedStalls { await ctx.open(corpus) }
                await ctx.look(atLine: middleLine(ctx), wheel: 600)
                let steps: [(String, () -> Void)] = [
                    ("larger text", { ctx.model.adjustFontSize(1) }), ("larger text again", { ctx.model.adjustFontSize(1) }),
                    ("smaller text", { ctx.model.adjustFontSize(-1) }), ("smaller text again", { ctx.model.adjustFontSize(-1) }), ("smaller text a third time", { ctx.model.adjustFontSize(-1) }),
                    ("default text size", { ctx.model.font.size = saved.fontSize }),
                    ("sidebar closed", { ctx.model.showFileView = false }), ("sidebar open", { ctx.model.showFileView = true }),
                    ("line numbers off", { ctx.model.showLineNumbers = false }), ("line numbers on", { ctx.model.showLineNumbers = true }),
                ]
                for (i, (label, action)) in steps.enumerated() {
                    // 맨 위 문단이 1~2 pt 만 보이게 맞춘다 (휠 이벤트는 정수 pt 라 마지막 소수점은 스크롤 위치를 직접 옮겨 맞춘다 — 트랙패드로는 흔한 위치다)
                    let sliver: CGFloat = [2.0, 1.0, 1.5][i % 3]
                    let v = ctx.visible
                    if let top = ctx.viewportFragments().first(where: { $0.maxY > v.minY + 3 }) {
                        await ctx.scrollBy((top.maxY - v.minY - sliver).rounded(.down)); await ctx.settle(100)
                        if let t = ctx.viewportFragments().first(where: { $0.offset == top.offset }) {
                            let clip = ctx.scroll.contentView
                            clip.scroll(to: NSPoint(x: clip.bounds.minX, y: t.maxY - sliver)); ctx.scroll.reflectScrolledClipView(clip)
                            await ctx.settle(150)
                        }
                    }
                    if let top = ctx.viewportFragments().first(where: { $0.maxY > ctx.visible.minY + 0.25 }) { ctx.note(String(format: "top paragraph shows %.1f pt", top.maxY - ctx.visible.minY)) }
                    await ctx.change("\(tag): a sliver of the top line — \(label)", action)
                }
            }
            await saved.restore(ctx)
        },
        // 테마 전환 · 구문 색 켬/끔 — 글꼴이 그대로라 아무것도 다시 감기지 않는다: 내용이 화면에서 움직이면 안 된다
        Scenario(name: "layout-theme") { ctx in
            let saved = ViewDefaults(ctx)
            for corpus in [RealUseContext.Corpus.notes, .wide] {
                let tag = corpus == .notes ? "notes" : "wide"
                await ctx.withRelaxedStalls { await ctx.open(corpus) }
                await ctx.look(atLine: middleLine(ctx), wheel: 600)
                let ids = ctx.model.themes.themes.map(\.id)
                for id in ids.prefix(4) where id != ctx.model.themes.current.id {
                    await ctx.change("\(tag): theme \(id)", strictPt: 2) { ctx.model.themes.select(id: id) }
                    ctx.snap("\(tag)-theme-\(id)")
                }
                await ctx.change("\(tag): theme back to \(saved.themeID)", strictPt: 2) { ctx.model.themes.select(id: saved.themeID) }
                await ctx.change("\(tag): syntax colors off", strictPt: 2) { ctx.model.syntaxHighlighting = false }
                ctx.snap("\(tag)-syntax-off")
                await ctx.change("\(tag): syntax colors on", strictPt: 2) { ctx.model.syntaxHighlighting = true }
                if let a = ctx.anchor() { await ctx.click(offset: a.offset); await ctx.settle(100) }
                if let other = ids.first(where: { $0 != saved.themeID }) {
                    await ctx.change("\(tag): theme \(other) (caret on screen)", strictPt: 2, then: .type) { ctx.model.themes.select(id: other) }
                    await ctx.change("\(tag): theme back (caret on screen)", strictPt: 2, then: .type) { ctx.model.themes.select(id: saved.themeID) }
                }
            }
            await saved.restore(ctx)
        },
        // 사이드바 · 하단 패널 · 마크다운 미리보기 여닫기
        Scenario(name: "layout-panels") { ctx in
            let saved = ViewDefaults(ctx)
            await ctx.withRelaxedStalls { await ctx.open(.wide) }
            await ctx.look(atLine: middleLine(ctx), wheel: 700)
            ctx.at("middle"); ctx.snap("before")
            // 하단 패널: 편집기 높이만 바뀐다 — 맨 위 줄은 제자리
            await ctx.change("bottom panel closed", strictPt: 2) { ctx.model.showBottomPanel = false }
            ctx.snap("bottom-closed")
            await ctx.change("bottom panel open", strictPt: 2) { ctx.model.showBottomPanel = true }
            await ctx.change("bottom panel: bookmarks tab", strictPt: 2) { ctx.model.bottomTab = .bookmarks }
            await ctx.change("bottom panel: output tab", strictPt: 2) { ctx.model.bottomTab = .output }
            await ctx.change("bottom panel: find tab", strictPt: 2) { ctx.model.bottomTab = .findResults }
            // 사이드바: 편집기 폭이 바뀌어 다시 감긴다
            await ctx.change("sidebar closed") { ctx.model.showFileView = false }
            ctx.snap("sidebar-closed")
            await ctx.change("sidebar open") { ctx.model.showFileView = true }
            await ctx.change("sidebar: outline", strictPt: 2) { ctx.model.showOutline() }
            await ctx.change("sidebar: files", strictPt: 2) { ctx.model.leftTab = .fileView }
            // 미리보기: 편집기 폭이 절반쯤으로
            await ctx.change("markdown preview on", settleMs: 600) { ctx.model.showMarkdownPreview = true }
            ctx.snap("preview-on")
            await ctx.change("markdown preview off", settleMs: 600) { ctx.model.showMarkdownPreview = false }
            ctx.snap("preview-off")
            // 구분선 끌기: 하단 패널의 높이(편집기 높이만 바뀐다) · 사이드바의 폭(다시 감긴다)
            if let bottom = ctx.editorSplit(sideBySide: false, dividerAfterEditor: true) {
                ctx.at("drag the bottom panel divider up")
                var before = ctx.place()
                await ctx.dragDivider(bottom, by: -120); await ctx.settle(300)
                ctx.checkSamePlace(before, "dragged the bottom panel divider 120 pt up", strictPt: 2); ctx.checkAll("bottom divider up"); ctx.checkInk("bottom divider up"); ctx.snap("bottom-divider-up")
                await ctx.scrollProbe("bottom divider up")
                ctx.at("drag the bottom panel divider down")
                before = ctx.place()
                await ctx.dragDivider(bottom, by: 120); await ctx.settle(300)
                ctx.checkSamePlace(before, "dragged the bottom panel divider 120 pt down", strictPt: 2); ctx.checkAll("bottom divider down"); ctx.checkInk("bottom divider down")
            } else { ctx.note("no stacked split view around the editor — bottom divider drag skipped") }
            if let side = ctx.editorSplit(sideBySide: true, dividerAfterEditor: false) {
                ctx.at("drag the sidebar divider right")
                var before = ctx.place()
                await ctx.dragDivider(side, by: 150); await ctx.settle(300)
                ctx.checkSamePlace(before, "dragged the sidebar divider 150 pt right"); ctx.checkAll("sidebar divider right"); ctx.checkInk("sidebar divider right"); ctx.snap("sidebar-divider-right")
                await ctx.scrollProbe("sidebar divider right")
                ctx.at("drag the sidebar divider left")
                before = ctx.place()
                await ctx.dragDivider(side, by: -150); await ctx.settle(300)
                ctx.checkSamePlace(before, "dragged the sidebar divider 150 pt left"); ctx.checkAll("sidebar divider left"); ctx.checkInk("sidebar divider left")
            } else { ctx.note("no side-by-side split view around the editor — sidebar divider drag skipped") }
            if let a = ctx.anchor() { await ctx.click(offset: a.offset); await ctx.settle(100) }
            await ctx.change("sidebar closed (caret on screen)", then: .type) { ctx.model.showFileView = false }
            await ctx.change("bottom panel closed (caret on screen)", strictPt: 2, then: .type) { ctx.model.showBottomPanel = false }
            await ctx.change("bottom panel open (caret on screen)", strictPt: 2, then: .type) { ctx.model.showBottomPanel = true }
            await ctx.change("sidebar open (caret on screen)", then: .type) { ctx.model.showFileView = true }
            ctx.snap("end")
            await saved.restore(ctx)
        },
        // 분할 켬/끔 · 방향 전환 — 주 편집기는 그대로 살아 있고 크기만 바뀐다
        Scenario(name: "layout-split") { ctx in
            let saved = ViewDefaults(ctx)
            for corpus in [RealUseContext.Corpus.wide, .notes] {
                let tag = corpus == .notes ? "notes" : "wide"
                await ctx.withRelaxedStalls { await ctx.open(corpus) }
                await ctx.look(atLine: middleLine(ctx), wheel: 700)
                await ctx.change("\(tag): split side by side", settleMs: 600) { ctx.model.setSplit(.vertical) }
                ctx.snap("\(tag)-split-vertical")
                await ctx.change("\(tag): split stacked", settleMs: 600) { ctx.model.setSplit(.horizontal) }
                ctx.snap("\(tag)-split-horizontal")
                await ctx.change("\(tag): split off", settleMs: 600) { ctx.model.setSplit(.none) }
                ctx.snap("\(tag)-split-off")
                if let a = ctx.anchor() { await ctx.click(offset: a.offset); await ctx.settle(100) }
                await ctx.change("\(tag): split side by side (caret on screen)", settleMs: 600, then: .type) { ctx.model.setSplit(.vertical) }
                await ctx.change("\(tag): split off (caret on screen)", settleMs: 600, then: .type) { ctx.model.setSplit(.none) }
            }
            await saved.restore(ctx)
        },
        // 창 크기 — 폭이 바뀌면 줄바꿈 폭이 바뀐다. 끌어서 조금씩 바꾸는 것처럼 여러 단계로
        Scenario(name: "layout-window") { ctx in
            let saved = ViewDefaults(ctx)
            await ctx.withRelaxedStalls { await ctx.open(.wide) }
            await ctx.look(atLine: middleLine(ctx), wheel: 700)
            ctx.at("middle"); ctx.snap("before")
            let f0 = ctx.window.frame
            func frame(dw: CGFloat, dh: CGFloat) -> NSRect { NSRect(x: f0.minX, y: f0.maxY - (f0.height + dh), width: f0.width + dw, height: f0.height + dh) }   // 왼쪽 위 모서리를 고정
            // 한 번에 크게
            await ctx.change("window 300 pt narrower") { ctx.window.setFrame(frame(dw: -300, dh: 0), display: true) }
            ctx.snap("narrow")
            await ctx.change("window back to the original width") { ctx.window.setFrame(f0, display: true) }
            // 끌기: 20 pt 씩 15 번 좁혔다가 되돌린다 (걸음마다 한 턴)
            ctx.at("drag narrower")
            var before = ctx.place()
            for i in 1...15 { ctx.window.setFrame(frame(dw: CGFloat(-20 * i), dh: 0), display: true); await ctx.turn() }
            await ctx.settle(350)
            ctx.checkSamePlace(before, "dragged the window edge 300 pt narrower in 15 steps"); ctx.checkAll("drag narrower"); ctx.checkInk("drag narrower")
            ctx.at("drag wider")
            before = ctx.place()
            for i in (0..<15).reversed() { ctx.window.setFrame(frame(dw: CGFloat(-20 * i), dh: 0), display: true); await ctx.turn() }
            await ctx.settle(350)
            ctx.checkSamePlace(before, "dragged the window edge back in 15 steps"); ctx.checkAll("drag wider"); ctx.checkInk("drag wider")
            // 높이만: 다시 감기지 않는다
            await ctx.change("window 200 pt shorter", strictPt: 2) { ctx.window.setFrame(frame(dw: 0, dh: -200), display: true) }
            ctx.snap("short")
            await ctx.change("window back to the original height", strictPt: 2) { ctx.window.setFrame(f0, display: true) }
            if let a = ctx.anchor() { await ctx.click(offset: a.offset); await ctx.settle(100) }
            await ctx.change("window 240 pt narrower (caret on screen)", then: .type) { ctx.window.setFrame(frame(dw: -240, dh: 0), display: true) }
            await ctx.change("window back (caret on screen)", then: .type) { ctx.window.setFrame(f0, display: true) }
            ctx.snap("end")
            await saved.restore(ctx)
        },
        // 문서 끝에서 쓰는 중에 레이아웃을 바꾼다 (메모를 끝에 덧붙이는 가장 흔한 상태): 끝 줄과 캐럿이 계속 보여야 한다
        Scenario(name: "layout-end") { ctx in
            let saved = ViewDefaults(ctx)
            for corpus in [RealUseContext.Corpus.notes, .wide] {
                let tag = corpus == .notes ? "notes" : "wide"
                await ctx.withRelaxedStalls { await ctx.open(corpus) }
                await ctx.key(.down, [.command]); await ctx.settle(250)
                await ctx.type("\n끝에서 쓰는 중 typing at the end")
                await ctx.settle(350)
                ctx.at("\(tag): typing at the end"); ctx.checkCaretVisible("\(tag): typing at the end"); ctx.checkAll("\(tag): typing at the end"); ctx.snap("\(tag)-end")
                let steps: [(String, () -> Void)] = [
                    ("larger text", { ctx.model.adjustFontSize(1) }), ("larger text again", { ctx.model.adjustFontSize(2) }), ("default text size", { ctx.model.font.size = saved.fontSize }),
                    ("smaller text", { ctx.model.adjustFontSize(-2) }), ("default text size again", { ctx.model.font.size = saved.fontSize }),
                    ("sidebar closed", { ctx.model.showFileView = false }), ("sidebar open", { ctx.model.showFileView = true }),
                    ("line numbers off", { ctx.model.showLineNumbers = false }), ("line numbers on", { ctx.model.showLineNumbers = true }),
                    ("theme", { ctx.model.themes.selectNext() }), ("theme back", { ctx.model.themes.select(id: saved.themeID) }),
                    ("split side by side", { ctx.model.setSplit(.vertical) }), ("split off", { ctx.model.setSplit(.none) }),
                ]
                for (label, action) in steps {
                    ctx.at("\(tag): at the end — \(label)")
                    action()
                    await ctx.settle(label.hasPrefix("split") ? 600 : 350)
                    let why = "\(tag): at the end of the document — \(label)"
                    ctx.checkCaretVisible(why)
                    let v = ctx.visible, docH = ctx.tv.frame.height
                    if docH > v.height, v.maxY < docH - 2 { ctx.issue("viewport-jump", "\(why): the view was at the end of the document, now \(Int(docH - v.maxY)) pt of the end are below the screen") }
                    ctx.checkAll(why); ctx.checkInk(why)
                    await ctx.type("x"); await ctx.settle(60)
                    ctx.checkCaretVisible("\(why) → type"); ctx.checkLayout("\(why) → type")
                    await ctx.key(.delete); await ctx.settle(350)
                    ctx.checkGutter("\(why) → type, delete")
                }
                ctx.snap("\(tag)-after")
                await saved.restore(ctx)
            }
        },
        // 접기: 모두 접으면 보던 줄을 품은 머리 줄이 화면 맨 위에 오고, 모두 펴면 그 머리 줄이 그대로 맨 위에 남는가
        Scenario(name: "layout-fold") { ctx in
            let saved = ViewDefaults(ctx)
            await ctx.withRelaxedStalls { await ctx.open(.notes) }
            await ctx.look(atLine: middleLine(ctx), wheel: 500)
            ctx.at("middle"); ctx.snap("before")
            guard let before = ctx.place() else { ctx.issue("other", "nothing laid out in the middle of the notes"); await saved.restore(ctx); return }
            ctx.at("fold all")
            ctx.model.send(.foldAll); await ctx.settle(500)
            ctx.checkAll("fold all"); ctx.checkInk("fold all"); ctx.snap("folded")
            // 보던 줄(before.topLine)은 접혀 사라졌거나 그대로 보인다: 화면 맨 위 줄은 그 줄이거나 그 줄을 품은 머리 줄(위쪽)이어야 하고, 둘째로 보이는 줄은 그 줄보다 아래여야 한다
            let idx = LineIndex(nsString: ctx.text)
            let v = ctx.visible
            let shown = ctx.viewportFragments().filter { $0.maxY > v.minY + 1 && $0.minY < v.maxY }.map { idx.lineNumber(forUTF16Offset: $0.offset) }
            ctx.note("fold all: was looking at line \(before.topLine); visible lines now start \(shown.prefix(4))")
            if let first = shown.first {
                if first > before.topLine || (shown.count > 1 && shown[1] <= before.topLine && first != before.topLine) {
                    ctx.issue("viewport-jump", "fold all: was looking at line \(before.topLine), but the top of the screen now shows lines \(shown.prefix(3)) — the header that holds line \(before.topLine) should be at the top")
                }
            } else { ctx.issue("coverage", "fold all: nothing visible") }
            let folded = ctx.place()
            await ctx.scrollProbe("fold all")
            ctx.at("unfold all")
            let beforeUnfold = ctx.place()
            ctx.model.send(.unfoldAll); await ctx.settle(500)
            ctx.checkSamePlace(beforeUnfold, "unfold all (the header at the top stays at the top)", tolLines: 0, strictPt: 2)
            if let f = folded, let n = ctx.place(), n.topLine > before.topLine || n.topLine < f.topLine - 1 {
                ctx.issue("viewport-jump", "fold all → unfold all: started at line \(before.topLine), header line \(f.topLine) was at the top while folded, now the top line is \(n.topLine)")
            }
            ctx.checkAll("unfold all"); ctx.checkInk("unfold all"); ctx.snap("unfolded")
            await ctx.scrollProbe("unfold all")
            // 접힌 채로 레이아웃을 바꾼다: 글자 크기 · 사이드바
            ctx.at("fold all again")
            ctx.model.send(.foldAll); await ctx.settle(500)
            await ctx.change("folded: larger text") { ctx.model.adjustFontSize(2) }
            await ctx.change("folded: sidebar closed") { ctx.model.showFileView = false }
            await ctx.change("folded: sidebar open") { ctx.model.showFileView = true }
            await ctx.change("folded: default text size") { ctx.model.font.size = saved.fontSize }
            ctx.snap("folded-end")
            ctx.model.send(.unfoldAll); await ctx.settle(400)
            await saved.restore(ctx)
        },
    ]
}
