import AppKit
import HyperCore

// 실사용 시뮬레이션 — 화면 가장자리에서의 입력: 맨 아랫줄에서 Enter·글자·한글 조합·붙여넣기로 캐럿이 아래 가장자리를 넘을 때, 맨 윗줄에서 Backspace 로
// 윗줄과 합쳐 위 가장자리를 넘을 때, 화면은 **넘은 만큼만** 따라가야 한다 (다른 에디터처럼 한두 줄).
//
// 배경(2026-11-25 실측): AppKit(TextKit 2)은 편집 직후 `scrollRangeToVisible` 로 캐럿을 보이게 하는데, 캐럿 줄이 화면 밖이면 그 줄을 화면 가운데쯤으로
// 데려간다 — 382 pt 화면의 맨 아랫줄에서 Enter 한 번에 213 pt, 글자를 쳐서 줄이 감기는 순간 192 pt 가 밀렸다. 방향키는 지난 라운드에 고쳤고
// (HyperTextView.revealCaretStep) 이 시나리오들은 입력 경로를 본다.

extension RealUseContext {
    /// 화면에 온전히 보이는 맨 아래(위) 문단
    func edgeParagraph(bottom: Bool) -> Frag? {
        let v = visible
        let inside = viewportFragments().filter { $0.minY >= v.minY - 0.5 && $0.maxY <= v.maxY + 0.5 }
        return bottom ? inside.last : inside.first
    }

    /// 캐럿 줄의 화면 높이 (뷰포트 위 가장자리로부터의 위·아래)
    func caretOnScreen() -> (top: CGFloat, bottom: CGFloat)? {
        guard let r = tv.caretRect(at: caret) else { return nil }
        return (r.minY - visible.minY, r.maxY - visible.minY)
    }

    /// 편집 한 번(키 하나)을 하고 화면이 캐럿을 따라 **필요한 만큼만** 움직였는지 본다:
    /// 캐럿 줄이 온전히 보이고, 화면이 움직였다면 캐럿 쪽으로 `maxLines` 줄 이내이며 캐럿 줄이 넘어온 가장자리에 붙어 있다(더 밀지 않았다).
    /// `mustStay`: 캐럿이 가장자리를 넘지 않는 편집 — 화면이 움직이면 안 된다. 반환: 내용이 화면에서 움직인 양(+ = 아래로 스크롤), 잴 수 없으면 nil
    @discardableResult
    func edgeEdit(_ why: String, maxLines: CGFloat = 1, mustStay: Bool = false, _ edit: () async -> Void) async -> CGFloat? {
        let v0 = visible
        let lh = lineHeight
        let caret0 = caret
        // 닻: 캐럿보다 앞에서 시작하는 문단 가운데 화면 가운데에 가장 가까운 것. 편집은 캐럿 자리(또는 그 바로 앞 글자)에서 일어나므로 그 앞에서 시작하는 문단은
        // 오프셋도 위 가장자리의 자리도 그대로다 — 화면에서 움직였다면 스크롤된 것이다. 캐럿 아래의 문단을 닻으로 삼으면 Enter·줄 합치기·줄 감김으로 줄 수가
        // 바뀔 때마다 한 줄씩 밀려 '스크롤됐다'로 잘못 잰다 (실측: 맨 윗줄 머리의 Enter 가 −24 pt 로 기록됐다)
        let a = viewportFragments().filter { $0.offset < caret0 }
            .min(by: { abs($0.minY - v0.minY - v0.height / 2) < abs($1.minY - v0.minY - v0.height / 2) })
            .map { (offset: $0.offset, y: $0.minY - v0.minY) }
        await edit()
        await quiesce()
        let moved = a.flatMap { a in screenY(ofFragmentAt: a.offset).map { a.y - $0 } }
        let v = visible
        checkCaretLineWhole(why)
        guard let r = tv.caretRect(at: caret) else { return moved }
        let top = r.minY - v.minY, bottom = r.maxY - v.minY
        let inset = tv.textContainerInset.height
        let atStart = v.minY < 0.5, atEnd = v.maxY > tv.frame.height - 1
        // 캐럿 앞에서 시작하는 배치된 문단이 없으면(맨 윗줄이 위 가장자리에 붙어 있다) 양은 잴 수 없다 — 부른 쪽이 캐럿 줄의 화면 높이로 본다
        guard a != nil else { checkLayout(why); return nil }
        guard let m = moved else {
            issue("viewport-jump", "\(why): the paragraph above the caret is gone after one edit — the view jumped (caret line now at screen y \(Int(top))…\(Int(bottom)) of \(Int(v.height)))")
            return nil
        }
        if mustStay {
            if abs(m) > 0.5 { issue("viewport-jump", "\(why): the caret did not leave the screen but the content moved \(String(format: "%.1f", m)) pt (caret line now at y \(Int(top))…\(Int(bottom)) of \(Int(v.height)))") }
        } else if abs(m) > 0.5 {
            let limit = maxLines * lh + 1 + ((atStart || atEnd) ? inset + 4 : 0)
            if abs(m) > limit {
                issue("viewport-jump", "\(why): one edit moved the content by \(String(format: "%.1f", m)) pt on screen — at most \(String(format: "%.1f", limit)) pt (\(Int(maxLines)) line) is needed to keep the caret line in view (caret line now at y \(Int(top))…\(Int(bottom)) of \(Int(v.height)))")
            } else {
                // 필요한 만큼만: 캐럿 줄이 넘어온 가장자리에 붙어 있다 (문서 처음·끝에서는 여백만큼 떨어진다)
                let gap = m > 0 ? v.height - bottom : top
                if gap > 1 + ((atStart || atEnd) ? inset + 4 : 0) {
                    issue("viewport-jump", "\(why): the view followed the caret by \(String(format: "%.1f", m)) pt but the caret line sits \(String(format: "%.1f", gap)) pt inside the \(m > 0 ? "bottom" : "top") edge — more was scrolled than needed")
                }
            }
        }
        checkLayout(why)
        return moved
    }

    /// 화면에 온전히 보이는 맨 아래 문단의 끝(개행 앞)을 클릭해 캐럿을 놓는다. 반환: 놓았는가
    func clickEndOfBottomLine(_ what: String) async -> Bool {
        guard let f = edgeParagraph(bottom: true) else { issue("other", "\(what): no whole paragraph on screen"); return false }
        let ns = text
        var end = f.offset + f.length
        if end > f.offset, end <= ns.length, ns.character(at: end - 1) == 10 { end -= 1 }
        return await clickCaret(end, what)
    }
}

extension RealUse {
    @MainActor static let scrollEdgeScenarios: [Scenario] = [
        // 큰 메모 가운데, 화면 맨 아랫줄: Enter · 글자(줄이 감김) · 한글 조합 · 조합 확정과 Enter 가 한 키 · 여러 줄 붙여넣기
        Scenario(name: "typing-edge-bottom") { ctx in
            let issues0 = ctx.issues.count   // 이 시나리오에서 난 문제만 센다 — 앞 시나리오가 남긴 문제(정지 한 번의 행 묶음 등)로 걸음을 건너뛰지 않게
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "edge-bottom.md") }
            ctx.model.jump(toLine: 9000); await ctx.settle(500)
            let expect = NSMutableString(string: ctx.textCopy() as String)
            // 맨 아랫줄의 바로 윗줄에서 Enter: 새 줄이 들어갈 자리가 있다 — 화면은 그대로여야 한다 (편집 직후의 캐럿 줄 자리는 추정이라 한 줄 아래로 재어진다)
            ctx.at("Enter one line above the bottom line")
            var at = 0
            let v0 = ctx.visible
            let whole = ctx.viewportFragments().filter { $0.minY >= v0.minY - 0.5 && $0.maxY <= v0.maxY + 0.5 }
            if whole.count > 3, v0.maxY - whole[whole.count - 2].maxY > ctx.lineHeight + 1 {
                let f = whole[whole.count - 2]
                at = f.offset + f.length - 1
                if await ctx.clickCaret(at, "the end of the line above the bottom line") {
                    _ = await ctx.edgeEdit("Enter one line above the bottom line", mustStay: true, { await ctx.press(.returnKey) })
                    expect.insert("\n", at: at); at += 1
                    _ = await ctx.edgeEdit("Backspace taking that line back", mustStay: true, { await ctx.press(.delete) })
                    at -= 1; expect.deleteCharacters(in: NSRange(location: at, length: 1))
                    ctx.checkTyped(expect, caret: at, "Enter and Backspace one line above the bottom line")
                }
            } else { ctx.issue("other", "Enter one line above the bottom line: there is no room for one more line under the second-to-last paragraph on screen — the step did not run") }

            ctx.at("click the end of the bottom line")
            guard await ctx.clickEndOfBottomLine("the end of the bottom line") else { return }
            at = ctx.caret
            if let c = ctx.caretOnScreen() { ctx.note(String(format: "caret line at screen y %.1f…%.1f of a %.0f pt viewport", c.top, c.bottom, ctx.visible.height)) }

            ctx.at("Enter × 6 on the bottom line")
            var amounts: [CGFloat] = []
            for i in 1...6 {
                if let m = await ctx.edgeEdit("Enter \(i) on the bottom line", { await ctx.press(.returnKey) }) { amounts.append(m) }
                expect.insert("\n", at: at); at += 1
            }
            ctx.note("Enter on the bottom line moved the content by " + amounts.map { String(format: "%.1f", $0) }.joined(separator: ", ") + " pt")
            // 첫 Enter 뒤로는 캐럿 줄이 아래 가장자리에 붙어 있다 — 그 뒤의 Enter 는 정확히 한 줄씩 민다
            for (i, m) in amounts.enumerated().dropFirst() where abs(m - ctx.lineHeight) > 1 {
                ctx.issue("viewport-jump", "Enter \(i + 1) on the bottom line moved the content by \(String(format: "%.1f", m)) pt, expected one line (\(String(format: "%.1f", ctx.lineHeight)))")
            }
            ctx.checkTyped(expect, caret: at, "6 × Enter on the bottom line"); ctx.checkInk("6 × Enter on the bottom line")
            ctx.snap("after-enters")

            ctx.at("type until the bottom line wraps")
            var wraps = 0
            let filler = "typing along the bottom line until it wraps to the next visual line and keeps going for a while after that "
            for (i, ch) in (filler + filler).enumerated() {
                let m = await ctx.edgeEdit("character \(i + 1) on the bottom line", { await ctx.typeKeys(String(ch)) })
                expect.insert(String(ch), at: at); at += 1
                if let m, abs(m) > 0.5 { wraps += 1 }
                if ctx.issues.count - issues0 > 12 { break }
            }
            ctx.note("typing \(filler.count * 2) characters on the bottom line scrolled the view \(wraps) time(s)")
            if wraps == 0 { ctx.issue("other", "typing \(filler.count * 2) characters on the bottom line never wrapped past the bottom edge — the scenario did not exercise the wrap") }
            ctx.checkTyped(expect, caret: at, "typed past the wrap on the bottom line"); ctx.checkInk("typed past the wrap on the bottom line")
            ctx.snap("after-wrap")

