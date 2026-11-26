import AppKit
import HyperCore

// 실사용 시뮬레이션 — 접힌 글 지키기. 숨은 문단은 배치에 없어서(FoldController.swift 머리말) AppKit 이 배치에서 구하는 이동·삭제 범위는 접힘을 통째로 건너뛴다.
// 여기서는 사용자가 보지 못하는 글이 사용자 모르게 지워지거나 바뀌지 않는지, 접힘이 까닭 없이 펴지지 않는지를 본다.
// 기준은 "같은 조작을 다 편 문서에서 한 결과" 다: 접힌 문서에서 한 결과가 그것과 다르면(더 많이 지워졌으면) 그 차이가 숨은 글이다.

extension RealUseContext {
    /// 키 바인딩이 부르는 명령을 그대로 보낸다 (하네스의 Key 에 없는 것 — ⌃K·⌃T·⌃A·⌃E …). 실제 키도 keyDown → 키 바인딩 → doCommand 로 여기에 닿는다
    func command(_ name: String) async {
        if window.firstResponder !== tv { window.makeFirstResponder(tv) }
        tv.doCommand(by: NSSelectorFromString(name))
        await turn()
    }

    /// 두 글의 같은 머리·꼬리 길이 (겹치지 않게)
    func commonEnds(_ a: NSString, _ b: NSString) -> (prefix: Int, suffix: Int) {
        let n = min(a.length, b.length)
        var p = 0
        while p < n, a.character(at: p) == b.character(at: p) { p += 1 }
        var s = 0
        while s < n - p, a.character(at: a.length - 1 - s) == b.character(at: b.length - 1 - s) { s += 1 }
        return (p, s)
    }

    /// 글을 `original` 로 되돌린다 — 되돌리기(⌘Z)로, 조작 하나가 undo 한 단계인지도 함께 본다 (`undos`: 그 조작이 만든 undo 단계 수)
    func restoreText(_ original: NSString, undos: Int = 1, _ label: String) async {
        var n = 0
        while !text.isEqual(to: original as String), n < undos { model.send(.undo); await pumpEvent(); await settle(120); n += 1 }
        if tv.multi != nil { await key(.escape) }
        if !text.isEqual(to: original as String) {
            issue("text", "\(label): \(undos) undo(s) did not bring the text back (length \(length), expected \(original.length))")
            tv.insertText(original as String, replacementRange: NSRange(location: 0, length: length)); await pumpEvent()
        }
        await settle(450)   // 줄 인덱스 250 ms + 영역 스캔
    }

    /// `header` 줄의 영역을 접는다 (다른 접힘은 모두 편 상태에서). 반환: 숨겨진 구간
    func foldOnly(_ header: Int, _ label: String) async -> NSRange? {
        model.send(.unfoldAll); await settle(150)
        model.send(.toggleFold(line: header)); await settle(250)
        if !hidden(line: header + 1) { await settle(500); model.send(.toggleFold(line: header)); await settle(250) }   // 영역 스캔이 덜 끝났을 수 있다
        guard hidden(line: header + 1), let span = tv.foldedSpan?(lineStart(header + 1)) else { issue("other", "\(label): line \(header) did not fold"); return nil }
        return span
    }

    /// 한 조작을 (1) 다 편 문서에서 해 기준 결과를 얻고 되돌린 뒤 (2) `header` 줄의 영역을 접고 똑같이 한다. 접힌 문서의 결과는 기준과 같아야 한다 —
    /// 접힌 문서에서만 더 지워졌거나 바뀌었다면 그것이 숨은 글이다. 숨은 글이 바뀌었으면 그 접힘은 펴져 있어야 한다(사용자가 바뀐 것을 본다).
    /// 끝나면 글을 되돌리고 모두 편다.
    /// - `place`: 캐럿·선택을 놓는다 (두 번 불린다 — 그때의 배치에서 좌표를 구할 것). false 면 그만둔다
    /// - `ready`: 접힌 문서에서 `place` 뒤, 조작 직전에 볼 것 (숨은 구간을 받는다)
    @discardableResult
    func sameAsUnfolded(_ label: String, fold header: Int, undos: Int = 1, place: () async -> Bool, ready: ((NSRange) -> Void)? = nil, act: () async -> Void) async -> Bool {
        model.send(.unfoldAll); await settle(150)
        let original = textCopy()
        guard await place() else { return false }
        await pumpEvent(); tv.breakUndoCoalescing()
        await act()
        await pumpEvent(); await settle(150)
        let reference = textCopy()
        let referenceSelection = tv.multi?.ranges ?? [tv.selectedRange()]
        await restoreText(original, undos: undos, "\(label) (open document)")

        guard let span = await foldOnly(header, label) else { return false }
        guard await place() else { model.send(.unfoldAll); await settle(150); return false }
        ready?(span)
        await pumpEvent(); tv.breakUndoCoalescing()
        await act()
        await pumpEvent(); await settle(300)
        let result = textCopy()
        let ends = commonEnds(original, result)
        let changed = NSRange(location: ends.prefix, length: max(0, original.length - ends.suffix - ends.prefix))
        let touchedHidden = !result.isEqual(to: original as String)
            && (NSIntersectionRange(changed, span).length > 0 || (changed.length == 0 && changed.location >= span.location && changed.location < NSMaxRange(span)))
        var same = true
        note("\(label): open document \(original.length) → \(reference.length) characters, folded \(original.length) → \(result.length); the fold is now \(foldsActive ? "closed" : "open")")
        if !result.isEqual(to: reference as String) {
            same = false
            issue("fold-loss", "\(label): with the region folded the text went from \(original.length) to \(result.length) characters, in the open document the same keys give \(reference.length) — "
                  + "the changed range \(changed) holds \(NSIntersectionRange(changed, span).length) of the \(span.length) hidden characters")
        } else {
            let selection = tv.multi?.ranges ?? [tv.selectedRange()]
            if selection != referenceSelection { issue("fold", "\(label): the text is the same as in the open document but the selection is \(selection), there \(referenceSelection)") }
        }
        if touchedHidden, foldsActive {   // 접어 둔 것은 이 영역 하나뿐이다
            issue("fold", "\(label): hidden text changed (range \(changed) of the text before) but the fold is still closed — the change is not on screen")
        }
        checkAllD(label); checkFoldState(label); checkInk(label)
        await restoreText(original, undos: undos, "\(label) (folded document)")
        model.send(.unfoldAll); await settle(150)
        return same
    }

