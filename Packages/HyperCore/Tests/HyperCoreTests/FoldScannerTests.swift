import XCTest
@testable import HyperCore

final class FoldScannerTests: XCTestCase {
    private func regions(_ text: String, markdown: Bool = false, range: Range<Int>? = nil) -> [FoldRegion] {
        FoldScanner.regions(in: text as NSString, index: LineIndex(text: text), isMarkdown: markdown, range: range)
    }
    private func pairs(_ r: [FoldRegion]) -> [[Int]] { r.map { [$0.startLine, $0.endLine] } }

    func testFlatTextHasNoRegions() {
        XCTAssertEqual(regions("a\nb\nc\n"), [])
        XCTAssertEqual(regions(""), [])
        XCTAssertEqual(regions("only one line"), [])
    }

    func testIndentationNesting() {
        let t = """
        root
            child 1
                grand 1
                grand 2
            child 2
        next root
        """
        // root(1) 은 2~5, child 1(2) 은 3~4; child 2 와 next root 는 숨길 줄이 없다
        XCTAssertEqual(pairs(regions(t)), [[1, 5], [2, 4]])
    }

    func testBlankLinesInsideAndAfterRegion() {
        let t = """
        def f():
            a = 1

            b = 2


        print(1)
        """
        // 빈 줄은 영역 안에 포함되지만(3) 영역 끝의 빈 줄(5, 6)은 제외된다
        XCTAssertEqual(pairs(regions(t)), [[1, 4]])
    }

    func testTabsAndSpaces() {
        let tabs = "root\n\tchild\n\t\tgrand\nend"
        XCTAssertEqual(pairs(regions(tabs)), [[1, 3], [2, 3]])
        // 탭 하나(4칸)와 공백 4개는 같은 깊이
        let mixed = "root\n\tchild a\n    child b\nend"
        XCTAssertEqual(pairs(regions(mixed)), [[1, 3]])
    }

    func testRegionAtEndOfFile() {
        XCTAssertEqual(pairs(regions("head\n    a\n    b")), [[1, 3]])
        XCTAssertEqual(pairs(regions("head\n    a\n    b\n")), [[1, 3]])      // 끝 개행 뒤의 빈 줄은 숨기지 않는다
        XCTAssertEqual(pairs(regions("head\n    a\n    b\n\n\n")), [[1, 3]])
    }

    func testBracketCloserLineIsIncludedInCode() {
        let t = """
        func f() {
            x()
        }
        let a = [
            1,
        ]
        if x {
            y
        } else {
            z
        }
        """
        // `}` 만 있는 줄은 머리와 함께 숨긴다 — `} else {` 처럼 내용이 있는 줄은 보이게 두고, 그 줄이 다시 머리가 된다
        XCTAssertEqual(pairs(regions(t)), [[1, 3], [4, 6], [7, 8], [9, 11]])
        // 마크다운에서는 괄호 규칙을 쓰지 않는다
        XCTAssertEqual(pairs(regions("f {\n    x\n}", markdown: true)), [[1, 2]])
    }

    func testMarkdownHeadingLevels() {
        let t = """
        # Title
        intro

        ## A
        a1
        ### A.1
        a11
        ## B
        b1

        # Second
        s1
        """
        let r = regions(t, markdown: true)
        // Title(1) 은 다음 # 직전까지(9, 끝 빈 줄 제외), A(4) 는 B 직전(7), A.1(6) 은 7, B(8) 은 9, Second(11) 은 12
        XCTAssertEqual(pairs(r), [[1, 9], [4, 7], [6, 7], [8, 9], [11, 12]])
        // 비마크다운 파일에서는 # 줄이 헤딩이 아니다 (코드 주석)
        XCTAssertEqual(regions(t, markdown: false), [])
    }

    func testMarkdownHeadingWithoutTextAndIndentedHashAreNotHeadings() {
        XCTAssertEqual(regions("#\nx\n# \ny\n#tag line\nz", markdown: true), [])
        // 들여쓴 `#` 은 헤딩이 아니다 — 들여쓰기 영역([1,3])만 생긴다
        XCTAssertEqual(pairs(regions("y\n    # indented\n    more\nz", markdown: true)), [[1, 3]])
    }

