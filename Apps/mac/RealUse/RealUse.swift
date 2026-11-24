import SwiftUI
import AppKit
import HyperCore

/// 실사용 시뮬레이션 하네스 (개발용): `--realuse [--realuse-only <a,b>] [--realuse-out <dir>] [--quit]`
/// 반드시 `--ephemeral --file <임시 파일>` 과 함께 띄운다 (scripts/realuse.sh 가 그렇게 한다).
///
/// 셀프테스트는 모델·텍스트 뷰 API 를 직접 부른다. 이 하네스는 사용자가 하는 그대로 — 키 이벤트(keyDown → 키 바인딩), 입력기 경로
/// (insertText / setMarkedText), 스크롤 휠 이벤트(픽셀 단위·줄 단위·트랙패드 제스처와 관성 단계), 마우스 클릭·드래그 — 를 실제 창에 보내고,
/// 걸음마다 불변식(선택 범위·뷰포트·캐럿 가시성·레이아웃 조각의 틈과 겹침·거터 줄 번호 정렬·그려진 잉크·메인 스레드 정지)을 검사하며
/// 화면을 PNG 로 남긴다. 앱을 활성화하지 않으므로 사용자가 쓰고 있는 다른 앱의 포커스를 뺏지 않는다.
///
/// 시나리오는 영역별 파일(RealUse+Scroll.swift 등)의 `static let <area>Scenarios` 에 더한다. 결과는 `<out>/report.md`·`report.json`·`log.txt`·PNG.
enum RealUse {
    static var enabled: Bool { CommandLine.arguments.contains("--realuse") }
    static var outDir: URL { URL(fileURLWithPath: LaunchOptions.value("--realuse-out") ?? (NSTemporaryDirectory() + "hyperedit-realuse"), isDirectory: true) }
    static func wants(_ name: String) -> Bool {
        guard let only = LaunchOptions.value("--realuse-only") else { return true }
        return only.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.contains(name)
    }

    struct Scenario {
        let name: String
        let run: @MainActor (RealUseContext) async -> Void
    }

    struct Issue: Codable {
        let scenario: String
        let step: String
        let kind: String        // gap · overlap · coverage · caret-hidden · scroll-delta · viewport-jump · text · gutter · blank · stall · selection · other
        let detail: String
        let snapshot: String?
    }

    /// 모든 시나리오 (영역 파일들이 채운다)
    @MainActor static var scenarios: [Scenario] {
        coreScenarios + scrollScenarios + typingScenarios + mouseScenarios + tabsScenarios + findScenarios + layoutScenarios + fileViewScenarios
    }

    @MainActor
    static func run(model: AppModel) async {
        // 앱을 활성화하지 않고 창을 맨 뒤에 두므로 2~3분쯤 지나면 App Nap 이 걸려 타이머가 늦게 깨고 CPU 우선순위가 깎인다 — 그 뒤로는 같은 동작이 3~5배
        // 느리게 재지고 가만히 기다리는 걸음에서도 '정지'가 기록된다(시나리오 순서를 바꾸면 느려지는 시나리오도 바뀐다). 실행 내내 막아 둔다
        let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical], reason: "real-use harness")
        defer { ProcessInfo.processInfo.endActivity(activity) }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        let out = outDir
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        guard let ctx = RealUseContext(model: model, out: out) else {
            try? "realuse: no editor window".write(to: out.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
            if CommandLine.arguments.contains("--quit") { NSApp.terminate(nil) }
            return
        }
        // 사용자가 쓰고 있는 앱의 포커스를 뺏지 않는다: 활성화됐으면 물러나고 창은 맨 뒤로
        if NSApp.isActive { NSApp.deactivate() }
        ctx.window.orderBack(nil)
        ctx.log("launch: app active=\(NSApp.isActive) window key=\(ctx.window.isKeyWindow) visible=\(ctx.window.isVisible) occluded=\(!ctx.window.occlusionState.contains(.visible)) frame=\(ctx.window.frame)")
        GutterView.captureRows = true
        ctx.startStallMonitor()
        await ctx.calibrate()
        let start = model.document.url
        for s in scenarios where wants(s.name) {
            ctx.begin(scenario: s.name)
            await s.run(ctx)
            ctx.end()
            // 시나리오가 연 임시 문서 탭을 닫고 시작 문서로 — 다음 시나리오가 깨끗한 상태에서 시작한다
            if model.tabs.contains(start) { model.activateTab(start) }
            model.closeTabs(in: ctx.dir)
            if model.session.splitMode != .none { model.session.splitMode = .none }
            await ctx.settle(300)
        }
        ctx.stopStallMonitor()
        ctx.writeReport()
        try? FileManager.default.removeItem(at: ctx.dir)
        if CommandLine.arguments.contains("--quit") { try? await Task.sleep(nanoseconds: 200_000_000); NSApp.terminate(nil) }
    }
}

/// 시나리오가 쓰는 운전대: 이벤트 합성 + 불변식 검사 + 기록
@MainActor
final class RealUseContext {
    let model: AppModel
    let out: URL
    /// 임시 말뭉치 폴더 (시나리오가 여는 파일은 전부 여기 — 사용자 문서는 건드리지 않는다)
    let dir: URL
    private(set) var scenario = ""
    private(set) var step = ""
    private(set) var issues: [RealUse.Issue] = []
    private var lines: [String] = []
    private var snapCount = 0
    private var stepsRun = 0
    private var checksRun = 0
    /// 키 이벤트가 keyDown 경로로 처리되는가 (앱이 활성 상태가 아니라 입력 컨텍스트가 무시하면 명령 선택자로 대신 보낸다)
    private(set) var keyEventsWork = true
    /// 스크롤 이벤트를 창의 sendEvent 로 보낼 수 있는가 (아니면 스크롤 뷰에 직접)
    private(set) var scrollViaWindow = true

