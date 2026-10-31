import XCTest
@testable import HyperCore

final class CommentToggleTests: XCTestCase {
    private let slash = CommentSyntax(line: "//")
    private let sharp = CommentSyntax(line: "#")
    private let html = CommentSyntax(block: ("<!--", "-->"))

    func testCommentMixedIndentAlignsAtCommonIndent() {
        let lines = ["    a", "  b", "      c"]
        let out = TextTools.toggleLineComment(lines: lines, syntax: slash)
        XCTAssertEqual(out, ["  //   a", "  // b", "  //     c"])
        XCTAssertEqual(TextTools.toggleLineComment(lines: out, syntax: slash), lines, "두 번 토글하면 원문")
    }

    func testAllCommentedUncomments() {
        let out = TextTools.toggleLineComment(lines: ["// a", "//b", "  // c"], syntax: slash)
        XCTAssertEqual(out, ["a", "b", "  c"], "기호 뒤 공백은 하나만 제거, 없으면 그대로")
    }

    func testPartiallyCommentedCommentsAll() {
        let out = TextTools.toggleLineComment(lines: ["// a", "b"], syntax: slash)
        XCTAssertEqual(out, ["// // a", "// b"])
    }

    func testBlankLinesUntouched() {
        let lines = ["a", "", "   ", "b"]
        let out = TextTools.toggleLineComment(lines: lines, syntax: sharp)
        XCTAssertEqual(out, ["# a", "", "   ", "# b"])
        XCTAssertEqual(TextTools.toggleLineComment(lines: out, syntax: sharp), lines, "빈 줄은 '주석됨' 판정에서 빠지므로 전부 해제된다")
    }

    func testOnlyBlankLinesGetMarker() {
        XCTAssertEqual(TextTools.toggleLineComment(lines: [""], syntax: slash), ["// "])
        XCTAssertEqual(TextTools.toggleLineComment(lines: ["// "], syntax: slash), [""])
    }

    func testTabsPreserved() {
        let lines = ["\t\tfoo", "\tbar"]
        let out = TextTools.toggleLineComment(lines: lines, syntax: slash)
        XCTAssertEqual(out, ["\t// \tfoo", "\t// bar"])
        XCTAssertEqual(TextTools.toggleLineComment(lines: out, syntax: slash), lines)
        // 탭과 공백이 섞이면 공통 접두가 없어 0열에
        XCTAssertEqual(TextTools.toggleLineComment(lines: ["\ta", "    b"], syntax: slash), ["// \ta", "//     b"])
    }

    func testBlockStylePerLine() {
        let lines = ["  <p>hi</p>", "", "  <b>x</b>  "]
        let out = TextTools.toggleLineComment(lines: lines, syntax: html)
        XCTAssertEqual(out, ["  <!-- <p>hi</p> -->", "", "  <!-- <b>x</b>   -->"])
        XCTAssertEqual(TextTools.toggleLineComment(lines: out, syntax: html), lines, "닫는 기호와 뒤 공백도 원래대로")
        XCTAssertEqual(TextTools.toggleLineComment(lines: ["<!--x-->"], syntax: html), ["x"], "공백 없는 블록도 해제")
    }

    func testIdempotenceOnRealisticSnippet() {
        let lines = ["func f() {", "    let x = 1", "", "    return x", "}"]
        let once = TextTools.toggleLineComment(lines: lines, syntax: slash)
        XCTAssertEqual(once, ["// func f() {", "//     let x = 1", "", "//     return x", "// }"])
        XCTAssertEqual(TextTools.toggleLineComment(lines: once, syntax: slash), lines)
    }

    func testUnusableSyntaxIsNoop() {
        XCTAssertEqual(TextTools.toggleLineComment(lines: ["a"], syntax: CommentSyntax()), ["a"])
    }

    func testRegistryMapping() {
        func line(_ name: String) -> String? { CommentRegistry.syntax(for: URL(fileURLWithPath: "/tmp/" + name)).line }
        func block(_ name: String) -> String? { CommentRegistry.syntax(for: URL(fileURLWithPath: "/tmp/" + name)).block?.open }
        XCTAssertEqual(line("a.swift"), "//")
        XCTAssertEqual(line("a.py"), "#")
        XCTAssertEqual(line("a.sh"), "#")
        XCTAssertEqual(line("a.yml"), "#")
        XCTAssertEqual(line("a.toml"), "#")
        XCTAssertEqual(line("a.ini"), "#")
        XCTAssertEqual(line("a.sql"), "--")
        XCTAssertEqual(line("notes"), "//", "확장자 없는 메모는 //")
        XCTAssertEqual(line("a.txt"), "//")
        XCTAssertNil(line("a.md")); XCTAssertEqual(block("a.md"), "<!--")
        XCTAssertNil(line("a.html")); XCTAssertEqual(block("a.html"), "<!--")
        XCTAssertNil(line("a.xml")); XCTAssertEqual(block("a.xml"), "<!--")
        XCTAssertNil(line("a.css")); XCTAssertEqual(block("a.css"), "/*")
        XCTAssertEqual(CommentRegistry.syntax(for: URL(fileURLWithPath: "/tmp/a.c")).block?.close, "*/")
    }
}
