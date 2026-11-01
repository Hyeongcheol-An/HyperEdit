import Foundation

/// 구문 토큰 종류. 테마 `syntax` 사전의 키와 1:1 (`themeKey`). 색이 없는 키는 본문 색으로 떨어진다.
public enum TokenKind: String, CaseIterable, Sendable, Hashable {
    case comment, keyword, string, number, function, type, variable, constant
    case `operator`, punctuation, link, title, special, attribute, property, tag

    /// `Theme.syntax[...]` 키
    public var themeKey: String { rawValue }
}

/// 한 줄 안의 토큰. `range` 는 호출 측이 넘긴 문자열(NSString, UTF-16) 기준 오프셋.
public struct Token: Equatable, Sendable {
    public let range: NSRange
    public let kind: TokenKind
    public init(_ range: NSRange, _ kind: TokenKind) { self.range = range; self.kind = kind }
    public init(location: Int, length: Int, kind: TokenKind) { range = NSRange(location: location, length: length); self.kind = kind }
}

/// 줄 시작(진입) 상태 — 여러 줄에 걸친 구문을 줄 단위 토크나이저가 이어받기 위한 것. 문서의 줄별 진입 상태는 `LineStateIndex` 가 들고 있다.
/// - `.blockComment`: 블록 주석(`/* */`, `<!-- -->`) 안에서 줄이 시작한다
/// - `.string(id)`: 여러 줄 문자열 안. id 는 `CodeLanguage.multilineStrings` 의 1-based 인덱스, Rust raw 문자열은 `0x80 | #개수`
/// - `.fence`: 마크다운 펜스 안. `marker` 는 `` ` `` 또는 `~`, `length` 는 여는 펜스 길이(닫는 펜스는 같은 기호가 그 이상), `language` 는 정보 문자열의 첫 단어(소문자, 없으면 nil),
///   `inner` 는 정보 문자열이 아는 코드 문법일 때 그 문법의 줄 상태(펜스 안의 블록 주석 등)
public enum LineState: Hashable, Sendable {
    case normal
    case blockComment
    case string(UInt8)
    indirect case fence(marker: UInt8, length: UInt8, language: String?, inner: LineState)

    public var isNormal: Bool { if case .normal = self { return true }; return false }
}

/// 줄 단위 토크나이저. 줄 시작 상태(`LineState`)를 받아 토큰과 줄 끝 상태를 돌려준다 — 블록 주석·여러 줄 문자열·마크다운 펜스가 줄을 넘어가도
/// 다음 줄은 그 상태로 이어서 칠해진다. 상태가 없는 문법(메모)은 항상 `.normal` 을 돌려주면 된다. 34k 줄 문서에서 한 줄의 비용은 수 µs.
public protocol LanguageGrammar: Sendable {
    /// 상태바에 보이는 언어 이름 ("Notes", "Markdown", "Python" …) — 고유명사라 번역하지 않는다
    var name: String { get }
    /// 이 문법이 여러 줄 상태를 만들 수 있는가. false 면 `LineStateIndex` 가 스캔 없이 모든 줄을 `.normal` 로 둔다 (메모 파일은 키 입력마다 비용 0)
    var tracksLineState: Bool { get }
    /// 한 줄(개행 제외)의 UTF-16 버퍼를 `entering` 상태로 시작해 토큰화한다. 반환 범위는 `base`(버퍼 첫 글자의 문서 오프셋)를 더한 절대 오프셋.
    func scanLine(_ line: UnsafeBufferPointer<unichar>, base: Int, entering: LineState) -> (tokens: [Token], exiting: LineState)
    /// 줄 끝 상태만 계산한다 (토큰 배열을 만들지 않아 전체 문서 상태 계산이 빠르다). `scanLine(...).exiting` 과 같은 값을 내야 한다.
    func exitState(line: UnsafeBufferPointer<unichar>, entering: LineState) -> LineState
}

public extension LanguageGrammar {
    var tracksLineState: Bool { false }

    func exitState(line: UnsafeBufferPointer<unichar>, entering: LineState) -> LineState {
        scanLine(line, base: 0, entering: entering).exiting
    }

