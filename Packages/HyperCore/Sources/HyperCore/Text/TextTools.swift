import Foundation

/// UltraEdit 편집 도구 계승: 줄 단위·선택 단위 순수 변환 함수.
public enum TextTools {
    // MARK: 줄 단위

    public static func sortLines(_ lines: [String], ascending: Bool = true, numeric: Bool = false, caseInsensitive: Bool = true) -> [String] {
        let sorted = lines.sorted { a, b in
            if numeric, let x = leadingNumber(a), let y = leadingNumber(b), x != y { return x < y }
            let r = caseInsensitive ? a.localizedCaseInsensitiveCompare(b) : a.compare(b)
            return r == .orderedAscending
        }
        return ascending ? sorted : Array(sorted.reversed())
    }

    private static func leadingNumber(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        var end = t.startIndex
        while end < t.endIndex, t[end].isNumber || t[end] == "." || t[end] == "-" || t[end] == "," { end = t.index(after: end) }
        return Double(t[t.startIndex..<end].replacingOccurrences(of: ",", with: ""))
    }

    /// 첫 등장만 남기고 중복 줄 제거 (순서 유지)
    public static func dedupeLines(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        return lines.filter { seen.insert($0).inserted }
    }

    public static func removeBlankLines(_ lines: [String]) -> [String] {
        lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    public static func trimTrailing(_ lines: [String]) -> [String] {
        lines.map { line in
            var s = Substring(line)
            while let last = s.last, last == " " || last == "\t" { s.removeLast() }
            return String(s)
        }
    }

    public static func trimBoth(_ lines: [String]) -> [String] {
        lines.map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// 탭 → 공백 (탭 스톱 기준으로 열 맞춤)
    public static func tabsToSpaces(_ lines: [String], width: Int = 4) -> [String] {
        lines.map { line in
            var out = ""; var col = 0
            for ch in line {
                if ch == "\t" { let n = width - (col % width); out += String(repeating: " ", count: n); col += n }
                else { out.append(ch); col += (ch.unicodeScalars.first.map { $0.value >= 0x1100 } ?? false) ? 2 : 1 }
            }
            return out
        }
    }

    /// 줄 앞쪽 공백만 탭으로
    public static func spacesToTabs(_ lines: [String], width: Int = 4) -> [String] {
        lines.map { line in
            var count = 0
            var idx = line.startIndex
            while idx < line.endIndex, line[idx] == " " { count += 1; idx = line.index(after: idx) }
            guard count >= width else { return line }
            return String(repeating: "\t", count: count / width) + String(repeating: " ", count: count % width) + line[idx...]
        }
    }

    public static func joinLines(_ lines: [String], separator: String = " ") -> [String] {
        [lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: separator)]
    }

    public static func reverseLines(_ lines: [String]) -> [String] { Array(lines.reversed()) }

    public static func numberLines(_ lines: [String], start: Int = 1, separator: String = ". ") -> [String] {
        let width = String(start + lines.count - 1).count
        return lines.enumerated().map { i, l in String(repeating: " ", count: width - String(start + i).count) + "\(start + i)" + separator + l }
    }

    // MARK: 선택 단위

    public static func upper(_ s: String) -> String { s.uppercased() }
    public static func lower(_ s: String) -> String { s.lowercased() }
    public static func capitalize(_ s: String) -> String { s.capitalized }
    public static func invertCase(_ s: String) -> String {
        String(s.map { c -> Character in
            if c.isUppercase { return Character(c.lowercased()) }
            if c.isLowercase { return Character(c.uppercased()) }
            return c
        })
    }

    /// 선택 통계: 줄/단어/문자(공백 제외)/바이트(UTF-8)
    public static func stats(_ s: String) -> (lines: Int, words: Int, chars: Int, charsNoSpace: Int, bytes: Int) {
        let lines = s.isEmpty ? 0 : s.split(separator: "\n", omittingEmptySubsequences: false).count
        let words = s.split { $0.isWhitespace || $0.isNewline }.count
        let chars = s.count
        let noSpace = s.filter { !$0.isWhitespace && !$0.isNewline }.count
        return (lines, words, chars, noSpace, s.utf8.count)
    }

    // MARK: 열 맞춤 (탭 표 · 마크다운 표)

    /// 고정폭 표시 폭: 한글·CJK·전각·이모지 2칸, 결합 문자·제로폭 0칸, 나머지 1칸. 탭은 1칸으로 센다.
    public static func displayWidth(_ s: String) -> Int {
        var w = 0
        for u in s.unicodeScalars { w += scalarWidth(u) }
        return w
    }

    static func scalarWidth(_ u: Unicode.Scalar) -> Int {
        let v = u.value
        if v < 0x20 { return v == 9 ? 1 : 0 }
        if v < 0x7F { return 1 }
        if v < 0xA0 { return 0 }
        switch u.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .format, .control: return 0
        default: break
        }
        if (0x1160...0x11FF).contains(v) || (0xD7B0...0xD7FF).contains(v) { return 0 }   // 한글 중성·종성 자모 (초성에 붙는다)
        return isWide(v) ? 2 : 1
    }

