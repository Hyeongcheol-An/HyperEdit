import SwiftUI
import AppKit
import LocalAuthentication
import HyperCore

// applock 셀프테스트: 수동 잠금 → 오버레이(표식 NSView)·hitTest·키 입력 차단(허용 목록만 통과)·메뉴 추적 취소·Quick Append 차단 →
// 가짜 인증기 실패/취소/성공 → Return 키 해제 → 유휴 타이머(1초 주입)·입력으로 재시작 → 잠자기/화면 잠금 연동 규칙 → 설정 저장/복원 → 타이핑 지연.
// 실제 Touch ID 프롬프트는 띄우지 않는다 (인증기를 가짜로 바꿔 끼운다).
extension SelfTest {
    /// 주입용 인증기: 결과를 정해 두고 호출 횟수를 센다
    @MainActor
    final class FakeAuthenticator: Authenticator {
        var isAvailable = true
        var biometry: LABiometryType = .touchID
        var result: AuthenticationResult = .success
        private(set) var calls = 0
        private(set) var lastReason = ""
        func authenticate(reason: String) async -> AuthenticationResult { calls += 1; lastReason = reason; return result }
    }

    /// NSView 트리에서 identifier 로 뷰 찾기 (LockOverlay 의 표식)
    @MainActor
    static func view(withIdentifier id: String, in root: NSView?) -> NSView? {
        guard let root else { return nil }
        if root.identifier?.rawValue == id { return root }
        for sub in root.subviews { if let f = view(withIdentifier: id, in: sub) { return f } }
        return nil
    }

    @MainActor
    static func runAppLock(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { pumpEvent(); try? await Task.sleep(nanoseconds: ms * 1_000_000) }
        func text() -> NSString { model.document.textStorage.string as NSString }
        func lineCount() -> Int { model.document.lineIndex.lineCount }
        func mark(_ s: String) { Perf.log("[selftest applock] " + s) }
        let lock = model.appLock
        let fake = FakeAuthenticator()
        lock.authenticator = fake
        guard let tv = model.session.primary?.textView, let win = tv.window else { check(false, "applock: editor window available"); return }
        func overlay() -> NSView? { view(withIdentifier: AppLockController.overlayIdentifier, in: win.contentView) }
        /// 편집기 가운데를 창 좌표로 hitTest — 잠기면 오버레이(호스팅 뷰)가, 아니면 편집기가 맞아야 한다
        func hitAtEditorCenter() -> NSView? {
            let p = tv.convert(NSPoint(x: tv.bounds.midX, y: tv.bounds.midY), to: nil)
            return win.contentView?.superview?.hitTest(p)
        }
        func hitIsEditor() -> Bool {
            guard let v = hitAtEditorCenter() else { return false }
            return v === tv || (tv.enclosingScrollView.map { v.isDescendant(of: $0) } ?? false)
        }
        func keyEvent(_ chars: String, keyCode: UInt16, flags: NSEvent.ModifierFlags = [], type: NSEvent.EventType = .keyDown) -> NSEvent? {
            NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                             windowNumber: win.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode)
        }
        /// 실제 이벤트 경로(NSApp.sendEvent → 로컬 모니터 → 창 → 첫 응답자)로 키 입력
        func sendKey(_ chars: String, keyCode: UInt16, flags: NSEvent.ModifierFlags = []) {
            if let e = keyEvent(chars, keyCode: keyCode, flags: flags) { NSApp.sendEvent(e) }
        }
        /// 모니터의 판정만 직접 확인 (⌘Q 같은 건 실제로 보내면 종료된다)
        func monitorPasses(_ chars: String, keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
            guard let e = keyEvent(chars, keyCode: keyCode, flags: flags) else { return false }
            return lock.handleLockedKeyDown(e) != nil
        }
        /// 메뉴 추적 검사는 알림만 흉내 낸다 — 실제 NSMenu.popUp 은 추적 중 OS 전체 키보드를 가로채므로, 테스트가 멈추면
        /// 사용자가 다른 앱에서도 입력을 못 한다(2026-11-01 실제 발생). ProbeMenu 는 컨트롤러가 cancelTracking 을 불렀는지만 센다
        final class ProbeMenu: NSMenu {
            var cancelled = 0
            override func cancelTrackingWithoutAnimation() { cancelled += 1 }
        }
        func simulateMenuTracking() -> Int {
            let menu = ProbeMenu(title: "applock-test")
            menu.addItem(withTitle: "applock test item", action: nil, keyEquivalent: "")
            NotificationCenter.default.post(name: NSMenu.didBeginTrackingNotification, object: menu)
            return menu.cancelled
        }
        let before = text() as String
        let linesBefore = lineCount()

