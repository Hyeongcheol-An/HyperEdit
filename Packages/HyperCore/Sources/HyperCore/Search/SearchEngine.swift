import Foundation

public struct SearchOptions: Equatable, Sendable, Codable {
    public var regex = false
    public var caseSensitive = false
    public var wholeWord = false
    public init() {}
}

public struct SearchHit: Identifiable, Hashable, Sendable {
    public let id: Int
    public let range: NSRange          // 문서 전체 기준 (UTF-16)
    public let line: Int               // 1-based
    public let column: Int             // 1-based
    public let lineText: String        // 미리보기(최대 160자, 매치 주변)
    public let matchInLine: NSRange    // lineText 기준 매치 범위
}

public enum SearchError: Error, Equatable { case invalidRegex(String) }

public enum SearchEngine {
    /// 검색 옵션에 맞는 정규식 (일반 검색도 이스케이프해 정규식으로 통일)
    public static func makeRegex(_ query: String, options: SearchOptions) throws -> NSRegularExpression {
        var pattern = options.regex ? query : NSRegularExpression.escapedPattern(for: query)
        if options.wholeWord { pattern = "\\b(?:" + pattern + ")\\b" }
        var opts: NSRegularExpression.Options = [.anchorsMatchLines]   // ^ $ 는 줄 단위 (에디터 관례)
        if !options.caseSensitive { opts.insert(.caseInsensitive) }
        do { return try NSRegularExpression(pattern: pattern, options: opts) }
        catch { throw SearchError.invalidRegex(error.localizedDescription) }
    }

    /// 매치 하나의 치환 문자열. 정규식 모드면 $1 같은 템플릿을 전개하고, 아니면 그대로.
    public static func replacement(for range: NSRange, in text: String, query: String, options: SearchOptions, template: String) -> String {
        guard options.regex, let re = try? makeRegex(query, options: options),
              let m = re.firstMatch(in: text, options: [.anchored], range: range) else { return template }
        return re.replacementString(for: m, in: text, offset: 0, template: template)
    }

    public static func search(_ query: String, in text: String, index: LineIndex, options: SearchOptions, limit: Int = 10_000) throws -> [SearchHit] {
        guard !query.isEmpty else { return [] }
        let re = try makeRegex(query, options: options)

        let ns = text as NSString
        var hits: [SearchHit] = []
        re.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) { m, _, stop in
            guard let m, m.range.length > 0 else { return }
            let line = index.lineNumber(forUTF16Offset: m.range.location)
            // 인덱스가 텍스트보다 낡았을 때를 대비해 줄 범위를 문자열 길이 안으로 클램프 (범위 밖 substring 은 예외 → 크래시)
            let lr = NSIntersectionRange(index.range(ofLine: line), NSRange(location: 0, length: ns.length))
            var pr = lr
            if pr.length > 160 {
                let start = max(lr.location, m.range.location - 60)
                pr = NSRange(location: start, length: min(160, NSMaxRange(lr) - start))
            }
            let lineText = ns.substring(with: pr)
            let matchStart = max(0, m.range.location - pr.location)
            let matchLen = max(0, min(m.range.length, NSMaxRange(pr) - m.range.location))
            hits.append(SearchHit(id: hits.count, range: m.range, line: line, column: m.range.location - lr.location + 1,
                                  lineText: lineText, matchInLine: NSRange(location: matchStart, length: matchLen)))
            if hits.count >= limit { stop.pointee = true }
        }
        return hits
    }
}
