import XCTest
@testable import HyperCore

/// 여러 줄 상태 추적: 블록 주석·여러 줄 문자열·마크다운 펜스(언어 중첩)·HTML 주석, 그리고 `LineStateIndex` 의 전체 계산 == 증분 갱신.
private func describe(_ tokens: [Token], in text: String) -> [String] {
    let ns = text as NSString
    return tokens.map { "\(ns.substring(with: $0.range)):\($0.kind.rawValue)" }
}

/// 줄마다 "토큰들" 과 줄 끝 상태 (토큰 범위는 본문 전체 기준 절대 오프셋)
private func lines(_ g: any LanguageGrammar, _ text: String) -> [(tokens: [String], exit: LineState)] {
    g.scanLines(in: text).map { r in (describe(r.tokens, in: text), r.exiting) }
}

final class LineStateCodeTests: XCTestCase {
    let swift = CodeGrammar(language: .swift)

    func testBlockCommentThreeLinesMiddleLineIsAllComment() {
        let text = "let a = 1 /* open\nmiddle line here\nclosed */ let b = 2"
        let r = lines(swift, text)
        XCTAssertEqual(r[0].tokens, ["let:keyword", "=:operator", "1:number", "/* open:comment"])
        XCTAssertEqual(r[0].exit, .blockComment)
        XCTAssertEqual(r[1].tokens, ["middle line here:comment"])
        XCTAssertEqual(r[1].exit, .blockComment)
        XCTAssertEqual(r[2].tokens, ["closed */:comment", "let:keyword", "=:operator", "2:number"])
        XCTAssertEqual(r[2].exit, .normal)
        // 상태 없이 토큰화하면(이전 동작) 가운데 줄은 평문이다
        XCTAssertEqual(describe(swift.tokens(in: "middle line here"), in: "middle line here"), [])
    }

    func testOpenAndCloseOnSameLineStaysNormal() {
        let r = lines(swift, "a /* x */ b /* y */\nlet c")
        XCTAssertEqual(r[0].tokens, ["/* x */:comment", "/* y */:comment"])
        XCTAssertEqual(r[0].exit, .normal)
        XCTAssertEqual(r[1].tokens, ["let:keyword"])
        // 열고 닫고 다시 열면 열린 채로
        XCTAssertEqual(lines(swift, "/* a */ /* b").last?.exit, .blockComment)
        // 빈 줄은 상태를 유지한다
        XCTAssertEqual(lines(swift, "/* a\n\nb */").map(\.exit), [.blockComment, .blockComment, .normal])
    }

    func testCommentCannotStartInsideStringAndStringCannotStartInsideComment() {
        XCTAssertEqual(lines(swift, "let s = \"/* not a comment\"\nlet t = 1").map(\.exit), [.normal, .normal])
        let r = lines(swift, "/* \"quote inside comment\nstill */ x")
        XCTAssertEqual(r.map(\.exit), [.blockComment, .normal])
        XCTAssertEqual(r[1].tokens.first, "still */:comment")
    }

    func testPythonTripleQuotedStringSpansLines() {
        let py = CodeGrammar(language: .python)
        let r = lines(py, "doc = \"\"\"first\nsecond # not a comment\nthird\"\"\"  # comment\nx = '''a\nb'''")
        XCTAssertEqual(r[0].tokens, ["=:operator", "\"\"\"first:string"])
        XCTAssertEqual(r[0].exit, .string(1))
        XCTAssertEqual(r[1].tokens, ["second # not a comment:string"])
        XCTAssertEqual(r[1].exit, .string(1))
        XCTAssertEqual(r[2].tokens, ["third\"\"\":string", "# comment:comment"])
        XCTAssertEqual(r[2].exit, .normal)
        XCTAssertEqual(r[3].exit, .string(2))
        XCTAssertEqual(r[4].tokens, ["b''':string"])
        XCTAssertEqual(r[4].exit, .normal)
        // 접두 f"""…""" 와 한 줄 docstring 은 그대로
        XCTAssertEqual(lines(py, "s = f\"\"\"{a}\nb\"\"\"").map(\.exit), [.string(1), .normal])
        XCTAssertEqual(lines(py, "\"\"\"Docstring on one line.\"\"\"")[0].tokens, ["\"\"\"Docstring on one line.\"\"\":string"])
        XCTAssertEqual(lines(py, "x = \"\" + ''")[0].tokens, ["=:operator", "\"\":string", "+:operator", "'':string"])
    }

