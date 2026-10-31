import AppKit
import Combine
import HyperCore

/// 매크로 기록·재생 (UltraEdit 매크로 계승).
/// 기록: `HyperTextView.macroSink` 가 입력(`insertText`)·명령(`doCommand`)·붙여넣기를, `EditorView.applyTextTool` 이 텍스트 도구를,
/// `AppModel.findNext` 가 다음 찾기를 보낸다. 마우스 클릭·선택 변경·멀티 커서 편집(모두 바꾸기, 숫자 채우기)은 기록하지 않는다.
/// 재생: 활성 텍스트 뷰에 단계를 순서대로 적용한다. 반복 전체가 undo 한 단계이고, find 가 실패하거나 한 바퀴에 아무 변화가 없으면 멈춘다.
@MainActor
final class MacroRecorder: ObservableObject {
    enum State: Equatable { case idle, recording, playing }

    struct PlayResult {
        /// 끝까지 수행한 반복 횟수
        var iterations = 0
        /// 적용된 단계 수 (건너뛴 것 제외)
        var steps = 0
        /// 알 수 없는 명령·도구라 건너뛴 단계 수
        var skipped = 0
        /// find 실패 또는 무변화로 요청 횟수 전에 멈춤
        var stoppedEarly = false
        var ms: Double = 0
    }

    static let maxRepeat = 10_000

    let store: MacroStore
    @Published private(set) var state: State = .idle
    // 알림창 상태 (ContentView 의 MacroAlerts 가 바인딩)
    @Published var showRepeatAlert = false
    @Published var repeatText = "10"
    @Published var showSaveAlert = false
    @Published var saveName = ""

    private var recording = MacroRecording()
    private weak var model: AppModel?
    private var cancellables = Set<AnyCancellable>()

    var isRecording: Bool { state == .recording }
    var isPlaying: Bool { state == .playing }
    var lastRecorded: Macro? { store.lastRecorded }
    var hasLast: Bool { !(store.lastRecorded?.steps.isEmpty ?? true) }

    init() {
        // 자동화 실행(셀프테스트·스냅샷·--ephemeral)은 사용자의 매크로 파일을 건드리지 않는다
        if LaunchOptions.has("--selftest") || LaunchOptions.has("--selftest-open") || LaunchOptions.has("--snapshot") || LaunchOptions.has("--ephemeral") {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("hyperedit-macros-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
            store = MacroStore(directory: dir)
        } else {
            store = MacroStore()
        }
    }

    /// 편집기가 텍스트 뷰를 만들 때 호출 — 기록 싱크를 달고 모델과 연결한다 (뷰가 여럿이어도 각자 호출; 모델 연결은 한 번)
    func install(on tv: HyperTextView, model: AppModel) {
        tv.macroSink = { [weak self] step in self?.record(step) }
        guard self.model == nil else { return }
        self.model = model
        // 상태 변화를 AppModel 구독자(메뉴 제목·리본·상태바)에도 전달. 기록 시작/중지·재생·저장 때만 발생한다
        objectWillChange.sink { [weak model] _ in model?.objectWillChange.send() }.store(in: &cancellables)
        store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        // 파일 전환: 기록 중이면 중단한다 (다른 문서에 이어 기록하는 것은 뜻이 없다). 매크로 JSON 을 직접 고치고 나왔으면 다시 읽는다
        model.document.$url
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.documentWillSwitch() }
            .store(in: &cancellables)
        if let e = store.loadError { model.log(String(localized: "Macros file could not be read · \(e)"), isError: true) }
    }

    private func documentWillSwitch() {
        guard let model else { return }
        if state == .recording {
            finishRecording()
            model.log(String(localized: "Macro recording stopped · document changed"))
        }
        // $url 은 willSet 에 발행되므로 document.url 은 아직 이전 파일 (동기 저장은 끝났다) — 그 파일이 매크로 JSON 이었으면 다시 읽는다.
        // 문서 URL 은 심볼릭 링크를 푼 경로라(MemoDocument.switchTo) 저장소 경로도 풀어서 비교한다 (Application Support 가 링크면 안 맞는다)
        if model.document.url.resolvingSymlinksInPath().path == store.fileURL.resolvingSymlinksInPath().path {
            store.reload()
            if let e = store.loadError { model.log(String(localized: "Macros file could not be read · \(e)"), isError: true) }
            else { model.log(String(localized: "Macros reloaded · \(store.macros.count) macros")) }
        }
    }

