import Foundation

/// 즉석 계산 (UltraEdit 의 Evaluate 계승): 안전한 산술식만 직접 파싱한다 — NSExpression·eval 을 쓰지 않는다.
///
/// 문법 (재귀 하강):
/// ```
/// expr    := term (('+' | '-') term)*
/// term    := unary (('*' | '/' | '%') unary)*
/// unary   := ('-' | '+') unary | power
/// power   := primary ('^' unary)?            // 우결합: 2^3^2 = 2^9
/// primary := number | ident '(' expr (',' expr)* ')' | ident | '(' expr ')'
/// number  := 숫자(천 단위 ',' 와 '_' 허용) ['.' 숫자] [('e'|'E') [+-] 숫자]
/// ident   := sqrt abs round floor ceil min max | pi e
/// ```
/// `×` `÷` `−` 는 `*` `/` `-` 로 읽는다. 0 으로 나누기, 문법 오류, 비유한 결과는 nil.
extension TextTools {
    public static func evaluate(_ expression: String) -> Double? {
        var p = ExpressionParser(expression)
        guard let v = p.parseExpression(), p.atEnd, v.isFinite else { return nil }
        return v
    }

    /// 결과 서식: 정수는 소수점 없이, 아니면 소수 6자리까지 끝의 0 을 떼고 (`3.75`, `0.333333`). 천 단위 구분 없음.
    public static func formatNumber(_ v: Double) -> String {
        guard v.isFinite else { return "NaN" }
        if v == 0 { return "0" }
        if v == v.rounded() {
            return abs(v) < 1e15 ? String(format: "%.0f", v) : String(format: "%g", v)
        }
        var s = String(format: "%.6f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        if s == "0" || s == "-0" { return String(format: "%g", v) }   // 1e-7 처럼 아주 작은 수는 지수 표기로
        return s
    }

    /// 한 줄에 즉석 계산을 적용한다.
    /// - `selectedExpression` 이 있으면 그것을 평가하고, 없으면 줄에서 고른다: 마지막 `⇒`/`=>` 뒤의 옛 결과를 떼어낸 뒤
    ///   마지막 `=` 뒤의 텍스트, 없으면 줄 전체(앞의 `- `/`* `/`1. ` 같은 목록 표시는 뺀다).
    /// - `selectionEnd`(줄 안 UTF-16 오프셋) 뒤에 있는 `⇒ 옛 결과` 만 교체 대상으로 본다.
    /// - 반환: 새 줄 텍스트(`<앞부분> ⇒ <결과>`), 평가한 수식, 서식화한 결과. 수식이 아니면 nil.
    public static func calculateLine(_ line: String, selectedExpression: String? = nil, selectionEnd: Int = 0)
        -> (line: String, expression: String, result: String)? {
        let ns = line as NSString
        let from = max(0, min(selectionEnd, ns.length))
        let tail = NSRange(location: from, length: ns.length - from)
        var head = line
        let cuts = ["⇒", "=>"].map { ns.range(of: $0, options: .backwards, range: tail).location }.filter { $0 != NSNotFound }
        if let cut = cuts.max() { head = ns.substring(to: cut) }

        var expr: String
        if let s = selectedExpression {
            expr = s
        } else {
            expr = head
            if let eq = expr.range(of: "=", options: .backwards) {
                expr = String(expr[eq.upperBound...])
            } else if let m = expr.range(of: #"^\s*(?:[-*•]|\d+[.)])\s+"#, options: .regularExpression) {
                expr.removeSubrange(m)                  // 목록 글머리
            }
        }
        expr = expr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expr.isEmpty, let value = evaluate(expr) else { return nil }
        let result = formatNumber(value)
        var prefix = Substring(head)
        while let last = prefix.last, last == " " || last == "\t" { prefix.removeLast() }
        return (prefix + " ⇒ " + result, expr, result)
    }
}

/// `TextTools.evaluate` 의 파서. 문자 배열 위에서 인덱스 하나로 움직인다.
struct ExpressionParser {
    private let s: [Character]
    private var i = 0

    init(_ text: String) {
        s = Array(text.replacingOccurrences(of: "×", with: "*")
                      .replacingOccurrences(of: "÷", with: "/")
                      .replacingOccurrences(of: "−", with: "-"))
    }

    var atEnd: Bool {
        mutating get { skipSpaces(); return i >= s.count }
    }

    private mutating func skipSpaces() { while i < s.count, s[i].isWhitespace { i += 1 } }

    private mutating func peek() -> Character? {
        skipSpaces()
        return i < s.count ? s[i] : nil
    }

    private mutating func eat(_ ch: Character) -> Bool {
        guard peek() == ch else { return false }
        i += 1
        return true
    }