    /// 동아시아 폭 Wide/Fullwidth + 이모지 표시 문자
    private static func isWide(_ v: UInt32) -> Bool {
        switch v {
        case 0x1100...0x115F, 0x231A...0x231B, 0x2329...0x232A, 0x23E9...0x23EC, 0x23F0, 0x23F3, 0x25FD...0x25FE,
             0x2614...0x2615, 0x2648...0x2653, 0x267F, 0x2693, 0x26A1, 0x26AA...0x26AB, 0x26BD...0x26BE, 0x26C4...0x26C5,
             0x26CE, 0x26D4, 0x26EA, 0x26F2...0x26F3, 0x26F5, 0x26FA, 0x26FD, 0x2705, 0x270A...0x270B, 0x2728, 0x274C,
             0x274E, 0x2753...0x2755, 0x2757, 0x2795...0x2797, 0x27B0, 0x27BF, 0x2B1B...0x2B1C, 0x2B50, 0x2B55,
             0x2E80...0x303E, 0x3041...0x33FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xA000...0xA4CF, 0xA960...0xA97F,
             0xAC00...0xD7A3, 0xF900...0xFAFF, 0xFE10...0xFE19, 0xFE30...0xFE6F, 0xFF00...0xFF60, 0xFFE0...0xFFE6,
             0x16FE0...0x16FE4, 0x17000...0x18AFF, 0x1B000...0x1B2FF, 0x1F004, 0x1F0CF, 0x1F18E, 0x1F191...0x1F19A,
             0x1F200...0x1F251, 0x1F300...0x1F64F, 0x1F680...0x1F6FF, 0x1F7E0...0x1F7EB, 0x1F90C...0x1F9FF,
             0x1FA70...0x1FAFF, 0x20000...0x3FFFD:
            return true
        default:
            return false
        }
    }

    /// 줄 묶음의 열 구분자 자동 판별: 탭이 하나라도 있으면 탭, 아니면 모든 줄에 `|` 가 있을 때 파이프(마크다운 표), 둘 다 아니면 nil
    public static func columnSeparator(for lines: [String]) -> Character? {
        if lines.contains(where: { $0.contains("\t") }) { return "\t" }
        if !lines.isEmpty, lines.allSatisfy({ $0.contains("|") }) { return "|" }
        return nil
    }

