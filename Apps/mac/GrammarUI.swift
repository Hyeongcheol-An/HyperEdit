import SwiftUI
import AppKit
import HyperCore

// grammar: 사용자 정의 문법 UI — 파일 메뉴 항목("Open Grammars Folder…", "Reload Grammars"), 시작 시 로드, 리로드 뒤 문서 문법·상태바 갱신.
// 엔진은 HyperCore `Highlight/UserGrammarStore.swift`(JSON 스키마·검증) 와 `GrammarRegistry`(사용자 문법 우선) 에 있다.
// UI 문자열은 영어 키(LocalizedStringKey) + Localizable.xcstrings 의 번역 (l10n/ui.<code>.json).

/// 파일 메뉴 "새 문서…" 그룹 뒤: 문법 폴더 열기 · 문법 다시 읽기
struct GrammarCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()
            Button("Open Grammars Folder…") { model.openGrammarsFolder() }
            Button("Reload Grammars") { model.reloadGrammars() }
        }
    }
}

extension UserGrammarStore {
    /// 자동화 실행(`--selftest` `--snapshot` `--ephemeral`)은 임시 폴더를 써 사용자의 grammars 폴더를 건드리지 않는다 (SnippetStore.launchDirectory 와 같은 규칙)
    static var launchDirectory: URL {
        if LaunchOptions.has("--selftest") || LaunchOptions.has("--selftest-open") || LaunchOptions.has("--snapshot") || LaunchOptions.has("--ephemeral") {
            return FileManager.default.temporaryDirectory.appendingPathComponent("hyperedit-ephemeral-\(ProcessInfo.processInfo.processIdentifier)/grammars", isDirectory: true)
        }
        return defaultDirectory
    }
}

extension AppModel {
    /// 시작: 문서를 만들기 전에 사용자 문법을 읽어 둔다 (첫 문서의 문법 결정에 반영). 문제는 init 이 끝난 뒤 `reportGrammarLoad()` 가 출력 패널에 적는다.
    static func loadUserGrammarsAtLaunch() {
        UserGrammarStore.shared.load(directory: UserGrammarStore.launchDirectory)
    }

    /// 시작 로드 결과를 출력 패널에 (문법이 있거나 건너뛴 파일이 있을 때만)
    func reportGrammarLoad() {
        let store = UserGrammarStore.shared
        logGrammarProblems(store)
        if store.count > 0 { log(String(localized: "User grammars loaded · \(store.count)")) }
    }

    /// 문법 폴더를 Finder 로 연다 (없으면 예제·README 와 함께 만든다)
    func openGrammarsFolder() {
        let dir = UserGrammarStore.launchDirectory
        if !FileManager.default.fileExists(atPath: dir.path) { UserGrammarStore.shared.load(directory: dir) }
        NSWorkspace.shared.open(dir)
    }

    /// 문법 폴더를 다시 읽고 현재 문서의 문법·줄 상태·상태바 언어 이름을 갱신한다. 출력: "Grammars reloaded · N" + 건너뛴 파일마다 한 줄
    func reloadGrammars() {
        let store = UserGrammarStore.shared
        let n = store.load(directory: UserGrammarStore.launchDirectory)
        logGrammarProblems(store)
        document.refreshGrammar()
        objectWillChange.send()   // 상태바 언어 이름(languageName)은 문서 문법에서 읽는다
        log(String(localized: "Grammars reloaded · \(n)"))
    }

    private func logGrammarProblems(_ store: UserGrammarStore) {
        for p in store.problems { log(String(localized: "Grammar file skipped · \(p.file): \(p.message)"), isError: true) }
    }
}
