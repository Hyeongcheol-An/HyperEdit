import SwiftUI
import AppKit
import HyperCore

// 분할 보기 + Quick Append + 문서 무결성 QA 셀프테스트 (적대적 시나리오). runDocumentTracking 뒤에 돈다.
// 샘플 문서 위에서 돌고 끝에 본문을 원상복구한다. 임시 파일(인코딩·읽기 전용·빈 문서)은 샘플 옆 임시 폴더에 만들고 지운다.
// 각 단계는 중첩 함수라 그 단계에서 잡은 코디네이터·텍스트 뷰 참조가 단계 끝에 풀린다 — 누수 검사(N)가 테스트 자신의 참조를 세지 않도록.
extension SelfTest {
    /// 상주 메모리(MB) — 분할 여닫기 누수 검사용
    static func residentMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
        }
        return kr == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
    }

    @MainActor
    static func runQASplit(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { pumpEvent(); try? await Task.sleep(nanoseconds: ms * 1_000_000) }   // 이벤트를 흘려 undo 그룹을 닫는다
        func text() -> String { model.document.textStorage.string }
        func disk(_ url: URL? = nil) -> String { (try? String(contentsOf: url ?? model.document.url, encoding: .utf8)) ?? "" }
        func count(_ needle: String) -> Int { text().components(separatedBy: needle).count - 1 }
        func bm() -> [Int] { model.bookmarks.bookmarks.map(\.line) }
        func mark(_ s: String) { Perf.log("[qa split] " + s) }
        func appendViaActive(_ s: String) {
            model.send(.perform { tv in
                tv.breakUndoCoalescing()
                let end = (tv.string as NSString).length
                tv.setSelectedRange(NSRange(location: end, length: 0))
                tv.insertText(s, replacementRange: tv.selectedRange())
            })
        }
        let session = model.session
        let doc = model.document
        let sampleURL = doc.url
        let dir = sampleURL.deletingLastPathComponent()
        let before = text()
        let fm = FileManager.default
        let headingRegex = Timestamp.headingRegex
        func isHeading(_ s: String) -> Bool { headingRegex.firstMatch(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length)) != nil }
        /// 본문을 통째로 바꾼 뒤 저장하고 undo 스택을 비운다 (검사 사이 원상복구)
        func restore(_ s: String) async {
            model.setSplit(.none); await wait(400)
            model.send(.perform { tv in
                let len = (tv.string as NSString).length
                tv.insertText(s, replacementRange: NSRange(location: 0, length: len))
            })
            await wait(200)
            doc.saveSynchronously()
            session.clearUndo()
            await wait(300)
        }

        // 0. 앞 단계가 남긴 상태 정리: 보관된 보조 편집기(redo 스택 때문에 남아 있을 수 있음)·북마크
        session.clearUndo(); await wait(300)
        for b in model.bookmarks.bookmarks { model.bookmarks.remove(id: b.id) }
        let baseLive = session.liveCoordinatorCount()
        log("qa-split start · live coordinators=\(baseLive) text views=\(session.liveTextViewCount()) retired=\(session.retiredCount)")
        check(session.splitMode == .none && baseLive == 1 && session.liveTextViewCount() == 1 && session.retiredCount == 0 && bm().isEmpty,
              "qa starts with one live editor, nothing retired, no bookmarks (live=\(baseLive) retired=\(session.retiredCount) bm=\(bm()))")

        // A. 보조에서 입력 → 분할 닫기 → 주에서 입력 → undo 두 번 → 둘 다 사라짐 (닫힌 뷰의 undo 항목이 보관된 뷰를 통해 되돌려진다)
        func sectionA() async {
            mark("A begin")
            model.setSplit(.vertical); await wait(700)
            guard let primaryTV = session.primary?.textView, let sec = session.secondary else { check(false, "A: split did not create two editors"); return }
            session.activate(sec)
            check(session.active === sec, "A: activate(secondary) makes it the active editor")
            appendViaActive("\nQA-SEC"); await wait(300)
            check(text().hasSuffix("QA-SEC") && primaryTV.string.hasSuffix("QA-SEC"), "A: typed in secondary, visible in primary")
            model.setSplit(.none); await wait(700)
            check(session.coordinators.count == 1 && session.active === session.primary, "A: split closed → active falls back to primary")
            check(session.retiredCount == 1 && session.liveCoordinatorCount() == baseLive + 1, "A: closed editor is retained while its undo item is on the stack (retired=\(session.retiredCount), live=\(session.liveCoordinatorCount()))")
            appendViaActive("\nQA-PRI"); await wait(300)
            check(text().hasSuffix("QA-SEC\nQA-PRI"), "A: typed in primary after closing the split")
            model.send(.undo); await wait(300)
            check(text().hasSuffix("QA-SEC") && !text().contains("QA-PRI"), "A: first undo removes the primary edit")
            model.send(.undo); await wait(300)
            check(text() == before, "A: second undo removes the edit made in the closed split")
            model.send(.redo); await wait(300)
            check(text().hasSuffix("QA-SEC"), "A: redo re-applies the closed split's edit")
            model.send(.undo); await wait(300)
            check(text() == before, "A: back to the original text (dirty=\(doc.isDirty))")
        }
        await sectionA()

        // B. 분할 켠 채 다른 파일 열기 → 두 뷰 모두 새 파일, undo 스택 비움, 보관 편집기 해제, 북마크 저장소 전환, 이전 파일의 편집은 저장됨.
        //    Quick Append 뒤 파일 전환 → undo 가 다른 파일로 넘어가지 않는다.
        func sectionB() async {
            mark("B begin")
            model.setSplit(.vertical); await wait(700)
            guard let secB = session.secondary else { check(false, "B: no secondary"); return }
            session.activate(secB)
            appendViaActive("\nQA-X"); await wait(300)
            check(session.undoManager.canUndo, "B: undo stack non-empty before switching files")
            model.jump(toLine: 2); await wait(300)
            model.toggleBookmarkAtCaret()
            check(bm() == [2], "B: bookmark on line 2 of sample (\(bm()))")
            let otherURL = dir.appendingPathComponent("other.md")
            model.open(url: otherURL); await wait(900)
            let otherText = text()
            check(otherText.hasPrefix("# Other"), "B: other.md loaded")
            check(session.coordinators.count == 2 && session.coordinators.allSatisfy { $0.textView?.string == otherText }, "B: both views show the new file")
            check(session.coordinators.allSatisfy { $0.textView?.isEditable == true }, "B: both views editable")
            check(!session.undoManager.canUndo && !session.undoManager.canRedo, "B: undo stack empty after the file switch")
            check(session.retiredCount == 0, "B: file switch releases retired editors (retired=\(session.retiredCount))")
            check(model.bookmarks.fileURL.standardizedFileURL.resolvingSymlinksInPath() == otherURL.standardizedFileURL.resolvingSymlinksInPath() && bm().isEmpty,
                  "B: bookmark store switched to other.md (\(model.bookmarks.fileURL.lastPathComponent), \(bm()))")
            check(disk(sampleURL).hasSuffix("QA-X") && !doc.isDirty, "B: dirty edit of the previous file was saved on switch")
            model.send(.undo); await wait(300)
            check(text() == otherText, "B: undo in the new file is a no-op (no cross-file undo)")
            // Quick Append → 즉시 파일 전환 → 되돌아와도 노트는 디스크에 있고, 새 파일에서 undo 는 아무것도 안 한다
            check(model.quickAppend("QA-CROSS", withTimestamp: false), "B: quick append into other.md")
            model.open(url: sampleURL); await wait(900)
            model.send(.undo); await wait(300)
            check(text().hasSuffix("QA-X") && !text().contains("QA-CROSS"), "B: undo after switching does not pull the quick append into sample")
            check(disk(otherURL).hasSuffix("QA-CROSS\n"), "B: quick append persisted in other.md across the switch")
            try? "# Other\nHyperEdit mention in another file\n".write(to: otherURL, atomically: true, encoding: .utf8)
            check(bm() == [2], "B: back to sample — bookmark \(bm()) restored from its store")
            model.bookmarks.toggle(line: 2, preview: "")
            check(bm().isEmpty, "B: bookmark removed")
        }
        await sectionB()
        await restore(before)
        check(text() == before && disk() == before, "B: sample restored")

        // C. 분할 + 마크다운 미리보기 → 미리보기 줄(firstVisibleLine)은 활성 뷰의 스크롤을 따라간다
        func sectionC() async {
            mark("C begin")
            model.setSplit(.vertical); await wait(700)
            guard let pC = session.primary, let sC = session.secondary, let pTV = pC.textView, let sTV = sC.textView, let pSV = pC.scrollView else {
                check(false, "C: split views missing"); return
            }
            session.activate(pC)
            appendViaActive(String(repeating: "\nfiller line for scroll sync", count: 200)); await wait(400)
            model.showMarkdownPreview = true; await wait(600)
            model.jump(toLine: 1); await wait(400)
            check(model.caret.firstVisibleLine == 1, "C: primary at top → firstVisibleLine \(model.caret.firstVisibleLine)")
            session.activate(sC)
            model.jump(toLine: 150); await wait(600)
            let fvSec = model.caret.firstVisibleLine
            check(fvSec > 60 && sTV.selectedRange().location == doc.lineIndex.range(ofLine: 150).location, "C: goToLine in the active secondary → firstVisibleLine \(fvSec)")
            check(pTV.visibleRect.minY < 5 && pTV.selectedRange().location == 0, "C: inactive primary did not scroll or move its caret (y=\(Int(pTV.visibleRect.minY)))")
            pSV.contentView.scroll(to: NSPoint(x: 0, y: max(0, pTV.bounds.height - pSV.contentView.bounds.height)))
            pSV.reflectScrolledClipView(pSV.contentView); await wait(400)
            check(model.caret.firstVisibleLine == fvSec, "C: scrolling the inactive primary does not move the preview line (\(model.caret.firstVisibleLine))")
            session.activate(pC)
            pSV.contentView.scroll(to: NSPoint(x: 0, y: max(0, pTV.bounds.height - pSV.contentView.bounds.height) - 10))
            pSV.reflectScrolledClipView(pSV.contentView); await wait(400)
            check(model.caret.firstVisibleLine > fvSec, "C: after activating the primary its scroll drives the preview (\(model.caret.firstVisibleLine) > \(fvSec))")
            model.showMarkdownPreview = false; await wait(300)
            model.send(.undo); await wait(400)
            check(text() == before && doc.isDirty, "C: filler undone (undo after save → dirty)")
            model.saveNow(); await wait(600)
            check(!doc.isDirty, "C: saved after the undo")
        }
        await sectionC()

        // D. 분할 중 테마 전환 → 두 뷰 모두 배경·입력 속성이 새 테마
        func sectionD() async {
            mark("D begin")
            let themes = model.themes
            let origTheme = themes.current
            let followed = themes.followsSystem
            guard let alt = themes.themes.first(where: { $0.background != origTheme.background && $0.isDark != origTheme.isDark }) ?? themes.themes.first(where: { $0.id != origTheme.id }) else {
                log("D: no alternative theme — skipped"); return
            }
            let dirtyBefore = doc.isDirty
            mark("D theme switch begin")
            themes.select(id: alt.id); await wait(600)
            mark("D theme switch end")
            let both = session.coordinators.compactMap(\.textView)
            check(both.count == 2 && both.allSatisfy { $0.backgroundColor == alt.background.nsColor }, "D: both views recolored to \(alt.id) background")
            check(both.allSatisfy { ($0.typingAttributes[.foregroundColor] as? NSColor) == alt.foreground.nsColor }, "D: both views' typing color follows the theme")
            check((doc.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) == alt.foreground.nsColor, "D: shared storage foreground is the new theme color")
            check(session.coordinators.allSatisfy { $0.scrollView?.backgroundColor == alt.background.nsColor }, "D: both scroll views recolored")
            check(doc.isDirty == dirtyBefore && !dirtyBefore, "D: theme change (attribute-only edit) does not dirty the document (before=\(dirtyBefore) after=\(doc.isDirty))")
            if followed { themes.setFollowsSystem(true) } else { themes.select(id: origTheme.id) }
            await wait(500)
            check(both.allSatisfy { $0.backgroundColor == themes.current.background.nsColor }, "D: theme restored on both views (\(themes.current.id))")
        }
        await sectionD()

        // E. 자동 줄바꿈·줄 번호·구문 색·열 모드는 두 뷰 모두에
        func sectionE() async {
            mark("E begin")
            let cs = session.coordinators
            model.wordWrap = false; await wait(300)
            check(cs.allSatisfy { $0.textView?.textContainer?.widthTracksTextView == false && $0.scrollView?.hasHorizontalScroller == true }, "E: word wrap off on both")
            model.wordWrap = true; await wait(300)
            check(cs.allSatisfy { $0.textView?.textContainer?.widthTracksTextView == true && $0.scrollView?.hasHorizontalScroller == false }, "E: word wrap on on both")
            model.showLineNumbers = false; await wait(300)
            check(cs.allSatisfy { $0.gutter?.isHidden == true }, "E: line numbers hidden on both")
            model.showLineNumbers = true; await wait(300)
            check(cs.allSatisfy { $0.gutter?.isHidden == false }, "E: line numbers shown on both")
            model.syntaxHighlighting = false; await wait(300)
            check(cs.allSatisfy { !$0.highlightEnabled }, "E: syntax colors off on both")
            model.syntaxHighlighting = true; await wait(300)
            check(cs.allSatisfy { $0.highlightEnabled }, "E: syntax colors on on both")
            model.columnMode = true; await wait(200)
            check(cs.allSatisfy { $0.textView?.columnModeEnabled == true }, "E: column mode on both")
            model.columnMode = false; await wait(200)
            check(cs.allSatisfy { $0.textView?.columnModeEnabled == false }, "E: column mode off on both")
        }
        await sectionE()

        // F. goToLine 은 활성 뷰만 움직인다, 상태바 줄 번호는 활성 뷰 기준
        func sectionF() async {
            mark("F begin")
            guard let pF = session.primary, let sF = session.secondary, let pFTV = pF.textView, let sFTV = sF.textView else { check(false, "F: views missing"); return }
            session.activate(pF); model.jump(toLine: 1); await wait(300)
            session.activate(sF)
            let pSel = pFTV.selectedRange()
            model.jump(toLine: 9); await wait(400)
            let line9 = doc.lineIndex.range(ofLine: 9).location
            check(sFTV.selectedRange().location == line9 && pFTV.selectedRange() == pSel, "F: goToLine moved only the active secondary (sec=\(sFTV.selectedRange().location) pri=\(pFTV.selectedRange().location))")
            check(model.caretLine == 9, "F: status bar line follows the active editor (\(model.caretLine))")
            session.activate(pF); await wait(200)
            model.send(.perform { tv in tv.setSelectedRange(tv.selectedRange()) }); await wait(200)
            check(model.caretLine == 1, "F: activating the primary → status bar shows its line (\(model.caretLine))")
        }
        await sectionF()

        // G. 분할 중 Quick Append → 한 번만 삽입, 두 뷰 모두 보임, 바로 저장, undo 한 번 → dirty
        func sectionG() async {
            mark("G begin")
            let views = session.coordinators.compactMap(\.textView)
            let okG = model.quickAppend("QA-SPLIT-NOTE", withTimestamp: false); await wait(300)
            check(okG && count("QA-SPLIT-NOTE") == 1, "G: quick append while split inserted once (\(count("QA-SPLIT-NOTE")))")
            check(views.count == 2 && views.allSatisfy { $0.string.hasSuffix("QA-SPLIT-NOTE\n") }, "G: both views show the appended note")
            await wait(600)
            check(!doc.isDirty && disk().hasSuffix("QA-SPLIT-NOTE\n"), "G: saved to disk")
            model.send(.undo); await wait(300)
            check(text() == before, "G: one undo removes it")
            check(doc.isDirty, "G: undo after the quick append's save marks the document dirty")
            model.saveNow(); await wait(600)
            check(!doc.isDirty && disk() == before, "G: saved back")
        }
        await sectionG()

        // H. 보조에서 undo-after-save → dirty; saveSynchronously 가 true 를 돌려주고 디스크 == 메모리
        func sectionH() async {
            mark("H begin")
            guard let pF = session.primary, let sF = session.secondary else { check(false, "H: views missing"); return }
            session.activate(pF)
            appendViaActive("\nQA-UNDO-SEC"); await wait(200)
            model.saveNow(); await wait(600)
            check(!doc.isDirty && disk().hasSuffix("QA-UNDO-SEC"), "H: typed in primary + saved")
            session.activate(sF)
            model.send(.undo); await wait(300)
            check(!text().contains("QA-UNDO-SEC") && doc.isDirty, "H: undo from the secondary after save → dirty (\(doc.isDirty))")
            let okSync = doc.saveSynchronously()
            check(okSync && !doc.isDirty && disk() == text() && disk() == before, "H: saveSynchronously after undo → true, disk == memory")
            check(doc.saveSynchronously() == false, "H: saveSynchronously with nothing to save → false")
        }
        await sectionH()

        // I. 수정 중 외부 변경 → 경고 + 스냅샷, 재로드 안 함; 저장 뒤 경고가 되살아나지 않음; 깨끗할 때 외부 변경 → 재로드 + undo 비움 (두 뷰 모두)
        func sectionI() async {
            mark("I begin")
            doc.autosaveDelay = 60
            func externalSnapshots() -> Int {
                ((try? fm.contentsOfDirectory(atPath: MemoDocument.snapshotDirectory.path)) ?? [])
                    .filter { $0.hasPrefix(sampleURL.lastPathComponent + "-") && $0.hasSuffix("-external.txt") }.count
            }
            let snapsBefore = externalSnapshots()
            if let p = session.primary { session.activate(p) }
            appendViaActive("\nQA-DIRTY"); await wait(200)
            check(doc.isDirty && doc.externalChange == nil, "I: dirty, no external change yet")
            await wait(1700)   // 우리 저장(ourLastWrite) 1.5 s 창을 벗어난다
            try? (before + "\nEXTERNAL-LINE\n").write(to: sampleURL, atomically: true, encoding: .utf8)
            await wait(1200)
            check(doc.externalChange != nil, "I: external change detected while dirty")
            check(doc.isDirty && text().hasSuffix("QA-DIRTY") && !text().contains("EXTERNAL-LINE"), "I: dirty buffer kept (not reloaded)")
            check(doc.status.contains("External change") || doc.status.contains("외부 변경"), "I: warning status '\(doc.status)'")
            check(externalSnapshots() == snapsBefore + 1, "I: external copy snapshotted (\(externalSnapshots() - snapsBefore))")
            model.saveNow(); await wait(700)
            check(!doc.isDirty && disk().hasSuffix("QA-DIRTY") && !disk().contains("EXTERNAL-LINE"), "I: save overwrites the external change")
            appendViaActive("\nQA-DIRTY2"); await wait(200)
            check(doc.isDirty && doc.externalChange == nil, "I: external-change flag cleared by our save — warning does not reappear on the next edit (flag=\(doc.externalChange != nil))")
            model.saveNow(); await wait(700)
            doc.autosaveDelay = 2
            await wait(1700)
            try? (before + "\nEXTERNAL-2\n").write(to: sampleURL, atomically: true, encoding: .utf8)
            await wait(1200)
            check(text() == before + "\nEXTERNAL-2\n" && !doc.isDirty, "I: clean buffer reloads the external change")
            check(session.coordinators.count == 2 && session.coordinators.allSatisfy { $0.textView?.string == text() }, "I: both split views show the reloaded text")
            check(!session.undoManager.canUndo && session.retiredCount == 0, "I: reload clears the undo stack and releases retired editors")
        }
        await sectionI()
        await restore(before)

        // J. 빈 문서·개행 3개로 끝나는 문서에 Quick Append (타임스탬프 끔/켬) · DOS 문서는 기록만
        func sectionJ() async {
            mark("J begin")
            let emptyURL = dir.appendingPathComponent("qa-empty.md")
            try? "".write(to: emptyURL, atomically: true, encoding: .utf8)
            model.open(url: emptyURL); await wait(800)
            check(doc.isLoaded && text().isEmpty, "J: empty document opened")
            check(model.quickAppend("first", withTimestamp: false), "J: quick append on empty doc")
            await wait(600)
            check(text() == "first\n" && disk() == "first\n", "J: empty doc → 'first\\n' (no leading separator) · disk ok")
            model.send(.perform { tv in tv.insertText("\n\n", replacementRange: NSRange(location: (tv.string as NSString).length, length: 0)) }); await wait(200)
            check(text() == "first\n\n\n", "J: document now ends with three newlines")
            _ = model.quickAppend("second", withTimestamp: false); await wait(300)
            check(text() == "first\n\n\nsecond\n", "J: no timestamp → appended on the next line without extra blank lines")
            _ = model.quickAppend("third", withTimestamp: true); await wait(300)
            let jl = text().components(separatedBy: "\n")
            check(jl.count >= 5 && jl[jl.count - 2] == "third" && isHeading(jl[jl.count - 3]) && jl[jl.count - 4].isEmpty && jl[jl.count - 5] == "second",
                  "J: timestamp → exactly one blank line + heading + note (tail \(jl.suffix(4)))")
            let empty2 = dir.appendingPathComponent("qa-empty2.md")
            try? "".write(to: empty2, atomically: true, encoding: .utf8)
            model.open(url: empty2); await wait(800)
            _ = model.quickAppend("x", withTimestamp: true); await wait(300)
            let j2 = text().components(separatedBy: "\n")
            check(j2.count == 3 && isHeading(j2[0]) && j2[1] == "x" && j2[2].isEmpty, "J: empty doc + timestamp → heading first, no leading blank (\(j2))")
            let dosURL = dir.appendingPathComponent("qa-dos.txt")
            try? "a\r\nb\r\n".write(to: dosURL, atomically: true, encoding: .utf8)
            model.open(url: dosURL); await wait(800)
            _ = model.quickAppend("c", withTimestamp: false); await wait(600)
            log("J: DOS document after quick append → \(disk().debugDescription) (lineEnding=\(doc.lineEnding))")
            for u in [emptyURL, empty2, dosURL] { try? fm.removeItem(at: u) }
        }
        await sectionJ()

        // K. Quick Append 10번 연속 → 디스크에 10개 모두 순서대로, 메모리와 일치
        func sectionK() async {
            mark("K begin")
            model.open(url: sampleURL); await wait(800)
            let savesBefore = doc.lastSaved
            for i in 1...10 { _ = model.quickAppend("rapid-\(i)", withTimestamp: false) }
            check(count("rapid-") == 10, "K: 10 rapid appends in memory (\(count("rapid-")))")
            await wait(1500)
            let dK = disk()
            var lastIdx = -1, ordered = true
            for i in 1...10 {
                guard let r = dK.range(of: "rapid-\(i)\n") else { ordered = false; break }
                let off = dK.distance(from: dK.startIndex, to: r.lowerBound)
                if off <= lastIdx { ordered = false }; lastIdx = off
            }
            check(ordered && dK == text() && !doc.isDirty, "K: all 10 on disk in order, disk == memory, clean (ordered=\(ordered), saved=\(doc.lastSaved != savesBefore))")
        }
        await sectionK()
        await restore(before)

        // L. 열지 못한 문서(읽기 권한 없음) → 두 뷰 편집 불가, Quick Append 거부 + 오류 로그; 쓰기 불가 폴더 → 저장 실패가 보고되고 dirty 유지
        func sectionL() async {
            mark("L begin")
            let noReadURL = dir.appendingPathComponent("qa-noread.md")
            try? "secret\n".write(to: noReadURL, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: noReadURL.path)
            model.setSplit(.vertical); await wait(600)
            model.open(url: noReadURL); await wait(900)
            check(!doc.isLoaded && text().isEmpty, "L: unreadable file → not loaded, buffer emptied (loaded=\(doc.isLoaded))")
            check(session.coordinators.count == 2 && session.coordinators.allSatisfy { $0.textView?.isEditable == false }, "L: both views read-only when the document is not loaded")
            let outBefore = model.output.count
            let refused = model.quickAppend("lost?", withTimestamp: false) == false
            let newErrors = model.output.dropFirst(outBefore).filter(\.isError).map(\.text)
            check(refused && text().isEmpty, "L: quick append refused when no document is loaded")
            check(newErrors.contains { $0.contains("Quick Append") || $0.contains("빠른 추가") }, "L: refusal logged as an error (\(newErrors))")
            check((try? Data(contentsOf: noReadURL)) == nil, "L: unreadable file untouched on disk")
            try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: noReadURL.path)
            let roDir = dir.appendingPathComponent("qa-ro", isDirectory: true)
            try? fm.createDirectory(at: roDir, withIntermediateDirectories: true)
            let roURL = roDir.appendingPathComponent("ro.md")
            try? "readonly folder\n".write(to: roURL, atomically: true, encoding: .utf8)
            try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: roDir.path)
            model.open(url: roURL); await wait(900)
            check(doc.isLoaded && text() == "readonly folder\n", "L: file in a read-only folder opens")
            let okRO = model.quickAppend("note in ro", withTimestamp: false); await wait(900)
            check(okRO && text().hasSuffix("note in ro\n"), "L: quick append into the buffer succeeds")
            check(doc.isDirty && !(doc.errorMessage ?? "").isEmpty, "L: save failure reported and document stays dirty (error='\(doc.errorMessage ?? "nil")')")
            check(disk(roURL) == "readonly folder\n", "L: disk unchanged after the failed save")
            check(doc.saveSynchronously() == false && doc.isDirty, "L: saveSynchronously also fails → still dirty (quit path would drop the note — see report)")
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: roDir.path)
            model.saveNow(); await wait(800)
            check(!doc.isDirty && disk(roURL).hasSuffix("note in ro\n"), "L: save succeeds once the folder is writable again")
            try? fm.removeItem(at: noReadURL); try? fm.removeItem(at: roURL); try? fm.removeItem(at: roDir)
        }
        await sectionL()

        // M. 인코딩 보존: EUC-KR 파일 + 한글 Quick Append → EUC-KR 그대로, UTF-8 BOM 파일 → BOM 유지
        func sectionM() async {
            mark("M begin")
            let krURL = dir.appendingPathComponent("qa-euckr.txt")
            let krText = "한글 메모\n"
            if let d = krText.data(using: MemoDocument.cp949) { try? d.write(to: krURL) }
            model.open(url: krURL); await wait(900)
            check(doc.isLoaded && doc.encodingName == "EUC-KR" && text() == krText, "M: EUC-KR detected (\(doc.encodingName))")
            _ = model.quickAppend("추가 메모", withTimestamp: false); await wait(900)
            let krRaw = (try? Data(contentsOf: krURL)) ?? Data()
            check(String(data: krRaw, encoding: MemoDocument.cp949) == krText + "추가 메모\n" && String(data: krRaw, encoding: .utf8) == nil && doc.encodingName == "EUC-KR",
                  "M: saved back as EUC-KR bytes (\(krRaw.count) bytes, enc=\(doc.encodingName))")
            let bomURL = dir.appendingPathComponent("qa-bom.md")
            try? (Data([0xEF, 0xBB, 0xBF]) + Data("bom text\n".utf8)).write(to: bomURL)
            model.open(url: bomURL); await wait(900)
            check(doc.hasBOM && doc.encodingName == "UTF-8 BOM" && text() == "bom text\n", "M: BOM detected (\(doc.encodingName))")
            _ = model.quickAppend("more ✓", withTimestamp: false); await wait(900)
            let bomRaw = (try? Data(contentsOf: bomURL)) ?? Data()
            check(bomRaw.prefix(3) == Data([0xEF, 0xBB, 0xBF]) && String(data: bomRaw.dropFirst(3), encoding: .utf8) == "bom text\nmore ✓\n" && doc.hasBOM,
                  "M: BOM preserved on save")
            try? fm.removeItem(at: krURL); try? fm.removeItem(at: bomURL)
        }
        await sectionM()

        // N. 분할 20회 여닫기 — 매번 보조에서 편집하고, 닫은 뒤 그 편집을 undo/redo 한다(보관된 뷰 경유) → 살아 있는 코디네이터·텍스트 뷰가
        //    보관 정책(최대 3) 안에 머물고, clearUndo 뒤 주 편집기만 남으며, RSS 증가 < 20 MB. 분할을 4번째 닫을 때 undo 스택이 비워지는 설계도 기록한다.
        func sectionN() async {
            mark("N begin")
            model.open(url: sampleURL); await wait(800)
            model.setSplit(.none); await wait(400)
            session.clearUndo(); await wait(300)
            let rssBefore = residentMB()
            let liveBefore = session.liveCoordinatorCount()
            var maxLive = 0, maxRetired = 0, undoWipes = 0
            for i in 1...20 {
                let hadUndo = session.undoManager.canUndo
                model.setSplit(i % 2 == 0 ? .horizontal : .vertical); await wait(250)
                if let s = session.secondary { session.activate(s) }
                appendViaActive("\nQA-TOGGLE-\(i)"); await wait(120)
                model.setSplit(.none); await wait(250)
                if hadUndo && !session.undoManager.canUndo { undoWipes += 1 }
                model.send(.undo); await wait(120)
                model.send(.redo); await wait(120)
                maxLive = max(maxLive, session.liveCoordinatorCount()); maxRetired = max(maxRetired, session.retiredCount)
            }
            await wait(500)
            let rssAfter = residentMB()
            log(String(format: "N: toggled split 20× · live coordinators before=%d after=%d max=%d · retired max=%d now=%d · undo stack wiped by retire policy %d× · RSS %.1f → %.1f MB (Δ %.1f)",
                       liveBefore, session.liveCoordinatorCount(), maxLive, maxRetired, session.retiredCount, undoWipes, rssBefore, rssAfter, rssAfter - rssBefore))
            check(session.coordinators.count == 1 && maxLive <= liveBefore + EditorSession.maxRetired + 1, "N: live coordinators bounded by the retained-undo policy (max \(maxLive), base \(liveBefore), cap \(EditorSession.maxRetired))")
            check(session.liveTextViewCount() == session.liveCoordinatorCount(), "N: no orphan text views (\(session.liveTextViewCount()) vs \(session.liveCoordinatorCount()))")
            check(rssAfter - rssBefore < 20, String(format: "N: RSS growth %.1f MB < 20 MB", rssAfter - rssBefore))
            check(count("QA-TOGGLE-") == 20, "N: all 20 toggle edits present after undo/redo through retired views (\(count("QA-TOGGLE-")))")
            session.clearUndo(); await wait(400)
            check(session.liveCoordinatorCount() == liveBefore && session.liveTextViewCount() == liveBefore && session.retiredCount == 0,
                  "N: after clearUndo only the primary remains (live=\(session.liveCoordinatorCount()))")
        }
        await sectionN()
        await restore(before)
        check(text() == before && disk() == before && session.splitMode == .none, "N: sample restored, split off")

        // O. 전역 단축키: 설정 변경 → Carbon 등록은 항상 하나 이하, 끄면 0, 같은 값 재설정은 중복 등록 없음, 되돌리면 다시 하나
        func sectionO() async {
            mark("O begin")
            let qa = model.quickAppend
            let origID = qa.hotkeyID
            check(GlobalHotKey.registeredCount == (qa.isHotKeyRegistered ? 1 : 0), "O: Carbon registrations match the controller state (\(GlobalHotKey.registeredCount), '\(qa.hotkeyStatus)')")
            qa.hotkeyID = "off"; await wait(100)
            check(!qa.isHotKeyRegistered && GlobalHotKey.registeredCount == 0 && (qa.hotkeyStatus.contains("off") || qa.hotkeyStatus.contains("끔")), "O: Off → unregistered, no Carbon handler left ('\(qa.hotkeyStatus)')")
            qa.hotkeyID = "ctrl-opt-space"; await wait(100)
            log("O: ⌃⌥Space → registered=\(qa.isHotKeyRegistered) failed=\(qa.hotkeyFailed) status='\(qa.hotkeyStatus)'")
            check(GlobalHotKey.registeredCount <= 1 && (qa.isHotKeyRegistered != qa.hotkeyFailed), "O: ⌃⌥Space attempt leaves at most one registration and a consistent status")
            qa.hotkeyID = "ctrl-opt-cmd-n"; await wait(100)
            qa.hotkeyID = "ctrl-opt-cmd-n"; await wait(100)
            check(GlobalHotKey.registeredCount == (qa.isHotKeyRegistered ? 1 : 0) && GlobalHotKey.registeredCount <= 1, "O: re-selecting the same shortcut does not double-register (\(GlobalHotKey.registeredCount))")
            qa.hotkeyID = origID; await wait(100)
            check(qa.hotkeyID == origID && GlobalHotKey.registeredCount == (qa.isHotKeyRegistered ? 1 : 0), "O: restored '\(origID)' → '\(qa.hotkeyStatus)'")
            // 패널 토글: 열려 있고 키 창이면 닫힌다 (앱이 비활성이면 isKeyWindow 가 false 라 다시 show 가 불린다 — 기록만)
            qa.show(); await wait(300)
            let visibleBefore = qa.isVisible, keyBefore = qa.isKeyWindow
            qa.toggle(); await wait(300)
            log("O: toggle while shown → visible \(visibleBefore)→\(qa.isVisible), key was \(keyBefore), app active=\(NSApp.isActive)")
            if keyBefore { check(!qa.isVisible, "O: toggle hides a key panel") }
            qa.hide(); qa.draft = ""
        }
        await sectionO()

        mark("done")
        log("qa-split done · live coordinators=\(session.liveCoordinatorCount()) retired=\(session.retiredCount)")
    }
}
