import AppKit
import HyperCore

// 실사용 시뮬레이션 — 트랙패드 제스처: 위상(phase)이 붙은 스크롤 이벤트, AppKit 의 관성·탄성(끝을 넘겨 당김)
//
// 왜 따로 있는가: NSScrollView 는 위상이 붙은 제스처를 '반응형 스크롤'로 처리한다(이 앱의 스크롤 뷰·클립 뷰·텍스트 뷰 모두 isCompatibleWithResponsiveScrolling).
// began 이벤트를 받으면 `-[NSScrollingBehaviorConcurrentVBL _scrollView:trackGestureScrollWithEvent:]` 가 추적을 시작하고, 뒤따르는 이벤트는 뷰의
// scrollWheel(with:) 로 오지 않는다 — 그래서 이벤트를 뷰에 하나씩 건네는 방식으로는 흉내 낼 수 없었다(2026-11-24: 320 pt 중 18 pt 만 움직이고 live scroll 에 갇힘).
//
// 되는 방법(2026-11-25 실측, macOS 27): 제스처의 손가락 구간 전체(began → changed… → ended)를 **앱 자신의 이벤트 큐**에 한꺼번에 넣는다(NSApp.postEvent —
// 전역 입력이 아니다). 주 이벤트 루프가 began 을 꺼내 보내면 추적기가 큐에 이미 있는 뒤 이벤트들을 직접 꺼내 간다. 손가락 구간의 합은 한 번에 반영되고,
// 그 뒤의 **관성은 AppKit 이 스스로 실시간으로 돌린다**(화면 주사율마다 main 스레드에 동기화 — 실제 트랙패드와 같은 경로: 클립 뷰 bounds 변화, live scroll 알림,
// 끝에서의 탄성, 끝나면 didEndLiveScroll). 관성 이벤트까지 큐에 넣으면 추적기가 그것도 삼키고 관성 없이 끝난다 — 넣지 않는다.
// 안 되는 것: 이벤트를 실시간 간격으로 큐에 넣기(추적기는 시작할 때 큐에 있던 것만 꺼낸다 — 뒤에 온 것은 무시되고 제스처가 끝나지 않는다).
// 그래서 '손가락을 천천히 끄는 동안'은 재현하지 못한다: 손가락 구간은 한 프레임에 지나가고, 실시간으로 도는 것은 관성과 탄성이다.
//
// 합성한 스크롤 이벤트에는 창이 없어(windowNumber 0) NSApp 이 보낼 곳을 모른다 — 하네스가 로컬 이벤트 모니터로 받아 편집기의 스크롤 뷰에 건넨다.

