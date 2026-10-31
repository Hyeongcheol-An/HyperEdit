import Foundation

/// 열(블록) 선택. 문자 열 기준(UTF-16 오프셋), 줄이 짧으면 가상 공백으로 간주해 삽입 시 공백으로 채운다 (UltraEdit 열 모드 계승).
/// 블록 안에서만 편집이 일어나므로 topLineStart(최상단 줄 시작 오프셋)는 편집 중 변하지 않는다.
public struct ColumnBlock: Equatable, Sendable {
    public var topLineStart: Int
    public var lineCount: Int
    public var anchorCol: Int
    public var headCol: Int
    /// 세로 확장의 머리(head)가 아래쪽 줄인가 (앵커가 위)
    public var headIsBottom: Bool

    public init(topLineStart: Int, lineCount: Int, anchorCol: Int, headCol: Int, headIsBottom: Bool = true) {
        self.topLineStart = topLineStart
        self.lineCount = max(1, lineCount)
        self.anchorCol = max(0, anchorCol)
        self.headCol = max(0, headCol)
        self.headIsBottom = headIsBottom
    }

    public var colLo: Int { min(anchorCol, headCol) }
    public var colHi: Int { max(anchorCol, headCol) }
    public var width: Int { colHi - colLo }

    /// 블록의 각 줄 정보
    public struct Line: Equatable, Sendable {
        public let lineStart: Int
        public let contentLength: Int      // 개행 제외
        public let range: NSRange          // 문서 기준, 줄 길이에 맞춰 잘라낸 선택 범위
        public let padding: Int            // colLo 까지 모자란 칸 수 (가상 공백)
        public var caretOffset: Int { range.location }
    }

    /// 텍스트를 따라 줄 범위를 계산. 문서 끝을 넘는 줄은 제외.
    public func lines(in text: NSString) -> [Line] {
        var out: [Line] = []
        var cursor = topLineStart
        let lo = colLo, hi = colHi
        for _ in 0..<lineCount {
            guard cursor <= text.length else { break }
            let lr = text.lineRange(for: NSRange(location: cursor, length: 0))
            var content = lr.length
            if content > 0, text.character(at: NSMaxRange(lr) - 1) == 10 { content -= 1 }
            if content > 0, text.character(at: lr.location + content - 1) == 13 { content -= 1 }
            let a = min(lo, content), b = min(hi, content)
            out.append(Line(lineStart: lr.location, contentLength: content,
                            range: NSRange(location: lr.location + a, length: b - a), padding: max(0, lo - content)))
            if NSMaxRange(lr) >= text.length || lr.length == 0 { break }
            cursor = NSMaxRange(lr)
        }
        return out
    }

    /// 머리(head)를 dx 칸, dy 줄 이동. 세로 이동은 문서 범위 안에서만.
    public func extended(dx: Int, dy: Int, in text: NSString) -> ColumnBlock {
        var b = self
        if dx != 0 { b.headCol = max(0, b.headCol + dx) }
        if dy > 0 {
            if b.headIsBottom || b.lineCount == 1 {
                // 아래로 늘림: 마지막 줄 다음 줄이 있어야 함
                if b.lineCount == 1 { b.headIsBottom = true }
                let ls = b.lines(in: text)
                if let last = ls.last {
                    let lr = text.lineRange(for: NSRange(location: last.lineStart, length: 0))
                    if NSMaxRange(lr) < text.length || (NSMaxRange(lr) == text.length && last.contentLength < lr.length) {
                        if NSMaxRange(lr) < text.length { b.lineCount += 1 }
                    }
                }
            } else {
                // 머리가 위: 아래로 줄이면 줄 수 감소, 위쪽 줄 시작 갱신
                let ls = b.lines(in: text)
                if ls.count >= 2 { b.topLineStart = ls[1].lineStart; b.lineCount -= 1 }
                if b.lineCount == 1 { b.headIsBottom = true }
            }
        } else if dy < 0 {
            if !b.headIsBottom || b.lineCount == 1 {
                if b.lineCount == 1 { b.headIsBottom = false }
                if b.topLineStart > 0 {
                    let prev = text.lineRange(for: NSRange(location: b.topLineStart - 1, length: 0))
                    b.topLineStart = prev.location
                    b.lineCount += 1
                }
            } else {
                b.lineCount -= 1
                if b.lineCount == 1 { b.headIsBottom = true }
            }
        }
        return b
    }

    /// 삽입 후: 열 폭 0, 열 위치 = colLo + width
    public func afterInsert(width w: Int) -> ColumnBlock {
        var b = self; let c = colLo + w; b.anchorCol = c; b.headCol = c; return b
    }

    /// 블록 내용 삭제 후 (또는 폭 0 에서 Backspace 후)
    public func afterDelete(backward: Bool) -> ColumnBlock {
        var b = self
        if width > 0 { b.anchorCol = colLo; b.headCol = colLo }
        else if backward { let c = max(0, colLo - 1); b.anchorCol = c; b.headCol = c }
        return b
    }

    /// 머리 위치(캐럿)의 문서 오프셋 (줄이 짧으면 줄 끝)
    public func headOffset(in text: NSString) -> Int {
        let ls = lines(in: text)
        guard let l = (headIsBottom ? ls.last : ls.first) else { return topLineStart }
        return l.lineStart + min(headCol, l.contentLength)
    }

    /// 각 줄에 대한 교체 문자열: 짧은 줄은 공백 패딩 + 텍스트
    public func replacements(in text: NSString, with strings: [String]) -> [(range: NSRange, string: String)] {
        let ls = lines(in: text)
        return ls.enumerated().map { i, l in
            let s = strings.count == ls.count ? strings[i] : (strings.first ?? "")
            return (l.range, String(repeating: " ", count: l.padding) + s)
        }
    }

    /// Insert Number: start 부터 step 씩, 같은 폭으로 0 패딩
    public static func numberStrings(count: Int, start: Int, step: Int, zeroPad: Bool) -> [String] {
        let values = (0..<count).map { start + $0 * step }
        let width = values.map { String($0).count }.max() ?? 1
        return values.map { v in
            let s = String(v)
            return zeroPad && v >= 0 ? String(repeating: "0", count: width - s.count) + s : s
        }
    }
}
