import Foundation

/// 사용자 정의 문법 — `~/Library/Application Support/HyperEdit/grammars/*.json` 을 `CodeLanguage` 로 바꿔 `CodeGrammar` 로 쓴다.
/// `GrammarRegistry` 가 내장 문법보다 먼저 여기서 찾으므로 내장 언어의 확장자를 덮어쓸 수 있다(`.py` 에 다른 키워드 집합 등).
/// 잘못된 파일은 `problems` 에 파일명·이유를 남기고 건너뛴다. 첫 로드 때 폴더가 없으면 만들고 `example.json`(확장자 `.example` 용 작은 언어)과
/// `README.md`(스키마 설명)를 써 둔다. 앱은 시작할 때와 문법 다시 읽기 메뉴(GrammarUI.swift)에서 `load(directory:)` 를 부른다.
///
/// 스키마 (모두 선택이지만 `name` 과 `extensions`/`filenames` 중 하나는 필수):
/// ```json
/// { "name": "MyLang", "extensions": ["foo"], "filenames": ["Foofile"], "mode": "code|markup|css|data|shell",
///   "lineComments": ["#"], "blockComment": ["/*", "*/"], "strings": ["\"", "'"], "multilineStrings": ["\"\"\""],
///   "keywords": [], "types": [], "constants": [], "builtins": [], "caseInsensitive": false }
/// ```
public final class UserGrammarStore: @unchecked Sendable {
    /// 앱 전체가 쓰는 저장소. 시작할 때 `load(directory:)` 전에는 비어 있다 (테스트는 자기 저장소를 만든다).
    public static let shared = UserGrammarStore()

    /// 건너뛴 파일과 이유 (출력 로그용)
    public struct Problem: Equatable, Sendable {
        public let file: String
        public let message: String
    }

    private let lock = NSLock()
    private var languages: [CodeLanguage] = []
    private var byExtension: [String: CodeLanguage] = [:]
    private var byFilename: [String: CodeLanguage] = [:]
    private var byName: [String: CodeLanguage] = [:]
    private var loadProblems: [Problem] = []
    private var loadedDirectory: URL?

    public init() {}