    func testMarkdownFenceAndHashInsideFence() {
        let t = """
        ## Code
        ```python
        # not a heading
        x = 1
        ```
        after
        """
        // 헤딩(1)은 끝까지, 펜스(2)는 닫는 ``` 줄(5)까지. 펜스 안 # 은 헤딩이 아니다
        XCTAssertEqual(pairs(regions(t, markdown: true)), [[1, 6], [2, 5]])
    }

    func testSameHeaderKeepsLongerRegion() {
        // 헤딩이면서 들여쓴 줄도 거느리는 줄: 헤딩 영역(더 긴 쪽) 하나만
        let t = "## H\n    code\nplain\n## Next\nx"
        XCTAssertEqual(pairs(regions(t, markdown: true)), [[1, 3], [4, 5]])
    }

    func testHelpers() {
        let t = "root\n    child\n        grand\n    child2\nnext\n    c\n"
        let r = regions(t)
        XCTAssertEqual(pairs(r), [[1, 4], [2, 3], [5, 6]])
        XCTAssertEqual(FoldScanner.region(containingHeaderLine: 2, in: r), FoldRegion(startLine: 2, endLine: 3))
        XCTAssertNil(FoldScanner.region(containingHeaderLine: 3, in: r))
        XCTAssertEqual(FoldScanner.innermostRegion(containingLine: 3, in: r), FoldRegion(startLine: 2, endLine: 3))
        XCTAssertEqual(FoldScanner.innermostRegion(containingLine: 4, in: r), FoldRegion(startLine: 1, endLine: 4))
        XCTAssertEqual(FoldScanner.innermostRegion(containingLine: 1, in: r), FoldRegion(startLine: 1, endLine: 4))
        XCTAssertNil(FoldScanner.innermostRegion(containingLine: 7, in: r))
        XCTAssertEqual(pairs(FoldScanner.enclosingRegions(ofLine: 3, in: r)), [[1, 4], [2, 3]])
        XCTAssertEqual(FoldRegion(startLine: 1, endLine: 4).hiddenLineCount, 3)
    }

    func testLineRangeScansOnlyThoseLines() {
        let t = "root\n    a\n    b\nsecond\n    c\n    d\nthird\n    e"
        XCTAssertEqual(pairs(regions(t)), [[1, 3], [4, 6], [7, 8]])
        XCTAssertEqual(pairs(regions(t, range: 4..<7)), [[4, 6]])
        XCTAssertEqual(pairs(regions(t, range: 4..<6)), [[4, 5]])     // 범위 끝에서 잘린다
        XCTAssertEqual(pairs(regions(t, range: 7..<99)), [[7, 8]])
    }

    func testPerformanceOnLargeDocument() {
        // 3만 줄 (들여쓰기 블록 + 마크다운 헤딩 혼합). Release 기준 < 20 ms 가 목표이고 Debug 테스트 빌드에서도 수백 ms 를 넘지 않아야 한다.
        var lines: [String] = []
        lines.reserveCapacity(30_000)
        for i in 0..<30_000 {
            switch i % 10 {
            case 0: lines.append("## Section \(i / 10)")
            case 1: lines.append("def f\(i)():")
            case 2, 3, 4: lines.append("    x = \(i)  # 한글 주석 포함")
            case 5: lines.append("        if x: y")
            case 6: lines.append("")
            default: lines.append("plain line \(i) with some words to make it longer")
            }
        }
        let text = lines.joined(separator: "\n")
        let ns = text as NSString
        let idx = LineIndex(nsString: ns)
        let t = CFAbsoluteTimeGetCurrent()
        let r = FoldScanner.regions(in: ns, index: idx, isMarkdown: true)
        let ms = (CFAbsoluteTimeGetCurrent() - t) * 1000
        XCTAssertEqual(idx.lineCount, 30_000)
        XCTAssertGreaterThan(r.count, 5_000)
        XCTAssertLessThan(ms, 400, "FoldScanner took \(ms) ms for 30k lines")
    }
}
