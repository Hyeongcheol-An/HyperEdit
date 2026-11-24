import AppKit
import HyperCore

// 실사용 시뮬레이션 — 스크롤: 픽셀·줄 단위 휠, 트랙패드 쓸기와 관성, Page Up/Down, 문서 처음·끝, 줄바꿈 켬·끔, 편집 뒤 스크롤
//
// 재는 법: TextKit 2 는 보이지 않는 문단의 높이를 추정하고 스크롤하면서 실측으로 바꾼다. 그때 문서 좌표(visible.minY·문서 높이)가 통째로 옮겨지므로
// "얼마나 스크롤됐나"는 좌표가 아니라 **닻 문단이 화면에서 움직인 양**으로 잰다(anchor → screenY). 사용자가 보는 것도 그것이다.

extension RealUseContext {
    /// 스크롤 상태 한 줄 (문서 좌표·문서 높이·보이는 조각의 처음과 끝·스크롤바 손잡이) — 로그용
    func scrollState(_ tag: String) {
        let v = visible
        let idx = LineIndex(nsString: text)
        let fr = viewportFragments()
        let on = fr.filter { $0.maxY > v.minY && $0.minY < v.maxY }
        guard let f = on.first, let l = on.last else { log("  \(tag): visibleY=\(v.minY) docH=\(tv.frame.height) no fragments on screen (laid out \(fr.count))"); return }
        log(String(format: "  %@: visibleY=%.1f h=%.0f docH=%.1f knob=%.4f frags=%d(on %d) first=L%d@%.1f last=L%d@%.1f…%.1f", tag, v.minY, v.height, tv.frame.height, knob, fr.count, on.count,
                   idx.lineNumber(forUTF16Offset: f.offset), f.minY - v.minY, idx.lineNumber(forUTF16Offset: l.offset), l.minY - v.minY, l.maxY - v.minY))
    }

    /// 창이 화면에 보이는가를 로그에 남긴다 — 완전히 가려지면(사용자의 다른 창·다른 Space) 표시 주기가 멈춰 합성 이벤트의 결과가 실제와 달라질 수 있다
    func logWindowState() {
        log("  \(scenario): window occluded=\(!window.occlusionState.contains(.visible)) onActiveSpace=\(window.isOnActiveSpace) appActive=\(NSApp.isActive) key=\(window.isKeyWindow)")
    }

    /// 세로 스크롤바 손잡이 위치 (0…1)
    var knob: Double { scroll.verticalScroller?.doubleValue ?? -1 }

    /// 지금 화면에 그려진 검색 강조의 픽셀 수 (강조색을 배경에 섞은 색과 가까운 픽셀, 2픽셀 간격 표본). 잴 수 없으면 -1.
    /// 비트맵 바이트를 직접 읽는다 — colorAt 은 픽셀당 수 µs 라 화면 전체를 훑으면 메인 스레드가 1초 가까이 멈춘다
    func matchHighlightPixels() -> Int {
        let v = visible
        guard v.height > 10, let rep = tv.bitmapImageRepForCachingDisplay(in: v) else { return -1 }
        tv.cacheDisplay(in: v, to: rep)
        guard rep.bitsPerSample == 8, rep.samplesPerPixel >= 3, !rep.isPlanar, let data = rep.bitmapData,
              let bgc = rep.colorAt(x: rep.pixelsWide - 3, y: 2), let hlc = tv.matchHighlightColor.usingColorSpace(bgc.colorSpace) else { return -1 }
        let first = rep.bitmapFormat.contains(.alphaFirst) ? 1 : 0
        let spp = rep.samplesPerPixel, bpr = rep.bytesPerRow
        // 배경 픽셀의 실제 바이트 + 같은 색 공간에서 섞은 강조색
        let bo = 2 * bpr + (rep.pixelsWide - 3) * spp + first
        let a = hlc.alphaComponent
        let want = [hlc.redComponent, hlc.greenComponent, hlc.blueComponent].enumerated().map { i, c in Int((c * a * 255 + CGFloat(data[bo + i]) * (1 - a)).rounded()) }
        var n = 0
        var y = 0
        while y < rep.pixelsHigh {
            var x = 0
            while x < rep.pixelsWide {
                let o = y * bpr + x * spp + first
                if abs(Int(data[o]) - want[0]) + abs(Int(data[o + 1]) - want[1]) + abs(Int(data[o + 2]) - want[2]) < 16 { n += 1 }
                x += 2
            }
            y += 2
        }
        return n
    }

    /// 화면 높이 `target`(뷰포트 위 가장자리로부터)에 가장 가까운, 온전히 보이는 문단 — 걸음 뒤에도 화면에 남을 닻을 고를 때
    func anchor(nearScreenY target: CGFloat) -> (offset: Int, y: CGFloat)? {
        let v = visible
        let frags = viewportFragments().filter { $0.minY >= v.minY && $0.maxY <= v.maxY }
        guard let f = frags.min(by: { abs($0.minY - v.minY - target) < abs($1.minY - v.minY - target) }) else { return nil }
        return (f.offset, f.minY - v.minY)
    }

    /// 화면에 걸친(일부만 보여도 되는) 맨 아래/맨 위 문단 — 한 화면 가까이 넘기는 Page Down/Up 뒤에도 배치 범위에 남는 닻
    func edgeAnchor(bottom: Bool) -> (offset: Int, y: CGFloat)? {
        let v = visible
        let on = viewportFragments().filter { $0.maxY > v.minY + 1 && $0.minY < v.maxY - 1 }
        guard let f = bottom ? on.last : on.first else { return nil }
        return (f.offset, f.minY - v.minY)
    }

    /// 트랙패드 쓸기를 닮은 픽셀 휠 흐름: 손가락 구간(같은 크기의 걸음) 뒤 관성 구간(기하급수로 줄어드는 걸음), 걸음 사이 `gapMs`(실제 이벤트 간격 8 ms 안팎).
    /// 걸음 사이에 레이아웃·그리기를 강제하지 않는다 — 표시 주기와 60 ms 스로틀이 실제처럼 끼어든다. 반환: 보낸 델타의 합(걸음마다 정수 pt 로 맞춘다).
    /// 위상(phase)이 붙은 제스처 이벤트는 쓰지 않는다: 스크롤 뷰가 제스처의 후속 이벤트를 창 서버에서 직접 읽어 추적하므로(반응형 스크롤) 합성해서 뷰에 건넨
    /// 이벤트로는 흉내 낼 수 없다. 실측: 코어의 `flick(total: 320)` 은 18 pt 만 움직이고, 제스처 '시작'만 받은 스크롤 뷰가 live scroll 상태로 남는다
    /// (끝 알림이 오지 않는다) — 그래서 이 영역의 시나리오는 `flick` 을 부르지 않는다
    @discardableResult
    func swipe(total: CGFloat, steps: Int = 8, momentumSteps: Int = 14, gapMs: UInt64 = 8) async -> CGFloat {
        let finger = total * 0.45
        var deltas = [CGFloat](repeating: (finger / CGFloat(steps)).rounded(), count: steps)
        var w: CGFloat = 1, weights: [CGFloat] = []
        for _ in 0..<momentumSteps { weights.append(w); w *= 0.8 }
        let sum = weights.reduce(0, +)
        for wt in weights { let d = ((total - finger) * wt / sum).rounded(); if d != 0 { deltas.append(d) } }
        var sent: CGFloat = 0
        for d in deltas {
            await scrollBy(d); sent += d
            // 창이 보이면 실제처럼 표시 주기에 맡기고, 완전히 가려져 표시 주기가 멈췄으면 걸음마다 배치를 끝낸다 (그러지 않으면 걸음들이 한 번의 큰 점프로 합쳐진다)
            if window.occlusionState.contains(.visible) { try? await Task.sleep(nanoseconds: gapMs * 1_000_000) } else { await settle(0) }
        }
        await settle(60)
        return sent
    }