    func testJavaScriptTemplateAndGoRawString() {
        let js = CodeGrammar(language: .javascript)
        let r = lines(js, "const q = `select *\n  from t where x = ${y}` // done\nlet z = 'single'")
        XCTAssertEqual(r[0].exit, .string(1))
        XCTAssertEqual(r[1].tokens, ["  from t where x = ${y}`:string", "// done:comment"])
        XCTAssertEqual(r[1].exit, .normal)
        XCTAssertEqual(r[2].exit, .normal)
        XCTAssertEqual(lines(js, "a = `x\\`y`").map(\.exit), [.normal], "이스케이프된 백틱은 닫지 않는다")
        let go = CodeGrammar(language: .go)
        XCTAssertEqual(lines(go, "s := `raw\nline` + \"x\"").map(\.exit), [.string(1), .normal])
        // 셸의 백틱은 한 줄 (여러 줄 구분자가 아님)
        XCTAssertEqual(lines(CodeGrammar(language: .shell), "x=`cmd").map(\.exit), [.normal])
    }

    func testRustRawStrings() {
        let rs = CodeGrammar(language: .rust)
        let r = lines(rs, "let s = r#\"line \"one\"\nstill \"# ; let t = r\"a\nb\" br\"x\"")
        XCTAssertEqual(r[0].tokens, ["let:keyword", "=:operator", "r#\"line \"one\":string"])
        XCTAssertEqual(r[0].exit, .string(0x81))
        XCTAssertEqual(r[1].tokens, ["still \"#:string", ";:punctuation", "let:keyword", "=:operator", "r\"a:string"])
        XCTAssertEqual(r[1].exit, .string(0x80))
        XCTAssertEqual(r[2].tokens, ["b\":string", "br\"x\":string"])
        XCTAssertEqual(r[2].exit, .normal)
        XCTAssertEqual(lines(rs, "let s = r##\"a\"# b\"##;").map(\.exit), [.normal], "# 개수가 모자라면 닫히지 않는다")
        XCTAssertEqual(lines(rs, "let s = \"plain unterminated").map(\.exit), [.normal], "일반 문자열은 한 줄")
    }

    func testHTMLAndXMLCommentsSpanLines() {
        let html = CodeGrammar(language: .html)
        let r = lines(html, "<p>a</p><!-- start\n<b>not a tag</b>\nend --><i>x</i>")
        XCTAssertEqual(r[0].exit, .blockComment)
        XCTAssertEqual(r[1].tokens, ["<b>not a tag</b>:comment"])
        XCTAssertEqual(r[1].exit, .blockComment)
        XCTAssertEqual(r[2].tokens, ["end -->:comment", "<:punctuation", "i:tag", ">:punctuation", "</:punctuation", "i:tag", ">:punctuation"])
        XCTAssertEqual(r[2].exit, .normal)
        XCTAssertEqual(lines(CodeGrammar(language: .xml), "<!-- a -- >\n-->").map(\.exit), [.blockComment, .normal])
    }

    func testCSSAndSQLBlockComments() {
        let css = CodeGrammar(language: .css)
        let r = lines(css, "a { color: red; /* note\n  more */ margin: 0 }")
        XCTAssertEqual(r[0].exit, .blockComment)
        XCTAssertEqual(r[1].tokens.first, "  more */:comment")
        XCTAssertEqual(r[1].exit, .normal)
        XCTAssertEqual(lines(CodeGrammar(language: .sql), "select 1 /* x\ny */ from t").map(\.exit), [.blockComment, .normal])
    }

