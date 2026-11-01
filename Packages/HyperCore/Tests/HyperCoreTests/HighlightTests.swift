import XCTest
@testable import HyperCore

/// 토큰 → "텍스트:종류" 로 바꿔 비교를 읽기 쉽게
private func describe(_ tokens: [Token], in text: String) -> [String] {
    let ns = text as NSString
    return tokens.map { "\(ns.substring(with: $0.range)):\($0.kind.rawValue)" }
}

private func tok(_ g: any LanguageGrammar, _ line: String) -> [String] { describe(g.tokens(in: line), in: line) }

final class PlainNotesGrammarTests: XCTestCase {
    let notes = PlainNotesGrammar(markdown: false)
    let md = PlainNotesGrammar(markdown: true)

    func testHeadingWholeLine() {
        XCTAssertEqual(tok(md, "## 2026-10-30 (금) 14:05"), ["## 2026-10-30 (금) 14:05:title"])
        XCTAssertEqual(tok(notes, "# Notes · 메모"), ["# Notes · 메모:title"])
        XCTAssertEqual(tok(notes, "####### seven"), [])                  // 7개는 헤딩 아님
        XCTAssertEqual(tok(notes, "#notag heading"), ["#notag:attribute"]) // 공백 없으면 태그
    }

    func testCodeLikeHashIsCommentInNotesOnly() {
        XCTAssertEqual(tok(notes, "# from pymongo import MongoClient"), ["# from pymongo import MongoClient:comment"])
        XCTAssertEqual(tok(md, "# from pymongo import MongoClient"), ["# from pymongo import MongoClient:title"])
        XCTAssertEqual(tok(notes, "# x = 3"), ["# x = 3:comment"])
    }

    func testListMarkersAndTasks() {
        XCTAssertEqual(tok(md, "- [ ] Sketch the ribbon layout"), ["-:punctuation", "[ ]:special"])
        XCTAssertEqual(tok(md, "- [x] Measure typing latency → 3.1 ms"), ["-:punctuation", "[x]:special", "→:operator"])
        XCTAssertEqual(tok(md, "  * nested item"), ["*:punctuation"])
        XCTAssertEqual(tok(md, "1) 메모 파일에도 append-only 가 잘 맞는다"), ["1):punctuation"])
        XCTAssertEqual(tok(md, "12. twelve"), ["12.:punctuation"])
        XCTAssertEqual(tok(md, "-not a list"), [])
    }

    func testBracketTitleAndKeyValue() {
        XCTAssertEqual(tok(notes, "[Reading] Designing Data-Intensive Applications"), ["[Reading]:title"])
        XCTAssertEqual(tok(notes, "[Title] bracket heading"), ["[Title]:title"])
        XCTAssertEqual(tok(notes, "status: blocked on review"), ["status:property"])
        XCTAssertEqual(tok(notes, "제목: 한글 키"), ["제목:property"])
        XCTAssertEqual(tok(notes, "https://example.com/a: not a key"), ["https://example.com/a:link"])
        XCTAssertEqual(tok(notes, "Column mode test block (⌥C, then ⇧↓):"), [])
    }

    func testURLsDatesTimes() {
        let line = "see https://developer.apple.com/documentation/appkit/nstextview, then 2022-01-06 01:21:02 INFO"
        XCTAssertEqual(tok(notes, line), ["https://developer.apple.com/documentation/appkit/nstextview:link", "2022-01-06:number", "01:21:02:number"])
        XCTAssertEqual(tok(notes, "(http://a.io/x) 14:05 at 9:30"), ["http://a.io/x:link", "14:05:number", "9:30:number"])
        XCTAssertEqual(tok(notes, "v2026-10-30x and 1234:56"), [])   // 단어 안·경계 없는 것은 제외
    }

