import XCTest
@testable import HyperCore

// 비밀 블록(```secret 펜스) 탐지·마스킹 규칙

final class SecretScannerTests: XCTestCase {
    private func blocks(_ t: String) -> [SecretBlock] { SecretScanner.blocks(in: t) }
    private func content(_ t: String, _ b: SecretBlock) -> String { (t as NSString).substring(with: b.contentRange) }

    func testNoBlocks() {
        XCTAssertEqual(blocks(""), [])
        XCTAssertEqual(blocks("plain\ntext\n"), [])
        XCTAssertEqual(blocks("```python\nsecret = 1\n```\n"), [])            // 다른 언어의 펜스
        XCTAssertEqual(blocks("```secrets\nnot a block\n```\n"), [])          // secret 뒤에 글자가 이어지면 아니다
        XCTAssertEqual(blocks("text with ```secret inline\n"), [])             // 줄 머리가 아니다
        XCTAssertEqual(blocks("    ```secret\nindented 4\n```\n"), [])         // 4칸 들여쓰기는 코드 줄
    }

    func testBasicBlockRangesAndLabel() {
        let t = "intro\n```secret bank\nPIN 1234\nACCOUNT 9876\n```\nafter\n"
        let b = blocks(t)
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(b[0].label, "bank")
        XCTAssertEqual((t as NSString).substring(with: b[0].openRange), "```secret bank")
        XCTAssertEqual(content(t, b[0]), "PIN 1234\nACCOUNT 9876\n")
        XCTAssertEqual(b[0].closeRange.map { (t as NSString).substring(with: $0) }, "```")
        XCTAssertTrue(b[0].isClosed)
        // 라벨 구분자 · 대소문자 · 틸드 펜스
        XCTAssertEqual(blocks("```Secret: AWS keys\nx\n```")[0].label, "AWS keys")
        XCTAssertEqual(blocks("~~~secret-aws\nx\n~~~")[0].label, "aws")
        XCTAssertEqual(blocks("```secret\nx\n```")[0].label, "")
        XCTAssertEqual(blocks("  ```secret\nx\n  ```")[0].label, "")             // 3칸 이하 들여쓰기는 펜스
    }

    func testEmptyAndUnclosedBlocks() {
        let empty = "```secret\n```\nafter"
        let eb = blocks(empty)
        XCTAssertEqual(eb.count, 1)
        XCTAssertEqual(eb[0].contentRange, NSRange(location: 10, length: 0))
        XCTAssertTrue(eb[0].isClosed)

        let open = "a\n```secret\nline 1\nline 2"
        let ob = blocks(open)
        XCTAssertEqual(ob.count, 1)
        XCTAssertFalse(ob[0].isClosed)
        XCTAssertEqual(content(open, ob[0]), "line 1\nline 2")
        XCTAssertTrue(ob[0].containsContent(offset: (open as NSString).length, textLength: (open as NSString).length))   // 문서 끝 캐럿도 안

        // 펜스가 마지막 줄: 내용 없음, 닫히지 않음
        let tail = "a\n```secret"
        XCTAssertEqual(blocks(tail).map { $0.contentRange.length }, [0])
        XCTAssertEqual(SecretScanner.redacted(tail), tail)
    }

    func testNestedFencesStayInside() {
        // 안쪽의 ```python 은 정보 문자열이 있어 블록을 닫지 않고, 더 긴 ```` 로만 닫힌다
        let t = "````secret\n```python\nkey = 'x'\n```\nmore\n````\nvisible"
        let b = blocks(t)
        XCTAssertEqual(b.count, 1)
        XCTAssertEqual(content(t, b[0]), "```python\nkey = 'x'\n```\nmore\n")
        // 비밀이 아닌 블록 안의 ```secret 은 열지 않는다
        XCTAssertEqual(blocks("```python\n```secret\nnot secret\n```\n"), [])
        // 짧은 펜스는 긴 펜스를 닫지 못한다
        XCTAssertFalse(blocks("````secret\nx\n```\ny")[0].isClosed)
        // 다른 문자(~~~)는 닫지 못한다
        XCTAssertFalse(blocks("```secret\nx\n~~~\ny")[0].isClosed)
        // 닫는 펜스 뒤 공백은 허용
        XCTAssertTrue(blocks("```secret\nx\n```   \ny")[0].isClosed)
    }

