import AppKit
import HyperCore

// 실사용 시뮬레이션 — 세로 스크롤바: 손잡이 끌기, 트랙 클릭, 손잡이의 자리가 문서에서의 자리(줄)와 맞는가
//
// 배경(2026-11-25 실측): TextKit 2 는 뷰포트를 배치할 때마다 문서 높이를 다시 어림한다 — 한 번도 안 본 곳으로 한 화면 넘게 뛰면 걸음마다 ±10~20 % 흔들린다
// (1.3 MB 메모: 847,845 … 1,157,051 pt, 실제는 약 70만). NSScrollView 는 손잡이를 "스크롤 위치 ÷ 문서 높이"로 놓으므로 손잡이가 진행 반대로 튀고(800 pt 걸음
// 250번 가운데 95번, 최대 14.6 pt) 문서에서의 자리(줄 비율)와 3~6 % 어긋난다. 끌 때도 같다: 끄는 동안 손잡이가 마우스에서 떨어졌다 붙고, 놓은 자리에 있지 않다.
//
// 끌기는 스크롤러의 mouseDown 을 직접 부른다 — 추적 루프가 이벤트를 기다리므로 끌기·떼기 이벤트를 먼저 앱의 큐에 넣어 둔다(코어의 drag 와 같은 방식).

/// 스크롤러가 동작(action)을 보낸 **뒤**를 알려 준다 — 손잡이를 끄는 동안 걸음마다, 스크롤 뷰가 스크롤하고 손잡이를 다시 놓은 뒤의 상태를 보려는 것이다.
/// (클립 뷰의 bounds 알림은 스크롤 뷰가 손잡이를 다시 놓기 전에 온다.) 이 프로세스 안에서만 그 스크롤러 클래스의 sendAction(_:to:) 구현을 감싼다
enum ScrollerProbe {
    @MainActor static var afterAction: ((NSScroller) -> Void)?
    @MainActor private static var wrapped: Set<ObjectIdentifier> = []

    @MainActor static func install(on scroller: NSScroller) {
        let sel = #selector(NSControl.sendAction(_:to:))
        guard let m = class_getInstanceMethod(type(of: scroller), sel) else { return }
        // 스크롤러의 클래스마다 한 번만 감싼다 (하위 클래스가 재정의했으면 그 구현, 아니면 물려받은 NSScroller 의 것 — 그때는 모든 스크롤러가 거쳐 가지만 알리기만 한다)
        let id = ObjectIdentifier(type(of: scroller))
        guard !wrapped.contains(id) else { return }
        wrapped.insert(id)
        typealias Fn = @convention(c) (AnyObject, Selector, Selector?, AnyObject?) -> Bool
        let original = unsafeBitCast(method_getImplementation(m), to: Fn.self)
        let block: @convention(block) (AnyObject, Selector?, AnyObject?) -> Bool = { me, action, target in
            let handled = original(me, sel, action, target)
            MainActor.assumeIsolated { if let s = me as? NSScroller { afterAction?(s) } }
            return handled
        }
        method_setImplementation(m, imp_implementationWithBlock(block))
    }
}

extension RealUseContext {
    var vScroller: NSScroller? { scroll.verticalScroller }

    /// 손잡이의 위 가장자리 (스크롤러 좌표, 위에서 아래로)
    var knobTop: CGFloat {
        guard let s = vScroller else { return -1 }
        let r = s.rect(for: .knob)
        return s.isFlipped ? r.minY : s.bounds.height - r.maxY
    }

    /// 손잡이의 값 (0 = 문서 처음 … 1 = 끝)
    var knobValue: Double { vScroller?.doubleValue ?? -1 }

    /// 손잡이가 움직일 수 있는 길이 (트랙 − 손잡이)
    var knobTravel: CGFloat {
        guard let s = vScroller else { return 1 }
        return max(1, s.rect(for: .knobSlot).height - s.rect(for: .knob).height)
    }

