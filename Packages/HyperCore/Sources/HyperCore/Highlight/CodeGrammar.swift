import Foundation

/// 코드 언어 정의 — 주석 기호·따옴표·키워드 집합과 몇 가지 스캐너 플래그. 언어마다 전용 파서를 두지 않고 하나의 줄 스캐너가 플래그로 분기한다.
public struct CodeLanguage: Sendable {
    public enum Mode: Sendable { case code, markup, css, data, shell }
    public enum AtRole: Sendable { case none, attribute, keyword, variable }

    public var id: String
    public var name: String
    public var mode: Mode = .code
    public var lineComments: [[unichar]] = []
    public var blockComment: (start: [unichar], end: [unichar])? = nil
    public var quotes: Set<unichar> = [0x22, 0x27]
    /// 여는/닫는 구분자가 같은 여러 줄 문자열 (`"""` `'''` `` ` ``). 줄에서 닫히지 않으면 다음 줄이 `.string(1-based 인덱스)` 로 시작한다.
    public var multilineStrings: [[unichar]] = []
    public var rawHashStrings = false          // Rust `r"…"` `r#"…"#` (여러 줄, 이스케이프 없음) → `.string(0x80 | #개수)`
    public var stringPrefixes: Set<unichar> = []
    public var keywords: Set<String> = []
    public var constants: Set<String> = []
    public var types: Set<String> = []
    public var builtins: Set<String> = []      // 내장 함수·명령 → function (사용자 문법의 `builtins`)
    public var caseInsensitive = false
    public var hashDirective = false           // `#if` `#include` → keyword
    public var angleInclude = false            // `#include <stdio.h>` 의 `<stdio.h>` → string
    public var atRole: AtRole = .none
    public var dollarVariable = false          // `$VAR` `${VAR}` → variable
    public var dollarIdent = false             // `$` 를 식별자 글자로 (JS)
    public var colonSymbol = false             // `:sym` → constant (Ruby)
    public var rustLifetimes = false           // `'a` → attribute, `'a'` → string
    public var macroBang = false               // `name!(` → function (Rust)
    public var keyBeforeColon = false          // `key:` → property (YAML/JSON)
    public var keyBeforeEquals = false         // `key =` → property (TOML/INI)
    public var sectionHeaders = false          // `[section]` → title (TOML/INI)
    public var commandPosition = false         // 줄·파이프 첫 단어 → function (shell)
    public var dashFlags = false               // `-x` `--flag` → attribute (shell)
    public var doubleQuoteIsIdentifier = false // `"col"` → property (SQL)
    public var identifierDash = false          // 식별자에 `-` 허용 (CSS·YAML 키)
    /// 사용자 정의 문법이 맡는 확장자·파일 이름 (소문자, `UserGrammarStore` 색인용). 내장 정의는 비어 있다 — 확장자 표는 `GrammarRegistry` 에 있다.
    public var userExtensions: [String] = []
    public var userFilenames: [String] = []

    public init(id: String, name: String) { self.id = id; self.name = name }

    /// 여러 줄 상태를 만들 수 있는 정의인가 (블록 주석·여러 줄 문자열·마크업 주석). 아니면 `LineStateIndex` 가 스캔을 건너뛴다.
    public var tracksLineState: Bool { blockComment != nil || !multilineStrings.isEmpty || rawHashStrings || mode == .markup }

    static func words(_ s: String) -> Set<String> { Set(s.split(separator: " ").map(String.init)) }
    static func u(_ s: String) -> [unichar] { Array(s.utf16) }
}

/// 코드 파일용 범용 줄 스캐너. 블록 주석·여러 줄 문자열이 줄에서 닫히지 않으면 줄 끝까지 칠하고 그 상태(`.blockComment` / `.string`)로 나간다 —
/// 다음 줄은 그 상태로 들어와 닫힘까지 이어서 칠한다.
public struct CodeGrammar: LanguageGrammar {
    public let language: CodeLanguage
    public var name: String { language.name }
    public var tracksLineState: Bool { language.tracksLineState }
    public init(language: CodeLanguage) { self.language = language }

    public func scanLine(_ buf: UnsafeBufferPointer<unichar>, base: Int, entering: LineState) -> (tokens: [Token], exiting: LineState) {
        var out: [Token] = []
        let exit = scan(buf, base, entering, emit: true, into: &out)
        return (out, exit)
    }

    public func exitState(line buf: UnsafeBufferPointer<unichar>, entering: LineState) -> LineState {
        var out: [Token] = []
        return scan(buf, 0, entering, emit: false, into: &out)
    }

