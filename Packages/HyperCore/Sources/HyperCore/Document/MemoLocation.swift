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

/// 첫 실행 때 기본 문서에 들어가는 안내문 (영/한)
public enum WelcomeDocument {
    public static let text = """
    # Welcome to HyperEdit · HyperEdit에 오신 것을 환영합니다

    HyperEdit is a fast plain-text editor built around one big notes file that you keep appending to.
    HyperEdit는 계속 길어지는 메모 파일 하나를 빠르게 쓰고 찾기 위한 텍스트 에디터입니다.

    ## Getting started · 시작하기

    - F7 inserts a timestamp heading (타임스탬프 삽입): `## 2026-10-31 (Sat) 09:00`
    - ⌘F find · ⌘R replace · ⇧⌘F find in files (찾기 · 바꾸기 · 파일에서 찾기)
    - ⌘F2 toggles a bookmark, F2 / ⌥F2 jump to the next / previous one (북마크)
    - ⌥C column mode · ⌘-click adds a caret · ⌘D selects the next match (열 모드 · 멀티 커서)
    - ⌘1 left dock (File View / Outline / Timeline) · ⌘2 results panel (좌측 도킹 · 결과 창)
    - Layout tab → Theme: 22 themes; by default the app follows the system light/dark setting (테마)
    - ⌘O opens any text file. This file lives at ~/Documents/HyperEdit/notes.md (이 파일의 위치)

    Changes are saved automatically two seconds after you stop typing, and a snapshot of the previous
    version is kept before the first save of each session (자동 저장 · 스냅샷).

    Delete this text and start writing. 이 글을 지우고 바로 쓰기 시작하세요.

    """
}