    /// 캐럿만 옮기는 명령을 편 문서와 접힌 문서에서 견준다. 편 문서에서 아무 일도 하지 않는 명령(줄 끝에서 ⌘→, 줄 머리에서 ⌘←)은 접힌 문서에서도 아무 일도
    /// 하지 않아야 한다 — 접힘이 펴져서는 안 된다. 편 문서에서 숨을 줄로 들어가는 명령은 접힌 문서에서 캐럿이 숨은 채 남지만 않으면 된다(그 접힘이 펴진다).
    func sameMoveAsUnfolded(_ label: String, fold header: Int, place: () async -> Bool, _ commands: [String]) async {
        model.send(.unfoldAll); await settle(150)
        guard await place() else { return }
        let start = tv.selectedRange()
        var referenceBeforeLast = start
        for c in commands { referenceBeforeLast = tv.selectedRange(); await command(c) }
        await settle(80)
        let reference = tv.selectedRange()
        guard let span = await foldOnly(header, label) else { return }
        guard await place() else { model.send(.unfoldAll); await settle(150); return }
        var beforeLast = tv.selectedRange()
        for c in commands { beforeLast = tv.selectedRange(); await command(c) }
        await settle(200)
        let now = tv.selectedRange()
        /// 캐럿이 숨은 줄에 있거나, 선택이 숨은 글자를 품는가 (머리 줄의 개행만 고른 선택은 아니다)
        func inside(_ r: NSRange) -> Bool { r.length == 0 ? NSLocationInRange(r.location, span) : NSIntersectionRange(r, span).length > 0 }
        let closed = hidden(span.location)
        if reference == start {
            if now != start || !closed {
                issue("fold", "\(label): \(commands.joined(separator: " ")) does nothing in the open document (selection stays \(start)), but with the region folded the selection is \(now) and the fold is \(closed ? "closed" : "open")")
            }
        } else if !inside(reference) {
            if now != reference || !closed {
                issue("fold", "\(label): \(commands.joined(separator: " ")) selects \(reference) in the open document without touching the folded lines, but with the region folded it gives \(now) and the fold is \(closed ? "closed" : "open")")
            }
        } else {
            if hidden(now.location) || (now.length > 0 && inside(now) && closed) { issue("fold", "\(label): \(commands.joined(separator: " ")) left the selection \(now) on hidden lines (fold \(span))") }
            // 편 문서에서 숨을 줄로 들어가는 걸음이다. 접힌 문서에서 접힘이 닫힌 채 그 너머로 넘어갔거나(다음 ⇧ 걸음·삭제가 접힘을 통째로 품는다),
            // 마지막 키가 아무 일도 하지 않았으면(몇 번을 눌러도 그대로다) 안 된다
            else if closed, now.length == 0, (beforeLast.location < span.location && now.location >= NSMaxRange(span)) || (beforeLast.location >= NSMaxRange(span) && now.location < span.location) {
                issue("fold", "\(label): \(commands.joined(separator: " ")) enters the folded lines in the open document (\(reference)), but with the region folded the caret jumped over the closed fold to \(now)")
            } else if closed, now == beforeLast, reference != referenceBeforeLast {
                issue("fold", "\(label): the last of \(commands.joined(separator: " ")) moves the selection to \(reference) in the open document, but with the region folded it does nothing (selection stays \(now), the fold stays closed)")
            }
            if now != reference { note("\(label): \(commands.joined(separator: " ")) → \(now) with the region folded, \(reference) in the open document (the fold is \(closed ? "closed" : "open"))") }
        }
        checkCaretVisible(label); checkFoldState(label)
        model.send(.unfoldAll); await settle(150)
    }
}

extension RealUse {
    /// 들여쓰기 영역이 겹겹인 짧은 코드 — 13줄이라 편집기(382 pt)에 한 화면으로 다 보인다. 영역: 1(2…5) · 2(3…4) · 7(8…9) · 11(12…13, 문서 끝까지)
    static let guardDoc = [
        "class Sample:",                 // 1
        "    def first(a, b):",          // 2
        "        body one alpha",        // 3
        "        body two beta",         // 4
        "    x = 1 after first",         // 5
        "plain line below class",        // 6
        "def third(z):",                 // 7
        "    third one",                 // 8
        "    third two words",           // 9
        "last plain line",               // 10
        "tail:",                         // 11
        "    tail one",                  // 12
        "    tail two end",              // 13
    ].joined(separator: "\n") + "\n"