    init?(model: AppModel, out: URL) {
        self.model = model
        self.out = out
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("hyperedit-realuse-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard model.session.primary?.textView?.window != nil else { return nil }
    }

    // MARK: 편집기 접근 (분할·탭 전환으로 바뀔 수 있어 매번 다시 얻는다)

    var coord: EditorView.Coordinator { model.session.active ?? model.session.primary! }
    var tv: HyperTextView { coord.textView! }
    var scroll: NSScrollView { coord.scrollView! }
    var gutter: GutterView? { coord.gutter }
    var window: NSWindow { tv.window! }
    var doc: MemoDocument { model.document }
    var length: Int { tv.textStorage?.length ?? 0 }
    var text: NSString { tv.textStorage?.mutableString ?? "" }
    var visible: NSRect { tv.visibleRect }
    var lineHeight: CGFloat { tv.caretRect(at: min(length, tv.selectedRange().location))?.height ?? 18 }
    var caret: Int { tv.selectedRange().location }

    // MARK: 기록

    func begin(scenario name: String) { scenario = name; step = ""; log("=== scenario \(name)") }
    func end() { log("=== end \(scenario)") }

    func log(_ s: String) {
        lines.append(s)
        FileHandle.standardError.write(("[realuse] " + s + "\n").data(using: .utf8)!)
    }

    /// 걸음 이름을 정한다 (이후의 문제·정지 기록에 붙는다)
    func at(_ name: String) { step = name; stepsRun += 1 }

    func issue(_ kind: String, _ detail: String, snap: Bool = true) {
        let file = snap ? self.snap("issue-\(issues.count + 1)-\(kind)") : nil
        issues.append(RealUse.Issue(scenario: scenario, step: step, kind: kind, detail: detail, snapshot: file))
        log("ISSUE [\(kind)] \(scenario) › \(step): \(detail)")
    }

    func note(_ s: String) { log("  \(scenario) › \(step): \(s)") }

    /// 창 내용을 PNG 로 (가려져 있어도 그린다). 반환: 파일 이름
    @discardableResult
    func snap(_ name: String) -> String? {
        guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        snapCount += 1
        let file = String(format: "%03d-%@-%@.png", snapCount, scenario, name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: " ", with: "_"))
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        try? data.write(to: out.appendingPathComponent(file))
        return file
    }

    func writeReport() {
        var md = "# HyperEdit real-use report\n\n"
        md += "Scenarios run: \(Set(lines.filter { $0.hasPrefix("=== scenario") }).count) · steps \(stepsRun) · checks \(checksRun) · issues \(issues.count)\n"
        md += "Key events: \(keyEventsWork ? "keyDown path" : "command selectors (input context inactive)") · scroll events: \(scrollViaWindow ? "window.sendEvent" : "scrollView.scrollWheel")\n\n"
        if issues.isEmpty { md += "No issues.\n" } else {
            md += "| # | scenario | step | kind | detail | snapshot |\n|---|---|---|---|---|---|\n"
            for (i, x) in issues.enumerated() {
                md += "| \(i + 1) | \(x.scenario) | \(x.step) | \(x.kind) | \(x.detail.replacingOccurrences(of: "|", with: "/")) | \(x.snapshot ?? "") |\n"
            }
        }
        try? md.write(to: out.appendingPathComponent("report.md"), atomically: true, encoding: .utf8)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(issues) { try? data.write(to: out.appendingPathComponent("report.json")) }
        try? lines.joined(separator: "\n").write(to: out.appendingPathComponent("log.txt"), atomically: true, encoding: .utf8)
        log(issues.isEmpty ? "DONE no issues" : "DONE issues=\(issues.count)")
    }

    // MARK: 시간

