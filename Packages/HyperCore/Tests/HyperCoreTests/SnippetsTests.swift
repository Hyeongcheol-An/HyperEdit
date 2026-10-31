import XCTest
@testable import HyperCore

final class SnippetTemplateTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_793_000_000)   // 2026-10-26 (월) 07:33 (UTC)
    private let utc = TimeZone(identifier: "UTC")!
    private let ko = Locale(identifier: "ko_KR")

    func testVariables() {
        let r = SnippetTemplate.render("${date} ${time} ${datetime} [${selection}] <${clipboard}> ${filename} ${unknown}",
                                       now: date, selection: "sel", clipboard: "clip", filename: "notes.md", locale: ko, timeZone: utc)
        XCTAssertEqual(r.text, "2026-10-26 07:33 2026-10-26 (월) 07:33 [sel] <clip> notes.md ${unknown}")
        XCTAssertTrue(r.tabstops.isEmpty)
        XCTAssertNil(r.final)
    }

    func testNumberedTabstopsWithPlaceholdersAndOrder() {
        let r = SnippetTemplate.render("[${2:url}]($1)$0 x")
        XCTAssertEqual(r.text, "[url]() x")
        XCTAssertEqual(r.tabstops, [[NSRange(location: 6, length: 0)], [NSRange(location: 1, length: 3)]], "번호 순(1, 2) — 본문 등장 순서가 아니다")
        XCTAssertEqual(r.final, 7)
    }

    func testEscaping() {
        let r = SnippetTemplate.render(#"cost \$1 and \\ and $$1"#)
        XCTAssertEqual(r.text, #"cost $1 and \ and $"#)
        XCTAssertEqual(r.tabstops, [[NSRange(location: 19, length: 0)]], "`$$1` 은 글자 $ 뒤에 탭스톱 1")
        XCTAssertEqual(SnippetTemplate.render("$").text, "$", "끝의 외톨이 $ 는 그대로")
        XCTAssertEqual(SnippetTemplate.render("${1:open").text, "${1:open", "닫히지 않은 중괄호는 글자")
    }

    func testMultilineBody() {
        let r = SnippetTemplate.render("```${1:lang}\n$0\n```")
        XCTAssertEqual(r.text, "```lang\n\n```")
        XCTAssertEqual(r.tabstops, [[NSRange(location: 3, length: 4)]])
        XCTAssertEqual(r.final, 8)
    }

    func testSameTabstopTwiceReturnsBothRanges() {
        let r = SnippetTemplate.render("<${1:div}>$0</$1>")
        XCTAssertEqual(r.text, "<div></>")
        XCTAssertEqual(r.tabstops, [[NSRange(location: 1, length: 3), NSRange(location: 7, length: 0)]])
        XCTAssertEqual(r.final, 5)
    }

    func testEmptyPlaceholderAndFinalInBraces() {
        let r = SnippetTemplate.render("a${2:}b${0}c")
        XCTAssertEqual(r.text, "abc")
        XCTAssertEqual(r.tabstops, [[NSRange(location: 1, length: 0)]])
        XCTAssertEqual(r.final, 2)
    }

    func testDefaultSnippetsRender() {
        for s in SnippetStore.defaults {
            let r = SnippetTemplate.render(s.body, now: date, locale: ko, timeZone: utc)
            XCTAssertFalse(r.text.contains("${"), "\(s.trigger): 변수가 남음 → \(r.text)")
        }
        let todo = SnippetTemplate.render(SnippetStore.defaults.first { $0.trigger == "todo" }!.body)
        XCTAssertEqual(todo.text, "- [ ] "); XCTAssertEqual(todo.final, 6)
    }
}

@MainActor
final class SnippetStoreTests: XCTestCase {
    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("he-snip-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func testFirstLoadWritesDefaultsAndRoundTrips() throws {
        let dir = tempDir()
        let store = SnippetStore(directory: dir)
        XCTAssertEqual(store.snippets, SnippetStore.defaults)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("snippets.json").path))
        let text = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("[\n  { \"trigger\": \"date\""), "트리거·제목·본문 순서의 읽기 쉬운 JSON")
        let again = SnippetStore(directory: dir)
        XCTAssertEqual(again.snippets, SnippetStore.defaults)
        XCTAssertEqual(again.snippet(forTrigger: "todo")?.body, "- [ ] $0")
    }

    func testUserEditedFileWithCommentsReloadsOnChange() throws {
        let dir = tempDir()
        let store = SnippetStore(directory: dir)
        try "// my snippets\n[\n  { \"trigger\": \"sig\", \"title\": \"Signature\", \"body\": \"-- HC\" },\n]\n".write(to: store.fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: store.fileURL.path)
        store.reloadIfChanged()
        XCTAssertEqual(store.snippets.map(\.trigger), ["sig"])
        XCTAssertNil(store.lastError)
        try "[ { \"trigger\": \"x\", }".write(to: store.fileURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(10)], ofItemAtPath: store.fileURL.path)
        store.reloadIfChanged()
        XCTAssertEqual(store.snippets.map(\.trigger), ["sig"], "깨진 파일이면 이전 목록 유지")
        XCTAssertNotNil(store.lastError)
    }
}
