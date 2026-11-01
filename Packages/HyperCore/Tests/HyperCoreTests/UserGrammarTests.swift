import XCTest
@testable import HyperCore

/// 사용자 정의 문법: JSON 디코드·검증·오류 처리, 폴더 부트스트랩(example.json·README), 확장자 덮어쓰기, 주석 토글 연동, 펜스 언어 매칭
final class UserGrammarTests: XCTestCase {
    private func tok(_ g: any LanguageGrammar, _ line: String) -> [String] {
        let ns = line as NSString
        return g.tokens(in: line).map { "\(ns.substring(with: $0.range)):\($0.kind.rawValue)" }
    }

    private func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("hypercore-grammars-\(UUID().uuidString.prefix(8))", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: d) }
        return d
    }

    func testDecodeFullSchema() throws {
        let json = """
        {
          // comment allowed
          "name": "MyLang", "extensions": [".foo", "FOO2"], "filenames": ["Foofile"], "mode": "code",
          "lineComments": ["#", "--"], "blockComment": ["(*", "*)"], "strings": ["\\""], "multilineStrings": ["'''"],
          "keywords": ["let", "fn"], "types": ["Int"], "constants": ["nil"], "builtins": ["print"], "caseInsensitive": false,
        }
        """
        let l = try UserGrammarStore.decode(Data(json.utf8), fileName: "mylang.json")
        XCTAssertEqual(l.name, "MyLang")
        XCTAssertEqual(l.id, "user.mylang")
        XCTAssertTrue(l.isUserDefined)
        XCTAssertEqual(l.userExtensions, ["foo", "foo2"])
        XCTAssertEqual(l.userFilenames, ["foofile"])
        XCTAssertEqual(l.lineComments.count, 2)
        XCTAssertEqual(l.blockComment.map { String(utf16CodeUnits: $0.start, count: 2) }, "(*")
        XCTAssertEqual(l.quotes, [0x22])
        XCTAssertEqual(l.multilineStrings.count, 1)
        XCTAssertTrue(l.tracksLineState)
        let g = CodeGrammar(language: l)
        XCTAssertEqual(g.name, "MyLang")
        XCTAssertEqual(tok(g, "let x: Int = print(\"a\") -- c"), ["let:keyword", "::operator", "Int:type", "=:operator", "print:function", "(:punctuation", "\"a\":string", "):punctuation", "-- c:comment"])
        XCTAssertEqual(tok(g, "fn f() (* open"), ["fn:keyword", "f:function", "(:punctuation", "):punctuation", "(* open:comment"])
        XCTAssertEqual(g.scanLines(in: "x = '''a\nb''' nil").map(\.exiting), [.string(1), .normal])
        XCTAssertEqual(tok(g, "s = 'single' x"), ["=:operator"], "`'` 는 따옴표 집합에 없으므로 문자열이 아니다")
        XCTAssertEqual(g.scanLines(in: "a (* multi\nline *) nil").map(\.exiting), [.blockComment, .normal])
    }

    func testDefaultsAndModes() throws {
        let minimal = try UserGrammarStore.decode(Data("{\"name\": \"Min\", \"extensions\": [\"mn\"]}".utf8), fileName: "min.json")
        XCTAssertEqual(minimal.quotes, [0x22, 0x27], "strings 생략 → 기본 따옴표")
        XCTAssertEqual(minimal.mode, .code)
        XCTAssertFalse(minimal.tracksLineState)
        let noStrings = try UserGrammarStore.decode(Data("{\"name\": \"NS\", \"extensions\": [\"ns\"], \"strings\": []}".utf8), fileName: "ns.json")
        XCTAssertTrue(noStrings.quotes.isEmpty)
        let data = try UserGrammarStore.decode(Data("{\"name\": \"Cfg\", \"filenames\": [\"Cfgfile\"], \"mode\": \"data\", \"lineComments\": [\";\"]}".utf8), fileName: "cfg.json")
        XCTAssertEqual(data.mode, .data)
        XCTAssertTrue(data.keyBeforeColon)
        XCTAssertEqual(tok(CodeGrammar(language: data), "name: value ; c"), ["name:property", "::operator", "; c:comment"])
        let shell = try UserGrammarStore.decode(Data("{\"name\": \"Sh\", \"extensions\": [\"xsh\"], \"mode\": \"shell\", \"keywords\": [\"if\"]}".utf8), fileName: "sh.json")
        XCTAssertTrue(shell.commandPosition && shell.dollarVariable && shell.dashFlags)
        XCTAssertEqual(tok(CodeGrammar(language: shell), "run --fast $X"), ["run:function", "--fast:attribute", "$X:variable"])
        let markup = try UserGrammarStore.decode(Data("{\"name\": \"Mk\", \"extensions\": [\"mk\"], \"mode\": \"markup\"}".utf8), fileName: "mk.json")
        XCTAssertTrue(markup.tracksLineState)
        XCTAssertEqual(CodeGrammar(language: markup).scanLines(in: "<a><!-- x\n--><b>").map(\.exiting), [.blockComment, .normal])
        let ci = try UserGrammarStore.decode(Data("{\"name\": \"CI\", \"extensions\": [\"ci\"], \"caseInsensitive\": true, \"keywords\": [\"SELECT\"], \"types\": [\"Int\"]}".utf8), fileName: "ci.json")
        XCTAssertEqual(tok(CodeGrammar(language: ci), "select INT"), ["select:keyword", "INT:type"])
    }

    func testValidationErrors() {
        func failure(_ json: String) -> UserGrammarError? {
            do { _ = try UserGrammarStore.decode(Data(json.utf8), fileName: "x.json"); return nil }
            catch let e as UserGrammarError { return e }
            catch { XCTFail("unexpected error \(error)"); return nil }
        }
        XCTAssertEqual(failure("{\"extensions\": [\"a\"]}"), .missingName)
        XCTAssertEqual(failure("{\"name\": \" \", \"extensions\": [\"a\"]}"), .missingName)
        XCTAssertEqual(failure("{\"name\": \"A\"}"), .missingExtensions)
        XCTAssertEqual(failure("{\"name\": \"A\", \"extensions\": [\"\", \" \"]}"), .missingExtensions)
        XCTAssertEqual(failure("{\"name\": \"A\", \"extensions\": [\"a\"], \"mode\": \"prose\"}"), .badMode("prose"))
        XCTAssertEqual(failure("{\"name\": \"A\", \"extensions\": [\"a\"], \"blockComment\": [\"/*\"]}"), .badBlockComment)
        XCTAssertEqual(failure("{\"name\": \"A\", \"extensions\": [\"a\"], \"strings\": [\"''\"]}"), .badStringDelimiter("''"))
        if case .notAnObject = failure("{\"name\": \"A\", \"extensions\": [\"a\"], \"keywords\": \"let\"}") {} else { XCTFail("type mismatch should be notAnObject") }
        if case .syntax(let line, let column, _)? = failure("{\"name\": \"A\",\n \"extensions\": [\"a\"") { XCTAssertEqual(line, 2); XCTAssertGreaterThan(column, 0) } else { XCTFail("truncated JSON should be a syntax error") }
        if case .notAnObject = failure("[1, 2]") {} else { XCTFail("array should be notAnObject") }
        XCTAssertNil(failure("{\"name\": \"A\", \"extensions\": [\"a\"], \"blockComment\": []}"), "빈 blockComment 는 없음과 같다")
        // 메시지는 현지화되지만 키 이름은 그대로 남는다 (출력 로그에서 어느 키인지 알 수 있게)
        XCTAssertTrue(UserGrammarError.missingName.message.contains("'name'"))
        XCTAssertTrue(UserGrammarError.badMode("x").message.contains("'mode'") && UserGrammarError.badMode("x").message.contains("'x'"))
        XCTAssertTrue(UserGrammarError.syntax(line: 3, column: 7, detail: "d").message.contains("3") && UserGrammarError.syntax(line: 3, column: 7, detail: "d").message.contains("7"))
    }

    func testLoadCreatesFolderWithExampleAndReadme() {
        let dir = tempDir()
        let store = UserGrammarStore()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
        let n = store.load(directory: dir)
        XCTAssertEqual(n, 1, "example.json 이 읽힌다")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("example.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("README.md").path))
        XCTAssertEqual(store.problems, [])
        XCTAssertEqual(store.grammars.map(\.name), ["Example"])
        XCTAssertEqual(store.directory, dir)
        let g = GrammarRegistry.grammar(for: URL(fileURLWithPath: "/tmp/x/test.example"), userGrammars: store)
        XCTAssertEqual(g.name, "Example")
        XCTAssertEqual(tok(g, "fn main() { print(\"hi\") } # c"), ["fn:keyword", "main:function", "(:punctuation", "):punctuation", "{:punctuation", "print:function", "(:punctuation", "\"hi\":string", "):punctuation", "}:punctuation", "# c:comment"])
        XCTAssertEqual(GrammarRegistry.grammar(for: URL(fileURLWithPath: "/tmp/Examplefile"), userGrammars: store).name, "Example", "filenames 매칭")
        XCTAssertEqual(GrammarRegistry.grammar(for: URL(fileURLWithPath: "/tmp/EXAMPLEFILE"), userGrammars: store).name, "Example", "대소문자 무시")
        XCTAssertEqual(GrammarRegistry.grammar(for: URL(fileURLWithPath: "/tmp/x.swift"), userGrammars: store).name, "Swift", "내장은 그대로")
        // README 가 스키마 키를 전부 설명한다
        let readme = (try? String(contentsOf: dir.appendingPathComponent("README.md"), encoding: .utf8)) ?? ""
        for key in ["name", "extensions", "filenames", "mode", "lineComments", "blockComment", "strings", "multilineStrings", "keywords", "types", "constants", "builtins", "caseInsensitive"] {
            XCTAssertTrue(readme.contains("`\(key)`"), "README mentions \(key)")
        }
        // 두 번째 로드는 예제를 다시 쓰지 않는다 (사용자가 지웠으면 그대로)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("example.json"))
        XCTAssertEqual(store.load(directory: dir), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("example.json").path))
        XCTAssertNil(store.grammar(for: URL(fileURLWithPath: "/tmp/x/test.example")))
    }

    func testOverrideBuiltinAndSkipBrokenFiles() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)   // 폴더가 이미 있으면 예제를 쓰지 않는다
        try """
        { "name": "MyPython", "extensions": ["py"], "lineComments": ["#"], "keywords": ["def"], "builtins": ["print"] }
        """.write(to: dir.appendingPathComponent("a-python.json"), atomically: true, encoding: .utf8)
        try "{ \"name\": \"Broken\", \"extensions\": [\"b\"] ".write(to: dir.appendingPathComponent("broken.json"), atomically: true, encoding: .utf8)
        try "{ \"extensions\": [\"c\"] }".write(to: dir.appendingPathComponent("noname.json"), atomically: true, encoding: .utf8)
        try "not json".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)   // json 이 아니면 무시
        let store = UserGrammarStore()
        XCTAssertEqual(store.load(directory: dir), 1)
        XCTAssertEqual(store.problems.map(\.file), ["broken.json", "noname.json"])
        XCTAssertTrue(store.problems[0].message.rangeOfCharacter(from: .decimalDigits) != nil, "syntax error carries line/column: \(store.problems[0].message)")
        XCTAssertTrue(store.problems[1].message.contains("'name'"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("example.json").path))
        let g = GrammarRegistry.grammar(for: URL(fileURLWithPath: "/p/x.py"), userGrammars: store)
        XCTAssertEqual(g.name, "MyPython", "내장 Python 을 덮어쓴다")
        XCTAssertEqual(tok(g, "def f(): return print"), ["def:keyword", "f:function", "(:punctuation", "):punctuation", "::operator", "print:function"], "내장 Python 의 return 키워드는 더 이상 없다")
        XCTAssertEqual(GrammarRegistry.languageName(for: URL(fileURLWithPath: "/p/x.PY"), userGrammars: store), "MyPython")
        XCTAssertEqual(GrammarRegistry.grammar(forExtension: "py", userGrammars: store).name, "MyPython")
        XCTAssertEqual(GrammarRegistry.builtinGrammar(forExtension: "py").name, "Python")
        // 비어 있는 공용 저장소는 내장만 돌려준다
        XCTAssertEqual(GrammarRegistry.grammar(for: URL(fileURLWithPath: "/p/x.py"), userGrammars: UserGrammarStore()).name, "Python")
    }

    func testLaterFileWinsForSameExtension() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{ \"name\": \"First\", \"extensions\": [\"dup\"] }".write(to: dir.appendingPathComponent("1-first.json"), atomically: true, encoding: .utf8)
        try "{ \"name\": \"Second\", \"extensions\": [\"dup\"] }".write(to: dir.appendingPathComponent("2-second.json"), atomically: true, encoding: .utf8)
        let store = UserGrammarStore()
        XCTAssertEqual(store.load(directory: dir), 2)
        XCTAssertEqual(store.grammar(forExtension: "dup")?.name, "Second")
        XCTAssertEqual(store.grammars.map(\.name), ["First", "Second"])
    }

    func testCommentRegistryUsesUserGrammar() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{ \"name\": \"L1\", \"extensions\": [\"l1\"], \"lineComments\": [\";;\"], \"blockComment\": [\"(*\", \"*)\"] }".write(to: dir.appendingPathComponent("l1.json"), atomically: true, encoding: .utf8)
        try "{ \"name\": \"L2\", \"extensions\": [\"l2\"], \"blockComment\": [\"{-\", \"-}\"] }".write(to: dir.appendingPathComponent("l2.json"), atomically: true, encoding: .utf8)
        try "{ \"name\": \"L3\", \"extensions\": [\"l3\"] }".write(to: dir.appendingPathComponent("l3.json"), atomically: true, encoding: .utf8)
        try "{ \"name\": \"MyMD\", \"extensions\": [\"md\"], \"lineComments\": [\"%\"] }".write(to: dir.appendingPathComponent("md.json"), atomically: true, encoding: .utf8)
        let store = UserGrammarStore()
        XCTAssertEqual(store.load(directory: dir), 4)
        let s1 = CommentRegistry.syntax(for: URL(fileURLWithPath: "/a/x.l1"), userGrammars: store)
        XCTAssertEqual(s1.line, ";;")
        XCTAssertEqual(s1.block?.open, "(*")
        XCTAssertEqual(TextTools.toggleLineComment(lines: ["a", "b"], syntax: s1), [";; a", ";; b"])
        let s2 = CommentRegistry.syntax(for: URL(fileURLWithPath: "/a/x.l2"), userGrammars: store)
        XCTAssertNil(s2.line)
        XCTAssertEqual(TextTools.toggleLineComment(lines: ["a"], syntax: s2), ["{- a -}"])
        XCTAssertFalse(CommentRegistry.syntax(for: URL(fileURLWithPath: "/a/x.l3"), userGrammars: store).isUsable, "주석 기호가 없으면 토글 불가")
        XCTAssertEqual(CommentRegistry.syntax(for: URL(fileURLWithPath: "/a/notes.md"), userGrammars: store).line, "%", "내장 마크다운 주석(<!-- -->)도 덮어쓴다")
        XCTAssertNil(CommentRegistry.syntax(for: URL(fileURLWithPath: "/a/notes.md"), userGrammars: UserGrammarStore()).line)
    }

    func testFenceLanguageMatchesUserGrammarByNameOrExtension() throws {
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "{ \"name\": \"Zig\", \"extensions\": [\"zg\"], \"keywords\": [\"pub\", \"fn\"] }".write(to: dir.appendingPathComponent("zig.json"), atomically: true, encoding: .utf8)
        let store = UserGrammarStore()
        store.load(directory: dir)
        XCTAssertEqual(GrammarRegistry.grammar(forFenceLanguage: "zig", userGrammars: store)?.name, "Zig")
        XCTAssertEqual(GrammarRegistry.grammar(forFenceLanguage: "ZG", userGrammars: store)?.name, "Zig")
        XCTAssertNil(GrammarRegistry.grammar(forFenceLanguage: "zig", userGrammars: UserGrammarStore()))
        XCTAssertEqual(GrammarRegistry.grammar(forFenceLanguage: "python", userGrammars: store)?.name, "Python")
        XCTAssertEqual(GrammarRegistry.grammar(forFenceLanguage: "Swift", userGrammars: store)?.name, "Swift")
        XCTAssertEqual(GrammarRegistry.grammar(forFenceLanguage: "c++", userGrammars: store)?.name, "C++")
        XCTAssertNil(GrammarRegistry.grammar(forFenceLanguage: "md", userGrammars: store), "마크다운 안의 마크다운은 중첩하지 않는다")
        XCTAssertNil(GrammarRegistry.grammar(forFenceLanguage: "mermaid", userGrammars: store))
    }

    func testExampleJSONDecodesAndTracksState() throws {
        let l = try UserGrammarStore.decode(Data(UserGrammarStore.exampleJSON.utf8), fileName: "example.json")
        XCTAssertEqual(l.name, "Example")
        XCTAssertEqual(l.userExtensions, ["example"])
        XCTAssertTrue(l.tracksLineState)
        let g = CodeGrammar(language: l)
        XCTAssertEqual(g.scanLines(in: "let s = \"\"\"a\nb\"\"\" /* c\nd */ fn").map(\.exiting), [.string(1), .blockComment, .normal])
        XCTAssertEqual(l.commentSyntax.line, "#")
    }
}
