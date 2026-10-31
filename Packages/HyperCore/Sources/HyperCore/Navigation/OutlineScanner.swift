import Foundation

public struct OutlineItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable { case heading, bracket, hangul, numbered }
    public let line: Int
    public let level: Int
    public let title: String
    public let kind: Kind
    public var id: Int { line }
}

public struct TimelineItem: Identifiable, Hashable, Sendable {
    public let line: Int
    public let year: Int
    public let month: Int
    public let day: Int
    public let hour: Int?
    public let minute: Int?
    public let preview: String
    /// `## 2026-10-30 (금) 14:05` 형식(앱이 넣은 타임스탬프)이면 true, 로그 등 느슨한 날짜 줄이면 false
    public let precise: Bool
    public var id: Int { line }
    public var dateLabel: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var timeLabel: String? { hour.flatMap { h in minute.map { String(format: "%02d:%02d", h, $0) } } }
    public var monthKey: String { String(format: "%04d-%02d", year, month) }
}

/// 구조 없는 메모에서 아웃라인/타임라인 항목을 뽑는다. 모든 정규식은 줄 단위.
public enum OutlineScanner {
    static let heading = try! NSRegularExpression(pattern: #"^(#{1,6})[ \t]+(\S.{0,120})$"#, options: [.anchorsMatchLines])
    static let bracket = try! NSRegularExpression(pattern: #"^\[([^\]\n]{1,40})\][ \t]*(.{0,80})$"#, options: [.anchorsMatchLines])
    static let hangul = try! NSRegularExpression(pattern: #"^[ \t]*([가나다라마바사아자차카타파하])\.[ \t]+(\S.{0,80})$"#, options: [.anchorsMatchLines])
    static let numbered = try! NSRegularExpression(pattern: #"^[ \t]*(\d{1,2})[.)][ \t]+(\S.{0,80})$"#, options: [.anchorsMatchLines])
    /// 앱이 넣는 타임스탬프 헤딩. 괄호 안 요일은 로케일에 따라 `금`/`Fri`/`ven.` 등 길이가 달라 1~12자 허용.
    static let preciseDate = try! NSRegularExpression(pattern: #"^## (\d{4})-(\d{2})-(\d{2}) \([^)\n]{1,12}\) (\d{2}):(\d{2})[ \t]*$"#, options: [.anchorsMatchLines])
    static let looseDate = try! NSRegularExpression(pattern: #"^(\d{4})[-./](\d{1,2})[-./](\d{1,2})(?:[ T](\d{1,2}):(\d{2}))?"#, options: [.anchorsMatchLines])
    /// `# ` 1단계 헤딩이 코드 주석일 가능성이 높은 패턴 (memo 에 파이썬 주석이 많음)
    static let codeLike = try! NSRegularExpression(pattern: #"^(from |import |print\(|def |class |return |if |for |while |#|\w+\s*=|\$|//|/\*|mypkey|ssh_)"#, options: [])

    public static func outline(_ text: String, index: LineIndex, isMarkdown: Bool = false) -> [OutlineItem] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var items: [OutlineItem] = []
        heading.enumerateMatches(in: text, options: [], range: full) { m, _, _ in
            guard let m else { return }
            let level = m.range(at: 1).length
            let title = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            if preciseDate.firstMatch(in: text, options: [], range: ns.lineRange(for: m.range)) != nil { return }   // 타임스탬프는 타임라인으로
            if level == 1, !isMarkdown, codeLike.firstMatch(in: title, options: [], range: NSRange(location: 0, length: (title as NSString).length)) != nil { return }
            items.append(OutlineItem(line: index.lineNumber(forUTF16Offset: m.range.location), level: level, title: title, kind: .heading))
        }
        bracket.enumerateMatches(in: text, options: [], range: full) { m, _, _ in
            guard let m else { return }
            let t = ns.substring(with: m.range(at: 1))
            if t.hasPrefix("ERROR") || t.hasPrefix("INFO") || t.hasPrefix("WARN") || t.hasPrefix("id=") || t.allSatisfy({ $0.isNumber || $0 == "-" || $0 == ":" }) { return }  // 로그 태그 제외
            items.append(OutlineItem(line: index.lineNumber(forUTF16Offset: m.range.location), level: 2, title: "[\(t)]", kind: .bracket))
        }
        hangul.enumerateMatches(in: text, options: [], range: full) { m, _, _ in
            guard let m else { return }
            items.append(OutlineItem(line: index.lineNumber(forUTF16Offset: m.range.location), level: 3,
                                     title: ns.substring(with: m.range(at: 1)) + ". " + ns.substring(with: m.range(at: 2)), kind: .hangul))
        }
        numbered.enumerateMatches(in: text, options: [], range: full) { m, _, _ in
            guard let m else { return }
            items.append(OutlineItem(line: index.lineNumber(forUTF16Offset: m.range.location), level: 3,
                                     title: ns.substring(with: m.range(at: 1)) + ") " + ns.substring(with: m.range(at: 2)), kind: .numbered))
        }
        return items.sorted { $0.line < $1.line }
    }

    public static func timeline(_ text: String, index: LineIndex) -> [TimelineItem] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var items: [TimelineItem] = []
        var seenLines = Set<Int>()
        preciseDate.enumerateMatches(in: text, options: [], range: full) { m, _, _ in
            guard let m else { return }
            let line = index.lineNumber(forUTF16Offset: m.range.location)
            seenLines.insert(line)
            let next = nextNonEmptyLine(after: line, index: index, text: ns)
            items.append(TimelineItem(line: line, year: int(ns, m, 1), month: int(ns, m, 2), day: int(ns, m, 3),
                                      hour: int(ns, m, 4), minute: int(ns, m, 5), preview: next, precise: true))
        }
        var lastLoose: (y: Int, mo: Int, d: Int, line: Int)?
        looseDate.enumerateMatches(in: text, options: [], range: full) { m, _, _ in
            guard let m else { return }
            let line = index.lineNumber(forUTF16Offset: m.range.location)
            guard !seenLines.contains(line) else { return }
            let y = int(ns, m, 1), mo = int(ns, m, 2), d = int(ns, m, 3)
            guard (1990...2100).contains(y), (1...12).contains(mo), (1...31).contains(d) else { return }
            // 연속된 같은 날짜(로그 덤프)는 첫 줄만
            if let l = lastLoose, l.y == y, l.mo == mo, l.d == d, line - l.line <= 3 { lastLoose = (y, mo, d, line); return }
            lastLoose = (y, mo, d, line)
            let lr = ns.lineRange(for: m.range)
            var preview = ns.substring(with: lr).trimmingCharacters(in: .whitespacesAndNewlines)
            if preview.count > 90 { preview = String(preview.prefix(90)) + "…" }
            let h = m.range(at: 4).location != NSNotFound ? int(ns, m, 4) : nil
            let mi = m.range(at: 5).location != NSNotFound ? int(ns, m, 5) : nil
            items.append(TimelineItem(line: line, year: y, month: mo, day: d, hour: h, minute: mi, preview: preview, precise: false))
        }
        return items.sorted { $0.line < $1.line }
    }

    private static func int(_ ns: NSString, _ m: NSTextCheckingResult, _ i: Int) -> Int {
        let r = m.range(at: i); return r.location == NSNotFound ? 0 : (Int(ns.substring(with: r)) ?? 0)
    }

    private static func nextNonEmptyLine(after line: Int, index: LineIndex, text: NSString) -> String {
        var n = line + 1
        while n <= index.lineCount, n <= line + 5 {
            let r = index.range(ofLine: n)
            let safe = NSIntersectionRange(r, NSRange(location: 0, length: text.length))
            let s = text.substring(with: safe).trimmingCharacters(in: .whitespaces)
            if !s.isEmpty { return s.count > 90 ? String(s.prefix(90)) + "…" : s }
            n += 1
        }
        return ""
    }
}