    /// 진입 상태의 꼬리(열린 블록 주석·문자열의 닫힘까지)를 먼저 처리하고 나머지를 보통 줄로 스캔한다. `emit == false` 면 토큰을 만들지 않는다 (상태 계산 전용).
    private func scan(_ buf: UnsafeBufferPointer<unichar>, _ base: Int, _ entering: LineState, emit: Bool, into out: inout [Token]) -> LineState {
        let n = buf.count
        var start = 0
        switch entering {
        case .blockComment:
            let end: [unichar] = language.mode == .markup ? Self.commentClose : (language.blockComment?.end ?? [])
            if end.isEmpty { break }   // 이 문법에는 블록 주석이 없다 (문법 교체 직후의 낡은 상태) → 보통 줄로
            guard let e = CharClass.find(end, in: buf, from: 0) else {
                if emit, n > 0 { out.append(Token(location: base, length: n, kind: .comment)) }
                return .blockComment
            }
            if emit { out.append(Token(location: base, length: e, kind: .comment)) }
            start = e
        case .string(let id):
            guard let e = multilineClose(id, buf, from: 0) else {
                if emit, n > 0 { out.append(Token(location: base, length: n, kind: .string)) }
                return .string(id)
            }
            if emit, e > 0 { out.append(Token(location: base, length: e, kind: .string)) }
            start = e
        default: break
        }
        guard start < n else { return .normal }
        let rest = start == 0 ? buf : UnsafeBufferPointer(rebasing: buf[start...])
        return language.mode == .markup ? scanMarkup(rest, base + start, emit: emit, into: &out) : scanCode(rest, base + start, emit: emit, into: &out)
    }

    /// 여러 줄 문자열 id 의 닫는 구분자를 `from` 부터 찾아 그 끝(배타)을 돌려준다. id 가 이 문법에 없으면(낡은 상태) 0 — 보통 줄로 스캔한다.
    private func multilineClose(_ id: UInt8, _ buf: UnsafeBufferPointer<unichar>, from: Int) -> Int? {
        if id & 0x80 != 0 { return Self.rawClose(buf, from: from, hashes: Int(id & 0x7F)) }
        let k = Int(id) - 1
        guard k >= 0, k < language.multilineStrings.count else { return 0 }
        return Self.close(of: language.multilineStrings[k], buf, from: from, escapes: true)
    }

    /// 닫는 구분자 `d` 를 찾는다 (백슬래시 이스케이프는 건너뜀). 반환: 닫힘 뒤 오프셋, 없으면 nil
    private static func close(of d: [unichar], _ buf: UnsafeBufferPointer<unichar>, from: Int, escapes: Bool) -> Int? {
        let n = buf.count
        var j = from
        while j + d.count <= n {
            if escapes, buf[j] == 0x5C { j += 2; continue }
            if buf[j] == d[0], CharClass.matches(buf, j, d) { return j + d.count }
            j += 1
        }
        return nil
    }

    /// Rust raw 문자열의 닫힘: `"` 뒤에 `#` 이 hashes 개
    private static func rawClose(_ buf: UnsafeBufferPointer<unichar>, from: Int, hashes h: Int) -> Int? {
        let n = buf.count
        var j = from
        while j < n {
            if buf[j] == 0x22 {
                var k = j + 1, m = 0
                while m < h, k < n, buf[k] == 0x23 { m += 1; k += 1 }
                if m == h { return k }
            }
            j += 1
        }
        return nil
    }

    // MARK: - 코드 / 데이터 / 셸 / CSS

