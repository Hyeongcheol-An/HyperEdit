import XCTest
@testable import HyperCore

final class MarkdownHTMLTests: XCTestCase {
    func testHeadingsParagraphsAndInlines() {
        let html = MarkdownHTML.body(for: "# Title\n\nSome *em* and **strong** and ~~gone~~ and `code`.\n\n### H3\n")
        XCTAssertTrue(html.contains("<h1 data-line=\"1\">Title</h1>"), html)
        XCTAssertTrue(html.contains("<p data-line=\"3\">Some <em>em</em> and <strong>strong</strong> and <del>gone</del> and <code>code</code>.</p>"), html)
        XCTAssertTrue(html.contains("<h3 data-line=\"5\">H3</h3>"), html)
    }

    func testListsAndTaskList() {
        let md = """
        - one
        - two
          - nested
        3. three
        4. four

        - [ ] open
        - [x] done
        """
        let html = MarkdownHTML.body(for: md)
        XCTAssertTrue(html.contains("<ul data-line=\"1\">"), html)
        XCTAssertTrue(html.contains("<li data-line=\"1\">one</li>"), html)            // tight item: no <p>
        XCTAssertTrue(html.contains("<li data-line=\"3\">nested</li>"), html)
        XCTAssertTrue(html.contains("<ol data-line=\"4\" start=\"3\">"), html)
        XCTAssertTrue(html.contains("<ul data-line=\"7\" class=\"task-list\">"), html)
        XCTAssertTrue(html.contains("<li data-line=\"7\" class=\"task\"><input type=\"checkbox\" disabled> open</li>"), html)
        XCTAssertTrue(html.contains("<li data-line=\"8\" class=\"task\"><input type=\"checkbox\" disabled checked> done</li>"), html)
    }

    func testTable() {
        let md = """
        | Name | Qty | Note |
        |:-----|----:|:----:|
        | a    | 1   | x    |
        | b    | 22  | y    |
        """
        let html = MarkdownHTML.body(for: md)
        XCTAssertTrue(html.contains("<table data-line=\"1\">"), html)
        XCTAssertTrue(html.contains("<th style=\"text-align: left\">Name</th><th style=\"text-align: right\">Qty</th><th style=\"text-align: center\">Note</th>"), html)
        XCTAssertTrue(html.contains("<tr data-line=\"3\"><td style=\"text-align: left\">a</td><td style=\"text-align: right\">1</td><td style=\"text-align: center\">x</td></tr>"), html)
        XCTAssertTrue(html.contains("<tr data-line=\"4\">"), html)
        XCTAssertEqual(html.components(separatedBy: "<tr").count - 1, 3)
    }

    func testCodeBlockEscapesAndLanguageClass() {
        let html = MarkdownHTML.body(for: "```swift\nlet a = \"<b>\" && 1 > 0\n```\n")
        XCTAssertTrue(html.contains("<pre data-line=\"1\"><code class=\"lang-swift\">let a = &quot;&lt;b&gt;&quot; &amp;&amp; 1 &gt; 0</code></pre>"), html)
        XCTAssertFalse(html.contains("<b>"), html)
        let plain = MarkdownHTML.body(for: "    indented\n")
        XCTAssertTrue(plain.contains("<pre data-line=\"1\"><code>indented</code></pre>"), plain)
    }

    func testRawHTMLIsEscapedNotInjected() {
        let html = MarkdownHTML.body(for: "<script>alert(1)</script>\n\nInline <img src=x onerror=alert(1)> here\n")
        XCTAssertFalse(html.contains("<script>"), html)
        XCTAssertFalse(html.contains("<img src=x"), html)
        XCTAssertTrue(html.contains("<p data-line=\"1\" class=\"raw-html\">&lt;script&gt;alert(1)&lt;/script&gt;</p>"), html)
        XCTAssertTrue(html.contains("<span class=\"raw-html\">&lt;img src=x onerror=alert(1)&gt;</span>"), html)
    }

    func testLinkFiltering() {
        let md = "[ok](https://example.com/a?b=1&c=2 \"T\") [mail](mailto:a@b.c) [js](javascript:alert(1)) [rel](docs/x.md) [file](file:///etc/passwd)\n"
        let html = MarkdownHTML.body(for: md)
        XCTAssertTrue(html.contains("<a href=\"https://example.com/a?b=1&amp;c=2\" title=\"T\">ok</a>"), html)
        XCTAssertTrue(html.contains("<a href=\"mailto:a@b.c\">mail</a>"), html)
        XCTAssertFalse(html.contains("javascript:"), html)
        XCTAssertFalse(html.contains("file:"), html)
        XCTAssertFalse(html.contains("docs/x.md"), html)
        XCTAssertTrue(html.contains(" js ") && html.contains(" rel ") && html.contains("file</p>"), html)
    }

