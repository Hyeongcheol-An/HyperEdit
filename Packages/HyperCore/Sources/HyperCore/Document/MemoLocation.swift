import Foundation

/// 문서 위치 결정. 우선순위: `--file <path>` 인자 → 마지막으로 연 텍스트 파일 → 기본 문서(`~/Documents/HyperEdit/notes.md`, 없으면 환영 문서로 생성).
/// 로컬 파일만 다룬다 (iCloud 연동 없음).
public enum MemoLocation {
    public static let pathKey = "hyperedit.memo.path"

    /// 기본 문서 폴더: macOS `~/Documents/HyperEdit`, iOS 앱 Documents/HyperEdit
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyperEdit", isDirectory: true)
    }

    public static var defaultLocalURL: URL { defaultDirectory.appendingPathComponent("notes.md") }

    public static func resolveDefault(arguments: [String] = CommandLine.arguments, defaults: UserDefaults = AppDefaults.store) -> URL {
        if let i = arguments.firstIndex(of: "--file"), i + 1 < arguments.count {
            return URL(fileURLWithPath: arguments[i + 1]).standardizedFileURL
        }
        // 마지막으로 연 파일 — 지워졌거나 텍스트가 아니면(이미지 등) 무시하고 기본 문서로
        if let p = defaults.string(forKey: pathKey) {
            let u = URL(fileURLWithPath: p)
            if FileManager.default.fileExists(atPath: p), TextFileDetector.isLikelyText(u) { return u }
        }
        ensureDefaultDocument()
        return defaultLocalURL
    }

    public static func remember(_ url: URL, defaults: UserDefaults = AppDefaults.store) {
        defaults.set(url.path, forKey: pathKey)
    }

    /// 기본 문서가 없으면 환영 문서를 만든다. 이미 있으면 아무것도 하지 않는다 (사용자 파일을 덮어쓰지 않음).
    @discardableResult
    public static func ensureDefaultDocument(fileManager fm: FileManager = .default) -> Bool {
        let url = defaultLocalURL
        guard !fm.fileExists(atPath: url.path) else { return false }
        try? fm.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)
        return fm.createFile(atPath: url.path, contents: WelcomeDocument.text.data(using: .utf8))
    }
}

/// 첫 실행 때 기본 문서에 들어가는 안내문. 언어별 파일 `Resources/Welcome/welcome.<code>.md` 에서 UI 언어에 맞는 것을 고른다 (없으면 영어).
public enum WelcomeDocument {
    /// 안내문이 있는 언어 코드 (파일 이름의 `welcome.<code>.md`)
    public static var availableLanguages: [String] {
        guard let dir = Bundle.module.url(forResource: "Welcome", withExtension: nil),
              let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return files.compactMap { name -> String? in
            guard name.hasPrefix("welcome."), name.hasSuffix(".md") else { return nil }
            return String(name.dropFirst("welcome.".count).dropLast(".md".count))
        }.sorted()
    }

    /// 우선 언어 목록(기본: 이 프로세스의 언어 설정)에 맞는 안내문. 번들과 같은 규칙(Bundle.preferredLocalizations)으로 고르고 없으면 영어.
    public static func text(for preferred: [String] = Locale.preferredLanguages) -> String {
        let codes = availableLanguages
        var code = "en"
        if !codes.isEmpty, let hit = Bundle.preferredLocalizations(from: codes, forPreferences: preferred).first, codes.contains(hit) { code = hit }
        if let url = Bundle.module.url(forResource: "Welcome", withExtension: nil)?.appendingPathComponent("welcome.\(code).md"),
           let s = try? String(contentsOf: url, encoding: .utf8), !s.isEmpty { return s }
        return fallback
    }

    public static var text: String { text() }

    /// 리소스를 읽지 못했을 때의 최소 안내문
    static let fallback = """
    # Welcome to HyperEdit

    HyperEdit is a fast plain-text editor built around one big notes file that you keep appending to.
    Press ⌘, for Settings, ⌘F to find, F7 to insert a timestamp heading. Delete this text and start writing.

    """
}