    /// 다음 런루프 턴
    func turn() async { await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } } }

    /// 레이아웃·그리기를 강제로 끝내고(창이 가려져 있어도) ms 만큼 기다린다 — 사용자가 한 동작 뒤 화면이 갱신된 상태
    func settle(_ ms: UInt64 = 0) async {
        await turn()
        window.layoutIfNeeded()
        window.displayIfNeeded()
        if ms > 0 { try? await Task.sleep(nanoseconds: ms * 1_000_000) }
        await turn()
        window.layoutIfNeeded()
        window.displayIfNeeded()
    }

    // MARK: 말뭉치 · 문서

    enum Corpus { case small, notes, wide, log }

    /// 임시 폴더에 말뭉치 파일을 만들어(없으면) 탭으로 연다
    @discardableResult
    func open(_ corpus: Corpus, name: String? = nil) async -> URL {
        let file: String
        let body: () -> String
        switch corpus {
        case .small: file = name ?? "small.md"; body = { Bench.smallText + "\n" }
        case .notes: file = name ?? "notes.md"; body = { Bench.makeCorpus(targetBytes: 1_300_000, seed: 22).text }
        case .wide:  file = name ?? "wide.md";  body = { Self.wideCorpus() }
        case .log:   file = name ?? "server.log"; body = { Bench.makeLogCorpus(targetBytes: 4_000_000, seed: 44).text }
        }
        let url = dir.appendingPathComponent(file)
        if !FileManager.default.fileExists(atPath: url.path) { try? body().write(to: url, atomically: true, encoding: .utf8) }
        model.open(url: url)
        await settle(700)
        tv.window?.makeFirstResponder(tv)
        return url
    }

    /// 임의 내용의 파일을 만들어 연다
    @discardableResult
    func open(text: String, name: String) async -> URL {
        let url = dir.appendingPathComponent(name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
        model.open(url: url)
        await settle(500)
        tv.window?.makeFirstResponder(tv)
        return url
    }

    /// 자동 줄바꿈으로 여러 번 감기는 긴 문단들 (한글·영문 혼합) — 추정 높이와 실측 높이가 크게 다른 문서
    static func wideCorpus() -> String {
        var s = ""
        let ko = "오늘 회의에서 정리한 내용을 길게 적어 둔다. 자동 줄바꿈이 두세 번 일어날 만큼 문장을 이어 가며 한글 글꼴 보정 경로도 함께 지나간다. "
        let en = "The quick brown fox jumps over the lazy dog near the river bank while the editor wraps this long paragraph several times. "
        for i in 1...4000 {
            switch i % 5 {
            case 0: s += "\(i) 짧은 줄\n"
            case 1: s += "\(i) " + ko + ko + "\n"
            case 2: s += "\(i) " + en + en + en + "\n"
            case 3: s += "\n"
            default: s += "\(i) " + ko + en + ko + en + ko + "\n"
            }
        }
        return s
    }

    // MARK: 키 이벤트

    enum Key {
        case up, down, left, right, pageUp, pageDown, home, end, delete, forwardDelete, returnKey, tab, escape
        var code: UInt16 {
            switch self {
            case .up: return 126; case .down: return 125; case .left: return 123; case .right: return 124
            case .pageUp: return 116; case .pageDown: return 121; case .home: return 115; case .end: return 119
            case .delete: return 51; case .forwardDelete: return 117; case .returnKey: return 36; case .tab: return 48; case .escape: return 53
            }
        }
        var chars: String {
            func f(_ v: Int) -> String { String(UnicodeScalar(v)!) }
            switch self {
            case .up: return f(NSUpArrowFunctionKey); case .down: return f(NSDownArrowFunctionKey)
            case .left: return f(NSLeftArrowFunctionKey); case .right: return f(NSRightArrowFunctionKey)
            case .pageUp: return f(NSPageUpFunctionKey); case .pageDown: return f(NSPageDownFunctionKey)
            case .home: return f(NSHomeFunctionKey); case .end: return f(NSEndFunctionKey)
            case .delete: return "\u{7F}"; case .forwardDelete: return f(NSDeleteFunctionKey)
            case .returnKey: return "\r"; case .tab: return "\t"; case .escape: return "\u{1B}"
            }
        }
        var isFunctionKey: Bool {
            switch self { case .delete, .returnKey, .tab, .escape: return false; default: return true }
        }
    }

    private func keyEvent(_ k: Key, _ mods: NSEvent.ModifierFlags, down: Bool = true) -> NSEvent? {
        var flags = mods
        if k.isFunctionKey { flags.insert(.function) }
        if [.up, .down, .left, .right].contains(k) { flags.insert(.numericPad) }
        return NSEvent.keyEvent(with: down ? .keyDown : .keyUp, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                windowNumber: window.windowNumber, context: nil, characters: k.chars, charactersIgnoringModifiers: k.chars,
                                isARepeat: false, keyCode: k.code)
    }

    /// 표준 키 바인딩이 이 키에 붙이는 명령 (입력 컨텍스트가 비활성이라 keyDown 이 무시될 때의 대체 경로)
    private func selector(for k: Key, _ mods: NSEvent.ModifierFlags) -> Selector? {
        let shift = mods.contains(.shift), opt = mods.contains(.option), cmd = mods.contains(.command)
        func pick(_ plain: String, _ sel: String) -> Selector { NSSelectorFromString(shift ? sel : plain) }
        switch k {
        case .up:    return cmd ? pick("moveToBeginningOfDocument:", "moveToBeginningOfDocumentAndModifySelection:") : opt ? pick("moveToBeginningOfParagraph:", "moveParagraphBackwardAndModifySelection:") : pick("moveUp:", "moveUpAndModifySelection:")
        case .down:  return cmd ? pick("moveToEndOfDocument:", "moveToEndOfDocumentAndModifySelection:") : opt ? pick("moveToEndOfParagraph:", "moveParagraphForwardAndModifySelection:") : pick("moveDown:", "moveDownAndModifySelection:")
        case .left:  return cmd ? pick("moveToLeftEndOfLine:", "moveToLeftEndOfLineAndModifySelection:") : opt ? pick("moveWordLeft:", "moveWordLeftAndModifySelection:") : pick("moveLeft:", "moveLeftAndModifySelection:")
        case .right: return cmd ? pick("moveToRightEndOfLine:", "moveToRightEndOfLineAndModifySelection:") : opt ? pick("moveWordRight:", "moveWordRightAndModifySelection:") : pick("moveRight:", "moveRightAndModifySelection:")
        case .pageUp:   return opt ? pick("pageUp:", "pageUpAndModifySelection:") : pick("scrollPageUp:", "pageUpAndModifySelection:")
        case .pageDown: return opt ? pick("pageDown:", "pageDownAndModifySelection:") : pick("scrollPageDown:", "pageDownAndModifySelection:")
        case .home: return pick("scrollToBeginningOfDocument:", "moveToBeginningOfDocumentAndModifySelection:")
        case .end:  return pick("scrollToEndOfDocument:", "moveToEndOfDocumentAndModifySelection:")
        case .delete: return opt ? #selector(NSResponder.deleteWordBackward(_:)) : cmd ? #selector(NSResponder.deleteToBeginningOfLine(_:)) : #selector(NSResponder.deleteBackward(_:))
        case .forwardDelete: return opt ? #selector(NSResponder.deleteWordForward(_:)) : #selector(NSResponder.deleteForward(_:))
        case .returnKey: return #selector(NSResponder.insertNewline(_:))
        case .tab: return shift ? #selector(NSResponder.insertBacktab(_:)) : #selector(NSResponder.insertTab(_:))
        case .escape: return #selector(NSResponder.cancelOperation(_:))
        }
    }

    /// 키를 누른다 — 사용자가 편집기에 포커스를 두고 누른 것과 같은 경로 (keyDown → 키 바인딩 → doCommand)
    func key(_ k: Key, _ mods: NSEvent.ModifierFlags = [], count: Int = 1) async {
        for _ in 0..<count {
            if window.firstResponder !== tv { window.makeFirstResponder(tv) }
            if keyEventsWork, let e = keyEvent(k, mods) {
                tv.keyDown(with: e)
                if let up = keyEvent(k, mods, down: false) { tv.keyUp(with: up) }
            } else if let sel = selector(for: k, mods) {
                tv.doCommand(by: sel)
            }
            await turn()
        }
    }

    /// ⌘ 조합 단축키 — 메뉴의 키 등가물 경로 (메뉴를 열지 않는다)
    @discardableResult
    func shortcut(_ chars: String, _ mods: NSEvent.ModifierFlags = [.command]) async -> Bool {
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars.lowercased(),
                                       isARepeat: false, keyCode: 0) else { return false }
        let handled = NSApp.mainMenu?.performKeyEquivalent(with: e) ?? false
        await turn()
        return handled
    }

    /// 글자를 친다 — 입력기가 확정 문자를 넣는 경로(insertText). 선택이 있으면 대체한다
    func type(_ s: String, turnEvery: Int = 1) async {
        if window.firstResponder !== tv { window.makeFirstResponder(tv) }
        var n = 0
        for ch in s {
            if ch == "\n" { await key(.returnKey); continue }
            tv.insertText(String(ch), replacementRange: NSRange(location: NSNotFound, length: 0))
            n += 1
            if n % turnEvery == 0 { await turn() }
        }
        await turn()
    }

    /// 한글 두벌식 조합을 흉내 낸다: 음절마다 조합 중 글자(setMarkedText)가 자라다가 확정(insertText)된다
    func composeHangul(_ s: String) async {
        if window.firstResponder !== tv { window.makeFirstResponder(tv) }
        let cho = ["ㄱ","ㄲ","ㄴ","ㄷ","ㄸ","ㄹ","ㅁ","ㅂ","ㅃ","ㅅ","ㅆ","ㅇ","ㅈ","ㅉ","ㅊ","ㅋ","ㅌ","ㅍ","ㅎ"]
        let none = NSRange(location: NSNotFound, length: 0)
        for ch in s {
            guard let u = ch.unicodeScalars.first, ch.unicodeScalars.count == 1, (0xAC00...0xD7A3).contains(u.value) else {
                tv.insertText(String(ch), replacementRange: none); await turn(); continue
            }
            let idx = Int(u.value - 0xAC00)
            let c = idx / 588, j = (idx % 588) / 28, t = idx % 28
            var stages = [cho[c], String(UnicodeScalar(UInt32(0xAC00 + c * 588 + j * 28))!)]
            if t != 0 { stages.append(String(ch)) }
            for st in stages {
                tv.setMarkedText(st, selectedRange: NSRange(location: (st as NSString).length, length: 0), replacementRange: none)
                await turn()
            }
            tv.insertText(String(ch), replacementRange: none)
            await turn()
        }
    }

    // MARK: 스크롤 이벤트

    private func scrollEvent(points: CGFloat, lines: Int32?, phase: Int64, momentum: Int64) -> NSEvent? {
        let cg: CGEvent?
        if let lines { cg = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0) }
        else {
            cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(points.rounded()), wheel2: 0, wheel3: 0)
            cg?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            cg?.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(points))
            cg?.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(points))
        }
        guard let cg else { return nil }
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        // 편집기 한가운데를 가리키는 위치 (전역 좌표: 왼쪽 위 원점)
        let mid = scroll.convert(NSPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: nil)
        let onScreen = window.convertPoint(toScreen: mid)
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        cg.location = CGPoint(x: onScreen.x, y: screenH - onScreen.y)
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.windowNumber))
        return NSEvent(cgEvent: cg)
    }

    private func deliverScroll(_ e: NSEvent) {
        if scrollViaWindow, e.window === window { window.sendEvent(e) } else { scroll.scrollWheel(with: e) }
    }

    /// 픽셀 단위 휠(트랙패드·매직 마우스의 연속 스크롤): 양수 = 문서 아래쪽으로
    func scrollBy(_ points: CGFloat) async {
        if let e = scrollEvent(points: -points, lines: nil, phase: 0, momentum: 0) { deliverScroll(e) }
        await turn()
    }

    /// 줄 단위 휠(일반 마우스의 딸깍 휠): 양수 = 아래로. 부드러운 스크롤 애니메이션이 끝나길 기다린다
    func wheelLines(_ n: Int32) async {
        if let e = scrollEvent(points: 0, lines: -n, phase: 0, momentum: 0) { deliverScroll(e) }
        await settle(250)
    }

    /// 트랙패드 쓸기: 손가락 단계(began → changed… → ended) 뒤 관성 단계(begin → continue… → end). total 양수 = 아래로
    func flick(total: CGFloat, steps: Int = 8, momentumSteps: Int = 12) async {
        let finger = total * 0.45, coast = total - finger
        let per = finger / CGFloat(max(1, steps))
        for i in 0..<steps {
            if let e = scrollEvent(points: -per, lines: nil, phase: i == 0 ? 1 : 2, momentum: 0) { deliverScroll(e) }
            await turn()
        }
        if let e = scrollEvent(points: 0, lines: nil, phase: 4, momentum: 0) { deliverScroll(e) }
        await turn()
        // 관성: 기하급수로 줄어드는 델타
        var weights: [CGFloat] = []
        var w: CGFloat = 1
        for _ in 0..<momentumSteps { weights.append(w); w *= 0.8 }
        let sum = weights.reduce(0, +)
        for (i, wt) in weights.enumerated() {
            let d = coast * wt / sum
            if let e = scrollEvent(points: -d, lines: nil, phase: 0, momentum: i == 0 ? 1 : 2) { deliverScroll(e) }
            await turn()
        }
        if let e = scrollEvent(points: 0, lines: nil, phase: 0, momentum: 3) { deliverScroll(e) }
        await settle(50)
    }

    // MARK: 마우스 이벤트

    private func mouseEvent(_ type: NSEvent.EventType, at pInWindow: NSPoint, clicks: Int, mods: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.mouseEvent(with: type, location: pInWindow, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: type == .leftMouseUp ? 0 : 1)
    }

    /// 문자 오프셋의 화면 위치 (텍스트 뷰 좌표). 보이지 않으면 nil
    func point(forOffset offset: Int, dx: CGFloat = 1) -> NSPoint? {
        guard let r = tv.caretRect(at: offset) else { return nil }
        let p = NSPoint(x: r.minX + dx, y: r.midY)
        return tv.visibleRect.contains(p) ? p : nil
    }

    /// 텍스트 뷰 좌표의 점을 클릭한다. 텍스트 뷰의 mouseDown 은 mouseUp 이 올 때까지 이벤트를 기다리므로 mouseUp 을 먼저 큐에 넣는다.
    /// 이벤트는 창의 sendEvent 가 아니라 텍스트 뷰에 직접 준다 — 비활성 창의 첫 클릭은 창을 활성화하는 데 쓰이고(뷰에 오지 않는다) 창을 앞으로 끌어올려
    /// 사용자가 쓰고 있는 화면을 가린다. 히트 테스트(점 → 글자)는 텍스트 뷰의 mouseDown 안에서 실제와 똑같이 일어난다
    func click(atViewPoint p: NSPoint, clicks: Int = 1, mods: NSEvent.ModifierFlags = []) async {
        let w = tv.convert(p, to: nil)
        if window.firstResponder !== tv { window.makeFirstResponder(tv) }
        // 더블·트리플 클릭은 앞선 클릭들이 먼저 온다 (clickCount 1, 2, …)
        for n in 1...max(1, clicks) {
            guard let down = mouseEvent(.leftMouseDown, at: w, clicks: n, mods: mods), let up = mouseEvent(.leftMouseUp, at: w, clicks: n, mods: mods) else { return }
            NSApp.postEvent(up, atStart: false)
            tv.mouseDown(with: down)
            await turn()
        }
    }

    /// 문자 오프셋 위치를 클릭한다 (보이는 곳이어야 한다). 반환: 클릭했는가
    @discardableResult
    func click(offset: Int, clicks: Int = 1, mods: NSEvent.ModifierFlags = []) async -> Bool {
        guard let p = point(forOffset: offset) else { return false }
        await click(atViewPoint: p, clicks: clicks, mods: mods)
        return true
    }

    /// 한 점에서 다른 점까지 끌어 선택한다 (텍스트 뷰 좌표)
    func drag(from a: NSPoint, to b: NSPoint, steps: Int = 6) async {
        let wa = tv.convert(a, to: nil), wb = tv.convert(b, to: nil)
        guard let down = mouseEvent(.leftMouseDown, at: wa, clicks: 1, mods: []) else { return }
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = NSPoint(x: wa.x + (wb.x - wa.x) * t, y: wa.y + (wb.y - wa.y) * t)
            if let d = mouseEvent(.leftMouseDragged, at: p, clicks: 1, mods: []) { NSApp.postEvent(d, atStart: false) }
        }
        if let up = mouseEvent(.leftMouseUp, at: wb, clicks: 1, mods: []) { NSApp.postEvent(up, atStart: false) }
        if window.firstResponder !== tv { window.makeFirstResponder(tv) }
        tv.mouseDown(with: down)
        await turn()
    }

    // MARK: 보정

    /// 이 실행에서 키·스크롤 이벤트 경로가 통하는지 확인한다 (앱이 비활성이어도 돌아야 한다)
    func calibrate() async {
        begin(scenario: "calibrate")
        await open(.small, name: "calibrate.md")
        at("key path")
        tv.setSelectedRange(NSRange(location: 0, length: 0))
        await key(.right)
        if tv.selectedRange().location != 1 {
            keyEventsWork = false
            await key(.right)
            note("keyDown ignored (input context inactive) → command selectors; caret now \(tv.selectedRange().location)")
        }
        log("calibrate: key events \(keyEventsWork ? "work" : "fall back to selectors")")
        at("scroll path")
        if let e = scrollEvent(points: -120, lines: nil, phase: 0, momentum: 0) {
            scrollViaWindow = e.window === window
            log("calibrate: scroll events via \(scrollViaWindow ? "window.sendEvent" : "scrollView.scrollWheel") (event window \(e.window == nil ? "nil" : "ok")) · a 120 px event reports scrollingDeltaY=\(e.scrollingDeltaY) deltaY=\(e.deltaY) precise=\(e.hasPreciseScrollingDeltas)")
        }
        model.closeTabs(in: dir)
        end()
    }

    // MARK: 불변식

    struct Frag { let minY: CGFloat; let maxY: CGFloat; let offset: Int; let length: Int }

    /// 지금 뷰포트에 배치된 레이아웃 조각들 (텍스트 뷰 좌표, 문서 순서). 높이 0(접힘)은 뺀다
    func viewportFragments() -> [Frag] {
        guard let lm = tv.textLayoutManager, let cs = tv.textContentStorage, let vr = lm.textViewportLayoutController.viewportRange else { return [] }
        let originY = tv.textContainerOrigin.y
        // 캐럿을 키보드로 옮긴 직후에는 viewportRange 가 길이 0 인 범위다 (AppKit 이 scrollRangeToVisible 안에서 뷰포트를 캐럿 줄로 '재배치'만 하고 다시 배치하지
        // 않는다 — 화면은 앞선 배치 그대로, 다음 스크롤·편집까지. 실측 2026-11-24). 그때는 보이는 영역의 위·아래 끝에 놓인 문단 사이를 본다 — 안 그러면 조각이
        // 0개라 checkLayout 이 "no layout fragments" 거짓 양성을 내고 checkGutter·checkInk 는 아무것도 보지 않은 채 통과한다
        var start = vr.location, end = vr.endLocation
        if vr.isEmpty {
            let v = tv.visibleRect
            guard let first = lm.textLayoutFragment(for: CGPoint(x: 0, y: max(0, v.minY - originY))) else { return [] }
            start = first.rangeInElement.location
            end = lm.textLayoutFragment(for: CGPoint(x: 0, y: max(0, v.maxY - originY)))?.rangeInElement.endLocation ?? lm.documentRange.endLocation
        }
        var out: [Frag] = []
        lm.enumerateTextLayoutFragments(from: start, options: []) { f in
            if f.rangeInElement.location.compare(end) != .orderedAscending { return false }
            let fr = f.layoutFragmentFrame
            if fr.height > 0 {
                let off = cs.offset(from: cs.documentRange.location, to: f.rangeInElement.location)
                let len = cs.offset(from: f.rangeInElement.location, to: f.rangeInElement.endLocation)
                out.append(Frag(minY: fr.minY + originY, maxY: fr.maxY + originY, offset: off, length: len))
            }
            return out.count < 400
        }
        return out
    }

    /// 선택 범위·뷰포트·레이아웃 조각의 틈/겹침/덮임을 검사한다. `why` 는 방금 한 동작
    func checkLayout(_ why: String) {
        checksRun += 1
        let sel = tv.selectedRange()
        if sel.location < 0 || NSMaxRange(sel) > length { issue("selection", "\(why): selection \(sel) outside 0..<\(length)") }
        let v = visible
        let docH = tv.frame.height
        if v.minY < -0.5 || v.maxY > docH + 0.5 { issue("viewport-jump", "\(why): visible \(Int(v.minY))…\(Int(v.maxY)) outside document height \(Int(docH))") }
        let frags = viewportFragments()
        guard !frags.isEmpty else { if length > 0 { issue("coverage", "\(why): no layout fragments in the viewport (visible \(Int(v.minY))…\(Int(v.maxY)))") }; return }
        for (a, b) in zip(frags, frags.dropFirst()) {
            let gap = b.minY - a.maxY
            if gap > 1 { issue("gap", "\(why): \(String(format: "%.1f", gap)) pt gap between fragments at offsets \(a.offset) and \(b.offset) (y \(Int(a.maxY)))") ; break }
            if gap < -1 { issue("overlap", "\(why): fragments at offsets \(a.offset) and \(b.offset) overlap by \(String(format: "%.1f", -gap)) pt (y \(Int(b.minY)))"); break }
        }
        let lh = lineHeight
        if let first = frags.first, first.minY > v.minY + lh, first.offset > 0 {
            issue("coverage", "\(why): viewport top \(Int(v.minY)) not covered — first fragment starts at \(Int(first.minY)) (offset \(first.offset))")
        }
        if let last = frags.last, last.maxY < v.maxY - lh, last.offset + last.length < length {
            issue("coverage", "\(why): viewport bottom \(Int(v.maxY)) not covered — last fragment ends at \(Int(last.maxY)) (offset \(last.offset))")
        }
    }

    /// 캐럿이 보이는가 (입력·화살표 이동 뒤에는 보여야 한다)
    func checkCaretVisible(_ why: String) {
        checksRun += 1
        guard let r = tv.caretRect(at: caret) else { return }
        let v = visible.insetBy(dx: 0, dy: -2)
        if r.maxY < v.minY || r.minY > v.maxY { issue("caret-hidden", "\(why): caret at offset \(caret) (y \(Int(r.minY))) outside visible \(Int(v.minY))…\(Int(v.maxY))") }
    }

    /// 스크롤 동작 뒤의 이동량이 기대와 맞는가
    func checkScrolled(from y0: CGFloat, expected: CGFloat, tolerance: CGFloat, _ why: String) {
        checksRun += 1
        let moved = visible.minY - y0
        if abs(moved - expected) > tolerance { issue("scroll-delta", "\(why): moved \(String(format: "%.1f", moved)) pt, expected \(String(format: "%.1f", expected)) ± \(Int(tolerance))") }
    }

    /// 스크롤하지 않는 동작 뒤에 화면이 튀지 않았는가
    func checkViewportStable(from y0: CGFloat, tolerance: CGFloat? = nil, _ why: String) {
        checksRun += 1
        let tol = tolerance ?? lineHeight * 2
        if abs(visible.minY - y0) > tol { issue("viewport-jump", "\(why): viewport moved \(String(format: "%.1f", visible.minY - y0)) pt (from \(Int(y0)) to \(Int(visible.minY)))") }
    }

    /// 거터의 줄 번호가 본문 조각과 같은 높이에 그려졌는가
    func checkGutter(_ why: String) {
        guard let g = gutter, !g.isHidden, g.bounds.width > 1 else { return }
        checksRun += 1
        g.display()
        let rows = g.debugRows
        let v = visible
        let idx = LineIndex(nsString: text)
        let frags = viewportFragments().filter { $0.maxY > v.minY + 1 && $0.minY < v.maxY - 1 }
        for f in frags {
            let line = idx.lineNumber(forUTF16Offset: f.offset)
            let y = f.minY - v.minY
            guard let row = rows.first(where: { $0.line == line }) else {
                issue("gutter", "\(why): line \(line) is on screen (y \(Int(y))) but the gutter drew no number for it (\(rows.count) rows drawn)"); return
            }
            if abs(row.y - y) > 1.5 { issue("gutter", "\(why): line \(line) number drawn at y \(String(format: "%.1f", row.y)) but its text is at \(String(format: "%.1f", y))"); return }
        }
    }

    /// 보이는 조각마다 실제로 글자가 그려졌는가 (TextKit 2 의 '빈 영역' 결함 탐지). 텍스트 뷰만 비트맵으로 그려 배경색과 다른 픽셀을 센다
    func checkInk(_ why: String) {
        checksRun += 1
        let v = visible
        guard v.height > 10, let rep = tv.bitmapImageRepForCachingDisplay(in: v) else { return }
        tv.cacheDisplay(in: v, to: rep)
        let scale = CGFloat(rep.pixelsHigh) / v.height
        guard let bg = rep.colorAt(x: rep.pixelsWide - 3, y: 2) else { return }
        func isInk(_ x: Int, _ y: Int) -> Bool {
            guard let c = rep.colorAt(x: x, y: y) else { return false }
            return abs(c.redComponent - bg.redComponent) + abs(c.greenComponent - bg.greenComponent) + abs(c.blueComponent - bg.blueComponent) > 0.25
        }
        let ns = text
        let frags = viewportFragments().filter { $0.minY >= v.minY && $0.maxY <= v.maxY }
        var blank = 0, firstBlank = -1
        for f in frags {
            let s = ns.substring(with: NSIntersectionRange(NSRange(location: f.offset, length: f.length), NSRange(location: 0, length: ns.length)))
            guard s.contains(where: { !$0.isWhitespace }) else { continue }
            let y0 = Int((f.minY - v.minY) * scale), y1 = Int((f.maxY - v.minY) * scale)
            var ink = false
            var y = y0 + 2
            while y < y1 - 1 && !ink {
                var x = 4
                while x < rep.pixelsWide - 4 { if isInk(x, y) { ink = true; break }; x += 3 }
                y += 2
            }
            if !ink { blank += 1; if firstBlank < 0 { firstBlank = f.offset } }
        }
        if blank > 0 { issue("blank", "\(why): \(blank) of \(frags.count) visible paragraphs have text but nothing drawn (first at offset \(firstBlank))") }
    }

    /// 화면 맨 위에 보이는 줄 번호 (레이아웃이 바뀌는 동작 전후에 같은 곳을 보고 있는지 비교)
    func topLine() -> Int {
        let v = visible
        let frags = viewportFragments()
        let f = frags.first(where: { $0.maxY > v.minY + 1 }) ?? frags.first
        return LineIndex(nsString: text).lineNumber(forUTF16Offset: f?.offset ?? 0)
    }

    /// 문단(조각 시작 오프셋)이 지금 화면의 어느 높이에 있는가 (뷰포트 위 가장자리로부터, pt). 배치돼 있지 않으면 nil
    func screenY(ofFragmentAt offset: Int) -> CGFloat? {
        viewportFragments().first(where: { $0.offset == offset }).map { $0.minY - visible.minY }
    }

    /// 화면 한가운데쯤에 보이는 문단의 (시작 오프셋, 화면 높이) — 스크롤·레이아웃 변화 전후에 "내용이 화면에서 얼마나 움직였나"를 재는 닻
    func anchor() -> (offset: Int, y: CGFloat)? {
        let v = visible
        let frags = viewportFragments().filter { $0.minY >= v.minY && $0.maxY <= v.maxY }
        guard let f = frags.dropFirst(frags.count / 2).first else { return nil }
        return (f.offset, f.minY - v.minY)
    }

    /// 스크롤 동작 뒤 **화면에서 내용이 움직인 양**이 기대와 맞는가. TextKit 2 는 스크롤 중 위쪽 문단의 추정 높이를 실측으로 바꾸며 문서 좌표를 통째로
    /// 옮길 수 있으므로 `visible.minY` 의 변화가 아니라 닻 문단의 화면 높이 변화를 본다. expected 양수 = 문서 아래쪽으로 스크롤(내용은 위로)
    func checkContentMoved(anchor a: (offset: Int, y: CGFloat)?, expected: CGFloat, tolerance: CGFloat, _ why: String) {
        checksRun += 1
        guard let a, let y1 = screenY(ofFragmentAt: a.offset) else { return }   // 닻이 화면 밖으로 나갔다 — 잴 수 없다
        let moved = a.y - y1
        if abs(moved - expected) > tolerance { issue("scroll-delta", "\(why): content moved \(String(format: "%.1f", moved)) pt on screen, expected \(String(format: "%.1f", expected)) ± \(Int(tolerance))") }
    }

    /// 자주 쓰는 묶음: 레이아웃 + 거터
    func checkAll(_ why: String) { checkLayout(why); checkGutter(why) }

    // MARK: 메인 스레드 정지 감시

    private var stallTimer: DispatchSourceTimer?
    private let stallQueue = DispatchQueue(label: "realuse.stall")
    private var stallThresholdMs: Double = 250

    func startStallMonitor() {
        let t = DispatchSource.makeTimerSource(queue: stallQueue)
        t.schedule(deadline: .now() + 0.05, repeating: 0.05)
        t.setEventHandler { [weak self] in
            let sent = CFAbsoluteTimeGetCurrent()
            DispatchQueue.main.async {
                let lag = (CFAbsoluteTimeGetCurrent() - sent) * 1000
                guard let self, lag > self.stallThresholdMs else { return }
                self.issue("stall", String(format: "main thread blocked for %.0f ms", lag), snap: false)
            }
        }
        t.resume()
        stallTimer = t
    }

    func stopStallMonitor() { stallTimer?.cancel(); stallTimer = nil }

    /// 무거운 준비(큰 파일 생성·열기) 동안은 정지 감시 문턱을 올려 둔다
    func withRelaxedStalls(_ ms: Double = 3000, _ body: () async -> Void) async {
        let old = stallThresholdMs; stallThresholdMs = ms
        await body()
        await turn()
        stallThresholdMs = old
    }
}

