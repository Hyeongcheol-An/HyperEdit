import AppKit

// 셀프테스트: 자동화 실행의 격리 (AutomationRun.swift). 테스트 빌드는 설치된 앱과 번들 ID 가 같아 설정 도메인을 같이 쓴다 — 이 실행이 사용자의 것을
// 건드리지 않는가: 설정에 저장되는 창 프레임(`NSWindow Frame …`), 포커스(활성화되면 물러난다 · 빠른 추가 패널이 키 입력을 가져가지 않는다),
// 전역 단축키(시스템에 등록하지 않는다).
// 맨 끝에 돈다 — 실행 전체에서 이 실행의 창이 저장값을 바꾼 적이 없는지도 본다. 같은 검사를 실사용 하네스의 `automation-isolated` 가 쓴다
extension SelfTest {
    @MainActor
    static func runIsolation(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        guard let win = model.session.primary?.textView?.window else { check(false, "isolation: editor window available"); return }
        for r in IsolationProbe.windowFrames(win) { check(r.ok, "isolation: " + r.what) }
        for r in await IsolationProbe.background(model: model) { check(r.ok, "isolation: " + r.what) }
        for r in await IsolationProbe.globalShortcut(model: model) { check(r.ok, "isolation: " + r.what) }
        log("isolation: the app was activated \(AppDelegate.stepBacks) times during this run and stepped back each time")
    }
}

/// 격리 검사 — 셀프테스트(`runIsolation`)와 실사용 하네스(`automation-isolated`)가 같이 쓴다. 결과: 통과했는가, 무엇을 보았는가
@MainActor
enum IsolationProbe {
    typealias Result = (ok: Bool, what: String)

    /// 포커스: 앞에서 돌라고 하지 않은 스크립트 실행은 활성화되면 물러나는가, 빠른 추가 패널을 띄워도 키 입력을 가져가지 않는가
    static func background(model: AppModel) async -> [Result] {
        let foreground = ["--selftest-foreground", "--bench-foreground", "--snapshot-activate"].filter { LaunchOptions.has($0) }
        guard AutomationRun.isScripted, foreground.isEmpty else { return [(true, "not a background run (\(foreground.joined(separator: " "))) — stepping back was not checked")] }
        var results: [Result] = [(!NSApp.isActive, "a scripted run is not the active app (active \(NSApp.isActive), stepped back \(AppDelegate.stepBacks) times so far)")]
        // 활성화 알림을 받았을 때 하는 일을 직접 부른다 (실제로 활성화하지는 않는다 — 다른 앱의 포커스를 뺏는다)
        let stepsBack = AppDelegate.stepBackIfAutomated()
        results.append((stepsBack && AppDelegate.automationStaysInBackground && !NSApp.isActive, "a scripted run steps back when it is activated (steps back \(stepsBack))"))
        // 빠른 추가 패널: 뒤에서 도는 동안에는 다른 창 위에 뜨지도, 키 창이 되지도 않는다
        guard !NSApp.isActive else { return results }
        let qa = model.quickAppend
        let wasVisible = qa.isVisible
        qa.show()
        for _ in 0..<20 where !qa.isVisible { try? await Task.sleep(nanoseconds: 50_000_000) }
        results.append((qa.isVisible && !qa.floatsAboveOtherWindows && !qa.isKeyWindow && !NSApp.isActive,
                        "the quick append panel of a background run does not float or take the keyboard (visible \(qa.isVisible), floating \(qa.floatsAboveOtherWindows), key \(qa.isKeyWindow), app active \(NSApp.isActive))"))
        if !wasVisible { qa.hide() }
        return results
    }

    /// 전역 단축키: 스크립트가 모는 실행은 시스템에 등록하지 않는가. 등록 없이도 눌림 → 패널 여닫기의 길은 그대로인가
    static func globalShortcut(model: AppModel) async -> [Result] {
        guard AutomationRun.isScripted else { return [(true, "not a scripted run — the global shortcut is registered as usual")] }
        var results: [Result] = [(!GlobalHotKey.registersWithSystem && GlobalHotKey.systemRegistrationCount == 0,
                                  "a scripted run registers no global shortcut with the system (\(GlobalHotKey.systemRegistrationCount) registered)")]
        let qa = model.quickAppend
        guard let shortcut = QuickAppendController.hotkeyOptions.first(where: { $0.id == qa.hotkeyID })?.shortcut else {
            results.append((!qa.isHotKeyRegistered && GlobalHotKey.registeredCount == 0, "the shortcut is set to off and nothing is on the books (\(qa.hotkeyID))"))
            return results
        }
        // 장부는 보통 실행과 같다: 설정한 조합 하나가 등록된 것으로 적혀 있다 (설정 화면의 문구도 같다)
        results.append((qa.isHotKeyRegistered && !qa.hotkeyFailed && GlobalHotKey.registeredCount == 1, "the controller keeps its shortcut on the books ('\(qa.hotkeyStatus)', \(GlobalHotKey.registeredCount))"))
        // 눌림: Carbon 이벤트 처리기가 타는 것과 같은 길 — 등록된 클로저 → toggle. 떠 있는 키 패널을 만들지 않게 뒤에서 돌 때만 한다
        guard !NSApp.isActive else { return results }
        func settle(until visible: Bool) async { for _ in 0..<20 where qa.isVisible != visible { try? await Task.sleep(nanoseconds: 50_000_000) } }
        let wasVisible = qa.isVisible
        let known = GlobalHotKey.press(shortcut)
        await settle(until: !wasVisible)
        results.append((known && qa.isVisible == !wasVisible, "pressing the shortcut toggles the quick append panel (was visible \(wasVisible), now \(qa.isVisible))"))
        GlobalHotKey.press(shortcut)
        await settle(until: wasVisible)
        results.append((qa.isVisible == wasVisible, "pressing it again toggles the panel back (\(qa.isVisible))"))
        if qa.isVisible != wasVisible { wasVisible ? qa.show() : qa.hide() }
        return results
    }