    /// 기본 폴더 `~/Library/Application Support/HyperEdit/grammars`
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyperEdit/grammars", isDirectory: true)
    }

    /// 마지막으로 읽은 폴더
    public var directory: URL? { lock.lock(); defer { lock.unlock() }; return loadedDirectory }
    /// 읽은 문법 (이름순)
    public var grammars: [CodeLanguage] { lock.lock(); defer { lock.unlock() }; return languages }
    public var count: Int { lock.lock(); defer { lock.unlock() }; return languages.count }
    public var problems: [Problem] { lock.lock(); defer { lock.unlock() }; return loadProblems }

    /// 폴더의 `*.json` 을 (다시) 읽는다. 폴더가 없으면 만들고 예제·README 를 써 둔다. 같은 확장자를 여러 파일이 쓰면 파일 이름순으로 뒤의 것이 이긴다. 반환: 읽은 문법 수
    @discardableResult
    public func load(directory: URL) -> Int {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: directory.path, isDirectory: &isDir) {
            try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            try? Data(Self.exampleJSON.utf8).write(to: directory.appendingPathComponent("example.json"), options: [.atomic])
            try? Data(Self.readme.utf8).write(to: directory.appendingPathComponent("README.md"), options: [.atomic])
        }
        var langs: [CodeLanguage] = []
        var problems: [Problem] = []
        let files = ((try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        for f in files {
            do {
                let data = try Data(contentsOf: f)
                langs.append(try Self.decode(data, fileName: f.lastPathComponent))
            } catch let e as UserGrammarError {
                problems.append(Problem(file: f.lastPathComponent, message: e.message))
            } catch {
                problems.append(Problem(file: f.lastPathComponent, message: error.localizedDescription))
            }
        }
        var ext: [String: CodeLanguage] = [:], names: [String: CodeLanguage] = [:], fnames: [String: CodeLanguage] = [:]
        for l in langs {
            for e in l.userExtensions { ext[e] = l }
            for n in l.userFilenames { fnames[n] = l }
            names[l.name.lowercased()] = l
        }
        lock.lock()
        languages = langs.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        byExtension = ext; byFilename = fnames; byName = names
        loadProblems = problems
        loadedDirectory = directory
        lock.unlock()
        return langs.count
    }

    /// 전부 비운다 (테스트용)
    public func clear() {
        lock.lock(); defer { lock.unlock() }
        languages = []; byExtension = [:]; byFilename = [:]; byName = [:]; loadProblems = []; loadedDirectory = nil
    }

    /// 파일 이름(대소문자 무시) → 확장자 순으로 찾는다
    public func grammar(for url: URL) -> CodeGrammar? {
        lock.lock(); defer { lock.unlock() }
        guard !languages.isEmpty else { return nil }
        if let l = byFilename[url.lastPathComponent.lowercased()] { return CodeGrammar(language: l) }
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty, let l = byExtension[ext] else { return nil }
        return CodeGrammar(language: l)
    }

    public func grammar(forExtension ext: String) -> CodeGrammar? {
        lock.lock(); defer { lock.unlock() }
        guard let l = byExtension[ext.lowercased()] else { return nil }
        return CodeGrammar(language: l)
    }

    /// 펜스 정보 문자열 → 이름 또는 확장자가 일치하는 사용자 문법
    public func grammar(forFenceLanguage key: String) -> CodeGrammar? {
        lock.lock(); defer { lock.unlock() }
        guard !languages.isEmpty else { return nil }
        let k = key.lowercased()
        if let l = byName[k] ?? byExtension[k] { return CodeGrammar(language: l) }
        return nil
    }

    // MARK: - 디코딩

    /// JSON 파일 내용 → 언어 정의 (주석·뒤따르는 쉼표 허용). 스키마 위반은 `UserGrammarError`.
    public static func decode(_ data: Data, fileName: String) throws -> CodeLanguage {
        guard let text = String(data: data, encoding: .utf8) else { throw UserGrammarError.notUTF8 }
        let strict: String
        do { strict = try JSONFormatter.minify(text) }
        catch let e as JSONFormatter.SyntaxError { throw UserGrammarError.syntax(line: e.line, column: e.column, detail: e.message) }
        let file: UserGrammarFile
        do { file = try JSONDecoder().decode(UserGrammarFile.self, from: Data(strict.utf8)) }
        catch { throw UserGrammarError.notAnObject(error.localizedDescription) }
        return try file.language()
    }

    // MARK: - 예제 · README (첫 로드 때 폴더에 쓴다)

    public static let exampleJSON = """
    {
      // HyperEdit user grammar for files named *.example — see README.md next to this file.
      // Comments and trailing commas are allowed. Reload with File › Reload Grammars.
      "name": "Example",
      "extensions": ["example"],
      "filenames": ["Examplefile"],
      "mode": "code",
      "lineComments": ["#"],
      "blockComment": ["/*", "*/"],
      "strings": ["\\"", "'"],
      "multilineStrings": ["\\"\\"\\""],
      "keywords": ["let", "fn", "if", "else", "for", "in", "while", "return", "import"],
      "types": ["Int", "String", "Bool", "List"],
      "constants": ["true", "false", "nil"],
      "builtins": ["print", "len", "range"],
      "caseInsensitive": false
    }

    """

    public static let readme = """
    # HyperEdit user grammars

    Every `*.json` file in this folder defines one syntax-coloring language. HyperEdit reads the folder
    when it starts and when you choose **File › Reload Grammars**. Files that fail to parse are skipped and
    the reason is written to the Output panel (⌘2 › Output). Comments and trailing commas are allowed in the JSON.

    A grammar is matched to a file by its extension (`extensions`) or its exact file name (`filenames`).
    User grammars take precedence over the built-in ones, so you can override, say, `.py` with your own keyword set.
    When two files claim the same extension, the one later in file-name order wins.

    ## Schema

    | Key | Type | Required | Meaning |
    |---|---|---|---|
    | `name` | string | yes | Language name shown in the status bar. Also matches a Markdown fence info string (```` ```name ````). |
    | `extensions` | [string] | one of extensions / filenames | File extensions without the dot, case-insensitive. |
    | `filenames` | [string] | one of extensions / filenames | Exact file names (`Makefile`, `.myrc`), case-insensitive. |
    | `mode` | string | no (`code`) | Scanner mode: `code` (default), `markup` (HTML/XML tags, `<!-- -->`), `css`, `data` (JSON/YAML-like `key:` values), `shell` (command position, `$VAR`, `--flags`). |
    | `lineComments` | [string] | no | Line comment starters, e.g. `["#"]`, `["//", "--"]`. The first one is used by Toggle Comment (⌘/). |
    | `blockComment` | [open, close] | no | Block comment delimiters, e.g. `["/*", "*/"]`. May span lines. Used by ⌘/ when there is no line comment. |
    | `strings` | [string] | no (`"` and `'`) | Single-character string quotes. Backslash escapes are honored. `[]` means no strings. |
    | `multilineStrings` | [string] | no | Delimiters that open and close a string spanning lines, e.g. `["\\"\\"\\""]`, `["`"]`. |
    | `keywords` | [string] | no | Colored as keywords. |
    | `types` | [string] | no | Colored as types. |
    | `constants` | [string] | no | Colored as constants (`true`, `null`, …). |
    | `builtins` | [string] | no | Colored as functions (built-in functions or commands). |
    | `caseInsensitive` | bool | no (`false`) | Match the word lists ignoring case (SQL-like languages). |

    Other things are colored by the shared scanner regardless of the grammar: numbers, operators, punctuation,
    identifiers followed by `(` (function), capitalized identifiers (type / constant), `@attribute`.
    Colors come from the current theme's `syntax` palette.

    ## Example

    `example.json` in this folder defines a small language for `*.example` files:

    ```json
    {
      "name": "Example",
      "extensions": ["example"],
      "lineComments": ["#"],
      "blockComment": ["/*", "*/"],
      "strings": ["\\"", "'"],
      "multilineStrings": ["\\"\\"\\""],
      "keywords": ["let", "fn", "if", "else", "return"],
      "types": ["Int", "String"],
      "constants": ["true", "false", "nil"],
      "builtins": ["print"]
    }
    ```

    Create `test.example`, open it in HyperEdit and the status bar shows "Example".

    """
}

