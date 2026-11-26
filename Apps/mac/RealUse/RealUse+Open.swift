import SwiftUI
import AppKit
import HyperCore

// 실사용 시뮬레이션 — 밖에서 넘어온 파일 열기(Finder 의 "다음으로 열기"·Dock 에 끌어다 놓기·`open -a`·명령줄의 맨 인자): 탭으로 열리는가, 창이 더 생기지
// 않는가, 앱이 앞으로 나오지 않는가(자동화 실행), 폴더·없는 파일·텍스트가 아닌 파일을 열지 않는가.
//
// 실제 Finder·`open` 은 쓰지 않는다 (앱을 활성화하고, 설치된 HyperEdit 으로 갈 수 있다). 대신 두 길로 같은 처리기에 닿는다:
//  - 켜져 있을 때: 앱 delegate(SwiftUI 의 delegate → 우리 AppDelegate) 의 `application(_:open:)` 을 직접 부른다
//  - 꺼져 있다가 뜰 때: 명령줄의 맨 인자 — `scripts/realuse.sh` 가 `open-launch` 를 파일과 함께 한 번 더 띄운다. 앱은 실행 인자를 직접 가려 열고
//    (ExternalOpen.takeLaunchFiles), AppKit 이 `application(_:openFiles:)` 로 넘기는 것은 견주기만 한다
// 자기 프로세스에 'odoc'·'rapp' 애플 이벤트를 보내지 않는다 — AppKit 의 처리기가 앱을 활성화할 때가 있다(실측 macOS 27: 세 번 중 두 번, 그 뒤
// `NSApp.deactivate()` 로도 물러나지 않았다). 애플 이벤트를 풀어 delegate 를 부르는 것은 AppKit 의 일이라 손으로 확인한다

extension RealUseContext {
    /// 문서 창의 수 (패널·시트·보이지 않는 창 제외) — 열기 이벤트로 창이 더 생기면 안 된다 (이 앱은 창 하나, 모델 하나)
    var documentWindowCount: Int {
        NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) && $0.sheetParent == nil && $0.contentView != nil && $0.frame.width > 200 }.count
    }

    /// 열기 요청이 처리될 때까지(활성 문서가 `url` 이 될 때까지) 기다린다. 반환: 걸린 시간(ms), 시간 안에 안 되면 nil
    func waitActive(_ url: URL, timeout: Double = 2000) async -> Double? {
        let t0 = CFAbsoluteTimeGetCurrent()
        while model.document.url != url {
            if elapsedMs(since: t0) > timeout { return nil }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return elapsedMs(since: t0)
    }

    /// 열기 요청 뒤의 공통 검사: 창이 늘지 않았는가, 앱이 앞으로 나오지 않았는가, 탭·내용·레이아웃이 맞는가. 반환 false: 창이 더 생겼다 — 더는 열기 요청을 보내지 말 것
    @discardableResult
    func checkAfterExternalOpen(_ why: String, windows: Int) -> Bool {
        let sameWindows = documentWindowCount == windows
        if !sameWindows {
            issue("open", "\(why): \(documentWindowCount) document windows (was \(windows)) — \(NSApp.windows.filter(\.isVisible).map { "\($0.className) '\($0.title)' \(Int($0.frame.width))×\(Int($0.frame.height))" })")
            // 더 생긴 창은 바로 닫는다 (사용자의 화면에 남지 않게)
            let main = window
            for w in NSApp.windows where w !== main && w.isVisible && !(w is NSPanel) && w.sheetParent == nil && w.frame.width > 200 { w.close() }
        }
        if NSApp.isActive {
            NSApp.deactivate()
            issue("open", "\(why): the open request activated the app during an automated run", snap: false)
        }
        checkTabs(why); checkTabBar(why); checkAll(why)
        return sameWindows
    }
}

