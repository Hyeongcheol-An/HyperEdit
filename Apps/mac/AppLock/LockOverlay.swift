import SwiftUI
import AppKit
import HyperCore

// applock: 잠금 오버레이 — ContentView 루트의 .overlay 로 리본·사이드바·편집기·패널·상태바 전부를 불투명하게 가린다.
// 파일 이름 같은 문서 정보는 보여 주지 않는다. 인증은 "Unlock" 버튼(또는 Return)을 눌러야 시작된다.

/// ContentView 에 붙는 한 줄: 잠겨 있을 때만 LockOverlay 를 그린다 (컨트롤러의 isLocked 를 직접 관찰)
struct AppLockOverlayHost: View {
    @ObservedObject var controller: AppLockController
    let theme: Theme

    var body: some View {
        if controller.isLocked { LockOverlay(controller: controller, theme: theme) }
    }
}

/// 잠긴 동안 콘텐츠를 접근성 트리에서 숨긴다 — 오버레이는 그림일 뿐이라 VoiceOver·손쉬운 사용 권한을 가진 앱은 AXValue 로 본문을 읽을 수 있었다(QA)
struct AppLockAccessibilityHider: ViewModifier {
    @ObservedObject var controller: AppLockController
    func body(content: Content) -> some View { content.accessibilityHidden(controller.isLocked) }
}

struct LockOverlay: View {
    @ObservedObject var controller: AppLockController
    let theme: Theme

    var body: some View {
        ZStack {
            theme.background.color
            LockOverlayMarker()
            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(theme.foregroundMuted.color)
                    .padding(.bottom, 4)
                Text("HyperEdit is locked")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.foreground.color)
                (controller.usesTouchID ? Text("Unlock with Touch ID or your password") : Text("Unlock with your password"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.foregroundMuted.color)
                Button {
                    Task { @MainActor in await controller.requestUnlock() }
                } label: {
                    Label("Unlock", systemImage: controller.usesTouchID ? "touchid" : "key.fill")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accent.color)
                .controlSize(.large)
                .disabled(controller.isAuthenticating)
                .padding(.top, 6)
                if let m = controller.message {
                    Text(m)
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.errorColor.color)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                Text("Return unlocks · ⌃⌘L locks at any time")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.foregroundDim.color)
                    .padding(.top, 10)
            }
            .padding(40)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("HyperEdit is locked"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())   // 클릭·스크롤이 아래 편집기로 가지 않는다
    }
}

/// 셀프테스트가 NSView 트리에서 오버레이를 찾는 표식 (SwiftUI 뷰는 NSView 가 아니라 접근성 프록시로만 노출된다). 이벤트는 받지 않는다
private struct LockOverlayMarker: NSViewRepresentable {
    final class MarkerView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override var isOpaque: Bool { false }
    }
    func makeNSView(context: Context) -> MarkerView {
        let v = MarkerView()
        v.identifier = NSUserInterfaceItemIdentifier(AppLockController.overlayIdentifier)
        v.setAccessibilityElement(false)
        return v
    }
    func updateNSView(_ nsView: MarkerView, context: Context) {}
}
