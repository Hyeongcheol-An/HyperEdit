import SwiftUI
import AppKit
import HyperCore

// 접기·스크롤바 마커·undo 사후 추적 QA (runFold 뒤에 돈다). 샘플 끝에 `qa-header:` 블록(자식 12줄 + 뒤 1줄)을 붙여 아래를 검사하고 원상복구한다.
//  - 머리 줄 입력/붙여넣기, 머리 줄 삭제 뒤 프래그먼트 높이, 숨은 텍스트를 건드리는 모두 바꾸기, 검색(F3)·북마크(F2)로 접힘 안 진입,
//    미리보기 firstVisibleLine, 자동 줄바꿈 토글 뒤 표식 사각형, 분할 보기(뷰별 접힘·보조에서 숨은 텍스트 편집·북마크 1회 이동·dirty),
//    모두 접기 멱등성, EOF 까지 닿는 접힘에서 ↓, 스크롤바 마커(3000+ 매치·가장자리 북마크·짧은 문서·테마·보조 편집기).
//  - `--selftest-markers-big <path>`: 그 파일(사본!)을 열어 5000 매치 상태의 타이핑 지연과 마커 그리기 시간을 잰다.
extension SelfTest {
    @MainActor
    static func runQAFold(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { pumpEvent(); try? await Task.sleep(nanoseconds: ms * 1_000_000) }   // 이벤트를 흘려 undo 그룹을 닫는다
        func text() -> NSString { model.document.textStorage.string as NSString }
        func lines() -> Int { LineIndex(nsString: text()).lineCount }
        func lineStart(_ line: Int) -> Int {
            let idx = LineIndex(nsString: text())
            return idx.lineStarts[max(0, min(line - 1, idx.lineCount - 1))]
        }
        func lineText(_ line: Int) -> String {
            let ns = text(); let r = LineIndex(nsString: ns).range(ofLine: line)
            return ns.substring(with: NSIntersectionRange(r, NSRange(location: 0, length: ns.length)))
        }
        let session = model.session
        func activeTV() -> HyperTextView? { session.active?.textView }
        func hidden(_ line: Int, in tv: HyperTextView? = nil) -> Bool {
            (tv ?? activeTV())?.isOffsetHidden?(lineStart(line)) ?? false
        }
        func pillCount(in tv: HyperTextView? = nil) -> Int {
            guard let tv = tv ?? activeTV() else { return -1 }
            return tv.foldPills?(NSRange(location: 0, length: (tv.string as NSString).length)).count ?? 0
        }
        /// 접힘 상태 일관성: 첫 자식이 숨겨져 있으면 표식이 정확히 하나, 아니면 없다
        func consistent(_ firstChild: Int, in tv: HyperTextView? = nil) -> Bool { pillCount(in: tv) == (hidden(firstChild, in: tv) ? 1 : 0) }
        /// 모든 레이아웃 프래그먼트의 높이가 양수인가 (접힘 해제 뒤 높이 0 고아 프래그먼트가 남지 않아야 한다)
        func allFragmentsPositive(_ tv: HyperTextView?) -> (ok: Bool, zero: Int, total: Int) {
            guard let tv, let lm = tv.textLayoutManager else { return (false, -1, -1) }
            lm.ensureLayout(for: lm.documentRange)
            var zero = 0, total = 0
            lm.enumerateTextLayoutFragments(from: lm.documentRange.location, options: [.ensuresLayout]) { f in
                total += 1
                if f.layoutFragmentFrame.height <= 0 { zero += 1 }
                return true
            }
            return (zero == 0 && total > 0, zero, total)
        }
        func caretLineNow(_ tv: HyperTextView? = nil) -> Int {
            guard let tv = tv ?? activeTV() else { return -1 }
            return LineIndex(nsString: tv.string as NSString).lineNumber(forUTF16Offset: tv.selectedRange().location)
        }
        func container(_ c: EditorView.Coordinator?) -> EditorContainerView? { c?.textView?.enclosingScrollView?.superview as? EditorContainerView }
        /// 마커 띠를 비트맵으로 그려 (x, y) 의 알파를 돌려준다 (0 = 투명)
        func markerAlpha(_ view: NSView, points: [(CGFloat, CGFloat)]) -> [CGFloat] {
            guard view.bounds.width > 0, view.bounds.height > 0, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return points.map { _ in -1 } }
            view.cacheDisplay(in: view.bounds, to: rep)
            let sx = CGFloat(rep.pixelsWide) / view.bounds.width, sy = CGFloat(rep.pixelsHigh) / view.bounds.height
            return points.map { p in
                let px = Int(p.0 * sx), py = Int(p.1 * sy)
                guard px >= 0, py >= 0, px < rep.pixelsWide, py < rep.pixelsHigh else { return -1 }
                return rep.colorAt(x: px, y: py)?.alphaComponent ?? -1
            }
        }
        func markerColor(_ view: NSView, at p: (CGFloat, CGFloat)) -> NSColor? {
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: rep)
            let sx = CGFloat(rep.pixelsWide) / view.bounds.width, sy = CGFloat(rep.pixelsHigh) / view.bounds.height
            return rep.colorAt(x: Int(p.0 * sx), y: Int(p.1 * sy))
        }

        // 0. 준비: 모두 펼치고 블록을 붙인다. 그 전에 (문서가 한 화면에 들어가는 지금) 마커 띠가 투명한지 본다
        model.setSplit(.none); await wait(300)
        session.activeEditorID = session.primary?.id
        model.send(.unfoldAll)
        for b in model.bookmarks.bookmarks { model.bookmarks.remove(id: b.id) }
        guard let pc = session.primary, let marker = container(pc)?.markerView as? ScrollMarkerView, let sv = pc.scrollView else {
            check(false, "qa-markers: primary marker view missing"); return
        }
        model.showScrollMarkers = true
        // 짧은 문서: 셀프테스트 폴더의 other.md (2줄) 를 열어 본다 — 샘플은 앞 단계들이 덧붙여 이미 한 화면을 넘는다
        let sampleURL = model.document.url
        model.open(url: sampleURL.deletingLastPathComponent().appendingPathComponent("other.md")); await wait(900)
        check(lines() == 3 && sv.documentView!.frame.height <= sv.contentView.bounds.height + 1,
              "qa-markers: other.md fits on one screen (\(lines()) lines, doc \(Int(sv.documentView!.frame.height)) ≤ view \(Int(sv.contentView.bounds.height)))")
        _ = model.bookmarks.toggle(line: 1, preview: "top")
        model.jump(toLine: 1); await wait(200)
        let h0 = marker.bounds.height
        let shortAlpha = markerAlpha(marker, points: [(1, 2), (1, h0 / 2), (6, h0 / 2), (1, h0 - 2)])
        check(shortAlpha.allSatisfy { $0 == 0 }, "qa-markers: strip is fully transparent when the document fits (alpha \(shortAlpha))")
        for b in model.bookmarks.bookmarks { model.bookmarks.remove(id: b.id) }
        model.open(url: sampleURL); await wait(900)
        check(model.document.url.lastPathComponent == "sample.md", "qa-markers: back on sample.md")
        session.activeEditorID = session.primary?.id
        let insertAt = text().length
        var block = "\nqa-header:"
        for i in 1...12 { block += "\n    qa child \(i)" }
        block += "\nqa-after"
        model.send(.perform { tv in tv.breakUndoCoalescing(); tv.insertText(block, replacementRange: NSRange(location: insertAt, length: 0)) })
        await wait(900)
        let H = lines() - 13
        log("qa-fold: block appended, header line \(H), \(lines()) lines")
        check(lineText(H) == "qa-header:" && lineText(H + 12) == "    qa child 12" && lineText(H + 13) == "qa-after", "qa-fold: block layout (\(lineText(H)))")

        // 1. 머리 줄 끝·첫머리 입력 → 접힘 유지 (스캔 뒤에도)
        model.jump(toLine: H); await wait(200); model.send(.fold); await wait(200)
        check(hidden(H + 1) && hidden(H + 12) && !hidden(H + 13) && pillCount() == 1, "qa-fold: folded \(H + 1)–\(H + 12)")
        model.send(.perform { tv in
            let r = LineIndex(nsString: tv.string as NSString).range(ofLine: H)
            tv.setSelectedRange(NSRange(location: NSMaxRange(r), length: 0)); tv.insertText(" tail-typed", replacementRange: tv.selectedRange())
        }); await wait(900)
        check(hidden(H + 1) && consistent(H + 1) && lineText(H) == "qa-header: tail-typed", "qa-fold: typing at the end of the header keeps the fold after rescan")
        model.send(.perform { tv in
            tv.setSelectedRange(NSRange(location: lineStart(H), length: 0)); tv.insertText("pre-", replacementRange: tv.selectedRange())
        }); await wait(900)
        check(hidden(H + 1) && consistent(H + 1) && lineText(H) == "pre-qa-header: tail-typed", "qa-fold: typing at the start of the header keeps the fold")
        model.send(.undo); await wait(300); model.send(.undo); await wait(900)
        check(lineText(H) == "qa-header:" && hidden(H + 1) && consistent(H + 1), "qa-fold: two undos restore the header, fold kept (\(lineText(H)))")

        // 2. 머리 줄에 여러 줄 붙여넣기 — 크래시 없이 상태가 일관돼야 한다 (동작은 기록)
        model.send(.perform { tv in
            tv.breakUndoCoalescing()
            tv.setSelectedRange(NSRange(location: lineStart(H), length: 0)); tv.insertText("p1\np2\n", replacementRange: tv.selectedRange())
        }); await wait(900)
        let afterPasteStart = (hidden: hidden(H + 3), pills: pillCount(), header: lineText(H + 2))
        log("qa-fold: paste 2 lines at header start → header now line \(H + 2) '\(afterPasteStart.header)', hidden=\(afterPasteStart.hidden), pills=\(afterPasteStart.pills)")
        check(afterPasteStart.header == "qa-header:" && afterPasteStart.hidden && afterPasteStart.pills == 1, "qa-fold: multi-line paste before the header shifts the fold (still folded)")
        model.send(.undo); await wait(900)
        check(lineText(H) == "qa-header:" && lines() == H + 13 && consistent(H + 1), "qa-fold: undo of the paste restores (hidden=\(hidden(H + 1)))")
        if !hidden(H + 1) { model.jump(toLine: H); await wait(200); model.send(.fold); await wait(200) }
        model.send(.perform { tv in
            tv.breakUndoCoalescing()
            let r = LineIndex(nsString: tv.string as NSString).range(ofLine: H)
            tv.setSelectedRange(NSRange(location: NSMaxRange(r), length: 0)); tv.insertText(" x\ny", replacementRange: tv.selectedRange())
        }); await wait(900)
        // 머리 줄 끝에 "x\ny" 를 붙이면 새 줄 y 가 자식들의 머리가 된다 — 접힘이 y 에 붙어 유지되거나 펼쳐지거나, 어느 쪽이든 표식과 숨김이 일치해야 한다
        let afterPasteEnd = (hidden: hidden(H + 2), pills: pillCount(), l1: lineText(H), l2: lineText(H + 1))
        log("qa-fold: paste ' x\\ny' at header end → '\(afterPasteEnd.l1)' / '\(afterPasteEnd.l2)', children hidden=\(afterPasteEnd.hidden), pills=\(afterPasteEnd.pills)")
        check(afterPasteEnd.l1 == "qa-header: x" && afterPasteEnd.l2 == "y" && afterPasteEnd.pills == (afterPasteEnd.hidden ? 1 : 0), "qa-fold: multi-line paste at header end leaves a consistent state")
        model.send(.undo); await wait(900)
        check(lineText(H) == "qa-header:" && lines() == H + 13, "qa-fold: undo restores the header after the end paste")

        // 3. 머리 줄 삭제(⇧⌘K) → 펼쳐짐, 모두 펼친 뒤 높이 0 프래그먼트 없음
        model.send(.unfoldAll); await wait(100)
        model.jump(toLine: H); await wait(200); model.send(.fold); await wait(200)
        check(hidden(H + 1), "qa-fold: refolded before deleting the header")
        model.textTool(.deleteLine); await wait(400)
        check(pillCount() == 0 && !hidden(H) && lineText(H) == "    qa child 1", "qa-fold: ⇧⌘K on the header unfolds (line \(H) = '\(lineText(H))')")
        model.send(.unfoldAll); await wait(300)
        let frag1 = allFragmentsPositive(activeTV())
        check(frag1.ok, "qa-fold: no zero-height fragments after header delete + unfold all (\(frag1.zero)/\(frag1.total))")
        model.send(.undo); await wait(900)
        check(lineText(H) == "qa-header:" && lines() == H + 13 && pillCount() == 0, "qa-fold: undo restores the header line")

        // 4. 모두 바꾸기: 숨은 텍스트를 건드리면 펼쳐진다, 건드리지 않으면 유지
        model.jump(toLine: H); await wait(200); model.send(.fold); await wait(200)
        model.searchQuery = "qa-after"; model.replaceText = "qa-after-2"; model.replaceAll(); await wait(700)
        check(lineText(H + 13) == "qa-after-2" && hidden(H + 1) && pillCount() == 1, "qa-fold: replace all outside the fold keeps it")
        model.searchQuery = "qa child 5"; model.replaceText = "qa child FIVE"; model.replaceAll(); await wait(700)
        check(lineText(H + 5) == "    qa child FIVE" && !hidden(H + 1) && pillCount() == 0, "qa-fold: replace all touching hidden text unfolds (hidden=\(hidden(H + 1)))")
        let frag2 = allFragmentsPositive(activeTV())
        check(frag2.ok, "qa-fold: no zero-height fragments after replace-all unfold (\(frag2.zero)/\(frag2.total))")
        model.send(.undo); await wait(300); model.send(.undo); await wait(700)
        check(lineText(H + 5) == "    qa child 5" && lineText(H + 13) == "qa-after" && pillCount() == 0, "qa-fold: undo ×2 restores both replacements")
        model.searchQuery = ""; model.replaceText = ""; model.runSearch(); await wait(200)

        // 5. 검색 매치가 접힌 안에 있을 때 F3 → 펼치고 선택
        model.jump(toLine: H); await wait(200); model.send(.fold); await wait(200)
        check(hidden(H + 7), "qa-fold: folded before F3")
        model.searchQuery = "qa child 7"; model.runSearch(); await wait(600)
        check(model.searchHits.count == 1, "qa-fold: one hit for 'qa child 7' (\(model.searchHits.count))")
        model.jump(toLine: H); await wait(200)
        model.findNext(); await wait(500)
        var selNow = NSRange(location: 0, length: 0)
        model.send(.perform { tv in selNow = tv.selectedRange() })
        check(!hidden(H + 7) && caretLineNow() == H + 7 && selNow.length == "qa child 7".utf16.count,
              "qa-fold: F3 into a folded region unfolds it and selects the match (hidden=\(hidden(H + 7)) line=\(caretLineNow()) sel=\(selNow))")
        model.send(.unfoldAll); model.searchQuery = ""; model.runSearch(); await wait(200)

        // 6. 북마크가 접힌 안에 있을 때 F2 → 펼치고 이동
        model.jump(toLine: H + 4); await wait(200); model.toggleBookmarkAtCaret()
        check(model.bookmarks.bookmarks.map(\.line) == [H + 4], "qa-fold: bookmark at \(H + 4)")
        model.jump(toLine: H); await wait(200); model.send(.fold); await wait(200)
        check(hidden(H + 4), "qa-fold: folded over the bookmark")
        model.nextBookmark(); await wait(500)
        check(!hidden(H + 4) && caretLineNow() == H + 4, "qa-fold: F2 into a folded region unfolds (line \(caretLineNow()))")
        model.toggleBookmarkAtCaret()
        check(model.bookmarks.bookmarks.isEmpty, "qa-fold: bookmark removed")

        // 7. 자동 줄바꿈 끄기/켜기 → 표식 사각형이 다시 계산된다 (그리기마다 재계산)
        model.jump(toLine: H); await wait(200); model.send(.fold); await wait(200)
        func pillRectCheck(_ label: String) {
            guard let tv = activeTV() else { check(false, label); return }
            tv.display()
            let headerEnd = lineStart(H + 1) - 1
            let expectedX = (tv.caretRect(at: headerEnd)?.maxX ?? -100) + 8
            let rects = tv.foldPillRects
            check(rects.count == 1 && abs(rects[0].0.minX - expectedX) < 0.5 && rects[0].1 == lineStart(H + 1),
                  "\(label) (rects=\(rects.count) x=\(rects.first?.0.minX ?? -1) expected=\(expectedX))")
        }
        pillRectCheck("qa-fold: pill rect follows the header end (wrap on)")
        model.wordWrap = false; await wait(300)
        pillRectCheck("qa-fold: pill rect recomputed with word wrap off")
        model.wordWrap = true; await wait(300)
        pillRectCheck("qa-fold: pill rect recomputed with word wrap back on")
        check(hidden(H + 1) && consistent(H + 1), "qa-fold: fold survives word wrap toggles")

        // 8. 마크다운 미리보기 켜기 → firstVisibleLine 은 1…줄 수 안의 보이는 줄
        model.showMarkdownPreview = true; await wait(600)
        model.send(.perform { tv in tv.scrollRangeToVisible(NSRange(location: lineStart(H), length: 0)) }); await wait(300)
        let fvl = model.caret.firstVisibleLine
        check(fvl >= 1 && fvl <= lines() && !hidden(fvl), "qa-fold: firstVisibleLine \(fvl) is a visible line with preview on")
        model.showMarkdownPreview = false; await wait(300)

        // 9. 모두 접기 두 번 (멱등) → 모두 펼치기
        model.send(.foldAll); await wait(300)
        let pills1 = pillCount(), hidden1 = (1...lines()).filter { hidden($0) }
        model.send(.foldAll); await wait(300)
        let pills2 = pillCount(), hidden2 = (1...lines()).filter { hidden($0) }
        check(pills1 == pills2 && hidden1 == hidden2 && !hidden1.isEmpty, "qa-fold: fold all twice is idempotent (\(hidden1.count) hidden lines, \(pills1) pill)")
        check(!hidden(caretLineNow()), "qa-fold: caret on a visible line after fold all (\(caretLineNow()))")

        // 10. EOF 까지 닿는 접힘(최상위 헤딩)에서 ↓: 캐럿이 숨은 자리에 남아서는 안 된다
        model.send(.perform { tv in tv.doCommand(by: #selector(NSResponder.moveDown(_:))) }); await wait(200)
        var caretHidden = false, caretOff = -1
        model.send(.perform { tv in caretOff = tv.selectedRange().location; caretHidden = tv.isOffsetHidden?(caretOff) ?? false })
        log("qa-fold: ↓ from the top header of an EOF fold → caret offset \(caretOff) (length \(text().length)), hidden=\(caretHidden), pills=\(pillCount())")
        check(!caretHidden && caretLineNow() == 1 && pillCount() == 1, "qa-fold: ↓ over a fold reaching EOF stays on the header, fold kept (offset \(caretOff), line \(caretLineNow()), hidden=\(caretHidden))")
        // 문서 끝으로 이동(⌘↓·goToEnd) → 끝 오프셋을 숨기는 접힘이 펼쳐져 캐럿이 보인다
        model.goToEnd(); await wait(300)
        model.send(.perform { tv in caretOff = tv.selectedRange().location; caretHidden = tv.isOffsetHidden?(caretOff) ?? false })
        check(!caretHidden && caretOff == text().length && !hidden(2) && caretLineNow() == lines(),
              "qa-fold: go-to-end into an EOF fold unfolds it (offset \(caretOff), hidden=\(caretHidden), line \(caretLineNow())/\(lines()))")
        model.send(.unfoldAll); await wait(300)
        let frag3 = allFragmentsPositive(activeTV())
        check(frag3.ok && pillCount() == 0, "qa-fold: unfold all → no zero-height fragments (\(frag3.zero)/\(frag3.total))")

        // 11. 분할 보기: 접힘은 뷰별, 보조에서 숨은 텍스트 편집 → 주 편집기가 펼침, 텍스트 손상 없음
        model.setSplit(.vertical); await wait(800)
        guard let pTV = session.primary?.textView, let sTV = session.secondary?.textView, pTV !== sTV else {
            check(false, "qa-fold: split did not produce two editors"); return
        }
        session.activeEditorID = session.primary?.id
        model.jump(toLine: H); await wait(200); model.send(.fold); await wait(300)
        check(hidden(H + 1, in: pTV) && !hidden(H + 1, in: sTV) && pillCount(in: pTV) == 1 && pillCount(in: sTV) == 0,
              "qa-split-fold: folding in the primary does not fold the secondary (per-view folds)")
        check(container(session.secondary)?.gutter.foldMarker?(lineStart(H), { lineStart(H + 1) }) == .foldable, "qa-split-fold: secondary gutter shows the region as foldable")
        session.activeEditorID = session.secondary?.id
        sTV.breakUndoCoalescing()
        sTV.setSelectedRange(NSRange(location: lineStart(H + 3) + 4, length: 0))
        sTV.insertText("ZZ", replacementRange: sTV.selectedRange()); await wait(400)
        check(lineText(H + 3) == "    ZZqa child 3", "qa-split-fold: typing in the secondary edits the shared text (\(lineText(H + 3)))")
        check(!hidden(H + 1, in: pTV) && pillCount(in: pTV) == 0, "qa-split-fold: editing hidden text from the secondary unfolds the primary")
        let fragP = allFragmentsPositive(pTV)
        check(fragP.ok, "qa-split-fold: primary has no zero-height fragments after the remote unfold (\(fragP.zero)/\(fragP.total))")
        model.send(.undo); await wait(400)
        check(lineText(H + 3) == "    qa child 3", "qa-split-fold: undo from the secondary restores the text")

        // 12. 분할 + 북마크: 보조에서 2줄 삽입 → undo(주) → redo(보조) → 북마크 10 → 12 → 10 → 12, 정확히 한 번씩
        _ = model.bookmarks.toggle(line: 10, preview: "qa")
        check(model.bookmarks.bookmarks.map(\.line) == [10], "qa-split-bm: bookmark at 10")
        model.saveNow(); await wait(500)
        check(!model.document.isDirty, "qa-split-bm: saved (clean) before the split edits")
        session.activeEditorID = session.secondary?.id
        sTV.breakUndoCoalescing()
        sTV.setSelectedRange(NSRange(location: 0, length: 0))
        sTV.insertText("L1\nL2\n", replacementRange: NSRange(location: 0, length: 0)); await wait(400)
        check(model.bookmarks.bookmarks.map(\.line) == [12], "qa-split-bm: insert 2 lines above via the secondary → \(model.bookmarks.bookmarks.map(\.line))")
        check(model.document.isDirty, "qa-split-bm: dirty after the secondary edit")
        model.saveNow(); await wait(500)
        session.activeEditorID = session.primary?.id
        model.send(.undo); await wait(500)
        check(model.bookmarks.bookmarks.map(\.line) == [10] && !text().hasPrefix("L1"), "qa-split-bm: undo via the primary → \(model.bookmarks.bookmarks.map(\.line))")
        check(model.document.isDirty, "qa-split-bm: dirty after undo in split mode")
        session.activeEditorID = session.secondary?.id
        model.send(.redo); await wait(500)
        check(model.bookmarks.bookmarks.map(\.line) == [12] && text().hasPrefix("L1\nL2\n"), "qa-split-bm: redo via the secondary → \(model.bookmarks.bookmarks.map(\.line))")
        model.send(.undo); await wait(500)
        check(model.bookmarks.bookmarks.map(\.line) == [10] && !text().hasPrefix("L1"), "qa-split-bm: final undo → \(model.bookmarks.bookmarks.map(\.line))")

        // 13. 분할 + 보조에서 줄 수를 바꾸는 모두 바꾸기 → undo: 북마크는 정확히 한 번만 되돌아와야 한다
        //     (등록된 undo 클로저는 보조 뷰의 performReplacements → shouldChangeText 로 추적되는데, 주 편집기는 같은 저장소 알림을 '추적되지 않은' 편집으로 볼 수 있다)
        session.activeEditorID = session.secondary?.id
        model.searchQuery = "NEEDLE"; model.replaceText = "NEEDLE\nX"; model.replaceAll(); await wait(700)
        check(lines() == H + 13 + 2 && model.bookmarks.bookmarks.map(\.line) == [12], "qa-split-bm: replace all adding 2 lines above via the secondary → \(model.bookmarks.bookmarks.map(\.line))")
        model.send(.undo); await wait(600)
        check(lines() == H + 13 && model.bookmarks.bookmarks.map(\.line) == [10],
              "qa-split-bm: undo of the secondary's replace all moves the bookmark back exactly once → \(model.bookmarks.bookmarks.map(\.line))")
        model.searchQuery = ""; model.replaceText = ""; model.runSearch()
        for b in model.bookmarks.bookmarks { model.bookmarks.remove(id: b.id) }

        // 14. 보조 편집기에도 마커 띠가 있다
        check(container(session.secondary)?.markerView is ScrollMarkerView && container(session.primary)?.markerView is ScrollMarkerView,
              "qa-markers: both split editors have a ScrollMarkerView")
        model.setSplit(.none); await wait(700)
        session.activeEditorID = session.primary?.id

        // 15. 스크롤바 마커: 긴 문서에서 1줄·마지막 줄 북마크가 띠 안에, 3000+ 매치, 테마 전환, 끄기/켜기 저장
        model.showScrollMarkers = true
        _ = model.bookmarks.toggle(line: 1, preview: "top")
        // 긴 문서: 4000줄 'zq' 필러
        var filler = ""
        for i in 1...4000 { filler += "\nzq filler \(i)" }
        let fillerAt = text().length
        model.send(.perform { tv in tv.breakUndoCoalescing(); tv.insertText(filler, replacementRange: NSRange(location: fillerAt, length: 0)) }); await wait(900)
        let last = lines()
        _ = model.bookmarks.toggle(line: last, preview: "bottom")
        model.jump(toLine: 1); await wait(300)
        check(sv.documentView!.frame.height > sv.contentView.bounds.height + 1, "qa-markers: document taller than the view (\(last) lines)")
        let h = marker.bounds.height
        let a = markerAlpha(marker, points: [(1, 2), (1, h - 2), (1, h / 2), (6, h / 2)])
        check(a[0] > 0 && a[1] > 0, "qa-markers: bookmarks at line 1 and line \(last) are drawn inside the strip (alpha top \(a[0]) bottom \(a[1]))")
        check(a[2] == 0 && a[3] == 0, "qa-markers: middle of the strip is empty without matches (alpha \(a[2]), \(a[3]))")
        model.searchQuery = "zq"; model.runSearch(); await wait(800)
        check(model.searchHits.count >= 4000, "qa-markers: \(model.searchHits.count) matches (> 3000 cap)")
        let t0 = CFAbsoluteTimeGetCurrent()
        marker.display()
        let drawMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        log(String(format: "qa-markers: strip draw with %d matches %.2f ms", model.searchHits.count, drawMs))
        check(drawMs < 30, "qa-markers: strip draw with 4000+ matches under 30 ms (\(String(format: "%.1f", drawMs)))")
        let mid = markerAlpha(marker, points: [(6, h / 2)])
        check(mid[0] > 0, "qa-markers: match ticks drawn (alpha \(mid[0]))")
        let before = markerColor(marker, at: (1, 2))
        let currentTheme = model.themes.current.id
        let other = model.themes.themes.first { $0.id != currentTheme && $0.isDark != model.themes.current.isDark }?.id ?? ThemeStore.defaultLightID
        model.themes.select(id: other); await wait(600)
        let after = markerColor(marker, at: (1, 2))
        log("qa-markers: bookmark pixel \(before?.description ?? "nil") → \(after?.description ?? "nil") after switching to \(other)")
        check(after != nil && after!.alphaComponent > 0 && (before == nil || before! != after!), "qa-markers: theme switch recolors the strip")
        model.themes.select(id: currentTheme); await wait(400)
        model.showScrollMarkers = false
        check(AppDefaults.store.object(forKey: "ui.scrollMarkers") as? Bool == false, "qa-markers: off persisted")
        let offAlpha = markerAlpha(marker, points: [(1, 2), (6, h / 2)])
        check(offAlpha.allSatisfy { $0 == 0 }, "qa-markers: strip transparent when off (alpha \(offAlpha))")
        model.showScrollMarkers = true
        check(AppDefaults.store.object(forKey: "ui.scrollMarkers") as? Bool == true, "qa-markers: on persisted")
        for b in model.bookmarks.bookmarks { model.bookmarks.remove(id: b.id) }
        model.searchQuery = ""; model.runSearch(); await wait(200)

        // 16. 원상복구 (필러 + qa 블록)
        model.send(.unfoldAll); await wait(100)
        model.send(.perform { tv in
            let len = (tv.string as NSString).length
            tv.breakUndoCoalescing()
            tv.insertText("", replacementRange: NSRange(location: insertAt, length: len - insertAt))
        }); await wait(500)
        check(text().length == insertAt && pillCount() == 0 && model.bookmarks.bookmarks.isEmpty, "qa-fold: sample restored (length \(text().length))")

        // 17. (선택) 큰 파일 + 5000 매치: 타이핑 지연·마커 그리기
        if let big = LaunchOptions.value("--selftest-markers-big") {
            let sampleURL = model.document.url
            model.open(url: URL(fileURLWithPath: big)); await wait(1500)
            model.searchQuery = "error"; model.runSearch(); await wait(1500)
            log("qa-markers-big: \(model.document.lineIndex.lineCount) lines · \(model.searchHits.count) hits")
            model.goToEnd(); await wait(400)
            guard let pc2 = session.primary, let marker2 = container(pc2)?.markerView as? ScrollMarkerView else { return }
            let d0 = CFAbsoluteTimeGetCurrent(); marker2.display(); let bigDraw = (CFAbsoluteTimeGetCurrent() - d0) * 1000
            let t1 = CFAbsoluteTimeGetCurrent()
            for _ in 0..<80 {
                model.send(.perform { tv in tv.insertText("a", replacementRange: tv.selectedRange()) })
                await wait(1)
            }
            let ms = (CFAbsoluteTimeGetCurrent() - t1) * 1000 / 80 - 1
            log(String(format: "qa-markers-big: strip draw %.2f ms · typing %.2f ms/keystroke with %d hits (incl. run loop)", bigDraw, ms, model.searchHits.count))
            check(ms < 16, "qa-markers-big: typing latency under one frame with thousands of matches")
            model.send(.perform { tv in
                let ns = tv.string as NSString
                tv.insertText("", replacementRange: NSRange(location: ns.length - 80, length: 80))
            }); await wait(300)
            model.searchQuery = ""; model.runSearch()
            model.open(url: sampleURL); await wait(800)
        }
    }
}
