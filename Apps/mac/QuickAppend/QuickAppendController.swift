import SwiftUI
import AppKit
import Combine
import HyperCore

/// Quick Append — 어디서든 전역 단축키(기본 ⌃⌥N)·메뉴(⇧⌘N)·홈 탭 삽입 그룹으로 떠 있는 입력 창을 열어 문서 끝에 메모를 덧붙인다.
/// - 창(QuickAppendPanel)은 앱을 활성화하지 않으므로 다른 앱이 앞에 있어도 바로 입력할 수 있고, ⌘↩ 뒤 포커스는 그 앱으로 돌아간다.
/// - Esc 로 닫으면 쓰던 글은 메모리에 남아 다음에 이어 쓸 수 있다 (디스크에는 저장하지 않음).
/// - 설정: `ui.quickAppend.timestamp`(헤딩 기본 켜짐) · `ui.quickAppend.hotkey`(단축키 id, 기본 ctrl-opt-n)
@MainActor
final class QuickAppendController: ObservableObject {
    struct HotKeyOption: Identifiable {
        let id: String
        let label: String
        let shortcut: GlobalHotKey.Shortcut?
    }
    /// 키 코드: N = 45, Space = 49
    static let hotkeyOptions: [HotKeyOption] = [
        .init(id: "off", label: "Off", shortcut: nil),
        .init(id: "ctrl-opt-n", label: "⌃⌥N", shortcut: .init(keyCode: 45, modifiers: [.control, .option])),
        .init(id: "ctrl-opt-space", label: "⌃⌥Space", shortcut: .init(keyCode: 49, modifiers: [.control, .option])),
        .init(id: "ctrl-shift-space", label: "⌃⇧Space", shortcut: .init(keyCode: 49, modifiers: [.control, .shift])),
        .init(id: "ctrl-opt-cmd-n", label: "⌃⌥⌘N", shortcut: .init(keyCode: 45, modifiers: [.control, .option, .command])),
    ]
    static let defaultHotkeyID = "ctrl-opt-n"

    unowned let model: AppModel
    /// 입력 중인 글 — 창을 닫아도 유지 (메모리)
    @Published var draft = ""
    @Published var withTimestamp: Bool {
        didSet { AppDefaults.store.set(withTimestamp, forKey: "ui.quickAppend.timestamp") }
    }
    @Published var hotkeyID: String {
        didSet {
            guard hotkeyID != oldValue else { return }
            AppDefaults.store.set(hotkeyID, forKey: "ui.quickAppend.hotkey")
            registerHotKey()
        }
    }
    /// 설정 화면에 보여 줄 등록 상태
    @Published private(set) var hotkeyStatus = ""
    @Published private(set) var hotkeyFailed = false
    /// 입력 텍스트 뷰 (포커스용, QuickAppendTextArea 가 등록)
    weak var textView: NSTextView?

    private var panel: QuickAppendPanel?
    private var hotkey: GlobalHotKey?

    init(model: AppModel) {
        self.model = model
        let d = AppDefaults.store
        withTimestamp = d.object(forKey: "ui.quickAppend.timestamp") as? Bool ?? true
        hotkeyID = d.string(forKey: "ui.quickAppend.hotkey") ?? Self.defaultHotkeyID
        registerHotKey()
    }

    // MARK: 창

    var isVisible: Bool { panel?.isVisible ?? false }
    /// 셀프테스트용: 패널이 키 창인가(앱이 활성일 때만 의미 있음) / 입력 뷰가 첫 응답자인가
    var isKeyWindow: Bool { panel?.isKeyWindow ?? false }
    var isTextViewFocused: Bool { textView != nil && panel?.firstResponder === textView }
    /// 셀프테스트용: 전역 단축키가 실제로 등록돼 있는가 (Carbon 이 noErr 를 돌려줌)
    var isHotKeyRegistered: Bool { hotkey != nil }

    func show() {
        let p = panel ?? makePanel()
        p.contentView?.layoutSubtreeIfNeeded()   // 처음 열 때 SwiftUI 가 텍스트 뷰를 만들도록 (makeNSView → textView 등록)
        // nonactivating 패널: 앱이 비활성이어도 윈도 서버가 키 입력을 이 창에 보낸다 (이때 isKeyWindow/NSApp.keyWindow 는 문서대로 false/nil — 활성화하지 않는다)
        p.makeKeyAndOrderFront(nil)
        focusTextView(in: p)
        if textView == nil { DispatchQueue.main.async { [weak self] in if let self, let p = self.panel { self.focusTextView(in: p) } } }
    }

    private func focusTextView(in p: NSPanel) {
        guard let tv = textView, p.firstResponder !== tv else { return }
        p.makeFirstResponder(tv)
    }

    func hide() { panel?.orderOut(nil) }

