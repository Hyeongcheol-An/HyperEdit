import Foundation

/// 접을 수 있는 영역: 머리 줄(계속 보임) + 그 아래 숨겨지는 줄들. 줄 번호는 1-based, `startLine < endLine`.
public struct FoldRegion: Equatable, Hashable, Sendable {
    /// 머리 줄 (접어도 보인다)
    public let startLine: Int
    /// 마지막 숨은 줄
    public let endLine: Int
    public init(startLine: Int, endLine: Int) { self.startLine = startLine; self.endLine = endLine }
    /// 숨겨지는 줄 수
    public var hiddenLineCount: Int { endLine - startLine }
    /// 머리 줄 또는 숨은 줄이면 true
    public func contains(line: Int) -> Bool { line >= startLine && line <= endLine }
}

/// 접기 영역 스캐너. UTF-16 버퍼를 64K 청크로 한 번 훑어 줄마다 (들여쓰기, 빈 줄, 마크다운 헤딩 레벨, 펜스, 괄호) 를 모은 뒤 O(줄 수) 로 영역을 만든다.
/// 1.3 MB·3만 줄 문서에서 Release 수 ms.
///
/// 영역 규칙
/// - 들여쓰기: 어떤 줄 다음에 더 깊이 들여쓴 줄이 오면 그 줄이 머리가 되어, 자기 들여쓰기 이하의 첫 줄 직전까지 소유한다. 빈 줄은 건너뛰고 끝의 빈 줄은 영역에 넣지 않는다 (탭 = 4칸).
/// - 괄호(코드 파일): 머리 줄이 `{` `[` `(` 로 끝나고 영역을 끝내는 줄이 짝 닫는 괄호만으로 된 줄(`}`, `});`, `],` …)이면 그 줄까지 숨긴다.
/// - 마크다운 헤딩(`isMarkdown`): `#` 헤딩은 같거나 높은 레벨의 다음 헤딩 직전까지 소유한다. 펜스(```) 안의 `#` 은 헤딩이 아니다.
/// - 마크다운 펜스: ``` 줄은 닫는 ``` 줄까지(닫는 줄 포함) 소유한다.
/// 숨는 줄이 하나도 없으면 영역이 아니다. 같은 머리 줄의 영역은 더 긴 것 하나만 남긴다.
public enum FoldScanner {
    private struct LineInfo {
        var indent: Int32 = 0      // 앞 공백의 표시 열 수 (탭 = 4)
        var blank = true           // 공백뿐인 줄
        var heading: UInt8 = 0     // 마크다운 헤딩 레벨 1~6 (0: 아님)
        var fence = false          // ``` / ~~~ 로 시작
        var opener: UInt16 = 0     // 마지막 비공백 문자가 { [ ( 이면 그 문자
        var closerOnly: UInt16 = 0 // 비공백 문자가 } ] ) ; , 뿐이면 첫 문자
    }

    /// `range` 는 1-based 줄 번호의 반개구간(예: `10..<40`). 주면 그 줄들만 하나의 문서처럼 훑는다 (바깥 줄은 보지 않는다).
    public static func regions(in text: NSString, index: LineIndex, isMarkdown: Bool, range: Range<Int>? = nil) -> [FoldRegion] {
        let lineCount = index.lineCount
        var firstLine = 1
        var startOffset = 0
        var endOffset = text.length
        if let r = range {
            let lo = max(1, min(r.lowerBound, lineCount))
            let hi = max(lo, min(r.upperBound, lineCount + 1))
            firstLine = lo
            startOffset = index.lineStarts[lo - 1]
            endOffset = hi <= lineCount ? index.lineStarts[hi - 1] : text.length
        }
        let info = scanLines(text, from: startOffset, to: endOffset, expectedLines: lineCount)
        var ends: [Int: Int] = [:]   // 머리 줄(0-based) → 마지막 숨은 줄(0-based), 같은 머리면 더 긴 쪽
        func add(_ start: Int, _ end: Int) {
            guard end > start else { return }
            if let e = ends[start], e >= end { return }
            ends[start] = end
        }
        indentationRegions(info, bracketClosers: !isMarkdown, add: add)
        if isMarkdown { markdownRegions(info, add: add) }
        return ends.map { FoldRegion(startLine: $0.key + firstLine, endLine: $0.value + firstLine) }
            .sorted { $0.startLine < $1.startLine }
    }