    /// 화면 맨 위 줄의 문서에서의 자리 (0…1): 맨 위에 걸친 문단의 번호 ÷ (전체 문단 수 − 화면의 문단 수)
    func lineRatio() -> Double {
        let v = visible
        let on = viewportFragments().filter { $0.maxY > v.minY + 1 && $0.minY < v.maxY - 1 }
        guard let f = on.first, let l = on.last else { return -1 }
        let idx = LineIndex(nsString: text)
        let top = Double(idx.lineNumber(forUTF16Offset: f.offset) - 1) + Double(max(0, min(1, (v.minY - f.minY) / max(1, f.maxY - f.minY))))
        var bottom = Double(idx.lineNumber(forUTF16Offset: l.offset) - 1) + Double(max(0, min(1, (v.maxY - l.minY) / max(1, l.maxY - l.minY))))
        if l.offset + l.length >= length { bottom = Double(idx.lineCount) }
        let rest = Double(idx.lineCount) - bottom
        return top + rest > 0 ? top / (top + rest) : 0
    }

    struct KnobDrag {
        /// 끄는 동안 스크롤이 일어날 때마다: 마우스의 y(스크롤러 좌표, 위에서 아래로)와 손잡이 위 가장자리
        var samples: [(mouse: CGFloat, knob: CGFloat)] = []
        var grab: CGFloat = 0          // 잡은 점이 손잡이 위 가장자리에서 얼마나 아래인가
        var releaseKnob: CGFloat = 0   // 놓는 순간의 손잡이 위 가장자리
        var ms: Double = 0
        /// 끄는 동안 손잡이가 마우스(잡은 점)에서 가장 멀리 떨어진 거리
        var worstLag: CGFloat { samples.map { abs($0.knob + grab - $0.mouse) }.max() ?? 0 }
    }