    func testMultipleBlocksAndOrder() {
        let t = "```secret a\n1\n```\nmid\n```secret b\n2\n3\n```\n"
        let b = blocks(t)
        XCTAssertEqual(b.map(\.label), ["a", "b"])
        XCTAssertEqual(b.map { content(t, $0) }, ["1\n", "2\n3\n"])
        XCTAssertLessThan(b[0].contentRange.location, b[1].contentRange.location)
    }

    func testCRLF() {
        let t = "head\r\n```secret\r\nPIN 1\r\n\r\nPIN 2\r\n```\r\ntail\r\n"
        let b = blocks(t)
        XCTAssertEqual(b.count, 1)
        XCTAssertTrue(b[0].isClosed)
        XCTAssertEqual(content(t, b[0]), "PIN 1\r\n\r\nPIN 2\r\n")
        let r = SecretScanner.redacted(t, mask: "***")
        XCTAssertEqual(r, "head\r\n```secret\r\n***\r\n***\r\n***\r\n```\r\ntail\r\n")
        XCTAssertEqual(r.components(separatedBy: "\n").count, t.components(separatedBy: "\n").count)
    }

    func testRedactedKeepsLineStructure() {
        let t = "# Title\n```secret bank\nPIN 1234\n\nlast line without newline"
        let r = SecretScanner.redacted(t)
        XCTAssertEqual(r, "# Title\n```secret bank\n••••••••\n••••••••\n••••••••")
        XCTAssertFalse(r.contains("PIN"))
        XCTAssertEqual(LineIndex(text: r).lineCount, LineIndex(text: t).lineCount)
        // 블록이 없으면 그대로 (같은 인스턴스 수준으로 비용 없음)
        XCTAssertEqual(SecretScanner.redacted("no secrets\n"), "no secrets\n")
        // 빈 블록은 아무것도 바꾸지 않는다
        XCTAssertEqual(SecretScanner.redacted("```secret\n```\n"), "```secret\n```\n")
    }

    func testRedactingSearchHits() throws {
        let t = "NEEDLE outside\n```secret\nNEEDLE inside\n```\n"
        let hits = try SearchEngine.search("NEEDLE", in: t, index: LineIndex(text: t), options: SearchOptions())
        XCTAssertEqual(hits.count, 2)
        let red = SecretScanner.redacting(hits: hits, in: t)
        XCTAssertEqual(red[0].lineText, hits[0].lineText)            // 바깥 줄은 그대로
        XCTAssertEqual(red[1].lineText, SecretScanner.defaultMask)   // 안쪽 줄은 마스크
        XCTAssertEqual(red[1].range, hits[1].range)                  // 매치·줄 번호는 그대로
        XCTAssertEqual(red[1].line, 3)
        XCTAssertEqual(red[1].matchInLine, NSRange(location: 0, length: 8))
    }

    func testIntersectsContent() {
        let t = "a\n```secret\nPIN 1234\n```\nz"
        let b = blocks(t)
        let len = (t as NSString).length
        let pin = (t as NSString).range(of: "PIN 1234")
        XCTAssertTrue(SecretScanner.intersectsContent(pin, blocks: b, textLength: len))
        XCTAssertTrue(SecretScanner.intersectsContent(NSRange(location: 0, length: len), blocks: b, textLength: len))   // 전체 선택
        XCTAssertTrue(SecretScanner.intersectsContent(NSRange(location: pin.location + 2, length: 0), blocks: b, textLength: len))   // 캐럿만
        XCTAssertFalse(SecretScanner.intersectsContent(NSRange(location: 0, length: 1), blocks: b, textLength: len))
        XCTAssertFalse(SecretScanner.intersectsContent((t as NSString).range(of: "```secret"), blocks: b, textLength: len))   // 펜스 줄은 비밀이 아니다
        XCTAssertFalse(SecretScanner.intersectsContent(NSRange(location: len - 1, length: 1), blocks: b, textLength: len))
    }

    func testLargeDocumentIsLinear() {
        var s = ""
        for i in 0..<20_000 { s += i % 500 == 0 ? "```secret\n" : (i % 500 == 3 ? "```\n" : "line \(i) some text here\n") }
        let t0 = CFAbsoluteTimeGetCurrent()
        let b = blocks(s)
        let r = SecretScanner.redacted(s)
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        XCTAssertEqual(b.count, 40)
        XCTAssertEqual(LineIndex(text: r).lineCount, LineIndex(text: s).lineCount)
        XCTAssertLessThan(ms, 500, "scan + redact of 20k lines took \(ms) ms")
    }
}
