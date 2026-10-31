import XCTest
@testable import HyperCore

// QA 적대적 검증 — 주석 토글 · JSON 정리 · 스니펫 템플릿/저장소 · 매크로 Codable/저장소.
// 경계(CRLF · 공백만 있는 줄 · 끝 줄) · 유니코드(한글·이모지·조합형 자모·외톨이 서러게이트) · 대용량(깊은 중첩 · 1 MB 문자열 · 1만 단계) 을 다룬다.
// "알려진 제한" 이라 적힌 검사는 현재 동작을 고정해 두는 것이지 바람직한 동작을 뜻하지 않는다.

final class QA_CommentToggleTests: XCTestCase {
    private let slash = CommentSyntax(line: "//")
    private let html = CommentSyntax(block: ("<!--", "-->"))
    private let css = CommentSyntax(block: ("/*", "*/"))
    private func toggle(_ lines: [String], _ syntax: CommentSyntax) -> [String] { TextTools.toggleLineComment(lines: lines, syntax: syntax) }

    func testCRLFKeepsCarriageReturnAtLineEndAndSkipsBlankLines() {
        // 문서가 CRLF 면 편집기는 "\n" 으로 나눠 각 줄 끝에 "\r" 이 남는다 — 빈 줄("\r")은 건너뛰고 기호는 "\r" 앞에 들어가야 한다
        let lines = ["a\r", "\r", "  b\r", "c"]   // 마지막 줄은 문서 끝이라 \r 없음
        let out = toggle(lines, slash)
        XCTAssertEqual(out, ["// a\r", "\r", "//   b\r", "// c"])
        XCTAssertEqual(toggle(out, slash), lines)
        // 블록: 닫는 기호가 "\r" 뒤에 붙으면 줄 중간에 CR 이 끼어 화면에서 줄이 갈라진다
        let h = toggle(["<p>x</p>\r", "\r", "  <b>y</b>\r"], html)
        XCTAssertEqual(h, ["<!-- <p>x</p> -->\r", "\r", "<!--   <b>y</b> -->\r"])
        XCTAssertEqual(toggle(h, html), ["<p>x</p>\r", "\r", "  <b>y</b>\r"])
        // CR 만 있는 줄들 → 모두 빈 줄 → 그 줄 자체에 기호
        XCTAssertEqual(toggle(["\r", "\r"], slash), ["// \r", "// \r"])
        XCTAssertEqual(toggle(["// \r", "// \r"], slash), ["\r", "\r"])
    }

    func testWhitespaceOnlyLinesMixedTabsSpaces() {
        let lines = ["\t", "  \t  ", ""]
        let out = toggle(lines, slash)
        XCTAssertEqual(out, ["// \t", "//   \t  ", "// "], "모두 빈 줄이면 그 줄들에 기호 — 탭·공백이 섞여 공통 접두는 없음")
        XCTAssertEqual(toggle(out, slash), lines)
        XCTAssertEqual(toggle(["  x", "   ", "\t"], slash), ["  // x", "   ", "\t"], "내용 줄이 하나라도 있으면 공백만 있는 줄은 손대지 않는다")
    }

    func testMixedTabSpaceIndentUsesCommonPrefixOnly() {
        let lines = ["\t  a", "\t\tb", "\t c"]
        let out = toggle(lines, slash)
        XCTAssertEqual(out, ["\t//   a", "\t// \tb", "\t//  c"])
        XCTAssertEqual(toggle(out, slash), lines)
    }

    func testSingleCommentedLineWithoutSpaceAfterMarker() {
        XCTAssertEqual(toggle(["//x"], slash), ["x"])
        XCTAssertEqual(toggle(["  //x"], slash), ["  x"])
        XCTAssertEqual(toggle(["///x"], slash), ["/x"], "기호 하나만 벗긴다")
        XCTAssertEqual(toggle(["// //x"], slash), ["//x"])
        XCTAssertEqual(toggle(["//"], slash), [""])
        XCTAssertEqual(toggle(["<!--x-->"], html), ["x"])
        XCTAssertEqual(toggle(["/*x*/"], css), ["x"])
    }