    /// 손잡이를 잡아 `dy` pt(양수 = 아래로)만큼 `steps` 걸음에 끌고 놓는다. 손잡이가 없으면(문서가 한 화면에 들어간다) nil
    func dragKnob(by dy: CGFloat, steps: Int = 12) async -> KnobDrag? {
        guard let s = vScroller, !s.isHidden, s.rect(for: .knob).height > 1, let win = s.window else { return nil }
        await settle(0)
        let knob = s.rect(for: .knob)
        let start = NSPoint(x: knob.midX, y: knob.midY)
        let sign: CGFloat = s.isFlipped ? 1 : -1
        func inWindow(_ offset: CGFloat) -> NSPoint { s.convert(NSPoint(x: start.x, y: start.y + sign * offset), to: nil) }
        func mouseY(_ e: NSEvent?) -> CGFloat {
            guard let e else { return -1 }
            let p = s.convert(e.locationInWindow, from: nil)
            return s.isFlipped ? p.y : s.bounds.height - p.y
        }
        func event(_ type: NSEvent.EventType, _ p: NSPoint) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: win.windowNumber,
                               context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
        }
        var out = KnobDrag()
        out.grab = (s.isFlipped ? start.y : s.bounds.height - start.y) - knobTop
        guard let down = event(.leftMouseDown, inWindow(0)) else { return nil }
        for i in 1...max(1, steps) { if let d = event(.leftMouseDragged, inWindow(dy * CGFloat(i) / CGFloat(max(1, steps)))) { NSApp.postEvent(d, atStart: false) } }
        if let up = event(.leftMouseUp, inWindow(dy)) { NSApp.postEvent(up, atStart: false) }
        // 끄는 동안의 기록: 스크롤러가 동작을 보내고 스크롤 뷰가 스크롤·손잡이 재배치를 끝낸 뒤의 손잡이와, 그때 처리 중인 끌기 이벤트의 자리
        ScrollerProbe.install(on: s)
        ScrollerProbe.afterAction = { sender in
            guard sender === s, let e = NSApp.currentEvent, e.type == .leftMouseDragged else { return }
            out.samples.append((mouseY(e), self.knobTop))
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        s.mouseDown(with: down)
        out.ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        out.releaseKnob = knobTop
        ScrollerProbe.afterAction = nil
        // 추적 루프가 남긴 이벤트가 있으면 버린다 (루프가 일찍 끝난 경우 — 다음 클릭이 그것을 받지 않게)
        while NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: nil, inMode: .default, dequeue: true) != nil {}
        await settle(60)
        return out
    }

    /// 끌기 한 걸음(마우스 이벤트 하나에 스크롤 한 번)의 시간. 끌기는 추적 루프 한 번 안에서 돌아 정지 감시로는 볼 수 없으므로(끌기 전체가 한 번의 '정지'다)
    /// 걸음당으로 본다. 실측(1.3 MB 메모): 여러 걸음 끌기 2.9~13.6 ms, 한 걸음에 1,200줄을 건너뛰는 짧은 끌기 11~34 ms(드물게 61 ms) —
    /// 걸음마다 그 자리의 뷰포트를 배치하고 닻으로 맞추는 값이다. 200 ms 를 넘으면 걸음마다 문서 크기에 비례하는 일을 하고 있는 것이다
    func checkDragCost(_ d: KnobDrag, budget: Double = 200, _ why: String) {
        let perStep = d.ms / Double(max(1, d.samples.count))
        if perStep > budget { issue("slow", String(format: "%@: dragging the knob cost %.1f ms per scroll step (%d steps, %.0f ms in all; budget %.0f ms per step)", why, perStep, d.samples.count, d.ms, budget), snap: false) }
    }

    /// 손잡이를 끌고 늘 보는 것을 본다: 끄는 동안 손잡이가 마우스를 따라오고, 놓은 뒤(화면이 가라앉고 휠을 한 번 건드린 뒤에도) 놓은 자리에 있고,
    /// 손잡이의 자리가 화면 맨 위 줄의 문서에서의 자리와 맞는다. 반환: 기록
    @discardableResult
    func dragKnobChecked(_ why: String, by dy: CGFloat, steps: Int = 12) async -> KnobDrag? {
        let k0 = knobTop, top0 = topLine()
        guard let d = await dragKnob(by: dy, steps: steps) else { issue("other", "\(why): there is no scroller knob to drag"); return nil }
        checkDragCost(d, why)
        let travel = knobTravel
        // 끄는 동안: 손잡이는 잡은 점 아래에 그대로 (트랙의 끝에 닿으면 마우스가 더 가도 멈춘다 — 그 구간은 빼고 본다)
        let free = d.samples.filter { $0.mouse - d.grab > 1 && $0.mouse - d.grab < travel - 1 }
        let lag = free.map { abs($0.knob + d.grab - $0.mouse) }.max() ?? 0
        if lag > 2 { issue("other", String(format: "%@: while dragging, the knob was up to %.1f pt away from the mouse (it should stay under it)", why, lag)) }
        // 놓은 뒤: 그 자리에
        await settle(250)
        let k1 = knobTop
        if abs(k1 - d.releaseKnob) > 1.5 { issue("other", String(format: "%@: the knob was released at %.1f pt but sits at %.1f pt after the view settled", why, d.releaseKnob, k1)) }
        // 휠을 1 pt 굴렸다 되돌려도(스크롤 뷰가 손잡이를 다시 놓는다) 그 자리에
        await scrollBy(dy > 0 ? -1 : 1); await settle(0); await scrollBy(dy > 0 ? 1 : -1); await settle(60)
        let k2 = knobTop
        if abs(k2 - d.releaseKnob) > 2 { issue("other", String(format: "%@: the knob was released at %.1f pt but jumped to %.1f pt on the next wheel event", why, d.releaseKnob, k2)) }
        // 손잡이의 자리 = 화면 맨 위 줄의 문서에서의 자리 (트랙에서 4 pt 또는 1 % 이내)
        let ratio = lineRatio(), value = knobValue
        if ratio >= 0, CGFloat(abs(value - ratio)) * travel > max(4, travel * 0.01) {
            issue("other", String(format: "%@: the knob is at %.3f of its %.0f pt travel but the top line is at %.3f of the document — %.1f pt apart", why, value, travel, ratio, CGFloat(value - ratio) * travel))
        }
        // 방향: 아래로 끌었으면 아래 줄이 보인다
        let top1 = topLine()
        if abs(k2 - k0) > 2, dy > 0 ? top1 < top0 : top1 > top0 { issue("scroll-delta", "\(why): dragged the knob \(dy > 0 ? "down" : "up") but the top line went from \(top0) to \(top1)") }
        note(String(format: "%@: knob %.1f → %.1f pt (released at %.1f, %d scroll steps, %.1f ms/step), worst distance from the mouse %.1f pt, top line %d → %d, line ratio %.4f vs knob %.4f",
                    why, k0, k2, d.releaseKnob, d.samples.count, d.ms / Double(max(1, d.samples.count)), lag, top0, top1, ratio, value))
        checkAll(why)
        return d
    }

    /// 겹침(overlay) 스크롤러의 손잡이가 지금 얼마나 보이는가 (0 = 숨음 … 1). 스크롤러가 그리는 데 쓰는 비공개 객체의 값이라 읽을 수 없으면 nil —
    /// 판정에는 '굴렸을 때는 보인다'를 먼저 확인한 실행에서만 쓴다
    var overlayKnobAlpha: CGFloat? {
        guard let s = vScroller, s.scrollerStyle == .overlay, s.responds(to: NSSelectorFromString("scrollerImp")),
              let imp = s.value(forKey: "scrollerImp") as? NSObject, imp.responds(to: NSSelectorFromString("knobAlpha")) else { return nil }
        return (imp.value(forKey: "knobAlpha") as? NSNumber).map { CGFloat($0.doubleValue) }
    }

    /// `ms` 동안 겹침 스크롤러 손잡이가 가장 많이 보인 정도 (10 ms 마다 본다)
    func watchOverlayKnob(ms: Int) async -> CGFloat {
        var top: CGFloat = 0
        for _ in 0..<max(1, ms / 10) {
            top = max(top, overlayKnobAlpha ?? 0)
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return top
    }

    /// 휠로 굴리는 동안 손잡이가 진행 방향으로만, 고르게 움직이는가. 반환: (거꾸로 간 가장 큰 걸음 pt, 한 걸음에 가장 많이 간 pt)
    @discardableResult
    func knobRun(_ label: String, steps: Int, by d: CGFloat) async -> (back: CGFloat, jump: CGFloat) {
        // 손잡이의 값 × 움직일 수 있는 길이 — 그려지는 자리(정수 pt)보다 잘게 본다
        let travel = knobTravel
        var last = CGFloat(knobValue) * travel, back: CGFloat = 0, fwd: CGFloat = 0, backAt = 0, fwdAt = 0
        let sign: CGFloat = d > 0 ? 1 : -1
        var line = topLine(), lineBack = 0, lineBackAt = 0
        for i in 1...steps {
            await scrollBy(d); await settle(0)
            let k = CGFloat(knobValue) * travel
            let dk = (k - last) * sign
            if dk < back { back = dk; backAt = i }
            if dk > fwd { fwd = dk; fwdAt = i }
            last = k
            let t = topLine()
            if (t - line) * Int(sign) < -lineBack { lineBack = -(t - line) * Int(sign); lineBackAt = i }
            line = t
        }
        if lineBack > 0 { note("\(label): the top line itself went \(lineBack) line(s) against the scroll direction at step \(lineBackAt) — the knob followed the content") }
        // 내용이 거꾸로 가는 것은 손잡이가 아니라 스크롤의 결함이다. 알려진 것 하나가 남아 있다: 한 화면을 넘는 걸음(800 pt)이 조각 캐시를 버리는 걸음과 겹치면
        // 화면에 남는 조각이 없어 스크롤 닻이 어림으로 바로잡는다 — 1.3 MB 메모의 108번째 걸음에서 22줄(실측, 되풀이해도 같다).
        // 한 걸음의 몫(|d| pt ÷ 24 pt 줄)보다 더 거꾸로 갔으면 그것과 다른 일이다
        let stepLines = max(8, Int(abs(d) / 24) + 4)
        if lineBack > stepLines { issue("scroll-delta", "\(label): the top line went \(lineBack) lines against the scroll direction at step \(lineBackAt) — more than one step's worth (\(stepLines) lines)") }
        note(String(format: "%@: %d × %+.0f pt — knob ended at %.1f of %.0f pt; worst step against the scroll direction %.1f pt (step %d), largest step along it %.1f pt (step %d)",
                    label, steps, d, last, knobTravel, -back, backAt, fwd, fwdAt))
        if -back > 1.5 { issue("other", String(format: "%@: the scroller knob moved %.1f pt against the scroll direction at step %d", label, -back, backAt)) }
        return (-back, fwd)
    }
}

