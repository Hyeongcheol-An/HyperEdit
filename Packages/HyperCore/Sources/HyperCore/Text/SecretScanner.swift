import Foundation

/// 비밀 블록 하나. 펜스 코드 블록의 정보 문자열이 `secret` 로 시작하면(```` ```secret ````, ```` ```secret 은행 ````) 닫는 펜스까지의 **안쪽 줄**이 비밀 줄이다.
/// 펜스 줄 자체는 보인다. 모든 범위는 UTF-16 오프셋.
public struct SecretBlock: Equatable, Hashable, Sendable {
    /// 여는 펜스 줄 (줄 끝 개행 제외)
    public let openRange: NSRange
    /// 안쪽 줄들: 첫 내용 줄 시작 ~ 닫는 펜스 줄 시작 (내용 줄의 개행 포함). 빈 블록이면 길이 0, 닫히지 않은 블록이면 문서 끝까지
    public let contentRange: NSRange
    /// 닫는 펜스 줄 (줄 끝 개행 제외). 닫히지 않았으면 nil
    public let closeRange: NSRange?
    /// `secret` 뒤의 라벨 (공백·`:`·`-` 를 떼고 다듬은 것, 없으면 "")
    public let label: String

    public init(openRange: NSRange, contentRange: NSRange, closeRange: NSRange?, label: String) {
        self.openRange = openRange; self.contentRange = contentRange; self.closeRange = closeRange; self.label = label
    }
    public var isClosed: Bool { closeRange != nil }
    /// 오프셋(보통 문단 시작)이 비밀 내용 줄 안인가. 문서 끝까지 닿는 블록은 끝 오프셋(= 문서 길이)도 안으로 본다
    public func containsContent(offset: Int, textLength: Int) -> Bool {
        offset >= contentRange.location && (offset < NSMaxRange(contentRange) || (offset == NSMaxRange(contentRange) && offset == textLength && !isClosed))
    }
}

/// 비밀 블록 스캐너. UTF-16 버퍼를 64K 청크로 한 번 훑는 O(n) 단일 패스 — 1.3 MB·3만 줄 문서에서 수 ms.
///
/// 규칙 (CommonMark 펜스 코드 블록에 맞춤)
/// - 펜스 줄: 앞 공백 3칸 이하 + 같은 문자(` 또는 ~) 3개 이상. 정보 문자열은 펜스 뒤의 나머지.
/// - 정보 문자열의 첫 단어가 `secret`(대소문자 무시, 뒤에 글자·숫자가 이어지지 않음)이면 비밀 블록이다. 라벨은 그 뒤.
/// - 닫는 펜스: 같은 문자, 길이는 여는 펜스 이상, 뒤에 공백뿐. 다른 정보 문자열이 있는 펜스 줄(```` ```python ````)은 블록을 닫지 않는다 → 중첩된 코드 블록은 비밀로 남는다.
/// - 비밀이 아닌 펜스 블록(```` ```python ````) 안의 ```` ```secret ```` 줄은 내용일 뿐 블록을 열지 않는다.
/// - 닫는 펜스가 없으면 문서 끝까지 비밀이다. CRLF 는 줄 끝 `\r` 을 무시해 같은 규칙.
public struct SecretScanner {
    public static let defaultMask = "••••••••"

    /// 비밀 블록을 문서 순서로
    public static func blocks(in text: String) -> [SecretBlock] { blocks(in: text as NSString) }

