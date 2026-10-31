import SwiftUI
import AppKit
import HyperCore

extension SelfTest {
    /// 접기 + 스크롤바 마커: 임시 샘플 끝에 들여쓴 블록(머리 1 + 자식 15 + 뒤 1줄)을 붙여 영역 계산·접기·펼치기·캐럿 진입·줄 이동 추적·
    /// ↓ 건너뛰기·전체 접기·타이핑 지연을 검사한 뒤 블록을 지워 원상복구한다. 접힘 상태는 HyperTextView 의 훅(isOffsetHidden 등)으로 읽는다.
    @MainActor
    static func runFold(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }
        func text() -> NSString { model.document.textStorage.string as NSString }
        func lineStart(_ line: Int) -> Int {
            let idx = LineIndex(nsString: text())
            return idx.lineStarts[max(0, min(line - 1, idx.lineCount - 1))]
        }
        func hidden(_ line: Int) -> Bool {
            var h = false
            let off = lineStart(line)
            model.send(.perform { tv in h = tv.isOffsetHidden?(off) ?? false })
            return h
        }
        func fragmentHeight(_ line: Int) -> CGFloat {
            var out: CGFloat = -1
            let off = lineStart(line)
            model.send(.perform { tv in
                guard let lm = tv.textLayoutManager, let cs = tv.textContentStorage,
                      let loc = cs.location(cs.documentRange.location, offsetBy: off) else { return }
                lm.ensureLayout(for: NSTextRange(location: loc))
                out = lm.textLayoutFragment(for: loc)?.layoutFragmentFrame.height ?? -1
            })
            return out
        }
        func pillCount() -> Int {
            var n = 0
            model.send(.perform { tv in n = tv.foldPills?(NSRange(location: 0, length: (tv.string as NSString).length)).count ?? 0 })
            return n
        }
        /// 캐럿 줄을 현재 텍스트로 직접 센다 (model.caretLine 은 250 ms 뒤에 갱신되는 문서 줄 인덱스를 쓴다)
        func caretLineNow() -> Int {
            var line = 0
            model.send(.perform { tv in line = LineIndex(nsString: tv.string as NSString).lineNumber(forUTF16Offset: tv.selectedRange().location) })
            return line
        }
        func gutterMarker(_ line: Int) -> GutterView.FoldMarker? {
            var m: GutterView.FoldMarker?
            let s = lineStart(line), e = lineStart(line + 1)
            model.send(.perform { tv in m = (tv.enclosingScrollView?.superview as? EditorContainerView)?.gutter.foldMarker?(s, { e }) })
            return m
        }
        model.send(.unfoldAll)
        let insertAt = text().length
        var block = "\nfold-header:"
        for i in 1...15 { block += "\n    child \(i)" }
        block += "\nafter-block"
        model.send(.perform { tv in tv.breakUndoCoalescing(); tv.insertText(block, replacementRange: NSRange(location: insertAt, length: 0)) })
        await wait(500)
        // 셀프테스트의 프로그램적 편집은 이벤트 사이가 아니라 Task 이어짐 사이에 일어나 undo 그룹이 저절로 닫히지 않는다 (실측: ⌘Z 가 지난 undo/redo 이후의 편집을
        // 전부 되돌림. undo 관리자를 직접 닫으면 SwiftUI 쪽 그룹과 어긋나 예외가 난다). undo → redo 한 쌍으로 경계를 만들어 두면 다음 편집부터 새 그룹이다.
        model.send(.undo); await wait(300); model.send(.redo); await wait(900)   // redo 뒤 줄 인덱스 250 ms + 백그라운드 영역 스캔
        let header = LineIndex(nsString: text()).lineCount - 16
        log("fold: appended block, header line \(header)")
        check(!hidden(header + 1) && pillCount() == 0, "fold: nothing folded before the command")
        check(gutterMarker(header) == .foldable && gutterMarker(header + 1) == nil, "fold: gutter marks the header as foldable (\(String(describing: gutterMarker(header))))")

        // ⌥⌘← : 캐럿 줄을 머리로 하는 영역을 접는다
        model.jump(toLine: header); await wait(300)
        model.send(.fold); await wait(300)
        check(hidden(header + 1) && hidden(header + 15) && !hidden(header) && !hidden(header + 16),
              "fold: hides lines \(header + 1)–\(header + 15) (header and after-block stay visible)")
        check(fragmentHeight(header + 3) == 0 && fragmentHeight(header) > 0,
              "fold: TextKit 2 fragment of a hidden line is zero-height (header \(fragmentHeight(header)), hidden \(fragmentHeight(header + 3)))")
        check(pillCount() == 1 && gutterMarker(header) == .folded, "fold: one ⋯ pill, gutter shows ▸")
        model.send(.perform { tv in (tv.enclosingScrollView?.superview as? EditorContainerView)?.gutter.display() })
        check(model.caretLine == header, "fold: caret stays on the header (line \(model.caretLine))")

