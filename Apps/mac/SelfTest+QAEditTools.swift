import SwiftUI
import AppKit
import HyperCore

// QA 셀프테스트 — 편집 도구의 경계 상황. runMacro 다음에 돌며 sample.md 가 디스크 그대로 열려 있다고 가정하고, 끝에 원상복구한다.
//  1. 주석 토글: 첫 줄(캐럿만) · 개행 없는 끝 줄 · 멀티 캐럿이 있을 때(단일 캐럿으로 접고 첫 범위의 줄만, 다른 곳 손상 없음) · dirty 전이
//  2. JSON 정리: 문서 전체가 JSON 이 아닐 때(텍스트 그대로·캐럿 오류 위치·출력 패널 오류·dirty 아님) · 줄 중간에서 시작하는 선택
//  3. 스니펫: 한글 바로 뒤 트리거(한 단어 → 펼치지 않음) · 같은 번호 탭스톱의 멀티 캐럿 편집 · ⇧Tab 되돌아가기 · Esc · 열 모드 · 깨진 snippets.json + 선택창
//  4. 매크로: IME 조합 + Backspace + Enter 기록 → ×3 재생 → undo 1회 · 마지막 줄 deleteLine · N번 재생 클램프(0 · 음수 · 10,001 · "10,000" · 글자) · 기록 중 재생 거부 · 깨진 macros.json
//  5. 성능: 1.3 MB 문서 전체 주석 토글 / JSON 정리·한 줄로 (동기 호출 시간, --debug-perf 로 메인 스레드 정지 확인)
extension SelfTest {
    @MainActor
    static func runQAEditTools(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { pumpEvent(); try? await Task.sleep(nanoseconds: ms * 1_000_000) }   // 이벤트를 흘려 undo 그룹을 닫는다
        func text() -> NSString { model.document.textStorage.string as NSString }
        func lines() -> [String] { (text() as String).components(separatedBy: "\n") }
        func lastLines(_ n: Int) -> [String] { Array(lines().suffix(n)) }
        func sel() -> NSRange { var r = NSRange(location: -1, length: 0); model.send(.perform { tv in r = tv.selectedRange() }); return r }
        func selectedText() -> String { let r = sel(); let ns = text(); return r.location >= 0 && NSMaxRange(r) <= ns.length ? ns.substring(with: r) : "" }
        func sessionActive() -> Bool { var a = false; model.send(.perform { tv in a = tv.snippetSession != nil }); return a }
        func command(_ s: Selector) { model.send(.perform { tv in tv.doCommand(by: s) }) }
        func tab() { command(#selector(NSResponder.insertTab(_:))) }
        func type(_ s: String) { model.send(.perform { tv in tv.insertText(s, replacementRange: tv.selectedRange()) }) }
        func caretTo(_ loc: Int) { model.send(.perform { tv in tv.setSelectedRange(NSRange(location: loc, length: 0)) }) }
        func append(_ s: String) {
            model.send(.perform { tv in
                tv.breakUndoCoalescing()
                tv.insertText(s, replacementRange: NSRange(location: (tv.string as NSString).length, length: 0))
                tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))
            })
        }
        func truncate(to length: Int) {
            model.send(.perform { tv in
                let n = (tv.string as NSString).length
                if n > length { tv.insertText("", replacementRange: NSRange(location: length, length: n - length)) }
            })
        }
        // 출력 패널은 500줄에서 잘리므로(AppModel.log) 개수가 아니라 마지막 줄의 id 를 표식으로 삼아 그 뒤에 추가된 줄만 본다
        func outputMark() -> OutputLine.ID? { model.output.last?.id }
        func outputSince(_ mark: OutputLine.ID?) -> [OutputLine] {
            guard let mark, let i = model.output.firstIndex(where: { $0.id == mark }) else { return model.output }
            return Array(model.output[(i + 1)...])
        }
        func mark(_ s: String) { Perf.log("[selftest qa] " + s) }
        let rec = model.macros
        let sampleURL = model.document.url
        let dir = sampleURL.deletingLastPathComponent()
        model.saveNow(); await wait(700)
        let original = text() as String
        let originalLength = text().length
        let lineCount = lines().count

        // 1. 주석 토글
        mark("1 toggle comment")
        check(!model.document.isDirty, "qa: clean document to start (dirty=\(model.document.isDirty))")
        caretTo(0)
        let firstLine = lines()[0]
        model.textTool(.toggleComment); await wait(250)
        check(lines()[0] == "<!-- \(firstLine) -->" && lines().count == lineCount && sel() == NSRange(location: 0, length: 0), "toggle comment on the first line (caret at 0) → '\(lines()[0])', caret \(sel())")
        check(model.document.isDirty, "toggle comment marks the document dirty")
        model.textTool(.toggleComment); await wait(250)
        check(text() as String == original, "toggle again restores the first line")
        append("\n끝 줄 without newline")
        let tailCount = lines().count
        model.textTool(.toggleComment); await wait(250)
        check(lastLines(1) == ["<!-- 끝 줄 without newline -->"] && lines().count == tailCount && !(text() as String).hasSuffix("\n") && sel() == NSRange(location: text().length, length: 0),
              "toggle comment on the last line without newline → '\(lastLines(1)[0])', no newline added, caret stays at end")
        model.textTool(.toggleComment); await wait(250)
        check(lastLines(1) == ["끝 줄 without newline"], "toggle again → original last line")
        truncate(to: originalLength); await wait(200)
        // 멀티 캐럿(⌘D 꼴 두 범위) 상태에서 ⌘/ → 단일 캐럿으로 접고 첫 범위의 줄만 바꾼다
        let needles: [NSRange] = {
            var out: [NSRange] = []; let ns = text(); var from = 0
            while from < ns.length {
                let r = ns.range(of: "NEEDLE", options: [], range: NSRange(location: from, length: ns.length - from))
                if r.location == NSNotFound { break }
                out.append(r); from = NSMaxRange(r)
            }
            return out
        }()
        check(needles.count == 2, "two NEEDLE occurrences for the multi-caret case (\(needles.count))")
        let needleLine = lines().firstIndex { $0.contains("NEEDLE") } ?? 0
        let needleText = lines()[needleLine], nextText = lines()[needleLine + 1]
        model.send(.perform { tv in tv.setMulti(needles) }); await wait(200)
        check(model.multiCaretCount == 2, "multi carets set (\(model.multiCaretCount))")
        model.textTool(.toggleComment); await wait(250)
        check(lines()[needleLine] == "<!-- \(needleText) -->" && lines()[needleLine + 1] == nextText && model.multiCaretCount <= 1,
              "toggle with multi-caret → only the first range's line, carets collapsed: '\(lines()[needleLine])' / '\(lines()[needleLine + 1])' carets=\(model.multiCaretCount)")
        check(text().length == originalLength + 9 && lines().count == lineCount, "no corruption elsewhere (+9 chars, same line count: \(text().length - originalLength), \(lines().count))")
        model.textTool(.toggleComment); await wait(250)
        check(text() as String == original, "toggle again restores after the multi-caret case")

        // 2. JSON 정리 — 오류 경로 (문서 전체) · 줄 중간 선택
        mark("2 format json")
        model.saveNow(); await wait(700)
        model.showBottomPanel = false; model.bottomTab = .findResults
        caretTo(5)
        var outCount = outputMark()
        model.textTool(.formatJSON); await wait(300)
        let jsonErr = outputSince(outCount).last { $0.isError }
        check(text() as String == original && sel() == NSRange(location: 0, length: 0), "non-JSON document: text unchanged, caret moved to the error offset 0 (sel \(sel()))")
        check(jsonErr != nil && (jsonErr?.text.contains("line 1, column 1") == true || jsonErr?.text.contains("1줄 1열") == true), "error logged with line 1, column 1 · '\(jsonErr?.text ?? "")'")
        check(model.showBottomPanel && model.bottomTab == .output, "bottom panel switched to Output (\(model.showBottomPanel), \(model.bottomTab))")
        check(!model.document.isDirty, "a failed format does not dirty the document (dirty=\(model.document.isDirty))")
        let json = "{\"b\":[1,{\"a\":\"한글\"}],\"c\":true}"
        append("\n접두사 prefix \(json) 접미사")
        let jr = text().range(of: json, options: .backwards)
        model.send(.perform { tv in tv.setSelectedRange(jr) })
        model.textTool(.formatJSON); await wait(300)
        let pretty = "{\n  \"b\": [\n    1,\n    {\n      \"a\": \"한글\"\n    }\n  ],\n  \"c\": true\n}"
        check(selectedText() == pretty && lastLines(9).first == "접두사 prefix {" && lastLines(1) == ["} 접미사"],
              "format JSON on a mid-line selection → selection = result, prefix/suffix kept (\(lastLines(9).first ?? "") … \(lastLines(1)[0]))")
        model.textTool(.minifyJSON); await wait(300)
        check(lastLines(1) == ["접두사 prefix \(json) 접미사"] && selectedText() == json, "minify restores the one-liner, selection = result")
        // 선택 안 오류: 줄·열은 문서 기준
        append("\nx = {\"a\":1,,}")
        let brokenRange = NSRange(location: text().length - 9, length: 9)
        model.send(.perform { tv in tv.setSelectedRange(brokenRange) })
        outCount = outputMark()
        model.textTool(.formatJSON); await wait(300)
        let selErr = outputSince(outCount).last { $0.isError }
        check(lastLines(1) == ["x = {\"a\":1,,}"] && sel() == NSRange(location: text().length - 2, length: 0) && (selErr?.text.contains("\(lines().count)") ?? false) && (selErr?.text.contains("12") ?? false),
              "error inside a mid-line selection → caret at the 2nd comma, document line \(lines().count) column 12 · '\(selErr?.text ?? "")'")
        truncate(to: originalLength); await wait(200)

        // 3. 스니펫
        mark("3 snippets")
        append("\n메모todo"); tab(); await wait(200)
        check(lastLines(1) == ["메모todo\t"], "'메모todo' + Tab → plain tab (Hangul counts as a word character, so no expansion) '\(lastLines(1)[0])'")
        append("\n메모 todo"); tab(); await wait(200)
        check(lastLines(1) == ["메모 - [ ] "], "'메모 todo' + Tab → expands after a space '\(lastLines(1)[0])'")
        append("\n🙂todo"); tab(); await wait(200)
        check(lastLines(1) == ["🙂- [ ] "], "emoji is a word boundary → expands '\(lastLines(1)[0])'")
        append("\n_todo"); tab(); await wait(200)
        check(lastLines(1) == ["_todo\t"], "'_todo' + Tab → '_' is a word character → plain tab")
        let store = model.snippets
        let defaultsJSON = (try? String(contentsOf: store.fileURL, encoding: .utf8)) ?? ""
        func writeSnippets(_ s: String, bump: TimeInterval) {
            try? s.write(to: store.fileURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(bump)], ofItemAtPath: store.fileURL.path)
        }
        writeSnippets(#"[{"trigger":"tag","title":"Tag","body":"<${1:div}>$0</$1>"},{"trigger":"link","title":"L","body":"[${1:text}](${2:url})$0"},{"trigger":"todo","body":"- [ ] $0"}]"#, bump: 5)
        append("\ntag"); tab(); await wait(250)
        check(lastLines(1) == ["<div></>"] && model.multiCaretCount == 2 && sessionActive(), "'tag' + Tab → both $1 as two carets (\(model.multiCaretCount)) '\(lastLines(1)[0])'")
        type("p"); await wait(200)
        check(lastLines(1) == ["<p></p>"] && sessionActive(), "typing over the multi-caret tabstop edits both → '\(lastLines(1)[0])'")
        tab(); await wait(200)
        check(!sessionActive() && model.multiCaretCount <= 1 && sel() == NSRange(location: text().length - 4, length: 0), "Tab → $0 between the tags, session ended (sel \(sel()), len \(text().length))")
        append("\nlink"); tab(); await wait(200)
        check(selectedText() == "text" && sessionActive(), "'link' + Tab selects $1 '\(selectedText())'")
        type("A"); await wait(150)
        tab(); await wait(150)
        check(selectedText() == "url" && lastLines(1) == ["[A](url)"], "Tab → $2 'url' after typing ('\(selectedText())')")
        command(#selector(NSResponder.insertBacktab(_:))); await wait(150)
        check(selectedText() == "A" && sessionActive(), "⇧Tab → back to $1 which now holds 'A' ('\(selectedText())')")
        type("B"); await wait(150)
        check(lastLines(1) == ["[B](url)"], "typing over the revisited $1 replaces it → '\(lastLines(1)[0])'")
        command(#selector(NSResponder.cancelOperation(_:))); await wait(150)
        check(!sessionActive() && lastLines(1) == ["[B](url)"], "Esc ends the session without changing text")
        tab(); await wait(150)
        check(lastLines(1) == ["[B\t](url)"], "Tab after Esc is a plain tab → '\(lastLines(1)[0])'")
        // 열 모드: 블록이 있으면 Tab 은 블록 삽입(펼치지 않음); 블록 없이 켜져만 있으면 단일 캐럿이라 펼친다
        append("\ntodo\ntodo")
        caretTo(text().length - 5)
        model.columnMode = true; await wait(150)
        model.send(.perform { tv in tv.extendBlock(dx: 0, dy: 1) }); await wait(150)
        check(model.columnBlockActive && model.multiCaretCount == 2, "column block over two lines (carets \(model.multiCaretCount))")
        tab(); await wait(200)
        check(lastLines(2) == ["todo\t", "todo\t"] && !sessionActive(), "Tab with a column block inserts tabs on both lines, no snippet → \(lastLines(2))")
        model.columnMode = false; await wait(150)
        append("\ntodo")
        model.columnMode = true; await wait(100)
        tab(); await wait(200)
        check(lastLines(1) == ["- [ ] "], "column mode on without a block: single caret → snippet expands '\(lastLines(1)[0])'")
        model.columnMode = false; await wait(100)
        // 깨진 snippets.json → 오류 유지 + 이전 목록 유지, 선택창은 오류를 보여 주며 열린다, Tab 확장은 계속
        writeSnippets("[ { \"trigger\": \"x\", ", bump: 10)
        store.reloadIfChanged()
        check(store.lastError != nil && store.snippets.map(\.trigger) == ["tag", "link", "todo"], "broken snippets.json → error kept, previous list kept · '\(store.lastError ?? "")'")
        model.showSnippetPicker = true; await wait(700)
        check(model.showSnippetPicker && store.lastError != nil, "snippet picker shown with the error (no crash)")
        model.showSnippetPicker = false; await wait(300)
        append("\ntodo"); tab(); await wait(200)
        check(lastLines(1) == ["- [ ] "], "Tab expansion still works from the previous list while the file is broken")
        writeSnippets(defaultsJSON, bump: 15)
        store.reloadIfChanged()
        check(store.lastError == nil && store.snippets == SnippetStore.defaults, "restored snippets.json → defaults, error cleared")
        truncate(to: originalLength); await wait(200)

        // 4. 매크로
        mark("4 macro")
        append("\n매크로")
        let macroBase = text().length
        model.toggleMacroRecording()
        model.send(.perform { tv in
            tv.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            tv.setMarkedText("하", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            tv.setMarkedText("한", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            tv.insertText("한", replacementRange: NSRange(location: NSNotFound, length: 0))
            tv.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
            tv.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        }); await wait(150)
        model.toggleMacroRecording()
        check(rec.lastRecorded?.steps == [.insert("한"), .command("deleteBackward:"), .command("insertNewline:")], "IME commit + Backspace + Enter recorded as 3 steps: \(rec.lastRecorded?.steps ?? [])")
        check(text().length == macroBase + 1 && (text() as String).hasSuffix("매크로\n"), "recording itself left one newline (len \(text().length) vs \(macroBase + 1))")
        let afterRecord = text().length
        let r1 = await rec.playLast(times: 3)
        check(r1?.iterations == 3 && r1?.steps == 9 && text().length == afterRecord + 3 && (text() as String).hasSuffix("매크로\n\n\n\n"), "play ×3 → three more newlines (\(r1?.iterations ?? -1) runs, \(r1?.steps ?? -1) steps, len \(text().length))")
        model.send(.undo); await wait(300)
        check(text().length == afterRecord, "one undo reverts all three runs (len \(text().length) vs \(afterRecord))")
        append("\n첫째\n둘째\n마지막")
        let beforeDel = text().length
        let r2 = await rec.play(Macro(name: "del", steps: [.tool("deleteLine")]), times: 5)
        check(lastLines(2) == ["둘째", ""] && text().length == beforeDel - 3 && (r2?.iterations ?? 0) >= 1,
              "deleteLine on the last line removes its text and leaves the empty last line (runs \(r2?.iterations ?? -1), early stop \(r2?.stoppedEarly ?? false)) → \(lastLines(2))")
        // N번 재생: 0 · 음수 · 10,001 · "10,000" · 글자 → 1 ~ 10,000 으로 클램프. .find 매크로는 두 번째 바퀴 뒤 멈춘다
        model.toggleMacroRecording(); model.searchQuery = "NEEDLE"; model.findNext(); model.toggleMacroRecording()
        check(rec.lastRecorded?.steps == [.find("NEEDLE")], "find macro recorded for the repeat tests (\(rec.lastRecorded?.steps ?? []))")
        var played: [String] = []
        for input in ["0", "-7", "10001", "10,000", "abc"] {
            caretTo(0)
            let n = outputMark()
            rec.repeatText = input
            model.playLastMacroRepeated()
            await wait(600)
            played.append(outputSince(n).last { $0.text.contains("Macro played") || $0.text.contains("매크로 재생") }?.text ?? "(no output)")
        }
        check(played[0].contains("×1") && !played[0].contains("stopped early") && !played[0].contains("조기"), "N=0 → plays once · '\(played[0])'")
        check(played[1].contains("×1"), "N=-7 → plays once · '\(played[1])'")
        func tenThousand(_ s: String) -> Bool { s.contains("10000") || s.contains("10,000") }   // 한국어 서식은 천 단위 쉼표를 붙인다
        check(played[2].contains("×2") && tenThousand(played[2]), "N=10001 → clamped to 10,000, stops after the 2nd NEEDLE · '\(played[2])'")
        check(played[3].contains("×2") && tenThousand(played[3]), "N='10,000' (as the placeholder suggests) → 10,000 · '\(played[3])'")
        check(played[4].contains("×1"), "N='abc' → plays once · '\(played[4])'")
        check(rec.state == .idle, "recorder idle after the repeat runs")
        // 기록 중 재생 거부
        model.toggleMacroRecording()
        let refused = await rec.playLast(times: 1)
        check(refused == nil && rec.isRecording, "play while recording is refused (nil) and recording continues")
        rec.repeatText = "3"; model.playLastMacroRepeated(); await wait(300)
        check(rec.state == .recording, "Play N Times while recording is refused too")
        model.toggleMacroRecording()
        check(rec.state == .idle && rec.lastRecorded?.steps == [.find("NEEDLE")], "stopping an empty recording keeps the previous macro")
        // 깨진 macros.json: 편집기로 열어 깨뜨리고 저장 → 다른 문서로 돌아오면 다시 읽어 오류를 출력에 알린다
        truncate(to: originalLength); model.saveNow(); await wait(700)
        let macroFile = rec.store.fileURL
        model.editMacrosFile(); await wait(800)
        check(model.document.url.resolvingSymlinksInPath().path == macroFile.resolvingSymlinksInPath().path && (text() as String).contains("\"macros\""), "Edit Macros File… opens macros.json in the editor (\(model.document.url.lastPathComponent))")
        model.send(.perform { tv in tv.insertText("{ \"macros\": [ broken", replacementRange: NSRange(location: 0, length: (tv.string as NSString).length)) }); await wait(200)
        model.saveNow(); await wait(700)
        outCount = outputMark()
        model.open(url: sampleURL); await wait(800)
        let loadErr = outputSince(outCount).first { $0.isError && ($0.text.contains("Macros file could not be read") || $0.text.contains("매크로 파일을 읽지 못함")) }
        check(loadErr != nil && rec.store.loadError != nil, "broken macros.json → load error surfaced in Output · '\(loadErr?.text ?? "")'")
        check(model.document.url.lastPathComponent == "sample.md" && text() as String == original, "sample reopened intact after editing macros.json")
        model.saveLastMacro(name: "QA 복구"); rec.store.reload()
        check(rec.store.loadError == nil && rec.store.macros.map(\.name) == ["QA 복구"], "next save overwrites the broken file (\(rec.store.loadError ?? "ok"))")
        if let id = rec.store.macros.first?.id { model.deleteMacro(id: id) }

        // 5. 성능 — 1.3 MB
        mark("5 perf")
        let bigText = (0..<24_000).map { String(format: "2026-01-01 12:%02d INFO 로그 줄 %06d 한글 텍스트 https://example.com/%d\tcol\t%d", $0 % 60, $0, $0, $0) }.joined(separator: "\n")
        let bigTxt = dir.appendingPathComponent("qa-big.txt")
        try? bigText.write(to: bigTxt, atomically: true, encoding: .utf8)
        model.open(url: bigTxt); await wait(1500)
        check(model.document.fileSize > 1_200_000 && model.document.lineIndex.lineCount == 24_000, "big text loaded (\(model.document.fileSize) bytes, \(model.document.lineIndex.lineCount) lines)")
        model.send(.perform { tv in tv.setSelectedRange(NSRange(location: 0, length: (tv.string as NSString).length)) })
        var t = CFAbsoluteTimeGetCurrent()
        model.textTool(.toggleComment)
        let commentMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
        await wait(300)
        check((text() as String).hasPrefix("// 2026-01-01 12:00") && lastLines(1)[0].hasPrefix("// 2026-01-01 12:59") && lines().count == 24_000, "toggle comment on 1.3 MB → every line commented")
        t = CFAbsoluteTimeGetCurrent()
        model.textTool(.toggleComment)
        let uncommentMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
        await wait(300)
        check(text() as String == bigText, "toggle back restores the 1.3 MB text exactly")
        // 목표 300 ms (docs/performance.md 의 '모두 바꾸기 5,000건' 예산은 500 ms). 다른 빌드가 도는 머신에서도 셀프테스트가 흔들리지 않게 검사는 '멈춤 아님(2 s)' 으로 두고 수치는 로그로 남긴다
        log(String(format: "perf toggle comment 1.3 MB (%d lines): comment %.0f ms · uncomment %.0f ms (target 300 ms)", 24_000, commentMs, uncommentMs))
        check(commentMs < 2000 && uncommentMs < 2000, "toggle comment on 1.3 MB is not a hang (\(Int(commentMs)) / \(Int(uncommentMs)) ms; target 300)")
        // JSON: 요소마다 줄을 바꾼 1.3 MB (한 줄짜리 1.3 MB 는 TextKit 2 가 문단 단위로 배치해 캐럿 이동마다 수십 초가 걸린다 — 아래 작은 크기로 따로 잰다)
        func element(_ i: Int) -> String { "{\"id\":\(i),\"name\":\"항목 \(i) 한글 이름\",\"tags\":[\"a\",\"b\",\"c\"],\"score\":\(Double(i) / 7),\"nested\":{\"ok\":true,\"none\":null,\"note\":\"line\\nbreak\"}}" }
        let bigJSON = "[\n" + (0..<12_000).map(element).joined(separator: ",\n") + "\n]"
        let bigJSONURL = dir.appendingPathComponent("qa-big.json")
        try? bigJSON.write(to: bigJSONURL, atomically: true, encoding: .utf8)
        model.open(url: bigJSONURL); await wait(1500)
        check(model.document.fileSize > 1_200_000 && model.document.lineIndex.lineCount == 12_002, "big JSON loaded (\(model.document.fileSize) bytes, \(model.document.lineIndex.lineCount) lines)")
        caretTo(0)
        outCount = outputMark()
        t = CFAbsoluteTimeGetCurrent()
        model.textTool(.formatJSON)
        let formatMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
        await wait(500)
        let formatLog = outputSince(outCount).first { $0.text.contains("JSON") }?.text ?? ""
        let prettyLen = text().length
        check((text() as String).hasPrefix("[\n  {\n    \"id\": 0,\n") && !formatLog.isEmpty && sel() == NSRange(location: 0, length: 0), "format JSON on 1.3 MB → pretty (\(prettyLen) chars), caret at 0 · '\(formatLog)'")
        model.send(.undo); await wait(500)
        check(text() as String == bigJSON, "one undo restores the original 1.3 MB JSON byte for byte")
        log(String(format: "perf format JSON 1.3 MB → %d chars: %.0f ms (target 300 ms)", prettyLen, formatMs))
        check(formatMs < 2000, "format JSON on 1.3 MB is not a hang (\(Int(formatMs)) ms; target 300)")
        // 한 줄로: 결과가 한 줄이 되므로 120 KB 로 잰다 — 1.3 MB 한 줄은 열기만으로 20 s 넘게 멈춘다 (보고서에 기록)
        let smallJSON = "[\n" + (0..<1_000).map(element).joined(separator: ",\n") + "\n]"
        let smallJSONURL = dir.appendingPathComponent("qa-small.json")
        try? smallJSON.write(to: smallJSONURL, atomically: true, encoding: .utf8)
        model.open(url: smallJSONURL); await wait(800)
        caretTo(0)
        t = CFAbsoluteTimeGetCurrent()
        model.textTool(.minifyJSON)
        let minifyMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
        await wait(500)
        check(text() as String == "[" + (0..<1_000).map(element).joined(separator: ",") + "]" && model.document.lineIndex.lineCount <= 2, "minify 120 KB → one line (\(text().length) chars)")
        t = CFAbsoluteTimeGetCurrent()
        model.send(.perform { tv in tv.setSelectedRange(NSRange(location: (tv.string as NSString).length / 2, length: 0)) })
        let caretMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
        log(String(format: "perf minify JSON 120 KB → single line: %.0f ms · caret move inside the %d-char line: %.0f ms", minifyMs, text().length, caretMs))
        model.send(.undo); await wait(300)
        check(text() as String == smallJSON, "undo restores the 120 KB JSON")

        // 원상복구
        model.open(url: sampleURL); await wait(800)
        check(model.document.url.lastPathComponent == "sample.md" && text() as String == original, "qa: sample reopened intact (len \(text().length) vs \(originalLength))")
    }
}