    public static func blocks(in ns: NSString) -> [SecretBlock] {
        let length = ns.length
        var out: [SecretBlock] = []
        // 열린 펜스 상태
        var openChar: unichar = 0
        var openRun = 0
        var openIsSecret = false
        var openLineRange = NSRange(location: 0, length: 0)
        var openLabel = ""
        var contentStart = 0
        // 줄 상태
        var lineStart = 0
        var indent = 0                 // 앞 공백 수 (탭은 펜스를 깨뜨린다)
        var inLeading = true
        var fenceChar: unichar = 0
        var fenceRun = 0
        var fenceBroken = false
        var info: [unichar] = []       // 펜스 뒤 정보 문자열 (최대 256자)
        var sawCR = false              // 줄 끝 \r (CRLF)

        func finishLine(end: Int, nextStart: Int) {
            // end: 개행 위치(또는 문서 끝), nextStart: 다음 줄 시작
            var textEnd = end
            if sawCR, textEnd > lineStart { textEnd -= 1 }
            let isFence = !fenceBroken && fenceRun >= 3 && indent <= 3
            if openChar != 0 {
                // 닫는 펜스: 같은 문자, 길이 이상, 정보 문자열은 공백뿐
                if isFence, fenceChar == openChar, fenceRun >= openRun, info.allSatisfy({ $0 == 32 || $0 == 9 }) {
                    if openIsSecret {
                        out.append(SecretBlock(openRange: openLineRange,
                                               contentRange: NSRange(location: contentStart, length: max(0, lineStart - contentStart)),
                                               closeRange: NSRange(location: lineStart, length: textEnd - lineStart),
                                               label: openLabel))
                    }
                    openChar = 0; openRun = 0; openIsSecret = false
                }
            } else if isFence {
                let trimmed = trim(info)
                openChar = fenceChar; openRun = fenceRun
                openLineRange = NSRange(location: lineStart, length: textEnd - lineStart)
                contentStart = nextStart
                if let label = secretLabel(trimmed) { openIsSecret = true; openLabel = label } else { openIsSecret = false; openLabel = "" }
            }
            lineStart = nextStart
            indent = 0; inLeading = true; fenceChar = 0; fenceRun = 0; fenceBroken = false; info.removeAll(keepingCapacity: true); sawCR = false
        }

        let chunk = 65_536
        var buf = [unichar](repeating: 0, count: min(chunk, max(1, length)))
        var pos = 0
        while pos < length {
            let len = min(chunk, length - pos)
            buf.withUnsafeMutableBufferPointer { p in ns.getCharacters(p.baseAddress!, range: NSRange(location: pos, length: len)) }
            buf.withUnsafeBufferPointer { p in
                var i = 0
                while i < len {
                    let c = p[i]
                    let off = pos + i
                    i += 1
                    if c == 10 { finishLine(end: off, nextStart: off + 1); continue }
                    if c == 13 { sawCR = true; continue }   // CRLF 의 \r (또는 외딴 \r — 줄 끝으로만 취급하지 않고 무시)
                    sawCR = false
                    if inLeading {
                        if c == 32 { indent += 1; continue }
                        inLeading = false
                        if c == 9 { fenceBroken = true }
                    }
                    if !fenceBroken {
                        if fenceRun == 0 {
                            if c == 0x60 || c == 0x7E { fenceChar = c; fenceRun = 1 } else { fenceBroken = true }   // ` ~
                        } else if c == fenceChar, info.isEmpty { fenceRun += 1 }
                        else if fenceRun >= 3 {
                            // 백틱 펜스의 정보 문자열에 백틱이 있으면 펜스가 아니다 (CommonMark)
                            if c == 0x60, fenceChar == 0x60 { fenceBroken = true } else if info.count < 256 { info.append(c) }
                        } else { fenceBroken = true }
                    }
                }
            }
            pos += len
        }
        finishLine(end: length, nextStart: length)
        // 닫히지 않은 비밀 블록은 문서 끝까지
        if openChar != 0, openIsSecret {
            out.append(SecretBlock(openRange: openLineRange,
                                   contentRange: NSRange(location: min(contentStart, length), length: max(0, length - min(contentStart, length))),
                                   closeRange: nil, label: openLabel))
        }
        return out
    }

    /// 비밀 줄을 마스크로 바꾼 텍스트 (미리보기·내보내기·찾기 결과용). 줄 수와 줄바꿈 종류는 그대로라 줄 번호가 맞는다.
    public static func redacted(_ text: String, mask: String = defaultMask) -> String {
        let ns = text as NSString
        let found = blocks(in: ns)
        guard !found.isEmpty else { return text }
        let out = NSMutableString(capacity: ns.length)
        var cursor = 0
        for b in found {
            let r = b.contentRange
            guard r.length > 0, r.location >= cursor else { continue }
            out.append(ns.substring(with: NSRange(location: cursor, length: r.location - cursor)))
            out.append(maskedLines(ns, range: r, mask: mask))
            cursor = NSMaxRange(r)
        }
        if cursor < ns.length { out.append(ns.substring(from: cursor)) }
        return out as String
    }

