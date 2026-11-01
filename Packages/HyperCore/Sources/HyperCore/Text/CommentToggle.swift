import Foundation

/// 파일 종류별 주석 기호. `line` 이 있으면 줄 주석을 쓰고, 없으면 `block` 을 줄마다 감싼다 (`<!-- … -->`, `/* … */`).
public struct CommentSyntax: Sendable {
    public var line: String?
    public var block: (open: String, close: String)?
    public init(line: String? = nil, block: (open: String, close: String)? = nil) {
        self.line = line
        self.block = block
    }
    /// 토글할 수 있는 기호가 하나라도 있는가
    public var isUsable: Bool { line != nil || block != nil }
}

/// 확장자 → 주석 기호. 코드 언어(사용자 정의 문법 포함)는 `CodeLanguage` 의 주석 정의를 그대로 쓰고, 메모·마크다운은 여기서 정한다.
public enum CommentRegistry {
    public static func syntax(for url: URL, userGrammars store: UserGrammarStore = .shared) -> CommentSyntax {
        let grammar = GrammarRegistry.grammar(for: url, userGrammars: store)
        if let code = grammar as? CodeGrammar { return code.language.commentSyntax }
        if let notes = grammar as? PlainNotesGrammar, notes.isMarkdown { return CommentSyntax(block: ("<!--", "-->")) }
        return CommentSyntax(line: "//")   // 메모(.txt · 확장자 없음) — 코드 조각이 섞인 메모라 `//` 가 가장 무난하다
    }
}

public extension CodeLanguage {
    /// 주석 토글용 기호. 마크업(HTML/XML)은 `<!-- -->`, CSS 는 `/* */` 블록만 (`//` 는 SCSS/Less 전용), 그 밖은 첫 줄 주석 기호 + 블록 주석.
    var commentSyntax: CommentSyntax {
        switch mode {
        case .markup: return CommentSyntax(block: ("<!--", "-->"))
        case .css: return CommentSyntax(block: ("/*", "*/"))
        default:
            let line = lineComments.first.map { String(utf16CodeUnits: $0, count: $0.count) }
            let block = blockComment.map { (String(utf16CodeUnits: $0.start, count: $0.start.count), String(utf16CodeUnits: $0.end, count: $0.end.count)) }
            return CommentSyntax(line: line, block: block)
        }
    }
}

public extension TextTools {
    /// 주석 토글 (VS Code 방식). 빈 줄(공백만 있는 줄)은 건드리지 않는다.
    /// - 비어 있지 않은 줄이 전부 주석이면 → 모두 해제 (기호와 그 뒤 공백 하나 제거. 블록은 닫는 기호와 그 앞 공백 하나도 제거)
    /// - 아니면 → 비어 있지 않은 줄을 모두 주석 처리. 기호는 각 줄 들여쓰기의 공통 접두(= 가장 얕은 들여쓰기) 뒤에 넣어 세로로 맞추고 공백 하나를 띄운다.
    ///   탭·공백은 있는 그대로 유지한다. 모든 줄이 비어 있으면 그 줄들 자체에 기호를 넣는다 (빈 줄에서 ⌘/ 를 누르면 `// ` 가 생긴다).
    static func toggleLineComment(lines: [String], syntax: CommentSyntax) -> [String] {
        guard syntax.isUsable, !lines.isEmpty else { return lines }
        // CRLF 문서: `\n` 으로 가른 줄 끝에 남는 `\r` 은 줄바꿈의 일부다 — 떼어 두고 처리한 뒤 되돌린다 (그대로 두면 `-->` 가 `\r` 뒤에 붙어 줄이 갈라진다)
        if lines.contains(where: { $0.hasSuffix("\r") }) {
            let out = toggleLineComment(lines: lines.map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }, syntax: syntax)
            return zip(out, lines).map { $1.hasSuffix("\r") ? $0 + "\r" : $0 }
        }
        let open: String, close: String?
        if let l = syntax.line { open = l; close = nil } else { open = syntax.block!.open; close = syntax.block!.close }

        func split(_ s: String) -> (indent: Substring, rest: Substring) {
            let i = s.firstIndex { $0 != " " && $0 != "\t" } ?? s.endIndex
            return (s[..<i], s[i...])
        }
        func isCommented(_ s: String) -> Bool {
            let rest = split(s).rest
            guard rest.hasPrefix(open) else { return false }
            guard let close else { return true }
            var body = rest.dropFirst(open.count)
            while let last = body.last, last == " " || last == "\t" { body.removeLast() }
            return body.hasSuffix(close)
        }

        var targets = lines.indices.filter { !split(lines[$0]).rest.isEmpty }
        if targets.isEmpty { targets = Array(lines.indices) }

        if targets.allSatisfy({ isCommented(lines[$0]) }) {
            var out = lines
            for i in targets {
                let (indent, rest) = split(lines[i])
                var body = rest.dropFirst(open.count)
                if body.first == " " { body.removeFirst() }
                if let close {
                    var trailing = Substring("")
                    while let last = body.last, last == " " || last == "\t" { trailing.insert(last, at: trailing.startIndex); body.removeLast() }
                    if body.hasSuffix(close) { body = body.dropLast(close.count) }
                    if body.last == " " { body.removeLast() }
                    body += trailing
                }
                out[i] = String(indent) + body
            }
            return out
        }

        // 공통 들여쓰기 접두 (공백·탭이 섞이면 공통 부분까지만)
        var prefix = split(lines[targets[0]]).indent
        for i in targets.dropFirst() {
            let ind = split(lines[i]).indent
            var k = prefix.startIndex, j = ind.startIndex
            while k < prefix.endIndex, j < ind.endIndex, prefix[k] == ind[j] { k = prefix.index(after: k); j = ind.index(after: j) }
            prefix = prefix[..<k]
        }
        let cut = prefix.count
        var out = lines
        for i in targets {
            let s = lines[i]
            let at = s.index(s.startIndex, offsetBy: cut)
            var line = String(s[..<at]) + open + " " + s[at...]
            if let close {
                // 빈 줄(공백만)에 블록 주석을 넣을 때는 `<!--  -->` 가 되지 않게 한 칸만
                if s[at...].isEmpty { line = String(s[..<at]) + open + " " + close } else { line += " " + close }
            }
            out[i] = line
        }
        return out
    }
}
