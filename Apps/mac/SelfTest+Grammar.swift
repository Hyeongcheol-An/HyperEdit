import SwiftUI
import AppKit
import HyperCore

// grammar 셀프테스트: 여러 줄 블록 주석 상태 추적(.swift) → 렌더링 색 → `/*` `*/` 입력에 따른 아래 줄 상태·색 변화 → 타이핑 지연 →
// 마크다운 펜스 언어 중첩·HTML 주석 → 사용자 문법 JSON 쓰기·Reload·.example 열기·주석 토글·이름 갱신 → 메뉴 → 34k 줄 전체 상태 계산 시간.
// 임시 폴더(sample.md 옆)에만 파일을 만들고, 끝에 sample.md 로 돌아간다.
extension SelfTest {
    @MainActor
    static func runGrammar(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { pumpEvent(); try? await Task.sleep(nanoseconds: ms * 1_000_000) }   // 이벤트를 흘려 undo 그룹을 닫는다
        func text() -> NSString { model.document.textStorage.string as NSString }
        func lineText(_ n: Int) -> String {
            let ns = text(); let r = LineIndex(nsString: ns).range(ofLine: n)
            return ns.substring(with: NSIntersectionRange(r, NSRange(location: 0, length: ns.length)))
        }
        func state(_ line: Int) -> LineState { model.document.lineStates.state(ofLine: line) }
        /// 보이는 프래그먼트의 렌더링 속성 색 (레이아웃을 보장한 뒤 읽는다)
        func renderingColor(line: Int, column: Int) -> NSColor? {
            var found: NSColor?
            model.send(.perform { tv in
                guard let lm = tv.textLayoutManager, let cs = tv.textContentStorage else { return }
                let r = LineIndex(nsString: tv.string as NSString).range(ofLine: line)
                guard let loc = cs.location(cs.documentRange.location, offsetBy: r.location + column - 1) else { return }
                lm.ensureLayout(for: NSTextRange(location: loc))
                lm.enumerateRenderingAttributes(from: loc, reverse: false) { _, attrs, range in
                    if range.contains(loc) { found = attrs[.foregroundColor] as? NSColor }
                    return false
                }
            })
            return found
        }
        func describe(_ c: NSColor?) -> String { c.map { $0.description } ?? "nil" }
        let theme = model.themes.current
        let comment = theme.syntaxColor("comment").nsColor
        let keyword = theme.syntaxColor("keyword").nsColor
        let title = theme.syntaxColor("title").nsColor
        let sampleURL = model.document.url
        let dir = sampleURL.deletingLastPathComponent()
        let fm = FileManager.default

        // 1. .swift — 여러 줄 블록 주석: 줄 상태 표와 렌더링 색
        let swiftURL = dir.appendingPathComponent("grammar-test.swift")
        let swiftText = "// header\nlet a = 1\nlet b = 2\nlet c = 3\n/* block starts\nmiddle line\nends here */\nlet d = 4"
        try? swiftText.write(to: swiftURL, atomically: true, encoding: .utf8)
        model.open(url: swiftURL); await wait(900)
        check(model.languageName == "Swift" && model.document.grammar.tracksLineState, "grammar: .swift → \(model.languageName), tracks line state")
        check(model.document.lineStates.lineCount == 8 && model.document.liveLineIndex.lineCount == 8, "grammar: line state table covers 8 lines (\(model.document.lineStates.lineCount))")
        check(state(5) == .normal && state(6) == .blockComment && state(7) == .blockComment && state(8) == .normal,
              "grammar: entering states 5..8 = \(state(5)) \(state(6)) \(state(7)) \(state(8))")
        check(model.document.lineState(atUTF16Offset: LineIndex(nsString: text()).range(ofLine: 6).location) == .blockComment, "grammar: lineState(atUTF16Offset:) for line 6")
        model.jump(toLine: 6); await wait(300)
        check(renderingColor(line: 6, column: 1) == comment, "grammar: middle line of the block comment is rendered in comment color (\(describe(renderingColor(line: 6, column: 1))))")
        check(renderingColor(line: 7, column: 1) == comment, "grammar: closing line is comment color up to */")
        check(renderingColor(line: 8, column: 1) == keyword && renderingColor(line: 2, column: 1) == keyword, "grammar: 'let' before/after the comment keeps keyword color")

        // 2. 2줄 끝에 `/*` 입력 → 3~5줄이 주석 상태로, 보이는 색도 바뀐다. `*/` 입력 → 복귀
        let line2End = NSMaxRange(LineIndex(nsString: text()).range(ofLine: 2))
        model.send(.perform { tv in tv.breakUndoCoalescing(); tv.setSelectedRange(NSRange(location: line2End, length: 0)); tv.insertText(" /*", replacementRange: tv.selectedRange()) })
        await wait(400)
        check(state(3) == .blockComment && state(4) == .blockComment && state(5) == .blockComment && state(6) == .blockComment && state(8) == .normal,
              "grammar: typing /* at the end of line 2 → lines 3-7 enter as comment, line 8 normal (\(state(3)) \(state(5)) \(state(8)))")
        check(renderingColor(line: 3, column: 1) == comment && renderingColor(line: 4, column: 1) == comment,
              "grammar: lines below the new /* are re-rendered as comment (\(describe(renderingColor(line: 3, column: 1))) / \(describe(renderingColor(line: 4, column: 1))))")
        check(renderingColor(line: 8, column: 1) == keyword, "grammar: line 8 after the existing */ keeps keyword color")
        check(model.document.liveLineIndex == LineIndex(nsString: text()), "grammar: live line index matches the text after the edit")
        model.send(.perform { tv in tv.insertText(" */", replacementRange: tv.selectedRange()) }); await wait(400)
        check(lineText(2) == "let a = 1 /* */", "grammar: line 2 is now '\(lineText(2))'")
        check(state(3) == .normal && state(4) == .normal && state(5) == .normal && state(6) == .blockComment && state(8) == .normal,
              "grammar: typing */ restores lines 3-5 (\(state(3)) \(state(4)) \(state(5))), original comment intact (\(state(6)))")
        check(renderingColor(line: 3, column: 1) == keyword && renderingColor(line: 4, column: 1) == keyword, "grammar: lines 3-4 back to keyword color")
        // Enter 로 주석 안에 줄 추가 → 새 줄도 주석 상태, 그 아래는 그대로
        let line6Mid = LineIndex(nsString: text()).range(ofLine: 6).location + 6
        model.send(.perform { tv in tv.breakUndoCoalescing(); tv.setSelectedRange(NSRange(location: line6Mid, length: 0)); tv.insertText("\n", replacementRange: tv.selectedRange()) })
        await wait(300)
        check(model.document.lineStates.lineCount == 9 && state(6) == .blockComment && state(7) == .blockComment && state(8) == .blockComment && state(9) == .normal,
              "grammar: Enter inside the comment → 9 lines, new line is comment state (\(state(7))), line 9 normal (\(state(9)))")
        check(renderingColor(line: 7, column: 1) == comment, "grammar: the split line is rendered as comment")
        model.send(.undo); await wait(300)
        check(model.document.lineStates.lineCount == 8 && state(7) == .blockComment, "grammar: undo → 8 lines, states follow (\(model.document.lineStates.lineCount))")
        check(model.document.lineStates == LineStateIndex(text: text(), lineIndex: LineIndex(nsString: text()), grammar: model.document.grammar),
              "grammar: incremental table equals a full recomputation after typing/undo")

        // 3. 타이핑 지연 (상태 추적이 켜진 .swift 문서, 80타)
        model.goToEnd(); await wait(200)
        let t1 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<80 {
            model.send(.perform { tv in tv.insertText("a", replacementRange: tv.selectedRange()) })
            await wait(1)
        }
        let typingMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000 / 80 - 1
        log(String(format: "grammar: perf typing %.2f ms/keystroke in .swift with line-state tracking (incl. run loop)", typingMs))
        check(typingMs < 16, "grammar: typing latency with line-state tracking under one frame (16 ms)")

        // 4. 마크다운 펜스 + 언어 중첩, HTML 주석
        let mdURL = dir.appendingPathComponent("fence.md")
        try? "# Title\n```swift\nlet x = 1\n```\nplain let word\n<!-- note\nhidden # heading\n-->\n# Real".write(to: mdURL, atomically: true, encoding: .utf8)
        model.open(url: mdURL); await wait(900)
        check(model.languageName == "Markdown" && model.document.grammar.tracksLineState, "grammar: .md tracks fence state")
        check(state(3) == .fence(marker: 0x60, length: 3, language: "swift", inner: .normal) && state(5) == .normal, "grammar: line 3 is inside a ```swift fence (\(state(3)))")
        model.jump(toLine: 1); await wait(300)
        check(renderingColor(line: 3, column: 1) == keyword, "grammar: 'let' inside the swift fence uses Swift keyword color (\(describe(renderingColor(line: 3, column: 1))))")
        check(renderingColor(line: 5, column: 7) == nil, "grammar: 'let' in plain Markdown text has no color")
        check(state(7) == .blockComment && renderingColor(line: 7, column: 1) == comment && renderingColor(line: 7, column: 8) == comment,
              "grammar: HTML comment spans lines — '# heading' inside it is comment, not title (\(state(7)))")
        check(state(9) == .normal && renderingColor(line: 9, column: 1) == title, "grammar: heading after the comment is title color")

        // 5. 사용자 문법: JSON 을 문법 폴더(ephemeral 임시 폴더)에 쓰고 Reload → .example 열기 → 이름·키워드 색·주석 상태·주석 토글 → 이름 바꿔 Reload → 상태바 갱신
        let gdir = UserGrammarStore.launchDirectory
        check(gdir.path.contains("hyperedit-ephemeral"), "grammar: self-test uses an ephemeral grammars folder (\(gdir.lastPathComponent))")
        check(fm.fileExists(atPath: gdir.appendingPathComponent("example.json").path) && fm.fileExists(atPath: gdir.appendingPathComponent("README.md").path),
              "grammar: first load created example.json and README.md")
        try? fm.createDirectory(at: gdir, withIntermediateDirectories: true)
        let userJSON = gdir.appendingPathComponent("selftest.json")
        let brokenJSON = gdir.appendingPathComponent("zz-broken.json")
        try? "{ \"name\": \"SelfTestLang\", \"extensions\": [\"example\"], \"lineComments\": [\"#\"], \"blockComment\": [\"/*\", \"*/\"], \"keywords\": [\"fn\", \"let\"], \"builtins\": [\"print\"] }"
            .write(to: userJSON, atomically: true, encoding: .utf8)
        try? "{ \"name\": \"Broken\", \"extensions\": [\"zz\"] ".write(to: brokenJSON, atomically: true, encoding: .utf8)
        // 출력 로그는 500줄로 잘리므로(이 시점에는 이미 가득) 개수 기준이 아니라 마지막 몇 줄을 본다 (리로드는 건너뛴 파일 1줄 + 결과 1줄)
        model.reloadGrammars(); await wait(300)
        var recent = model.output.suffix(4).map(\.text)
        check(recent.contains { ($0.contains("Grammars reloaded") || $0.contains("문법 다시 읽음")) && $0.contains("2") }, "grammar: reload logged with count 2 (example + selftest): \(recent)")
        check(recent.contains { $0.contains("zz-broken.json") }, "grammar: broken grammar file is reported by name in the output log")
        check(UserGrammarStore.shared.grammars.map(\.name).contains("SelfTestLang"), "grammar: store lists SelfTestLang (\(UserGrammarStore.shared.grammars.map(\.name)))")
        let exURL = dir.appendingPathComponent("test.example")
        try? "fn main\n/* a\nb */ let x = print\n# c".write(to: exURL, atomically: true, encoding: .utf8)
        model.open(url: exURL); await wait(900)
        check(model.languageName == "SelfTestLang", "grammar: .example → status bar language '\(model.languageName)'")
        model.jump(toLine: 1); await wait(300)
        check(renderingColor(line: 1, column: 1) == keyword, "grammar: user keyword 'fn' colored as keyword (\(describe(renderingColor(line: 1, column: 1))))")
        check(state(3) == .blockComment && renderingColor(line: 3, column: 1) == comment, "grammar: user blockComment spans lines (\(state(3)))")
        check(renderingColor(line: 3, column: 6) == keyword, "grammar: 'let' after the closing */ is keyword color (\(describe(renderingColor(line: 3, column: 6))))")
        check(renderingColor(line: 4, column: 1) == comment, "grammar: user line comment '#' is comment color")
        check(CommentRegistry.syntax(for: exURL).line == "#", "grammar: comment toggle uses the user grammar's line comment")
        model.jump(toLine: 1); await wait(200)
        model.textTool(.toggleComment); await wait(300)
        check(lineText(1) == "# fn main", "grammar: ⌘/ on a user-grammar file → '\(lineText(1))'")
        model.textTool(.toggleComment); await wait(300)
        check(lineText(1) == "fn main", "grammar: ⌘/ again → '\(lineText(1))'")
        // 열린 채로 이름을 바꿔 Reload → 문서 문법·상태바 이름 갱신
        try? "{ \"name\": \"Renamed\", \"extensions\": [\"example\"], \"keywords\": [\"fn\"] }".write(to: userJSON, atomically: true, encoding: .utf8)
        model.reloadGrammars(); await wait(300)
        check(model.languageName == "Renamed" && model.document.grammar.name == "Renamed", "grammar: reload refreshes the open document's grammar (\(model.languageName))")
        check(!model.document.grammar.tracksLineState && model.document.lineStates.isEmpty, "grammar: grammar without block comments stops tracking (table cleared)")
        check(renderingColor(line: 3, column: 1) != comment, "grammar: after reload the old block comment is no longer colored as comment")
        // 사용자 파일 제거 → 내장 example.json 의 'Example' 로 돌아간다
        try? fm.removeItem(at: userJSON); try? fm.removeItem(at: brokenJSON)
        model.reloadGrammars(); await wait(300)
        recent = model.output.suffix(2).map(\.text)
        check(model.languageName == "Example" && !recent.contains { $0.contains("zz-broken") }, "grammar: removing the file falls back to example.json's 'Example' (\(model.languageName)), no stale error")

        // 6. 메뉴 항목 (파일 메뉴, 현재 UI 언어의 제목)
        if let menu = NSApp.mainMenu {
            var titles: [String] = []
            func walk(_ m: NSMenu) { for it in m.items { titles.append(it.title); if let s = it.submenu { walk(s) } } }
            walk(menu)
            let hasOpen = titles.contains { $0.contains("Grammars Folder") || $0.contains("문법 폴더") }
            let hasReload = titles.contains { $0.contains("Reload Grammars") || $0.contains("문법 다시") }
            check(hasOpen && hasReload, "grammar: menu has 'Open Grammars Folder…' and 'Reload Grammars'")
        }

        // 7. 34k 줄 문서 전체 상태 계산 시간 (Release: 수 ms)
        var big = ""
        big.reserveCapacity(1_500_000)
        for i in 0..<34_000 {
            switch i % 6 {
            case 0: big += "/* comment \(i)\n"
            case 1: big += " * inside \"quoted\" /* nested\n"
            case 2: big += " */ let v\(i) = f(\"s\", 0x1F) // tail\n"
            default: big += "    guard let url = URL(string: \"https://example.com/\(i)\") else { return nil } // 주석 \(i)\n"
            }
        }
        let bigNS = big as NSString
        let li = LineIndex(nsString: bigNS)
        let t2 = CFAbsoluteTimeGetCurrent()
        let idx = LineStateIndex(text: bigNS, lineIndex: li, grammar: CodeGrammar(language: .swift))
        let fullMs = (CFAbsoluteTimeGetCurrent() - t2) * 1000
        log(String(format: "grammar: perf full line-state computation %d lines · %d chars · %.1f ms", li.lineCount, bigNS.length, fullMs))
        check(idx.lineCount == li.lineCount && fullMs < 150, "grammar: 34k-line full state computation under 150 ms (\(String(format: "%.1f", fullMs)) ms)")

        // 8. 원상복구: sample.md 로
        model.open(url: sampleURL); await wait(800)
        check(model.document.url.lastPathComponent == "sample.md" && model.languageName == "Markdown", "grammar: back on sample.md")
    }
}
