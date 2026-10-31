import SwiftUI
import AppKit
import HyperCore

/// Quick Append 입력 창. 앱을 활성화하지 않는 플로팅 패널이라 다른 앱이 앞에 있어도 키 입력을 받고, 닫히면 포커스가 그 앱으로 돌아간다.
/// ⌘↩ 은 창의 performKeyEquivalent 에서, Esc 는 텍스트 뷰 delegate(cancelOperation:) 에서 처리한다.
final class QuickAppendPanel: NSPanel {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 230),
                   styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        title = String(localized: "Quick Append")
        level = .floating
        hidesOnDeactivate = false
        isFloatingPanel = true
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        minSize = NSSize(width: 360, height: 160)
        // 위치·크기 기억 (자동화 실행의 휘발성 설정에서는 기억하지 않는다 — 창 프레임 자동 저장은 표준 UserDefaults 에 쓰이므로)
        let remembered = AppDefaults.store === UserDefaults.standard && setFrameUsingName("QuickAppend")
        if !remembered, let screen = NSScreen.main ?? NSScreen.screens.first {
            let v = screen.visibleFrame
            let w: CGFloat = 520, h: CGFloat = 230
            setFrame(NSRect(x: v.midX - w / 2, y: v.maxY - h - 120, width: w, height: h), display: false)
        }
        if AppDefaults.store === UserDefaults.standard { setFrameAutosaveName("QuickAppend") }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, event.keyCode == 36 || event.keyCode == 76 {   // ⌘↩ (return / keypad enter)
            onSubmit?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

// MARK: - SwiftUI 내용

struct QuickAppendView: View {
    @ObservedObject var controller: QuickAppendController
    @ObservedObject var model: AppModel

    var body: some View {
        let theme = model.themes.current
        VStack(alignment: .leading, spacing: 8) {
            QuickAppendTextArea(text: $controller.draft, theme: theme, font: model.font,
                                onSubmit: { controller.submit() }, onCancel: { controller.hide() },
                                onCreate: { controller.textView = $0 })
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(theme.border.color))
            HStack(spacing: 10) {
                QuickAppendTarget(document: model.document, theme: theme)
                Spacer()
                Toggle("Timestamp heading", isOn: $controller.withTimestamp).toggleStyle(.checkbox)
            }
            .font(.system(size: 11))
            .foregroundStyle(theme.foregroundMuted.color)
            Text("⌘↩ append · Esc close").font(.system(size: 10.5)).foregroundStyle(theme.foregroundDim.color)
        }
        .padding(EdgeInsets(top: 30, leading: 12, bottom: 10, trailing: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.color)
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}

/// "→ notes.md" — 붙을 문서 이름 (문서 전환을 따라간다)
private struct QuickAppendTarget: View {
    @ObservedObject var document: MemoDocument
    let theme: Theme
    var body: some View {
        Text(verbatim: "→ " + document.url.lastPathComponent)
            .lineLimit(1).truncationMode(.middle)
            .help(document.url.path)
    }
}

/// 고정폭·테마 색의 여러 줄 입력. SwiftUI TextEditor 대신 NSTextView 를 직접 쓰는 이유: Esc(cancelOperation:)·⌘↩ 를 delegate 에서 가로채기 위해.
struct QuickAppendTextArea: NSViewRepresentable {
    @Binding var text: String
    let theme: Theme
    let font: FontSettings
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onCreate: (NSTextView) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        guard let tv = scroll.documentView as? NSTextView else { return scroll }
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.string = text
        context.coordinator.textView = tv
        context.coordinator.applyAppearance(theme: theme, font: font, to: tv)
        onCreate(tv)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        context.coordinator.applyAppearance(theme: theme, font: font, to: tv)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: QuickAppendTextArea
        weak var textView: NSTextView?
        private var appliedTheme: String?
        private var appliedFont: FontSettings?

        init(_ parent: QuickAppendTextArea) { self.parent = parent }

        func applyAppearance(theme: Theme, font: FontSettings, to tv: NSTextView) {
            guard appliedTheme != theme.id || appliedFont != font else { return }
            appliedTheme = theme.id
            appliedFont = font
            let base = FontCascade.baseFont(font)
            tv.font = base
            tv.typingAttributes = [.font: base, .foregroundColor: theme.foreground.nsColor]
            tv.textColor = theme.foreground.nsColor
            tv.backgroundColor = theme.background.nsColor
            tv.drawsBackground = true
            tv.insertionPointColor = theme.cursor.nsColor
            tv.selectedTextAttributes = [.backgroundColor: theme.selection.nsColor]
        }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            if parent.text != tv.string { parent.text = tv.string }
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) || commandSelector == #selector(NSResponder.complete(_:)) {
                parent.onCancel(); return true
            }
            if commandSelector == #selector(NSResponder.insertNewline(_:)), NSApp.currentEvent?.modifierFlags.contains(.command) == true {
                parent.onSubmit(); return true
            }
            return false
        }
    }
}

// MARK: - 설정 섹션

struct QuickAppendSettingsSection: View {
    @ObservedObject var controller: QuickAppendController

    var body: some View {
        Section("Quick Append") {
            Picker("Global shortcut", selection: $controller.hotkeyID) {
                ForEach(QuickAppendController.hotkeyOptions) { opt in
                    if opt.shortcut == nil { Text("Off").tag(opt.id) } else { Text(verbatim: opt.label).tag(opt.id) }
                }
            }
            Text(controller.hotkeyStatus)
                .font(.caption).foregroundStyle(controller.hotkeyFailed ? Color.red : Color.secondary)
            Text("⌃⌥Space and ⌃⇧Space are often taken by input-source switching (System Settings › Keyboard › Shortcuts). In the app, ⇧⌘N opens the panel; ⌘↩ appends to the end of the current document and saves at once.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
