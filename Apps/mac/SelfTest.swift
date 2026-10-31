import SwiftUI
import AppKit
import HyperCore

/// 개발용 셀프테스트: `--selftest [--selftest-out <txt>] [--quit]`.
/// 임시 폴더에 자체 샘플 파일을 만들어 그 위에서만 편집·저장하므로 사용자 문서는 건드리지 않는다.
/// `--selftest-open` 은 파일 전환 성능 벤치 — 큰 파일 사본을 `--file` 로 준 폴더에서만 실행할 것(문서를 수정함).
enum SelfTest {
    static var enabled: Bool { CommandLine.arguments.contains("--selftest") }
    static var openEnabled: Bool { CommandLine.arguments.contains("--selftest-open") }

    /// 줄 번호가 검사에 쓰이므로 순서를 바꾸지 말 것
    static let sample = """
    # HyperEdit self-test sample

    ## 2026-10-30 (금) 09:30
    NEEDLE first
    - NEEDLE second
    third line

    [Title] bracket heading
    2022-01-06 01:21:02 INFO log line
    ## Real heading
    가. 한글 항목
    1) numbered item
    tail
    """

    static var outPath: String? {
        let a = CommandLine.arguments
        guard let i = a.firstIndex(of: "--selftest-out"), i + 1 < a.count else { return nil }
        return a[i + 1]
    }