    func testStatelessLanguagesDoNotTrack() {
        XCTAssertFalse(CodeGrammar(language: .yaml).tracksLineState)
        XCTAssertFalse(CodeGrammar(language: .toml).tracksLineState)
        XCTAssertFalse(CodeGrammar(language: .shell).tracksLineState)
        XCTAssertFalse(CodeGrammar(language: .ruby).tracksLineState)
        XCTAssertFalse(PlainNotesGrammar(markdown: false).tracksLineState)
        XCTAssertTrue(CodeGrammar(language: .swift).tracksLineState)
        XCTAssertTrue(CodeGrammar(language: .html).tracksLineState)
        XCTAssertTrue(PlainNotesGrammar(markdown: true).tracksLineState)
    }

    func testStaleStateFromAnotherGrammarIsHarmless() {
        // 문법이 바뀐 직후 낡은 상태가 들어와도 보통 줄로 스캔한다 (크래시·빈 결과 없음)
        let yaml = CodeGrammar(language: .yaml)
        let line = Array("key: value".utf16)
        line.withUnsafeBufferPointer { buf in
            XCTAssertEqual(yaml.scanLine(buf, base: 0, entering: .blockComment).exiting, .normal)
            XCTAssertEqual(yaml.scanLine(buf, base: 0, entering: .string(7)).exiting, .normal)
            XCTAssertEqual(swift.scanLine(buf, base: 0, entering: .string(9)).exiting, .normal)
            XCTAssertEqual(swift.scanLine(buf, base: 0, entering: .fence(marker: 0x60, length: 3, language: nil, inner: .normal)).exiting, .normal)
        }
    }

    /// `exitState`(토큰 없이) 와 `scanLine(...).exiting` 이 항상 같아야 한다 — 상태 표와 렌더러가 같은 결과를 봐야 하므로
    func testExitStateMatchesScanLine() {
        let corpus = [
            "let a = 1 /* open", "middle", "closed */ x /* again", "*/ \"str\" /* \"", "x = f\"\"\"{a}", "b\"\"\" # c", "r#\"raw", "\"# done",
            "<div><!-- c", "--> <b>", "a#b /* not", "`tpl ${x}", "end` + 'q'", "#if DEBUG /* c */", "'a' 'b /* c", "@\"x /* y\" z",
            "#[cfg(feature = \"x /*\")] /* k", "${X:-\"/*\"} ok", "- url: https://x.io/#frag", "```swift", "let x = \"\"\"", "   ~~~", "<!-- md",
            "`<!-- inline`", "**<!-- bold** still", "# <!-- heading", "> quote <!--",
        ]
        let grammars: [any LanguageGrammar] = [swift, CodeGrammar(language: .python), CodeGrammar(language: .rust), CodeGrammar(language: .javascript),
                                                CodeGrammar(language: .html), CodeGrammar(language: .c), CodeGrammar(language: .shell), CodeGrammar(language: .objc),
                                                PlainNotesGrammar(markdown: true), PlainNotesGrammar(markdown: false)]
        let starts: [LineState] = [.normal, .blockComment, .string(1), .string(2), .string(0x81), .fence(marker: 0x60, length: 3, language: "swift", inner: .normal),
                                   .fence(marker: 0x7E, length: 4, language: nil, inner: .normal), .fence(marker: 0x60, length: 3, language: "python", inner: .string(1))]
        for g in grammars {
            for line in corpus {
                let units = Array(line.utf16)
                units.withUnsafeBufferPointer { buf in
                    for s in starts {
                        XCTAssertEqual(g.exitState(line: buf, entering: s), g.scanLine(buf, base: 0, entering: s).exiting, "\(g.name) · \(line) · \(s)")
                    }
                }
            }
        }
    }
}

