import Foundation

/// 문서의 줄별 진입 상태(`LineState`) 표. 뷰포트 레이아웃이 임의의 줄에서 시작하므로 그 줄이 블록 주석·여러 줄 문자열·펜스 안인지를
/// 여기서 O(1) 로 찾는다. 상태는 종류가 적어 표(`table`)에 한 번만 두고 줄마다 UInt16 id 만 저장한다 (34k 줄 ≈ 68 KB).
///
/// - `init(text:lineIndex:grammar:)` 전체 계산 O(n): 문법의 `exitState` 만 쓰므로 토큰 배열을 만들지 않는다 (1.3 MB 코드 파일 수 ms)
/// - `update(...)` 증분: 편집된 첫 줄부터 다시 스캔해 다음 줄의 진입 상태가 이전과 같아지는 줄에서 멈춘다 (키 입력당 보통 1~2줄).
///   `/*` 를 열거나 닫으면 아래 줄 전부의 상태가 바뀌므로 그때만 끝까지 간다. 돌려주는 범위를 편집기가 다시 칠한다.
/// - 상태가 없는 문법(`tracksLineState == false`)이면 비어 있고 모든 줄이 `.normal` — 메모 파일은 키 입력마다 비용 0
public struct LineStateIndex: Sendable {
    private var ids: [UInt16] = []
    private var table: [LineState] = [.normal]
    private var lookup: [LineState: UInt16] = [.normal: 0]
    /// 문법이 상태를 추적해 이 표가 유효한가 (false 면 `state(ofLine:)` 는 항상 `.normal`)
    public private(set) var isTracking = false

    public init() {}

    /// 전체 계산. `lineIndex` 는 `text` 와 일치해야 한다.
    public init(text: NSString, lineIndex: LineIndex, grammar: any LanguageGrammar) {
        guard grammar.tracksLineState else { return }
        isTracking = true
        let n = lineIndex.lineCount
        ids = [UInt16](repeating: 0, count: n)
        var state = LineState.normal
        Self.forEachLine(text, lineIndex, from: 0) { line, buf in
            if line > 0 { ids[line] = intern(state) }
            state = grammar.exitState(line: buf, entering: state)
            return true
        }
    }

    /// 줄 수 (추적하지 않으면 0)
    public var lineCount: Int { ids.count }
    public var isEmpty: Bool { ids.isEmpty }

    /// 1-based 줄의 진입 상태. 범위 밖·추적 안 함 → `.normal`
    public func state(ofLine n: Int) -> LineState {
        guard n >= 1, n <= ids.count else { return .normal }
        return table[Int(ids[n - 1])]
    }

    /// 테스트·도구용: 모든 줄의 진입 상태
    public var states: [LineState] { ids.map { table[Int($0)] } }

