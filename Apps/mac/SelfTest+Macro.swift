import SwiftUI
import AppKit
import HyperCore

extension SelfTest {
    /// 빈 NSEvent 하나를 흘린다 — AppKit 은 이벤트 처리 끝에만 자동 undo 그룹을 닫으므로(런루프 양보·타이머로는 안 닫힘, 실측),
    /// 프로그램적 편집만 하는 셀프테스트는 이걸 넣어야 대화형 사용과 같은 undo 단위가 된다 (SelfTest.run 의 wait 도 사용)
    @MainActor
    static func pumpEvent() {
        guard let e = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) else { return }
        NSApp.postEvent(e, atStart: false)
    }

    /// 매크로: 기록(연속 입력 합치기·명령) → JSON 왕복 → ×2 재생 → undo 1회 복구 → IME 조합은 확정만 기록 → 기록 중 타이핑 지연
    /// → 알 수 없는 단계 건너뜀·무변화 반복 중단 → find 단계 → 저장/삭제(임시 폴더) → 메뉴 → 1.3 MB 문서 ×100 재생 성능 → 파일 전환 시 기록 중단
    @MainActor
    static func runMacro(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { pumpEvent(); try? await Task.sleep(nanoseconds: ms * 1_000_000) }
        func text() -> NSString { model.document.textStorage.string as NSString }
        func lastLines(_ n: Int) -> [String] { Array((text() as String).components(separatedBy: "\n").suffix(n)) }
        /// 출력 패널 최근 6줄에 영어/한국어 문구가 있는지 (셀프테스트의 PASS 줄도 같은 패널에 섞여 들어온다)
        func lastOutput(_ en: String, _ ko: String) -> Bool { model.output.suffix(6).contains { $0.text.contains(en) || $0.text.contains(ko) } }
        func undoLevel() -> Int { var l = -1; model.send(.perform { tv in l = tv.undoManager?.groupingLevel ?? -1 }); return l }
        /// --debug-perf 로그에 진행 표시 (멈추는 지점 추적용)
        func mark(_ s: String) { Perf.log("[selftest macro] " + s) }
        let rec = model.macros
        let lengthBefore = text().length

        // 0. 끝에 세 줄 덧붙이고 첫 줄(alpha) 머리에 캐럿 — 끝에서 전부 걷어낸다
        mark("step 0")
        let appended = "alpha\nbeta\ngamma"
        model.send(.perform { tv in
            tv.breakUndoCoalescing()
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            tv.insertText("\n" + appended, replacementRange: tv.selectedRange())
            tv.setSelectedRange(NSRange(location: (tv.string as NSString).length - (appended as NSString).length, length: 0))
        }); await wait(200)

        // 1. 기록: "-" + " " (합쳐져 "- ") → 줄 끝 → " ✓" → 아래 → 줄 머리 = 5단계
        mark("step 1")
        model.toggleMacroRecording()
        check(rec.isRecording && lastOutput("Macro recording started", "매크로 기록 시작"), "macro recording started · '\(model.output.suffix(2).map(\.text).joined(separator: " | "))'")
        model.send(.perform { tv in
            tv.insertText("-", replacementRange: tv.selectedRange())
            tv.insertText(" ", replacementRange: tv.selectedRange())
            tv.doCommand(by: #selector(NSResponder.moveToEndOfLine(_:)))
            tv.insertText(" ✓", replacementRange: tv.selectedRange())
            tv.doCommand(by: #selector(NSResponder.moveDown(_:)))
            tv.doCommand(by: #selector(NSResponder.moveToBeginningOfLine(_:)))
        }); await wait(100)
        model.toggleMacroRecording()
        let macro = rec.lastRecorded
        let expected: [MacroStep] = [.insert("- "), .command("moveToEndOfLine:"), .insert(" ✓"), .command("moveDown:"), .command("moveToBeginningOfLine:")]
        check(!rec.isRecording && macro?.steps == expected, "macro recorded · 5 coalesced steps: \(macro?.steps ?? [])")
        check(lastOutput("Macro recorded · 5 steps", "매크로 기록 완료 · 5단계"), "output log: recorded · '\(model.output.suffix(2).map(\.text).joined(separator: " | "))'")
        check(lastLines(3)[0] == "- alpha ✓", "recording applied to the line: '\(lastLines(3)[0])'")
        if let m = macro {
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
            let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
            let back = (try? enc.encode(m)).flatMap { try? dec.decode(Macro.self, from: $0) }
            check(back == m, "macro JSON round trip")
        }

        // 2. ×2 재생 → beta·gamma 변환, undo 한 번으로 둘 다 복구
        mark("step 2")
        log("undo grouping level before play: \(undoLevel())")
        let r1 = await rec.playLast(times: 2)
        log("undo grouping level after play: \(undoLevel())")
        check(r1?.iterations == 2 && r1?.steps == 10 && lastLines(2) == ["- beta ✓", "- gamma ✓"], "play ×2 → \(lastLines(2)) (\(r1.map { "\($0.iterations) runs · \($0.steps) steps · \(Int($0.ms)) ms" } ?? "nil"))")
        check(lastOutput("Macro played ×2", "매크로 재생 ×2"), "output log: played · '\(model.output.suffix(2).map(\.text).joined(separator: " | "))'")
        model.send(.undo); await wait(200)
        check(lastLines(3) == ["- alpha ✓", "beta", "gamma"], "single undo reverts the whole playback → \(lastLines(3))")

        // 3. IME: 조합(setMarkedText)은 기록하지 않고 확정(insertText)만 — 문서에도 확정 글자만 남는다
        mark("step 3")
        model.send(.perform { tv in tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0)) })
        model.toggleMacroRecording()
        model.send(.perform { tv in
            tv.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            tv.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            tv.insertText("한", replacementRange: NSRange(location: NSNotFound, length: 0))
        }); await wait(100)
        model.toggleMacroRecording()
        check(rec.lastRecorded?.steps == [.insert("한")], "IME: only the committed syllable is recorded → \(rec.lastRecorded?.steps ?? [])")
        check(lastLines(1) == ["gamma한"], "IME commit replaced the marked text → '\(lastLines(1)[0])'")

        // 4. 기록 중 타이핑 지연 (싱크 설치 + 기록 상태) — 80타가 한 단계로 합쳐진다
        mark("step 4")
        model.toggleMacroRecording()
        let t1 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<80 {
            model.send(.perform { tv in tv.insertText("a", replacementRange: tv.selectedRange()) })
            await wait(1)
        }
        let typingMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000 / 80 - 1
        model.toggleMacroRecording()
        log(String(format: "perf typing while recording a macro %.2f ms/keystroke (incl. run loop)", typingMs))
        check(typingMs < 16, "typing latency while recording under one frame (16 ms)")
        check(rec.lastRecorded?.steps == [.insert(String(repeating: "a", count: 80))], "80 keystrokes coalesced into one insert step (\(rec.lastRecorded?.steps.count ?? -1))")

        // 5. 알 수 없는 명령·도구는 건너뛰고, 한 바퀴에 아무 변화가 없으면 반복을 멈춘다 (문서 끝에서 moveRight 는 무효)
        mark("step 5")
        let odd = Macro(name: "odd", steps: [.command("noSuchCommand:"), .tool("noSuchTool"), .command("moveRight:")])
        model.send(.perform { tv in tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0)) })
        let r2 = await rec.play(odd, times: 50)
        check(r2?.skipped == 2 && r2?.iterations == 1 && r2?.stoppedEarly == true,
              "unknown steps skipped (\(r2?.skipped ?? -1)) and no-change loop stopped after \(r2?.iterations ?? -1) run")
        check(lastOutput("stopped early", "조기 중단"), "output log: stopped early · '\(model.output.suffix(2).map(\.text).joined(separator: " | "))'")

        // 6. find 단계: NEEDLE 은 두 개 → 세 번째 바퀴에서 실패해 멈춘다. F3 는 .find(검색어) 로 기록된다
        mark("step 6")
        model.send(.perform { tv in tv.setSelectedRange(NSRange(location: 0, length: 0)) })
        let r3 = await rec.play(Macro(name: "find", steps: [.find("NEEDLE")]), times: 10)
        var sel = NSRange(location: 0, length: 0)
        model.send(.perform { tv in sel = tv.selectedRange() })
        check(r3?.iterations == 2 && r3?.stoppedEarly == true && sel.length == 6 && text().substring(with: sel) == "NEEDLE" && sel.location > 60,
              "find ×10 stops after the 2nd NEEDLE (runs \(r3?.iterations ?? -1), sel \(sel))")
        model.toggleMacroRecording()
        model.searchQuery = "NEEDLE"; model.findNext()
        model.toggleMacroRecording()
        check(rec.lastRecorded?.steps == [.find("NEEDLE")], "F3 while recording → .find(query) \(rec.lastRecorded?.steps ?? [])")
        await wait(400)

        // 7. 저장·삭제 — 자동화 실행의 저장소는 임시 폴더 (사용자 파일 무관)
        mark("step 7")
        model.saveLastMacro(name: "Find needle")
        let storeURL = rec.store.fileURL
        check(rec.store.macros.map(\.name) == ["Find needle"] && FileManager.default.fileExists(atPath: storeURL.path), "saved macro listed and persisted · \(storeURL.path)")
        check(storeURL.path.contains("hyperedit-macros-"), "self-test macro store lives in a temp folder")
        let again = MacroStore(directory: rec.store.directory)
        check(again.macros == rec.store.macros && again.lastRecorded == rec.lastRecorded, "store reload from disk matches")
        if let id = rec.store.macros.first?.id { model.deleteMacro(id: id) }
        check(rec.store.macros.isEmpty && lastOutput("Macro deleted", "매크로 삭제"), "macro deleted · '\(model.output.suffix(2).map(\.text).joined(separator: " | "))'")

        // 8. 메뉴: ⇧⌘M · ⌥⌘M 이 각각 정확히 한 항목
        mark("step 8")
        if let menu = NSApp.mainMenu {
            func items(_ key: String, _ mods: NSEvent.ModifierFlags) -> [String] {
                var hits: [String] = []
                func walk(_ m: NSMenu) { for it in m.items { if it.keyEquivalent == key, it.keyEquivalentModifierMask.contains(mods) { hits.append(it.title) }; if let s = it.submenu { walk(s) } } }
                walk(menu); return hits
            }
            let rec1 = items("m", [.command, .shift]), play1 = items("m", [.command, .option])
            check(rec1.count == 1 && play1.count == 1, "⇧⌘M / ⌥⌘M bound to exactly one menu item each: \(rec1) / \(play1)")
        }

        // 9. 원상복구: 덧붙인 텍스트 전부 제거 (이후 단계는 원래 샘플 기준)
        mark("step 9")
        model.send(.perform { tv in
            let ns = tv.string as NSString
            tv.insertText("", replacementRange: NSRange(location: lengthBefore, length: ns.length - lengthBefore))
        }); await wait(200)
        check(text().length == lengthBefore, "appended text removed (len \(text().length) vs \(lengthBefore))")

        // 10. 1.3 MB·3만 줄 문서: 10단계 ×100 재생 < 1 s, undo 한 번으로 복구. 기록 중 파일 전환 → 기록 중단 로그
        mark("step 10")
        let dir = model.document.url.deletingLastPathComponent()
        let bigURL = dir.appendingPathComponent("big.md")
        let big = (0..<33_000).map { String(format: "2026-01-01 12:%02d INFO log line %06d", $0 % 60, $0) }.joined(separator: "\n")
        try? big.write(to: bigURL, atomically: true, encoding: .utf8)
        model.toggleMacroRecording()
        model.open(url: bigURL); await wait(1500)
        check(!rec.isRecording && model.output.contains { $0.text.contains("document changed") || $0.text.contains("문서가 바뀜") }, "recording stops when the document changes")
        check(model.document.lineIndex.lineCount >= 33_000, "big document loaded lines=\(model.document.lineIndex.lineCount) size=\(model.document.fileSize)")
        model.send(.perform { tv in tv.setSelectedRange(NSRange(location: 0, length: 0)); tv.scrollRangeToVisible(NSRange(location: 0, length: 0)) }); await wait(300)
        let ten = Macro(name: "ten", steps: [.insert("- "), .command("moveToEndOfLine:"), .insert(" ✓"), .command("moveToBeginningOfLine:"), .command("moveRight:"),
                                              .command("moveLeft:"), .insert("x"), .command("deleteBackward:"), .command("moveDown:"), .command("moveToBeginningOfLine:")])
        let bigLen = text().length
        let r4 = await rec.play(ten, times: 100)
        log(String(format: "perf macro ×100 (10 steps) on %.2f MB: %.0f ms", Double(model.document.fileSize) / 1_048_576, r4?.ms ?? -1))
        check(r4?.iterations == 100 && (r4?.ms ?? 9999) < 1000, "100 runs of a 10-step macro on a 1.3 MB document in under 1 s (\(Int(r4?.ms ?? -1)) ms)")
        check(text().length == bigLen + 400 && (text() as String).hasPrefix("- 2026-01-01 12:00 INFO log line 000000 ✓\n"), "100 lines transformed (+\(text().length - bigLen) chars)")
        model.send(.undo); await wait(300)
        check(text().length == bigLen && (text() as String).hasPrefix("2026-01-01 12:00 INFO log line 000000\n"), "single undo reverts all 100 runs")
        model.open(url: dir.appendingPathComponent("sample.md")); await wait(800)
        check(model.document.url.lastPathComponent == "sample.md" && text().length == lengthBefore, "sample reopened intact (len \(text().length))")
    }
}