final class LineStateMarkdownTests: XCTestCase {
    let md = PlainNotesGrammar(markdown: true)

    func testFenceWithKnownLanguageUsesThatGrammar() {
        let text = "# Title\n```swift\nlet x = 1 // c\n# not a heading\n```\n# Heading again"
        let r = lines(md, text)
        XCTAssertEqual(r[0].tokens, ["# Title:title"])
        XCTAssertEqual(r[1].tokens, ["```swift:punctuation"])
        XCTAssertEqual(r[1].exit, .fence(marker: 0x60, length: 3, language: "swift", inner: .normal))
        XCTAssertEqual(r[2].tokens, ["let:keyword", "=:operator", "1:number", "// c:comment"])
        XCTAssertEqual(r[3].tokens, [], "펜스 안의 # 줄은 헤딩이 아니라 Swift 로 스캔된다")
        XCTAssertEqual(r[4].tokens, ["```:punctuation"])
        XCTAssertEqual(r[4].exit, .normal)
        XCTAssertEqual(r[5].tokens, ["# Heading again:title"])
    }

    func testFenceWithUnknownOrNoLanguageHasNoColors() {
        let r = lines(md, "```\n# heading? no\n- [ ] task https://x.io/a\n```\n- [ ] back")
        XCTAssertEqual(r[0].exit, .fence(marker: 0x60, length: 3, language: nil, inner: .normal))
        XCTAssertEqual(r[1].tokens, [])
        XCTAssertEqual(r[2].tokens, [])
        XCTAssertEqual(r[3].exit, .normal)
        XCTAssertEqual(r[4].tokens, ["-:punctuation", "[ ]:special"])
        XCTAssertEqual(lines(md, "```unknownlang\nx = 1")[1].tokens, [])
        XCTAssertEqual(lines(md, "```mermaid\ngraph TD")[1].tokens, [])
    }

    func testFenceAliasesAndNestedState() {
        XCTAssertEqual(lines(md, "```python\nx = 1")[1].tokens, ["=:operator", "1:number"])
        XCTAssertEqual(lines(md, "```js\nconst a = 1")[1].tokens, ["const:keyword", "=:operator", "1:number"])
        XCTAssertEqual(lines(md, "```bash\necho hi")[1].tokens, ["echo:keyword"])
        XCTAssertEqual(lines(md, "```JSON {.class}\n{\"a\": 1}")[1].tokens, ["{:punctuation", "\"a\":property", "::operator", "1:number", "}:punctuation"])
        // 펜스 안의 블록 주석이 줄을 넘어가면 inner 가 그 상태를 든다
        let r = lines(md, "```c\nint x; /* open\nstill comment\n*/ int y;\n```")
        XCTAssertEqual(r[1].exit, .fence(marker: 0x60, length: 3, language: "c", inner: .blockComment))
        XCTAssertEqual(r[2].tokens, ["still comment:comment"])
        XCTAssertEqual(r[3].tokens.first, "*/:comment")
        XCTAssertEqual(r[3].exit, .fence(marker: 0x60, length: 3, language: "c", inner: .normal))
        XCTAssertEqual(r[4].exit, .normal)
    }

