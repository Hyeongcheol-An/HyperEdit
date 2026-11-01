import SwiftUI
import AppKit
import HyperCore

// appearance: 커서 스타일(Bar/Block/Underline, 깜빡임)과 배경 투명도(창·편집기·패널, 블러).
// 값은 AppModel(@Published, UserDefaults `ui.cursorStyle` `ui.cursorBlink` `ui.backgroundOpacity` `ui.backgroundBlur`)에 있고,
// 적용은 EditorView(캐럿·편집기 배경) · ContentView/패널(SwiftUI 표면) · WindowChromeView(창 isOpaque·블러)가 한다. 설정 UI 는 AppearanceSettings.swift.

/// 캐럿 모양. 원시값은 UserDefaults 와 `--cursor` 인자에 쓰인다
enum CursorStyle: String, CaseIterable, Identifiable {
    case bar, block, underline
    var id: String { rawValue }
    var label: LocalizedStringKey {
        switch self { case .bar: "Bar"; case .block: "Block"; case .underline: "Underline" }
    }
    static let defaultsKey = "ui.cursorStyle"
    static var stored: CursorStyle { CursorStyle(rawValue: AppDefaults.store.string(forKey: defaultsKey) ?? "") ?? .bar }
}

/// 배경 투명도 (0.5 ~ 1.0, 기본 1.0 = 불투명)
enum BackgroundOpacity {
    static let range: ClosedRange<Double> = 0.5...1.0
    static let defaultsKey = "ui.backgroundOpacity"
    /// 보기 메뉴 '창 투명도' 단계
    static let presets: [Double] = [1.0, 0.9, 0.8, 0.7]

    static func clamped(_ v: Double) -> Double { v.isFinite ? min(range.upperBound, max(range.lowerBound, v)) : 1 }
    static var stored: Double {
        guard let v = AppDefaults.store.object(forKey: defaultsKey) as? Double else { return 1 }
        return clamped(v)
    }
    /// 1 미만이면 창·표면이 반투명
    static func isTranslucent(_ v: Double) -> Bool { v < 0.999 }
}

extension AppModel {
    /// `--cursor <bar|block|underline>` `--no-cursor-blink` `--opacity <0.5~1.0>` `--blur` (스크린샷·수동 테스트용)
    func applyAppearanceLaunchOptions() {
        if let s = LaunchOptions.value("--cursor"), let style = CursorStyle(rawValue: s.lowercased()) { cursorStyle = style }
        if LaunchOptions.has("--no-cursor-blink") { cursorBlink = false }
        if let o = LaunchOptions.value("--opacity"), let v = Double(o) { backgroundOpacity = BackgroundOpacity.clamped(v) }
        if LaunchOptions.has("--blur") { backgroundBlur = true }
    }

    var isTranslucentWindow: Bool { BackgroundOpacity.isTranslucent(backgroundOpacity) }

    /// SwiftUI 표면(리본·문서 탭 줄·상태바·사이드바·하단 패널)의 배경색 — 투명도 < 1 이면 같은 α 를 입힌다
    func surfaceColor(_ c: RGBA) -> Color {
        isTranslucentWindow ? c.color.opacity(backgroundOpacity) : c.color
    }

    /// 다른 표면 위에 겹치는 바탕(창 전체 배경, 사이드바 탭 줄 등): 투명도 < 1 이면 비운다 — 두 겹이면 (1-α)² 만 비쳐 더 불투명해 보인다
    func surfaceColorIfOpaque(_ c: RGBA) -> Color {
        isTranslucentWindow ? Color.clear : c.color
    }
}

/// 보기 메뉴 '창 투명도' 하위 메뉴(100/90/80/70%) + 블러 토글. HyperEditApp 의 View 메뉴 끝에 한 줄로 들어간다
struct AppearanceMenuItems: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Divider()
        Menu("Window Opacity") {
            ForEach(BackgroundOpacity.presets, id: \.self) { v in
                let title = "\(Int((v * 100).rounded()))%"
                Button { model.backgroundOpacity = v } label: {
                    if abs(model.backgroundOpacity - v) < 0.001 {
                        Label { Text(verbatim: title) } icon: { Image(systemName: "checkmark") }
                    } else {
                        Text(verbatim: title)
                    }
                }
            }
            Divider()
            Toggle("Blur Behind Window", isOn: $model.backgroundBlur).disabled(!model.isTranslucentWindow)
        }
    }
}

/// 창 투명도·블러 적용기 — ContentView 의 맨 뒤 배경으로 들어가 창을 찾는다.
/// 투명도 < 1: 창 `isOpaque = false`·배경 clear (각 SwiftUI 표면과 편집기 컨테이너가 테마 배경을 α 로 칠한다).
/// 블러: 자기 자리(모든 내용의 뒤)에 NSVisualEffectView(.behindWindow) 를 둔다. 창 속성만 바꾸므로 전체 화면·분할·테마 전환과 무관하다.
struct WindowChromeView: NSViewRepresentable {
    let opacity: Double
    let blur: Bool

    func makeNSView(context: Context) -> WindowChromeNSView { WindowChromeNSView() }
    func updateNSView(_ view: WindowChromeNSView, context: Context) { view.configure(opacity: opacity, blur: blur) }
}

final class WindowChromeNSView: NSView {
    private var opacity = 1.0
    private var blur = false
    private(set) var effectView: NSVisualEffectView?
    /// 처음 만난 창의 배경색 (불투명으로 돌아갈 때 복원)
    private var originalBackground: NSColor?

    func configure(opacity: Double, blur: Bool) {
        self.opacity = opacity
        self.blur = blur
        apply()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
    }

    private func apply() {
        guard let window else { return }
        if originalBackground == nil { originalBackground = window.backgroundColor }
        let translucent = BackgroundOpacity.isTranslucent(opacity)
        if window.isOpaque == translucent { window.isOpaque = !translucent }
        let bg: NSColor = translucent ? .clear : (originalBackground ?? .windowBackgroundColor)
        if window.backgroundColor != bg { window.backgroundColor = bg }
        let wantsBlur = translucent && blur
        if wantsBlur, effectView == nil {
            let v = NSVisualEffectView(frame: bounds)
            v.blendingMode = .behindWindow
            v.material = .underWindowBackground
            v.state = .active
            v.autoresizingMask = [.width, .height]
            addSubview(v)
            effectView = v
        } else if !wantsBlur, let v = effectView {
            v.removeFromSuperview()
            effectView = nil
        }
        window.invalidateShadow()
    }
}