    // MARK: 기록

    func record(_ step: MacroStep) {
        guard state == .recording else { return }
        recording.append(step)
    }

    /// F3 (AppModel.findNext) — 검색어를 함께 기록해 재생이 검색 패널 상태와 무관하게 결정적이도록
    func recordFind(_ query: String) {
        guard state == .recording, !query.isEmpty else { return }
        recording.append(.find(query))
    }

    func toggleRecording() {
        switch state {
        case .recording: stopRecording()
        case .idle: startRecording()
        case .playing: break
        }
    }

    func startRecording() {
        guard state == .idle, let model else { return }
        recording = MacroRecording()
        state = .recording
        model.focusEditor()
        model.log(String(localized: "Macro recording started"))
    }

    @discardableResult
    func stopRecording() -> Macro? {
        guard state == .recording else { return nil }
        let macro = finishRecording()
        if let macro {
            model?.log(String(localized: "Macro recorded · \(macro.steps.count) steps"))
        } else {
            model?.log(String(localized: "Macro recording stopped · nothing recorded"))
        }
        return macro
    }

    @discardableResult
    private func finishRecording() -> Macro? {
        state = .idle
        let steps = recording.steps
        recording = MacroRecording()
        guard !steps.isEmpty else { return nil }
        let macro = Macro(name: "", steps: steps)
        store.setLastRecorded(macro)
        return macro
    }

    // MARK: 재생

    @discardableResult
    func playLast(times: Int = 1) async -> PlayResult? {
        guard let macro = store.lastRecorded, !macro.steps.isEmpty else {
            model?.log(String(localized: "No macro recorded yet (⇧⌘M to record)"))
            return nil
        }
        return await play(macro, times: times)
    }

    @discardableResult
    func play(id: UUID, times: Int = 1) async -> PlayResult? {
        guard let macro = store.macro(id: id) else { return nil }
        return await play(macro, times: times)
    }

    /// 활성 텍스트 뷰에 재생. 반복 전체가 undo 한 단계. 50 ms 마다 런루프에 양보해 메인 스레드가 멈춘 것으로 보이지 않게 한다
    /// (양보 중에도 undo 그룹이 열려 있도록 groupsByEvent 를 잠시 끈다 — 켜진 채로는 런루프 끝에 그룹이 자동으로 닫힌다).
    @discardableResult
    func play(_ macro: Macro, times: Int) async -> PlayResult? {
        guard state == .idle, let model, !macro.steps.isEmpty else { return nil }
        let times = max(1, min(times, Self.maxRepeat))
        var target: HyperTextView?
        model.send(.perform { target = $0 })
        guard let tv = target else { return nil }

        state = .playing
        tv.macroSuppressDepth += 1
        defer { tv.macroSuppressDepth -= 1; state = .idle }
        // 재생 중 사용자 키·마우스 입력은 버린다 — 50 ms 마다 런루프에 양보하는 동안 ⌘Z(undo) 가 들어오면 열어 둔 undo 그룹이 닫혀
        // 아래 endUndoGrouping 이 NSInternalInconsistencyException 으로 죽고, 클릭은 활성 편집기를 바꿔 단계가 다른 뷰에 적용된다
        let inputMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { _ in nil }
        defer { if let inputMonitor { NSEvent.removeMonitor(inputMonitor) } }
        tv.window?.makeFirstResponder(tv)
        tv.breakUndoCoalescing()
        let um = tv.undoManager
        // AppKit 은 이벤트 처리 끝에만 자동 undo 그룹을 닫는다 (런루프 양보·타이머로는 안 닫힘 — 실측). 사용자 조작 뒤에는 여기서 레벨이 0 이지만,
        // 이벤트 없이 프로그램적으로 편집한 직후(셀프테스트·자동화)엔 열린 채일 수 있다. 직접 endUndoGrouping 으로 닫으면 NSTextView 의 입력 합치기
        // 상태와 어긋나 다음 입력에서 _prepareEventGrouping 예외가 난다(실측) → 빈 이벤트를 하나 흘려 AppKit 스스로 닫게 한 뒤 시작한다.
        var pumps = 0
        while let um, um.groupingLevel > 0, pumps < 3 {
            pumps += 1
            if let e = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApp.postEvent(e, atStart: false)
            }
            try? await Task.sleep(nanoseconds: 30_000_000)
            Perf.log("macro: pumped an event to close the open undo group → level \(um.groupingLevel)")
        }
        let groupsByEvent = um?.groupsByEvent ?? true
        um?.groupsByEvent = false
        um?.beginUndoGrouping()

