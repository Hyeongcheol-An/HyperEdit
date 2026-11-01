import SwiftUI
import AppKit
import Combine
import HyperCore

// 비밀 블록(```secret 펜스) — 앱 수준 상태: 설정(가리기·자동 재마스킹·클립보드 소거), "Reveal Secrets" ⌥⌘S 토글과 자동 재마스킹 타이머,
// 클립보드 자동 소거 예약. 편집기별 가림·캐럿 드러내기는 Editor/SecretController.swift, 설정 섹션은 SecretsSettings.swift.
// 표시만 가리는 것이며 파일은 평문으로 저장된다 (암호화 아님).

@MainActor
final class SecretsStore: ObservableObject {
    static let maskKey = "secrets.mask"
    static let remaskKey = "secrets.remaskSeconds"
    static let clipboardKey = "secrets.clipboardClearSeconds"
    /// 자동 재마스킹 지연 (초, 0 = 수동) · 클립보드 소거 지연 (초, 0 = 끔)
    static let remaskOptions = [10, 30, 60, 0]
    static let clipboardOptions = [0, 10, 30, 60]

    weak var model: AppModel?

    /// "Mask secret blocks" (기본 켜짐). 끄면 비밀 줄이 그대로 보이고 찾기 결과·미리보기·클립보드 소거도 하지 않는다
    @Published var maskEnabled: Bool {
        didSet {
            guard maskEnabled != oldValue else { return }
            AppDefaults.store.set(maskEnabled, forKey: Self.maskKey)
            if !maskEnabled { remaskAll(automatic: false, quiet: true) }
            model?.log(maskEnabled ? String(localized: "Secret blocks masked") : String(localized: "Secret block masking off — secret lines are shown"))
            model?.rescanStructure()   // 아웃라인·타임라인의 비밀 줄 제외/포함
            NotificationCenter.default.post(name: .secretsSettingsDidChange, object: nil)   // 마크다운 미리보기 다시 렌더
        }
    }
    /// "Re-mask after" — 전부 드러낸 뒤 자동으로 다시 가리기까지 (초, 0 = Never)
    @Published var remaskSeconds: Int {
        didSet {
            guard remaskSeconds != oldValue else { return }
            AppDefaults.store.set(remaskSeconds, forKey: Self.remaskKey)
            if revealedAll { scheduleRemask() }
        }
    }
    /// "Clear clipboard after copying a secret" (초, 0 = Off)
    @Published var clipboardClearSeconds: Int {
        didSet { if clipboardClearSeconds != oldValue { AppDefaults.store.set(clipboardClearSeconds, forKey: Self.clipboardKey) } }
    }
    /// ⌥⌘S: 모든 비밀 블록을 드러낸 상태
    @Published private(set) var revealedAll = false
    /// 현재 문서의 비밀 블록 수 (편집기 컨트롤러가 스캔 뒤 알린다 — 상태바)
    @Published var blockCount = 0
    /// 클립보드 소거가 예약돼 있는가 (상태바 툴팁·셀프테스트)
    @Published private(set) var clipboardClearPending = false

    /// 셀프테스트용 지연 주입 (초). nil 이면 설정값
    var remaskDelayOverride: TimeInterval?
    var clipboardClearDelayOverride: TimeInterval?

