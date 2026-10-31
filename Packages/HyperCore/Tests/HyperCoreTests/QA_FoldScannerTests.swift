import XCTest
import HyperCore

/// FoldScanner 경계 사례 (QA). 줄 끝 CRLF, 탭·공백 혼용, EOF, 펜스 안 헤딩, 비마크다운의 `#`, 빈 `{ }`, 짝 안 맞는 괄호, 1줄·빈 파일,
/// 한글·이모지(서러게이트 쌍) 오프셋, 빈 줄만 있는 영역, 64K 청크 경계, 큰 문서 스캔 시간.
final class QA_FoldScannerTests: XCTestCase {
    private func regions(_ text: String, markdown: Bool = false, range: Range<Int>? = nil) -> [FoldRegion] {
        FoldScanner.regions(in: text as NSString, index: LineIndex(text: text), isMarkdown: markdown, range: range)
    }
    private func pairs(_ r: [FoldRegion]) -> [[Int]] { r.map { [$0.startLine, $0.endLine] } }

    // MARK: 줄 끝

    func testCRLFMatchesLF() {
        let lf = "def f():\n    a = 1\n    b = 2\nprint(1)\n"
        let crlf = lf.replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertEqual(pairs(regions(crlf)), [[1, 3]])
        XCTAssertEqual(regions(crlf), regions(lf))
        // 괄호 규칙: `{\r` 끝과 `}\r` 닫는 줄도 LF 와 같다
        XCTAssertEqual(pairs(regions("f() {\r\n    x\r\n}\r\nnext\r\n")), [[1, 3]])
        // 마크다운 헤딩·펜스
        let md = "# T\r\nx\r\n## A\r\ny\r\n```\r\n# in fence\r\n```\r\n"
        XCTAssertEqual(pairs(regions(md, markdown: true)), [[1, 7], [3, 7], [5, 7]])
        // CRLF 빈 줄(\r 만 있는 줄)은 빈 줄이다 — 영역 끝의 빈 줄은 제외된다
        XCTAssertEqual(pairs(regions("a\r\n    b\r\n\r\n\r\nc\r\n")), [[1, 2]])
    }

    func testCROnlyFileIsOneLine() {
        // 옛 Mac 줄 끝(\r 만)은 LineIndex 가 한 줄로 보므로 영역이 없다 (크래시 없이)
        XCTAssertEqual(regions("a\r    b\r    c\rd"), [])
    }

    // MARK: 탭·공백

    func testTabsMixedWithSpaces() {
        // "\tchild" = 4, "    \tgrand" = 8 (탭은 다음 4의 배수로), "  \t  sib" = 6
        let t = "root\n\tchild\n    \tgrand\n  \t  sib\nend"
        XCTAssertEqual(pairs(regions(t)), [[1, 4], [2, 4]])
        // 탭 뒤 공백 1개(5)와 공백 5개는 같은 깊이
        XCTAssertEqual(pairs(regions("r\n\t a\n     b\nz")), [[1, 3]])
        // 탭과 공백이 같은 깊이를 다르게 쓰는 형제 줄도 한 영역
        XCTAssertEqual(pairs(regions("r\n\ta\n    b\n\tc\nz")), [[1, 4]])
    }

    // MARK: EOF

    func testRegionsEndingAtEOF() {
        XCTAssertEqual(pairs(regions("f() {\n    x\n}")), [[1, 3]])          // 개행 없는 닫는 괄호 줄
        XCTAssertEqual(pairs(regions("# A\nx", markdown: true)), [[1, 2]])
        XCTAssertEqual(pairs(regions("# A\nx\n", markdown: true)), [[1, 2]])
        XCTAssertEqual(pairs(regions("```\ncode", markdown: true)), [[1, 2]])  // 닫히지 않은 펜스는 끝까지
        XCTAssertEqual(pairs(regions("a\n    b")), [[1, 2]])
        XCTAssertEqual(pairs(regions("a\n    b\n    ")), [[1, 2]])             // 끝의 공백뿐인 줄은 숨기지 않는다
    }

    // MARK: 마크다운