    /// `range`(내용 줄들, 개행 포함)의 각 줄을 마스크 + 원래 줄 끝으로
    static func maskedLines(_ ns: NSString, range: NSRange, mask: String) -> String {
        var out = ""
        var pos = range.location
        let end = NSMaxRange(range)
        while pos < end {
            let lr = ns.lineRange(for: NSRange(location: pos, length: 0))
            let lineEnd = min(NSMaxRange(lr), end)
            var contentEnd = lineEnd
            if contentEnd > pos, ns.character(at: contentEnd - 1) == 10 { contentEnd -= 1 }
            if contentEnd > pos, ns.character(at: contentEnd - 1) == 13 { contentEnd -= 1 }
            out += mask
            if contentEnd < lineEnd { out += ns.substring(with: NSRange(location: contentEnd, length: lineEnd - contentEnd)) }
            pos = max(lineEnd, pos + 1)
        }
        return out
    }

    /// 검색 결과의 미리보기 줄을 가린다: 매치 위치·줄 번호는 그대로, 비밀 줄의 `lineText` 는 마스크 (매치 범위는 마스크 전체)
    public static func redacting(hits: [SearchHit], in text: String, mask: String = defaultMask) -> [SearchHit] {
        let found = blocks(in: text)
        guard !found.isEmpty else { return hits }
        let length = (text as NSString).length
        return hits.map { h in
            guard found.contains(where: { $0.containsContent(offset: h.range.location, textLength: length) }) else { return h }
            return SearchHit(id: h.id, range: h.range, line: h.line, column: h.column, lineText: mask, matchInLine: NSRange(location: 0, length: (mask as NSString).length))
        }
    }

    /// 범위가 비밀 내용 줄과 겹치는가 (클립보드 소거 판단용)
    public static func intersectsContent(_ range: NSRange, blocks: [SecretBlock], textLength: Int) -> Bool {
        for b in blocks {
            let c = b.contentRange
            if range.length == 0 {
                if b.containsContent(offset: range.location, textLength: textLength) { return true }
            } else if c.length > 0, range.location < NSMaxRange(c), NSMaxRange(range) > c.location { return true }
        }
        return false
    }

    // MARK: - 내부

    private static func trim(_ chars: [unichar]) -> [unichar] {
        var lo = 0, hi = chars.count
        while lo < hi, chars[lo] == 32 || chars[lo] == 9 { lo += 1 }
        while hi > lo, chars[hi - 1] == 32 || chars[hi - 1] == 9 { hi -= 1 }
        return Array(chars[lo..<hi])
    }

    /// 정보 문자열이 `secret` 로 시작하면 라벨을, 아니면 nil
    private static func secretLabel(_ info: [unichar]) -> String? {
        let word: [unichar] = [0x73, 0x65, 0x63, 0x72, 0x65, 0x74]   // "secret"
        guard info.count >= word.count else { return nil }
        for (i, w) in word.enumerated() {
            let c = info[i]
            let lower = (c >= 0x41 && c <= 0x5A) ? c + 32 : c
            if lower != w { return nil }
        }
        if info.count > word.count {
            let next = info[word.count]
            let isAlnum = (next >= 0x30 && next <= 0x39) || (next >= 0x41 && next <= 0x5A) || (next >= 0x61 && next <= 0x7A)
            if isAlnum { return nil }   // "secrets", "secretive" 는 비밀 블록이 아니다
        }
        var rest = Array(info[word.count...])
        var lo = 0
        while lo < rest.count, rest[lo] == 32 || rest[lo] == 9 || rest[lo] == 0x3A || rest[lo] == 0x2D { lo += 1 }   // 공백 : -
        rest = Array(rest[lo...])
        return String(utf16CodeUnits: rest, count: rest.count)
    }
}
