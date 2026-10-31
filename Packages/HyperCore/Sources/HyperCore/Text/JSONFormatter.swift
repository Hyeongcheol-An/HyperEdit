import Foundation

/// JSON 정리(보기 좋게 / 한 줄로). Foundation 의 JSONSerialization 은 키 순서를 바꾸고 숫자를 다시 쓰므로(1.0 → 1, 큰 정수 손실)
/// UTF-8 바이트 위에서 도는 작은 재귀 하강 파서로 **키 순서·숫자 표기를 그대로** 두고 공백만 다시 만든다.
/// 입력은 느슨하게 받는다 — UTF-8 BOM, 뒤따르는 쉼표, `//` `/* */` 주석(JSONC) — 출력은 항상 엄격한 JSON.
/// 문자열은 의미를 유지한 채 다시 이스케이프한다 (제어 문자만 `\n` `\t` `\u00XX` 로, 한글·이모지 같은 비ASCII 는 그대로, `\/` 는 `/` 로).
public enum JSONFormatter {
    public enum Indent: Sendable, Equatable {
        case spaces(Int)
        case tabs
    }

    /// 1-based 줄·열(UTF-16 단위) + 문제 문자의 UTF-16 오프셋. `line:column` 으로 출력 패널에 보여 주고 캐럿을 옮기는 데 쓴다.
    public struct SyntaxError: Error, Equatable, Sendable {
        public let line: Int
        public let column: Int
        public let offset: Int
        public let message: String
        public var description: String { "\(line):\(column) \(message)" }
    }

    public static func format(_ s: String, indent: Indent = .spaces(2)) throws -> String {
        try run(s, indent: indent)
    }

    public static func minify(_ s: String) throws -> String {
        try run(s, indent: nil)
    }

    /// 문자열을 JSON 문자열 리터럴로 (따옴표 포함). 스니펫 파일 같은 자체 JSON 을 쓸 때 사용.
    public static func quote(_ s: String) -> String {
        var out: [UInt8] = [0x22]
        out.reserveCapacity(s.utf8.count + 2)
        for b in s.utf8 { appendEscaped(b, to: &out) }
        out.append(0x22)
        return String(decoding: out, as: UTF8.self)
    }

    // MARK: - 구현

    private static func run(_ s: String, indent: Indent?) throws -> String {
        var bytes = Array(s.utf8)
        var start = 0
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { start = 3 }
        let trailingNewline = bytes.last == 0x0A
        var out: [UInt8] = []
        out.reserveCapacity(indent == nil ? bytes.count : bytes.count + bytes.count / 2)
        try bytes.withUnsafeBufferPointer { buf in
            var p = Parser(buf: buf, pos: start, indentUnit: indent.map(unit) ?? [], pretty: indent != nil)
            try p.skipTrivia()
            guard p.pos < buf.count else { throw p.error(at: p.pos, "Unexpected end of input") }
            try p.value(depth: 0, into: &out)
            try p.skipTrivia()
            if p.pos < buf.count { throw p.error(at: p.pos, "Unexpected character after JSON value") }
        }
        if trailingNewline { out.append(0x0A) }
        bytes.removeAll()
        return String(decoding: out, as: UTF8.self)
    }

    private static func unit(_ indent: Indent) -> [UInt8] {
        switch indent {
        case .tabs: return [0x09]
        case .spaces(let n): return [UInt8](repeating: 0x20, count: max(0, n))
        }
    }

    @inline(__always) private static func appendEscaped(_ b: UInt8, to out: inout [UInt8]) {
        switch b {
        case 0x22: out.append(0x5C); out.append(0x22)
        case 0x5C: out.append(0x5C); out.append(0x5C)
        case 0x08: out.append(0x5C); out.append(0x62)
        case 0x0C: out.append(0x5C); out.append(0x66)
        case 0x0A: out.append(0x5C); out.append(0x6E)
        case 0x0D: out.append(0x5C); out.append(0x72)
        case 0x09: out.append(0x5C); out.append(0x74)
        case 0..<0x20: appendUnicodeEscape(UInt16(b), to: &out)
        default: out.append(b)
        }
    }