    private func scanCode(_ buf: UnsafeBufferPointer<unichar>, _ base: Int, emit: Bool, into out: inout [Token]) -> LineState {
        let L = language
        let n = buf.count
        @inline(__always) func c(_ i: Int) -> unichar { i < n ? buf[i] : 0 }
        @inline(__always) func add(_ from: Int, _ to: Int, _ k: TokenKind) { if emit, to > from { out.append(Token(location: base + from, length: to - from, kind: k)) } }
        @inline(__always) func nextNonSpace(_ from: Int) -> Int { var k = from; while k < n, CharClass.isSpace(buf[k]) { k += 1 }; return k }
        @inline(__always) func isIdent(_ ch: unichar) -> Bool { CharClass.isWord(ch) || (L.dollarIdent && ch == 0x24) || (L.identifierDash && ch == 0x2D) }

        var i = nextNonSpace(0)
        let firstNonSpace = i
        var expectCommand = L.commandPosition
        var valueMode = false          // 데이터 모드: 키 뒤의 값 — 식별자·연산자는 칠하지 않는다
        var afterKey = false           // 직전 토큰이 키였는가 (바로 뒤의 : / = 만 연산자로 칠한다)
        var cssSelectorLine = false
        if L.mode == .css { var k = 0; while k < n { if buf[k] == 0x7B { cssSelectorLine = true; break }; k += 1 } }

        /// 따옴표 문자열 끝(배타) — 이스케이프 처리, 닫히지 않으면 줄 끝
        func stringEnd(from s: Int, quote q: unichar) -> Int {
            var j = s + 1
            while j < n {
                if buf[j] == 0x5C { j += 2; continue }
                if buf[j] == q { return j + 1 }
                j += 1
            }
            return n
        }
        /// `s` 에서 여러 줄 문자열 구분자가 시작하면 그 id (1-based)
        @inline(__always) func multilineDelimiter(at s: Int) -> Int? {
            guard !L.multilineStrings.isEmpty, s < n else { return nil }
            for (k, d) in L.multilineStrings.enumerated() where buf[s] == d[0] && CharClass.matches(buf, s, d) { return k + 1 }
            return nil
        }
        /// `s` 에서 시작하는 문자열의 끝(배타). 여러 줄 구분자가 줄에서 닫히지 않으면 (n, 나갈 상태)
        func stringFrom(_ s: Int) -> (end: Int, exit: LineState?) {
            if let id = multilineDelimiter(at: s) {
                let d = L.multilineStrings[id - 1]
                if let e = Self.close(of: d, buf, from: s + d.count, escapes: true) { return (e, nil) }
                return (n, .string(UInt8(id)))
            }
            return (stringEnd(from: s, quote: buf[s]), nil)
        }
        func numberEnd(from s: Int) -> Int {
            var j = s
            if buf[s] == 0x30, (c(s + 1) | 0x20) == 0x78 || (c(s + 1) | 0x20) == 0x62 || (c(s + 1) | 0x20) == 0x6F {
                j = s + 2
                while j < n, CharClass.isHex(buf[j]) || buf[j] == 0x5F { j += 1 }
                return j
            }
            while j < n, CharClass.isDigit(buf[j]) || buf[j] == 0x5F { j += 1 }
            if c(j) == 0x2E, CharClass.isDigit(c(j + 1)) { j += 1; while j < n, CharClass.isDigit(buf[j]) { j += 1 } }
            if (c(j) | 0x20) == 0x65, CharClass.isDigit(c(j + 1)) || ((c(j + 1) == 0x2B || c(j + 1) == 0x2D) && CharClass.isDigit(c(j + 2))) {
                j += 2; while j < n, CharClass.isDigit(buf[j]) { j += 1 }
            }
            if L.mode == .data {
                // 2026-10-30 / 14:05:00 같은 날짜·시각도 하나의 숫자 토큰으로
                while (c(j) == 0x2D || c(j) == 0x3A || c(j) == 0x2E || c(j) == 0x54) && CharClass.isDigit(c(j + 1)) { j += 1; while j < n, CharClass.isDigit(buf[j]) { j += 1 } }
            }
            while j < n, CharClass.isWord(buf[j]) || buf[j] == 0x25 { j += 1 }   // 단위·접미사 (px, f, u32, %)
            return j
        }

        while i < n {
            let ch = buf[i]
            if CharClass.isSpace(ch) { i += 1; continue }
            let prev: unichar = i > 0 ? buf[i - 1] : 0x20
            let wasAfterKey = afterKey
            afterKey = false

            // 줄 주석
            var isLineComment = false
            for lc in L.lineComments where CharClass.matches(buf, i, lc) {
                // `#` 한 글자 주석은 단어 안(`a#b`)·`$#` 에서는 제외
                if lc.count == 1, lc[0] == 0x23, CharClass.isWord(prev) || prev == 0x24 { continue }
                isLineComment = true; break
            }
            if isLineComment { add(i, n, .comment); return .normal }
            if let bc = L.blockComment, CharClass.matches(buf, i, bc.start) {
                // 줄에서 닫히지 않으면 줄 끝까지 주석이고 다음 줄은 `.blockComment` 로 시작한다
                guard let e = CharClass.find(bc.end, in: buf, from: i + bc.start.count) else { add(i, n, .comment); return .blockComment }
                add(i, e, .comment); i = e; continue
            }

            // Rust: 'a' 문자 vs 'a 수명
            if L.rustLifetimes, ch == 0x27 {
                if c(i + 2) == 0x27 { add(i, i + 3, .string); i += 3; continue }
                if c(i + 1) == 0x5C { let e = stringEnd(from: i, quote: 0x27); add(i, e, .string); i = e; continue }
                if CharClass.isIdentStart(c(i + 1)) { var j = i + 1; while j < n, CharClass.isWord(buf[j]) { j += 1 }; add(i, j, .attribute); i = j; continue }
            }
            // 문자열 (여러 줄 구분자 `"""` `` ` `` 는 따옴표 집합과 무관하게 본다)
            if L.quotes.contains(ch) || multilineDelimiter(at: i) != nil {
                let (e, exit) = stringFrom(i)
                if let exit { add(i, n, .string); return exit }
                var kind = TokenKind.string
                if L.doubleQuoteIsIdentifier, ch == 0x22 || ch == 0x60 { kind = .property }
                if L.keyBeforeColon, c(nextNonSpace(e)) == 0x3A { kind = .property; valueMode = true; afterKey = true }
                if L.keyBeforeEquals, c(nextNonSpace(e)) == 0x3D { kind = .property; valueMode = true; afterKey = true }
                add(i, e, kind); i = e; expectCommand = false; continue
            }
            // 숫자
            if CharClass.isDigit(ch) || (ch == 0x2E && CharClass.isDigit(c(i + 1)) && !CharClass.isWord(prev)) {
                if CharClass.isWord(prev) { while i < n, CharClass.isWord(buf[i]) { i += 1 }; continue }   // abc123 의 일부
                let e = numberEnd(from: i); add(i, e, .number); i = e; expectCommand = false; continue
            }
            // `#if` `#include` 지시문 (주석이 아닌 언어)
            if ch == 0x23, L.hashDirective, CharClass.isIdentStart(c(i + 1)) {
                var j = i + 1
                while j < n, CharClass.isWord(buf[j]) { j += 1 }
                add(i, j, .keyword)
                if L.angleInclude, c(nextNonSpace(j)) == 0x3C {
                    let s = nextNonSpace(j); var k = s + 1
                    while k < n, buf[k] != 0x3E { k += 1 }
                    if k < n { add(s, k + 1, .string); j = k + 1 }
                }
                i = j; continue
            }
            // Rust `#[derive(...)]` / `#![...]`
            if ch == 0x23, L.macroBang, c(i + 1) == 0x5B || (c(i + 1) == 0x21 && c(i + 2) == 0x5B) {
                var j = i; var depth = 0
                while j < n { if buf[j] == 0x5B { depth += 1 } else if buf[j] == 0x5D { depth -= 1; if depth == 0 { j += 1; break } }; j += 1 }
                add(i, j, .attribute); i = j; continue
            }
            // CSS `#fff` 색 / `#id` 선택자 / `.class`
            if L.mode == .css, ch == 0x23 || ch == 0x2E, CharClass.isWord(c(i + 1)) {
                var j = i + 1
                while j < n, CharClass.isWord(buf[j]) || buf[j] == 0x2D { j += 1 }
                var isColor = false
                if ch == 0x23, !cssSelectorLine {
                    let len = j - i - 1
                    isColor = (len == 3 || len == 4 || len == 6 || len == 8)
                    var k = i + 1; while isColor, k < j { if !CharClass.isHex(buf[k]) { isColor = false }; k += 1 }
                }
                add(i, j, isColor ? .number : .type); i = j; continue
            }
            if L.mode == .css, ch == 0x21, CharClass.matches(buf, i, Self.important) { add(i, i + 10, .keyword); i += 10; continue }
            // `@` 접두: 속성(Swift/Python/Java/TS 데코레이터) · ObjC 키워드 · Ruby 인스턴스 변수 · CSS at-rule
            if ch == 0x40 {
                if L.atRole == .keyword, c(i + 1) == 0x22 { let e = stringEnd(from: i + 1, quote: 0x22); add(i, e, .string); i = e; continue }
                var j = i + 1
                if L.atRole == .variable, c(j) == 0x40 { j += 1 }
                if CharClass.isIdentStart(c(j)) {
                    while j < n, CharClass.isWord(buf[j]) || buf[j] == 0x2D { j += 1 }
                    let kind: TokenKind
                    switch L.atRole {
                    case .attribute: kind = .attribute
                    case .keyword: kind = .keyword
                    case .variable: kind = .variable
                    case .none: kind = L.mode == .css ? .keyword : .attribute
                    }
                    add(i, j, kind); i = j; continue
                }
                i += 1; continue
            }
            // 셸 변수
            if ch == 0x24, L.dollarVariable {
                if c(i + 1) == 0x7B {
                    var j = i + 2; while j < n, buf[j] != 0x7D { j += 1 }
                    add(i, min(j + 1, n), .variable); i = min(j + 1, n); continue
                }
                if c(i + 1) == 0x28 { add(i, i + 2, .punctuation); i += 2; expectCommand = true; continue }
                if CharClass.isWord(c(i + 1)) {
                    var j = i + 1; while j < n, CharClass.isWord(buf[j]) { j += 1 }
                    add(i, j, .variable); i = j; continue
                }
                if i + 1 < n, !CharClass.isSpace(c(i + 1)) { add(i, i + 2, .variable); i += 2; continue }
                i += 1; continue
            }
            // Ruby 심벌
            if ch == 0x3A, L.colonSymbol, CharClass.isIdentStart(c(i + 1)), !CharClass.isWord(prev), c(i + 1) != 0x3A {
                var j = i + 1; while j < n, CharClass.isWord(buf[j]) || buf[j] == 0x3F || buf[j] == 0x21 { j += 1 }
                add(i, j, .constant); i = j; continue
            }
            // 셸 플래그 `-v` `--all`
            if ch == 0x2D, L.dashFlags, CharClass.isSpace(prev) || i == 0, CharClass.isAlpha(c(i + 1)) || (c(i + 1) == 0x2D && CharClass.isAlpha(c(i + 2))) {
                var j = i + 1; while j < n, CharClass.isWord(buf[j]) || buf[j] == 0x2D { j += 1 }
                add(i, j, .attribute); i = j; continue
            }
            // TOML/INI `[section]` / `[[array]]`
            if ch == 0x5B, L.sectionHeaders, i == firstNonSpace {
                var j = i; while j < n, buf[j] != 0x5D { j += 1 }
                while j < n, buf[j] == 0x5D { j += 1 }
                add(i, j, .title); i = j; continue
            }
            // YAML 앵커·별칭·태그
            if L.mode == .data, (ch == 0x26 || ch == 0x2A) && CharClass.isIdentStart(c(i + 1)) && !CharClass.isWord(prev) {
                var j = i + 1; while j < n, CharClass.isWord(buf[j]) || buf[j] == 0x2D { j += 1 }
                add(i, j, .attribute); i = j; continue
            }
            if L.mode == .data, ch == 0x21, c(i + 1) == 0x21 {
                var j = i + 2; while j < n, CharClass.isWord(buf[j]) { j += 1 }
                add(i, j, .type); i = j; continue
            }

            // 식별자
            if CharClass.isIdentStart(ch) || (L.dollarIdent && ch == 0x24) {
                var j = i + 1
                while j < n, isIdent(buf[j]) { j += 1 }
                // Rust raw 문자열 r"…" r#"…"# br"…" — 이스케이프 없음, 여러 줄
                if L.rawHashStrings, (j - i == 1 && buf[i] == 0x72) || (j - i == 2 && buf[i] == 0x62 && buf[i + 1] == 0x72), c(j) == 0x23 || c(j) == 0x22 {
                    var h = 0, k = j
                    while k < n, buf[k] == 0x23, h < 127 { h += 1; k += 1 }
                    if c(k) == 0x22 {
                        guard let e = Self.rawClose(buf, from: k + 1, hashes: h) else { add(i, n, .string); return .string(0x80 | UInt8(h)) }
                        add(i, e, .string); i = e; continue
                    }
                }
                // 접두 문자열 f"…" r'…' b"…" (f"""…""" 처럼 여러 줄 구분자가 따라와도 된다)
                if !L.stringPrefixes.isEmpty, j - i <= 2, L.quotes.contains(c(j)) || multilineDelimiter(at: j) != nil {
                    var ok = true; var k = i; while k < j { if !L.stringPrefixes.contains(buf[k]) { ok = false }; k += 1 }
                    if ok {
                        let (e, exit) = stringFrom(j)
                        if let exit { add(i, n, .string); return exit }
                        add(i, e, .string); i = e; continue
                    }
                }
                // Rust 매크로 name!(
                if L.macroBang, c(j) == 0x21, c(j + 1) == 0x28 || c(j + 1) == 0x5B || c(j + 1) == 0x7B { add(i, j + 1, .function); i = j + 1; continue }
                if !emit { i = j; expectCommand = false; continue }   // 상태 계산 전용: 종류 분류(문자열 생성·집합 조회)는 건너뛴다
                let word = CharClass.string(buf, i, j)
                let key = L.caseInsensitive ? word.lowercased() : word
                let k = nextNonSpace(j)
                let nc = c(k)
                var kind: TokenKind?
                if L.keyBeforeColon, nc == 0x3A, !valueMode, k + 1 == n || CharClass.isSpace(c(k + 1)) || L.mode == .data && c(k + 1) != 0x2F {
                    kind = .property; valueMode = true; afterKey = true
                } else if L.keyBeforeEquals, nc == 0x3D, !valueMode {
                    kind = .property; valueMode = true; afterKey = true
                } else if L.mode == .css {
                    if cssSelectorLine { kind = L.keywords.contains(key) ? .keyword : .tag }
                    else if nc == 0x3A { kind = .property }
                    else if nc == 0x28 { kind = .function }
                    else if L.constants.contains(key) { kind = .constant }
                    else if L.keywords.contains(key) { kind = .keyword }
                } else if L.constants.contains(key) {
                    kind = .constant
                } else if L.mode == .shell, prev == 0x2F || prev == 0x2E || prev == 0x7E || prev == 0x2D || prev == 0x3D {
                    kind = nil                                   // 경로·파일명의 일부 (/usr/local, ./run.sh, FOO=bar)
                } else if L.keywords.contains(key) {
                    kind = .keyword
                    if L.commandPosition, Self.shellCommandLeaders.contains(key) { add(i, j, .keyword); expectCommand = true; i = j; continue }
                } else if L.types.contains(key) {
                    kind = .type
                } else if L.builtins.contains(key) {
                    kind = .function
                } else if valueMode {
                    kind = nil
                } else if expectCommand {
                    kind = nc == 0x3D ? .variable : .function
                } else if nc == 0x28 {
                    kind = .function
                } else if CharClass.isUpper(ch) {
                    var hasLower = false; var m = i; while m < j { if CharClass.isLower(buf[m]) { hasLower = true; break }; m += 1 }
                    kind = hasLower ? .type : (nc == 0x2E || j - i == 1 ? .type : .constant)
                }
                if let kind { add(i, j, kind) }
                expectCommand = false
                i = j; continue
            }

            // 구두점 / 연산자
            if L.mode == .data, ch == 0x2D, i + 1 == n || CharClass.isSpace(c(i + 1)) {   // YAML 목록 `- `
                add(i, i + 1, .punctuation); i += 1; continue
            }
            if ch == 0x28 || ch == 0x29 || ch == 0x7B || ch == 0x7D || ch == 0x5B || ch == 0x5D || ch == 0x2C || ch == 0x3B {
                add(i, i + 1, .punctuation); i += 1
                if L.commandPosition, ch == 0x3B || ch == 0x28 || ch == 0x7B { expectCommand = true }
                if L.mode == .data, ch == 0x2C || ch == 0x7B || ch == 0x5B { valueMode = false }
                continue
            }
            if Self.isOperatorChar(ch, L.mode) {
                var j = i + 1
                while j < n, Self.isOperatorChar(buf[j], L.mode) { j += 1 }
                if L.mode == .data, valueMode, !wasAfterKey { i = j; continue }   // 값 안의 `//` `.` `-` 는 그냥 글자
                add(i, j, .operator)
                if L.commandPosition, (ch == 0x7C || ch == 0x26) { expectCommand = true }
                if L.mode == .data, (ch == 0x3A || ch == 0x3D) { valueMode = true }
                i = j; continue
            }
            if CharClass.isWord(ch) { while i < n, CharClass.isWord(buf[i]) { i += 1 }; continue }
            i += 1
        }
        return .normal
    }

