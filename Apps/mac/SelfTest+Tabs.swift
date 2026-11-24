import AppKit
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
        // 사라진 파일의 탭을 누르면 탭만 걷어낸다 (빈 파일을 새로 만들지 않는다)
        try? FileManager.default.removeItem(at: a)
        model.activateTab(ra); await wait(250)
        check(!model.tabs.contains(ra) && model.document.url == rb && !FileManager.default.fileExists(atPath: a.path), "tabs: a tab whose file is gone is dropped instead of creating an empty file")
        // 다른 탭 모두 닫기 · 정리
        model.activateTab(base); await wait(300)
        model.closeOtherTabs(); await wait(150)
        check(model.tabs == [base] && model.document.url == base, "tabs: close other tabs leaves only the active one (\(names()))")
        model.closeTabs(in: dir)
        try? FileManager.default.removeItem(at: dir)
        check(model.document.url == base, "tabs: back on \(base.lastPathComponent)")
    }
}