    private static func appendUnicodeEscape(_ v: UInt16, to out: inout [UInt8]) {
        let hex: [UInt8] = Array("0123456789abcdef".utf8)
        out.append(0x5C); out.append(0x75)
        out.append(hex[Int(v >> 12) & 0xF]); out.append(hex[Int(v >> 8) & 0xF]); out.append(hex[Int(v >> 4) & 0xF]); out.append(hex[Int(v) & 0xF])
    }

    private struct Parser {
        let buf: UnsafeBufferPointer<UInt8>
        var pos: Int
        let indentUnit: [UInt8]
        let pretty: Bool
        var n: Int { buf.count }

        @inline(__always) func c(_ i: Int) -> UInt8 { i < n ? buf[i] : 0 }

        func error(at i: Int, _ message: String) -> SyntaxError {
            let upto = min(i, n)
            var line = 1, lineStart = 0
            var k = 0
            while k < upto { if buf[k] == 0x0A { line += 1; lineStart = k + 1 }; k += 1 }
            let col = String(decoding: UnsafeBufferPointer(rebasing: buf[lineStart..<upto]), as: UTF8.self).utf16.count + 1
            let offset = String(decoding: UnsafeBufferPointer(rebasing: buf[0..<upto]), as: UTF8.self).utf16.count
            return SyntaxError(line: line, column: col, offset: offset, message: message)
        }

        /// 공백 + 주석(`//` 줄 끝까지, `/* */`)
        mutating func skipTrivia() throws {
            while pos < n {
                let b = buf[pos]
                if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D { pos += 1; continue }
                if b == 0x2F, c(pos + 1) == 0x2F {
                    pos += 2
                    while pos < n, buf[pos] != 0x0A { pos += 1 }
                    continue
                }
                if b == 0x2F, c(pos + 1) == 0x2A {
                    let start = pos
                    pos += 2
                    while pos < n, !(buf[pos] == 0x2A && c(pos + 1) == 0x2F) { pos += 1 }
                    guard pos < n else { throw error(at: start, "Unterminated comment") }
                    pos += 2
                    continue
                }
                return
            }
        }

        mutating func newline(depth: Int, into out: inout [UInt8]) {
            out.append(0x0A)
            for _ in 0..<depth { out.append(contentsOf: indentUnit) }
        }

        mutating func value(depth: Int, into out: inout [UInt8]) throws {
            guard pos < n else { throw error(at: pos, "Unexpected end of input") }
            switch buf[pos] {
            case 0x7B: try object(depth: depth, into: &out)
            case 0x5B: try array(depth: depth, into: &out)
            case 0x22: try string(into: &out)
            case 0x74: try literal("true", into: &out)
            case 0x66: try literal("false", into: &out)
            case 0x6E: try literal("null", into: &out)
            case 0x2D, 0x30...0x39: try number(into: &out)
            case 0x7D: throw error(at: pos, "Unexpected '}'")
            case 0x5D: throw error(at: pos, "Unexpected ']'")
            case 0x2C: throw error(at: pos, "Unexpected ','")
            case 0x27: throw error(at: pos, "Single quotes are not allowed in JSON — use double quotes")
            default: throw error(at: pos, "Unexpected character '\(describe(buf[pos]))'")
            }
        }

        private func describe(_ b: UInt8) -> String {
            if b >= 0x20, b < 0x7F { return String(UnicodeScalar(b)) }
            // 비ASCII 는 해당 UTF-8 시퀀스 전체를 보여 준다
            if b >= 0xC0 {
                var e = pos + 1
                while e < n, buf[e] & 0xC0 == 0x80 { e += 1 }
                return String(decoding: UnsafeBufferPointer(rebasing: buf[pos..<e]), as: UTF8.self)
            }
            return String(format: "\\u%04x", Int(b))
        }

