import XCTest
@testable import HyperCore

// 북마크 줄 추적 · 즉석 계산 · 열 맞춤

@MainActor
final class BookmarkStoreTests: XCTestCase {
    private func makeStore(lines: [Int]) -> (BookmarkStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("he-bm-\(UUID().uuidString)", isDirectory: true)
        let file = dir.appendingPathComponent("doc.md")
        let store = BookmarkStore(fileURL: file, storeDirectory: dir)
        for l in lines { store.toggle(line: l, preview: "L\(l)") }
        return (store, dir)
    }
    func testShiftInsertMovesLaterLinesOnly() {
        let (s, _) = makeStore(lines: [2, 5, 9])
        s.shift(fromLine: 3, delta: 2)
        XCTAssertEqual(s.bookmarks.map(\.line), [2, 7, 11])
        s.shift(fromLine: 0, delta: 1)                         // 문서 맨 앞(줄 머리) 삽입은 pivot 0 → 전부 이동
        XCTAssertEqual(s.bookmarks.map(\.line), [3, 8, 12])
        s.shift(fromLine: 12, delta: 3)                        // 마지막 북마크 줄 안의 Enter 는 그 줄을 움직이지 않음
        XCTAssertEqual(s.bookmarks.map(\.line), [3, 8, 12])
    }
    func testShiftDeleteRemovesInsideAndShiftsAfter() {
        let (s, _) = makeStore(lines: [2, 5, 9])
        s.shift(fromLine: 4, delta: -3)                        // 5~7줄 삭제
        XCTAssertEqual(s.bookmarks.map(\.line), [2, 6])
        s.shift(fromLine: 1, delta: -1)                        // 2줄 삭제 (줄 머리에서 시작 → pivot 1)
        XCTAssertEqual(s.bookmarks.map(\.line), [5])
        s.shift(fromLine: 5, delta: -2)                        // 5줄 중간부터 7줄까지 지워도 5줄 북마크는 남는다
        XCTAssertEqual(s.bookmarks.map(\.line), [5])
    }
    func testShiftPersistsAndZeroDeltaIsNoop() {
        let (s, dir) = makeStore(lines: [4])
        let before = try? Data(contentsOf: s.storeURL)
        s.shift(fromLine: 10, delta: 0)
        s.shift(fromLine: 10, delta: 5)                        // 뒤쪽 편집은 영향 없음 → 저장도 안 함
        XCTAssertEqual(try? Data(contentsOf: s.storeURL), before)
        s.shift(fromLine: 1, delta: 2)
        let again = BookmarkStore(fileURL: dir.appendingPathComponent("doc.md"), storeDirectory: dir)
        XCTAssertEqual(again.bookmarks.map(\.line), [6], "이동 결과가 JSON 에 저장됨")
    }
    func testClampToLineCount() {
        let (s, _) = makeStore(lines: [2, 5, 9])
        s.clamp(toLineCount: 6)
        XCTAssertEqual(s.bookmarks.map(\.line), [2, 5, 6])
        s.clamp(toLineCount: 4)
        XCTAssertEqual(s.bookmarks.map(\.line), [2, 4], "같은 줄로 몰린 북마크는 하나만")
        s.clamp(toLineCount: 0)
        XCTAssertEqual(s.bookmarks.map(\.line), [1])
    }
}