    mutating func parseExpression() -> Double? {
        guard var v = parseTerm() else { return nil }
        while let op = peek(), op == "+" || op == "-" {
            i += 1
            guard let r = parseTerm() else { return nil }
            v = op == "+" ? v + r : v - r
        }
        return v
    }

    private mutating func parseTerm() -> Double? {
        guard var v = parseUnary() else { return nil }
        while let op = peek(), op == "*" || op == "/" || op == "%" {
            i += 1
            guard let r = parseUnary() else { return nil }
            switch op {
            case "*": v *= r
            case "/": guard r != 0 else { return nil }; v /= r
            default: guard r != 0 else { return nil }; v = v.truncatingRemainder(dividingBy: r)
            }
        }
        return v
    }

    private mutating func parseUnary() -> Double? {
        if eat("-") { return parseUnary().map { -$0 } }
        if eat("+") { return parseUnary() }
        return parsePower()
    }

    private mutating func parsePower() -> Double? {
        guard let base = parsePrimary() else { return nil }
        if eat("^") {
            guard let e = parseUnary() else { return nil }
            return pow(base, e)
        }
        return base
    }

    private mutating func parsePrimary() -> Double? {
        guard let ch = peek() else { return nil }
        if ch == "(" {
            i += 1
            guard let v = parseExpression(), eat(")") else { return nil }
            return v
        }
        if isDigit(ch) || ch == "." { return parseNumber() }
        if ch.isLetter { return parseIdentifier() }
        return nil
    }

    private func isDigit(_ ch: Character) -> Bool { ch.isASCII && ch.isNumber }

    /// s[k] == "," 가 천 단위 구분인지: 앞은 숫자, 뒤는 정확히 세 자리 숫자
    private func isThousandsSeparator(at k: Int) -> Bool {
        guard k > 0, isDigit(s[k - 1]), k + 3 < s.count else { return false }
        guard isDigit(s[k + 1]), isDigit(s[k + 2]), isDigit(s[k + 3]) else { return false }
        return k + 4 >= s.count || !isDigit(s[k + 4])
    }

    private mutating func parseNumber() -> Double? {
        var text = ""
        while i < s.count {
            let ch = s[i]
            if isDigit(ch) { text.append(ch); i += 1 }
            else if ch == "_" { i += 1 }
            else if ch == ",", isThousandsSeparator(at: i) { i += 1 }
            else { break }
        }
        if i < s.count, s[i] == "." {
            text.append("."); i += 1
            while i < s.count, isDigit(s[i]) || s[i] == "_" { if s[i] != "_" { text.append(s[i]) }; i += 1 }
        }
        if i < s.count, s[i] == "e" || s[i] == "E" {
            var j = i + 1
            if j < s.count, s[j] == "+" || s[j] == "-" { j += 1 }
            if j < s.count, isDigit(s[j]) {
                text.append("e"); i += 1
                if s[i] == "+" || s[i] == "-" { text.append(s[i]); i += 1 }
                while i < s.count, isDigit(s[i]) { text.append(s[i]); i += 1 }
            }
        }
        if text.hasPrefix(".") { text = "0" + text }
        if text.hasSuffix(".") { text.removeLast() }
        guard !text.isEmpty, let v = Double(text) else { return nil }
        return v
    }

    private mutating func parseIdentifier() -> Double? {
        var name = ""
        while i < s.count, s[i].isLetter || isDigit(s[i]) || s[i] == "_" { name.append(s[i]); i += 1 }
        name = name.lowercased()
        if eat("(") {
            var args: [Double] = []
            if !eat(")") {
                repeat {
                    guard let v = parseExpression() else { return nil }
                    args.append(v)
                } while eat(",")
                guard eat(")") else { return nil }
            }
            return Self.apply(name, args)
        }
        switch name {
        case "pi": return .pi
        case "e": return M_E
        default: return nil
        }
    }

    private static func apply(_ name: String, _ a: [Double]) -> Double? {
        switch (name, a.count) {
        case ("sqrt", 1): return a[0] >= 0 ? a[0].squareRoot() : nil
        case ("abs", 1): return abs(a[0])
        case ("round", 1): return a[0].rounded()
        case ("round", 2):                                   // round(x, 자릿수)
            let f = pow(10, a[1].rounded())
            return f > 0 ? (a[0] * f).rounded() / f : nil
        case ("floor", 1): return a[0].rounded(.down)
        case ("ceil", 1): return a[0].rounded(.up)
        case ("min", let n) where n >= 1: return a.min()
        case ("max", let n) where n >= 1: return a.max()
        default: return nil
        }
    }
}
