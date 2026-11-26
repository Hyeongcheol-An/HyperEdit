import AppKit
import ScreenCaptureKit
import HyperCore

/// 개발·CI 보조: `--snapshot <png경로>` 로 실행하면 2.5초 뒤 첫 창을 화면 캡처(ScreenCaptureKit)해 PNG 로 저장한다.
/// TextKit 2 본문은 GPU 서피스로 그려져 cacheDisplay 로는 잡히지 않으므로 실제 화면을 캡처한다(화면 녹화 권한 필요, 없으면 .txt 에 오류).
/// `--quit` 가 함께 있으면 저장 후 종료.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 언어 변경 뒤 '지금 재실행': 종료 직전에 이 프로세스가 끝나기를 기다렸다가 같은 번들을 여는 셸을 띄운다 (AppLanguage.relaunch)
    nonisolated(unsafe) static var relaunchOnQuit = false

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.current?.secrets.flushPendingClipboardClear()   // secrets: 예약된 소거는 프로세스와 함께 사라진다 → 지금 비운다
        guard Self.relaunchOnQuit else { return }
        Self.relaunchOnQuit = false
        let pid = ProcessInfo.processInfo.processIdentifier
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // 종료 전에 열면 두 인스턴스가 겹치고 LaunchServices 가 기존 인스턴스를 앞으로 가져올 수 있다 → 프로세스가 사라진 뒤 `open -n`
        task.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; exec /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
        do { try task.run() } catch { NSLog("relaunch failed: \(error)") }
    }

    /// 셀프테스트를 뒤에서 돌리는가. 터미널·IDE 가 앞에 있을 때 앱을 띄우면 macOS 가 새 앱을 활성화한다 — 검사가 도는 몇 분 동안 창이 앞에 나오고
    /// 사용자가 다른 앱에 치던 키 입력을 받는다 (2026-11-24 실측: 10번 중 9번이 활성 상태로 돌았다). `--selftest-foreground` 를 주면 예전처럼 앞에서 돈다
    static var selfTestStaysInBackground: Bool { (SelfTest.enabled || SelfTest.openEnabled) && !LaunchOptions.has("--selftest-foreground") }

    /// 벤치(`--bench`)와 실행 시간 계측(`--bench-launch-log`·`--quit-after-launch` — scripts/bench.sh 가 여섯 번 띄운다)도 같은 방식으로 뒤에서 돈다:
    /// 사용자가 Mac 을 쓰는 동안에도 성능을 잴 수 있게. `--bench-foreground` 를 주면 예전처럼 앞에서 돈다.
    /// 벤치는 키 창·첫 응답자·이벤트에 기대지 않는다(모델과 텍스트 뷰를 직접 부른다). 다만 창이 완전히 가려지면 그리기가 빠지므로 어떻게 돌았는지를
    /// 결과에 적는다(Bench.RunMode) — 뒤에서 잰 수치는 뒤에서 잰 수치끼리만 견준다
    static var benchStaysInBackground: Bool {
        (Bench.enabled || LaunchOptions.has("--quit-after-launch") || LaunchOptions.value("--bench-launch-log") != nil) && !LaunchOptions.has("--bench-foreground")
    }

    /// 앞으로 나오지 않는 자동화 실행: 스크립트가 모는 실행 전부 (AutomationRun.isScripted — 셀프테스트·벤치·실사용 하네스·스크린샷). 앞에서 돌라고 한 것만
    /// 예외다: `--selftest-foreground` · `--bench-foreground` · `--snapshot-activate`
    static var automationStaysInBackground: Bool {
        AutomationRun.isScripted && !LaunchOptions.has("--selftest-foreground") && !LaunchOptions.has("--bench-foreground") && !LaunchOptions.has("--snapshot-activate")
    }

    /// 이 실행이 활성화되어 물러난 횟수. 물러난 뒤에는 활성이었는지 알 수 없으므로 세어 두고 하네스·셀프테스트의 로그에 적는다
    nonisolated(unsafe) private(set) static var stepBacks = 0

    func applicationDidBecomeActive(_ notification: Notification) {
        if Self.stepBackIfAutomated() { Self.stepBacks += 1 }
    }

    /// 뒤에서 도는 자동화 실행이 활성화됐다 → 바로 물러나고 창을 맨 뒤로. 시작할 때만의 일이 아니다: 도는 중에도 Launch Services 가 같은 번들 ID 의
    /// 이 인스턴스를 앞으로 가져올 수 있다 (Finder 에서 연 파일이 이리 올 때, 스크립트가 몇 분 뒤 두 번째 실행을 띄울 때). 반환: 물러나는 실행인가
    @MainActor @discardableResult
    static func stepBackIfAutomated() -> Bool {
        guard automationStaysInBackground else { return false }
        NSApp.deactivate()
        for w in NSApp.windows where w.isVisible { w.orderBack(nil) }
        return true
    }

    /// 뒤에서 도는 자동화 실행(셀프테스트·벤치·하네스)이 App Nap 에 걸리지 않게 실행 내내 잡아 두는 활동 토큰. 비활성 + 가려진 창이면 2~3분 뒤 타이머가 늦게 깨고 CPU 우선순위가
    /// 깎여, 시간을 재는 검사(매크로 100회·타이핑 지연·유휴 잠금)가 몇 배 느리게 재진다 (2026-11-24 실측: 막지 않은 실행에서 8건 실패)
    private var backgroundActivity: NSObjectProtocol?

    /// Finder 의 "다음으로 열기"·Dock 아이콘에 끌어다 놓기·`open -a HyperEdit <파일>` 로 넘어온 파일 → 탭으로 연다 (ExternalOpen.swift).
    /// 앱이 꺼져 있다가 뜨는 경우에는 `applicationDidFinishLaunching` 보다 먼저, 창이 생기기 전에 불린다 (모델은 그보다 먼저 만들어져 있다)
    func application(_ application: NSApplication, open urls: [URL]) { ExternalOpen.receive(urls) }

    /// 명령줄의 맨 인자(`HyperEdit <파일>`): AppKit 은 이것을 위의 URL 경로가 아니라 이 옛 경로로, 인자마다 한 번씩 넘긴다 (실측 macOS 27).
    /// AppKit 의 판정은 이 앱의 옵션과 어긋나므로(옵션의 값이 섞여 오고, 파일이 빠진다) 맨 인자는 실행 인자에서 직접 가려 연다 — 여기서는 어긋난 것만
    /// 적는다 (`ExternalOpen.receive(commandLine:)`)
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        ExternalOpen.receive(commandLine: filenames)
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if Self.automationStaysInBackground {
            backgroundActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "background automated run")
        }
        Bench.launchMilestone("didFinishLaunching")   // perf bench (계측이 꺼져 있으면 비용 0)
        if Perf.enabled { PerfProbe.log = { Perf.log($0) } }
        Perf.startWatchdog()
        // 파일 탭: ⌃Tab = 직전에 보던 탭(최근 활성 순서, UltraEdit Ctrl+F6 "Last file"), ⌃⇧Tab = 이전 탭(순서). ⌘⇧] / ⌘⇧[ 는 메뉴 단축키
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 48, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isSuperset(of: [.control]),
                  !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.option),
                  let model = AppModel.current, model.tabKeysApply, model.tabs.count > 1 else { return event }
            // 편집기 창이 앞에 있고 옮겨 갈 탭이 있을 때만 가로챈다 — 설정 창·Quick Append 패널·저장/내보내기 패널·매크로 재생 중에는 뒤의 문서를 바꾸지 않고,
            // 탭이 하나뿐이면 ⌃Tab 의 원래 뜻(다음 키 뷰)을 삼키지 않는다
            if event.modifierFlags.contains(.shift) { model.previousTab() } else { model.activateLastActiveTab() }
            return nil
        }
        // 같은 앱의 다른 인스턴스가 떠 있는 상태에서 LaunchServices 가 새 인스턴스를 띄우면 SwiftUI 가 기본 창을 만들지 않는 경우가 있다.
        // 잠시 뒤에도 창이 없으면 '다시 열기(rapp)' 애플 이벤트를 자신에게 보내 WindowGroup 창을 열게 한다.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard NSApp.windows.isEmpty else { return }
            let target = NSAppleEventDescriptor(processIdentifier: ProcessInfo.processInfo.processIdentifier)
            let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEReopenApplication),
                                               targetDescriptor: target, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            do { try event.sendEvent(options: [.noReply], timeout: 1) } catch { NSLog("reopen event failed: \(error)") }
            if args.contains("--debug-startup") { FileHandle.standardError.write("[startup] no window after launch → sent reopen event\n".data(using: .utf8)!) }
        }
        if args.contains("--debug-startup") {
            func dump(_ tag: String) {
                let ws = NSApp.windows.map { "\(type(of: $0)) visible=\($0.isVisible) frame=\($0.frame) title='\($0.title)'" }
                let line = "[startup \(tag)] active=\(NSApp.isActive) policy=\(NSApp.activationPolicy().rawValue) windows=\(NSApp.windows.count) \(ws)\n"
                FileHandle.standardError.write(line.data(using: .utf8)!)
                if let i = args.firstIndex(of: "--debug-startup-log"), i + 1 < args.count, let h = FileHandle(forWritingAtPath: args[i + 1]) ?? { FileManager.default.createFile(atPath: args[i + 1], contents: nil); return FileHandle(forWritingAtPath: args[i + 1]) }() {
                    h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
                }
            }
            dump("didFinishLaunching")
            for i in 1...4 { DispatchQueue.main.asyncAfter(deadline: .now() + Double(i)) { dump("+\(i)s") } }
        }
        // 개발용: `--window-width <pt>` 로 첫 창 폭을 바꿔 좁은 창(리본 접힘) 상태를 스크린샷한다.
        // 스냅샷 실행은 폭을 주지 않으면 1280 으로 고정한다 (자동화 실행은 저장된 창 프레임을 읽지 않아 기본 크기로 뜨지만, 그 기본이 바뀌어도 그림이 같게).
        // 개발용: `--snapshot-activate` 는 캡처 전에 앱을 앞으로 가져와 창이 활성(색 신호등) 상태로 찍히게 한다 (README 용; 다른 앱의 포커스를 잠시 뺏는다)
        if args.contains("--snapshot-activate") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.activate(ignoringOtherApps: true) }
        }
        // 개발용: `--window-height <pt>` 는 첫 창 높이도 고정한다 (왼쪽 위 모서리는 그대로). 창의 기본 높이는 화면의 쓸 수 있는 높이를 따르므로, 실사용 하네스의
        // 결과가 모니터·Dock 배치에 따라 달라지지 않게 한다 (scripts/realuse.sh)
        let requested = LaunchOptions.value("--window-width").flatMap(Double.init) ?? (args.contains("--snapshot") ? 1280 : nil)
        let requestedHeight = LaunchOptions.value("--window-height").flatMap(Double.init)
        if requested != nil || requestedHeight != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard let win = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { return }
                var f = win.frame
                if let width = requested { f.size.width = max(900, CGFloat(width)) }
                if let height = requestedHeight { let top = f.maxY; f.size.height = max(480, CGFloat(height)); f.origin.y = top - f.size.height }
                win.setFrame(f, display: true)
            }
        }
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let path = args[i + 1]
        let quit = args.contains("--quit")
        var delay = 2.5
        if let d = args.firstIndex(of: "--snapshot-delay"), d + 1 < args.count, let v = Double(args[d + 1]) { delay = v }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in
                await Self.captureFirstWindow(to: path)
                // quick append: `--snapshot-panel <png>` 는 떠 있는 Quick Append 창(`--quick-append` 로 열림)을 따로 찍는다
                if let p = LaunchOptions.value("--snapshot-panel") {
                    if let panel = NSApp.windows.first(where: { $0 is QuickAppendPanel && $0.isVisible }) { await Self.capture(window: panel, to: p) }
                    else { try? "snapshot: no panel".write(toFile: p + ".txt", atomically: true, encoding: .utf8) }
                }
                // l10n: `--snapshot-settings <png>` 는 `--show-settings` 로 연 설정 창(문서 창이 아닌 두 번째 일반 창)을 따로 찍는다
                if let p = LaunchOptions.value("--snapshot-settings") {
                    let main = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) })
                    if let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && !($0 is QuickAppendPanel) && $0 !== main }) { await Self.capture(window: w, to: p) }
                    else {
                        let ws = NSApp.windows.map { "\(type(of: $0)) visible=\($0.isVisible) title='\($0.title)' frame=\($0.frame)" }.joined(separator: "\n")
                        try? "snapshot: no settings window\n\(ws)".write(toFile: p + ".txt", atomically: true, encoding: .utf8)
                    }
                }
                // 시트(스니펫 선택창 ⇧⌘I 등)는 별도 창이라 첫 창 캡처에 들어가지 않는다 — `--snapshot-sheet <png>` 로 첫 창에 붙은 시트를 따로 찍는다
                if let p = LaunchOptions.value("--snapshot-sheet") {
                    // ScreenCaptureKit 은 시트 창을 고르면 부모 창까지 합성한 그림을 시트 크기에 맞춰 돌려준다 → 부모 창 크기로 받아야 읽을 수 있다
                    if let main = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }), let sheet = main.attachedSheet {
                        await Self.capture(window: sheet, to: p, size: main.frame.size)
                    } else { try? "snapshot: no sheet".write(toFile: p + ".txt", atomically: true, encoding: .utf8) }
                }
                if quit { NSApp.terminate(nil) }
            }
        }
    }

    @MainActor
    static func captureFirstWindow(to path: String) async {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }) else {
            try? "snapshot: no window".write(toFile: path + ".txt", atomically: true, encoding: .utf8); return
        }
        await capture(window: window, to: path)
    }

    @MainActor
    static func capture(window: NSWindow, to path: String, size: CGSize? = nil) async {
        let wid = CGWindowID(window.windowNumber)
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let w = content.windows.first(where: { $0.windowID == wid }) else {
                try? "snapshot: window not shareable".write(toFile: path + ".txt", atomically: true, encoding: .utf8); return
            }
            let filter = SCContentFilter(desktopIndependentWindow: w)
            let cfg = SCStreamConfiguration()
            let scale = window.backingScaleFactor
            let size = size ?? w.frame.size
            cfg.width = Int(size.width * scale); cfg.height = Int(size.height * scale); cfg.showsCursor = false
            let img = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            try? "snapshot: ok \(cfg.width)x\(cfg.height)".write(toFile: path + ".txt", atomically: true, encoding: .utf8)
        } catch {
            try? "snapshot error: \(error)".write(toFile: path + ".txt", atomically: true, encoding: .utf8)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// ⌘Q·창 닫기: 2초 자동 저장을 기다리지 못한 편집을 동기로 저장하고 종료 (비동기 저장 Task 는 종료 전에 실행될 기회가 없다).
    /// 저장이 실패해 편집이 남아 있으면(쓰기 불가 폴더, 빈 내용 저장 차단 등) 메모리 내용을 스냅샷 폴더에 비상 사본으로 남기고 종료할지 묻는다 —
    /// Quick Append 는 패널이 바로 닫히고 앱이 비활성이라 상태바의 저장 오류를 볼 기회가 없기 때문이다.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let doc = AppModel.current?.document else { return .terminateNow }   // 탭이 여럿이어도 살아 있는 문서는 하나 (다른 탭은 전환할 때 저장됐다)
        if doc.saveSynchronously() || !doc.isDirty { return .terminateNow }
        let copy = doc.writeEmergencyCopy()
        AppModel.current?.log(copy.map { String(localized: "Save failed on quit — emergency copy written to \($0.path)") }
                              ?? String(localized: "Save failed on quit — no emergency copy could be written"), isError: true)
        // 스크립트가 모는 실행(셀프테스트·벤치·하네스·스크린샷)은 묻지 않고 종료한다 — 대답할 사람이 없다
        if AutomationRun.isScripted { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "The document could not be saved")
        alert.informativeText = copy.map { String(localized: "An emergency copy of the unsaved text was written to \($0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")). Quit anyway, or cancel to keep editing?") }
            ?? String(localized: "No emergency copy could be written. Quit anyway, or cancel to keep editing?")
        alert.addButton(withTitle: String(localized: "Quit Anyway"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        if alert.runModal() == .alertFirstButtonReturn { return .terminateNow }
        Self.relaunchOnQuit = false   // 취소했으면 예약된 재실행도 취소 (다음 ⌘Q 가 재실행이 되지 않게)
        return .terminateCancel
    }
}