    func testTagsBoldCodeArrows() {
        XCTAssertEqual(tok(notes, "work on #hyperedit and #한글태그 (#x)"), ["#hyperedit:attribute", "#한글태그:attribute", "#x:attribute"])
        XCTAssertEqual(tok(notes, "a#b is not a tag"), [])
        XCTAssertEqual(tok(md, "This is **bold** and `code` ⇒ done"), ["**bold**:constant", "`code`:string", "⇒:operator"])
        XCTAssertEqual(tok(notes, "3 + 0.5 + 0.25 ⇒ 3.75 days => ok -> fine"), ["⇒:operator", "=>:operator", "->:operator"])
        XCTAssertEqual(tok(notes, "unclosed `code and **bold"), [])
        XCTAssertEqual(tok(notes, "✓ done ✗ failed ☐ todo"), ["✓:special", "✗:special", "☐:special"])
    }

    func testFenceAndQuote() {
        XCTAssertEqual(tok(md, "```python"), ["```python:punctuation"])
        XCTAssertEqual(tok(md, "> quoted text with 14:05"), [">:punctuation", "14:05:number"])
    }

    func testHangulLinesStayPlain() {
        XCTAssertEqual(tok(notes, "에디터 재작성 시작. TextKit 2 와 단일 메모 파일로 결정."), [])
        XCTAssertEqual(tok(notes, "가. 쓰기 증폭(write amplification) 정리"), [])
        XCTAssertEqual(tok(notes, "item_a\t120\tdone"), [])
    }

    func testMultiLineRangesAreAbsolute() {
        let text = "plain\n# Head\n- [ ] task https://x.io/a\r\nkey: v"
        let ns = text as NSString
        let tokens = notes.tokens(in: ns, range: NSRange(location: 0, length: ns.length))
        XCTAssertEqual(describe(tokens, in: text), ["# Head:title", "-:punctuation", "[ ]:special", "https://x.io/a:link", "key:property"])
        // 범위를 줄 중간에서 시작해도 (TextKit 요소 범위) 절대 오프셋이 맞아야 한다
        let sub = notes.tokens(in: ns, range: NSRange(location: 6, length: 6))
        XCTAssertEqual(sub.map(\.range), [NSRange(location: 6, length: 6)])
    }
}

final class CodeGrammarTests: XCTestCase {
    func testPython() {
        let g = CodeGrammar(language: .python)
        XCTAssertEqual(tok(g, "def stamp() -> str:  # same format"),
                       ["def:keyword", "stamp:function", "(:punctuation", "):punctuation", "->:operator", "str:type", "::operator", "# same format:comment"])
        XCTAssertEqual(tok(g, "    return datetime.now().strftime(\"## %Y-%m-%d\")"),
                       ["return:keyword", ".:operator", "now:function", "(:punctuation", "):punctuation", ".:operator", "strftime:function", "(:punctuation", "\"## %Y-%m-%d\":string", "):punctuation"])
        // 코드 모드에는 `키:` 규칙이 없다 — seen 은 평문
        XCTAssertEqual(tok(g, "seen: set[str] = set()"), ["::operator", "set:type", "[:punctuation", "str:type", "]:punctuation", "=:operator", "set:type", "(:punctuation", "):punctuation"])
        XCTAssertEqual(tok(g, "x = f\"{a}\" + r'raw' + 0x1F + 3.5e-2"), ["=:operator", "f\"{a}\":string", "+:operator", "r'raw':string", "+:operator", "0x1F:number", "+:operator", "3.5e-2:number"])
        XCTAssertEqual(tok(g, "@dataclass"), ["@dataclass:attribute"])
        XCTAssertEqual(tok(g, "if x is None or MAX_SIZE:"), ["if:keyword", "is:keyword", "None:constant", "or:keyword", "MAX_SIZE:constant", "::operator"])
        XCTAssertEqual(tok(g, "\"\"\"Docstring on one line.\"\"\""), ["\"\"\"Docstring on one line.\"\"\":string"])
    }