    func testClosingFenceRules() {
        // 닫는 펜스는 같은 기호가 여는 길이 이상, 뒤에는 공백뿐
        XCTAssertEqual(lines(md, "````\n```\nstill\n````\nout").map(\.exit), [.fence(marker: 0x60, length: 4, language: nil, inner: .normal), .fence(marker: 0x60, length: 4, language: nil, inner: .normal), .fence(marker: 0x60, length: 4, language: nil, inner: .normal), .normal, .normal])
        XCTAssertEqual(lines(md, "~~~\n```\n~~~").map(\.exit), [.fence(marker: 0x7E, length: 3, language: nil, inner: .normal), .fence(marker: 0x7E, length: 3, language: nil, inner: .normal), .normal])
        XCTAssertEqual(lines(md, "```\n``` trailing text\n```").map(\.exit), [.fence(marker: 0x60, length: 3, language: nil, inner: .normal), .fence(marker: 0x60, length: 3, language: nil, inner: .normal), .normal])
        XCTAssertEqual(lines(md, "```\n  ```  ").map(\.exit), [.fence(marker: 0x60, length: 3, language: nil, inner: .normal), .normal])
        // 정보 문자열에 백틱이 있으면 펜스가 아니다
        XCTAssertEqual(lines(md, "``` a`b\nx").map(\.exit), [.normal, .normal])
        // 메모(.txt) 는 펜스 상태가 없다
        XCTAssertEqual(lines(PlainNotesGrammar(markdown: false), "```\n# heading").map(\.exit), [.normal, .normal])
        XCTAssertEqual(lines(PlainNotesGrammar(markdown: false), "```\n# heading")[1].tokens, ["# heading:title"])
    }

    func testHTMLCommentSpansLinesInMarkdown() {
        let r = lines(md, "intro <!-- hidden\n# not a heading\nend --> https://x.io/after\n# heading")
        XCTAssertEqual(r[0].tokens, ["<!-- hidden:comment"])
        XCTAssertEqual(r[0].exit, .blockComment)
        XCTAssertEqual(r[1].tokens, ["# not a heading:comment"])
        XCTAssertEqual(r[2].tokens, ["end -->:comment", "https://x.io/after:link"])
        XCTAssertEqual(r[2].exit, .normal)
        XCTAssertEqual(r[3].tokens, ["# heading:title"])
        XCTAssertEqual(lines(md, "a <!-- one line --> b").map(\.exit), [.normal])
        // 메모 모드에서는 HTML 주석을 보지 않는다
        XCTAssertEqual(lines(PlainNotesGrammar(markdown: false), "a <!-- x").map(\.exit), [.normal])
    }

    func testMultiLineTokensViaTokensInText() {
        // 편의 API `tokens(in:)` 도 줄 사이 상태를 잇는다
        let text = "```swift\nlet a = 1\n```"
        XCTAssertEqual(describe(md.tokens(in: text), in: text), ["```swift:punctuation", "let:keyword", "=:operator", "1:number", "```:punctuation"])
        let sw = "/* a\nb */ let c"
        XCTAssertEqual(describe(CodeGrammar(language: .swift).tokens(in: sw), in: sw), ["/* a:comment", "b */:comment", "let:keyword"])
    }

    func testScanLineInNSStringStripsNewline() {
        let ns = "let a = 1 // c\r\nnext" as NSString
        let toks = CodeGrammar(language: .swift).scanLine(in: ns, range: NSRange(location: 0, length: 16), entering: .normal)
        XCTAssertEqual(describe(toks, in: ns as String), ["let:keyword", "=:operator", "1:number", "// c:comment"])
        XCTAssertEqual(CodeGrammar(language: .swift).scanLine(in: ns, range: NSRange(location: 16, length: 4), entering: .blockComment).map(\.kind), [.comment])
    }
}

final class LineStateIndexTests: XCTestCase {
    private func states(_ text: String, _ g: any LanguageGrammar) -> [LineState] {
        let ns = text as NSString
        return LineStateIndex(text: ns, lineIndex: LineIndex(nsString: ns), grammar: g).states
    }