        // 0. 자동화 실행은 시작 잠금을 하지 않았고, 기본값은 전부 꺼짐/안 함/켜짐
        mark("step 0")
        check(!lock.isLocked, "applock: automation run starts unlocked")
        check(!lock.requireOnLaunch && lock.idleMinutes == 0 && lock.lockOnSleep, "applock: defaults require=off idle=Never lockOnSleep=on")
        check(overlay() == nil, "applock: no overlay marker view while unlocked")
        model.goToEnd(); model.focusEditor(); await wait(300)
        check(win.firstResponder === tv, "applock: editor is first responder before the test")
        // 실제 키 경로 확인: 'x' 입력이 문서에 들어간다
        let lenBefore = text().length
        sendKey("x", keyCode: 7); await wait(200)
        let keyPathWorks = text().length == lenBefore + 1 && text().hasSuffix("x")
        check(keyPathWorks, "applock: sanity — a key event sent through NSApp reaches the editor (+\(text().length - lenBefore) chars)")
        if keyPathWorks { model.send(.perform { tv in tv.insertText("", replacementRange: NSRange(location: (tv.string as NSString).length - 1, length: 1)) }); await wait(150) }
        check(hitIsEditor(), "applock: hitTest at the editor center reaches the editor while unlocked (\(hitAtEditorCenter().map { String(describing: type(of: $0)) } ?? "nil"))")
        check(simulateMenuTracking() == 0, "applock: sanity — menu tracking is left alone while unlocked")