        mutating func object(depth: Int, into out: inout [UInt8]) throws {
            let open = pos
            pos += 1
            out.append(0x7B)
            try skipTrivia()
            if c(pos) == 0x7D { pos += 1; out.append(0x7D); return }
            var first = true
            while true {
                try skipTrivia()
                guard pos < n else { throw error(at: open, "Unterminated object — missing '}'") }
                if buf[pos] == 0x7D {   // 뒤따르는 쉼표 뒤의 닫힘
                    pos += 1; break
                }
                guard buf[pos] == 0x22 else {
                    if buf[pos] == 0x27 { throw error(at: pos, "Single quotes are not allowed in JSON — use double quotes") }
                    throw error(at: pos, first ? "Expected a string key" : "Expected a string key after ','")
                }
                if !first { out.append(0x2C) }
                if pretty { newline(depth: depth + 1, into: &out) }
                try string(into: &out)
                try skipTrivia()
                guard c(pos) == 0x3A else { throw error(at: pos, "Expected ':' after object key") }
                pos += 1
                out.append(0x3A)
                if pretty { out.append(0x20) }
                try skipTrivia()
                try value(depth: depth + 1, into: &out)
                first = false
                try skipTrivia()
                guard pos < n else { throw error(at: open, "Unterminated object — missing '}'") }
                if buf[pos] == 0x2C { pos += 1; continue }
                if buf[pos] == 0x7D { pos += 1; break }
                throw error(at: pos, "Expected ',' or '}' in object")
            }
            if pretty, !first { newline(depth: depth, into: &out) }
            out.append(0x7D)
        }

        mutating func array(depth: Int, into out: inout [UInt8]) throws {
            let open = pos
            pos += 1
            out.append(0x5B)
            try skipTrivia()
            if c(pos) == 0x5D { pos += 1; out.append(0x5D); return }
            var first = true
            while true {
                try skipTrivia()
                guard pos < n else { throw error(at: open, "Unterminated array — missing ']'") }
                if buf[pos] == 0x5D { pos += 1; break }
                if !first { out.append(0x2C) }
                if pretty { newline(depth: depth + 1, into: &out) }
                try value(depth: depth + 1, into: &out)
                first = false
                try skipTrivia()
                guard pos < n else { throw error(at: open, "Unterminated array — missing ']'") }
                if buf[pos] == 0x2C { pos += 1; continue }
                if buf[pos] == 0x5D { pos += 1; break }
                throw error(at: pos, "Expected ',' or ']' in array")
            }
            if pretty, !first { newline(depth: depth, into: &out) }
            out.append(0x5D)
        }

        mutating func literal(_ word: StaticString, into out: inout [UInt8]) throws {
            let start = pos
            let ok = word.withUTF8Buffer { w -> Bool in
                guard start + w.count <= n else { return false }
                for k in 0..<w.count where buf[start + k] != w[k] { return false }
                return true
            }
            let end = word.utf8CodeUnitCount
            guard ok, start + end >= n || !isWordByte(buf[start + end]) else {
                var e = start
                while e < n, isWordByte(buf[e]) { e += 1 }
                throw error(at: start, "Unexpected '\(String(decoding: UnsafeBufferPointer(rebasing: buf[start..<e]), as: UTF8.self))'")
            }
            pos += end
            word.withUTF8Buffer { out.append(contentsOf: $0) }
        }

