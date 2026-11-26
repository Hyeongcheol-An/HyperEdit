import AppKit
import HyperCore

// 실사용 시뮬레이션 — 줄바꿈 끔(가로 스크롤): 가로 스크롤 범위, 캐럿을 따라가는 가로 스크롤, 열 블록·강조·거터, 오른쪽→왼쪽 글, 분할·탭 전환, 4 MB 로그
//
// 줄바꿈을 끄면 텍스트 뷰의 폭은 내용(가장 긴 줄)이 정한다. 이 파일은 그 폭과 가로 스크롤이 사용자가 기대하는 대로인지 본다: 긴 줄의 끝까지 갈 수 있는가,
// 캐럿이 오른쪽 가장자리를 넘으면 따라가는가, 가로로 밀어 둔 채 세로로 움직여도 내용이 옆으로 튀지 않는가, 그리고 그 사이에 멈추지 않는가.

// MARK: - 도우미

extension RealUseContext {
    /// 가로 픽셀 휠: 양수 = 오른쪽으로 (내용은 왼쪽으로). 세로 성분은 0
    func hscrollBy(_ points: CGFloat) async {
        guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: Int32((-points).rounded()), wheel3: 0) else { return }
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(-points))
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: Double(-points))
        let mid = scroll.convert(NSPoint(x: scroll.bounds.midX, y: scroll.bounds.midY), to: nil)
        let onScreen = window.convertPoint(toScreen: mid)
        cg.location = CGPoint(x: onScreen.x, y: (NSScreen.screens.first?.frame.height ?? 0) - onScreen.y)
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window.windowNumber))
        cg.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window.windowNumber))
        guard let e = NSEvent(cgEvent: cg) else { return }
        if scrollViaWindow, e.window === window { window.sendEvent(e) } else { scroll.scrollWheel(with: e) }
        await turn()
    }

    /// 가로 상태 한 줄 (로그용): 텍스트 뷰 폭·보이는 가로 범위·가로 막대
    func hstate(_ tag: String) {
        let hs = scroll.horizontalScroller
        note(String(format: "%@: text view width %.1f, clip width %.1f, x %.1f, container width %.3g, h-scroller %@ (knob %.3f, at %.3f), wrap %@",
                    tag, tv.frame.width, scroll.contentView.bounds.width, visible.minX, Double(tv.textContainer?.size.width ?? -1),
                    scroll.hasHorizontalScroller ? (hs?.isHidden == false ? "shown" : "hidden") : "none", Double(hs?.knobProportion ?? -1), hs?.doubleValue ?? -1,
                    model.wordWrap ? "on" : "off"))
    }

    /// 줄 끝(개행 앞) 캐럿의 x (텍스트 뷰 좌표). 그 문단을 배치한다 — 화면에 있는 줄에만 쓴다
    func endX(ofLine n: Int) -> CGFloat? { tv.caretRect(at: lineEnd(n))?.minX }

    /// 캐럿이 가로·세로 모두 보이는 영역 안에 있는가
    func checkCaretInView(_ why: String) {
        guard let r = tv.caretRect(at: caret) else { return }
        let v = visible
        if r.minX < v.minX - 1 || r.maxX > v.maxX + 1 || r.minY < v.minY - 1 || r.maxY > v.maxY + 1 {
            issue("caret-hidden", "\(why): caret at x \(Int(r.minX)), y \(Int(r.minY)) is outside the visible rect x \(Int(v.minX))…\(Int(v.maxX)), y \(Int(v.minY))…\(Int(v.maxY))")
        }
    }

    /// 화면에 있는 그 줄의 끝까지 가로로 스크롤할 수 있는가: 텍스트 뷰의 폭이 줄 끝을 넘고, 가로 막대가 있다
    func checkReaches(line n: Int, _ why: String) {
        guard let x = endX(ofLine: n) else { issue("other", "\(why): line \(n) has no caret rect"); return }
        if tv.frame.width < x - 0.5 { issue("hscroll", "\(why): line \(n) ends at x \(Int(x)) but the text view is only \(Int(tv.frame.width)) pt wide — its end cannot be scrolled into view") }
        if x > scroll.contentView.bounds.width, !scroll.hasHorizontalScroller { issue("hscroll", "\(why): line \(n) is wider than the editor but there is no horizontal scroller") }
    }

    /// 보이는 영역의 가로 위치가 기대와 같은가
    func checkX(_ expected: CGFloat, tolerance: CGFloat = 1, _ why: String) {
        if abs(visible.minX - expected) > tolerance { issue("hscroll", "\(why): the view is at x \(String(format: "%.1f", visible.minX)), expected \(String(format: "%.1f", expected))") }
    }

    /// 선택이 기대와 같은가
    func expectSel(_ expected: NSRange, _ why: String) {
        let sel = tv.selectedRange()
        if sel != expected { issue("selection", "\(why): selection is {\(sel.location), \(sel.length)}, expected {\(expected.location), \(expected.length)}") }
    }

    /// 화면에 있는 줄이 **그려진** 가로 범위 (텍스트 뷰 좌표): 텍스트 뷰를 비트맵으로 그려 그 줄 높이에서 바탕과 다른 픽셀의 처음과 끝. 보이지 않으면 nil
    func inkSpan(ofLine n: Int) -> (minX: CGFloat, maxX: CGFloat)? {
        guard let r = tv.caretRect(at: lineStart(n)) else { return nil }
        let v = visible
        guard r.minY >= v.minY, r.maxY <= v.maxY, let rep = tv.bitmapImageRepForCachingDisplay(in: v) else { return nil }
        tv.cacheDisplay(in: v, to: rep)
        guard let data = rep.bitmapData, rep.bitsPerSample == 8, rep.samplesPerPixel >= 3, !rep.isPlanar else { return nil }
        let w = rep.pixelsWide, bpr = rep.bytesPerRow, spp = rep.samplesPerPixel, skip = rep.bitmapFormat.contains(.alphaFirst) ? 1 : 0
        let sx = CGFloat(w) / v.width, sy = CGFloat(rep.pixelsHigh) / v.height
        let y0 = Int((r.minY - v.minY + 3) * sy), y1 = Int((r.maxY - v.minY - 3) * sy)
        var lo = Int.max, hi = Int.min
        for y in stride(from: y0, to: y1, by: 2) {
            // 그 행의 바탕: 가장 흔한 색 (현재 줄 띠가 깔려 있어도 된다)
            var counts: [Int: Int] = [:]
            var row: [Int] = []
            row.reserveCapacity(w)
            for x in 0..<w {
                let p = data + y * bpr + x * spp + skip
                let k = (Int(p[0]) << 16) | (Int(p[1]) << 8) | Int(p[2])
                row.append(k); counts[k, default: 0] += 1
            }
            guard let bg = counts.max(by: { $0.value < $1.value })?.key else { continue }
            func far(_ k: Int) -> Bool { abs((k >> 16) - (bg >> 16)) + abs(((k >> 8) & 255) - ((bg >> 8) & 255)) + abs((k & 255) - (bg & 255)) > 60 }
            if let a = row.firstIndex(where: far) { lo = min(lo, a) }
            if let b = row.lastIndex(where: far) { hi = max(hi, b) }
        }
        guard lo <= hi else { return nil }
        return (v.minX + CGFloat(lo) / sx, v.minX + CGFloat(hi + 1) / sx)
    }

    /// 화면에 있는 줄의 자리 한 줄 기록: 조각 틀, 첫 줄 조각의 글자 상자, 줄 머리·줄 끝 캐럿 x, 그려진 가로 범위 — 오른쪽→왼쪽 글이 어디에 놓이는지 견줄 때
    @discardableResult
    func placement(ofLine n: Int, _ tag: String) -> (frameX: CGFloat, frameW: CGFloat, headX: CGFloat, tailX: CGFloat, ink: (minX: CGFloat, maxX: CGFloat)?)? {
        guard let lm = tv.textLayoutManager, let cs = tv.textContentStorage, let loc = cs.location(cs.documentRange.location, offsetBy: lineStart(n)),
              let frag = lm.textLayoutFragment(for: loc), let head = tv.caretRect(at: lineStart(n)), let tail = tv.caretRect(at: lineEnd(n)) else { return nil }
        let o = tv.textContainerOrigin, fr = frag.layoutFragmentFrame
        let tb = frag.textLineFragments.first?.typographicBounds ?? .zero
        let ink = inkSpan(ofLine: n)
        note(String(format: "%@ line %d: fragment x %.1f w %.1f · line box x %.1f w %.1f · caret at the head x %.1f, at the end x %.1f · drawn x %@ (view x %.1f…%.1f, text view width %.1f)",
                    tag, n, fr.minX + o.x, fr.width, fr.minX + tb.minX + o.x, tb.width, head.minX, tail.minX,
                    ink.map { String(format: "%.1f…%.1f", $0.minX, $0.maxX) } ?? "none", visible.minX, visible.maxX, tv.frame.width))
        return (fr.minX + o.x, fr.width, head.minX, tail.minX, ink)
    }

    /// 현재 줄 띠가 캐럿 줄에 편집기 폭 전체로 칠해졌는가 — 가로로 밀어 둔 상태에서도 잴 수 있게 왼쪽 여백 열(checkLineHighlight)이 아니라 보이는 폭의 다섯 군데에서,
    /// 캐럿 줄 상자의 맨 위 줄(글자 획이 닿지 않는 높이)의 색을 같은 글자가 놓인 두 줄 아래의 같은 자리와 견준다. 거터의 띠도 같은 높이여야 한다
    func checkBandAcrossWidth(_ why: String) {
        guard tv.currentLineColor != nil, tv.selectedRange().length == 0, tv.multi == nil, let r = tv.caretRect(at: caret) else { return }
        let v = visible
        guard r.minY >= v.minY, r.maxY + 2 * r.height <= v.maxY, let rep = tv.bitmapImageRepForCachingDisplay(in: v) else { return }
        tv.cacheDisplay(in: v, to: rep)
        let sx = CGFloat(rep.pixelsWide) / v.width, sy = CGFloat(rep.pixelsHigh) / v.height
        func color(_ x: CGFloat, _ y: CGFloat) -> NSColor? { rep.colorAt(x: Int((x - v.minX) * sx), y: Int((y - v.minY) * sy)) }
        func differs(_ a: NSColor?, _ b: NSColor?) -> Bool {
            guard let a, let b else { return false }
            return abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent) > 0.02
        }
        var painted = 0
        let xs = (1...5).map { v.minX + v.width * CGFloat($0) / 6 }
        for x in xs where differs(color(x, r.minY + 1.5), color(x, r.minY + 2 * r.height + 1.5)) { painted += 1 }
        if painted < xs.count { issue("highlight", "\(why): the current-line band covers \(painted) of \(xs.count) sampled columns across the visible width (view x \(Int(v.minX))…\(Int(v.maxX)), caret row y \(Int(r.minY - v.minY)))") }
        if let g = gutter, !g.isHidden, g.bounds.width > 4 {
            window.displayIfNeeded(); CATransaction.flush()
            if let band = g.debugBand {
                if abs(band.lowerBound - (r.minY - v.minY)) > 1.5 { issue("highlight", "\(why): the gutter band is at screen y \(Int(band.lowerBound)) but the caret row is at \(Int(r.minY - v.minY))") }
            } else { issue("highlight", "\(why): the gutter drew no current-line band (caret row at screen y \(Int(r.minY - v.minY)))") }
        }
    }

    /// 열 블록·멀티 선택의 범위마다 선택 강조가 칠해졌는가 — 가로로 밀어 둔 상태에서도 잴 수 있게 범위 첫 글자 칸의 왼쪽 위 모서리를 그 바로 왼쪽(블록 밖)과 견준다
    func checkBlockPainted(_ why: String) {
        let v = visible
        guard v.height > 10, let rep = tv.bitmapImageRepForCachingDisplay(in: v) else { return }
        tv.cacheDisplay(in: v, to: rep)
        let sx = CGFloat(rep.pixelsWide) / v.width, sy = CGFloat(rep.pixelsHigh) / v.height
        func color(_ x: CGFloat, _ y: CGFloat) -> NSColor? { rep.colorAt(x: Int((x - v.minX) * sx), y: Int((y - v.minY) * sy)) }
        func differs(_ a: NSColor?, _ b: NSColor?) -> Bool {
            guard let a, let b else { return false }
            return abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent) > 0.06
        }
        let ranges = (tv.multi?.ranges ?? tv.selectedRanges.map(\.rangeValue)).filter { $0.length > 0 }
        var seen = 0, unpainted = 0
        for r in ranges {
            guard let c = tv.caretRect(at: r.location), c.minX - 4 >= v.minX, c.minX + 4 <= v.maxX, c.minY >= v.minY, c.maxY <= v.maxY else { continue }
            seen += 1
            if !differs(color(c.minX + 1.5, c.minY + 1.5), color(c.minX - 2.5, c.minY + 1.5)) { unpainted += 1 }
        }
        if unpainted > 0 { issue("selection", "\(why): \(unpainted) of \(seen) selected ranges on screen show no selection highlight (view x \(Int(v.minX)))") }
        else if seen == 0, !ranges.isEmpty { issue("selection", "\(why): none of the \(ranges.count) selected ranges is on screen (view x \(Int(v.minX))…\(Int(v.maxX)))") }
    }

    /// 한 구간을 시간만 재며 실행한다 (정지 감시는 문턱을 올려 두고, 걸린 시간을 직접 본다). 반환: ms
    func timed(_ body: () async -> Void) async -> Double {
        let t0 = CFAbsoluteTimeGetCurrent()
        await withRelaxedStalls(120_000) { await body() }
        return (CFAbsoluteTimeGetCurrent() - t0) * 1000
    }

    /// 줄바꿈을 켜거나 끄고 300 ms 기다린다. 전환에 걸린 시간(기다림 제외)이 `budget` ms 를 넘으면 문제로 남긴다. 반환: 걸린 ms.
    /// 줄바꿈을 끌 때 AppKit 이 문서 전체를 배치하던 때에는 이 전환이 1.3 MB 에서 2.1~2.4 s 였다 (문서 크기에 비례 — 50 KB 문서면 90 ms 쯤).
    /// 지금은 문서 크기를 거의 타지 않는다 (실측: 3,000줄 문서에서 끄기 26~49 ms, 켜기 55~56 ms; 120줄·200줄 문서 55~65 ms) — 기본 예산은 그 3~4 배
    @discardableResult
    func setWrap(_ on: Bool, budget: Double = 200, _ why: String) async -> Double {
        let ms = await timed { model.wordWrap = on; await settle(300) } - 300
        note(String(format: "%@: turning word wrap %@ took %.0f ms", why, on ? "on" : "off", ms))
        if ms > budget { issue("stall", String(format: "%@: turning word wrap %@ took %.0f ms (budget %.0f ms)", why, on ? "on" : "off", ms, budget), snap: false) }
        return ms
    }
}