    func testFullComputation() {
        let swift = CodeGrammar(language: .swift)
        XCTAssertEqual(states("a\n/* b\nc\nd */\ne", swift), [.normal, .normal, .blockComment, .blockComment, .normal])
        XCTAssertEqual(states("", swift), [.normal])
        XCTAssertEqual(states("/*", swift), [.normal])
        XCTAssertEqual(states("/*\n", swift), [.normal, .blockComment])
        XCTAssertEqual(states("a\r\n/* b\r\nc */\r\nd", swift), [.normal, .normal, .blockComment, .normal], "CRLF")
        let idx = LineStateIndex(text: "x" as NSString, lineIndex: LineIndex(text: "x"), grammar: PlainNotesGrammar(markdown: false))
        XCTAssertFalse(idx.isTracking)
        XCTAssertTrue(idx.isEmpty)
        XCTAssertEqual(idx.state(ofLine: 1), .normal)
        let md = states("```py\nx = 1\n```\n# h", PlainNotesGrammar(markdown: true))
        XCTAssertEqual(md, [.normal, .fence(marker: 0x60, length: 3, language: "py", inner: .normal), .fence(marker: 0x60, length: 3, language: "py", inner: .normal), .normal])
    }

    func testStateOfLineIsOneBasedAndClamped() {
        let ns = "a\n/* b\nc */" as NSString
        let idx = LineStateIndex(text: ns, lineIndex: LineIndex(nsString: ns), grammar: CodeGrammar(language: .swift))
        XCTAssertEqual(idx.lineCount, 3)
        XCTAssertEqual(idx.state(ofLine: 1), .normal)
        XCTAssertEqual(idx.state(ofLine: 3), .blockComment)
        XCTAssertEqual(idx.state(ofLine: 0), .normal)
        XCTAssertEqual(idx.state(ofLine: 99), .normal)
    }

    /// 편집 한 번: 증분 == 전체, 그리고 돌려준 '바뀐 줄 범위' 가 실제로 바뀐 줄을 다 담는다
    private func apply(_ text: inout String, _ idx: inout LineStateIndex, _ live: inout LineIndex, replacing r: NSRange, with repl: String, grammar g: any LanguageGrammar,
                       file: StaticString = #filePath, line: UInt = #line) -> Range<Int> {
        let before = idx.states
        let old = live
        let ns = text as NSString
        let newText = ns.replacingCharacters(in: r, with: repl)
        let newNS = newText as NSString
        live = old.updated(replacing: r, with: repl as NSString)
        XCTAssertEqual(live, LineIndex(nsString: newNS), file: file, line: line)
        let edited = NSRange(location: r.location, length: (repl as NSString).length)
        let first = old.lineNumber(forUTF16Offset: r.location)
        let last = max(first, live.lineNumber(forUTF16Offset: NSMaxRange(edited)))
        let changed = idx.update(text: newNS, lineIndex: live, editedLines: first..<(last + 1), lineDelta: live.lineCount - old.lineCount, grammar: g)
        let full = LineStateIndex(text: newNS, lineIndex: live, grammar: g)
        XCTAssertEqual(idx, full, "replace \(r) with \(repl.debugDescription) in \(text.debugDescription)", file: file, line: line)
        // 바뀐 줄 보고: 편집 줄(first...last) 밖에서 상태가 달라진 줄은 모두 changed 안에 있어야 한다 (뒤쪽은 lineDelta 만큼 밀어 비교)
        let after = idx.states
        for lineNo in (last + 1)...max(last + 1, after.count) where lineNo <= after.count {
            let oldLine = lineNo - (live.lineCount - old.lineCount)
            guard oldLine >= 1, oldLine <= before.count else { continue }
            if before[oldLine - 1] != after[lineNo - 1] {
                XCTAssertTrue(changed.contains(lineNo), "line \(lineNo) changed (\(before[oldLine - 1]) → \(after[lineNo - 1])) but not reported in \(changed)", file: file, line: line)
            }
        }
        text = newText
        return changed
    }