    func testSwift() {
        let g = CodeGrammar(language: .swift)
        XCTAssertEqual(tok(g, "@MainActor final class Foo: NSObject { // note"),
                       ["@MainActor:attribute", "final:keyword", "class:keyword", "Foo:type", "::operator", "NSObject:type", "{:punctuation", "// note:comment"])
        XCTAssertEqual(tok(g, "let url = URL(string: \"https://a.io\")! /* c */ #if DEBUG"),
                       ["let:keyword", "=:operator", "URL:function", "(:punctuation", "::operator", "\"https://a.io\":string", "):punctuation", "!:operator", "/* c */:comment", "#if:keyword", "DEBUG:constant"])
        XCTAssertEqual(tok(g, "return nil"), ["return:keyword", "nil:constant"])
        XCTAssertEqual(tok(g, "/* unterminated block comment"), ["/* unterminated block comment:comment"])
    }

    func testJavaScriptAndJSON() {
        let js = CodeGrammar(language: .javascript)
        XCTAssertEqual(tok(js, "const $el = document.querySelector(`#id`); // x"),
                       ["const:keyword", "=:operator", ".:operator", "querySelector:function", "(:punctuation", "`#id`:string", "):punctuation", ";:punctuation", "// x:comment"])
        XCTAssertEqual(tok(js, "export async function load(): Promise<void> {}"),
                       ["export:keyword", "async:keyword", "function:keyword", "load:function", "(:punctuation", "):punctuation", "::operator", "Promise:type", "<:operator", "void:keyword", ">:operator", "{:punctuation", "}:punctuation"])
        let json = CodeGrammar(language: .json)
        XCTAssertEqual(tok(json, "  \"name\": \"HyperEdit\", \"n\": 12, \"ok\": true, \"x\": null"),
                       ["\"name\":property", "::operator", "\"HyperEdit\":string", ",:punctuation", "\"n\":property", "::operator", "12:number", ",:punctuation", "\"ok\":property", "::operator", "true:constant", ",:punctuation", "\"x\":property", "::operator", "null:constant"])
    }

    func testShellAndYAML() {
        let sh = CodeGrammar(language: .shell)
        XCTAssertEqual(tok(sh, "if [ -f \"$HOME/.zshrc\" ]; then source ~/.zshrc; fi # ok"),
                       ["if:keyword", "[:punctuation", "-f:attribute", "\"$HOME/.zshrc\":string", "]:punctuation", ";:punctuation", "then:keyword", "source:keyword", ";:punctuation", "fi:keyword", "# ok:comment"])
        XCTAssertEqual(tok(sh, "git commit -m 'x' | grep ${PATTERN} && echo done"),
                       ["git:function", "-m:attribute", "'x':string", "|:operator", "grep:function", "${PATTERN}:variable", "&&:operator", "echo:keyword", "done:keyword"])
        XCTAssertEqual(tok(sh, "cd /usr/local/bin && ./run.sh --all"), ["cd:keyword", "&&:operator", "--all:attribute"])
        XCTAssertEqual(tok(sh, "FOO=bar"), ["FOO:variable", "=:operator"])
        let y = CodeGrammar(language: .yaml)
        XCTAssertEqual(tok(y, "name: John Smith  # comment"), ["name:property", "::operator", "# comment:comment"])
        XCTAssertEqual(tok(y, "  - url: https://x.io/a"), ["-:punctuation", "url:property", "::operator"])
        XCTAssertEqual(tok(y, "flow: {a: 1, b: \"x\"}"), ["flow:property", "::operator", "{:punctuation", "a:property", "::operator", "1:number", ",:punctuation", "b:property", "::operator", "\"x\":string", "}:punctuation"])
        XCTAssertEqual(tok(y, "enabled: true"), ["enabled:property", "::operator", "true:constant"])
        XCTAssertEqual(tok(y, "date: 2026-10-30"), ["date:property", "::operator", "2026-10-30:number"])
    }