        // 진행 감지: 스토리지 편집 횟수 + 선택 범위가 한 바퀴 뒤에도 그대로면 더 돌려도 소용없다
        var edits = 0
        var observer: AnyCancellable?
        if let ts = tv.textStorage {
            observer = NotificationCenter.default.publisher(for: NSTextStorage.didProcessEditingNotification, object: ts).sink { _ in edits += 1 }
        }

        var result = PlayResult()
        var reason: String?
        let t0 = CFAbsoluteTimeGetCurrent()
        var lastYield = t0
        loop: for i in 0..<times {
            let editsBefore = edits, selBefore = tv.selectedRange()
            for step in macro.steps {
                switch apply(step, on: tv, model: model) {
                case .applied: result.steps += 1
                case .skipped: result.skipped += 1
                case .failed(let why): reason = why; result.stoppedEarly = true; break loop
                }
            }
            result.iterations = i + 1
            if times > 1, edits == editsBefore, tv.selectedRange() == selBefore {
                reason = String(localized: "nothing changed"); result.stoppedEarly = true; break
            }
            if i + 1 < times, CFAbsoluteTimeGetCurrent() - lastYield > 0.05 {
                try? await Task.sleep(nanoseconds: 1_000_000)
                lastYield = CFAbsoluteTimeGetCurrent()
            }
        }
        observer?.cancel()
        um?.endUndoGrouping()
        um?.groupsByEvent = groupsByEvent
        result.ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        tv.scrollRangeToVisible(tv.selectedRange())

        let summary = String(localized: "Macro played ×\(result.iterations) · \(result.steps) steps · \(Int(result.ms.rounded())) ms")
        if result.stoppedEarly, let reason {
            model.log(summary + " · " + String(localized: "stopped early at run \(result.iterations) of \(times) · \(reason)"))
        } else {
            model.log(summary)
        }
        return result
    }

    private enum StepOutcome { case applied, skipped, failed(String) }

    private func apply(_ step: MacroStep, on tv: HyperTextView, model: AppModel) -> StepOutcome {
        switch step {
        case .insert(let s):
            tv.insertText(s, replacementRange: tv.selectedRange())
            return .applied
        case .command(let name):
            // 동작 셀렉터만 (인자 하나 → 끝이 ':'). 손으로 고친 JSON 의 임의 메서드 이름은 거른다
            let sel = Selector(name)
            guard name.hasSuffix(":"), tv.responds(to: sel) else {
                model.log(String(localized: "Macro · unknown command skipped · \(name)"))
                return .skipped
            }
            tv.doCommand(by: sel)
            return .applied
        case .tool(let raw):
            guard let tool = TextTool(rawValue: raw) else {
                model.log(String(localized: "Macro · unknown tool skipped · \(raw)"))
                return .skipped
            }
            model.send(.textTool(tool))
            return .applied
        case .find(let query):
            return findNext(query, on: tv, model: model) ? .applied : .failed(String(localized: "'\(query)' not found"))
        }
    }

    /// 캐럿(선택 끝) 뒤에서 검색어를 찾아 선택. 검색 패널의 옵션(정규식·대소문자·단어)을 따르고, 문서 끝까지 없으면 실패 (되감지 않음 — 반복 재생의 종료 조건)
    private func findNext(_ query: String, on tv: HyperTextView, model: AppModel) -> Bool {
        guard let re = try? SearchEngine.makeRegex(query, options: model.searchOptions) else { return false }
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        let from = min(ns.length, sel.length > 0 ? sel.location + 1 : sel.location)
        guard let m = re.firstMatch(in: ns as String, options: [], range: NSRange(location: from, length: ns.length - from)), m.range.length > 0 else { return false }
        tv.setSelectedRange(m.range)
        return true
    }
}

