import SwiftUI
import AppKit
import HyperCore

// 셀프테스트: 외형(appearance) — 커서 스타일 3종(저장·텍스트 뷰 상태·칸 기하), 깜빡임 토글, 배경 투명도(창 isOpaque·편집기 배경 α·복귀),
// 블러(NSVisualEffectView 추가/제거), 실행 인자 파싱, 블록 캐럿 상태의 타이핑 지연.
extension SelfTest {
    @MainActor
    static func runAppearance(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { pumpEvent(); try? await Task.sleep(nanoseconds: ms * 1_000_000) }
        guard let coord = model.session.primary, let tv = coord.textView, let window = tv.window else {
            check(false, "appearance: primary editor, text view and window available"); return
        }
        let d = AppDefaults.store
        func effectViews() -> [NSVisualEffectView] {
            var found: [NSVisualEffectView] = []
            func walk(_ v: NSView) {
                if let e = v as? NSVisualEffectView, e.blendingMode == .behindWindow, e.material == .underWindowBackground { found.append(e) }
                v.subviews.forEach(walk)
            }
            if let cv = window.contentView { walk(cv) }
            return found
        }
        func containerAlpha() -> CGFloat {
            guard let cg = coord.container?.layer?.backgroundColor, let c = NSColor(cgColor: cg) else { return -1 }
            return c.alphaComponent
        }

        // 0. 기본값 — 휘발성 저장소라 사용자 설정과 무관
        check(model.cursorStyle == .bar && model.cursorBlink && model.backgroundOpacity == 1 && !model.backgroundBlur,
              "appearance: defaults — bar caret, blink on, opacity 100%, no blur")
        check(window.isOpaque && tv.cursorStyle == .bar && tv.cursorBlinks && tv.isOpaque, "appearance: window opaque, text view mirrors the defaults")
        check(BackgroundOpacity.clamped(0.3) == 0.5 && BackgroundOpacity.clamped(1.7) == 1 && BackgroundOpacity.clamped(0.8) == 0.8 && BackgroundOpacity.clamped(.nan) == 1,
              "appearance: --opacity values clamp to 0.5…1.0")
        check(CursorStyle(rawValue: "block") == .block && CursorStyle(rawValue: "Block") == nil && CursorStyle.allCases.map(\.rawValue) == ["bar", "block", "underline"],
              "appearance: --cursor raw values bar/block/underline")
        check(BackgroundOpacity.presets == [1.0, 0.9, 0.8, 0.7], "appearance: View › Window Opacity presets 100/90/80/70%")

        // 1. 커서 스타일 3종: 저장값 + 텍스트 뷰 상태
        for style in [CursorStyle.block, .underline, .bar] {
            model.cursorStyle = style; await wait(250)
            check(d.string(forKey: CursorStyle.defaultsKey) == style.rawValue && tv.cursorStyle == style,
                  "appearance: cursor style '\(style.rawValue)' stored (\(d.string(forKey: CursorStyle.defaultsKey) ?? "nil")) and applied to the text view (\(tv.cursorStyle.rawValue))")
        }
        if let secondary = model.session.secondary?.textView {
            check(secondary.cursorStyle == .bar, "appearance: secondary editor follows the cursor style too")
        }

        // 2. 칸 기하 (블록·밑줄이 쓰는 글자 칸): 글자 위 = 글자 폭, 줄 끝 = 공백 한 칸, 한글 = 실제(넓은) 폭, 열 모드 가상 공백 = padding × 글자 폭
        model.cursorStyle = .block; await wait(250)
        model.jump(toLine: 4); await wait(300)   // 'NEEDLE first'
        let text = tv.string
        let ns = text as NSString
        let index = LineIndex(text: text)
        let line4 = index.range(ofLine: 4)
        let cw = tv.charWidth
        let onGlyph = tv.caretCell(at: line4.location)
        let contentLen = (ns.substring(with: line4).trimmingCharacters(in: .newlines) as NSString).length
        let atEnd = tv.caretCell(at: line4.location + contentLen)
        check(onGlyph != nil && abs((onGlyph?.width ?? 0) - cw) < 0.75 && (onGlyph?.height ?? 0) > 10,
              "appearance: block cell on 'N' is one character wide (\(onGlyph?.width ?? -1) vs \(cw)) and line-high (\(onGlyph?.height ?? -1))")
        check(atEnd != nil && abs((atEnd?.width ?? 0) - cw) < 0.75 && abs((atEnd?.minY ?? -1) - (onGlyph?.minY ?? -2)) < 0.5,
              "appearance: block cell at the line end is a space-wide cell on the same line")
        let line11 = index.range(ofLine: 11)   // '가. 한글 항목'
        let hangul = tv.caretCell(at: line11.location)
        check(hangul != nil && (hangul?.width ?? 0) > cw * 1.2, "appearance: block cell on '가' uses the glyph's real width (\(hangul?.width ?? -1) > \(cw))")
        let padded = tv.caretCell(at: line4.location, padding: 3)
        check(padded != nil && onGlyph != nil && abs((padded?.minX ?? 0) - ((onGlyph?.minX ?? 0) + 3 * cw)) < 0.5 && abs((padded?.width ?? 0) - cw) < 0.75,
              "appearance: column-mode virtual-space cell is shifted by padding × char width")
        let emptyLine = index.range(ofLine: 7)   // 빈 줄
        let onEmpty = tv.caretCell(at: emptyLine.location)
        check(onEmpty != nil && abs((onEmpty?.width ?? 0) - cw) < 0.75, "appearance: block cell on an empty line is a space-wide cell")

        // 3. 깜빡임 토글 — 창이 키가 아닌 셀프테스트에서는 타이머가 돌지 않아야 한다
        model.cursorBlink = false; await wait(200)
        check(d.object(forKey: "ui.cursorBlink") as? Bool == false && tv.cursorBlinks == false, "appearance: blink off stored and applied")
        check(!tv.isBlinkTimerRunning, "appearance: no blink timer while blink is off")
        model.cursorBlink = true; await wait(200)
        check(d.object(forKey: "ui.cursorBlink") as? Bool == true && tv.cursorBlinks, "appearance: blink on restored")
        check(tv.isBlinkTimerRunning == tv.headCaretVisible, "appearance: blink timer runs only while the caret is visible — key window + first responder + no selection (visible=\(tv.headCaretVisible), timer=\(tv.isBlinkTimerRunning))")
        check(tv.headCaretVisible == (window.isKeyWindow && window.firstResponder === tv), "appearance: head caret visibility follows key window + first responder (key=\(window.isKeyWindow))")
        if let ind = tv.insertionIndicator {
            check(ind.displayMode == .hidden, "appearance: native indicator hidden while the block caret is drawn by the view")
            model.cursorStyle = .bar; model.cursorBlink = false; await wait(200)
            if !ind.isHidden {
                check(ind.displayMode == .visible, "appearance: bar + blink off → native indicator .visible (no blink)")
                ind.displayMode = .automatic   // AppKit 이 다시 보일 때 하는 일을 흉내 → KVO 가 다음 턴에 되돌려야 한다
                await wait(100)
                check(ind.displayMode == .visible, "appearance: indicator mode re-applied when AppKit resets it")
            }
            model.cursorBlink = true; await wait(200)
            if !ind.isHidden { check(ind.displayMode == .automatic, "appearance: bar + blink on → native indicator .automatic") }
            log("appearance: native insertion indicator present (hidden=\(ind.isHidden), mode=\(ind.displayMode.rawValue))")
        } else {
            log("appearance: native insertion indicator not created (window was never key) — indicator mode checks skipped; verified by screenshots")
        }
        model.cursorStyle = .bar; model.cursorBlink = true; await wait(200)

        // 4. 투명도 0.8 → 창·편집기·패널 반투명
        model.backgroundOpacity = 0.8; await wait(400)
        check(abs((d.object(forKey: BackgroundOpacity.defaultsKey) as? Double ?? 0) - 0.8) < 0.001, "appearance: opacity 0.8 stored")
        check(!window.isOpaque && window.backgroundColor.alphaComponent == 0, "appearance: window non-opaque with a clear background at 80% (isOpaque=\(window.isOpaque))")
        check(tv.backgroundColor.alphaComponent == 0 && !tv.isOpaque, "appearance: text view background clear and non-opaque")
        check(abs(containerAlpha() - 0.8) < 0.01, "appearance: editor container layer carries the theme background at α 0.8 (\(containerAlpha()))")
        check(coord.scrollView?.drawsBackground == false, "appearance: scroll view stops drawing its background")
        check((tv.currentLineColor?.alphaComponent ?? 1) < 0.81, "appearance: current line highlight takes the same alpha (\(tv.currentLineColor?.alphaComponent ?? -1))")
        check(coord.gutter?.surfaceAlpha == 0.8, "appearance: gutter leaves its background to the container layer")
        check(effectViews().isEmpty, "appearance: no blur view while blur is off")

        // 5. 블러 켜기/끄기 → NSVisualEffectView 추가/제거, 불투명이면 효과 없음
        model.backgroundBlur = true; await wait(400)
        check(d.object(forKey: "ui.backgroundBlur") as? Bool == true, "appearance: blur stored")
        check(effectViews().count == 1 && effectViews().first?.state == .active, "appearance: blur adds one active behind-window NSVisualEffectView (\(effectViews().count))")
        if let e = effectViews().first, let host = e.superview {
            check(e.frame.width > 100 && abs(e.frame.width - host.bounds.width) < 1 && abs(e.frame.height - host.bounds.height) < 1,
                  "appearance: effect view fills its host (\(Int(e.frame.width))×\(Int(e.frame.height)))")
        }
        model.backgroundBlur = false; await wait(300)
        check(effectViews().isEmpty, "appearance: blur off removes the effect view")
        model.backgroundBlur = true; await wait(300)
        model.backgroundOpacity = 1.0; await wait(400)
        check(effectViews().isEmpty, "appearance: blur has no effect while the window is opaque")
        check(window.isOpaque && tv.backgroundColor.alphaComponent == 1 && tv.isOpaque && coord.scrollView?.drawsBackground == true,
              "appearance: 100% restores an opaque window, text view and scroll view")
        check(abs(containerAlpha() - 1) < 0.01 && coord.gutter?.surfaceAlpha == 1, "appearance: container layer and gutter opaque again")
        model.backgroundBlur = false; await wait(200)
        // 테마 전환 뒤에도 투명도가 유지되어야 한다
        model.backgroundOpacity = 0.7; await wait(300)
        let before = model.themes.current.id
        model.themes.selectNext(step: 1); await wait(500)
        check(model.themes.current.id != before && abs(containerAlpha() - 0.7) < 0.01 && !window.isOpaque, "appearance: theme change keeps the 70% translucency (\(containerAlpha()))")
        model.themes.select(id: before); await wait(400)
        model.backgroundOpacity = 1.0; await wait(300)
        check(window.isOpaque && abs(containerAlpha() - 1) < 0.01, "appearance: back to opaque after the theme round trip")

        // 6. 블록 캐럿 상태의 타이핑 지연 (키 입력마다 drawBackground 가 캐럿 칸을 계산한다)
        model.cursorStyle = .block; await wait(200)
        model.goToEnd(); await wait(300)
        let t1 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<40 {
            model.send(.perform { tv in tv.insertText("b", replacementRange: tv.selectedRange()) })
            await wait(1)
        }
        let typingMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000 / 40 - 1
        log(String(format: "perf typing with block caret %.2f ms/keystroke (incl. run loop)", typingMs))
        check(typingMs < 16, "appearance: typing latency under one frame (16 ms) with the block caret")
        model.send(.perform { tv in
            let ns = tv.string as NSString
            tv.insertText("", replacementRange: NSRange(location: ns.length - 40, length: 40))
        }); await wait(200)

        // 7. 기본값 복원 (이후 화면용 상태·스크린샷에 영향 없게)
        model.cursorStyle = .bar; model.cursorBlink = true; model.backgroundOpacity = 1; model.backgroundBlur = false; await wait(250)
        check(tv.cursorStyle == .bar && tv.cursorBlinks && window.isOpaque && effectViews().isEmpty, "appearance: defaults restored")
    }
}
