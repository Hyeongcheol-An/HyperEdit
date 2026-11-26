import AppKit
import Combine
import HyperCore

/// 밖에서 온 "이 파일을 열어라" — Finder 의 "다음으로 열기", Dock 아이콘에 끌어다 놓기, `open -a HyperEdit <파일>`, 명령줄의 맨 인자.
/// `AppDelegate.application(_:open:)` 이 받은 경로를 여기 모아 두었다가 **열어도 되는 때** `AppModel.openExternal` 로 넘긴다:
///  - 앱이 꺼져 있다가 뜨는 경우, 요청은 `applicationDidFinishLaunching` 보다 먼저, 창이 생기기 전에 온다. 모델(첫 문서·지난 세션의 탭)은 그보다도 먼저
///    만들어져 있어(실측) 바로 연다 — 편집기는 나중에 그 문서에 붙는다. 지난 세션의 탭은 그대로 두고 넘어온 파일이 활성 탭이 된다.
///    모델이 아직 없으면 만들어진 직후(`modelReady`)에 연다
///  - 앱 잠금 중에는 열지 않는다 (잠금 화면 뒤에서 문서를 바꾸지 않는다 — 창 제목에 파일 이름이 드러난다) → 풀리면 연다
///  - 매크로 재생 중(남은 걸음이 새 파일에 들어간다)·시트나 모달 패널이 떠 있는 동안(줄 이동·내보내기가 다른 문서를 대상으로 삼게 된다)·빠른 추가
///    패널에 쓰던 메모가 있는 동안(패널은 지금 보이는 문서의 끝에 덧붙인다 — 쓰는 중에 문서가 바뀌면 ⌘↩ 가 엉뚱한 파일에 붙는다)에도 미룬다.
///    빈 빠른 추가 패널은 미룰 까닭이 아니다: 그 패널은 다른 데를 눌러도 닫히지 않고 모든 Space 에 떠 있어, 열어 둔 채 잊으면 Finder 에서 연 파일이
///    탭도 알림도 없이 끝없이 기다리게 된다 (탭을 누르면 패널의 대상이 바로 바뀌는 것과도 어긋난다).
///    설정 창이 앞에 있는 것도 미룰 까닭이 아니다 (`AppModel.tabKeysApply` 는 그때도 탭 단축키를 막지만, 그것은 키가 설정 창의 것이어서다)
@MainActor
enum ExternalOpen {
    private static var pending: [URL] = []
    private static var retry: Timer?
    private static var unlockWatch: AnyCancellable?
    private static var flushScheduled = false

    /// 아직 열지 못하고 기다리는 파일 수 (셀프테스트·하네스가 본다)
    static var pendingCount: Int { pending.count }

    /// 열기 요청을 받는다 (Finder·Dock·`open -a` 의 애플 이벤트). 지금 열 수 있으면 바로 연다
    static func receive(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        pending += files
        flush()
        showWindow()
    }

    /// 명령줄의 맨 인자로 넘어온 파일 (`HyperEdit <파일>…`, 상대 경로는 현재 폴더 기준) — 모델이 만들어질 때 한 번 받는다 (`modelReady`).
    /// AppKit 이 넘겨주는 것(`application(_:openFiles:)`)에 기대지 않고 실행 인자를 우리 문법으로 가른다 (`LaunchOptions.parse`). AppKit 은 한 줄표로
    /// 시작하는 인자마다 그 뒤의 인자를 값으로 짝짓고 남는 것을 "열 파일"로 넘기는데(NSTreatUnknownArgumentsAsOpen), 이 앱의 옵션에는 값이 없는 것
    /// (`--ephemeral`·`--quit` …)이 섞여 있어 짝이 어긋난다 — 옵션의 값을 파일이라며 넘기고(실측: `--ephemeral --ephemeral-suite <이름> --file <경로>
    /// --realuse --realuse-out <폴더> … --quit --realuse-only <목록>` 에서 `<이름>`·`<폴더>`·`<목록>`. 없는 경로를 열면 빈 파일이 만들어진다),
    /// 값 없는 옵션 바로 뒤의 파일은 그 옵션의 값으로 삼켜 넘기지 않는다 (`--ephemeral a.md`)
    private static var launchFilesTaken = false
    private static func takeLaunchFiles() {
        guard !launchFilesTaken else { return }
        launchFilesTaken = true
        pending += LaunchOptions.files().map { URL(fileURLWithPath: $0) }
    }

