import XCTest
@testable import HyperCore

// Quick Append 창이 문서 끝에 덧붙이는 문자열 조립 규칙

final class QuickAppendTests: XCTestCase {
    private let heading = "## 2026-10-31 (토) 09:00"

    func testTrailingNewlineCount() {
        XCTAssertEqual(QuickAppendComposer.trailingNewlineCount(of: "abc"), 0)
        XCTAssertEqual(QuickAppendComposer.trailingNewlineCount(of: "abc\n"), 1)
        XCTAssertEqual(QuickAppendComposer.trailingNewlineCount(of: "abc\n\n\n"), 3)
        XCTAssertEqual(QuickAppendComposer.trailingNewlineCount(of: "abc\r\n\r\n"), 2)     // DOS 줄바꿈은 한 개로
        XCTAssertEqual(QuickAppendComposer.trailingNewlineCount(of: ""), 0)
        XCTAssertEqual(QuickAppendComposer.trailingNewlineCount(of: "\n"), 1)
    }

    func testHeadingGetsExactlyOneBlankLineBefore() {
        // 문서가 "tail" 로 끝남 → 개행 둘 (줄 끝 + 빈 줄)
        XCTAssertEqual(QuickAppendComposer.insertion(trailingNewlines: 0, isEmptyDocument: false, note: "quick note", heading: heading),
                       "\n\n\(heading)\nquick note\n")
        // 문서가 "tail\n" 로 끝남 → 빈 줄 하나만
        XCTAssertEqual(QuickAppendComposer.insertion(trailingNewlines: 1, isEmptyDocument: false, note: "quick note", heading: heading),
                       "\n\(heading)\nquick note\n")
        // 이미 빈 줄로 끝남 → 구분 개행 없음
        XCTAssertEqual(QuickAppendComposer.insertion(trailingNewlines: 2, isEmptyDocument: false, note: "quick note", heading: heading),
                       "\(heading)\nquick note\n")
        XCTAssertEqual(QuickAppendComposer.insertion(trailingNewlines: 5, isEmptyDocument: false, note: "quick note", heading: heading),
                       "\(heading)\nquick note\n")
    }

    func testWithoutHeadingStartsOnNewLineOnly() {
        XCTAssertEqual(QuickAppendComposer.insertion(trailingNewlines: 0, isEmptyDocument: false, note: "note", heading: nil), "\nnote\n")
        XCTAssertEqual(QuickAppendComposer.insertion(trailingNewlines: 1, isEmptyDocument: false, note: "note", heading: nil), "note\n")
        XCTAssertEqual(QuickAppendComposer.insertion(trailingNewlines: 3, isEmptyDocument: false, note: "note", heading: nil), "note\n")
    }

    func testEmptyDocumentHasNoSeparator() {
        XCTAssertEqual(QuickAppendComposer.insertion(trailingNewlines: 0, isEmptyDocument: true, note: "first", heading: heading), "\(heading)\nfirst\n")
        XCTAssertEqual(QuickAppendComposer.insertion(trailingNewlines: 0, isEmptyDocument: true, note: "first", heading: nil), "first\n")
    }

    func testNoteIsTrimmedAndMultilinePreserved() {
        XCTAssertEqual(QuickAppendComposer.insertion(trailingNewlines: 1, isEmptyDocument: false, note: "\n\n  indented\nsecond  \n\n", heading: nil),
                       "  indented\nsecond\n")
        XCTAssertEqual(QuickAppendComposer.insertion(trailingNewlines: 1, isEmptyDocument: false, note: "a\r\nb\r\n", heading: nil), "a\nb\n")
        XCTAssertEqual(QuickAppendComposer.insertion(trailingNewlines: 0, isEmptyDocument: false, note: "   \n\n", heading: heading), "")
        XCTAssertEqual(QuickAppendComposer.insertion(trailingNewlines: 0, isEmptyDocument: false, note: "", heading: nil), "")
    }
}
