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
}