    func testHeadingsInsideFenceAreNotHeadings() {
        let t = "# Top\n```\n# not heading\n## nor this\n```\n# Second\nx\n"
        XCTAssertEqual(pairs(regions(t, markdown: true)), [[1, 5], [2, 5], [6, 7]])
        // ~~~ 펜스도 같다
        XCTAssertEqual(pairs(regions("~~~\n# x\n~~~\n", markdown: true)), [[1, 3]])
        // 닫히지 않은 펜스 안의 헤딩은 끝까지 헤딩이 아니다
        XCTAssertEqual(pairs(regions("# A\n```\n# B\nx\n", markdown: true)), [[1, 4], [2, 4]])
        // 들여쓴(4칸) 펜스는 펜스가 아니다 — 들여쓰기 영역만
        XCTAssertEqual(pairs(regions("a\n    ```\n    # c\n    ```\nb", markdown: true)), [[1, 4]])
    }

    func testHashLinesInNonMarkdownAreNotHeadings() {
        let code = "# comment\nx = 1\n# another\ny = 2\n#!/bin/sh\n#pragma once\n"
        XCTAssertEqual(regions(code, markdown: false), [])
        // 마크다운이어도 `#!`, `#pragma` 처럼 공백 없이 이어지는 줄은 헤딩이 아니다
        XCTAssertEqual(regions("#!/bin/sh\necho\n#pragma once\nx\n", markdown: true), [])
        // `#` 7개 이상은 헤딩이 아니다
        XCTAssertEqual(regions("####### seven\nx\n", markdown: true), [])
        XCTAssertEqual(pairs(regions("###### six\nx\n", markdown: true)), [[1, 2]])
    }

    func testHeadingRegionEndsBeforeNextBlankRun() {
        // 헤딩 영역은 같거나 높은 레벨의 다음 헤딩 직전까지, 끝의 빈 줄은 제외
        let t = "# A\na1\n\n\n## B\nb1\n\n# C\nc1\n\n\n"
        XCTAssertEqual(pairs(regions(t, markdown: true)), [[1, 6], [5, 6], [8, 9]])
    }

    func testHeadingWithOnlyBlankLinesBelowIsNotARegion() {
        XCTAssertEqual(regions("# A\n\n\n# B\n", markdown: true), [])
        XCTAssertEqual(regions("# A\n   \n\t\n# B\n", markdown: true), [])
    }

    // MARK: 괄호

    func testOpenBraceImmediatelyClosed() {
        // `{` 바로 다음 줄이 `}` 이면 숨길 줄이 없다 — 영역 아님 (문서화된 동작: 빈 블록은 접지 않는다)
        XCTAssertEqual(regions("f() {\n}\nx\n"), [])
        XCTAssertEqual(regions("a = [\n]\n"), [])
        // 한 줄짜리 블록 `{ x }` 는 당연히 아님
        XCTAssertEqual(regions("f() { x }\ny\n"), [])
    }

    func testUnbalancedBrackets() {
        XCTAssertEqual(pairs(regions("a = [\n    1,\n    2\n")), [[1, 3]])            // 닫는 괄호 없음 → 들여쓰기 규칙만
        XCTAssertEqual(regions("x\n]\n"), [])                                            // 닫는 괄호만
        XCTAssertEqual(pairs(regions("f() {\n    a\n}\n}\n")), [[1, 3]])                 // 닫는 괄호 하나 더 — 무시
        XCTAssertEqual(pairs(regions("a = [\n    1\n}\n")), [[1, 2]])                    // 종류가 다른 닫는 괄호는 머리와 짝이 아니다 → 보이게 둔다
        XCTAssertEqual(pairs(regions("f(\n    a\n  )\n")), [[1, 3]])                     // 들여쓴 `)` 는 들여쓰기 규칙으로 포함
        XCTAssertEqual(pairs(regions("f() {   \n    x\n}\n")), [[1, 3]])                 // 머리 줄 끝 공백 허용
        XCTAssertEqual(pairs(regions("f() { // c\n    x\n}\n")), [[1, 2]])               // 머리 줄 끝 주석 → 괄호 규칙 미적용 (문서화)
        XCTAssertEqual(pairs(regions("f() {\n    x\n} // end\n")), [[1, 2]])             // 닫는 줄의 주석 → 보이게 둔다 (문서화)
        XCTAssertEqual(pairs(regions("f() {\n    x\n});\n")), [[1, 3]])                  // `});` `],` 는 닫는 줄
        XCTAssertEqual(pairs(regions("a = [\n    1\n],\n")), [[1, 3]])
        // 깊이 들어간 중첩: 안쪽 `}` 는 안쪽 머리에만 붙는다
        let nested = "a {\n    b {\n        c\n    }\n    d\n}\n"
        XCTAssertEqual(pairs(regions(nested)), [[1, 6], [2, 4]])
    }