    /// 상태 없이(`.normal` 로 시작) 한 줄을 토큰화 — 테스트·도구용 호환 경로
    func tokens(line: UnsafeBufferPointer<unichar>, base: Int) -> [Token] {
        scanLine(line, base: base, entering: .normal).tokens
    }

    /// TextKit 2 레이아웃 프래그먼트(= 한 문단) 토큰화. `range` 끝의 개행(`\n` `\r\n` `\r`)은 뺀다. 범위는 `ns` 기준 절대 오프셋.
    func scanLine(in ns: NSString, range: NSRange, entering: LineState) -> [Token] {
        var safe = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        while safe.length > 0 {
            let c = ns.character(at: NSMaxRange(safe) - 1)
            if c == 0x0A || c == 0x0D { safe.length -= 1 } else { break }
        }
        guard safe.length > 0 else { return [] }
        // 레이아웃 프래그먼트마다 불리므로 힙 배열 대신 임시 버퍼(짧은 줄은 스택)로 복사 — 보이는 줄마다 생기던 할당/해제를 없앤다
        return withUnsafeTemporaryAllocation(of: unichar.self, capacity: safe.length) { buf in
            ns.getCharacters(buf.baseAddress!, range: safe)
            return scanLine(UnsafeBufferPointer(buf), base: safe.location, entering: entering).tokens
        }
    }

    /// `ns` 의 `range` 를 줄로 나눠 토큰화한다 (`.normal` 로 시작해 줄 사이 상태를 이어 간다). 범위는 `ns` 기준 절대 오프셋.
    func tokens(in ns: NSString, range: NSRange) -> [Token] {
        let safe = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        guard safe.length > 0 else { return [] }
        return withUnsafeTemporaryAllocation(of: unichar.self, capacity: safe.length) { buf in
            ns.getCharacters(buf.baseAddress!, range: safe)
            return tokens(buffer: UnsafeBufferPointer(buf), base: safe.location)
        }
    }

    /// 테스트·도구용: 문자열(여러 줄 가능)을 토큰화. 범위는 문자열의 UTF-16 오프셋. 줄 사이 상태는 이어진다.
    func tokens(in text: String) -> [Token] {
        let units = Array(text.utf16)
        return units.withUnsafeBufferPointer { tokens(buffer: $0, base: 0) }
    }

    /// 테스트용: 줄마다 (토큰, 줄 끝 상태). 첫 줄은 `entering` 으로 시작한다.
    func scanLines(in text: String, entering: LineState = .normal) -> [(tokens: [Token], exiting: LineState)] {
        var state = entering
        var result: [(tokens: [Token], exiting: LineState)] = []
        let ns = text as NSString
        var start = 0
        while start <= ns.length {
            var end = start
            while end < ns.length, ns.character(at: end) != 0x0A { end += 1 }
            let r = scanLine(in: ns, range: NSRange(location: start, length: end - start), entering: state)
            let exit = exitState(in: ns, range: NSRange(location: start, length: end - start), entering: state)
            result.append((r, exit))
            state = exit
            start = end + 1
        }
        return result
    }

    /// 한 줄 범위의 끝 상태 (끝의 개행은 뺀다)
    func exitState(in ns: NSString, range: NSRange, entering: LineState) -> LineState {
        var safe = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        while safe.length > 0 {
            let c = ns.character(at: NSMaxRange(safe) - 1)
            if c == 0x0A || c == 0x0D { safe.length -= 1 } else { break }
        }
        guard safe.length > 0 else { return exitState(line: UnsafeBufferPointer(start: nil, count: 0), entering: entering) }
        return withUnsafeTemporaryAllocation(of: unichar.self, capacity: safe.length) { buf in
            ns.getCharacters(buf.baseAddress!, range: safe)
            return exitState(line: UnsafeBufferPointer(buf), entering: entering)
        }
    }