// MARK: - 기본 시나리오 (하네스 자체 점검)

extension RealUse {
    @MainActor static let coreScenarios: [Scenario] = [
        Scenario(name: "smoke") { ctx in
            await ctx.withRelaxedStalls { await ctx.open(.notes) }
            ctx.at("opened"); ctx.checkAll("after open"); ctx.checkInk("after open"); ctx.snap("opened")
            ctx.at("jump to end")
            await ctx.key(.down, [.command])
            await ctx.settle(100)
            ctx.checkAll("after ⌘↓"); ctx.checkInk("after ⌘↓"); ctx.checkCaretVisible("after ⌘↓"); ctx.snap("at-end")
            ctx.at("type at end")
            let y0 = ctx.visible.minY
            await ctx.type("real use smoke 한글 ")
            await ctx.composeHangul("실제 입력")
            await ctx.settle(50)
            ctx.checkViewportStable(from: y0, "typing at the end"); ctx.checkCaretVisible("typing at the end"); ctx.checkAll("typing at the end")
            ctx.at("wheel up")
            let a = ctx.anchor()
            await ctx.scrollBy(-200); await ctx.settle(50)
            ctx.checkContentMoved(anchor: a, expected: -200, tolerance: 2, "pixel wheel up 200"); ctx.checkAll("wheel up"); ctx.checkInk("wheel up")
            ctx.at("click")
            if let t = ctx.anchor() {
                let ok = await ctx.click(offset: t.offset)
                if ok, ctx.caret != t.offset { ctx.issue("other", "clicked the start of the paragraph at offset \(t.offset) but the caret went to \(ctx.caret)") }
            }
            ctx.snap("end")
        },
        // 진단용: 문서 끝에서 위로 조금씩 스크롤하며 문서 좌표·화면 좌표가 어떻게 움직이는지, 클릭이 그려진 줄에 놓이는지 기록한다 (검사 없이 로그만)
        Scenario(name: "diag") { ctx in
            await ctx.withRelaxedStalls { await ctx.open(.notes) }
            await ctx.key(.down, [.command]); await ctx.settle(300)
            let idx = LineIndex(nsString: ctx.text)
            @MainActor func state(_ tag: String) {
                let v = ctx.visible
                let fr = ctx.viewportFragments().filter { $0.maxY > v.minY && $0.minY < v.maxY }
                guard let f = fr.first, let l = fr.last else { ctx.log("  \(tag): no fragments"); return }
                ctx.log(String(format: "  %@: visibleY=%.1f h=%.0f docH=%.1f frags=%d first=L%d@%.1f last=L%d@%.1f", tag, v.minY, v.height, ctx.tv.frame.height, fr.count,
                               idx.lineNumber(forUTF16Offset: f.offset), f.minY - v.minY, idx.lineNumber(forUTF16Offset: l.offset), l.minY - v.minY))
            }
            state("at end")
            for i in 1...14 {
                let a = ctx.anchor(); let y0 = ctx.visible.minY, h0 = ctx.tv.frame.height
                await ctx.scrollBy(-100); await ctx.settle(0)
                let y1 = a.flatMap { ctx.screenY(ofFragmentAt: $0.offset) }
                ctx.log(String(format: "  step %d (-100): visibleY %+.1f, docH %+.1f, anchor on screen %@", i, ctx.visible.minY - y0, ctx.tv.frame.height - h0,
                               (a != nil && y1 != nil) ? String(format: "%+.1f", y1! - a!.y) : "lost"))
            }
            state("after 14 × -100")
            let v = ctx.visible
            for f in ctx.viewportFragments().filter({ $0.minY >= v.minY && $0.maxY <= v.maxY }).prefix(12) {
                let target = idx.lineNumber(forUTF16Offset: f.offset)
                guard let p = ctx.point(forOffset: f.offset) else { continue }
                await ctx.click(atViewPoint: p)
                let got = LineIndex(nsString: ctx.text).lineNumber(forUTF16Offset: ctx.caret)
                ctx.log(String(format: "  click L%d at view y=%.1f (screen %.1f) → caret L%d offset %+d%@", target, p.y, p.y - ctx.visible.minY, got, ctx.caret - f.offset, got == target ? "" : "  ✗"))
            }
            ctx.snap("after-clicks")
        },
    ]
}