// MARK: - 말뭉치

extension RealUse {
    /// 3,000 줄: 대부분 짧고 몇 줄만 길다 — 5번 줄(약 300자, 첫 화면), 60번 줄(약 600자, 첫 화면 바로 아래), 2500번 줄(약 2,000자, 멀리 아래쪽의 가장 긴 줄)
    static func noWrapDoc() -> String {
        (1...3000).map { i -> String in
            switch i {
            case 5: return "5 " + String(repeating: "abcdefghij", count: 30) + " END5"
            case 7: return "7\t탭과 한글이 섞인 줄\tcolumn\t끝"
            case 60: return "60 " + String(repeating: "0123456789", count: 60) + " END60"
            case 2500: return "2500 " + String(repeating: "the widest line ", count: 125) + "END2500"
            default: return i % 9 == 0 ? "\(i) 짧은 한글 줄" : "\(i) short line"
            }
        }.joined(separator: "\n") + "\n"
    }

    /// 화면보다 넓은 고정 폭 줄들 (열 블록·강조 시험용): 한 줄 약 200자, 다섯째 줄마다 짧은 줄
    static func wideColumnDoc(lines: Int = 120) -> String {
        (0..<lines).map { i in
            i % 5 == 4 ? String(format: "%03d|ab", i)
                : String(format: "%03d|", i) + (0..<19).map { String(format: "c%02d:abcdefg", $0) }.joined(separator: "|") + "|tail"
        }.joined(separator: "\n") + "\n"
    }

    /// 오른쪽→왼쪽 글이 섞인 문서: 2 아랍어 · 3 히브리어 · 4 영문 뒤 아랍어 · 5 긴 영문 · 6 긴 아랍어 · 8 아랍어로 시작해 영문으로 끝남, 나머지는 짧은 영문
    static func rtlDoc() -> String {
        (1...200).map { i -> String in
            switch i {
            case 2: return "مرحبا بالعالم هذا سطر عربي قصير"
            case 3: return "שלום עולם זו שורה קצרה בעברית"
            case 4: return "4 mixed: english first then عربي في النهاية"
            case 5: return "5 " + String(repeating: "long english line ", count: 20) + "END5"
            case 6: return String(repeating: "هذا سطر عربي طويل ", count: 20) + "نهاية"
            case 8: return "عربي في البداية then english at the end 8"
            default: return "\(i) short line"
            }
        }.joined(separator: "\n") + "\n"
    }
}

// MARK: - 시나리오

