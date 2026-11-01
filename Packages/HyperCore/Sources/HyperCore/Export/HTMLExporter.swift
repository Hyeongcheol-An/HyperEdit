import Foundation

/// 문서 → 독립 HTML (파일 › Export as HTML… / PDF… 의 엔진). 순수 함수 — 앱은 결과 문자열을 파일로 쓰거나 WKWebView 에 올려 PDF 로 찍는다.
/// - 마크다운(.md 등): `MarkdownHTML` 의 독립 문서(미리보기 스크립트 없음 + 인쇄 스타일). 상대 이미지 경로는 그대로 두므로 HTML 을 원문 옆에 저장하면 맞는다.
/// - 그 밖(메모·코드): `<pre class="code">` 에 현재 문법(`GrammarRegistry`)의 토큰을 `<span class="tok-keyword">` 처럼 입히고 테마 `syntax` 색을 CSS 로.
///   선택하면 줄 번호 열(`.ln`). 줄 바꿈은 `pre-wrap` — 긴 줄은 접힌다(인쇄에서도 잘리지 않음).
/// - 원문은 전부 이스케이프되어 글자로만 들어간다(스크립트·외부 리소스 없음).
public enum HTMLExporter {
    public struct Options: Sendable, Equatable {
        /// 코드·메모용 줄 번호 열 (마크다운에는 영향 없음)
        public var lineNumbers = false
        /// `<title>` — 보통 파일 이름
        public var title: String?
        /// 마크다운 상대 경로의 기준 폴더. nil 이면 `<base>` 없이 — 저장한 HTML 파일 위치 기준으로 풀린다.
        public var baseURL: URL?
        public init(lineNumbers: Bool = false, title: String? = nil, baseURL: URL? = nil) {
            self.lineNumbers = lineNumbers; self.title = title; self.baseURL = baseURL
        }
    }

    /// 마크다운 파일인가 (GrammarRegistry 의 확장자 규칙과 같다)
    public static func isMarkdown(_ url: URL) -> Bool { (GrammarRegistry.grammar(for: url) as? PlainNotesGrammar)?.isMarkdown == true }

    /// 파일 종류에 따라 분기한 완전한 HTML 문서
    public static func html(for text: String, url: URL, theme: Theme, options: Options = Options()) -> String {
        if isMarkdown(url) { return markdownHTML(text, theme: theme, options: options) }
        return codeHTML(text, grammar: GrammarRegistry.grammar(for: url), theme: theme, options: options)
    }

    /// 마크다운 → 독립 HTML (`MarkdownHTML.html(... includeScript: false)` 와 같다)
    public static func markdownHTML(_ markdown: String, theme: Theme, options: Options = Options()) -> String {
        MarkdownHTML.html(for: markdown, theme: theme, baseURL: options.baseURL, title: options.title, includeScript: false)
    }

    // MARK: - 코드 · 메모