extension RealUse {
    @MainActor static let openScenarios: [Scenario] = [
        // 꺼져 있다가 뜰 때 명령줄로 넘어온 것. `scripts/realuse.sh` 는 이 시나리오를 파일과 함께 따로 한 번 더 띄우고, 무엇을 맨 인자로 주었는지를 환경 변수
        // REALUSE_LAUNCH_FILES(줄마다 하나)로 알려 준다 — 기대하는 탭을 앱의 인자 해석(LaunchOptions.parse)과 따로 정하려는 것이다. 그 변수가 없는 실행
        // (다른 시나리오와 함께 도는 보통의 실행)에서는 옵션의 값이 탭이나 빈 파일이 되지 않았는지만 본다 — AppKit 은 `--realuse-out <폴더>` 의 폴더나
        // `--realuse-only <목록>` 의 목록도 "열 파일"로 넘긴다. 시작 잠금과 함께 보려면 손으로: `scripts/realuse.sh --only open-launch -- --locked`
        Scenario(name: "open-launch") { ctx in
            let m = ctx.model
            let args = CommandLine.arguments
            await ctx.settle(200)   // 보정 걸음이 방금 임시 문서의 탭을 닫았다 — 창 제목은 다음 SwiftUI 갱신에서 따라온다 (다른 시나리오는 문서를 열고 기다리며 시작한다)
            ctx.at("option values are not opened")
            let bare = (ProcessInfo.processInfo.environment["REALUSE_LAUNCH_FILES"] ?? "").split(separator: "\n").map(String.init)
            if let stray = bare.first(where: { !args.contains($0) }) { ctx.issue("open", "REALUSE_LAUNCH_FILES names \(stray), which is not among the launch arguments", snap: false) }
            // 옵션의 값일 수 있는 것: 한 줄표로 시작하지 않고, 맨 인자로 준 것도 아닌 인자
            let values = args.dropFirst().filter { !$0.hasPrefix("-") && !bare.contains($0) }
            let startFile = LaunchOptions.value("--file").map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
            for v in values {
                let u = URL(fileURLWithPath: v).resolvingSymlinksInPath()
                if u != startFile, m.tabs.contains(u) { ctx.issue("open", "the value of a launch option became a tab: \(v)", snap: false) }
                // 없는 경로를 열면 빈 파일이 만들어진다 — 옵션 값 이름의 빈 파일이 현재 폴더에 생기지 않았어야 한다
                if !v.contains("/"), let size = (try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? Int, size == 0 {
                    ctx.issue("open", "an empty file named after a launch option value exists: \(u.path)", snap: false)
                }
            }
            if bare.isEmpty {
                ctx.log("  open-launch: no files were given at launch — only the option values were checked in this launch (scripts/realuse.sh launches this scenario once more, with files)")
            }
            let files = bare.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath() }
            var isDir: ObjCBool = false
            let wanted = files.filter { FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDir) && !isDir.boolValue && TextFileDetector.isLikelyText($0) }
            // `--locked`(시작 잠금)로 띄웠으면: 넘어온 파일은 잠금이 풀릴 때까지 열리지 않는다 — 잠금 화면 뒤에서 문서·탭·창 제목이 바뀌지 않는다
            if m.appLock.isLocked {
                ctx.at("locked at launch")
                if ExternalOpen.pendingCount != bare.count { ctx.issue("open", "locked at launch: \(ExternalOpen.pendingCount) open requests are waiting, \(bare.count) files were given", snap: false) }
                for u in wanted where m.tabs.contains(u) || m.document.url == u || ctx.window.title == u.lastPathComponent {
                    ctx.issue("open", "locked at launch: \(u.lastPathComponent) was opened behind the lock screen (tabs \(m.tabs.map(\.lastPathComponent)), window title '\(ctx.window.title)')")
                }
                ctx.snap("locked")
                m.appLock.authenticator = SelfTest.FakeAuthenticator()   // 실제 Touch ID 프롬프트를 띄우지 않는다
                await m.appLock.requestUnlock()
                await ctx.settle(500)
                if m.appLock.isLocked || ExternalOpen.pendingCount != 0 { ctx.issue("open", "after unlocking: locked \(m.appLock.isLocked), \(ExternalOpen.pendingCount) requests still waiting") }
            }
            ctx.at("bare arguments are tabs")
            ctx.note("launch arguments: \(values.count) option values, \(bare.count) bare (\(wanted.count) text files) · tabs \(m.tabs.map(\.lastPathComponent)) · active \(m.document.url.lastPathComponent)")
            let said = m.output.filter(\.isError).map(\.text)
            for u in files where !wanted.contains(u) {
                if m.tabs.contains(u) { ctx.issue("open", "\(u.lastPathComponent) (a folder, a missing or a non-text file) was given on the command line and became a tab", snap: false) }
                // 스크립트는 없는 파일의 이름에 missing 을 넣는다 — 없는 경로를 열면 빈 파일이 만들어진다
                if u.lastPathComponent.contains("missing"), FileManager.default.fileExists(atPath: u.path) { ctx.issue("open", "a file was created at the missing path given on the command line: \(u.lastPathComponent)", snap: false) }
                if !said.contains(where: { $0.contains(u.lastPathComponent) }) { ctx.issue("open", "nothing in the output panel says that \(u.lastPathComponent) could not be opened (error lines: \(said))", snap: false) }
            }
            var last = -1
            for u in wanted {
                guard let i = m.tabs.firstIndex(of: u) else { ctx.issue("open", "\(u.lastPathComponent) was given on the command line but has no tab (tabs: \(m.tabs.map(\.lastPathComponent)))", snap: false); continue }
                if i < last { ctx.issue("open", "the tabs of the files given on the command line are not in the order given (\(m.tabs.map(\.lastPathComponent)))", snap: false) }
                last = i
            }
            // 넘어온 파일 가운데 마지막 것이 보이고 있어야 한다 (하네스의 보정 걸음이 임시 문서를 열었다 닫았지만 닫으면 왼쪽 이웃 = 그 파일로 돌아온다)
            if let shown = wanted.last, m.document.url != shown { ctx.issue("open", "the last file given on the command line is \(shown.lastPathComponent) but the document is \(m.document.url.lastPathComponent)") }
            if let s = startFile, !wanted.isEmpty, m.tabs.first != s { ctx.issue("open", "the start document is not the first tab any more (tabs: \(m.tabs.map(\.lastPathComponent)))", snap: false) }
            if ctx.documentWindowCount != 1 { ctx.issue("open", "\(ctx.documentWindowCount) document windows after launch") }
            ctx.checkTabs("after launch"); ctx.checkTabBar("after launch"); ctx.checkAll("after launch")
            ctx.snap("launched"); ctx.snapTabBar("launched")
        },