    /// AppKit 이 실행 인자 가운데 "열 파일"이라며 넘긴 것 (인자마다 한 번씩 부른다). 우리가 가른 맨 인자는 이미 받아 두었다 — 여기서는 판정이 갈린 것만 본다:
    /// 우리 문법으로 옵션의 값인 것은 열지 않고 stderr 에 적고, 실행 인자에 없는 이름은 열기 요청으로 받는다
    static func receive(commandLine names: [String]) {
        takeLaunchFiles()
        let parsed = LaunchOptions.parse()
        for name in names where !parsed.files.contains(name) {
            if let owner = parsed.values.first(where: { $0.value == name }) {
                FileHandle.standardError.write("[open] not a file to open: '\(name)' is the value of \(owner.option)\n".data(using: .utf8)!)
            } else {
                pending.append(URL(fileURLWithPath: name))
            }
        }
        scheduleFlush()
    }

    /// 모델이 다 만들어졌다 (`AppModel.init` 의 끝) — 명령줄의 맨 인자와, 그 전에 와 있던 요청을 연다. 지금은 모델이 `applicationWillFinishLaunching`
    /// 보다도 먼저 만들어져 요청이 먼저 오는 일이 없지만(실측), 그 순서는 SwiftUI 의 사정이라 기대지 않는다
    static func modelReady() { takeLaunchFiles(); scheduleFlush() }

    /// 다음 턴에 한 번 연다 — 여러 곳에서 이어 들어온 것을 모아서 (그러지 않으면 파일마다 읽고 바로 다음 파일로 넘어간다). 모델의 `init` 안에서 문서를 바꾸지도 않는다
    private static func scheduleFlush() {
        guard !pending.isEmpty, !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.async { flushScheduled = false; flush() }
    }

    // MARK: 스크립트가 모는 실행이 열어도 되는 파일

    /// 테스트 픽스처의 폴더 이름은 이것으로 시작한다 — 셀프테스트·하네스·벤치가 임시 폴더에 만드는 것(`hyperedit-open-…`·`hyperedit-realuse-…`)과
    /// 실행 스크립트가 `mktemp` 로 만드는 것(`hyperedit-realuse-start.…`) 모두
    static let fixturePrefix = "hyperedit-"

    /// `--file` 로 준 시작 문서가 있는 폴더 (실행 스크립트가 만든 폴더 — `TMPDIR` 을 바꾼 셸에서는 시스템 임시 폴더 밖이다. Foundation 은 `TMPDIR` 을 따르지 않는다)
    static let startDocumentFolder: URL? = LaunchOptions.value("--file").map { URL(fileURLWithPath: $0).deletingLastPathComponent() }

    /// 이 실행이 밖에서 온 `url` 을 열어도 되는가. 테스트 빌드는 설치된 앱과 번들 ID 가 같아서, 도는 중에 사용자가 Finder 에서 연 파일이 이 인스턴스로 올 수 있다 —
    /// 그러면 사용자의 파일이 숨은 창의 활성 탭이 되고 테스트의 다음 편집(입력·매크로·모두 바꾸기)이 그 파일에 자동 저장된다. 그래서 스크립트가 모는 실행
    /// (셀프테스트·벤치·실사용 하네스·스크린샷 — AutomationRun.isScripted)은 자기 것만 연다. 사람이 쓰는 실행(`--ephemeral` 만 준 것 포함)은 가리지 않는다.
    /// 자기 것은 둘뿐이다:
    ///  - 시스템 임시 폴더 바로 아래의, 이름이 `hyperedit-` 로 시작하는 폴더 안(깊이는 상관없다). 임시 폴더 전체가 아니다 — 다른 앱도 거기에 사본을 두고
    ///    "외부 편집기로 열기"로 넘긴다 (파일 전송·Git 클라이언트)
    ///  - 시작 문서와 같은 폴더의 파일, 그 폴더 바로 아래만. 하위 폴더까지 받으면 `--file ~/Desktop/copy.md` 로 띄운 실행이 데스크탑 아래 전부를 연다
    /// 경로는 심볼릭 링크를 풀고 견준다 (`/var/…` 와 `/private/var/…` 는 같은 곳이다 — 없는 경로는 링크가 풀리지 않으므로 `/private` 을 직접 뗀다)
    static func mayOpen(_ url: URL, scripted: Bool = AutomationRun.isScripted, temporary: URL = FileManager.default.temporaryDirectory,
                        startFolder: URL? = startDocumentFolder) -> Bool {
        guard scripted else { return true }
        func key(_ u: URL) -> String {
            let path = u.resolvingSymlinksInPath().path
            return path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path
        }
        let path = key(url)
        if let startFolder, (path as NSString).deletingLastPathComponent == key(startFolder) { return true }
        let root = key(temporary) + "/"
        guard path.hasPrefix(root) else { return false }
        let parts = path.dropFirst(root.count).split(separator: "/")
        return parts.count >= 2 && parts[0].hasPrefix(fixturePrefix)   // 그런 이름의 폴더 '안' — 임시 폴더 바로 아래의 낱개 파일은 이름이 같아도 아니다
    }

