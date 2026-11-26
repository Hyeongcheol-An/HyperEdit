import AppKit
import ObjectiveC

/// "자동화 실행"의 판정 — 한곳에서 정한다. 뜻이 둘이다:
///
/// - `isScripted`: **스크립트가 모는 실행** — 셀프테스트(`--selftest`·`--selftest-open`), 벤치(`--bench`)와 실행 시간 계측(`--quit-after-launch`·
///   `--bench-launch-log`), 실사용 하네스(`--realuse`), 스크린샷(`--snapshot`). 앞에 앉은 사람이 없다 → 시작 잠금을 걸지 않고(인증할 사람이 없다),
///   밖에서 온 열기 요청에 창을 앞으로 가져오지 않고, 종료할 때 묻지 않는다.
/// - `isIsolated`: **사용자의 것과 떨어져 도는 실행** — 스크립트가 모는 실행 전부 + 손으로 시험할 때 쓰는 `--ephemeral`. 설정(UserDefaults)·기본 문서 폴더·
///   스냅샷·북마크·스니펫·매크로·사용자 문법·저장된 창 상태·창 프레임 저장값을 읽지도 쓰지도 않는다. `--ephemeral` 만 준 실행은 사람이 쓰는 실행이라 그 밖에는
///   보통 실행과 같다 (창이 앞으로 오고, 시작 잠금 설정을 따른다).
///
/// 앞으로 나오지 않는(포커스를 가져가지 않는) 실행인지는 또 다른 물음이다 — 스크립트가 모는 실행은 모두 그렇지만 `--selftest-foreground`·
/// `--bench-foreground`·`--snapshot-activate` 로 바꿀 수 있어 `AppDelegate.automationStaysInBackground` 가 따로 정한다.
enum AutomationRun {
    static let isScripted: Bool = SelfTest.enabled || SelfTest.openEnabled || Bench.enabled || RealUse.enabled || LaunchOptions.has("--snapshot")
        || LaunchOptions.has("--quit-after-launch") || LaunchOptions.value("--bench-launch-log") != nil

    static let isIsolated: Bool = isScripted || LaunchOptions.has("--ephemeral")
}

// MARK: - 창 프레임 저장값

extension AutomationRun {
    /// 이 실행이 창 프레임을 설정에 적지도 읽지도 않게 해 두었는가 (`keepWindowFramesOutOfDefaults`)
    nonisolated(unsafe) private(set) static var keepsWindowFramesOut = false
    /// 이 실행에서 거절한 창 프레임 저장 수 (셀프테스트·하네스가 본다)
    nonisolated(unsafe) private(set) static var refusedWindowFrameSaves = 0
    /// 시작할 때 설정에 있던 창 프레임 저장값 (`NSWindow Frame <이름>` → 값) — 끝날 때 이 실행이 바꾼 것이 없는지 견준다
    nonisolated(unsafe) private(set) static var windowFramesAtLaunch: [String: String] = [:]

    /// 지금 설정(번들 ID 의 도메인 — 설치된 앱과 같이 쓴다)에 있는 창 프레임 저장값
    static func savedWindowFrames() -> [String: String] {
        let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) } ?? [:]
        return domain.reduce(into: [:]) { if $1.key.hasPrefix("NSWindow Frame "), let v = $1.value as? String { $0[$1.key] = v } }
    }

    /// 사용자의 것과 떨어져 도는 실행은 창의 위치·크기를 설정에 적지도, 거기서 읽지도 않는다. 창이 만들어지기 전에 한 번 부른다 (HyperEditApp.init).
    ///
    /// 창 프레임은 휘발성 저장소(AppDefaults)가 아니라 표준 UserDefaults 에 `NSWindow Frame <이름>` 으로 적힌다 — 테스트 빌드는 설치된 앱과 번들 ID 가 같아
    /// 사용자의 창 위치를 덮어쓴다. SwiftUI 는 WindowGroup 의 창에 자동 저장 이름을 걸지 않고, 창이 키 창이 될 때 자기 이름으로 직접 저장한다
    /// (`AppKitWindowController.windowDidBecomeKey` → `AppKitWindow.saveFrame(usingName:)` → NSWindow 의 구현. 실측 macOS 27: 뒤에서 도는 셀프테스트의
    /// 창도 시트가 떠 있는 동안 키 창이 되어, 설치된 앱의 저장값이 테스트 창의 1280 × 820 으로 바뀌었다). `.restorationBehavior(.disabled)` 와
    /// `ApplePersistenceIgnoreState` 는 '저장된 창 상태'만 막고 이 저장은 막지 못한다. 설정 창은 자동 저장 이름으로 저장한다.
    /// 끄는 공개된 방법이 없어, 이 실행에서만 NSWindow 의 저장·읽기·이름 걸기 구현을 갈아 끼운다 — SwiftUI 의 재정의는 super 를 부르므로 여기서 막힌다
    static func keepWindowFramesOutOfDefaults() {
        guard isIsolated, !keepsWindowFramesOut else { return }
        keepsWindowFramesOut = true
        windowFramesAtLaunch = savedWindowFrames()
        func replace(_ selector: Selector, with block: Any) {
            guard let method = class_getInstanceMethod(NSWindow.self, selector) else { return }
            method_setImplementation(method, imp_implementationWithBlock(block))
        }
        let save: @convention(block) (NSWindow, NSString) -> Void = { _, _ in refusedWindowFrameSaves += 1 }
        let read: @convention(block) (NSWindow, NSString) -> Bool = { _, _ in false }
        let readForced: @convention(block) (NSWindow, NSString, Bool) -> Bool = { _, _, _ in false }
        let setName: @convention(block) (NSWindow, NSString) -> Bool = { _, _ in false }
        replace(#selector(NSWindow.saveFrame(usingName:)), with: save)
        replace(#selector(NSWindow.setFrameUsingName(_:) as (NSWindow) -> (NSWindow.FrameAutosaveName) -> Bool), with: read)
        replace(#selector(NSWindow.setFrameUsingName(_:force:)), with: readForced)
        replace(#selector(NSWindow.setFrameAutosaveName(_:)), with: setName)
    }

    /// 시작한 뒤로 값이 바뀐 창 프레임 저장값 가운데 **이 실행의 창이 쓴 것** — 새 값이 이 프로세스의 어느 창의 프레임과 같은 것. 설치된 앱도 같은 도메인에
    /// 자기 창을 적으므로(사용자가 그 창을 옮기면) 값이 바뀐 것만으로는 이 실행의 탓이 아니다. 비어 있어야 한다
    @MainActor static func windowFramesWrittenByThisRun() -> [String] {
        let mine = Set(NSApp.windows.map { $0.frameDescriptor.trimmingCharacters(in: .whitespaces) })
        return savedWindowFrames().filter { windowFramesAtLaunch[$0.key] != $0.value && mine.contains($0.value.trimmingCharacters(in: .whitespaces)) }
            .map { "\($0.key.suffix(24)) = \($0.value)" }.sorted()
    }
}