    @MainActor static let foldGuardScenarios: [Scenario] = [
        // 접힌 블록 옆에서 선택 없이 지우는 키(단어·줄·문단 단위), 줄 도구, 접힘을 가로지른 선택 위의 입력·삭제 — 숨은 글이 사용자 모르게 사라지지 않는가
        Scenario(name: "fold-delete") { ctx in
            await ctx.open(text: RealUse.guardDoc, name: "fold-delete.py")
            await ctx.settle(700)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            guard ctx.markers(inLines: 1...13)[7] == .foldable, ctx.markers(inLines: 1...13)[11] == .foldable else { ctx.issue("other", "the guard document has no foldable regions at lines 7 and 11"); return }
            @MainActor func offset(_ line: Int, _ col: Int?) -> Int { col.map { ctx.lineStart(line) + $0 } ?? ctx.lineEnd(line) }
            /// 캐럿을 (줄, 열)에 두고(열 nil = 줄 끝) 조작한다
            @MainActor func caretCase(_ label: String, fold header: Int, line: Int, col: Int?, undos: Int = 1, _ act: () async -> Void) async {
                ctx.at(label)
                await ctx.sameAsUnfolded(label, fold: header, undos: undos, place: { await ctx.clickExpect(offset(line, col), "\(label): place the caret") }, act: act)
            }
            // ① 단어 단위로 뒤로 지우기: 접힘 아래 줄의 머리 / 들여쓰기 뒤 (공백과 개행을 건너 앞 단어까지 지운다)
            await caretCase("⌥⌫ at the start of the line below a fold", fold: 7, line: 10, col: 0) { await ctx.key(.delete, [.option]) }
            ctx.snap("word-delete-below-fold")
            await caretCase("⌥⌫ after the indentation of the line below a fold", fold: 2, line: 5, col: 4) { await ctx.key(.delete, [.option]) }
            await caretCase("⌥⌫ at the start of the indented line below a fold", fold: 2, line: 5, col: 0) { await ctx.key(.delete, [.option]) }
            await caretCase("⌥⌫ twice at the start of the line below a fold", fold: 7, line: 10, col: 0, undos: 2) { await ctx.key(.delete, [.option]); await ctx.pumpEvent(); await ctx.key(.delete, [.option]) }
            // ② 단어 단위로 앞으로 지우기: 접힌 머리 줄 끝 (문서 끝까지 닿는 접힘도)
            await caretCase("⌥⌦ at the end of a folded header", fold: 7, line: 7, col: nil) { await ctx.key(.forwardDelete, [.option]) }
            await caretCase("⌥⌦ at the end of the header of a fold that reaches the end", fold: 11, line: 11, col: nil) { await ctx.key(.forwardDelete, [.option]) }
            // ③ 줄 머리까지 지우기
            await caretCase("⌘⌫ at the start of the line below a fold", fold: 7, line: 10, col: 0) { await ctx.key(.delete, [.command]) }
            await caretCase("⌘⌫ after the indentation of the line below a fold", fold: 2, line: 5, col: 4) { await ctx.key(.delete, [.command]) }
            await caretCase("deleteToBeginningOfParagraph at the start of the line below a fold", fold: 7, line: 10, col: 0) { await ctx.command("deleteToBeginningOfParagraph:") }
            // ④ 줄·문단 끝까지 지우기 (⌃K)
            await caretCase("⌃K at the end of a folded header", fold: 7, line: 7, col: nil) { await ctx.command("deleteToEndOfParagraph:") }
            await caretCase("⌃K at the end of the header of a fold that reaches the end", fold: 11, line: 11, col: nil) { await ctx.command("deleteToEndOfParagraph:") }
            await caretCase("deleteToEndOfLine at the end of a folded header", fold: 7, line: 7, col: nil) { await ctx.command("deleteToEndOfLine:") }
            // ⑤ 한 글자
            await caretCase("⌫ at the start of the line below a fold", fold: 7, line: 10, col: 0) { await ctx.key(.delete) }
            await caretCase("⌦ at the end of a folded header", fold: 7, line: 7, col: nil) { await ctx.key(.forwardDelete) }
            await caretCase("⌦ at the end of the header of a fold that reaches the end", fold: 11, line: 11, col: nil) { await ctx.key(.forwardDelete) }
            await caretCase("⌃⌫ at the start of the line below a fold", fold: 7, line: 10, col: 0) { await ctx.command("deleteBackwardByDecomposingPreviousCharacter:") }
            await caretCase("⌃T at the start of the line below a fold", fold: 7, line: 10, col: 0) { await ctx.command("transpose:") }
            // 접힘과 떨어진 자리의 같은 키는 접힘을 그대로 둔다
            ctx.at("word and line deletes away from the fold leave it closed")
            if let span = await ctx.foldOnly(7, "deletes away from the fold") {
                let before = ctx.length
                await ctx.clickExpect(offset(10, 9), "click inside the line below the fold")
                await ctx.key(.delete, [.option]); await ctx.pumpEvent()
                await ctx.clickExpect(offset(7, 3), "click inside the folded header")
                await ctx.key(.forwardDelete, [.option]); await ctx.pumpEvent(); await ctx.settle(500)
                ctx.expect(ctx.length < before && ctx.hidden(ctx.lineStart(8)) && ctx.foldCount() == 1, "fold",
                           "word deletes inside the header and inside the line below (not next to the fold): length \(before) → \(ctx.length), fold closed \(ctx.hidden(ctx.lineStart(8))), pills \(ctx.foldCount()) (fold was \(span))")
                ctx.checkAllD("deletes away from the fold"); ctx.checkFoldState("deletes away from the fold")
                ctx.model.send(.undo); await ctx.pumpEvent(); ctx.model.send(.undo); await ctx.pumpEvent(); await ctx.settle(450)
                ctx.expect(ctx.text.isEqual(to: RealUse.guardDoc), "text", "two undos did not restore the text (length \(ctx.length))")
            }

            // ⑥ 줄 도구: 접힌 머리 줄과 그 이웃 줄에서
            @MainActor func toolCase(_ label: String, _ tool: TextTool, line: Int) async {
                ctx.at(label)
                await ctx.sameAsUnfolded(label, fold: 7, place: { await ctx.clickExpect(offset(line, 2), "\(label): place the caret") }) { ctx.model.textTool(tool); await ctx.settle(100) }
            }
            await toolCase("delete line on a folded header", .deleteLine, line: 7)
            await toolCase("delete line on the line below a fold", .deleteLine, line: 10)
            await toolCase("delete line on the line above a folded header", .deleteLine, line: 6)
            await toolCase("duplicate line on a folded header", .duplicateLine, line: 7)
            await toolCase("duplicate line on the line above a folded header", .duplicateLine, line: 6)
            await toolCase("move line down on a folded header", .moveLineDown, line: 7)
            await toolCase("move line up on a folded header", .moveLineUp, line: 7)
            await toolCase("move line up on the line below a fold", .moveLineUp, line: 10)
            await toolCase("move line down on the line above a folded header", .moveLineDown, line: 6)
            await toolCase("join lines on a folded header", .joinLines, line: 7)
            await toolCase("upper case on a folded header", .upper, line: 7)
            ctx.snap("line-tools")

            // ⑦ 접힘을 통째로 가로지른 선택(양 끝이 보인다) 위의 입력·삭제·여러 줄 넣기. 잘라내기·붙여넣기는 사용자의 클립보드를 쓰므로 같은 편집 경로
            //    (delete: · insertText)로 대신한다. 끌어다 놓기는 실제 끌기 세션이 필요해 여기서 하지 않는다
            @MainActor func across() async -> Bool {
                let a = offset(6, 6), b = offset(10, 4)
                guard let pa = ctx.point(forOffset: a), let pb = ctx.point(forOffset: b) else { ctx.issue("other", "lines 6 and 10 are not on screen to drag across"); return false }
                await ctx.mdrag(from: pa, to: pb); await ctx.settle(80)
                let want = NSRange(location: a, length: b - a)
                if ctx.tv.selectedRange() != want { ctx.issue("selection", "dragging from line 6 to line 10: selection \(ctx.tv.selectedRange()), expected \(want)"); return false }
                return true
            }
            @MainActor func stillClosed(_ why: String) -> (NSRange) -> Void {
                { span in ctx.expect(ctx.hidden(span.location), "fold", "\(why): selecting across the fold (both ends visible) opened it") }
            }
            ctx.at("type over a selection that spans a fold")
            await ctx.sameAsUnfolded("type over a selection that spans a fold", fold: 7, place: across, ready: stillClosed("type over")) { await ctx.type("Z") }
            ctx.at("delete a selection that spans a fold")
            await ctx.sameAsUnfolded("delete a selection that spans a fold (the edit Cut makes)", fold: 7, place: across, ready: stillClosed("delete")) { ctx.tv.delete(nil); await ctx.turn() }
            ctx.at("⌫ on a selection that spans a fold")
            await ctx.sameAsUnfolded("⌫ on a selection that spans a fold", fold: 7, place: across, ready: stillClosed("⌫")) { await ctx.key(.delete) }
            ctx.at("insert two lines over a selection that spans a fold")
            await ctx.sameAsUnfolded("insert two lines over a selection that spans a fold (the edit Paste makes)", fold: 7, place: across, ready: stillClosed("paste")) {
                ctx.tv.insertText("pasted one\npasted two", replacementRange: NSRange(location: NSNotFound, length: 0)); await ctx.turn()
            }
            ctx.at("⌥⌫ with a selection that spans a fold deletes the selection only")
            await ctx.sameAsUnfolded("⌥⌫ with a selection that spans a fold", fold: 7, place: across) { await ctx.key(.delete, [.option]) }
            ctx.snap("end")
        },

        // 캐럿이 움직이지 않는 줄 머리·줄 끝 키(⌘← ⌘→ ⌃A ⌃E 와 ⇧ 변형)가 옆의 접힘을 펴지 않는가. 글자·단어 걸음이 접힘 안으로 들어가는 것은 그대로다
        Scenario(name: "fold-lineends") { ctx in
            await ctx.open(text: RealUse.guardDoc, name: "fold-lineends.py")
            await ctx.settle(700)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            @MainActor func offset(_ line: Int, _ col: Int?) -> Int { col.map { ctx.lineStart(line) + $0 } ?? ctx.lineEnd(line) }
            ctx.at("⌘→ twice on a folded header, type, ⌘← on the line below")
            if await ctx.foldOnly(7, "⌘→ on a folded header") != nil {
                await ctx.clickExpect(offset(7, 4), "click inside the folded header")
                await ctx.key(.right, [.command]); await ctx.settle(100)
                ctx.expectCaret(offset(7, nil), "⌘→ on the folded header")
                ctx.expect(ctx.hidden(line: 8), "fold", "⌘→ from inside a folded header opened the fold")
                await ctx.key(.right, [.command]); await ctx.settle(200)
                ctx.expectCaret(offset(7, nil), "a second ⌘→ at the end of the folded header")
                ctx.expect(ctx.hidden(line: 8) && ctx.foldCount() == 1, "fold", "a second ⌘→ at the end of a folded header opened the fold (caret \(ctx.place(ctx.caret)), pills \(ctx.foldCount()))")
                await ctx.type(" # end"); await ctx.settle(500)
                ctx.expect(ctx.hidden(line: 8) && ctx.caretLineText() == "def third(z): # end", "fold", "typing after ⌘→ ⌘→ on a folded header: line \"\(ctx.caretLineText())\", folded \(ctx.hidden(line: 8))")
                await ctx.clickExpect(offset(10, 0), "click the start of the line below the fold")
                await ctx.key(.left, [.command]); await ctx.settle(200)
                ctx.expectCaret(offset(10, 0), "⌘← at the start of the line below a fold")
                ctx.expect(ctx.hidden(line: 8) && ctx.foldCount() == 1, "fold", "⌘← at the start of the line below a fold opened the fold (caret \(ctx.place(ctx.caret)))")
                ctx.checkAllD("line-end keys next to a fold"); ctx.checkFoldState("line-end keys next to a fold"); ctx.snap("line-ends")
                await ctx.restoreText(RealUse.guardDoc as NSString, undos: 6, "undo the typing")
            }
            // 명령마다: 편 문서에서의 결과와 견준다
            let atEnd = ["moveToRightEndOfLine:", "moveToEndOfLine:", "moveToRightEndOfLineAndModifySelection:", "moveToEndOfLineAndModifySelection:",
                         "moveToEndOfParagraph:", "moveToEndOfParagraphAndModifySelection:", "moveParagraphForwardAndModifySelection:", "moveRight:", "moveWordRight:", "moveRightAndModifySelection:", "moveDownAndModifySelection:"]
            for c in atEnd {
                ctx.at("\(c) at the end of a folded header")
                await ctx.sameMoveAsUnfolded("end of a folded header", fold: 7, place: { await ctx.clickExpect(offset(7, nil), "click the end of the folded header") }, [c])
            }
            let atStart = ["moveToLeftEndOfLine:", "moveToBeginningOfLine:", "moveToLeftEndOfLineAndModifySelection:", "moveToBeginningOfLineAndModifySelection:",
                           "moveToBeginningOfParagraph:", "moveToBeginningOfParagraphAndModifySelection:", "moveParagraphBackwardAndModifySelection:", "moveLeft:", "moveWordLeft:", "moveLeftAndModifySelection:", "moveUpAndModifySelection:"]
            for c in atStart {
                ctx.at("\(c) at the start of the line below a fold")
                await ctx.sameMoveAsUnfolded("start of the line below a fold", fold: 7, place: { await ctx.clickExpect(offset(10, 0), "click the start of the line below the fold") }, [c])
            }
            for c in ["moveToRightEndOfLine:", "moveToEndOfLine:", "moveToEndOfParagraph:", "moveToRightEndOfLineAndModifySelection:", "moveParagraphForwardAndModifySelection:"] {
                ctx.at("\(c) at the end of the header of a fold that reaches the end")
                await ctx.sameMoveAsUnfolded("end of the last folded header", fold: 11, place: { await ctx.clickExpect(offset(11, nil), "click the end of the last header") }, [c])
            }
            // 줄 가운데에서 누르면 보통대로 움직이고 접힘은 그대로다
            for (c, line) in [("moveToRightEndOfLine:", 7), ("moveToLeftEndOfLine:", 10), ("moveToEndOfParagraph:", 7), ("moveToBeginningOfParagraph:", 10), ("moveToLeftEndOfLine:", 7), ("moveToRightEndOfLine:", 10)] {
                ctx.at("\(c) from the middle of line \(line)")
                await ctx.sameMoveAsUnfolded("middle of line \(line)", fold: 7, place: { await ctx.clickExpect(offset(line, 5), "click inside line \(line)") }, [c])
            }
        },

        // 모두 바꾸기가 접힘 위와 안을 함께 바꿀 때: 접힘이 펴진 뒤 모든 줄(문서의 마지막 줄까지)이 보이는가
        Scenario(name: "fold-replace") { ctx in
            let doc = ["first foo here", "second line", "function mid() {", "    mid foo one", "    mid two", "}", "between foo line",
                       "function tail() {", "    inner foo one", "    inner two", "    inner three", "}"].joined(separator: "\n") + "\n"
            await ctx.open(text: doc, name: "fold-replace.js")
            await ctx.settle(700)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            @MainActor func foldBoth() async -> Bool {
                ctx.model.send(.unfoldAll); await ctx.settle(150)
                ctx.model.send(.toggleFold(line: 3)); await ctx.settle(150)
                ctx.model.send(.toggleFold(line: 8)); await ctx.settle(250)
                let ok = ctx.hidden(line: 4) && ctx.hidden(line: 6) && !ctx.hidden(line: 7) && ctx.hidden(line: 9) && ctx.hidden(line: 12) && ctx.hidden(ctx.length) && ctx.foldCount() == 2
                if !ok { ctx.issue("other", "the two blocks did not fold: hidden(4)=\(ctx.hidden(line: 4)) hidden(9)=\(ctx.hidden(line: 9)) end hidden \(ctx.hidden(ctx.length)) pills \(ctx.foldCount())") }
                return ok
            }
            /// 모든 줄이 보이는가: 배치(높이)·잉크·마지막 줄 클릭
            @MainActor func allShown(_ why: String, lines: Int) async {
                ctx.expect(!ctx.foldsActive && ctx.foldCount() == 0, "fold", "\(why): hidden text was replaced but a fold is still closed (pills \(ctx.foldCount()))")
                ctx.checkAllD(why); ctx.checkFoldState(why); ctx.checkInk(why)
                let shown = ctx.viewportFragments().count
                ctx.expect(shown == lines, "fold", "\(why): \(shown) of \(lines) lines are laid out with a height — the others are not on screen")
                await ctx.clickExpect(ctx.lineStart(lines), "\(why): click the last line of the file")
            }
            @MainActor func replaceAll(_ query: String, _ with: String) async { ctx.model.searchQuery = query; ctx.model.replaceText = with; ctx.model.replaceAll(); await ctx.pumpEvent(); await ctx.settle(800) }

            ctx.at("replace all, growing: matches above, inside and between two folds")
            if await foldBoth() {
                ctx.checkAllD("two blocks folded"); ctx.checkFoldState("two blocks folded"); ctx.snap("folded")
                await replaceAll("foo", "fooBar")
                ctx.expect(ctx.text.isEqual(to: doc.replacingOccurrences(of: "foo", with: "fooBar")), "text", "replace all foo → fooBar: unexpected text (length \(ctx.length))")
                await allShown("replace all (growing) across two folds", lines: 12); ctx.snap("replaced-growing")
                await ctx.restoreText(doc as NSString, "undo the replace all")
                await allShown("undo of the replace all", lines: 12)
            }
            ctx.at("replace all, shrinking: matches above, inside and between two folds")
            if await foldBoth() {
                await replaceAll("foo", "f")
                ctx.expect(ctx.text.isEqual(to: doc.replacingOccurrences(of: "foo", with: "f")), "text", "replace all foo → f: unexpected text (length \(ctx.length))")
                await allShown("replace all (shrinking) across two folds", lines: 12); ctx.snap("replaced-shrinking")
                await ctx.restoreText(doc as NSString, "undo the replace all")
            }
            ctx.at("replace all outside the folds keeps them, moved by the change")
            if await foldBoth() {
                await replaceAll("line", "LINE!!")   // 2, 7 번 줄 — 접힘 밖
                ctx.expect(ctx.hidden(line: 4) && ctx.hidden(line: 6) && !ctx.hidden(line: 7) && !ctx.hidden(line: 8) && ctx.hidden(line: 9) && ctx.hidden(line: 12) && ctx.foldCount() == 2, "fold",
                           "replace all outside the folds: hidden(4)=\(ctx.hidden(line: 4)) hidden(7)=\(ctx.hidden(line: 7)) hidden(8)=\(ctx.hidden(line: 8)) hidden(9)=\(ctx.hidden(line: 9)) pills \(ctx.foldCount())")
                ctx.checkAllD("replace all outside the folds"); ctx.checkFoldState("replace all outside the folds"); ctx.checkInk("replace all outside the folds")
                ctx.expect(ctx.viewportFragments().count == 5, "fold", "replace all outside the folds: \(ctx.viewportFragments().count) lines laid out with a height, expected 5 (lines 1, 2, 3, 7, 8)")
                await ctx.restoreText(doc as NSString, "undo the replace all")
                ctx.expect(ctx.hidden(line: 4) && ctx.hidden(line: 9) && ctx.foldCount() == 2, "fold", "undo of a replace all outside the folds: hidden(4)=\(ctx.hidden(line: 4)) hidden(9)=\(ctx.hidden(line: 9)) pills \(ctx.foldCount())")
                ctx.checkAllD("undo of the replace all outside the folds"); ctx.checkFoldState("undo of the replace all outside the folds")
            }
            ctx.at("replace all with a match only inside the last fold")
            if await foldBoth() {
                await replaceAll("inner two", "inner 2 (two)")
                ctx.expect(!ctx.hidden(line: 9) && !ctx.hidden(line: 12) && ctx.hidden(line: 4) && ctx.foldCount() == 1, "fold", "replace all inside the last fold: hidden(9)=\(ctx.hidden(line: 9)) hidden(4)=\(ctx.hidden(line: 4)) pills \(ctx.foldCount())")
                ctx.checkAllD("replace all inside the last fold"); ctx.checkFoldState("replace all inside the last fold"); ctx.checkInk("replace all inside the last fold")
                ctx.expect(ctx.viewportFragments().count == 9, "fold", "replace all inside the last fold: \(ctx.viewportFragments().count) lines laid out with a height, expected 9")
                await ctx.clickExpect(ctx.lineStart(12), "click the last line after the last fold opened")
                await ctx.restoreText(doc as NSString, "undo the replace all")
            }
            // 문서 끝까지 접힌 채 프로그램이 끝에 덧붙일 때(빠른 추가): 덧붙인 줄이 보이는가
            ctx.at("text appended at the end while a fold reaches the end")
            if await foldBoth() {
                ctx.tv.breakUndoCoalescing()
                ctx.tv.insertText("appended line\n", replacementRange: NSRange(location: ctx.length, length: 0)); await ctx.pumpEvent(); await ctx.settle(600)
                ctx.note("after appending: \(ctx.foldCount()) pills, hidden(9)=\(ctx.hidden(line: 9)) hidden(12)=\(ctx.hidden(line: 12)) hidden(13)=\(ctx.hidden(line: 13)), \(ctx.viewportFragments().count) lines with a height")
                ctx.expect(!ctx.hidden(line: 13), "fold", "a line appended after a fold that reached the end is hidden")
                ctx.checkAllD("appended after a fold that reached the end"); ctx.checkFoldState("appended after a fold that reached the end"); ctx.checkInk("appended after a fold that reached the end")
                ctx.snap("appended")
                await ctx.restoreText(doc as NSString, "undo the append")
            }
            ctx.model.searchQuery = ""; ctx.model.replaceText = ""; ctx.model.runSearch(); await ctx.settle(200)
            ctx.model.send(.unfoldAll); await ctx.settle(200)
        },

        // 열 블록·멀티 캐럿이 접힘에 걸칠 때: 숨은 줄에 블록의 행·추가 캐럿이 놓인 채(보이지 않는 채) 입력을 받지 않는가
        Scenario(name: "fold-multi") { ctx in
            await ctx.open(text: RealUse.guardDoc, name: "fold-multi.py")
            await ctx.settle(700)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            @MainActor func offset(_ line: Int, _ col: Int) -> Int { ctx.lineStart(line) + col }
            @MainActor func rowsShown(_ why: String) -> (NSRange) -> Void {
                { span in
                    let ranges = ctx.tv.multi?.ranges ?? [ctx.tv.selectedRange()]
                    let hiddenRows = ranges.filter { ctx.hidden($0.location) }.map { ctx.liveLine($0.location) }
                    ctx.note("\(why): \(ranges.count) carets/rows, fold \(ctx.hidden(span.location) ? "closed" : "open")")
                    if !hiddenRows.isEmpty { ctx.issue("fold", "\(why): \(hiddenRows.count) of \(ranges.count) rows/carets sit on hidden lines \(hiddenRows) — the next key edits lines that are not on screen") }
                }
            }
            @MainActor func replacing(_ text: NSString, _ ranges: [NSRange], with new: String) -> NSString {
                let m = NSMutableString(string: text as String)
                for r in ranges.sorted(by: { $0.location > $1.location }) { m.replaceCharacters(in: r, with: new) }
                return m
            }
            /// ⌥끌기로 접힘 위(6번 줄)에서 아래(10번 줄)까지 블록을 잡는다. 블록이 숨은 줄에 닿으면 그 접힘이 펴져 줄들이 마우스 아래로 내려오므로 블록의 마지막 행은
            /// 마우스가 멈춘 자리의 줄이다(편 문서에서처럼 5행이 아닐 수 있다) — 어느 쪽이든 모든 행이 화면에 보이고, 다음 키는 그 행들만 고쳐야 한다
            @MainActor func dragBlock(_ why: String, replacement: String, _ act: () async -> Void) async {
                ctx.at(why)
                guard await ctx.foldOnly(7, why) != nil else { return }
                let original = ctx.textCopy()
                guard let a = ctx.point(forOffset: offset(6, 2)), let b = ctx.point(forOffset: offset(10, 6)) else { ctx.issue("other", "\(why): lines 6 and 10 are not on screen"); return }
                await ctx.dragWith(mods: [.option], from: a, to: b); await ctx.settle(150)
                guard let m = ctx.tv.multi, m.isColumn, m.ranges.count >= 2 else { ctx.issue("multi", "\(why): ⌥-drag from line 6 down made \(ctx.tv.multi?.ranges.count ?? 0) rows"); return }
                let rows = m.ranges
                let hiddenRows = rows.filter { ctx.hidden($0.location) }.map { ctx.liveLine($0.location) }
                ctx.note("\(why): \(rows.count) rows on lines \(rows.map { ctx.liveLine($0.location) }), fold \(ctx.foldsActive ? "closed" : "open")")
                if !hiddenRows.isEmpty { ctx.issue("fold", "\(why): \(hiddenRows.count) of \(rows.count) rows sit on hidden lines \(hiddenRows) — the next key edits lines that are not on screen") }
                let laidOut = Set(ctx.viewportFragments().map(\.offset))
                let unseen = rows.map { ctx.liveLine($0.location) }.filter { !laidOut.contains(ctx.lineStart($0)) }
                if !unseen.isEmpty, hiddenRows.isEmpty { ctx.issue("fold", "\(why): the block has rows on lines \(unseen) that are not laid out on screen") }
                ctx.expectBlockHighlighted(why); ctx.expectSelectionPainted(why)
                await ctx.pumpEvent(); ctx.tv.breakUndoCoalescing()
                await act()
                await ctx.pumpEvent(); await ctx.settle(300)
                let want = replacing(original, rows, with: replacement)
                ctx.expect(ctx.text.isEqual(to: want as String), "fold-loss", "\(why): the key changed the text to \(ctx.length) characters; replacing the \(rows.count) rows that were shown gives \(want.length)")
                ctx.expect(!ctx.foldsActive, "fold", "\(why): rows inside the fold were edited but the fold is closed")
                ctx.checkAllD(why); ctx.checkFoldState(why); ctx.checkInk(why)
                await ctx.restoreText(original, why)
                ctx.model.send(.unfoldAll); await ctx.settle(150)
            }
            await dragBlock("type into a column block ⌥-dragged across a fold", replacement: "Q") { await ctx.type("Q") }
            ctx.snap("block-typed")
            await dragBlock("⌫ in a column block ⌥-dragged across a fold", replacement: "") { await ctx.key(.delete) }
            ctx.at("column mode: ⇧↓ from a folded header, then type")
            ctx.model.columnMode = true; await ctx.settle(80)
            await ctx.sameAsUnfolded("type into a block extended with ⇧↓ from a folded header", fold: 7, place: {
                guard await ctx.clickExpect(offset(7, 3), "click the folded header") else { return false }
                await ctx.key(.right, [.shift]); await ctx.key(.right, [.shift])
                await ctx.key(.down, [.shift]); await ctx.key(.down, [.shift]); await ctx.key(.down, [.shift]); await ctx.settle(120)
                guard let m = ctx.tv.multi, m.isColumn, m.ranges.count == 4 else { ctx.issue("multi", "⇧→⇧→⇧↓⇧↓⇧↓ in column mode made \(ctx.tv.multi?.ranges.count ?? 0) rows, expected 4"); return false }
                return true
            }, ready: rowsShown("block extended with ⇧↓ from a folded header")) { await ctx.type("W") }
            ctx.model.columnMode = false; await ctx.settle(80)
            ctx.at("select all matches (some inside a fold), then type")
            await ctx.sameAsUnfolded("type over all matches selected as carets", fold: 7, place: {
                let gen = ctx.model.searchCompletionCount
                ctx.model.searchQuery = "third"; ctx.model.runSearch()
                guard await ctx.awaitSearch(after: gen), ctx.model.searchHits.count == 3 else { ctx.issue("find", "'third' found \(ctx.model.searchHits.count) matches, expected 3"); return false }
                ctx.model.selectAllMatches(); await ctx.settle(150)
                guard ctx.tv.multi?.ranges.count == 3 else { ctx.issue("multi", "select all matches made \(ctx.tv.multi?.ranges.count ?? 0) carets, expected 3"); return false }
                return true
            }, ready: rowsShown("all matches selected as carets")) { await ctx.type("3rd") }
            ctx.model.searchQuery = ""; ctx.model.runSearch(); await ctx.settle(200)
            ctx.at("⌘D adds the next occurrence inside a fold, then type")
            await ctx.sameAsUnfolded("type over the occurrences added with ⌘D", fold: 7, place: {
                ctx.tv.setSelectedRange(NSRange(location: offset(7, 4), length: 5))   // "third"
                await ctx.settle(60)
                ctx.model.send(.addNextOccurrence); await ctx.settle(120)
                guard ctx.tv.multi?.ranges.count == 2 else { ctx.issue("multi", "⌘D made \(ctx.tv.multi?.ranges.count ?? 0) selections, expected 2"); return false }
                return true
            }, ready: rowsShown("occurrence added with ⌘D")) { await ctx.type("x") }
            ctx.snap("end")

            // 모두 접은 1.3 MB 메모에서 수백 번 나오는 낱말의 모든 일치를 캐럿으로: 캐럿이 놓인 접힘이 한 번에 펴지고(수백~수천 개), 멈추지 않는다
            ctx.at("select all matches in a fully folded 1.3 MB document")
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "fold-multi-notes.md") }
            await ctx.settle(900)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            ctx.model.send(.foldAll); await ctx.settle(500)
            let gen = ctx.model.searchCompletionCount
            ctx.model.searchQuery = "budget"; ctx.model.runSearch()
            if await ctx.awaitSearch(after: gen), ctx.model.searchHits.count > 200, ctx.foldsActive {
                let hits = ctx.model.searchHits.count
                let hiddenHits = ctx.model.searchHits.filter { ctx.hidden($0.range.location) }.count
                let t0 = CFAbsoluteTimeGetCurrent()
                await ctx.withRelaxedStalls { ctx.model.selectAllMatches(); await ctx.settle(0) }
                let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
                await ctx.settle(500)
                let ranges = ctx.tv.multi?.ranges ?? []
                let stillHidden = ranges.filter { ctx.hidden($0.location) }.count
                ctx.note(String(format: "select all matches: %d matches (%d inside folds) → %d carets in %.0f ms, %d still on hidden lines", hits, hiddenHits, ranges.count, ms, stillHidden))
                ctx.expect(ranges.count == hits && stillHidden == 0, "fold", "select all matches in a folded document: \(ranges.count) carets for \(hits) matches, \(stillHidden) on hidden lines")
                // 실측: 접지 않은 같은 문서에서 모든 일치 선택이 드는 시간의 두 배 안쪽 (아래에서 잰다)
                await ctx.key(.escape); await ctx.settle(200)
                ctx.model.send(.unfoldAll); await ctx.settle(400)
                let t1 = CFAbsoluteTimeGetCurrent()
                await ctx.withRelaxedStalls { ctx.model.selectAllMatches(); await ctx.settle(0) }
                let plainMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000
                ctx.note(String(format: "the same selection with nothing folded: %.0f ms", plainMs))
                // 실측: 84 ms (접지 않은 같은 선택 86~256 ms). 캐럿마다 따로 펴던 때는 4,993 ms 였고 캐럿도 864개 가운데 192개만 남았다
                if ms > max(300, plainMs * 2) { ctx.issue("stall", String(format: "select all matches in a fully folded document took %.0f ms (%.0f ms with nothing folded)", ms, plainMs), snap: false) }
                ctx.checkAll("after select all matches in a folded document"); ctx.checkFoldState("after select all matches in a folded document")
                await ctx.key(.escape); await ctx.settle(200)
            } else { ctx.issue("other", "the notes corpus has \(ctx.model.searchHits.count) matches for 'budget' (folds active \(ctx.foldsActive)) — the step did not run") }
            ctx.model.searchQuery = ""; ctx.model.runSearch(); await ctx.settle(200)
            ctx.model.send(.unfoldAll); await ctx.settle(300)
        },

        // 접힌 뒤의 다시 스캔·되돌리기·한글 조합: 선택이 든 줄이 접혀 사라지지 않는가, 되돌린 자리(캐럿)가 화면에 남는가, 조합 중인 글자가 유지되는가
        Scenario(name: "fold-rescan") { ctx in
            await ctx.open(text: RealUse.foldDoc(h1: false, sections: 60), name: "fold-rescan.md")
            await ctx.settle(700)
            let h5 = RealUse.foldHeader(5), h7 = RealUse.foldHeader(7), h9 = RealUse.foldHeader(9)
            @MainActor func foldSection(_ header: Int) async {
                ctx.model.jump(toLine: header); await ctx.settle(250)
                if !ctx.hidden(line: header + 1) { ctx.model.send(.fold); await ctx.settle(200) }
            }
            // 구역 아래의 빈 줄에 글을 쓰면 그 줄은 구역에 든다(다음 제목 전까지) — 다시 스캔이 접힘을 그 줄까지 넓히려 한다
            ctx.at("a selection on a line the rescan would fold away")
            await foldSection(h5)
            if await ctx.clickExpect(ctx.lineStart(h5 + 7), "click the blank line below the folded section") {
                await ctx.type("abc def")
                await ctx.key(.left, [.shift], count: 3)
                let sel = ctx.tv.selectedRange()
                ctx.expect(sel.length == 3 && ctx.text.substring(with: sel) == "def", "selection", "⇧←×3 after typing selected \(sel)")
                await ctx.settle(900)   // 줄 인덱스 250 ms + 영역 스캔 + 보정
                let now = ctx.tv.selectedRange()
                ctx.note("after the rescan: selection \(now) at \(ctx.place(now.location)), hidden \(ctx.hidden(now.location)), section folded \(ctx.hidden(line: h5 + 1)), pills \(ctx.foldCount())")
                ctx.expect(now == sel && !ctx.hidden(now.location) && !ctx.hidden(NSMaxRange(now)), "fold", "the rescan folded the line that holds the selection \(now) (\(ctx.place(now.location))) — the next key changes text that is not on screen")
                ctx.checkCaretVisible("selection on a line the rescan would fold"); ctx.checkAllD("selection on a line the rescan would fold"); ctx.checkFoldState("selection on a line the rescan would fold")
                await ctx.type("Z"); await ctx.settle(300)
                ctx.expect(ctx.caretLineText() == "abc Z" && !ctx.hidden(ctx.caret), "fold", "typing over the selection: line \"\(ctx.caretLineText())\", caret hidden \(ctx.hidden(ctx.caret))")
                ctx.checkCaretVisible("typed over the selection"); ctx.snap("selection-kept")
            }
            // 캐럿만 있을 때(기존 동작): 쓰고 있는 줄은 접히지 않는다
            ctx.at("a caret on a line the rescan would fold away")
            await foldSection(h7)
            if await ctx.clickExpect(ctx.lineStart(h7 + 7), "click the blank line below the folded section") {
                await ctx.type("typing here")
                await ctx.settle(900)
                ctx.expect(!ctx.hidden(ctx.caret) && ctx.caretLineText() == "typing here", "fold", "the rescan folded the line being typed on (caret \(ctx.place(ctx.caret)))")
                ctx.checkCaretVisible("caret on a line the rescan would fold"); ctx.checkAllD("caret on a line the rescan would fold"); ctx.checkFoldState("caret on a line the rescan would fold")
            }
            // 한글 조합 중에 다시 스캔이 접힘을 고친다(속성 편집 통지) — 조합이 유지되는가
            ctx.at("composing Hangul while the rescan corrects a fold")
            await foldSection(h9)
            if await ctx.clickExpect(ctx.lineStart(h9 + 7), "click the blank line below the folded section") {
                let at = ctx.caret
                await ctx.composeOnly("한")
                ctx.expectMarked(NSRange(location: at, length: 1), "composing below a folded section")
                await ctx.settle(900)
                ctx.note("composing during the rescan: marked \(ctx.tv.markedRange()), section folded \(ctx.hidden(line: h9 + 1)), pills \(ctx.foldCount())")
                ctx.expectMarked(NSRange(location: at, length: 1), "after the rescan corrected the fold during composition")
                await ctx.commitComposition("한"); await ctx.settle(200)
                ctx.expect(ctx.caretLineText() == "한" && !ctx.hidden(ctx.caret), "text", "after committing the syllable the line is \"\(ctx.caretLineText())\" (caret hidden \(ctx.hidden(ctx.caret)))")
                ctx.checkCaretVisible("committed below a folded section"); ctx.checkAllD("committed below a folded section"); ctx.checkFoldState("committed below a folded section")
            }
            ctx.at("composing Hangul at the end of a folded header")
            let h11 = RealUse.foldHeader(11)
            await foldSection(h11)
            if await ctx.clickExpect(ctx.lineEnd(h11), "click the end of the folded header") {
                let at = ctx.caret
                await ctx.composeOnly("글")
                await ctx.settle(900)
                ctx.expectMarked(NSRange(location: at, length: 1), "composing at the end of a folded header, after the rescan")
                ctx.expect(ctx.hidden(line: h11 + 1) && ctx.foldCount() >= 1, "fold", "composing at the end of a folded header opened the fold")
                await ctx.commitComposition("글"); await ctx.settle(500)
                ctx.expect(ctx.caretLineText().hasSuffix("제목글") && ctx.hidden(line: h11 + 1), "fold", "after committing on a folded header: line \"\(ctx.caretLineText())\", folded \(ctx.hidden(line: h11 + 1))")
                ctx.checkCaretVisible("committed on a folded header"); ctx.checkAllD("committed on a folded header"); ctx.checkFoldState("committed on a folded header")
            }
            ctx.model.send(.unfoldAll); await ctx.settle(300)

            // 되돌리기: 접힘의 위·아래에서 편집하고 휠로 멀리 간 뒤 ⌘Z — 화면이 되돌린 자리로 가고(HyperTextView.undoDidChange), 한 턴 뒤의 접힘 다시 배치
            // (FoldStore.textWillChange 의 사후 통지 경로)가 그것을 밀어내지 않는가. 접지 않은 문서에서 같은 조작을 한 결과와 견준다
            let h3 = RealUse.foldHeader(3), h20 = RealUse.foldHeader(20), h21 = RealUse.foldHeader(21), h30 = RealUse.foldHeader(30), h40 = RealUse.foldHeader(40)
            @MainActor func undoRedo(_ why: String, editLine: Int, away: CGFloat) async -> [String] {
                await ctx.look(atLine: editLine)
                guard await ctx.clickExpect(ctx.lineEnd(editLine), "\(why): click the end of line \(editLine)") else { return [] }
                await ctx.pumpEvent(); ctx.tv.breakUndoCoalescing()
                let lines0 = LineIndex(nsString: ctx.text).lineCount
                await ctx.type(" edited"); await ctx.key(.returnKey); await ctx.type("new line"); await ctx.pumpEvent(); await ctx.settle(500)
                var outcome: [String] = []
                for (name, cmd) in [("undo", EditorCommand.undo), ("redo", EditorCommand.redo), ("undo again", EditorCommand.undo)] {
                    await ctx.wheelTo(steps: 10, by: away); await ctx.settle(200)   // 캐럿은 편집한 자리에 남고 화면만 멀어진다
                    if ctx.caretLineScreenY() != nil { ctx.note("\(why): the caret line is still on screen after wheeling away") }
                    ctx.model.send(cmd); await ctx.turn(); await ctx.turn()
                    let y0 = ctx.caretLineScreenY()
                    await ctx.pumpEvent(); await ctx.settle(450)
                    let y1 = ctx.caretLineScreenY()
                    ctx.note("\(why): \(name) → caret \(ctx.place(ctx.caret)), its line at y \(y0.map { String(format: "%.1f", $0) } ?? "off screen") right after, \(y1.map { String(format: "%.1f", $0) } ?? "off screen") once settled; pills \(ctx.foldCount())")
                    outcome.append("\(name): caret on line \(ctx.liveLine(ctx.caret) - editLine) from the edited line, \(y1 == nil ? "off screen" : "on screen")")
                    ctx.checkCaretVisible("\(why): \(name)")
                    if let y0, let y1, abs(y1 - y0) > 2 { ctx.issue("viewport-jump", "\(why): after \(name) the caret line was at y \(String(format: "%.1f", y0)), then moved to \(String(format: "%.1f", y1)) when the folds were laid out again") }
                    ctx.checkAllD("\(why): \(name)"); ctx.checkFoldState("\(why): \(name)")
                }
                ctx.expect(LineIndex(nsString: ctx.text).lineCount == lines0, "text", "\(why): undo, redo, undo left \(LineIndex(nsString: ctx.text).lineCount) lines, expected \(lines0)")
                return outcome
            }
            ctx.at("undo and redo without folds (the reference)")
            let plainAbove = await undoRedo("no folds, edit near the top", editLine: h3 + 2, away: 120)
            let plainBelow = await undoRedo("no folds, edit in the middle", editLine: h30 + 2, away: -120)
            ctx.at("undo and redo an edit above the folds")
            await foldSection(h20); await foldSection(h21); await foldSection(h40)
            ctx.expect(ctx.foldCount() == 3, "fold", "expected sections 20, 21 and 40 folded, pills \(ctx.foldCount())")
            let foldedAbove = await undoRedo("edit above the folds", editLine: h3 + 2, away: 120)
            ctx.expect(foldedAbove == plainAbove, "fold", "undo/redo of an edit above the folds: \(foldedAbove), without folds \(plainAbove)")
            ctx.expect(ctx.foldCount() == 3 && ctx.hidden(line: h20 + 1) && ctx.hidden(line: h40 + 1), "fold", "after undo/redo above the folds: pills \(ctx.foldCount()), hidden(\(h20 + 1))=\(ctx.hidden(line: h20 + 1))")
            ctx.at("undo and redo an edit between the folds")
            let foldedBelow = await undoRedo("edit between the folds", editLine: h30 + 2, away: -120)
            ctx.expect(foldedBelow == plainBelow, "fold", "undo/redo of an edit between the folds: \(foldedBelow), without folds \(plainBelow)")
            ctx.expect(ctx.foldCount() == 3 && ctx.hidden(line: h20 + 1) && ctx.hidden(line: h40 + 1), "fold", "after undo/redo between the folds: pills \(ctx.foldCount()), hidden(\(h20 + 1))=\(ctx.hidden(line: h20 + 1))")
            ctx.snap("end")
            ctx.model.send(.unfoldAll); await ctx.settle(300)
        },

        // 숨은 문단을 건너뛰는 열거(FoldingContentStorage)의 계약: 접힌 문서의 열거 = 편 문서의 열거에서 숨은 문단을 뺀 것 — 어느 자리에서 시작하든, 어느 방향이든.
        // 숨은 위치의 배치 질의가 무엇을 돌려주는지도 적는다 (거터·표식·캐럿 사각형이 기대는 값)
        Scenario(name: "fold-enum") { ctx in
            await ctx.open(text: RealUse.guardDoc, name: "fold-enum.py")
            await ctx.settle(700)
            await ctx.key(.up, [.command]); await ctx.settle(200)
            guard let cs = ctx.tv.textContentStorage, let lm = ctx.tv.textLayoutManager else { return }
            let start = cs.documentRange.location
            let length = ctx.length
            @MainActor func loc(_ o: Int) -> NSTextLocation { cs.location(start, offsetBy: o) ?? start }
            @MainActor func off(_ l: NSTextLocation) -> Int { cs.offset(from: start, to: l) }
            /// 한 자리에서 한 방향으로 끝까지 열거한 문단 시작 오프셋들과 반환값
            @MainActor func elements(from o: Int?, reverse: Bool) -> (starts: [Int], end: Int?) {
                var out: [Int] = []
                let reached = cs.enumerateTextElements(from: o.map(loc), options: reverse ? [.reverse] : []) { e in
                    if let r = e.elementRange { out.append(off(r.location)) }
                    return out.count < 200
                }
                return (out, reached.map(off))
            }
            @MainActor func fragments(from o: Int?, reverse: Bool) -> [Int] {
                var out: [Int] = []
                lm.enumerateTextLayoutFragments(from: o.map(loc), options: reverse ? [.reverse, .ensuresLayout] : [.ensuresLayout]) { f in
                    out.append(off(f.rangeInElement.location)); return out.count < 200
                }
                return out
            }
            let probes: [Int?] = [nil] + (1...13).map { Optional(ctx.lineStart($0)) } + [Optional(ctx.lineStart(9) + 6), Optional(ctx.lineStart(4) + 3), Optional(ctx.lineStart(7) + 4), Optional(length)]
            // 기준: 편 문서
            var reference: [String: (starts: [Int], end: Int?)] = [:]
            var referenceFragments: [String: [Int]] = [:]
            for p in probes { for rev in [false, true] {
                let key = "\(p.map(String.init) ?? "nil")/\(rev ? "reverse" : "forward")"
                reference[key] = elements(from: p, reverse: rev)
                referenceFragments[key] = fragments(from: p, reverse: rev)
            } }
            ctx.note("open document: forward from the start \(reference["nil/forward"]!.starts.count) elements, returns \(reference["nil/forward"]!.end.map(String.init) ?? "nil"); reverse from the end \(reference["nil/reverse"]!.starts.count), returns \(reference["nil/reverse"]!.end.map(String.init) ?? "nil"); reverse from the start of line 10 begins with line \(reference["\(ctx.lineStart(10))/reverse"]!.starts.first.map { ctx.liveLine($0) } ?? -1), from the middle of line 9 with line \(reference["\(ctx.lineStart(9) + 6)/reverse"]!.starts.first.map { ctx.liveLine($0) } ?? -1)")

            for (name, headers) in [("one fold in the middle", [7]), ("three folds, one reaching the end", [2, 7, 11]), ("nested folds", [2, 1, 11])] {
                ctx.at("enumeration with \(name)")
                ctx.model.send(.unfoldAll); await ctx.settle(150)
                for h in headers { ctx.model.send(.toggleFold(line: h)); await ctx.settle(120) }
                await ctx.settle(200)
                // 열거에 남는 문단: 숨지 않은 것 + 끝까지 닿는 접힘의 마지막 문단(높이 0 으로 남긴다)
                let tailStart = ctx.lineStart(13)
                let tailKept = ctx.hidden(length)
                @MainActor func kept(_ o: Int) -> Bool { !ctx.hidden(o) || (tailKept && o == tailStart) }
                var bad = 0
                for p in probes { for rev in [false, true] {
                    let key = "\(p.map(String.init) ?? "nil")/\(rev ? "reverse" : "forward")"
                    let want = reference[key]!.starts.filter(kept)
                    let got = elements(from: p, reverse: rev)
                    if got.starts != want {
                        bad += 1
                        if bad <= 3 { ctx.issue("fold", "\(name): enumerating text elements \(rev ? "backward" : "forward") from \(p.map { ctx.place($0) } ?? "the default end") gives lines \(got.starts.map { ctx.liveLine($0) }), expected \(want.map { ctx.liveLine($0) })") }
                    }
                    if got.end != reference[key]!.end, !(got.starts.isEmpty && want.isEmpty) {
                        // 반환값(열거가 멈춘 자리)이 편 문서와 다르면 적는다 — 마지막으로 넘긴 요소가 같다면 같아야 한다
                        let sameLast = got.starts.last == reference[key]!.starts.last
                        if sameLast { ctx.issue("fold", "\(name): enumerating \(rev ? "backward" : "forward") from \(p.map { ctx.place($0) } ?? "the default end") returns \(got.end.map(String.init) ?? "nil"), the open document returns \(reference[key]!.end.map(String.init) ?? "nil") for the same last element") }
                    }
                    let wantFragments = referenceFragments[key]!.filter(kept)
                    let gotFragments = fragments(from: p, reverse: rev)
                    if gotFragments != wantFragments {
                        bad += 1
                        if bad <= 3 { ctx.issue("fold", "\(name): enumerating layout fragments \(rev ? "backward" : "forward") from \(p.map { ctx.place($0) } ?? "the default end") gives lines \(gotFragments.map { ctx.liveLine($0) }), expected \(wantFragments.map { ctx.liveLine($0) })") }
                    }
                } }
                ctx.note("\(name): \(probes.count * 2) start points checked in both APIs, \(bad) mismatches; reverse from the end returns \(elements(from: nil, reverse: true).end.map(String.init) ?? "nil"), forward from the start returns \(elements(from: nil, reverse: false).end.map(String.init) ?? "nil")")
                // 열거 블록 안에서 시작한 다른 열거도 같은 숨김을 본다
                var nestedHidden: [Int] = []
                var first = true
                _ = cs.enumerateTextElements(from: start, options: []) { _ in
                    guard first else { return false }
                    first = false
                    for e in cs.textElements(for: cs.documentRange) { if let r = e.elementRange, !kept(off(r.location)) { nestedHidden.append(ctx.liveLine(off(r.location))) } }
                    return false
                }
                if !nestedHidden.isEmpty { ctx.issue("fold", "\(name): an enumeration started inside another enumeration's block sees the hidden lines \(nestedHidden)") }
                // 숨은 위치의 배치 질의
                if let h = (1...13).first(where: { ctx.hidden(line: $0) && !(tailKept && $0 == 13) }) {
                    let o = ctx.lineStart(h) + 2
                    lm.ensureLayout(for: NSTextRange(location: loc(o)))
                    let frag = lm.textLayoutFragment(for: loc(o))
                    var segments = 0
                    lm.enumerateTextSegments(in: NSTextRange(location: loc(o)), type: .standard, options: [.rangeNotRequired]) { _, _, _, _ in segments += 1; return true }
                    let rect = ctx.tv.caretRect(at: o)
                    ctx.note("\(name): hidden \(ctx.place(o)) → layout fragment \(frag.map { "line \(ctx.liveLine(off($0.rangeInElement.location))) height \($0.layoutFragmentFrame.height)" } ?? "none"), \(segments) segment(s), caretRect \(rect.map { "y \(Int($0.minY)) h \($0.height)" } ?? "nil")")
                    ctx.expect(frag == nil && segments == 0 && rect == nil, "fold", "\(name): a layout query at the hidden \(ctx.place(o)) returns something (fragment \(frag != nil), segments \(segments), caretRect \(rect != nil)) — callers would place things on a line that is not shown")
                }
                if tailKept {
                    let o = tailStart + 2
                    lm.ensureLayout(for: NSTextRange(location: loc(o)))
                    let frag = lm.textLayoutFragment(for: loc(o))
                    ctx.note("\(name): the kept last paragraph → \(frag.map { "\(type(of: $0)) height \($0.layoutFragmentFrame.height)" } ?? "no fragment"), document usage height \(lm.usageBoundsForTextContainer.height)")
                    ctx.expect(frag is FoldedLayoutFragment && (frag?.layoutFragmentFrame.height ?? 1) == 0, "fold", "\(name): the last paragraph of a fold that reaches the end should be a zero-height FoldedLayoutFragment, got \(frag.map { "\(type(of: $0)) height \($0.layoutFragmentFrame.height)" } ?? "none")")
                }
                ctx.checkAllD("enumeration with \(name)"); ctx.checkFoldState("enumeration with \(name)")
            }
            ctx.model.send(.unfoldAll); await ctx.settle(200)
        },
    ]
}