    /// 닻 문단이 화면에서 움직인 양 (양수 = 문서 아래쪽으로 스크롤됨 = 내용이 위로). 닻이 화면 밖으로 나갔으면 nil
    func moved(since a: (offset: Int, y: CGFloat)?) -> CGFloat? {
        guard let a, let y1 = screenY(ofFragmentAt: a.offset) else { return nil }
        return a.y - y1
    }

    /// 픽셀 휠 한 걸음을 보내고 **화면에서 내용이 정확히 그만큼 움직였는지** 검사한다. 문서 처음·끝에 걸려 다 못 가는 걸음은 검사하지 않는다(끝 상태는 따로 본다).
    /// `restMs` 는 걸음 뒤의 쉼 — 60 ms 넘게 쉬었다가 굴리는 첫 걸음이 사용자의 "스크롤을 시작하는 순간"이다. 반환: 움직인 양(잴 수 없으면 nil)
    @discardableResult
    func wheelChecked(_ d: CGFloat, restMs: UInt64 = 0, tolerance: CGFloat = 1, _ why: String) async -> CGFloat? {
        let v = visible
        let clamped = d < 0 ? v.minY < -d + 1 : tv.frame.height - v.maxY < d + 1
        // 닻: 아래로 가면(내용이 위로) 화면 아래쪽 문단, 위로 가면 위쪽 문단 — 걸음 뒤에도 화면에 남는다
        let a = anchor(nearScreenY: d > 0 ? min(v.height - 60, d + 30) : max(10, v.height + d - 90))
        await scrollBy(d); await settle(0)
        let m = moved(since: a)
        let n0 = issues.count
        if !clamped { checkContentMoved(anchor: a, expected: d, tolerance: tolerance, why) }
        // 창이 완전히 가려지면(다른 Space·전체 화면 앱) 표시 주기가 멈춰 합성 이벤트의 결과가 달라질 수 있다 — 문제가 났을 때의 창 상태를 남긴다
        if issues.count > n0 { note("window at the failed step: occluded=\(!window.occlusionState.contains(.visible)) onActiveSpace=\(window.isOnActiveSpace) appActive=\(NSApp.isActive)") }
        if restMs > 0 { await settle(restMs) }
        return m
    }

    /// 검사 없이 자리만 옮긴다: 픽셀 휠 `steps` 걸음. 걸음마다 레이아웃을 끝낸다 — 창이 가려져 표시 주기가 멈춰 있어도(사용자가 다른 창으로 덮었을 때)
    /// 화면에 보일 때와 같은 순서로 배치되게 (한꺼번에 밀면 사이의 문단이 실측되지 않은 채 남아 뒤 걸음의 조건이 달라진다)
    func wheelTo(steps: Int, by d: CGFloat) async {
        for _ in 0..<steps { await scrollBy(d); await settle(0) }
    }

    /// 시나리오 안에서 문제가 `limit` 개 넘게 쌓였는가 — 같은 문제가 걸음마다 반복될 때 그 구간을 멈춰 보고서가 묻히지 않게 한다
    func tooManyIssues(since n0: Int, limit: Int = 5) -> Bool {
        guard issues.count - n0 >= limit else { return false }
        note("stopping this stretch after \(issues.count - n0) issues")
        return true
    }

    /// 문서 맨 처음에 있는가: y = 0, 첫 줄이 화면 맨 위(위 여백 바로 아래), 손잡이 0
    func expectTop(_ why: String) {
        let v = visible
        if abs(v.minY) > 0.5 { issue("viewport-jump", "\(why): expected the very top (y 0) but the viewport is at y \(String(format: "%.1f", v.minY))") }
        if let f = viewportFragments().first {
            if f.offset != 0 { issue("coverage", "\(why): at the top but the first laid-out paragraph starts at offset \(f.offset), not 0") }
            else if abs(f.minY - tv.textContainerOrigin.y) > 1 { issue("gap", "\(why): the first line sits at y \(String(format: "%.1f", f.minY)), expected the top inset \(tv.textContainerOrigin.y)") }
        }
        if knob > 0.001 { issue("other", "\(why): at the top but the scroller knob is at \(String(format: "%.4f", knob))") }
    }

    /// 문서 맨 끝에 있는가: 뷰포트 아래 = 문서 높이, 마지막 문단이 화면에 있고 그 아래 빈 띠는 아래 여백뿐, 손잡이 1
    func expectBottom(_ why: String) {
        let v = visible
        let docH = tv.frame.height
        guard docH > v.height + 1 else { return }
        // 문서 높이는 정수 pt, 스크롤 위치는 화면 픽셀(0.5 pt) 격자라 1 pt 까지는 어긋날 수 있다(실측 0.6)
        if abs(v.maxY - docH) > 1 { issue("viewport-jump", "\(why): expected the very end but the viewport bottom is \(String(format: "%.1f", v.maxY)) of document height \(String(format: "%.1f", docH))") }
        guard let last = viewportFragments().last else { return }
        if last.offset + last.length < length { issue("coverage", "\(why): at the end but the last laid-out paragraph ends at offset \(last.offset + last.length) of \(length)") }
        else {
            let band = v.maxY - last.maxY
            let inset = tv.textContainerInset.height
            // 아래 여백(12) + 문서 높이의 정수 올림 + 마지막 줄 조각 높이의 소수 차이까지 3 pt 남짓은 정상이다(실측 12.9…14.9). 줄 하나(24 pt)에 못 미치는 5 pt 를 넘으면 빈 띠
            if band > inset + 5 { issue("gap", "\(why): \(String(format: "%.1f", band)) pt of empty space under the last line (bottom inset is \(inset))") }
            if band < -0.5 { issue("coverage", "\(why): the last line is cut off by \(String(format: "%.1f", -band)) pt at the bottom") }
        }
        if knob < 0.999 { issue("other", "\(why): at the end but the scroller knob is at \(String(format: "%.4f", knob))") }
    }

    /// 한 구간을 픽셀 휠로 굴리며 걸음마다 이동량·레이아웃을, 가끔 거터·잉크를 본다. 걸음당 가장 오래 걸린 시간(ms)을 돌려준다
    @discardableResult
    func wheelRun(_ label: String, steps: Int, by d: CGFloat, restMs: UInt64 = 0, deepEvery: Int = 25) async -> Double {
        let n0 = issues.count
        var worst = 0.0, total = 0.0
        for i in 1...steps {
            let t0 = CFAbsoluteTimeGetCurrent()
            await wheelChecked(d, "\(label) #\(i) (\(Int(d)) pt)")
            let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            worst = max(worst, ms); total += ms
            checkLayout("\(label) #\(i)")
            if i % deepEvery == 0 { checkGutter("\(label) #\(i)"); checkInk("\(label) #\(i)") }
            if restMs > 0 { await settle(restMs) }
            if tooManyIssues(since: n0) { break }
        }
        note(String(format: "%@: %d × %+.0f pt — %.1f ms/step avg, %.1f ms worst", label, steps, d, total / Double(steps), worst))
        // 한 걸음이 100 ms(60 Hz 6프레임)를 넘으면 사용자가 끊김으로 느낀다
        if worst > 100 { issue("stall", String(format: "%@: one wheel step took %.0f ms (avg %.1f ms)", label, worst, total / Double(steps)), snap: false) }
        return worst
    }