final class CalculatorTests: XCTestCase {
    func testArithmetic() {
        XCTAssertEqual(TextTools.evaluate("3+0.5+0.25"), 3.75)
        XCTAssertEqual(TextTools.evaluate("2*(3+4)"), 14)
        XCTAssertEqual(TextTools.evaluate("10 - 2 - 3"), 5, "좌결합")
        XCTAssertEqual(TextTools.evaluate("7 / 2"), 3.5)
        XCTAssertEqual(TextTools.evaluate("10 % 3"), 1)
        XCTAssertEqual(TextTools.evaluate("-2^2"), -4, "단항 음수는 거듭제곱보다 약하게")
        XCTAssertEqual(TextTools.evaluate("2^3^2"), 512, "거듭제곱은 우결합")
        XCTAssertEqual(TextTools.evaluate("3 × 4 ÷ 2"), 6)
        XCTAssertEqual(TextTools.evaluate("+5 - -3"), 8)
    }
    func testNumbers() {
        XCTAssertEqual(TextTools.evaluate("1,234 + 1_000"), 2234)
        XCTAssertEqual(TextTools.evaluate("1,234,567.5"), 1234567.5)
        XCTAssertEqual(TextTools.evaluate(".5 + 1."), 1.5)
        XCTAssertEqual(TextTools.evaluate("1e3 + 2E-1"), 1000.2)
        XCTAssertNil(TextTools.evaluate("1,23 + 1"), "세 자리가 아니면 천 단위 구분이 아니다")
    }
    func testFunctionsAndConstants() throws {
        XCTAssertEqual(TextTools.evaluate("sqrt(16) + abs(-2) + round(2.5) + floor(2.7) + ceil(2.1)"), 14)
        XCTAssertEqual(TextTools.evaluate("min(3, 1, 2) + max(1,2)"), 3)
        XCTAssertEqual(TextTools.evaluate("max(1,234)"), 1234, "쉼표+세 자리는 천 단위로 읽힌다 (인자 구분은 공백을 두거나 자릿수를 달리할 것)")
        XCTAssertEqual(TextTools.evaluate("round(10/3, 2)"), 3.33)
        XCTAssertEqual(try XCTUnwrap(TextTools.evaluate("pi")), Double.pi, accuracy: 1e-12)
        XCTAssertEqual(try XCTUnwrap(TextTools.evaluate("2*E")), 2 * M_E, accuracy: 1e-12)
        XCTAssertNil(TextTools.evaluate("sqrt(-1)"))
        XCTAssertNil(TextTools.evaluate("foo(1)"))
        XCTAssertNil(TextTools.evaluate("x + 1"))
    }
    func testErrors() {
        XCTAssertNil(TextTools.evaluate(""))
        XCTAssertNil(TextTools.evaluate("1/0"))
        XCTAssertNil(TextTools.evaluate("5 % 0"))
        XCTAssertNil(TextTools.evaluate("3+"))
        XCTAssertNil(TextTools.evaluate("(1+2"))
        XCTAssertNil(TextTools.evaluate("hello world"))
        XCTAssertNil(TextTools.evaluate("2e"))
        XCTAssertNil(TextTools.evaluate("10^400"), "비유한 결과")
    }
    func testFormat() {
        XCTAssertEqual(TextTools.formatNumber(3.75), "3.75")
        XCTAssertEqual(TextTools.formatNumber(1.0 / 3), "0.333333")
        XCTAssertEqual(TextTools.formatNumber(14), "14")
        XCTAssertEqual(TextTools.formatNumber(-0.0), "0")
        XCTAssertEqual(TextTools.formatNumber(1234567.891), "1234567.891")
        XCTAssertEqual(TextTools.formatNumber(-2.5), "-2.5")
        XCTAssertNotEqual(TextTools.formatNumber(2.5e-7), "0")
    }
    func testCalculateLine() throws {
        XCTAssertEqual(try XCTUnwrap(TextTools.calculateLine("3+0.5+0.25")).line, "3+0.5+0.25 ⇒ 3.75")
        XCTAssertEqual(try XCTUnwrap(TextTools.calculateLine("3+0.5+0.5 ⇒ 3.75")).line, "3+0.5+0.5 ⇒ 4", "옛 결과 교체")
        XCTAssertEqual(try XCTUnwrap(TextTools.calculateLine("3+0.5+0.25 ⇒ 3.75")).line, "3+0.5+0.25 ⇒ 3.75", "다시 실행해도 같다")
        XCTAssertEqual(try XCTUnwrap(TextTools.calculateLine("total = 2*(3+4)")).line, "total = 2*(3+4) ⇒ 14")
        XCTAssertEqual(try XCTUnwrap(TextTools.calculateLine("total = 2*(3+4) => 10")).line, "total = 2*(3+4) ⇒ 14")
        XCTAssertEqual(try XCTUnwrap(TextTools.calculateLine("- 3+0.5")).line, "- 3+0.5 ⇒ 3.5", "목록 글머리는 수식에서 뺀다")
        XCTAssertEqual(try XCTUnwrap(TextTools.calculateLine("-3+0.5")).line, "-3+0.5 ⇒ -2.5")
        XCTAssertNil(TextTools.calculateLine("hello"))
        XCTAssertNil(TextTools.calculateLine("⇒ 5"))
        let sel = try XCTUnwrap(TextTools.calculateLine("a ⇒ 1   2+3", selectedExpression: "2+3", selectionEnd: 11))
        XCTAssertEqual(sel.line, "a ⇒ 1   2+3 ⇒ 5", "선택 앞의 ⇒ 는 건드리지 않는다")
        XCTAssertEqual(try XCTUnwrap(TextTools.calculateLine("x 2+3 ⇒ 9", selectedExpression: "2+3", selectionEnd: 5)).line, "x 2+3 ⇒ 5")
        XCTAssertEqual(sel.expression, "2+3"); XCTAssertEqual(sel.result, "5")
    }
}