    private var remaskTask: Task<Void, Never>?
    private var clipboardTask: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
        let d = AppDefaults.store
        maskEnabled = d.object(forKey: Self.maskKey) as? Bool ?? true
        let r = d.object(forKey: Self.remaskKey) as? Int ?? 30
        remaskSeconds = Self.remaskOptions.contains(r) ? r : 30
        let c = d.object(forKey: Self.clipboardKey) as? Int ?? 30
        clipboardClearSeconds = Self.clipboardOptions.contains(c) ? c : 30
        if LaunchOptions.has("--reveal-secrets") { revealedAll = true }   // 스크린샷용: 시작부터 드러낸 상태 (타이머 없음)
    }

    // MARK: 드러내기 / 다시 가리기

    func toggleRevealAll() {
        guard maskEnabled else { model?.log(String(localized: "Secret block masking is off (Settings › Secrets)")); return }
        if revealedAll { remaskAll(automatic: false) } else { revealAll() }
    }

    func revealAll() {
        guard maskEnabled else { return }
        revealedAll = true
        scheduleRemask()
        let delay = effectiveRemaskDelay
        model?.log(delay > 0 ? String(localized: "Secrets revealed · masked again in \(Int(delay.rounded())) s (⌥⌘S)")
                             : String(localized: "Secrets revealed · ⌥⌘S masks them again"))
    }

    func remaskAll(automatic: Bool, quiet: Bool = false) {
        remaskTask?.cancel(); remaskTask = nil
        guard revealedAll else { return }
        revealedAll = false
        if !quiet { model?.log(automatic ? String(localized: "Secrets masked again automatically") : String(localized: "Secrets masked")) }
    }

    private var effectiveRemaskDelay: TimeInterval { remaskDelayOverride ?? TimeInterval(remaskSeconds) }

    private func scheduleRemask() {
        remaskTask?.cancel()
        let delay = effectiveRemaskDelay
        guard delay > 0 else { remaskTask = nil; return }
        remaskTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.remaskAll(automatic: true)
        }
    }

    // MARK: 클립보드

    /// 비밀 줄이 섞인 복사 뒤: 설정 지연 뒤 클립보드의 changeCount 가 그대로일 때만 비운다 (그 사이 다른 복사가 있었으면 건드리지 않는다)
    func scheduleClipboardClear() {
        let delay = clipboardClearDelayOverride ?? TimeInterval(clipboardClearSeconds)
        guard maskEnabled, delay > 0 else { return }
        let pb = NSPasteboard.general
        let count = pb.changeCount
        clipboardTask?.cancel()
        clipboardClearPending = true
        clipboardTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.clipboardClearPending = false
            guard pb.changeCount == count else { return }
            pb.clearContents()
            self.model?.log(String(localized: "Clipboard cleared (secret)"))
        }
    }

    func clearClipboardNow() {
        clipboardTask?.cancel(); clipboardTask = nil
        clipboardClearPending = false
        NSPasteboard.general.clearContents()
        model?.log(String(localized: "Clipboard cleared"))
    }
}

extension Notification.Name {
    /// 비밀 블록 설정(가리기 켜고 끔)이 바뀜 — 마크다운 미리보기가 다시 렌더한다
    static let secretsSettingsDidChange = Notification.Name("HyperEdit.secretsSettingsDidChange")
}

// MARK: - 메뉴 (편집 메뉴 끝)

struct SecretsCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            SecretsMenuItems(store: model.secrets)
        }
    }
}

private struct SecretsMenuItems: View {
    @ObservedObject var store: SecretsStore

    var body: some View {
        Divider()
        Button(store.revealedAll ? "Mask Secrets" : "Reveal Secrets") { store.toggleRevealAll() }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(!store.maskEnabled)
        Toggle("Mask Secret Blocks", isOn: $store.maskEnabled)
        Button("Clear Clipboard") { store.clearClipboardNow() }
    }
}

// MARK: - 상태바 셀

/// `•••• N`(가려진 블록 수, 흐리게) / `REVEALED`(전부 드러냄, 경고색) — COL · MD 처럼 번역하지 않는 상태 토큰
struct SecretsStatusCell: View {
    @ObservedObject var store: SecretsStore
    let theme: Theme

    var body: some View {
        if store.maskEnabled, store.blockCount > 0 || store.revealedAll {
            let token = store.revealedAll ? "REVEALED" : "•••• \(store.blockCount)"
            Text(verbatim: token)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity)
                .foregroundStyle(store.revealedAll ? theme.warningColor.color : theme.foregroundDim.color)
                .overlay(alignment: .trailing) { theme.border.color.frame(width: 1).padding(.vertical, 4) }
                .help(helpText)
        }
    }

    private var helpText: String {
        if store.revealedAll {
            return store.remaskSeconds > 0
                ? String(localized: "Secrets revealed — masked again automatically after \(store.remaskSeconds) s (⌥⌘S masks now)")
                : String(localized: "Secrets revealed — ⌥⌘S masks them again")
        }
        return String(localized: "\(store.blockCount) secret blocks masked — the caret reveals a block, ⌥⌘S reveals all")
    }
}
