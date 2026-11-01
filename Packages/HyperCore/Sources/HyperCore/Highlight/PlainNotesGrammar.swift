import Foundation

/// 메모·마크다운용 가벼운 규칙. 1.3 MB 메모 파일에서 쓰이는 기본 문법이므로 정규식 없이 한 번 훑는다.
/// - 헤딩 `# …` → title (줄 전체; 메모 모드에서는 코드 주석처럼 보이는 `# from x import` 는 comment)
/// - `[제목]` 줄머리 괄호 → title · 목록 기호 `- * +` / `1)` `1.` → punctuation · 체크박스 `[ ]` `[x]` → special
/// - URL → link · ISO 날짜 `2026-10-30`, 시각 `14:05` → number · `#태그` → attribute · `키: 값` 의 키 → property
/// - `**굵게**` → constant · `` `코드` `` → string · `⇒ → ← ↔ => ->` → operator · `✓ ✗ ☐ ☑` → special
/// - 마크다운 모드의 여러 줄 상태: 펜스(``` / ~~~) 안은 `.fence` — 정보 문자열이 `GrammarRegistry` 가 아는 코드 언어면 그 문법으로 토큰화하고(GitHub 처럼),
///   모르면 메모 규칙을 끄고 색 없음. HTML 주석 `<!-- … -->` 도 줄을 넘어간다(`.blockComment`). 메모 모드(.txt)는 상태가 없다.
public struct PlainNotesGrammar: LanguageGrammar {
    public let isMarkdown: Bool
    public var name: String { isMarkdown ? "Markdown" : "Notes" }
    public var tracksLineState: Bool { isMarkdown }

    public init(markdown: Bool = false) { isMarkdown = markdown }

    private static let http = CharClass.units("http://")
    private static let https = CharClass.units("https://")
    static let commentOpen = CharClass.units("<!--")
    static let commentClose = CharClass.units("-->")
    /// 메모 파일의 `# ` 줄이 헤딩이 아니라 코드 주석일 때의 첫 단어 (OutlineScanner.codeLike 와 같은 취지)
    private static let codeLikeWords: Set<String> = ["from", "import", "print", "def", "class", "return", "if", "for", "while", "else", "elif", "try", "except", "with", "export", "sudo", "pip", "brew", "git", "cd", "ls", "python", "python3", "echo", "docker", "kubectl", "ssh", "curl", "npm", "yarn"]

    public func scanLine(_ buf: UnsafeBufferPointer<unichar>, base: Int, entering: LineState) -> (tokens: [Token], exiting: LineState) {
        var out: [Token] = []
        let exit = scan(buf, base, entering, emit: true, into: &out)
        return (out, exit)
    }

    public func exitState(line buf: UnsafeBufferPointer<unichar>, entering: LineState) -> LineState {
        var out: [Token] = []
        return scan(buf, 0, entering, emit: false, into: &out)
    }

    /// 펜스 정보 문자열 → 중첩할 코드 문법 (사용자 문법 포함). 모르면 nil = 펜스 안은 색 없음
    static func nestedGrammar(_ language: String?) -> CodeGrammar? {
        guard let language, !language.isEmpty else { return nil }
        return GrammarRegistry.grammar(forFenceLanguage: language)
    }

    private func scan(_ buf: UnsafeBufferPointer<unichar>, _ base: Int, _ entering: LineState, emit: Bool, into out: inout [Token]) -> LineState {
        let n = buf.count
        if isMarkdown {
            switch entering {
            case .fence(let marker, let length, let language, let inner):
                if Self.isClosingFence(buf, marker: marker, length: length) {
                    if emit, n > 0 { out.append(Token(location: base, length: n, kind: .punctuation)) }
                    return .normal
                }
                guard let nested = Self.nestedGrammar(language) else { return entering }
                if emit {
                    let r = nested.scanLine(buf, base: base, entering: inner)
                    out.append(contentsOf: r.tokens)
                    return .fence(marker: marker, length: length, language: language, inner: r.exiting)
                }
                return .fence(marker: marker, length: length, language: language, inner: nested.exitState(line: buf, entering: inner))
            case .blockComment:
                guard let e = CharClass.find(Self.commentClose, in: buf, from: 0) else {
                    if emit, n > 0 { out.append(Token(location: base, length: n, kind: .comment)) }
                    return .blockComment
                }
                if emit { out.append(Token(location: base, length: e, kind: .comment)) }
                guard e < n else { return .normal }
                return scanNormal(UnsafeBufferPointer(rebasing: buf[e...]), base + e, emit: emit, into: &out)
            default: break
            }
        }
        return scanNormal(buf, base, emit: emit, into: &out)
    }