    /// 사이드바 파일 전환 성능: 작은 .md ↔ 큰 문서를 번갈아 열며 소요 시간 기록 (벤치 전용, 사본 폴더에서만)
    @MainActor
    static func runOpen(model: AppModel) async {
        var lines: [String] = []
        func log(_ s: String) { lines.append(s); Perf.log("[open] " + s); model.log("[selftest-open] " + s) }
        func wait(_ ms: UInt64) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }
        func nextTurn() async { await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } } }
        func afterFrame() async { await withCheckedContinuation { c in DispatchQueue.main.asyncAfter(deadline: .now() + 0.001) { c.resume() } } }
        await wait(1500)
        let big = model.document.url
        let dir = big.deletingLastPathComponent()
        let smalls = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "md" && $0 != big }.sorted { $0.path < $1.path }
        guard let small = smalls.first else { log("no small .md file next to the document"); return }
        log("start · big lines=\(model.document.lineIndex.lineCount) small=\(small.lastPathComponent)")
        for round in 1...3 {
            for target in [small, big] {
                let t = CFAbsoluteTimeGetCurrent()
                model.open(url: target)
                let sync = (CFAbsoluteTimeGetCurrent() - t) * 1000
                await nextTurn()
                let turn = (CFAbsoluteTimeGetCurrent() - t) * 1000
                await afterFrame()
                let settled = (CFAbsoluteTimeGetCurrent() - t) * 1000
                log(String(format: "round %d open %@ · sync %.0f ms · next turn %.0f ms · after frame %.0f ms", round, target.lastPathComponent, sync, turn, settled))
                await wait(2500)
            }
        }
        // 저장 정확성: dirty 상태로 전환 → 이전 파일이 백그라운드 저장되고, 새 파일 상태는 그 저장 콜백에 오염되지 않아야 함
        var failures = 0
        func check(_ cond: Bool, _ s: String) { if !cond { failures += 1 }; log((cond ? "PASS " : "FAIL ") + s) }
        let marker = "HE-SWITCH-TEST-\(Int(Date().timeIntervalSince1970))"
        let bigSizeBefore = ((try? FileManager.default.attributesOfItem(atPath: big.path))?[.size] as? Int) ?? -1
        model.open(url: small); await wait(400)
        model.goToEnd(); await wait(200)
        model.send(.perform { tv in tv.insertText("\n" + marker, replacementRange: tv.selectedRange()) }); await wait(200)
        check(model.document.isDirty, "typing marks small dirty")
        model.open(url: big)
        await wait(1200)
        let smallDisk = (try? String(contentsOf: small, encoding: .utf8)) ?? ""
        let bigDisk = (try? String(contentsOf: big, encoding: .utf8)) ?? ""
        check(smallDisk.contains(marker), "switch-while-dirty saved previous file (marker on disk)")
        check(!bigDisk.contains(marker), "big file untouched by small's save")
        check(model.document.fileSize == bigSizeBefore, "big state intact after stale save callback (fileSize \(model.document.fileSize) vs \(bigSizeBefore))")
        check(model.document.url.path == big.resolvingSymlinksInPath().path && !model.document.isDirty, "current doc is big and clean")
        model.open(url: small); await wait(400)
        model.send(.perform { tv in
            let ns = tv.string as NSString
            let r = ns.range(of: "\n" + marker)
            if r.location != NSNotFound { tv.insertText("", replacementRange: r) }
        }); await wait(200)
        model.saveNow(); await wait(800)
        let smallAfter = (try? String(contentsOf: small, encoding: .utf8)) ?? ""
        check(!smallAfter.contains(marker), "marker removed and saved")
        log(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
        log("done")
        if let p = outPath { try? lines.joined(separator: "\n").write(toFile: p, atomically: true, encoding: .utf8) }
        if CommandLine.arguments.contains("--quit") { NSApp.terminate(nil) }
    }

    @MainActor
    static func run(model: AppModel) async {
        var lines: [String] = []
        var failures = 0
        func log(_ s: String) { lines.append(s); model.log("[selftest] " + s) }
        func check(_ cond: Bool, _ s: String) { if !cond { failures += 1 }; log((cond ? "PASS " : "FAIL ") + s) }
        func text() -> NSString { model.document.textStorage.string as NSString }
        func lineText(_ n: Int) -> String {
            let ns = text(); let idx = LineIndex(text: ns as String); let r = idx.range(ofLine: n)
            return ns.substring(with: NSIntersectionRange(r, NSRange(location: 0, length: ns.length)))
        }
        func count(_ needle: String) -> Int { (text() as String).components(separatedBy: needle).count - 1 }
        func wait(_ ms: UInt64) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }

        // 0. 임시 폴더에 샘플 두 개 생성 후 열기 — 사용자 문서는 건드리지 않음
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hyperedit-selftest-\(UUID().uuidString.prefix(8))", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try sample.write(to: dir.appendingPathComponent("sample.md"), atomically: true, encoding: .utf8)
            try "# Other\nHyperEdit mention in another file\n".write(to: dir.appendingPathComponent("other.md"), atomically: true, encoding: .utf8)
        } catch { log("FAIL cannot create sample dir: \(error)"); return }
        await wait(800)
        model.open(url: dir.appendingPathComponent("sample.md"))
        await wait(800)
        log("sample loaded lines=\(model.document.lineIndex.lineCount) at \(dir.path)")
        check(model.document.lineIndex.lineCount == 13, "sample has 13 lines")

        // 1. 검색 → 이동 → 북마크
        model.searchQuery = "NEEDLE"; model.runSearch(); await wait(700)
        check(model.searchHits.count == 2, "search 'NEEDLE' hits=\(model.searchHits.count)")
        if let h = model.searchHits.first { model.jump(to: h) }; await wait(400)
        check(model.caretLine == 4, "jump → line \(model.caretLine)")
        model.toggleBookmarkAtCaret()
        check(model.bookmarks.bookmarks.map(\.line) == [4], "bookmark \(model.bookmarks.bookmarks.map(\.line))")
        model.toggleBookmarkAtCaret()
        check(model.bookmarks.bookmarks.isEmpty, "bookmark toggled off")

        // 2. ⌘D 멀티 커서: NEEDLE 두 개 선택 → 입력으로 치환 → ⌘Z 복구
        model.send(.addNextOccurrence); await wait(300)
        check(model.multiCaretCount == 2, "⌘D multi carets=\(model.multiCaretCount)")
        model.send(.perform { tv in tv.insertText("NEEDLE!", replacementRange: tv.selectedRange()) }); await wait(300)
        check(count("NEEDLE!") == 2, "multi insert → 'NEEDLE!' ×\(count("NEEDLE!"))")
        model.send(.undo); await wait(300)
        check(count("NEEDLE!") == 0 && count("NEEDLE") == 2, "undo restores (NEEDLE! \(count("NEEDLE!")), NEEDLE \(count("NEEDLE")))")
        model.send(.perform { tv in tv.clearMulti() })

        // 3. 열 모드: 4~5줄 앞에 '> ' 삽입 → Backspace 2번으로 제거 → 숫자 채우기 → undo
        model.jump(toLine: 4); await wait(300)
        model.columnMode = true
        model.send(.perform { tv in tv.extendBlock(dx: 0, dy: 1) }); await wait(200)
        check(model.multiCaretCount == 2 && model.columnBlockActive, "column block lines=\(model.multiCaretCount) active=\(model.columnBlockActive)")
        model.send(.perform { tv in tv.insertText("> ", replacementRange: tv.selectedRange()) }); await wait(300)
        check(lineText(4).hasPrefix("> NEEDLE") && lineText(5).hasPrefix("> - NEEDLE"), "column insert: '\(lineText(4).prefix(12))' / '\(lineText(5).prefix(12))'")
        model.send(.perform { tv in tv.doCommand(by: #selector(NSResponder.deleteBackward(_:))); tv.doCommand(by: #selector(NSResponder.deleteBackward(_:))) }); await wait(300)
        check(lineText(4).hasPrefix("NEEDLE") && lineText(5).hasPrefix("- NEEDLE"), "column backspace ×2: '\(lineText(4).prefix(8))' / '\(lineText(5).prefix(8))'")
        model.send(.perform { tv in tv.extendBlock(dx: 0, dy: 1) }); await wait(200)
        model.insertNumberStart = "1"; model.insertNumberStep = "1"; model.insertColumnNumbers(); await wait(300)
        check(lineText(4).hasPrefix("1") && lineText(5).hasPrefix("2") && lineText(6).hasPrefix("3"), "insert numbers: \(lineText(4).prefix(6)) | \(lineText(5).prefix(6)) | \(lineText(6).prefix(6))")
        model.send(.undo); await wait(300)
        check(lineText(4).hasPrefix("NEEDLE"), "undo numbers → '\(lineText(4).prefix(6))'")
        model.columnMode = false
        check(model.multiCaretCount <= 1, "column mode off collapses (carets=\(model.multiCaretCount))")

        // 4. 바꾸기: 모두 바꾸기 → ⌘Z 한 번으로 전부 복구, 정규식 템플릿
        model.searchQuery = "NEEDLE"; model.replaceText = "NEEDLE2"; model.replaceAll(); await wait(600)
        check(count("NEEDLE2") == 2, "replace all → NEEDLE2 ×\(count("NEEDLE2"))")
        model.send(.undo); await wait(300)
        check(count("NEEDLE2") == 0 && count("NEEDLE") == 2, "single undo reverts replace all (NEEDLE2 \(count("NEEDLE2")))")
        model.searchOptions.regex = true; model.searchQuery = "(NEE)(DLE)"; model.replaceText = "$2$1"; await wait(500)
        model.replaceAll(); await wait(600)
        check(count("DLENEE") == 2, "regex template replace → DLENEE ×\(count("DLENEE"))")
        model.send(.undo); await wait(300)
        model.searchOptions.regex = false; model.searchQuery = "NEEDLE"; await wait(400)

        // 5. 파일에서 찾기 (임시 폴더, *.md)
        model.fileSearchDirectory = dir
        model.fileMask = "*.md"; model.searchQuery = "HyperEdit"; model.runFindInFiles(); await wait(1200)
        let files = Set(model.fileHits.map(\.fileName))
        check(files == ["sample.md", "other.md"], "find in files: \(model.fileSearchSummary) files=\(files.sorted())")

        // 6. 아웃라인 / 타임라인
        model.rescanStructure(); await wait(1200)
        let titles = model.outline.map(\.title)
        check(titles.contains("[Title]") && titles.contains("Real heading") && titles.contains { $0.hasPrefix("가. ") } && titles.contains { $0.hasPrefix("1) ") },
              "outline items=\(titles)")
        check(!titles.contains { $0.contains("2026-10-30") }, "timestamp excluded from outline")
        check(model.timeline.count == 2 && model.timeline.first?.precise == true && model.timeline.last?.line == 9,
              "timeline items=\(model.timeline.map { "\($0.dateLabel)@L\($0.line)" })")

        // 7. 타임스탬프 + 저장
        model.goToEnd(); await wait(300); model.insertTimestamp(); await wait(500)
        let ns = text()
        check(Timestamp.headingRegex.firstMatch(in: ns as String, options: [], range: NSRange(location: max(0, ns.length - 60), length: min(60, ns.length))) != nil, "timestamp at end")
        model.saveNow(); await wait(700)
        check(!model.document.isDirty && model.document.errorMessage == nil, "saved status='\(model.document.status)'")
        let disk = (try? String(contentsOf: dir.appendingPathComponent("sample.md"), encoding: .utf8)) ?? ""
        check(disk.contains("tail\n") && Timestamp.headingRegex.firstMatch(in: disk, options: [], range: NSRange(location: 0, length: (disk as NSString).length)) != nil, "disk content has tail + timestamp")

        // 8. 성능: 타이핑 80타 지연(런루프 포함)
        model.goToEnd(); await wait(300)
        let t1 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<80 {
            model.send(.perform { tv in tv.insertText("a", replacementRange: tv.selectedRange()) })
            await wait(1)
        }
        let typingMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000 / 80 - 1
        log(String(format: "perf typing %.2f ms/keystroke (incl. run loop)", typingMs))
        check(typingMs < 16, "typing latency under one frame (16 ms)")
        model.send(.perform { tv in
            let ns = tv.string as NSString
            tv.insertText("", replacementRange: NSRange(location: ns.length - 80, length: 80))
        }); await wait(200)

        // 9. 북마크 줄 추적: 10줄 북마크 → 위에 2줄 삽입 → 12 → undo → 10 → redo → 12 → undo → 10 → 줄 삭제 → 제거
        func bm() -> [Int] { model.bookmarks.bookmarks.map(\.line) }
        model.jump(toLine: 10); await wait(300)
        model.toggleBookmarkAtCaret()
        check(bm() == [10] && lineText(10) == "## Real heading", "bookmark line 10 '\(lineText(10))'")
        // 앞 단계의 프로그램적 insertText 들이 한 '입력' undo 그룹으로 합쳐져 있으므로 끊고 시작 (실제 타이핑은 캐럿 이동이 끊어 준다)
        model.send(.perform { tv in tv.breakUndoCoalescing(); tv.insertText("x\ny\n", replacementRange: NSRange(location: 0, length: 0)) }); await wait(300)
        check(bm() == [12] && lineText(12) == "## Real heading", "insert 2 lines above → bookmark \(bm())")
        model.send(.undo); await wait(300)
        check(bm() == [10] && lineText(10) == "## Real heading", "undo → bookmark \(bm()) line10='\(lineText(10))'")
        model.send(.redo); await wait(300)
        check(bm() == [12] && lineText(12) == "## Real heading", "redo → bookmark \(bm())")
        model.send(.undo); await wait(400)
        check(bm() == [10] && lineText(10) == "## Real heading", "undo again → bookmark \(bm())")
        model.jump(toLine: 10); await wait(300)
        model.textTool(.deleteLine); await wait(300)
        check(bm().isEmpty && lineText(10) == "가. 한글 항목", "delete bookmarked line → bookmarks \(bm()), line 10 '\(lineText(10))'")
        model.send(.undo); await wait(400)
        // 줄은 돌아오지만 북마크 제거는 undo 대상이 아니다. (NSTextView 는 redo 뒤 프로그램적 입력 그룹을 다시 합치기도 해 전체 줄 수는 고정하지 않는다)
        check(lineText(10) == "## Real heading" && bm().isEmpty, "undo delete → line10='\(lineText(10))' bookmarks \(bm())")

        // 10. 즉석 계산: 줄 끝에 ⇒ 결과, 다시 실행해도 같음, 수식이 아니면 그대로 두고 출력에 알림
        func lastLine() -> String { (text() as String).components(separatedBy: "\n").last ?? "" }
        model.goToEnd(); await wait(300)
        model.send(.perform { tv in tv.insertText("\n3+0.5+0.25", replacementRange: tv.selectedRange()) }); await wait(200)
        model.textTool(.calculate); await wait(300)
        check(lastLine() == "3+0.5+0.25 ⇒ 3.75", "calculate → '\(lastLine())'")
        model.textTool(.calculate); await wait(300)
        check(lastLine() == "3+0.5+0.25 ⇒ 3.75", "calculate again → '\(lastLine())'")
        model.send(.perform { tv in tv.insertText("\ntotal = 2*(3+4)", replacementRange: tv.selectedRange()) }); await wait(200)
        model.textTool(.calculate); await wait(300)
        check(lastLine() == "total = 2*(3+4) ⇒ 14", "calculate after '=' → '\(lastLine())'")
        model.send(.perform { tv in tv.insertText("\nhello world", replacementRange: tv.selectedRange()) }); await wait(200)
        let outputCount = model.output.count
        model.textTool(.calculate); await wait(300)
        let lastOut = model.output.last?.text ?? ""
        check(lastLine() == "hello world" && model.output.count == outputCount + 1 && (lastOut.contains("Not a valid expression") || lastOut.contains("유효한 수식")),
              "invalid expression untouched, output '\(lastOut)'")

        // 11. 열 맞춤: 한글 셀이 있는 탭 표 3줄 → 열이 같은 표시 열에서 시작
        model.send(.perform { tv in tv.insertText("\nname\tqty\tnote\n홍길동\t3\tok\nab\t12345\tx", replacementRange: tv.selectedRange()) }); await wait(200)
        model.send(.perform { tv in tv.setSelectedRange(NSRange(location: (tv.string as NSString).length - 3, length: 0)) })   // 선택 없이 마지막 줄에서
        model.textTool(.alignColumns); await wait(300)
        let table = Array((text() as String).components(separatedBy: "\n").suffix(3))
        func start(_ line: String, _ cell: String) -> Int {
            guard let r = line.range(of: cell) else { return -1 }
            return TextTools.displayWidth(String(line[..<r.lowerBound]))
        }
        let col2 = Set([start(table[0], "qty"), start(table[1], "3"), start(table[2], "12345")])
        let col3 = Set([start(table[0], "note"), start(table[1], "ok"), start(table[2], "x")])
        check(table == ["name    qty    note", "홍길동  3      ok", "ab      12345  x"] && col2 == [8] && col3 == [15],
              "align columns → \(table) starts \(col2.sorted()) / \(col3.sorted())")
        check(!(text() as String).contains("\tqty"), "tabs replaced by padding")

        // 화면용 상태: 타임라인 탭 + 찾기 결과 + 열 블록
        model.searchQuery = "NEEDLE"; model.runSearch()
        model.showTimeline()
        model.jump(toLine: 4); await wait(300)
        model.columnMode = true
        model.send(.perform { tv in tv.extendBlock(dx: 4, dy: 1) })

        log(failures == 0 ? "ALL PASS" : "FAILURES: \(failures)")
        if let p = outPath { try? lines.joined(separator: "\n").write(toFile: p, atomically: true, encoding: .utf8) }
        if CommandLine.arguments.contains("--quit") { await wait(300); NSApp.terminate(nil) }
    }
}