    /// 코드/메모 → 완전한 HTML 문서
    public static func codeHTML(_ text: String, grammar: any LanguageGrammar, theme: Theme, options: Options = Options()) -> String {
        let titleTag = options.title.map { "<title>\(MarkdownHTML.escape($0))</title>\n" } ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="color-scheme" content="\(theme.isDark ? "dark" : "light")">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(titleTag)<style>
        \(codeCSS(for: theme))
        </style>
        </head>
        <body>
        \(codeBody(text, grammar: grammar, lineNumbers: options.lineNumbers))
        </body>
        </html>
        """
    }

    /// `<pre class="code" data-language="…">` 본문. 줄 번호를 켜면 줄마다 `<span class="line"><span class="ln">n</span>…</span>` 블록
    /// (블록 사이에 개행을 두지 않는다 — pre-wrap 에서는 그 개행이 빈 줄로 보인다). 끄면 토큰 span 과 실제 개행만 — 복사하면 원문이 나온다.
    public static func codeBody(_ text: String, grammar: any LanguageGrammar, lineNumbers: Bool) -> String {
        let units = Array(text.utf16)
        let bounds = lineRanges(units)
        let digits = max(2, String(bounds.count).count)
        var out = ""
        out.reserveCapacity(units.count + units.count / 2 + 256)
        out += "<pre class=\"code\(lineNumbers ? " with-ln" : "")\" data-language=\"\(MarkdownHTML.escape(grammar.name))\""
        out += lineNumbers ? " style=\"--ln-w: \(digits)ch\">" : ">\n"   // HTML 파서는 <pre> 바로 뒤의 개행 하나를 버린다 → 첫 줄이 빈 줄이어도 보존
        units.withUnsafeBufferPointer { buf in
            var state = LineState.normal   // grammar: 줄 시작 상태 (블록 주석·여러 줄 문자열·펜스)
            for (i, r) in bounds.enumerated() {
                if lineNumbers { out += "<span class=\"line\"><span class=\"ln\">\(i + 1)</span>" }
                appendLine(buf, r, grammar: grammar, state: &state, to: &out)   // grammar: 블록 주석·여러 줄 문자열 상태를 줄 사이로 넘긴다
                if lineNumbers { out += "</span>" } else if i + 1 < bounds.count { out += "\n" }
            }
        }
        out += "</pre>"
        return out
    }

    /// 한 줄을 토큰 span 으로. 토큰은 문법이 스캔 순서대로 돌려주므로 정렬·비중첩이라고 보되, 어긋나는 것은 건너뛴다.
    private static func appendLine(_ buf: UnsafeBufferPointer<unichar>, _ r: Range<Int>, grammar: any LanguageGrammar, state: inout LineState, to out: inout String) {
        guard !r.isEmpty else { return }   // 빈 줄은 상태를 바꾸지 않는다
        let line = UnsafeBufferPointer(rebasing: buf[r])
        let scanned = grammar.scanLine(line, base: r.lowerBound, entering: state)
        state = scanned.exiting
        let tokens = scanned.tokens
        var pos = r.lowerBound
        for t in tokens {
            let s = t.range.location, e = NSMaxRange(t.range)
            guard s >= pos, e <= r.upperBound, e > s else { continue }
            if s > pos { out += escaped(buf, pos..<s) }
            out += "<span class=\"tok-\(t.kind.rawValue)\">\(escaped(buf, s..<e))</span>"
            pos = e
        }
        if pos < r.upperBound { out += escaped(buf, pos..<r.upperBound) }
    }

    private static func escaped(_ buf: UnsafeBufferPointer<unichar>, _ r: Range<Int>) -> String {
        MarkdownHTML.escape(String(utf16CodeUnits: buf.baseAddress! + r.lowerBound, count: r.count))
    }

    /// 줄 범위(개행 제외). `\n` `\r\n` `\r` 모두 구분자. 텍스트가 개행으로 끝나면 그 뒤의 빈 꼬리는 줄로 세지 않는다 ("a\nb\n" → 2줄).
    static func lineRanges(_ units: [unichar]) -> [Range<Int>] {
        var out: [Range<Int>] = []
        let n = units.count
        var start = 0, i = 0
        while i < n {
            let c = units[i]
            if c == 0x0A || c == 0x0D {
                out.append(start..<i)
                if c == 0x0D, i + 1 < n, units[i + 1] == 0x0A { i += 1 }
                start = i + 1
            }
            i += 1
        }
        if start < n || out.isEmpty { out.append(start..<n) }
        return out
    }

    /// 코드 문서 CSS: 테마 배경·본문색, 모노스페이스 스택(편집기와 같은 Fira Code · D2Coding 우선), 토큰 색(`syntax` 팔레트에 있는 종류만), 줄 번호 열, 인쇄 스타일
    public static func codeCSS(for theme: Theme) -> String {
        let bg = theme.background.hexString
        let fg = theme.foreground.hexString
        let muted = theme.foregroundMuted.hexString
        let dim = theme.foregroundDim.hexString
        let border = theme.border.hexString
        let selection = theme.selection.hexString
        let mono = #""Fira Code", "D2Coding", "SF Mono", Menlo, Monaco, Consolas, "Apple SD Gothic Neo", monospace"#
        var tokens = ""
        for kind in TokenKind.allCases {
            guard let c = theme.syntax[kind.themeKey] else { continue }
            tokens += ".tok-\(kind.rawValue) { color: \(c.hexString); }\n"
        }
        return """
        :root { color-scheme: \(theme.isDark ? "dark" : "light"); }
        html { background: \(bg); }
        body { margin: 0; padding: 18px 24px 40px; background: \(bg); color: \(fg); font-family: \(mono); font-size: 13px; line-height: 1.5; -webkit-text-size-adjust: 100%; font-variant-ligatures: contextual; }
        pre.code { margin: 0; font: inherit; white-space: pre-wrap; overflow-wrap: anywhere; tab-size: 4; -moz-tab-size: 4; }
        pre.code.with-ln .line { display: block; position: relative; padding-left: calc(var(--ln-w, 3ch) + 1.4em); min-height: 1.5em; }
        pre.code.with-ln .ln { position: absolute; left: 0; top: 0; width: var(--ln-w, 3ch); text-align: right; color: \(dim); -webkit-user-select: none; user-select: none; }
        pre.code.with-ln .line::before { content: ""; position: absolute; left: calc(var(--ln-w, 3ch) + 0.6em); top: 0; bottom: 0; border-left: 1px solid \(border); }
        \(tokens)a { color: inherit; }
        ::selection { background: \(selection); }
        @media print {
          html, body { background: \(bg); -webkit-print-color-adjust: exact; print-color-adjust: exact; }
          body { padding: 0; font-size: 11px; }
          pre.code.with-ln .ln { color: \(muted); }
        }
        """
    }
}