    private static let important = CodeLanguage.u("!important")
    private static let shellCommandLeaders: Set<String> = ["then", "do", "else", "if", "elif", "while", "until", "exec", "time", "sudo", "nohup", "env"]

    @inline(__always) private static func isOperatorChar(_ c: unichar, _ mode: CodeLanguage.Mode) -> Bool {
        if mode == .shell {   // 경로의 / . ~ - 는 연산자가 아니다
            return c == 0x7C || c == 0x26 || c == 0x3C || c == 0x3E || c == 0x3D || c == 0x21
        }
        switch c {
        case 0x2B, 0x2D, 0x2A, 0x2F, 0x25, 0x3D, 0x3C, 0x3E, 0x21, 0x26, 0x7C, 0x5E, 0x7E, 0x3F, 0x3A, 0x2E: return true
        case 0x21D2, 0x2192: return true
        default: return false
        }
    }

    // MARK: - HTML / XML

    private static let commentOpen = CodeLanguage.u("<!--")
    private static let commentClose = CodeLanguage.u("-->")

    private func scanMarkup(_ buf: UnsafeBufferPointer<unichar>, _ base: Int, emit: Bool, into out: inout [Token]) -> LineState {
        let n = buf.count
        @inline(__always) func c(_ i: Int) -> unichar { i < n ? buf[i] : 0 }
        @inline(__always) func add(_ from: Int, _ to: Int, _ k: TokenKind) { if emit, to > from { out.append(Token(location: base + from, length: to - from, kind: k)) } }
        @inline(__always) func isName(_ ch: unichar) -> Bool { CharClass.isWord(ch) || ch == 0x2D || ch == 0x3A || ch == 0x2E }
        var i = 0
        while i < n {
            let ch = buf[i]
            if ch == 0x3C, CharClass.matches(buf, i, Self.commentOpen) {
                // `<!-- … -->` 가 줄에서 닫히지 않으면 다음 줄은 `.blockComment`
                guard let e = CharClass.find(Self.commentClose, in: buf, from: i + 4) else { add(i, n, .comment); return .blockComment }
                add(i, e, .comment); i = e; continue
            }
            if ch == 0x3C {
                if c(i + 1) == 0x21 || c(i + 1) == 0x3F {       // <!DOCTYPE …> <?xml …?>
                    var j = i; while j < n, buf[j] != 0x3E { j += 1 }
                    add(i, min(j + 1, n), .keyword); i = min(j + 1, n); continue
                }
                var j = i + 1
                if c(j) == 0x2F { j += 1 }
                guard CharClass.isIdentStart(c(j)) else { i += 1; continue }
                var k = j; while k < n, isName(buf[k]) { k += 1 }
                add(i, j, .punctuation); add(j, k, .tag); i = k
                // 속성 영역 (같은 줄에서 `>` 까지)
                while i < n {
                    let a = buf[i]
                    if CharClass.isSpace(a) { i += 1; continue }
                    if a == 0x3E { add(i, i + 1, .punctuation); i += 1; break }
                    if a == 0x2F, c(i + 1) == 0x3E { add(i, i + 2, .punctuation); i += 2; break }
                    if a == 0x3F, c(i + 1) == 0x3E { add(i, i + 2, .punctuation); i += 2; break }
                    if a == 0x22 || a == 0x27 {
                        var e = i + 1; while e < n, buf[e] != a { e += 1 }
                        add(i, min(e + 1, n), .string); i = min(e + 1, n); continue
                    }
                    if CharClass.isIdentStart(a) {
                        var e = i; while e < n, isName(buf[e]) { e += 1 }
                        add(i, e, .attribute); i = e; continue
                    }
                    if a == 0x3D { add(i, i + 1, .operator); i += 1; continue }
                    i += 1
                }
                continue
            }
            if ch == 0x26 {                                     // &amp; &#39;
                var j = i + 1; while j < n, j - i < 10, CharClass.isWord(buf[j]) || buf[j] == 0x23 { j += 1 }
                if c(j) == 0x3B, j > i + 1 { add(i, j + 1, .constant); i = j + 1; continue }
            }
            i += 1
        }
        return .normal
    }
}