/// 문법 파일을 읽지 못한 이유. `message` 는 출력 로그용(현지화).
public enum UserGrammarError: Error, Equatable {
    case notUTF8
    case syntax(line: Int, column: Int, detail: String)
    case notAnObject(String)
    case missingName
    case missingExtensions
    case badMode(String)
    case badBlockComment
    case badStringDelimiter(String)
    case tooManyMultilineStrings

    public var message: String {
        switch self {
        case .notUTF8: return String(localized: "not UTF-8 text", bundle: .module)
        case .syntax(let line, let column, let detail): return String(localized: "line \(line) column \(column): \(detail)", bundle: .module)
        case .notAnObject(let detail): return String(localized: "not a grammar object: \(detail)", bundle: .module)
        case .missingName: return String(localized: "'name' is required", bundle: .module)
        case .missingExtensions: return String(localized: "'extensions' or 'filenames' is required", bundle: .module)
        case .badMode(let mode): return String(localized: "'mode' must be one of code, markup, css, data, shell (got '\(mode)')", bundle: .module)
        case .badBlockComment: return String(localized: "'blockComment' must be [open, close]", bundle: .module)
        case .badStringDelimiter(let s): return String(localized: "'strings' entries must be a single character (got '\(s)')", bundle: .module)
        case .tooManyMultilineStrings: return String(localized: "'multilineStrings' has too many entries (max 127)", bundle: .module)
        }
    }
}

/// JSON 파일 모양 그대로의 디코딩용 구조체
struct UserGrammarFile: Decodable {
    var name: String?
    var extensions: [String]?
    var filenames: [String]?
    var mode: String?
    var lineComments: [String]?
    var blockComment: [String]?
    var strings: [String]?
    var multilineStrings: [String]?
    var keywords: [String]?
    var types: [String]?
    var constants: [String]?
    var builtins: [String]?
    var caseInsensitive: Bool?

    /// 검증 + `CodeLanguage` 변환
    func language() throws -> CodeLanguage {
        guard let name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { throw UserGrammarError.missingName }
        let exts = (extensions ?? []).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }.filter { !$0.isEmpty }
        let fnames = (filenames ?? []).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }
        guard !exts.isEmpty || !fnames.isEmpty else { throw UserGrammarError.missingExtensions }
        var l = CodeLanguage(id: "user." + name.lowercased(), name: name)
        switch (mode ?? "code").lowercased() {
        case "code": l.mode = .code
        case "markup": l.mode = .markup
        case "css": l.mode = .css; l.identifierDash = true
        case "data": l.mode = .data; l.keyBeforeColon = true
        case "shell": l.mode = .shell; l.commandPosition = true; l.dollarVariable = true; l.dashFlags = true
        default: throw UserGrammarError.badMode(mode ?? "")
        }
        l.lineComments = (lineComments ?? []).filter { !$0.isEmpty }.map(CodeLanguage.u)
        if let bc = blockComment, !bc.isEmpty {
            guard bc.count == 2, !bc[0].isEmpty, !bc[1].isEmpty else { throw UserGrammarError.badBlockComment }
            l.blockComment = (CodeLanguage.u(bc[0]), CodeLanguage.u(bc[1]))
        }
        if let qs = strings {
            var set = Set<unichar>()
            for q in qs {
                let units = Array(q.utf16)
                guard units.count == 1 else { throw UserGrammarError.badStringDelimiter(q) }
                set.insert(units[0])
            }
            l.quotes = set
        }
        l.multilineStrings = (multilineStrings ?? []).filter { !$0.isEmpty }.map(CodeLanguage.u)
        guard l.multilineStrings.count <= 127 else { throw UserGrammarError.tooManyMultilineStrings }
        l.caseInsensitive = caseInsensitive ?? false
        func words(_ a: [String]?) -> Set<String> {
            Set((a ?? []).map { l.caseInsensitive ? $0.lowercased() : $0 }.filter { !$0.isEmpty })
        }
        l.keywords = words(keywords)
        l.types = words(types)
        l.constants = words(constants)
        l.builtins = words(builtins)
        l.userExtensions = exts
        l.userFilenames = fnames
        return l
    }
}

public extension CodeLanguage {
    /// 사용자 정의 문법인가 (`UserGrammarStore` 가 만든 정의)
    var isUserDefined: Bool { id.hasPrefix("user.") }
}
