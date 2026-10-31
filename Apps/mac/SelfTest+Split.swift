import SwiftUI
import AppKit
import HyperCore

// 분할 보기(split) + Quick Append 셀프테스트. SelfTest.run 의 샘플 문서 위에서 돌고 끝에 원상복구한다.
// `--selftest-split-big <path>` 를 주면 그 파일(사본!)을 열어 분할 상태의 타이핑 지연을 추가로 잰다 (개발용, 문서를 수정하지는 않음).
extension SelfTest {
    @MainActor
    static func runSplit(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { pumpEvent(); try? await Task.sleep(nanoseconds: ms * 1_000_000) }   // 이벤트를 흘려 undo 그룹을 닫는다
        func text() -> String { model.document.textStorage.string }
        func appendViaActive(_ s: String) {
            model.send(.perform { tv in
                tv.breakUndoCoalescing()
                let end = (tv.string as NSString).length
                tv.setSelectedRange(NSRange(location: end, length: 0))
                tv.insertText(s, replacementRange: tv.selectedRange())
            })
        }
        let session = model.session
        let before = text()
        check(session.splitMode == .none && session.coordinators.count == 1, "starts with a single editor (\(session.coordinators.count))")

        // 1. 좌우 분할 → 편집기 둘, 같은 콘텐츠 스토리지·undo 매니저
        session.splitMode = .vertical; await wait(700)
        let cs = session.coordinators
        check(cs.count == 2 && session.primary != nil && session.secondary != nil, "split vertical → \(cs.count) editors (primary + secondary)")
        check(cs.allSatisfy { $0.textView?.textContentStorage === session.contentStorage }, "both text views share session.contentStorage")
        check(cs.allSatisfy { $0.textView?.undoManager === session.undoManager }, "both text views use the shared undo manager")
        check(session.contentStorage.textStorage === model.document.textStorage, "shared content storage is bound to the document storage")
        let primaryTV = session.primary?.textView
        let secondaryTV = session.secondary?.textView
        check(primaryTV != nil && secondaryTV != nil && primaryTV !== secondaryTV, "two distinct text views")

        // 2. 주 편집기 입력 → 보조 편집기에 보임, 보조에서 undo
        session.activeEditorID = session.primary?.id
        appendViaActive("\nSPLIT-A"); await wait(300)
        check(secondaryTV?.string.hasSuffix("SPLIT-A") == true, "typing in primary is visible in secondary")
        session.activeEditorID = session.secondary?.id
        model.send(.undo); await wait(300)
        check(text() == before, "undo from secondary reverts primary typing")

        // 3. 보조 편집기 입력 → 주 편집기에 보임, 주에서 undo
        appendViaActive("\nSPLIT-B"); await wait(300)
        check(primaryTV?.string.hasSuffix("SPLIT-B") == true, "typing in secondary is visible in primary")
        session.activeEditorID = session.primary?.id
        model.send(.undo); await wait(300)
        check(text() == before, "undo from primary reverts secondary typing")

        // 4. 모두 바꾸기(주) → 보조에서 undo 한 번
        model.searchQuery = "NEEDLE"; model.replaceText = "NEEDLE9"; model.replaceAll(); await wait(600)
        check(text().contains("NEEDLE9"), "replace all while split")
        session.activeEditorID = session.secondary?.id
        model.send(.undo); await wait(300)
        check(text() == before, "one undo from secondary reverts replace all")

        // 5. 상하 분할 → 보조만 다시 만들어지고 주 텍스트 뷰는 그대로
        model.setSplit(.horizontal); await wait(700)
        check(session.splitMode == .horizontal && session.coordinators.count == 2, "stacked split → \(session.coordinators.count) editors")
        check(session.primary?.textView === primaryTV, "stacked split keeps the primary text view")
        check(session.secondary?.textView !== secondaryTV && session.secondary?.textView?.textContentStorage === session.contentStorage,
              "stacked split recreates the secondary on the shared storage")

        // 6. 보조에서 입력 → 분할 끄기 → 편집기 하나, undo 스택 유지, undo 가 그 입력을 되돌린다
        session.activeEditorID = session.secondary?.id
        appendViaActive("\nSPLIT-C"); await wait(300)
        check(text().hasSuffix("SPLIT-C"), "typing in secondary before closing the split")
        model.setSplit(.none); await wait(700)
        check(session.splitMode == .none && session.coordinators.count == 1 && session.primary?.textView === primaryTV,
              "split off → one editor, primary text view kept (\(session.coordinators.count))")
        check(session.isActive(session.primary!), "primary becomes active after the split closes")
        check(session.undoManager.canUndo, "undo stack survives closing the split")
        model.send(.undo); await wait(400)
        check(text() == before, "undo after closing the split reverts typing made in the closed editor")

        // 7. Quick Append: 빈 줄 + 타임스탬프 헤딩 + 메모가 끝에 붙고 바로 저장되며, undo 한 번으로 사라진다
        let ok = model.quickAppend("quick note", withTimestamp: true)
        model.document.saveSynchronously()
        await wait(300)
        let lines = text().components(separatedBy: "\n")
        let n = lines.count
        let headingOK = n >= 4 && Timestamp.headingRegex.firstMatch(in: lines[n - 3], options: [], range: NSRange(location: 0, length: (lines[n - 3] as NSString).length)) != nil
        check(ok && text().hasSuffix("quick note\n") && headingOK && lines[n - 4].isEmpty,
              "quick append → blank line + timestamp heading + note (tail: \(lines.suffix(4)))")
        check(!model.document.isDirty, "quick append saved immediately")
        let disk = (try? String(contentsOf: model.document.url, encoding: .utf8)) ?? ""
        check(disk.hasSuffix("quick note\n"), "quick append is on disk")
        let recent = model.output.suffix(6).map(\.text)
        check(recent.contains { !$0.hasPrefix("[selftest]") && ($0.contains("Quick Append") || $0.contains("빠른 추가")) }, "quick append logged in the output panel")
        model.send(.undo); await wait(300)
        check(text() == before, "one undo removes the quick append")
        check(model.quickAppend("   \n", withTimestamp: false) == false, "blank quick append is ignored")

        // 7b. Quick Append 창: 전역 단축키 등록, 열기 → 키 창 + 입력 포커스, 입력 → ⌘↩(submit) → 숨김 + 파일 저장, Esc(hide) 는 초안을 남긴다
        let qa = model.quickAppend
        check(qa.isHotKeyRegistered && !qa.hotkeyFailed, "global hotkey registered: '\(qa.hotkeyStatus)'")
        qa.show()
        for _ in 0..<30 where !(qa.isVisible && qa.isTextViewFocused && (qa.isKeyWindow || !NSApp.isActive)) { await wait(100) }   // 부하가 큰 머신에서는 창 전환이 늦다
        // 앱이 비활성이면 isKeyWindow 는 문서대로 false 다 (nonactivating 패널은 그래도 키 입력을 받는다) → 활성일 때만 키 창 여부를 본다
        check(qa.isVisible && (qa.isKeyWindow || !NSApp.isActive), "quick append panel is visible\(NSApp.isActive ? " and key" : " (app inactive — key status not reported)") (key=\(qa.isKeyWindow))")
        check(qa.isTextViewFocused, "quick append text view is the first responder (textView=\(qa.textView != nil))")
        qa.textView?.insertText("panel note", replacementRange: NSRange(location: 0, length: 0)); await wait(200)
        check(qa.draft == "panel note", "typing in the panel updates the draft ('\(qa.draft)' tv='\(qa.textView?.string ?? "nil")')")
        qa.submit(); await wait(600)
        check(!qa.isVisible && qa.draft.isEmpty && text().hasSuffix("panel note\n"), "⌘↩ appends, clears the draft and hides the panel")
        check(((try? String(contentsOf: model.document.url, encoding: .utf8)) ?? "").hasSuffix("panel note\n"), "panel note saved to disk")
        model.send(.undo); await wait(300)
        check(text() == before, "undo removes the panel note")
        qa.show(); await wait(300)
        qa.textView?.insertText("kept draft", replacementRange: NSRange(location: 0, length: 0)); await wait(100)
        qa.hide(); await wait(200)
        check(!qa.isVisible && qa.draft == "kept draft", "Esc/hide keeps the draft for next time")
        qa.draft = ""

        // 8. (선택) 큰 파일에서 분할 상태 타이핑 지연
        if let big = LaunchOptions.value("--selftest-split-big") {
            let sampleURL = model.document.url
            model.open(url: URL(fileURLWithPath: big)); await wait(1500)
            model.setSplit(.vertical); await wait(1000)
            session.activeEditorID = session.primary?.id
            model.goToEnd(); await wait(400)
            let t1 = CFAbsoluteTimeGetCurrent()
            for _ in 0..<80 {
                model.send(.perform { tv in tv.insertText("a", replacementRange: tv.selectedRange()) })
                await wait(1)
            }
            let ms = (CFAbsoluteTimeGetCurrent() - t1) * 1000 / 80 - 1
            log(String(format: "perf typing split %.2f ms/keystroke (incl. run loop) · %d lines · %d bytes", ms, model.document.lineIndex.lineCount, model.document.fileSize))
            check(ms < 16, "split typing latency under one frame (16 ms)")
            model.send(.perform { tv in
                let ns = tv.string as NSString
                tv.insertText("", replacementRange: NSRange(location: ns.length - 80, length: 80))
            }); await wait(200)
            model.setSplit(.none); await wait(500)
            model.open(url: sampleURL); await wait(800)
        }
    }
}
