import XCTest
@testable import HyperCore

final class LineIndexTests: XCTestCase {
    func testBasic() {
        let i = LineIndex(text: "a\nbb\n\nccc")
        XCTAssertEqual(i.lineCount, 4)
        XCTAssertEqual(i.lineNumber(forUTF16Offset: 0), 1)
        XCTAssertEqual(i.lineNumber(forUTF16Offset: 2), 2)
        XCTAssertEqual(i.lineNumber(forUTF16Offset: 5), 3)
        XCTAssertEqual(i.lineNumber(forUTF16Offset: 99), 4)
        XCTAssertEqual(i.range(ofLine: 2), NSRange(location: 2, length: 2))
        XCTAssertEqual(i.range(ofLine: 3), NSRange(location: 5, length: 0))
        XCTAssertEqual(i.range(ofLine: 4), NSRange(location: 6, length: 3))
        XCTAssertEqual(i.column(forUTF16Offset: 3), 2)
    }
    func testTrailingNewlineAndEmpty() {
        XCTAssertEqual(LineIndex(text: "a\n").lineCount, 2)
        XCTAssertEqual(LineIndex(text: "a\n").range(ofLine: 2), NSRange(location: 2, length: 0))
        XCTAssertEqual(LineIndex(text: "").lineCount, 1)
        XCTAssertEqual(LineIndex().lineNumber(forUTF16Offset: 0), 1)
    }
    func testHangul() {
        let i = LineIndex(text: "한글\n둘")
        XCTAssertEqual(i.lineNumber(forUTF16Offset: 3), 2)
        XCTAssertEqual(i.range(ofLine: 1), NSRange(location: 0, length: 2))
    }
}

final class SearchTests: XCTestCase {
    func testPlain() throws {
        let t = "foo bar\nBaz foo\n"
        let hits = try SearchEngine.search("foo", in: t, index: LineIndex(text: t), options: SearchOptions())
        XCTAssertEqual(hits.map(\.line), [1, 2])
        XCTAssertEqual(hits[1].column, 5)
        XCTAssertEqual(hits[1].lineText, "Baz foo")
        XCTAssertEqual(hits[1].matchInLine, NSRange(location: 4, length: 3))
    }
    func testRegexAndCase() throws {
        var o = SearchOptions(); o.regex = true; o.caseSensitive = true
        let t = "Baz\nbaz\n"
        XCTAssertEqual(try SearchEngine.search("^B.z$", in: t, index: LineIndex(text: t), options: o).count, 1)
        o.caseSensitive = false
        XCTAssertEqual(try SearchEngine.search("^B.z$", in: t, index: LineIndex(text: t), options: o).count, 2)
    }
    func testWholeWord() throws {
        var o = SearchOptions(); o.wholeWord = true
        let t = "cat concat cat"
        XCTAssertEqual(try SearchEngine.search("cat", in: t, index: LineIndex(text: t), options: o).count, 2)
    }
    func testInvalidRegex() {
        var o = SearchOptions(); o.regex = true
        XCTAssertThrowsError(try SearchEngine.search("(", in: "x", index: LineIndex(text: "x"), options: o))
    }
    func testLongLinePreviewIsTrimmed() throws {
        let t = String(repeating: "a", count: 500) + "NEEDLE" + String(repeating: "b", count: 500)
        let hits = try SearchEngine.search("NEEDLE", in: t, index: LineIndex(text: t), options: SearchOptions())
        XCTAssertEqual(hits.count, 1)
        XCTAssertLessThanOrEqual(hits[0].lineText.count, 160)
        XCTAssertEqual((hits[0].lineText as NSString).substring(with: hits[0].matchInLine), "NEEDLE")
    }
}

final class TimestampTests: XCTestCase {
    func testFormat() {
        var cal = Calendar(identifier: .gregorian)
        let tz = TimeZone(identifier: "Asia/Seoul")!
        cal.timeZone = tz
        let d = cal.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 14, minute: 5))!
        let s = Timestamp.heading(d, locale: Locale(identifier: "ko_KR"), timeZone: tz)
        XCTAssertEqual(s, "## 2026-10-30 (금) 14:05")
        XCTAssertNotNil(Timestamp.headingRegex.firstMatch(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length)))
        // 영어 로케일 요일(3글자)도 타임스탬프로 인식
        let en = Timestamp.heading(d, locale: Locale(identifier: "en_US"), timeZone: tz)
        XCTAssertEqual(en, "## 2026-10-30 (Fri) 14:05")
        XCTAssertNotNil(Timestamp.headingRegex.firstMatch(in: en, options: [], range: NSRange(location: 0, length: (en as NSString).length)))
        XCTAssertEqual(OutlineScanner.timeline(en + "\nnext", index: LineIndex(text: en + "\nnext")).first?.precise, true)
    }
}

