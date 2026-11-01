import XCTest
@testable import HyperCore

final class HTMLExporterTests: XCTestCase {
    private func theme(_ id: String) throws -> Theme {
        try XCTUnwrap(try ThemeStore.loadBundled().first { $0.id == id })
    }

    func testEscapesEverythingAndHasNoScripts() throws {
        let t = try theme("hyper-light")
        let src = "<script>alert(1)</script> & \"quotes\" 'single'\n# not a heading <b>"
        let html = HTMLExporter.codeHTML(src, grammar: PlainNotesGrammar(markdown: false), theme: t, options: .init(title: "a<b>.txt"))
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertFalse(html.contains("<script"), html)
        XCTAssertFalse(html.contains("<b>"), html)
        XCTAssertTrue(html.contains("&lt;script&gt;alert(1)&lt;/script&gt; &amp; &quot;quotes&quot; &#39;single&#39;"), html)
        XCTAssertTrue(html.contains("<title>a&lt;b&gt;.txt</title>"), html)
        XCTAssertTrue(html.contains("<meta name=\"color-scheme\" content=\"light\">"), html)
        XCTAssertTrue(html.contains("background: \(t.background.hexString)"), html)
        XCTAssertTrue(html.contains("data-language=\"Notes\""), html)
        XCTAssertFalse(html.contains("<link "), html)
    }

    func testTokenSpansUseGrammarAndThemeColors() throws {
        let t = try theme("hyper-dark")
        let py = "def f(x):\n    return \"s\"  # c\n"
        let html = HTMLExporter.codeHTML(py, grammar: CodeGrammar(language: .python), theme: t)
        XCTAssertTrue(html.contains("<span class=\"tok-keyword\">def</span> <span class=\"tok-function\">f</span><span class=\"tok-punctuation\">(</span>x<span class=\"tok-punctuation\">)</span><span class=\"tok-operator\">:</span>"), html)
        XCTAssertTrue(html.contains("<span class=\"tok-keyword\">return</span> <span class=\"tok-string\">&quot;s&quot;</span>  <span class=\"tok-comment\"># c</span>"), html)
        XCTAssertTrue(html.contains("data-language=\"Python\""), html)
        // 테마 syntax 팔레트의 색이 그대로 CSS 로
        XCTAssertTrue(html.contains(".tok-keyword { color: \(t.syntax["keyword"]!.hexString); }"), html)
        XCTAssertTrue(html.contains(".tok-comment { color: \(t.syntax["comment"]!.hexString); }"), html)
        // 줄 번호 없음: 실제 개행만, 줄 블록 없음 (복사하면 원문)
        XCTAssertFalse(html.contains("class=\"line\""), html)
        XCTAssertTrue(html.contains("<pre class=\"code\" data-language=\"Python\">\n<span"), html)
    }

    func testLineNumbersColumn() throws {
        let t = try theme("hyper-light")
        let body = HTMLExporter.codeBody("one\n\nthree\n", grammar: PlainNotesGrammar(markdown: false), lineNumbers: true)
        XCTAssertTrue(body.hasPrefix("<pre class=\"code with-ln\" data-language=\"Notes\" style=\"--ln-w: 2ch\">"), body)
        XCTAssertEqual(body.components(separatedBy: "<span class=\"line\">").count - 1, 3, body)
        XCTAssertTrue(body.contains("<span class=\"line\"><span class=\"ln\">1</span>one</span>"), body)
        XCTAssertTrue(body.contains("<span class=\"line\"><span class=\"ln\">2</span></span>"), body)       // 빈 줄도 블록 하나
        XCTAssertTrue(body.contains("<span class=\"line\"><span class=\"ln\">3</span>three</span></pre>"), body)
        XCTAssertFalse(body.contains("</span>\n<span class=\"line\">"), body)   // 블록 사이 개행 없음
        // 자릿수에 따라 열 폭
        var big = ""
        for i in 1...120 { big += "line \(i)\n" }
        let wide = HTMLExporter.codeBody(big, grammar: PlainNotesGrammar(markdown: false), lineNumbers: true)
        XCTAssertTrue(wide.contains("--ln-w: 3ch"), String(wide.prefix(120)))
        XCTAssertEqual(wide.components(separatedBy: "class=\"ln\"").count - 1, 120)
        XCTAssertTrue(HTMLExporter.codeCSS(for: t).contains(".with-ln .ln {"))
    }

    func testLineSplittingHandlesAllLineEndings() {
        func lines(_ s: String) -> [String] { let u = Array(s.utf16); return HTMLExporter.lineRanges(u).map { String(decoding: u[$0], as: UTF16.self) } }
        XCTAssertEqual(lines("a\nb"), ["a", "b"])
        XCTAssertEqual(lines("a\nb\n"), ["a", "b"])            // 끝 개행 뒤 빈 꼬리는 줄이 아님
        XCTAssertEqual(lines("a\n\n"), ["a", ""])
        XCTAssertEqual(lines("a\r\nb\rc"), ["a", "b", "c"])
        XCTAssertEqual(lines(""), [""])
        XCTAssertEqual(lines("\n"), [""])
        XCTAssertEqual(lines("한글\n줄"), ["한글", "줄"])
    }