// MARK: - 언어 정의

public extension CodeLanguage {
    static let swift: CodeLanguage = {
        var l = CodeLanguage(id: "swift", name: "Swift")
        l.lineComments = [u("//")]; l.blockComment = (u("/*"), u("*/"))
        l.quotes = [0x22]; l.multilineStrings = [u("\"\"\"")]
        l.hashDirective = true; l.atRole = .attribute
        l.keywords = words("import class struct enum protocol extension func var let if else guard for while repeat in return switch case default break continue fallthrough where defer do try catch throw throws rethrows as is init deinit static final override public private fileprivate internal open mutating nonmutating inout associatedtype typealias some any await async actor get set willSet didSet lazy weak unowned subscript operator precedencegroup indirect convenience required optional dynamic isolated nonisolated consuming borrowing macro package")
        l.constants = words("true false nil self Self super")
        return l
    }()

    static let python: CodeLanguage = {
        var l = CodeLanguage(id: "python", name: "Python")
        l.lineComments = [u("#")]
        l.multilineStrings = [u("\"\"\""), u("'''")]; l.stringPrefixes = [0x66, 0x46, 0x72, 0x52, 0x62, 0x42, 0x75, 0x55]
        l.atRole = .attribute
        l.keywords = words("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case print")
        l.constants = words("True False None self cls NotImplemented Ellipsis")
        l.types = words("int str list dict set tuple float bool bytes object type range frozenset complex")
        return l
    }()