final class ThemeTests: XCTestCase {
    func testBundleLoads() throws {
        let themes = try ThemeStore.loadBundled()
        XCTAssertEqual(themes.count, 22)
        XCTAssertEqual(themes.filter { !$0.isDark }.count, 5)
        XCTAssertEqual(themes.first?.id, ThemeStore.defaultLightID)
        XCTAssertEqual(themes[1].id, ThemeStore.defaultDarkID)
        XCTAssertEqual(Set(themes.map(\.id)).count, 22)
        XCTAssertFalse(themes.contains { $0.name.hasPrefix("KP") })
    }
    @MainActor func testDefaultFollowsSystemAppearance() {
        let d = UserDefaults(suiteName: "hyperedit.tests.\(UUID().uuidString)")!
        let store = ThemeStore(defaults: d, systemIsDark: false)
        XCTAssertTrue(store.followsSystem)
        XCTAssertEqual(store.current.id, ThemeStore.defaultLightID)
        store.systemAppearanceChanged(isDark: true)
        XCTAssertEqual(store.current.id, ThemeStore.defaultDarkID)
        store.select(id: "homebrew-terminal")
        XCTAssertFalse(store.followsSystem)
        store.systemAppearanceChanged(isDark: false)
        XCTAssertEqual(store.current.id, "homebrew-terminal", "직접 고른 테마는 시스템 전환에 바뀌지 않음")
        let again = ThemeStore(defaults: d, systemIsDark: false)
        XCTAssertEqual(again.current.id, "homebrew-terminal", "선택이 저장됨")
        again.setFollowsSystem(true)
        XCTAssertEqual(again.current.id, ThemeStore.defaultLightID)
    }
    func testDerive() {
        let t = Theme(palette: .fallback)
        XCTAssertEqual(t.background.hexString, "#010f1e")
        XCTAssertEqual(t.cursor.hexString, "#38fe27")
        XCTAssertEqual(t.selection.a, Double(0xA6) / 255, accuracy: 0.01)
        XCTAssertEqual(t.syntaxColor("keyword").hexString, "#00e5e5")
    }
    func testHex() {
        XCTAssertEqual(RGBA(hex: "#FFF")?.hexString, "#ffffff")
        XCTAssertEqual(RGBA(hex: "#00000080")?.a ?? 0, 128.0 / 255, accuracy: 0.001)
        XCTAssertNil(RGBA(hex: "zz"))
    }
}

final class HangulFixerTests: XCTestCase {
    func testContainsHangul() {
        XCTAssertTrue(HangulFontFixer.containsHangul("abc 한글"))
        XCTAssertFalse(HangulFontFixer.containsHangul("abc 123"))
    }
}

final class TextToolsTests: XCTestCase {
    func testSort() {
        XCTAssertEqual(TextTools.sortLines(["b", "A", "c"]), ["A", "b", "c"])
        XCTAssertEqual(TextTools.sortLines(["10 x", "9 y", "100 z"], numeric: true), ["9 y", "10 x", "100 z"])
        XCTAssertEqual(TextTools.sortLines(["a", "b"], ascending: false), ["b", "a"])
    }
    func testDedupeAndBlank() {
        XCTAssertEqual(TextTools.dedupeLines(["a", "b", "a", "c", "b"]), ["a", "b", "c"])
        XCTAssertEqual(TextTools.removeBlankLines(["a", "", "  ", "b"]), ["a", "b"])
    }
    func testWhitespace() {
        XCTAssertEqual(TextTools.trimTrailing(["a  ", "b\t", "c"]), ["a", "b", "c"])
        XCTAssertEqual(TextTools.tabsToSpaces(["a\tb", "\tx"], width: 4), ["a   b", "    x"])
        XCTAssertEqual(TextTools.spacesToTabs(["        x", "   y"], width: 4), ["\t\tx", "   y"])
        XCTAssertEqual(TextTools.tabsToSpaces(["한\tb"], width: 4), ["한  b"])
    }
    func testJoinNumberCase() {
        XCTAssertEqual(TextTools.joinLines(["a", " b ", ""]), ["a b"])
        XCTAssertEqual(TextTools.numberLines(["x", "y"]), ["1. x", "2. y"])
        XCTAssertEqual(TextTools.invertCase("aB1"), "Ab1")
        XCTAssertEqual(TextTools.capitalize("hello world"), "Hello World")
    }
    func testStats() {
        let s = TextTools.stats("ab cd\n한글")
        XCTAssertEqual(s.lines, 2); XCTAssertEqual(s.words, 3); XCTAssertEqual(s.chars, 8); XCTAssertEqual(s.charsNoSpace, 6)
    }
}