    func testBracketRuleDisabledInMarkdown() {
        XCTAssertEqual(pairs(regions("f {\n    x\n}\n", markdown: true)), [[1, 2]])
    }

    // MARK: 작은 파일

    func testTinyFiles() {
        for t in ["", "x", "    x", "{", "}", "\n", "\n\n", "# H", "```", "\t", " "] {
            XCTAssertEqual(regions(t), [], "'\(t.debugDescription)'")
            XCTAssertEqual(regions(t, markdown: true), [], "'\(t.debugDescription)' md")
        }
        // 2줄: 숨길 줄 하나면 영역
        XCTAssertEqual(pairs(regions("a\n    b")), [[1, 2]])
        XCTAssertEqual(pairs(regions("# a\nb", markdown: true)), [[1, 2]])
    }

    // MARK: 한글·이모지 (UTF-16 서러게이트)

    func testKoreanAndEmojiOffsets() {
        let t = "함수 정의 {\n    한글 😀 줄\n    두 번째 😀😀\n}\n다음 😀\n"
        let ns = t as NSString
        let idx = LineIndex(nsString: ns)
        XCTAssertEqual(idx.lineCount, 6)
        XCTAssertEqual(pairs(regions(t)), [[1, 4]])
        // 줄 시작 오프셋이 UTF-16 기준으로 맞는지 (이모지는 2 유닛)
        XCTAssertEqual(ns.substring(with: NSRange(location: idx.lineStarts[3], length: 1)), "}")
        XCTAssertEqual(ns.substring(from: idx.lineStarts[4]), "다음 😀\n")
        // 부분 범위 스캔도 같은 결과
        XCTAssertEqual(pairs(regions(t, range: 1..<5)), [[1, 4]])
        // 마크다운 헤딩에 이모지
        XCTAssertEqual(pairs(regions("# 제목 😀\n본문 😀\n## 소제목 👨‍👩‍👧\n내용\n", markdown: true)), [[1, 4], [3, 4]])
        // 이모지로 시작하는 줄은 헤딩·펜스·괄호 어느 것도 아니다
        XCTAssertEqual(regions("😀 a\n😀 b\n", markdown: true), [])
        // 전각 공백(U+3000)은 들여쓰기가 아니다
        XCTAssertEqual(regions("a\n\u{3000}b\nc"), [])
    }

    func testBOMAtStartBlocksFirstHeading() {
        // 문서화: BOM(U+FEFF) 이 남아 있으면 첫 줄은 `#` 으로 시작하지 않아 헤딩이 아니다 (로더가 BOM 을 벗기는지 별도 확인)
        XCTAssertEqual(pairs(regions("\u{FEFF}# A\nx\n# B\ny\n", markdown: true)), [[3, 4]])
    }

    // MARK: 빈 줄

    func testRegionsWithOnlyBlankLines() {
        XCTAssertEqual(regions("head\n\n\n\nnext"), [])
        XCTAssertEqual(regions("head\n    \n\t\n        \nnext"), [])          // 들여쓴 공백뿐인 줄도 빈 줄
        XCTAssertEqual(pairs(regions("a\n    b\n   \n    c\nd")), [[1, 4]])     // 안쪽 빈 줄은 포함
        XCTAssertEqual(pairs(regions("a\n    b\n        \nd")), [[1, 2]])       // 끝의 더 깊은 공백 줄은 제외
        XCTAssertEqual(pairs(regions("a\n        b\n    c\nd")), [[1, 3]])      // 중간 깊이로 내려와도 바깥 영역에 포함
    }

    // MARK: 청크 경계