    static let javascript: CodeLanguage = {
        var l = CodeLanguage(id: "javascript", name: "JavaScript")
        l.lineComments = [u("//")]; l.blockComment = (u("/*"), u("*/"))
        l.quotes = [0x22, 0x27, 0x60]; l.multilineStrings = [u("`")]   // 템플릿 리터럴은 여러 줄
        l.dollarIdent = true; l.atRole = .attribute
        l.keywords = words("async await break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new of return static super switch throw try typeof var void while with yield interface type enum implements declare namespace public private protected readonly abstract as from get set keyof satisfies override module require")
        l.constants = words("true false null undefined NaN Infinity this")
        l.types = words("string number boolean any void never object unknown symbol bigint")
        return l
    }()

    static let typescript = CodeLanguage(copy: javascript, id: "typescript", name: "TypeScript")

    static let json: CodeLanguage = {
        var l = CodeLanguage(id: "json", name: "JSON")
        l.mode = .data; l.quotes = [0x22]
        l.lineComments = [u("//")]; l.blockComment = (u("/*"), u("*/"))   // JSONC
        l.keyBeforeColon = true
        l.constants = words("true false null")
        return l
    }()

    static let shell: CodeLanguage = {
        var l = CodeLanguage(id: "shell", name: "Shell")
        l.mode = .shell
        l.lineComments = [u("#")]
        l.quotes = [0x22, 0x27, 0x60]
        l.dollarVariable = true; l.commandPosition = true; l.dashFlags = true
        l.keywords = words("if then else elif fi for while until do done case esac in function select time return exit break continue local export readonly declare typeset unset shift source alias eval exec trap set echo cd test printf read")
        return l
    }()