final class ColumnBlockTests: XCTestCase {
    let text = "abcdef\nab\nabcdefgh\n" as NSString
    func testLinesClampAndPadding() {
        let b = ColumnBlock(topLineStart: 0, lineCount: 3, anchorCol: 2, headCol: 4)
        let ls = b.lines(in: text)
        XCTAssertEqual(ls.count, 3)
        XCTAssertEqual(ls[0].range, NSRange(location: 2, length: 2))
        XCTAssertEqual(ls[1].range, NSRange(location: 7 + 2, length: 0)); XCTAssertEqual(ls[1].padding, 0)
        XCTAssertEqual(ls[2].range, NSRange(location: 10 + 2, length: 2))
        let short = ColumnBlock(topLineStart: 7, lineCount: 1, anchorCol: 5, headCol: 5)
        XCTAssertEqual(short.lines(in: text)[0].padding, 3)
        XCTAssertEqual(short.replacements(in: text, with: ["X"])[0].string, "   X")
    }
    func testExtendAndCollapse() {
        var b = ColumnBlock(topLineStart: 0, lineCount: 1, anchorCol: 1, headCol: 1)
        b = b.extended(dx: 2, dy: 1, in: text)
        XCTAssertEqual(b.lineCount, 2); XCTAssertEqual(b.colLo, 1); XCTAssertEqual(b.colHi, 3)
        b = b.extended(dx: 0, dy: -1, in: text)
        XCTAssertEqual(b.lineCount, 1)
        b = b.extended(dx: 0, dy: -1, in: text)   // 첫 줄이라 더 못 올라감
        XCTAssertEqual(b.lineCount, 1); XCTAssertEqual(b.topLineStart, 0)
        let bottom = ColumnBlock(topLineStart: 10, lineCount: 1, anchorCol: 0, headCol: 0).extended(dx: 0, dy: -1, in: text)
        XCTAssertEqual(bottom.topLineStart, 7); XCTAssertEqual(bottom.lineCount, 2); XCTAssertFalse(bottom.headIsBottom)
        XCTAssertEqual(b.afterInsert(width: 2).colLo, 3)
        XCTAssertEqual(ColumnBlock(topLineStart: 0, lineCount: 1, anchorCol: 2, headCol: 4).afterDelete(backward: true).colLo, 2)
        XCTAssertEqual(ColumnBlock(topLineStart: 0, lineCount: 1, anchorCol: 2, headCol: 2).afterDelete(backward: true).colLo, 1)
    }
    func testNumberStrings() {
        XCTAssertEqual(ColumnBlock.numberStrings(count: 3, start: 9, step: 1, zeroPad: true), ["09", "10", "11"])
        XCTAssertEqual(ColumnBlock.numberStrings(count: 2, start: 0, step: 5, zeroPad: false), ["0", "5"])
    }
}

final class OutlineScannerTests: XCTestCase {
    let sample = """
    # from pymongo import MongoClient
    ## 2026-10-30 (금) 09:30
    오늘 할 일
    [대출이자계산기] 광고없고
    가. Auto Scale Up 비교
    1) 데이터의 생명주기
    ## 진짜 헤딩
    2022-01-06 01:21:02.910+0000 [id=1] INFO log
    2022-01-06 01:22:10.477+0000 [id=1] WARNING log
    [ERROR] something
    """
    func testOutline() {
        let items = OutlineScanner.outline(sample, index: LineIndex(text: sample))
        let titles = items.map(\.title)
        XCTAssertFalse(titles.contains { $0.contains("pymongo") })          // 코드 주석 제외
        XCTAssertFalse(titles.contains { $0.contains("2026-10-30") })       // 타임스탬프 제외
        XCTAssertTrue(titles.contains("[대출이자계산기]"))
        XCTAssertTrue(titles.contains { $0.hasPrefix("가. ") })
        XCTAssertTrue(titles.contains { $0.hasPrefix("1) ") })
        XCTAssertTrue(titles.contains("진짜 헤딩"))
        XCTAssertFalse(titles.contains("[ERROR]"))
        XCTAssertEqual(items.map(\.line), items.map(\.line).sorted())
    }
    func testTimeline() {
        let items = OutlineScanner.timeline(sample, index: LineIndex(text: sample))
        XCTAssertEqual(items.count, 2)                 // 정밀 1 + 로그 날짜(연속 같은 날짜는 1개)
        XCTAssertTrue(items[0].precise); XCTAssertEqual(items[0].timeLabel, "09:30"); XCTAssertEqual(items[0].preview, "오늘 할 일")
        XCTAssertFalse(items[1].precise); XCTAssertEqual(items[1].dateLabel, "2022-01-06"); XCTAssertEqual(items[1].line, 8)
    }
}