        // 머리 줄 끝에 입력해도(스캔이 다시 돌아도) 접힘 유지, undo 도 유지
        model.send(.perform { tv in
            let r = LineIndex(nsString: tv.string as NSString).range(ofLine: header)
            tv.setSelectedRange(NSRange(location: NSMaxRange(r), length: 0))
            tv.insertText(" x", replacementRange: tv.selectedRange())
        }); await wait(900)
        check(hidden(header + 1) && pillCount() == 1, "fold: typing in the header keeps the fold")
        // undo 는 macOS 27 에서 shouldChangeText/didChangeText 를 거치지 않는다 — HyperTextView 의 저장소 알림 보강이 접힘을 옮기고 문서를 dirty 로 만들어야 한다
        model.saveNow(); await wait(600)
        check(!model.document.isDirty, "fold: saved before undo (clean)")
        model.send(.undo); await wait(400)
        check(hidden(header + 1) && pillCount() == 1, "fold: undo in the header keeps the fold")
        check(model.document.isDirty, "undo marks the document dirty (didChangeText fallback)")

        // ↓ 는 접힌 구간을 건너뛴다, ↑ 는 머리 줄로 돌아온다
        model.jump(toLine: header); await wait(200)
        model.send(.perform { tv in tv.doCommand(by: #selector(NSResponder.moveDown(_:))) }); await wait(200)
        check(caretLineNow() == header + 16 && hidden(header + 1), "fold: ↓ from the header lands after the fold (line \(caretLineNow()))")
        model.send(.perform { tv in tv.doCommand(by: #selector(NSResponder.moveUp(_:))) }); await wait(200)
        check(caretLineNow() == header && hidden(header + 1), "fold: ↑ returns to the header (line \(caretLineNow()))")

        // 캐럿이 숨은 줄로 들어가면 펼친다 (줄로 이동 — 검색·북마크 점프와 같은 경로)
        model.jump(toLine: header + 5); await wait(300)
        check(!hidden(header + 1) && caretLineNow() == header + 5 && pillCount() == 0, "fold: go-to-line into a hidden line unfolds (caret \(caretLineNow()))")

        // 접힘 위에 줄 삽입 → 접힘이 따라 내려감, undo → 제자리
        model.jump(toLine: header); await wait(200); model.send(.fold); await wait(200)
        model.send(.perform { tv in tv.insertText("inserted\n", replacementRange: NSRange(location: 0, length: 0)) }); await wait(300)
        check(hidden(header + 2) && !hidden(header + 1) && pillCount() == 1, "fold: inserting a line above shifts the fold down")
        model.send(.undo); await wait(400)
        check(hidden(header + 1) && !hidden(header) && pillCount() == 1, "fold: undo moves the fold back")

        // 머리 줄 삭제 → 접힘 해제
        model.jump(toLine: header); await wait(200)
        model.textTool(.deleteLine); await wait(300)
        check(pillCount() == 0 && !hidden(header), "fold: deleting the header line removes the fold")
        model.send(.undo); await wait(400)
        check(pillCount() == 0 && LineIndex(nsString: text()).lineCount - 16 == header, "fold: undo restores the line (fold stays open)")

        // 전체 접기 / 펼치기 — 샘플의 마크다운 헤딩 영역도 함께 접힌다
        model.send(.foldAll); await wait(300)
        // 바깥 헤딩(1줄 `# …`)이 문서 전체를 숨기므로 보이는 표식은 가장 바깥 하나뿐 (안쪽 접힘의 표식은 숨은 머리 줄에 그리지 않는다)
        check(hidden(header + 1) && hidden(2) && pillCount() == 1, "fold all: everything under the top heading hidden, \(pillCount()) visible pill")
        check(!hidden(caretLineNow()), "fold all: caret moved to a visible header (line \(caretLineNow()))")
        model.send(.unfoldAll); await wait(300)
        check(!hidden(header + 1) && pillCount() == 0, "unfold all: nothing hidden")

        // 성능: 접힘이 있는 상태에서 타이핑 40타 (fold delegate 가 문단마다 호출된다)
        model.jump(toLine: header); await wait(200); model.send(.fold); await wait(200)
        model.goToEnd(); await wait(200)
        let t1 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<40 {
            model.send(.perform { tv in tv.insertText("a", replacementRange: tv.selectedRange()) })
            await wait(1)
        }
        let typingMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000 / 40 - 1
        log(String(format: "perf typing with fold %.2f ms/keystroke (incl. run loop)", typingMs))
        check(typingMs < 16, "fold: typing latency under one frame with the fold delegate installed")
        check(hidden(header + 1), "fold: typing after the fold keeps it")

        // 스크롤바 마커: 설정 토글이 저장되고 뷰가 존재한다
        var markerOK = false
        model.send(.perform { tv in markerOK = (tv.enclosingScrollView?.superview as? EditorContainerView)?.markerView is ScrollMarkerView })
        check(markerOK && model.showScrollMarkers, "markers: ScrollMarkerView attached, default on")
        model.showScrollMarkers = false
        check(AppDefaults.store.object(forKey: "ui.scrollMarkers") as? Bool == false, "markers: toggle persisted to ui.scrollMarkers")
        model.showScrollMarkers = true

        // 원상복구: 모두 펼치고 붙인 블록(+타이핑)을 지운다
        model.send(.unfoldAll); await wait(100)
        model.send(.perform { tv in
            let len = (tv.string as NSString).length
            tv.breakUndoCoalescing()
            tv.insertText("", replacementRange: NSRange(location: insertAt, length: len - insertAt))
        }); await wait(300)
        check(text().length == insertAt && pillCount() == 0, "fold: sample restored (length \(text().length))")
    }
}