extension RealUseContext {
    /// 위상이 붙은 픽셀 스크롤 이벤트 (CG 값: began 1 · changed 2 · ended 4). `uptime` 은 이벤트 시각(부팅 뒤 초) — 추적기가 속도를 여기서 구한다
    func phasedScrollEvent(points: CGFloat, phase: Int64, uptime: TimeInterval) -> NSEvent? {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(points.rounded()), wheel2: 0, wheel3: 0) else { return nil }
        cg.timestamp = UInt64(uptime * 1_000_000_000)
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(points))
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(points))
        cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        let mid = scroll.convert(NSPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: nil)
        let onScreen = window.convertPoint(toScreen: mid)
        cg.location = CGPoint(x: onScreen.x, y: (NSScreen.screens.first?.frame.height ?? 0) - onScreen.y)
        return NSEvent(cgEvent: cg)
    }

    /// 제스처 하나의 기록. `frames` 는 화면이 갱신될 때마다(배치가 끝난 뒤)의 상태다
    struct TrackpadRun {
        struct Frame {
            let ms: Double          // 제스처를 큐에 넣은 뒤의 시간
            let clipY: CGFloat
            let over: CGFloat       // 문서 처음·끝을 넘겨 당겨진 양 (탄성; 0 = 문서 안)
            let step: CGFloat?      // 앞 프레임 뒤로 내용이 화면에서 움직인 양 (+ = 아래로 스크롤). 잴 문단이 없었으면 nil
        }
        var frames: [Frame] = []
        var started = 0, ended = 0   // live scroll 시작·끝 알림
        var routed = 0               // 하네스가 스크롤 뷰에 건넨 이벤트 수 (began 하나여야 한다 — 나머지는 추적기가 큐에서 꺼내 간다)
        var finger: CGFloat = 0      // 보낸 손가락 구간의 합
        var moved: CGFloat = 0       // 잰 프레임들의 내용 이동 합
        var ms: Double = 0
        var timedOut = false
        /// 탄성으로 문서 밖에 나갔다가 돌아온 횟수 (문서 안 → 밖으로 넘어간 횟수)
        var stretches: Int { zip(frames, frames.dropFirst()).filter { abs($0.over) < 0.5 && abs($1.over) >= 0.5 }.count + ((frames.first.map { abs($0.over) >= 0.5 } ?? false) ? 1 : 0) }
        var worstOver: CGFloat { frames.map { abs($0.over) }.max() ?? 0 }
    }

    /// 손가락 구간의 이벤트들 (began → changed… → ended), `gapMs` 간격의 시각을 붙여서
    private func swipeEvents(finger total: CGFloat, steps: Int, gapMs: Double) -> [NSEvent] {
        let t0 = ProcessInfo.processInfo.systemUptime
        let per = (total / CGFloat(max(1, steps))).rounded()
        var out: [NSEvent] = []
        for i in 0..<steps { if let e = phasedScrollEvent(points: -per, phase: i == 0 ? 1 : 2, uptime: t0 + Double(i) * gapMs / 1000) { out.append(e) } }
        if let e = phasedScrollEvent(points: 0, phase: 4, uptime: t0 + Double(steps) * gapMs / 1000) { out.append(e) }
        return out
    }

    /// 쓸기 한 번을 앱의 이벤트 큐에 넣는다 (기록은 하지 않는다 — 진행 중인 제스처에 끼워 넣을 때)
    func postSwipe(finger total: CGFloat, steps: Int = 8, gapMs: Double = 8) {
        for e in swipeEvents(finger: total, steps: steps, gapMs: gapMs) { NSApp.postEvent(e, atStart: false) }
    }

    /// 트랙패드 쓸기 한 번: 손가락 구간 `finger` pt(양수 = 아래로)를 `steps` 걸음, 걸음 사이 `gapMs`(속도 = finger / (steps × gapMs)) — 그 뒤의 관성·탄성은 AppKit 이 돌린다.
    /// 제스처가 끝날 때까지(didEndLiveScroll 뒤 화면이 멈출 때까지) 기다리며 프레임마다 기록한다. `during` 은 `afterMs` 뒤(관성 중)에 한 번 끼어든다;
    /// 끼어든 동작이 제스처를 하나 더 시작하면 `gestures` 를 2 로 준다
    func trackpadSwipe(finger total: CGFloat, steps: Int = 8, gapMs: Double = 8, gestures: Int = 1, timeout: Double = 9,
                       afterMs: Double = 0, during: (@MainActor () async -> Void)? = nil) async -> TrackpadRun {
        await settle(0)
        let sv = scroll, clip = sv.contentView
        var run = TrackpadRun()
        let t0 = CFAbsoluteTimeGetCurrent()
        let dir: CGFloat = total >= 0 ? 1 : -1
        var tokens: [NSObjectProtocol] = []
        for name in [NSScrollView.willStartLiveScrollNotification, NSScrollView.didEndLiveScrollNotification] {
            tokens.append(NotificationCenter.default.addObserver(forName: name, object: sv, queue: nil) { n in
                MainActor.assumeIsolated { if n.name == NSScrollView.willStartLiveScrollNotification { run.started += 1 } else { run.ended += 1 } }
            })
        }
        // 창이 없는 스크롤 이벤트는 편집기의 스크롤 뷰로 (파일 머리말)
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { e in
            guard e.window == nil else { return e }
            MainActor.assumeIsolated { run.routed += 1; sv.scrollWheel(with: e) }
            return nil
        }
        // 프레임 기록: 런루프가 쉬기 직전(그 턴의 배치·그리기가 끝난 뒤)에 클립 위치가 바뀌어 있으면 적는다. 창이 완전히 가려져 표시 주기가 멈췄으면 여기서 배치를
        // 끝낸다 — 그러지 않으면 관성이 도는 동안 한 번도 배치되지 않아, 화면에 보일 때와 다른 것을 재게 된다
        var lastY = clip.bounds.minY, lastChange = t0
        var tracked = anchor(nearScreenY: dir > 0 ? visible.height - 70 : 46)
        let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, CFRunLoopActivity.beforeWaiting.rawValue, true, CFIndex.max) { _, _ in
            MainActor.assumeIsolated {
                let y = clip.bounds.minY
                guard abs(y - lastY) > 0.01 else { return }
                if !self.window.occlusionState.contains(.visible) { self.window.layoutIfNeeded(); self.window.displayIfNeeded() }
                let now = CFAbsoluteTimeGetCurrent()
                let y1 = clip.bounds.minY
                let step = tracked.flatMap { a in self.screenY(ofFragmentAt: a.offset).map { a.y - $0 } }
                run.frames.append(.init(ms: (now - t0) * 1000, clipY: y1, over: y1 - clip.constrainBoundsRect(clip.bounds).minY, step: step))
                if let step { run.moved += step }
                tracked = self.anchor(nearScreenY: dir > 0 ? self.visible.height - 70 : 46)
                lastY = y1; lastChange = now
            }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        let events = swipeEvents(finger: total, steps: steps, gapMs: gapMs)
        run.finger = events.reduce(0) { $0 - $1.scrollingDeltaY }
        for e in events { NSApp.postEvent(e, atStart: false) }
        // 끝을 기다린다: live scroll 이 끝났고(끼어든 제스처까지) 그 뒤 150 ms 동안 화면이 멈춰 있으면 끝
        var interrupted = during == nil
        while true {
            try? await Task.sleep(nanoseconds: 10_000_000)
            let now = CFAbsoluteTimeGetCurrent()
            if !interrupted, (now - t0) * 1000 >= afterMs { interrupted = true; await during?() }
            if interrupted, run.ended >= gestures, run.ended >= run.started, now - lastChange > 0.15 { break }
            if now - t0 > timeout { run.timedOut = true; break }
        }
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
        if let monitor { NSEvent.removeMonitor(monitor) }
        tokens.forEach { NotificationCenter.default.removeObserver($0) }
        run.ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        await settle(60)
        return run
    }

    /// 쓸기 한 번을 하고 늘 보는 것을 본다. 반환: 기록 (제스처가 끝나지 않았으면 nil — 그 뒤의 스크롤은 믿을 수 없으니 시나리오를 멈춘다)
    @discardableResult
    func swipeChecked(_ why: String, finger: CGFloat, steps: Int = 8, gapMs: Double = 8, expectStretch: Bool = false) async -> TrackpadRun? {
        let run = await trackpadSwipe(finger: finger, steps: steps, gapMs: gapMs)
        let dir: CGFloat = finger >= 0 ? 1 : -1
        note(String(format: "%@: finger %+.0f pt in %d × %.0f ms → %d frames over %.0f ms, content moved %+.0f pt, worst stretch %.0f pt (%d×), live scroll %d/%d, routed %d",
                    why, run.finger, steps, gapMs, run.frames.count, run.ms, run.moved, run.worstOver, run.stretches, run.started, run.ended, run.routed))
        if run.timedOut || run.started == 0 || run.ended < run.started {
            issue("other", "\(why): the trackpad gesture did not run to its end (live scroll started \(run.started)×, ended \(run.ended)×, \(run.routed) events handed to the scroll view) — the phased-event path is not working in this run")
            return nil
        }
        checkTrackpadFrames(run, dir: dir, why)
        // 끝난 뒤: 문서 밖에 남아 있으면 안 된다
        let clip = scroll.contentView
        let over = clip.bounds.minY - clip.constrainBoundsRect(clip.bounds).minY
        if abs(over) > 0.5 { issue("viewport-jump", "\(why): after the gesture ended the view is still \(String(format: "%.1f", over)) pt outside the document") }
        // 끝을 넘겨 당긴 것은 한 번 늘었다가 돌아오는 것이다 — 문서 안팎을 여러 번 오갔으면 무언가가 탄성과 싸운 것이다
        if run.stretches > 1 { issue("viewport-jump", "\(why): the view crossed the document edge \(run.stretches) times during one gesture (worst \(String(format: "%.1f", run.worstOver)) pt) — something pulled it back while it was rubber-banding") }
        if !expectStretch, run.worstOver > 0.5 { note("\(why): stretched \(String(format: "%.1f", run.worstOver)) pt past the document edge") }
        checkLayout(why)
        return run
    }

    /// 프레임 사이의 내용 이동: 문서 안에서는 쓴 방향으로만, 관성이 줄어드는 대로 — 거꾸로 가거나 갑자기 크게 뛰면 화면이 튄 것이다.
    /// `from`: 이 시각(ms) 뒤의 프레임만 본다 (끼어든 제스처의 앞·뒤를 따로 볼 때)
    func checkTrackpadFrames(_ run: TrackpadRun, dir: CGFloat, from: Double = 0, until: Double = .greatestFiniteMagnitude, _ why: String) {
        let frames = run.frames.filter { $0.ms >= from && $0.ms < until }
        guard frames.count > 1 else { return }
        // 기준 프레임 간격 (120 Hz 화면 8 ms, 60 Hz 16 ms)
        let gaps = zip(frames, frames.dropFirst()).map { $1.ms - $0.ms }.sorted()
        let nominal = max(4, gaps[gaps.count / 2])
        var recent: [CGFloat] = []   // 앞선 세 프레임의 이동량 (쓴 방향)
        var back = 0, spikes = 0, worstBack: CGFloat = 0, worstSpike: CGFloat = 0, backAt = 0.0, spikeAt = 0.0
        var caughtUp: [String] = []   // 늦은 앞 프레임의 몫을 실어 온 것으로 보아 튐으로 세지 않은 프레임 (기록으로 남긴다)
        func clipStep(_ i: Int) -> CGFloat { (frames[i].clipY - frames[i - 1].clipY) * dir }
        for (i, f) in frames.enumerated() {
            let s = f.step.map { $0 * dir }
            defer { if let s { recent.append(s); if recent.count > 3 { recent.removeFirst() } } else { recent.removeAll() } }
            guard i > 0, let s, abs(f.over) < 0.5, abs(frames[i - 1].over) < 0.5 else { continue }   // 첫 프레임은 손가락 구간, 탄성 중은 되돌아오는 것이 정상
            if s < -1.5 { back += 1; if -s > worstBack { worstBack = -s; backAt = f.ms } }
            // 관성은 줄어들기만 한다. main 동기화는 고르지 않다(한 주기의 몫이 24 + 46 pt 로 나뉘어 오거나, 프레임을 놓치면 다음 프레임이 몇 주기 몫을 간다 — 끊김이지
            // 튐이 아니다): 앞선 세 프레임 가운데 가장 큰 것을 기준으로, 지난 시간만큼의 몫(여유 1.3 배, 적어도 1.8 배) + 24 pt 를 넘으면 튄 것이다
            guard let top = recent.max(), top >= 0, recent.count >= 2 else { continue }
            let limit = top * max(1.8, 1.3 * CGFloat((f.ms - frames[i - 1].ms) / nominal)) + 24
            guard s > limit else { continue }
            // 앞 프레임이 늦게 왔으면(메인 스레드가 한두 주기 밀렸다) 그 프레임에는 한 주기의 몫만 실리고 밀린 몫은 이 프레임에 실려 온다 — 앞 프레임이 지난
            // 시간에 견줘 모자랐던 만큼은 튄 것으로 세지 않는다. 실측 두 건: 8.8 ms 마다 106 pt 씩 가던 중 20 ms 만에 온 프레임이 102 pt, 그다음 13 ms 프레임이
            // 296 pt — 두 프레임의 합 398 pt / 33 ms 는 앞뒤 속도(12 pt/ms)와 같다. 44 ms 만에 온 프레임이 63 pt, 그다음 18 ms 프레임이 298 pt — 합 361 pt /
            // 62 ms = 5.8 pt/ms (앞 8.5, 뒤 6 pt/ms). 내용이 관성보다 더 간 것이 아니라 화면이 한 프레임 늦게 따라잡은 것이다 (끊김이지 튐이 아니다).
            // 늦은 프레임은 조각을 버린 무거운 배치 패스 뒤에 오기 쉽고, 그 자리가 좌표가 옮겨지는 자리이기도 하다. 그래서 두 가지가 다 맞을 때만 인정한다:
            //  · 앞 프레임이 정말 늦었다 (한 주기의 1.5 배 넘게 걸렸다)
            //  · 그 몫을 **스크롤이** 실어 왔다: 두 프레임의 (클립 이동 ÷ 내용 이동)이 그 앞 프레임들의 비율에서 크게 떨어지지 않는다. 끊김이면 클립도 같이 늦었다가
            //    따라잡고(위의 두 건: 클립 −171 다음 −409, −51 다음 −434), 좌표가 옮겨져 튄 것이면 클립은 그대로인데 내용만 더 간다.
            //    두 합이 같은지를 볼 수는 없다 — 버려진 구간을 거슬러 오를 때는 프레임마다 높이가 다시 재어져 클립이 내용의 1.2~2.1 배를 간다 (−109/−130, −106/−224)
            var owed: CGFloat = 0
            if i >= 2, let before = frames[i - 1].step.map({ $0 * dir }) {
                let latePeriods = CGFloat((frames[i - 1].ms - frames[i - 2].ms) / nominal)
                let content2 = before + s, clip2 = clipStep(i - 1) + clipStep(i)
                var content0: CGFloat = 0, clip0: CGFloat = 0
                for k in max(1, i - 4)..<(i - 1) { if let c = frames[k].step { content0 += c * dir; clip0 += clipStep(k) } }
                let usual = content0 > 1 ? clip0 / content0 : 1
                if latePeriods >= 1.5, content2 > 1, clip2 / content2 >= 0.6 * usual { owed = max(0, top * latePeriods - before) }
            }
            if s > limit + owed { spikes += 1; if s > worstSpike { worstSpike = s; spikeAt = f.ms } }
            else { caughtUp.append(String(format: "%.0f ms: %.0f pt (clip %.0f) after a %.0f ms frame of %.0f pt (clip %.0f)", f.ms, s, clipStep(i), frames[i - 1].ms - frames[i - 2].ms, (frames[i - 1].step ?? 0) * dir, clipStep(i - 1))) }
        }
        if !caughtUp.isEmpty { note("\(why): \(caughtUp.count) frame(s) carried the share of a late frame before them and were not counted as jumps — " + caughtUp.joined(separator: "; ")) }
        if back > 0 || spikes > 0 {
            // 문제가 난 프레임 둘레를 남긴다 (시각 ms: 내용 이동 pt / 클립 이동 pt)
            let center = run.frames.firstIndex(where: { $0.ms >= (back > 0 ? backAt : spikeAt) }) ?? 0
            let lo = max(0, center - 6), hi = min(run.frames.count, center + 5)
            note("\(why): frames around \(Int(back > 0 ? backAt : spikeAt)) ms — " + (lo..<hi).map { i in
                let f = run.frames[i]
                return String(format: "%.0f: %@/%+.0f%@", f.ms, f.step.map { String(format: "%+.0f", $0) } ?? "?", i > 0 ? f.clipY - run.frames[i - 1].clipY : 0, abs(f.over) >= 0.5 ? String(format: " over %+.0f", f.over) : "")
            }.joined(separator: " | "))
        }
        if back > 0 { issue("scroll-delta", "\(why): the content moved against the swipe in \(back) frame(s) of the momentum (worst \(String(format: "%.1f", worstBack)) pt, around \(Int(backAt)) ms)") }
        if spikes > 0 { issue("scroll-delta", "\(why): the content jumped ahead in \(spikes) frame(s) of the momentum (worst a \(String(format: "%.1f", worstSpike)) pt frame, far more than the frames before it, around \(Int(spikeAt)) ms)") }
    }
}