    func testStatePersistsAcrossChunkBoundary() {
        // 64K 청크 경계를 걸치는 긴 줄: 줄 끝의 `{`, 다음 줄의 들여쓰기, 닫는 `}` 가 모두 유지돼야 한다
        let long = String(repeating: "x", count: 70_000)
        XCTAssertEqual(pairs(regions(long + " {\n    y\n}\n")), [[1, 3]])
        // 경계에 걸친 헤딩 줄 (마크다운)
        let md = "# " + long + "\nbody\n## B\nb\n"
        XCTAssertEqual(pairs(regions(md, markdown: true)), [[1, 4], [3, 4]])
        // 경계 직전에 개행이 오는 경우 (65_535 글자 + \n)
        let edge = String(repeating: "a", count: 65_535) + "\n    b\nc\n"
        XCTAssertEqual(pairs(regions(edge)), [[1, 2]])
    }

    // MARK: range 인자 경계

    func testRangeArgumentEdges() {
        let t = "root\n    a\n    b\nsecond\n    c\n    d\nthird\n    e"
        XCTAssertEqual(regions(t, range: 50..<60), [])            // 문서 밖 → 마지막 줄만 스캔
        XCTAssertEqual(regions(t, range: 0..<0), [])              // 빈 범위
        XCTAssertEqual(regions(t, range: -5..<0), [])             // 음수
        XCTAssertEqual(pairs(regions(t, range: 1..<2)), [])       // 머리 줄만
        XCTAssertEqual(pairs(regions(t, range: 2..<4)), [])       // 숨은 줄만 (같은 깊이) → 영역 없음
        XCTAssertEqual(pairs(regions(t, range: 7..<8)), [])
        XCTAssertEqual(pairs(regions(t, range: 7..<9)), [[7, 8]])
    }

    func testHelpersOnEmptyAndSingle() {
        XCTAssertNil(FoldScanner.region(containingHeaderLine: 1, in: []))
        XCTAssertNil(FoldScanner.innermostRegion(containingLine: 1, in: []))
        XCTAssertEqual(FoldScanner.enclosingRegions(ofLine: 1, in: []), [])
        let one = [FoldRegion(startLine: 3, endLine: 5)]
        XCTAssertEqual(FoldScanner.region(containingHeaderLine: 3, in: one), one[0])
        XCTAssertNil(FoldScanner.region(containingHeaderLine: 4, in: one))
        XCTAssertEqual(FoldScanner.innermostRegion(containingLine: 5, in: one), one[0])
        XCTAssertNil(FoldScanner.innermostRegion(containingLine: 6, in: one))
        XCTAssertNil(FoldScanner.innermostRegion(containingLine: 2, in: one))
        XCTAssertTrue(one[0].contains(line: 3) && one[0].contains(line: 5) && !one[0].contains(line: 6) && !one[0].contains(line: 2))
        XCTAssertEqual(one[0].hiddenLineCount, 2)
    }

    // MARK: 성능

    func testScan160kLines() {
        var lines: [String] = []
        lines.reserveCapacity(160_000)
        for i in 0..<160_000 {
            switch i % 16 {
            case 0: lines.append("## Section \(i / 16)")
            case 1: lines.append("def f\(i)(a, b):")
            case 2, 3, 4, 5: lines.append("    x = \(i)  # 한글 주석 😀")
            case 6: lines.append("        if x: {")
            case 7: lines.append("            y")
            case 8: lines.append("        }")
            case 9: lines.append("")
            case 10: lines.append("```")
            case 11: lines.append("# inside fence")
            case 12: lines.append("```")
            default: lines.append("plain line \(i) with some words to make it longer")
            }
        }
        let text = lines.joined(separator: "\n")
        let ns = text as NSString
        let idx = LineIndex(nsString: ns)
        XCTAssertEqual(idx.lineCount, 160_000)
        var best = Double.greatestFiniteMagnitude
        var count = 0
        for _ in 0..<3 {
            let t = CFAbsoluteTimeGetCurrent()
            let r = FoldScanner.regions(in: ns, index: idx, isMarkdown: true)
            best = min(best, (CFAbsoluteTimeGetCurrent() - t) * 1000)
            count = r.count
        }
        print("QA FoldScanner 160k lines (\(ns.length) UTF-16) · \(count) regions · best of 3: \(String(format: "%.1f", best)) ms")
        XCTAssertGreaterThan(count, 30_000)
        #if DEBUG
        XCTAssertLessThan(best, 3_000, "Debug build tolerance (Release target is < 60 ms — see the Release benchmark)")
        #else
        XCTAssertLessThan(best, 60, "FoldScanner took \(best) ms for 160k lines")
        #endif
    }
}
