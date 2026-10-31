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

/// 줄 단위 토크나이저. 줄마다 독립적으로 계산한다 — 여러 줄에 걸친 블록 주석·문자열은 같은 줄에서 닫히는 것만 본다.
/// (뷰포트 레이아웃이 임의의 줄에서 시작하므로 줄 시작 상태가 필요 없는 규칙만 둔다. 34k 줄 문서에서 한 줄의 비용은 수 µs.)
public protocol LanguageGrammar: Sendable {
    /// 상태바에 보이는 언어 이름 ("Notes", "Markdown", "Python" …) — 고유명사라 번역하지 않는다
    var name: String { get }
    /// 한 줄(개행 제외)의 UTF-16 버퍼를 받아 토큰을 돌려준다. 반환 범위는 `base`(버퍼 첫 글자의 문서 오프셋)를 더한 절대 오프셋.
    func tokens(line: UnsafeBufferPointer<unichar>, base: Int) -> [Token]
}

public extension LanguageGrammar {
    /// `ns` 의 `range` 를 줄로 나눠 토큰화한다. 범위는 `ns` 기준 절대 오프셋 (TextKit 2 요소 범위를 그대로 넘기면 된다).
    func tokens(in ns: NSString, range: NSRange) -> [Token] {
        let safe = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        guard safe.length > 0 else { return [] }
        var buf = [unichar](repeating: 0, count: safe.length)
        buf.withUnsafeMutableBufferPointer { ns.getCharacters($0.baseAddress!, range: safe) }
        return buf.withUnsafeBufferPointer { tokens(buffer: $0, base: safe.location) }
    }

    /// 테스트·도구용: 문자열(여러 줄 가능)을 토큰화. 범위는 문자열의 UTF-16 오프셋.
    func tokens(in text: String) -> [Token] {
        let units = Array(text.utf16)
        return units.withUnsafeBufferPointer { tokens(buffer: $0, base: 0) }
    }

    /// 버퍼를 `\n` / `\r` / `\r\n` 으로 나눠 줄마다 `tokens(line:base:)` 호출
    func tokens(buffer: UnsafeBufferPointer<unichar>, base: Int) -> [Token] {
        var out: [Token] = []
        let n = buffer.count
        var lineStart = 0
        var i = 0
        while i <= n {
            if i == n || buffer[i] == 0x0A || buffer[i] == 0x0D {
                if i > lineStart {
                    let line = UnsafeBufferPointer(rebasing: buffer[lineStart..<i])
                    out.append(contentsOf: tokens(line: line, base: base + lineStart))
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
    static func units(_ s: String) -> [unichar] { Array(s.utf16) }
    /// 버퍼 구간을 String 으로 (키워드 조회용)
    @inline(__always) static func string(_ buf: UnsafeBufferPointer<unichar>, _ from: Int, _ to: Int) -> String {
        String(utf16CodeUnits: buf.baseAddress! + from, count: to - from)
    }
}