    func testMarkupAndCSS() {
        let html = CodeGrammar(language: .html)
        XCTAssertEqual(tok(html, "<a href=\"https://x.io\" class='b'>Hi &amp; bye</a><!-- c -->"),
                       ["<:punctuation", "a:tag", "href:attribute", "=:operator", "\"https://x.io\":string", "class:attribute", "=:operator", "'b':string", ">:punctuation", "&amp;:constant", "</:punctuation", "a:tag", ">:punctuation", "<!-- c -->:comment"])
        XCTAssertEqual(tok(html, "<!DOCTYPE html><br/>"), ["<!DOCTYPE html>:keyword", "<:punctuation", "br:tag", "/>:punctuation"])
        XCTAssertEqual(tok(html, "if a < b then"), [])
        let css = CodeGrammar(language: .css)
        XCTAssertEqual(tok(css, "a:hover, .btn > #main { /* c */"),
                       ["a:tag", "::operator", "hover:tag", ",:punctuation", ".btn:type", ">:operator", "#main:type", "{:punctuation", "/* c */:comment"])
        XCTAssertEqual(tok(css, "  color: #fff; margin: 12px 1.5em !important;"),
                       ["color:property", "::operator", "#fff:number", ";:punctuation", "margin:property", "::operator", "12px:number", "1.5em:number", "!important:keyword", ";:punctuation"])
        XCTAssertEqual(tok(css, "@media (max-width: 600px) {"), ["@media:keyword", "(:punctuation", "max-width:tag", "::operator", "600px:number", "):punctuation", "{:punctuation"])
    }

    func testCFamilyGoRust() {
        let c = CodeGrammar(language: .c)
        XCTAssertEqual(tok(c, "#include <stdio.h>"), ["#include:keyword", "<stdio.h>:string"])
        XCTAssertEqual(tok(c, "static int main(int argc, char *argv[]) { return 0; }"),
                       ["static:keyword", "int:keyword", "main:function", "(:punctuation", "int:keyword", ",:punctuation", "char:keyword", "*:operator", "[:punctuation", "]:punctuation", "):punctuation", "{:punctuation", "return:keyword", "0:number", ";:punctuation", "}:punctuation"])
        let objc = CodeGrammar(language: .objc)
        XCTAssertEqual(tok(objc, "@interface Foo : NSObject @end NSLog(@\"hi\");"),
                       ["@interface:keyword", "Foo:type", "::operator", "NSObject:type", "@end:keyword", "NSLog:function", "(:punctuation", "@\"hi\":string", "):punctuation", ";:punctuation"])
        let go = CodeGrammar(language: .go)
        XCTAssertEqual(tok(go, "func (s *Server) Run(ctx context.Context) error { return nil }"),
                       ["func:keyword", "(:punctuation", "*:operator", "Server:type", "):punctuation", "Run:function", "(:punctuation", ".:operator", "Context:type", "):punctuation", "error:type", "{:punctuation", "return:keyword", "nil:constant", "}:punctuation"])
        let rs = CodeGrammar(language: .rust)
        XCTAssertEqual(tok(rs, "#[derive(Debug)] pub fn new<'a>(s: &'a str) -> Option<u32> { println!(\"{}\", 'c'); }"),
                       ["#[derive(Debug)]:attribute", "pub:keyword", "fn:keyword", "<:operator", "'a:attribute", ">:operator", "(:punctuation", "::operator", "&:operator", "'a:attribute", "str:type", "):punctuation", "->:operator", "Option:type", "<:operator", "u32:type", ">:operator", "{:punctuation", "println!:function", "(:punctuation", "\"{}\":string", ",:punctuation", "'c':string", "):punctuation", ";:punctuation", "}:punctuation"])
    }

