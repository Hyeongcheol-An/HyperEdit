import AppKit
import HyperCore

// 실사용 시뮬레이션 — 접힌 글 지키기 (2). RealUse+FoldGuard.swift 와 같은 기준이다: 사용자가 보지 못하는 글이 사용자 모르게 지워지거나 바뀌지 않는가.
// 여기서는 접힘이 **나중에** 닫히는 쪽(캐럿·열 블록이 이미 놓인 영역을 접는다)과, 접힘에 바로 붙어 있지 않은 자리에서의 단어 걸음을 본다.

extension RealUseContext {
    /// 지금의 캐럿·선택들 (여러 캐럿·열 블록이면 그 범위들, 아니면 네이티브 선택)
    var carets: [NSRange] { tv.multi?.ranges ?? [tv.selectedRange()] }

    /// 닫힌 접힘 안에 놓인 캐럿·선택 끝 (화면에 그려지지 않는다)
    func caretsOnHiddenLines() -> [NSRange] {
        carets.filter { r in
            if hidden(r.location) { return true }
            guard r.length > 0, let span = tv.foldedSpan?(NSMaxRange(r)) else { return false }
            return NSMaxRange(r) > span.location && NSMaxRange(r) < NSMaxRange(span)
        }
    }

    /// 첫 자리는 클릭, 나머지는 ⌘클릭으로 캐럿을 놓는다 (모두 화면에 보이는 자리여야 한다)
    func placeCarets(_ offsets: [Int], _ why: String) async -> Bool {
        guard let first = offsets.first, await clickExpect(first, "\(why): click the first caret") else { return false }
        for o in offsets.dropFirst() {
            guard await mclick(offset: o, mods: [.command]) else { issue("other", "\(why): \(place(o)) is not on screen to ⌘-click"); return false }
        }
        await settle(60)
        let got = carets.map(\.location)
        if got != offsets.sorted() { issue("multi", "\(why): ⌘-clicking \(offsets.count) places made carets at \(got), expected \(offsets.sorted())"); return false }
        return true
    }

    func describe(_ ranges: [NSRange]) -> String {
        ranges.map { $0.length == 0 ? "line \(liveLine($0.location)) col \($0.location - lineStart(liveLine($0.location)))" : "{\($0.location), \($0.length)}" }.joined(separator: ", ")
    }

    /// 캐럿·블록을 놓고(`place`) → 그 가운데 일부가 든 영역을 접고(`fold`) → 글자를 친다.
    /// 접은 뒤: 닫힌 접힘 안에 캐럿·행이 남아 있으면 안 된다 (그려지지 않는 캐럿이 다음 키를 받는다). 친 뒤: 숨어 있던 글은 그대로여야 하고 접힘도 닫힌 채여야 한다 —
    /// 글자는 접은 뒤에 보이던 캐럿 자리에만 들어간다. `expect` 가 있으면 접은 뒤의 캐럿 자리도 견준다. 끝나면 글을 되돌리고 모두 편다
    func foldUnderCarets(_ why: String, hides line: Int, snap name: String? = nil, expect: (() -> [NSRange])? = nil, place: () async -> Bool, fold: () async -> Void) async {
        at(why)
        model.send(.unfoldAll); await settle(150)
        if tv.multi != nil { await key(.escape) }
        let original = textCopy()
        guard await place() else { return }
        let placed = carets
        await fold(); await settle(300)
        defer { flushMouseEvents() }
        guard hidden(line: line), let span = tv.foldedSpan?(lineStart(line)) else { issue("other", "\(why): line \(line) is not folded — the step did not run"); return }
        let after = carets
        let stuck = caretsOnHiddenLines()
        note("\(why): carets \(describe(placed)) → after folding \(describe(after)) (\(tv.multi == nil ? "single selection" : tv.multi?.block != nil ? "column block" : "multi"))")
        if !stuck.isEmpty {
            issue("fold", "\(why): \(stuck.count) of \(after.count) carets/rows are inside the closed fold (\(describe(stuck))) — they are not drawn, and the next key edits lines that are not on screen")
        }
        if let want = expect?(), after != want { issue("fold", "\(why): after folding the carets are at \(describe(after)), expected \(describe(want))") }
        checkCaretVisible(why)
        if let name { snap(name) }
        let hiddenText = text.substring(with: span)
        await pumpEvent(); tv.breakUndoCoalescing()
        await type("Q"); await pumpEvent(); await settle(300)
        // 숨어 있던 글이 그대로 있고(연달아 같은 글자들), 접힘이 닫힌 채인가
        let now = text
        let kept = now.range(of: hiddenText).location != NSNotFound
        if !kept { issue("fold-loss", "\(why): typing one character changed the \(span.length) characters that were folded away (text \(original.length) → \(now.length) characters)") }
        if !hidden(line: line) { issue("fold", "\(why): typing one character opened the fold — a caret was inside it") }
        // 글자는 접은 뒤의 캐럿 자리마다 하나씩
        let m = NSMutableString(string: original as String)
        for r in after.sorted(by: { $0.location > $1.location }) { m.replaceCharacters(in: r, with: "Q") }
        if stuck.isEmpty, !now.isEqual(to: m as String) { issue("text", "\(why): typing Q at \(describe(after)) gave \(now.length) characters, expected \(m.length)") }
        checkAllD(why); checkFoldState(why); checkInk(why)
        await restoreText(original, why)
        model.send(.unfoldAll); await settle(150)
    }
}

extension RealUseContext {
    /// 글의 줄 끝을 센다: \r\n 쌍 · 혼자인 \r · 혼자인 \n
    func lineEndings() -> [Int] {
        let ns = text
        var crlf = 0, cr = 0, lf = 0, i = 0
        while i < ns.length {
            let c = ns.character(at: i)
            if c == 13 {
                if i + 1 < ns.length, ns.character(at: i + 1) == 10 { crlf += 1; i += 2; continue }
                cr += 1
            } else if c == 10 { lf += 1 }
            i += 1
        }
        return [crlf, cr, lf]
    }

    /// 줄의 내용 끝 — \r\n 으로 끝나는 줄이면 \r 앞 (`lineEnd` 는 \n 앞, 곧 \r 과 \n 사이를 준다)
    func contentEnd(_ line: Int) -> Int {
        let end = lineEnd(line)
        return end > lineStart(line) && text.character(at: end - 1) == 13 ? end - 1 : end
    }

    /// 범위 안의 글자 가운데 닫힌 접힘에 숨어 있는 것의 수 (문단 단위로 센다)
    func hiddenCharacters(in range: NSRange) -> Int {
        let ns = text
        var n = 0, p = range.location
        while p < NSMaxRange(range), p < ns.length {
            let para = ns.paragraphRange(for: NSRange(location: p, length: 0))
            let end = min(NSMaxRange(para), NSMaxRange(range))
            if hidden(para.location) { n += end - p }
            p = max(end, p + 1)
        }
        return n
    }

    /// sameAsUnfolded 의 일반형 — 접는 방법을 직접 준다(겹쳐 접기·모두 접기). 걸음(`step`)과 편집(`edit`)을 갈라 본다: 걸음 뒤의 선택이 편 문서에서와 같은지,
    /// 닫힌 접힘에 숨은 글자를 품고 있지 않은지(고른 것이 화면에 다 보이는지), 그리고 편집 결과가 편 문서와 같은지. 끝나면 글을 되돌리고 모두 편다
    @discardableResult
    func sameAsOpenDocument(_ label: String, undos: Int = 1, folding: () async -> Bool, place: () async -> Bool, step: () async -> Void, edit: (() async -> Void)? = nil,
                            after: (() -> Void)? = nil) async -> Bool {
        at(label)
        model.send(.unfoldAll); await settle(150)
        let original = textCopy()
        guard await place() else { return false }
        await pumpEvent(); tv.breakUndoCoalescing()
        await step(); await settle(80)
        let referenceSelection = tv.selectedRange()
        if let edit { await edit(); await pumpEvent(); await settle(150) }
        let reference = textCopy()
        await restoreText(original, undos: edit == nil ? 0 : undos, "\(label) (open document)")
        guard await folding() else { issue("other", "\(label): the regions did not fold — the step did not run"); model.send(.unfoldAll); await settle(150); return false }
        guard await place() else { model.send(.unfoldAll); await settle(150); return false }
        await pumpEvent(); tv.breakUndoCoalescing()
        await step(); await settle(150)
        let selection = tv.selectedRange()
        var same = true
        note("\(label): the step selects \(selection) with the regions folded, \(referenceSelection) in the open document; \(hiddenCharacters(in: selection)) selected characters are hidden; \(foldCount()) pill(s) left")
        if selection != referenceSelection { same = false; issue("fold", "\(label): the step selects \(selection) with the regions folded, \(referenceSelection) in the open document") }
        let unseen = hiddenCharacters(in: selection)
        if unseen > 0 || hidden(selection.location) {
            same = false
            issue("fold", "\(label): \(unseen) of the \(selection.length) selected characters are inside closed folds — they are selected without being on screen")
        }
        after?()
        if let edit {
            await edit(); await pumpEvent(); await settle(300)
            let result = textCopy()
            note("\(label): open document \(original.length) → \(reference.length) characters, folded \(original.length) → \(result.length)")
            if !result.isEqual(to: reference as String) {
                same = false
                issue("fold-loss", "\(label): with the regions folded the text went from \(original.length) to \(result.length) characters, in the open document the same keys give \(reference.length)")
            }
        }
        checkAllD(label); checkFoldState(label); checkInk(label)
        await restoreText(original, undos: edit == nil ? 0 : undos, "\(label) (folded document)")
        model.send(.unfoldAll); await settle(150)
        return same
    }
}

extension RealUse {
    /// 겹친 영역(JSON): 바깥 `[`(2…10) 안에 낱말이 없는 `[`(3…5)와 `{`(7…9). 안쪽 머리 줄들에 낱말이 없어서 낱말 걸음이 바깥 머리 줄에서 안쪽 접힘 속으로 곧장 간다
    static let nestedDoc = ["[", "  [", "    {},", "    {}", "  ],", "  {", "    \"name\": \"a\",", "    \"size\": 1", "  }", "]", "end line"].joined(separator: "\n") + "\n"

    /// 오른쪽→왼쪽 문단(히브리어)의 마크다운: 제목 줄이 문장 부호로 끝나고(낱말 걸음이 다음 줄로 넘어간다), 접힘 아래의 제목은 `## ` 로 시작한다. 영역: 2(3…4)
    static let rtlFoldDoc = ["שורת פתיחה רגילה", "## כותרת ראשונה (א):", "גוף ראשון בתוך הסעיף", "גוף שני בתוך הסעיף", "", "## כותרת שנייה", "גוף של הסעיף השני", ""].joined(separator: "\n")

    /// 머리 줄은 길고 그 아래 숨는 줄은 짧은 문서 — 열 블록을 머리 줄의 오른쪽 열에서 아래로 늘이면 숨은 줄의 행은 폭이 0 이다. 영역: 2(3…4)
    static let shortBodyDoc = [
        "a plain first line that is long enough here",   // 1
        "def a_long_header_name(argument_one):",          // 2
        "    short",                                      // 3
        "    tiny",                                       // 4
        "after the fold, a line that is long enough",     // 5
        "the last line of this small document here",      // 6
    ].joined(separator: "\n") + "\n"