    func testIncrementalOpenAndCloseBlockComment() {
        let g = CodeGrammar(language: .swift)
        var text = "let a = 1\nlet b = 2\nlet c = 3\nlet d = 4\n"
        var live = LineIndex(text: text)
        var idx = LineStateIndex(text: text as NSString, lineIndex: live, grammar: g)
        XCTAssertEqual(idx.states, [.normal, .normal, .normal, .normal, .normal])
        // 1줄 끝에 `/*` → 2줄부터 끝까지 blockComment, 바뀐 줄 2...5
        var changed = apply(&text, &idx, &live, replacing: NSRange(location: 9, length: 0), with: " /*", grammar: g)
        XCTAssertEqual(idx.states, [.normal, .blockComment, .blockComment, .blockComment, .blockComment])
        XCTAssertEqual(changed, 2..<6)
        // 주석 안에서 타이핑: 상태 변화 없음 → 빈 범위
        changed = apply(&text, &idx, &live, replacing: NSRange(location: 22, length: 0), with: "x", grammar: g)
        XCTAssertEqual(changed, 0..<0)
        // 3줄 끝에 `*/` → 4, 5줄 복귀
        let line3End = NSMaxRange(live.range(ofLine: 3))
        changed = apply(&text, &idx, &live, replacing: NSRange(location: line3End, length: 0), with: " */", grammar: g)
        XCTAssertEqual(idx.states, [.normal, .blockComment, .blockComment, .normal, .normal])
        XCTAssertEqual(changed, 4..<6)
        // Enter 로 줄 추가 (주석 안): 새 줄은 blockComment, 보고 범위는 비어 있음 (편집 줄은 TextKit 이 다시 배치)
        changed = apply(&text, &idx, &live, replacing: NSRange(location: 22, length: 0), with: "\n", grammar: g)
        XCTAssertEqual(idx.states, [.normal, .blockComment, .blockComment, .blockComment, .normal, .normal])
        XCTAssertEqual(changed, 0..<0)
        // `/*` 삭제 → 전부 normal
        changed = apply(&text, &idx, &live, replacing: NSRange(location: 9, length: 3), with: "", grammar: g)
        XCTAssertEqual(idx.states, [.normal, .normal, .normal, .normal, .normal, .normal])
        XCTAssertEqual(changed, 2..<5)
    }

    func testIncrementalMarkdownFence() {
        let g = PlainNotesGrammar(markdown: true)
        var text = "# T\nlet a = 1\n# H\n"
        var live = LineIndex(text: text)
        var idx = LineStateIndex(text: text as NSString, lineIndex: live, grammar: g)
        _ = apply(&text, &idx, &live, replacing: NSRange(location: 4, length: 0), with: "```swift\n", grammar: g)
        XCTAssertEqual(idx.states[2], .fence(marker: 0x60, length: 3, language: "swift", inner: .normal))
        XCTAssertEqual(idx.states[3], .fence(marker: 0x60, length: 3, language: "swift", inner: .normal))
        // 언어 이름을 바꾸면 아래 줄 상태의 payload 가 바뀐다 → 보고돼야 한다
        let changed = apply(&text, &idx, &live, replacing: NSRange(location: 7, length: 5), with: "python", grammar: g)
        XCTAssertEqual(idx.states[2], .fence(marker: 0x60, length: 3, language: "python", inner: .normal))
        XCTAssertTrue(changed.contains(3) && changed.contains(4), "\(changed)")
    }

    func testInconsistentArgumentsFallBackToFullRecompute() {
        let g = CodeGrammar(language: .swift)
        let ns = "a\n/* b\nc */\nd" as NSString
        var idx = LineStateIndex(text: ns, lineIndex: LineIndex(nsString: ns), grammar: g)
        let changed = idx.update(text: ns, lineIndex: LineIndex(nsString: ns), editedLines: 1..<2, lineDelta: 7, grammar: g)
        XCTAssertEqual(idx, LineStateIndex(text: ns, lineIndex: LineIndex(nsString: ns), grammar: g))
        XCTAssertEqual(changed, 1..<5)
        var none = LineStateIndex()
        XCTAssertEqual(none.update(text: ns, lineIndex: LineIndex(nsString: ns), editedLines: 1..<2, lineDelta: 0, grammar: g), 0..<0)
    }