extension RealUse {
    @MainActor static let noWrapScenarios: [Scenario] = [
        // 가로 스크롤 범위: 화면에 있는 가장 긴 줄의 끝까지 갈 수 있고, 멀리 아래의 더 긴 줄도 거기 가면 닿는다. 가로로 밀어 둔 채 세로로 움직여도 옆으로 튀지 않는다
        Scenario(name: "nowrap-hscroll") { ctx in
            let saved = ViewDefaults(ctx)
            await ctx.withRelaxedStalls { await ctx.open(text: noWrapDoc(), name: "nowrap-h.md") }
            await ctx.key(.up, [.command]); await ctx.settle(200)
            ctx.at("wrap off at the top")
            ctx.hstate("before")
            await ctx.setWrap(false, "3,000-line document, at the top")
            ctx.hstate("wrap off")
            if !ctx.scroll.hasHorizontalScroller { ctx.issue("hscroll", "word wrap is off but the editor has no horizontal scroller") }
            ctx.checkAll("wrap off at the top"); ctx.checkInk("wrap off at the top")
            ctx.checkReaches(line: 5, "wrap off at the top"); ctx.checkReaches(line: 7, "wrap off at the top")
            ctx.checkX(0, "wrap off at the top")
            ctx.snap("top")

            ctx.at("horizontal wheel")
            let clipW = ctx.scroll.contentView.bounds.width
            await ctx.hscrollBy(300); await ctx.settle(60)
            ctx.checkX(300, "horizontal wheel 300"); ctx.checkAll("horizontal wheel 300")
            let y0 = ctx.visible.minY
            await ctx.hscrollBy(-300); await ctx.settle(60)
            ctx.checkX(0, "horizontal wheel back"); ctx.checkViewportStable(from: y0, tolerance: 1, "horizontal wheel")
            // 오른쪽 끝까지: 더 갈 수 없는 곳이 텍스트 뷰의 오른쪽 가장자리이고, 5번 줄의 끝이 그 안에 보인다
            await ctx.hscrollBy(100_000); await ctx.settle(100)
            ctx.hstate("scrolled to the right end")
            if abs(ctx.visible.maxX - ctx.tv.frame.width) > 1 { ctx.issue("hscroll", "scrolled right as far as it goes, but the view ends at x \(Int(ctx.visible.maxX)) of \(Int(ctx.tv.frame.width))") }
            if let x = ctx.endX(ofLine: 5), x < ctx.visible.minX || x > ctx.visible.maxX { ctx.issue("hscroll", "at the right end the end of line 5 (x \(Int(x))) is not in view (x \(Int(ctx.visible.minX))…\(Int(ctx.visible.maxX)))") }
            ctx.checkGutter("at the right end"); ctx.snap("right-end")
            await ctx.hscrollBy(-100_000); await ctx.settle(100)
            ctx.checkX(0, "scrolled back to the left")

            // 첫 화면 바로 아래의 더 긴 줄(60번): 휠로 내려가면 그 줄의 끝까지 갈 수 있어야 한다
            ctx.at("wheel down to a longer line")
            let w0 = ctx.tv.frame.width
            for _ in 0..<8 { await ctx.scrollBy(150); await ctx.settle(0) }
            await ctx.settle(100)
            ctx.hstate("line 60 on screen")
            ctx.checkAll("line 60 on screen"); ctx.checkInk("line 60 on screen")
            ctx.checkReaches(line: 60, "line 60 on screen")
            ctx.note(String(format: "text view width at the top %.1f, with line 60 on screen %.1f", w0, ctx.tv.frame.width))

            // 멀리 아래의 가장 긴 줄(2500번): 줄 이동 → 줄 끝으로
            ctx.at("go to the widest line")
            let jumpMs = await ctx.timed { ctx.model.jump(toLine: 2500); await ctx.settle(400) } - 400
            ctx.note(String(format: "go to line 2500 took %.0f ms", jumpMs))
            // 실측 17~38 ms (2,500줄 떨어진 가장 긴 줄로: 폭을 넓히고 보던 곳을 맞춘다). 150 ms 를 넘으면 그 사이의 줄을 배치하고 있는 것이다
            if jumpMs > 150 { ctx.issue("stall", String(format: "word wrap off: go to line 2500 took %.0f ms (budget 150 ms)", jumpMs), snap: false) }
            ctx.hstate("line 2500 on screen")
            ctx.checkAll("go to line 2500"); ctx.checkCaretInView("go to line 2500")
            ctx.checkReaches(line: 2500, "line 2500 on screen")
            await ctx.key(.right, [.command]); await ctx.settle(100)
            ctx.expectSel(NSRange(location: ctx.lineEnd(2500), length: 0), "⌘→ on line 2500")
            ctx.checkCaretInView("⌘→ on line 2500"); ctx.checkAll("⌘→ on line 2500")
            ctx.hstate("at the end of line 2500")
            if ctx.visible.minX < clipW { ctx.issue("hscroll", "⌘→ to the end of a 2,000-character line left the view at x \(Int(ctx.visible.minX))") }
            ctx.snap("widest-end")

            // 긴 줄의 끝을 보는 채로 글자 크기를 바꾼다: 같은 글자들(줄 끝)이 계속 보인다 — 가로 위치가 처음 열로 돌아가면 안 된다
            ctx.at("text size while scrolled sideways")
            let size0 = ctx.model.font.size
            for (label, action) in [("larger text", { ctx.model.adjustFontSize(2) }), ("default text size", { ctx.model.font.size = size0 }),
                                    ("smaller text", { ctx.model.adjustFontSize(-2) }), ("default text size again", { ctx.model.font.size = size0 })] as [(String, () -> Void)] {
                let xBefore = ctx.visible.minX
                action(); await ctx.settle(350)
                ctx.hstate(label)
                ctx.checkCaretInView("\(label) at the end of line 2500"); ctx.checkReaches(line: 2500, label); ctx.checkAll(label)
                if ctx.visible.minX < xBefore / 2 { ctx.issue("hscroll", "\(label): the view was at x \(Int(xBefore)) showing the end of line 2500 and went back to x \(Int(ctx.visible.minX))") }
            }
            // 밖에서 바뀐 파일을 다시 읽어도(덧붙여지는 로그) 가로 위치는 그대로다
            ctx.at("reload while scrolled sideways")
            let xReload = ctx.visible.minX, topReload = ctx.topLine()
            ctx.model.reloadFromDisk(); await ctx.settle(500)
            ctx.hstate("reloaded from disk")
            if abs(ctx.visible.minX - xReload) > 1 { ctx.issue("hscroll", "reloading the file moved the view sideways from x \(Int(xReload)) to \(Int(ctx.visible.minX))") }
            if abs(ctx.topLine() - topReload) > 1 { ctx.issue("viewport-jump", "reloading the file moved the view from line \(topReload) to \(ctx.topLine())") }
            ctx.checkAll("reloaded from disk")

            // 가로로 밀어 둔 채 세로로 움직인다: 가장 긴 줄이 화면 밖으로 나가도 가로 위치가 그대로다 (폭이 줄어들며 내용이 옆으로 튀면 안 된다)
            ctx.at("vertical wheel while scrolled sideways")
            let x1 = ctx.visible.minX, w1 = ctx.tv.frame.width
            for d in [-600, -900, -900, 1200] as [CGFloat] {
                await ctx.scrollBy(d); await ctx.settle(60)
                if abs(ctx.visible.minX - x1) > 1 { ctx.issue("hscroll", "wheel \(Int(d)) with the view at x \(Int(x1)): the view jumped sideways to x \(Int(ctx.visible.minX)) (text view width \(Int(w1)) → \(Int(ctx.tv.frame.width)))") }
                ctx.checkLayout("wheel \(Int(d)) while scrolled sideways")
            }
            ctx.hstate("after vertical wheels")
            if ctx.tv.frame.width < w1 - 1 { ctx.note(String(format: "the text view got narrower while scrolling away from the widest line: %.1f → %.1f", w1, ctx.tv.frame.width)) }
            ctx.snap("sideways")

            ctx.at("back to column 1 and the top")
            ctx.model.jump(toLine: 2400); await ctx.settle(300)
            ctx.checkCaretInView("go to line 2400 (short line) from a sideways view")
            ctx.hstate("go to a short line")
            await ctx.key(.up, [.command]); await ctx.settle(300)
            ctx.checkX(0, "⌘↑"); ctx.checkAll("⌘↑"); ctx.checkInk("⌘↑")
            ctx.hstate("back at the top")

            // 다시 켜면 가로 막대가 사라지고 폭이 편집기 폭으로 돌아온다
            ctx.at("wrap back on")
            await ctx.setWrap(true, "3,000-line document, back at the top")
            ctx.hstate("wrap on")
            if ctx.scroll.hasHorizontalScroller { ctx.issue("hscroll", "word wrap is on but the horizontal scroller is still there") }
            if abs(ctx.tv.frame.width - ctx.scroll.contentView.bounds.width) > 1 { ctx.issue("hscroll", "word wrap is on but the text view is \(Int(ctx.tv.frame.width)) pt wide in a \(Int(ctx.scroll.contentView.bounds.width)) pt editor") }
            ctx.checkX(0, "wrap on"); ctx.checkAll("wrap on"); ctx.checkInk("wrap on")
            await saved.restore(ctx)
        },

        // 캐럿을 따라가는 가로 스크롤: 줄 끝·줄 머리, → 로 오른쪽 가장자리 넘기, 타이핑으로 넘기, 한글 조합, 오른쪽 멀리 있는 찾기 결과
        Scenario(name: "nowrap-caret") { ctx in
            let saved = ViewDefaults(ctx)
            await ctx.withRelaxedStalls { await ctx.open(text: noWrapDoc(), name: "nowrap-c.md") }
            await ctx.key(.up, [.command]); await ctx.settle(200)
            await ctx.setWrap(false, "3,000-line document")
            let clipW = ctx.scroll.contentView.bounds.width

            ctx.at("⌘→ and ⌘← on a long line")
            guard await ctx.clickCaret(ctx.lineStart(5), "the head of line 5") else { await saved.restore(ctx); return }
            await ctx.press(.right, [.command]); await ctx.settle(60)
            ctx.expectSel(NSRange(location: ctx.lineEnd(5), length: 0), "⌘→ on line 5")
            ctx.checkCaretInView("⌘→ on line 5"); ctx.checkAll("⌘→ on line 5")
            if ctx.visible.minX < 1 { ctx.issue("hscroll", "⌘→ to the end of a 300-character line did not scroll sideways") }
            ctx.hstate("⌘→ on line 5"); ctx.snap("line-end")
            await ctx.press(.left, [.command]); await ctx.settle(60)
            ctx.expectSel(NSRange(location: ctx.lineStart(5), length: 0), "⌘← on line 5")
            ctx.checkCaretInView("⌘← on line 5"); ctx.checkX(0, "⌘← on line 5")

            // → 로 한 글자씩: 오른쪽 가장자리를 넘는 순간부터 캐럿이 계속 보인다
            ctx.at("→ across the right edge")
            var hidden = 0, firstHidden = -1
            for i in 1...150 {
                await ctx.press(.right)
                if let r = ctx.tv.caretRect(at: ctx.caret), r.maxX > ctx.visible.maxX + 1 || r.minX < ctx.visible.minX - 1 { hidden += 1; if firstHidden < 0 { firstHidden = i } }
            }
            await ctx.settle(60)
            if hidden > 0 { ctx.issue("caret-hidden", "→ × 150 along line 5: the caret was outside the visible columns after \(hidden) presses (first at #\(firstHidden))") }
            ctx.expectSel(NSRange(location: ctx.lineStart(5) + 150, length: 0), "→ × 150")
            if ctx.visible.minX < 1 { ctx.issue("hscroll", "→ × 150 (past the right edge at about column \(Int(clipW / max(1, ctx.tv.charWidth)))) did not scroll sideways") }
            ctx.checkAll("→ × 150"); ctx.hstate("→ × 150")
            // ← 로 되돌아가 왼쪽 가장자리를 넘는다
            hidden = 0
            var hiddenAt: [String] = []
            for i in 1...150 {
                await ctx.press(.left)
                if let r = ctx.tv.caretRect(at: ctx.caret), r.maxX > ctx.visible.maxX + 1 || r.minX < ctx.visible.minX - 1 {
                    hidden += 1
                    if hiddenAt.count < 4 { hiddenAt.append(String(format: "#%d caret x %.1f…%.1f, view x %.1f…%.1f", i, r.minX, r.maxX, ctx.visible.minX, ctx.visible.maxX)) }
                }
            }
            await ctx.settle(60)
            if hidden > 0 { ctx.issue("caret-hidden", "← × 150 back along line 5: the caret was outside the visible columns after \(hidden) presses (\(hiddenAt.joined(separator: "; ")))") }
            ctx.checkX(0, "← × 150 back to column 1")

            // 짧은 줄 끝에서 타이핑으로 오른쪽 가장자리를 넘긴다 (지금까지의 어느 줄보다 길어진다 — 텍스트 뷰가 따라 넓어져야 한다)
            ctx.at("type past the right edge")
            guard await ctx.clickCaret(ctx.lineEnd(12), "the end of line 12") else { await saved.restore(ctx); return }
            let expect = NSMutableString(string: ctx.textCopy() as String)
            var at = ctx.caret
            let w0 = ctx.tv.frame.width
            hidden = 0
            let chunk = " typing past the edge"
            for _ in 0..<20 {
                await ctx.typeKeys(chunk)
                expect.insert(chunk, at: at); at += (chunk as NSString).length
                if let r = ctx.tv.caretRect(at: ctx.caret), r.maxX > ctx.visible.maxX + 1 || r.minX < ctx.visible.minX - 1 { hidden += 1 }
            }
            await ctx.quiesce()
            if hidden > 0 { ctx.issue("caret-hidden", "typing 420 characters on line 12: the caret was outside the visible columns after \(hidden) of 20 chunks") }
            ctx.expectText(expect, "typed past the right edge"); ctx.expectSel(NSRange(location: at, length: 0), "typed past the right edge")
            ctx.checkCaretInView("typed past the right edge"); ctx.checkAll("typed past the right edge")
            ctx.checkReaches(line: 12, "typed past the right edge")
            ctx.hstate("typed 420 characters on line 12")
            ctx.note(String(format: "text view width before typing %.1f, after %.1f", w0, ctx.tv.frame.width))
            ctx.snap("typed")
            ctx.at("compose Hangul past the right edge")
            await ctx.composeKeys("한글 조합 입력"); await ctx.quiesce()
            expect.insert("한글 조합 입력", at: at); at += 8
            ctx.expectText(expect, "composed Hangul past the right edge"); ctx.expectSel(NSRange(location: at, length: 0), "composed Hangul past the right edge")
            ctx.checkCaretInView("composed Hangul past the right edge"); ctx.checkReaches(line: 12, "composed Hangul past the right edge")
            // 조합 중인 글자(밑줄)도 보인다
            await ctx.composeOnly("끝")
            if let r = ctx.tv.caretRect(at: ctx.caret), r.maxX > ctx.visible.maxX + 1 || r.minX < ctx.visible.minX - 1 { ctx.issue("caret-hidden", "while composing past the right edge the caret (x \(Int(r.minX))) is outside x \(Int(ctx.visible.minX))…\(Int(ctx.visible.maxX))") }
            await ctx.commitComposition("끝"); await ctx.quiesce()
            expect.insert("끝", at: at); at += 1
            ctx.expectText(expect, "committed the composing syllable")
            ctx.snap("composed")
            // Enter: 새 줄의 첫 칸으로 — 가로 위치가 0 으로 돌아온다
            ctx.at("enter after a long line")
            await ctx.press(.returnKey); await ctx.quiesce()
            ctx.checkCaretInView("Enter after a long line"); ctx.checkX(0, "Enter after a long line")
            await ctx.press(.delete); await ctx.quiesce()
            ctx.checkCaretInView("Backspace joined back onto the long line")
            if ctx.visible.minX < 1 { ctx.issue("hscroll", "after joining back onto the end of the long line the view did not scroll to the caret") }
            await ctx.settle(350)
            ctx.checkGutter("after typing on line 12")

            // 찾기: 오른쪽 멀리 있는 결과로 점프하면 그 결과가 가로로도 보인다
            ctx.at("find a match far to the right")
            await ctx.key(.up, [.command]); await ctx.settle(200)
            let m = ctx.model
            m.findInEditor(); await ctx.settle(200)
            for q in ["END60", "END2500", "END5"] {
                let gen = m.searchCompletionCount
                ctx.typeQuery(q)
                guard await ctx.awaitSearch(after: gen), let hit = m.searchHits.first else { ctx.issue("find", "'\(q)' search did not finish"); continue }
                m.jump(to: hit); await ctx.settle(450)
                ctx.expectSel(hit.range, "jumped to '\(q)'")
                if let a = ctx.tv.caretRect(at: hit.range.location), let b = ctx.tv.caretRect(at: NSMaxRange(hit.range)) {
                    let v = ctx.visible
                    if a.minX < v.minX - 1 || b.minX > v.maxX + 1 || a.minY < v.minY - 1 || a.maxY > v.maxY + 1 {
                        ctx.issue("caret-hidden", "jumped to '\(q)' (x \(Int(a.minX))…\(Int(b.minX)), y \(Int(a.minY))) but the view shows x \(Int(v.minX))…\(Int(v.maxX)), y \(Int(v.minY))…\(Int(v.maxY))")
                    }
                }
                ctx.checkAll("jumped to '\(q)'"); ctx.hstate("jumped to '\(q)'")
                if q == "END2500" { ctx.snap("find-far-right") }
            }
            m.closeQuickFind(); await ctx.settle(300)
            await saved.restore(ctx)
        },

        // 그리기: 현재 줄 띠·거터·열 블록·멀티 캐럿·검색 강조·스크롤 마커 — 가로로 밀지 않았을 때와 밀었을 때
        Scenario(name: "nowrap-draw") { ctx in
            let saved = ViewDefaults(ctx)
            await ctx.withRelaxedStalls { await ctx.open(text: wideColumnDoc(), name: "nowrap-d.md") }
            await ctx.key(.up, [.command]); await ctx.settle(200)
            await ctx.setWrap(false, "120 wide lines")
            let cw = ctx.tv.charWidth
            @MainActor func pt(_ line: Int, _ col: Int) -> NSPoint? {
                guard let r = ctx.tv.caretRect(at: ctx.lineStart(line) + col) else { return nil }
                let p = NSPoint(x: r.minX + 1, y: r.midY)
                return ctx.visible.contains(p) ? p : nil
            }
            for (tag, x) in [("unscrolled", CGFloat(0)), ("scrolled sideways", CGFloat(600))] {
                ctx.at("\(tag): band and gutter")
                if x > 0 { await ctx.hscrollBy(x); await ctx.settle(100); ctx.checkX(x, "\(tag)") }
                let col = Int((x / cw).rounded()) + 20
                guard let p = pt(4, col) else { ctx.issue("other", "\(tag): line 4 column \(col) is not on screen"); continue }
                await ctx.mclick(atViewPoint: p); await ctx.settle(100)
                ctx.expectSel(NSRange(location: ctx.lineStart(4) + col, length: 0), "\(tag): clicked line 4 column \(col)")
                // 왼쪽 여백 열로 띠를 재는 검사와 잉크 검사는 가로로 밀지 않았을 때만 뜻이 있다 (밀어 두면 그 열에 글자가 오고, 짧은 줄은 보이는 폭에 글자가 없다)
                if x == 0 { ctx.checkLineHighlight("\(tag): caret on line 4"); ctx.checkInk("\(tag): caret on line 4") }
                ctx.checkBandAcrossWidth("\(tag): caret on line 4"); ctx.checkAll("\(tag): caret on line 4")
                ctx.checkX(x, "\(tag): after a click")
                // 열 블록: ⌥ 끌기 4줄 × 12열 (6…9번 줄 — 모두 긴 줄)
                ctx.at("\(tag): column block")
                guard let a = pt(6, col), let b = pt(9, col + 12) else { ctx.issue("other", "\(tag): block corners are not on screen"); continue }
                await ctx.dragWith(mods: .option, from: a, to: b); await ctx.settle(100)
                if let blk = ctx.tv.multi?.block {
                    let lo = min(blk.anchorCol, blk.headCol), hi = max(blk.anchorCol, blk.headCol)
                    if blk.lineCount != 4 || lo != col || hi != col + 12 {
                        ctx.issue("multi", "\(tag): ⌥-dragged lines 6…9 columns \(col)…\(col + 12) but the block is \(blk.lineCount) lines, columns \(lo)…\(hi)")
                    }
                } else { ctx.issue("multi", "\(tag): ⌥-drag made no column block (selection \(ctx.tv.selectedRange()))") }
                ctx.expectBlockHighlighted("\(tag): column block"); ctx.checkBlockPainted("\(tag): column block")
                ctx.checkX(x, "\(tag): after the block drag")
                ctx.snap("\(tag.replacingOccurrences(of: " ", with: "-"))-block")
                let before = ctx.textCopy()
                await ctx.typeKeys("#"); await ctx.quiesce()
                // 고른 12열이 줄마다 한 글자로 바뀐다: 4줄 × (1 − 12)
                if ctx.length - before.length != 4 * (1 - 12) { ctx.issue("multi", "\(tag): typed one character over a 4-line × 12-column block but the text length changed by \(ctx.length - before.length), expected \(4 * (1 - 12))") }
                for line in 6...9 where ctx.text.character(at: ctx.lineStart(line) + col) != 35 { ctx.issue("multi", "\(tag): line \(line) column \(col) should hold the typed character after the block edit"); break }
                ctx.checkAll("\(tag): typed into the block"); ctx.checkX(x, "\(tag): after typing into the block")
                await ctx.undo(); await ctx.quiesce()
                ctx.expectText(before, "\(tag): undo of the block edit")
                await ctx.press(.escape); await ctx.settle(60)
                // 짧은 줄을 지나가는 블록(8…11번 줄 — 10번 줄은 6자): 짧은 줄에서는 블록이 줄 끝 너머의 빈 칸에 놓인다. 끄는 동안 화면이 옆으로 튀지 않아야 한다
                ctx.at("\(tag): column block across a short line")
                if let a = pt(8, col), let b = pt(11, col + 12) {
                    await ctx.dragWith(mods: .option, from: a, to: b); await ctx.settle(100)
                    if let blk = ctx.tv.multi?.block {
                        let lo = min(blk.anchorCol, blk.headCol), hi = max(blk.anchorCol, blk.headCol)
                        if blk.lineCount != 4 || lo != col || hi != col + 12 {
                            ctx.issue("multi", "\(tag): ⌥-dragged lines 8…11 (line 10 is short) columns \(col)…\(col + 12) but the block is \(blk.lineCount) lines, columns \(lo)…\(hi) — the view moved sideways to x \(Int(ctx.visible.minX)) during the drag")
                        }
                    } else { ctx.issue("multi", "\(tag): ⌥-drag across a short line made no column block") }
                    ctx.expectBlockHighlighted("\(tag): column block across a short line"); ctx.checkBlockPainted("\(tag): column block across a short line")
                    ctx.checkX(x, "\(tag): after the block drag across a short line")
                    ctx.snap("\(tag.replacingOccurrences(of: " ", with: "-"))-block-short-line")
                    let before2 = ctx.textCopy()
                    await ctx.typeKeys("#"); await ctx.quiesce()
                    // 긴 줄 셋은 12열이 한 글자로, 짧은 줄은 빈 칸을 공백으로 채우고 한 글자: 3 × (1 − 12) + (col − 6 + 1)
                    let want = 3 * (1 - 12) + (col - 6 + 1)
                    if ctx.length - before2.length != want { ctx.issue("multi", "\(tag): typed into a block across a short line: the text length changed by \(ctx.length - before2.length), expected \(want)") }
                    await ctx.undo(); await ctx.quiesce()
                    ctx.expectText(before2, "\(tag): undo of the block edit across a short line")
                    await ctx.press(.escape); await ctx.settle(60)
                    if abs(ctx.visible.minX - x) > 1 { await ctx.hscrollBy(x - ctx.visible.minX); await ctx.settle(60) }
                }
                // ⌘클릭 멀티 캐럿
                ctx.at("\(tag): ⌘-click carets")
                if let p1 = pt(13, col + 3), let p2 = pt(14, col + 7), let p3 = pt(16, col + 1) {
                    await ctx.mclick(atViewPoint: p1)
                    await ctx.mclick(atViewPoint: p2, mods: .command); await ctx.mclick(atViewPoint: p3, mods: .command)
                    await ctx.settle(60)
                    let want = [ctx.lineStart(13) + col + 3, ctx.lineStart(14) + col + 7, ctx.lineStart(16) + col + 1]
                    let got = ctx.tv.multi?.ranges.map(\.location) ?? []
                    if got != want { ctx.issue("multi", "\(tag): ⌘-clicked three places \(want) but the carets are at \(got)") }
                    ctx.checkX(x, "\(tag): after ⌘-clicks")
                    await ctx.press(.escape); await ctx.settle(60)
                }
                // 검색 강조
                ctx.at("\(tag): find highlights")
                let m = ctx.model
                m.findInEditor(); await ctx.settle(200)
                let gen = m.searchCompletionCount
                ctx.typeQuery("c0\(Int((x / cw).rounded()) / 11 + 3):abc")
                if await ctx.awaitSearch(after: gen), !m.searchHits.isEmpty {
                    // 빠른 찾기는 첫 결과로 점프한다 — 보던 가로 위치로 되돌려 놓고 강조를 본다
                    await ctx.key(.up, [.command]); await ctx.settle(150)
                    if x > 0 { await ctx.hscrollBy(x - ctx.visible.minX); await ctx.settle(100) }
                    let n = ctx.checkHighlightPaint("\(tag): find highlights")
                    if n == 0 { ctx.issue("highlight", "\(tag): \(m.searchHits.count) matches but none could be checked on screen (view x \(Int(ctx.visible.minX)))") }
                    ctx.note("\(tag): \(n) visible matches painted")
                    ctx.snap("\(tag.replacingOccurrences(of: " ", with: "-"))-find")
                    // 스크롤 마커 띠: 편집기 오른쪽 가장자리에 붙어 있고 결과 눈금이 그려진다
                    if let mv = ctx.coord.container?.markerView, let box = ctx.coord.container {
                        // 띠는 오른쪽 가장자리에 붙는다 — '스크롤 막대 항상 보기' 설정이면 세로 막대(17 pt)의 왼쪽
                        if abs(mv.frame.maxX - box.bounds.maxX) > 20 || abs(mv.frame.height - box.bounds.height) > 1 {
                            ctx.issue("other", "\(tag): the scroll marker strip is at \(mv.frame) in an editor of \(box.bounds.size)")
                        }
                        if let rep = mv.bitmapImageRepForCachingDisplay(in: mv.bounds) {
                            mv.cacheDisplay(in: mv.bounds, to: rep)
                            var painted = 0
                            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) { if let c = rep.colorAt(x: rep.pixelsWide / 2, y: y), c.alphaComponent > 0.3 { painted += 1 } }
                            if painted == 0 { ctx.issue("other", "\(tag): \(m.searchHits.count) matches but the scroll marker strip is empty") }
                        }
                    }
                } else { ctx.issue("find", "\(tag): search did not finish") }
                m.closeQuickFind(); await ctx.settle(300)
                await ctx.hscrollBy(-100_000); await ctx.settle(100)
            }
            await saved.restore(ctx)
        },

