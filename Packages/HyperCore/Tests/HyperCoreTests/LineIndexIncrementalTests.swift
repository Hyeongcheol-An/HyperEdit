import XCTest
@testable import HyperCore

/// `LineIndex.updated(replacing:with:)` — 증분 갱신이 전체 재스캔과 항상 같은 결과를 내야 한다.
final class LineIndexIncrementalTests: XCTestCase {
    private func check(_ text: String, replacing range: NSRange, with repl: String, file: StaticString = #filePath, line: UInt = #line) {
        let before = LineIndex(text: text)
        let after = before.updated(replacing: range, with: repl as NSString)
        let ns = text as NSString
        let expectedText = ns.replacingCharacters(in: range, with: repl)
        let expected = LineIndex(text: expectedText)
        XCTAssertEqual(after, expected, "replace \(range) with \(repl.debugDescription) in \(text.debugDescription)", file: file, line: line)
        XCTAssertEqual(after.utf16Count, (expectedText as NSString).length, file: file, line: line)
    }

    func testInsertCharacter() {
        check("ab\ncd\nef", replacing: NSRange(location: 4, length: 0), with: "x")
        check("ab\ncd\nef", replacing: NSRange(location: 0, length: 0), with: "x")
        check("ab\ncd\nef", replacing: NSRange(location: 8, length: 0), with: "x")
    }

    func testInsertNewline() {
        check("ab\ncd\nef", replacing: NSRange(location: 4, length: 0), with: "\n")      // 줄 중간 Enter
        check("ab\ncd\nef", replacing: NSRange(location: 3, length: 0), with: "\n")      // 줄 머리 Enter
        check("ab\ncd\nef", replacing: NSRange(location: 8, length: 0), with: "\n")      // 문서 끝 Enter → 빈 마지막 줄
        check("", replacing: NSRange(location: 0, length: 0), with: "\n\n\n")
    }

    func testDeleteNewline() {
        check("ab\ncd\nef", replacing: NSRange(location: 2, length: 1), with: "")       // 줄 합치기
        check("ab\ncd\nef", replacing: NSRange(location: 2, length: 4), with: "")       // 두 개행 삭제
        check("ab\ncd\nef\n", replacing: NSRange(location: 8, length: 1), with: "")     // 마지막 개행 삭제
        check("a\n", replacing: NSRange(location: 0, length: 2), with: "")              // 전부 삭제
    }

    func testReplaceSpanningLines() {
        check("one\ntwo\nthree\nfour", replacing: NSRange(location: 2, length: 7), with: "X\nY\nZ")
        check("one\ntwo\nthree\nfour", replacing: NSRange(location: 0, length: 18), with: "new\ncontent")
        check("one\ntwo", replacing: NSRange(location: 0, length: 7), with: "")
    }

    func testHangulAndSurrogates() {
        check("한글\n둘\n셋", replacing: NSRange(location: 3, length: 0), with: "가\n나")
        check("a😀b\nc", replacing: NSRange(location: 1, length: 2), with: "\n")        // 서로게이트 쌍 교체
    }

    func testOutOfRangeIsClamped() {
        let idx = LineIndex(text: "ab\ncd")
        let r = idx.updated(replacing: NSRange(location: 3, length: 50), with: "x\ny" as NSString)
        XCTAssertEqual(r.lineStarts, [0, 3, 5])
        XCTAssertEqual(r.utf16Count, 6)
        _ = idx.updated(replacing: NSRange(location: 99, length: 1), with: "" as NSString)   // 크래시하지 않음
    }

    /// 결정적 PRNG 로 무작위 편집 500회 — 매번 전체 재스캔과 비교
    func testFuzzAgainstFullRebuild() {
        var s: UInt64 = 0x9E3779B97F4A7C15
        func rnd(_ n: Int) -> Int { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return Int(s % UInt64(max(1, n))) }
        // BMP 문자만 (서로게이트 쌍을 가르면 String 변환이 U+FFFD 로 바꿔 길이가 달라진다 — 쌍 교체는 위 테스트에서 따로 본다)
        let pieces = ["a", "b", "\n", "\n\n", "한", "글\n", " ", "x\ny\nz", ""]
        var text = "start\nline two\n셋째 줄\n\nend"
        var idx = LineIndex(text: text)
        for _ in 0..<500 {
            let ns = text as NSString
            let loc = rnd(ns.length + 1)
            let len = rnd(min(6, ns.length - loc + 1))
            let r = NSRange(location: loc, length: len)
            let repl = (0..<rnd(3)).map { _ in pieces[rnd(pieces.count)] }.joined()
            idx = idx.updated(replacing: r, with: repl as NSString)
            text = ns.replacingCharacters(in: r, with: repl)
            XCTAssertEqual(idx, LineIndex(text: text), "after replacing \(r) with \(repl.debugDescription)")
            if idx != LineIndex(text: text) { return }
        }
        XCTAssertGreaterThan(text.utf16.count, 0)
    }

    func testIncrementalIsFastOnLargeText() {
        var big = ""
        big.reserveCapacity(8_000_000)
        for i in 0..<160_000 { big += "line \(i) 한글 텍스트 with some words\n" }
        let idx = LineIndex(text: big)
        let mid = idx.range(ofLine: 80_000).location
        measure {
            for _ in 0..<20 { _ = idx.updated(replacing: NSRange(location: mid, length: 0), with: "\n" as NSString) }
        }
    }
}