final class DocumentLocationTests: XCTestCase {
    func testTextFileDetector() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("he-tfd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let txt = dir.appendingPathComponent("a.txt"); try "hello".write(to: txt, atomically: true, encoding: .utf8)
        let png = dir.appendingPathComponent("b.png"); try "not really".write(to: png, atomically: true, encoding: .utf8)
        let nul = dir.appendingPathComponent("c.dat"); try Data([0x41, 0x00, 0x42]).write(to: nul)
        XCTAssertTrue(TextFileDetector.isLikelyText(txt))
        XCTAssertFalse(TextFileDetector.isLikelyText(png), "확장자로 바이너리 판정")
        XCTAssertFalse(TextFileDetector.isLikelyText(nul), "NUL 바이트로 바이너리 판정")
        XCTAssertTrue(TextFileDetector.isLikelyText(dir.appendingPathComponent("missing.md")), "없는 파일은 텍스트로 간주")
    }
    func testRememberedBinaryPathIsIgnored() throws {
        let d = UserDefaults(suiteName: "hyperedit.tests.\(UUID().uuidString)")!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("he-loc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let png = dir.appendingPathComponent("image.png"); try Data([0x89, 0x50, 0x4E, 0x47, 0]).write(to: png)
        MemoLocation.remember(png, defaults: d)
        XCTAssertEqual(MemoLocation.resolveDefault(arguments: [], defaults: d), MemoLocation.defaultLocalURL, "이미지 경로는 무시하고 기본 문서로")
        let txt = dir.appendingPathComponent("notes.txt"); try "x".write(to: txt, atomically: true, encoding: .utf8)
        MemoLocation.remember(txt, defaults: d)
        XCTAssertEqual(MemoLocation.resolveDefault(arguments: [], defaults: d).path, txt.path)
        XCTAssertEqual(MemoLocation.resolveDefault(arguments: ["app", "--file", "/tmp/x.md"], defaults: d).path, "/tmp/x.md", "--file 이 최우선")
    }
}

final class FileSearchTests: XCTestCase {
    func testMaskAndSearch() throws {
        XCTAssertTrue(FileSearch.matches(mask: "*.md;*.txt", fileName: "A.MD"))
        XCTAssertFalse(FileSearch.matches(mask: "*.md", fileName: "a.txt"))
        XCTAssertTrue(FileSearch.matches(mask: "", fileName: "anything"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ue-fs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try "hello world\nfoo".write(to: dir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "no match".write(to: dir.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        try "world again".write(to: dir.appendingPathComponent("sub/c.txt"), atomically: true, encoding: .utf8)
        try Data([0, 1, 2, 3]).write(to: dir.appendingPathComponent("bin.dat"))
        let r = try FileSearch.search("world", in: dir, mask: "*.txt", options: SearchOptions())
        XCTAssertEqual(r.hits.count, 2); XCTAssertEqual(r.filesMatched, 2); XCTAssertEqual(r.filesScanned, 2)
        XCTAssertEqual(Set(r.hits.map(\.fileName)), ["a.txt", "c.txt"])
    }
    func testReplacementTemplate() {
        var o = SearchOptions(); o.regex = true
        let text = "price 120 won"
        let hits = try! SearchEngine.search(#"(\d+) won"#, in: text, index: LineIndex(text: text), options: o)
        XCTAssertEqual(SearchEngine.replacement(for: hits[0].range, in: text, query: #"(\d+) won"#, options: o, template: "₩$1"), "₩120")
        XCTAssertEqual(SearchEngine.replacement(for: hits[0].range, in: text, query: "x", options: SearchOptions(), template: "Y"), "Y")
    }
}
