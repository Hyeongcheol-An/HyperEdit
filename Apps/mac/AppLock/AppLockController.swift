import AppKit
import Combine
import LocalAuthentication
import HyperCore

// applock: 앱 잠금 — 시작 시 요구 · 유휴 시간 · 잠자기/화면 잠금 연동 · 수동 잠금(⌃⌘L).
// 화면을 가리는 프라이버시 잠금이며 파일 암호화가 아니다. 잠긴 동안에도 자동 저장 같은 백그라운드 동작은 계속된다.
// 인증은 LocalAuthentication 의 .deviceOwnerAuthentication (Touch ID → 실패/미지원 시 시스템이 암호 폴백을 띄운다).
// 인증기는 Authenticator 프로토콜로 추상화해 셀프테스트가 성공/실패/취소를 주입한다 (SelfTest+AppLock.swift).
// 설정 키: applock.requireOnLaunch(기본 꺼짐) · applock.idleMinutes(0 = 안 함) · applock.lockOnSleep(기본 켜짐, 시작 잠금이 켜져 있을 때만 의미)

/// 인증 결과
enum AuthenticationResult: Equatable {
    case success
    /// 사용자가 취소 — 잠긴 채 유지, 메시지 없음 (버튼으로 재시도)
    case cancelled
    /// 인증 실패 — 잠긴 채 유지, 오버레이에 메시지
    case failed(String)
    /// 이 Mac 에 인증 수단이 없음(로그인 암호 미설정) — 보호할 수단이 없으므로 해제하고 출력 패널에 알린다
    case unavailable(String)
}

/// 인증기 — 실제는 LAContext, 셀프테스트는 가짜를 주입
@MainActor
protocol Authenticator: AnyObject {
    /// Touch ID 또는 로그인 암호로 인증할 수 있는가 (설정을 켤 때 확인 — 없으면 다음 실행에서 풀 수 없다)
    var isAvailable: Bool { get }
    /// 생체 인증 종류 (안내문·아이콘용)
    var biometry: LABiometryType { get }
    func authenticate(reason: String) async -> AuthenticationResult
}

