import Foundation
import Markdown

/// GFM 마크다운 → HTML 변환기 (분할 미리보기용). Apple swift-markdown(cmark-gfm) 으로 파싱한 트리를 `MarkupVisitor` 로 순회한다.
/// - 모든 블록 요소에 `data-line="<1-based 소스 줄>"` 을 붙여 편집기 → 미리보기 스크롤 동기화에 쓴다.
/// - 원문의 HTML 블록·인라인 HTML 은 **이스케이프해 글자로** 보여 준다 (원시 HTML 주입 없음).
/// - 링크는 http/https/mailto 만 `<a>`, 나머지는 글자로. 이미지는 상대 경로(문서 폴더 기준 `<base href>`)와 http/https 만.
public enum MarkdownHTML {
    /// 본문 조각만 (문서 래퍼·스타일 없음).
    public static func body(for markdown: String) -> String {
        // 스마트 문장부호(따옴표 → 곡선 따옴표, -- → 대시)는 GitHub 처럼 끈다: 원문 그대로 보여 주는 편이 편집기 옆 미리보기에 맞다
        let doc = Document(parsing: markdown, options: [.disableSmartOpts])
        var visitor = HTMLVisitor()
        return visitor.visit(doc)
    }

    /// 테마 스타일·스크롤 동기화 스크립트가 포함된 완전한 HTML 문서.
    /// - baseURL: 문서가 있는 폴더 — 상대 경로 이미지가 이 폴더 기준으로 풀린다 (`<base href>`).
    public static func html(for markdown: String, theme: Theme, baseURL: URL?) -> String {
        var base = ""
        if let u = baseURL {
            var s = u.absoluteString
            if !s.hasSuffix("/") { s += "/" }
            base = "<base href=\"\(escape(s))\">\n"
        }
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="\(theme.isDark ? "dark" : "light")">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(base)<style>
        \(css(for: theme))
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(body(for: markdown))
        </article>
        <script>
        \(script)
        </script>
        </body>
        </html>
        """
    }

    // MARK: - 스타일

    /// 팔레트에서 유도한 CSS. 제목 = syntax.title(없으면 accent), 링크 = syntax.link, 코드 배경 = backgroundAlt, 인용 테두리 = border.
    public static func css(for theme: Theme) -> String {
        let bg = theme.background.hexString
        let fg = theme.foreground.hexString
        let muted = theme.foregroundMuted.hexString
        let border = theme.border.hexString
        let accent = theme.accent.hexString
        let codeBg = codeBackground(for: theme).hexString
        let title = (theme.syntax["title"] ?? theme.accent).hexString
        let link = (theme.syntax["link"] ?? theme.accent).hexString
        let selection = theme.selection.hexString
        let stripe = theme.background.mix(theme.foreground, 0.035).hexString
        let prose = #"-apple-system, BlinkMacSystemFont, "SF Pro Text", "Apple SD Gothic Neo", "Helvetica Neue", Helvetica, Arial, sans-serif"#
        let mono = #""Fira Code", "D2Coding", "SF Mono", Menlo, Monaco, Consolas, "Apple SD Gothic Neo", monospace"#
        return """
        :root { color-scheme: \(theme.isDark ? "dark" : "light"); }
        html { scroll-behavior: auto; background: \(bg); }
        body { margin: 0; padding: 18px 28px 56px; background: \(bg); color: \(fg); font-family: \(prose); font-size: 15px; line-height: 1.65; -webkit-text-size-adjust: 100%; overflow-wrap: break-word; }
        .markdown-body { max-width: 880px; margin: 0 auto; }
        .markdown-body > :first-child { margin-top: 0; }
        h1, h2, h3, h4, h5, h6 { color: \(title); font-weight: 600; line-height: 1.3; margin: 1.5em 0 0.6em; }
        h1 { font-size: 1.85em; padding-bottom: 0.3em; border-bottom: 1px solid \(border); }
        h2 { font-size: 1.45em; padding-bottom: 0.25em; border-bottom: 1px solid \(border); }
        h3 { font-size: 1.2em; }
        h4 { font-size: 1.05em; }
        h5, h6 { font-size: 1em; color: \(muted); }
        p { margin: 0 0 1em; }
        a { color: \(link); text-decoration: none; }
        a:hover { text-decoration: underline; }
        strong { font-weight: 600; }
        del { color: \(muted); }
        code, pre, kbd { font-family: \(mono); }
        code { font-size: 0.88em; background: \(codeBg); border-radius: 4px; padding: 0.15em 0.4em; }
        pre { margin: 0 0 1em; padding: 12px 14px; background: \(codeBg); border: 1px solid \(border); border-radius: 6px; overflow-x: auto; line-height: 1.5; }
        pre code { display: block; padding: 0; background: none; border-radius: 0; font-size: 0.86em; white-space: pre; }
        blockquote { margin: 0 0 1em; padding: 0.25em 1em; border-left: 4px solid \(border); color: \(muted); }
        blockquote > :last-child { margin-bottom: 0; }
        ul, ol { margin: 0 0 1em; padding-left: 1.8em; }
        li { margin: 0.2em 0; }
        li > ul, li > ol, li > p:last-child { margin-bottom: 0; }
        li > p { margin-bottom: 0.5em; }
        ul.task-list { list-style: none; padding-left: 0.5em; }
        li.task > input[type=checkbox] { margin: 0 0.55em 0 0; vertical-align: -0.12em; accent-color: \(accent); }
        table { border-collapse: collapse; border-spacing: 0; margin: 0 0 1em; display: block; max-width: 100%; overflow-x: auto; }
        th, td { border: 1px solid \(border); padding: 6px 12px; text-align: left; vertical-align: top; }
        th { background: \(codeBg); font-weight: 600; }
        tbody tr:nth-child(even) td { background: \(stripe); }
        hr { border: 0; border-top: 2px solid \(border); margin: 1.6em 0; }
        img { max-width: 100%; height: auto; }
        .raw-html { font-family: \(mono); font-size: 0.86em; color: \(muted); white-space: pre-wrap; }
        p.raw-html { margin: 0 0 1em; padding: 8px 12px; background: \(codeBg); border-radius: 6px; }
        ::selection { background: \(selection); }
        """
    }

    /// 코드·표 머리글 배경. 팔레트의 bg_alt 가 본문 배경과 거의 같으면(라이트 테마) 조금 더 띄운다.
    static func codeBackground(for theme: Theme) -> RGBA {
        let alt = theme.backgroundAlt
        let contrast = abs(alt.luminance - theme.background.luminance)
        return contrast < 0.03 ? theme.background.mix(theme.foreground, theme.isDark ? 0.08 : 0.06) : alt
    }

    // MARK: - 스크립트

    /// `window.scrollToLine(n)`: n 이하의 가장 가까운 `[data-line]` 요소로 즉시 스크롤 (다음 블록까지 줄 비율로 보간).
    /// 링크 클릭은 탐색하지 않고 `webkit.messageHandlers.link` 로 href 를 보낸다 (앱이 기본 브라우저로 연다).
    static let script = """
    (function () {
      var blocks = null;
      function collect() {
        blocks = [];
        var els = document.querySelectorAll('[data-line]');
        for (var i = 0; i < els.length; i++) {
          var n = parseInt(els[i].getAttribute('data-line'), 10);
          if (!isNaN(n)) blocks.push({ line: n, el: els[i] });
        }
        blocks.sort(function (a, b) { return a.line - b.line; });
      }
      function top(el) { return el.getBoundingClientRect().top + window.scrollY; }
      window.scrollToLine = function (n) {
        if (!blocks) collect();
        if (!blocks.length || n <= 1) { window.scrollTo(0, 0); return; }
        var best = -1;
        for (var i = 0; i < blocks.length; i++) { if (blocks[i].line <= n) best = i; else break; }
        if (best < 0) { window.scrollTo(0, 0); return; }
        var y = top(blocks[best].el);
        var next = best + 1 < blocks.length ? blocks[best] : null;
        for (var j = best + 1; j < blocks.length; j++) { if (blocks[j].line > blocks[best].line) { next = blocks[j]; break; } }
        if (next && next.line > blocks[best].line) {
          var f = (n - blocks[best].line) / (next.line - blocks[best].line);
          y += Math.max(0, Math.min(1, f)) * (top(next.el) - y);
        }
        window.scrollTo(0, Math.max(0, y - 12));
      };
      document.addEventListener('click', function (e) {
        var t = e.target;
        while (t && t.nodeType === 1 && t.tagName !== 'A') t = t.parentNode;
        if (!t || t.nodeType !== 1 || !t.getAttribute('href')) return;
        e.preventDefault();
        try { window.webkit.messageHandlers.link.postMessage(t.href); } catch (err) {}
      }, true);
    })();
    """

    // MARK: - 보조

    /// HTML 텍스트/속성 이스케이프.
    public static func escape(_ s: String) -> String {
        var needs = false
        for u in s.utf8 where u == 38 || u == 60 || u == 62 || u == 34 || u == 39 { needs = true; break }
        guard needs else { return s }
        var out = ""
        out.reserveCapacity(s.utf8.count + 16)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(ch)
            }
        }
        return out
    }

    /// `scheme:` 접두사 (RFC 3986 문법에 맞을 때만, 소문자). 없으면 nil — 상대 경로.
    static func scheme(of s: String) -> String? {
        var it = s.unicodeScalars.makeIterator()
        guard let first = it.next(), first.properties.isAlphabetic, first.isASCII else { return nil }
        var scheme = String(first)
        while let c = it.next() {
            if c == ":" { return scheme.lowercased() }
            guard c.isASCII, c.properties.isAlphabetic || ("0"..."9").contains(c) || c == "+" || c == "-" || c == "." else { return nil }
            scheme.unicodeScalars.append(c)
        }
        return nil
    }

    /// 맨 URL(http/https) 을 `<a>` 로 — GFM 자동 링크의 단순판 (swift-markdown 은 cmark-gfm 의 autolink 확장을 붙이지 않는다).
    /// GitHub 처럼 끝의 문장부호와 짝이 없는 `)` 는 링크에서 뺀다. 결과는 이스케이프된 HTML.
    nonisolated(unsafe) static let bareURL = try! NSRegularExpression(pattern: #"https?://[^\s<>"'`]+"#)
    public static func autolinkedHTML(_ text: String) -> String {
        guard text.contains("http") else { return escape(text) }
        let ns = text as NSString
        let matches = bareURL.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return escape(text) }
        var out = ""
        var pos = 0
        for m in matches {
            var url = ns.substring(with: m.range)
            while let last = url.last {
                if ".,:;!?*_~'\"".contains(last) { url.removeLast(); continue }
                if last == ")", url.filter({ $0 == ")" }).count > url.filter({ $0 == "(" }).count { url.removeLast(); continue }
                break
            }
            let len = (url as NSString).length
            guard len > 8, url.contains("://"), url.range(of: "://")?.upperBound != url.endIndex else { continue }
            out += escape(ns.substring(with: NSRange(location: pos, length: m.range.location - pos)))
            out += "<a href=\"\(escape(url))\">\(escape(url))</a>"
            pos = m.range.location + len
        }
        out += escape(ns.substring(from: pos))
        return out
    }

    /// 링크로 허용: http / https / mailto
    public static func isAllowedLink(_ destination: String) -> Bool {
        guard let s = scheme(of: destination) else { return false }
        return s == "http" || s == "https" || s == "mailto"
    }

    /// 이미지로 허용: 상대·절대 경로(스킴 없음) 또는 http / https
    public static func isAllowedImage(_ source: String) -> Bool {
        guard let s = scheme(of: source) else { return !source.isEmpty }
        return s == "http" || s == "https"
    }
}

// MARK: - 방문자

struct HTMLVisitor: MarkupVisitor {
    typealias Result = String

    private var inTableHead = false
    private var columnAlignments: [Table.ColumnAlignment?] = []
    /// 명시적 링크 안에서는 맨 URL 을 다시 링크로 만들지 않는다
    private var linkDepth = 0

    private func esc(_ s: String) -> String { MarkdownHTML.escape(s) }

    /// `data-line` 속성 — 블록의 소스 시작 줄(1-based)
    private func line(_ m: Markup) -> String {
        guard let r = m.range else { return "" }
        return " data-line=\"\(r.lowerBound.line)\""
    }

    private mutating func children(_ m: Markup) -> String {
        var s = ""
        for c in m.children { s += visit(c) }
        return s
    }

    mutating func defaultVisit(_ markup: Markup) -> String { children(markup) }

    // 블록

    mutating func visitDocument(_ d: Document) -> String { children(d) }

    mutating func visitHeading(_ h: Heading) -> String {
        let level = max(1, min(6, h.level))
        return "<h\(level)\(line(h))>\(children(h))</h\(level)>\n"
    }

    mutating func visitParagraph(_ p: Paragraph) -> String { "<p\(line(p))>\(children(p))</p>\n" }

    mutating func visitBlockQuote(_ q: BlockQuote) -> String { "<blockquote\(line(q))>\n\(children(q))</blockquote>\n" }

    mutating func visitCodeBlock(_ c: CodeBlock) -> String {
        var cls = ""
        if let info = c.language?.split(whereSeparator: { $0 == " " || $0 == "\t" }).first, !info.isEmpty {
            cls = " class=\"lang-\(esc(String(info)))\""
        }
        var code = c.code
        if code.hasSuffix("\n") { code.removeLast() }
        return "<pre\(line(c))><code\(cls)>\(esc(code))</code></pre>\n"
    }

    /// 원시 HTML 은 실행하지 않고 글자로 보여 준다
    mutating func visitHTMLBlock(_ h: HTMLBlock) -> String {
        var raw = h.rawHTML
        if raw.hasSuffix("\n") { raw.removeLast() }
        return "<p\(line(h)) class=\"raw-html\">\(esc(raw))</p>\n"
    }

    mutating func visitThematicBreak(_ t: ThematicBreak) -> String { "<hr\(line(t))>\n" }

    mutating func visitUnorderedList(_ l: UnorderedList) -> String {
        let task = l.children.contains { ($0 as? ListItem)?.checkbox != nil }
        return "<ul\(line(l))\(task ? " class=\"task-list\"" : "")>\n\(children(l))</ul>\n"
    }

    mutating func visitOrderedList(_ l: OrderedList) -> String {
        let start = l.startIndex != 1 ? " start=\"\(l.startIndex)\"" : ""
        return "<ol\(line(l))\(start)>\n\(children(l))</ol>\n"
    }

    mutating func visitListItem(_ li: ListItem) -> String {
        // swift-markdown 은 목록의 tight/loose 를 노출하지 않는다 → 문단이 하나뿐인 항목은 <p> 없이 (GitHub 의 tight 목록과 같은 모양)
        let paragraphCount = li.children.reduce(0) { $0 + ($1 is Paragraph ? 1 : 0) }
        var body = ""
        for c in li.children {
            if paragraphCount == 1, let p = c as? Paragraph { body += children(p) } else { body += visit(c) }
        }
        var prefix = "", cls = ""
        if let box = li.checkbox {
            cls = " class=\"task\""
            prefix = "<input type=\"checkbox\" disabled\(box == .checked ? " checked" : "")> "
        }
        return "<li\(line(li))\(cls)>\(prefix)\(body)</li>\n"
    }

    // 표

    mutating func visitTable(_ t: Table) -> String {
        let savedAlign = columnAlignments
        columnAlignments = t.columnAlignments
        defer { columnAlignments = savedAlign }
        var s = "<table\(line(t))>\n"
        s += visit(t.head)
        if t.body.childCount > 0 { s += visit(t.body) }
        s += "</table>\n"
        return s
    }

    mutating func visitTableHead(_ h: Table.Head) -> String {
        inTableHead = true
        defer { inTableHead = false }
        return "<thead>\n<tr\(line(h))>\(children(h))</tr>\n</thead>\n"
    }

    mutating func visitTableBody(_ b: Table.Body) -> String { "<tbody>\n\(children(b))</tbody>\n" }

    mutating func visitTableRow(_ r: Table.Row) -> String { "<tr\(line(r))>\(children(r))</tr>\n" }

    mutating func visitTableCell(_ c: Table.Cell) -> String {
        // colspan/rowspan 0 = 다른 셀의 병합 범위에 덮인 자리 → 출력하지 않는다
        guard c.colspan > 0, c.rowspan > 0 else { return "" }
        let tag = inTableHead ? "th" : "td"
        var attrs = ""
        if c.colspan > 1 { attrs += " colspan=\"\(c.colspan)\"" }
        if c.rowspan > 1 { attrs += " rowspan=\"\(c.rowspan)\"" }
        let i = c.indexInParent
        if i < columnAlignments.count, let a = columnAlignments[i] {
            switch a {
            case .left: attrs += " style=\"text-align: left\""
            case .center: attrs += " style=\"text-align: center\""
            case .right: attrs += " style=\"text-align: right\""
            }
        }
        return "<\(tag)\(attrs)>\(children(c))</\(tag)>"
    }

    // 인라인

    mutating func visitText(_ t: Text) -> String { linkDepth > 0 ? esc(t.string) : MarkdownHTML.autolinkedHTML(t.string) }
    mutating func visitEmphasis(_ e: Emphasis) -> String { "<em>\(children(e))</em>" }
    mutating func visitStrong(_ s: Strong) -> String { "<strong>\(children(s))</strong>" }
    mutating func visitStrikethrough(_ s: Strikethrough) -> String { "<del>\(children(s))</del>" }
    mutating func visitInlineCode(_ c: InlineCode) -> String { "<code>\(esc(c.code))</code>" }
    mutating func visitInlineHTML(_ h: InlineHTML) -> String { "<span class=\"raw-html\">\(esc(h.rawHTML))</span>" }
    mutating func visitSoftBreak(_ b: SoftBreak) -> String { "\n" }
    mutating func visitLineBreak(_ b: LineBreak) -> String { "<br>\n" }

    mutating func visitLink(_ l: Link) -> String {
        linkDepth += 1
        let inner = children(l)
        linkDepth -= 1
        guard let dest = l.destination, MarkdownHTML.isAllowedLink(dest) else { return inner }   // 허용되지 않은 스킴·상대 경로는 글자로
        let title = l.title.map { " title=\"\(esc($0))\"" } ?? ""
        return "<a href=\"\(esc(dest))\"\(title)>\(inner)</a>"
    }

    mutating func visitImage(_ i: Image) -> String {
        let alt = esc(i.plainText)
        guard let src = i.source, MarkdownHTML.isAllowedImage(src) else { return alt }
        let title = i.title.map { " title=\"\(esc($0))\"" } ?? ""
        return "<img src=\"\(esc(src))\" alt=\"\(alt)\"\(title)>"
    }

    mutating func visitSymbolLink(_ s: SymbolLink) -> String { "<code>\(esc(s.destination ?? ""))</code>" }
    mutating func visitInlineAttributes(_ a: InlineAttributes) -> String { children(a) }
    mutating func visitBlockDirective(_ d: BlockDirective) -> String { children(d) }
    mutating func visitCustomBlock(_ b: CustomBlock) -> String { children(b) }
    mutating func visitCustomInline(_ i: CustomInline) -> String { children(i) }
}