        // 1. 수동 잠금: 상태·오버레이·hitTest·설정 창 닫힘·Quick Append 패널 닫힘·출력 로그
        mark("step 1")
        let settingsWin = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environmentObject(model)))
        settingsWin.styleMask = [.titled, .closable]; settingsWin.isReleasedWhenClosed = false
        settingsWin.setContentSize(NSSize(width: 560, height: 800)); settingsWin.orderFront(nil)
        model.quickAppend.show(); await wait(300)
        check(settingsWin.isVisible && model.quickAppend.isVisible, "applock: settings window and Quick Append panel open before locking")
        model.showGoToLine = true   // 잠글 때 떠 있던 알림은 닫혀야 한다 (시트는 오버레이가 가리지 못한다)
        lock.lock()
        let lockLine = model.output.last?.text ?? ""
        await wait(400)
        check(lock.isLocked, "applock: manual lock → isLocked")
        check(lockLine.contains("HyperEdit locked") || lockLine.contains("HyperEdit 잠김"), "applock: lock is logged · '\(lockLine)'")
        check(overlay() != nil, "applock: overlay marker view '\(AppLockController.overlayIdentifier)' present in the window while locked")
        check(!hitIsEditor(), "applock: hitTest at the editor center no longer reaches the editor (\(hitAtEditorCenter().map { String(describing: type(of: $0)) } ?? "nil"))")
        check(!settingsWin.isVisible, "applock: open settings window is closed by locking")
        check(!model.showGoToLine, "applock: an open Go to Line alert is dismissed by locking")
        check(win.firstResponder !== tv, "applock: editor resigns first responder while locked (dictation/insertText cannot reach the document)")
        check(!model.quickAppend.isVisible, "applock: Quick Append panel is hidden by locking")
        check(win.isVisible, "applock: document window stays open")
        lock.lock()
        check(lock.isLocked, "applock: locking twice is a no-op")

        // 2. 잠긴 동안 입력 차단: 타이핑·Cocoa 편집 바인딩(⌃K)·⌘⌫·⇧⌘K(줄 삭제)·⌘V 는 버려지고, ⌘Q·⌘H·⌘M·⌘W 만 메뉴로 통과한다. 메뉴는 열리자마자 닫힌다
        mark("step 2")
        if keyPathWorks {
            sendKey("x", keyCode: 7); sendKey("\u{0B}", keyCode: 40, flags: [.control]); sendKey("\u{7F}", keyCode: 51, flags: [.command])
            sendKey("\r", keyCode: 36, flags: [.shift]); sendKey("k", keyCode: 40, flags: [.command, .shift]); sendKey("v", keyCode: 9, flags: [.command])
            await wait(300)
            check(text() as String == before && lineCount() == linesBefore, "applock: typing, ⌃K, ⌘⌫, ⇧⌘K and ⌘V are swallowed while locked (len \(text().length) vs \(before.utf16.count), \(lineCount()) lines)")
        }
        check(monitorPasses("q", keyCode: 12, flags: [.command]) && monitorPasses("h", keyCode: 4, flags: [.command]) && monitorPasses("h", keyCode: 4, flags: [.command, .option])
              && monitorPasses("m", keyCode: 46, flags: [.command]) && monitorPasses("w", keyCode: 13, flags: [.command]) && monitorPasses("f", keyCode: 3, flags: [.command, .control]),
              "applock: ⌘Q ⌘H ⌥⌘H ⌘M ⌘W ⌃⌘F pass the locked key monitor")
        check(monitorPasses("ㅂ", keyCode: 12, flags: [.command]), "applock: ⌘Q passes under a non-Latin input source (matched by key code)")
        check(!monitorPasses(",", keyCode: 43, flags: [.command]) && !monitorPasses("v", keyCode: 9, flags: [.command]) && !monitorPasses("q", keyCode: 12, flags: [.command, .shift])
              && !monitorPasses("a", keyCode: 0, flags: []) && !monitorPasses("s", keyCode: 1, flags: [.command]),
              "applock: ⌘, ⌘V ⇧⌘Q ⌘S and plain typing are swallowed by the locked key monitor")
        check(!monitorPasses("z", keyCode: 13, flags: [.command]) && !monitorPasses(",", keyCode: 13, flags: [.command]) && !monitorPasses(",", keyCode: 46, flags: [.command]),
              "applock: AZERTY ⌘Z and Dvorak/AZERTY ⌘, are swallowed — characters decide, key codes only for non-Latin input")
        let cancelledBefore = lock.cancelledMenuCount
        let lockedCancels = simulateMenuTracking()
        check(lockedCancels == 1 && lock.cancelledMenuCount == cancelledBefore + 1, "applock: a menu that begins tracking while locked is cancelled at once (cancelled \(lockedCancels), controller count +\(lock.cancelledMenuCount - cancelledBefore))")

        // 3. Quick Append 는 패널 대신 잠금 해제 프롬프트: 취소하면 잠긴 채 패널도 없고, 성공하면 해제되고 패널이 열린다
        mark("step 3")
        fake.result = .cancelled
        let calls0 = fake.calls
        model.quickAppend.show(); await wait(300)
        check(fake.calls == calls0 + 1 && lock.isLocked && !model.quickAppend.isVisible, "applock: Quick Append while locked prompts (calls \(fake.calls - calls0)), cancel keeps it locked and hidden")
        check(fake.lastReason.isEmpty == false, "applock: authentication reason passed to the authenticator · '\(fake.lastReason)'")

        // 4. 가짜 인증기: 실패 → 잠긴 채 메시지, 취소 → 잠긴 채, 성공 → 해제·오버레이 제거·포커스 편집기
        mark("step 4")
        fake.result = .failed("nope")
        await lock.requestUnlock(); await wait(200)
        check(lock.isLocked && lock.message == "nope" && overlay() != nil, "applock: failed authentication keeps the lock and shows the message '\(lock.message ?? "nil")'")
        fake.result = .failed("")
        await lock.requestUnlock(); await wait(100)
        check(lock.isLocked && (lock.message ?? "").isEmpty == false && lock.message != "nope", "applock: empty failure detail falls back to the generic message '\(lock.message ?? "nil")'")
        fake.result = .cancelled
        await lock.requestUnlock(); await wait(100)
        check(lock.isLocked && lock.message != nil, "applock: cancel keeps the lock (message from the earlier failure stays until unlock)")
        fake.result = .success
        await lock.requestUnlock()
        let unlockLine = model.output.last?.text ?? ""
        await wait(400)
        check(!lock.isLocked && lock.message == nil, "applock: successful authentication unlocks and clears the message")
        check(unlockLine.contains("HyperEdit unlocked") || unlockLine.contains("잠금 해제됨"), "applock: unlock is logged · '\(unlockLine)'")
        check(overlay() == nil, "applock: overlay marker view removed after unlock")
        check(hitIsEditor(), "applock: hitTest reaches the editor again after unlock")
        check(win.firstResponder === tv, "applock: editor regains focus after unlock")
        if keyPathWorks {
            sendKey("y", keyCode: 16); await wait(200)
            check(text().hasSuffix("y"), "applock: typing works again after unlock")
            model.send(.perform { tv in tv.insertText("", replacementRange: NSRange(location: (tv.string as NSString).length - 1, length: 1)) }); await wait(150)
        }
        check(text() as String == before, "applock: document text unchanged by the lock/unlock round trip")
        check(simulateMenuTracking() == 0, "applock: menu tracking is left alone again after unlock")

        // 5. Return 키 → 잠금 해제 요청 (실제 키 경로) · 해제 성공 뒤 Quick Append 는 그대로 열린다
        mark("step 5")
        lock.lock(); await wait(200)
        fake.result = .success
        let callsRet = fake.calls
        sendKey("\r", keyCode: 36); await wait(400)
        check(fake.calls == callsRet + 1 && !lock.isLocked, "applock: Return while locked requests unlock (calls +\(fake.calls - callsRet)) → unlocked")
        lock.lock(); await wait(200)
        model.quickAppend.show(); await wait(400)
        check(!lock.isLocked && model.quickAppend.isVisible, "applock: Quick Append after successful unlock opens the panel")
        model.quickAppend.hide(); await wait(150)

        // 6. 유휴 타이머: 1초 주입 → 잠김. 입력(flagsChanged)이 있으면 타이머가 뒤로 밀린다
        mark("step 6")
        lock.idleIntervalOverride = 1.0
        await wait(600)
        check(!lock.isLocked, "applock: idle timer (1 s) has not fired after 0.6 s")
        await wait(900)
        check(lock.isLocked, "applock: idle timer locks after 1 s without input")
        fake.result = .success
        await lock.requestUnlock(); await wait(200)
        check(!lock.isLocked, "applock: unlocked again (idle timer re-armed)")
        await wait(600)
        if let e = keyEvent("", keyCode: 56, flags: [.shift], type: .flagsChanged) { NSApp.sendEvent(e) }
        await wait(100)
        await wait(600)
        check(!lock.isLocked, "applock: input at 0.6 s pushes the idle lock back (still unlocked at 1.3 s)")
        await wait(1100)
        check(lock.isLocked, "applock: idle lock fires 1 s after the last input")
        await lock.requestUnlock(); await wait(200)
        lock.idleIntervalOverride = nil
        check(!lock.isLocked, "applock: idle override cleared, unlocked")
        await wait(1200)
        check(!lock.isLocked, "applock: no idle lock once the interval is Never")

        // 7. 잠자기·화면 잠금 연동: Require 와 Lock-on-sleep 이 모두 켜져 있을 때만
        mark("step 7")
        lock.systemEvent(.sleep)
        check(!lock.isLocked, "applock: sleep does not lock while Require… is off")
        lock.requireOnLaunch = true
        check(lock.requireOnLaunch && lock.settingsWarning == nil, "applock: Require… turns on when authentication is available")
        lock.lockOnSleep = false
        lock.systemEvent(.screenLock)
        check(!lock.isLocked, "applock: screen lock does not lock while Lock-on-sleep is off")
        lock.lockOnSleep = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.willSleepNotification, object: NSWorkspace.shared)
        await wait(300)
        check(lock.isLocked, "applock: NSWorkspace.willSleepNotification locks (Require… + Lock-on-sleep on)")
        await lock.requestUnlock(); await wait(200)
        lock.systemEvent(.screenLock); await wait(100)
        check(lock.isLocked, "applock: screen-lock event locks")
        await lock.requestUnlock(); await wait(200)
        // 인증 수단이 없는 Mac 에서는 켜지지 않는다 (켜 두면 다음 실행에서 풀 수 없다)
        lock.requireOnLaunch = false
        fake.isAvailable = false
        lock.requireOnLaunch = true
        check(!lock.requireOnLaunch && lock.settingsWarning != nil && AppDefaults.store.bool(forKey: "applock.requireOnLaunch") == false,
              "applock: Require… refuses to turn on without Touch ID / password · '\(lock.settingsWarning ?? "")'")
        fake.isAvailable = true
        lock.requireOnLaunch = true
        check(lock.requireOnLaunch && lock.settingsWarning == nil, "applock: warning clears once authentication is available again")
        lock.requireOnLaunch = false
        // 인증 수단이 사라진 뒤의 해제 요청은 가리지 않고 푼다 (unavailable → unlock + 출력 패널 경고)
        lock.lock(); await wait(100)
        fake.result = .unavailable("no passcode")
        await lock.requestUnlock()
        let warnLines = model.output.suffix(2)
        await wait(200)
        check(!lock.isLocked && warnLines.contains { $0.isError && $0.text.contains("no passcode") }, "applock: unavailable authentication unlocks with a logged warning · '\(warnLines.first?.text ?? "")'")
        fake.result = .success

        // 8. 설정 저장/복원: applock.* 키 → 새 컨트롤러가 같은 값을 읽는다. 끝에 기본값으로 되돌린다
        mark("step 8")
        lock.requireOnLaunch = true; lock.idleMinutes = 15; lock.lockOnSleep = false
        let d = AppDefaults.store
        check(d.bool(forKey: "applock.requireOnLaunch") && d.integer(forKey: "applock.idleMinutes") == 15 && d.object(forKey: "applock.lockOnSleep") as? Bool == false,
              "applock: settings stored under applock.* (\(d.bool(forKey: "applock.requireOnLaunch")), \(d.integer(forKey: "applock.idleMinutes")), \(String(describing: d.object(forKey: "applock.lockOnSleep"))))")
        let second = AppLockController(model: model, authenticator: fake)
        check(second.requireOnLaunch && second.idleMinutes == 15 && !second.lockOnSleep && !second.isLocked,
              "applock: a fresh controller restores the stored settings and (automation run) starts unlocked")
        second.shutdown()
        d.set(7, forKey: "applock.idleMinutes")
        let third = AppLockController(model: model, authenticator: fake)
        check(third.idleMinutes == 0, "applock: an idle value outside the choices falls back to Never")
        third.shutdown()
        lock.requireOnLaunch = false; lock.idleMinutes = 0; lock.lockOnSleep = true
        check(!d.bool(forKey: "applock.requireOnLaunch") && d.integer(forKey: "applock.idleMinutes") == 0 && d.bool(forKey: "applock.lockOnSleep"), "applock: settings restored to defaults")
        check(Set(AppLockController.idleChoices) == [0, 1, 5, 15, 30], "applock: idle choices Never/1/5/15/30")

        // 9. 타이핑 지연: 유휴 모니터가 설치된 상태(5분)로 실제 키 이벤트 40타 (모니터 + 창 + 편집기 경로). 빠르게 보낸 키 이벤트는 일부가 입력 컨텍스트에서
        //    합쳐지거나 버려질 수 있으므로 들어간 글자 수만큼만 되돌린다
        mark("step 9")
        lock.idleMinutes = 5
        model.goToEnd(); model.focusEditor(); await wait(200)
        let t1 = CFAbsoluteTimeGetCurrent()
        let n = 40
        for _ in 0..<n {
            if keyPathWorks { sendKey("a", keyCode: 0) } else { model.send(.perform { tv in tv.insertText("a", replacementRange: tv.selectedRange()) }) }
            await wait(1)
        }
        let typingMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000 / Double(n) - 1
        await wait(200)
        model.send(.perform { tv in tv.unmarkText() })
        let landed = text().length - before.utf16.count
        log(String(format: "perf typing with app lock idle monitor %.2f ms/keystroke (incl. run loop, %@, %d of %d landed)", typingMs, keyPathWorks ? "real key events" : "programmatic", landed, n))
        check(typingMs < 16, "applock: typing latency with the idle monitor under one frame (16 ms)")
        check(landed > 0 && landed <= n, "applock: keystrokes landed through the monitor (\(landed) of \(n))")
        if landed > 0 {
            model.send(.perform { tv in
                let ns = tv.string as NSString
                tv.insertText("", replacementRange: NSRange(location: ns.length - landed, length: landed))
            }); await wait(200)
        }
        lock.idleMinutes = 0
        check(text() as String == before && !lock.isLocked, "applock: document restored and unlocked at the end")
    }
}