    /// 증분 갱신. `text`/`lineIndex` 는 편집 뒤의 것, `editedLines` 는 편집 뒤 텍스트 기준 1-based 편집된 줄 범위(반열림, 최소 1줄),
    /// `lineDelta` 는 줄 수 변화(편집 뒤 − 편집 전). 반환: 편집 줄 밖에서 진입 상태가 바뀐 줄 범위(1-based 반열림; 비어 있으면 없음) —
    /// 편집된 줄 자체는 TextKit 이 다시 배치하므로 포함하지 않는다. 인자가 현재 표와 맞지 않으면(낡은 표) 전체를 다시 계산하고 모든 줄을 돌려준다.
    @discardableResult
    public mutating func update(text: NSString, lineIndex new: LineIndex, editedLines: Range<Int>, lineDelta: Int, grammar: any LanguageGrammar) -> Range<Int> {
        guard isTracking else { return 0..<0 }
        let total = new.lineCount
        let first = editedLines.lowerBound - 1              // 0-based
        let newCount = editedLines.count
        let oldCount = newCount - lineDelta
        let consistent = first >= 0 && newCount >= 1 && oldCount >= 1
            && first + oldCount <= ids.count && first + newCount <= total
            && ids.count - (first + oldCount) == total - (first + newCount)
        guard consistent else {
            self = LineStateIndex(text: text, lineIndex: new, grammar: grammar)
            return 1..<(total + 1)
        }
        if newCount != oldCount {
            // 편집 영역의 줄 수가 바뀜: 그 구간만 바꿔 끼운다 (뒤쪽은 그대로 — 진입 상태는 줄 내용이 아니라 위 줄들의 결과이므로 값은 유효하다)
            ids.replaceSubrange(first..<(first + oldCount), with: repeatElement(ids[first], count: newCount))
        }
        var state = table[Int(ids[first])]                // 첫 편집 줄의 진입 상태 — 위 줄들이 그대로이므로 불변
        let editedEnd = first + newCount
        var lastChanged = -1
        Self.forEachLine(text, new, from: first) { line, buf in
            let exiting = grammar.exitState(line: buf, entering: state)
            let next = line + 1
            guard next < total else { return false }
            let id = intern(exiting)
            if next >= editedEnd {
                if ids[next] == id { return false }       // 수렴: 다음 줄부터는 이전과 같다
                lastChanged = next
            }
            ids[next] = id
            state = exiting
            return true
        }
        guard lastChanged >= 0 else { return 0..<0 }
        return (editedEnd + 1)..<(lastChanged + 2)         // 0-based editedEnd...lastChanged → 1-based
    }

    private mutating func intern(_ s: LineState) -> UInt16 {
        if let id = lookup[s] { return id }
        guard table.count < Int(UInt16.max) else { return 0 }   // 상태 종류가 65k 를 넘는 일은 없다 — 넘으면 .normal 로 둔다
        let id = UInt16(table.count)
        table.append(s)
        lookup[s] = id
        return id
    }

    /// `from`(0-based) 줄부터 차례로 줄 내용(개행·끝의 \r 제외)을 버퍼로 넘긴다. 64K 창 단위로 복사하고 창보다 긴 줄은 그 줄만큼 키운다.
    /// body 가 false 를 돌려주면 멈춘다.
    private static func forEachLine(_ ns: NSString, _ idx: LineIndex, from: Int, _ body: (Int, UnsafeBufferPointer<unichar>) -> Bool) {
        let total = idx.lineCount
        let length = ns.length
        guard from < total else { return }
        var window: [unichar] = []
        var winStart = 0, winEnd = 0
        var line = from
        while line < total {
            var r = idx.range(ofLine: line + 1)
            if r.location > length { r = NSRange(location: length, length: 0) }
            if NSMaxRange(r) > length { r.length = length - r.location }
            if r.length > 0, r.location < winStart || NSMaxRange(r) > winEnd {
                let count = min(max(65_536, r.length), length - r.location)
                if window.count < count { window = [unichar](repeating: 0, count: count) }
                window.withUnsafeMutableBufferPointer { ns.getCharacters($0.baseAddress!, range: NSRange(location: r.location, length: count)) }
                winStart = r.location; winEnd = r.location + count
            }
            let cont: Bool
            if r.length == 0 {
                cont = body(line, UnsafeBufferPointer(start: nil, count: 0))
            } else {
                cont = window.withUnsafeBufferPointer { p -> Bool in
                    var lo = r.location - winStart, hi = NSMaxRange(r) - winStart
                    if hi > lo, p[hi - 1] == 0x0D { hi -= 1 }   // CRLF 문서의 \r
                    if hi == lo { lo = 0; hi = 0 }
                    return body(line, UnsafeBufferPointer(rebasing: p[lo..<hi]))
                }
            }
            if !cont { break }
            line += 1
        }
    }
}

extension LineStateIndex: Equatable {
    /// 줄별 상태열이 같은가 (표의 id 배치는 무시)
    public static func == (a: LineStateIndex, b: LineStateIndex) -> Bool {
        guard a.isTracking == b.isTracking, a.ids.count == b.ids.count else { return false }
        for i in 0..<a.ids.count where a.table[Int(a.ids[i])] != b.table[Int(b.ids[i])] { return false }
        return true
    }
}
