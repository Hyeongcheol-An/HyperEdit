import AppKit
import HyperCore

// 셀프테스트: 밖에서 넘어온 파일 열기 (Finder 의 "다음으로 열기"·Dock·`open -a`·명령줄의 맨 인자 → ExternalOpen → AppModel.openExternal).
// 여러 파일 → 모두 탭·마지막이 활성 / 이미 열린 파일 / 열 수 없는 것 / 창은 하나 / 잠금 중·시트가 떠 있는 동안·매크로 재생 중·빠른 추가 패널에 쓰던 메모가
// 있는 동안에는 미뤘다가 연다 (빈 패널은 미루지 않는다) /
// 떠나는 탭을 저장할 수 없으면 머물되 탭은 남는다 / 실행 인자에서 옵션의 값 가려내기.
// 실제 Finder·`open` 은 쓰지 않는다 — 앱 delegate 의 메서드와 ExternalOpen 을 직접 부른다 (실사용 하네스 `open-external` 도 그렇다. 자기 프로세스에 애플
// 이벤트를 보내면 앱이 활성화될 때가 있다)
extension SelfTest {
    @MainActor
    static func runExternalOpen(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { pumpEvent(); try? await Task.sleep(nanoseconds: ms * 1_000_000) }
        func text() -> String { model.document.textStorage.string }
        func names() -> [String] { model.tabs.map(\.lastPathComponent) }
        func documentWindows() -> Int { NSApp.windows.filter { $0.isVisible && !($0 is NSPanel) && $0.sheetParent == nil && $0.contentView != nil && $0.frame.width > 200 }.count }
        func errors() -> [String] { model.output.filter(\.isError).map(\.text) }
        guard let tv = model.session.primary?.textView, let win = tv.window else { check(false, "open: editor window available"); return }
        let fm = FileManager.default
        let base = model.document.url
        let dir = fm.temporaryDirectory.appendingPathComponent("hyperedit-open-\(UUID().uuidString.prefix(8))", isDirectory: true)
        func make(_ name: String, _ body: String) -> URL {
            let u = dir.appendingPathComponent(name)
            try? body.write(to: u, atomically: true, encoding: .utf8)
            return u.resolvingSymlinksInPath()
        }
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch { check(false, "open: cannot create samples: \(error)"); return }
        let x1 = make("x1.md", "ONE\n"), x2 = make("x2.md", "TWO\n"), x3 = make("x3.txt", "THREE\n"), x4 = make("x4.md", "FOUR\n"), x5 = make("x5.md", "FIVE\n")
        let sub = dir.appendingPathComponent("folder", isDirectory: true), missing = dir.appendingPathComponent("missing.md"), binary = dir.appendingPathComponent("data.txt")
        try? fm.createDirectory(at: sub, withIntermediateDirectories: true)
        fm.createFile(atPath: binary.path, contents: Data([0x41, 0x00, 0x42]))
        let windows0 = documentWindows(), n0 = model.tabs.count

        // 여러 파일: 모두 탭(준 순서로 끝에), 마지막 것이 활성 — 앞의 것은 읽지 않는다(탭은 경로일 뿐)
        ExternalOpen.receive([x1, x2]); await wait(300)
        check(Array(model.tabs.suffix(2)) == [x1, x2] && model.tabs.count == n0 + 2 && model.document.url == x2 && text().hasPrefix("TWO"),
              "open: two files from outside become two tabs and the last one is shown (\(names().suffix(2)), \(model.document.url.lastPathComponent))")
        check((AppDefaults.store.stringArray(forKey: AppModel.openDocumentsKey) ?? []) == model.tabs.map(\.path), "open: the new tabs are in the saved session")
        // 앱 delegate 를 거쳐서(SwiftUI 의 delegate → AppDelegate): 이미 열린 파일은 그 탭으로, 창은 늘지 않는다
        NSApp.delegate?.application?(NSApp, open: [x1]); await wait(400)
        check(model.document.url == x1 && model.tabs.count == n0 + 2 && text().hasPrefix("ONE"), "open: a file that already has a tab is shown in that tab (\(model.document.url.lastPathComponent), \(model.tabs.count - n0) new tabs)")
        check(documentWindows() == windows0, "open: an open request does not add a window (\(documentWindows()), was \(windows0))")
        // 보고 있는 파일을 다시 열라는 요청은 아무것도 바꾸지 않는다 (디스크에서 다시 읽지 않는다 — 치던 글과 캐럿이 그대로)
        model.send(.perform { tv in tv.breakUndoCoalescing(); tv.insertText("typed ", replacementRange: NSRange(location: 0, length: 0)) }); await wait(150)
        let generation = model.document.reloadGeneration, caret = tv.selectedRange()
        ExternalOpen.receive([x1]); await wait(200)
        check(model.document.reloadGeneration == generation && text().hasPrefix("typed ONE") && tv.selectedRange() == caret && model.document.isDirty,
              "open: asking for the file being viewed does not reload it ('\(text().prefix(9))', caret \(tv.selectedRange().location), was \(caret.location))")
        // 폴더·없는 파일·텍스트가 아닌 파일: 열지 않고 출력 패널에 적는다. 없는 경로에 빈 파일을 만들지 않는다. 섞여 온 텍스트 파일은 연다
        let errors0 = errors().count
        ExternalOpen.receive([sub, missing, binary, x3]); await wait(300)
        let said = errors().dropFirst(errors0)
        check(model.document.url == x3 && model.tabs.count == n0 + 3 && !fm.fileExists(atPath: missing.path), "open: only the text file of a mixed request is opened and no file is created at a missing path (\(names().suffix(3)))")
        check(said.count == 3 && ["folder", "missing.md", "data.txt"].allSatisfy { name in said.contains { $0.contains(name) } }, "open: each thing that could not be opened is reported in the output panel (\(said.count))")
        check((try? String(contentsOf: x1, encoding: .utf8)) == "typed ONE\n", "open: the edit in the tab that was left was saved")
        ExternalOpen.receive([sub, missing]); await wait(150)
        check(model.document.url == x3 && model.tabs.count == n0 + 3 && ExternalOpen.pendingCount == 0, "open: a request with nothing that can be opened changes nothing")
        // 이 실행의 폴더 밖 파일(셀프테스트는 스크립트가 모는 실행이다): 열지 않는다 — 테스트 인스턴스는 설치된 앱과 번들 ID 가 같아 사용자가 Finder 에서 연 파일이
        // 올 수 있고, 열면 검사의 다음 편집이 그 파일에 저장된다. 읽기 전용 시스템 파일로 본다
        let outside = URL(fileURLWithPath: "/usr/share/dict/words")
        let refused0 = errors().count
        ExternalOpen.receive([outside, x3]); await wait(300)
        let stray = model.tabs.filter { $0.path.hasPrefix("/usr/") }
        check(fm.fileExists(atPath: outside.path) && stray.isEmpty && model.document.url == x3 && model.tabs.count == n0 + 3,
              "open: a file outside this run's folders is refused in a scripted run (tabs \(names().suffix(3)), document \(model.document.url.lastPathComponent))")
        check(errors().dropFirst(refused0).contains { $0.contains("/usr/share/dict") }, "open: and the refusal is reported in the output panel")
        for u in stray { model.closeTab(u) }
        check(ExternalOpen.mayOpen(x1) && (!x1.path.hasPrefix("/var/") || ExternalOpen.mayOpen(URL(fileURLWithPath: "/private" + x1.path))),
              "open: a file in a fixture folder of the temporary folder is inside, by its /private spelling too")
        check(ExternalOpen.mayOpen(outside, scripted: false) && !ExternalOpen.mayOpen(outside, scripted: true), "open: a run that is not scripted opens anything, a scripted one only its own files")
        // 임시 폴더라고 다 이 실행의 것이 아니다: 다른 앱도 거기에 사본을 두고 "외부 편집기로 열기"로 넘긴다. 이름이 hyperedit- 로 시작하는 폴더 밖은 열지 않는다
        let foreign = fm.temporaryDirectory.appendingPathComponent("other-app-\(UUID().uuidString.prefix(8))", isDirectory: true), copy = foreign.appendingPathComponent("copy of notes.md")
        try? fm.createDirectory(at: foreign, withIntermediateDirectories: true)
        try? "COPY\n".write(to: copy, atomically: true, encoding: .utf8)
        let foreign0 = errors().count
        ExternalOpen.receive([copy]); await wait(300)
        let foreignTabs = model.tabs.filter { $0.lastPathComponent == copy.lastPathComponent }
        check(fm.fileExists(atPath: copy.path) && foreignTabs.isEmpty && model.document.url == x3 && errors().dropFirst(foreign0).contains { $0.contains(foreign.lastPathComponent) },
              "open: a file another app keeps in the temporary folder is refused and reported (tabs \(names().suffix(3)), document \(model.document.url.lastPathComponent))")
        for u in foreignTabs { model.closeTab(u) }
        try? fm.removeItem(at: foreign)
        // 경계: 임시 폴더 쪽은 바로 아래의 이름이 hyperedit- 로 시작하는 폴더 안이면 깊이와 상관없이, 시작 문서(`--file`) 쪽은 그 폴더 바로 아래의 파일만
        let tmp = URL(fileURLWithPath: "/tmp/hyperedit-test-root"), start = URL(fileURLWithPath: "/work/run")
        func may(_ path: String, start: URL? = start) -> Bool { ExternalOpen.mayOpen(URL(fileURLWithPath: path), scripted: true, temporary: tmp, startFolder: start) }
        check(may("/tmp/hyperedit-test-root/hyperedit-open-1/x.md") && may("/tmp/hyperedit-test-root/hyperedit-open-1/sub/deep/x.md") && may("/private/tmp/hyperedit-test-root/hyperedit-x/missing.md"),
              "open: scripted — anything under a hyperedit- folder of the temporary folder, however deep, a missing path and the /private spelling included")
        check(!may("/tmp/hyperedit-test-root/x.md") && !may("/tmp/hyperedit-test-root/hyperedit-loose.md") && !may("/tmp/hyperedit-test-root/OtherApp-1234/copy.md") && !may("/tmp/hyperedit-test-root/com.example.transfer/hyperedit-notes/x.md")
              && !may("/tmp/hyperedit-test-root/not-hyperedit-x/x.md") && !may("/tmp/hyperedit-test-root-2/hyperedit-x/x.md") && !may("/tmp/hyperedit-x/x.md"),
              "open: scripted — nothing else there: a loose file (even one named hyperedit-…), another app's folder, a hyperedit- folder inside one, a sibling of the temporary folder")
        check(may("/work/run/copy.md") && may("/work/run/missing.md") && !may("/work/run/sub/copy.md") && !may("/work/run-2/copy.md") && !may("/work/copy.md") && !may("/work/run")
              && !may("/work/run/copy.md", start: nil),
              "open: scripted — next to the start document only the files directly in its folder, not a subfolder, a sibling folder or the parent")

        // 잠금 중: 열지 않는다 (잠금 화면 뒤에서 문서·창 제목이 바뀌지 않는다) → 풀리면 연다
        let lock = model.appLock
        let realAuthenticator = lock.authenticator
        let fake = FakeAuthenticator()
        lock.authenticator = fake
        lock.lock(); await wait(200)
        let titleLocked = win.title
        NSApp.delegate?.application?(NSApp, open: [x4]); await wait(400)
        check(lock.isLocked && ExternalOpen.pendingCount == 1 && model.document.url == x3 && !model.tabs.contains(x4) && win.title == titleLocked,
              "open: while locked a request waits — document, tabs and window title unchanged (pending \(ExternalOpen.pendingCount), '\(win.title)')")
        check(fake.calls == 0, "open: a request does not start authentication by itself (\(fake.calls))")
        await lock.requestUnlock(); await wait(400)
        check(!lock.isLocked && ExternalOpen.pendingCount == 0 && model.document.url == x4 && text().hasPrefix("FOUR"), "open: after unlocking the waiting file opens (\(model.document.url.lastPathComponent))")
        lock.authenticator = realAuthenticator

        // 시트가 떠 있는 동안(스니펫 선택창): 미뤘다가 닫히면 연다
        model.showSnippetPicker = true
        for _ in 0..<40 where win.attachedSheet == nil { await wait(100) }
        if win.attachedSheet != nil {
            ExternalOpen.receive([x1]); await wait(400)
            check(ExternalOpen.pendingCount == 1 && model.document.url == x4, "open: a request waits while a sheet is up (pending \(ExternalOpen.pendingCount), \(model.document.url.lastPathComponent))")
            model.showSnippetPicker = false
            for _ in 0..<30 where model.document.url != x1 { await wait(100) }
            check(ExternalOpen.pendingCount == 0 && model.document.url == x1, "open: the waiting file opens once the sheet is gone (\(model.document.url.lastPathComponent))")
        } else {
            check(false, "open: the snippet sheet did not attach within 4 s — the sheet case did not run")
            model.showSnippetPicker = false; await wait(300)
            ExternalOpen.receive([x1]); await wait(300)
        }

        // 매크로 재생 중: 남은 걸음이 새 파일에 들어가지 않게 미뤘다가 재생이 끝나면 연다
        model.send(.perform { tv in tv.setSelectedRange(NSRange(location: 0, length: 0)) }); await wait(100)
        let before = text()
        let macro = Macro(name: "open-hold", steps: [.insert("m"), .command("deleteBackward:")])
        let playing = Task { @MainActor in await model.macros.play(macro, times: MacroRecorder.maxRepeat) }
        var sawPlaying = false, heldWhilePlaying = false
        for _ in 0..<1000 {
            if model.macros.isPlaying { sawPlaying = true; break }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        if sawPlaying {
            ExternalOpen.receive([x2])
            heldWhilePlaying = ExternalOpen.pendingCount == 1 && model.document.url == x1
        }
        let result = await playing.value
        for _ in 0..<30 where model.document.url != x2 { await wait(100) }
        if sawPlaying {
            check(heldWhilePlaying && model.document.url == x2 && ExternalOpen.pendingCount == 0, "open: a request waits while a macro is playing and opens afterwards (held \(heldWhilePlaying), \(model.document.url.lastPathComponent))")
            check((try? String(contentsOf: x1, encoding: .utf8)) == before && text().hasPrefix("TWO"),
                  "open: the macro finished in its own file and none of it went into the opened one (\(result?.iterations ?? -1) iterations)")
        } else {
            check(false, "open: the macro was never seen playing (\(result?.iterations ?? -1) iterations) — the macro case did not run")
            ExternalOpen.receive([x2]); await wait(300)
        }

        // 빠른 추가 패널이 떠 있는 동안. 빈 패널은 열기를 막지 않는다 — 그 패널은 다른 데를 눌러도 닫히지 않아, 열어 둔 채 잊으면 넘어온 파일이 끝없이 기다린다
        let qa = model.quickAppend
        qa.draft = ""
        qa.show()
        for _ in 0..<30 where !(qa.isVisible && qa.textView != nil) { await wait(100) }
        ExternalOpen.receive([x3]); await wait(500)
        check(qa.isVisible && ExternalOpen.pendingCount == 0 && model.document.url == x3,
              "open: an empty quick append panel does not hold a request back (panel \(qa.isVisible), pending \(ExternalOpen.pendingCount), \(model.document.url.lastPathComponent))")
        // 쓰던 메모가 있으면 미룬다: 패널은 지금 보이는 문서의 끝에 덧붙인다 — 쓰는 중에 문서가 바뀌면 ⌘↩ 가 엉뚱한 파일에 붙는다. 닫히면 연다
        let shown = model.document.url
        qa.textView?.insertText("note for the file that was showing", replacementRange: NSRange(location: 0, length: 0)); await wait(200)
        ExternalOpen.receive([x1]); await wait(500)
        check(qa.isVisible && qa.draft == "note for the file that was showing" && ExternalOpen.pendingCount == 1 && model.document.url == shown,
              "open: a request waits while a note is being written in the quick append panel (panel \(qa.isVisible), draft '\(qa.draft.prefix(8))', pending \(ExternalOpen.pendingCount), \(model.document.url.lastPathComponent))")
        qa.submit()
        for _ in 0..<30 where model.document.url != x1 { await wait(100) }
        check(!qa.isVisible && ExternalOpen.pendingCount == 0 && model.document.url == x1, "open: the waiting file opens once the panel is closed (\(model.document.url.lastPathComponent))")
        check(((try? String(contentsOf: shown, encoding: .utf8)) ?? "").hasSuffix("note for the file that was showing\n") && !text().contains("note for the file"),
              "open: the quick append note went to the file that was showing, not to the opened one")
        // 잠긴 동안 빠른 추가를 불렀고(풀리면 패널이 뜬다) 파일도 넘어와 있다: 풀리는 턴에 패널이 뜬다. 그 패널에 쓰던 메모가 남아 있으면(닫아도 초안은 남는다)
        // 파일은 패널이 닫힌 뒤에 열리고, 빈 패널이면 바로 열린다
        qa.draft = "draft kept from before the lock"
        let fake2 = FakeAuthenticator()
        lock.authenticator = fake2
        lock.lock(); await wait(200)
        ExternalOpen.receive([x4])
        qa.show()   // 잠겨 있으면 인증을 청하고 풀린 뒤에 뜬다
        for _ in 0..<30 where !(qa.isVisible && !lock.isLocked) { await wait(100) }
        await wait(400)
        check(!lock.isLocked && qa.isVisible && ExternalOpen.pendingCount == 1 && model.document.url == x1,
              "open: after unlocking into a quick append panel that holds a draft the waiting file still waits (locked \(lock.isLocked), panel \(qa.isVisible), pending \(ExternalOpen.pendingCount), \(model.document.url.lastPathComponent))")
        qa.hide()
        for _ in 0..<30 where model.document.url != x4 { await wait(100) }
        check(ExternalOpen.pendingCount == 0 && model.document.url == x4, "open: and opens when that panel is dismissed (\(model.document.url.lastPathComponent))")
        qa.draft = ""
        lock.lock(); await wait(200)
        ExternalOpen.receive([x2])
        qa.show()
        for _ in 0..<30 where !(qa.isVisible && !lock.isLocked) { await wait(100) }
        for _ in 0..<30 where model.document.url != x2 { await wait(100) }
        check(!lock.isLocked && qa.isVisible && ExternalOpen.pendingCount == 0 && model.document.url == x2,
              "open: after unlocking into an empty quick append panel the waiting file opens at once (panel \(qa.isVisible), pending \(ExternalOpen.pendingCount), \(model.document.url.lastPathComponent))")
        qa.hide()
        lock.authenticator = realAuthenticator

        // 떠나는 탭을 저장하지도 비상 사본으로 남기지도 못하면 그 탭에 머문다 — 넘어온 파일의 탭은 남아 나중에 누르면 열린다
        let roDir = dir.appendingPathComponent("ro", isDirectory: true), ro = roDir.appendingPathComponent("locked.md")
        try? fm.createDirectory(at: roDir, withIntermediateDirectories: true)
        try? "LOCKED\n".write(to: ro, atomically: true, encoding: .utf8)
        let rro = ro.resolvingSymlinksInPath()
        model.open(url: ro); await wait(400)
        try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: roDir.path)
        model.send(.perform { tv in tv.insertText("EDIT ", replacementRange: NSRange(location: 0, length: 0)) }); await wait(150)
        let keepOverride = AppDefaults.snapshotDirectoryOverride
        AppDefaults.snapshotDirectoryOverride = URL(fileURLWithPath: "/dev/null/hyperedit-no-snapshots")
        ExternalOpen.receive([x5]); await wait(400)
        check(model.document.url == rro && text().hasPrefix("EDIT LOCKED") && model.tabs.last == x5 && ExternalOpen.pendingCount == 0,
              "open: when the tab being left cannot be saved the app stays on it and the requested file keeps a tab (\(model.document.url.lastPathComponent), last tab \(names().last ?? "-"))")
        AppDefaults.snapshotDirectoryOverride = keepOverride
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: roDir.path)
        model.activateTab(x5); await wait(400)
        check(model.document.url == x5 && text().hasPrefix("FIVE") && (try? String(contentsOf: ro, encoding: .utf8)) == "EDIT LOCKED\n", "open: once the folder is writable the tab opens and the edit is saved")
        check(documentWindows() == windows0, "open: still one window after all requests (\(documentWindows()))")

