import Foundation

/// 줄 시작 오프셋(UTF-16) 테이블. 줄 번호 ↔ 오프셋 변환을 O(log n) 으로.
public struct LineIndex: Sendable, Equatable {
    public private(set) var lineStarts: [Int]
    public let utf16Count: Int

    public init() { lineStarts = [0]; utf16Count = 0 }

    public init(text: String) { self.init(nsString: text as NSString) }

    /// 64K 청크 버퍼로 스캔 — 브리지된 문자열의 utf16 반복보다 수십 배 빠르다(Debug 포함)
    public init(nsString ns: NSString) {
        let n = ns.length
        var starts = [0]
        starts.reserveCapacity(n / 32 + 1)
        let chunk = 65_536
        var buf = [unichar](repeating: 0, count: min(chunk, max(1, n)))
        var pos = 0
        while pos < n {
            let len = min(chunk, n - pos)
            buf.withUnsafeMutableBufferPointer { p in ns.getCharacters(p.baseAddress!, range: NSRange(location: pos, length: len)) }
            buf.withUnsafeBufferPointer { p in
                var i = 0
                while i < len { if p[i] == 10 { starts.append(pos + i + 1) }; i += 1 }
            }
            pos += len
        }
        lineStarts = starts
        utf16Count = n
    }

    /// 마지막이 개행으로 끝나면 빈 마지막 줄을 하나 더 센다(에디터 관례).
    public var lineCount: Int { lineStarts.count }

    /// 1-based 줄 번호
    public func lineNumber(forUTF16Offset offset: Int) -> Int {
        let o = max(0, min(offset, utf16Count))
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= o { lo = mid } else { hi = mid - 1 }
        }
        return lo + 1
    }

    /// 1-based 줄의 내용 범위(개행 제외)
    public func range(ofLine n: Int) -> NSRange {
        let idx = max(0, min(n - 1, lineStarts.count - 1))
        let start = lineStarts[idx]
        let end = idx + 1 < lineStarts.count ? lineStarts[idx + 1] - 1 : utf16Count
        return NSRange(location: start, length: max(0, end - start))
    }

    /// 1-based 열
    public func column(forUTF16Offset offset: Int) -> Int {
        let o = max(0, min(offset, utf16Count))
        return o - lineStarts[lineNumber(forUTF16Offset: o) - 1] + 1
    }

    /// 범위 안의 개행(\n) 수. 인덱스 없이 문자열을 직접 세므로 편집 직후(인덱스가 250 ms 뒤에 갱신되기 전)에도 정확하다.
    public static func countNewlines(in ns: NSString, range: NSRange) -> Int {
        let r = NSIntersectionRange(range, NSRange(location: 0, length: ns.length))
        guard r.length > 0 else { return 0 }
        let chunk = 65_536
        var buf = [unichar](repeating: 0, count: min(chunk, r.length))
        var count = 0, pos = r.location
        let end = NSMaxRange(r)
        while pos < end {
            let len = min(chunk, end - pos)
            buf.withUnsafeMutableBufferPointer { p in ns.getCharacters(p.baseAddress!, range: NSRange(location: pos, length: len)) }
            buf.withUnsafeBufferPointer { p in
                var i = 0
                while i < len { if p[i] == 10 { count += 1 }; i += 1 }
            }
            pos += len
        }
        return count
    }
}
