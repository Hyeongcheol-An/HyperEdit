import AppKit
import HyperCore

// 실사용 시뮬레이션 — 접기: 접힌 문서에서의 키 이동·편집·찾기·리플로, 큰 접힘, 분할 보기(접힘은 문서 단위), 비밀 블록, 줄바꿈 끔.
// 접힌 문서의 휠 스크롤은 RealUse+Scroll 의 `scroll-folded`, 거터 화살표·표식·선택은 RealUse+Mouse 의 `mouse-fold`·`mouse-foldall`,
// 탭 전환 뒤의 접힘은 RealUse+Tabs 의 `tabs-fold-bookmark`, 글자 크기·사이드바는 RealUse+Layout 의 `layout-fold` 가 본다.

extension RealUseContext {
    /// 그 텍스트 뷰가 그리는 ⋯ 표식 수 (분할의 다른 편집기를 볼 때 — `foldCount()` 는 활성 편집기 것이다)
    func pillCount(in view: HyperTextView) -> Int { view.foldPills?(NSRange(location: 0, length: view.textStorage?.length ?? 0)).count ?? 0 }

    func hidden(line: Int, in view: HyperTextView) -> Bool { view.isOffsetHidden?(lineStart(line)) ?? false }

    /// 화면에 배치된 문단 가운데 접힌(숨어야 할) 것이 없는가 — 숨김이 풀린 채 그려지거나, 펴졌는데 배치가 낡은 경우
    func checkNoHiddenOnScreen(_ why: String, in view: HyperTextView? = nil) {
        let view = view ?? tv
        guard let lm = view.textLayoutManager, let cs = view.textContentStorage, let vr = lm.textViewportLayoutController.viewportRange, !vr.isEmpty else { return }
        var bad = -1
        lm.enumerateTextLayoutFragments(from: vr.location, options: []) { f in
            if f.rangeInElement.location.compare(vr.endLocation) != .orderedAscending { return false }
            let off = cs.offset(from: cs.documentRange.location, to: f.rangeInElement.location)
            if f.layoutFragmentFrame.height > 0, view.isOffsetHidden?(off) == true { bad = off; return false }
            return true
        }
        if bad >= 0 { issue("fold", "\(why): the paragraph at \(place(bad)) is inside a fold but it is laid out on screen") }
        checkShownLaidOut(why, in: view)
    }

    /// 숨지 않은 문단은 전부 배치돼 있는가 — 위 검사의 반대쪽. 숨은 문단은 조각이 아예 없으므로(열거에서 빠진다) "펴고 난 뒤에도 열거에서 빠진 채 남은 줄"은
    /// 높이 0 조각을 찾는 검사로는 보이지 않는다. 배치된 범위에서 이웃한 조각 사이에 빠진 문단이 있으면 그 문단은 숨은 것이어야 하고, 숨지 않은 문단이
    /// 높이 없이(접힌 꼬리의 높이 0 조각·0.01 pt 표시용 문단) 놓여 있어도 안 된다
    func checkShownLaidOut(_ why: String, in view: HyperTextView? = nil) {
        let view = view ?? tv
        guard let lm = view.textLayoutManager, let cs = view.textContentStorage, let ns = view.textStorage?.mutableString else { return }
        if lm.textViewportLayoutController.viewportRange?.isEmpty ?? true { lm.textViewportLayoutController.layoutViewport() }   // 캐럿만 옮긴 직후에는 범위가 비어 있다
        guard let vr = lm.textViewportLayoutController.viewportRange, !vr.isEmpty else { return }
        let start = cs.documentRange.location
        func isHidden(_ o: Int) -> Bool { view.isOffsetHidden?(o) ?? false }
        var previousEnd = -1, seen = 0
        var problem: String?
        lm.enumerateTextLayoutFragments(from: vr.location, options: []) { f in
            if f.rangeInElement.location.compare(vr.endLocation) != .orderedAscending { return false }
            let offset = cs.offset(from: start, to: f.rangeInElement.location)
            var p = previousEnd
            while p >= 0, p < offset {   // 앞 조각과의 사이에 빠진 문단들
                if !isHidden(p) { problem = "the paragraph at \(self.place(p)) is not folded, but it is missing from the layout (between the paragraphs laid out before and after it)"; return false }
                p = NSMaxRange(ns.paragraphRange(for: NSRange(location: p, length: 0)))
            }
            if !isHidden(offset), f.layoutFragmentFrame.height < 2 {
                problem = "the paragraph at \(self.place(offset)) is not folded, but it is laid out \(f.layoutFragmentFrame.height) pt tall (\(Swift.type(of: f))) — it is not on screen"; return false
            }
            previousEnd = cs.offset(from: start, to: f.rangeInElement.endLocation)
            seen += 1
            return seen < 600
        }
        if let problem { issue("fold", "\(why): \(problem)") }
    }

    /// 문서 끝까지 접혀 있으면 마지막으로 보이는 줄(그 접힘의 머리 줄) 아래에 문서 높이가 남아 있지 않은가 — 숨은 꼬리가 자리를 차지하면 그만큼이 빈 띠로
    /// 스크롤된다. 코어의 checkLayout 은 그 경우 머리 줄 아래를 보지 않고, expectBottom 은 문서가 화면보다 길 때만 본다
    func checkFoldedTail(_ why: String) {
        guard let span = tv.foldedSpan?(length), let lm = tv.textLayoutManager, let last = viewportFragments().last, last.offset + last.length >= span.location else { return }
        let band = lm.usageBoundsForTextContainer.maxY + tv.textContainerOrigin.y - last.maxY
        if band > 5 { issue("gap", "\(why): the document is \(String(format: "%.1f", band)) pt taller than its last visible line (the header of the fold that reaches the end) — the hidden lines take up space") }
    }

    /// ⋯ 표식이 제 머리 줄의 글자 오른쪽, 같은 높이에 있는가 (글자와 겹치지 않는가)
    func checkPillsClear(_ why: String) {
        for (rect, hiddenStart) in pillRects() {
            // 머리 줄의 내용 끝 (\r\n 으로 끝나는 줄이면 \r 앞)
            let end = hiddenStart >= 2 && text.character(at: hiddenStart - 2) == 13 ? hiddenStart - 2 : hiddenStart - 1
            guard let r = tv.caretRect(at: end) else { continue }
            if rect.minX < r.maxX + 2 || abs(rect.midY - r.midY) > 3 {
                issue("fold", "\(why): the ⋯ pill of the header ending at \(place(end)) is drawn at x \(Int(rect.minX)) y \(Int(rect.midY)), but that header's text ends at x \(Int(r.maxX)) y \(Int(r.midY))")
                return
            }
        }
    }

    /// 표식 수와 숨김이 맞는가: 보이는 머리 줄의 접힘마다 표식 하나
    func checkFoldState(_ why: String) {
        checkNoHiddenOnScreen(why)
        checkPillsClear(why)
        checkFoldedTail(why)
    }

    /// 그 텍스트 뷰의 화면 맨 위 문단과 그 문단이 위 가장자리에서 떨어진 높이 (분할의 다른 편집기가 보던 곳)
    func topOf(_ view: HyperTextView) -> (offset: Int, inset: CGFloat)? { view.firstVisibleParagraphAnchor() }

    /// 줄 범위의 거터 화살표 상태를 한 번에 (줄 인덱스를 한 번만 만든다 — `marker(atLine:)` 는 부를 때마다 문서 전체를 센다)
    func markers(inLines lines: ClosedRange<Int>) -> [Int: GutterView.FoldMarker] {
        let idx = LineIndex(nsString: text)
        var out: [Int: GutterView.FoldMarker] = [:]
        for line in lines where line >= 1 && line <= idx.lineCount {
            let s = idx.lineStarts[line - 1]
            let e = line < idx.lineCount ? idx.lineStarts[line] : idx.utf16Count
            if let m = gutter?.foldMarker?(s, { e }) { out[line] = m }
        }
        return out
    }

    /// 캐럿이 놓인 줄의 글 (개행 제외)
    func caretLineText() -> String {
        let ns = text
        var r = ns.lineRange(for: NSRange(location: min(caret, ns.length), length: 0))
        if r.length > 0, ns.character(at: NSMaxRange(r) - 1) == 10 { r.length -= 1 }
        return ns.substring(with: r)
    }
}

extension RealUse {
    /// 가운데에 `lines` 줄짜리 들여쓴 영역 하나가 있는 문서 (앞뒤로 `around` 줄씩) — 큰 접힘 하나를 휠로 지나갈 때
    static func bigRegionDoc(lines: Int, around: Int) -> (text: String, header: Int) {
        var s = ""
        for i in 1...around { s += "before \(i) 앞쪽 줄\n" }
        s += "big region:\n"
        for i in 1...lines { s += "    inside \(i) lorem ipsum dolor sit amet\n" }
        for i in 1...around { s += "after \(i) 뒤쪽 줄\n" }
        return (s, around + 1)
    }