            ctx.at("compose Hangul until the bottom line wraps")
            _ = await ctx.edgeEdit("Enter before composing", { await ctx.press(.returnKey) })
            expect.insert("\n", at: at); at += 1
            wraps = 0
            let ko = "맨 아랫줄에서 한글을 조합하며 줄 끝을 넘긴다 조합 중인 글자가 다음 줄로 감겨도 화면은 한 줄만 따라와야 한다 그리고 계속 쓴다"
            for (i, ch) in ko.enumerated() {
                if ("가"..."힣").contains(ch) {
                    // 조합 단계(밑줄 상태)와 확정을 따로 본다 — 줄을 넘기는 것은 조합 단계다
                    let m1 = await ctx.edgeEdit("composing syllable \(i + 1) on the bottom line", { await ctx.composeOnly(ch) })
                    let m2 = await ctx.edgeEdit("committing syllable \(i + 1) on the bottom line", { await ctx.commitComposition(ch) })
                    if abs(m1 ?? 0) > 0.5 || abs(m2 ?? 0) > 0.5 { wraps += 1 }
                } else {
                    if let m = await ctx.edgeEdit("character \(i + 1) between syllables", { await ctx.typeKeys(String(ch)) }), abs(m) > 0.5 { wraps += 1 }
                }
                expect.insert(String(ch), at: at); at += (String(ch) as NSString).length
                if ctx.issues.count - issues0 > 12 { break }
            }
            ctx.note("composing \(ko.count) characters on the bottom line scrolled the view \(wraps) time(s)")
            if wraps == 0 { ctx.issue("other", "composing on the bottom line never wrapped past the bottom edge — the scenario did not exercise the wrap") }
            if ctx.tv.hasMarkedText() { ctx.issue("ime", "marked text is still pending after the last syllable was committed") }
            ctx.checkTyped(expect, caret: at, "composed past the wrap on the bottom line"); ctx.checkInk("composed past the wrap on the bottom line")
            ctx.snap("after-hangul")

            // 조합 중에 Return: 입력기는 한 키 안에서 조합을 확정(insertText)하고 줄을 바꾼다(insertNewline:)
            ctx.at("commit and Enter in one key")
            await ctx.composeOnly("끝")
            _ = await ctx.edgeEdit("commit + Enter in one key on the bottom line", {
                ctx.tv.insertText("끝", replacementRange: NSRange(location: NSNotFound, length: 0))
                ctx.tv.doCommand(by: #selector(NSResponder.insertNewline(_:)))
                await ctx.turn(); await ctx.pumpEvent()
            })
            expect.insert("끝\n", at: at); at += 2
            ctx.checkTyped(expect, caret: at, "commit + Enter in one key")

            ctx.at("Tab and Backspace on the bottom line")
            _ = await ctx.edgeEdit("Tab on the bottom line", mustStay: true, { await ctx.press(.tab) })
            expect.insert("\t", at: at); at += 1
            _ = await ctx.edgeEdit("Backspace on the bottom line", mustStay: true, { await ctx.press(.delete) })
            at -= 1; expect.deleteCharacters(in: NSRange(location: at, length: 1))
            // 빈 맨 아랫줄에서 Backspace: 윗줄 끝으로 올라간다 — 그 줄은 이미 보이므로 화면은 그대로다
            _ = await ctx.edgeEdit("Backspace joining the empty bottom line", mustStay: true, { await ctx.press(.delete) })
            at -= 1; expect.deleteCharacters(in: NSRange(location: at, length: 1))
            ctx.checkTyped(expect, caret: at, "Tab and Backspace on the bottom line")

            // 붙여넣기는 입력기 확정과 같은 경로(insertText)다 — 클립보드는 건드리지 않는다
            ctx.at("paste three lines on the bottom line")
            let three = " pasted one\npasted two\npasted three"
            _ = await ctx.edgeEdit("pasting three lines on the bottom line", maxLines: 2, {
                ctx.tv.insertText(three, replacementRange: NSRange(location: NSNotFound, length: 0)); await ctx.pumpEvent()
            })
            expect.insert(three, at: at); at += (three as NSString).length
            ctx.checkTyped(expect, caret: at, "pasted three lines on the bottom line"); ctx.checkInk("pasted three lines on the bottom line")
            ctx.snap("after-paste-3")

            // 한 화면이 넘는 붙여넣기: 캐럿이 멀리 간다 — 얼마나 미는지는 정하지 않고(AppKit 그대로) 캐럿이 보이는지만 본다
            ctx.at("paste sixty lines")
            let sixty = "\n" + (1...60).map { "pasted far \($0)" }.joined(separator: "\n")
            ctx.tv.insertText(sixty, replacementRange: NSRange(location: NSNotFound, length: 0)); await ctx.pumpEvent(); await ctx.quiesce()
            expect.insert(sixty, at: at); at += (sixty as NSString).length
            ctx.checkTyped(expect, caret: at, "pasted sixty lines"); ctx.checkCaretLineWhole("pasted sixty lines"); ctx.checkInk("pasted sixty lines")

            // 되돌리기는 캐럿을 멀리 옮긴다 — 지금 동작(보이게만) 그대로
            ctx.at("undo the big paste")
            await ctx.undo(); await ctx.quiesce(); await ctx.settle(200)
            ctx.checkCaretVisible("⌘Z after the big paste"); ctx.checkAll("⌘Z after the big paste"); ctx.checkInk("⌘Z after the big paste")
            ctx.snap("end")
            await ctx.settle(600)
            ctx.checkLineCount("0.6 s after the edge edits"); ctx.checkGutter("0.6 s after the edge edits")
        },