        // 오른쪽→왼쪽 글: 줄바꿈을 끈 상태에서 아랍어·히브리어 줄이 어디에 그려지는가 (줄바꿈 켬과 견줘 기록한다), 그 줄에서의 클릭·줄 끝 이동
        Scenario(name: "nowrap-rtl") { ctx in
            let saved = ViewDefaults(ctx)
            await ctx.withRelaxedStalls { await ctx.open(text: rtlDoc(), name: "nowrap-rtl.md") }
            await ctx.key(.up, [.command]); await ctx.settle(200)
            _ = await ctx.clickCaret(ctx.lineStart(1), "line 1")
            ctx.at("wrap on")
            ctx.hstate("wrap on")
            for n in [2, 3, 4, 6, 8] { ctx.placement(ofLine: n, "wrap on") }
            ctx.snap("wrap-on")
            ctx.at("wrap off")
            await ctx.setWrap(false, "right-to-left document")
            ctx.hstate("wrap off")
            var placed: [Int: (frameX: CGFloat, frameW: CGFloat, headX: CGFloat, tailX: CGFloat, ink: (minX: CGFloat, maxX: CGFloat)?)] = [:]
            for n in [2, 3, 4, 6, 8] { placed[n] = ctx.placement(ofLine: n, "wrap off") }
            ctx.checkAll("wrap off"); ctx.checkInk("wrap off")
            ctx.snap("wrap-off")
            // 오른쪽→왼쪽 문단은 왼쪽 여백에서 시작해 그려진다 (줄바꿈 끔: 줄의 폭이 곧 내용의 폭이다 — 2026-11-25 수정 전 빌드에서 잰 자리와 같다)
            let margin = ctx.tv.textContainerOrigin.x + (ctx.tv.textContainer?.lineFragmentPadding ?? 0)
            for n in [2, 3, 6] {
                guard let p = placed[n], let ink = p.ink else { ctx.issue("other", "wrap off: line \(n) is not drawn on screen"); continue }
                if abs(ink.minX - margin) > 6 { ctx.issue("rtl", "wrap off: the right-to-left line \(n) is drawn from x \(String(format: "%.1f", ink.minX)), expected it to start at the left margin \(String(format: "%.1f", margin))") }
                // 오른쪽→왼쪽 문단의 머리(첫 글자)는 오른쪽 끝, 끝은 왼쪽 끝이다
                if p.headX <= p.tailX { ctx.issue("rtl", "wrap off: line \(n) is right-to-left but its first character (x \(Int(p.headX))) is not to the right of its last (x \(Int(p.tailX)))") }
            }
            // 긴 아랍어 줄(6번)의 머리는 화면 밖 오른쪽에 있다: 줄 머리로 가면(⌘→ = 오른쪽 끝) 보이게 밀린다
            ctx.at("ends of a long right-to-left line")
            ctx.checkReaches(line: 5, "wrap off")
            if let p = placed[6], ctx.tv.frame.width < max(p.headX, p.tailX) - 0.5 { ctx.issue("hscroll", "the long right-to-left line 6 spans to x \(Int(max(p.headX, p.tailX))) but the text view is \(Int(ctx.tv.frame.width)) pt wide") }
            if let p = ctx.point(forOffset: ctx.lineEnd(6), dx: 3) {
                await ctx.mclick(atViewPoint: p); await ctx.settle(60)
                ctx.note("clicked the left end of line 6 → caret at \(ctx.place(ctx.caret)) (line end is \(ctx.lineEnd(6)))")
                ctx.checkCaretInView("clicked the left end of the right-to-left line 6")
                await ctx.press(.right, [.command]); await ctx.settle(60)
                ctx.note("⌘→ on line 6 → caret at \(ctx.place(ctx.caret)), view x \(Int(ctx.visible.minX))")
                ctx.checkCaretInView("⌘→ on the right-to-left line 6"); ctx.checkAll("⌘→ on line 6")
                ctx.snap("rtl-right-end")
                await ctx.press(.left, [.command]); await ctx.settle(60)
                ctx.note("⌘← on line 6 → caret at \(ctx.place(ctx.caret)), view x \(Int(ctx.visible.minX))")
                ctx.checkCaretInView("⌘← on the right-to-left line 6")
            } else { ctx.issue("other", "the end of line 6 is not on screen") }
            // 오른쪽→왼쪽 줄에 타이핑
            ctx.at("type on a right-to-left line")
            if await ctx.clickCaret(ctx.lineEnd(2), "the end of line 2") {
                await ctx.typeKeys(" نص"); await ctx.quiesce()
                ctx.checkCaretInView("typed Arabic at the end of line 2"); ctx.checkAll("typed Arabic at the end of line 2")
                ctx.placement(ofLine: 2, "after typing")
            }
            ctx.at("wrap back on")
            await ctx.setWrap(true, "right-to-left document")
            for n in [2, 6] { ctx.placement(ofLine: n, "wrap back on") }
            ctx.checkAll("wrap back on"); ctx.checkInk("wrap back on")
            await saved.restore(ctx)
        },