extension RealUse {
    @MainActor static let scrollTrackpadScenarios: [Scenario] = [
        // 쓸기 + 관성: 문서 가운데에서 작게·크게, 아래로·위로, 쉬었다가
        Scenario(name: "scroll-trackpad-swipe") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "trackpad-swipe.md") }
            ctx.model.jump(toLine: 6000); await ctx.settle(450)
            ctx.at("swipes in the middle")
            for (i, f) in [CGFloat(48), 144, -144, 480, -480, 1440, -1440].enumerated() {
                let top0 = ctx.topLine()
                guard let run = await ctx.swipeChecked("swipe \(i + 1) (\(Int(f)) pt)", finger: f) else { return }
                // 손가락이 간 만큼은 가야 한다 (관성이 더 보탠다)
                if run.moved * (f > 0 ? 1 : -1) < abs(f) - 2, run.frames.allSatisfy({ $0.step != nil }) {
                    ctx.issue("scroll-delta", "swipe \(i + 1): the fingers moved \(Int(f)) pt but the content moved only \(String(format: "%.1f", run.moved)) pt")
                }
                let top1 = ctx.topLine()
                if f > 0 ? top1 < top0 : top1 > top0 { ctx.issue("scroll-delta", "swipe \(i + 1) (\(Int(f)) pt): top line went from \(top0) to \(top1) — the wrong way") }
                ctx.checkGutter("swipe \(i + 1)"); ctx.checkInk("swipe \(i + 1)")
                await ctx.settle(250)   // 손을 뗐다가 다시
            }
            ctx.snap("middle")
            // 느린 쓸기(관성이 거의 없다)와 빠른 쓸기를 번갈아
            ctx.at("slow and fast swipes")
            for (i, p) in [(CGFloat(60), 12, 16.0), (CGFloat(-60), 12, 16.0), (CGFloat(900), 6, 8.0), (CGFloat(-900), 6, 8.0)].enumerated() {
                guard await ctx.swipeChecked("swipe \(i + 1) (\(Int(p.0)) pt in \(p.1) × \(Int(p.2)) ms)", finger: p.0, steps: p.1, gapMs: p.2) != nil else { return }
                ctx.checkGutter("slow/fast swipe \(i + 1)"); ctx.checkInk("slow/fast swipe \(i + 1)")
                await ctx.settle(250)
            }
            // 제스처 뒤에는 보통 휠·키가 그대로 통해야 한다 (스크롤 뷰가 live scroll 에 갇히지 않았다)
            ctx.at("plain wheel and keys after the gestures")
            await ctx.wheelChecked(120, restMs: 100, "pixel wheel after trackpad gestures")
            await ctx.wheelChecked(-120, "pixel wheel back after trackpad gestures")
            await ctx.key(.down, [.command]); await ctx.settle(300)
            ctx.expectBottom("⌘↓ after trackpad gestures"); ctx.checkCaretVisible("⌘↓ after trackpad gestures"); ctx.checkAll("⌘↓ after trackpad gestures"); ctx.checkInk("⌘↓ after trackpad gestures")
            ctx.snap("end")
        },

        // 문서 끝·처음에서: 끝을 넘겨 당기면 한 번 늘었다가 돌아오고, 끝난 뒤에는 정확히 끝(처음)에 있다
        Scenario(name: "scroll-trackpad-ends") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "trackpad-ends.md") }
            ctx.at("swipe down at the very end")
            await ctx.key(.down, [.command]); await ctx.settle(400)
            ctx.expectBottom("after ⌘↓")
            // 손가락 구간은 한 프레임에 통째로 반영된다(파일 머리말) — 실제 손가락으로는 화면 높이를 넘겨 당길 수 없으므로 한 화면이 안 되게 준다
            for (i, f) in [CGFloat(272), 96, 200].enumerated() {
                guard await ctx.swipeChecked("swipe down at the end \(i + 1) (\(Int(f)) pt)", finger: f, expectStretch: true) != nil else { return }
                ctx.expectBottom("after swiping down at the end \(i + 1)"); ctx.checkAll("after swiping down at the end \(i + 1)"); ctx.checkInk("after swiping down at the end \(i + 1)")
                await ctx.settle(250)
            }
            ctx.snap("end-after-bounce")
            // 끝 근처에서 관성으로 끝에 닿는다
            ctx.at("arrive at the end with momentum")
            guard await ctx.swipeChecked("swipe up from the end (-600 pt)", finger: -600) != nil else { return }
            await ctx.settle(250)
            guard await ctx.swipeChecked("swipe back down past the end (1600 pt)", finger: 1600, expectStretch: true) != nil else { return }
            ctx.expectBottom("after arriving at the end with momentum"); ctx.checkAll("after arriving at the end with momentum"); ctx.checkInk("after arriving at the end with momentum")
            // 끝에서의 첫 휠·입력
            await ctx.wheelChecked(-30, restMs: 120, "first wheel up after the bounce at the end")
            await ctx.wheelChecked(30, "wheel back down after the bounce at the end")
            ctx.expectBottom("after wheeling back to the end")

            ctx.at("swipe up at the very top")
            await ctx.key(.up, [.command]); await ctx.settle(400)
            ctx.expectTop("after ⌘↑")
            for (i, f) in [CGFloat(-272), -96, -200].enumerated() {
                guard await ctx.swipeChecked("swipe up at the top \(i + 1) (\(Int(f)) pt)", finger: f, expectStretch: true) != nil else { return }
                ctx.expectTop("after swiping up at the top \(i + 1)"); ctx.checkAll("after swiping up at the top \(i + 1)"); ctx.checkInk("after swiping up at the top \(i + 1)")
                await ctx.settle(250)
            }
            ctx.at("arrive at the top with momentum")
            guard await ctx.swipeChecked("swipe down from the top (600 pt)", finger: 600) != nil else { return }
            await ctx.settle(250)
            guard await ctx.swipeChecked("swipe back up past the top (-1600 pt)", finger: -1600, expectStretch: true) != nil else { return }
            ctx.expectTop("after arriving at the top with momentum"); ctx.checkAll("after arriving at the top with momentum"); ctx.checkInk("after arriving at the top with momentum")
            ctx.snap("top-after-bounce")

            // 여러 번 감기는 문단의 문서: 끝 부분의 높이가 배치하며 바뀐다
            await ctx.withRelaxedStalls { await ctx.open(.wide, name: "trackpad-ends-wide.md") }
            ctx.at("wide: swipe down at the end")
            await ctx.key(.down, [.command]); await ctx.settle(400)
            guard await ctx.swipeChecked("wide: swipe down at the end (400 pt)", finger: 400, expectStretch: true) != nil else { return }
            ctx.expectBottom("wide: after swiping down at the end"); ctx.checkAll("wide: after swiping down at the end"); ctx.checkInk("wide: after swiping down at the end")
            ctx.model.jump(toLine: 3960); await ctx.settle(450)
            // 한 번도 안 본 끝으로 관성에 실려 들어간다 (끝 부분의 높이는 그동안 추정이다)
            for i in 1...4 {
                guard await ctx.swipeChecked("wide: swipe into the unseen end \(i) (600 pt)", finger: 600, expectStretch: true) != nil else { return }
                await ctx.settle(250)
                if ctx.visible.maxY > ctx.tv.frame.height - 1 { break }
            }
            guard await ctx.swipeChecked("wide: swipe again at the end (240 pt)", finger: 240, expectStretch: true) != nil else { return }
            ctx.expectBottom("wide: after swiping into the end"); ctx.checkAll("wide: after swiping into the end"); ctx.checkInk("wide: after swiping into the end")
            ctx.snap("wide-end")
        },

        // 관성이 도는 중에 끼어든다: 글자 입력, 방향키, 클릭
        Scenario(name: "scroll-trackpad-interrupt") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "trackpad-interrupt.md") }
            ctx.model.jump(toLine: 8000); await ctx.settle(450)
            @MainActor func report(_ why: String, _ run: RealUseContext.TrackpadRun) -> Bool {
                ctx.note(String(format: "%@: %d frames over %.0f ms, content moved %+.0f pt, live scroll %d/%d, routed %d", why, run.frames.count, run.ms, run.moved, run.started, run.ended, run.routed))
                if run.timedOut || run.started == 0 || run.ended < run.started {
                    ctx.issue("other", "\(why): the gesture did not run to its end (live scroll started \(run.started)×, ended \(run.ended)×, \(run.routed) events handed to the scroll view)")
                    return false
                }
                let clip = ctx.scroll.contentView
                let over = clip.bounds.minY - clip.constrainBoundsRect(clip.bounds).minY
                if abs(over) > 0.5 { ctx.issue("viewport-jump", "\(why): after the gesture ended the view is still \(String(format: "%.1f", over)) pt outside the document") }
                return true
            }
            // 관성 중에 반대로 쓰는 것은 여기서 보지 못한다: 관성이 도는 중에 온 두 번째 제스처는 큐에 든 뒤 이벤트를 꺼내 가지 않아 끝나지 않는다
            // (2026-11-25 실측: live scroll 시작 2 · 끝 1, 9초 뒤에도 그대로). 방향을 바꿔 가며 쉬었다 쓰는 것은 scroll-trackpad-swipe 가 본다

            // 관성 중에 글자를 친다: 캐럿은 화면 밖에 남아 있다 — 화면은 캐럿으로 돌아오고, 관성이 그것을 다시 끌고 가지 않는다
            ctx.at("type during the momentum")
            guard let a = ctx.anchor() else { ctx.issue("other", "no paragraph on screen"); return }
            guard await ctx.clickCaret(a.offset, "a line in the middle of the screen") else { return }
            let expect = NSMutableString(string: ctx.textCopy() as String)
            var at = a.offset
            var run = await ctx.trackpadSwipe(finger: 900, afterMs: 250, during: { await ctx.typeKeys("typed mid-flight ") })
            guard report("swipe 900 and type after 250 ms", run) else { return }
            await ctx.quiesce()
            expect.insert("typed mid-flight ", at: at); at += ("typed mid-flight " as NSString).length
            ctx.checkTyped(expect, caret: at, "typed during the momentum"); ctx.checkCaretLineWhole("typed during the momentum"); ctx.checkInk("typed during the momentum")
            ctx.snap("typed-mid-flight")

            // 관성 중에 방향키: 캐럿 줄로 돌아온다
            ctx.at("arrow key during the momentum")
            run = await ctx.trackpadSwipe(finger: -900, afterMs: 250, during: { await ctx.press(.down) })
            guard report("swipe -900 and ↓ after 250 ms", run) else { return }
            await ctx.quiesce()
            ctx.checkCaretVisible("↓ during the momentum"); ctx.checkAll("↓ during the momentum"); ctx.checkInk("↓ during the momentum")

            // 관성 중에 클릭: 클릭한 글자에 캐럿이 놓인다 (하네스의 클릭은 텍스트 뷰에 직접 가므로 AppKit 이 관성을 멈추는 것까지는 재현하지 못한다)
            ctx.at("click during the momentum")
            var clicked = -1, landed = -1
            run = await ctx.trackpadSwipe(finger: 600, afterMs: 300, during: {
                guard let t = ctx.anchor() else { return }
                clicked = t.offset
                if await ctx.click(offset: t.offset) { landed = ctx.caret }
            })
            guard report("swipe 600 and click after 300 ms", run) else { return }
            if clicked >= 0, landed >= 0, landed != clicked {
                ctx.issue("other", "clicked the head of the paragraph at offset \(clicked) while the view was coasting but the caret went to \(landed)")
            } else if landed < 0 { ctx.note("the click during the momentum could not be placed (no paragraph on screen at that moment)") }
            ctx.checkAll("click during the momentum"); ctx.checkInk("click during the momentum")
            ctx.snap("end")
        },

        // 긴 문서를 오래 쓸기: 한 번도 안 본 곳으로 관성에 실려 들어가며 조각 캐시를 넘긴다 (2,000 문단) — 프레임마다 쓴 방향으로만 움직이고, 같은 길로 돌아오면 처음이다
        Scenario(name: "scroll-trackpad-long") { ctx in
            let issues0 = ctx.issues.count   // 이 시나리오에서 난 문제만 센다 — 앞 시나리오가 남긴 문제(정지 한 번의 행 묶음 등)로 걸음을 건너뛰지 않게
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "trackpad-long.md") }
            ctx.setFragmentCacheLimit()
            await ctx.key(.up, [.command]); await ctx.settle(300)
            ctx.at("swipes down through unseen text")
            var last = ctx.topLine()
            for i in 1...14 {
                guard await ctx.swipeChecked("down \(i) (1200 pt)", finger: 1200) != nil else { return }
                let t = ctx.topLine()
                if t <= last { ctx.issue("scroll-delta", "swipe down \(i): top line went from \(last) to \(t)") }
                last = t
                if i % 4 == 0 { ctx.checkGutter("swipe down \(i)"); ctx.checkInk("swipe down \(i)") }
                if ctx.issues.count - issues0 > 10 { return }
                await ctx.settle(150)
            }
            ctx.logFragmentCache("after 14 swipes down")
            ctx.note("14 swipes down reached line \(last)")
            if last < 2_200 { ctx.issue("scroll-delta", "14 swipes of 1200 pt (plus momentum) only reached line \(last) — expected to pass 2,200 paragraphs (the fragment cache limit)") }
            ctx.snap("down")
            ctx.at("swipes back up")
            for i in 1...24 {
                guard await ctx.swipeChecked("up \(i) (-1200 pt)", finger: -1200, expectStretch: true) != nil else { return }
                let t = ctx.topLine()
                if t > last { ctx.issue("scroll-delta", "swipe up \(i): top line went from \(last) to \(t)") }
                last = t
                if i % 4 == 0 { ctx.checkGutter("swipe up \(i)"); ctx.checkInk("swipe up \(i)") }
                if ctx.issues.count - issues0 > 10 { return }
                await ctx.settle(150)
                if ctx.visible.minY < 0.5 { break }
            }
            ctx.expectTop("after swiping back up"); ctx.checkAll("back at the top"); ctx.checkInk("back at the top")
            // 여러 번 감기는 문단
            await ctx.withRelaxedStalls { await ctx.open(.wide, name: "trackpad-long-wide.md") }
            await ctx.key(.up, [.command]); await ctx.settle(300)
            ctx.at("wide: swipes down and back")
            last = ctx.topLine()
            for i in 1...6 {
                guard await ctx.swipeChecked("wide down \(i) (1200 pt)", finger: 1200) != nil else { return }
                let t = ctx.topLine()
                if t <= last { ctx.issue("scroll-delta", "wide swipe down \(i): top line went from \(last) to \(t)") }
                last = t
                await ctx.settle(150)
            }
            ctx.checkGutter("wide: after 6 swipes down"); ctx.checkInk("wide: after 6 swipes down")
            for i in 1...12 {
                guard await ctx.swipeChecked("wide up \(i) (-1200 pt)", finger: -1200, expectStretch: true) != nil else { return }
                await ctx.settle(150)
                if ctx.visible.minY < 0.5 { break }
            }
            ctx.expectTop("wide: after swiping back up"); ctx.checkAll("wide: back at the top"); ctx.checkInk("wide: back at the top")
            ctx.snap("end")
        },

        // 제스처 중의 '캐럿 보이기' 요청은 그 제스처가 끝날 때 한 번만 따른다: 끝 알림이 빠진 채 남은 요청이 나중의 휠·손잡이 끌기 끝에서 화면을 캐럿으로 끌고 가면 안 되고,
        // 관성이 도는 중에 탭을 바꿨을 때 새 탭의 화면이 (화면 밖에 둔) 캐럿으로 튀면 안 된다
        Scenario(name: "scroll-trackpad-stale-reveal") { ctx in
            ctx.logWindowState()
            var first: URL?
            await ctx.withRelaxedStalls { first = await ctx.open(.notes, name: "trackpad-stale-a.md") }
            ctx.model.jump(toLine: 6000); await ctx.settle(450)

            // (1) 끝 알림이 오지 않은 제스처: 제스처 중에 친 글자의 '보이기' 요청이 남는다. 제스처 판정은 마지막 움직임에서 1초 뒤에 풀린다 —
            //     그 뒤에 휠로 캐럿에서 멀리 가면 거기 머물러야 한다 (휠도 live scroll 끝 알림을 낸다)
            ctx.at("a reveal request left by a gesture that never ended")
            guard let a = ctx.anchor(), await ctx.clickCaret(a.offset, "a line in the middle of the screen") else { return }
            var liveEnds = 0
            let token = NotificationCenter.default.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: ctx.scroll, queue: nil) { _ in MainActor.assumeIsolated { liveEnds += 1 } }
            ctx.tv.liveScrollTick = CFAbsoluteTimeGetCurrent()   // 제스처가 도는 중인 것으로 (끝 알림은 보내지 않는다)
            await ctx.typeKeys("x"); await ctx.quiesce()
            await ctx.settle(1300)
            let line0 = ctx.topLine()
            await ctx.scrollBy(2400); await ctx.settle(400)   // 한 번에: 끝 알림이 한 번뿐이어야 되돌아간 것이 그대로 남는다
            ctx.note("wheeled 2,400 pt away from the caret after a gesture that never ended: top line \(line0) → \(ctx.topLine()), caret visible \(ctx.tv.isCaretVisible), live scroll end notifications during the wheel \(liveEnds)")
            if ctx.tv.isCaretVisible || ctx.topLine() < line0 + 40 {
                ctx.issue("viewport-jump", "a plain wheel scroll of 2,400 pt ended back at the caret (top line \(line0) → \(ctx.topLine())) — a reveal request left over from an earlier gesture was carried out")
            }
            if liveEnds == 0 { ctx.note("the wheel sent no live scroll end notification in this run — the stale request could not be triggered this way") }
            // 손잡이 끌기의 끝도 같다
            ctx.tv.liveScrollTick = CFAbsoluteTimeGetCurrent()
            if await ctx.clickCaret(ctx.anchor()?.offset ?? 0, "a line in the middle of the screen (2)") {
                await ctx.typeKeys("y"); await ctx.quiesce()
                await ctx.settle(1300)
                let line1 = ctx.topLine()
                liveEnds = 0
                await ctx.withRelaxedStalls(5_000) { _ = await ctx.dragKnob(by: 40, steps: 8) }
                await ctx.settle(400)
                ctx.note("dragged the scroller knob 40 pt after a gesture that never ended: top line \(line1) → \(ctx.topLine()), caret visible \(ctx.tv.isCaretVisible), live scroll end notifications during the drag \(liveEnds)")
                if ctx.tv.isCaretVisible || ctx.topLine() < line1 + 40 {
                    ctx.issue("viewport-jump", "dragging the scroller knob ended back at the caret (top line \(line1) → \(ctx.topLine())) — a reveal request left over from an earlier gesture was carried out")
                }
            }
            NotificationCenter.default.removeObserver(token)
            ctx.checkAll("after the stale reveal requests"); ctx.checkInk("after the stale reveal requests")

            // (2) 관성 중에 탭을 바꾼다: 돌아간 탭은 읽던 곳(캐럿은 화면 밖 위쪽)을 보여 줘야 한다 — 관성이 끝날 때 캐럿으로 튀지 않는다
            ctx.at("switch tabs during the momentum")
            ctx.model.jump(toLine: 300); await ctx.settle(450)
            await ctx.wheelTo(steps: 30, by: 800); await ctx.settle(300)   // 캐럿(300번 줄)에서 24,000 pt 아래를 읽는 중
            var reading = ctx.topLine()
            if ctx.tv.isCaretVisible { ctx.issue("other", "the caret should be off screen before the tab switch") }
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "trackpad-stale-b.md") }
            ctx.model.jump(toLine: 8000); await ctx.settle(450)
            for typeFirst in [false, true] {
                guard let first else { break }
                let why = typeFirst ? "typed, then switched tabs during the momentum" : "switched tabs during the momentum"
                let run = await ctx.trackpadSwipe(finger: 900, afterMs: 200, during: {
                    if typeFirst { await ctx.typeKeys("z") }
                    await ctx.withRelaxedStalls { ctx.model.activateTab(first); await ctx.turn() }
                })
                await ctx.settle(700)
                ctx.note(String(format: "%@: %d frames over %.0f ms, live scroll %d/%d — on the first tab the top line is %d (was reading at %d), caret visible %@",
                                why, run.frames.count, run.ms, run.started, run.ended, ctx.topLine(), reading, ctx.tv.isCaretVisible ? "yes" : "no"))
                if run.timedOut || run.ended < run.started { ctx.issue("other", "\(why): the gesture did not run to its end (live scroll \(run.started)/\(run.ended))"); break }
                if ctx.doc.url != first { ctx.issue("other", "\(why): the first tab is not active"); break }
                // 남은 관성이 새 탭의 글을 조금 더 민다(아래로) — 읽던 곳에서 아래로 몇 화면 안이어야 하고, 300번 줄의 캐럿이 보이면 캐럿으로 튄 것이다
                if ctx.tv.isCaretVisible || ctx.topLine() < reading - 3 {
                    ctx.issue("viewport-jump", "\(why): back on the first tab the view should show where it was reading (line \(reading)) but it jumped to the caret (top line \(ctx.topLine()))")
                }
                ctx.checkAll(why); ctx.checkInk(why)
                // 다음 판을 위해: 다시 둘째 탭으로 (첫 탭의 읽던 곳은 지금 자리로 저장된다 — 캐럿은 여전히 화면 밖)
                if !typeFirst {
                    reading = ctx.topLine()
                    await ctx.withRelaxedStalls { await ctx.open(.notes, name: "trackpad-stale-b.md") }
                    ctx.model.jump(toLine: 8000); await ctx.settle(450)
                }
            }

            // (3) 돌아가는 탭의 캐럿이 읽던 곳의 맨 위 문단 머리에 있다 (문서 처음을 보던 탭, 캐럿은 첫 글자). 읽던 곳을 되살리는 스크롤의 대상이 캐럿 자리와 같아도
            //     그것은 캐럿을 보이려는 요청이 아니다 — 남은 관성이 새 탭을 굴린 뒤 제스처가 끝날 때 화면이 캐럿(문서 처음)으로 되돌아가면 안 된다
            if let first {
                ctx.at("switch during the momentum to a tab whose caret heads its view")
                await ctx.withRelaxedStalls { ctx.model.activateTab(first); await ctx.settle(700) }
                await ctx.key(.up, [.command]); await ctx.settle(900)   // 캐럿 0 · 화면 맨 위 (보기 위치 저장 0.8 s 를 기다린다)
                await ctx.withRelaxedStalls { await ctx.open(.notes, name: "trackpad-stale-b.md") }
                ctx.model.jump(toLine: 8000); await ctx.settle(450)
                let run = await ctx.trackpadSwipe(finger: 900, afterMs: 200, during: {
                    await ctx.withRelaxedStalls { ctx.model.activateTab(first); await ctx.turn() }
                })
                await ctx.settle(700)
                // 전환 뒤의 프레임: 첫 탭은 문서 처음에서 시작한다 (둘째 탭은 8,000번 줄 — 스크롤 위치가 19만 pt 를 넘는다)
                let deepest = run.frames.filter { $0.clipY < 20_000 }.map(\.clipY).max() ?? 0
                ctx.note(String(format: "switched to the tab at its top: %d frames over %.0f ms, live scroll %d/%d — the momentum carried the first tab down to y %.0f; it rests at y %.0f (top line %d), caret visible %@",
                                run.frames.count, run.ms, run.started, run.ended, deepest, ctx.visible.minY, ctx.topLine(), ctx.tv.isCaretVisible ? "yes" : "no"))
                if run.timedOut || run.ended < run.started { ctx.issue("other", "switch to the tab at its top: the gesture did not run to its end (live scroll \(run.started)/\(run.ended))") }
                else if ctx.doc.url != first { ctx.issue("other", "switch to the tab at its top: the first tab is not active") }
                else if deepest > ctx.visible.height + 48 {
                    // 관성이 캐럿 줄을 화면 밖으로 밀어냈다 — 끝난 뒤 캐럿이 보이면 제스처 끝에 캐럿으로 되돌아간 것이다
                    if ctx.tv.isCaretVisible {
                        ctx.issue("viewport-jump", String(format: "the momentum left after the tab switch carried the view %.0f pt down the first tab, then the view jumped back to the caret at the top (now y %.0f)", deepest, ctx.visible.minY))
                    }
                } else { ctx.note("the momentum left after the switch was too small to push the caret off screen — nothing to judge in this run") }
                ctx.checkAll("switched to the tab at its top"); ctx.checkInk("switched to the tab at its top")
            }
            ctx.snap("end")
        },
    ]
}