    func testSQLRubyJavaTOMLINI() {
        let sql = CodeGrammar(language: .sql)
        XCTAssertEqual(tok(sql, "SELECT count(*) FROM \"users\" WHERE id = 3 -- c"),
                       ["SELECT:keyword", "count:function", "(:punctuation", "*:operator", "):punctuation", "FROM:keyword", "\"users\":property", "WHERE:keyword", "=:operator", "3:number", "-- c:comment"])
        let rb = CodeGrammar(language: .ruby)
        XCTAssertEqual(tok(rb, "def initialize(name); @name = name; @@count += 1; :sym; end"),
                       ["def:keyword", "initialize:function", "(:punctuation", "):punctuation", ";:punctuation", "@name:variable", "=:operator", ";:punctuation", "@@count:variable", "+=:operator", "1:number", ";:punctuation", ":sym:constant", ";:punctuation", "end:keyword"])
        let java = CodeGrammar(language: .java)
        XCTAssertEqual(tok(java, "@Override public String toString() { return null; }"),
                       ["@Override:attribute", "public:keyword", "String:type", "toString:function", "(:punctuation", "):punctuation", "{:punctuation", "return:keyword", "null:constant", ";:punctuation", "}:punctuation"])
        let kt = CodeGrammar(language: .kotlin)
        XCTAssertEqual(tok(kt, "val x: Int = 1"), ["val:keyword", "::operator", "Int:type", "=:operator", "1:number"])
        let toml = CodeGrammar(language: .toml)
        XCTAssertEqual(tok(toml, "[package] # c"), ["[package]:title", "# c:comment"])
        XCTAssertEqual(tok(toml, "name = \"hyper\" # c"), ["name:property", "=:operator", "\"hyper\":string", "# c:comment"])
        XCTAssertEqual(tok(toml, "edition = 2021"), ["edition:property", "=:operator", "2021:number"])
        let ini = CodeGrammar(language: .ini)
        XCTAssertEqual(tok(ini, "[core]"), ["[core]:title"])
        XCTAssertEqual(tok(ini, "autocrlf = Some Value ; note"), ["autocrlf:property", "=:operator", "; note:comment"])
    }

    func testRegistry() {
        XCTAssertEqual(GrammarRegistry.grammar(for: URL(fileURLWithPath: "/a/notes.md")).name, "Markdown")
        XCTAssertEqual(GrammarRegistry.grammar(for: URL(fileURLWithPath: "/a/notes.txt")).name, "Notes")
        XCTAssertEqual(GrammarRegistry.grammar(for: URL(fileURLWithPath: "/a/LICENSE")).name, "Notes")
        XCTAssertEqual(GrammarRegistry.grammar(for: URL(fileURLWithPath: "/a/Dockerfile")).name, "Shell")
        XCTAssertEqual(GrammarRegistry.grammar(for: URL(fileURLWithPath: "/a/x.PY")).name, "Python")
        XCTAssertEqual(GrammarRegistry.grammar(for: URL(fileURLWithPath: "/a/x.tsx")).name, "TypeScript")
        XCTAssertEqual(GrammarRegistry.grammar(for: URL(fileURLWithPath: "/a/x.hpp")).name, "C++")
        XCTAssertEqual(GrammarRegistry.grammar(for: URL(fileURLWithPath: "/a/x.unknownext")).name, "Notes")
        XCTAssertTrue(GrammarRegistry.grammar(forExtension: "md") is PlainNotesGrammar)
    }

    func testTokensNeverOverlapOrExceedLine() {
        let samples: [(any LanguageGrammar, String)] = [
            (PlainNotesGrammar(markdown: true), "- [x] **a** `b` https://x.io/#frag?q=1) #tag 2026-10-30 14:05 ⇒ ok"),
            (CodeGrammar(language: .python), "x = f\"{a!r}\" if y else '''z"),
            (CodeGrammar(language: .html), "<div class=\"a\" data-x='1'><span>&lt;</span>"),
            (CodeGrammar(language: .shell), "echo \"$X ${Y} $1 $? $@\" | wc -l # c"),
            (CodeGrammar(language: .rust), "let s: &'static str = \"x\"; 'a 'b'"),
            (CodeGrammar(language: .css), "#abc { color: #abcdef; } .x:hover{}"),
        ]
        for (g, line) in samples {
            let ts = g.tokens(in: line)
            let n = (line as NSString).length
            var last = 0
            for t in ts {
                XCTAssertGreaterThanOrEqual(t.range.location, last, "overlap in \(g.name): \(line)")
                XCTAssertLessThanOrEqual(NSMaxRange(t.range), n, "past end in \(g.name): \(line)")
                XCTAssertGreaterThan(t.range.length, 0)
                last = NSMaxRange(t.range)
            }
        }
    }