        // 분할 보기(두 텍스트 뷰), 줄바꿈 켬↔끔 전환 뒤 보던 줄, 탭 전환 뒤의 위치
        Scenario(name: "nowrap-split") { ctx in
            let saved = ViewDefaults(ctx)
            let url = await ctx.open(text: noWrapDoc(), name: "nowrap-s.md")
            await ctx.key(.up, [.command]); await ctx.settle(200)
            await ctx.setWrap(false, "3,000-line document, before splitting")
            ctx.at("split side by side")
            ctx.model.setSplit(.vertical); await ctx.settle(700)
            let cs = ctx.model.session.coordinators
            if cs.count != 2 { ctx.issue("other", "split side by side shows \(cs.count) editors") }
            for c in cs {
                guard let tv = c.textView, let sv = c.scrollView else { continue }
                if tv.textContainer?.widthTracksTextView != false || !sv.hasHorizontalScroller { ctx.issue("hscroll", "split, word wrap off: the \(c.role) editor is not in no-wrap mode (tracks width \(String(describing: tv.textContainer?.widthTracksTextView)), h-scroller \(sv.hasHorizontalScroller))") }
                ctx.note(String(format: "%@ editor: text view width %.1f, clip %.1f, x %.1f", "\(c.role)", tv.frame.width, sv.contentView.bounds.width, tv.visibleRect.minX))
            }
            if let p = ctx.model.session.primary, let s = ctx.model.session.secondary, let ptv = p.textView, let stv = s.textView {
                // 주 편집기만 가로로 민다 — 보조 편집기는 그대로
                ctx.window.makeFirstResponder(ptv); await ctx.settle(60)
                let sx0 = stv.visibleRect.minX
                await ctx.hscrollBy(250); await ctx.settle(100)
                ctx.note(String(format: "after a 250 pt horizontal wheel over the middle of the active editor: primary x %.1f, secondary x %.1f", ptv.visibleRect.minX, stv.visibleRect.minX))
                if abs(ptv.visibleRect.minX - 250) > 1 { ctx.issue("hscroll", "split: horizontal wheel 250 over the primary editor moved it to x \(Int(ptv.visibleRect.minX))") }
                if abs(stv.visibleRect.minX - sx0) > 1 { ctx.issue("hscroll", "split: scrolling the primary editor sideways moved the secondary to x \(Int(stv.visibleRect.minX))") }
                ctx.checkAll("split: primary scrolled sideways")
                // 주 편집기에서 긴 줄을 만든다 — 같은 줄을 보여 주는 보조 편집기도 그 끝까지 갈 수 있어야 한다
                ctx.at("split: type a long line")
                await ctx.hscrollBy(-100_000); await ctx.settle(60)
                if await ctx.clickCaret(ctx.lineEnd(3), "the end of line 3 (primary)") {
                    let w0 = stv.frame.width
                    for _ in 0..<12 { await ctx.typeKeys(" split typing makes this line long") }
                    await ctx.quiesce(); await ctx.settle(200)
                    ctx.checkCaretInView("split: typed a long line in the primary"); ctx.checkReaches(line: 3, "split: primary")
                    let endOff = ctx.lineEnd(3)
                    if let r = stv.caretRect(at: endOff) {
                        ctx.note(String(format: "secondary editor: width %.1f → %.1f, line 3 now ends at x %.1f", w0, stv.frame.width, r.minX))
                        if stv.frame.width < r.minX - 0.5 { ctx.issue("hscroll", "split: line 3 ends at x \(Int(r.minX)) in the secondary editor but that editor is only \(Int(stv.frame.width)) pt wide") }
                    }
                    ctx.snap("split-typed")
                }
            }
            // 분할한 채 글자 크기를 바꾼다: 두 편집기 모두 잰 폭을 글자 폭의 비율만큼 **한 번만** 고친다 — 가장 긴 줄(+ 여백)을 크게 넘는 폭은 빈 가로 스크롤 범위다
            ctx.at("split: text size")
            let splitSize0 = ctx.model.font.size
            for (label, action) in [("larger text", { ctx.model.adjustFontSize(3) }), ("default text size", { ctx.model.font.size = splitSize0 }),
                                    ("smaller text", { ctx.model.adjustFontSize(-3) }), ("default text size again", { ctx.model.font.size = splitSize0 })] as [(String, () -> Void)] {
                action(); await ctx.settle(450)
                for c in ctx.model.session.coordinators {
                    guard let tv = c.textView, let sv = c.scrollView else { continue }
                    // 그 편집기가 배치해 본 가장 긴 줄은 첫 화면의 3번 줄(방금 길게 친 줄)과 5번 줄이다
                    guard let widest = [3, 5].compactMap({ tv.caretRect(at: ctx.lineEnd($0))?.maxX }).max() else { continue }
                    let needed = max(sv.contentView.bounds.width, widest + (tv.textContainer?.lineFragmentPadding ?? 0) + tv.textContainerInset.width)
                    ctx.note(String(format: "split, %@ — %@ editor: text view width %.1f, the widest line seen needs %.1f, x %.1f", label, "\(c.role)", tv.frame.width, needed, tv.visibleRect.minX))
                    if tv.frame.width < needed - 1 { ctx.issue("hscroll", "split, \(label): the \(c.role) editor is \(Int(tv.frame.width)) pt wide but its widest line needs \(Int(needed)) pt") }
                    // 비율로 고친 폭은 어림이다(한글·탭이 섞인 줄은 글자 폭 비율과 조금 다르다) — 2 % + 줄 여백까지는 본다
                    if tv.frame.width > needed * 1.02 + 16 { ctx.issue("hscroll", "split, \(label): the \(c.role) editor is \(Int(tv.frame.width)) pt wide but its widest line needs only \(Int(needed)) pt — \(Int(tv.frame.width - needed)) pt of empty horizontal scroll range") }
                }
                ctx.checkAll("split, \(label)")
            }
            ctx.at("split off")
            let xBefore = ctx.visible.minX
            ctx.model.setSplit(.none); await ctx.settle(600)
            ctx.hstate("split off")
            // 분할을 닫아도 주 편집기의 가로 위치는 그대로다 (넓어진 만큼 오른쪽 끝에 걸리는 것은 빼고)
            if ctx.visible.minX > xBefore + 1 { ctx.issue("hscroll", "closing the split moved the view sideways from x \(Int(xBefore)) to \(Int(ctx.visible.minX))") }
            ctx.checkAll("split off")
            await ctx.press(.left, [.command]); await ctx.settle(100)
            ctx.checkX(0, "⌘← after closing the split"); ctx.checkCaretInView("⌘← after closing the split"); ctx.checkInk("split off, back at column 1")

            // 줄바꿈 켬↔끔: 보던 줄이 그대로 (문서 가운데, 캐럿은 화면 밖)
            await ctx.look(atLine: 1500, wheel: 400)
            await ctx.change("no-wrap doc: wrap on") { ctx.model.wordWrap = true }
            await ctx.change("no-wrap doc: wrap off") { ctx.model.wordWrap = false }
            ctx.hstate("after wrap on → off in the middle")

            // 탭 전환: 가로로 밀어 둔 문서를 떠났다 돌아온다
            ctx.at("tab switch")
            ctx.model.jump(toLine: 2500); await ctx.settle(400)
            await ctx.key(.right, [.command]); await ctx.settle(100)
            let x0 = ctx.visible.minX, top0 = ctx.topLine(), caret0 = ctx.caret
            await ctx.withRelaxedStalls { await ctx.open(.small, name: "nowrap-other.md") }
            ctx.hstate("the other tab")
            ctx.checkX(0, "a short document after a sideways-scrolled one"); ctx.checkAll("the other tab")
            await ctx.withRelaxedStalls { ctx.model.activateTab(url); await ctx.settle(700) }
            ctx.hstate("back on the first tab")
            // 가로 위치는 탭의 보기 상태에 저장하지 않는다 — 돌아오면 첫 열이다 (세로 위치와 캐럿은 되살아난다). 바라는 동작이 정해진 것이 아니라 기록만 한다
            ctx.note(String(format: "tab switch: left at x %.1f top line %d caret %d → back at x %.1f top line %d caret %d (the sideways position is not part of the saved view state)", x0, top0, caret0, ctx.visible.minX, ctx.topLine(), ctx.caret))
            if ctx.caret != caret0 { ctx.issue("selection", "tab switch: the caret was at \(caret0), back on the tab it is at \(ctx.caret)") }
            if abs(ctx.topLine() - top0) > 1 { ctx.issue("viewport-jump", "tab switch: was looking at line \(top0), back on the tab the top line is \(ctx.topLine())") }
            ctx.checkAll("back on the first tab"); ctx.checkInk("back on the first tab")
            ctx.snap("tab-back")
            await ctx.withRelaxedStalls { await saved.restore(ctx) }
        },