    /// 창 프레임: 이 실행의 창이 설정의 `NSWindow Frame …` 을 쓰지도 읽지도 않는가
    static func windowFrames(_ win: NSWindow) -> [Result] {
        var results: [Result] = [(AutomationRun.isIsolated && AutomationRun.keepsWindowFramesOut, "this run keeps window frames out of the defaults")]
        // 막혀 있지 않으면 아래의 저장 시도가 사용자의 설정에 그대로 적힌다 — 하지 않는다
        guard AutomationRun.keepsWindowFramesOut else { return results }
        let defaults = UserDefaults.standard
        let probe = "hyperedit-isolation-probe", key = "NSWindow Frame " + probe
        func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }

        // 이름을 주어 저장 (SwiftUI 가 WindowGroup 의 창에 하는 그대로)
        let refused = AutomationRun.refusedWindowFrameSaves
        win.saveFrame(usingName: probe)
        let written = defaults.object(forKey: key) != nil
        if written { defaults.removeObject(forKey: key) }
        results.append((!written && AutomationRun.refusedWindowFrameSaves == refused + 1, "a window frame saved by name does not reach the defaults (written \(written))"))

        // 자동 저장 이름 (설정 창·패널의 길): 이름이 걸리지 않는다
        let named = win.setFrameAutosaveName(probe)
        let name = win.frameAutosaveName
        if !name.isEmpty { win.setFrameAutosaveName(""); defaults.removeObject(forKey: key) }
        results.append((!named && name.isEmpty, "a window does not take a frame autosave name ('\(name)')"))

        // 읽기: 설정에 있는 저장값(설치된 앱의 창)으로 이 창이 옮겨 가지 않는다
        let frame = win.frame
        if let saved = AutomationRun.savedWindowFrames().keys.sorted().first {
            let savedName = String(saved.dropFirst("NSWindow Frame ".count))
            let applied = win.setFrameUsingName(savedName) || win.setFrameUsingName(savedName, force: true)
            let moved = win.frame != frame
            if moved { win.setFrame(frame, display: true) }
            results.append((!applied && !moved, "a saved window frame is not read (applied \(applied), moved \(moved))"))
        } else {
            results.append((true, "no window frame is saved in the defaults — reading one was not tried"))
        }

        // SwiftUI 자신의 저장: 창이 키 창이 될 때 한다 → 그 처리기를 직접 부른다 (앱을 활성화하지 않는다). 저장하려 했는지는 거절 수로 본다
        let before = AutomationRun.savedWindowFrames(), asked = AutomationRun.refusedWindowFrameSaves
        win.delegate?.windowDidBecomeKey?(Notification(name: NSWindow.didBecomeKeyNotification, object: win))
        win.delegate?.windowDidResignKey?(Notification(name: NSWindow.didResignKeyNotification, object: win))
        let mine = trimmed(win.frameDescriptor)
        let wrote = AutomationRun.savedWindowFrames().filter { before[$0.key] != $0.value && trimmed($0.value) == mine }
        results.append((wrote.isEmpty && AutomationRun.refusedWindowFrameSaves > asked, "the frame SwiftUI saves when its window becomes key does not reach the defaults (asked \(AutomationRun.refusedWindowFrameSaves - asked) times, delegate \(win.delegate.map { String(describing: type(of: $0)) } ?? "none"))"))

        // 실행 전체: 시작한 뒤로 이 실행의 창이 바꾼 저장값이 없다
        let byThisRun = AutomationRun.windowFramesWrittenByThisRun()
        results.append((byThisRun.isEmpty, "no saved window frame was changed by this run (\(AutomationRun.refusedWindowFrameSaves) saves refused since launch)\(byThisRun.isEmpty ? "" : " — \(byThisRun)")"))
        return results
    }
}