    /// 결정적 PRNG 로 무작위 편집 200회 × 두 문법 — 매번 전체 재계산과 비교
    func testFuzzIncrementalEqualsFull() {
        var s: UInt64 = 0x9E3779B97F4A7C15
        func rnd(_ n: Int) -> Int { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return Int(s % UInt64(max(1, n))) }
        let pieces = ["a", "b", "\n", "\n\n", "/*", "*/", "/* x */", " ", "x\ny\nz", "\"", "\"\"\"", "`", "r#\"", "\"#", "```", "```swift\n", "~~~", "<!--", "-->", "# h", "", "'''"]
        let grammars: [any LanguageGrammar] = [CodeGrammar(language: .swift), PlainNotesGrammar(markdown: true), CodeGrammar(language: .python), CodeGrammar(language: .rust)]
        for g in grammars {
            var text = "start /* c */\nlet s = \"\"\"\nline two\n\"\"\"\n```python\nx = 1\n```\nend"
            var live = LineIndex(text: text)
            var idx = LineStateIndex(text: text as NSString, lineIndex: live, grammar: g)
            for _ in 0..<200 {
                let ns = text as NSString
                let loc = rnd(ns.length + 1)
                let len = rnd(min(8, ns.length - loc + 1))
                let repl = (0..<rnd(3)).map { _ in pieces[rnd(pieces.count)] }.joined()
                _ = apply(&text, &idx, &live, replacing: NSRange(location: loc, length: len), with: repl, grammar: g)
                if idx != LineStateIndex(text: text as NSString, lineIndex: live, grammar: g) { return }
            }
        }
    }

    /// 34k 줄(2.8 MB) 코드 파일: 전체 계산은 토큰 없이 (Release 실측 10 ms, 디버그 빌드 ≈ 400 ms), 키 입력 한 번의 증분 갱신은 1 ms 안 (Release 0.06 ms).
    /// 상한은 다른 빌드가 함께 도는 디버그 환경을 감안해 넉넉히 둔다.
    func testPerformance34kLines() {
        var text = ""
        text.reserveCapacity(1_400_000)
        for i in 0..<34_000 {
            switch i % 9 {
            case 0: text += "/* block comment opens here \(i)\n"
            case 1: text += " * still inside the comment with a \"quote\" and /* nested\n"
            case 2: text += " */ let value\(i) = compute(\"string\", 0x1F, 3.5e-2) // trailing\n"
            case 3: text += "@MainActor final class Foo\(i): NSObject { var x = \"\"\"\n"
            case 4: text += "multi-line string body line \(i) with #if and // not a comment\n"
            case 5: text += "  \"\"\" // string closed \(i)\n"
            default: text += "    guard let url = URL(string: \"https://example.com/\(i)\") else { return nil } // 한글 주석 \(i)\n"
            }
        }
        let ns = text as NSString
        let li = LineIndex(nsString: ns)
        let g = CodeGrammar(language: .swift)
        _ = LineStateIndex(text: ns, lineIndex: li, grammar: g)   // 워밍업
        let t = CFAbsoluteTimeGetCurrent()
        var idx = LineStateIndex(text: ns, lineIndex: li, grammar: g)
        let fullMs = (CFAbsoluteTimeGetCurrent() - t) * 1000
        XCTAssertEqual(idx.lineCount, li.lineCount)
        let t2 = CFAbsoluteTimeGetCurrent()
        let changed = idx.update(text: ns, lineIndex: li, editedLines: 17_000..<17_001, lineDelta: 0, grammar: g)
        let incMs = (CFAbsoluteTimeGetCurrent() - t2) * 1000
        XCTAssertEqual(changed, 0..<0)
        print(String(format: "[perf] LineStateIndex %d lines · full %.1f ms · incremental %.3f ms", li.lineCount, fullMs, incMs))
        XCTAssertLessThan(fullMs, 1500, "full computation (debug build)")
        XCTAssertLessThan(incMs, 20, "one-line incremental update (debug build)")
    }
}