    /// 지금 문서를 바꾸면 안 되는 까닭
    private enum Hold { case noModel, locked, busy }

    private static func hold(_ model: AppModel?) -> Hold? {
        guard let model else { return .noModel }
        if model.appLock.isLocked { return .locked }
        if model.macros.isPlaying || NSApp.modalWindow != nil || editorWindow(model)?.attachedSheet != nil || noteInProgress(model.quickAppend) { return .busy }
        return nil
    }

    /// 빠른 추가 패널에 쓰던 메모가 있는가: 패널이 떠 있고 덧붙일 글이 있다 (⌘↩ 가 받아들이는 것과 같은 기준 — 공백뿐이면 없는 것. 입력기로 조합 중인 글자는
    /// 아직 초안에 없을 수 있어 입력 뷰도 본다)
    private static func noteInProgress(_ panel: QuickAppendController) -> Bool {
        guard panel.isVisible else { return false }
        return ![panel.draft, panel.textView?.string ?? ""].allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private static func editorWindow(_ model: AppModel) -> NSWindow? { model.session.primary?.textView?.window }

    private static func flush() {
        let model = AppModel.current
        let why = pending.isEmpty ? nil : hold(model)
        if why != .busy { retry?.invalidate(); retry = nil }
        guard !pending.isEmpty else { return }
        switch why {
        case .noModel:
            break   // `modelReady` 가 다시 부른다
        case .locked:
            // 잠금은 오래 갈 수 있다 — 주기적으로 보지 않고 풀리는 순간을 기다린다 (@Published 는 값이 바뀌기 직전에 알리므로 다음 턴에 본다)
            if unlockWatch == nil, let model {
                unlockWatch = model.appLock.$isLocked.dropFirst().filter { !$0 }.receive(on: RunLoop.main).sink { _ in
                    MainActor.assumeIsolated { unlockWatch = nil; flush() }
                }
            }
        case .busy:
            // 재생이 끝나거나 시트·패널이 닫히거나 빠른 추가 창의 메모가 붙을(또는 창이 닫힐) 때까지 — 닫혔다고 알려 주는 곳이 없는 상태(모달 패널)가 있어
            // 잠깐씩 다시 본다. 잠금이 풀리며 쓰던 메모가 있는 빠른 추가 창이 뜨는 경우(잠긴 동안 부른 것은 풀리는 그 턴에 뜬다)도 여기로 온다 — 기다리던
            // 열기는 다음 턴에야 보므로
            if retry == nil {
                retry = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in MainActor.assumeIsolated { flush() } }
            }
        case nil:
            guard let model else { return }
            let urls = pending
            pending = []
            model.openExternal(urls)
        }
    }

    /// 요청을 받으면 창을 보인다(잠겨 있거나 시트가 떠 있어 아직 열지 못했어도 — 왜 안 열리는지 보여야 한다): 최소화돼 있으면 꺼내고 앞으로.
    /// 앱을 앞으로 가져오는 것은 시스템의 몫이다(Finder·Dock·`open` 이 앱을 활성화한다) — 여기서 `activate` 하지 않으므로 `open -g` 처럼 뒤에서
    /// 열라는 요청은 다른 앱의 포커스를 뺏지 않는다. 자동화 실행은 창을 건드리지 않는다. 시작할 때는 아직 창이 없다 (SwiftUI 가 곧 만든다)
    private static func showWindow() {
        guard !AutomationRun.isScripted, let model = AppModel.current, let window = editorWindow(model) else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        if !window.isKeyWindow { window.makeKeyAndOrderFront(nil) }
    }
}