    @MainActor static let foldGuard2Scenarios: [Scenario] = [
        // 여러 캐럿·열 블록이 놓인 영역을 접는다(거터 화살표·접기·모두 접기, 분할의 다른 편집기에서): 닫힌 접힘 안에 캐럿이 남아 다음 키가 숨은 줄을 고치지 않는가
        Scenario(name: "fold-multicaret") { ctx in
            await ctx.open(text: RealUse.guardDoc, name: "fold-multicaret.py")
            await ctx.settle(700)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            guard ctx.markers(inLines: 1...13)[7] == .foldable, ctx.markers(inLines: 1...13)[2] == .foldable else { ctx.issue("other", "the guard document has no foldable regions at lines 2 and 7"); return }
            @MainActor func offset(_ line: Int, _ col: Int?) -> Int { col.map { ctx.lineStart(line) + $0 } ?? ctx.lineEnd(line) }
            @MainActor func arrow(_ line: Int) -> () async -> Void {
                { if let p = ctx.foldArrowPoint(forLine: line) { await ctx.clickGutter(at: p) } else { ctx.issue("other", "no fold arrow on screen for line \(line)") } }
            }
            // ① 캐럿 셋(8·9·12번 줄 — 머리는 12번 줄)인 채 7번 줄의 영역을 접는다: 숨은 캐럿 둘은 머리 줄 끝 하나로 모인다
            await ctx.foldUnderCarets("carets on lines 8, 9 and 12, fold line 7 with the gutter arrow", hides: 8, snap: "carets-folded",
                                      expect: { [NSRange(location: offset(7, nil), length: 0), NSRange(location: offset(12, 4), length: 0)] },
                                      place: { await ctx.placeCarets([offset(8, 4), offset(9, 4), offset(12, 4)], "three carets") }, fold: arrow(7))
            await ctx.foldUnderCarets("carets on lines 8, 9 and 12, toggle the fold of line 7", hides: 8,
                                      place: { await ctx.placeCarets([offset(8, 4), offset(9, 4), offset(12, 4)], "three carets") }) { ctx.model.send(.toggleFold(line: 7)) }
            // ② 머리 캐럿이 숨는 쪽: 6·9번 줄의 캐럿(머리는 9번 줄)에서 접기 명령 — 보이는 캐럿(6번 줄)은 남는다
            await ctx.foldUnderCarets("carets on lines 6 and 9, Fold at the head caret", hides: 8,
                                      expect: { [NSRange(location: offset(6, 5), length: 0), NSRange(location: offset(7, nil), length: 0)] },
                                      place: { await ctx.placeCarets([offset(6, 5), offset(9, 4)], "two carets") }) { ctx.model.send(.fold) }
            // ③ 모두 접기: 3번 줄(두 겹으로 숨는다)·6번 줄(보인다)·13번 줄(끝까지 닿는 접힘 안)
            await ctx.foldUnderCarets("carets on lines 3, 6 and 13, Fold All", hides: 3,
                                      expect: { [NSRange(location: offset(1, nil), length: 0), NSRange(location: offset(6, 5), length: 0), NSRange(location: offset(11, nil), length: 0)] },
                                      place: { await ctx.placeCarets([offset(3, 8), offset(6, 5), offset(13, 4)], "three carets") }) { ctx.model.send(.foldAll) }
            // ④ 모든 일치를 고른 채(길이 있는 선택 셋 — 둘은 숨는다) 접는다
            await ctx.foldUnderCarets("all matches of 'third' selected, fold line 7", hides: 8, place: {
                let gen = ctx.model.searchCompletionCount
                ctx.model.searchQuery = "third"; ctx.model.runSearch()
                guard await ctx.awaitSearch(after: gen), ctx.model.searchHits.count == 3 else { ctx.issue("find", "'third' found \(ctx.model.searchHits.count) matches, expected 3"); return false }
                ctx.model.selectAllMatches(); await ctx.settle(150)
                // 찾기는 여기서 끝낸다 — 켜 둔 채 글을 고치면 다시 찾기가 지금 일치(숨은 줄의 것)로 가며 그 접힘을 편다 (그것은 찾기의 일이다)
                ctx.model.searchQuery = ""; ctx.model.runSearch(); await ctx.settle(200)
                return ctx.tv.multi?.ranges.count == 3
            }, fold: arrow(7))
            // ⑤ 폭 0 인 ⌥끌기 블록(6~10번 줄)인 채 접는다: 블록은 줄을 건너뛸 수 없으므로 머리 캐럿 하나로 접힌다
            @MainActor func block(_ why: String) async -> Bool {
                guard let a = ctx.point(forOffset: offset(6, 2)), let b = ctx.point(forOffset: offset(10, 2)) else { ctx.issue("other", "\(why): lines 6 and 10 are not on screen"); return false }
                await ctx.dragWith(mods: [.option], from: a, to: b); await ctx.settle(120)
                guard let m = ctx.tv.multi, m.isColumn, m.ranges.count == 5 else { ctx.issue("multi", "\(why): ⌥-drag over lines 6…10 made \(ctx.tv.multi?.ranges.count ?? 0) rows"); return false }
                return true
            }
            await ctx.foldUnderCarets("zero-width column block over lines 6…10, fold line 7 with the gutter arrow", hides: 8, snap: "block-folded",
                                      place: { await block("⌥-drag") }, fold: arrow(7))
            await ctx.foldUnderCarets("zero-width column block over lines 6…10, Fold All", hides: 8, place: { await block("⌥-drag") }) { ctx.model.send(.foldAll) }
            // 캐럿이 모두 보이는 곳에 있으면 접어도 그대로다
            await ctx.foldUnderCarets("carets on lines 6, 10 and 12 (none inside), fold line 7", hides: 8,
                                      expect: { [offset(6, 5), offset(10, 4), offset(12, 4)].map { NSRange(location: $0, length: 0) } },
                                      place: { await ctx.placeCarets([offset(6, 5), offset(10, 4), offset(12, 4)], "three carets") }, fold: arrow(7))

            // ⑥ 분할: 보조 편집기에 블록, 주 편집기에서 접는다 (접힘은 문서의 것) — 보조 편집기는 보던 곳 그대로, 숨은 행은 없어야 한다
            ctx.at("split: a column block in the other editor, fold here")
            ctx.model.send(.unfoldAll); await ctx.settle(150)
            ctx.model.setSplit(.vertical); await ctx.settle(900)
            if let p = ctx.model.session.primary?.textView, let s = ctx.model.session.secondary?.textView, p !== s {
                ctx.window.makeFirstResponder(s); await ctx.settle(80)
                s.setBlock(ColumnBlock(topLineStart: ctx.lineStart(6), lineCount: 5, anchorCol: 2, headCol: 2)); await ctx.settle(80)
                ctx.window.makeFirstResponder(p); await ctx.settle(80)
                p.setSelectedRange(NSRange(location: offset(1, 3), length: 0))
                ctx.model.send(.toggleFold(line: 7)); await ctx.settle(300)
                let rows = s.multi?.ranges ?? [s.selectedRange()]
                let stuck = rows.filter { s.isOffsetHidden?($0.location) ?? false }
                ctx.note("split: the other editor's block → \(ctx.describe(rows)); line 8 hidden \(ctx.hidden(line: 8, in: s))")
                ctx.expect(ctx.hidden(line: 8, in: s) && ctx.hidden(line: 8, in: p), "fold", "split: folding line 7 here did not fold both editors")
                if !stuck.isEmpty { ctx.issue("fold", "split: \(stuck.count) of \(rows.count) rows of the other editor's block are inside the closed fold (\(ctx.describe(stuck)))") }
                let before = ctx.textCopy()
                ctx.window.makeFirstResponder(s); await ctx.settle(80)
                await ctx.pumpEvent(); s.breakUndoCoalescing()
                s.insertText("Q", replacementRange: NSRange(location: NSNotFound, length: 0)); await ctx.pumpEvent(); await ctx.settle(300)
                let hiddenText = before.substring(with: NSRange(location: ctx.lineStart(8), length: ctx.lineStart(10) - ctx.lineStart(8)))
                ctx.expect(ctx.text.range(of: hiddenText).location != NSNotFound && ctx.hidden(line: 8, in: p), "fold-loss",
                           "split: typing in the other editor changed the folded lines (text \(before.length) → \(ctx.length) characters, line 8 hidden \(ctx.hidden(line: 8, in: p)))")
                ctx.checkNoHiddenOnScreen("split: primary", in: p); ctx.checkNoHiddenOnScreen("split: secondary", in: s)
                ctx.snap("split")
                if s.multi != nil { s.doCommand(by: #selector(NSResponder.cancelOperation(_:))) }
                ctx.window.makeFirstResponder(p); await ctx.settle(80)
                await ctx.restoreText(before, "split: undo the typing")
            } else { ctx.issue("other", "the split did not produce two editors") }
            ctx.model.send(.unfoldAll); await ctx.settle(150)
            ctx.model.setSplit(.none); await ctx.settle(700)

            // ⑦ 열 모드에서 긴 접힌 머리 줄의 오른쪽 열 블록을 ⇧↓ 로 늘인다: 숨은 줄은 그 열보다 짧아 행의 폭이 0 이다 — 네이티브 선택(길이 있는 범위들)은
            //    그대로라 선택 변경 통지에 기대면 접힘이 닫힌 채 남는다
            await ctx.open(text: RealUse.shortBodyDoc, name: "fold-multicaret-short.py")
            await ctx.settle(700)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            ctx.at("column mode: a block at columns 20…22 of a long folded header, ⇧↓ over shorter hidden lines")
            ctx.model.columnMode = true; await ctx.settle(80)
            await ctx.sameAsUnfolded("type into a block extended with ⇧↓ over short hidden lines", fold: 2, place: {
                guard await ctx.clickExpect(ctx.lineStart(2) + 20, "click column 20 of the folded header") else { return false }
                await ctx.key(.right, [.shift]); await ctx.key(.right, [.shift])
                await ctx.key(.down, [.shift]); await ctx.key(.down, [.shift]); await ctx.settle(120)
                guard let m = ctx.tv.multi, m.isColumn, m.ranges.count == 3 else { ctx.issue("multi", "⇧→⇧→⇧↓⇧↓ in column mode made \(ctx.tv.multi?.ranges.count ?? 0) rows, expected 3"); return false }
                return true
            }, ready: { span in
                let stuck = ctx.caretsOnHiddenLines()
                ctx.note("block over short hidden lines: rows \(ctx.describe(ctx.carets)), native selection \(ctx.tv.selectedRanges.map(\.rangeValue)), fold \(ctx.hidden(span.location) ? "closed" : "open")")
                if !stuck.isEmpty { ctx.issue("fold", "block extended with ⇧↓ over short hidden lines: \(stuck.count) rows sit on hidden lines (\(ctx.describe(stuck))) — the next key pads and edits lines that are not on screen") }
            }) { await ctx.type("W") }
            ctx.model.columnMode = false; await ctx.settle(80)
            ctx.snap("end")
        },

        // 단어 걸음(⌥←/→ 와 ⇧ 변형)이 접힘에 바로 붙어 있지 않은 자리에서 접힘을 건너뛰는가: 숨은 문단은 배치에 없어서 AppKit 의 걸음이 그것을 넘어가면
        // 선택이 닫힌 접힘을 통째로 걸치고, 이어지는 ⌫ 가 숨은 줄들을 지운다. 그리고 머리 줄의 개행만 고른 선택(접힘은 닫힌 채)에서의 ⇧ 키
        Scenario(name: "fold-wordstep") { ctx in
            await ctx.open(text: RealUse.guardDoc, name: "fold-wordstep.py")
            await ctx.settle(700)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            @MainActor func offset(_ line: Int, _ col: Int?) -> Int { col.map { ctx.lineStart(line) + $0 } ?? ctx.lineEnd(line) }
            @MainActor func caretCase(_ label: String, fold header: Int, line: Int, col: Int?, undos: Int = 1, _ act: () async -> Void) async {
                ctx.at(label)
                await ctx.sameAsUnfolded(label, fold: header, undos: undos, place: { await ctx.clickExpect(offset(line, col), "\(label): place the caret") }, act: act)
            }
            // ① 선택을 늘리는 단어 걸음 뒤에 지운다 — 편 문서에서 같은 키로 지워지는 글과 같아야 한다
            await caretCase("⇧⌥→ after the z of a folded header, then ⌫", fold: 7, line: 7, col: 11) { await ctx.key(.right, [.shift, .option]); await ctx.pumpEvent(); await ctx.key(.delete) }
            ctx.snap("word-right-delete")
            await caretCase("⇧⌥→ twice after the z of a folded header, then ⌫", fold: 7, line: 7, col: 11) {
                await ctx.key(.right, [.shift, .option]); await ctx.key(.right, [.shift, .option]); await ctx.pumpEvent(); await ctx.key(.delete)
            }
            await caretCase("⇧⌥→ inside the folded header, then ⌫", fold: 7, line: 7, col: 5) { await ctx.key(.right, [.shift, .option]); await ctx.pumpEvent(); await ctx.key(.delete) }
            await caretCase("⇧⌥← after the indentation of the line below a fold, then ⌫", fold: 2, line: 5, col: 4) { await ctx.key(.left, [.shift, .option]); await ctx.pumpEvent(); await ctx.key(.delete) }
            await caretCase("⇧⌥← after the first word of the line below a fold, twice, then ⌫", fold: 7, line: 10, col: 4) {
                await ctx.key(.left, [.shift, .option]); await ctx.key(.left, [.shift, .option]); await ctx.pumpEvent(); await ctx.key(.delete)
            }
            await caretCase("⇧⌥→ after the colon of the header of a fold that reaches the end, then ⌫", fold: 11, line: 11, col: 4) { await ctx.key(.right, [.shift, .option]); await ctx.pumpEvent(); await ctx.key(.delete) }
            // ② 선택 없는 단어 걸음 뒤에 친다 — 글자가 들어가는 자리가 편 문서와 같아야 한다
            await caretCase("⌥→ after the z of a folded header, then type", fold: 7, line: 7, col: 11) { await ctx.key(.right, [.option]); await ctx.type("X") }
            await caretCase("⌥← after the indentation of the line below a fold, then type", fold: 2, line: 5, col: 4) { await ctx.key(.left, [.option]); await ctx.type("X") }
            await caretCase("⌥← inside the first word of the line below a fold, twice, then type", fold: 7, line: 10, col: 2) { await ctx.key(.left, [.option]); await ctx.key(.left, [.option]); await ctx.type("X") }
            // ③ 걸음만: 편 문서에서 숨을 줄로 들어가는 걸음은 접힌 문서에서 그 접힘을 펴야 한다 (닫힌 채 넘어가거나, 아무 일도 없으면 안 된다)
            for (c, line, col) in [("moveWordRight:", 7, 11), ("moveWordRightAndModifySelection:", 7, 11), ("moveWordForward:", 7, 11), ("moveWordForwardAndModifySelection:", 7, 12),
                                   ("moveWordRight:", 7, 13), ("moveWordRightAndModifySelection:", 7, 13)] as [(String, Int, Int)] {
                ctx.at("\(c) at line \(line) col \(col), near the end of a folded header")
                await ctx.sameMoveAsUnfolded("line \(line) col \(col)", fold: 7, place: { await ctx.clickExpect(offset(line, col), "click line \(line) col \(col)") }, [c])
            }
            for (c, line, col) in [("moveWordLeft:", 5, 4), ("moveWordLeftAndModifySelection:", 5, 4), ("moveWordBackward:", 5, 4), ("moveWordBackwardAndModifySelection:", 5, 2),
                                   ("moveWordLeft:", 5, 0), ("moveWordLeftAndModifySelection:", 5, 0)] as [(String, Int, Int)] {
                ctx.at("\(c) at line \(line) col \(col), below a fold")
                await ctx.sameMoveAsUnfolded("line \(line) col \(col)", fold: 2, place: { await ctx.clickExpect(offset(line, col), "click line \(line) col \(col)") }, [c])
            }
            // ④ 머리 줄 끝에서 ⇧→ 로 개행만 고른 뒤(접힘은 닫힌 채 — 경계 규칙) 줄 끝·문단 끝으로 늘이는 키: 편 문서에서는 첫 숨은 줄을 고른다.
            //    접힌 문서에서 아무 일도 일어나지 않으면 안 된다 (몇 번을 눌러도 그대로였다)
            for c in ["moveToRightEndOfLineAndModifySelection:", "moveToEndOfLineAndModifySelection:", "moveParagraphForwardAndModifySelection:", "moveToEndOfParagraphAndModifySelection:",
                      "moveRightAndModifySelection:", "moveWordRightAndModifySelection:", "moveDownAndModifySelection:"] {
                ctx.at("⇧→ at the end of a folded header, then \(c)")
                await ctx.sameMoveAsUnfolded("⇧→ then \(c)", fold: 7, place: { await ctx.clickExpect(offset(7, nil), "click the end of the folded header") }, ["moveRightAndModifySelection:", c])
            }
            ctx.at("⇧⌥↓ twice at the end of a folded header")
            await ctx.sameMoveAsUnfolded("⇧⌥↓ twice", fold: 7, place: { await ctx.clickExpect(offset(7, nil), "click the end of the folded header") },
                                         ["moveParagraphForwardAndModifySelection:", "moveParagraphForwardAndModifySelection:"])
            // ⑤ 선택을 줄이는 걸음: 움직이는 끝(머리)은 접힘에서 먼 쪽이다 — 접힘 옆에 놓인 닻에서 걸음을 재면 닫혀 있어야 할 접힘이 펴진다.
            //    뒤로 고른 선택(닻 = 접힌 머리 줄 끝)을 ⇧⌥→ 로, 앞으로 고른 선택(닻 = 접힘 아래 줄 머리)을 ⇧⌥← 로 줄인다
            let left3 = Array(repeating: "moveLeftAndModifySelection:", count: 3), right3 = Array(repeating: "moveRightAndModifySelection:", count: 3)
            ctx.at("⇧←×3 from the end of a folded header, then ⇧⌥→ shrinks the selection")
            await ctx.sameMoveAsUnfolded("shrink a backward selection with ⇧⌥→", fold: 7, place: { await ctx.clickExpect(offset(7, nil), "click the end of the folded header") }, left3 + ["moveWordRightAndModifySelection:"])
            ctx.at("⇧←×3 from the end of a folded header, then ⇧→")
            await ctx.sameMoveAsUnfolded("shrink a backward selection with ⇧→", fold: 7, place: { await ctx.clickExpect(offset(7, nil), "click the end of the folded header") }, left3 + ["moveRightAndModifySelection:"])
            ctx.at("⇧→×3 from the start of the line below a fold, then ⇧⌥← shrinks the selection")
            await ctx.sameMoveAsUnfolded("shrink a forward selection with ⇧⌥←", fold: 7, place: { await ctx.clickExpect(offset(10, 0), "click the start of the line below the fold") }, right3 + ["moveWordLeftAndModifySelection:"])
            ctx.at("⇧→×3 from the start of the line below a fold, then ⇧⌘←")
            await ctx.sameMoveAsUnfolded("shrink a forward selection with ⇧⌘←", fold: 7, place: { await ctx.clickExpect(offset(10, 0), "click the start of the line below the fold") }, right3 + ["moveToLeftEndOfLineAndModifySelection:"])
            // 닻을 넘어 뒤집히는 걸음은 접힘으로 들어간다 (머리가 닻 너머의 숨은 줄에 놓인다): ⇧←×2 뒤 ⇧⌥→ 두 번
            ctx.at("⇧←×2 from the end of a folded header, then ⇧⌥→ twice crosses the anchor into the fold")
            await ctx.sameMoveAsUnfolded("⇧⌥→ past the anchor", fold: 7, place: { await ctx.clickExpect(offset(7, nil), "click the end of the folded header") },
                                         ["moveLeftAndModifySelection:", "moveLeftAndModifySelection:", "moveWordRightAndModifySelection:", "moveWordRightAndModifySelection:"])
            // 거울상: 접힘 아래 줄 머리에서 ⇧← 로 앞 줄의 개행을 고르면 선택의 머리가 숨은 줄 끝에 놓인다 — 그 접힘은 펴진다
            for c in ["moveToLeftEndOfLineAndModifySelection:", "moveParagraphBackwardAndModifySelection:", "moveLeftAndModifySelection:"] {
                ctx.at("⇧← at the start of the line below a fold, then \(c)")
                await ctx.sameMoveAsUnfolded("⇧← then \(c)", fold: 7, place: { await ctx.clickExpect(offset(10, 0), "click the start of the line below the fold") }, ["moveLeftAndModifySelection:", c])
            }
            ctx.snap("end")
        },

        // 화면보다 긴 접힘이 편집·다시 스캔으로 펴질 때: 쓰고 있던 줄(캐럿)이 화면에 남는가. 다시 스캔이 펴는 접힘은 250 ms 뒤의 다시 배치에서 펴진다 —
        // 그 배치가 맨 위 줄을 지키면 그 아래의 캐럿 줄은 펴진 높이만큼 밀려 화면 밖으로 나간다 (두세 줄짜리 접힘으로는 보이지 않는다)
        Scenario(name: "fold-tall") { ctx in
            let big = RealUse.bigRegionDoc(lines: 60, around: 40)
            await ctx.open(text: big.text, name: "fold-tall.txt")
            await ctx.settle(900)
            let header = big.header, below = big.header + 61
            @MainActor func y(_ v: CGFloat?) -> String { v.map { String(format: "%.1f", $0) } ?? "off screen" }
            /// 접고 → 접힘 아래 줄의 머리에 캐럿 → 편집. 지운 자리(숨어 있던 마지막 줄의 끝)로는 AppKit 이 화면을 데려온다 — 그 뒤의 다시 배치가 그 줄을 밀어내지
            /// 않는지를 본다. **이 걸음은 회귀 감시다 — 캐럿 닻(FoldStore 의 미뤄진 다시 배치)을 넣기 전에도 통과한다**: 편집이 편 접힘의 줄들은 편집 직후의 첫
            /// 배치에서 이미 놓이므로 한 턴 뒤의 다시 배치는 화면을 바꾸지 않는다. 캐럿 닻이 고친 것은 아래의 걸음(다시 스캔이 접힘을 펼 때)이다
            @MainActor func editBelow(_ why: String, _ act: () async -> Void) async {
                ctx.at(why)
                ctx.model.send(.unfoldAll); await ctx.settle(150)
                await ctx.look(atLine: header - 3)
                ctx.model.send(.toggleFold(line: header)); await ctx.settle(300)
                guard ctx.hidden(line: header + 1), ctx.hidden(line: header + 60), !ctx.hidden(line: below) else { ctx.issue("other", "\(why): the 60-line region did not fold"); return }
                let original = ctx.textCopy()
                guard await ctx.clickExpect(ctx.lineStart(below), "\(why): click the start of the line below the fold") else { return }
                let y0 = ctx.caretLineScreenY()
                await ctx.pumpEvent(); ctx.tv.breakUndoCoalescing()
                await act()
                let yEdit = ctx.caretLineScreenY()
                await ctx.pumpEvent(); await ctx.settle(400)
                let y1 = ctx.caretLineScreenY()
                ctx.note("\(why): caret line at y \(y(y0)) before, \(y(yEdit)) right after the key, \(y(y1)) once the opened lines are laid out; caret \(ctx.place(ctx.caret)); fold \(ctx.foldsActive ? "closed" : "open"); viewport \(Int(ctx.visible.height))")
                ctx.expect(!ctx.foldsActive, "fold", "\(why): the key changed hidden text but the fold is still closed")
                // 지운 자리는 숨어 있던 마지막 줄의 끝이다 — 편집기가 그 줄을 화면에 데려온다(가운데쯤). 그 뒤의 다시 배치가 그 줄을 다시 밀어내면 안 된다
                ctx.checkCaretVisible(why)
                if y1 == nil { ctx.issue("caret-hidden", "\(why): after the fold opened the caret line is off screen (it was at y \(y(y0)), \(y(yEdit)) right after the key)") }
                else if let yEdit, let y1, abs(y1 - yEdit) > 2 { ctx.issue("viewport-jump", "\(why): the caret line was at y \(y(yEdit)) right after the key, then moved to \(y(y1)) when the opened lines were laid out") }
                ctx.checkAllD(why); ctx.checkFoldState(why); ctx.checkInk(why)
                ctx.snap(why.hasPrefix("⌫") ? "backspace-below-tall-fold" : "edit-below-tall-fold")
                await ctx.restoreText(original, why)
                ctx.checkCaretVisible("\(why): undone")
            }
            await editBelow("⌫ at the start of the line below a fold taller than the screen") { await ctx.key(.delete) }

            // 길게 접힌 마크다운 구역 아래의 빈 줄에 쓴다: 쓴 줄은 그 구역에 든다(다음 제목 전까지) — 다시 스캔이 접힘을 그 줄까지 넓히려 하지만 쓰고 있는 줄을
            // 숨길 수는 없어 접힘을 편다. 쓰던 줄은 그 자리에 있어야 한다
            var md = "preface line\n\n## Long section\n"
            for i in 1...60 { md += "body line \(i) of the long section\n" }
            md += "\n## Next section\nbody of the next section\n\n"
            for i in 1...40 { md += "trailing line \(i)\n" }
            await ctx.open(text: md, name: "fold-tall.md")
            await ctx.settle(900)
            ctx.at("type on the blank line below a folded section taller than the screen")
            await ctx.key(.up, [.command]); await ctx.settle(200)
            ctx.model.send(.toggleFold(line: 3)); await ctx.settle(300)
            if ctx.hidden(line: 4), ctx.hidden(line: 63), !ctx.hidden(line: 64), await ctx.clickExpect(ctx.lineStart(64), "click the blank line below the folded section") {
                let y0 = ctx.caretLineScreenY()
                await ctx.type("typing here")
                let yTyped = ctx.caretLineScreenY()
                await ctx.settle(900)   // 줄 인덱스 250 ms + 영역 스캔 + 보정
                let y1 = ctx.caretLineScreenY()
                ctx.note("typed below a tall folded section: caret line at y \(y(y0)) before, \(y(yTyped)) after typing, \(y(y1)) after the rescan; section \(ctx.hidden(line: 4) ? "folded" : "open"); caret \(ctx.place(ctx.caret))")
                ctx.expect(!ctx.hidden(ctx.caret) && ctx.caretLineText() == "typing here", "fold", "the rescan hid the line being typed on (caret \(ctx.place(ctx.caret)), line \"\(ctx.caretLineText())\")")
                ctx.checkCaretVisible("typed below a tall folded section")
                if let y0, let y1 { if abs(y1 - y0) > ctx.lineHeight * 1.5 { ctx.issue("viewport-jump", "typed below a tall folded section: the line being typed on was at y \(y(y0)), and \(y(y1)) after the rescan") } }
                else if y1 == nil { ctx.issue("caret-hidden", "typed below a tall folded section: after the rescan the line being typed on is off screen (it was at y \(y(y0)))") }
                await ctx.type(" more"); await ctx.settle(200)
                ctx.expect(ctx.caretLineText() == "typing here more", "text", "typing on after the rescan: line \"\(ctx.caretLineText())\"")
                ctx.checkCaretVisible("typed on after the rescan"); ctx.checkAllD("typed below a tall folded section"); ctx.checkFoldState("typed below a tall folded section"); ctx.checkInk("typed below a tall folded section")
                ctx.snap("typed-below-tall-section")
            } else { ctx.issue("other", "the long section did not fold (hidden(4)=\(ctx.hidden(line: 4)) hidden(63)=\(ctx.hidden(line: 63)) hidden(64)=\(ctx.hidden(line: 64)))") }
            ctx.model.send(.unfoldAll); await ctx.settle(200)
        },

        // 되돌리기는 shouldChangeText 를 거치지 않고 저장소 알림으로 사후에 전해진다. 닫힌 접힘이 하나도 없어도 그 통지는 접기 쪽에 닿아야 한다:
        // 후보(거터 화살표·접기 명령이 쓰는 영역)의 오프셋을 옮겨야 하고, 되돌리기 묶음의 앞 편집이 마지막 접힘을 폈으면 뒤 편집만큼 다시 배치할 범위도 옮겨야 한다
        Scenario(name: "fold-undo") { ctx in
            await ctx.open(text: RealUse.guardDoc, name: "fold-undo.py")
            await ctx.settle(700)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            @MainActor func offset(_ line: Int, _ col: Int?) -> Int { col.map { ctx.lineStart(line) + $0 } ?? ctx.lineEnd(line) }
            @MainActor func arrows() -> [Int] { ctx.markers(inLines: 1...15).filter { $0.value == .foldable }.keys.sorted() }
            guard arrows() == [1, 2, 7, 11] else { ctx.issue("other", "the guard document's fold arrows are at lines \(arrows()), expected 1, 2, 7, 11"); return }
            // ① 접힘이 없는 문서: 맨 위에 두 줄을 넣고(다시 스캔까지 기다린다) 되돌린 직후 — 다시 스캔되기 전에 — 화살표가 제 줄에 있고, 접기 명령이 제 영역을 접는가
            ctx.at("fold arrows and Fold right after an undo, with nothing folded")
            ctx.tv.breakUndoCoalescing()
            ctx.tv.insertText("a new first line\nand a second one\n", replacementRange: NSRange(location: 0, length: 0)); await ctx.pumpEvent()
            await ctx.settle(700)
            ctx.expect(arrows() == [3, 4, 9, 13], "fold", "after inserting two lines at the top the fold arrows are at lines \(arrows()), expected 3, 4, 9, 13")
            ctx.model.send(.undo); await ctx.turn()
            ctx.expect(ctx.text.isEqual(to: RealUse.guardDoc), "text", "undo did not restore the text (length \(ctx.length))")
            let right = arrows()
            ctx.expect(right == [1, 2, 7, 11], "fold", "right after the undo (before the rescan) the fold arrows are at lines \(right), expected 1, 2, 7, 11")
            // 10번 줄은 어느 영역에도 들지 않는다 — 옛 오프셋의 후보로 보면 7번 줄의 영역(34자 밀린)에 든다
            ctx.tv.setSelectedRange(NSRange(location: offset(10, 7), length: 0))
            ctx.model.send(.fold); await ctx.turn(); await ctx.settle(60)
            let hiddenLines = (1...13).filter { ctx.hidden(line: $0) }
            ctx.expect(hiddenLines.isEmpty, "fold", "Fold on line 10 right after the undo folded lines \(hiddenLines) — line 10 is not in a region (the regions still had the offsets from before the undo)")
            ctx.model.send(.unfoldAll); await ctx.settle(100)
            ctx.model.send(.redo); await ctx.turn()   // 다시 두 줄이 들어간다: 영역은 두 줄 아래로
            let afterRedo = arrows()
            ctx.expect(afterRedo == [3, 4, 9, 13], "fold", "right after the redo the fold arrows are at lines \(afterRedo), expected 3, 4, 9, 13")
            ctx.tv.setSelectedRange(NSRange(location: offset(10, 6), length: 0))   // 지금의 10번 줄 = 원래 8번 줄 (7번 줄 영역 안)
            ctx.model.send(.fold); await ctx.turn(); await ctx.settle(60)
            let folded = (1...15).filter { ctx.hidden(line: $0) }
            ctx.expect(folded == [10, 11], "fold", "Fold right after the redo folded lines \(folded), expected 10 and 11 (the region of line 9)")
            ctx.checkAllD("fold right after a redo"); ctx.checkFoldState("fold right after a redo"); ctx.snap("fold-after-redo")
            await ctx.settle(600)
            ctx.expect((1...15).filter { ctx.hidden(line: $0) } == [10, 11], "fold", "after the rescan the folded lines are \((1...15).filter { ctx.hidden(line: $0) })")
            ctx.model.send(.unfoldAll); await ctx.settle(100)
            await ctx.restoreText(RealUse.guardDoc as NSString, "undo the redo")

            // ② 한 묶음의 두 편집(영역 위의 줄을 비우고, 영역 안에 글자를 넣는다)을 되돌린다 — 그 영역이 유일한 접힘일 때. 되돌리기는 뒤 편집부터: 영역 안의 편집이
            //    접힘을 펴고(접힘이 하나도 남지 않는다), 이어서 영역 위에 22자가 돌아온다. 펴진 줄들이 모두 화면에 나오는가
            ctx.at("undo a group that edits above and inside the only fold")
            await ctx.pumpEvent(); ctx.tv.breakUndoCoalescing()
            ctx.tv.insertText("", replacementRange: NSRange(location: offset(6, 0), length: 22))          // 6번 줄의 글을 지운다 (줄은 남는다)
            ctx.tv.insertText("XY", replacementRange: NSRange(location: offset(8, 6), length: 0))         // 8번 줄 안에
            await ctx.pumpEvent(); await ctx.settle(700)
            let edited = ctx.textCopy()
            ctx.expect(edited.length == RealUse.guardDoc.utf16.count - 20, "text", "the two edits left \(edited.length) characters")
            if await ctx.foldOnly(7, "undo a two-edit group") != nil {
                ctx.model.send(.undo); await ctx.pumpEvent(); await ctx.settle(500)
                if !ctx.text.isEqual(to: RealUse.guardDoc) {   // 두 편집이 한 묶음이 아니었다 — 한 번 더
                    ctx.note("the two edits were separate undo steps (length \(ctx.length) after one undo)")
                    ctx.model.send(.undo); await ctx.pumpEvent(); await ctx.settle(500)
                }
                ctx.expect(ctx.text.isEqual(to: RealUse.guardDoc), "text", "undo did not restore the text (length \(ctx.length))")
                ctx.expect(!ctx.foldsActive, "fold", "the undo changed hidden text but the fold is still closed")
                let shown = ctx.viewportFragments().count
                ctx.expect(shown == 13, "fold", "after undoing a group that edited above and inside the only fold, \(shown) of 13 lines are laid out with a height")
                ctx.checkAllD("undo of a two-edit group"); ctx.checkFoldState("undo of a two-edit group"); ctx.checkInk("undo of a two-edit group")
                await ctx.clickExpect(ctx.lineStart(9) + 4, "click line 9 after the undo")
                ctx.snap("group-undone")
                // 다시 실행: 접힘 없는 문서에서의 묶음 — 후보도 두 편집만큼
                ctx.model.send(.redo); await ctx.pumpEvent(); await ctx.turn()
                ctx.expect(ctx.text.isEqual(to: edited as String), "text", "redo did not bring the two edits back (length \(ctx.length))")
                ctx.expect(arrows() == [1, 2, 7, 11], "fold", "right after redoing the group the fold arrows are at lines \(arrows()), expected 1, 2, 7, 11")
                ctx.checkAllD("redo of a two-edit group"); ctx.checkFoldState("redo of a two-edit group")
                await ctx.settle(400)
                await ctx.restoreText(RealUse.guardDoc as NSString, undos: 2, "undo the group again")
            }
            ctx.model.send(.unfoldAll); await ctx.settle(200)

            // ③ 같은 묶음, 접힘이 문서 끝까지 닿을 때: 마지막 문단은 접힌 동안 높이 0 조각 · 0.01 pt 표시용 문단으로 열거에 남아 있다 — 펴진 뒤 다시 만들어지지
            //    않으면 파일의 마지막 줄이 화면에 나오지 않는다. 영역 위에 돌아오는 22자만큼 다시 배치할 범위가 뒤로 가야 그 문단에 닿는다
            ctx.at("undo a group that edits above and inside the only fold, which reaches the end")
            await ctx.pumpEvent(); ctx.tv.breakUndoCoalescing()
            ctx.tv.insertText("", replacementRange: NSRange(location: offset(6, 0), length: 22))
            ctx.tv.insertText("XY", replacementRange: NSRange(location: offset(12, 6), length: 0))
            await ctx.pumpEvent(); await ctx.settle(700)
            if await ctx.foldOnly(11, "undo a two-edit group under the last fold") != nil {
                ctx.expect(ctx.hidden(ctx.length), "fold", "the fold of line 11 does not reach the end of the document")
                ctx.model.send(.undo); await ctx.pumpEvent(); await ctx.settle(500)
                if !ctx.text.isEqual(to: RealUse.guardDoc) { ctx.model.send(.undo); await ctx.pumpEvent(); await ctx.settle(500) }
                ctx.expect(ctx.text.isEqual(to: RealUse.guardDoc), "text", "undo did not restore the text (length \(ctx.length))")
                ctx.expect(!ctx.foldsActive, "fold", "the undo changed hidden text but the fold is still closed")
                let shown = ctx.viewportFragments().count
                ctx.expect(shown == 13, "fold", "after undoing a group that edited above and inside the fold that reached the end, \(shown) of 13 lines are laid out with a height — the last line of the file is not on screen")
                ctx.checkAllD("undo of a two-edit group under the last fold"); ctx.checkFoldState("undo of a two-edit group under the last fold"); ctx.checkInk("undo of a two-edit group under the last fold")
                await ctx.clickExpect(ctx.lineStart(13) + 4, "click the last line after the undo")
                ctx.snap("last-fold-group-undone")
            }
            ctx.model.send(.unfoldAll); await ctx.settle(200)

            // ④ 접힘 없는 큰 문서에서의 되돌리기 비용: 사후 통지가 접기 후보(수천 개)를 옮기는 만큼이 더 든다 — 입력 한 글자가 드는 것과 같은 일이다
            ctx.at("undo cost in a 1.3 MB document with nothing folded")
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "fold-undo-notes.md") }
            await ctx.settle(900)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            await ctx.pumpEvent(); ctx.tv.breakUndoCoalescing()
            for i in 0..<20 { ctx.tv.insertText("x", replacementRange: NSRange(location: 10 + i * 3, length: 0)); await ctx.pumpEvent(); ctx.tv.breakUndoCoalescing() }
            await ctx.settle(500)
            var t = CFAbsoluteTimeGetCurrent()
            for _ in 0..<20 { ctx.model.send(.undo); await ctx.pumpEvent() }
            let perUndo = (CFAbsoluteTimeGetCurrent() - t) * 1000 / 20
            await ctx.settle(500)
            let a = ctx.lineStart(15_000), b = ctx.lineStart(15_600)
            ctx.tv.insertText("", replacementRange: NSRange(location: a, length: b - a)); await ctx.pumpEvent(); await ctx.settle(500)
            t = CFAbsoluteTimeGetCurrent()
            ctx.model.send(.undo); await ctx.settle(0)
            let bigUndo = (CFAbsoluteTimeGetCurrent() - t) * 1000
            await ctx.settle(500)
            ctx.note(String(format: "undo with nothing folded (%d fold regions known): %.1f ms per one-character undo (incl. one event turn), %.1f ms to bring back 600 deleted lines (%d characters)", ctx.markers(inLines: 1...400).count, perUndo, bigUndo, b - a))
            // 실측(네 번씩): 한 글자 0.5~1.4 ms · 600줄 17~34 ms. 접기 쪽에 전하지 않던 때는 0.5~0.7 ms · 16~33 ms — 잴 수 있는 차이가 없다.
            // 예산은 잰 값 가운데 큰 쪽의 서너 배
            if perUndo > 5 || bigUndo > 120 { ctx.issue("stall", String(format: "undo with nothing folded: %.1f ms per one-character undo, %.0f ms for 600 lines", perUndo, bigUndo), snap: false) }
            ctx.checkAll("after the undos in the notes"); ctx.checkCaretVisible("after the undo of 600 lines")
        },

        // 자동 줄바꿈으로 두 줄 넘게 감긴 접힌 머리 줄과 그 아래의 감긴 줄 사이를 ↑/↓ 로 오간다: 누를 때마다 화면 줄 하나씩 — 머리 줄의 남은 화면 줄을 건너뛰지 않고,
        // 접힘은 닫힌 채 건너뛴다
        Scenario(name: "fold-wrapped") { ctx in
            let long = "- a long bullet that wraps: " + String(repeating: "word ", count: 60) + "end of the bullet"
            let doc = ["intro line", long, "    child one", "    child two", "below: " + String(repeating: "text ", count: 60) + "end of the line below", "last line"].joined(separator: "\n") + "\n"
            await ctx.open(text: doc, name: "fold-wrapped.txt")
            await ctx.settle(700)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            guard await ctx.foldOnly(2, "wrapped header") != nil else { return }
            let headerRows = ctx.visualLines(ofParagraphAt: ctx.lineStart(2)), belowRows = ctx.visualLines(ofParagraphAt: ctx.lineStart(5))
            guard headerRows.count >= 2, belowRows.count >= 2 else { ctx.issue("other", "the long lines do not wrap here (\(headerRows.count) and \(belowRows.count) screen lines)"); return }
            /// 캐럿이 놓인 (문서 줄, 그 문단의 몇째 화면 줄) — 캐럿 사각형의 높이로 고른다 (감긴 자리의 캐럿은 앞줄 끝에 그려질 수 있다)
            @MainActor func row() -> String {
                let line = ctx.liveLine(ctx.caret)
                let rows = ctx.visualLines(ofParagraphAt: ctx.lineStart(line))
                guard rows.count > 1, let r = ctx.tv.caretRect(at: ctx.caret) else { return "\(line).0" }
                return "\(line).\(rows.firstIndex { abs($0.rect.midY - r.midY) < $0.rect.height / 2 } ?? -1)"
            }
            let down = (1..<headerRows.count).map { "2.\($0)" } + (0..<belowRows.count).map { "5.\($0)" } + ["6.0"]
            ctx.at("↓ from the first screen line of a wrapped folded header")
            if await ctx.clickExpect(ctx.lineStart(2) + 6, "click the first screen line of the folded header") {
                var trail: [String] = []
                for _ in down {
                    await ctx.key(.down); await ctx.settle(40)
                    trail.append(row())
                    if ctx.hidden(ctx.caret) || !ctx.hidden(line: 3) { break }
                }
                ctx.note("↓ × \(trail.count): \(trail.joined(separator: " → ")) (line.screen line; the header has \(headerRows.count) screen lines, the line below \(belowRows.count))")
                ctx.expect(trail == down, "fold", "↓ from the first screen line of a wrapped folded header went \(trail.joined(separator: " → ")), expected \(down.joined(separator: " → ")) — one screen line per press")
                ctx.expect(ctx.hidden(line: 3) && ctx.foldCount() == 1, "fold", "↓ across a wrapped folded header opened the fold")
                ctx.checkCaretVisible("↓ across a wrapped folded header"); ctx.checkAllD("↓ across a wrapped folded header"); ctx.checkFoldState("↓ across a wrapped folded header")
                ctx.snap("down")
                ctx.at("↑ back from the line under the wrapped line below the fold")
                let up = Array(((0..<belowRows.count).map { "5.\($0)" }).reversed()) + Array(((0..<headerRows.count).map { "2.\($0)" }).reversed()) + ["1.0"]
                trail = []
                for _ in up {
                    await ctx.key(.up); await ctx.settle(40)
                    trail.append(row())
                    if ctx.hidden(ctx.caret) || !ctx.hidden(line: 3) { break }
                }
                ctx.note("↑ × \(trail.count): \(trail.joined(separator: " → "))")
                ctx.expect(trail == up, "fold", "↑ from below a wrapped line under a fold went \(trail.joined(separator: " → ")), expected \(up.joined(separator: " → ")) — one screen line per press")
                ctx.expect(ctx.hidden(line: 3) && ctx.foldCount() == 1, "fold", "↑ across a wrapped folded header opened the fold")
                ctx.checkCaretVisible("↑ across a wrapped folded header"); ctx.checkAllD("↑ across a wrapped folded header"); ctx.checkFoldState("↑ across a wrapped folded header")
            }
            // ⇧↓ 는 감긴 머리 줄의 가운데 화면 줄에서는 같은 문단 안에서 늘어난다 (접힘은 닫힌 채)
            ctx.at("⇧↓ from the first screen line of a wrapped folded header")
            if await ctx.clickExpect(ctx.lineStart(2) + 6, "click the first screen line of the folded header") {
                await ctx.key(.down, [.shift]); await ctx.settle(80)
                let sel = ctx.tv.selectedRange()
                ctx.expect(sel.location == ctx.lineStart(2) + 6 && NSMaxRange(sel) <= ctx.lineEnd(2) && sel.length > 0 && ctx.hidden(line: 3), "fold",
                           "⇧↓ on the first screen line of a wrapped folded header: selection \(sel), fold \(ctx.hidden(line: 3) ? "closed" : "open") — it should select to the next screen line of the header")
            }
            ctx.model.send(.unfoldAll); await ctx.settle(200)
        },

        // 스크롤바 옆 표식 띠: 스크롤만으로는 다시 그리지 않는다(fold-giant 가 본다 — 접힘 15,000개 문서에서 걸음마다 10 ms 였다). 여기서는 반대쪽을 본다:
        // 띠가 보여 주는 것(접힌 머리 줄 · 찾은 자리 · 북마크)이 바뀌면 다시 그려야 한다 — 그리기를 아끼다가 옛 눈금이 남으면 안 된다
        Scenario(name: "fold-strip") { ctx in
            await ctx.open(text: RealUse.foldDoc(h1: false, sections: 60), name: "fold-strip.md")
            await ctx.settle(700)
            guard let strip = (ctx.scroll.superview as? EditorContainerView)?.markerView as? ScrollMarkerView else { ctx.issue("other", "no scroll marker strip next to the editor"); return }
            let h10 = RealUse.foldHeader(10)
            await ctx.look(atLine: h10)
            @MainActor func redraws(_ why: String, _ change: () async -> Void) async {
                ctx.at(why)
                await ctx.settle(300)   // 앞 걸음이 남긴 그리기(캐럿 줄 60 ms · 문서 높이 100 ms 로 묶인 것)를 끝낸다
                let before = strip.debugDrawCount
                await change()
                await ctx.settle(300)
                let n = strip.debugDrawCount - before
                ctx.note("\(why): the scroll marker strip was drawn \(n) time(s)")
                if n == 0 { ctx.issue("other", "\(why): the scroll marker strip was not drawn again — it still shows the ticks from before") }
            }
            await redraws("fold one section") { ctx.model.send(.toggleFold(line: h10)) }
            ctx.expect(ctx.hidden(line: h10 + 1), "fold", "section 10 did not fold")
            await redraws("unfold it") { ctx.model.send(.toggleFold(line: h10)) }
            await redraws("fold all") { ctx.model.send(.foldAll) }
            await redraws("unfold all") { ctx.model.send(.unfoldAll) }
            await redraws("find 'nested'") {
                let gen = ctx.model.searchCompletionCount
                ctx.model.searchQuery = "nested"; ctx.model.runSearch()
                _ = await ctx.awaitSearch(after: gen)
            }
            await redraws("clear the search") { ctx.model.searchQuery = ""; ctx.model.runSearch() }
            await redraws("add a bookmark") { ctx.model.toggleBookmarkAtCaret() }
            await redraws("remove the bookmark") { ctx.model.toggleBookmarkAtCaret() }
            // 그리고 아무것도 바뀌지 않는 휠 스크롤은 그리지 않는다 (문서 높이 어림이 바뀔 때만 — 걸음 수보다 훨씬 적어야 한다)
            ctx.at("wheel without any change")
            await ctx.settle(300)
            let before = strip.debugDrawCount
            await ctx.wheelRun("strip: wheel down", steps: 20, by: 60, deepEvery: 10)
            let draws = strip.debugDrawCount - before
            ctx.note("20 wheel steps: the scroll marker strip was drawn \(draws) time(s)")
            if draws > 8 { ctx.issue("stall", "the scroll marker strip was redrawn \(draws) times during 20 wheel steps", snap: false) }
        },

        // 겹쳐 접힌 영역에서의 낱말 걸음: 바깥 머리 줄 끝에서 ⇧⌥→ 는 안쪽 접힘 속의 낱말까지 간다 — 그 사이의 접힘(바깥·지나치는 안쪽·닿는 안쪽)이 모두 펴져야
        // 고른 글이 화면에 보인다. 바깥 접힘만 펴지면 AppKit 의 걸음은 닫힌 안쪽 접힘들을 넘어가고, 이어지는 ⌫ 가 그 속의 줄을 지운다
        Scenario(name: "fold-nested") { ctx in
            await ctx.open(text: RealUse.nestedDoc, name: "fold-nested.json")
            await ctx.settle(700)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            let arrows = ctx.markers(inLines: 1...11).filter { $0.value == .foldable }.keys.sorted()
            guard arrows == [1, 2, 6] else { ctx.issue("other", "the nested document's fold arrows are at lines \(arrows), expected 1, 2, 6"); return }
            @MainActor func foldAll() async -> Bool {
                ctx.model.send(.foldAll); await ctx.settle(300)
                return ctx.hidden(line: 2) && ctx.hidden(line: 3) && ctx.hidden(line: 7) && ctx.hidden(line: 10) && !ctx.hidden(line: 11)
            }
            @MainActor func caret(_ o: Int) -> () async -> Bool { { ctx.tv.setSelectedRange(NSRange(location: o, length: 0)); await ctx.settle(60); return ctx.caret == o } }
            let headerEnd = ctx.lineEnd(1), belowStart = ctx.lineStart(11)
            await ctx.sameAsOpenDocument("⇧⌥→ at the end of the outer header with everything folded, then ⌫", folding: foldAll, place: caret(headerEnd),
                                         step: { await ctx.key(.right, [.shift, .option]) }, edit: { await ctx.key(.delete) })
            ctx.snap("word-right-into-nested")
            await ctx.sameAsOpenDocument("⇧⌥→ twice at the end of the outer header, then ⌫", folding: foldAll, place: caret(headerEnd),
                                         step: { await ctx.key(.right, [.shift, .option]); await ctx.key(.right, [.shift, .option]) }, edit: { await ctx.key(.delete) })
            // 선택 없는 걸음은 캐럿이 놓일 줄의 접힘만 편다 — 지나친 안쪽 접힘(2번 줄의 것)은 닫힌 채다
            await ctx.sameAsOpenDocument("⌥→ at the end of the outer header, then type", folding: foldAll, place: caret(headerEnd),
                                         step: { await ctx.key(.right, [.option]) }, edit: { await ctx.type("X") },
                                         after: { ctx.expect(ctx.hidden(line: 3) && !ctx.hidden(line: 7), "fold", "⌥→ into the nested folds: the fold the caret only passed (line 2) is \(ctx.hidden(line: 3) ? "closed" : "open"), the one it landed in (line 6) is \(ctx.hidden(line: 7) ? "closed" : "open")") })
            await ctx.sameAsOpenDocument("⇧⌥← at the start of the line below the outer fold, then ⌫", folding: foldAll, place: caret(belowStart),
                                         step: { await ctx.key(.left, [.shift, .option]) }, edit: { await ctx.key(.delete) })
            await ctx.sameAsOpenDocument("⇧⌥↓ at the end of the outer header, then ⌫", folding: foldAll, place: caret(headerEnd),
                                         step: { await ctx.command("moveParagraphForwardAndModifySelection:") }, edit: { await ctx.key(.delete) })
            await ctx.sameAsOpenDocument("⇧↓ at the end of the outer header, then ⌫", folding: foldAll, place: caret(headerEnd),
                                         step: { await ctx.key(.down, [.shift]) }, edit: { await ctx.key(.delete) })
            ctx.snap("end")
        },

        // 오른쪽→왼쪽 문단: ←/→ 는 화면의 방향이라 "왼쪽"이 글의 뒤쪽으로 나아간다. 접힌 제목 줄의 끝 쪽에서 ⇧⌥← 는 숨은 본문의 낱말로 간다 — 명령 이름만 보고
        // 앞쪽(글의 머리 쪽)만 살피면 접힘이 닫힌 채 넘어가고, ⌫ 가 숨은 구역을 지운다
        Scenario(name: "fold-rtl") { ctx in
            await ctx.open(text: RealUse.rtlFoldDoc, name: "fold-rtl.md")
            await ctx.settle(700)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            guard ctx.markers(inLines: 1...7)[2] == .foldable else { ctx.issue("other", "the right-to-left document has no foldable heading at line 2"); return }
            @MainActor func caret(_ o: Int) -> () async -> Bool { { ctx.tv.setSelectedRange(NSRange(location: o, length: 0)); await ctx.settle(60); return ctx.caret == o } }
            let nearEnd = ctx.lineEnd(2) - 2          // 제목의 마지막 낱말 뒤, 닫는 괄호와 쌍점 앞
            let afterMarks = ctx.lineStart(6) + 3     // 접힘 아래 제목의 `## ` 뒤
            if let a = ctx.tv.caretRect(at: ctx.lineStart(3)), let b = ctx.tv.caretRect(at: ctx.lineEnd(3)) {
                ctx.note("line 3 runs from x \(Int(a.minX)) to x \(Int(b.minX)) — \(b.minX < a.minX ? "right to left" : "left to right"); the app reads the paragraph as \(ctx.tv.writingDirections(ofParagraphAt: ctx.lineStart(3)))")
                ctx.expect(b.minX < a.minX, "other", "the Hebrew line is not laid out right to left here — the scenario does not test what it means to")
            }
            // 걸음만: 편 문서에서 숨을 줄로 들어가는 쪽은 접힘이 펴져야 하고, 반대쪽은 접힘을 그대로 둬야 한다 (양쪽을 다 살피면 까닭 없이 펴진다)
            for c in ["moveWordLeftAndModifySelection:", "moveWordRightAndModifySelection:", "moveWordLeft:", "moveWordRight:", "moveLeftAndModifySelection:", "moveRightAndModifySelection:",
                      "moveToLeftEndOfLineAndModifySelection:", "moveToRightEndOfLineAndModifySelection:"] {
                ctx.at("\(c) near the end of a folded right-to-left heading")
                await ctx.sameMoveAsUnfolded("near the end of the heading", fold: 2, place: caret(nearEnd), [c])
                ctx.at("\(c) after the marks of the heading below the fold")
                await ctx.sameMoveAsUnfolded("after the ## of the heading below", fold: 2, place: caret(afterMarks), [c])
            }
            for c in ["moveLeftAndModifySelection:", "moveRightAndModifySelection:", "moveLeft:", "moveRight:", "moveWordLeftAndModifySelection:", "moveWordRightAndModifySelection:"] {
                ctx.at("\(c) at the end of a folded right-to-left heading")
                await ctx.sameMoveAsUnfolded("end of the heading", fold: 2, place: caret(ctx.lineEnd(2)), [c])
            }
            // 걸음 뒤에 지운다 — 편 문서와 같은 글이어야 한다
            for (name, key) in [("⇧⌥←", RealUseContext.Key.left), ("⇧⌥→", RealUseContext.Key.right)] {
                ctx.at("\(name) near the end of a folded right-to-left heading, then ⌫")
                await ctx.sameAsUnfolded("\(name) near the end of a folded right-to-left heading, then ⌫", fold: 2, place: caret(nearEnd)) { await ctx.key(key, [.shift, .option]); await ctx.pumpEvent(); await ctx.key(.delete) }
                ctx.at("\(name) after the marks of the heading below the fold, then ⌫")
                await ctx.sameAsUnfolded("\(name) after the ## of the heading below the fold, then ⌫", fold: 2, place: caret(afterMarks)) { await ctx.key(key, [.shift, .option]); await ctx.pumpEvent(); await ctx.key(.delete) }
            }
            ctx.snap("end")
        },

        // 긴 문서에서 캐럿 여러 개(모든 일치 — 머리 캐럿은 문서의 마지막 일치)를 둔 채 멀리 떨어진 영역을 접는다: 숨은 캐럿은 머리 줄로 옮겨지지만 화면은 방금 접은
        // 자리에 남아야 한다 — 옮겨지지도 않은 머리 캐럿을 따라가면 접은 자리가 화면에서 사라진다. 분할의 다른 편집기도 보던 곳을 지킨다
        Scenario(name: "fold-carets-far") { ctx in
            let m = ctx.model
            await ctx.open(text: RealUse.foldDoc(h1: false, sections: 60), name: "fold-carets-far.md")
            await ctx.settle(700)
            let h10 = RealUse.foldHeader(10), h12 = RealUse.foldHeader(12), h50 = RealUse.foldHeader(50)
            @MainActor func y(_ v: CGFloat?) -> String { v.map { String(format: "%.1f", $0) } ?? "off screen" }
            /// 구역마다 한 번 나오는 글 60개를 모두 고른다 (머리 캐럿은 60번 구역 — 화면도 거기로 간다). 그다음 선택은 그대로 둔 채 휠로 10번 구역까지 올라간다
            @MainActor func selectAllAndLook(atHeader target: Int, _ why: String) async -> Bool {
                m.send(.unfoldAll); await ctx.settle(150)
                if ctx.tv.multi != nil { await ctx.key(.escape) }
                let gen = m.searchCompletionCount
                m.searchQuery = "nested detail a"; m.runSearch()
                guard await ctx.awaitSearch(after: gen), m.searchHits.count == 60 else { ctx.issue("find", "\(why): 'nested detail a' found \(m.searchHits.count) matches, expected 60"); return false }
                m.selectAllMatches(); await ctx.settle(200)
                m.searchQuery = ""; m.runSearch(); await ctx.settle(200)
                guard ctx.tv.multi?.ranges.count == 60 else { ctx.issue("multi", "\(why): select all matches made \(ctx.tv.multi?.ranges.count ?? 0) selections, expected 60"); return false }
                var steps = 0
                while ctx.topLine() > max(1, target - 2), steps < 400 { await ctx.scrollBy(-240); await ctx.settle(0); steps += 1 }   // 걸음마다 배치를 끝내야 맨 위 줄을 읽을 수 있다
                await ctx.settle(250)
                guard ctx.tv.multi?.ranges.count == 60, ctx.screenY(ofFragmentAt: ctx.lineStart(target)) != nil else { ctx.issue("other", "\(why): could not wheel up to line \(target) with the selections kept (top line \(ctx.topLine()), \(ctx.tv.multi?.ranges.count ?? 0) selections)"); return false }
                return true
            }
            @MainActor func selectAllAndLookAtSection10(_ why: String) async -> Bool { await selectAllAndLook(atHeader: h10, why) }
            // ① 거터 화살표로 10번 구역을 접는다: 그 안의 선택 하나만 숨는다
            ctx.at("fold a section far above the head caret with the gutter arrow")
            if await selectAllAndLookAtSection10("gutter fold") {
                let y0 = ctx.screenY(ofFragmentAt: ctx.lineStart(h10)), top0 = ctx.topLine()
                if let p = ctx.foldArrowPoint(forLine: h10) { await ctx.clickGutter(at: p) } else { ctx.issue("other", "no fold arrow on screen for line \(h10)") }
                await ctx.settle(300)
                let y1 = ctx.screenY(ofFragmentAt: ctx.lineStart(h10))
                let ranges = ctx.carets
                ctx.note("gutter fold with 60 selections: header \(h10) at y \(y(y0)) → \(y(y1)), top line \(top0) → \(ctx.topLine()); \(ranges.count) selections, \(ctx.caretsOnHiddenLines().count) on hidden lines")
                ctx.expect(ctx.hidden(line: h10 + 1) && ctx.foldCount() == 1, "fold", "section 10 did not fold")
                if let y0, let y1 { if abs(y1 - y0) > 2 { ctx.issue("viewport-jump", "folding section 10 with selections elsewhere moved its header from y \(y(y0)) to \(y(y1))") } }
                else { ctx.issue("viewport-jump", "folding section 10 with the head selection in section 60: the header that was just folded is no longer on screen (top line \(top0) → \(ctx.topLine())) — the view went to a selection that did not move") }
                ctx.expect(ranges.count == 60 && ranges.contains(NSRange(location: ctx.lineEnd(h10), length: 0)) && ctx.caretsOnHiddenLines().isEmpty, "fold",
                           "after folding section 10: \(ranges.count) selections, caret at the end of the header \(ranges.contains(NSRange(location: ctx.lineEnd(h10), length: 0))), \(ctx.caretsOnHiddenLines().count) on hidden lines")
                ctx.checkAllD("gutter fold with selections elsewhere"); ctx.checkFoldState("gutter fold with selections elsewhere"); ctx.snap("gutter-fold")
            }
            // ② 모두 접기: 선택 60개가 모두 숨는다(머리 캐럿도). 머리 캐럿의 줄은 화면 밖이었다 — 읽던 곳(10번 구역)에 남는다
            ctx.at("fold all while reading far from the head caret")
            if await selectAllAndLookAtSection10("fold all") {
                let top0 = ctx.topLine()
                m.send(.foldAll); await ctx.settle(400)
                let top1 = ctx.topLine()
                let ranges = ctx.carets
                ctx.note("fold all with 60 selections: top line \(top0) → \(top1); header 10 at y \(y(ctx.screenY(ofFragmentAt: ctx.lineStart(h10)))); \(ranges.count) carets, \(ctx.caretsOnHiddenLines().count) on hidden lines")
                ctx.expect(ctx.foldsActive && ctx.caretsOnHiddenLines().isEmpty && ranges.count == 60, "fold", "fold all with 60 selections: \(ranges.count) carets, \(ctx.caretsOnHiddenLines().count) on hidden lines")
                // 맨 위에 있던 줄(또는 그 줄을 품은 머리 줄)이 맨 위에 남는다: 10번 구역 언저리다. 머리 캐럿(60번 구역)으로 갔으면 한참 아래다
                if abs(top1 - top0) > 8 || ctx.screenY(ofFragmentAt: ctx.lineStart(h10)) == nil {
                    ctx.issue("viewport-jump", "fold all while reading section 10 (the head caret was off screen in section 60): top line \(top0) → \(top1), header 10 \(ctx.screenY(ofFragmentAt: ctx.lineStart(h10)) == nil ? "off screen" : "on screen")")
                }
                ctx.checkAllD("fold all with selections"); ctx.checkFoldState("fold all with selections"); ctx.snap("fold-all")
                // 이어서 친다: 글자는 머리 줄 끝 60곳에 — 숨은 줄은 그대로다
                let before = ctx.textCopy()
                await ctx.pumpEvent(); ctx.tv.breakUndoCoalescing()
                await ctx.type("Q"); await ctx.pumpEvent(); await ctx.settle(400)
                ctx.expect(ctx.length == before.length + 60 && ctx.hidden(line: h10 + 1) && ctx.hidden(line: h50 + 1), "fold-loss",
                           "typing with 60 carets after fold all: \(before.length) → \(ctx.length) characters (expected +60), section 10 \(ctx.hidden(line: h10 + 1) ? "folded" : "open")")
                await ctx.restoreText(before, "undo the typing")
            }
            // 첫 일치(1번 구역)가 화면에 보이는 문서 맨 위에서도 같다 — 화면이 따라가는 것은 머리 캐럿(마지막 일치)이고, 그것은 화면 밖이다
            ctx.at("fold all at the top of the document, the first selection on screen and the head caret far below")
            if await selectAllAndLook(atHeader: RealUse.foldHeader(1), "fold all at the top") {
                let top0 = ctx.topLine()
                m.send(.foldAll); await ctx.settle(400)
                ctx.note("fold all at the top with 60 selections: top line \(top0) → \(ctx.topLine())")
                if abs(ctx.topLine() - top0) > 8 { ctx.issue("viewport-jump", "fold all at the top of the document (the head caret was off screen in section 60): top line \(top0) → \(ctx.topLine())") }
                ctx.expect(ctx.caretsOnHiddenLines().isEmpty && ctx.carets.count == 60, "fold", "fold all at the top: \(ctx.carets.count) carets, \(ctx.caretsOnHiddenLines().count) on hidden lines")
            }
            m.send(.unfoldAll); await ctx.settle(200)
            if ctx.tv.multi != nil { await ctx.key(.escape) }
            // ③ 캐럿 하나: 캐럿(50번 구역)과 떨어진 곳을 읽다가 모두 접기 — 같은 규칙이다
            ctx.at("fold all with a single caret off screen")
            m.jump(toLine: h50 + 3); await ctx.settle(300)
            var steps = 0
            while ctx.topLine() > h10 - 2, steps < 400 { await ctx.scrollBy(-240); await ctx.settle(0); steps += 1 }
            await ctx.settle(250)
            let top0 = ctx.topLine()
            m.send(.foldAll); await ctx.settle(400)
            ctx.note("fold all with one caret off screen: top line \(top0) → \(ctx.topLine()); caret \(ctx.place(ctx.caret))")
            ctx.expect(ctx.caret == ctx.lineEnd(h50) && !ctx.hidden(ctx.caret), "fold", "fold all: the caret went to \(ctx.place(ctx.caret)), expected the end of header \(h50)")
            if abs(ctx.topLine() - top0) > 8 || ctx.screenY(ofFragmentAt: ctx.lineStart(h10)) == nil { ctx.issue("viewport-jump", "fold all while reading section 10 (the caret was off screen in section 50): top line \(top0) → \(ctx.topLine())") }
            // 그 뒤의 입력은 캐럿으로 간다
            await ctx.type("z"); await ctx.settle(200)
            ctx.checkCaretVisible("typing after fold all away from the caret")
            await ctx.restoreText(RealUse.foldDoc(h1: false, sections: 60) as NSString, "undo the typing")
            m.send(.unfoldAll); await ctx.settle(200)

            // ④ 분할: 다른 편집기에 캐럿 셋(10번 구역 안에 둘, 머리는 50번 구역) — 여기서 10번 구역을 접으면 그 편집기의 두 캐럿은 머리 줄 끝 하나로 모이고,
            //    그 편집기가 보던 곳(12번 구역)은 그대로다
            ctx.at("split: the other editor has carets inside the section folded here")
            m.setSplit(.vertical); await ctx.settle(900)
            if let p = m.session.primary?.textView, let s = m.session.secondary?.textView, p !== s {
                ctx.window.makeFirstResponder(s); await ctx.settle(80)
                let inside = [ctx.lineStart(h10 + 1) + 3, ctx.lineStart(h10 + 3) + 4], head = ctx.lineStart(h50 + 3) + 4
                s.setMulti((inside + [head]).map { NSRange(location: $0, length: 0) }); await ctx.settle(200)
                var n = 0
                while ctx.topLine() > h12, n < 400 { await ctx.scrollBy(-240); await ctx.settle(0); n += 1 }   // 활성 편집기(보조)를 12번 구역까지 올린다
                await ctx.settle(250)
                let top0 = ctx.topOf(s)
                ctx.window.makeFirstResponder(p); await ctx.settle(80)
                m.jump(toLine: h10); await ctx.settle(300)
                m.send(.fold); await ctx.settle(300)
                let rows = s.multi?.ranges ?? [s.selectedRange()]
                let top1 = ctx.topOf(s)
                ctx.note("split: the other editor's carets → \(ctx.describe(rows)); its top paragraph \(top0.map { ctx.place($0.offset) } ?? "?") → \(top1.map { ctx.place($0.offset) } ?? "?")")
                ctx.expect(ctx.hidden(line: h10 + 1, in: p) && ctx.hidden(line: h10 + 1, in: s), "fold", "split: folding section 10 here did not fold both editors")
                ctx.expect(rows == [NSRange(location: ctx.lineEnd(h10), length: 0), NSRange(location: head, length: 0)], "fold",
                           "split: the other editor's carets are at \(ctx.describe(rows)), expected the end of header \(h10) and line \(h50 + 3)")
                if let a = top0, let b = top1 { if a.offset != b.offset || abs(a.inset - b.inset) > 1 { ctx.issue("viewport-jump", "split: folding here moved the other editor from \(ctx.place(a.offset)) (inset \(String(format: "%.1f", a.inset))) to \(ctx.place(b.offset)) (inset \(String(format: "%.1f", b.inset)))") } }
                else { ctx.issue("other", "split: could not read the other editor's top paragraph (before \(top0 != nil), after \(top1 != nil))") }
                ctx.checkNoHiddenOnScreen("split: primary", in: p); ctx.checkNoHiddenOnScreen("split: secondary", in: s); ctx.snap("split")
                if s.multi != nil { s.doCommand(by: #selector(NSResponder.cancelOperation(_:))) }
            } else { ctx.issue("other", "the split did not produce two editors") }
            m.send(.unfoldAll); await ctx.settle(150)
            m.setSplit(.none); await ctx.settle(700)
        },

        // \r\n 으로 끝나는 문서의 접기. "머리 줄 끝"은 \r 앞이다 — 숨김 구간 시작 − 1 은 \r 과 \n 사이라서, 접은 뒤 거기 놓인 캐럿에 글자를 치면 줄 끝이
        // `\rQ\n` 으로 깨진다. 글자 걸음도 \r\n 을 한 걸음으로 세어야 한다: 머리 줄 끝의 ⇧→ 는 줄 끝(두 글자)만 골라야지 닫힌 접힘을 통째로 걸치면 안 된다.
        // 걸음마다 줄 끝의 수(\r\n · 혼자인 \r · 혼자인 \n)가 그대로인지 문자열로 센다
        Scenario(name: "fold-crlf") { ctx in
            let doc = RealUse.guardDoc.replacingOccurrences(of: "\n", with: "\r\n")
            await ctx.open(text: doc, name: "fold-crlf.py")
            await ctx.settle(700)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            guard ctx.lineEndings() == [13, 0, 0], ctx.markers(inLines: 1...13)[7] == .foldable, ctx.markers(inLines: 1...13)[11] == .foldable else {
                ctx.issue("other", "the CR LF document was not opened as written (line ends \(ctx.lineEndings())) or has no foldable regions at lines 7 and 11"); return
            }
            @MainActor func col(_ line: Int, _ c: Int) -> Int { ctx.lineStart(line) + c }
            @MainActor func caret(_ o: @escaping @MainActor () -> Int) -> () async -> Bool { { let at = o(); ctx.tv.setSelectedRange(NSRange(location: at, length: 0)); await ctx.settle(60); return ctx.caret == at } }
            @MainActor func lineText(_ line: Int) -> String { ctx.text.substring(with: NSRange(location: ctx.lineStart(line), length: ctx.contentEnd(line) - ctx.lineStart(line))) }
            /// 줄 끝의 수가 그대로인가, 캐럿이 \r 과 \n 사이에 놓이지 않았는가
            @MainActor func intact(_ why: String, _ want: [Int] = [13, 0, 0]) {
                let now = ctx.lineEndings()
                if now != want { ctx.issue("text", "\(why): the line ends are now \(now[0]) CR LF, \(now[1]) lone CR, \(now[2]) lone LF — they were \(want[0]), \(want[1]), \(want[2])") }
                for r in ctx.carets where r.location > 0 && r.location < ctx.length && ctx.text.character(at: r.location - 1) == 13 && ctx.text.character(at: r.location) == 10 {
                    ctx.issue("text", "\(why): a caret sits between the CR and the LF of line \(ctx.liveLine(r.location)) (offset \(r.location)) — typing there breaks the line end")
                }
            }
            /// 접은 뒤 입력하고 되돌린다: 글자는 `line` 줄의 내용 끝에 들어가고, 줄 끝은 그대로, 접힘은 닫힌 채
            @MainActor func typeAtHeader(_ why: String, line: Int, hidden: Int, want: [Int] = [13, 0, 0]) async {
                let before = ctx.textCopy()
                let header = lineText(line)
                ctx.expectCaret(ctx.contentEnd(line), "\(why): the caret goes to the end of the header text")
                intact("\(why), before typing", want)
                await ctx.pumpEvent(); ctx.tv.breakUndoCoalescing()
                await ctx.type("Q"); await ctx.pumpEvent(); await ctx.settle(300)
                ctx.expect(lineText(line) == header + "Q" && ctx.hidden(line: hidden), "fold", "\(why): after typing Q line \(line) reads \"\(lineText(line))\" (expected \"\(header)Q\"), the fold is \(ctx.hidden(line: hidden) ? "closed" : "open")")
                intact("\(why), after typing", want)
                ctx.checkAllD(why); ctx.checkFoldState(why)
                await ctx.restoreText(before, why)
                intact("\(why), after undo", want)
            }
            /// ⋯ 표식이 머리 줄 글자의 바로 오른쪽, 같은 높이에 있는가 (내용 끝 기준)
            @MainActor func pillAfterText(_ why: String, line: Int) {
                guard let pill = ctx.pillRects().first(where: { $0.1 == ctx.lineStart(line + 1) }), let end = ctx.tv.caretRect(at: ctx.contentEnd(line)) else { ctx.issue("fold", "\(why): no ⋯ pill for the fold of line \(line)"); return }
                if pill.0.minX < end.maxX + 2 || pill.0.minX > end.maxX + 40 || abs(pill.0.midY - end.midY) > 3 {
                    ctx.issue("fold", "\(why): the ⋯ pill is at x \(Int(pill.0.minX)) y \(Int(pill.0.midY)), the header text ends at x \(Int(end.maxX)) y \(Int(end.midY))")
                }
            }

            // ① 영역 안에 캐럿을 두고 접는다 (거터 화살표와 같은 경로 · 접기 명령 · 모두 접기)
            ctx.at("caret inside the region, toggle the fold, type")
            ctx.tv.setSelectedRange(NSRange(location: col(8, 6), length: 0)); await ctx.settle(60)
            ctx.model.send(.toggleFold(line: 7)); await ctx.settle(300)
            pillAfterText("fold of line 7", line: 7)
            await typeAtHeader("caret inside, toggle fold", line: 7, hidden: 8)
            ctx.snap("folded")
            ctx.model.send(.unfoldAll); await ctx.settle(150)
            ctx.at("caret inside the region, Fold, type")
            ctx.tv.setSelectedRange(NSRange(location: col(9, 8), length: 0)); await ctx.settle(60)
            ctx.model.send(.fold); await ctx.settle(300)
            await typeAtHeader("caret inside, Fold", line: 7, hidden: 8)
            ctx.model.send(.unfoldAll); await ctx.settle(150)
            ctx.at("caret inside a nested region, Fold All, type")
            ctx.tv.setSelectedRange(NSRange(location: col(3, 10), length: 0)); await ctx.settle(60)
            ctx.model.send(.foldAll); await ctx.settle(300)
            await typeAtHeader("caret inside, Fold All", line: 1, hidden: 2)
            ctx.model.send(.unfoldAll); await ctx.settle(150)
            // 길이 있는 선택이 통째로 숨을 때도 같은 자리다
            ctx.at("a selection inside the region, toggle the fold, type")
            ctx.tv.setSelectedRange(NSRange(location: col(8, 4), length: 5)); await ctx.settle(60)
            ctx.model.send(.toggleFold(line: 7)); await ctx.settle(300)
            await typeAtHeader("selection inside, toggle fold", line: 7, hidden: 8)
            ctx.model.send(.unfoldAll); await ctx.settle(150)

            // ② 여러 캐럿을 둔 채 접는다
            ctx.at("two carets, one inside the region, fold, type")
            ctx.tv.setMulti([NSRange(location: col(8, 6), length: 0), NSRange(location: col(12, 6), length: 0)]); await ctx.settle(100)
            ctx.model.send(.toggleFold(line: 7)); await ctx.settle(300)
            do {
                let before = ctx.textCopy()
                let want = [NSRange(location: ctx.contentEnd(7), length: 0), NSRange(location: col(12, 6), length: 0)]
                ctx.expect(ctx.carets == want, "fold", "two carets after folding: \(ctx.describe(ctx.carets)), expected \(ctx.describe(want))")
                intact("two carets, before typing")
                await ctx.pumpEvent(); ctx.tv.breakUndoCoalescing()
                await ctx.type("Q"); await ctx.pumpEvent(); await ctx.settle(300)
                ctx.expect(lineText(7) == "def third(z):Q" && lineText(12) == "    taQil one" && ctx.hidden(line: 8), "fold", "two carets, after typing: line 7 \"\(lineText(7))\", line 12 \"\(lineText(12))\", fold \(ctx.hidden(line: 8) ? "closed" : "open")")
                intact("two carets, after typing")
                await ctx.restoreText(before, "two carets")
                intact("two carets, after undo")
            }
            ctx.model.send(.unfoldAll); await ctx.settle(150)
            if ctx.tv.multi != nil { await ctx.key(.escape) }

            // ④ 접힌 머리 줄에서 줄 끝으로 가는 키 뒤에 친다 (⌘→ · ⌃E · 문단 끝 · End 는 화면만 옮긴다)
            for (name, press) in [("⌘→", { await ctx.key(.right, [.command]) }), ("⌃E", { await ctx.command("moveToEndOfLine:") }), ("moveToEndOfParagraph", { await ctx.command("moveToEndOfParagraph:") }),
                                  ("⌘→ twice", { await ctx.key(.right, [.command]); await ctx.key(.right, [.command]) })] as [(String, () async -> Void)] {
                ctx.at("\(name) on a folded header, then type")
                guard await ctx.foldOnly(7, "\(name) on a folded header") != nil else { continue }
                ctx.tv.setSelectedRange(NSRange(location: col(7, 4), length: 0)); await ctx.settle(60)
                await press(); await ctx.settle(100)
                await typeAtHeader("\(name) on a folded header", line: 7, hidden: 8)
            }
            ctx.at("End on a folded header, then type")
            if await ctx.foldOnly(7, "End on a folded header") != nil {
                ctx.tv.setSelectedRange(NSRange(location: ctx.contentEnd(7), length: 0)); await ctx.settle(60)
                await ctx.key(.end); await ctx.settle(200)
                await typeAtHeader("End on a folded header", line: 7, hidden: 8)
            }
            // ↑ 로 접힘을 건너 머리 줄에 온다 (아래 줄이 더 길다 — 머리 줄의 내용 끝에 놓인다) · 끝까지 닿는 접힘의 머리 줄에서 ↓ (머리 줄 끝에 머문다)
            ctx.at("↑ from the end of the longer line below a fold, then type")
            if await ctx.foldOnly(7, "↑ onto a folded header") != nil {
                ctx.tv.setSelectedRange(NSRange(location: ctx.contentEnd(10), length: 0)); await ctx.settle(60)
                await ctx.key(.up); await ctx.settle(100)
                await typeAtHeader("↑ onto a folded header", line: 7, hidden: 8)
            }
            ctx.at("↓ on the header of a fold that reaches the end, then type")
            if await ctx.foldOnly(11, "↓ on the last folded header") != nil {
                ctx.tv.setSelectedRange(NSRange(location: col(11, 2), length: 0)); await ctx.settle(60)
                await ctx.key(.down); await ctx.settle(100)
                await typeAtHeader("↓ on the last folded header", line: 11, hidden: 12)
            }
            ctx.model.send(.unfoldAll); await ctx.settle(150)

            // 걸음: 편 문서에서와 같은 선택이어야 한다. 머리 줄 끝의 ⇧→ 는 줄 끝 두 글자만 고르고 접힘은 닫힌 채다 — 그 뒤의 ⌫ 는 그 두 글자만 지운다
            for c in ["moveRight:", "moveRightAndModifySelection:", "moveForward:", "moveWordRight:", "moveWordRightAndModifySelection:", "moveDownAndModifySelection:", "moveParagraphForwardAndModifySelection:",
                      "moveToRightEndOfLine:", "moveToEndOfLineAndModifySelection:"] {
                ctx.at("\(c) at the end of a folded header")
                await ctx.sameMoveAsUnfolded("end of a folded header (CR LF)", fold: 7, place: caret { ctx.contentEnd(7) }, [c])
            }
            for c in ["moveLeft:", "moveLeftAndModifySelection:", "moveBackward:", "moveWordLeft:", "moveWordLeftAndModifySelection:", "moveUpAndModifySelection:", "moveParagraphBackwardAndModifySelection:",
                      "moveToLeftEndOfLine:"] {
                ctx.at("\(c) at the start of the line below a fold")
                await ctx.sameMoveAsUnfolded("start of the line below a fold (CR LF)", fold: 7, place: caret { ctx.lineStart(10) }, [c])
            }
            ctx.at("⇧→ twice at the end of a folded header")
            await ctx.sameMoveAsUnfolded("⇧→ twice (CR LF)", fold: 7, place: caret { ctx.contentEnd(7) }, ["moveRightAndModifySelection:", "moveRightAndModifySelection:"])
            for (name, act) in [("⇧→ at the end of a folded header, then ⌫", { await ctx.key(.right, [.shift]); await ctx.pumpEvent(); await ctx.key(.delete) }),
                                ("⌦ at the end of a folded header", { await ctx.key(.forwardDelete) }),
                                ("⇧⌥→ at the end of a folded header, then ⌫", { await ctx.key(.right, [.shift, .option]); await ctx.pumpEvent(); await ctx.key(.delete) }),
                                ("⌃K at the end of a folded header", { await ctx.command("deleteToEndOfParagraph:") })] as [(String, () async -> Void)] {
                ctx.at(name)
                await ctx.sameAsUnfolded("\(name) (CR LF)", fold: 7, place: caret { ctx.contentEnd(7) }, act: act)
                intact("\(name), restored")
            }
            for (name, act) in [("⇧← at the start of the line below a fold, then ⌫", { await ctx.key(.left, [.shift]); await ctx.pumpEvent(); await ctx.key(.delete) }),
                                ("⌫ at the start of the line below a fold", { await ctx.key(.delete) }),
                                ("⌥⌫ at the start of the line below a fold", { await ctx.key(.delete, [.option]) })] as [(String, () async -> Void)] {
                ctx.at(name)
                await ctx.sameAsUnfolded("\(name) (CR LF)", fold: 7, place: caret { ctx.lineStart(10) }, act: act)
                intact("\(name), restored")
            }

            // ⑤ 줄 끝이 섞인 문서: 마지막 줄만 \r 없이 끝난다 (끝까지 닿는 접힘) · 접는 머리 줄만 \r 없이 끝난다
            ctx.at("mixed line ends: the last line ends without CR, fold the tail")
            let lastBare = (doc as NSString).substring(to: (doc as NSString).length - 2) + "\n"   // 끝의 \r\n 두 단위를 \n 하나로 (Swift 의 Character 로는 \r\n 이 한 글자다)
            await ctx.open(text: lastBare, name: "fold-crlf-last.py")
            await ctx.settle(700)
            if ctx.lineEndings() == [12, 0, 1] {
                ctx.tv.setSelectedRange(NSRange(location: col(13, 6), length: 0)); await ctx.settle(60)
                ctx.model.send(.toggleFold(line: 11)); await ctx.settle(300)
                await typeAtHeader("last line without CR, tail folded", line: 11, hidden: 12, want: [12, 0, 1])
                ctx.model.send(.unfoldAll); await ctx.settle(150)
            } else { ctx.issue("other", "the mixed document was not opened as written: line ends \(ctx.lineEndings())") }
            ctx.at("mixed line ends: only the folded header ends without CR")
            let headerBare = doc.replacingOccurrences(of: "def third(z):\r\n", with: "def third(z):\n")
            await ctx.open(text: headerBare, name: "fold-crlf-header.py")
            await ctx.settle(700)
            if ctx.lineEndings() == [12, 0, 1] {
                ctx.tv.setSelectedRange(NSRange(location: col(8, 6), length: 0)); await ctx.settle(60)
                ctx.model.send(.toggleFold(line: 7)); await ctx.settle(300)
                await typeAtHeader("header without CR", line: 7, hidden: 8, want: [12, 0, 1])
                ctx.model.send(.unfoldAll); await ctx.settle(150)
            } else { ctx.issue("other", "the mixed document was not opened as written: line ends \(ctx.lineEndings())") }

            // ③ 닻이 머리 줄 끝으로 가는 경로: 캐럿 줄이 화면에 보이는 채 모두 접으면 캐럿이 옮겨 간 머리 줄이 캐럿 줄이 있던 높이에 온다
            ctx.at("fold all keeps the caret's header at the caret line's height")
            let long = RealUse.foldDoc(h1: false, sections: 60).replacingOccurrences(of: "\n", with: "\r\n")
            await ctx.open(text: long, name: "fold-crlf-long.md")
            await ctx.settle(700)
            let endsLong = ctx.lineEndings()
            let h9 = RealUse.foldHeader(9)
            await ctx.look(atLine: h9 + 3)
            ctx.tv.setSelectedRange(NSRange(location: col(h9 + 3, 6), length: 0)); await ctx.settle(100)
            if endsLong[1] == 0 && endsLong[2] == 0, let yBody = ctx.caretLineScreenY() {
                ctx.model.send(.foldAll); await ctx.settle(300)
                let yHeader = ctx.caretLineScreenY()
                ctx.note("fold all (CR LF): the caret line was at y \(String(format: "%.1f", yBody)); its header is now at \(yHeader.map { String(format: "%.1f", $0) } ?? "off screen"); caret \(ctx.place(ctx.caret))")
                if let yHeader { if abs(yHeader - yBody) > 2 { ctx.issue("viewport-jump", "fold all (CR LF): the caret line was at y \(String(format: "%.1f", yBody)), but the header the caret moved to is at y \(String(format: "%.1f", yHeader))") } }
                else { ctx.issue("caret-hidden", "fold all (CR LF): the header the caret moved to is not on screen") }
                pillAfterText("fold all (CR LF)", line: h9)
                await typeAtHeader("fold all in a long CR LF document", line: h9, hidden: h9 + 1, want: endsLong)
                ctx.checkInk("fold all (CR LF)"); ctx.snap("fold-all")
                ctx.model.send(.unfoldAll); await ctx.settle(300)
                ctx.checkCaretVisible("unfold all (CR LF)"); ctx.checkAllD("unfold all (CR LF)")
            } else { ctx.issue("other", "the long CR LF document: line ends \(endsLong), caret line \(ctx.caretLineScreenY() == nil ? "off screen" : "on screen")") }
        },
    ]
}