extension RealUse {
    @MainActor static let scrollKnobScenarios: [Scenario] = [
        // 손잡이 끌기: 끄는 만큼 따라오고, 놓으면 그 자리 — 그리고 그 자리가 문서에서의 자리와 맞는다. 두 스크롤러 스타일(겹침·항상 보임) 모두
        Scenario(name: "scroll-knob-drag") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "knob-drag.md") }
            let style0 = ctx.scroll.scrollerStyle
            for style in [NSScroller.Style.legacy, .overlay] {
                let name = style == .legacy ? "legacy" : "overlay"
                ctx.scroll.scrollerStyle = style
                await ctx.key(.up, [.command]); await ctx.settle(300)
                ctx.at("\(name): drag down in one go")
                ctx.note("\(name): scroller \(ctx.vScroller.map { String(describing: type(of: $0)) } ?? "none") style \(ctx.vScroller?.scrollerStyle.rawValue ?? -1), knob travel \(Int(ctx.knobTravel)) pt, responsive scrolling \(type(of: ctx.scroll).isCompatibleWithResponsiveScrolling)")
                await ctx.withRelaxedStalls(5_000) { _ = await ctx.dragKnobChecked("\(name): drag down 150 pt in 30 steps", by: 150, steps: 30) }
                ctx.checkInk("\(name): after the long drag"); ctx.snap("\(name)-dragged")
                ctx.at("\(name): short drags")
                for i in 1...6 { await ctx.withRelaxedStalls(5_000) { _ = await ctx.dragKnobChecked("\(name): short drag down \(i) (18 pt)", by: 18, steps: 4) } }
                for i in 1...6 { await ctx.withRelaxedStalls(5_000) { _ = await ctx.dragKnobChecked("\(name): short drag up \(i) (-22 pt)", by: -22, steps: 4) } }
                ctx.checkInk("\(name): after the short drags")
                // 끝까지: 트랙의 끝을 넘겨 끌면 문서의 끝·처음
                ctx.at("\(name): drag to the ends")
                await ctx.withRelaxedStalls(5_000) { if let d = await ctx.dragKnob(by: ctx.knobTravel + 60, steps: 20) { ctx.checkDragCost(d, "\(name): drag to the bottom") } }
                await ctx.settle(300)
                ctx.expectBottom("\(name): after dragging the knob past the bottom of the track"); ctx.checkAll("\(name): knob at the bottom"); ctx.checkInk("\(name): knob at the bottom")
                await ctx.withRelaxedStalls(5_000) { if let d = await ctx.dragKnob(by: -(ctx.knobTravel + 60), steps: 20) { ctx.checkDragCost(d, "\(name): drag to the top") } }
                await ctx.settle(300)
                ctx.expectTop("\(name): after dragging the knob past the top of the track"); ctx.checkAll("\(name): knob at the top"); ctx.checkInk("\(name): knob at the top")
                // 끈 뒤의 휠: 손잡이가 진행 방향으로만
                ctx.at("\(name): wheel after dragging")
                await ctx.withRelaxedStalls(5_000) { _ = await ctx.dragKnobChecked("\(name): drag to the middle", by: ctx.knobTravel * 0.5, steps: 16) }
                await ctx.knobRun("\(name): wheel down after the drag", steps: 40, by: 300)
                await ctx.knobRun("\(name): wheel up after the drag", steps: 40, by: -300)
            }
            ctx.scroll.scrollerStyle = style0
            // 작은 문서(전체가 몇 화면): 손잡이가 길다 — 끄는 양과 화면이 가는 양이 맞는다
            await ctx.open(text: (1...240).map { "line \($0) " + ($0 % 6 == 0 ? String(repeating: "wrapped words 감기는 줄 ", count: 9) : "short") }.joined(separator: "\n") + "\n", name: "knob-small.md")
            await ctx.key(.up, [.command]); await ctx.settle(300)
            ctx.at("small document")
            for i in 1...5 { _ = await ctx.dragKnobChecked("small: drag down \(i) (40 pt)", by: 40, steps: 8) }
            for i in 1...5 { _ = await ctx.dragKnobChecked("small: drag up \(i) (-40 pt)", by: -40, steps: 8) }
            ctx.expectTop("small: after dragging down and back up the same amount")
            _ = await ctx.dragKnob(by: ctx.knobTravel + 40, steps: 12); await ctx.settle(200)
            ctx.expectBottom("small: after dragging the knob to the bottom"); ctx.checkAll("small: knob at the bottom"); ctx.checkInk("small: knob at the bottom")
            ctx.snap("small-end")
        },

        // 손잡이의 자리: 휠·Page·줄 이동 뒤에 화면 맨 위 줄의 문서에서의 자리와 맞고, 굴리는 동안 진행 방향으로만 움직인다 (본 적 없는 곳으로 크게 뛸 때도)
        Scenario(name: "scroll-knob-position") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "knob-position.md") }
            await ctx.key(.up, [.command]); await ctx.settle(300)
            let count = LineIndex(nsString: ctx.text).lineCount
            @MainActor func agree(_ why: String) {
                let travel = ctx.knobTravel, ratio = ctx.lineRatio(), value = ctx.knobValue
                guard ratio >= 0 else { return }
                if CGFloat(abs(value - ratio)) * travel > max(4, travel * 0.01) {
                    ctx.issue("other", String(format: "%@: the knob is at %.3f of its travel but the top line is at %.3f of the document (%.1f pt apart on a %.0f pt track)", why, value, ratio, CGFloat(value - ratio) * travel, travel))
                }
            }
            ctx.at("big wheel steps into unseen text")
            await ctx.knobRun("wheel down 800", steps: 120, by: 800); agree("after wheeling down 96,000 pt")
            await ctx.knobRun("wheel up 800", steps: 60, by: -800); agree("after wheeling back up 48,000 pt")
            ctx.at("small wheel steps")
            await ctx.knobRun("wheel down 35", steps: 80, by: 35); agree("after 80 small steps down")
            await ctx.knobRun("wheel up 35", steps: 80, by: -35); agree("after 80 small steps up")
            ctx.at("go to line")
            for n in [count / 4, count / 2, count * 3 / 4, count - 40, 30] {
                ctx.model.jump(toLine: n); await ctx.settle(450)
                agree("after go to line \(n)")
                ctx.note(String(format: "line %d of %d → knob %.4f, line ratio %.4f", n, count, ctx.knobValue, ctx.lineRatio()))
            }
            ctx.at("page keys")
            ctx.model.jump(toLine: count / 2); await ctx.settle(450)
            var last = ctx.knobValue
            for i in 1...12 {
                await ctx.key(.pageDown); await ctx.settle(250)
                if ctx.knobValue < last - 0.003 { ctx.issue("other", String(format: "Page Down %d: the knob moved up (%.4f → %.4f)", i, last, ctx.knobValue)) }
                last = ctx.knobValue
            }
            agree("after 12 × Page Down")
            for i in 1...12 {
                await ctx.key(.pageUp); await ctx.settle(250)
                if ctx.knobValue > last + 0.003 { ctx.issue("other", String(format: "Page Up %d: the knob moved down (%.4f → %.4f)", i, last, ctx.knobValue)) }
                last = ctx.knobValue
            }
            agree("after 12 × Page Up")
            ctx.at("ends")
            await ctx.key(.down, [.command]); await ctx.settle(300)
            ctx.expectBottom("after ⌘↓")
            await ctx.knobRun("wheel up from the end", steps: 60, by: -800); agree("after wheeling up from the end")
            await ctx.key(.up, [.command]); await ctx.settle(300)
            ctx.expectTop("after ⌘↑")
            // 입력으로 줄 수가 바뀌어도 맞는다
            ctx.at("after editing")
            ctx.model.jump(toLine: count / 3); await ctx.settle(450)
            await ctx.type(String(repeating: "new line\n", count: 30)); await ctx.settle(400)
            agree("after typing 30 lines in the first third")
            // 여러 번 감기는 문단의 문서
            await ctx.withRelaxedStalls { await ctx.open(.wide, name: "knob-position-wide.md") }
            await ctx.key(.up, [.command]); await ctx.settle(300)
            ctx.at("wide: wheel")
            await ctx.knobRun("wide: wheel down 700", steps: 80, by: 700); agree("wide: after wheeling down")
            await ctx.knobRun("wide: wheel up 700", steps: 80, by: -700); agree("wide: after wheeling up")
            ctx.snap("end")
        },

        // 손잡이를 줄 기준으로 놓지 않는 상태(줄바꿈 끔 · 접힌 문단이 있는 문서)와 그 사이를 오갈 때, 그리고 입력만 하는 동안의 겹침 스크롤러
        Scenario(name: "scroll-knob-state") { ctx in
            ctx.logWindowState()
            let saved = ViewDefaults(ctx)
            let style0 = ctx.scroll.scrollerStyle
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "knob-state.md") }
            /// AppKit 의 좌표 기준 값: 스크롤 위치 ÷ (문서 높이 − 화면 높이)
            @MainActor func coordinateValue() -> Double {
                let clip = ctx.scroll.contentView
                return Double(clip.bounds.minY / max(1, ctx.tv.frame.height - clip.bounds.height))
            }
            @MainActor func expectCoordinateKnob(_ why: String) {
                if ctx.tv.usesLineScroller { ctx.issue("other", "\(why): the knob should be placed by coordinates here, but the line-based placement is on") }
                let travel = ctx.knobTravel
                if CGFloat(abs(ctx.knobValue - coordinateValue())) * travel > 1.5 {
                    ctx.issue("other", String(format: "%@: the knob is at %.4f but the scroll position is at %.4f of the document — %.1f pt apart on a %.0f pt track", why, ctx.knobValue, coordinateValue(), CGFloat(ctx.knobValue - coordinateValue()) * travel, travel))
                }
            }

            // 입력만 하는 동안: 줄 수가 바뀔 때마다 손잡이의 값이 조금씩 바뀐다 — 그렇다고 겹침 스크롤러가 나타나면 안 된다 (굴릴 때만 나타난다)
            ctx.at("overlay scroller while typing")
            ctx.scroll.scrollerStyle = .overlay
            ctx.model.jump(toLine: 9_000); await ctx.settle(600)
            await ctx.scrollBy(120); await ctx.settle(0)
            let shownByWheel = await ctx.watchOverlayKnob(ms: 400)
            if shownByWheel > 0.05 {
                // 스크롤러가 다시 숨을 때까지 기다린다
                for _ in 0..<40 { if (ctx.overlayKnobAlpha ?? 0) < 0.01 { break }; try? await Task.sleep(nanoseconds: 100_000_000) }
                let rest = ctx.overlayKnobAlpha ?? 0
                if let a = ctx.anchor(nearScreenY: 100), await ctx.clickCaret(a.offset, "a line near the top of the screen") {
                    let y0 = ctx.visible.minY
                    var shown: CGFloat = 0
                    for _ in 0..<10 {
                        await ctx.typeKeys("line\n")
                        shown = max(shown, await ctx.watchOverlayKnob(ms: 60))
                    }
                    shown = max(shown, await ctx.watchOverlayKnob(ms: 300))
                    ctx.note(String(format: "overlay scroller: knob alpha %.2f after a wheel step, %.2f at rest, at most %.2f while typing 10 lines (view moved %.1f pt)", shownByWheel, rest, shown, ctx.visible.minY - y0))
                    if abs(ctx.visible.minY - y0) < 0.5, shown > max(0.05, rest + 0.05) {
                        ctx.issue("other", String(format: "typing 10 lines without scrolling made the overlay scroller appear (knob alpha %.2f; %.2f at rest)", shown, rest))
                    }
                }
            } else { ctx.note(String(format: "overlay scroller: the knob did not show after a wheel step in this run (alpha %.2f, readable %@) — the typing check was not made", shownByWheel, ctx.overlayKnobAlpha == nil ? "no" : "yes")) }
            ctx.scroll.scrollerStyle = .legacy

            // 줄바꿈 끔: 손잡이는 AppKit 의 좌표 기준 그대로, 끌기도 그대로 — 그리고 줄바꿈을 다시 켜면 줄 기준으로 돌아온다
            ctx.at("word wrap off: the knob follows the scroll position")
            await ctx.key(.up, [.command]); await ctx.settle(300)
            await ctx.withRelaxedStalls { ctx.model.wordWrap = false; await ctx.settle(400) }
            await ctx.wheelTo(steps: 12, by: 600); await ctx.settle(200)
            expectCoordinateKnob("word wrap off, after wheeling down")
            await ctx.withRelaxedStalls(5_000) {
                if let d = await ctx.dragKnob(by: 60, steps: 10) {
                    await ctx.settle(250)
                    ctx.note(String(format: "word wrap off: dragged the knob 60 pt — worst distance from the mouse %.1f pt, %.1f ms/step", d.worstLag, d.ms / Double(max(1, d.samples.count))))
                    if d.worstLag > 2 { ctx.issue("other", String(format: "word wrap off: while dragging, the knob was up to %.1f pt away from the mouse", d.worstLag)) }
                } else { ctx.issue("other", "word wrap off: there is no scroller knob to drag") }
            }
            expectCoordinateKnob("word wrap off, after dragging the knob"); ctx.checkAll("word wrap off, after dragging the knob"); ctx.checkInk("word wrap off, after dragging the knob")
            await ctx.withRelaxedStalls { ctx.model.wordWrap = true; await ctx.settle(500) }
            await ctx.scrollBy(48); await ctx.settle(100)
            let ratio = ctx.lineRatio()
            if !ctx.tv.usesLineScroller { ctx.issue("other", "word wrap back on: the line-based knob placement did not come back") }
            if ratio >= 0, CGFloat(abs(ctx.knobValue - ratio)) * ctx.knobTravel > max(4, ctx.knobTravel * 0.01) {
                ctx.issue("other", String(format: "word wrap back on: the knob is at %.4f but the top line is at %.4f of the document", ctx.knobValue, ratio))
            }

            // 접힌 문단이 있는 문서: 좌표 기준 (접힌 줄은 높이가 없어 줄 수와 화면이 비례하지 않는다). 모두 펴면 줄 기준으로 돌아온다
            ctx.at("folded: the knob follows the scroll position")
            ctx.model.jump(toLine: 9_000); await ctx.settle(500)
            ctx.model.send(.foldAll); await ctx.settle(700)
            if ctx.tv.hasFolds?() == true {
                await ctx.wheelTo(steps: 6, by: 300); await ctx.settle(200)
                expectCoordinateKnob("folded, after wheeling down")
                await ctx.withRelaxedStalls(5_000) {
                    if let d = await ctx.dragKnob(by: -30, steps: 6) {
                        await ctx.settle(250)
                        if d.worstLag > 2 { ctx.issue("other", String(format: "folded: while dragging, the knob was up to %.1f pt away from the mouse", d.worstLag)) }
                    }
                }
                expectCoordinateKnob("folded, after dragging the knob"); ctx.checkLayout("folded, after dragging the knob")
            } else { ctx.issue("other", "Fold All folded nothing in the notes corpus — the folded knob check was not made") }
            ctx.model.send(.unfoldAll); await ctx.settle(700)
            await ctx.scrollBy(48); await ctx.settle(100)
            if !ctx.tv.usesLineScroller { ctx.issue("other", "unfolded: the line-based knob placement did not come back") }
            let unfolded = ctx.lineRatio()
            if unfolded >= 0, CGFloat(abs(ctx.knobValue - unfolded)) * ctx.knobTravel > max(4, ctx.knobTravel * 0.01) {
                ctx.issue("other", String(format: "unfolded: the knob is at %.4f but the top line is at %.4f of the document", ctx.knobValue, unfolded))
            }
            ctx.scroll.scrollerStyle = style0
            ctx.snap("end")
            await ctx.withRelaxedStalls { await saved.restore(ctx) }
        },
    ]
}