/// LocalAuthentication 인증기. evaluatePolicy 는 호출마다 새 LAContext 로 — 이전 인증 결과를 재사용하지 않는다.
final class LocalAuthenticator: Authenticator {
    var isAvailable: Bool { LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) }

    var biometry: LABiometryType {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)   // biometryType 은 canEvaluatePolicy 뒤에야 채워진다
        return ctx.biometryType
    }

    func authenticate(reason: String) async -> AuthenticationResult {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            return .unavailable(err?.localizedDescription ?? "")
        }
        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) ? .success : .failed("")
        } catch let e as LAError {
            switch e.code {
            case .userCancel, .systemCancel, .appCancel: return .cancelled
            case .passcodeNotSet: return .unavailable(e.localizedDescription)
            default: return .failed(e.localizedDescription)
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

/// 잠금 상태 머신 (unlocked ↔ locked) + 유휴 타이머 + 시스템 알림 구독 + 잠긴 동안의 입력 차단.
/// 잠긴 동안: 창 콘텐츠는 LockOverlay 가 가리고, 키 입력은 로컬 모니터가 버리며(종료·가리기·창 명령의 키 등가물만 통과), 메뉴 막대는 열리는 즉시 닫히고
/// (NSMenu.didBeginTrackingNotification → cancelTracking; 메뉴 막대는 창 밖이라 오버레이가 가리지 못하고 SwiftUI 가 NSPrincipalClass 를 무시해 sendAction 을 가로챌 수 없다),
/// Quick Append 는 패널 대신 잠금 해제 프롬프트를 띄운다 (QuickAppendController.show).
@MainActor
final class AppLockController: ObservableObject {
    enum Trigger { case manual, launch, idle, sleep, screenLock }

    static let idleChoices = [0, 1, 5, 15, 30]
    /// LockOverlay 안 표식 NSView 의 identifier (셀프테스트가 NSView 트리에서 찾는다)
    static let overlayIdentifier = "applock.overlay"

    @Published private(set) var isLocked = false
    @Published private(set) var isAuthenticating = false
    /// 마지막 인증 오류 (오버레이에 표시, 잠금 해제·다시 잠금 때 지움)
    @Published private(set) var message: String?
    /// 설정 토글을 켜지 못했을 때의 안내 (이 Mac 에 인증 수단이 없음)
    @Published private(set) var settingsWarning: String?

    /// "Require Touch ID or password to open HyperEdit" — 시작 잠금. 잠자기/화면 잠금 연동의 전제이기도 하다
    @Published var requireOnLaunch: Bool {
        didSet {
            guard requireOnLaunch != oldValue else { return }
            if requireOnLaunch, !authenticator.isAvailable {
                requireOnLaunch = false   // 켜 두면 다음 실행에서 풀 수 없다. @Published 는 이 대입에도 didSet 을 다시 부르므로(경고를 지운다) 경고는 그 뒤에 쓴다
                settingsWarning = String(localized: "App Lock needs Touch ID or a login password on this Mac.")
                return
            }
            settingsWarning = nil
            AppDefaults.store.set(requireOnLaunch, forKey: "applock.requireOnLaunch")
        }
    }
    /// "Lock after inactivity" — 0 이면 안 함. 시작 잠금과 무관하게 고르면 바로 동작한다
    @Published var idleMinutes: Int {
        didSet {
            guard idleMinutes != oldValue else { return }
            AppDefaults.store.set(idleMinutes, forKey: "applock.idleMinutes")
            rearmIdle()
        }
    }
    /// "Lock when the Mac sleeps or the screen locks" — requireOnLaunch 가 켜져 있을 때만 의미
    @Published var lockOnSleep: Bool {
        didSet {
            guard lockOnSleep != oldValue else { return }
            AppDefaults.store.set(lockOnSleep, forKey: "applock.lockOnSleep")
        }
    }

    /// 셀프테스트가 바꿔 끼운다
    var authenticator: Authenticator
    /// 셀프테스트용: idleMinutes 대신 쓸 유휴 간격(초)
    var idleIntervalOverride: TimeInterval? { didSet { rearmIdle() } }

    private unowned let model: AppModel
    private var idleTimer: Timer?
    private var lastActivity = Date()
    private var activityMonitor: Any?
    private var lockedKeyMonitor: Any?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObserver: NSObjectProtocol?
    private var menuTrackingObserver: NSObjectProtocol?
    /// 셀프테스트·진단용: 잠긴 동안 닫은 메뉴 수
    private(set) var cancelledMenuCount = 0

    /// 자동화 실행은 시작 잠금을 하지 않는다 (테스트가 명시적으로 건다). `--locked` 는 스크린샷용 강제 시작 잠금
    static var isAutomationRun: Bool {
        SelfTest.enabled || SelfTest.openEnabled || Bench.enabled || LaunchOptions.has("--snapshot") || LaunchOptions.has("--quit-after-launch")
    }

    init(model: AppModel, authenticator: Authenticator? = nil) {
        self.model = model
        self.authenticator = authenticator ?? LocalAuthenticator()   // 기본 인자는 비격리 문맥이라 여기서 만든다
        let d = AppDefaults.store
        requireOnLaunch = d.object(forKey: "applock.requireOnLaunch") as? Bool ?? false
        let minutes = d.object(forKey: "applock.idleMinutes") as? Int ?? 0
        idleMinutes = Self.idleChoices.contains(minutes) ? minutes : 0
        lockOnSleep = d.object(forKey: "applock.lockOnSleep") as? Bool ?? true
        subscribeSystemEvents()
        subscribeMenuTracking()
        rearmIdle()
        if LaunchOptions.has("--locked") || (requireOnLaunch && !Self.isAutomationRun && self.authenticator.isAvailable) {
            lock(.launch)
        }
    }

    /// 셀프테스트가 만든 임시 인스턴스 정리 (모니터·타이머·알림 구독 해제)
    func shutdown() {
        idleTimer?.invalidate(); idleTimer = nil
        removeActivityMonitor()
        if let m = lockedKeyMonitor { NSEvent.removeMonitor(m); lockedKeyMonitor = nil }
        let ws = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { ws.removeObserver($0) }
        workspaceObservers.removeAll()
        if let o = distributedObserver { DistributedNotificationCenter.default().removeObserver(o); distributedObserver = nil }
        if let o = menuTrackingObserver { NotificationCenter.default.removeObserver(o); menuTrackingObserver = nil }
    }

    // MARK: 안내문

    /// 설정 캡션: 이 Mac 의 인증 수단
    var availabilityDescription: String {
        guard authenticator.isAvailable else { return String(localized: "No Touch ID or login password is set up on this Mac — App Lock cannot be turned on.") }
        switch authenticator.biometry {
        case .touchID: return String(localized: "Touch ID is available — the login password is the fallback.")
        default: return String(localized: "This Mac has no Touch ID — the login password is used.")
        }
    }
    var usesTouchID: Bool { authenticator.biometry == .touchID }

    // MARK: 잠금 / 해제

    func lock(_ trigger: Trigger = .manual) {
        guard !isLocked else { return }
        isLocked = true
        message = nil
        idleTimer?.invalidate(); idleTimer = nil
        installLockedKeyMonitor()
        closeAuxiliaryWindows()
        model.log(logLine(for: trigger))
    }

    /// 오버레이의 "Unlock" 버튼 · Return · Quick Append 호출: 인증기를 돌려 성공하면 해제한다. 인증 중 중복 호출은 무시
    func requestUnlock() async {
        guard isLocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let result = await authenticator.authenticate(reason: String(localized: "unlock your documents"))
        guard isLocked else { return }   // 인증 중 다른 경로로 이미 풀렸으면
        switch result {
        case .success:
            unlock()
        case .cancelled:
            break
        case .failed(let detail):
            message = detail.isEmpty ? String(localized: "Authentication failed — try again.") : detail
        case .unavailable(let detail):
            model.log(String(localized: "App Lock: this Mac has no Touch ID or login password, so HyperEdit was unlocked without authentication. \(detail)"), isError: true)
            unlock()
        }
    }

    /// 잠겨 있으면 인증 뒤에, 아니면 바로 실행 (Quick Append 가 쓴다)
    func whenUnlocked(_ action: @escaping @MainActor () -> Void) {
        guard isLocked else { action(); return }
        Task { @MainActor in
            await requestUnlock()
            if !isLocked { action() }
        }
    }

    private func unlock() {
        isLocked = false
        message = nil
        if let m = lockedKeyMonitor { NSEvent.removeMonitor(m); lockedKeyMonitor = nil }
        rearmIdle()
        model.log(String(localized: "HyperEdit unlocked"))
        model.focusEditor()
    }

    private func logLine(for trigger: Trigger) -> String {
        switch trigger {
        case .manual: return String(localized: "HyperEdit locked")
        case .launch: return String(localized: "HyperEdit locked — Touch ID or password required to open")
        case .idle: return String(localized: "HyperEdit locked after \(idleMinutes) min of inactivity")
        case .sleep: return String(localized: "HyperEdit locked — the Mac is going to sleep")
        case .screenLock: return String(localized: "HyperEdit locked — the screen was locked")
        }
    }

    /// 열린 설정 창(SwiftUI Settings 장면 · `--show-settings` 창)과 Quick Append 패널을 닫는다.
    /// 편집기(HyperTextView)를 담은 문서 창과 그 시트는 그대로 둔다 — 오버레이가 가린다.
    private func closeAuxiliaryWindows() {
        for w in NSApp.windows where w.isVisible && !(w is NSPanel) && w.sheetParent == nil && !Self.containsEditor(w.contentView) {
            w.close()
        }
        if model.quickAppend.isVisible { model.quickAppend.hide() }
    }

    private static func containsEditor(_ view: NSView?) -> Bool {
        guard let view else { return false }
        if view is HyperTextView { return true }
        return view.subviews.contains { containsEditor($0) }
    }

    // MARK: 잠긴 동안의 키 입력

    private func installLockedKeyMonitor() {
        guard lockedKeyMonitor == nil else { return }
        lockedKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            MainActor.assumeIsolated { self?.handleLockedKeyDown(e) }
        }
    }

    /// 잠긴 동안 통과시키는 키 등가물 (키 코드는 자판 배열과 무관 — 한글 입력 소스에서도 ⌘Q 가 동작한다): 종료 ⌘Q · 가리기 ⌘H / ⌥⌘H · 최소화 ⌘M · 닫기 ⌘W · 전체 화면 ⌃⌘F
    static let allowedKeyEquivalents: [(keyCode: UInt16, char: String, flags: NSEvent.ModifierFlags)] = [
        (12, "q", .command), (4, "h", .command), (4, "h", [.command, .option]), (46, "m", .command), (13, "w", .command), (3, "f", [.command, .control]),
    ]

    /// 허용 목록의 ⌘ 키 등가물만 그대로 통과시켜 메뉴로 보내고(⌘V·⌘, 같은 나머지 ⌘ 조합과 편집기의 ⌘⌫ 키 바인딩은 버린다),
    /// Return / Enter / Space 는 잠금 해제 요청, 나머지(타이핑·⌃K 같은 Cocoa 편집 바인딩)는 버린다. 반환 nil = 이벤트 소비
    func handleLockedKeyDown(_ e: NSEvent) -> NSEvent? {
        guard isLocked else { return e }
        let flags = e.modifierFlags.intersection([.command, .shift, .option, .control])
        if flags.contains(.command) {
            let chars = (e.charactersIgnoringModifiers ?? "").lowercased()
            let typed = (e.characters ?? "").lowercased()
            let allowed = Self.allowedKeyEquivalents.contains { $0.flags == flags && ($0.keyCode == e.keyCode || $0.char == chars || $0.char == typed) }
            return allowed ? e : nil
        }
        if !e.isARepeat, flags.isEmpty, [36, 76, 49].contains(e.keyCode) {   // return · keypad enter · space
            Task { @MainActor in await self.requestUnlock() }
        }
        return nil
    }

    // MARK: 잠긴 동안의 메뉴

    /// 메뉴 막대(와 모든 메뉴)는 창 밖이라 오버레이가 가리지 못한다 — 잠긴 동안 열리면 바로 닫는다. 종료는 ⌘Q·Dock 메뉴로
    private func subscribeMenuTracking() {
        menuTrackingObserver = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { [weak self] n in
            MainActor.assumeIsolated {
                guard let self, self.isLocked, let menu = n.object as? NSMenu else { return }
                self.cancelledMenuCount += 1
                menu.cancelTrackingWithoutAnimation()
            }
        }
    }

    // MARK: 유휴 타이머

    private var idleInterval: TimeInterval? {
        if let o = idleIntervalOverride { return o }
        return idleMinutes > 0 ? TimeInterval(idleMinutes * 60) : nil
    }

    /// 마지막 입력 시각만 기록하는 모니터(입력당 Date() 하나) + 한 번 울리는 타이머: 울렸을 때 아직 간격이 안 찼으면 남은 시간만큼 다시 건다
    private func rearmIdle() {
        idleTimer?.invalidate(); idleTimer = nil
        guard let interval = idleInterval else { removeActivityMonitor(); return }
        installActivityMonitor()
        guard !isLocked else { return }
        lastActivity = Date()
        scheduleIdleTimer(after: interval)
    }

    private func scheduleIdleTimer(after seconds: TimeInterval) {
        idleTimer?.invalidate()
        let t = Timer(timeInterval: max(0.05, seconds), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.idleTimerFired() }
        }
        t.tolerance = min(1, seconds * 0.1)
        RunLoop.main.add(t, forMode: .common)
        idleTimer = t
    }

    private func idleTimerFired() {
        guard !isLocked, let interval = idleInterval else { return }
        let elapsed = Date().timeIntervalSince(lastActivity)
        if elapsed >= interval - 0.02 { lock(.idle) } else { scheduleIdleTimer(after: interval - elapsed) }
    }

    /// 사용자 입력이 있었다고 알린다 (모니터가 호출; 테스트도 호출)
    func noteActivity() { lastActivity = Date() }

    private func installActivityMonitor() {
        guard activityMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        activityMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] e in
            MainActor.assumeIsolated { self?.lastActivity = Date() }
            return e
        }
    }

    private func removeActivityMonitor() {
        if let m = activityMonitor { NSEvent.removeMonitor(m); activityMonitor = nil }
    }

    // MARK: 잠자기 · 화면 잠금

    private func subscribeSystemEvents() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            workspaceObservers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.systemEvent(.sleep) }
            })
        }
        // 화면 잠금(⌃⌘Q·화면 보호기 암호)은 공개 NSWorkspace 알림이 없다 — loginwindow 가 보내는 분산 알림을 듣는다
        distributedObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemEvent(.screenLock) }
        }
    }

    /// 잠자기·화면 잠금: 시작 잠금("Require…")과 "Lock when the Mac sleeps…" 가 모두 켜져 있을 때만 잠근다
    func systemEvent(_ trigger: Trigger) {
        guard requireOnLaunch, lockOnSleep else { return }
        lock(trigger)
    }
}