    func testMarkerInsideStringIsNotTreatedAsComment() {
        let lines = [##"let s = "// not a comment""##, ##"  print("# nope")"##]
        let out = toggle(lines, slash)
        XCTAssertEqual(out, [##"// let s = "// not a comment""##, ##"//   print("# nope")"##])
        XCTAssertEqual(toggle(out, slash), lines)
        // 문자열 안에 닫는 블록 기호가 있어도 줄 단위 감싸기는 바깥 쌍만 벗긴다
        let h = [#"<a title="-->">x</a>"#]
        let wrapped = toggle(h, html)
        XCTAssertEqual(wrapped, [#"<!-- <a title="-->">x</a> -->"#])
        XCTAssertEqual(toggle(wrapped, html), h)
    }

    func testBlockWrapperWhenCloseMarkerAlreadyInsideLine() {
        XCTAssertEqual(toggle(["a --> b"], html), ["<!-- a --> b -->"])
        XCTAssertEqual(toggle(["<!-- a --> b -->"], html), ["a --> b"])
        XCTAssertEqual(toggle(["<!--"], html), ["<!-- <!-- -->"], "열림만 있는 줄은 주석이 아니다")
        XCTAssertEqual(toggle(["<!-- <!-- -->"], html), ["<!--"])
        let mixed = ["<!-- a -->", "b"]
        let once = toggle(mixed, html)
        XCTAssertEqual(once, ["<!-- <!-- a --> -->", "<!-- b -->"], "섞여 있으면 모두 감싼다 (VS Code 방식)")
        XCTAssertEqual(toggle(once, html), mixed)
        XCTAssertEqual(toggle(["<!---->"], html), [""], "빈 블록 주석은 '주석된 빈 줄'")
        XCTAssertEqual(toggle(["/**/"], css), [""])
        XCTAssertEqual(toggle(["a */ b"], css), ["/* a */ b */"])
        XCTAssertEqual(toggle(["/* a */ b */"], css), ["a */ b"])
    }

    func testKoreanEmojiAndDecomposedJamoKeepIndentOffsets() {
        let lines = ["  한글 줄", "  🙂 이모지 👩‍💻", "  각\u{1100}\u{1161}\u{11A8} 조합형", "  é\u{301}"]
        let out = toggle(lines, slash)
        XCTAssertEqual(out, ["  // 한글 줄", "  // 🙂 이모지 👩‍💻", "  // 각\u{1100}\u{1161}\u{11A8} 조합형", "  // é\u{301}"])
        XCTAssertEqual(toggle(out, slash), lines)
        // 공백 뒤에 결합 문자가 오면 Swift 는 " \u{301}" 을 한 글자로 본다 — 들여쓰기가 아니라 본문으로 처리하고, 크래시 없이 왕복해야 한다
        let odd = [" \u{301}x", "  y"]
        let o = toggle(odd, slash)
        XCTAssertEqual(o.count, 2)
        XCTAssertEqual(toggle(o, slash), odd)
    }

    func testEmptyInputAndTrailingWhitespaceAfterBlockClose() {
        XCTAssertEqual(toggle([], slash), [])
        XCTAssertEqual(toggle([""], html), ["<!-- -->"])
        XCTAssertEqual(toggle(["<!-- -->"], html), [""])
        let lines = ["a   ", "\tb\t"]
        let out = toggle(lines, html)
        XCTAssertEqual(out, ["<!-- a    -->", "<!-- \tb\t -->"])
        XCTAssertEqual(toggle(out, html), lines, "닫는 기호 앞의 원래 공백은 보존")
    }
}

final class QA_JSONFormatterTests: XCTestCase {
    private func err(_ s: String) -> JSONFormatter.SyntaxError? {
        do { _ = try JSONFormatter.format(s); return nil } catch let e as JSONFormatter.SyntaxError { return e } catch { return nil }
    }

    func testDeepNesting500LevelsFormatsWithoutStackOverflow() throws {
        let depth = 500
        let arrays = String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        let out = try JSONFormatter.format(arrays)
        XCTAssertEqual(out.components(separatedBy: "\n").count, 2 * depth - 1)
        XCTAssertEqual(try JSONFormatter.minify(out), arrays)
        let objects = String(repeating: #"{"a":"#, count: depth) + "1" + String(repeating: "}", count: depth)
        XCTAssertEqual(try JSONFormatter.minify(try JSONFormatter.format(objects)), objects)
    }

    func testNestingBeyondLimitIsAnErrorNotACrash() {
        // 50 KB 의 `[` 만으로 앱이 스택 오버플로로 죽어선 안 된다 (실측: 512 KB 스택 ≈ 1,000단계, 8 MB 메인 스레드 ≈ 20,000단계에서 크래시) → 깊이 제한 → 문법 오류
        let deep = String(repeating: "[", count: 50_000) + String(repeating: "]", count: 50_000)
        let e = err(deep)
        XCTAssertNotNil(e)
        XCTAssertTrue(e?.message.contains("deep") ?? false, e?.message ?? "nil")
        XCTAssertEqual(e?.offset, JSONFormatter.maxDepth, "제한을 넘는 첫 여는 괄호 위치")
        XCTAssertNotNil(err(String(repeating: #"{"k":"#, count: 50_000)))
        XCTAssertNotNil(err(String(repeating: #"[{"k":"#, count: 30_000)))
        XCTAssertGreaterThanOrEqual(JSONFormatter.maxDepth, 500, "깊이 500 은 허용")
    }

    func testExtremeNumbersCopiedVerbatim() throws {
        let src = "[1e400,-1E-400,123456789012345678901234567890,0.10,-0.0,1e+0,0e0]"
        XCTAssertEqual(try JSONFormatter.minify(src), src)
    }

    func testNulEscapeAndLoneSurrogates() throws {
        let u = "\\u"
        XCTAssertEqual(try JSONFormatter.minify(#"["\#(u)0000"]"#), #"["\#(u)0000"]"#)
        XCTAssertEqual(try JSONFormatter.minify(#"["a\#(u)001Fb"]"#), #"["a\#(u)001fb"]"#)
        XCTAssertEqual(try JSONFormatter.minify(#"["\#(u)D800"]"#), #"["\#(u)d800"]"#, "외톨이 상위 서러게이트는 이스케이프 유지")
        XCTAssertEqual(try JSONFormatter.minify(#"["\#(u)DFFF x"]"#), #"["\#(u)dfff x"]"#)
        XCTAssertEqual(try JSONFormatter.minify(#"["\#(u)D83D\#(u)0041"]"#), #"["\#(u)d83dA"]"#, "상위 뒤가 하위가 아니면 상위만 이스케이프")
        XCTAssertEqual(try JSONFormatter.minify(#"["\#(u)D83D"]"#), #"["\#(u)d83d"]"#)
        XCTAssertEqual(try JSONFormatter.minify(#"["\#(u)DE00\#(u)D83D"]"#), #"["\#(u)de00\#(u)d83d"]"#, "순서가 뒤집힌 쌍은 합치지 않는다")
        let out = try JSONFormatter.format(#"["\#(u)D800\#(u)0000\#(u)DC00"]"#)
        XCTAssertEqual(try JSONFormatter.format(out), out, "다시 돌려도 안정")
    }

    func testDuplicateKeysBothPreservedInOrder() throws {
        XCTAssertEqual(try JSONFormatter.minify(#"{"a":1,"b":2,"a":3}"#), #"{"a":1,"b":2,"a":3}"#)
        XCTAssertEqual(try JSONFormatter.format(#"{"a":1,"a":2}"#), "{\n  \"a\": 1,\n  \"a\": 2\n}")
    }

    func testOneMegabyteStringIsLinear() throws {
        let unit = "가나다라 abcd 🙂 "
        let big = String(repeating: unit, count: 1_048_576 / unit.utf8.count)
        XCTAssertGreaterThan(big.utf8.count, 1_000_000)
        let src = "[\"\(big)\"]"
        var t = CFAbsoluteTimeGetCurrent()
        let out = try JSONFormatter.format(src)
        let fast = CFAbsoluteTimeGetCurrent() - t
        XCTAssertEqual(out, "[\n  \"\(big)\"\n]")
        let src2 = "[\"\\n\(big)\\t\"]"   // 이스케이프가 있으면 느린 길 — 역시 선형
        t = CFAbsoluteTimeGetCurrent()
        let out2 = try JSONFormatter.minify(src2)
        let slow = CFAbsoluteTimeGetCurrent() - t
        XCTAssertEqual(out2, src2)
        print(String(format: "QA 1 MB string: fast path %.0f ms, escape path %.0f ms", fast * 1000, slow * 1000))
        XCTAssertLessThan(fast, 1.0); XCTAssertLessThan(slow, 1.0)
    }

    func testWhitespaceOnlyAndEmptyContainers() throws {
        XCTAssertEqual(err("   \n\t \r\n ")?.message, "Unexpected end of input")
        XCTAssertEqual(err("")?.message, "Unexpected end of input")
        XCTAssertEqual(err("\u{FEFF}")?.message, "Unexpected end of input", "BOM 만 있는 문서")
        XCTAssertEqual(try JSONFormatter.format("[[],{},[{}],{\"a\":[]}]"), "[\n  [],\n  {},\n  [\n    {}\n  ],\n  {\n    \"a\": []\n  }\n]")
        XCTAssertEqual(try JSONFormatter.format("{ }"), "{}")
        XCTAssertEqual(try JSONFormatter.format("[ /* c */ ]"), "[]")
        XCTAssertEqual(try JSONFormatter.format("[\n\n]"), "[]")
        XCTAssertEqual(try JSONFormatter.minify("{\"a\":[ ],}"), "{\"a\":[]}")
    }

    func testNonJSONLiteralsRejected() {
        for s in ["NaN", "Infinity", "-Infinity", "[NaN]", "{\"a\":Infinity}", "undefined", "0x10", ".5", "1.", "+1", "1_000", "01", "--1", "1e", "1e+", "tru", "nulll", "True", "None", "[1 2]", "{\"a\" 1}", "{\"a\":1 \"b\":2}"] {
            XCTAssertNotNil(err(s), "허용되면 안 됨: \(s)")
        }
    }

    func testCommentMarkersInsideStringsStay() throws {
        let src = #"{"url":"http://a/b","c":"/* not */ // nope","d":"a\/b"}"#
        XCTAssertEqual(try JSONFormatter.minify(src), #"{"url":"http://a/b","c":"/* not */ // nope","d":"a/b"}"#)
        XCTAssertEqual(err("[1 /* open")?.message, "Unterminated comment")
        XCTAssertEqual(err("[1 / 2]")?.message, "Expected ',' or ']' in array")
    }

    func testErrorColumnsAreUTF16AfterEmojiAndKorean() {
        let e = err(#"{"🙂한":x}"#)
        XCTAssertEqual(e?.offset, 7, "`{` `\"` 🙂(2) 한 `\"` `:` 뒤")
        XCTAssertEqual(e?.column, 8); XCTAssertEqual(e?.line, 1)
        XCTAssertEqual(e?.message, "Unexpected character 'x'")
        let e2 = err("[\n  \"한\",\n  \"🙂\" \"x\"\n]")
        XCTAssertEqual(e2?.line, 3); XCTAssertEqual(e2?.column, 8)
        XCTAssertEqual(err("[\"한\", 한]")?.message, "Unexpected character '한'", "비ASCII 는 UTF-8 시퀀스 전체를 보여 준다")
    }

    func testUnterminatedConstructsPointAtOpener() {
        XCTAssertEqual(err("[1, 2")?.message, "Unterminated array — missing ']'"); XCTAssertEqual(err("[1, 2")?.offset, 0)
        XCTAssertEqual(err("{\"a\": 1")?.offset, 0)
        XCTAssertEqual(err("{\"a\":")?.message, "Unexpected end of input")
        XCTAssertEqual(err(" \"abc")?.message, "Unterminated string"); XCTAssertEqual(err(" \"abc")?.offset, 1)
        XCTAssertEqual(err("[\"a\tb\"]")?.message, "Control character in string must be escaped")
        XCTAssertEqual(err("[\"a\\x\"]")?.message, "Invalid escape '\\x'")
        XCTAssertEqual(err("[\"\\u12\"]")?.message, "Invalid \\u escape")
    }

    func testCRLFInputProducesLFOutputAndKeepsOneTrailingNewline() throws {
        // 알려진 제한: CRLF 문서를 정리하면 LF 로 바뀐다 (상태바의 줄바꿈 표시는 저장 전까지 DOS 로 남을 수 있음)
        XCTAssertEqual(try JSONFormatter.format("{\r\n\"a\":1\r\n}\r\n"), "{\n  \"a\": 1\n}\n")
        XCTAssertEqual(try JSONFormatter.minify("[1]\n\n"), "[1]\n", "끝 개행은 하나만 유지")
    }
}

final class QA_SnippetTemplateTests: XCTestCase {
    func testTwoDigitTabstopIsSingleDigitThenLiteral() {
        // $1…$9 만 지원 — `$10` 은 탭스톱 1 + 글자 '0', `${10:x}` 는 탭스톱이 아니라 글자 그대로 (문서화된 동작)
        let r = SnippetTemplate.render("$10|${10:x}")
        XCTAssertEqual(r.text, "0|${10:x}")
        XCTAssertEqual(r.tabstops, [[NSRange(location: 0, length: 0)]])
        XCTAssertNil(r.final)
    }

    func testEmptyPlaceholderIsZeroLengthStop() {
        let r = SnippetTemplate.render("a${1:}b")
        XCTAssertEqual(r.text, "ab"); XCTAssertEqual(r.tabstops, [[NSRange(location: 1, length: 0)]])
    }

    func testUnknownOrMalformedVariablesStayVerbatim() {
        XCTAssertEqual(SnippetTemplate.render("${weird} ${} ${ date } ${DATE}").text, "${weird} ${} ${ date } ${DATE}")
        XCTAssertEqual(SnippetTemplate.render("${1").text, "${1")
        XCTAssertEqual(SnippetTemplate.render("$").text, "$")
        XCTAssertEqual(SnippetTemplate.render("$$").text, "$$")
        XCTAssertEqual(SnippetTemplate.render("${}").tabstops, [])
        XCTAssertEqual(SnippetTemplate.render("$a $가").text, "$a $가")
    }

    func testNestedPlaceholderIsNotSupportedButDoesNotCorrupt() {
        // 알려진 제한: VS Code 식 중첩 `${1:${date}}` 은 첫 `}` 에서 닫혀 자리표시자가 "${date" 가 되고 마지막 `}` 는 글자로 남는다
        let r = SnippetTemplate.render("${1:${date}}")
        XCTAssertEqual(r.text, "${date}")
        XCTAssertEqual(r.tabstops, [[NSRange(location: 0, length: 6)]])
    }

    func testBackslashEscapes() {
        XCTAssertEqual(SnippetTemplate.render(#"\\$1"#).text, #"\"#)
        XCTAssertEqual(SnippetTemplate.render(#"\\$1"#).tabstops, [[NSRange(location: 1, length: 0)]])
        XCTAssertEqual(SnippetTemplate.render(#"\$1 \${date}"#).text, "$1 ${date}")
        XCTAssertEqual(SnippetTemplate.render(#"\n \t \x \"#).text, #"\n \t \x \"#, "\\$ 와 \\\\ 만 이스케이프 — 나머지 역슬래시는 글자")
        XCTAssertEqual(SnippetTemplate.render(#"\\\$1"#).text, #"\$1"#)
    }

    func testTabstopOffsetsAreUTF16WithKoreanAndEmoji() {
        let r = SnippetTemplate.render("한글 ${1:값} 🙂$2 끝$0")
        XCTAssertEqual(r.text, "한글 값 🙂 끝")
        XCTAssertEqual(r.tabstops, [[NSRange(location: 3, length: 1)], [NSRange(location: 7, length: 0)]], "🙂 는 UTF-16 두 단위")
        XCTAssertEqual(r.final, 9)
        XCTAssertEqual((r.text as NSString).length, 9)
    }

    func testBodyWithoutTrailingNewlineAndFinalPlacement() {
        XCTAssertEqual(SnippetTemplate.render("a$0").final, 1)
        XCTAssertNil(SnippetTemplate.render("a").final)
        let r = SnippetTemplate.render("${0:end}")
        XCTAssertEqual(r.text, "end"); XCTAssertEqual(r.final, 0); XCTAssertTrue(r.tabstops.isEmpty, "알려진 제한: $0 자리표시자는 글자로 들어가고 캐럿은 그 앞 (선택되지 않음)")
        XCTAssertEqual(SnippetTemplate.render("$0 $0").final, 1, "마지막 $0 이 이긴다 (본문은 ' ' 한 글자)")
    }

    func testVariableValuesAreNotReparsed() {
        let r = SnippetTemplate.render("${selection}|${clipboard}", selection: "$1 ${date} \\$", clipboard: "${2:x}")
        XCTAssertEqual(r.text, "$1 ${date} \\$|${2:x}")
        XCTAssertTrue(r.tabstops.isEmpty)
    }

    func testDefaultsAreDistinctAndTriggersAreWordLike() {
        let triggers = SnippetStore.defaults.map(\.trigger)
        XCTAssertEqual(Set(triggers).count, triggers.count)
        for t in triggers { XCTAssertTrue(t.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }, "Tab 으로 닿을 수 없는 트리거: \(t)") }
    }
}

@MainActor
final class QA_SnippetStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("he-qa-snip-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func bump(_ url: URL, _ s: TimeInterval) throws {
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(s)], ofItemAtPath: url.path)
    }

    func testBrokenFileOnFirstLoadIsNotOverwritten() throws {
        let dir = tempDir()
        let url = dir.appendingPathComponent("snippets.json")
        try "[ { \"trigger\": \"x\", ".write(to: url, atomically: true, encoding: .utf8)
        let store = SnippetStore(directory: dir)
        XCTAssertTrue(store.snippets.isEmpty)
        XCTAssertTrue(store.lastError?.hasPrefix("snippets.json") ?? false, store.lastError ?? "nil")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "[ { \"trigger\": \"x\", ", "깨진 파일을 기본값으로 덮어쓰지 않는다")
    }

    func testHandWrittenFileMissingTitleDuplicateAndEmptyTriggers() throws {
        let dir = tempDir()
        let store = SnippetStore(directory: dir)
        try #"[{"trigger":"a","body":"x"}, {"trigger":"","title":"t","body":"x"}, {"trigger":"dup","title":"1","body":"one"}, {"trigger":"dup","title":"2","body":"two"},]"#.write(to: store.fileURL, atomically: true, encoding: .utf8)
        try bump(store.fileURL, 5)
        store.reloadIfChanged()
        XCTAssertNil(store.lastError, store.lastError ?? "")
        XCTAssertEqual(store.snippets.map(\.trigger), ["a", "dup", "dup"], "title 생략 허용 · 빈 트리거 제외 · 중복은 둘 다 (첫 항목이 이긴다)")
        XCTAssertEqual(store.snippet(forTrigger: "a")?.title, "")
        XCTAssertEqual(store.snippet(forTrigger: "dup")?.body, "one")
        try #"[{"trigger":"nobody","title":"t"}]"#.write(to: store.fileURL, atomically: true, encoding: .utf8)
        try bump(store.fileURL, 10)
        store.reloadIfChanged()
        XCTAssertNotNil(store.lastError, "body 가 없으면 오류")
        XCTAssertEqual(store.snippets.map(\.trigger), ["a", "dup", "dup"], "오류 때는 이전 목록 유지")
        XCTAssertEqual(try JSONDecoder().decode([Snippet].self, from: Data(try JSONEncoder().encode(store.snippets))), store.snippets, "인코딩은 그대로 왕복")
    }

    func testDeletedFileIsRecreatedWithDefaults() throws {
        let dir = tempDir()
        let store = SnippetStore(directory: dir)
        try FileManager.default.removeItem(at: store.fileURL)
        store.reloadIfChanged()
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path))
        XCTAssertEqual(store.snippets, SnippetStore.defaults)
        XCTAssertNil(store.lastError)
    }
}

final class QA_MacroCodableTests: XCTestCase {
    private func roundTrip<T: Codable & Equatable>(_ v: T) throws -> T {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return try dec.decode(T.self, from: enc.encode(v))
    }

    func testUnusualSelectorStringsRoundTrip() throws {
        let steps: [MacroStep] = [
            .command(""), .command(":"), .command("a:b:"), .command("한글명령:"), .command("insertText:replacementRange:"), .command("💥:"),
            .insert("줄\n바꿈\t탭 \"따옴표\" \\ 역슬래시 \u{0} 널 \u{1F} 제어 \r CR"), .insert(String(repeating: "가", count: 100_000)),
            .tool(""), .tool("deleteLine"), .find("(?i)needle|^$"), .find("\\"),
        ]
        XCTAssertEqual(try roundTrip(steps), steps)
        let m = Macro(name: "  이름 \n", steps: steps)
        XCTAssertEqual(try roundTrip(m), m)
    }

    func testHandWrittenJSONVariants() throws {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try dec.decode([MacroStep].self, from: Data(#"[{"type":"insert"},{"value":"x","type":"command"}]"#.utf8)), [.insert(""), .command("x")])
        XCTAssertThrowsError(try dec.decode(MacroStep.self, from: Data(#"{"type":"Insert","value":"x"}"#.utf8)), "type 은 소문자")
        XCTAssertThrowsError(try dec.decode(MacroStep.self, from: Data(#"{"value":"x"}"#.utf8)))
        XCTAssertThrowsError(try dec.decode(MacroStep.self, from: Data(#"{"type":"insert","value":1}"#.utf8)))
        XCTAssertThrowsError(try dec.decode(Macro.self, from: Data(#"{"id":"not-a-uuid","name":"x","steps":[],"created":"2026-01-01T00:00:00Z"}"#.utf8)))
        XCTAssertThrowsError(try dec.decode(Macro.self, from: Data(#"{"id":"00000000-0000-0000-0000-000000000000","name":"x","steps":[],"created":"yesterday"}"#.utf8)))
        let ok = try dec.decode(Macro.self, from: Data(#"{"id":"00000000-0000-0000-0000-000000000000","name":"x","steps":[],"created":"2026-01-01T00:00:00Z"}"#.utf8))
        XCTAssertEqual(ok.steps, [])
    }

    func testTenThousandStepsEncodeDecodeUnderASecond() throws {
        let steps = (0..<10_000).map { i -> MacroStep in
            switch i % 4 {
            case 0: return .insert("한글 입력 \(i) 🙂")
            case 1: return .command("moveRight:")
            case 2: return .tool("upper")
            default: return .find("needle\(i)")
            }
        }
        let m = Macro(name: "big", steps: steps)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let t0 = CFAbsoluteTimeGetCurrent()
        let data = try enc.encode(m)
        let t1 = CFAbsoluteTimeGetCurrent()
        let back = try dec.decode(Macro.self, from: data)
        let t2 = CFAbsoluteTimeGetCurrent()
        print(String(format: "QA macro 10k steps: encode %.0f ms (%.0f KB), decode %.0f ms", (t1 - t0) * 1000, Double(data.count) / 1024, (t2 - t1) * 1000))
        XCTAssertEqual(back, m)
        XCTAssertLessThan(t1 - t0, 1.0); XCTAssertLessThan(t2 - t1, 1.0)
    }

    func testRecordingCoalescingEdgeCases() {
        var r = MacroRecording()
        r.append(.insert("")); XCTAssertEqual(r.steps, [.insert("")], "빈 입력도 단계 — 재생 시 무해")
        r.append(.insert("ㅎ")); r.append(.insert("\u{1161}"))
        XCTAssertEqual(r.steps, [.insert("ㅎ\u{1161}")])
        r.append(.find("")); r.append(.find(""))
        XCTAssertEqual(r.steps.count, 3, "find 는 합치지 않는다")
    }
}

@MainActor
final class QA_MacroStoreTests: XCTestCase {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("he-qa-macro-\(UUID().uuidString)", isDirectory: true)
    }

    func testTenThousandStepMacroPersistsAndReloads() throws {
        let dir = tempDir()
        let s = MacroStore(directory: dir)
        let steps = (0..<10_000).map { MacroStep.insert("x\($0)") }
        let t0 = CFAbsoluteTimeGetCurrent()
        s.setLastRecorded(Macro(name: "", steps: steps))
        let saved = s.save(Macro(name: "", steps: steps), name: "big")
        let again = MacroStore(directory: dir)
        let dt = CFAbsoluteTimeGetCurrent() - t0
        print(String(format: "QA macro store 2×10k steps save+reload %.0f ms", dt * 1000))
        XCTAssertEqual(s.lastRecorded?.steps.count, 10_000)
        XCTAssertNil(again.lastRecorded, "마지막 기록은 메모리에만 (디스크에 쓰지 않는다)")
        XCTAssertEqual(again.macros, [saved])
        XCTAssertLessThan(dt, 3.0)
    }

    func testCorruptFileKeepsMemoryAndNextSaveOverwrites() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("macros.json")
        try Data("{ \"macros\": [ broken".utf8).write(to: url)
        let s = MacroStore(directory: dir)
        XCTAssertNotNil(s.loadError)
        s.save(Macro(name: "", steps: [.insert("a")]), name: "n")
        s.reload()
        XCTAssertNil(s.loadError, "저장이 깨진 파일을 덮어쓴다")
        XCTAssertEqual(s.macros.map(\.name), ["n"])
        try Data(#"{"macros":[]}"#.utf8).write(to: url); s.reload()
        XCTAssertNil(s.loadError, "lastRecorded 생략 가능")
        XCTAssertTrue(s.macros.isEmpty)
        try Data(#"{"lastRecorded":null}"#.utf8).write(to: url); s.reload()
        XCTAssertNotNil(s.loadError, "macros 키는 필수")
    }

    func testFallbackNamesUseCountAndCanRepeatAfterDelete() {
        // 알려진 제한: 빈 이름은 `Macro N` (N = 현재 개수 + 1) 이라 삭제 뒤 같은 이름이 다시 나올 수 있다 (id 는 다르므로 동작엔 문제 없음)
        let s = MacroStore(directory: tempDir())
        let m = Macro(name: "", steps: [.insert("a")])
        let a = s.save(m, name: ""); let b = s.save(m, name: "   ")
        XCTAssertEqual([a.name, b.name], ["Macro 1", "Macro 2"])
        s.delete(id: a.id)
        XCTAssertEqual(s.save(m, name: "").name, "Macro 2")
        XCTAssertEqual(s.macros.map(\.name), ["Macro 2", "Macro 2"])
        XCTAssertEqual(Set(s.macros.map(\.id)).count, 2)
    }
}