    /// 전역 단축키: 떠 있고 키 창이면 닫고, 아니면 연다
    func toggle() {
        // nonactivating 패널은 앱이 비활성일 때 isKeyWindow 가 false 이므로, 보이는 패널은 비활성 상태에서도 닫는다
        if let p = panel, p.isVisible, p.isKeyWindow || !NSApp.isActive { hide() } else { show() }
    }

    /// ⌘↩: 덧붙이고 닫는다. 빈 글이면 아무것도 하지 않는다.
    func submit() {
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { NSSound.beep(); return }
        guard model.quickAppend(draft, withTimestamp: withTimestamp) else { NSSound.beep(); return }
        draft = ""
        hide()
    }

    private func makePanel() -> QuickAppendPanel {
        let p = QuickAppendPanel()
        p.onSubmit = { [weak self] in self?.submit() }
        p.onCancel = { [weak self] in self?.hide() }
        let host = NSHostingView(rootView: QuickAppendView(controller: self, model: model))
        host.sizingOptions = []   // 내용에 맞춰 창 크기를 바꾸지 않는다 (사용자가 정한 크기 유지)
        p.contentView = host
        panel = p
        return p
    }

    // MARK: 전역 단축키

    private func registerHotKey() {
        hotkey?.unregister()
        hotkey = nil
        guard let opt = Self.hotkeyOptions.first(where: { $0.id == hotkeyID }), let sc = opt.shortcut else {
            hotkeyStatus = String(localized: "Global shortcut off")
            hotkeyFailed = false
            return
        }
        do {
            hotkey = try GlobalHotKey(sc) { [weak self] in self?.toggle() }
            hotkeyStatus = String(localized: "Global shortcut registered: \(opt.label)")
            hotkeyFailed = false
        } catch let e as GlobalHotKey.RegistrationError {
            hotkeyStatus = String(localized: "Global shortcut \(opt.label) could not be registered (in use by another app, error \(Int(e.status)))")
            hotkeyFailed = true
            model.log(hotkeyStatus, isError: true)
        } catch {
            hotkeyStatus = error.localizedDescription
            hotkeyFailed = true
            model.log(hotkeyStatus, isError: true)
        }
    }
}

// MARK: - AppModel

extension AppModel {
    /// 문서 끝에 메모를 덧붙이고 바로 저장한다 (Mac 이 잠들어도 잃지 않도록). 편집기가 있으면 그 undo 스택을 지나므로 ⌘Z 한 번으로 되돌릴 수 있다.
    /// 캐럿이 끝에 있었을 때만 끝으로 따라가고, 다른 곳을 보고 있었으면 보던 자리를 건드리지 않는다. 반환: 실제로 덧붙였는지.
    @discardableResult
    func quickAppend(_ text: String, withTimestamp: Bool) -> Bool {
        guard document.isLoaded else {
            log(String(localized: "Quick Append failed — no document is open"), isError: true)
            return false
        }
        let ns = document.textStorage.string as NSString
        var insertion = QuickAppendComposer.insertion(trailingNewlines: QuickAppendComposer.trailingNewlineCount(of: ns),
                                                      isEmptyDocument: ns.length == 0, note: text,
                                                      heading: withTimestamp ? Timestamp.heading() : nil)
        guard !insertion.isEmpty else { return false }
        if document.lineEnding == "DOS" { insertion = insertion.replacingOccurrences(of: "\n", with: "\r\n") }   // CRLF 문서는 줄바꿈을 맞춘다
        let end = ns.length
        let range = NSRange(location: end, length: 0)
        if let tv = (session.active ?? session.primary)?.textView, tv.isEditable {
            // shouldChangeText → replaceCharacters → didChangeText: undo 한 항목, 캐럿은 건드리지 않는다 (insertText 는 캐럿을 끝으로 옮긴다)
            let wasAtEnd = tv.selectedRange().location >= end
            tv.breakUndoCoalescing()
            guard tv.shouldChangeText(in: range, replacementString: insertion) else { return false }
            tv.textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: insertion, attributes: tv.typingAttributes))
            tv.didChangeText()
            if wasAtEnd {
                let newEnd = (tv.string as NSString).length
                tv.setSelectedRange(NSRange(location: newEnd, length: 0))
                tv.scrollRangeToVisible(NSRange(location: newEnd, length: 0))
            }
        } else {
            let ts = document.textStorage
            ts.beginEditing()
            ts.replaceCharacters(in: range, with: insertion)
            ts.endEditing()
            document.textDidChange()
        }
        document.save()
        let chars = (QuickAppendComposer.trimmed(text) as NSString).length
        log(String(localized: "Quick Append · \(chars) chars"))
        return true
    }

    /// `--quick-append`: 창이 뜬 뒤 입력 창을 연다 (스크린샷용). 전역 단축키는 컨트롤러가 만들어지며 등록되므로 여기서 한 번 만든다.
    func applyQuickAppendLaunchOptions() {
        _ = quickAppend
        guard LaunchOptions.has("--quick-append") else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in self?.quickAppend.show() }
    }
}