        // 화면 맨 윗줄: Backspace 로 윗줄(화면 위로 잘려 있다)과 합치기, Delete 로 아랫줄 당기기, 맨 윗줄 머리의 Enter
        Scenario(name: "typing-edge-top") { ctx in
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "edge-top.md") }
            ctx.model.jump(toLine: 7000); await ctx.settle(500)
            // 맨 위 문단이 위 가장자리에 반쯤 잘리게 굴려 둔다
            await ctx.scrollBy(ctx.lineHeight * 6 + 11); await ctx.settle(200)
            let expect = NSMutableString(string: ctx.textCopy() as String)
            ctx.at("Backspace at the head of the top line")
            guard let f = ctx.edgeParagraph(bottom: false) else { ctx.issue("other", "no whole paragraph on screen"); return }
            ctx.note(String(format: "top whole paragraph at screen y %.1f (the one above it is cut by the top edge)", f.minY - ctx.visible.minY))
            guard await ctx.clickCaret(f.offset, "the head of the top line") else { return }
            var at = f.offset
            // 윗줄 끝으로 올라간다: 그 줄(잘려 있던 문단의 마지막 줄)이 다 보일 만큼만 위로
            let up = await ctx.edgeEdit("Backspace joining the top line to the one above", { await ctx.press(.delete) })
            at -= 1; expect.deleteCharacters(in: NSRange(location: at, length: 1))
            if let up, up > 0.5 { ctx.issue("viewport-jump", "Backspace at the head of the top line moved the content \(String(format: "%.1f", up)) pt the wrong way") }
            ctx.checkTyped(expect, caret: at, "Backspace joined the top line"); ctx.checkInk("Backspace joined the top line")
            ctx.snap("joined-top")

            ctx.at("type and delete on the top line")
            for (i, ch) in "top line words".enumerated() {
                _ = await ctx.edgeEdit("character \(i + 1) on the top line", mustStay: true, { await ctx.typeKeys(String(ch)) })
                expect.insert(String(ch), at: at); at += 1
            }
            _ = await ctx.edgeEdit("Backspace on the top line", mustStay: true, { await ctx.press(.delete) })
            at -= 1; expect.deleteCharacters(in: NSRange(location: at, length: 1))
            ctx.checkTyped(expect, caret: at, "typed on the top line")

            // 윗줄이 화면 위로 완전히 나가 있을 때: 한 줄만 올라온다
            ctx.at("Backspace when the line above is fully hidden")
            if let top = ctx.edgeParagraph(bottom: false) {
                let dy = top.minY - ctx.visible.minY
                if dy > 0.5 { await ctx.scrollBy(dy.rounded()); await ctx.settle(150) }
            }
            if let top = ctx.edgeParagraph(bottom: false), top.minY - ctx.visible.minY < 1.5, await ctx.clickCaret(top.offset, "the head of the top line, flush with the top edge") {
                at = top.offset
                _ = await ctx.edgeEdit("Backspace joining the top line to the hidden line above", { await ctx.press(.delete) })
                at -= 1; expect.deleteCharacters(in: NSRange(location: at, length: 1))
                // 위에 배치된 문단이 없어 양을 잴 닻이 없다 — 올라온 줄이 위 가장자리에 붙어 있으면 한 줄만 올라온 것이다
                if let c = ctx.caretOnScreen() {
                    ctx.note(String(format: "the line above came into view: caret line at screen y %.1f…%.1f", c.top, c.bottom))
                    if c.top > 1.5 { ctx.issue("viewport-jump", "Backspace at the head of the top line: the line above was brought \(String(format: "%.1f", c.top)) pt below the top edge — more was scrolled than needed") }
                }
                ctx.checkTyped(expect, caret: at, "Backspace joined the hidden line above"); ctx.checkInk("Backspace joined the hidden line above")
            } else { ctx.issue("other", "Backspace when the line above is fully hidden: could not put a paragraph flush with the top edge — the step did not run") }

            // Delete(앞으로 지우기)로 아랫줄을 당긴다: 캐럿은 제자리 — 화면도 제자리
            ctx.at("forward delete at the end of the top line")
            await ctx.press(.down, [.option]); await ctx.quiesce()   // ⌥↓: 문단 끝 (⌘→ 는 감긴 줄의 끝에서 멈춘다)
            at = ctx.caret
            if at < expect.length, expect.character(at: at) == 10, let c = ctx.caretOnScreen(), c.top > -0.5, c.bottom < ctx.visible.height + 0.5 {
                _ = await ctx.edgeEdit("Delete pulling the next line up to the top line", mustStay: true, { await ctx.press(.forwardDelete) })
                expect.deleteCharacters(in: NSRange(location: at, length: 1))
                ctx.checkTyped(expect, caret: at, "Delete joined the next line")
            } else { ctx.issue("other", "forward delete at the end of the top line: ⌥↓ did not land on a visible paragraph end — the step did not run") }

            // 맨 윗줄 머리에서 Enter: 글이 아래로 밀리고 캐럿은 한 줄 내려간다 — 화면은 그대로
            ctx.at("Enter at the head of the top line")
            if let top = ctx.edgeParagraph(bottom: false), await ctx.clickCaret(top.offset, "the head of the top line (2)") {
                at = top.offset
                let y0 = ctx.caretOnScreen()?.top ?? 0
                _ = await ctx.edgeEdit("Enter at the head of the top line", mustStay: true, { await ctx.press(.returnKey) })
                expect.insert("\n", at: at); at += 1
                ctx.checkTyped(expect, caret: at, "Enter at the head of the top line")
                // 맨 윗줄이 위 가장자리에 붙어 있으면 그 앞에 닻으로 삼을 문단이 없다 — 캐럿 줄이 한 줄 내려갔는지로 본다
                if let c = ctx.caretOnScreen(), abs(c.top - (y0 + ctx.lineHeight)) > 1 {
                    ctx.issue("viewport-jump", "Enter at the head of the top line: the caret line went from screen y \(String(format: "%.1f", y0)) to \(String(format: "%.1f", c.top)), expected one line down — the view moved")
                }
                // 다시 지운다: 캐럿이 맨 윗줄(방금 생긴 빈 줄)로 올라간다 — 보이는 줄이므로 그대로
                _ = await ctx.edgeEdit("Backspace removing the new line", mustStay: true, { await ctx.press(.delete) })
                at -= 1; expect.deleteCharacters(in: NSRange(location: at, length: 1))
                ctx.checkTyped(expect, caret: at, "Backspace removed the new line")
                if let c = ctx.caretOnScreen(), abs(c.top - y0) > 1 {
                    ctx.issue("viewport-jump", "Backspace removing the new first line: the caret line is at screen y \(String(format: "%.1f", c.top)), it was at \(String(format: "%.1f", y0)) before the Enter — the view moved")
                }
            }
            ctx.checkInk("top edge edits")
            ctx.snap("end")
            await ctx.settle(600)
            ctx.checkLineCount("0.6 s after the top edge edits"); ctx.checkGutter("0.6 s after the top edge edits")
        },

        // 문서 끝 가까이(끝에서 몇 줄 위)의 맨 아랫줄: 넘은 만큼만 밀다가 문서 끝에 닿으면 끝에 붙는다. 그리고 여러 번 감기는 문단
        Scenario(name: "typing-edge-end") { ctx in
            let issues0 = ctx.issues.count   // 이 시나리오에서 난 문제만 센다 — 앞 시나리오가 남긴 문제(정지 한 번의 행 묶음 등)로 걸음을 건너뛰지 않게
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "edge-end.md") }
            await ctx.press(.down, [.command]); await ctx.settle(300)
            await ctx.scrollBy(-(ctx.lineHeight * 5 + 7)); await ctx.settle(200)
            let expect = NSMutableString(string: ctx.textCopy() as String)
            ctx.at("Enter near the document end")
            guard await ctx.clickEndOfBottomLine("the end of the bottom line, five lines above the document end") else { return }
            var at = ctx.caret
            for i in 1...9 {
                _ = await ctx.edgeEdit("Enter \(i) near the document end", { await ctx.press(.returnKey) })
                expect.insert("\n", at: at); at += 1
                if i % 3 == 0 {
                    for ch in "줄 \(i)" {
                        if ("가"..."힣").contains(ch) { await ctx.composeKeys(String(ch)) } else { await ctx.typeKeys(String(ch)) }
                    }
                    await ctx.quiesce()
                    expect.insert("줄 \(i)", at: at); at += ("줄 \(i)" as NSString).length
                    ctx.checkCaretLineWhole("typed after Enter \(i) near the document end")
                }
            }
            ctx.checkTyped(expect, caret: at, "9 × Enter near the document end"); ctx.checkInk("9 × Enter near the document end")
            ctx.snap("near-end")
            // 문서의 마지막 줄에서: 끝에 붙어 있어야 한다
            ctx.at("Enter on the last line of the document")
            await ctx.press(.down, [.command]); await ctx.quiesce()
            at = ctx.caret
            for i in 1...4 {
                await ctx.press(.returnKey); await ctx.typeKeys("x"); await ctx.quiesce()
                expect.insert("\nx", at: at); at += 2
                ctx.checkCaretLineWhole("Enter \(i) on the last line"); ctx.checkLayout("Enter \(i) on the last line")
            }
            ctx.checkTyped(expect, caret: at, "typed on the last line")
            let slack = ctx.tv.frame.height - ctx.visible.maxY
            if slack > ctx.lineHeight { ctx.issue("viewport-jump", "after typing on the last line the viewport stops \(Int(slack)) pt above the document bottom") }
            ctx.snap("at-end")

            // 여러 번 감기는 문단: 맨 아래 문단의 끝에서 계속 쓴다 — 줄이 하나 늘 때마다 한 줄씩
            await ctx.withRelaxedStalls { await ctx.open(.wide, name: "edge-wide.md") }
            ctx.model.jump(toLine: 2000); await ctx.settle(500)
            ctx.at("wide: type at the end of the bottom paragraph")
            guard await ctx.clickEndOfBottomLine("the end of the bottom paragraph") else { return }
            let wide = NSMutableString(string: ctx.textCopy() as String)
            at = ctx.caret
            var wraps = 0
            let more = " 감긴 문단의 끝에 이어 쓴다 and keeps typing so that the paragraph grows by more visual lines, one line at a time 한 줄씩"
            for (i, ch) in (more + more).enumerated() {
                let m: CGFloat?
                if ("가"..."힣").contains(ch) { m = await ctx.edgeEdit("wide: syllable \(i + 1)", { await ctx.composeKeys(String(ch)) }) }
                else { m = await ctx.edgeEdit("wide: character \(i + 1)", { await ctx.typeKeys(String(ch)) }) }
                wide.insert(String(ch), at: at); at += (String(ch) as NSString).length
                if let m, abs(m) > 0.5 { wraps += 1 }
                if ctx.issues.count - issues0 > 12 { break }
            }
            ctx.note("wide: typing \(more.count * 2) characters at the end of the bottom paragraph scrolled the view \(wraps) time(s)")
            ctx.checkTyped(wide, caret: at, "wide: typed at the end of the bottom paragraph"); ctx.checkInk("wide: typed at the end of the bottom paragraph")
            ctx.at("wide: Enter in the middle of the bottom paragraph")
            _ = await ctx.edgeEdit("wide: Enter at the end of the bottom paragraph", { await ctx.press(.returnKey) })
            wide.insert("\n", at: at); at += 1
            ctx.checkTyped(wide, caret: at, "wide: Enter at the end of the bottom paragraph")
            ctx.snap("wide-end")
        },

        // 비용: 캐럿을 따라가는 일이 키마다 드는 시간 — Enter 가 많은 입력(줄마다 배치를 한 번 한다)과, 한 턴 안에서 되풀이되는 삽입(매크로 재생·텍스트 도구와 같은 꼴)
        Scenario(name: "typing-edge-cost") { ctx in
            RealUse.keepAwakeForTiming()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "edge-cost.md") }
            ctx.model.jump(toLine: 9000); await ctx.settle(500)
            ctx.at("lines typed in the middle of the screen")
            guard let a = ctx.anchor(nearScreenY: 100) else { ctx.issue("other", "no paragraph on screen"); return }
            guard await ctx.clickCaret(a.offset, "the head of a line near the top of the screen") else { return }
            // 화면 가운데에서: 줄 여덟 개 (가장자리를 넘지 않는다)
            ctx.reportTiming(await ctx.typeTimed(String(repeating: "abc 가나\n", count: 8)), "Enter-heavy typing in the middle of the screen (8 lines)")
            ctx.at("lines typed on the bottom line")
            guard await ctx.clickEndOfBottomLine("the end of the bottom line") else { return }
            // 맨 아랫줄에서: 줄마다 화면이 한 줄씩 따라온다
            ctx.reportTiming(await ctx.typeTimed(String(repeating: "\nabc 가나", count: 40)), "Enter-heavy typing on the bottom line (40 lines)")
            ctx.checkCaretLineWhole("after typing 40 lines on the bottom line"); ctx.checkAll("after typing 40 lines on the bottom line")
            // 한 턴 안에서 되풀이되는 삽입: 화면 갱신 없이 300 번 (매크로 재생이 이렇게 돈다)
            ctx.at("300 inserts in one turn")
            let none = NSRange(location: NSNotFound, length: 0)
            var ms = 0.0
            await ctx.withRelaxedStalls(20_000) {   // 이 걸음은 일부러 한 턴을 오래 쓴다
                let t0 = CFAbsoluteTimeGetCurrent()
                for _ in 0..<300 {
                    ctx.tv.insertText("macro line", replacementRange: none)
                    ctx.tv.doCommand(by: #selector(NSResponder.insertNewline(_:)))
                }
                ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                await ctx.pumpEvent(); await ctx.quiesce()
            }
            ctx.note(String(format: "300 × (insert + Enter) in one turn on the bottom line: %.0f ms (%.2f ms per iteration)", ms, ms / 300))
            // 1.3 MB 메모 가운데에서는 편집 두 번(삽입 + Enter) 자체가 4.2~4.4 ms 다(실측 2026-11-25, 캐럿 따라가기를 AppKit 에 맡겼을 때). 캐럿 줄을 재려고
            // Enter 마다 뷰포트를 한 번 배치하는 몫은 +0.3 ms — 그 두 배를 넘겨 10 ms 가 되면 따라가기가 편집보다 비싸진 것이다
            if ms / 300 > 10 { ctx.issue("slow", String(format: "300 × (insert + Enter) in one turn took %.0f ms (%.2f ms per iteration) — following the caret costs too much per edit", ms, ms / 300), snap: false) }
            ctx.checkCaretLineWhole("after 300 inserts in one turn"); ctx.checkAll("after 300 inserts in one turn"); ctx.checkInk("after 300 inserts in one turn")
            ctx.snap("end")
        },

        // 매크로 재생: 한 턴 안에서 편집과 캐럿 이동을 수백 번 되풀이한다 (셀프테스트의 `perf macro ×100 (10 steps)` 와 같은 문서·같은 매크로).
        // 걸음마다 캐럿을 따라 스크롤하면 그 측정이 걸음 수만큼 쌓이고, 턴 안에서는 앞서 고친 줄들의 높이가 어림이라 측정도 틀린다 — 재생 중에는 화면이 갱신될
        // 때와 끝에서만 따라간다 (HyperTextView.revealCaretAfterReplaySteps). 비용, 재생 뒤 캐럿 줄이 보이는가, 한 번의 되돌리기, 화면이 까닭 없이 움직이지 않는가를 본다
        Scenario(name: "typing-macro-cost") { ctx in
            RealUse.keepAwakeForTiming()
            let big = (0..<33_000).map { String(format: "2026-01-01 12:%02d INFO log line %06d", $0 % 60, $0) }.joined(separator: "\n")
            await ctx.withRelaxedStalls(20_000) { await ctx.open(text: big, name: "macro-cost.md") }
            let ten = Macro(name: "ten", steps: [.insert("- "), .command("moveToEndOfLine:"), .insert(" ✓"), .command("moveToBeginningOfLine:"), .command("moveRight:"),
                                                  .command("moveLeft:"), .insert("x"), .command("deleteBackward:"), .command("moveDown:"), .command("moveToBeginningOfLine:")])
            let original = ctx.textCopy()
            // 벽시계 시간과 함께 메인 스레드의 CPU 시간을 잰다 — 다른 작업이 함께 도는 기계에서는 벽시계가 ±15 % 흔들린다 (typeTimed 와 같은 까닭)
            func cpu() -> Double { Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1_000_000 }
            var times: [Double] = [], cpus: [Double] = []
            for round in 1...5 {
                ctx.at("macro ×100, round \(round)")
                await ctx.key(.up, [.command]); await ctx.settle(300)
                await ctx.pumpEvent()
                var result: MacroRecorder.PlayResult?
                var cpuMs = 0.0
                await ctx.withRelaxedStalls(20_000) {   // 재생은 50 ms 마다만 런루프에 양보한다
                    let c0 = cpu()
                    result = await ctx.model.macros.play(ten, times: 100)
                    cpuMs = cpu() - c0
                    await ctx.pumpEvent(); await ctx.quiesce()
                }
                guard let r = result else { ctx.issue("other", "round \(round): the macro did not play"); return }
                times.append(r.ms); cpus.append(cpuMs)
                ctx.note(String(format: "round %d: 100 runs of the 10-step macro on 1.2 MB: %.0f ms, main-thread CPU %.0f ms (%d iterations, %d steps)", round, r.ms, cpuMs, r.iterations, r.steps))
                if r.iterations != 100 || ctx.text.length != original.length + 400 || !ctx.text.hasPrefix("- 2026-01-01 12:00 INFO log line 000000 ✓\n") {
                    ctx.issue("text", "round \(round): expected 100 transformed lines (+400 chars), got \(r.iterations) iterations and \(ctx.text.length - original.length) chars")
                }
                // 재생이 끝난 자리(101번째 줄의 머리)가 보여야 한다
                if LineIndex(nsString: ctx.text).lineNumber(forUTF16Offset: ctx.caret) != 101 { ctx.issue("selection", "round \(round): the caret should be on line 101 after 100 runs, it is at offset \(ctx.caret)") }
                ctx.checkCaretLineWhole("after the macro, round \(round)"); ctx.checkAll("after the macro, round \(round)"); ctx.checkInk("after the macro, round \(round)")
                if round == 1 { ctx.snap("played") }
                await ctx.withRelaxedStalls(20_000) { await ctx.undo(); await ctx.settle(300) }
                if !ctx.expectText(original, "one undo after the macro, round \(round)") { return }
            }
            let sorted = times.sorted(), sortedCPU = cpus.sorted()
            ctx.note(String(format: "macro ×100 over %d rounds: median %.0f ms, best %.0f, worst %.0f · main-thread CPU median %.0f ms, best %.0f, worst %.0f",
                            times.count, sorted[sorted.count / 2], sorted[0], sorted[sorted.count - 1], sortedCPU[sortedCPU.count / 2], sortedCPU[0], sortedCPU[sortedCPU.count - 1]))
            // 견줄 기준: 같은 걸음을 재생기 없이 하나씩 보낸다 — 걸음마다 캐럿을 따라가는(재생 중에는 미루는) 그 비용이 든다. 재생기처럼 50 ms 마다 양보한다.
            // 절대 시간은 기계의 부하를 탄다(실측: 같은 빌드의 첫 재생이 645~757 ms) — 같은 실행 안의 기준과 견준다. 다른 작업에 밀린 시간이 섞이지 않게 CPU 시간으로
            ctx.at("the same steps without the player")
            var direct: [Double] = []
            for round in 1...2 {
                await ctx.key(.up, [.command]); await ctx.settle(300)
                await ctx.pumpEvent()
                var cpuMs = 0.0
                await ctx.withRelaxedStalls(20_000) {
                    let c0 = cpu()
                    var lastYield = CFAbsoluteTimeGetCurrent()
                    for _ in 0..<100 {
                        for step in ten.steps {
                            switch step {
                            case .insert(let text): ctx.tv.insertText(text, replacementRange: ctx.tv.selectedRange())
                            case .command(let name): ctx.tv.doCommand(by: Selector(name))
                            default: break
                            }
                        }
                        if CFAbsoluteTimeGetCurrent() - lastYield > 0.05 { try? await Task.sleep(nanoseconds: 1_000_000); lastYield = CFAbsoluteTimeGetCurrent() }
                    }
                    cpuMs = cpu() - c0
                    await ctx.pumpEvent(); await ctx.quiesce()
                }
                direct.append(cpuMs)
                ctx.note(String(format: "round %d: the same 1,000 steps sent one by one: main-thread CPU %.0f ms", round, cpuMs))
                if ctx.text.length != original.length + 400 { ctx.issue("text", "the same steps sent one by one changed \(ctx.text.length - original.length) units, expected 400") }
                await ctx.withRelaxedStalls(20_000) {
                    var undos = 0
                    while !ctx.text.isEqual(to: original as String), undos < 12, ctx.tv.undoManager?.canUndo == true { await ctx.undo(); undos += 1 }
                    await ctx.settle(300)
                }
                if !ctx.expectText(original, "undo after the steps sent one by one, round \(round)") { return }
            }
            // 실측 (메인 스레드 CPU, 되돌린 뒤의 재생): 걸음마다 따라가던 때 914~983 ms, 미룬 뒤 739~830 ms. 재생이 하나씩 보낸 것의 90 % 를 넘으면 미루기가 사라진 것이다.
            // 셀프테스트의 한도(1 s)도 그대로 본다
            let replay = cpus.dropFirst().sorted(), followed = direct.min() ?? 0
            let replayMedian = replay.isEmpty ? cpus[0] : replay[replay.count / 2]
            ctx.note(String(format: "replay after an undo: median %.0f ms of main-thread CPU; the same steps one by one: %.0f ms (%.0f %%)", replayMedian, followed, followed > 0 ? replayMedian / followed * 100 : 0))
            if followed > 0, replayMedian > followed * 0.9 {
                ctx.issue("slow", String(format: "100 runs of a 10-step macro cost %.0f ms of main-thread CPU, the same steps sent one by one %.0f ms — the replay should be clearly cheaper (at most 90 %%)", replayMedian, followed), snap: false)
            }
            if sorted[sorted.count / 2] > 1000 { ctx.issue("slow", String(format: "100 runs of a 10-step macro took a median of %.0f ms (budget 1000 ms)", sorted[sorted.count / 2]), snap: false) }

            // 문서 가운데, 캐럿이 화면 위쪽 1/3 에 있을 때 여덟 번: 캐럿은 여덟 줄 내려가지만 화면 안에 머문다 — 화면은 움직이지 않아야 한다.
            // 한 턴 안에서 편집이 되풀이되면 앞서 고친 줄들의 높이가 어림으로 돌아가 있어 캐럿 줄의 자리가 실제보다 아래로 재어진다 (실측: 여덟 줄 뒤 +192 pt)
            ctx.at("macro ×8 with the caret in the upper third of the screen")
            ctx.model.jump(toLine: 16_000); await ctx.settle(500)
            await ctx.pumpEvent()
            if let a = ctx.anchor(nearScreenY: 30), a.offset < ctx.caret {
                await ctx.withRelaxedStalls(20_000) { _ = await ctx.model.macros.play(ten, times: 8); await ctx.pumpEvent(); await ctx.quiesce() }
                if let y = ctx.screenY(ofFragmentAt: a.offset) {
                    ctx.note(String(format: "8 runs in the upper third of the screen: the paragraph above the caret moved %+.1f pt on screen", a.y - y))
                    if abs(y - a.y) > 1 { ctx.issue("viewport-jump", String(format: "8 runs of the macro kept the caret on screen but the content moved %+.1f pt", a.y - y)) }
                } else { ctx.issue("viewport-jump", "8 runs of the macro kept the caret on screen but the view jumped (top line \(ctx.topLine()))") }
                ctx.checkCaretLineWhole("after 8 runs in the upper third"); ctx.checkAll("after 8 runs in the upper third")
                ctx.snap("mid-screen")
            } else { ctx.issue("other", "no paragraph above the caret after going to line 16,000") }
            // 화면 맨 아랫줄에서 한 번: 캐럿이 한 줄 내려가 아래 가장자리를 넘는다 — 화면은 그 한 줄만 따라간다
            ctx.at("macro once on the bottom line")
            if let f = ctx.edgeParagraph(bottom: true), await ctx.clickCaret(f.offset, "the head of the bottom line") {
                for i in 1...3 {
                    _ = await ctx.edgeEdit("macro run \(i) on the bottom line", { _ = await ctx.model.macros.play(ten, times: 1) })
                }
            }
            ctx.snap("bottom-line")

            // 문서 끝에서 "글자 + Enter" 를 되풀이한다. 재생 뒤의 '캐럿 보이기'는 방향키와 같은 길로 들어가므로, 편집이 부른 보이기라면 AppKit 에 맡겼을
            // '문서의 마지막 줄'(문서가 자라는 중이라 텍스트 뷰의 높이가 옛 값일 수 있다)을 그 길이 직접 다룬다 — 끝난 뒤 캐럿 줄이 온전히 보이고 화면이 문서 끝이어야 한다
            ctx.at("macro at the end of the document: a character and Enter")
            await ctx.press(.down, [.command]); await ctx.settle(400)
            let typeLine = Macro(name: "line", steps: [.insert("x"), .command("insertNewline:")])
            let lengthAtEnd = ctx.length
            await ctx.withRelaxedStalls(20_000) { _ = await ctx.model.macros.play(typeLine, times: 40); await ctx.pumpEvent(); await ctx.quiesce() }
            if ctx.length != lengthAtEnd + 80 || ctx.caret != ctx.length { ctx.issue("text", "40 runs of “x, Enter” at the end: \(ctx.length - lengthAtEnd) units added (expected 80), caret at \(ctx.caret) of \(ctx.length)") }
            ctx.checkCaretLineWhole("after 40 runs at the end of the document"); ctx.expectBottom("after 40 runs at the end of the document")
            ctx.checkAll("after 40 runs at the end of the document"); ctx.checkInk("after 40 runs at the end of the document")
            for i in 1...3 {
                _ = await ctx.edgeEdit("macro run \(i) on the last line of the document", { _ = await ctx.model.macros.play(typeLine, times: 1) })
                ctx.expectBottom("macro run \(i) on the last line of the document")
            }
            ctx.snap("document-end")

            // 문서를 통째로 바꾸는 걸음이 든 매크로를 문서 끝에서: 모두 선택 → 주석 토글 → 문서 끝으로. 재생 뒤의 보이기는 뷰포트를 먼저 배치한다 —
            // 문서 전체가 바뀐 직후 스크롤 위치가 문서 끝 너머면 그 배치가 문서를 처음부터 훑는다 (그래서 그 앞에서 끝 너머인지 본다)
            ctx.at("macro with a whole-document step at the end of the document")
            let wholesale = Macro(name: "wholesale", steps: [.command("selectAll:"), .tool(TextTool.toggleComment.rawValue), .command("moveToEndOfDocument:")])
            for what in ["comment", "uncomment"] {
                let lengthBefore = ctx.length, before = ctx.fragmentCache?.count ?? 0
                var ms = 0.0, after = 0.0
                await ctx.withRelaxedStalls(60_000) {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    _ = await ctx.model.macros.play(wholesale, times: 1)
                    ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    for _ in 0..<3 { await ctx.turn(); ctx.window.layoutIfNeeded(); ctx.window.displayIfNeeded() }
                    after = (CFAbsoluteTimeGetCurrent() - t0) * 1000 - ms
                    await ctx.pumpEvent(); await ctx.settle(400)
                }
                let added = (ctx.fragmentCache?.count ?? 0) - before
                ctx.note(String(format: "select all, toggle comment (%@), go to the end as one macro at the end of 1.2 MB: %.0f ms, the screen settled %.0f ms later; the fragment table grew by %d entries; %+d units",
                                what, ms, after, added, ctx.length - lengthBefore))
                if ctx.length == lengthBefore { ctx.issue("text", "the macro with a whole-document step (\(what)) changed nothing") }
                if ms > 900 { ctx.issue("slow", String(format: "the macro with a whole-document step (%@) took %.0f ms (budget 900 ms)", what, ms), snap: false) }
                if after > 500 { ctx.issue("stall", String(format: "the macro with a whole-document step (%@): the screen needed %.0f ms to settle (budget 500 ms)", what, after), snap: false) }
                if added > 4_000 { ctx.issue("other", "the macro with a whole-document step (\(what)) laid out \(added) paragraphs — the whole document", snap: false) }
                if ctx.caret != ctx.length { ctx.issue("selection", "the macro with a whole-document step (\(what)) should end with the caret at the end, it is at \(ctx.caret) of \(ctx.length)") }
                ctx.checkCaretLineWhole("after the macro with a whole-document step (\(what))"); ctx.expectBottom("after the macro with a whole-document step (\(what))")
                ctx.checkAll("after the macro with a whole-document step (\(what))"); ctx.checkInk("after the macro with a whole-document step (\(what))")
            }
            ctx.snap("whole-document-step")
        },

        // 문서 전체를 바꾸는 도구(주석 토글 · JSON 정리)의 비용. 편집 뒤의 '캐럿 보이기'가 뷰포트를 배치해 캐럿 줄을 재려 들면, 문서 전체가 바뀐 직후라
        // 그 배치가 문서를 처음부터 훑는다 — 편집 한 번이 수백 ms 에서 수 초가 된다 (셀프테스트의 perf toggle comment / format JSON 과 같은 입력)
        Scenario(name: "typing-big-tools") { ctx in
            RealUse.keepAwakeForTiming()
            @MainActor func run(_ what: String, budget: Double, _ action: () -> Void) async -> Double {
                var ms = 0.0
                await ctx.withRelaxedStalls(60_000) {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    action()
                    ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    await ctx.pumpEvent(); await ctx.settle(400)
                }
                ctx.note(String(format: "%@: %.0f ms", what, ms))
                if ms > budget { ctx.issue("slow", String(format: "%@ took %.0f ms (budget %.0f ms)", what, ms, budget), snap: false) }
                return ms
            }
            // 1.3 MB · 24,000 줄: 모두 선택 → 주석 토글 (문서 전체가 한 번의 편집으로 바뀌고 선택은 결과 전체)
            let lines = (0..<24_000).map { String(format: "2026-01-01 12:%02d INFO 로그 줄 %06d 한글 텍스트 https://example.com/%d\tcol\t%d", $0 % 60, $0, $0, $0) }.joined(separator: "\n")
            await ctx.withRelaxedStalls(20_000) { await ctx.open(text: lines, name: "big-tools.txt") }
            for place in ["at the end", "in the middle", "at the top"] {
                ctx.at("toggle comment, view \(place)")
                if place == "in the middle" { ctx.model.jump(toLine: 12_000); await ctx.settle(500) }
                if place == "at the top" { await ctx.key(.up, [.command]); await ctx.settle(300) }
                await ctx.selectAll(); await ctx.settle(100)
                // 실측: 150~320 ms. 캐럿 보이기가 뷰포트 배치로 떨어지면 1.4 s 였다
                _ = await run("toggle comment on 1.3 MB (24,000 lines), view \(place)", budget: 900) { ctx.model.textTool(.toggleComment) }
                if !ctx.text.hasPrefix("// 2026-01-01") { ctx.issue("text", "toggle comment (view \(place)): the first line is not commented") }
                ctx.checkLayout("toggle comment, view \(place)")
                _ = await run("toggle comment back, view \(place)", budget: 900) { ctx.model.textTool(.toggleComment) }
                if ctx.text.length != (lines as NSString).length { ctx.issue("text", "toggle comment back (view \(place)): length \(ctx.text.length), expected \((lines as NSString).length)") }
                ctx.checkLayout("toggle comment back, view \(place)")
                await ctx.press(.left); await ctx.settle(100)
            }
            // 1.7 MB JSON · 12,002 줄 → 정리하면 180,002 줄 (캐럿은 문서 처음에 놓인다)
            func element(_ i: Int) -> String { "{\"id\":\(i),\"name\":\"항목 \(i) 한글 이름\",\"tags\":[\"a\",\"b\",\"c\"],\"score\":\(Double(i) / 7),\"nested\":{\"ok\":true,\"none\":null,\"note\":\"line\\nbreak\"}}" }
            let json = "[\n" + (0..<12_000).map(element).joined(separator: ",\n") + "\n]"
            await ctx.withRelaxedStalls(20_000) { await ctx.open(text: json, name: "big-tools.json") }
            for place in ["at the end", "at the top", "in the middle"] {
                ctx.at("format JSON, view \(place)")
                if place == "at the top" { await ctx.key(.up, [.command]); await ctx.settle(300) }
                if place == "in the middle" { ctx.model.jump(toLine: 6_000); await ctx.settle(500) }
                // 실측: 문서 처음에서 150~200 ms
                _ = await run("format JSON on 1.7 MB (12,002 → 180,002 lines), view \(place)", budget: 900) { ctx.model.textTool(.formatJSON) }
                if !ctx.text.hasPrefix("[\n  {\n    \"id\": 0,") { ctx.issue("text", "format JSON (view \(place)): the result does not start with the pretty-printed first element") }
                if ctx.tv.selectedRange() != NSRange(location: 0, length: 0) { ctx.issue("selection", "format JSON (view \(place)): the caret should be at the start, it is at \(ctx.tv.selectedRange())") }
                ctx.expectTop("format JSON, view \(place)"); ctx.checkAll("format JSON, view \(place)"); ctx.checkInk("format JSON, view \(place)")
                await ctx.withRelaxedStalls(60_000) { await ctx.undo(); await ctx.settle(500) }
                if ctx.text.length != (json as NSString).length { ctx.issue("text", "undo of format JSON (view \(place)): length \(ctx.text.length), expected \((json as NSString).length)") }
            }
            ctx.snap("end")
        },

        // 문서 전체를 바꾼 도구의 되돌리기·다시 실행(⌘Z · ⇧⌘Z)을 화면이 문서 끝일 때: 입력과 다른 길이다 (shouldChangeText 를 거치지 않고, 끝난 뒤 따로 캐럿을
        // 보이게 한다) — 문서 전체가 바뀐 직후 문서 끝에서의 배치가 문서를 처음부터 훑지 않는가. 편집 자체의 시간과 그 뒤 화면이 가라앉는 시간을 따로 잰다:
        // 되돌리기의 편집은 AppKit 의 몫이라(NSUndoTyping 이 속성 문자열을 다시 넣는다 — 실측: 1.3 MB 주석 토글의 되돌리기·다시 실행 5.3 s, JSON 정리 0.85 s;
        // 속성 런 배열의 memmove 이고 화면 위치와 무관하다) 여기서는 기록만 하고, 스크롤·배치의 몫인 '그 뒤'를 판정한다
        Scenario(name: "typing-big-tools-redo") { ctx in
            RealUse.keepAwakeForTiming()
            /// 동작 하나(편집)의 시간과 그 뒤 화면이 가라앉을 때까지의 시간. `judgeEdit`: 편집 시간도 예산으로 본다 (도구 자체)
            @MainActor func timed(_ what: String, judgeEdit: Bool, _ action: () async -> Void) async {
                var edit = 0.0, after = 0.0
                let before = ctx.fragmentCache?.count ?? 0
                await ctx.withRelaxedStalls(60_000) {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    await action()
                    edit = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    for _ in 0..<3 { await ctx.turn(); ctx.window.layoutIfNeeded(); ctx.window.displayIfNeeded() }
                    after = (CFAbsoluteTimeGetCurrent() - t0) * 1000 - edit
                    await ctx.settle(400)
                }
                let added = (ctx.fragmentCache?.count ?? 0) - before
                ctx.note(String(format: "%@: the edit took %.0f ms, the screen settled %.0f ms later; the fragment table grew by %d entries", what, edit, after, added))
                if judgeEdit, edit > 900 { ctx.issue("slow", String(format: "%@ took %.0f ms (budget 900 ms)", what, edit), snap: false) }
                // 실측: 편집 뒤 화면이 가라앉기까지 0~3 ms. 문서 전체를 배치하면 1 s 를 넘는다
                if after > 500 { ctx.issue("stall", String(format: "%@: the screen needed %.0f ms to settle after the edit (budget 500 ms)", what, after), snap: false) }
                if added > 4_000 { ctx.issue("other", "\(what) laid out \(added) paragraphs — the whole document", snap: false) }
            }
            let lines = (0..<24_000).map { String(format: "2026-01-01 12:%02d INFO 로그 줄 %06d 한글 텍스트 https://example.com/%d\tcol\t%d", $0 % 60, $0, $0, $0) }.joined(separator: "\n")
            await ctx.withRelaxedStalls(20_000) { await ctx.open(text: lines, name: "big-redo.txt") }
            ctx.at("toggle comment: undo and redo with the view at the end")
            await ctx.key(.down, [.command]); await ctx.settle(400)
            await ctx.selectAll(); await ctx.settle(100)
            await timed("toggle comment on 1.3 MB, view at the end", judgeEdit: true) { ctx.model.textTool(.toggleComment); await ctx.pumpEvent() }
            await ctx.press(.down, [.command]); await ctx.settle(400)
            await timed("undo of toggle comment, view at the end", judgeEdit: false) { await ctx.undo() }
            if ctx.text.length != (lines as NSString).length { ctx.issue("text", "undo of toggle comment left \(ctx.text.length) units, expected \((lines as NSString).length)") }
            ctx.checkLayout("undo of toggle comment")
            await ctx.press(.down, [.command]); await ctx.settle(400)
            ctx.expectBottom("before the redo")
            await timed("redo of toggle comment, view at the end", judgeEdit: false) { await ctx.redo() }
            if !ctx.text.hasPrefix("// 2026-01-01") { ctx.issue("text", "redo of toggle comment: the first line is not commented") }
            ctx.checkAll("redo of toggle comment"); ctx.checkInk("redo of toggle comment")
            // JSON 정리: 12,002 줄 → 180,002 줄
            func element(_ i: Int) -> String { "{\"id\":\(i),\"name\":\"항목 \(i) 한글 이름\",\"tags\":[\"a\",\"b\",\"c\"],\"score\":\(Double(i) / 7),\"nested\":{\"ok\":true,\"none\":null,\"note\":\"line\\nbreak\"}}" }
            let json = "[\n" + (0..<12_000).map(element).joined(separator: ",\n") + "\n]"
            await ctx.withRelaxedStalls(20_000) { await ctx.open(text: json, name: "big-redo.json") }
            ctx.at("format JSON: undo and redo with the view at the end")
            await ctx.key(.down, [.command]); await ctx.settle(400)
            await timed("format JSON on 1.7 MB, view at the end", judgeEdit: true) { ctx.model.textTool(.formatJSON); await ctx.pumpEvent() }
            let formatted = ctx.text.length
            await ctx.press(.down, [.command]); await ctx.settle(400)
            await timed("undo of format JSON, view at the end of the formatted text", judgeEdit: false) { await ctx.undo() }
            if ctx.text.length != (json as NSString).length { ctx.issue("text", "undo of format JSON left \(ctx.text.length) units, expected \((json as NSString).length)") }
            ctx.checkLayout("undo of format JSON")
            await ctx.press(.down, [.command]); await ctx.settle(400)
            ctx.expectBottom("before the redo of format JSON")
            await timed("redo of format JSON, view at the end", judgeEdit: false) { await ctx.redo() }
            if ctx.text.length != formatted { ctx.issue("text", "redo of format JSON left \(ctx.text.length) units, expected \(formatted)") }
            ctx.checkAll("redo of format JSON"); ctx.checkInk("redo of format JSON")
            ctx.snap("end")
        },

        // 빈 문서에 큰 붙여넣기: 새 파일을 만들어 다른 곳의 내용을 통째로 붙이는 흔한 시작. 한 줄이라도 있던 문서에 붙일 때와 비용이 같아야 한다 —
        // 붙여넣은 뒤의 배치가 문서 전체를 훑으면 그 한 번이 1 s 를 넘는다
        Scenario(name: "typing-paste-empty") { ctx in
            RealUse.keepAwakeForTiming()
            let block = (0..<24_000).map { String(format: "2026-01-01 12:%02d INFO 로그 줄 %06d 한글 텍스트 https://example.com/%d\tcol\t%d", $0 % 60, $0, $0, $0) }.joined(separator: "\n")
            let none = NSRange(location: NSNotFound, length: 0)
            /// 붙여넣고 화면이 가라앉을 때까지의 시간, 그 뒤 조각 표가 는 항목 수 (문서 전체가 배치됐으면 문단 수만큼이다)
            @MainActor func pasteTimed(_ why: String) async -> (ms: Double, fragments: Int) {
                let before = ctx.fragmentCache?.count ?? 0
                var ms = 0.0
                await ctx.withRelaxedStalls(60_000) {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    ctx.tv.insertText(block, replacementRange: none)
                    for _ in 0..<3 { await ctx.turn(); ctx.window.layoutIfNeeded(); ctx.window.displayIfNeeded() }
                    ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    await ctx.pumpEvent(); await ctx.settle(400)
                }
                let added = (ctx.fragmentCache?.count ?? 0) - before
                ctx.note(String(format: "%@: pasting 1.3 MB (24,000 lines) took %.0f ms until the screen settled; the fragment table grew by %d entries", why, ms, added))
                return (ms, added)
            }
            // 견줄 기준: 한 줄이 있는 문서의 끝에 붙인다
            ctx.at("paste into a one-line document")
            await ctx.open(text: "첫 줄\n", name: "paste-one-line.md")
            await ctx.press(.down, [.command]); await ctx.settle(200)
            let oneLine = await pasteTimed("into a one-line document")
            ctx.checkTyped(("첫 줄\n" + block) as NSString, caret: ("첫 줄\n" + block as NSString).length, "pasted into a one-line document")
            ctx.checkCaretLineWhole("pasted into a one-line document"); ctx.checkInk("pasted into a one-line document")
            // 빈 문서에 붙인다
            ctx.at("paste into an empty document")
            await ctx.open(text: "", name: "paste-empty.md")
            if ctx.length != 0 { ctx.issue("other", "the new document should be empty, it holds \(ctx.length) units"); return }
            let empty = await pasteTimed("into an empty document")
            ctx.checkTyped(block as NSString, caret: (block as NSString).length, "pasted into an empty document")
            ctx.checkCaretLineWhole("pasted into an empty document"); ctx.checkInk("pasted into an empty document")
            ctx.snap("pasted-into-empty")
            if empty.ms > oneLine.ms * 2 + 200 {
                ctx.issue("stall", String(format: "pasting 1.3 MB into an empty document took %.0f ms; into a one-line document %.0f ms", empty.ms, oneLine.ms), snap: false)
            }
            if empty.fragments > 4_000 { ctx.issue("other", "pasting 24,000 lines into an empty document laid out \(empty.fragments) paragraphs — the whole document", snap: false) }
            // 이어서 쓰고, 한 번에 되돌린다
            ctx.at("type after the paste, then undo")
            await ctx.typeKeys(" 끝"); await ctx.quiesce()
            ctx.checkTyped((block + " 끝") as NSString, caret: (block as NSString).length + 2, "typed after pasting into an empty document"); ctx.checkCaretLineWhole("typed after pasting into an empty document")
            var undos = 0
            await ctx.withRelaxedStalls(20_000) {
                while ctx.length > 0, undos < 6, ctx.tv.undoManager?.canUndo == true { await ctx.undo(); undos += 1 }
                await ctx.settle(300)
            }
            if ctx.length != 0 { ctx.issue("text", "\(undos) × ⌘Z after pasting into an empty document left \(ctx.length) units") }
            ctx.checkLayout("the paste taken back")
        },

        // 문서 전체를 바꾸는 줄 도구를, 첫 줄들이 아주 긴(한 줄 2만 자 넘는) 파일의 끝을 보던 중에 쓴다 (JSONL·한 줄 로그 묶음). 캐럿을 따라가려고 편집이 시작된
        // 문서 처음의 문단들을 배치해 두는데, 그 문단들이 거대하면 아무도 보지 않을 배치에 시간을 쓴다
        Scenario(name: "typing-big-tools-long-head") { ctx in
            RealUse.keepAwakeForTiming()
            /// 도구 한 번의 시간. 편집 뒤 화면이 가라앉는 시간과 조각 표가 는 항목 수도 판정한다 — 미리 배치해 둔 문단이 하나도 없을 때(첫 64줄이 전부 거대 문단)
            /// 다음 배치 패스가 문서를 처음부터 훑으면 여기에 드러난다 (실측: 가라앉기까지 20~30 ms, 조각 표는 화면만큼만 는다)
            @MainActor func toggleTimed(_ what: String) async -> Double {
                var ms = 0.0, after = 0.0
                let before = ctx.fragmentCache?.count ?? 0
                await ctx.withRelaxedStalls(60_000) {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    ctx.model.textTool(.toggleComment)
                    ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                    for _ in 0..<3 { await ctx.turn(); ctx.window.layoutIfNeeded(); ctx.window.displayIfNeeded() }
                    after = (CFAbsoluteTimeGetCurrent() - t0) * 1000 - ms
                    await ctx.pumpEvent(); await ctx.settle(400)
                }
                let added = (ctx.fragmentCache?.count ?? 0) - before
                ctx.note(String(format: "%@: %.0f ms (%.0f ms until the screen settled; the fragment table grew by %d entries)", what, ms, ms + after, added))
                if after > 500 { ctx.issue("stall", String(format: "%@: the screen needed %.0f ms to settle after the edit (budget 500 ms)", what, after), snap: false) }
                if added > 4_000 { ctx.issue("other", "\(what) laid out \(added) paragraphs — the whole document", snap: false) }
                return ms
            }
            let short = (0..<20_000).map { String(format: "2026-01-01 12:%02d INFO 로그 줄 %06d 한글 텍스트 https://example.com/%d", $0 % 60, $0, $0) }
            let record = String(repeating: "{\"k\":\"값 value\",\"n\":12345},", count: 1_000)   // 한 줄 약 26,000자
            let longHead = ((0..<64).map { "[\($0)," + record + "0]" } + short).joined(separator: "\n")
            let mixedHead = ((0..<10).map { "[\($0)," + record + "0]" } + short + short.prefix(18_000)).joined(separator: "\n")   // 긴 줄 열 개 뒤에 보통 줄
            let plain = (short + short + short.prefix(4_000)).joined(separator: "\n")   // 같은 크기의 보통 문서 (약 3 M 자)
            var results: [String: Double] = [:]
            for (name, text) in [("plain", plain), ("long-head", longHead), ("mixed-head", mixedHead)] {
                await ctx.withRelaxedStalls(30_000) { await ctx.open(text: text, name: "tools-\(name).txt") }
                ctx.at("\(name): toggle comment, view at the end")
                await ctx.withRelaxedStalls(30_000) { await ctx.key(.down, [.command]); await ctx.settle(500) }
                await ctx.selectAll(); await ctx.settle(100)
                results[name] = await toggleTimed("\(name): toggle comment on \(ctx.length / 1000) K units, view at the end")
                if !ctx.text.hasPrefix("// ") { ctx.issue("text", "\(name): the first line is not commented") }
                ctx.checkLayout("\(name): toggle comment")
                _ = await toggleTimed("\(name): toggle comment back")
                if ctx.text.length != (text as NSString).length { ctx.issue("text", "\(name): toggle comment back left \(ctx.text.length) units, expected \((text as NSString).length)") }
                ctx.checkLayout("\(name): toggle comment back")
                await ctx.press(.left); await ctx.settle(100)
            }
            // 긴 줄 64개는 문서의 일부일 뿐이다 — 같은 크기의 보통 문서보다 몇 배 걸리면 보지 않을 문단을 배치한 것이다
            ctx.at("compared with the plain document")
            for (name, what) in [("long-head", "starts with 64 very long lines"), ("mixed-head", "starts with 10 very long lines")] {
                if let a = results["plain"], let b = results[name], b > a * 2 + 300 {
                    ctx.issue("slow", String(format: "toggle comment with the view at the end took %.0f ms on the document that %@, %.0f ms on a plain one", b, what, a), snap: false)
                }
            }
            ctx.snap("end")
        },

        // 화면에 보이는 거대 문단(한 줄이 2만 자를 넘는 JSONL 줄) 바로 뒤에서의 Enter 도 한 줄만 민다. 그 문단은 화면에 그리려고 어차피 배치하는 것이라
        // 캐럿 줄을 재는 데 드는 것이 없다 — 재지 않고 AppKit 에 맡기면 화면이 가운데로 튄다
        Scenario(name: "typing-edge-huge-line") { ctx in
            let record = String(repeating: "{\"k\":\"값 value\",\"n\":12345},", count: 1_000)   // 한 줄 약 26,000자 — 자동 줄바꿈으로 수백 줄
            let short = (1...200).map { "short line \($0)" }
            let before: [String] = Array(short.prefix(100)), after: [String] = Array(short.suffix(100))
            let text = (before + ["[" + record + "0]"] + after).joined(separator: "\n") + "\n"
            await ctx.withRelaxedStalls(20_000) { await ctx.open(text: text, name: "edge-huge-line.jsonl") }
            ctx.at("Enter after a very long line on the bottom line")
            ctx.model.jump(toLine: 102); await ctx.settle(500)
            let head = ctx.lineStart(101), end = ctx.lineEnd(101)
            if ctx.text.paragraphRange(for: NSRange(location: end, length: 0)).length <= HyperTextView.hugeParagraphLength { ctx.issue("other", "line 101 should be longer than the huge-paragraph limit"); return }
            // 거대 문단 안의 캐럿 사각형은 구하지 않으므로(클릭할 자리를 못 잰다) 그 아랫줄의 머리를 누르고 ← 로 줄 끝에 간다
            guard await ctx.clickCaret(ctx.lineStart(102), "the head of the line below the very long line"), let below = ctx.caretOnScreen() else { return }
            let lh = below.bottom - below.top
            // 아랫줄이 화면 바로 아래로 나가게 올린다 — 거대 줄의 마지막 화면 줄이 맨 아랫줄이 된다
            await ctx.scrollBy(below.top - ctx.visible.height); await ctx.settle(200)
            await ctx.press(.left); await ctx.quiesce()
            if ctx.caret != end { ctx.issue("selection", "← from the head of line 102 should land at the end of the very long line (\(end)), the caret is at \(ctx.caret)"); return }
            /// 거대 문단의 조각이 화면에서 어디 있는가 (위·아래 가장자리, 뷰포트 위 가장자리로부터)
            @MainActor func huge() -> (top: CGFloat, bottom: CGFloat)? {
                ctx.viewportFragments().first(where: { $0.offset == head }).map { ($0.minY - ctx.visible.minY, $0.maxY - ctx.visible.minY) }
            }
            guard let h0 = huge(), abs(h0.bottom - ctx.visible.height) < 1.5 else {
                ctx.issue("other", "could not put the last screen line of the very long line on the bottom line (its paragraph ends at y \(huge().map { Int($0.bottom) } ?? -1) of \(Int(ctx.visible.height)))"); return
            }
            let expect = NSMutableString(string: ctx.textCopy() as String)
            var at = end
            /// 편집 하나 뒤에 내용이 화면에서 움직인 양 (거대 문단의 위 가장자리로 잰다 — 그 문단은 캐럿보다 앞에서 시작한다)
            @MainActor func edit(_ why: String, expected: CGFloat, _ body: () async -> Void) async {
                guard let before = huge() else { ctx.issue("other", "\(why): the very long paragraph is not laid out in the viewport"); return }
                let t0 = CFAbsoluteTimeGetCurrent()
                await body(); await ctx.quiesce()
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                guard let after = huge() else { ctx.issue("viewport-jump", "\(why): the very long paragraph left the viewport — the view jumped (top line \(ctx.topLine()))"); return }
                let moved = before.top - after.top
                ctx.note(String(format: "%@: the content moved %.1f pt on screen (one line is %.1f pt), %.0f ms", why, moved, lh, ms))
                if abs(moved - expected) > 1.5 { ctx.issue("viewport-jump", String(format: "%@: the content moved %.1f pt on screen — %.1f pt is what keeps the caret line in view", why, moved, expected)) }
                ctx.checkCaretLineWhole(why)
            }
            await edit("Enter after the very long line on the bottom line", expected: lh) { await ctx.press(.returnKey) }
            expect.insert("\n", at: at); at += 1
            ctx.checkTyped(expect, caret: at, "Enter after the very long line")
            await edit("typing on the new line", expected: 0) { await ctx.typeKeys("x") }
            expect.insert("x", at: at); at += 1
            await edit("a second Enter", expected: lh) { await ctx.press(.returnKey) }
            expect.insert("\n", at: at); at += 1
            ctx.checkTyped(expect, caret: at, "a second Enter below the very long line"); ctx.checkInk("below the very long line")
            ctx.snap("end")
        },

        // 줄바꿈 끔에서도 같다: 맨 아랫줄의 ↓·Enter·입력, 맨 윗줄의 ↑·Backspace 는 한 줄씩만 민다. 가로는 캐럿(선택을 늘리는 중이면 움직인 쪽 끝)이 보이는 열에 남는다
        Scenario(name: "typing-edge-nowrap") { ctx in
            let issues0 = ctx.issues.count   // 이 시나리오에서 난 문제만 센다 — 앞 시나리오가 남긴 문제(정지 한 번의 행 묶음 등)로 걸음을 건너뛰지 않게
            let saved = ViewDefaults(ctx)
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "edge-nowrap.md") }
            await ctx.withRelaxedStalls { ctx.model.wordWrap = false; await ctx.settle(300) }
            ctx.model.jump(toLine: 9000); await ctx.settle(500)
            ctx.at("no wrap: ↓ past the bottom edge")
            if await ctx.arrowWalk(.down, count: 40, "no wrap ↓") == 0 { ctx.issue("other", "no wrap ↓: 40 presses never reached the bottom edge") }
            ctx.checkX(0, "no wrap: ↓ along the first column")
            ctx.at("no wrap: ↑ past the top edge")
            if await ctx.arrowWalk(.up, count: 60, "no wrap ↑") == 0 { ctx.issue("other", "no wrap ↑: 60 presses never reached the top edge") }
            ctx.at("no wrap: ⇧↓ and ⇧↑ past the edges")
            await ctx.arrowWalk(.down, [.shift], count: 30, "no wrap ⇧↓")
            await ctx.arrowWalk(.up, [.shift], count: 50, "no wrap ⇧↑")
            await ctx.press(.left); await ctx.quiesce()
            ctx.snap("nowrap-arrows")

            // 맨 아랫줄 머리에서 Enter: 그 줄이 한 줄씩 밀려 내려간다 — 화면도 한 줄씩
            ctx.at("no wrap: Enter × 6 on the bottom line")
            guard let bottom = ctx.edgeParagraph(bottom: true), await ctx.clickCaret(bottom.offset, "the head of the bottom line (no wrap)") else {
                ctx.issue("other", "no wrap: could not put the caret on the bottom line"); await ctx.withRelaxedStalls { await saved.restore(ctx) }; return
            }
            let expect = NSMutableString(string: ctx.textCopy() as String)
            var at = ctx.caret
            var amounts: [CGFloat] = []
            for i in 1...6 {
                if let m = await ctx.edgeEdit("no wrap: Enter \(i) on the bottom line", { await ctx.press(.returnKey) }) { amounts.append(m) }
                expect.insert("\n", at: at); at += 1
            }
            ctx.note("no wrap: Enter on the bottom line moved the content by " + amounts.map { String(format: "%.1f", $0) }.joined(separator: ", ") + " pt")
            if amounts.count < 6 { ctx.issue("other", "no wrap: only \(amounts.count) of 6 Enter presses on the bottom line could be measured") }
            for (i, m) in amounts.enumerated().dropFirst() where abs(m - ctx.lineHeight) > 1 {
                ctx.issue("viewport-jump", "no wrap: Enter \(i + 1) on the bottom line moved the content by \(String(format: "%.1f", m)) pt, expected one line (\(String(format: "%.1f", ctx.lineHeight)))")
            }
            ctx.checkTyped(expect, caret: at, "no wrap: 6 × Enter on the bottom line"); ctx.checkInk("no wrap: 6 × Enter on the bottom line"); ctx.checkX(0, "no wrap: Enter at the head of a line")
            ctx.snap("nowrap-enters")

            // 맨 아랫줄에서 오른쪽 가장자리를 넘겨 친다: 가로로만 따라간다 (세로로는 움직이지 않는다)
            ctx.at("no wrap: type past the right edge on the bottom line")
            await ctx.press(.right, [.command]); await ctx.quiesce()
            at = ctx.caret
            var hidden = 0, movedUp = 0
            var hiddenAt: [String] = []
            let filler = " typing along the bottom line with word wrap off until the caret passes the right edge of the editor and then some more"
            for (i, ch) in (filler + filler).enumerated() {
                let m = await ctx.edgeEdit("no wrap: character \(i + 1) on the bottom line", mustStay: true, { await ctx.typeKeys(String(ch)) })
                expect.insert(String(ch), at: at); at += 1
                if let m, abs(m) > 0.5 { movedUp += 1 }
                if let r = ctx.tv.caretRect(at: ctx.caret), r.maxX > ctx.visible.maxX + 1 || r.minX < ctx.visible.minX - 1 {
                    hidden += 1
                    if hiddenAt.count < 3 { hiddenAt.append(String(format: "#%d caret x %.1f…%.1f, view x %.1f…%.1f, text view width %.1f", i + 1, r.minX, r.maxX, ctx.visible.minX, ctx.visible.maxX, ctx.tv.frame.width)) }
                }
                if ctx.issues.count - issues0 > 12 { break }
            }
            if hidden > 0 { ctx.issue("caret-hidden", "no wrap: typing \(filler.count * 2) characters on the bottom line left the caret outside the visible columns after \(hidden) of them (\(hiddenAt.joined(separator: "; ")))") }
            if ctx.visible.minX < 1 { ctx.issue("other", "no wrap: typing \(filler.count * 2) characters on the bottom line never passed the right edge — the scenario did not exercise the sideways follow") }
            ctx.note("no wrap: typing on the bottom line moved the view vertically \(movedUp) time(s); view x \(Int(ctx.visible.minX))")
            ctx.checkTyped(expect, caret: at, "no wrap: typed past the right edge on the bottom line"); ctx.checkCaretInView("no wrap: typed past the right edge on the bottom line")
            ctx.snap("nowrap-typed")

            // 긴 줄에서 ⇧← 로 선택을 왼쪽으로 늘린다: 움직이는 쪽 끝이 보이는 열에 남는다 (선택의 다른 끝은 화면 밖 오른쪽에 남는다)
            ctx.at("no wrap: ⇧← across the left edge of the view")
            hidden = 0
            let x0 = ctx.visible.minX
            for _ in 0..<120 {
                await ctx.press(.left, [.shift])
                let sel = ctx.tv.selectedRange()
                if let r = ctx.tv.caretRect(at: sel.location), r.maxX > ctx.visible.maxX + 1 || r.minX < ctx.visible.minX - 1 { hidden += 1 }
            }
            await ctx.quiesce()
            if ctx.tv.selectedRange().length != 120 { ctx.issue("selection", "no wrap: ⇧← × 120 selected \(ctx.tv.selectedRange().length) characters") }
            if hidden > 0 { ctx.issue("caret-hidden", "no wrap: ⇧← × 120 along the bottom line: the moving end of the selection was outside the visible columns after \(hidden) presses (view x \(Int(x0)) → \(Int(ctx.visible.minX)))") }
            if ctx.visible.minX > x0 - 1 { ctx.issue("other", "no wrap: ⇧← × 120 never passed the left edge of the view (x \(Int(x0)) → \(Int(ctx.visible.minX))) — the scenario did not exercise the sideways follow") }
            ctx.checkCaretLineWhole("no wrap: ⇧← × 120"); ctx.checkLayout("no wrap: ⇧← × 120")
            await ctx.press(.left); await ctx.quiesce()

            // 맨 윗줄 머리에서 Backspace: 화면 위로 나가 있는 윗줄과 합친다 — 한 줄만 올라온다
            ctx.at("no wrap: Backspace at the head of the top line")
            await ctx.press(.left, [.command]); await ctx.quiesce()
            ctx.model.jump(toLine: 7000); await ctx.settle(500)
            await ctx.scrollBy(ctx.lineHeight * 6); await ctx.settle(200)
            if let top = ctx.edgeParagraph(bottom: false), await ctx.clickCaret(top.offset, "the head of the top line (no wrap)") {
                let before = ctx.textCopy()
                await ctx.press(.delete); await ctx.quiesce()
                if ctx.length != before.length - 1 { ctx.issue("text", "no wrap: Backspace at the head of the top line changed the length by \(ctx.length - before.length)") }
                ctx.checkCaretInView("no wrap: Backspace joined the top line to the one above")
                if let c = ctx.caretOnScreen() {
                    ctx.note(String(format: "no wrap: the line above came into view: caret line at screen y %.1f…%.1f", c.top, c.bottom))
                    if c.top > 1.5 || c.top < -0.5 { ctx.issue("viewport-jump", "no wrap: Backspace at the head of the top line: the joined line sits at screen y \(String(format: "%.1f", c.top)) — it should be flush with the top edge (one line scrolled)") }
                }
                ctx.checkLayout("no wrap: Backspace joined the top line"); ctx.checkInk("no wrap: Backspace joined the top line")
            } else { ctx.issue("other", "no wrap: could not put the caret at the head of the top line") }
            ctx.snap("nowrap-end")

            // 비용: 4 MB 로그, 줄바꿈 끔 — 맨 아랫줄에서 ↓ 를 누르는 걸음당 시간
            ctx.at("no wrap, 4 MB log: ↓ on the bottom line")
            await ctx.withRelaxedStalls(20_000) { await ctx.open(.log, name: "edge-nowrap.log") }
            ctx.model.jump(toLine: 20_000); await ctx.settle(500)
            await ctx.key(.down, count: 14); await ctx.settle(100)
            var costs: [Double] = []
            let top0 = ctx.topLine()
            for _ in 0..<60 {
                let t0 = CFAbsoluteTimeGetCurrent()
                await ctx.key(.down); await ctx.settle(0)
                costs.append((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            }
            costs.sort()
            ctx.note(String(format: "no wrap, 4 MB log: ↓ × 60 from the bottom line — median %.1f ms, worst %.1f ms per press (key + layout + drawing); top line %d → %d", costs[costs.count / 2], costs.last ?? 0, top0, ctx.topLine()))
            // 한 줄 밀기는 뷰포트 배치 한 번이다 (실측 중앙값 6.2~6.6 ms; AppKit 이 가운데로 데려가던 때는 5.2 ms 에 여덟 걸음마다 한 번 30 ms).
            // 30 ms 를 넘으면 문서 크기에 비례하는 일이 걸음마다 돌고 있는 것이다
            if costs[costs.count / 2] > 30 { ctx.issue("slow", String(format: "no wrap, 4 MB log: ↓ on the bottom line costs %.1f ms per press (median)", costs[costs.count / 2]), snap: false) }
            if ctx.topLine() - top0 > 62 || ctx.topLine() - top0 < 40 { ctx.issue("viewport-jump", "no wrap, 4 MB log: ↓ × 60 from the bottom line moved the top line from \(top0) to \(ctx.topLine()), expected about 60 lines") }
            ctx.checkCaretLineWhole("no wrap, 4 MB log: after ↓ × 60"); ctx.checkAll("no wrap, 4 MB log: after ↓ × 60")
            await ctx.withRelaxedStalls(20_000) { await saved.restore(ctx) }
        },

        // 멀티 캐럿: 캐럿 하나가 화면 위(한 번도 배치하지 않은 곳)에 있을 때 치면, 화면에 보이는 머리 캐럿의 줄은 제자리에 있어야 한다.
        // 편집이 건드린 가장 앞 문단(화면 밖의 캐럿)의 자리는 어림이라 거기서부터 재면 머리 캐럿 줄의 자리가 틀린다
        Scenario(name: "typing-edge-multicaret") { ctx in
            for corpus in [RealUseContext.Corpus.notes, .wide] {
                let tag = corpus == .notes ? "notes" : "wide"
                await ctx.withRelaxedStalls { await ctx.open(corpus, name: "edge-multi-\(tag).md") }
                for (step, back) in [("a caret 30 lines above the screen", 30), ("a caret 12 lines above the screen", 12), ("a caret 55 lines above the screen", 55),
                                     ("a caret 400 lines above the screen", 400)].enumerated() {
                    // 본 적 없는 곳으로 뛴다 — 화면 위쪽은 배치돼 있지 않다
                    ctx.at("\(tag): \(back.0)")
                    ctx.model.jump(toLine: (corpus == .notes ? 9_000 : 1_500) + step * (corpus == .notes ? 1_200 : 700)); await ctx.settle(500)
                    let v = ctx.visible
                    let whole = ctx.viewportFragments().filter { $0.minY >= v.minY - 0.5 && $0.maxY <= v.maxY + 0.5 }
                    guard let first = whole.first, let head = whole.dropFirst(whole.count / 2).first else { ctx.issue("other", "\(tag): no whole paragraph on screen"); continue }
                    // 여러 번 감기는 문단의 문서에서는 짧은 줄(다섯째 줄마다)을 고른다 — 친 글자로 그 문단이 한 줄 더 감기면 아래의 글이 밀리는 것은 정상이라 잴 수 없다
                    var aboveLine = max(1, ctx.liveLine(first.offset) - back.1)
                    if corpus == .wide { aboveLine = max(5, aboveLine - aboveLine % 5) }
                    let above = ctx.lineStart(aboveLine)
                    ctx.tv.setMulti([NSRange(location: above, length: 0), NSRange(location: head.offset, length: 0)])
                    await ctx.settle(60)
                    guard ctx.tv.multi?.ranges.count == 2 else { ctx.issue("multi", "\(tag): could not set two carets"); continue }
                    guard let y0 = ctx.caretOnScreen()?.top else { ctx.issue("other", "\(tag): the head caret is not measurable"); continue }
                    var worst: CGFloat = 0, moves = 0, scrolled = 0
                    for ch in "multi" {
                        let before = ctx.caretOnScreen()?.top ?? y0, clip0 = ctx.scroll.contentView.bounds.minY
                        await ctx.typeKeys(String(ch)); await ctx.quiesce()
                        guard let now = ctx.caretOnScreen()?.top else { ctx.issue("caret-hidden", "\(tag): after typing with \(back.0) the head caret has no rect"); break }
                        if abs(now - before) > 0.5 { moves += 1; worst = max(worst, abs(now - before)) }
                        if abs(ctx.scroll.contentView.bounds.minY - clip0) > 0.5 { scrolled += 1 }
                        ctx.checkCaretLineWhole("\(tag): typed with \(back.0)"); ctx.checkLayout("\(tag): typed with \(back.0)")
                    }
                    let end = ctx.caretOnScreen()?.top ?? -1
                    ctx.note(String(format: "%@: typed 5 characters with %@ — the head caret line started at screen y %.1f, ended at %.1f; %d key(s) moved it (worst %.1f pt), %d key(s) scrolled the view",
                                    tag, back.0, y0, end, moves, worst, scrolled))
                    // 보는 것은 편집 뒤의 '캐럿 보이기'가 화면을 끌고 가는가다: 키 하나에 화면의 절반 넘게 밀렸거나 다섯 키 뒤에 그만큼 흘러가 있으면 그렇다
                    // (고치기 전: 키마다 192 pt — 382 pt 화면의 절반 — 또는 한 번에 1,047 … 2,052 pt).
                    // 그보다 작은 밀림은 남아 있고 기록만 한다. 편집이 화면 위에서 시작한 경우는 AppKit 의 '보이게 스크롤'에 맡기는데, TextKit 2 가 화면 위의 고쳐진
                    // 문단부터 높이를 다시 어림해 그 아래의 글이 밀리고(친 글자마다 0.6~1 pt, 한 번에 4 … 33 pt), 그 어림을 믿은 AppKit 이 보이는 캐럿을 다시
                    // 데려가기도 한다(앞선 시나리오가 조각 캐시를 흔든 뒤 실측 127 pt). 편집 뒤의 배치 패스는 스크롤 닻이 쉬어 바로잡히지 않는다
                    if worst > ctx.visible.height / 2 || abs(end - y0) > ctx.visible.height / 2 {
                        ctx.issue("viewport-jump", "\(tag): typing with \(back.0): the head caret line was on screen and should stay where it is, but it went from y \(String(format: "%.1f", y0)) to \(String(format: "%.1f", end)) (\(moves) of 5 keys moved it, the worst by \(String(format: "%.1f", worst)) pt; \(scrolled) of them scrolled the view)")
                    }
                    if ctx.tv.multi?.ranges.count != 2 { ctx.issue("multi", "\(tag): typing with two carets left \(ctx.tv.multi?.ranges.count ?? 1) caret(s)") }
                    let ns = ctx.text
                    if !(ns.substring(with: NSRange(location: above, length: 5)) == "multi") { ctx.issue("text", "\(tag): the caret above the screen did not receive the typed text") }
                    ctx.checkInk("\(tag): typed with \(back.0)")
                    await ctx.press(.escape); await ctx.settle(60)
                }
                ctx.snap("\(tag)-end")
            }
        },
    ]
}