        // 줄바꿈을 끈 채 레이아웃을 바꾼다. 폭이 바뀌는 변화(사이드바·분할·줄 번호)는 아무것도 다시 감지 않으므로 내용이 화면에서 움직이면 안 되고,
        // 테마·구문 색도 그렇다. 글자 크기는 보던 줄을 지킨다. 바꾼 직후의 휠 한 걸음이 그만큼만 움직이는가(change 의 scrollProbe)도 함께 본다
        Scenario(name: "nowrap-layout") { ctx in
            let saved = ViewDefaults(ctx)
            for corpus in [RealUseContext.Corpus.notes, .wide] {
                let tag = corpus == .notes ? "notes" : "wide"
                await ctx.withRelaxedStalls { await ctx.open(corpus, name: "nowrap-l-\(tag).md") }
                await ctx.look(atLine: middleLine(ctx), wheel: 600)
                await ctx.change("\(tag): wrap off") { ctx.model.wordWrap = false }
                ctx.hstate("\(tag): wrap off in the middle")
                let ids = ctx.model.themes.themes.map(\.id)
                if let other = ids.first(where: { $0 != saved.themeID }) {
                    await ctx.change("\(tag), no wrap: theme \(other)", strictPt: 2) { ctx.model.themes.select(id: other) }
                    await ctx.change("\(tag), no wrap: theme back", strictPt: 2) { ctx.model.themes.select(id: saved.themeID) }
                }
                await ctx.change("\(tag), no wrap: syntax colors off", strictPt: 2) { ctx.model.syntaxHighlighting = false }
                await ctx.change("\(tag), no wrap: syntax colors on", strictPt: 2) { ctx.model.syntaxHighlighting = true }
                await ctx.change("\(tag), no wrap: sidebar closed", strictPt: 2) { ctx.model.showFileView = false }
                await ctx.change("\(tag), no wrap: sidebar open", strictPt: 2) { ctx.model.showFileView = true }
                await ctx.change("\(tag), no wrap: line numbers off", strictPt: 2) { ctx.model.showLineNumbers = false }
                await ctx.change("\(tag), no wrap: line numbers on", strictPt: 2) { ctx.model.showLineNumbers = true }
                await ctx.change("\(tag), no wrap: split side by side", strictPt: 2, settleMs: 600) { ctx.model.setSplit(.vertical) }
                await ctx.change("\(tag), no wrap: split off", strictPt: 2, settleMs: 600) { ctx.model.setSplit(.none) }
                await ctx.change("\(tag), no wrap: larger text") { ctx.model.adjustFontSize(2) }
                ctx.hstate("\(tag): larger text")
                await ctx.change("\(tag), no wrap: default text size") { ctx.model.font.size = saved.fontSize }
                ctx.snap("\(tag)-middle")
                // 캐럿이 화면 안에 있을 때: 바꾼 직후 바로 타이핑
                if let a = ctx.anchor() { await ctx.click(offset: a.offset); await ctx.settle(100) }
                await ctx.change("\(tag), no wrap: larger text (caret on screen)", then: .type) { ctx.model.adjustFontSize(2) }
                await ctx.change("\(tag), no wrap: default text size (caret on screen)", then: .type) { ctx.model.font.size = saved.fontSize }
                await ctx.change("\(tag), no wrap: sidebar closed (caret on screen)", strictPt: 2, then: .type) { ctx.model.showFileView = false }
                await ctx.change("\(tag), no wrap: sidebar open (caret on screen)", strictPt: 2, then: .type) { ctx.model.showFileView = true }
                // 문서 끝에서 쓰는 중
                await ctx.key(.down, [.command]); await ctx.settle(250)
                await ctx.type("\n끝에서 쓰는 중 typing at the end"); await ctx.settle(350)
                let steps: [(String, () -> Void)] = [
                    ("larger text", { ctx.model.adjustFontSize(2) }), ("default text size", { ctx.model.font.size = saved.fontSize }),
                    ("smaller text", { ctx.model.adjustFontSize(-2) }), ("default text size again", { ctx.model.font.size = saved.fontSize }),
                    ("sidebar closed", { ctx.model.showFileView = false }), ("sidebar open", { ctx.model.showFileView = true }),
                    ("wrap on", { ctx.model.wordWrap = true }), ("wrap off", { ctx.model.wordWrap = false }),
                ]
                for (label, action) in steps {
                    ctx.at("\(tag), no wrap: at the end — \(label)")
                    action()
                    await ctx.settle(350)
                    let why = "\(tag): at the end of the document, word wrap \(ctx.model.wordWrap ? "on" : "off") — \(label)"
                    ctx.checkCaretVisible(why)
                    let v = ctx.visible, docH = ctx.tv.frame.height
                    if docH > v.height, v.maxY < docH - 2 { ctx.issue("viewport-jump", "\(why): the view was at the end of the document, now \(Int(docH - v.maxY)) pt of the end are below the screen") }
                    ctx.checkAll(why); ctx.checkInk(why)
                    await ctx.type("x"); await ctx.settle(60)
                    ctx.checkCaretVisible("\(why) → type"); ctx.checkLayout("\(why) → type")
                    await ctx.key(.delete); await ctx.settle(350)
                    ctx.checkGutter("\(why) → type, delete")
                }
                ctx.snap("\(tag)-end")
                await ctx.withRelaxedStalls { await saved.restore(ctx) }
            }
        },