    /// 닫는 펜스: 같은 기호가 여는 펜스 길이 이상 이어지고 뒤에는 공백뿐
    private static func isClosingFence(_ buf: UnsafeBufferPointer<unichar>, marker: UInt8, length: UInt8) -> Bool {
        let n = buf.count
        var i = 0
        while i < n, CharClass.isSpace(buf[i]) { i += 1 }
        var j = i
        while j < n, buf[j] == unichar(marker) { j += 1 }
        guard j - i >= Int(length), j - i >= 3 else { return false }
        while j < n { if !CharClass.isSpace(buf[j]) { return false }; j += 1 }
        return true
    }

    /// 여는 펜스의 정보 문자열 첫 단어 (소문자). `{` 나 공백 앞까지. 없으면 nil
    private static func infoLanguage(_ buf: UnsafeBufferPointer<unichar>, from: Int) -> String? {
        let n = buf.count
        var i = from
        while i < n, CharClass.isSpace(buf[i]) { i += 1 }
        var j = i
        while j < n, !CharClass.isSpace(buf[j]), buf[j] != 0x7B, j - i < 32 { j += 1 }
        guard j > i else { return nil }
        return CharClass.string(buf, i, j).lowercased()
    }

    private func scanNormal(_ buf: UnsafeBufferPointer<unichar>, _ base: Int, emit: Bool, into out: inout [Token]) -> LineState {
        let n = buf.count
        guard n > 0 else { return .normal }
        @inline(__always) func c(_ i: Int) -> unichar { i < n ? buf[i] : 0 }
        @inline(__always) func add(_ from: Int, _ to: Int, _ k: TokenKind) { if emit, to > from { out.append(Token(location: base + from, length: to - from, kind: k)) } }

        var i = 0
        while i < n, CharClass.isSpace(buf[i]) { i += 1 }
        guard i < n else { return .normal }

        // 헤딩: `#{1,6}` + 공백 → 줄 전체
        if buf[i] == 0x23 {
            var j = i
            while j < n, buf[j] == 0x23, j - i < 7 { j += 1 }
            let hashes = j - i
            if hashes <= 6, j < n, CharClass.isSpace(buf[j]) {
                var k = j
                while k < n, CharClass.isSpace(buf[k]) { k += 1 }
                var kind = TokenKind.title
                if !isMarkdown, hashes == 1 {
                    // `# from pymongo import …` 처럼 코드 주석일 가능성이 높으면 주석색
                    var w = k
                    while w < n, CharClass.isWord(buf[w]) { w += 1 }
                    let word = w > k ? CharClass.string(buf, k, w) : ""
                    var p = w
                    while p < n, CharClass.isSpace(buf[p]) { p += 1 }
                    if Self.codeLikeWords.contains(word) || c(w) == 0x28 /* f( */ || c(p) == 0x3D /* x = */ || c(k) == 0x24 /* $ */ || c(k) == 0x23 { kind = .comment }
                }
                add(i, n, kind)
                return .normal
            }
        }
        // 코드 펜스 ``` / ~~~ → 줄 전체 punctuation. 마크다운이면 펜스 안으로 들어간다 (정보 문자열 = 언어)
        if buf[i] == 0x60 || (isMarkdown && buf[i] == 0x7E) {
            var j = i
            while j < n, buf[j] == buf[i] { j += 1 }
            if j - i >= 3 {
                guard isMarkdown else { add(i, n, .punctuation); return .normal }
                // 백틱 펜스의 정보 문자열에는 백틱이 올 수 없다 (CommonMark) — 그런 줄은 펜스가 아니다
                var k = j
                var backtickInInfo = false
                if buf[i] == 0x60 { while k < n { if buf[k] == 0x60 { backtickInInfo = true; break }; k += 1 } }
                if !backtickInInfo {
                    add(i, n, .punctuation)
                    return .fence(marker: UInt8(buf[i]), length: UInt8(min(j - i, 255)), language: Self.infoLanguage(buf, from: j), inner: .normal)
                }
            }
        }

        var contentStart = i
        // 인용 `> `
        if buf[i] == 0x3E, i + 1 < n, CharClass.isSpace(buf[i + 1]) {
            add(i, i + 1, .punctuation); i += 2
            while i < n, CharClass.isSpace(buf[i]) { i += 1 }
            contentStart = i
        }
        // 목록 기호 `- ` `* ` `+ ` / `1) ` `1. ` / 체크박스
        if i < n, (buf[i] == 0x2D || buf[i] == 0x2A || buf[i] == 0x2B), i + 1 < n, CharClass.isSpace(buf[i + 1]) {
            add(i, i + 1, .punctuation); i += 2
        } else if i < n, CharClass.isDigit(buf[i]) {
            var j = i
            while j < n, CharClass.isDigit(buf[j]), j - i < 3 { j += 1 }
            if j < n, (buf[j] == 0x29 || buf[j] == 0x2E), j + 1 < n, CharClass.isSpace(buf[j + 1]) { add(i, j + 1, .punctuation); i = j + 2 }
        }
        while i < n, CharClass.isSpace(buf[i]) { i += 1 }
        if i > contentStart, i + 2 < n, buf[i] == 0x5B, buf[i + 2] == 0x5D, (buf[i + 1] == 0x20 || buf[i + 1] == 0x78 || buf[i + 1] == 0x58 || buf[i + 1] == 0x2D) {
            add(i, i + 3, .special); i += 3
        } else if i == contentStart, i < n, buf[i] == 0x5B {
            // 줄머리 `[제목]` (체크박스가 아닌 것)
            var j = i + 1
            while j < n, buf[j] != 0x5D, j - i < 42 { j += 1 }
            if j < n, buf[j] == 0x5D, j > i + 1, !(j == i + 2 && (buf[i + 1] == 0x20 || buf[i + 1] == 0x78)) {
                add(i, j + 1, .title); i = j + 1
            }
        }
        while i < n, CharClass.isSpace(buf[i]) { i += 1 }
        // `키: 값` — 줄 첫 단어가 콜론으로 끝나고 뒤에 공백/줄끝
        if i == contentStart, i < n, CharClass.isIdentStart(buf[i]) {
            var j = i
            while j < n, (CharClass.isWord(buf[j]) || buf[j] == 0x2D || buf[j] == 0x2E || buf[j] == 0x2F), j - i < 40 { j += 1 }
            if j < n, buf[j] == 0x3A, (j + 1 == n || CharClass.isSpace(buf[j + 1])), !(j + 2 < n && buf[j + 1] == 0x2F) {
                add(i, j, .property); i = j + 1
            }
        }

        // 본문: URL · 날짜/시각 · #태그 · **굵게** · `코드` · 화살표 · 체크 기호 · (마크다운) HTML 주석
        while i < n {
            let ch = buf[i]
            let prev: unichar = i > 0 ? buf[i - 1] : 0x20
            let atBoundary = !CharClass.isWord(prev)
            if ch == 0x68 /* h */, atBoundary, CharClass.matches(buf, i, Self.https) || CharClass.matches(buf, i, Self.http) {
                var j = i
                while j < n, !CharClass.isSpace(buf[j]), buf[j] != 0x3C, buf[j] != 0x3E, buf[j] != 0x22, buf[j] != 0x60, buf[j] != 0x27 { j += 1 }
                // 꼬리 구두점은 URL 에서 제외
                while j > i {
                    let t = buf[j - 1]
                    if t == 0x2E || t == 0x2C || t == 0x3B || t == 0x3A || t == 0x21 || t == 0x3F || t == 0x5D || t == 0x7D { j -= 1 }
                    else if t == 0x29, !containsOpenParen(buf, i, j) { j -= 1 }
                    else { break }
                }
                if j - i > 8 { add(i, j, .link); i = j; continue }
                i += 1; continue
            }
            if CharClass.isDigit(ch), atBoundary {
                // ISO 날짜 YYYY-MM-DD
                if i + 10 <= n, CharClass.isDigit(c(i + 1)), CharClass.isDigit(c(i + 2)), CharClass.isDigit(c(i + 3)), c(i + 4) == 0x2D,
                   CharClass.isDigit(c(i + 5)), CharClass.isDigit(c(i + 6)), c(i + 7) == 0x2D, CharClass.isDigit(c(i + 8)), CharClass.isDigit(c(i + 9)), !CharClass.isWord(c(i + 10)) {
                    add(i, i + 10, .number); i += 10; continue
                }
                // 시각 H:MM / HH:MM[:SS]
                var j = i
                while j < n, CharClass.isDigit(buf[j]), j - i < 2 { j += 1 }
                if c(j) == 0x3A, CharClass.isDigit(c(j + 1)), CharClass.isDigit(c(j + 2)), !CharClass.isWord(c(j + 3)) || c(j + 3) == 0x3A {
                    var k = j + 3
                    if c(k) == 0x3A, CharClass.isDigit(c(k + 1)), CharClass.isDigit(c(k + 2)), !CharClass.isWord(c(k + 3)) { k += 3 }
                    if !CharClass.isWord(c(k)) { add(i, k, .number); i = k; continue }
                }
                while i < n, CharClass.isWord(buf[i]) { i += 1 }
                continue
            }
            if ch == 0x23 /* # */, atBoundary, (prev == 0x20 || prev == 0x09 || prev == 0x28 || i == contentStart || i == 0), i + 1 < n, CharClass.isWord(buf[i + 1]), !CharClass.isSpace(buf[i + 1]) {
                var j = i + 1
                while j < n, CharClass.isWord(buf[j]) || buf[j] == 0x2D { j += 1 }
                add(i, j, .attribute); i = j; continue
            }
            if ch == 0x2A /* * */, i + 1 < n, buf[i + 1] == 0x2A, i + 2 < n, !CharClass.isSpace(buf[i + 2]) {
                var j = i + 2
                while j + 1 < n, !(buf[j] == 0x2A && buf[j + 1] == 0x2A) { j += 1 }
                if j + 1 < n, j > i + 2 { add(i, j + 2, .constant); i = j + 2; continue }
                i += 2; continue
            }
            if ch == 0x60 /* ` */ {
                var j = i + 1
                while j < n, buf[j] != 0x60 { j += 1 }
                if j < n, j > i + 1 { add(i, j + 1, .string); i = j + 1; continue }
                i += 1; continue
            }
            if isMarkdown, ch == 0x3C, CharClass.matches(buf, i, Self.commentOpen) {
                // HTML 주석 — 줄에서 닫히지 않으면 다음 줄은 `.blockComment`
                guard let e = CharClass.find(Self.commentClose, in: buf, from: i + 4) else { add(i, n, .comment); return .blockComment }
                add(i, e, .comment); i = e; continue
            }
            if ch == 0x21D2 || ch == 0x2192 || ch == 0x2190 || ch == 0x21D0 || ch == 0x2194 || ch == 0x21D4 || ch == 0x21E8 || ch == 0x21E6 {
                add(i, i + 1, .operator); i += 1; continue
            }
            if (ch == 0x3D || ch == 0x2D) && c(i + 1) == 0x3E /* => -> */ && !CharClass.isWord(prev) {
                add(i, i + 2, .operator); i += 2; continue
            }
            if ch == 0x2713 || ch == 0x2714 || ch == 0x2717 || ch == 0x2718 || ch == 0x2610 || ch == 0x2611 || ch == 0x2612 || ch == 0x2605 || ch == 0x2606 {
                add(i, i + 1, .special); i += 1; continue
            }
            if CharClass.isWord(ch) {
                while i < n, CharClass.isWord(buf[i]) { i += 1 }
                continue
            }
            i += 1
        }
        return .normal
    }

    private func containsOpenParen(_ buf: UnsafeBufferPointer<unichar>, _ from: Int, _ to: Int) -> Bool {
        var k = from
        while k < to { if buf[k] == 0x28 { return true }; k += 1 }
        return false
    }
}
