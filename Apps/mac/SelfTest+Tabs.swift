import AppKit
import UniformTypeIdentifiers
import HyperCore

// 셀프테스트: 파일 탭 (UltraEdit 식) — 열기/전환/내용·보기 위치 유지/다음·이전/최근 순서/순서 바꾸기·정렬/닫기/다시 열기/세션 저장/사라진 파일
extension SelfTest {
    @MainActor
    static func runTabs(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { pumpEvent(); try? await Task.sleep(nanoseconds: ms * 1_000_000) }
        func text() -> String { model.document.textStorage.string }
        func names() -> [String] { model.tabs.map(\.lastPathComponent) }
        guard let tv = model.session.primary?.textView else { check(false, "tabs: primary editor available"); return }
        let base = model.document.url
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hyperedit-tabs-\(UUID().uuidString.prefix(8))", isDirectory: true)
        let a = dir.appendingPathComponent("a.md"), b = dir.appendingPathComponent("b.md"), c = dir.appendingPathComponent("c.txt")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try ("AAA\n" + (1...300).map { "line \($0) of a" }.joined(separator: "\n") + "\n").write(to: a, atomically: true, encoding: .utf8)
            try "BBB\n".write(to: b, atomically: true, encoding: .utf8)
            try "CCC\n".write(to: c, atomically: true, encoding: .utf8)
        } catch { check(false, "tabs: cannot create samples: \(error)"); return }
        let ra = a.resolvingSymlinksInPath(), rb = b.resolvingSymlinksInPath(), rc = c.resolvingSymlinksInPath()
        let n0 = model.tabs.count
        model.open(url: a); await wait(400)
        model.open(url: b); await wait(400)
        check(model.tabs.count == n0 + 2 && model.document.url == rb, "tabs: opening two files adds two tabs and activates the last (\(model.tabs.count - n0), \(model.document.url.lastPathComponent))")
        check(Array(model.tabs.suffix(2)) == [ra, rb], "tabs: new tabs go to the end in opening order (\(names().suffix(2)))")
        model.open(url: a); await wait(300)
        check(model.tabs.count == n0 + 2 && model.document.url == ra, "tabs: opening an open file switches to its tab without adding one")
        // 탭을 떠나면 편집이 저장되고, 돌아오면 내용과 캐럿이 그대로다
        model.send(.perform { tv in tv.breakUndoCoalescing(); tv.insertText("X", replacementRange: NSRange(location: 0, length: 0)) }); await wait(150)
        let caretInA = (tv.string as NSString).lineRange(for: NSRange(location: 2000, length: 0)).location
        model.send(.perform { tv in tv.setSelectedRange(NSRange(location: caretInA, length: 0)); tv.scrollRangeToVisible(tv.selectedRange()) }); await wait(1000)   // 보기 위치 저장(0.8 s)
        check(model.document.isDirty, "tabs: the edited tab is dirty before leaving it")
        model.activateTab(rb); await wait(400)
        let onDisk = (try? String(contentsOf: a, encoding: .utf8)) ?? ""
        check(text().hasPrefix("BBB") && model.document.url == rb, "tabs: switching shows the other file ('\(text().prefix(3))')")
        check(onDisk.hasPrefix("XAAA"), "tabs: leaving a dirty tab saves it ('\(onDisk.prefix(4))')")
        model.activateTab(ra); await wait(500)
        check(text().hasPrefix("XAAA") && !model.document.isDirty, "tabs: coming back shows the saved edit ('\(text().prefix(4))', dirty \(model.document.isDirty))")
        check(tv.selectedRange().location == caretInA, "tabs: the caret position is restored per tab (\(tv.selectedRange().location), expected \(caretInA))")
        // 다음/이전 (순환) · 직전 탭
        model.open(url: c); await wait(300)
        check(model.document.url == rc && model.tabs.last == rc, "tabs: a third file opens as the last tab")
        model.nextTab(); await wait(300)
        check(model.document.url == model.tabs.first, "tabs: next from the last tab wraps to the first (\(model.document.url.lastPathComponent))")
        model.previousTab(); await wait(300)
        check(model.document.url == rc, "tabs: previous from the first tab wraps to the last")
        model.activateTab(ra); await wait(250); model.activateTab(rb); await wait(250)
        model.activateLastActiveTab(); await wait(250)
        check(model.document.url == ra, "tabs: last-active switching goes back to the previously viewed tab (\(model.document.url.lastPathComponent))")
        model.activateLastActiveTab(); await wait(250)
        check(model.document.url == rb, "tabs: last-active switching toggles between the two most recent tabs")
        // 순서 바꾸기 · 정렬 · 세션 저장
        model.moveTab(rc, to: 0)
        check(model.tabs.first == rc, "tabs: a tab can be moved to the front")
        model.sortTabs(by: .name)
        check(names() == names().sorted { $0.localizedStandardCompare($1) == .orderedAscending }, "tabs: sort by name orders the tabs (\(names()))")
        let session = AppDefaults.store.stringArray(forKey: AppModel.openDocumentsKey) ?? []
        check(session == model.tabs.map(\.path), "tabs: the open tabs are persisted in order (\(session.count))")
        // 활성 탭 닫기 → 왼쪽 이웃 (UltraEdit nearest left)
        model.moveTab(ra, to: model.tabs.count); model.moveTab(rb, to: model.tabs.count)   // … a, b
        model.activateTab(rb); await wait(250)
        model.closeTab(rb); await wait(400)
        check(!model.tabs.contains(rb) && model.document.url == ra, "tabs: closing the active tab activates its left neighbour (\(model.document.url.lastPathComponent))")
        model.reopenLastClosedTab(); await wait(400)
        check(model.document.url == rb && model.tabs.last == rb, "tabs: reopen last closed tab brings b.md back as the last tab")
        // 비활성 탭 닫기는 활성 탭을 바꾸지 않는다
        model.closeTab(rc); await wait(150)
        check(model.document.url == rb && !model.tabs.contains(rc), "tabs: closing an inactive tab keeps the active one")
        // 보고 있지 않던 탭을 더블클릭해 닫으면 (첫 클릭이 그 탭으로 전환했더라도) 보던 탭으로 돌아간다. 보던 탭을 더블클릭하면 왼쪽 이웃
        model.open(url: c); await wait(300)                                                   // … a, b, c
        model.activateTab(ra); await wait(250)
        model.tabClicked(rc)                                                                  // 더블클릭의 첫 클릭: 바로 전환한다 (동기)
        let switchedByClick = model.document.url == rc
        model.tabDoubleClicked(rc); await wait(400)                                           // 두 번째 클릭 (같은 이벤트 시각 안)
        check(switchedByClick && !model.tabs.contains(rc) && model.document.url == ra,
              "tabs: double-clicking a background tab closes it and returns to the tab being viewed (\(model.document.url.lastPathComponent))")
        model.open(url: c); await wait(300)                                                   // … a, b, c (c 를 보고 있다 — 클릭으로 온 것이 아니다)
        model.tabClicked(rc); model.tabDoubleClicked(rc); await wait(400)
        check(!model.tabs.contains(rc) && model.document.url == rb, "tabs: double-clicking the viewed tab closes it and goes to the left neighbour (\(model.document.url.lastPathComponent))")
        // 사라진 파일의 탭을 누르면 탭만 걷어낸다 (빈 파일을 새로 만들지 않는다)
        try? FileManager.default.removeItem(at: a)
        model.activateTab(ra); await wait(250)
        check(!model.tabs.contains(ra) && model.document.url == rb && !FileManager.default.fileExists(atPath: a.path), "tabs: a tab whose file is gone is dropped instead of creating an empty file")
        // 파일에서 찾기 결과가 가리키는 파일이 그 사이 지워졌으면 열지 않는다 (빈 파일·빈 탭을 만들지 않는다)
        model.open(hit: FileSearchHit(url: a, line: 1, column: 1, lineText: "AAA", matchInLine: NSRange(location: 0, length: 3))); await wait(350)
        check(!model.tabs.contains(ra) && model.document.url == rb && !FileManager.default.fileExists(atPath: a.path), "tabs: a find-in-files hit in a deleted file opens nothing")
        // 활성 탭을 닫을 때 옮겨 갈 왼쪽 이웃의 파일이 사라졌으면 그 탭도 함께 걷어내고 그다음 탭으로 간다
        let g = dir.appendingPathComponent("gone.md")
        try? "GONE\n".write(to: g, atomically: true, encoding: .utf8)
        let rg = g.resolvingSymlinksInPath()
        model.open(url: g); await wait(250); model.open(url: c); await wait(300)                // … b, gone, c (c 활성)
        try? FileManager.default.removeItem(at: g)
        model.closeTab(rc); await wait(400)
        check(!model.tabs.contains(rg) && !model.tabs.contains(rc) && model.document.url == rb && !FileManager.default.fileExists(atPath: g.path),
              "tabs: closing the active tab also drops a neighbour whose file is gone (\(names()))")
        // 편집 전 내용의 스냅샷은 파일마다 실행당 한 번 — 탭을 오갈 때마다 새로 찍으면 파일별 보관 칸이 금방 돈다. 편집 직후(자동 저장 전) 떠나도 찍힌다
        let fm = FileManager.default
        func snapshots(_ prefix: String, _ suffix: String) -> [URL] {
            ((try? fm.contentsOfDirectory(at: MemoDocument.snapshotDirectory, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.lastPathComponent.hasSuffix(suffix) }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        for round in 1...2 {
            model.send(.perform { tv in tv.insertText("\(round)", replacementRange: NSRange(location: 0, length: 0)) }); await wait(120)
            model.activateTab(base); await wait(250)
            model.activateTab(rb); await wait(250)
        }
        check(text().hasPrefix("21BBB") && snapshots("b.md-", "-before-first-save.txt").count == 1,
              "tabs: leaving right after an edit snapshots the file once per run (\(snapshots("b.md-", "-before-first-save.txt").count), '\(text().prefix(6))')")
        // 떠나는 파일의 저장이 실패하면(쓰기 불가 폴더) 메모리의 내용을 비상 사본으로 남기고 전환한다 — 편집이 조용히 사라지지 않는다
        let roDir = dir.appendingPathComponent("ro", isDirectory: true), ro = roDir.appendingPathComponent("locked.md")
        try? fm.createDirectory(at: roDir, withIntermediateDirectories: true)
        try? "LOCKED\n".write(to: ro, atomically: true, encoding: .utf8)
        let rro = ro.resolvingSymlinksInPath()
        model.open(url: ro); await wait(400)
        try? fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: roDir.path)
        model.send(.perform { tv in tv.insertText("EDIT ", replacementRange: NSRange(location: 0, length: 0)) }); await wait(150)
        let copiesBefore = snapshots("locked.md-", "-unsaved.txt").count
        model.activateTab(rb); await wait(400)
        let copies = snapshots("locked.md-", "-unsaved.txt")
        check(model.document.url == rb && copies.count == copiesBefore + 1 && (copies.last.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "").hasPrefix("EDIT LOCKED"),
              "tabs: leaving a file that cannot be saved writes an emergency copy of the unsaved text (\(copies.count - copiesBefore))")
        check((try? String(contentsOf: ro, encoding: .utf8)) == "LOCKED\n", "tabs: the unwritable file on disk is unchanged")
        // 비상 사본도 쓸 수 없으면 떠나지 않는다 — 전환도 닫기도 거절하고 글은 그대로 남는다
        model.activateTab(rro); await wait(400)
        model.send(.perform { tv in tv.insertText("AGAIN ", replacementRange: NSRange(location: 0, length: 0)) }); await wait(150)
        let keepOverride = AppDefaults.snapshotDirectoryOverride
        AppDefaults.snapshotDirectoryOverride = URL(fileURLWithPath: "/dev/null/hyperedit-no-snapshots")
        model.activateTab(rb); await wait(300)
        let stayedOnSwitch = model.document.url == rro && model.document.isDirty
        model.closeTab(rro); await wait(300)
        check(stayedOnSwitch && model.document.url == rro && model.tabs.contains(rro) && text().hasPrefix("AGAIN LOCKED"),
              "tabs: when neither the save nor an emergency copy works, switching and closing are refused and the text stays (\(model.document.url.lastPathComponent))")
        AppDefaults.snapshotDirectoryOverride = keepOverride
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: roDir.path)
        model.closeTab(rro); await wait(400)
        check(!model.tabs.contains(rro) && (try? String(contentsOf: ro, encoding: .utf8)) == "AGAIN LOCKED\n", "tabs: once the folder is writable again, closing saves the text")
        // 다른 탭 모두 닫기 · 왼쪽 탭 닫기 · 모두 닫기 · 정리
        model.activateTab(base); await wait(300)
        model.closeOtherTabs(); await wait(150)
        check(model.tabs == [base] && model.document.url == base, "tabs: close other tabs leaves only the active one (\(names()))")
        model.open(url: b); await wait(250); model.open(url: c); await wait(300)                // base, b, c (c 활성)
        model.closeTabs(toLeftOf: rc); await wait(300)
        check(model.tabs == [rc] && model.document.url == rc, "tabs: close tabs to the left keeps the clicked tab (\(names()))")
        model.closeAllTabs(); await wait(400)
        check(model.tabs == [model.defaultDocumentURL] && model.document.url == model.defaultDocumentURL, "tabs: close all tabs leaves the default document (\(names()))")
        model.open(url: base); await wait(400)
        model.closeTab(model.defaultDocumentURL); await wait(150)
        check(model.tabs == [base] && model.document.url == base, "tabs: the default document's tab can be closed once another file is open")
        model.closeTabs(in: dir)
        try? FileManager.default.removeItem(at: dir)
        check(model.document.url == base, "tabs: back on \(base.lastPathComponent)")
        await runTabDrag(model: model, check: check, log: log)
    }