        // 타이핑 비용: 같은 문서의 같은 자리에서 줄바꿈을 켰을 때와 껐을 때의 키당 비용을 견준다 (긴 문단이 섞인 1.2 MB 문서, 짧은 줄과 긴 줄 끝에서)
        Scenario(name: "nowrap-typing") { ctx in
            let saved = ViewDefaults(ctx)
            keepAwakeForTiming()
            await ctx.withRelaxedStalls { await ctx.open(.wide, name: "nowrap-t.md") }
            func median(_ v: [Double]) -> Double { let s = v.sorted(); return s.isEmpty ? 0 : s[s.count / 2] }
            var cost: [String: Double] = [:]
            for wrap in [true, false, true, false] {
                // 1.2 MB 문서에서의 전환: 실측 끄기 76~91 ms, 켜기 130 ms (줄바꿈을 끌 때 문서 전체를 배치하던 때는 2 s 를 넘었다)
                if ctx.model.wordWrap != wrap { await ctx.setWrap(wrap, budget: 400, "1.2 MB document of long paragraphs") }
                await ctx.settle(100)
                let tag = wrap ? "wrap on" : "wrap off"
                for (place, line) in [("a short line", 2000), ("the end of a long line", 2002)] {
                    ctx.at("\(tag): type on \(place)")
                    ctx.model.jump(toLine: line); await ctx.settle(400)
                    await ctx.press(.right, [.command]); await ctx.settle(100)
                    let before = ctx.textCopy()
                    let samples = await ctx.typeTimed(" typing cost sample, 한글도 조금 섞는다.")
                    await ctx.quiesce()
                    ctx.checkCaretInView("\(tag): typed on \(place)"); ctx.checkAll("\(tag): typed on \(place)")
                    let m = median(samples.map(\.frameCPU))
                    cost["\(tag) · \(place)"] = min(cost["\(tag) · \(place)"] ?? .greatestFiniteMagnitude, m)
                    ctx.note(String(format: "%@, %@: median %.2f ms of main-thread CPU per key (edit + layout + drawing), wall clock median %.2f ms, n=%d", tag, place, m, median(samples.map(\.frame)), samples.count))
                    await ctx.undo(); await ctx.quiesce()
                    if !ctx.text.isEqual(to: before as String) { for _ in 0..<40 where !ctx.text.isEqual(to: before as String) { await ctx.undo() }; await ctx.quiesce() }
                }
            }
            for place in ["a short line", "the end of a long line"] {
                guard let on = cost["wrap on · \(place)"], let off = cost["wrap off · \(place)"] else { continue }
                ctx.note(String(format: "typing on %@: word wrap on %.2f ms/key, off %.2f ms/key (best of two runs each)", place, on, off))
                // 줄바꿈 끔이 켬의 1.5배 + 2 ms 를 넘으면 문서 크기에 비례하는 일이 키마다 돌고 있는 것이다 (수정 전: 끔 13~16 ms)
                if off > on * 1.5 + 2 { ctx.issue("slow", String(format: "typing on %@ costs %.2f ms per key with word wrap off but %.2f ms with it on", place, off, on), snap: false) }
            }
            await ctx.withRelaxedStalls { await saved.restore(ctx) }
        },