    /// 구분자로 나뉜 열을 표시 폭 기준으로 맞춘다. 구분자가 없는 줄은 그대로.
    /// - 탭 등 일반 구분자: 셀을 열 최대 폭까지 공백으로 채우고 `gap` 칸 띄워 잇는다 (결과에는 구분자가 남지 않아 어느 편집기에서나 같은 모양).
    ///   첫 셀의 들여쓰기는 유지하고 끝 공백은 뗀다.
    /// - `|`: 마크다운 표. ` | ` 로 잇고 셀 안을 채우며, `---`/`:--:` 구분 줄은 열 폭에 맞춰 다시 그린다. `--:` 열은 오른쪽 정렬.
    public static func alignColumns(_ lines: [String], separator: Character = "\t", gap: Int = 2) -> [String] {
        if separator == "|" { return alignPipeTable(lines) }
        let rows: [[String]?] = lines.map { line in
            guard line.contains(separator) else { return nil }
            var cells = line.split(separator: separator, omittingEmptySubsequences: false).map { String($0) }
            for k in cells.indices {
                cells[k] = k == 0 ? trimTrailingSpaces(cells[k]) : cells[k].trimmingCharacters(in: .whitespaces)
            }
            return cells
        }
        var widths: [Int] = []
        for case let cells? in rows {
            for (k, c) in cells.enumerated() {
                let w = displayWidth(c)
                if k >= widths.count { widths.append(w) } else { widths[k] = max(widths[k], w) }
            }
        }
        return zip(lines, rows).map { line, cells in
            guard let cells else { return line }
            var out = ""
            for (k, c) in cells.enumerated() {
                out += c
                if k < cells.count - 1 { out += String(repeating: " ", count: widths[k] - displayWidth(c) + gap) }
            }
            return trimTrailingSpaces(out)
        }
    }

    private static func trimTrailingSpaces(_ s: String) -> String {
        var t = Substring(s)
        while let last = t.last, last == " " || last == "\t" { t.removeLast() }
        return String(t)
    }

    private struct PipeRow {
        var indent: String
        var leading: Bool
        var trailing: Bool
        var cells: [String]
        var isRule: Bool
    }

    private static func alignPipeTable(_ lines: [String]) -> [String] {
        let rows: [PipeRow?] = lines.map { line in
            guard line.contains("|") else { return nil }
            let indentEnd = line.firstIndex { $0 != " " && $0 != "\t" } ?? line.endIndex
            let indent = String(line[..<indentEnd])
            var body = String(line[indentEnd...]).trimmingCharacters(in: .whitespaces)
            let leading = body.hasPrefix("|")
            if leading { body.removeFirst() }
            let trailing = body.hasSuffix("|")
            if trailing { body.removeLast() }
            let cells = body.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            let isRule = cells.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0 == "-" || $0 == ":" } } && cells.contains { $0.contains("-") }
            return PipeRow(indent: indent, leading: leading, trailing: trailing, cells: cells, isRule: isRule)
        }
        var widths: [Int] = []
        var rightAligned: [Bool] = []
        let hasRule = rows.contains { $0?.isRule == true }
        for case let row? in rows {
            for (k, c) in row.cells.enumerated() {
                let w = row.isRule ? 3 : displayWidth(c)
                if k >= widths.count { widths.append(w) } else { widths[k] = max(widths[k], w) }
                if k >= rightAligned.count { rightAligned.append(false) }
                if row.isRule, c.hasSuffix(":"), !c.hasPrefix(":") { rightAligned[k] = true }
            }
        }
        if hasRule { widths = widths.map { max($0, 3) } }
        return zip(lines, rows).map { line, row in
            guard let row else { return line }
            var parts: [String] = []
            for (k, c) in row.cells.enumerated() {
                let width = widths[k]
                if row.isRule {
                    let left = c.hasPrefix(":"), right = c.hasSuffix(":") && c.count > 1
                    let dashes = max(1, width - (left ? 1 : 0) - (right ? 1 : 0))
                    parts.append((left ? ":" : "") + String(repeating: "-", count: dashes) + (right ? ":" : ""))
                } else {
                    let pad = String(repeating: " ", count: max(0, width - displayWidth(c)))
                    let isLast = k == row.cells.count - 1
                    if isLast && !row.trailing { parts.append(c) }
                    else if rightAligned[k] { parts.append(pad + c) }
                    else { parts.append(c + pad) }
                }
            }
            var out = row.indent + (row.leading ? "| " : "") + parts.joined(separator: " | ")
            if row.trailing { out += " |" }
            return trimTrailingSpaces(out)
        }
    }
}