    /// `line` 을 머리로 하는 영역 (regions 는 `regions(in:…)` 가 돌려준 정렬 순서)
    public static func region(containingHeaderLine line: Int, in regions: [FoldRegion]) -> FoldRegion? {
        var lo = 0, hi = regions.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if regions[mid].startLine == line { return regions[mid] }
            if regions[mid].startLine < line { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }

    /// `line`(머리 또는 숨은 줄)을 포함하는 가장 안쪽 영역
    public static func innermostRegion(containingLine line: Int, in regions: [FoldRegion]) -> FoldRegion? {
        var best: FoldRegion?
        for r in regions {
            if r.startLine > line { break }
            if r.endLine >= line, best == nil || r.startLine >= best!.startLine { best = r }
        }
        return best
    }

    /// `line` 을 포함하는 영역을 바깥에서 안쪽 순으로
    public static func enclosingRegions(ofLine line: Int, in regions: [FoldRegion]) -> [FoldRegion] {
        var out: [FoldRegion] = []
        for r in regions {
            if r.startLine > line { break }
            if r.endLine >= line { out.append(r) }
        }
        return out
    }

    // MARK: - 줄 정보 수집 (UTF-16 청크 스캔)

    private static func scanLines(_ ns: NSString, from start: Int, to end: Int, expectedLines: Int) -> [LineInfo] {
        var lines: [LineInfo] = []
        lines.reserveCapacity(min(expectedLines, max(1, (end - start) / 24 + 1)))
        var cur = LineInfo()
        var inLeading = true
        var col = 0                 // 앞 공백 뒤 몇 번째 문자인지
        var hashRun = 0             // 줄 앞 '#' 연속 수 (헤딩 후보)
        var hashState = 0           // 0: '#' 세는 중, 1: 공백 봄(비공백 기다림), 2: 확정/탈락
        var fenceChar: unichar = 0
        var fenceRun = 0
        var fenceBroken = false
        var closerOnly = true
        var firstChar: unichar = 0
        var lastNonSpace: unichar = 0

        func finishLine() {
            if !cur.blank {
                if hashState == 2, hashRun >= 1, hashRun <= 6, cur.indent == 0, lastNonSpace != 0 { cur.heading = UInt8(hashRun) }
                if fenceRun >= 3, cur.indent <= 3 { cur.fence = true }
                if lastNonSpace == 0x7B || lastNonSpace == 0x5B || lastNonSpace == 0x28 { cur.opener = UInt16(lastNonSpace) }   // { [ (
                if closerOnly, firstChar == 0x7D || firstChar == 0x5D || firstChar == 0x29 { cur.closerOnly = UInt16(firstChar) }  // } ] )
            }
            lines.append(cur)
            cur = LineInfo(); inLeading = true; col = 0; hashRun = 0; hashState = 0
            fenceChar = 0; fenceRun = 0; fenceBroken = false; closerOnly = true; firstChar = 0; lastNonSpace = 0
        }

        let chunk = 65_536
        var buf = [unichar](repeating: 0, count: min(chunk, max(1, end - start)))
        var pos = start
        while pos < end {
            let len = min(chunk, end - pos)
            buf.withUnsafeMutableBufferPointer { p in ns.getCharacters(p.baseAddress!, range: NSRange(location: pos, length: len)) }
            buf.withUnsafeBufferPointer { p in
                var i = 0
                while i < len {
                    let c = p[i]
                    i += 1
                    if c == 10 { finishLine(); continue }
                    if inLeading {
                        if c == 32 { cur.indent += 1; continue }
                        if c == 9 { cur.indent += 4 - cur.indent % 4; continue }
                        if c == 13 { continue }
                        inLeading = false
                        cur.blank = false
                        firstChar = c
                    }
                    if c == 32 || c == 9 || c == 13 {
                        if hashState == 0 && hashRun > 0 { hashState = 1 }
                    } else {
                        lastNonSpace = c
                        if hashState == 0 { if c == 0x23 { hashRun += 1 } else { hashState = 2; hashRun = 0 } }   // '#'
                        else if hashState == 1 { hashState = 2 }
                        if closerOnly && !(c == 0x7D || c == 0x5D || c == 0x29 || c == 0x3B || c == 0x2C) { closerOnly = false }   // } ] ) ; ,
                    }
                    if !fenceBroken {
                        if col == 0 {
                            if c == 0x60 || c == 0x7E { fenceChar = c; fenceRun = 1 } else { fenceBroken = true }   // ` ~
                        } else if c == fenceChar && fenceRun == col { fenceRun += 1 }
                        else if fenceRun < 3 { fenceBroken = true }
                    }
                    col += 1
                }
            }
            pos += len
        }
        finishLine()
        return lines
    }

    // MARK: - 영역 만들기

    private static func indentationRegions(_ info: [LineInfo], bracketClosers: Bool, add: (Int, Int) -> Void) {
        var stack: [(line: Int, indent: Int32)] = []
        var lastNonBlank = -1
        for i in 0..<info.count where !info[i].blank {
            let d = info[i].indent
            while let top = stack.last, top.indent >= d {
                stack.removeLast()
                var end = lastNonBlank
                if bracketClosers, end > top.line, let closer = matchingCloser(info[top.line].opener), info[i].closerOnly == closer { end = i }
                add(top.line, end)
            }
            stack.append((i, d))
            lastNonBlank = i
        }
        for top in stack { add(top.line, lastNonBlank) }
    }

    private static func matchingCloser(_ opener: UInt16) -> UInt16? {
        switch opener { case 0x7B: 0x7D; case 0x5B: 0x5D; case 0x28: 0x29; default: nil }
    }

    private static func markdownRegions(_ info: [LineInfo], add: (Int, Int) -> Void) {
        var stack: [(line: Int, level: UInt8)] = []
        var lastNonBlank = -1
        var fenceOpen: Int? = nil
        for i in 0..<info.count {
            if info[i].fence {
                if let open = fenceOpen { add(open, i); fenceOpen = nil } else { fenceOpen = i }
                lastNonBlank = i
                continue
            }
            if info[i].blank { continue }
            if fenceOpen == nil, info[i].heading > 0 {
                while let top = stack.last, top.level >= info[i].heading {
                    stack.removeLast()
                    add(top.line, lastNonBlank)
                }
                stack.append((i, info[i].heading))
            }
            lastNonBlank = i
        }
        if let open = fenceOpen { add(open, lastNonBlank) }
        for top in stack { add(top.line, lastNonBlank) }
    }
}
