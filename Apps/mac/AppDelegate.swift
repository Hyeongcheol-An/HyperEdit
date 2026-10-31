import AppKit
import ScreenCaptureKit
import HyperCore

/// 개발·CI 보조: `--snapshot <png경로>` 로 실행하면 2.5초 뒤 첫 창을 화면 캡처(ScreenCaptureKit)해 PNG 로 저장한다.
/// TextKit 2 본문은 GPU 서피스로 그려져 cacheDisplay 로는 잡히지 않으므로 실제 화면을 캡처한다(화면 녹화 권한 필요, 없으면 .txt 에 오류).
/// `--quit` 가 함께 있으면 저장 후 종료.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        Bench.launchMilestone("didFinishLaunching")   // perf bench (계측이 꺼져 있으면 비용 0)
        if Perf.enabled { PerfProbe.log = { Perf.log($0) } }
        Perf.startWatchdog()
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
        // 스냅샷 실행은 폭을 주지 않으면 1280 으로 고정한다 (AppKit 의 창 프레임 자동 저장이 이전 실행 크기를 되살리므로).
        // 개발용: `--snapshot-activate` 는 캡처 전에 앱을 앞으로 가져와 창이 활성(색 신호등) 상태로 찍히게 한다 (README 용; 다른 앱의 포커스를 잠시 뺏는다)
        if args.contains("--snapshot-activate") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.activate(ignoringOtherApps: true) }
        }
        let requested = LaunchOptions.value("--window-width").flatMap(Double.init) ?? (args.contains("--snapshot") ? 1280 : nil)
        if let width = requested {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard let win = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }) else { return }
                var f = win.frame; f.size.width = max(900, CGFloat(width)); win.setFrame(f, display: true)
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
        guard let doc = AppModel.current?.document else { return .terminateNow }
        if doc.saveSynchronously() || !doc.isDirty { return .terminateNow }
        let copy = doc.writeEmergencyCopy()
        AppModel.current?.log(copy.map { String(localized: "Save failed on quit — emergency copy written to \($0.path)") }
                              ?? String(localized: "Save failed on quit — no emergency copy could be written"), isError: true)
        // 자동화 실행(셀프테스트·벤치·스크린샷)은 묻지 않고 종료한다
        if SelfTest.enabled || Bench.enabled || LaunchOptions.has("--snapshot") { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(localized: "The document could not be saved")
        alert.informativeText = copy.map { String(localized: "An emergency copy of the unsaved text was written to \($0.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")). Quit anyway, or cancel to keep editing?") }
            ?? String(localized: "No emergency copy could be written. Quit anyway, or cancel to keep editing?")
        alert.addButton(withTitle: String(localized: "Quit Anyway"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}