    func testMarkdownPathMatchesMarkdownHTMLWithoutPreviewScript() throws {
        let t = try theme("hyper-dark")
        let md = "# Title\n\nSome **bold** text and [link](https://example.com) ![i](img/a.png)\n"
        let url = URL(fileURLWithPath: "/tmp/x/notes.md")
        let exported = HTMLExporter.html(for: md, url: url, theme: t, options: .init(lineNumbers: true, title: "notes.md"))
        XCTAssertEqual(exported, MarkdownHTML.html(for: md, theme: t, baseURL: nil, title: "notes.md", includeScript: false))
        XCTAssertTrue(exported.contains(MarkdownHTML.body(for: md)), exported)   // 본문은 미리보기와 같다
        XCTAssertTrue(exported.contains("<h1 data-line=\"1\">Title</h1>"), exported)
        XCTAssertTrue(exported.contains("<a href=\"https://example.com\">link</a>"), exported)
        XCTAssertTrue(exported.contains("<img src=\"img/a.png\""), exported)             // 상대 경로 그대로
        XCTAssertFalse(exported.contains("<base "), exported)                                // baseURL 없음 → 저장 위치 기준
        XCTAssertFalse(exported.contains("<script"), exported)                               // 미리보기 스크립트 없음 (브라우저에서 링크가 살아 있다)
        XCTAssertFalse(exported.contains("messageHandlers"), exported)
        XCTAssertTrue(exported.contains("<title>notes.md</title>"), exported)
        XCTAssertTrue(exported.contains("@media print"), exported)
        XCTAssertFalse(exported.contains("class=\"line\""), exported)                        // 줄 번호 옵션은 마크다운에 영향 없음
        // 미리보기용 호출은 그대로 (스크립트 포함, 인쇄 CSS 없음)
        let preview = MarkdownHTML.html(for: md, theme: t, baseURL: URL(fileURLWithPath: "/tmp/x", isDirectory: true))
        XCTAssertTrue(preview.contains("messageHandlers.link") && preview.contains("<base href=\"file:///tmp/x/\">"), preview)
        XCTAssertFalse(preview.contains("@media print"), preview)
        // PDF 경로: 문서 폴더를 base 로
        let withBase = HTMLExporter.html(for: md, url: url, theme: t, options: .init(baseURL: url.deletingLastPathComponent()))
        XCTAssertTrue(withBase.contains("<base href=\"file:///tmp/x/\">"), withBase)
    }

    func testDispatchByExtension() throws {
        let t = try theme("hyper-light")
        XCTAssertTrue(HTMLExporter.isMarkdown(URL(fileURLWithPath: "/a/b.md")))
        XCTAssertTrue(HTMLExporter.isMarkdown(URL(fileURLWithPath: "/a/b.markdown")))
        XCTAssertFalse(HTMLExporter.isMarkdown(URL(fileURLWithPath: "/a/notes.txt")))
        XCTAssertFalse(HTMLExporter.isMarkdown(URL(fileURLWithPath: "/a/Makefile")))
        let swift = HTMLExporter.html(for: "let x = 1 // c", url: URL(fileURLWithPath: "/a/x.swift"), theme: t)
        XCTAssertTrue(swift.contains("data-language=\"Swift\"") && swift.contains("<span class=\"tok-keyword\">let</span>"), swift)
        let txt = HTMLExporter.html(for: "## 2026-10-30 (금) 14:05\nstatus: ok https://a.io", url: URL(fileURLWithPath: "/a/notes.txt"), theme: t)
        XCTAssertTrue(txt.contains("<span class=\"tok-title\">## 2026-10-30 (금) 14:05</span>"), txt)
        XCTAssertTrue(txt.contains("<span class=\"tok-property\">status</span>: ok <span class=\"tok-link\">https://a.io</span>"), txt)
    }

    func testLargeCodeDocumentExportsQuickly() throws {
        let t = try theme("hyper-dark")
        var text = ""
        for i in 1...30_000 { text += "## 2026-10-30 (금) 14:05 entry \(i)\n- [x] item https://example.com/\(i) ⇒ done **bold** `code`\n" }
        let start = CFAbsoluteTimeGetCurrent()
        let html = HTMLExporter.codeHTML(text, grammar: PlainNotesGrammar(markdown: false), theme: t, options: .init(lineNumbers: true))
        let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
        XCTAssertEqual(html.components(separatedBy: "class=\"ln\"").count - 1, 60_000)
        XCTAssertLessThan(ms, 3000, "export took \(ms) ms")
    }
}