    static let yaml: CodeLanguage = {
        var l = CodeLanguage(id: "yaml", name: "YAML")
        l.mode = .data
        l.lineComments = [u("#")]
        l.keyBeforeColon = true; l.identifierDash = true
        l.constants = words("true false null yes no on off True False Null Yes No TRUE FALSE NULL ~")
        return l
    }()

    static let html: CodeLanguage = { var l = CodeLanguage(id: "html", name: "HTML"); l.mode = .markup; return l }()
    static let xml: CodeLanguage = { var l = CodeLanguage(id: "xml", name: "XML"); l.mode = .markup; return l }()

    static let css: CodeLanguage = {
        var l = CodeLanguage(id: "css", name: "CSS")
        l.mode = .css
        l.lineComments = [u("//")]; l.blockComment = (u("/*"), u("*/"))   // `//` 는 SCSS/Less
        l.identifierDash = true
        l.keywords = words("important media import keyframes font-face supports charset layer container mixin include extend if else each for function return")
        l.constants = words("inherit initial unset none auto transparent currentColor")
        return l
    }()

    static let c: CodeLanguage = {
        var l = CodeLanguage(id: "c", name: "C")
        l.lineComments = [u("//")]; l.blockComment = (u("/*"), u("*/"))
        l.hashDirective = true; l.angleInclude = true
        l.keywords = words("auto break case char const continue default do double else enum extern float for goto if inline int long register restrict return short signed sizeof static struct switch typedef union unsigned void volatile while _Bool bool")
        l.constants = words("true false NULL")
        return l
    }()

    static let cpp: CodeLanguage = {
        var l = CodeLanguage(copy: c, id: "cpp", name: "C++")
        l.keywords.formUnion(words("class namespace template typename using new delete this public private protected virtual override final try catch throw constexpr consteval constinit nullptr operator friend explicit static_cast dynamic_cast reinterpret_cast const_cast noexcept decltype auto mutable thread_local concept requires co_await co_return co_yield export module import"))
        l.constants.formUnion(words("nullptr this"))
        return l
    }()