    /// 탭 끌어 순서 바꾸기의 양 끝(`TabDrag`): 전용 형식의 선언 · 끌 때 나가는 것 · 놓였을 때의 순서 변경. 실제 끌기 세션은 열지 않는다(실제 마우스를 따라간다) —
    /// 끌 때 만들어지는 provider 를 그대로 놓는 쪽에 건넨다. SwiftUI 가 하는 부분(끌기 시작, 어느 탭 위인지 판정, 끄는 동안의 모양)은 여기서 볼 수 없다
    @MainActor
    static func runTabDrag(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { pumpEvent(); try? await Task.sleep(nanoseconds: ms * 1_000_000) }
        /// provider 들을 `target` 탭 위에 놓고 처리가 끝날 때까지 기다린다 (경로는 비동기로 읽힌다)
        func drop(_ providers: [NSItemProvider], on target: URL) async -> (accepted: Bool, moved: Bool) {
            await withCheckedContinuation { c in
                let accepted = TabDrag.drop(providers, on: target, model: model) { moved in c.resume(returning: (true, moved)) }
                if !accepted { c.resume(returning: (false, false)) }
            }
        }
        let fm = FileManager.default
        let base = model.document.url
        let dir = fm.temporaryDirectory.appendingPathComponent("hyperedit-tabdrag-\(UUID().uuidString.prefix(8))", isDirectory: true)
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch { check(false, "tab drag: cannot create samples: \(error)"); return }
        func make(_ name: String) -> URL {
            let u = dir.appendingPathComponent(name)
            try? "\(name)\n".write(to: u, atomically: true, encoding: .utf8)
            return u.resolvingSymlinksInPath()
        }
        let d1 = make("d1.md"), d2 = make("d2.md"), d3 = make("d3.md"), ko = make("탭 끌기 — 한글 이름.md")
        for u in [d1, d2, d3, ko] { model.open(url: u); await wait(200) }
        let n0 = model.tabs.count - 4
        func slice() -> [URL] { Array(model.tabs.dropFirst(n0)) }
        func label(_ list: [URL]) -> String { list.map { $0 == ko ? "ko" : $0.deletingPathExtension().lastPathComponent }.joined(separator: " ") }
        guard n0 >= 1, slice() == [d1, d2, d3, ko], model.document.url == ko else { check(false, "tab drag: four sample tabs open (\(label(slice())))"); return }

        // 형식 선언: 전용 형식이 Info.plist 에 내보내는 형식으로 선언돼 있다 (선언이 없으면 UTType(exportedAs:) 는 임시 형식이 돼 다른 프로세스·재실행 사이에 같다는 보장이 없다)
        let id = "io.github.hyeongcheol-an.hyperedit.tab"
        let declared = (Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]])?.first { $0["UTTypeIdentifier"] as? String == id }
        check(UTType.hyperEditTab.identifier == id && ((declared?["UTTypeConformsTo"] as? [String]) ?? []).contains("public.data"),
              "tab drag: the tab type is declared in Info.plist as an exported type conforming to public.data (\(declared == nil ? "missing" : "found"))")
        log("tab drag: UTType \(id) declared to the system: \(UTType.hyperEditTab.isDeclared), dynamic: \(UTType.hyperEditTab.isDynamic)")
        check(!UTType.hyperEditTab.conforms(to: .text) && !UTType.hyperEditTab.conforms(to: .url), "tab drag: the tab type is neither text nor a URL")

        // 끌 때 나가는 것: 전용 형식 하나뿐 — 글·URL 로는 읽을 수 없다(편집기 위에 놓아도 경로가 삽입되지 않는다). 내용은 탭의 경로(UTF-8)
        let dragged = TabDrag.provider(for: ko)
        check(dragged.registeredTypeIdentifiers == [id] && !dragged.canLoadObject(ofClass: NSString.self) && !dragged.canLoadObject(ofClass: NSURL.self)
              && !dragged.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) && !dragged.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
              "tab drag: a dragged tab carries only the tab type (\(dragged.registeredTypeIdentifiers))")
        let payload: Data? = await withCheckedContinuation { c in _ = dragged.loadDataRepresentation(forTypeIdentifier: id) { data, _ in c.resume(returning: data) } }
        check(payload.flatMap { String(data: $0, encoding: .utf8) } == ko.path, "tab drag: the payload is the tab's path, also for a non-ASCII name (\(payload?.count ?? -1) bytes)")

        // 놓기: 끌어온 탭이 놓인 탭의 자리로 간다 — 왼쪽에서 오면 그 탭 뒤, 오른쪽에서 오면 앞. 활성 탭은 바뀌지 않고 세션에 순서가 저장된다
        var r = await drop([TabDrag.provider(for: d1)], on: d3)
        check(r.accepted && r.moved && slice() == [d2, d3, d1, ko], "tab drag: a tab dropped on a tab to its right takes that place (\(label(slice())))")
        r = await drop([TabDrag.provider(for: ko)], on: d2)
        check(r.accepted && r.moved && slice() == [ko, d2, d3, d1], "tab drag: a tab dropped on a tab to its left takes that place (\(label(slice())))")
        check(model.document.url == ko && (AppDefaults.store.stringArray(forKey: AppModel.openDocumentsKey) ?? []) == model.tabs.map(\.path),
              "tab drag: reordering keeps the active tab and saves the order (\(model.document.url.lastPathComponent))")
        // 맨 앞 · 맨 뒤 (다른 파일의 탭들까지 포함한 줄 전체에서)
        if let first = model.tabs.first, let last = model.tabs.last {
            r = await drop([TabDrag.provider(for: last)], on: first)
            check(r.moved && model.tabs.first == last && model.tabs.count == n0 + 4, "tab drag: the last tab dropped on the first becomes the first (\(model.tabs.first?.lastPathComponent ?? "-"))")
            if let end = model.tabs.last {
                r = await drop([TabDrag.provider(for: last)], on: end)
                check(r.moved && model.tabs.last == last && model.tabs.first == first, "tab drag: the first tab dropped on the last becomes the last (\(model.tabs.last?.lastPathComponent ?? "-"))")
            }
        }
        // 아무것도 바꾸지 않는 놓기: 자기 자신 위 · 탭이 아닌 경로 · 그 사이 닫힌 탭 위 · UTF-8 이 아닌 내용
        let order = model.tabs
        r = await drop([TabDrag.provider(for: d2)], on: d2)
        check(r.accepted && !r.moved && model.tabs == order, "tab drag: a tab dropped on itself stays where it is")
        r = await drop([TabDrag.provider(for: dir.appendingPathComponent("not-a-tab.md"))], on: d2)
        check(r.accepted && !r.moved && model.tabs == order, "tab drag: a path that is not a tab moves nothing")
        r = await drop([TabDrag.provider(for: d1)], on: dir.appendingPathComponent("closed-meanwhile.md"))
        check(!r.moved && model.tabs == order, "tab drag: a drop on a tab that is gone moves nothing")
        let garbage = NSItemProvider()
        garbage.registerDataRepresentation(forTypeIdentifier: id, visibility: .ownProcess) { done in done(Data([0xFF, 0xFE, 0xFD]), nil); return nil }
        r = await drop([garbage], on: d2)
        check(r.accepted && !r.moved && model.tabs == order, "tab drag: a payload that is not a path moves nothing")
        // 다른 형식(편집기에서 끌어온 글, Finder 의 파일)은 받지 않는다. 섞여 있으면 탭 형식만 쓴다
        r = await drop([NSItemProvider(object: d1.path as NSString)], on: d2)
        let textRefused = !r.accepted && model.tabs == order
        r = await drop([NSItemProvider(object: d1 as NSURL)], on: d2)
        check(textRefused && !r.accepted && model.tabs == order, "tab drag: text and file URLs dropped on a tab are refused")
        r = await drop([], on: d2)
        check(!r.accepted, "tab drag: a drop with nothing in it is refused")
        r = await drop([NSItemProvider(object: d3.path as NSString), TabDrag.provider(for: d3)], on: d2)
        check(r.accepted && r.moved && model.tabs != order && Set(model.tabs) == Set(order), "tab drag: among mixed items the tab one is used")

        model.activateTab(base); await wait(300)
        model.closeTabs(in: dir)
        try? fm.removeItem(at: dir)
        check(model.document.url == base && model.tabs.count == n0, "tab drag: back on \(base.lastPathComponent)")
    }
}