    @MainActor static let foldScenarios: [Scenario] = [
        // 모두 접은 1.3 MB 메모에서 Page Down/Up · End · Home · ⌘↓(끝의 접힘이 펴진다) · ⌘↑ · ↓ 연타
        Scenario(name: "fold-keys") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "fold-keys.md") }
            await ctx.settle(900)   // 접기 후보 스캔
            await ctx.key(.up, [.command]); await ctx.settle(200)
            ctx.at("fold all")
            let tFold = CFAbsoluteTimeGetCurrent()
            ctx.model.send(.foldAll); await ctx.settle(0)
            let foldAllMs = (CFAbsoluteTimeGetCurrent() - tFold) * 1000
            await ctx.settle(500)
            guard ctx.foldsActive else { ctx.issue("other", "Fold All folded nothing in the notes corpus"); return }
            ctx.note(String(format: "fold all on the 1.3 MB notes took %.1f ms", foldAllMs))
            // 실측 40~60 ms (정지 감시의 250 ms 문턱은 그대로 둔다) — 그 서너 배를 넘으면 문제로
            if foldAllMs > 200 { ctx.issue("stall", String(format: "fold all on the 1.3 MB notes took %.0f ms", foldAllMs), snap: false) }
            ctx.scrollState("folded"); ctx.checkAll("fold all"); ctx.checkFoldState("fold all")
            ctx.at("Page Down × 10")
            var amounts: [CGFloat] = []
            var worst = 0.0
            for i in 1...10 {
                // 키 큰 화면(아래 패널을 닫은 창)에서는 접힌 문서가 열 쪽이 안 된다 — 끝에 닿았으면 그만 넘긴다. 끝에 닿는 마지막 쪽은 짧으므로 쪽 크기 비교에서 뺀다
                if ctx.visible.maxY >= ctx.tv.frame.height - 1 { ctx.note("folded: the end of the document was reached after \(i - 1) page(s)"); break }
                let a = ctx.edgeAnchor(bottom: true)
                let top0 = ctx.topLine()
                let t0 = CFAbsoluteTimeGetCurrent()
                await ctx.key(.pageDown)
                worst = max(worst, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
                await ctx.settle(250)
                if let m = ctx.moved(since: a) { if ctx.visible.maxY < ctx.tv.frame.height - 1 { amounts.append(m) } } else { ctx.issue("scroll-delta", "folded: Page Down #\(i): the line at the bottom edge of the previous page is not on screen any more (lines were skipped)") }
                if ctx.topLine() <= top0 { ctx.issue("scroll-delta", "folded: Page Down #\(i): top line stayed at \(top0)") }
                ctx.checkAll("folded: Page Down #\(i)"); ctx.checkNoHiddenOnScreen("folded: Page Down #\(i)")
                if i % 5 == 0 { ctx.checkInk("folded: Page Down #\(i)"); ctx.checkPillsClear("folded: Page Down #\(i)") }
            }
            ctx.note("folded Page Down amounts: " + amounts.map { String(format: "%.1f", $0) }.joined(separator: ", ") + String(format: " (viewport %.0f) · slowest key %.1f ms", ctx.visible.height, worst))
            if amounts.count < 3 { ctx.issue("scroll-delta", "folded: only \(amounts.count) full page(s) could be compared before the end of the document — the scenario did not exercise Page Down") }
            if let mn = amounts.min(), let mx = amounts.max(), mx - mn > 2 { ctx.issue("scroll-delta", "folded: Page Down moved by \(String(format: "%.1f", mn))…\(String(format: "%.1f", mx)) pt — pages should be the same size") }
            if worst > 100 { ctx.issue("stall", String(format: "folded: one Page Down took %.0f ms", worst), snap: false) }
            ctx.snap("paged-down")
            ctx.at("End")
            await ctx.key(.end); await ctx.settle(400)
            ctx.scrollState("folded, End")
            ctx.expectBottom("folded: End"); ctx.checkAll("folded: End"); ctx.checkInk("folded: End"); ctx.checkFoldState("folded: End")
            ctx.snap("end")
            ctx.at("Page Up × 4 from the end")
            var ups: [CGFloat] = []
            for i in 1...4 {
                let a = ctx.edgeAnchor(bottom: false)
                await ctx.key(.pageUp); await ctx.settle(250)
                if let m = ctx.moved(since: a) { ups.append(m) } else { ctx.issue("scroll-delta", "folded: Page Up #\(i) from the end: the line at the top edge of the previous page is not on screen any more") }
                ctx.checkAll("folded: Page Up #\(i)"); ctx.checkNoHiddenOnScreen("folded: Page Up #\(i)")
            }
            ctx.note("folded Page Up amounts: " + ups.map { String(format: "%.1f", $0) }.joined(separator: ", "))
            if let mn = ups.min(), let mx = ups.max(), mx - mn > 2 { ctx.issue("scroll-delta", "folded: Page Up moved by \(String(format: "%.1f", -mx))…\(String(format: "%.1f", -mn)) pt — pages should be the same size") }
            ctx.at("Home")
            await ctx.key(.home); await ctx.settle(400)
            ctx.expectTop("folded: Home"); ctx.checkAll("folded: Home"); ctx.checkInk("folded: Home")
            ctx.at("↓ × 40 from the first line (each press lands on the next visible line)")
            await ctx.click(offset: 0); await ctx.settle(100)
            var lastLine = ctx.liveLine(ctx.caret)
            var slowest = 0.0
            for i in 1...40 {
                let t0 = CFAbsoluteTimeGetCurrent()
                await ctx.key(.down)
                slowest = max(slowest, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
                let line = ctx.liveLine(ctx.caret)
                if ctx.hidden(ctx.caret) || line <= lastLine { ctx.issue("fold", "folded: ↓ #\(i): caret went from line \(lastLine) to line \(line) (hidden \(ctx.hidden(ctx.caret)))"); break }
                lastLine = line
                if i % 8 == 0 { await ctx.settle(60); ctx.checkCaretVisible("folded: ↓ #\(i)"); ctx.checkAll("folded: ↓ #\(i)"); ctx.checkNoHiddenOnScreen("folded: ↓ #\(i)") }
            }
            ctx.note(String(format: "folded: ↓ × 40 reached line %d, slowest key %.1f ms", lastLine, slowest))
            ctx.expect(ctx.foldsActive, "fold", "arrow keys over folded headers opened the folds")
            ctx.at("⌘↓ opens the fold at the end of the document")
            await ctx.key(.down, [.command]); await ctx.settle(400)
            ctx.expect(ctx.caret == ctx.length && !ctx.hidden(ctx.caret), "fold", "⌘↓ in a folded document: caret at \(ctx.place(ctx.caret)), hidden \(ctx.hidden(ctx.caret)) (length \(ctx.length))")
            ctx.checkCaretVisible("folded: ⌘↓"); ctx.checkAll("folded: ⌘↓"); ctx.checkInk("folded: ⌘↓"); ctx.checkNoHiddenOnScreen("folded: ⌘↓")
            ctx.expectBottom("folded: ⌘↓")
            ctx.snap("cmd-down")
            ctx.at("⌘↑")
            await ctx.key(.up, [.command]); await ctx.settle(400)
            ctx.expectTop("folded: ⌘↑"); ctx.checkAll("folded: ⌘↑")
            ctx.expect(ctx.foldsActive, "fold", "⌘↑ opened every fold")
            ctx.model.send(.unfoldAll); await ctx.settle(400)
        },

        // 접힌 채 편집: 머리 줄 안·끝의 입력, 머리 줄 끝 Return, 머리 줄 삭제 뒤 되돌리기, 머리 줄 끝 ⌦ · 접힘 아래 줄 머리의 ⌫ (숨은 줄과 합쳐진다), 접힘 위에 줄 넣기
        Scenario(name: "fold-edit") { ctx in
            await ctx.open(text: RealUse.foldDoc(h1: false), name: "fold-edit.md")
            await ctx.settle(600)
            let h5 = RealUse.foldHeader(5), h6 = RealUse.foldHeader(6), h9 = RealUse.foldHeader(9)
            let lines0 = LineIndex(nsString: ctx.text).lineCount
            @MainActor func lineCount() -> Int { LineIndex(nsString: ctx.text).lineCount }
            @MainActor func foldSection(_ header: Int) async {
                ctx.model.jump(toLine: header); await ctx.settle(250)
                if !ctx.hidden(line: header + 1) { ctx.model.send(.fold); await ctx.settle(150) }
            }
            @MainActor func verify(_ why: String) { ctx.checkAllD(why); ctx.checkInk(why); ctx.checkFoldState(why); ctx.checkCaretVisible(why) }

            ctx.at("fold section 5")
            await foldSection(h5)
            ctx.expect(ctx.hidden(line: h5 + 1) && ctx.hidden(line: h5 + 6) && !ctx.hidden(line: h5 + 7) && ctx.foldCount() == 1, "fold", "section 5 did not fold: hidden(\(h5 + 1))=\(ctx.hidden(line: h5 + 1)) pills=\(ctx.foldCount())")
            verify("section 5 folded")

            ctx.at("type in the middle of the folded header")
            await ctx.clickExpect(ctx.lineStart(h5) + 5, "click inside the folded header")
            let y0 = ctx.caretLineScreenY()
            await ctx.type("가나 x"); await ctx.settle(500)   // 다시 스캔된 뒤에도
            ctx.expect(ctx.hidden(line: h5 + 1) && ctx.foldCount() == 1 && ctx.caretLineText().contains("가나 x"), "fold", "typing inside a folded header: folded \(ctx.hidden(line: h5 + 1)), pills \(ctx.foldCount()), line \"\(ctx.caretLineText())\"")
            if let y0, let y1 = ctx.caretLineScreenY(), abs(y1 - y0) > 1 { ctx.issue("viewport-jump", "typing inside a folded header moved its line \(String(format: "%+.1f", y1 - y0)) pt on screen") }
            verify("typed inside a folded header")
            ctx.at("type at the end of the folded header")
            await ctx.key(.right, [.command]); await ctx.type(" 끝"); await ctx.settle(500)
            ctx.expect(ctx.hidden(line: h5 + 1) && ctx.foldCount() == 1 && ctx.caret == ctx.lineEnd(h5), "fold", "typing at the end of a folded header: folded \(ctx.hidden(line: h5 + 1)), caret \(ctx.place(ctx.caret))")
            verify("typed at the end of a folded header")

            ctx.at("Return at the end of the folded header")
            await ctx.key(.returnKey); await ctx.settle(600)
            ctx.note("Return at the end of a folded header: \(lineCount()) lines (was \(lines0)), caret \(ctx.place(ctx.caret)), fold kept \(ctx.hidden(line: h5 + 2)), pills \(ctx.foldCount())")
            ctx.expect(lineCount() == lines0 + 1 && ctx.liveLine(ctx.caret) == h5 + 1 && !ctx.hidden(ctx.caret), "fold", "Return at the end of a folded header: \(lineCount()) lines, caret \(ctx.place(ctx.caret)), hidden \(ctx.hidden(ctx.caret))")
            ctx.expect(ctx.foldCount() == (ctx.hidden(line: h5 + 2) ? 1 : 0), "fold", "Return at the end of a folded header: \(ctx.foldCount()) pills but hidden(\(h5 + 2)) = \(ctx.hidden(line: h5 + 2))")
            verify("Return at the end of a folded header"); ctx.snap("return-at-header-end")
            ctx.at("undo the Return")
            ctx.model.send(.undo); await ctx.settle(600)
            ctx.expect(lineCount() == lines0, "text", "undo of Return: \(lineCount()) lines, expected \(lines0)")
            ctx.expect(ctx.foldCount() == (ctx.hidden(line: h5 + 1) ? 1 : 0), "fold", "after undoing the Return: \(ctx.foldCount()) pills but hidden(\(h5 + 1)) = \(ctx.hidden(line: h5 + 1))")
            verify("undid the Return")

            ctx.at("delete the folded header line, then undo")
            await foldSection(h5)
            let len0 = ctx.length
            ctx.model.textTool(.deleteLine); await ctx.settle(300)
            ctx.expect(ctx.foldCount() == 0 && !ctx.hidden(line: h5) && !ctx.hidden(line: h5 + 1), "fold", "deleting a folded header: pills \(ctx.foldCount()), hidden(\(h5))=\(ctx.hidden(line: h5))")
            verify("deleted a folded header")
            ctx.model.send(.undo); await ctx.settle(600)
            ctx.expect(ctx.length == len0 && ctx.foldCount() == 0, "fold", "undo of the header delete: length \(len0) → \(ctx.length), pills \(ctx.foldCount())")
            verify("undid the header delete")

            ctx.at("⌦ at the end of a folded header joins the first hidden line")
            await foldSection(h6)
            await ctx.clickExpect(ctx.lineStart(h6) + 2, "click the folded header of section 6")
            await ctx.key(.right, [.command])
            let before6 = ctx.length
            await ctx.key(.forwardDelete); await ctx.settle(300)
            ctx.expect(ctx.length == before6 - 1 && ctx.foldCount() == 0 && !ctx.hidden(line: h6 + 1), "fold", "⌦ at the end of a folded header: length \(before6) → \(ctx.length), pills \(ctx.foldCount()), hidden(\(h6 + 1))=\(ctx.hidden(line: h6 + 1))")
            ctx.expect(ctx.caretLineText().contains("first body line of section 6"), "text", "⌦ at the end of a folded header: the line is \"\(ctx.caretLineText())\"")
            verify("⌦ at the end of a folded header"); ctx.snap("joined-header")
            ctx.model.send(.undo); await ctx.settle(600)
            ctx.expect(ctx.length == before6, "text", "undo of ⌦: length \(ctx.length), expected \(before6)")
            verify("undid ⌦")

            ctx.at("⌫ at the start of the line below a fold joins the last hidden line")
            await foldSection(h6)
            if await ctx.clickExpect(ctx.lineStart(h6 + 7), "click the blank line below the fold") {
                let beforeB = ctx.length
                await ctx.key(.delete); await ctx.settle(300)
                ctx.expect(ctx.length == beforeB - 1 && !ctx.hidden(ctx.caret) && !ctx.hidden(line: h6 + 1), "fold", "⌫ below a fold: length \(beforeB) → \(ctx.length), caret \(ctx.place(ctx.caret)) hidden \(ctx.hidden(ctx.caret)), section folded \(ctx.hidden(line: h6 + 1))")
                verify("⌫ below a fold")
                ctx.model.send(.undo); await ctx.settle(600)
                ctx.expect(ctx.length == beforeB, "text", "undo of ⌫: length \(ctx.length), expected \(beforeB)")
                verify("undid ⌫")
            }

            ctx.at("← at the start of the line below a fold goes into the fold (it opens)")
            await foldSection(h6)
            if await ctx.clickExpect(ctx.lineStart(h6 + 7), "click the blank line below the fold") {
                await ctx.key(.left); await ctx.settle(150)
                ctx.expect(ctx.caret == ctx.lineEnd(h6 + 6) && !ctx.hidden(ctx.caret), "fold", "← from the line below a fold: caret \(ctx.place(ctx.caret)) (expected the end of line \(h6 + 6)), hidden \(ctx.hidden(ctx.caret))")
                verify("← into a fold")
            }
            ctx.at("→ at the end of a folded header goes into the fold (it opens)")
            await foldSection(h6)
            await ctx.clickExpect(ctx.lineStart(h6) + 2, "click the folded header of section 6")
            await ctx.key(.right, [.command]); await ctx.key(.right); await ctx.settle(150)
            ctx.expect(ctx.caret == ctx.lineStart(h6 + 1) && !ctx.hidden(ctx.caret), "fold", "→ from the end of a folded header: caret \(ctx.place(ctx.caret)) (expected the start of line \(h6 + 1)), hidden \(ctx.hidden(ctx.caret))")
            verify("→ into a fold")

            ctx.at("insert a line above the folds, then undo")
            await foldSection(h6); await foldSection(h9)
            ctx.expect(ctx.foldCount() == 2, "fold", "expected sections 6 and 9 folded, pills \(ctx.foldCount())")
            ctx.model.send(.perform { tv in tv.breakUndoCoalescing(); tv.insertText("inserted above\n", replacementRange: NSRange(location: 0, length: 0)) })
            await ctx.settle(500)
            ctx.expect(!ctx.hidden(line: h6 + 1) && ctx.hidden(line: h6 + 2) && ctx.hidden(line: h9 + 2) && !ctx.hidden(line: h9 + 8) && ctx.foldCount() == 2, "fold",
                       "a line inserted above: hidden(\(h6 + 1))=\(ctx.hidden(line: h6 + 1)) hidden(\(h6 + 2))=\(ctx.hidden(line: h6 + 2)) hidden(\(h9 + 2))=\(ctx.hidden(line: h9 + 2)) pills \(ctx.foldCount())")
            ctx.checkAllD("a line inserted above the folds"); ctx.checkFoldState("a line inserted above the folds")
            ctx.model.send(.undo); await ctx.settle(600)
            ctx.expect(ctx.hidden(line: h6 + 1) && !ctx.hidden(line: h6) && ctx.hidden(line: h9 + 1) && ctx.foldCount() == 2, "fold",
                       "undo of the inserted line: hidden(\(h6 + 1))=\(ctx.hidden(line: h6 + 1)) hidden(\(h9 + 1))=\(ctx.hidden(line: h9 + 1)) pills \(ctx.foldCount())")
            ctx.checkAllD("undid the inserted line"); ctx.checkFoldState("undid the inserted line")

            ctx.at("fold all and unfold all keep the caret's line at the same height")
            ctx.model.send(.unfoldAll); await ctx.settle(300)
            await ctx.look(atLine: h9 + 3)
            await ctx.clickExpect(ctx.lineStart(h9 + 3) + 6, "click a body line of section 9")
            if let yBody = ctx.caretLineScreenY() {
                ctx.model.send(.foldAll); await ctx.settle(300)
                ctx.expectCaret(ctx.lineEnd(h9), "fold all: the caret moves to the end of its section header")
                let yHeader = ctx.caretLineScreenY()
                ctx.note("fold all: the caret line was at y \(String(format: "%.1f", yBody)); its header is now at \(yHeader.map { String(format: "%.1f", $0) } ?? "off screen")")
                if let yHeader, abs(yHeader - yBody) > 2 { ctx.issue("viewport-jump", "fold all: the caret line was at y \(String(format: "%.1f", yBody)), but the header the caret moved to is at y \(String(format: "%.1f", yHeader))") }
                if yHeader == nil { ctx.issue("caret-hidden", "fold all: the header the caret moved to is not on screen") }
                verify("fold all with the caret in a body line")
                ctx.model.send(.unfoldAll); await ctx.settle(300)
                let yAfter = ctx.caretLineScreenY()
                if let yHeader, let yAfter, abs(yAfter - yHeader) > 2 { ctx.issue("viewport-jump", "unfold all: the caret line was at y \(String(format: "%.1f", yHeader)), now \(String(format: "%.1f", yAfter))") }
                if yAfter == nil { ctx.issue("caret-hidden", "unfold all: the caret line is not on screen") }
                verify("unfold all with the caret on a header")
            } else { ctx.issue("other", "the caret line is not on screen after clicking it") }

            ctx.at("fold all, type at the end of the last header (the fold reaches the end of the document)")
            ctx.model.send(.foldAll); await ctx.settle(300)
            await ctx.key(.end); await ctx.settle(300)
            ctx.expectBottom("small document, everything folded: End"); ctx.checkAllD("everything folded: End"); ctx.checkFoldState("everything folded: End")
            ctx.snap("all-folded-end")
            ctx.model.send(.unfoldAll); await ctx.settle(300)
            ctx.checkAllD("unfold all"); ctx.checkInk("unfold all")
        },

        // 접힌 범위 안의 찾기 결과·줄 이동: 그 접힘만 펴지고 결과가 화면에 보인다
        Scenario(name: "fold-find") { ctx in
            let m = ctx.model
            await ctx.open(text: RealUse.foldDoc(h1: false, sections: 60), name: "fold-find.md")
            await ctx.settle(600)
            await ctx.key(.up, [.command]); await ctx.settle(150)
            ctx.model.send(.foldAll); await ctx.settle(300)
            guard ctx.foldsActive else { ctx.issue("other", "Fold All folded nothing"); return }
            let h41 = RealUse.foldHeader(41), h40 = RealUse.foldHeader(40), h42 = RealUse.foldHeader(42), h20 = RealUse.foldHeader(20)
            ctx.at("find a phrase that is inside a fold")
            m.findInEditor(); await ctx.settle(200)
            var gen = m.searchCompletionCount
            ctx.typeQuery("nested detail b of 41")
            if await ctx.awaitSearch(after: gen), m.searchHits.count == 1 {
                m.jump(to: m.searchHits[0]); await ctx.settle(450)
                let sel = ctx.tv.selectedRange()
                ctx.expectSelectedHit(0, "jumped to the only result")
                ctx.expect(!ctx.hidden(sel.location) && !ctx.hidden(line: h41 + 4), "fold", "the result inside section 41 is still hidden (selection \(ctx.place(sel.location)))")
                ctx.expect(ctx.hidden(line: h40 + 1) && ctx.hidden(line: h42 + 1), "fold", "jumping to a result in section 41 opened its neighbours: hidden(\(h40 + 1))=\(ctx.hidden(line: h40 + 1)) hidden(\(h42 + 1))=\(ctx.hidden(line: h42 + 1))")
                if let r = ctx.tv.caretRect(at: sel.location), !ctx.visible.intersects(r) { ctx.issue("caret-hidden", "the result inside a fold was selected but it is not on screen (y \(Int(r.minY)), visible \(Int(ctx.visible.minY))…\(Int(ctx.visible.maxY)))") }
                ctx.checkAllD("result inside a fold"); ctx.checkInk("result inside a fold"); ctx.checkFoldState("result inside a fold"); ctx.checkHighlightPaint("result inside a fold")
                ctx.snap("result-in-fold")
                await ctx.scrollProbe("result inside a fold", by: 60)
            } else { ctx.issue("find", "the search for a phrase inside a fold found \(m.searchHits.count) results, expected 1") }
            ctx.at("walk through results that are all inside folds")
            m.closeQuickFind(); await ctx.settle(200)
            ctx.model.send(.foldAll); await ctx.settle(300)
            await ctx.key(.up, [.command]); await ctx.settle(150)
            m.findInEditor(); await ctx.settle(200)
            gen = m.searchCompletionCount
            ctx.typeQuery("closing line of section 3")   // 3, 30…39
            if await ctx.awaitSearch(after: gen), m.searchHits.count == 11 {
                for i in 1...6 {
                    m.submitFind(); await ctx.settle(250)
                    let sel = ctx.tv.selectedRange()
                    if sel.length == 0 || ctx.hidden(sel.location) { ctx.issue("fold", "Enter #\(i): the selected result at \(ctx.place(sel.location)) is hidden (length \(sel.length))"); break }
                    if let r = ctx.tv.caretRect(at: sel.location), !ctx.visible.intersects(r) { ctx.issue("caret-hidden", "Enter #\(i): the result at \(ctx.place(sel.location)) is not on screen") }
                    ctx.checkAll("Enter #\(i) through folded results"); ctx.checkNoHiddenOnScreen("Enter #\(i) through folded results")
                }
                ctx.checkInk("after walking through folded results"); ctx.snap("walked-results")
            } else { ctx.issue("find", "'closing line of section 3' found \(m.searchHits.count) results, expected 11") }
            m.closeQuickFind(); await ctx.settle(200)
            ctx.at("go to a line inside a fold")
            ctx.model.send(.foldAll); await ctx.settle(300)
            await ctx.look(atLine: h20 + 3)
            ctx.expect(ctx.liveLine(ctx.caret) == h20 + 3 && !ctx.hidden(ctx.caret) && ctx.hidden(line: h20 - 7), "fold", "go to line \(h20 + 3): caret \(ctx.place(ctx.caret)), hidden \(ctx.hidden(ctx.caret)), the section above still folded \(ctx.hidden(line: h20 - 7))")
            ctx.checkCaretVisible("go to a line inside a fold"); ctx.checkAllD("go to a line inside a fold"); ctx.checkFoldState("go to a line inside a fold")
            ctx.model.send(.unfoldAll); await ctx.settle(300)
        },

        // 1.3 MB 메모에서 몇 군데만 접고 휠로 지나간다, 표식·거터 화살표로 펴고 접을 때 그 위의 줄이 움직이지 않는가
        Scenario(name: "fold-partial") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "fold-partial.md") }
            await ctx.settle(900)
            let mid = RealUse.middleLine(ctx)
            await ctx.look(atLine: mid)
            ctx.at("fold six regions around the middle")
            var folded: [Int] = []
            let arrows = ctx.markers(inLines: (mid - 150)...(mid + 2500))
            var line = mid - 150
            while folded.count < 6, line < mid + 2500 {
                if arrows[line] == .foldable, !ctx.hidden(line: line) {
                    ctx.model.send(.toggleFold(line: line)); await ctx.settle(60)
                    if ctx.hidden(line: line + 1) { folded.append(line) }
                    line += 12
                } else { line += 1 }
            }
            ctx.note("folded the regions at lines \(folded)")
            guard folded.count == 6 else { ctx.issue("other", "could fold only \(folded.count) regions near line \(mid)"); return }
            ctx.checkAll("six regions folded"); ctx.checkFoldState("six regions folded")
            ctx.at("wheel down across the folds")
            await ctx.look(atLine: folded[0] - 40)
            await ctx.wheelRun("partly folded: wheel down", steps: 80, by: 60, deepEvery: 10)
            ctx.checkNoHiddenOnScreen("partly folded: after wheel down")
            ctx.at("rested wheels")
            await ctx.restedSteps("partly folded")
            ctx.at("wheel up across the folds")
            await ctx.wheelRun("partly folded: wheel up", steps: 80, by: -60, deepEvery: 10)
            ctx.checkNoHiddenOnScreen("partly folded: after wheel up"); ctx.snap("wheeled")
            ctx.at("unfold by clicking a ⋯ pill: the lines above it stay")
            await ctx.look(atLine: folded[2] - 6)
            if let pill = ctx.pillRects().first(where: { ctx.visible.insetBy(dx: 0, dy: 30).contains(NSPoint(x: $0.0.midX, y: $0.0.midY)) }) {
                let before = ctx.place()
                let headerLine = ctx.liveLine(pill.1 - 1)
                let y0 = ctx.screenY(ofFragmentAt: ctx.lineStart(headerLine))
                await ctx.mclick(atViewPoint: NSPoint(x: pill.0.midX, y: pill.0.midY)); await ctx.settle(250)
                ctx.expect(!ctx.hidden(line: headerLine + 1), "fold", "clicking the pill of line \(headerLine) did not unfold it")
                ctx.checkSamePlace(before, "unfold by pill (the top line stays)", tolLines: 0, strictPt: 2)
                if let y0, let y1 = ctx.screenY(ofFragmentAt: ctx.lineStart(headerLine)), abs(y1 - y0) > 2 { ctx.issue("viewport-jump", "unfold by pill: the header moved \(String(format: "%+.1f", y1 - y0)) pt on screen") }
                ctx.checkAll("unfold by pill"); ctx.checkInk("unfold by pill"); ctx.checkFoldState("unfold by pill")
                await ctx.scrollProbe("unfold by pill")
                ctx.at("fold it again by its gutter arrow: the header stays under the mouse")
                if let p = ctx.foldArrowPoint(forLine: headerLine) {
                    let b2 = ctx.place()
                    let y2 = ctx.screenY(ofFragmentAt: ctx.lineStart(headerLine))
                    await ctx.clickGutter(at: p); await ctx.settle(250)
                    ctx.expect(ctx.hidden(line: headerLine + 1), "fold", "clicking the gutter arrow of line \(headerLine) did not fold it")
                    ctx.checkSamePlace(b2, "fold by gutter arrow (the top line stays)", tolLines: 0, strictPt: 2)
                    if let y2, let y3 = ctx.screenY(ofFragmentAt: ctx.lineStart(headerLine)), abs(y3 - y2) > 2 { ctx.issue("viewport-jump", "fold by gutter arrow: the header moved \(String(format: "%+.1f", y3 - y2)) pt on screen") }
                    ctx.checkAll("fold by gutter arrow"); ctx.checkInk("fold by gutter arrow"); ctx.checkFoldState("fold by gutter arrow")
                    await ctx.scrollProbe("fold by gutter arrow")
                } else { ctx.issue("fold", "no gutter row for line \(headerLine)") }
            } else { ctx.issue("fold", "no ⋯ pill on screen near line \(folded[2])") }
            ctx.at("fold a region above the screen with the caret inside it: the header comes to the top")
            ctx.model.send(.unfoldAll); await ctx.settle(300)
            // 화면보다 긴 영역에서, 머리 줄이 화면 위로 나가게 25줄 넘게 내려간 본문 줄(더 안쪽 영역에는 들지 않는 줄)을 눌러 캐럿을 두고 접는다.
            // 그런 줄은 영역 스캐너로 직접 찾는다 — 거터 화살표만 보고 찾으면(화살표 없는 줄이 40줄 이어지는 곳) 이 말뭉치에는 없어서 이 걸음이 돌지 않았다
            let index = LineIndex(nsString: ctx.text)
            let regions = FoldScanner.regions(in: ctx.text, index: index, isMarkdown: true)
            var target: (header: Int, line: Int)?
            for r in regions where r.startLine >= mid && r.hiddenLineCount >= 40 {
                let body = ((r.startLine + 25)...(r.endLine - 2)).first { l in index.range(ofLine: l).length > 1 && FoldScanner.innermostRegion(containingLine: l, in: regions) == r }
                if let body { target = (r.startLine, body); break }
            }
            if let target {
                await ctx.look(atLine: target.line)
                await ctx.clickExpect(ctx.lineStart(target.line), "click a body line of the long region")
                ctx.expect(ctx.screenY(ofFragmentAt: ctx.lineStart(target.header)) == nil, "other", "the header (line \(target.header)) of the long region is still on screen with the caret on line \(target.line)")
                ctx.model.send(.fold); await ctx.settle(300)
                ctx.note("folded with the caret on line \(target.line) (header \(target.header)): caret now \(ctx.place(ctx.caret)), top line \(ctx.topLine())")
                ctx.expect(ctx.hidden(line: target.header + 1) && ctx.caret == ctx.lineEnd(target.header) && !ctx.hidden(ctx.caret), "fold",
                           "fold at the caret: region of line \(target.header) folded \(ctx.hidden(line: target.header + 1)), caret \(ctx.place(ctx.caret)) (expected the end of line \(target.header)), hidden \(ctx.hidden(ctx.caret))")
                ctx.checkCaretVisible("fold at the caret with the header above the screen"); ctx.checkAll("fold at the caret with the header above the screen")
                ctx.checkFoldState("fold at the caret with the header above the screen"); ctx.snap("fold-at-caret")
                await ctx.scrollProbe("fold at the caret")
            } else { ctx.issue("other", "no region of 40 or more lines after line \(mid) with a body line of its own — the fold-above-the-screen step did not run") }
            ctx.model.send(.unfoldAll); await ctx.settle(300)
        },

        // 접힌 채 리플로: 창 폭 · 줄 번호 · 줄바꿈 켬/끔 — 보던 줄이 유지되는가, 멈추지 않는가 (글자 크기·사이드바는 layout-fold)
        Scenario(name: "fold-reflow") { ctx in
            let saved = ViewDefaults(ctx)
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "fold-reflow.md") }
            await ctx.settle(900)
            await ctx.look(atLine: middleLine(ctx), wheel: 400)
            ctx.at("fold all")
            ctx.model.send(.foldAll); await ctx.settle(500)
            guard ctx.foldsActive else { ctx.issue("other", "Fold All folded nothing"); await saved.restore(ctx); return }
            ctx.checkAll("fold all"); ctx.checkFoldState("fold all"); ctx.snap("folded")
            let f0 = ctx.window.frame
            func frame(dw: CGFloat) -> NSRect { NSRect(x: f0.minX, y: f0.minY, width: f0.width + dw, height: f0.height) }
            await ctx.change("folded: window 300 pt narrower") { ctx.window.setFrame(frame(dw: -300), display: true) }
            ctx.checkFoldState("folded: narrower"); ctx.snap("narrow")
            await ctx.change("folded: window back to the original width") { ctx.window.setFrame(f0, display: true) }
            ctx.at("folded: drag the window edge")
            var before = ctx.place()
            for i in 1...12 { ctx.window.setFrame(frame(dw: CGFloat(-20 * i)), display: true); await ctx.turn() }
            await ctx.settle(350)
            ctx.checkSamePlace(before, "folded: dragged the window edge 240 pt narrower"); ctx.checkAll("folded: drag narrower"); ctx.checkInk("folded: drag narrower")
            before = ctx.place()
            for i in (0..<12).reversed() { ctx.window.setFrame(frame(dw: CGFloat(-20 * i)), display: true); await ctx.turn() }
            await ctx.settle(350)
            ctx.checkSamePlace(before, "folded: dragged the window edge back"); ctx.checkAll("folded: drag wider"); ctx.checkInk("folded: drag wider")
            await ctx.change("folded: line numbers off") { ctx.model.showLineNumbers = false }
            await ctx.change("folded: line numbers on") { ctx.model.showLineNumbers = true }
            // 캐럿을 화면의 머리 줄에 두고: 캐럿 줄이 그 높이에 남아야 한다
            if let a = ctx.anchor() { await ctx.click(offset: a.offset); await ctx.settle(100) }
            await ctx.change("folded, caret on screen: larger text") { ctx.model.adjustFontSize(3) }
            ctx.checkFoldState("folded: larger text"); ctx.snap("large")
            await ctx.change("folded, caret on screen: default text size") { ctx.model.font.size = saved.fontSize }
            await ctx.change("folded: word wrap off", tolLines: 0) { ctx.model.wordWrap = false }
            ctx.checkFoldState("folded: wrap off"); ctx.snap("nowrap")
            await ctx.change("folded: word wrap on", tolLines: 0) { ctx.model.wordWrap = true }
            ctx.checkFoldState("folded: wrap on")
            ctx.expect(ctx.foldsActive, "fold", "the folds were lost during the layout changes")
            ctx.at("unfold all after the layout changes")
            let y0 = ctx.caretLineScreenY()
            ctx.model.send(.unfoldAll); await ctx.settle(500)
            // 캐럿 줄이 화면 밖으로 밀려나는 것이 이 걸음이 잡으려는 결함이다 — 그때는 높이를 잴 수 없으므로(nil) 그것 자체를 문제로 센다
            if let y0 {
                if let y1 = ctx.caretLineScreenY() {
                    if abs(y1 - y0) > 2 { ctx.issue("viewport-jump", "unfold all: the caret line was at y \(String(format: "%.1f", y0)), now \(String(format: "%.1f", y1))") }
                } else { ctx.issue("caret-hidden", "unfold all: the caret line was on screen at y \(String(format: "%.1f", y0)) and is not on screen any more (caret \(ctx.place(ctx.caret)), visible \(Int(ctx.visible.minY))…\(Int(ctx.visible.maxY)))") }
            } else { ctx.issue("other", "unfold all: the caret line is not on screen before the command — the caret-height check cannot run") }
            ctx.checkAll("unfold all"); ctx.checkInk("unfold all")
            await ctx.scrollProbe("unfold all")
            await saved.restore(ctx)
        },

        // 큰 접힘: 문서 끝까지 닿는 12,000줄 접힘 하나(한 줄만 남는다) · 문서 전체를 거느리는 제목 · 가운데의 16,000줄 영역을 휠로 지나가기
        Scenario(name: "fold-giant") { ctx in
            // 첫 줄 아래가 전부 들여쓴 줄 — 접으면 첫 줄 하나만 남고, 접힘이 문서 끝까지 닿는다
            var whole = "everything below is one region:\n"
            for i in 1...12_000 { whole += "    inside \(i) lorem ipsum dolor sit amet\n" }
            await ctx.withRelaxedStalls { await ctx.open(text: whole, name: "fold-giant.txt") }
            await ctx.settle(1200)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            let total = LineIndex(nsString: ctx.text).lineCount
            ctx.at("fold the first line's region: one line is left")
            await ctx.click(offset: 3); await ctx.settle(100)
            var t0 = CFAbsoluteTimeGetCurrent()
            ctx.model.send(.fold); await ctx.settle(0)
            let foldMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            await ctx.settle(300)
            ctx.expect(ctx.hidden(line: 2) && ctx.hidden(line: total - 1) && ctx.hidden(ctx.length) && ctx.foldCount() == 1, "fold",
                       "folding the whole document: hidden(2)=\(ctx.hidden(line: 2)) hidden(\(total - 1))=\(ctx.hidden(line: total - 1)) end hidden \(ctx.hidden(ctx.length)) pills \(ctx.foldCount())")
            let shown = ctx.viewportFragments().count
            ctx.note(String(format: "folded %d lines under one line in %.1f ms; %d paragraph(s) laid out, document height %.0f, viewport %.0f", total - 1, foldMs, shown, ctx.tv.frame.height, ctx.visible.height))
            ctx.expect(shown == 1, "fold", "with the whole document folded under line 1, \(shown) paragraphs are laid out")
            if ctx.tv.frame.height > ctx.visible.height + 1 { ctx.issue("viewport-jump", "one visible line, but the document is \(Int(ctx.tv.frame.height)) pt tall (viewport \(Int(ctx.visible.height))) — it scrolls into nothing") }
            if foldMs > 120 { ctx.issue("stall", String(format: "folding %d lines took %.0f ms", total - 1, foldMs), snap: false) }
            ctx.checkAllD("whole document folded"); ctx.checkInk("whole document folded"); ctx.checkFoldState("whole document folded"); ctx.snap("one-line")
            ctx.at("type on the only visible line")
            await ctx.key(.right, [.command])
            t0 = CFAbsoluteTimeGetCurrent()
            await ctx.type(" typing here")
            let perKey = (CFAbsoluteTimeGetCurrent() - t0) * 1000 / 12
            await ctx.settle(500)
            ctx.note(String(format: "typing on the header of a %d-line fold: %.1f ms/key (incl. one run-loop turn)", total - 1, perKey))
            ctx.expect(ctx.hidden(line: 2) && ctx.caretLineText().hasSuffix(" typing here"), "fold", "typing on the header of the giant fold: folded \(ctx.hidden(line: 2)), line \"\(ctx.caretLineText())\"")
            if perKey > 16 { ctx.issue("stall", String(format: "typing on the header of a %d-line fold takes %.1f ms per key", total - 1, perKey), snap: false) }
            ctx.checkAllD("typed on the giant fold's header"); ctx.checkCaretVisible("typed on the giant fold's header")
            ctx.at("↓ stays on the header (the fold reaches the end)")
            await ctx.key(.down); await ctx.settle(100)
            ctx.expect(ctx.liveLine(ctx.caret) == 1 && !ctx.hidden(ctx.caret) && ctx.hidden(line: 2), "fold", "↓ on the header of a fold that reaches the end: caret \(ctx.place(ctx.caret)), folded \(ctx.hidden(line: 2))")
            ctx.at("End and Home do not move a one-line document")
            await ctx.key(.end); await ctx.settle(200); ctx.checkAllD("giant fold: End")
            if ctx.visible.minY > 0.5 { ctx.issue("viewport-jump", "giant fold: End scrolled a one-line document to y \(String(format: "%.1f", ctx.visible.minY))") }
            await ctx.key(.home); await ctx.settle(200); ctx.expectTop("giant fold: Home")
            ctx.at("unfold")
            t0 = CFAbsoluteTimeGetCurrent()
            ctx.model.send(.unfold); await ctx.settle(0)
            let unfoldMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            await ctx.settle(300)
            ctx.note(String(format: "unfolded %d lines in %.1f ms", total - 1, unfoldMs))
            ctx.expect(!ctx.hidden(line: 2) && !ctx.hidden(ctx.length) && ctx.foldCount() == 0, "fold", "unfolding left hidden(2)=\(ctx.hidden(line: 2)) pills \(ctx.foldCount())")
            if unfoldMs > 120 { ctx.issue("stall", String(format: "unfolding %d lines took %.0f ms", total - 1, unfoldMs), snap: false) }
            ctx.checkAllD("giant fold opened"); ctx.checkInk("giant fold opened"); ctx.expectTop("giant fold opened")
            await ctx.scrollProbe("giant fold opened")
            ctx.at("⌘↓ after folding again opens it and shows the last line")
            await ctx.click(offset: 3); await ctx.settle(100)
            ctx.model.send(.fold); await ctx.settle(300)
            await ctx.key(.down, [.command]); await ctx.settle(400)
            ctx.expect(ctx.caret == ctx.length && !ctx.hidden(ctx.caret) && ctx.foldCount() == 0, "fold", "⌘↓ into a fold that reaches the end: caret \(ctx.place(ctx.caret)), hidden \(ctx.hidden(ctx.caret)), pills \(ctx.foldCount())")
            ctx.checkCaretVisible("⌘↓ into the giant fold"); ctx.checkAllD("⌘↓ into the giant fold"); ctx.checkInk("⌘↓ into the giant fold"); ctx.expectBottom("⌘↓ into the giant fold")
            // 명령으로 편 직후의 ⌘↓ 도 끝에 닿아야 한다. 끝까지 닿는 접힘이 펴진 직후에는 마지막 문단의 조각이 접혀 있던 때의 자리(머리 줄 바로 아래)에 남아,
            // AppKit 이 그 줄을 화면에 있다고 보고 스크롤하지 않았다 (HyperTextView.revealDocumentEndIfMissed). 높이 어림이 배치하는 동안 다시 잡히는 실행에서는
            // 드러나지 않는다 — 앞에서 돈 시나리오에 달려 있어(다른 문서를 스크롤한 뒤에 났다) 전체 묶음과 `--only scroll-knob-state,fold-giant` 에서 본다
            ctx.at("⌘↓ right after unfolding with the command")
            await ctx.key(.up, [.command]); await ctx.settle(200)
            await ctx.click(offset: 3); await ctx.settle(100)
            ctx.model.send(.fold); await ctx.settle(300)
            ctx.model.send(.unfold); await ctx.settle(300)
            ctx.expect(ctx.foldCount() == 0 && !ctx.hidden(line: 2), "fold", "unfolding with the command left pills \(ctx.foldCount())")
            await ctx.key(.down, [.command]); await ctx.settle(400)
            ctx.expect(ctx.caret == ctx.length, "fold", "⌘↓ after unfolding: caret \(ctx.place(ctx.caret))")
            ctx.checkAllD("⌘↓ after unfolding"); ctx.checkInk("⌘↓ after unfolding"); ctx.expectBottom("⌘↓ after unfolding")

            // 문서 전체를 거느리는 # 제목 (24,000줄; 끝의 빈 줄은 영역 밖이라 두 줄이 남는다)
            await ctx.withRelaxedStalls { await ctx.open(text: RealUse.foldDoc(h1: true, sections: 3000), name: "fold-giant.md") }
            await ctx.settle(1200)
            ctx.at("fold all under a top heading")
            await ctx.key(.up, [.command]); await ctx.settle(200)
            t0 = CFAbsoluteTimeGetCurrent()
            ctx.model.send(.foldAll); await ctx.settle(0)
            let allMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            await ctx.settle(400)
            // 실측 약 40 ms (펴기 약 50 ms) — 그 서너 배를 넘으면 문제로. 정지 감시는 풀지 않는다
            if allMs > 150 { ctx.issue("stall", String(format: "fold all with 6,001 nested regions took %.0f ms", allMs), snap: false) }
            let left = ctx.viewportFragments().count
            ctx.note(String(format: "fold all (6,001 regions nested under one heading) took %.1f ms; %d paragraph(s) laid out, document height %.0f", allMs, left, ctx.tv.frame.height))
            ctx.expect(ctx.hidden(line: 2) && left <= 2 && ctx.foldCount() == 1, "fold", "fold all under a top heading: hidden(2)=\(ctx.hidden(line: 2)), \(left) paragraphs laid out, \(ctx.foldCount()) visible pill(s)")
            ctx.checkAllD("fold all under a top heading"); ctx.checkInk("fold all under a top heading"); ctx.checkFoldState("fold all under a top heading"); ctx.snap("top-heading")
            ctx.at("unfold all under a top heading")
            t0 = CFAbsoluteTimeGetCurrent()
            ctx.model.send(.unfoldAll); await ctx.settle(0)
            let unfoldAllMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            ctx.note(String(format: "unfold all took %.1f ms", unfoldAllMs))
            if unfoldAllMs > 180 { ctx.issue("stall", String(format: "unfold all with 6,001 nested regions took %.0f ms", unfoldAllMs), snap: false) }
            await ctx.settle(400)
            ctx.checkAllD("unfold all under a top heading"); ctx.checkInk("unfold all under a top heading"); ctx.expectTop("unfold all under a top heading")

            // 가운데의 큰 영역 하나
            let big = RealUse.bigRegionDoc(lines: 16_000, around: 400)
            await ctx.withRelaxedStalls { await ctx.open(text: big.text, name: "fold-giant-mid.txt") }
            await ctx.settle(1200)
            ctx.at("fold a 16,000-line region in the middle and wheel across it")
            await ctx.look(atLine: big.header - 10)
            ctx.model.send(.toggleFold(line: big.header)); await ctx.settle(300)
            ctx.expect(ctx.hidden(line: big.header + 1) && ctx.hidden(line: big.header + 16_000) && !ctx.hidden(line: big.header + 16_001), "fold", "the big region did not fold: hidden(\(big.header + 1))=\(ctx.hidden(line: big.header + 1))")
            ctx.checkAll("big region folded"); ctx.checkFoldState("big region folded"); ctx.snap("big-folded")
            await ctx.wheelRun("big fold: wheel down across it", steps: 30, by: 60, deepEvery: 10)
            await ctx.wheelRun("big fold: wheel up across it", steps: 30, by: -60, deepEvery: 10)
            ctx.at("jump to the end and back with the big fold")
            await ctx.key(.end); await ctx.settle(400)
            ctx.expectBottom("big fold: End"); ctx.checkAll("big fold: End"); ctx.checkInk("big fold: End")
            await ctx.wheelRun("big fold: wheel up from the end", steps: 30, by: -60, deepEvery: 10)
            await ctx.key(.home); await ctx.settle(400)
            ctx.expectTop("big fold: Home")
            // 긴 영역의 한가운데에서 접는다: 문서가 384,000 pt 줄어 스크롤 위치가 새 문서 끝을 한참 넘긴 채 첫 배치가 돈다
            ctx.at("fold the big region from deep inside it")
            ctx.model.send(.toggleFold(line: big.header)); await ctx.settle(300)   // 펴고
            await ctx.look(atLine: big.header + 8_000)
            if let a = ctx.anchor() { await ctx.click(offset: a.offset); await ctx.settle(100) }
            let t1 = CFAbsoluteTimeGetCurrent()
            ctx.model.send(.fold); await ctx.settle(0)
            let deepMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000
            await ctx.settle(300)
            ctx.note(String(format: "folding a 16,000-line region with the caret 8,000 lines inside it took %.1f ms; top line now %d, caret %@", deepMs, ctx.topLine(), ctx.place(ctx.caret)))
            ctx.expect(ctx.hidden(line: big.header + 1) && ctx.caret == ctx.lineEnd(big.header), "fold", "fold from deep inside: hidden \(ctx.hidden(line: big.header + 1)), caret \(ctx.place(ctx.caret))")
            if deepMs > 120 { ctx.issue("stall", String(format: "folding a 16,000-line region from deep inside it took %.0f ms", deepMs), snap: false) }
            ctx.checkCaretVisible("fold from deep inside"); ctx.checkAll("fold from deep inside"); ctx.checkInk("fold from deep inside"); ctx.checkFoldState("fold from deep inside")
            await ctx.scrollProbe("fold from deep inside")
            ctx.at("unfold the big region: the header stays")
            await ctx.look(atLine: big.header - 5)
            let before = ctx.place()
            ctx.model.send(.toggleFold(line: big.header)); await ctx.settle(300)
            ctx.checkSamePlace(before, "unfold the big region (the top line stays)", tolLines: 0, strictPt: 2)
            ctx.checkAll("big region opened"); ctx.checkInk("big region opened")
            await ctx.scrollProbe("big region opened")

            // 작은 영역이 아주 많은 문서(두 줄짜리 영역 15,000개)를 끝 쪽에서 모두 접는다: 문서가 절반으로 줄어 스크롤 위치가 새 문서 끝을 넘긴 채 첫 배치가 돌고,
            // 접은 뒤에도 보이는 문단이 15,000개다
            var many = ""
            for i in 1...15_000 { many += "item \(i):\n    detail of item \(i) lorem ipsum\n" }
            await ctx.withRelaxedStalls { await ctx.open(text: many, name: "fold-many.txt") }
            await ctx.settle(1500)
            ctx.at("fold all near the end of a document with 15,000 small regions")
            await ctx.look(atLine: 29_001)
            if let a = ctx.anchor() { await ctx.click(offset: a.offset); await ctx.settle(100) }
            let caretLine = ctx.liveLine(ctx.caret)
            let t2 = CFAbsoluteTimeGetCurrent()
            ctx.model.send(.foldAll); await ctx.settle(0)
            let manyMs = (CFAbsoluteTimeGetCurrent() - t2) * 1000
            await ctx.settle(400)
            ctx.note(String(format: "fold all (15,000 regions, caret on line %d): %.1f ms; top line now %d, document height %.0f", caretLine, manyMs, ctx.topLine(), ctx.tv.frame.height))
            ctx.expect(ctx.foldsActive && !ctx.hidden(ctx.caret), "fold", "fold all with 15,000 regions: folded \(ctx.foldsActive), caret hidden \(ctx.hidden(ctx.caret))")
            if manyMs > 250 { ctx.issue("stall", String(format: "fold all near the end of a document with 15,000 small regions took %.0f ms", manyMs), snap: false) }
            ctx.checkCaretVisible("fold all, 15,000 regions"); ctx.checkAll("fold all, 15,000 regions"); ctx.checkInk("fold all, 15,000 regions"); ctx.checkFoldState("fold all, 15,000 regions")
            // 스크롤바 옆 띠는 접힌 머리 줄마다 눈금을 그린다(여기서는 15,000개) — 스크롤 걸음마다 다시 그려지면 걸음이 그만큼 느려진다 (실측: 걸음당 13.7 ms 가운데 10 ms)
            let strip = (ctx.scroll.superview as? EditorContainerView)?.markerView as? ScrollMarkerView
            let draws0 = strip?.debugDrawCount ?? 0
            await ctx.wheelRun("15,000 folds: wheel up", steps: 20, by: -60, deepEvery: 10)
            if let strip {
                let draws = strip.debugDrawCount - draws0
                ctx.note("15,000 folds: the scroll marker strip was drawn \(draws) time(s) during 20 wheel steps")
                // 문서 높이 어림이 바뀌면(100 ms 로 묶어) 다시 그리는 것은 정상이다 — 걸음마다 그리면 20번을 넘는다
                if draws > 8 { ctx.issue("stall", "the scroll marker strip was redrawn \(draws) times during 20 wheel steps — it draws a tick for each of the 15,000 folds every time", snap: false) }
            } else { ctx.issue("other", "no scroll marker strip to watch during the wheel run") }
            let t3 = CFAbsoluteTimeGetCurrent()
            ctx.model.send(.unfoldAll); await ctx.settle(0)
            let manyUnfoldMs = (CFAbsoluteTimeGetCurrent() - t3) * 1000
            await ctx.settle(400)
            ctx.note(String(format: "unfold all (15,000 regions): %.1f ms", manyUnfoldMs))
            if manyUnfoldMs > 250 { ctx.issue("stall", String(format: "unfold all of 15,000 small regions took %.0f ms", manyUnfoldMs), snap: false) }
            ctx.checkAll("unfold all, 15,000 regions"); ctx.checkInk("unfold all, 15,000 regions")   // 캐럿은 휠로 화면 밖에 두었다 — 맨 위 줄이 지켜진다
        },

        // 분할 보기: 접힘은 문서의 것이다 — 한쪽에서 접으면 양쪽이 접히고, 다른 쪽은 보던 곳이 그대로다. 어느 쪽에서 편집·되돌리기를 해도 접힘은 한 번만 옮겨진다
        Scenario(name: "fold-split") { ctx in
            let m = ctx.model
            await ctx.open(text: RealUse.foldDoc(h1: false, sections: 60), name: "fold-split.md")
            await ctx.settle(600)
            m.setSplit(.vertical); await ctx.settle(900)
            guard let p = m.session.primary?.textView, let s = m.session.secondary?.textView, p !== s else { ctx.issue("other", "the split did not produce two editors"); return }
            let h10 = RealUse.foldHeader(10), h30 = RealUse.foldHeader(30)
            @MainActor func focus(_ view: HyperTextView) async { ctx.window.makeFirstResponder(view); await ctx.settle(60) }
            @MainActor func sameFolds(_ why: String) {
                for i in [1, 10, 30, 59] {
                    let l = RealUse.foldHeader(i) + 1
                    if ctx.hidden(line: l, in: p) != ctx.hidden(line: l, in: s) { ctx.issue("fold", "\(why): line \(l) is hidden in one editor and shown in the other"); return }
                }
                if ctx.pillCount(in: p) != ctx.pillCount(in: s) { ctx.issue("fold", "\(why): \(ctx.pillCount(in: p)) pills in the primary, \(ctx.pillCount(in: s)) in the secondary") }
            }
            // 보조 편집기는 30번 구역을 보고, 캐럿을 그 본문 줄에 둔다
            await focus(s)
            m.jump(toLine: h30 + 3); await ctx.settle(400)
            s.setSelectedRange(NSRange(location: ctx.lineStart(h30 + 3) + 4, length: 0))
            await focus(p)
            m.jump(toLine: h10); await ctx.settle(400)
            ctx.at("fold in the primary: the secondary folds too and keeps its place")
            let top0 = ctx.topOf(s)
            m.send(.fold); await ctx.settle(300)
            ctx.expect(ctx.hidden(line: h10 + 1, in: p) && ctx.hidden(line: h10 + 1, in: s) && ctx.pillCount(in: p) == 1 && ctx.pillCount(in: s) == 1, "fold",
                       "fold in the primary: hidden primary \(ctx.hidden(line: h10 + 1, in: p)) secondary \(ctx.hidden(line: h10 + 1, in: s)), pills \(ctx.pillCount(in: p)) / \(ctx.pillCount(in: s))")
            if let a = top0, let b = ctx.topOf(s), a.offset != b.offset || abs(a.inset - b.inset) > 1 {
                ctx.issue("viewport-jump", "folding a section above in the other editor moved the secondary: top paragraph \(ctx.place(a.offset)) inset \(String(format: "%.1f", a.inset)) → \(ctx.place(b.offset)) inset \(String(format: "%.1f", b.inset))")
            }
            ctx.checkAllD("primary after the fold"); ctx.checkNoHiddenOnScreen("secondary after the fold", in: s); ctx.snap("fold-in-primary")
            ctx.at("fold all from the primary: the secondary's caret leaves the hidden line, its view stays on that section")
            m.send(.foldAll); await ctx.settle(400)
            sameFolds("fold all")
            let sCaret = s.selectedRange()
            ctx.expect(sCaret.length == 0 && sCaret.location == ctx.lineEnd(h30) && !(s.isOffsetHidden?(sCaret.location) ?? true), "fold",
                       "fold all from the primary: the secondary's caret is at \(ctx.place(sCaret.location)) (expected the end of header \(h30))")
            if let b = ctx.topOf(s) {
                let topLine = ctx.liveLine(b.offset)
                ctx.note("secondary after fold all: top line \(topLine) (was looking at section 30, header line \(h30))")
                if topLine > h30 || topLine < h30 - 8 * 20 { ctx.issue("viewport-jump", "fold all from the other editor: the secondary was looking at section 30 (line \(h30)), now its top line is \(topLine)") }
            }
            ctx.checkAllD("primary after fold all"); ctx.checkNoHiddenOnScreen("secondary after fold all", in: s); ctx.snap("fold-all")
            ctx.at("typing in the secondary moves the shared folds once")
            await focus(s)
            s.breakUndoCoalescing()
            s.insertText("typed in the secondary\n", replacementRange: NSRange(location: 0, length: 0)); await ctx.settle(200)
            @MainActor func shifted(_ by: Int) -> Bool { [1, 10, 30, 59].allSatisfy { i in ctx.hidden(line: RealUse.foldHeader(i) + 1 + by, in: p) && !ctx.hidden(line: RealUse.foldHeader(i) + by, in: p) && !ctx.hidden(line: RealUse.foldHeader(i) + 7 + by, in: p) } }
            ctx.expect(shifted(1), "fold", "a line typed at the top in the secondary: the folds did not move by exactly one line (hidden(\(h10 + 2))=\(ctx.hidden(line: h10 + 2, in: p)), hidden(\(h10 + 1))=\(ctx.hidden(line: h10 + 1, in: p)))")
            sameFolds("typed in the secondary")
            await ctx.settle(500)   // 다시 스캔된 뒤에도
            ctx.expect(shifted(1), "fold", "after the rescan the folds are not where they were (typed in the secondary)")
            ctx.at("undo from the primary moves them back once")
            await focus(p)
            m.send(.undo); await ctx.settle(600)
            ctx.expect(shifted(0), "fold", "undo from the primary: the folds did not move back by exactly one line (hidden(\(h10 + 1))=\(ctx.hidden(line: h10 + 1, in: p)), hidden(\(h10))=\(ctx.hidden(line: h10, in: p)))")
            sameFolds("undo from the primary")
            ctx.at("redo from the secondary, undo from the secondary")
            await focus(s)
            m.send(.redo); await ctx.settle(600)
            ctx.expect(shifted(1), "fold", "redo from the secondary: the folds did not move by exactly one line")
            m.send(.undo); await ctx.settle(600)
            ctx.expect(shifted(0), "fold", "undo from the secondary: the folds did not move back by exactly one line")
            sameFolds("redo and undo from the secondary")
            ctx.at("typing in the primary moves them once too")
            await focus(p)
            p.breakUndoCoalescing()
            p.insertText("typed in the primary\n", replacementRange: NSRange(location: 0, length: 0)); await ctx.settle(600)
            ctx.expect(shifted(1), "fold", "a line typed at the top in the primary: the folds did not move by exactly one line")
            m.send(.undo); await ctx.settle(600)
            ctx.expect(shifted(0), "fold", "undo of the primary's line: the folds did not move back")
            ctx.at("the caret entering a hidden line in the secondary opens the fold in both")
            await focus(s)
            s.setSelectedRange(NSRange(location: ctx.lineStart(h10 + 3) + 2, length: 0)); await ctx.settle(300)
            ctx.expect(!ctx.hidden(line: h10 + 1, in: p) && !ctx.hidden(line: h10 + 1, in: s) && ctx.hidden(line: h30 + 1, in: p), "fold",
                       "caret on a hidden line in the secondary: hidden primary \(ctx.hidden(line: h10 + 1, in: p)) secondary \(ctx.hidden(line: h10 + 1, in: s))")
            sameFolds("caret entered a fold in the secondary")
            ctx.checkNoHiddenOnScreen("primary after the secondary opened a fold", in: p); ctx.checkNoHiddenOnScreen("secondary after it opened a fold", in: s)
            ctx.at("close the split: the folds stay; open it again: the new editor shows them")
            await focus(p)
            m.setSplit(.none); await ctx.settle(800)
            ctx.expect(ctx.hidden(line: h30 + 1) && ctx.foldCount() > 0, "fold", "closing the split lost the folds (pills \(ctx.foldCount()))")
            ctx.checkAllD("split closed"); ctx.checkInk("split closed"); ctx.checkFoldState("split closed")
            let pills = ctx.foldCount()
            m.setSplit(.vertical); await ctx.settle(900)
            if let s2 = m.session.secondary?.textView {
                ctx.expect(ctx.pillCount(in: s2) == pills && ctx.hidden(line: h30 + 1, in: s2), "fold", "the reopened secondary shows \(ctx.pillCount(in: s2)) pills, the primary \(pills)")
                ctx.checkNoHiddenOnScreen("reopened secondary", in: s2)
            } else { ctx.issue("other", "the split did not reopen") }
            ctx.snap("reopened")
            m.send(.unfoldAll); await ctx.settle(300)
            m.setSplit(.none); await ctx.settle(700)
        },

        // 비밀 블록(가림막)과 접기는 같은 레이아웃 delegate 를 쓴다: 접으면 가린 줄도 숨고, 펴면 다시 가려져 있다. 문서 끝의 비밀 블록을 품은 접힘도
        Scenario(name: "fold-secret") { ctx in
            var text = "notes before the block\nline two 둘째 줄\n\n```secret\npassword: hunter2\ntoken = abcdef123456\n한글 비밀 줄 secret\n```\n\nnotes after the block\n"
            for i in 1...40 { text += "filler line \(i) 채움 줄\n" }
            text += "## last section\nabove the block\n```secret\nlast secret line\n```\n"
            await ctx.open(text: text, name: "fold-secret.md")
            await ctx.settle(700)
            // 가리기가 꺼져 있으면 켜고 한다 (건너뛰면 이 시나리오가 아무것도 보지 않은 채 0건이 된다)
            let maskWasOn = ctx.model.secrets.maskEnabled
            if !maskWasOn { ctx.model.secrets.maskEnabled = true; await ctx.settle(400) }
            defer { if !maskWasOn { ctx.model.secrets.maskEnabled = false } }
            guard ctx.model.secrets.maskEnabled else { ctx.issue("other", "secret masking could not be turned on — the scenario did not run"); return }
            let total = LineIndex(nsString: ctx.text).lineCount            // 마지막 빈 줄 포함
            let lastSecret = total - 2                                     // "last secret line"
            @MainActor func masked(_ line: Int) -> Bool { ctx.tv.isOffsetMasked?(ctx.lineStart(line)) ?? false }
            @MainActor func fragmentKind(_ line: Int) -> String {
                guard let lm = ctx.tv.textLayoutManager, let cs = ctx.tv.textContentStorage, let loc = cs.location(cs.documentRange.location, offsetBy: ctx.lineStart(line)) else { return "none" }
                lm.ensureLayout(for: NSTextRange(location: loc))
                guard let f = lm.textLayoutFragment(for: loc) else { return "none" }
                return f is MaskedLayoutFragment ? "masked" : (f is FoldedLayoutFragment ? "folded" : "plain")
            }
            ctx.at("masked as opened")
            await ctx.key(.up, [.command]); await ctx.settle(200)   // 새로 연 문서는 끝에서 열린다
            await ctx.clickExpect(ctx.lineStart(1) + 3, "click the first line")
            ctx.expect(masked(5) && masked(7) && !masked(4) && masked(lastSecret) && fragmentKind(5) == "masked", "secret", "mask state: lines 4…8 \((4...8).map { masked($0) }), last secret \(masked(lastSecret)), fragment of line 5 \(fragmentKind(5))")
            ctx.at("fold the secret block by its fence line")
            ctx.model.send(.toggleFold(line: 4)); await ctx.settle(250)
            ctx.expect(ctx.hidden(line: 5) && ctx.hidden(line: 7) && ctx.foldCount() == 1 && fragmentKind(5) == "none", "fold", "folding the secret block: hidden(5)=\(ctx.hidden(line: 5)) hidden(7)=\(ctx.hidden(line: 7)) pills \(ctx.foldCount()) fragment \(fragmentKind(5))")
            ctx.checkAllD("secret block folded"); ctx.checkInk("secret block folded"); ctx.checkFoldState("secret block folded"); ctx.snap("folded")
            ctx.at("unfold: the block is masked again")
            ctx.model.send(.toggleFold(line: 4)); await ctx.settle(250)
            ctx.expect(!ctx.hidden(line: 5) && masked(5) && masked(7) && fragmentKind(5) == "masked" && fragmentKind(4) == "plain", "secret", "after unfolding: hidden(5)=\(ctx.hidden(line: 5)) masked \((5...7).map { masked($0) }) fragments \(fragmentKind(4))/\(fragmentKind(5))")
            ctx.checkAllD("secret block unfolded"); ctx.checkInk("secret block unfolded"); ctx.snap("unfolded")
            ctx.at("fold all: the last section (with its secret block) is folded to the end")
            ctx.model.send(.foldAll); await ctx.settle(300)
            await ctx.key(.end); await ctx.settle(300)
            ctx.expect(ctx.hidden(line: lastSecret) && ctx.hidden(ctx.length), "fold", "fold all: the last secret line hidden \(ctx.hidden(line: lastSecret)), end hidden \(ctx.hidden(ctx.length))")
            ctx.expectBottom("secret document, everything folded: End"); ctx.checkAllD("everything folded: End"); ctx.checkInk("everything folded: End"); ctx.checkFoldState("everything folded: End")
            ctx.snap("all-folded-end")
            ctx.at("unfold all: every block is masked, nothing is left collapsed")
            ctx.model.send(.unfoldAll); await ctx.settle(300)
            await ctx.key(.end); await ctx.settle(300)
            ctx.expect(masked(5) && masked(lastSecret) && fragmentKind(lastSecret) == "masked" && fragmentKind(total - 1) == "plain", "secret",
                       "after unfold all: masked(5)=\(masked(5)) last secret \(masked(lastSecret)) fragments \(fragmentKind(lastSecret))/\(fragmentKind(total - 1))")
            ctx.expectBottom("secret document unfolded: End"); ctx.checkAllD("unfold all"); ctx.checkInk("unfold all"); ctx.snap("unfolded-end")
        },

        // 줄바꿈 끔: 접기·휠·끝/처음 — 접기 전의 같은 걸음과 견준다 (줄바꿈 끔 자체의 문제는 다른 영역)
        Scenario(name: "fold-nowrap") { ctx in
            let saved = ViewDefaults(ctx)
            await ctx.open(text: RealUse.foldDoc(h1: false, sections: 150), name: "fold-nowrap.md")
            await ctx.settle(600)
            ctx.model.wordWrap = false; await ctx.settle(600)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            ctx.at("wrap off, not folded: wheel (the reference)")
            let n0 = ctx.issues.count
            await ctx.wheelRun("wrap off, unfolded: wheel down", steps: 30, by: 40, deepEvery: 10)
            await ctx.wheelRun("wrap off, unfolded: wheel up", steps: 30, by: -40, deepEvery: 10)
            let reference = ctx.issues.count - n0
            if reference > 0 { ctx.note("wrap off shows \(reference) issue(s) before anything is folded — those are not fold defects") }
            ctx.at("wrap off: fold all")
            await ctx.key(.up, [.command]); await ctx.settle(200)
            ctx.model.send(.foldAll); await ctx.settle(400)
            guard ctx.foldsActive else { ctx.issue("other", "Fold All folded nothing"); await saved.restore(ctx); return }
            ctx.checkAllD("wrap off: fold all"); ctx.checkInk("wrap off: fold all"); ctx.checkFoldState("wrap off: fold all"); ctx.snap("folded")
            await ctx.wheelRun("wrap off, folded: wheel down", steps: 30, by: 40, deepEvery: 10)
            ctx.checkNoHiddenOnScreen("wrap off, folded: after wheel down")
            await ctx.wheelRun("wrap off, folded: wheel up", steps: 30, by: -40, deepEvery: 10)
            ctx.expectTop("wrap off, folded: after the round trip")
            ctx.at("wrap off, folded: End and Home")
            await ctx.key(.end); await ctx.settle(400)
            ctx.expectBottom("wrap off, folded: End"); ctx.checkAllD("wrap off, folded: End"); ctx.checkInk("wrap off, folded: End"); ctx.snap("folded-end")
            await ctx.key(.home); await ctx.settle(400)
            ctx.expectTop("wrap off, folded: Home")
            ctx.at("wrap off: unfold one section by its gutter arrow, fold it again")
            let h4 = RealUse.foldHeader(4)
            if let pt = ctx.foldArrowPoint(forLine: h4) {
                await ctx.clickGutter(at: pt); await ctx.settle(200)
                ctx.expect(!ctx.hidden(line: h4 + 1), "fold", "wrap off: the gutter arrow of line \(h4) did not unfold it")
                ctx.checkAllD("wrap off: one section opened"); ctx.checkFoldState("wrap off: one section opened")
                if let pt2 = ctx.foldArrowPoint(forLine: h4) { await ctx.clickGutter(at: pt2); await ctx.settle(200) }
                ctx.expect(ctx.hidden(line: h4 + 1), "fold", "wrap off: the gutter arrow of line \(h4) did not fold it again")
                ctx.checkAllD("wrap off: folded again"); ctx.checkFoldState("wrap off: folded again")
            } else { ctx.issue("fold", "wrap off: no gutter row for line \(h4)") }
            ctx.at("turn wrap on with everything folded")
            ctx.model.wordWrap = true; await ctx.settle(600)
            ctx.expect(ctx.foldsActive && ctx.hidden(line: h4 + 1), "fold", "turning word wrap on lost the folds")
            ctx.checkAllD("wrap on, folded"); ctx.checkInk("wrap on, folded"); ctx.checkFoldState("wrap on, folded")
            ctx.model.send(.unfoldAll); await ctx.settle(300)
            ctx.checkAllD("unfold all"); ctx.checkInk("unfold all")
            await saved.restore(ctx)
        },
    ] + foldGuardScenarios + foldGuard2Scenarios   // 접힌 글 지키기 (RealUse+FoldGuard.swift, RealUse+FoldGuard2.swift)
}