    func testBareURLsAreAutolinked() {
        let html = MarkdownHTML.body(for: "see https://example.com/a_(b). and (https://x.y/z?q=1&r=2) end\n\n[https://a.b](https://a.b) and `https://not.a/link`\n\nhttp://한글.kr/경로, done\n")
        XCTAssertTrue(html.contains("see <a href=\"https://example.com/a_(b)\">https://example.com/a_(b)</a>. and (<a href=\"https://x.y/z?q=1&amp;r=2\">https://x.y/z?q=1&amp;r=2</a>) end"), html)
        XCTAssertEqual(html.components(separatedBy: "<a href=\"https://a.b\"").count - 1, 1, html)   // 명시적 링크 안은 그대로
        XCTAssertTrue(html.contains("<code>https://not.a/link</code>"), html)
        XCTAssertTrue(html.contains("<a href=\"http://한글.kr/경로\">http://한글.kr/경로</a>, done"), html)
        XCTAssertEqual(MarkdownHTML.autolinkedHTML("bare https:// nothing"), "bare https:// nothing")
        XCTAssertEqual(MarkdownHTML.autolinkedHTML("a < b"), "a &lt; b")
    }

    func testImages() {
        let html = MarkdownHTML.body(for: "![alt text](img/a.png \"cap\") ![remote](https://x.y/z.png) ![bad](javascript:x) ![data](data:image/png;base64,AAAA)\n")
        XCTAssertTrue(html.contains("<img src=\"img/a.png\" alt=\"alt text\" title=\"cap\">"), html)
        XCTAssertTrue(html.contains("<img src=\"https://x.y/z.png\" alt=\"remote\">"), html)
        XCTAssertFalse(html.contains("javascript:"), html)
        XCTAssertFalse(html.contains("data:image"), html)
        XCTAssertTrue(html.contains(" bad ") && html.contains("data</p>"), html)
    }

    func testBlockQuoteBreaksAndRule() {
        let html = MarkdownHTML.body(for: "> quoted\n> line two\n\nhard  \nbreak\nsoft\n\n---\n")
        XCTAssertTrue(html.contains("<blockquote data-line=\"1\">\n<p data-line=\"1\">quoted\nline two</p>\n</blockquote>"), html)
        XCTAssertTrue(html.contains("hard<br>\nbreak\nsoft"), html)
        XCTAssertTrue(html.contains("<hr data-line=\"8\">"), html)
    }

    func testFullDocumentWrapsThemeAndBase() throws {
        let themes = try ThemeStore.loadBundled()
        let dark = try XCTUnwrap(themes.first { $0.id == "hyper-dark" })
        let light = try XCTUnwrap(themes.first { $0.id == "hyper-light" })
        let html = MarkdownHTML.html(for: "# 한글 제목\n\n본문 <tag>", theme: dark, baseURL: URL(fileURLWithPath: "/tmp/docs", isDirectory: true))
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains("<meta name=\"color-scheme\" content=\"dark\">"), html)
        XCTAssertTrue(html.contains("<base href=\"file:///tmp/docs/\">"), html)
        XCTAssertTrue(html.contains("background: \(dark.background.hexString)"), html)
        XCTAssertTrue(html.contains("<h1 data-line=\"1\">한글 제목</h1>"), html)
        XCTAssertTrue(html.contains("본문 <span class=\"raw-html\">&lt;tag&gt;</span>"), html)   // <tag> 는 인라인 HTML → 이스케이프
        XCTAssertFalse(html.contains("<tag>"), html)
        XCTAssertTrue(html.contains("window.scrollToLine = function"), html)
        XCTAssertTrue(html.contains("messageHandlers.link"), html)
        let lightHTML = MarkdownHTML.html(for: "x", theme: light, baseURL: nil)
        XCTAssertTrue(lightHTML.contains("content=\"light\""), lightHTML)
        XCTAssertFalse(lightHTML.contains("<base "), lightHTML)
    }

    func testEscapeAndSchemes() {
        XCTAssertEqual(MarkdownHTML.escape("a<b>&\"'"), "a&lt;b&gt;&amp;&quot;&#39;")
        XCTAssertEqual(MarkdownHTML.escape("plain 한글"), "plain 한글")
        XCTAssertTrue(MarkdownHTML.isAllowedLink("HTTP://X"))
        XCTAssertFalse(MarkdownHTML.isAllowedLink("ftp://x"))
        XCTAssertFalse(MarkdownHTML.isAllowedLink("#anchor"))
        XCTAssertFalse(MarkdownHTML.isAllowedLink("C:/x"))          // 한 글자 스킴도 스킴이지만 허용 목록에 없음
        XCTAssertTrue(MarkdownHTML.isAllowedImage("../a.png"))
        XCTAssertTrue(MarkdownHTML.isAllowedImage("/abs/a.png"))
        XCTAssertFalse(MarkdownHTML.isAllowedImage("file:///a.png"))
        XCTAssertFalse(MarkdownHTML.isAllowedImage(""))
    }

    func testLargeDocumentRendersQuickly() {
        var md = ""
        for i in 1...4000 { md += "## Heading \(i)\n\nParagraph \(i) with `code` and **bold** text.\n\n- item a\n- item b\n\n" }
        let t = CFAbsoluteTimeGetCurrent()
        let html = MarkdownHTML.body(for: md)
        let ms = (CFAbsoluteTimeGetCurrent() - t) * 1000
        XCTAssertTrue(html.contains("<h2 data-line=\"1\">Heading 1</h2>"))
        XCTAssertLessThan(ms, 4000, "render took \(ms) ms")
    }
}