    static let objc: CodeLanguage = {
        var l = CodeLanguage(copy: c, id: "objc", name: "Objective-C")
        l.atRole = .keyword
        l.keywords.formUnion(words("id instancetype BOOL Class SEL IMP in out inout bycopy byref oneway self super nil Nil YES NO __weak __strong __block __bridge nonatomic atomic strong weak copy assign retain readonly readwrite nullable nonnull"))
        l.constants.formUnion(words("YES NO nil Nil self super"))
        return l
    }()

    static let go: CodeLanguage = {
        var l = CodeLanguage(id: "go", name: "Go")
        l.lineComments = [u("//")]; l.blockComment = (u("/*"), u("*/"))
        l.quotes = [0x22, 0x27, 0x60]; l.multilineStrings = [u("`")]   // raw 문자열은 여러 줄
        l.keywords = words("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var")
        l.constants = words("true false nil iota")
        l.types = words("int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 uintptr float32 float64 complex64 complex128 string bool byte rune error any")
        return l
    }()

    static let rust: CodeLanguage = {
        var l = CodeLanguage(id: "rust", name: "Rust")
        l.lineComments = [u("//")]; l.blockComment = (u("/*"), u("*/"))
        l.quotes = [0x22]
        l.rustLifetimes = true; l.macroBang = true; l.rawHashStrings = true
        l.keywords = words("as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return static struct super trait type unsafe use where while macro_rules union")
        l.constants = words("true false self Self None Some Ok Err")
        l.types = words("i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 str bool char")
        return l
    }()

    static let sql: CodeLanguage = {
        var l = CodeLanguage(id: "sql", name: "SQL")
        l.lineComments = [u("--")]; l.blockComment = (u("/*"), u("*/"))
        l.quotes = [0x27, 0x22, 0x60]
        l.caseInsensitive = true; l.doubleQuoteIsIdentifier = true
        l.keywords = words("select from where insert into values update set delete create table drop alter add column index view as join inner left right outer full cross on and or not null is in exists between like ilike limit offset order by group having distinct union all case when then else end primary key foreign references default unique check constraint begin commit rollback transaction with recursive over partition if function returns return declare asc desc using truncate explain analyze grant revoke")
        l.constants = words("null true false")
        l.types = words("int integer bigint smallint serial text varchar char boolean bool date timestamp timestamptz time numeric decimal real float double json jsonb uuid bytea blob")
        return l
    }()

    static let ruby: CodeLanguage = {
        var l = CodeLanguage(id: "ruby", name: "Ruby")
        l.lineComments = [u("#")]
        l.atRole = .variable; l.colonSymbol = true; l.dollarVariable = true
        l.keywords = words("alias and begin break case class def defined? do else elsif end ensure for if in module next not or redo rescue retry return then undef unless until when while yield require require_relative include extend attr_accessor attr_reader attr_writer private public protected raise lambda proc puts module_function")
        l.constants = words("true false nil self super __FILE__ __LINE__")
        return l
    }()

    static let java: CodeLanguage = {
        var l = CodeLanguage(id: "java", name: "Java")
        l.lineComments = [u("//")]; l.blockComment = (u("/*"), u("*/"))
        l.atRole = .attribute
        l.keywords = words("abstract assert boolean break byte case catch char class const continue default do double else enum extends final finally float for goto if implements import instanceof int interface long native new package private protected public return short static strictfp super switch synchronized this throw throws transient try void volatile while var record sealed permits yield")
        l.constants = words("true false null this super")
        return l
    }()

    static let kotlin: CodeLanguage = {
        var l = CodeLanguage(copy: java, id: "kotlin", name: "Kotlin")
        l.keywords.formUnion(words("fun val when object companion data override open internal lateinit init is in as typealias suspend inline reified sealed out vararg constructor by get set where crossinline noinline tailrec operator infix annotation external actual expect"))
        return l
    }()

    static let toml: CodeLanguage = {
        var l = CodeLanguage(id: "toml", name: "TOML")
        l.mode = .data
        l.lineComments = [u("#")]
        l.keyBeforeEquals = true; l.sectionHeaders = true; l.identifierDash = true
        l.constants = words("true false inf nan")
        return l
    }()

    static let ini: CodeLanguage = {
        var l = CodeLanguage(id: "ini", name: "INI")
        l.mode = .data
        l.lineComments = [u("#"), u(";")]
        l.keyBeforeEquals = true; l.keyBeforeColon = true; l.sectionHeaders = true; l.identifierDash = true
        l.constants = words("true false yes no on off")
        return l
    }()

    /// 다른 정의를 복사해 id·이름만 바꾼다 (TypeScript ← JavaScript, C++ ← C …)
    init(copy other: CodeLanguage, id: String, name: String) {
        self = other
        self.id = id
        self.name = name
    }
}