final class AlignColumnsTests: XCTestCase {
    func testDisplayWidth() {
        XCTAssertEqual(TextTools.displayWidth("abc"), 3)
        XCTAssertEqual(TextTools.displayWidth("한글"), 4)
        XCTAssertEqual(TextTools.displayWidth("e\u{301}"), 1, "결합 문자는 0")
        XCTAssertEqual(TextTools.displayWidth("\u{1100}\u{1161}"), 2, "조합형 자모는 한 글자로 2칸")
        XCTAssertEqual(TextTools.displayWidth("日本語"), 6)
        XCTAssertEqual(TextTools.displayWidth("Ａ"), 2, "전각")
        XCTAssertEqual(TextTools.displayWidth(""), 0)
    }
    func testTabTableLatin() {
        XCTAssertEqual(TextTools.alignColumns(["a\tb", "plain", "cc\td"]), ["a   b", "plain", "cc  d"])
        XCTAssertEqual(TextTools.alignColumns(["x\t\tz", "aaaa\tb\tc"]), ["x        z", "aaaa  b  c"], "빈 셀은 간격만 차지")
        XCTAssertEqual(TextTools.alignColumns(["  k\tv  ", "key2\tvalue"]), ["  k   v", "key2  value"], "첫 셀 들여쓰기 유지, 끝 공백 제거")
    }
    func testTabTableHangul() {
        let out = TextTools.alignColumns(["name\tqty\tnote", "홍길동\t3\tok", "ab\t12345\tx"])
        XCTAssertEqual(out, ["name    qty    note", "홍길동  3      ok", "ab      12345  x"])
        // 두 번째·세 번째 열이 모든 줄에서 같은 표시 열에서 시작
        func start(_ line: String, _ cell: String) -> Int {
            TextTools.displayWidth(String(line[..<line.range(of: cell)!.lowerBound]))
        }
        XCTAssertEqual(Set([start(out[0], "qty"), start(out[1], "3"), start(out[2], "12345")]), [8])
        XCTAssertEqual(Set([start(out[0], "note"), start(out[1], "ok"), start(out[2], "x")]), [15])
    }
    func testPipeTable() {
        let out = TextTools.alignColumns(["| a | bb |", "|---|---|", "| ccc | d |"], separator: "|")
        XCTAssertEqual(out, ["| a   | bb  |", "| --- | --- |", "| ccc | d   |"])
        let right = TextTools.alignColumns(["| item | 가격 |", "| :-- | --: |", "| 사과 | 1,000 |", "x"], separator: "|")
        XCTAssertEqual(right, ["| item |  가격 |", "| :--- | ----: |", "| 사과 | 1,000 |", "x"], "--: 열은 오른쪽 정렬")
        XCTAssertEqual(TextTools.alignColumns(["a | bb", "ccc | d"], separator: "|"), ["a   | bb", "ccc | d"], "바깥 | 없는 표")
    }
    func testSeparatorDetection() {
        XCTAssertEqual(TextTools.columnSeparator(for: ["a\tb", "c"]), "\t")
        XCTAssertEqual(TextTools.columnSeparator(for: ["|a|", "|b|"]), "|")
        XCTAssertNil(TextTools.columnSeparator(for: ["a|b", "c"]))
        XCTAssertNil(TextTools.columnSeparator(for: []))
        XCTAssertEqual(TextTools.columnSeparator(for: ["a|b", "c\td"]), "\t", "탭이 하나라도 있으면 탭")
    }
}