        // 켜져 있을 때 넘어온 파일: 여러 개 → 모두 탭·마지막 것이 활성, 이미 열린 파일 → 그 탭, 보고 있는 파일 → 그대로(다시 읽지 않는다),
        // 폴더·없는 파일·텍스트가 아닌 파일 → 열지 않고 출력 패널에, 창은 그대로 하나, 앱은 앞으로 나오지 않는다
        Scenario(name: "open-external") { ctx in
            let m = ctx.model
            let fm = FileManager.default
            let folder = ctx.dir.appendingPathComponent("ext", isDirectory: true)
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            @MainActor func make(_ name: String, lines: Int = 300) -> URL { ctx.writeNumbered(name, in: folder, lines: lines) }
            let e1 = make("ext-one.md"), e2 = make("ext-two.txt"), e3 = make("ext-three.md", lines: 3000), e4 = make("ext-four.log"), e5 = make("ext-five.md")
            let sub = folder.appendingPathComponent("a-folder", isDirectory: true)
            try? fm.createDirectory(at: sub, withIntermediateDirectories: true)
            let missing = folder.appendingPathComponent("not-there.md")
            let image = folder.appendingPathComponent("picture.png"), nul = folder.appendingPathComponent("has-nul.txt")
            fm.createFile(atPath: image.path, contents: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]))
            fm.createFile(atPath: nul.path, contents: Data([0x41, 0x00, 0x42, 0x0A]))
            let windows = ctx.documentWindowCount
            let tabs0 = m.tabs
            guard let delegate = NSApp.delegate else { ctx.issue("open", "the app has no delegate"); return }
            ctx.note("delegate \(String(reflecting: type(of: delegate))) · responds to application(_:open:) \(delegate.responds(to: #selector(NSApplicationDelegate.application(_:open:)))) · document windows \(windows)")

            ctx.at("three files through the delegate")
            delegate.application?(NSApp, open: [e1, e2, e3])
            await ctx.settle(500)
            ctx.expectTabs(tabs0 + [e1, e2, e3], active: e3, "three files opened from outside")
            // 창이 더 생겼으면 여기서 그만둔다 — 요청마다 창이 하나씩 는다
            guard ctx.checkAfterExternalOpen("three files opened from outside", windows: windows) else { return }
            ctx.snap("three-opened"); ctx.snapTabBar("three-opened")

            ctx.at("a file that already has a tab")
            delegate.application?(NSApp, open: [e1])
            await ctx.settle(400)
            ctx.expectTabs(tabs0 + [e1, e2, e3], active: e1, "an open file opened again from outside")
            ctx.checkAfterExternalOpen("an open file opened again from outside", windows: windows)

            ctx.at("the file being viewed")
            await ctx.key(.down, [.command]); await ctx.settle(100)
            await ctx.type("typed before the open request ")
            let gen = m.document.reloadGeneration, caret = ctx.caret, length = ctx.length
            delegate.application?(NSApp, open: [e1])
            await ctx.settle(300)
            if m.document.reloadGeneration != gen { ctx.issue("open", "opening the file that is already showing reloaded it from disk") }
            if ctx.caret != caret || ctx.length != length { ctx.issue("open", "opening the file that is already showing moved the caret \(caret) → \(ctx.caret) or changed the text \(length) → \(ctx.length)") }
            if m.tabs != tabs0 + [e1, e2, e3] { ctx.issue("open", "opening the file that is already showing changed the tabs") }
            ctx.checkCaretVisible("the viewed file opened again"); ctx.checkAll("the viewed file opened again")

            ctx.at("one more file, leaving an edited tab")
            delegate.application?(NSApp, open: [e4])
            if await ctx.waitActive(e4) == nil { ctx.issue("open", "the file was not opened (document \(m.document.url.lastPathComponent))") }
            await ctx.settle(500)
            ctx.expectTabs(tabs0 + [e1, e2, e3, e4], active: e4, "one more file")
            ctx.checkAfterExternalOpen("one more file", windows: windows)
            // 떠난 탭(끝에 글을 치던 ext-one)의 편집은 저장됐다
            if let disk = try? String(contentsOf: e1, encoding: .utf8), !disk.hasSuffix("typed before the open request ") { ctx.issue("open", "the edit made in the tab that was left was not saved") }

            ctx.at("a folder, a missing file, two non-text files and a text file")
            // 새 오류 줄은 시각으로 가른다 — 출력 패널은 500줄에서 앞을 버려, 줄 수로 가르면 가득 찬 뒤(전체 묶음)에는 새 줄의 처음을 놓친다
            let errorsSince = Date()
            delegate.application?(NSApp, open: [sub, missing, image, nul, e5])
            if await ctx.waitActive(e5) == nil { ctx.issue("open", "the text file among things that cannot be opened was not opened (document \(m.document.url.lastPathComponent))") }
            await ctx.settle(500)
            ctx.expectTabs(tabs0 + [e1, e2, e3, e4, e5], active: e5, "mixed request")
            ctx.checkAfterExternalOpen("mixed request", windows: windows)
            if fm.fileExists(atPath: missing.path) { ctx.issue("open", "a file was created at the missing path that was asked to be opened", snap: false) }
            let errors = m.output.filter { $0.isError && $0.time >= errorsSince }.map(\.text)
            for name in ["a-folder", "not-there.md", "picture.png", "has-nul.txt"] where !errors.contains(where: { $0.contains(name) }) {
                ctx.issue("open", "nothing in the output panel says that \(name) could not be opened (new error lines: \(errors))", snap: false)
            }
            ctx.note("output: \(errors)")

            // 이 실행의 폴더 밖 파일: 테스트 인스턴스는 설치된 앱과 번들 ID 가 같아 사용자가 Finder 에서 연 파일이 올 수 있다 — 열면 다음 편집 걸음이 그 파일에 저장된다.
            // 읽기 전용 시스템 파일로 본다 (거절이 깨져 열리더라도 쓸 수 없는 파일이다)
            ctx.at("a file outside this run's folders")
            let outside = URL(fileURLWithPath: "/usr/share/dict/words")
            if fm.fileExists(atPath: outside.path) {
                let refusedSince = Date()
                delegate.application?(NSApp, open: [outside])
                await ctx.settle(400)
                let opened = m.tabs.filter { !$0.path.hasPrefix(ctx.dir.resolvingSymlinksInPath().path) && !tabs0.contains($0) }
                if !opened.isEmpty || m.document.url != e5 {
                    ctx.issue("open", "a file outside this run's folders was opened in an automated run: \(opened.map(\.path)) (document \(m.document.url.path))", snap: false)
                    for u in opened { m.closeTab(u) }
                    await ctx.settle(300)
                }
                let said = m.output.filter { $0.isError && $0.time >= refusedSince }.map(\.text)
                if !said.contains(where: { $0.contains("/usr/share/dict") }) { ctx.issue("open", "nothing in the output panel says that the outside file was refused (new error lines: \(said))", snap: false) }
                ctx.expectTabs(tabs0 + [e1, e2, e3, e4, e5], active: e5, "an outside file")
                ctx.checkAfterExternalOpen("an outside file", windows: windows)
            } else { ctx.issue("open", "no /usr/share/dict/words on this Mac — the outside-file step did not run", snap: false) }
            // 같은 폴더의 다른 표기는 안쪽이다 (`/private/var/…` ↔ `/var/…`), 사람이 쓰는 실행은 가리지 않는다
            let privateSpelling = URL(fileURLWithPath: "/private" + e1.path)
            if e1.path.hasPrefix("/var/"), !ExternalOpen.mayOpen(privateSpelling) { ctx.issue("open", "\(privateSpelling.path) is taken for a file outside this run's folders", snap: false) }
            if !ExternalOpen.mayOpen(outside, scripted: false) { ctx.issue("open", "a run that is not driven by a script refuses a file", snap: false) }

            // 임시 폴더라고 다 이 실행의 것이 아니다. 다른 앱도 거기에 사본을 두고 "외부 편집기로 열기"로 넘긴다(파일 전송·Git 클라이언트) — 그런 파일이 도는 중에 오면
            // 숨은 창의 활성 탭이 되고 다음 편집 걸음이 거기 저장된다. 이름이 `hyperedit-` 로 시작하는 폴더(픽스처는 전부 그 안이다) 밖은 열지 않는다
            ctx.at("another app's copy in the temporary folder")
            let foreign = fm.temporaryDirectory.appendingPathComponent("other-app-\(UUID().uuidString.prefix(8))", isDirectory: true)
            let copy = foreign.appendingPathComponent("copy of notes.md")
            try? fm.createDirectory(at: foreign, withIntermediateDirectories: true)
            try? "a copy another app keeps in the temporary folder\n".write(to: copy, atomically: true, encoding: .utf8)
            let foreignSince = Date()
            delegate.application?(NSApp, open: [copy])
            await ctx.settle(400)
            let strays = m.tabs.filter { $0.lastPathComponent == copy.lastPathComponent }
            if !strays.isEmpty || m.document.url != e5 {
                ctx.issue("open", "a file another app keeps in the temporary folder was opened in an automated run: \(strays.map(\.path)) (document \(m.document.url.lastPathComponent))", snap: false)
                for u in strays { m.closeTab(u) }
                await ctx.settle(300)
            }
            if !m.output.filter({ $0.isError && $0.time >= foreignSince }).contains(where: { $0.text.contains(foreign.lastPathComponent) }) {
                ctx.issue("open", "nothing in the output panel says that the other app's copy was refused", snap: false)
            }
            try? fm.removeItem(at: foreign)
            ctx.expectTabs(tabs0 + [e1, e2, e3, e4, e5], active: e5, "another app's copy in the temporary folder")
            ctx.checkAfterExternalOpen("another app's copy in the temporary folder", windows: windows)
            // 시작 문서(`--file`) 쪽: 그 폴더 바로 아래의 파일만 이 실행의 것이다 (하위 폴더·형제 폴더·부모 폴더는 아니다). 이 실행의 시작 폴더는 임시 폴더의
            // 픽스처 폴더라 실제 파일로는 가를 수 없어 규칙을 직접 묻는다
            let root = URL(fileURLWithPath: "/tmp/hyperedit-test-root"), startFolder = URL(fileURLWithPath: "/work/run")
            let wrong = [("/work/run/copy.md", true), ("/work/run/sub/copy.md", false), ("/work/run-2/copy.md", false), ("/work/copy.md", false),
                         ("/tmp/hyperedit-test-root/hyperedit-run/deep/x.md", true), ("/tmp/hyperedit-test-root/other-app/x.md", false), ("/tmp/hyperedit-test-root/x.md", false)]
                .filter { ExternalOpen.mayOpen(URL(fileURLWithPath: $0.0), scripted: true, temporary: root, startFolder: startFolder) != $0.1 }
            if !wrong.isEmpty { ctx.issue("open", "the rule for what a scripted run may open is wrong for \(wrong.map { "\($0.0) (should be \($0.1 ? "allowed" : "refused"))" })", snap: false) }

            ctx.at("only things that cannot be opened")
            delegate.application?(NSApp, open: [sub, missing])
            await ctx.settle(300)
            ctx.expectTabs(tabs0 + [e1, e2, e3, e4, e5], active: e5, "a request with nothing to open")
            ctx.checkAfterExternalOpen("a request with nothing to open", windows: windows)
            if ExternalOpen.pendingCount != 0 { ctx.issue("open", "\(ExternalOpen.pendingCount) open requests are still waiting", snap: false) }
            ctx.snap("end"); ctx.snapTabBar("end")

            // 빠른 추가 패널이 떠 있을 때. 빈 패널은 열기를 막지 않는다 — 패널의 대상이 새 문서로 바뀔 뿐이다(탭을 눌렀을 때와 같다). 쓰던 메모가 있으면 그 메모가
            // 엉뚱한 파일에 붙지 않게 패널이 닫힐 때까지 미룬다. 뒤에서 도는 실행의 패널은 다른 창 위에 뜨지도, 키 입력을 받지도 않는다 (QuickAppendController.show)
            ctx.at("quick append panel up")
            let qa = m.quickAppend
            if NSApp.isActive {
                ctx.issue("open", "the app is active — the quick append step did not run (its panel would take the keyboard)", snap: false)
            } else {
                let e6 = make("ext-six.md"), e7 = make("ext-seven.md")
                qa.draft = ""
                qa.show()
                for _ in 0..<20 where !(qa.isVisible && qa.textView != nil) { await ctx.settle(50) }
                delegate.application?(NSApp, open: [e6])
                if await ctx.waitActive(e6, timeout: 1500) == nil {
                    ctx.issue("open", "an empty quick append panel held an open request back (panel \(qa.isVisible), waiting \(ExternalOpen.pendingCount), document \(m.document.url.lastPathComponent))", snap: false)
                    qa.hide()
                    _ = await ctx.waitActive(e6)
                    qa.show()
                }
                await ctx.settle(400)
                if !qa.isVisible { ctx.issue("open", "the open request closed the quick append panel", snap: false) }
                ctx.expectTabs(tabs0 + [e1, e2, e3, e4, e5, e6], active: e6, "a file opened while an empty quick append panel is up")
                ctx.checkAfterExternalOpen("a file opened while an empty quick append panel is up", windows: windows)

                qa.textView?.insertText("note for ext-six", replacementRange: NSRange(location: 0, length: 0))
                await ctx.settle(150)
                if qa.draft != "note for ext-six" { ctx.issue("open", "typing in the quick append panel did not make a draft ('\(qa.draft)')", snap: false) }
                delegate.application?(NSApp, open: [e7])
                await ctx.settle(700)
                if ExternalOpen.pendingCount != 1 || m.document.url != e6 || m.tabs.contains(e7) {
                    ctx.issue("open", "an open request did not wait while a note was being written in the quick append panel (waiting \(ExternalOpen.pendingCount), document \(m.document.url.lastPathComponent))", snap: false)
                }
                qa.submit()   // ⌘↩: 보이던 문서에 붙이고 패널을 닫는다 → 기다리던 파일이 열린다
                if await ctx.waitActive(e7, timeout: 3000) == nil { ctx.issue("open", "the waiting file did not open after the quick append panel was closed (waiting \(ExternalOpen.pendingCount), panel \(qa.isVisible))") }
                await ctx.settle(400)
                let six = (try? String(contentsOf: e6, encoding: .utf8)) ?? "", seven = (try? String(contentsOf: e7, encoding: .utf8)) ?? ""
                if !six.hasSuffix("note for ext-six\n") || seven.contains("note for ext-six") || (ctx.text as String).contains("note for ext-six") {
                    ctx.issue("open", "the quick append note did not go to the file that was showing when it was written (ext-six ends '\(six.suffix(24))')")
                }
                ctx.expectTabs(tabs0 + [e1, e2, e3, e4, e5, e6, e7], active: e7, "a file opened once the quick append note was appended")
                ctx.checkAfterExternalOpen("a file opened once the quick append note was appended", windows: windows)
                if qa.isVisible { qa.hide() }
                qa.draft = ""
            }

            // 같은 파일의 다른 표기 — 대소문자, 한글의 조합형(NFC)·분해형(NFD): 파일 시스템은 한 파일로 보므로 탭도 하나여야 한다. 탭은 디스크에 적힌 표기로 견준다
            // (`resolvingSymlinksInPath` 가 그 표기를 돌려준다 — 실측 macOS 27. 그러지 않는 시스템이 나오면 여기서 걸린다)
            ctx.at("other spellings of one file")
            let nfc = "한글 메모.md".precomposedStringWithCanonicalMapping
            try? "korean\n".write(to: folder.appendingPathComponent(nfc), atomically: true, encoding: .utf8)
            try? "case\n".write(to: folder.appendingPathComponent("Case Notes.md"), atomically: true, encoding: .utf8)
            let before = m.tabs.count
            for name in [nfc, nfc.decomposedStringWithCanonicalMapping, "Case Notes.md", "case notes.md", "CASE NOTES.MD"] {
                delegate.application?(NSApp, open: [folder.appendingPathComponent(name)])
                await ctx.settle(300)
            }
            // 사이드바가 쓰는 표기(폴더 목록에 나온 그대로)로도 연다
            let listed = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent.hasPrefix("Case") || $0.lastPathComponent.hasSuffix("메모.md") }
            for u in listed { m.open(url: u); await ctx.settle(300) }
            let made = m.tabs.suffix(max(0, m.tabs.count - before)).map { "\($0.lastPathComponent) (\($0.lastPathComponent.unicodeScalars.count) scalars)" }
            if m.tabs.count - before != 2 || listed.count != 2 { ctx.issue("open", "two files opened by seven spellings made \(m.tabs.count - before) tabs: \(made)", snap: false) }
            ctx.note("spellings: on disk \(listed.map { "\($0.lastPathComponent) (\($0.lastPathComponent.unicodeScalars.count) scalars)" }) · tabs made \(made)")
            ctx.checkAfterExternalOpen("other spellings of one file", windows: windows)
            // 끝에 친 글을 걷어낸다 (탭은 하네스가 닫는다)
            m.activateTab(e1); await ctx.settle(300)
        },
    ]
}