        @inline(__always) private func isWordByte(_ b: UInt8) -> Bool {
            (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x5F || b >= 0x80
        }
        @inline(__always) private func isDigit(_ b: UInt8) -> Bool { b >= 0x30 && b <= 0x39 }

        /// 숫자는 문법만 검사하고 원문 그대로 복사한다 (1.0 → 1 로 바꾸지 않고 큰 정수도 손실 없음)
        mutating func number(into out: inout [UInt8]) throws {
            let start = pos
            if buf[pos] == 0x2D { pos += 1 }
            guard pos < n, isDigit(buf[pos]) else { throw error(at: pos, "Expected a digit after '-'") }
            if buf[pos] == 0x30 {
                pos += 1
                if pos < n, isDigit(buf[pos]) { throw error(at: pos, "Leading zeros are not allowed") }
            } else {
                while pos < n, isDigit(buf[pos]) { pos += 1 }
            }
            if c(pos) == 0x2E {
                pos += 1
                guard pos < n, isDigit(buf[pos]) else { throw error(at: pos, "Expected a digit after '.'") }
                while pos < n, isDigit(buf[pos]) { pos += 1 }
            }
            if c(pos) == 0x65 || c(pos) == 0x45 {
                pos += 1
                if c(pos) == 0x2B || c(pos) == 0x2D { pos += 1 }
                guard pos < n, isDigit(buf[pos]) else { throw error(at: pos, "Expected a digit in exponent") }
                while pos < n, isDigit(buf[pos]) { pos += 1 }
            }
            if pos < n, isWordByte(buf[pos]) { throw error(at: pos, "Invalid number") }
            out.append(contentsOf: UnsafeBufferPointer(rebasing: buf[start..<pos]))
        }

        mutating func string(into out: inout [UInt8]) throws {
            let open = pos
            pos += 1
            out.append(0x22)
            // 빠른 길: 역슬래시·제어 문자가 없으면 그대로 복사
            var i = pos
            while i < n {
                let b = buf[i]
                if b == 0x22 {
                    out.append(contentsOf: UnsafeBufferPointer(rebasing: buf[pos..<i]))
                    out.append(0x22)
                    pos = i + 1
                    return
                }
                if b == 0x5C || b < 0x20 { break }
                i += 1
            }
            out.append(contentsOf: UnsafeBufferPointer(rebasing: buf[pos..<i]))
            pos = i
            // 느린 길: 이스케이프 해석 → 최소 이스케이프로 다시 쓰기
            while pos < n {
                let b = buf[pos]
                if b == 0x22 { pos += 1; out.append(0x22); return }
                if b == 0x0A || b == 0x0D { throw error(at: open, "Unterminated string") }
                if b < 0x20 { throw error(at: pos, "Control character in string must be escaped") }
                if b != 0x5C { out.append(b); pos += 1; continue }
                // 역슬래시
                let escAt = pos
                pos += 1
                guard pos < n else { throw error(at: open, "Unterminated string") }
                let e = buf[pos]
                pos += 1
                switch e {
                case 0x22, 0x5C: out.append(0x5C); out.append(e)
                case 0x2F: out.append(0x2F)                                  // `\/` → `/`
                case 0x62, 0x66, 0x6E, 0x72, 0x74: out.append(0x5C); out.append(e)
                case 0x75:
                    guard let v = hex4(at: pos) else { throw error(at: escAt, "Invalid \\u escape") }
                    pos += 4
                    if v >= 0xD800, v <= 0xDBFF {
                        // 서러게이트 쌍이면 합쳐서 UTF-8 로, 아니면 이스케이프를 유지
                        if c(pos) == 0x5C, c(pos + 1) == 0x75, let lo = hex4(at: pos + 2), lo >= 0xDC00, lo <= 0xDFFF {
                            pos += 6
                            let scalar = 0x10000 + ((UInt32(v) - 0xD800) << 10) + (UInt32(lo) - 0xDC00)
                            appendUTF8(scalar, to: &out)
                        } else {
                            JSONFormatter.appendUnicodeEscape(v, to: &out)
                        }
                    } else if v >= 0xDC00, v <= 0xDFFF {
                        JSONFormatter.appendUnicodeEscape(v, to: &out)
                    } else if v < 0x20 || v == 0x22 || v == 0x5C {
                        JSONFormatter.appendEscaped(UInt8(v), to: &out)
                    } else {
                        appendUTF8(UInt32(v), to: &out)
                    }
                default: throw error(at: escAt, "Invalid escape '\\\(describe(e))'")
                }
            }
            throw error(at: open, "Unterminated string")
        }

        private func hex4(at i: Int) -> UInt16? {
            guard i + 4 <= n else { return nil }
            var v: UInt16 = 0
            for k in 0..<4 {
                let b = buf[i + k]
                let d: UInt16
                switch b {
                case 0x30...0x39: d = UInt16(b - 0x30)
                case 0x41...0x46: d = UInt16(b - 0x41 + 10)
                case 0x61...0x66: d = UInt16(b - 0x61 + 10)
                default: return nil
                }
                v = v << 4 | d
            }
            return v
        }

        private func appendUTF8(_ s: UInt32, to out: inout [UInt8]) {
            if s < 0x80 { out.append(UInt8(s)) }
            else if s < 0x800 { out.append(UInt8(0xC0 | (s >> 6))); out.append(UInt8(0x80 | (s & 0x3F))) }
            else if s < 0x10000 { out.append(UInt8(0xE0 | (s >> 12))); out.append(UInt8(0x80 | ((s >> 6) & 0x3F))); out.append(UInt8(0x80 | (s & 0x3F))) }
            else { out.append(UInt8(0xF0 | (s >> 18))); out.append(UInt8(0x80 | ((s >> 12) & 0x3F))); out.append(UInt8(0x80 | ((s >> 6) & 0x3F))); out.append(UInt8(0x80 | (s & 0x3F))) }
        }
    }
}