        // 4 MB 로그, 줄바꿈 끔: 열기·휠·처음과 끝·Page Up/Down·클릭·타이핑·찾기 점프 — 멈추지 않고, 휠 델타만큼 움직인다
        Scenario(name: "nowrap-log") { ctx in
            let saved = ViewDefaults(ctx)
            // 말뭉치는 미리 만들어 둔다 (만드는 시간은 재지 않는다)
            let url = ctx.dir.appendingPathComponent("nowrap-server.log")
            await ctx.withRelaxedStalls(20_000) {
                if !FileManager.default.fileExists(atPath: url.path) { try? Bench.makeLogCorpus(targetBytes: 4_000_000, seed: 44).text.write(to: url, atomically: true, encoding: .utf8) }
                await ctx.turn()
            }
            // 견줄 기준: 줄바꿈을 켠 채 같은 파일을 여는 시간
            ctx.at("open with word wrap on")
            var ms = await ctx.timed { ctx.model.open(url: url); await ctx.settle(700) }
            let openOn = ms - 700
            ctx.note(String(format: "word wrap on: opening the 4 MB log took %.0f ms", openOn))
            ctx.at("word wrap off on the open log")
            ms = await ctx.timed { ctx.model.wordWrap = false; await ctx.settle(300) }
            ctx.note(String(format: "turning word wrap off on the 4 MB log took %.0f ms", ms - 300))
            if ms - 300 > 250 { ctx.issue("stall", String(format: "turning word wrap off on a 4 MB log blocked the app for %.0f ms", ms - 300), snap: false) }
            ctx.checkAll("wrap off on the log"); ctx.checkInk("wrap off on the log"); ctx.hstate("wrap off on the log")
            // 줄바꿈을 끈 채 다시 연다 (닫았다가)
            ctx.at("open with word wrap off")
            await ctx.withRelaxedStalls(20_000) { await ctx.open(.small, name: "nowrap-log-other.md") }   // 다른 탭으로 갔다가 돌아오면 같은 저장소에 내용을 통째로 다시 넣는다 (여는 것과 같은 경로)
            ms = await ctx.timed { ctx.model.open(url: url); await ctx.settle(700) }
            let openOff = ms - 700
            ctx.note(String(format: "word wrap off: opening the 4 MB log took %.0f ms (with word wrap on: %.0f ms)", openOff, openOn))
            if openOff > openOn + 250 { ctx.issue("stall", String(format: "word wrap off: opening a 4 MB log took %.0f ms, %.0f ms longer than with word wrap on", openOff, openOff - openOn), snap: false) }
            ctx.tv.window?.makeFirstResponder(ctx.tv)
            ctx.checkAll("opened with word wrap off"); ctx.checkInk("opened with word wrap off"); ctx.hstate("opened with word wrap off")
            ctx.snap("opened")
            // 여기부터는 정지 감시가 그대로 본다 (250 ms). 수정 전에는 걸음마다 십수 초가 걸렸다 — 그런 빌드에서는 몇 걸음만 재고 멈춘다
            let n0 = ctx.issues.count
            @MainActor func stalled() -> Bool { ctx.issues.count - n0 >= 40 }
            ctx.at("⌘↑")
            ms = await ctx.timed { await ctx.key(.up, [.command]); await ctx.settle(200) }
            ctx.note(String(format: "⌘↑ took %.0f ms", ms - 200))
            if ms - 200 > 250 { ctx.issue("stall", String(format: "word wrap off: ⌘↑ in the 4 MB log took %.0f ms", ms - 200), snap: false) }
            ctx.expectTop("after ⌘↑"); ctx.checkAll("at the top"); ctx.checkInk("at the top")
            ctx.at("wheel down")
            let probe = await ctx.timed { await ctx.scrollBy(60); await ctx.settle(0) }
            ctx.note(String(format: "first 60 pt wheel step took %.0f ms", probe))
            let slowBuild = probe > 2000
            if slowBuild { ctx.issue("stall", String(format: "word wrap off: one 60 pt wheel step in the 4 MB log took %.1f s — skipping the long wheel runs", probe / 1000), snap: false) }
            if !slowBuild {
                await ctx.wheelRun("wheel down", steps: 60, by: 60)
                if abs(ctx.visible.minX) > 0.5 { ctx.issue("hscroll", "vertical wheeling moved the view sideways to x \(String(format: "%.1f", ctx.visible.minX))") }
                ctx.at("wheel up")
                await ctx.wheelRun("wheel up", steps: 61, by: -60)
                ctx.expectTop("after the wheel round trip")
                ctx.at("fast wheel")
                await ctx.wheelRun("fast wheel down", steps: 40, by: 1400, deepEvery: 10)
                ctx.hstate("after the fast wheel")
                ctx.at("page keys")
                for k in [RealUseContext.Key.pageDown, .pageDown, .pageUp, .pageDown] {
                    let a = ctx.edgeAnchor(bottom: k == .pageDown)
                    let t = await ctx.timed { await ctx.key(k); await ctx.settle(60) }
                    if t - 60 > 250 { ctx.issue("stall", String(format: "word wrap off: a page key took %.0f ms", t - 60), snap: false) }
                    if let moved = ctx.moved(since: a), abs(abs(moved) - ctx.visible.height) > ctx.lineHeight * 3 { ctx.issue("scroll-delta", "page key moved the content \(Int(moved)) pt in a \(Int(ctx.visible.height)) pt editor") }
                    ctx.checkAll("page key"); ctx.checkInk("page key")
                }
            }
            ctx.at("⌘↓")
            ms = await ctx.timed { await ctx.key(.down, [.command]); await ctx.settle(300) }
            ctx.note(String(format: "⌘↓ took %.0f ms", ms - 300))
            if ms - 300 > 250 { ctx.issue("stall", String(format: "word wrap off: ⌘↓ in the 4 MB log took %.0f ms", ms - 300), snap: false) }
            ctx.checkCaretInView("after ⌘↓"); ctx.checkAll("after ⌘↓"); ctx.checkInk("after ⌘↓"); ctx.expectBottom("after ⌘↓")
            ctx.snap("end")
            if !slowBuild && !stalled() {
                ctx.at("rested wheels at the end")
                await ctx.restedSteps("at the end", [-40, -200, 200, -120, 60])
                ctx.at("go to line and click")
                ms = await ctx.timed { ctx.model.jump(toLine: 20_000); await ctx.settle(400) }
                if ms - 400 > 250 { ctx.issue("stall", String(format: "word wrap off: go to line 20000 took %.0f ms", ms - 400), snap: false) }
                ctx.checkAll("go to line 20000"); ctx.checkCaretInView("go to line 20000")
                await ctx.clickGrid("log, word wrap off, line 20000")
                ctx.at("type in the middle")
                // 화면 가운데에 가까운 줄 가운데 **줄 끝이 보이는 열 안에 있는** 것을 고른다. 줄바꿈 끔에서는 화면보다 긴 줄의 끝이 오른쪽 가장자리 밖이라 누를 수 없다
                // (실측: 이 시나리오가 맨 처음 돌 때 가운데 문단의 줄 끝이 x 929, 보이는 폭 733 — '화면에 없어 누를 수 없다'로 이 걸음이 통째로 빠졌다)
                let v = ctx.visible, ns = ctx.text
                func endOffset(_ f: RealUseContext.Frag) -> Int {
                    var e = f.offset + f.length
                    if e > f.offset, e <= ns.length, ns.character(at: e - 1) == 10 { e -= 1 }
                    return e
                }
                let near = ctx.viewportFragments().filter { $0.minY >= v.minY && $0.maxY <= v.maxY }.sorted { abs($0.minY - v.midY) < abs($1.minY - v.midY) }
                if let f = near.first(where: { (ctx.tv.caretRect(at: endOffset($0))?.maxX ?? .infinity) < v.maxX - 4 }) {
                    let end = endOffset(f)
                    if await ctx.clickCaret(end, "the end of a log line") {
                        ctx.reportTiming(await ctx.typeTimed(" typed into the log with word wrap off, 한글도."), "typing in the 4 MB log, word wrap off", budgetEdit: 8, budgetFrame: 16)
                        await ctx.quiesce()
                        ctx.checkCaretInView("typed in the log"); ctx.checkAll("typed in the log"); ctx.checkInk("typed in the log")
                        await ctx.press(.returnKey); await ctx.typeKeys("new line"); await ctx.quiesce()
                        ctx.checkCaretInView("Enter in the log"); ctx.checkAll("Enter in the log")
                        await ctx.settle(350); ctx.checkGutter("typed in the log")
                    }
                } else { ctx.issue("other", "no line on screen ends inside the visible columns (visible x \(Int(v.minX))…\(Int(v.maxX)))") }
                ctx.at("find jump")
                let m = ctx.model
                m.findInEditor(); await ctx.settle(200)
                let gen = m.searchCompletionCount
                ctx.typeQuery("재시도 후 복구됨")
                if await ctx.awaitSearch(after: gen, timeoutMs: 15_000), m.searchHits.count > 10 {
                    let n = m.searchHits.count
                    for k in [n - 1, 0, n / 2] {
                        let t = await ctx.timed { m.jump(to: m.searchHits[k]); await ctx.settle(450) }
                        if t - 450 > 250 { ctx.issue("stall", String(format: "word wrap off: jumping to a find result took %.0f ms", t - 450), snap: false) }
                        ctx.expectSelectedHit(k, "log: result row \(k)")
                        ctx.checkAll("log: result row \(k)"); ctx.checkInk("log: result row \(k)")
                        await ctx.scrollProbe("log: result row \(k)", by: 120)
                    }
                } else { ctx.issue("find", "log: the search did not finish (\(m.searchHits.count) hits)") }
                m.closeQuickFind(); await ctx.settle(300)
                ctx.at("⌘↑ again")
                await ctx.key(.up, [.command]); await ctx.settle(300)
                ctx.expectTop("after ⌘↑ from the middle"); ctx.checkX(0, "after ⌘↑")
            }
            ctx.at("wrap back on")
            ms = await ctx.timed { ctx.model.wordWrap = true; await ctx.settle(300) }
            ctx.note(String(format: "turning word wrap back on took %.0f ms", ms - 300))
            if ms - 300 > 250 { ctx.issue("stall", String(format: "turning word wrap on in a 4 MB log blocked the app for %.0f ms", ms - 300), snap: false) }
            ctx.checkAll("wrap back on"); ctx.checkInk("wrap back on")
            await ctx.withRelaxedStalls(20_000) { await saved.restore(ctx) }
        },
    ]
}
