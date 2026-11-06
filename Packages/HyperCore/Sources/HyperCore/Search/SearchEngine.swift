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
        let ns = text as NSString
        var hits: [SearchHit] = []
        /// 매치 하나를 결과로. 반환 false 면 상한에 닿았다
        func append(_ range: NSRange) -> Bool {
            let line = index.lineNumber(forUTF16Offset: range.location)
            // 인덱스가 텍스트보다 낡았을 때를 대비해 줄 범위를 문자열 길이 안으로 클램프 (범위 밖 substring 은 예외 → 크래시)
            let lr = NSIntersectionRange(index.range(ofLine: line), NSRange(location: 0, length: ns.length))
            var pr = lr
            if pr.length > 160 {
                let start = max(lr.location, range.location - 60)
                pr = NSRange(location: start, length: min(160, NSMaxRange(lr) - start))
            }
            if pr.length > 0, ns.character(at: NSMaxRange(pr) - 1) == 13 { pr.length -= 1 }   // CRLF 파일: 줄 인덱스는 \n 만 빼므로 \r 이 미리보기에 남는다
            var lineText = ns.substring(with: pr)
            lineText.makeContiguousUTF8()   // NSString 브리지 문자열끼리의 == 는 느리다 (결과 1만 건 비교에 48 ms) — 네이티브로
            let matchStart = max(0, range.location - pr.location)
            let matchLen = max(0, min(range.length, NSMaxRange(pr) - range.location))
            hits.append(SearchHit(id: hits.count, range: range, line: line, column: range.location - lr.location + 1,
                                  lineText: lineText, matchInLine: NSRange(location: matchStart, length: matchLen)))
            return hits.count < limit
        }
        if let needle = asciiNeedle(query, options: options) {
            scanASCII(ns, needle: needle, caseInsensitive: !options.caseSensitive) { append($0) }
            return hits
        }
        let re = try makeRegex(query, options: options)
        re.enumerateMatches(in: text, options: [], range: NSRange(location: 0, length: ns.length)) { m, _, stop in
            guard let m, m.range.length > 0 else { return }
            if !append(m.range) { stop.pointee = true }
        }
        return hits
    }

    // MARK: - ASCII 일반 검색 빠른 경로

    /// 정규식·단어 단위가 아니고 검색어가 ASCII 뿐이면 빠른 경로의 바늘 (UTF-16 단위), 아니면 nil
    static func asciiNeedle(_ query: String, options: SearchOptions) -> [UInt16]? {
        guard !options.regex, !options.wholeWord else { return nil }
        let units = Array(query.utf16)
        guard !units.isEmpty, units.allSatisfy({ $0 < 128 }) else { return nil }
        return units
    }

    /// ASCII 바늘을 64K 청크로 복사한 UTF-16 버퍼에서 직접 찾는다 — ICU 정규식은 28 MB 에 150~230 ms, 이 경로는 수십 ms (perf).
    /// 규칙은 정규식 경로와 같다: 왼쪽부터 겹치지 않게, `body` 가 false 를 돌려주면 멈춘다. 대소문자 무시는 ASCII 글자(A–Z)만 접으므로
    /// 켈빈 기호 K(U+212A)·긴 s(ſ) 같은 유니코드 접기와 ß↔ss 는 정규식 경로와 달리 매치하지 않는다.
    static func scanASCII(_ ns: NSString, needle: [UInt16], caseInsensitive: Bool, _ body: (NSRange) -> Bool) {
        let n = ns.length, m = needle.count
        guard m > 0, n >= m else { return }
        @inline(__always) func fold(_ u: UInt16) -> UInt16 { (u >= 65 && u <= 90) ? u + 32 : u }   // A–Z → a–z
        let pat = caseInsensitive ? needle.map(fold) : needle
        let first = pat[0]
        let firstAlt = (caseInsensitive && first >= 97 && first <= 122) ? first - 32 : first
        let chunk = 65_536
        var buf = [unichar](repeating: 0, count: chunk + m - 1)
        var pos = 0          // 이 청크의 문서 오프셋
        var minStart = 0     // 이 오프셋 앞에서 시작하는 매치는 직전 매치와 겹친다
        while pos < n {
            let len = min(chunk + m - 1, n - pos)   // 청크 끝을 걸치는 매치를 위해 m-1 만큼 더 읽는다
            guard len >= m else { break }
            buf.withUnsafeMutableBufferPointer { p in ns.getCharacters(p.baseAddress!, range: NSRange(location: pos, length: len)) }
            let stop: Bool = buf.withUnsafeBufferPointer { p in
                var i = max(0, minStart - pos)
                let last = min(len - m, chunk - 1)     // 이 청크가 책임지는 시작 위치 (그 뒤는 다음 청크가 본다)
                while i <= last {
                    let c = p[i]
                    if c == first || c == firstAlt {
                        var k = 1
                        while k < m, (caseInsensitive ? fold(p[i + k]) : p[i + k]) == pat[k] { k += 1 }
                        if k == m {
                            if !body(NSRange(location: pos + i, length: m)) { return true }
                            minStart = pos + i + m
                            i += m
                            continue
                        }
                    }
                    i += 1
                }
                return false
            }
            if stop { return }
            pos += chunk
        }
    }
}