// MARK: - AppModel 진입점 (메뉴·리본·셀프테스트)

extension AppModel {
    func toggleMacroRecording() { macros.toggleRecording() }

    func playLastMacro() {
        Task { @MainActor in await macros.playLast(times: 1) }
    }

    func playMacro(id: UUID, times: Int = 1) {
        Task { @MainActor in await macros.play(id: id, times: times) }
    }

    /// "여러 번 재생…" 알림창 확인 — 횟수 상자(1 ~ 10,000)
    func playLastMacroRepeated() {
        // 자리표시자가 "1 ~ 10,000" 이라 "10,000" 처럼 치기 쉽다 — 천 단위 쉼표·공백은 걷어낸다 (못 읽으면 1회)
        let n = Int(macros.repeatText.filter { !$0.isWhitespace && $0 != "," }) ?? 1
        macros.showRepeatAlert = false
        Task { @MainActor in await macros.playLast(times: n) }
    }

    func saveLastMacro(name: String) {
        macros.showSaveAlert = false
        guard let last = macros.lastRecorded else { return }
        let saved = macros.store.save(last, name: name)
        log(String(localized: "Macro saved · \(saved.name) · \(saved.steps.count) steps"))
    }

    func deleteMacro(id: UUID) {
        guard let m = macros.store.macro(id: id) else { return }
        macros.store.delete(id: id)
        log(String(localized: "Macro deleted · \(m.name)"))
    }

    /// macros.json 을 편집기로 연다 (저장 뒤 다른 문서로 돌아가면 다시 읽는다)
    func editMacrosFile() {
        macros.store.ensureFileExists()
        open(url: macros.store.fileURL)
    }
}

// MARK: - HyperTextView 훅 구현 (클래스 본문의 한 줄 훅이 부른다)

extension HyperTextView {
    /// `insertText(_:replacementRange:)`: 실제 입력만 기록한다 — 선택 범위 교체, NSNotFound(선택/조합 문자열 교체), IME 확정(조합 범위 교체).
    /// 텍스트 도구의 명시적 범위 편집은 `.tool` 로 따로 기록되고 내부 insertText 는 macroSuppressDepth 로 꺼져 있다.
    func macroRecordInsert(_ string: Any, replacementRange: NSRange) {
        guard macroSuppressDepth == 0, let sink = macroSink else { return }
        guard replacementRange.location == NSNotFound || replacementRange == selectedRange()
                || (hasMarkedText() && replacementRange == markedRange()) else { return }
        let str = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        sink(.insert(str))
    }

    /// `doCommand(by:)`: 이동·삭제·줄바꿈·탭 등 모든 셀렉터. 호출 측이 깊이를 올려 내부 insertText(insertNewline → "\n") 는 중복 기록되지 않는다
    func macroRecordCommand(_ selector: Selector) {
        guard macroSuppressDepth == 0, let sink = macroSink else { return }
        sink(.command(NSStringFromSelector(selector)))
    }

    /// `paste(_:)`: 클립보드 문자열을 `.insert` 로 기록해 재생이 당시 내용으로 결정적이도록 (내부 insertText 는 호출 측이 끈다)
    func macroRecordPaste() {
        guard macroSuppressDepth == 0, let sink = macroSink, let s = NSPasteboard.general.string(forType: .string) else { return }
        sink(.insert(s))
    }

    /// `EditorView.applyTextTool` 앞: 도구 한 번 = 단계 하나. 도구가 끝날 때까지(defer) 내부 편집 기록을 끈다
    func macroWillApplyTool(_ raw: String) {
        if macroSuppressDepth == 0 { macroSink?(.tool(raw)) }
        macroSuppressDepth += 1
    }

    func macroDidApplyTool() { macroSuppressDepth -= 1 }
}