    /// 버퍼를 `\n` / `\r` / `\r\n` 으로 나눠 줄마다 `scanLine` 호출 — 줄 사이 상태를 이어 간다
    func tokens(buffer: UnsafeBufferPointer<unichar>, base: Int) -> [Token] {
        var out: [Token] = []
        var state = LineState.normal
        let n = buffer.count
        var lineStart = 0
        var i = 0
        while i <= n {
            if i == n || buffer[i] == 0x0A || buffer[i] == 0x0D {
                if i > lineStart {
                    let line = UnsafeBufferPointer(rebasing: buffer[lineStart..<i])
                    let r = scanLine(line, base: base + lineStart, entering: state)
                    out.append(contentsOf: r.tokens)
                    state = r.exiting
                }
                if i < n, buffer[i] == 0x0D, i + 1 < n, buffer[i + 1] == 0x0A { i += 1 }
                lineStart = i + 1
            }
            i += 1
        }
        return out
    }
}

// MARK: - 문자 분류 (UTF-16 단위, 정규식 없이)

@usableFromInline
enum CharClass {
    @inline(__always) static func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }
    @inline(__always) static func isDigit(_ c: unichar) -> Bool { c >= 0x30 && c <= 0x39 }
    @inline(__always) static func isHex(_ c: unichar) -> Bool { isDigit(c) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66) }
    @inline(__always) static func isUpper(_ c: unichar) -> Bool { c >= 0x41 && c <= 0x5A }
    @inline(__always) static func isLower(_ c: unichar) -> Bool { c >= 0x61 && c <= 0x7A }
    @inline(__always) static func isAlpha(_ c: unichar) -> Bool { isUpper(c) || isLower(c) }
    /// 식별자 시작: 영문·`_`·비ASCII 문자(한글 등). 화살표·기호 블록은 제외.
    @inline(__always) static func isIdentStart(_ c: unichar) -> Bool { isAlpha(c) || c == 0x5F || isNonASCIIWord(c) }
    @inline(__always) static func isWord(_ c: unichar) -> Bool { isAlpha(c) || isDigit(c) || c == 0x5F || isNonASCIIWord(c) }
    /// 비ASCII 중 "글자"로 볼 것 — 일반 구두점(U+2000–U+2BFF: 대시·화살표·수학 기호·박스), CJK 구두점(U+3000–U+303F), ·×÷ 는 기호
    @inline(__always) static func isNonASCIIWord(_ c: unichar) -> Bool {
        guard c >= 0x80 else { return false }
        if c >= 0x2000 && c <= 0x2BFF { return false }
        if c >= 0x3000 && c <= 0x303F { return false }
        if c == 0xB7 || c == 0xD7 || c == 0xF7 || c == 0xA0 { return false }
        return true
    }
    @inline(__always) static func isHangul(_ c: unichar) -> Bool {
        (c >= 0xAC00 && c <= 0xD7A3) || (c >= 0x1100 && c <= 0x11FF) || (c >= 0x3130 && c <= 0x318F)
    }
    /// 문자열 비교 (버퍼 `i` 에서 ASCII 리터럴과 일치하는가)
    @inline(__always) static func matches(_ buf: UnsafeBufferPointer<unichar>, _ i: Int, _ lit: [unichar]) -> Bool {
        guard i + lit.count <= buf.count else { return false }
        for k in 0..<lit.count where buf[i + k] != lit[k] { return false }
        return true
    }
    /// `lit` 가 `from` 이후 처음 나타나는 자리의 끝(배타) 오프셋. 없으면 nil
    @inline(__always) static func find(_ lit: [unichar], in buf: UnsafeBufferPointer<unichar>, from: Int) -> Int? {
        guard !lit.isEmpty else { return nil }
        var j = from
        let first = lit[0]
        while j + lit.count <= buf.count {
            if buf[j] == first, matches(buf, j, lit) { return j + lit.count }
            j += 1
        }
        return nil
    }
    static func units(_ s: String) -> [unichar] { Array(s.utf16) }
    /// 버퍼 구간을 String 으로 (키워드 조회용)
    @inline(__always) static func string(_ buf: UnsafeBufferPointer<unichar>, _ from: Int, _ to: Int) -> String {
        String(utf16CodeUnits: buf.baseAddress! + from, count: to - from)
    }
}
