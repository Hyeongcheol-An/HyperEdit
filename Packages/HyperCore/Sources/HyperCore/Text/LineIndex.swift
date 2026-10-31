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

    init(lineStarts: [Int], utf16Count: Int) {
        self.lineStarts = lineStarts
        self.utf16Count = utf16Count
    }

    /// 이 인덱스가 설명하는 텍스트의 `range` 를 `text` 로 바꾼 뒤의 인덱스 (증분 갱신).
    /// 전체 재스캔(8 MB ≈ 5 ms + 스냅샷 복사) 대신 편집 범위 안의 개행만 다시 세고 뒤쪽 줄 시작은 길이 변화만큼 옮긴다 — 줄 수에 비례하는
    /// 배열 복사뿐이라 18만 줄에서도 0.1 ms 수준. `NSTextStorageDelegate.didProcessEditing` 의 (editedRange, changeInLength) 로 호출할 수 있다:
    /// `old = NSRange(location: edited.location, length: edited.length - delta)`, `new = string.substring(with: edited)`.
    /// 범위가 텍스트 밖이면 잘라 낸다(낡은 인덱스에 대한 방어) — 그 경우 결과는 근사치이며 다음 전체 재빌드가 바로잡는다.
    public func updated(replacing range: NSRange, with text: NSString) -> LineIndex {
        // NSIntersectionRange 는 빈 교집합(끝 위치 삽입 등)을 {0,0} 으로 돌려주므로 직접 자른다
        let loc = min(max(0, range.location), utf16Count)
        let len = min(max(0, range.length), utf16Count - loc)
        let end = loc + len
        let delta = text.length - len
        // 삭제되는 개행의 줄 시작 s 는 loc < s <= end 에 있다 (개행 p 는 줄 시작 p+1 을 만든다). lo = 첫 s > loc, hi = 첫 s > end.
        let lo = firstIndex(greaterThan: loc)
        let hi = firstIndex(greaterThan: end)
        var inserted: [Int] = []
        Self.forEachNewline(in: text) { k in inserted.append(loc + k + 1) }
        let tail = lineStarts.count - hi
        let total = lo + inserted.count + tail
        let starts = [Int](unsafeUninitializedCapacity: total) { buf, count in
            lineStarts.withUnsafeBufferPointer { src in
                buf.baseAddress!.initialize(from: src.baseAddress!, count: lo)          // 앞부분 그대로 (memcpy)
                var k = lo
                for v in inserted { buf[k] = v; k += 1 }
                let tailSrc = src.baseAddress! + hi
                for i in 0..<tail { buf[k + i] = tailSrc[i] + delta }               // 뒷부분은 길이 변화만큼 이동
            }
            count = total
        }
        return LineIndex(lineStarts: starts, utf16Count: utf16Count + delta)
    }

    /// lineStarts 에서 `value` 보다 큰 첫 원소의 인덱스 (없으면 count). lineStarts[0] == 0 이므로 value >= 0 이면 항상 >= 1.
    private func firstIndex(greaterThan value: Int) -> Int {
        var lo = 0, hi = lineStarts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if lineStarts[mid] <= value { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// `ns` 의 개행(\n) 오프셋을 차례로 넘긴다. 짧은 문자열(입력 한 글자)은 스택 버퍼로, 긴 붙여넣기는 64K 청크로.
    static func forEachNewline(in ns: NSString, _ body: (Int) -> Void) {
        let n = ns.length
        guard n > 0 else { return }
        let chunk = min(n, 65_536)
        withUnsafeTemporaryAllocation(of: unichar.self, capacity: chunk) { buf in
            var pos = 0
            while pos < n {
                let len = min(chunk, n - pos)
                ns.getCharacters(buf.baseAddress!, range: NSRange(location: pos, length: len))
                var i = 0
                while i < len { if buf[i] == 10 { body(pos + i) }; i += 1 }
                pos += len
            }
        }
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
