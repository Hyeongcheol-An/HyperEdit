import XCTest
@testable import HyperCore

// 검색 엔진: ASCII 일반 검색 빠른 경로가 정규식 경로와 같은 매치를 내는지, 청크 경계·겹침·상한·네이티브 문자열
final class SearchEngineTests: XCTestCase {
    private func viaRegex(_ q: String, _ t: String, caseSensitive: Bool) throws -> [NSRange] {
        var o = SearchOptions(); o.regex = true; o.caseSensitive = caseSensitive
        return try SearchEngine.search(NSRegularExpression.escapedPattern(for: q), in: t, index: LineIndex(text: t), options: o, limit: 1_000_000).map(\.range)
    }
    private func viaFast(_ q: String, _ t: String, caseSensitive: Bool) throws -> [NSRange] {
        var o = SearchOptions(); o.caseSensitive = caseSensitive
        XCTAssertNotNil(SearchEngine.asciiNeedle(q, options: o), "fast path expected for \(q)")
        return try SearchEngine.search(q, in: t, index: LineIndex(text: t), options: o, limit: 1_000_000).map(\.range)
    }

    func testFastPathAgreesWithRegex() throws {
        var rng = UInt64(0x9E3779B97F4A7C15)
        func next() -> Int { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return Int(rng % 1000) }
        let words = ["error", "Error", "ERROR", "err", "or", "errorerror", "한글", "오류 error", "e", "E", "\n", "\t", "worker-3]", "id=12", "[", "a.b", "é", "e\u{301}", "ẞ", "ß"]
        var t = ""
        for _ in 0..<4000 { t += words[next() % words.count]; if next() % 5 == 0 { t += " " } }
        for q in ["error", "ERROR", "e", "or", "rr", "\n", "worker-3]", "id=12", "[", "a.b", "errorerror", "ERRORE"] {
            for cs in [true, false] {
                XCTAssertEqual(try viaFast(q, t, caseSensitive: cs), try viaRegex(q, t, caseSensitive: cs), "query \(q) caseSensitive=\(cs)")
            }
        }
    }

    func testFastPathIsSkippedForRegexWholeWordAndNonASCII() {
        var o = SearchOptions()
        XCTAssertNotNil(SearchEngine.asciiNeedle("abc", options: o))
        XCTAssertNil(SearchEngine.asciiNeedle("한글", options: o))
        XCTAssertNil(SearchEngine.asciiNeedle("", options: o))
        o.regex = true; XCTAssertNil(SearchEngine.asciiNeedle("abc", options: o))
        o = SearchOptions(); o.wholeWord = true; XCTAssertNil(SearchEngine.asciiNeedle("abc", options: o))
    }

    func testMatchesAcrossChunkBoundaries() throws {
        // 64K 청크 경계(65,536)를 걸치는 매치와 경계 바로 앞·뒤의 매치가 한 번씩만 잡힌다
        var t = String(repeating: "x", count: 65_530) + "needle" + String(repeating: "y", count: 10) + "NEEDLE" + String(repeating: "z", count: 70_000)
        t += "needle"
        let found = try viaFast("needle", t, caseSensitive: false)
        XCTAssertEqual(found, try viaRegex("needle", t, caseSensitive: false))
        XCTAssertEqual(found.map(\.location), [65_530, 65_546, (t as NSString).length - 6])
        // 경계 직전에서 시작해 경계를 넘는 매치가 다음 청크에서 중복 보고되지 않는다
        let t2 = String(repeating: "a", count: 65_535) + "ab" + String(repeating: "c", count: 100)
        XCTAssertEqual(try viaFast("ab", t2, caseSensitive: true).map(\.location), [65_535])
    }

    func testNonOverlappingAndLimit() throws {
        let t = "aaaaaaa"   // "aa" → 0, 2, 4 (정규식과 같은 겹치지 않는 규칙)
        XCTAssertEqual(try viaFast("aa", t, caseSensitive: true).map(\.location), [0, 2, 4])
        XCTAssertEqual(try viaFast("aa", t, caseSensitive: true), try viaRegex("aa", t, caseSensitive: true))
        let limited = try SearchEngine.search("a", in: t, index: LineIndex(text: t), options: SearchOptions(), limit: 3)
        XCTAssertEqual(limited.count, 3)
    }

    func testCaseFoldingIsASCIIOnly() throws {
        // 정규식 경로는 켈빈 기호 K(U+212A) 를 k 로 접지만 빠른 경로는 ASCII 만 접는다 — 문서화된 차이
        let t = "k \u{212A} K"
        XCTAssertEqual(try viaFast("k", t, caseSensitive: false).map(\.location), [0, 4])
        XCTAssertEqual(try viaFast("k", t, caseSensitive: true).map(\.location), [0])
    }

    func testCRLFPreviewDropsCarriageReturn() throws {
        let t = "first\r\nsecond ERROR line\r\nthird\r\n"
        let hits = try SearchEngine.search("error", in: t, index: LineIndex(text: t), options: SearchOptions())
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].lineText, "second ERROR line")
        XCTAssertEqual((hits[0].lineText as NSString).substring(with: hits[0].matchInLine), "ERROR")
        // 매치가 줄 끝(\r 직전)에 있어도 범위는 그대로
        let tail = try SearchEngine.search("line", in: t, index: LineIndex(text: t), options: SearchOptions())
        XCTAssertEqual(tail.map(\.range), [NSRange(location: 20, length: 4)])
        XCTAssertEqual((tail[0].lineText as NSString).substring(with: tail[0].matchInLine), "line")
    }

    func testHitPreviewIsNativeString() throws {
        let t = "first line\nsecond ERROR line\n"
        let hits = try SearchEngine.search("error", in: t, index: LineIndex(text: t), options: SearchOptions())
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].line, 2)
        XCTAssertEqual(hits[0].lineText, "second ERROR line")
        XCTAssertTrue(hits[0].lineText.isContiguousUTF8)
        XCTAssertEqual((hits[0].lineText as NSString).substring(with: hits[0].matchInLine), "ERROR")
    }
}