        // 명령줄: 맨 인자는 실행 인자를 우리 문법으로 갈라서 얻는다 — 값을 받는 옵션의 목록(LaunchOptions.valueOptions)으로. AppKit 은 한 줄표로 시작하는 인자마다
        // 뒤의 인자를 값으로 짝지어, 옵션의 값을 파일이라며 넘기고 값 없는 옵션 바로 뒤의 파일은 삼킨다
        let harness = ["HyperEdit", "-ApplePersistenceIgnoreState", "YES", "--ephemeral", "--ephemeral-suite", "suite.name", "--file", "/p/start.md", "--realuse", "--realuse-out",
                       "build/out", "--quit", "--realuse-only", "smoke,tabs-bar", "/p/a.md", "b.md"]
        check(LaunchOptions.files(in: harness) == ["/p/a.md", "b.md"] && LaunchOptions.parse(harness).values.map(\.value) == ["YES", "suite.name", "/p/start.md", "build/out", "smoke,tabs-bar"],
              "open: launch option values are told apart from files given on the command line (\(LaunchOptions.files(in: harness)))")
        check(LaunchOptions.files(in: ["HyperEdit", "--ephemeral", "--quit", "a.md"]) == ["a.md"] && LaunchOptions.files(in: ["HyperEdit", "--ephemeral", "a.md"]) == ["a.md"]
              && LaunchOptions.files(in: ["HyperEdit", "a.md", "--ephemeral", "b.md", "--locked"]) == ["a.md", "b.md"],
              "open: a file after an option that takes no value is a file (\(LaunchOptions.files(in: ["HyperEdit", "--ephemeral", "--quit", "a.md"])))")
        check(LaunchOptions.files(in: ["HyperEdit", "-AppleLanguages", "(ar)", "x.md"]) == ["x.md"] && LaunchOptions.files(in: ["HyperEdit", "--split", "vertical", "x.md"]) == ["x.md"]
              && LaunchOptions.files(in: ["HyperEdit", "--split", "x.md"]) == ["x.md"] && LaunchOptions.files(in: ["HyperEdit", "--theme"]).isEmpty,
              "open: the value of a system option is not a file; --split takes a value only when it is a split mode")
        // 목록과 `value` 호출이 어긋날 수 없다: 목록에 없는 옵션은 값을 돌려받지 못한다 (넣는 것을 잊으면 그 옵션이 먹지 않아 바로 드러난다)
        check(LaunchOptions.valueOptions.allSatisfy { LaunchOptions.value($0, in: ["HyperEdit", $0, "v"]) == "v" } && LaunchOptions.value("--not-an-option", in: ["HyperEdit", "--not-an-option", "v"]) == nil
              && LaunchOptions.value("--split", in: ["HyperEdit", "--split", "horizontal"]) == "horizontal" && LaunchOptions.value("--split", in: ["HyperEdit", "--split", "x.md"]) == nil,
              "open: only a listed option gets a value (\(LaunchOptions.valueOptions.count) listed)")
        ExternalOpen.receive(commandLine: [x1.path]); await wait(300)   // 인자마다 따로 온다 — 모았다가 다음 턴에 연다
        check(model.document.url == x1, "open: a file given on the command line opens (\(model.document.url.lastPathComponent))")

        model.activateTab(base); await wait(300)
        model.closeTabs(in: dir)
        try? fm.removeItem(at: dir)
        check(model.document.url == base && model.tabs.count == n0, "open: back on \(base.lastPathComponent) with the tabs as before (\(model.tabs.count), was \(n0))")
    }
}