    /// 쉬었다가 굴리는 걸음들 (걸음 사이 150 ms) — 크기와 방향을 섞는다
    func restedSteps(_ label: String, _ deltas: [CGFloat] = [-3, -12, -40, -200, -120, 40, 200, -200, -3, 3, -60, 60]) async {
        let n0 = issues.count
        for d in deltas {
            await wheelChecked(d, restMs: 150, "\(label): first wheel after a pause (\(Int(d)) pt)")
            checkAll("\(label): rested wheel \(Int(d))")
            if tooManyIssues(since: n0) { break }
        }
        checkInk("\(label): after rested wheels")
    }
}

extension RealUse {
    @MainActor static let scrollScenarios: [Scenario] = [
        // 픽셀 휠 왕복: 문서 처음에서 짧은 걸음으로 내려갔다가 같은 걸음으로 올라오면 처음으로 돌아와야 한다. 큰 걸음도
        Scenario(name: "scroll-wheel-roundtrip") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "roundtrip.md") }
            ctx.at("⌘↑")
            await ctx.key(.up, [.command]); await ctx.settle(200)
            ctx.expectTop("after ⌘↑"); ctx.checkAll("at the top"); ctx.checkInk("at the top")
            ctx.at("wheel down 240 × 35")
            await ctx.wheelRun("wheel down", steps: 240, by: 35)
            ctx.snap("after-down")
            let mid = ctx.topLine()
            if mid < 100 { ctx.issue("scroll-delta", "240 × 35 pt down from the top only reached line \(mid)") }
            ctx.at("wheel up 240 × 35")
            await ctx.wheelRun("wheel up", steps: 240, by: -35)
            ctx.at("back at the top")
            ctx.expectTop("after the 240-step round trip"); ctx.checkAll("back at the top"); ctx.checkInk("back at the top")
            ctx.at("big steps down 14 × 700")
            var last = ctx.topLine()
            for i in 1...14 {
                await ctx.scrollBy(700); await ctx.settle(0)
                let t = ctx.topLine()
                if t <= last { ctx.issue("scroll-delta", "big step down #\(i): top line went from \(last) to \(t)") }
                last = t
                ctx.checkAll("big step down #\(i)"); ctx.checkInk("big step down #\(i)")
            }
            ctx.at("big steps up 14 × 700")
            for i in 1...14 {
                await ctx.scrollBy(-700); await ctx.settle(0)
                let t = ctx.topLine()
                if t >= last, last > 1 { ctx.issue("scroll-delta", "big step up #\(i): top line went from \(last) to \(t)") }
                last = t
                ctx.checkAll("big step up #\(i)"); ctx.checkInk("big step up #\(i)")
            }
            ctx.expectTop("after the big-step round trip")
            ctx.snap("end")
        },

        // 쉬었다가 굴리는 첫 걸음 (사용자가 스크롤을 시작하는 순간): 끝·줄 이동 뒤·휠로 내려간 뒤 각각, 위쪽은 아직 실측되지 않은 상태
        Scenario(name: "scroll-rested-wheel") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "rested.md") }
            ctx.at("at the end")
            await ctx.key(.down, [.command]); await ctx.settle(300)
            ctx.scrollState("at the end")
            await ctx.restedSteps("at the end")
            ctx.snap("end-rested")
            ctx.at("after go to line 12000")
            ctx.model.jump(toLine: 12000); await ctx.settle(400)
            ctx.scrollState("after go to line")
            await ctx.restedSteps("after go to line 12000")
            ctx.at("after wheeling down")
            await ctx.key(.up, [.command]); await ctx.settle(200)
            await ctx.wheelTo(steps: 12, by: 600)
            await ctx.settle(300)
            await ctx.restedSteps("after wheeling down 7200")
            // 손을 뗐다가 다시: 계속 위로만, 걸음마다 쉼 (딸깍 휠을 천천히 굴리는 것과 같다)
            ctx.at("slow wheel up from the end")
            await ctx.key(.down, [.command]); await ctx.settle(300)
            await ctx.wheelRun("slow wheel up", steps: 30, by: -48, restMs: 90, deepEvery: 10)
            ctx.snap("slow-up")
        },

        // 여러 번 감기는 긴 문단: 추정 높이와 실측 높이가 크게 다르다 — 화면이 튀면 여기서 가장 크게 튄다
        Scenario(name: "scroll-wide-wrap") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.wide, name: "wide-scroll.md") }
            ctx.at("⌘↑")
            await ctx.key(.up, [.command]); await ctx.settle(200)
            ctx.expectTop("after ⌘↑"); ctx.checkAll("at the top"); ctx.checkInk("at the top")
            ctx.at("wheel down 120 × 40")
            await ctx.wheelRun("wheel down", steps: 120, by: 40)
            ctx.at("wheel up 120 × 40")
            await ctx.wheelRun("wheel up", steps: 120, by: -40)
            ctx.expectTop("after the round trip")
            ctx.at("at the end")
            await ctx.key(.down, [.command]); await ctx.settle(300)
            ctx.expectBottom("after ⌘↓"); ctx.checkAll("at the end"); ctx.checkInk("at the end"); ctx.checkCaretVisible("after ⌘↓")
            ctx.snap("end")
            await ctx.restedSteps("at the end")
            ctx.at("continuous wheel up from the end")
            await ctx.key(.down, [.command]); await ctx.settle(300)
            await ctx.wheelRun("wheel up from the end", steps: 80, by: -45)
            ctx.at("after go to line 2000")
            ctx.model.jump(toLine: 2000); await ctx.settle(400)
            ctx.checkCaretVisible("after go to line 2000"); ctx.checkAll("after go to line 2000")
            await ctx.restedSteps("after go to line 2000")
            ctx.at("slow wheel up")
            await ctx.wheelRun("slow wheel up", steps: 24, by: -52, restMs: 90, deepEvery: 8)
            ctx.snap("slow-up")
        },

        // 줄 단위 휠(딸깍 휠): 방향이 맞고, 같은 수만큼 내렸다 올리면 제자리여야 한다
        Scenario(name: "scroll-line-wheel") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "linewheel.md") }
            ctx.model.jump(toLine: 8000); await ctx.settle(400)
            ctx.at("line wheel")
            var net: CGFloat = 0
            var perLine: [CGFloat] = []
            for n: Int32 in [1, 1, 3, -3, -1, -1, 5, -5, -2, 2] {
                let a = ctx.anchor(nearScreenY: n > 0 ? 320 : 100)
                await ctx.wheelLines(n); await ctx.settle(250)
                guard let m = ctx.moved(since: a) else { ctx.issue("scroll-delta", "line wheel \(n): the reference paragraph left the screen (more than \(Int(ctx.visible.height / 2)) pt for \(abs(n)) notches?)"); continue }
                if abs(m) < 1 || (m > 0) != (n > 0) { ctx.issue("scroll-delta", "line wheel \(n): content moved \(String(format: "%.1f", m)) pt (wrong direction or nothing)") }
                net += m
                perLine.append(m / CGFloat(n))
                ctx.checkAll("line wheel \(n)")
            }
            ctx.note("line wheel: per-notch movement " + perLine.map { String(format: "%.1f", $0) }.joined(separator: ", "))
            if abs(net) > 1.5 { ctx.issue("scroll-delta", "line wheel: equal notches down and up left the content \(String(format: "%.1f", net)) pt away from where it started") }
            ctx.checkInk("after line wheels")
            // 끝에서 위로 딸깍딸깍 (걸음마다 쉼이 있다 — 위쪽은 아직 실측 전)
            ctx.at("line wheel up from the end")
            await ctx.key(.down, [.command]); await ctx.settle(300)
            var ups: [CGFloat] = []
            for i in 1...10 {
                let a = ctx.anchor(nearScreenY: 120)
                await ctx.wheelLines(-1); await ctx.settle(150)
                if let m = ctx.moved(since: a) { ups.append(m) } else { ctx.issue("scroll-delta", "notch up #\(i) from the end: the reference paragraph left the screen") }
                ctx.checkAll("notch up #\(i)")
            }
            ctx.note("notches up from the end: " + ups.map { String(format: "%.1f", $0) }.joined(separator: ", "))
            if let mn = ups.min(), let mx = ups.max(), mx - mn > 1.5 { ctx.issue("scroll-delta", "one notch up from the end moved the content by \(String(format: "%.1f", -mx))…\(String(format: "%.1f", -mn)) pt — the same notch should always move the same amount") }
            ctx.snap("end")
        },

        // 트랙패드 쓸기 + 관성 (위상 없는 픽셀 이벤트 흐름 — swipe 주석)
        Scenario(name: "scroll-flick") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "flick.md") }
            await ctx.key(.up, [.command]); await ctx.settle(200)
            ctx.at("small swipe down")
            var a = ctx.anchor(nearScreenY: 380)
            var sent = await ctx.swipe(total: 320)
            ctx.checkContentMoved(anchor: a, expected: sent, tolerance: 1, "swipe down \(Int(sent))"); ctx.checkAll("swipe down 320"); ctx.checkInk("swipe down 320")
            ctx.at("small swipe up")
            a = ctx.anchor(nearScreenY: 40)
            sent = await ctx.swipe(total: -320)
            ctx.checkContentMoved(anchor: a, expected: sent, tolerance: 1, "swipe up \(Int(-sent))"); ctx.checkAll("swipe up 320")
            ctx.expectTop("after swiping down and up 320")
            ctx.at("big swipes down")
            var last = ctx.topLine()
            for i in 1...6 {
                await ctx.swipe(total: 3200)
                let t = ctx.topLine()
                if t <= last { ctx.issue("scroll-delta", "swipe down #\(i): top line went from \(last) to \(t)") }
                last = t
                ctx.checkAll("swipe down #\(i)"); ctx.checkInk("swipe down #\(i)")
            }
            ctx.snap("after-swipes-down")
            ctx.at("big swipes up")
            for i in 1...6 {
                await ctx.swipe(total: -3200)
                ctx.checkAll("swipe up #\(i)"); ctx.checkInk("swipe up #\(i)")
            }
            // 같은 양만큼 올라왔으니 처음이어야 한다 (모자라거나 남으면 올라오는 길의 이동량이 내려간 길과 달랐다는 뜻)
            ctx.expectTop("after 6 swipes down and 6 equal swipes up")
            ctx.at("swipe up past the top")
            await ctx.swipe(total: -900); await ctx.settle(300)
            ctx.expectTop("after swiping past the top"); ctx.checkAll("after swiping past the top")
            ctx.at("swipe down past the end")
            await ctx.key(.down, [.command]); await ctx.settle(300)
            await ctx.swipe(total: 900); await ctx.settle(300)
            ctx.expectBottom("after swiping past the end"); ctx.checkAll("after swiping past the end"); ctx.checkInk("after swiping past the end")
            // 끝에서 위로: 쉬었다가 쓸기를 시작하는 순간이 가장 튀기 쉬운 곳 (위쪽은 실측 전)
            ctx.at("swipes up from the end")
            for i in 1...5 {
                await ctx.settle(220)
                a = ctx.anchor(nearScreenY: 40)
                sent = await ctx.swipe(total: -300)
                ctx.checkContentMoved(anchor: a, expected: sent, tolerance: 1, "swipe up \(Int(-sent)) from the end #\(i)"); ctx.checkAll("swipe up from the end #\(i)")
            }
            ctx.at("swipe back down to the end")
            for _ in 1...3 { await ctx.swipe(total: 900) }
            await ctx.settle(200)
            ctx.expectBottom("after swiping back to the end"); ctx.checkInk("back at the end")
            ctx.snap("end")
        },

        // Page Down / Page Up: 겹치는 줄이 남고, 같은 수만큼 오르내리면 제자리
        Scenario(name: "scroll-page-keys") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "pagekeys.md") }
            await ctx.key(.up, [.command]); await ctx.settle(200)
            ctx.at("Page Down × 8 from the top")
            var amounts: [CGFloat] = []
            for i in 1...8 {
                // AppKit 의 Page Down 은 화면 높이에서 겹침 20 pt 를 뺀 만큼 간다(줄 하나에 못 미친다) — 화면에 걸쳐 있던 맨 아래 문단이 맨 위에 남는지로 잰다
                let a = ctx.edgeAnchor(bottom: true)
                let top0 = ctx.topLine()
                await ctx.key(.pageDown); await ctx.settle(300)
                if let m = ctx.moved(since: a) { amounts.append(m) } else { ctx.issue("scroll-delta", "Page Down #\(i): the paragraph at the bottom edge of the previous page is not on screen any more (text was skipped)") }
                if ctx.topLine() <= top0 { ctx.issue("scroll-delta", "Page Down #\(i): top line stayed at \(top0)") }
                ctx.checkAll("Page Down #\(i)"); if i % 4 == 0 { ctx.checkInk("Page Down #\(i)") }
            }
            ctx.note("Page Down amounts: " + amounts.map { String(format: "%.1f", $0) }.joined(separator: ", ") + " (viewport \(Int(ctx.visible.height)))")
            if let mn = amounts.min(), let mx = amounts.max(), mx - mn > 2 { ctx.issue("scroll-delta", "Page Down moved by \(String(format: "%.1f", mn))…\(String(format: "%.1f", mx)) pt — pages should be the same size") }
            ctx.at("Page Up × 8 back")
            for i in 1...8 {
                await ctx.key(.pageUp); await ctx.settle(300)
                ctx.checkAll("Page Up #\(i)"); if i % 4 == 0 { ctx.checkInk("Page Up #\(i)") }
            }
            ctx.expectTop("after 8 × Page Down and 8 × Page Up")
            // 가운데에서 위로 먼저 (위쪽은 아직 실측 전)
            ctx.at("Page Up × 6 from line 12000")
            ctx.model.jump(toLine: 12000); await ctx.settle(400)
            let line0 = ctx.topLine()
            let ref = ctx.anchor()
            var ups: [CGFloat] = []
            for i in 1...6 {
                let a = ctx.edgeAnchor(bottom: false)
                await ctx.key(.pageUp); await ctx.settle(300)
                if let m = ctx.moved(since: a) { ups.append(m) } else { ctx.issue("scroll-delta", "Page Up #\(i) from line 12000: the paragraph at the top edge of the previous page is not on screen any more (text was skipped)") }
                ctx.checkAll("Page Up #\(i) from the middle"); if i % 3 == 0 { ctx.checkInk("Page Up #\(i) from the middle") }
            }
            ctx.note("Page Up amounts: " + ups.map { String(format: "%.1f", $0) }.joined(separator: ", "))
            if let mn = ups.min(), let mx = ups.max(), mx - mn > 2 { ctx.issue("scroll-delta", "Page Up moved by \(String(format: "%.1f", -mx))…\(String(format: "%.1f", -mn)) pt — pages should be the same size") }
            ctx.at("Page Down × 6 back")
            for i in 1...6 {
                await ctx.key(.pageDown); await ctx.settle(300)
                ctx.checkAll("Page Down #\(i) back")
            }
            if let m = ctx.moved(since: ref) {
                if abs(m) > 2 { ctx.issue("scroll-delta", "6 × Page Up then 6 × Page Down from line \(line0): the content ended \(String(format: "%.1f", m)) pt away from where it started") }
            } else { ctx.issue("scroll-delta", "6 × Page Up then 6 × Page Down from line \(line0) ended at line \(ctx.topLine()) — the starting paragraph is not on screen") }
            // ⌥Page Down/Up: 캐럿도 함께 움직인다
            ctx.at("⌥Page Down / ⌥Page Up")
            for i in 1...4 {
                await ctx.key(.pageDown, [.option]); await ctx.settle(300)
                ctx.checkCaretVisible("⌥Page Down #\(i)"); ctx.checkAll("⌥Page Down #\(i)")
            }
            for i in 1...6 {
                await ctx.key(.pageUp, [.option]); await ctx.settle(300)
                ctx.checkCaretVisible("⌥Page Up #\(i)"); ctx.checkAll("⌥Page Up #\(i)")
            }
            ctx.checkInk("after ⌥Page keys")
            ctx.snap("end")
        },

        // 문서 처음·끝·줄로 이동 뒤의 상태
        Scenario(name: "scroll-ends") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "ends.md") }
            ctx.at("⌘↓")
            await ctx.key(.down, [.command]); await ctx.settle(300)
            ctx.expectBottom("after ⌘↓"); ctx.checkCaretVisible("after ⌘↓"); ctx.checkAll("after ⌘↓"); ctx.checkInk("after ⌘↓")
            if ctx.caret != ctx.length { ctx.issue("selection", "⌘↓ left the caret at \(ctx.caret), not the end \(ctx.length)") }
            ctx.snap("cmd-down")
            ctx.at("wheel down at the end")
            var a = ctx.anchor()
            await ctx.scrollBy(300); await ctx.settle(150)
            ctx.checkContentMoved(anchor: a, expected: 0, tolerance: 0.5, "wheel down at the very end"); ctx.expectBottom("after wheeling down at the end")
            ctx.at("⌘↑")
            await ctx.key(.up, [.command]); await ctx.settle(300)
            ctx.expectTop("after ⌘↑"); ctx.checkCaretVisible("after ⌘↑"); ctx.checkAll("after ⌘↑"); ctx.checkInk("after ⌘↑")
            ctx.at("wheel up at the top")
            a = ctx.anchor()
            await ctx.scrollBy(-300); await ctx.settle(150)
            ctx.checkContentMoved(anchor: a, expected: 0, tolerance: 0.5, "wheel up at the very top"); ctx.expectTop("after wheeling up at the top")
            ctx.at("⌃⌘E")
            let handled = await ctx.shortcut("e", [.command, .control])
            await ctx.settle(400)
            if !handled { ctx.note("⌃⌘E was not handled by the menu (key equivalents inactive) — using the model command") ; ctx.model.goToEnd(); await ctx.settle(400) }
            ctx.expectBottom("after ⌃⌘E"); ctx.checkCaretVisible("after ⌃⌘E"); ctx.checkAll("after ⌃⌘E"); ctx.checkInk("after ⌃⌘E")
            if ctx.caret != ctx.length { ctx.issue("selection", "⌃⌘E left the caret at \(ctx.caret), not the end \(ctx.length)") }
            // 줄로 이동: 캐럿 줄이 화면 위에서 1/3 쯤 (처음·끝 근처는 그만큼 못 간다)
            let count = LineIndex(nsString: ctx.text).lineCount
            for n in [1, 2, 37, 12000, 20001, count - 1, count, 5000] {
                ctx.at("go to line \(n)")
                ctx.model.jump(toLine: n); await ctx.settle(450)
                let got = LineIndex(nsString: ctx.text).lineNumber(forUTF16Offset: ctx.caret)
                if got != n { ctx.issue("selection", "go to line \(n) put the caret on line \(got)") }
                ctx.checkCaretVisible("go to line \(n)"); ctx.checkAll("go to line \(n)"); ctx.checkInk("go to line \(n)")
                let v = ctx.visible
                if let r = ctx.tv.caretRect(at: ctx.caret), v.minY > 1, v.maxY < ctx.tv.frame.height - 1 {
                    let y = r.minY - v.minY
                    if abs(y - v.height / 3) > ctx.lineHeight { ctx.issue("viewport-jump", "go to line \(n): the caret line is at screen y \(String(format: "%.1f", y)), expected about a third of the way down (\(String(format: "%.1f", v.height / 3)))") }
                }
                if n == count { ctx.expectBottom("after go to the last line") }
                if n == 1 { ctx.expectTop("after go to line 1") }
            }
            ctx.snap("goto-5000")
            // Home / End: 캐럿은 두고 화면만
            ctx.at("End key")
            let caret0 = ctx.caret
            await ctx.key(.end); await ctx.settle(400)
            ctx.expectBottom("after End"); ctx.checkAll("after End"); ctx.checkInk("after End")
            ctx.at("Home key")
            await ctx.key(.home); await ctx.settle(400)
            ctx.expectTop("after Home"); ctx.checkAll("after Home"); ctx.checkInk("after Home")
            if ctx.caret != caret0 { ctx.issue("selection", "Home/End moved the caret from \(caret0) to \(ctx.caret) (they should only scroll)") }
            ctx.snap("end")
        },

        // 먼 곳에서 문서 끝으로 점프: 어떤 상태에서 가도 마지막 줄 아래에 빈 띠가 없어야 한다 (끝 부근의 추정 높이가 실측으로 바뀌며 문서가 줄어든다)
        Scenario(name: "scroll-jump-end") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "jumpend.md") }
            let count = LineIndex(nsString: ctx.text).lineCount
            @MainActor func arrive(_ how: String, caretFollows: Bool = true, _ go: @MainActor () async -> Void) async {
                ctx.at(how)
                await go(); await ctx.settle(350)
                ctx.scrollState(how)
                ctx.expectBottom(how); ctx.checkAll(how); ctx.checkInk(how)
                if caretFollows { ctx.checkCaretVisible(how) }
                // 끝에 닿은 뒤의 첫 휠: 위치가 끝을 넘어 있었다면 여기서 그만큼 튄다
                await ctx.wheelChecked(-30, restMs: 120, "\(how): first wheel up")
                await ctx.wheelChecked(30, "\(how): wheel back down")
                ctx.expectBottom("\(how): after wheeling back")
            }
            await arrive("⌘↓ right after opening") { await ctx.key(.down, [.command]) }
            ctx.model.jump(toLine: 12000); await ctx.settle(450)
            await arrive("⌘↓ after go to line 12000") { await ctx.key(.down, [.command]) }
            ctx.model.jump(toLine: count * 3 / 4); await ctx.settle(450)
            await ctx.wheelTo(steps: 150, by: -800)
            await arrive("⌘↓ after wheeling up from 3/4") { await ctx.key(.down, [.command]) }
            ctx.snap("after-wheel-up-then-cmd-down")
            await ctx.key(.up, [.command]); await ctx.settle(300)
            await ctx.wheelTo(steps: 50, by: 800)
            await arrive("⌃⌘E after wheeling down from the top") { ctx.model.goToEnd() }
            ctx.model.jump(toLine: count / 3); await ctx.settle(450)
            await ctx.wheelTo(steps: 120, by: -700)
            await arrive("go to the last line after wheeling up from 1/3") { ctx.model.jump(toLine: count) }
            ctx.model.jump(toLine: count / 2); await ctx.settle(450)
            await ctx.wheelTo(steps: 100, by: -900)
            await arrive("End key after wheeling up from the middle", caretFollows: false) { await ctx.key(.end) }
            // 한 번도 안 본 끝 부분으로 휠만 굴려 들어간다 (새 문서 — 끝 300줄은 추정 높이)
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "jumpend2.md") }
            ctx.model.jump(toLine: count - 300); await ctx.settle(450)
            // 끝에 닿은 뒤에도 몇 걸음 더 굴린다: 마지막 배치에서 문서가 조금 늘면(추정 → 실측) 그만큼 더 내려갈 수 있다 — 사용자는 멈출 때까지 굴린다
            await arrive("wheel down into the unseen end", caretFollows: false) { await ctx.wheelTo(steps: 40, by: 450); await ctx.settle(100); await ctx.wheelTo(steps: 4, by: 450) }
            await ctx.withRelaxedStalls { await ctx.open(.wide, name: "jumpend-wide.md") }
            ctx.model.jump(toLine: 3900); await ctx.settle(450)
            await arrive("wide: wheel down into the unseen end", caretFollows: false) { await ctx.wheelTo(steps: 60, by: 450); await ctx.settle(100); await ctx.wheelTo(steps: 4, by: 450) }
            ctx.model.jump(toLine: 1500); await ctx.settle(450)
            await ctx.wheelTo(steps: 60, by: -700)
            await arrive("wide: ⌘↓ after wheeling up from line 1500") { await ctx.key(.down, [.command]) }
            ctx.snap("end")
        },

        // 가운데로 스크롤 → 그 자리에 입력 → 다시 스크롤. 그리고 위쪽을 한 번도 안 본 채 끝에서 입력 → 위로
        Scenario(name: "scroll-edit-then-scroll") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "editscroll.md") }
            await ctx.key(.up, [.command]); await ctx.settle(200)
            await ctx.wheelTo(steps: 20, by: 500)
            await ctx.settle(300)
            ctx.at("click and type in the middle")
            guard let target = ctx.anchor() else { ctx.issue("other", "no paragraph on screen to click"); return }
            await ctx.click(offset: target.offset)
            if ctx.caret != target.offset { ctx.issue("other", "clicked the start of the paragraph at offset \(target.offset) but the caret went to \(ctx.caret)") }
            await ctx.type("scroll then type 스크롤 뒤 입력 ")
            await ctx.composeHangul("한글 조합")
            await ctx.key(.returnKey)
            await ctx.type("second line")
            await ctx.settle(60)
            // 거터는 줄 인덱스(편집 뒤 250 ms 지연 갱신)로 번호를 매긴다 — 그 사이의 번호 어긋남은 입력 영역의 문제라 여기서는 갱신 뒤에 본다(아래 'wheel after the index refresh')
            ctx.checkCaretVisible("typing after scrolling"); ctx.checkLayout("typing after scrolling")
            // 캐럿 문단 머리에 입력했으므로 그 문단의 시작 오프셋은 그대로다 — 화면에서 움직이면 안 된다
            if let m = ctx.moved(since: target), abs(m) > 1 { ctx.issue("viewport-jump", "typing in the middle moved the paragraph being typed in by \(String(format: "%.1f", m)) pt on screen") }
            ctx.at("wheel right after typing")
            await ctx.wheelChecked(-150, "wheel up right after typing")
            await ctx.wheelChecked(-150, "wheel up right after typing (2)")
            await ctx.wheelChecked(300, "wheel down right after typing")
            ctx.checkLayout("wheel right after typing"); ctx.checkInk("wheel right after typing")
            ctx.at("wheel after the index refresh")
            await ctx.settle(500)   // 줄 인덱스 갱신(250 ms)·접기 재스캔이 끝난 뒤
            ctx.checkGutter("after the index refresh")
            await ctx.restedSteps("after typing in the middle", [-40, -200, 200, 40, -120, 120])
            ctx.at("scroll away and back")
            let home = ctx.anchor()
            await ctx.wheelRun("away", steps: 40, by: 75)
            await ctx.wheelRun("back", steps: 40, by: -75)
            if let m = ctx.moved(since: home) {
                if abs(m) > 1.5 { ctx.issue("scroll-delta", "40 × 75 pt away and back: the content ended \(String(format: "%.1f", m)) pt from where it started") }
            } else { ctx.issue("scroll-delta", "40 × 75 pt away and back: the starting paragraph is not on screen (top line \(ctx.topLine()))") }
            ctx.snap("middle")
            // 위쪽을 한 번도 안 본 상태: 끝으로 → 입력 → 위로
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "editscroll-end.md") }
            ctx.at("type at the end")
            await ctx.key(.down, [.command]); await ctx.settle(200)
            let e0 = ctx.anchor(nearScreenY: 60)
            await ctx.type("typed at the end 끝에 입력 ")
            await ctx.composeHangul("마지막 줄")
            await ctx.key(.returnKey); await ctx.key(.returnKey)
            await ctx.type("one more")
            await ctx.settle(60)
            ctx.checkCaretVisible("typing at the end"); ctx.checkLayout("typing at the end"); ctx.expectBottom("after typing at the end")
            // 두 줄이 늘었으니 내용은 두 줄만큼 위로 올라가야 한다. 마지막 줄에 한글이 들어가 그 줄이 1.3 pt 높아지고 끝의 여백 올림이 2 pt 까지 달라질 수 있다 → ±4
            if let m = ctx.moved(since: e0), abs(m - 2 * ctx.lineHeight) > 4 { ctx.issue("viewport-jump", "two new lines at the end moved the content by \(String(format: "%.1f", m)) pt, expected two lines (\(String(format: "%.1f", 2 * ctx.lineHeight)))") }
            ctx.at("first wheel up after typing at the end")
            await ctx.wheelChecked(-200, restMs: 150, "first wheel up after typing at the end")
            await ctx.settle(400)   // 줄 인덱스 갱신 뒤 (거터)
            ctx.checkAll("first wheel up after typing at the end"); ctx.checkInk("first wheel up after typing at the end")
            ctx.at("wheel up into unseen text")
            await ctx.wheelRun("wheel up into unseen text", steps: 60, by: -50)
            ctx.at("wheel back to the end")
            await ctx.wheelRun("wheel back down", steps: 70, by: 50)
            ctx.expectBottom("after wheeling back to the end"); ctx.checkInk("back at the end")
            ctx.snap("end")
        },

        // 방향키로 화면 가장자리를 넘어갈 때: 한 줄씩만 밀려야 한다
        Scenario(name: "scroll-arrow-keys") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "arrows.md") }
            // AppKit(TextKit 2)은 캐럿이 화면 밖으로 나가는 순간 한 줄만 밀지 않고 캐럿 줄을 화면 가운데쯤으로 다시 맞춘다(실측: 가장자리를 넘을 때 약 220 pt).
            // 그래서 걸음마다의 요구는: 캐럿 줄이 온전히 보이고, 화면이 움직였다면 가는 방향으로만 반 화면(+한 줄) 이내, 가장자리를 넘지 않은 걸음에서는 움직이지 않는다
            @MainActor func walk(_ key: RealUseContext.Key, _ count: Int, _ label: String) async {
                let n0 = ctx.issues.count
                let up = key == .up
                let lh = ctx.lineHeight
                var scrolled = 0, landings: [Int] = []
                for i in 1...count {
                    let v0 = ctx.visible
                    let before = ctx.tv.caretRect(at: ctx.caret).map { $0.minY - v0.minY }
                    let a = ctx.anchor(nearScreenY: up ? 60 : v0.height - 90)
                    await ctx.key(key); await ctx.settle(0)
                    let v = ctx.visible
                    guard let r = ctx.tv.caretRect(at: ctx.caret) else { continue }
                    let cy = r.minY - v.minY
                    if cy < -0.75 || cy + r.height > v.height + 0.75 {
                        ctx.issue("caret-hidden", "\(label) #\(i): after the arrow key the caret line is at screen y \(String(format: "%.1f", cy))…\(String(format: "%.1f", cy + r.height)) of a \(Int(v.height)) pt viewport — not visible")
                    }
                    if let m = ctx.moved(since: a), abs(m) > 0.5 {
                        scrolled += 1; landings.append(Int(cy))
                        // 가장자리에서 먼 캐럿(이동 전 화면 안쪽 두 줄 밖)이 움직였는데 화면이 밀렸다 / 반대 방향으로 밀렸다 / 반 화면 넘게 밀렸다
                        let nearEdge = before.map { up ? $0 < 2 * lh : $0 > v0.height - 3 * lh } ?? true
                        if !nearEdge || (up ? m > 0.5 : m < -0.5) || abs(m) > v0.height / 2 + 2 * lh {
                            ctx.issue("viewport-jump", "\(label) #\(i): one arrow key moved the content by \(String(format: "%.1f", m)) pt on screen (caret was at y \(before.map { String(Int($0)) } ?? "?"), now \(Int(cy)); half a viewport is \(Int(v0.height / 2)))")
                        }
                    }
                    ctx.checkLayout("\(label) #\(i)")
                    if i % 20 == 0 { ctx.checkGutter("\(label) #\(i)"); ctx.checkInk("\(label) #\(i)") }
                    if ctx.tooManyIssues(since: n0) { break }
                }
                ctx.note("\(label): \(scrolled) of \(count) presses scrolled the view; the caret landed at screen y \(landings)")
            }
            ctx.at("↑ × 90 from the end")
            await ctx.key(.down, [.command]); await ctx.settle(300)
            await walk(.up, 90, "↑ from the end")
            ctx.snap("up-from-end")
            ctx.at("↓ × 110 back to the end")
            await walk(.down, 110, "↓ back to the end")
            ctx.expectBottom("after walking back to the end")
            ctx.at("↑ × 60 from line 9000")
            ctx.model.jump(toLine: 9000); await ctx.settle(400)
            await walk(.up, 60, "↑ from line 9000")
            // 검색 강조는 캐럿만 옮겨도(스크롤 없이) 남아 있어야 한다
            ctx.at("search highlights while moving the caret")
            ctx.model.jump(toLine: 3000); await ctx.settle(450)
            ctx.model.searchQuery = "e"; ctx.model.runSearch(keepScroll: true); await ctx.settle(900)
            let lit = ctx.matchHighlightPixels()
            if lit < 40 { ctx.note("search highlights not measurable (\(lit) px) — skipped") } else {
                for i in 1...6 {
                    await ctx.key(i <= 3 ? .down : .up); await ctx.settle(0)
                    let now = ctx.matchHighlightPixels()
                    // 캐럿 줄의 강조는 현재 줄 띠와 섞여 색이 달라진다 → 한 줄 몫(전체의 1/4 이하)은 줄 수 있다
                    if now < lit * 6 / 10 { ctx.issue("blank", "search highlights: \(lit) highlighted px before, \(now) after arrow key #\(i) — the highlights were erased without scrolling"); break }
                    ctx.checkLayout("arrow key #\(i) with search highlights")
                }
            }
            ctx.model.searchQuery = ""; ctx.model.runSearch(); await ctx.settle(300)
            ctx.at("↓ × 90 from there")
            await walk(.down, 90, "↓ from line ~8940")
            ctx.snap("end")
        },

        // 스크롤바 손잡이: 스크롤 방향과 반대로 튀지 않고, 위치와 대략 비례한다
        Scenario(name: "scroll-knob") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "knob.md") }
            await ctx.key(.up, [.command]); await ctx.settle(300)
            let count = LineIndex(nsString: ctx.text).lineCount
            @MainActor func run(_ label: String, steps: Int, by d: CGFloat) async {
                var last = ctx.knob, back = 0.0, fwd = 0.0, backAt = 0, fwdAt = 0
                let sign: Double = d > 0 ? 1 : -1
                for i in 1...steps {
                    await ctx.scrollBy(d); await ctx.settle(0)
                    let k = ctx.knob
                    let dk = (k - last) * sign
                    if dk < back { back = dk; backAt = i }
                    if dk > fwd { fwd = dk; fwdAt = i }
                    last = k
                }
                let track = Double(ctx.scroll.verticalScroller?.bounds.height ?? ctx.visible.height)
                ctx.note(String(format: "%@: %d × %+.0f pt — knob ended at %.4f; worst step against the scroll direction %.4f (%.1f pt of the %.0f pt track, step %d), worst jump along it %.4f (%.1f pt, step %d)",
                                label, steps, d, last, back, -back * track, track, backAt, fwd, fwd * track, fwdAt))
                // 손잡이가 스크롤 방향과 반대로 3 pt 넘게 움직이면 눈에 띈다
                if -back * track > 3 { ctx.issue("other", String(format: "%@: the scroller knob jumped %.1f pt against the scroll direction at step %d (knob %.4f)", label, -back * track, backAt, back)) }
                // 한 걸음에 손잡이가 트랙의 3% 넘게 뛰면 튄 것
                if fwd > 0.03 { ctx.issue("other", String(format: "%@: the scroller knob jumped %.1f pt along the track in one step (step %d)", label, fwd * track, fwdAt)) }
            }
            ctx.at("knob while wheeling down")
            await run("wheel down", steps: 250, by: 800)
            ctx.at("knob while wheeling up")
            await run("wheel up", steps: 250, by: -800)
            ctx.expectTop("after the knob round trip")
            ctx.at("knob after go to line")
            for n in [count / 4, count / 2, count * 3 / 4] {
                ctx.model.jump(toLine: n); await ctx.settle(450)
                let want = Double(n) / Double(count)
                if abs(ctx.knob - want) > 0.06 { ctx.issue("other", String(format: "go to line %d of %d: the scroller knob is at %.3f, expected about %.3f", n, count, ctx.knob, want)) }
                ctx.note(String(format: "line %d/%d → knob %.4f (line ratio %.4f)", n, count, ctx.knob, want))
            }
            ctx.at("knob from the middle upward")
            await run("wheel up from 3/4", steps: 150, by: -800)
            ctx.at("knob at the end")
            await ctx.key(.down, [.command]); await ctx.settle(300)
            ctx.expectBottom("after ⌘↓")
            await run("wheel up from the end", steps: 150, by: -800)
            ctx.snap("end")
        },

        // 4 MB 로그: 줄바꿈 끔(가로 스크롤)과 켬 각각 — 이동량·정지·처음과 끝
        Scenario(name: "scroll-log") { ctx in
            ctx.logWindowState()
            let wrap0 = ctx.model.wordWrap
            ctx.model.wordWrap = false
            await ctx.settle(200)
            // 줄바꿈 끔 + 큰 파일: 여는 데 걸리는 시간을 직접 잰다 (정지 감시는 50 ms 마다 쌓인 핑을 전부 보고해 보고서를 덮으므로 이 구간은 꺼 둔다)
            ctx.at("no wrap: open 4 MB")
            let t0 = CFAbsoluteTimeGetCurrent()
            await ctx.withRelaxedStalls(120_000) { await ctx.open(.log, name: "scroll.log") }
            let openMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000 - 700   // open 의 고정 기다림 700 ms 제외 (말뭉치 생성 포함)
            ctx.note(String(format: "no wrap: opening the 4 MB log took %.0f ms (incl. writing the corpus)", openMs))
            if openMs > 2500 { ctx.issue("stall", String(format: "no wrap: opening a 4 MB log blocked the app for about %.1f s (with word wrap on the same file opens in well under a second)", openMs / 1000), snap: false) }
            ctx.at("no wrap: ⌘↑")
            await ctx.key(.up, [.command]); await ctx.settle(300)
            ctx.expectTop("no wrap: after ⌘↑"); ctx.checkAll("no wrap: at the top"); ctx.checkInk("no wrap: at the top")
            ctx.at("no wrap: wheel down")
            await ctx.withRelaxedStalls(120_000) { _ = await ctx.wheelRun("no wrap: wheel down", steps: 60, by: 60) }
            if abs(ctx.visible.minX) > 0.5 { ctx.issue("viewport-jump", "no wrap: vertical wheeling moved the view sideways to x \(String(format: "%.1f", ctx.visible.minX))") }
            ctx.at("no wrap: wheel up")
            await ctx.withRelaxedStalls(120_000) { _ = await ctx.wheelRun("no wrap: wheel up", steps: 60, by: -60) }
            ctx.expectTop("no wrap: after the round trip")
            ctx.at("no wrap: fast wheel")
            var worstFast = 0.0
            await ctx.withRelaxedStalls(120_000) {
                for i in 1...40 {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    await ctx.scrollBy(1400); await ctx.settle(0)
                    worstFast = max(worstFast, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
                    if i % 10 == 0 { ctx.checkAll("no wrap: fast wheel #\(i)"); ctx.checkInk("no wrap: fast wheel #\(i)") }
                }
            }
            ctx.note(String(format: "no wrap: 40 × 1400 pt — worst step %.1f ms", worstFast))
            if worstFast > 100 { ctx.issue("stall", String(format: "no wrap: one 1400 pt wheel step took %.0f ms", worstFast), snap: false) }
            ctx.at("no wrap: ⌘↓")
            let tEnd = CFAbsoluteTimeGetCurrent()
            await ctx.withRelaxedStalls(120_000) { await ctx.key(.down, [.command]); await ctx.settle(400) }
            let endMs = (CFAbsoluteTimeGetCurrent() - tEnd) * 1000 - 400
            if endMs > 500 { ctx.issue("stall", String(format: "no wrap: ⌘↓ in the 4 MB log took %.1f s", endMs / 1000), snap: false) }
            ctx.checkCaretVisible("no wrap: after ⌘↓"); ctx.checkAll("no wrap: after ⌘↓"); ctx.checkInk("no wrap: after ⌘↓")
            ctx.snap("nowrap-end")
            await ctx.withRelaxedStalls(120_000) { await ctx.restedSteps("no wrap: at the end", [-40, -200, 200, -120, 60]) }
            ctx.at("no wrap: ⌘↑ again")
            await ctx.withRelaxedStalls(120_000) { await ctx.key(.up, [.command]); await ctx.settle(400) }
            ctx.expectTop("no wrap: after ⌘↑ from the end")
            if abs(ctx.visible.minX) > 0.5 { ctx.issue("viewport-jump", "no wrap: after ⌘↑ the view is still scrolled sideways (x \(String(format: "%.1f", ctx.visible.minX)))") }
            // 줄바꿈 켬
            await ctx.withRelaxedStalls(120_000) { ctx.model.wordWrap = true; await ctx.settle(600) }
            ctx.at("wrap: at the top")
            await ctx.key(.up, [.command]); await ctx.settle(300)
            ctx.expectTop("wrap: after ⌘↑"); ctx.checkAll("wrap: at the top"); ctx.checkInk("wrap: at the top")
            ctx.at("wrap: wheel down")
            await ctx.wheelRun("wrap: wheel down", steps: 120, by: 60)
            ctx.at("wrap: wheel up")
            await ctx.wheelRun("wrap: wheel up", steps: 120, by: -60)
            ctx.expectTop("wrap: after the round trip")
            ctx.at("wrap: ⌘↓")
            await ctx.key(.down, [.command]); await ctx.settle(400)
            ctx.expectBottom("wrap: after ⌘↓"); ctx.checkCaretVisible("wrap: after ⌘↓"); ctx.checkAll("wrap: after ⌘↓"); ctx.checkInk("wrap: after ⌘↓")
            await ctx.restedSteps("wrap: at the end")
            ctx.at("wrap: wheel up from the end")
            await ctx.wheelRun("wrap: wheel up from the end", steps: 100, by: -60)
            ctx.snap("wrap-up-from-end")
            ctx.model.wordWrap = wrap0
            await ctx.settle(300)
        },

        // 접힌 영역(높이 0 조각)이 있는 문서에서의 스크롤
        Scenario(name: "scroll-folded") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "folded.md") }
            await ctx.settle(900)   // 접기 후보 스캔(줄 인덱스 발행 뒤 백그라운드)
            ctx.at("fold all")
            await ctx.key(.up, [.command]); await ctx.settle(200)
            await ctx.withRelaxedStalls { ctx.model.send(.foldAll); await ctx.settle(600) }
            guard ctx.tv.hasFolds?() == true else { ctx.issue("other", "Fold All folded nothing in the notes corpus"); return }
            ctx.scrollState("folded")
            ctx.checkAll("after Fold All"); ctx.checkInk("after Fold All")
            ctx.snap("folded-top")
            ctx.at("folded: wheel down")
            await ctx.wheelRun("folded: wheel down", steps: 100, by: 40, deepEvery: 10)
            ctx.at("folded: rested wheels")
            await ctx.restedSteps("folded: in the middle")
            ctx.at("folded: wheel up")
            await ctx.wheelRun("folded: wheel up", steps: 100, by: -40, deepEvery: 10)
            ctx.expectTop("folded: after the round trip")
            ctx.at("folded: End key")
            await ctx.key(.end); await ctx.settle(400)
            ctx.expectBottom("folded: after End"); ctx.checkAll("folded: after End"); ctx.checkInk("folded: after End")
            ctx.snap("folded-end")
            await ctx.restedSteps("folded: at the end")
            ctx.at("folded: wheel up from the end")
            await ctx.wheelRun("folded: wheel up from the end", steps: 60, by: -45, deepEvery: 10)
            ctx.at("unfold all")
            let ref = ctx.anchor()
            await ctx.withRelaxedStalls { ctx.model.send(.unfoldAll); await ctx.settle(600) }
            ctx.checkAll("after Unfold All"); ctx.checkInk("after Unfold All")
            if let m = ctx.moved(since: ref) { ctx.note(String(format: "Unfold All moved the middle paragraph by %.1f pt on screen", m)) } else { ctx.note("Unfold All: the middle paragraph left the screen (top line \(ctx.topLine()))") }
            await ctx.restedSteps("after Unfold All")
            ctx.snap("unfolded")
        },
    ]
}