    func testEmptyAndWhitespaceLines() {
        for g in [PlainNotesGrammar(markdown: true) as any LanguageGrammar, CodeGrammar(language: .swift), CodeGrammar(language: .html), CodeGrammar(language: .yaml)] {
            XCTAssertEqual(g.tokens(in: "").count, 0)
            XCTAssertEqual(g.tokens(in: "   \t ").count, 0)
            XCTAssertEqual(g.tokens(in: "\n\n").count, 0)
        }
    }
}

final class HighlightPerformanceTests: XCTestCase {
    /// 34k 줄 메모(1.3 MB 급)를 통째로 토큰화해도 100 ms 안 — 실제 앱은 보이는 줄만 계산하므로 여기는 상한 확인
    func testNotesGrammar34kLines() {
        let sample = """
        ## 2026-08-12 (수) 09:10
        Kickoff for the editor rewrite. Decided on TextKit 2 and one plain-text notes file.
        에디터 재작성 시작. TextKit 2 와 단일 메모 파일로 결정.
        - [ ] Sketch the ribbon layout
        - [x] Measure typing latency on a 1.3 MB file → 3.1 ms per keystroke
        [Reading] Designing Data-Intensive Applications, chapter 3 — LSM trees vs B-trees
        가. 쓰기 증폭(write amplification) 정리
        1) 메모 파일에도 append-only 가 잘 맞는다
        Quick calculation while planning the release:  3 + 0.5 + 0.25 ⇒ 3.75 days
        - https://developer.apple.com/documentation/appkit/nstextview #apple #textkit
        item_a\t120\tdone
        status: blocked on review until 14:05
        # from pymongo import MongoClient
        2022-01-06 01:21:02 INFO log line with `code` and **bold** text

        """
        let text = String(repeating: sample, count: 34_000 / 14 + 1)
        let ns = text as NSString
        let lines = text.utf8.reduce(0) { $0 + ($1 == 10 ? 1 : 0) }
        XCTAssertGreaterThanOrEqual(lines, 34_000)
        let g = PlainNotesGrammar(markdown: true)
        _ = g.tokens(in: ns, range: NSRange(location: 0, length: min(ns.length, 50_000)))   // 워밍업
        let t = CFAbsoluteTimeGetCurrent()
        let tokens = g.tokens(in: ns, range: NSRange(location: 0, length: ns.length))
        let ms = (CFAbsoluteTimeGetCurrent() - t) * 1000
        print(String(format: "[perf] PlainNotesGrammar %d lines · %d chars · %d tokens · %.1f ms", lines, ns.length, tokens.count, ms))
        XCTAssertGreaterThan(tokens.count, 40_000)
        // 릴리스(-O)에서 100 ms 상한. `swift test` 기본(디버그, 인라인 없음)은 3~4배 느려 상한을 늘린다.
        XCTAssertLessThan(ms, Self.isOptimized ? 100 : 350, "34k-line notes tokenization should stay under 100 ms (release)")
    }

    static var isOptimized: Bool {
        #if DEBUG
        return false
        #else
        return true
        #endif
    }

    func testPythonGrammar34kLines() {
        let sample = """
        def dedupe(lines: list[str]) -> list[str]:
            \"\"\"Keep the first of identical lines.\"\"\"
            seen: set[str] = set()
            out = []
            for line in lines:   # 0x1F 3.5e-2
                if line not in seen and MAX_SIZE > 0:
                    seen.add(line)
                    out.append(f"{line!r}")
            return out

        """
        let text = String(repeating: sample, count: 3_400)
        let ns = text as NSString
        let g = CodeGrammar(language: .python)
        _ = g.tokens(in: ns, range: NSRange(location: 0, length: min(ns.length, 50_000)))
        let t = CFAbsoluteTimeGetCurrent()
        let tokens = g.tokens(in: ns, range: NSRange(location: 0, length: ns.length))
        let ms = (CFAbsoluteTimeGetCurrent() - t) * 1000
        print(String(format: "[perf] CodeGrammar(python) 34k lines · %d chars · %d tokens · %.1f ms", ns.length, tokens.count, ms))
        XCTAssertLessThan(ms, Self.isOptimized ? 150 : 2000, "34k-line Python tokenization (CI debug runner measured 854 ms)")
    }
}
