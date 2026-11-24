import AppKit
import HyperCore

// 실사용 시뮬레이션 — 마우스: 클릭으로 캐럿 놓기(그려진 글자와 맞는가), 더블·트리플 클릭, 끌어 선택, ⇧클릭, 스크롤 뒤 클릭, 거터 정렬,
// 접기 화살표·표식, ⌘클릭 멀티 캐럿, ⌥끌기 열 블록, 현재 줄 강조, 편집기 가장자리

/// 이 파일의 검사·클릭 수 (코어의 checksRun 은 private 이라 따로 센다 — 시나리오 끝에 로그로 남긴다)
@MainActor enum MouseStats {
    static var checks = 0
    static var clicks = 0
}

// MARK: - 도우미

extension RealUseContext {
    /// 자동 줄바꿈으로 나뉜 시각 줄 하나: 문서 범위와 텍스트 뷰 좌표의 사각형
    struct VisualLine { let range: NSRange; let rect: NSRect }

    /// "offset N (line L col C)" — 문제 설명용 (지금 문자열 기준)
    func place(_ off: Int) -> String {
        let idx = LineIndex(nsString: text)
        let o = min(max(0, off), length)
        let line = idx.lineNumber(forUTF16Offset: o)
        return "offset \(o) (line \(line) col \(o - idx.lineStarts[line - 1]))"
    }

    /// 1-based 줄의 시작 오프셋 (지금 문자열 기준)
    func lineStart(_ line: Int) -> Int {
        let idx = LineIndex(nsString: text)
        return idx.lineStarts[max(0, min(line, idx.lineCount) - 1)]
    }

    /// 1-based 줄의 내용 끝 오프셋 (개행 앞)
    func lineEnd(_ line: Int) -> Int {
        let ns = text
        let r = ns.lineRange(for: NSRange(location: lineStart(line), length: 0))
        var end = NSMaxRange(r)
        if r.length > 0, ns.character(at: end - 1) == 10 { end -= 1 }
        return end
    }

    func liveLine(_ offset: Int) -> Int { LineIndex(nsString: text).lineNumber(forUTF16Offset: min(max(0, offset), length)) }

    /// 문단(오프셋이 든)의 시각 줄들
    func visualLines(ofParagraphAt offset: Int) -> [VisualLine] {
        guard let lm = tv.textLayoutManager, let cs = tv.textContentStorage,
              let loc = cs.location(cs.documentRange.location, offsetBy: min(max(0, offset), length)),
              let frag = lm.textLayoutFragment(for: loc) else { return [] }
        let base = cs.offset(from: cs.documentRange.location, to: frag.rangeInElement.location)
        let o = tv.textContainerOrigin, ff = frag.layoutFragmentFrame
        return frag.textLineFragments.map { lf in
            let b = lf.typographicBounds
            return VisualLine(range: NSRange(location: base + lf.characterRange.location, length: lf.characterRange.length),
                              rect: NSRect(x: ff.minX + b.minX + o.x, y: ff.minY + b.minY + o.y, width: b.width, height: b.height))
        }
    }

    func mouseEv(_ type: NSEvent.EventType, _ pInWindow: NSPoint, clicks: Int = 1, mods: NSEvent.ModifierFlags = []) -> NSEvent? {
        NSEvent.mouseEvent(with: type, location: pInWindow, modifierFlags: mods, timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: type == .leftMouseUp ? 0 : 1)
    }

    /// 큐에 남은 마우스 이벤트를 버린다. 코어의 click 은 mouseUp 을 먼저 큐에 넣고 mouseDown 을 부르는데, ⌘클릭(캐럿 추가)·접기 표식 클릭처럼 텍스트 뷰의
    /// 추적 루프를 타지 않는 경로는 그 mouseUp 을 소비하지 않는다 — 남아 있으면 다음 클릭의 추적 루프가 (다른 자리의) 그 mouseUp 을 받아 끌어서 선택한 것처럼 된다
    func flushMouseEvents() {
        while NSApp.nextEvent(matching: [.leftMouseDown, .leftMouseUp, .leftMouseDragged], until: nil, inMode: .default, dequeue: true) != nil {}
    }

    /// 코어의 click 앞뒤로 남은 마우스 이벤트를 비운다
    func mclick(atViewPoint p: NSPoint, clicks: Int = 1, mods: NSEvent.ModifierFlags = []) async {
        flushMouseEvents()
        MouseStats.clicks += 1
        await click(atViewPoint: p, clicks: clicks, mods: mods)
        flushMouseEvents()
    }

    @discardableResult
    func mclick(offset: Int, clicks: Int = 1, mods: NSEvent.ModifierFlags = []) async -> Bool {
        guard let p = point(forOffset: offset) else { return false }
        await mclick(atViewPoint: p, clicks: clicks, mods: mods)
        return true
    }

    func mdrag(from a: NSPoint, to b: NSPoint, steps: Int = 6) async {
        flushMouseEvents()
        await drag(from: a, to: b, steps: steps)
        flushMouseEvents()
    }

    /// 수식 키를 누른 채 끌기 (⌥ = 열 블록, 없음 = 일반 선택). 코어의 drag 와 같은 방식 — 끌기·떼기 이벤트를 먼저 큐에 넣고 텍스트 뷰의 mouseDown 을 직접 부른다
    func dragWith(mods: NSEvent.ModifierFlags, from a: NSPoint, to b: NSPoint, steps: Int = 6) async {
        flushMouseEvents()
        defer { flushMouseEvents() }
        let wa = tv.convert(a, to: nil), wb = tv.convert(b, to: nil)
        guard let down = mouseEv(.leftMouseDown, wa, mods: mods) else { return }
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = NSPoint(x: wa.x + (wb.x - wa.x) * t, y: wa.y + (wb.y - wa.y) * t)
            if let d = mouseEv(.leftMouseDragged, p, mods: mods) { NSApp.postEvent(d, atStart: false) }
        }
        if let up = mouseEv(.leftMouseUp, wb, mods: mods) { NSApp.postEvent(up, atStart: false) }
        if window.firstResponder !== tv { window.makeFirstResponder(tv) }
        tv.mouseDown(with: down)
        await turn()
    }

    /// 거터의 한 점을 클릭한다 (거터 좌표). 거터의 mouseDown 은 추적 루프가 없어 바로 돌아온다. 화살표 열(왼쪽 18 pt) 안만 누른다
    func clickGutter(at p: NSPoint) async {
        guard let g = gutter, p.x <= GutterView.foldColumnWidth + 4, let e = mouseEv(.leftMouseDown, g.convert(p, to: nil)) else { return }
        g.mouseDown(with: e)
        await turn()
    }

    /// 거터가 그 줄 번호를 그린 높이의 접기 화살표 한가운데 (거터 좌표). 그 줄이 화면에 없으면 nil
    func foldArrowPoint(forLine line: Int) -> NSPoint? {
        guard let g = gutter, !g.isHidden else { return nil }
        g.display()
        guard let row = g.debugRows.first(where: { $0.line == line }) else { return nil }
        return NSPoint(x: GutterView.foldColumnWidth / 2 + 2, y: row.y + lineHeight / 2)
    }

    func hidden(_ offset: Int) -> Bool { tv.isOffsetHidden?(offset) ?? false }
    func hidden(line: Int) -> Bool { hidden(lineStart(line)) }
    var foldsActive: Bool { tv.hasFolds?() ?? false }

    /// 그 줄의 거터 화살표 상태 (접을 수 있음 · 접힘 · 없음)
    func marker(atLine line: Int) -> GutterView.FoldMarker? {
        let idx = LineIndex(nsString: text)
        guard line >= 1, line <= idx.lineCount else { return nil }
        let s = idx.lineStarts[line - 1]
        let e = line < idx.lineCount ? idx.lineStarts[line] : idx.utf16Count
        return gutter?.foldMarker?(s, { e })
    }

    /// 지금 그려지는 `⋯ N lines` 표식들 (텍스트 뷰 좌표)
    func pillRects() -> [(NSRect, Int)] {
        tv.display()
        return tv.foldPillRects
    }

    // MARK: 기대값 검사

    func expectCaret(_ expected: Int, _ why: String) {
        MouseStats.checks += 1
        let sel = tv.selectedRange()
        if sel.location != expected || sel.length != 0 {
            issue("click", "\(why): expected the caret at \(place(expected)) but the selection is {\(sel.location), \(sel.length)} → \(place(sel.location))")
        }
    }

    fileprivate func expectSelection(_ expected: NSRange, _ why: String) {
        MouseStats.checks += 1
        let sel = tv.selectedRange()
        if sel != expected {
            issue("selection", "\(why): expected {\(expected.location), \(expected.length)} (\(place(expected.location)) … \(place(NSMaxRange(expected)))) but got {\(sel.location), \(sel.length)} (\(place(sel.location)) … \(place(NSMaxRange(sel))))")
        }
    }

    func expect(_ ok: Bool, _ kind: String, _ what: @autoclosure () -> String) {
        MouseStats.checks += 1
        if !ok { issue(kind, what()) }
    }

    /// 열 블록·멀티 선택에서 길이 있는 범위가 모두 네이티브 선택에 들어 있는가 (선택 강조는 네이티브 선택이 그린다 — 빠지면 그 줄은 고른 티가 나지 않는다)
    func expectBlockHighlighted(_ why: String) {
        MouseStats.checks += 1
        guard let m = tv.multi else { issue("multi", "\(why): no multi selection"); return }
        let want = m.ranges.filter { $0.length > 0 }
        let native = tv.selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
        if want != native {
            issue("multi", "\(why): the block selects \(want.map { "{\($0.location), \($0.length)}" }.joined(separator: " ")) but the native selection (what gets highlighted) is \(tv.selectedRanges.map(\.rangeValue).map { "{\($0.location), \($0.length)}" }.joined(separator: " "))")
        }
    }

    /// 고른 범위마다 선택 강조가 실제로 칠해지는가 (새로 그린 그림에서, 범위 첫 글자 칸의 왼쪽 위 모서리와 같은 높이의 왼쪽 여백 색을 견준다)
    func expectSelectionPainted(_ why: String) {
        MouseStats.checks += 1
        let v = visible
        guard v.height > 10, let rep = tv.bitmapImageRepForCachingDisplay(in: v) else { return }
        tv.cacheDisplay(in: v, to: rep)
        let scale = CGFloat(rep.pixelsHigh) / v.height
        func color(_ p: NSPoint) -> NSColor? { rep.colorAt(x: Int((p.x - v.minX) * scale), y: Int((p.y - v.minY) * scale)) }
        func differs(_ a: NSColor?, _ b: NSColor?) -> Bool {
            guard let a, let b else { return false }
            return abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent) > 0.06
        }
        let ranges = (tv.multi?.ranges ?? tv.selectedRanges.map(\.rangeValue)).filter { $0.length > 0 }
        var seen = 0
        var unpainted: [NSRange] = []
        for r in ranges {
            guard let c = tv.caretRect(at: r.location), v.contains(NSPoint(x: c.minX + 2, y: c.minY + 2)), c.minX > 8 else { continue }
            seen += 1
            if !differs(color(NSPoint(x: c.minX + 1.5, y: c.minY + 1.5)), color(NSPoint(x: 3, y: c.minY + 1.5))) { unpainted.append(r) }
        }
        if let f = unpainted.first {
            issue("selection", "\(why): \(unpainted.count) of \(seen) selected ranges on screen show no selection highlight — first {\(f.location), \(f.length)} at \(place(f.location))")
        } else if seen == 0, !ranges.isEmpty { note("\(why): no selected range on screen to sample") }
    }

    /// 글자 `off` 의 왼쪽 가장자리 바로 안쪽을 클릭하고 캐럿이 그 글자 앞에 놓였는지 본다. 보이지 않는 곳이면 false
    @discardableResult
    func clickExpect(_ off: Int, _ why: String) async -> Bool {
        guard let p = point(forOffset: off) else { issue("other", "\(why): \(place(off)) is not on screen to click (visible \(Int(visible.minY))…\(Int(visible.maxY)))"); return false }
        await mclick(atViewPoint: p)
        expectCaret(off, why)
        return true
    }

    /// 보이는 문단들의 여러 열(줄 머리·가운데 글자의 왼쪽 절반과 오른쪽 절반·마지막 글자·줄 끝 너머)을 클릭해 캐럿이 클릭한 글자에 놓이는지 본다.
    /// 클릭할 점은 글자가 **그려지는 자리**(레이아웃 세그먼트)에서 구하고, 캐럿은 텍스트 뷰의 mouseDown 히트 테스트가 정한다 — 둘이 어긋나면 사용자는
    /// 누른 글자가 아닌 곳에 캐럿이 놓이는 것을 본다. 감긴 문단은 둘째·셋째 시각 줄도 누른다. 반환: (클릭 수, 어긋난 수)
    @discardableResult
    func clickGrid(_ why: String, paragraphs maxParas: Int = 12, visualLines maxVL: Int = 3) async -> (clicks: Int, misses: Int) {
        if !ensureViewportRange(why) { checkScreen(why) }
        let ns = text
        let v = visible
        let y0 = v.minY
        let frags = viewportFragments().filter { $0.minY >= v.minY && $0.maxY <= v.maxY }
        guard !frags.isEmpty else { issue("click", "\(why): no fully visible paragraph to click (visible \(Int(v.minY))…\(Int(v.maxY)))"); return (0, 0) }
        let stride = max(1, Int((Double(frags.count) / Double(maxParas)).rounded(.up)))
        var clicks = 0, misses = 0
        var first: String?
        struct Target { let p: NSPoint; let expect: Int; let what: String }
        // 접힌 머리 줄 끝의 ⋯ 표식은 단추다(누르면 펼친다) — 줄 끝 너머를 누를 때는 표식을 지나친 곳을 누른다
        let pills = foldsActive ? pillRects().map { $0.0.insetBy(dx: -3, dy: -3) } : []
        for (i, f) in frags.enumerated() where i % stride == 0 {
            let vls = visualLines(ofParagraphAt: f.offset)
            for (li, vl) in vls.enumerated() where li < maxVL || li == vls.count - 1 {
                var content = vl.range
                while content.length > 0 {
                    let last = ns.character(at: NSMaxRange(content) - 1)
                    // 문단 끝의 개행, 그리고 감긴 줄 끝의 공백(줄을 넘기는 자리 — 폭 없이 매달려 있어 그 글자를 누를 수 없다)은 뺀다
                    if last == 10 || last == 13 || (li < vls.count - 1 && (last == 32 || last == 9)) { content.length -= 1 } else { break }
                }
                var targets: [Target] = []
                // 그 오프셋의 글자가 이 시각 줄에 그려지는가 (감긴 줄의 경계 오프셋은 앞 줄 끝으로도 뒷 줄 머리로도 볼 수 있어 뺀다)
                func rectOnThisLine(_ off: Int) -> NSRect? {
                    guard let r = tv.caretRect(at: off), abs(r.midY - vl.rect.midY) < max(2, vl.rect.height / 2) else { return nil }
                    return r
                }
                if content.length == 0 {
                    if li == 0, let r = rectOnThisLine(content.location) {
                        targets.append(Target(p: NSPoint(x: r.minX + 1, y: r.midY), expect: content.location, what: "the empty line"))
                        targets.append(Target(p: NSPoint(x: r.minX + 120, y: r.midY), expect: content.location, what: "120 pt right of the empty line"))
                    }
                } else {
                    let head = content.location
                    let mid = ns.rangeOfComposedCharacterSequence(at: content.location + content.length / 2)
                    let tail = ns.rangeOfComposedCharacterSequence(at: NSMaxRange(content) - 1)
                    if li == 0, let r = rectOnThisLine(head) { targets.append(Target(p: NSPoint(x: r.minX + 1, y: r.midY), expect: head, what: "the first character")) }
                    if mid.location > head, let r = rectOnThisLine(mid.location) {
                        targets.append(Target(p: NSPoint(x: r.minX + 1, y: r.midY), expect: mid.location, what: "the left half of a middle character"))
                        if NSMaxRange(mid) < NSMaxRange(content), let rn = rectOnThisLine(NSMaxRange(mid)), rn.minX - r.minX > 4 {
                            targets.append(Target(p: NSPoint(x: rn.minX - 1.5, y: r.midY), expect: NSMaxRange(mid), what: "the right half of a middle character"))
                        }
                    }
                    if tail.location > mid.location, let r = rectOnThisLine(tail.location) {
                        targets.append(Target(p: NSPoint(x: r.minX + 1, y: r.midY), expect: tail.location, what: "the last character"))
                    }
                    // 문단의 마지막 시각 줄: 줄 끝 너머의 빈 곳을 누르면 줄 끝
                    if li == vls.count - 1, let r = rectOnThisLine(NSMaxRange(content)) {
                        var p = NSPoint(x: r.minX + 40, y: r.midY)
                        if let pill = pills.first(where: { $0.contains(p) }) { p.x = pill.maxX + 30 }
                        if p.x < v.maxX - 24 { targets.append(Target(p: p, expect: NSMaxRange(content), what: "\(Int(p.x - r.minX)) pt past the end of the line")) }
                    }
                }
                for t in targets where tv.visibleRect.contains(t.p) {
                    flushMouseEvents()
                    await click(atViewPoint: t.p)
                    clicks += 1
                    let got = tv.selectedRange()
                    if got.location != t.expect || got.length != 0 {
                        misses += 1
                        if first == nil {
                            first = "clicked \(t.what) at \(place(t.expect)), visual line \(li + 1) of \(vls.count), view point (\(Int(t.p.x)), \(Int(t.p.y))) = screen y \(Int(t.p.y - tv.visibleRect.minY)) → selection {\(got.location), \(got.length)} at \(place(got.location))"
                        }
                    }
                }
            }
        }
        MouseStats.clicks += clicks
        MouseStats.checks += 1
        if misses > 0 { issue("click", "\(why): \(misses) of \(clicks) clicks landed on a different character — first: \(first ?? "")") }
        if clicks == 0 { issue("click", "\(why): nothing clickable among \(frags.count) visible paragraphs") }
        // 보이는 줄을 누르는 것만으로 화면이 움직이면 안 된다
        if abs(visible.minY - y0) > 1 { issue("viewport-jump", "\(why): clicking visible lines moved the viewport \(String(format: "%.1f", visible.minY - y0)) pt") }
        note("\(why): \(clicks) clicks, \(misses) misses")
        return (clicks, misses)
    }

    // MARK: 현재 줄 강조 (픽셀)

    /// 텍스트 뷰를 비트맵으로 그려, 글자가 없는 왼쪽 여백 열(x = 3 pt)에서 배경색과 다른 가로 띠를 찾는다 (텍스트 뷰 좌표의 y 구간).
    /// 현재 줄 강조는 x = 0 부터 뷰 전체 폭으로 칠하고, 선택 강조·접기 표식·글자는 이 열에 닿지 않는다
    func marginBands() -> [(minY: CGFloat, maxY: CGFloat)] { bands(in: tv, rect: visible, x: 3) }

    /// 거터를 비트맵으로 그려 왼쪽 끝 열(x = 1 pt — 접기 화살표·번호가 닿지 않는다)에서 배경색과 다른 가로 띠를 찾는다 (거터 좌표 = 화면 y)
    func gutterBands() -> [(minY: CGFloat, maxY: CGFloat)] {
        guard let g = gutter, !g.isHidden, g.bounds.width > 4 else { return [] }
        return bands(in: g, rect: g.bounds, x: 1)
    }

    private func bands(in view: NSView, rect v: NSRect, x xPt: CGFloat) -> [(minY: CGFloat, maxY: CGFloat)] {
        guard v.height > 10, let rep = view.bitmapImageRepForCachingDisplay(in: v) else { return [] }
        view.cacheDisplay(in: v, to: rep)
        let scale = CGFloat(rep.pixelsHigh) / v.height
        let x = Int(xPt * scale)
        func key(_ y: Int) -> Int {
            guard let c = rep.colorAt(x: x, y: y) else { return -1 }
            return (Int(c.redComponent * 255) << 16) | (Int(c.greenComponent * 255) << 8) | Int(c.blueComponent * 255)
        }
        var keys: [Int] = []
        keys.reserveCapacity(rep.pixelsHigh)
        for y in 0..<rep.pixelsHigh { keys.append(key(y)) }
        var counts: [Int: Int] = [:]
        for k in keys { counts[k, default: 0] += 1 }
        guard let bg = counts.max(by: { $0.value < $1.value })?.key else { return [] }
        var out: [(minY: CGFloat, maxY: CGFloat)] = []
        var start: Int?
        for y in 0...rep.pixelsHigh {
            let on = y < rep.pixelsHigh && keys[y] != bg
            if on, start == nil { start = y }
            if !on, let s = start { out.append((v.minY + CGFloat(s) / scale, v.minY + CGFloat(y) / scale)); start = nil }
        }
        return out
    }

    /// 현재 줄 강조가 캐럿 줄에, 그 줄에만 그려지는가. 선택이 있거나 멀티 캐럿이면 띠가 없어야 한다. 거터의 띠도 편집기의 띠와 같은 높이여야 한다
    func checkLineHighlight(_ why: String) {
        MouseStats.checks += 1
        guard tv.currentLineColor != nil else { return }
        let sel = tv.selectedRange()
        let v = visible
        let wantsBand = sel.length == 0 && tv.multi == nil
        let caretR = tv.caretRect(at: sel.location)
        let onScreen = caretR.map { $0.maxY > v.minY + 1 && $0.minY < v.maxY - 1 } ?? false
        func desc(_ b: [(minY: CGFloat, maxY: CGFloat)]) -> String { b.map { "\(Int($0.minY - v.minY))…\(Int($0.maxY - v.minY))" }.joined(separator: ", ") }
        // 1) 거터가 **마지막으로 실제 그린** 띠 (강제로 다시 그리기 전에 본다 — 선택이 바뀌었는데 거터를 다시 그리지 않으면 낡은 띠가 화면에 남는다)
        if let g = gutter, !g.isHidden, g.bounds.width > 4 {
            // 레이어 뷰의 실제 그리기는 창의 표시 주기 뒤 Core Animation 커밋에서 일어난다 — 대기 중인 것만 지금 끝낸다 (거터를 직접 무효화하지는 않는다)
            window.displayIfNeeded(); CATransaction.flush()
            let drawn = g.debugBand
            let want: ClosedRange<CGFloat>? = (wantsBand && onScreen) ? caretR.map { ($0.minY - v.minY)...($0.maxY - v.minY) } : nil
            let same: Bool
            switch (drawn, want) {
            case (nil, nil): same = true
            case let (d?, w?): same = abs(d.lowerBound - w.lowerBound) < 1.5 && abs(d.upperBound - w.upperBound) < 1.5
            default: same = false
            }
            if !same {
                func d(_ r: ClosedRange<CGFloat>?) -> String { r.map { "\(Int($0.lowerBound))…\(Int($0.upperBound))" } ?? "none" }
                issue("highlight", "\(why): the gutter last drew its current-line band at screen y \(d(drawn)) but the caret row is now \(d(want)) — the gutter was not redrawn")
            }
        }
        let bands = marginBands()
        // 2) 거터의 띠와 편집기의 띠가 한 줄로 이어지는가 (새로 그린 그림끼리 비교)
        if let g = gutter, !g.isHidden, g.bounds.width > 4 {
            let gb = gutterBands()
            let tb = bands.map { (minY: $0.minY - v.minY, maxY: $0.maxY - v.minY) }
            let aligned = gb.count == tb.count && zip(gb, tb).allSatisfy { abs($0.minY - $1.minY) <= 1.5 && abs($0.maxY - $1.maxY) <= 1.5 }
            if !aligned {
                issue("highlight", "\(why): gutter band at screen y \(gb.map { "\(Int($0.minY))…\(Int($0.maxY))" }.joined(separator: ", ")) but the editor band at \(desc(bands)) (\(gb.count) vs \(tb.count))")
            }
        }
        if !wantsBand || !onScreen {
            if !bands.isEmpty { issue("highlight", "\(why): no current-line band expected (selection length \(sel.length), caret \(onScreen ? "on" : "off") screen) but found bands at screen y \(desc(bands))") }
            return
        }
        guard let r = caretR else { return }
        let want = (minY: max(r.minY, v.minY), maxY: min(r.maxY, v.maxY))
        if bands.count != 1 { issue("highlight", "\(why): expected one current-line band at screen y \(Int(want.minY - v.minY))…\(Int(want.maxY - v.minY)) but found \(bands.count): \(desc(bands))"); return }
        if abs(bands[0].minY - want.minY) > 1.5 || abs(bands[0].maxY - want.maxY) > 1.5 {
            issue("highlight", "\(why): current-line band drawn at screen y \(desc(bands)) but the caret line is at \(Int(want.minY - v.minY))…\(Int(want.maxY - v.minY))")
        }
    }

    /// 개행으로 끝나는 문서의 마지막 빈 줄에도 거터가 번호를 그리는가 (그 줄이 화면에 있을 때)
    func checkLastLineNumber(_ why: String) {
        guard let g = gutter, !g.isHidden, g.bounds.width > 4 else { return }
        let ns = text
        guard ns.length == 0 || ns.character(at: ns.length - 1) == 10, let r = tv.caretRect(at: ns.length) else { return }
        let v = visible
        guard r.minY >= v.minY, r.maxY <= v.maxY, !hidden(ns.length) else { return }
        MouseStats.checks += 1
        g.display()
        let last = LineIndex(nsString: ns).lineCount
        let y = r.minY - v.minY
        guard let row = g.debugRows.first(where: { $0.line == last }) else {
            issue("gutter", "\(why): the last line \(last) (empty, after the final newline) is on screen at y \(Int(y)) but the gutter drew no number for it (rows: \(g.debugRows.suffix(3).map { "\($0.line)@\(Int($0.y))" }.joined(separator: " ")))"); return
        }
        if abs(row.y - y) > 1.5 { issue("gutter", "\(why): the last line \(last) number is drawn at y \(String(format: "%.1f", row.y)) but the line is at \(String(format: "%.1f", y))") }
    }

    // MARK: 실제 화면 (조각 뷰)
    // 코어의 snap·checkInk 는 cacheDisplay 로 **새로 그린** 그림을 본다 — 화면에 올라가 있는 것이 낡았어도 그 그림은 멀쩡하다. TextKit 2 의 NSTextView 는
    // 뷰포트의 조각마다 `_NSTextViewportElementView` 를 `_NSTextContentView` 아래에 두고 그 레이어가 화면에 보이는 글자다(macOS 27 실측: 프레임 = 조각의
    // renderingSurfaceBounds 를 조각 원점으로 옮긴 것). 그 뷰들의 자리를 레이아웃 조각(클릭 히트 테스트·캐럿 위치가 쓰는 것)과 견준다 — 어긋나면 사용자는
    // 보이는 글자와 다른 곳에 캐럿이 놓이는 것을, 뷰가 없으면 빈 영역을 본다.

    /// 화면에 올라가 있는 조각 뷰들의 사각형 (텍스트 뷰 좌표)
    func fragmentViewFrames() -> [NSRect] {
        guard let content = tv.subviews.first(where: { String(describing: Swift.type(of: $0)) == "_NSTextContentView" }) else { return [] }
        return content.subviews.filter { !$0.isHidden }.map { tv.convert($0.frame, from: content) }
    }

    /// 보이는 문단마다 제자리에 조각 뷰가 있는가, 레이아웃에 없는 자리에 남은 조각 뷰(낡은 글자)는 없는가. 반환: 검사했는가 (창이 가려져 있으면 표시 주기가 돌지 않아 건너뛴다)
    @discardableResult
    func checkScreen(_ why: String) -> Bool {
        guard window.occlusionState.contains(.visible) else { log("  \(scenario) › \(step): (screen check skipped — window occluded) \(why)"); return false }
        guard let lm = tv.textLayoutManager, let cs = tv.textContentStorage, length > 0 else { return false }
        MouseStats.checks += 1
        window.displayIfNeeded(); CATransaction.flush()
        let views = fragmentViewFrames()
        let o = tv.textContainerOrigin, v = visible
        let ns = text
        var wanted: [(rect: NSRect, offset: Int)] = []
        // 읽기만 한다: 뷰포트 범위의 조각을 배치를 강제하지 않고 훑는다. 점 질의(textLayoutFragment(for:))나 .ensuresLayout 열거는 뷰포트 위쪽의 아직 배치되지 않은
        // 문단을 배치해 그 아래 조각들의 자리를 통째로 옮길 수 있다(실측: 모두 접기 뒤 20개 조각이 +8.8 pt) — 검사가 상태를 바꾸면 안 된다
        guard let vr = lm.textViewportLayoutController.viewportRange, !vr.isEmpty else { return false }
        var n = 0
        lm.enumerateTextLayoutFragments(from: vr.location, options: []) { f in
            if f.rangeInElement.location.compare(vr.endLocation) != .orderedAscending { return false }
            n += 1
            let fr = f.layoutFragmentFrame
            guard f.state == .layoutAvailable, fr.height > 0, fr.maxY + o.y > v.minY, fr.minY + o.y < v.maxY else { return n < 3000 }
            let off = cs.offset(from: cs.documentRange.location, to: f.rangeInElement.location)
            let len = cs.offset(from: f.rangeInElement.location, to: f.rangeInElement.endLocation)
            let s = ns.substring(with: NSIntersectionRange(NSRange(location: off, length: len), NSRange(location: 0, length: ns.length)))
            guard s.contains(where: { !$0.isWhitespace }) else { return n < 3000 }   // 빈 줄은 조각 뷰가 없다
            wanted.append((f.renderingSurfaceBounds.offsetBy(dx: fr.minX + o.x, dy: fr.minY + o.y), off))
            return n < 3000
        }
        func matches(_ view: NSRect, _ want: NSRect) -> Bool { abs(view.minY - want.minY) < 1.5 && abs(view.width - want.width) < 2.5 && abs(view.height - want.height) < 2.5 }
        // 화면에 온전히 들어온 문단만 따진다 (가장자리에 걸친 것은 TextKit 이 아직 올리지 않았을 수 있다)
        let inside = wanted.filter { $0.rect.minY >= v.minY - 2 && $0.rect.maxY <= v.maxY + 6 }
        let missing = inside.filter { w in !views.contains(where: { matches($0, w.rect) }) }
        if let m = missing.first {
            let near = views.filter { abs($0.minY - m.rect.minY) < 60 }.sorted { $0.minY < $1.minY }.map { "y \(String(format: "%.1f", $0.minY - v.minY)) w \(Int($0.width))" }.joined(separator: ", ")
            issue("screen", "\(why): \(missing.count) of \(inside.count) visible paragraphs are not on screen where the layout puts them — first: \(place(m.offset)) expected at screen y \(String(format: "%.1f", m.rect.minY - v.minY)) (width \(Int(m.rect.width))); fragment views near it: [\(near)] (\(views.count) views in all)")
        }
        if missing.isEmpty { log("  \(scenario) › \(step): screen ok — \(inside.count) visible paragraphs have their fragment views in place (\(why))") }
        let ghosts = views.filter { f in f.maxY > v.minY + 2 && f.minY < v.maxY - 2 && !wanted.contains(where: { matches(f, $0.rect) }) }
        if missing.isEmpty, let g = ghosts.first {
            issue("screen", "\(why): \(ghosts.count) fragment views on screen match no laid-out paragraph (stale text) — first at screen y \(String(format: "%.1f", g.minY - v.minY)) width \(Int(g.width)) height \(Int(g.height))")
        }
        return true
    }

    /// 뷰포트를 배치한 뒤 아무 조작 없이 기다리는 동안 조각의 자리(레이아웃)가 움직이는가. 움직이면 화면의 조각 뷰는 옛 자리에 남으므로(다음 뷰포트 배치까지)
    /// 줄 번호·접기 표식·클릭 위치가 보이는 글자와 그만큼 어긋난다. 창이 가려져 있어도 잴 수 있다 (표시 주기가 할 뷰포트 배치를 먼저 대신 한다)
    func checkFramesStable(_ why: String, wait ms: UInt64 = 350) async {
        guard let lm = tv.textLayoutManager, length > 0 else { return }
        MouseStats.checks += 1
        lm.textViewportLayoutController.layoutViewport()
        let y0 = visible.minY
        let f1 = viewportFragments()
        await settle(ms)
        let f2 = viewportFragments()
        var moved = 0
        var first = ""
        for a in f1 {
            guard let b = f2.first(where: { $0.offset == a.offset }) else { continue }
            let d = (b.minY - visible.minY) - (a.minY - y0)
            if abs(d) > 0.75 { moved += 1; if first.isEmpty { first = "paragraph at \(place(a.offset)) moved \(String(format: "%+.1f", d)) pt on screen (document y \(String(format: "%.1f", a.minY)) → \(String(format: "%.1f", b.minY)), viewport \(String(format: "%.1f", y0)) → \(String(format: "%.1f", visible.minY)))" } }
        }
        if moved > 0 { issue("layout-shift", "\(why): \(moved) of \(f1.count) laid-out paragraphs changed place within \(ms) ms with no input — \(first)") }
        else { log("  \(scenario) › \(step): frames stable for \(ms) ms (\(f1.count) fragments) — \(why)") }
    }

    /// 코어의 `viewportFragments()` 는 `textViewportLayoutController.viewportRange` 를 훑는데, 그 범위는 저장소의 속성 편집 통지(접기·테마·구문 색 무효화) 직후나
    /// 창이 가려져 표시 주기가 돌지 않는 동안 빈 범위(x..<x)로 남는다 — 화면의 조각 뷰는 멀쩡한데 "no layout fragments in the viewport" 가 나온다(거짓 양성).
    /// 그때는 실제 화면을 먼저 확인하고(checkScreen — 창이 보일 때), 표시 주기가 할 일(layoutViewport)을 대신 해 범위를 채운다. 반환: 범위가 비어 있었는가
    @discardableResult
    func ensureViewportRange(_ why: String) -> Bool {
        guard length > 0, viewportFragments().isEmpty else { return false }
        diagViewport("viewport range empty — \(why)")
        checkScreen(why + " (viewport range empty)")
        tv.textLayoutManager?.textViewportLayoutController.layoutViewport()
        return true
    }

    /// checkAll + 실제 화면(조각 뷰) 검사. 뷰포트 범위가 비어 있으면 먼저 채운다
    func checkAllD(_ why: String) {
        if !ensureViewportRange(why) { checkScreen(why) }
        checkAll(why)
    }

    /// 진단: 뷰포트 레이아웃 컨트롤러의 상태 (조각이 하나도 없다고 나올 때 무엇이 비어 있는지)
    func diagViewport(_ tag: String) {
        guard let lm = tv.textLayoutManager, let cs = tv.textContentStorage else { return }
        let vc = lm.textViewportLayoutController
        let vr = vc.viewportRange
        let a = vr.map { cs.offset(from: cs.documentRange.location, to: $0.location) } ?? -1
        let b = vr.map { cs.offset(from: cs.documentRange.location, to: $0.endLocation) } ?? -1
        var n = 0, zero = 0
        if let vr {
            lm.enumerateTextLayoutFragments(from: vr.location, options: []) { f in
                if f.rangeInElement.location.compare(vr.endLocation) != .orderedAscending { return false }
                n += 1; if f.layoutFragmentFrame.height <= 0 { zero += 1 }
                return n < 400
            }
        }
        let fv = fragmentViewFrames().sorted { $0.minY < $1.minY }
        log("  DIAG \(tag): fragment views \(fv.count) y \(fv.first.map { String(format: "%.0f", $0.minY) } ?? "-")…\(fv.last.map { String(format: "%.0f", $0.maxY) } ?? "-")")
        log("  DIAG \(tag): viewportRange \(a)..<\(b) fragments \(n) (zero-height \(zero)) viewportBounds \(vc.viewportBounds) visible \(tv.visibleRect) prepared \(tv.preparedContentRect) frame \(tv.frame) clip \(scroll.contentView.bounds) needsLayout \(tv.needsLayout) occluded \(!window.occlusionState.contains(.visible)) caret \(caret) length \(length)")
    }

    /// 화면(뒷저장소)에 칠해져 있는 현재 줄 띠가 캐럿 줄에, 그 줄에만 있는가 — HyperTextView 가 실제 그리기를 따라가며 흉내 낸 값(debugBandOnScreen)으로 본다.
    /// 새로 그린 그림(checkLineHighlight)은 멀쩡해도, 다시 그리기가 빠지면 화면에는 띠가 옛 줄에 남거나 새 줄에 안 칠해진다
    func checkBandOnScreen(_ why: String) {
        guard tv.currentLineColor != nil else { return }
        if !HyperTextView.trackBandForRealUse { HyperTextView.trackBandForRealUse = true; tv.display() }   // 처음: 지금 상태를 한 번 통째로 칠해 기준을 잡는다
        // 창이 가려져 있어도 무효화된 구역의 실제 그리기는 표시 주기를 돌리면 일어난다 (가려진 창에서 멈추는 것은 스크롤 뒤의 뷰포트 재배치다 — checkScreen 참고)
        MouseStats.checks += 1
        window.displayIfNeeded(); CATransaction.flush()
        let v = visible
        let sel = tv.selectedRange()
        var want: ClosedRange<CGFloat>?
        if sel.length == 0, tv.multi == nil, let r = tv.caretRect(at: sel.location), r.maxY > v.minY + 1, r.minY < v.maxY - 1 { want = max(r.minY, v.minY)...min(r.maxY, v.maxY) }
        let have = tv.debugBandOnScreen.compactMap { b -> ClosedRange<CGFloat>? in
            let lo = max(b.lowerBound, v.minY), hi = min(b.upperBound, v.maxY)
            return hi - lo > 1 ? lo...hi : nil
        }
        func d(_ r: ClosedRange<CGFloat>) -> String { "\(Int(r.lowerBound - v.minY))…\(Int(r.upperBound - v.minY))" }
        let ok: Bool
        if let w = want { ok = have.count == 1 && abs(have[0].lowerBound - w.lowerBound) < 1.5 && abs(have[0].upperBound - w.upperBound) < 1.5 } else { ok = have.isEmpty }
        if !ok {
            issue("highlight", "\(why): on screen the current-line band is painted at y [\(have.map(d).joined(separator: ", "))] but the caret row is \(want.map(d) ?? "none (selection or off screen)") — the editor did not repaint the right rows\(window.occlusionState.contains(.visible) ? "" : " (window occluded)")")
        }
    }

    /// 시나리오 끝: 이 파일이 센 검사·클릭 수를 로그에 남긴다
    func mouseSummary() { log("  \(scenario): mouse checks so far \(MouseStats.checks), clicks \(MouseStats.clicks)") }
}

// MARK: - 말뭉치

extension RealUse {
    /// 선택 시험용: 한글·영문·탭·빈 줄·감기는 긴 줄·들여쓴 줄이 6줄 주기로 돈다 (줄 머리에 줄 번호)
    static func selectionDoc(lines: Int = 180) -> String {
        (1...lines).map { i -> String in
            switch i % 6 {
            case 0: return "\(i) 한글 문장을 적는다 가나다라 마바사 끝"
            case 1: return "\(i) alpha beta gamma delta epsilon zeta"
            case 2: return "\(i)\tname\tqty\tnote"
            case 3: return ""
            case 4: return "\(i) The quick brown fox jumps over the lazy dog near the river bank while the editor wraps this long paragraph several times so that it spans at least two visual lines in a wide window, and then some more words follow to be safe: one two three four five six seven eight nine ten eleven twelve."
            default: return "    indented code line \(i) { return x }"
            }
        }.joined(separator: "\n") + "\n"
    }

    /// 열 블록 시험용: 고정 폭 ASCII 줄, 다섯째 줄마다 짧은 줄 (가상 공백)
    static func columnDoc(lines: Int = 60) -> String {
        (0..<lines).map { i in i % 5 == 4 ? String(format: "%02d|ab", i) : String(format: "%02d|abcdefghijklmnopqrstuvwxyz|0123456789|tail", i) }.joined(separator: "\n") + "\n"
    }

    /// 접기 시험용 마크다운: `## Section i` 가 8줄 주기(머리·본문·항목·들여쓴 두 줄·항목·닫는 줄·빈 줄). h1 이면 문서 전체를 품는 `# Top` 이 첫 줄
    static func foldDoc(h1: Bool, sections: Int = 30) -> String {
        var s = h1 ? "# Top title\n\nintro paragraph under the top heading\n\n" : "preface line one\npreface line two\n\n"
        for i in 1...sections {
            s += "## Section \(i) 제목\n"
            s += "first body line of section \(i)\n"
            s += "- item \(i).1\n"
            s += "    nested detail a of \(i)\n"
            s += "    nested detail b of \(i)\n"
            s += "- item \(i).2 한글 항목\n"
            s += "closing line of section \(i)\n"
            s += "\n"
        }
        return s
    }
    /// foldDoc(h1: false) 에서 i 번째 구역의 머리 줄 (1-based)
    static func foldHeader(_ i: Int, h1: Bool = false) -> Int { (h1 ? 5 : 4) + (i - 1) * 8 }
}

// MARK: - 시나리오

extension RealUse {
    @MainActor static let mouseScenarios: [Scenario] = [
        // 작은 문서: 보이는 모든 줄의 여러 열 클릭 — 줄바꿈 켬/끔
        Scenario(name: "mouse-click-small") { ctx in
            let wrap0 = ctx.model.wordWrap
            await ctx.open(.small, name: "mouse-small.md")
            ctx.at("opened"); ctx.checkAllD("after open")
            await ctx.clickGrid("small document as opened", paragraphs: 40)
            ctx.checkLineHighlight("after clicks"); ctx.snap("clicked")
            ctx.at("wrap toggled")
            ctx.model.wordWrap = !wrap0; await ctx.settle(200)
            ctx.checkAllD("wrap \(!wrap0 ? "on" : "off")"); ctx.checkInk("wrap toggled")
            await ctx.clickGrid("small document, wrap \(!wrap0 ? "on" : "off")", paragraphs: 40)
            ctx.model.wordWrap = wrap0; await ctx.settle(200)
            ctx.at("wrap restored"); ctx.checkAllD("wrap restored")
            await ctx.clickGrid("small document, wrap restored", paragraphs: 40)
            ctx.mouseSummary()
        },

        // 1.3 MB 메모: 문서 끝·멀리 스크롤한 뒤·맨 위·페이지 넘김·줄 이동·잘게 스크롤한 뒤의 클릭
        Scenario(name: "mouse-click-notes") { ctx in
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "mouse-notes.md") }
            ctx.at("opened at the end"); await ctx.settle(200)
            ctx.checkAllD("opened"); ctx.checkInk("opened"); ctx.checkLastLineNumber("opened at the end"); ctx.checkLineHighlight("opened at the end")
            await ctx.clickGrid("opened at the end of the document")
            ctx.at("flick up 6000")
            await ctx.flick(total: -6000); await ctx.settle(100)
            ctx.checkAllD("flick up"); ctx.checkInk("flick up")
            await ctx.clickGrid("after a 6000 pt flick up from the end"); ctx.snap("flick-up")
            ctx.at("wheel up 30 lines")
            for _ in 0..<10 { await ctx.wheelLines(-3) }
            ctx.checkAllD("wheel up"); await ctx.clickGrid("after 10 wheel notches up")
            ctx.at("jump to the top")
            await ctx.key(.up, [.command]); await ctx.settle(100)
            ctx.checkAllD("⌘↑"); await ctx.clickGrid("at the top after ⌘↑")
            ctx.at("page down ×25")
            await ctx.key(.pageDown, count: 25); await ctx.settle(100)
            ctx.checkAllD("page down"); ctx.checkInk("page down"); await ctx.clickGrid("after 25 page downs")
            ctx.at("go to line 15000")
            ctx.model.jump(toLine: 15000); await ctx.settle(300)
            ctx.checkAllD("go to line"); await ctx.clickGrid("after go to line 15000"); ctx.snap("line-15000")
            ctx.at("pixel scroll down 40 × 137")
            for _ in 0..<40 { await ctx.scrollBy(137) }
            await ctx.settle(50)
            ctx.checkAllD("pixel scroll down"); ctx.checkInk("pixel scroll down"); await ctx.clickGrid("after 40 small scrolls down")
            ctx.at("pixel scroll up 30 × 53")
            for _ in 0..<30 { await ctx.scrollBy(-53) }
            await ctx.settle(50)
            ctx.checkAllD("pixel scroll up"); await ctx.clickGrid("after 30 small scrolls up")
            ctx.at("jump to the end")
            await ctx.key(.down, [.command]); await ctx.settle(150)
            ctx.checkAllD("⌘↓"); ctx.checkInk("⌘↓"); await ctx.clickGrid("at the end after ⌘↓")
            // 문서 끝에서 위로 조금씩: 위쪽 문단의 추정 높이가 실측으로 바뀌는 구간
            for i in 1...6 {
                ctx.at("from the end, up 100 (\(i))")
                await ctx.scrollBy(-100); await ctx.settle(0)
                ctx.checkAllD("up 100 from the end"); await ctx.clickGrid("scrolled up \(i * 100) pt from the end", paragraphs: 8)
            }
            ctx.snap("end-up"); ctx.mouseSummary()
        },

        // 4 MB 로그(한 줄 ≈ 100자): 끝·멀리 쓸어 올린 뒤·줄 이동·처음에서의 클릭
        Scenario(name: "mouse-click-log") { ctx in
            await ctx.withRelaxedStalls { await ctx.open(.log, name: "mouse-server.log") }
            ctx.at("opened at the end"); await ctx.settle(200)
            ctx.checkAllD("opened"); ctx.checkInk("opened"); ctx.checkLastLineNumber("opened at the end")
            await ctx.clickGrid("log, at the end")
            ctx.at("flick up 20000")
            await ctx.flick(total: -20000); await ctx.settle(100)
            ctx.checkAllD("flick up"); ctx.checkInk("flick up"); await ctx.clickGrid("log, after a 20000 pt flick up"); ctx.snap("flick-up")
            ctx.at("go to line 20000")
            ctx.model.jump(toLine: 20000); await ctx.settle(300)
            ctx.checkAllD("go to line"); await ctx.clickGrid("log, line 20000")
            ctx.at("page up ×8")
            await ctx.key(.pageUp, count: 8); await ctx.settle(100)
            ctx.checkAllD("page up"); await ctx.clickGrid("log, after 8 page ups")
            ctx.at("top")
            await ctx.key(.up, [.command]); await ctx.settle(100)
            ctx.checkAllD("⌘↑"); await ctx.clickGrid("log, at the top"); ctx.checkBandOnScreen("log, at the top")
            ctx.mouseSummary()
        },

        // 여러 번 감기는 긴 문단: 둘째·셋째 시각 줄 클릭 — 처음·가운데·끝, 줄바꿈 끄고 켠 뒤
        Scenario(name: "mouse-click-wrapped") { ctx in
            let wrap0 = ctx.model.wordWrap
            if !wrap0 { ctx.model.wordWrap = true }
            await ctx.withRelaxedStalls { await ctx.open(.wide, name: "mouse-wide.md") }
            ctx.at("opened at the end"); await ctx.settle(200)
            ctx.checkAllD("opened"); ctx.checkInk("opened")
            await ctx.clickGrid("wrapped document, at the end", visualLines: 4); ctx.snap("end")
            ctx.at("top")
            await ctx.key(.up, [.command]); await ctx.settle(100)
            ctx.checkAllD("⌘↑"); await ctx.clickGrid("wrapped document, at the top", visualLines: 4)
            ctx.at("flick down 9000")
            await ctx.flick(total: 9000); await ctx.settle(100)
            ctx.checkAllD("flick down"); ctx.checkInk("flick down")
            await ctx.clickGrid("wrapped document, after a 9000 pt flick", visualLines: 4); ctx.snap("flick")
            ctx.at("go to line 2000")
            ctx.model.jump(toLine: 2000); await ctx.settle(300)
            ctx.checkAllD("go to line"); await ctx.clickGrid("wrapped document, line 2000", visualLines: 4)
            ctx.at("wheel down 12 notches")
            for _ in 0..<12 { await ctx.wheelLines(3) }
            ctx.checkAllD("wheel"); await ctx.clickGrid("wrapped document, after wheel notches", visualLines: 4)
            // 줄바꿈 전환의 정지·보던 곳 유지는 레이아웃 영역의 몫 — 여기서는 전환 뒤의 클릭 위치를 본다
            ctx.at("wrap off")
            await ctx.withRelaxedStalls(8000) { ctx.model.wordWrap = false; await ctx.settle(300) }
            ctx.checkAllD("wrap off"); ctx.checkInk("wrap off"); ctx.checkCaretVisible("wrap off")
            await ctx.clickGrid("long lines, wrap off"); ctx.snap("nowrap")
            ctx.at("wrap on again")
            await ctx.withRelaxedStalls(8000) { ctx.model.wordWrap = true; await ctx.settle(300) }
            ctx.checkAllD("wrap on"); ctx.checkInk("wrap on"); ctx.checkCaretVisible("wrap on")
            await ctx.clickGrid("wrapped document, wrap back on", visualLines: 4); ctx.snap("rewrap")
            if !wrap0 { ctx.model.wordWrap = false; await ctx.settle(100) }
            ctx.mouseSummary()
        },

        // 더블 클릭(단어)·트리플 클릭(문단)·⇧클릭(범위)·끌어 선택(아래로·위로·감긴 문단 안)
        Scenario(name: "mouse-select") { ctx in
            let wrap0 = ctx.model.wordWrap
            if !wrap0 { ctx.model.wordWrap = true }
            await ctx.open(text: RealUse.selectionDoc(), name: "mouse-select.txt")
            await ctx.key(.up, [.command]); await ctx.settle(100)
            ctx.model.jump(toLine: 60); await ctx.settle(300)
            let ns = ctx.text
            let v = ctx.visible
            ctx.ensureViewportRange("after go to line 60")
            let frags = ctx.viewportFragments().filter { $0.minY >= v.minY && $0.maxY <= v.maxY }
            func para(containing word: String) -> (frag: RealUseContext.Frag, word: NSRange)? {
                for f in frags {
                    let r = ns.range(of: word, options: [], range: NSRange(location: f.offset, length: f.length))
                    if r.location != NSNotFound { return (f, r) }
                }
                return nil
            }
            ctx.at("double-click an English word")
            if let (f, w) = para(containing: "gamma") {
                await ctx.mclick(offset: w.location + 2, clicks: 2)
                ctx.expectSelection(w, "double-click on \"gamma\""); ctx.expectSelectionPainted("double-click on a word")
                ctx.checkLineHighlight("word selected"); ctx.snap("double-click")
                ctx.at("triple-click the paragraph")
                await ctx.mclick(offset: w.location + 2, clicks: 3)
                let sel = ctx.tv.selectedRange()
                let whole = NSRange(location: f.offset, length: f.length)
                ctx.expect(sel == whole || sel == NSRange(location: f.offset, length: f.length - 1), "selection",
                           "triple-click: expected the paragraph {\(whole.location), \(whole.length)} but got {\(sel.location), \(sel.length)}")
                ctx.snap("triple-click")
                ctx.at("single click after a triple click")
                await ctx.clickExpect(w.location, "single click collapses the paragraph selection")
            } else { ctx.issue("other", "no visible line with \"gamma\"") }
            ctx.at("double-click a Korean word")
            if let (_, w) = para(containing: "가나다라") {
                await ctx.mclick(offset: w.location + 1, clicks: 2)
                let sel = ctx.tv.selectedRange()
                let s = ns.substring(with: sel)
                ctx.expect(sel.length > 0 && NSLocationInRange(w.location + 1, sel) && !s.contains(" ") && !s.contains("\n"), "selection",
                           "double-click on 가나다라: selection {\(sel.location), \(sel.length)} = \"\(s)\"")
            }
            ctx.at("shift-click extends")
            if let (f, w) = para(containing: "alpha"), let (g, x) = para(containing: "indented") {
                _ = f; _ = g
                await ctx.clickExpect(w.location, "anchor click")
                let lo = min(w.location, x.location + 3), hi = max(w.location, x.location + 3)
                await ctx.mclick(offset: x.location + 3, mods: [.shift])
                ctx.expectSelection(NSRange(location: lo, length: hi - lo), "⇧click from alpha to indented+3")
                ctx.checkLineHighlight("range selected"); ctx.snap("shift-click")
                // 한 번 더: 같은 쪽으로 더 멀리 (선택 안쪽을 ⇧클릭하면 AppKit 은 가까운 끝을 옮긴다 — 닻 기준이 아니므로 바깥쪽만 본다)
                let far = x.location < w.location ? g.offset : g.offset + g.length - 1
                await ctx.mclick(offset: far, mods: [.shift])
                ctx.expectSelection(NSRange(location: min(w.location, far), length: abs(far - w.location)), "second ⇧click further out")
            }
            ctx.at("drag down across lines")
            let lines = frags.filter { $0.length > 12 }
            if lines.count >= 6 {
                let a = lines[1].offset + 3, b = lines[4].offset + 7
                if let pa = ctx.point(forOffset: a), let pb = ctx.point(forOffset: b) {
                    await ctx.mdrag(from: pa, to: pb)
                    ctx.expectSelection(NSRange(location: a, length: b - a), "drag from line \(ctx.liveLine(a)) col 3 down to line \(ctx.liveLine(b)) col 7")
                    ctx.expectSelectionPainted("drag selection"); ctx.checkLineHighlight("drag selection"); ctx.snap("drag-down")
                    ctx.at("drag up across lines")
                    await ctx.mdrag(from: pb, to: pa)
                    ctx.expectSelection(NSRange(location: a, length: b - a), "drag from line \(ctx.liveLine(b)) col 7 up to line \(ctx.liveLine(a)) col 3")
                    ctx.at("click collapses a drag selection")
                    await ctx.clickExpect(lines[2].offset + 5, "click inside the old selection")
                    ctx.checkLineHighlight("collapsed")
                }
            } else { ctx.issue("other", "not enough visible lines to drag over (\(lines.count))") }
            ctx.at("drag inside a wrapped paragraph")
            if let (f, _) = para(containing: "quick brown") {
                let vls = ctx.visualLines(ofParagraphAt: f.offset)
                if vls.count >= 2 {
                    let a = vls[0].range.location + 10, b = vls[1].range.location + 14
                    if let pa = ctx.point(forOffset: a), let pb = ctx.point(forOffset: b) {
                        await ctx.mdrag(from: pa, to: pb)
                        ctx.expectSelection(NSRange(location: a, length: b - a), "drag from the first to the second visual line of a wrapped paragraph")
                        ctx.snap("drag-wrapped")
                    }
                } else { ctx.note("the long paragraph did not wrap (\(vls.count) visual line)") }
            }
            ctx.at("after selections"); ctx.checkAllD("after selections")
            await ctx.key(.right); ctx.checkLineHighlight("→ collapses the selection")
            if !wrap0 { ctx.model.wordWrap = false; await ctx.settle(100) }
            ctx.mouseSummary()
        },

        // ⌘클릭 멀티 캐럿 → 입력 → 되돌리기, ⌥끌기 열 블록(아래로·위로·가상 공백) → 입력, 열 모드에서의 끌기·클릭
        Scenario(name: "mouse-multi") { ctx in
            await ctx.open(text: RealUse.columnDoc(), name: "mouse-column.txt")
            await ctx.key(.up, [.command]); await ctx.settle(150)
            let original = ctx.text.copy() as! NSString
            @MainActor func at(_ line0: Int, _ col: Int) -> Int { ctx.lineStart(line0 + 1) + col }
            @MainActor func lineText(_ line0: Int) -> String {
                let ns = ctx.text
                return ns.substring(with: NSRange(location: ctx.lineStart(line0 + 1), length: ctx.lineEnd(line0 + 1) - ctx.lineStart(line0 + 1)))
            }
            ctx.at("⌘click adds carets")
            let a = at(2, 5), b = at(3, 9), c = at(6, 14)
            await ctx.clickExpect(a, "first caret")
            await ctx.mclick(offset: b, mods: [.command]); await ctx.mclick(offset: c, mods: [.command])
            let m1 = ctx.tv.multi
            ctx.expect(m1?.ranges == [a, b, c].map { NSRange(location: $0, length: 0) } && m1?.block == nil, "multi",
                       "⌘click at offsets \(a), \(b), \(c): multi carets are \(m1?.ranges.map(\.location) ?? [])")
            ctx.checkLineHighlight("multi carets"); ctx.snap("multi-carets")
            ctx.at("type at three carets")
            await ctx.type("#")
            ctx.expect(lineText(2).hasPrefix("02|ab#cd") && lineText(3).hasPrefix("03|abcdef#g") && lineText(6).hasPrefix("06|abcdefghijk#l"), "text",
                       "typing # at three carets: lines are \"\(lineText(2).prefix(12))\", \"\(lineText(3).prefix(14))\", \"\(lineText(6).prefix(18))\"")
            ctx.expect(ctx.tv.multi?.ranges.count == 3, "multi", "after typing, \(ctx.tv.multi?.ranges.count ?? 0) carets remain (expected 3)")
            ctx.at("⌘click an existing caret removes it")
            // 여러 문단을 한 번에 바꾼 직후에는 TextKit 2 가 캐럿 사각형을 잠깐 틀리게 답한다(실측: 세 줄 아래) — 사용자는 다시 그려진 화면을 보고 누르므로 배치가 끝난 뒤의 자리를 누른다
            await ctx.settle(60)
            if let last = ctx.tv.multi?.ranges.last {
                let before = ctx.tv.multi?.ranges.map(\.location) ?? []
                let p = ctx.point(forOffset: last.location)
                await ctx.mclick(offset: last.location, mods: [.command])
                let after = ctx.tv.multi?.ranges.map(\.location) ?? []
                if after.count != 2, let p {
                    ctx.note("DIAG ⌘click at \(ctx.place(last.location)) view point \(p): carets \(before) → \(after); characterIndexForInsertion(at: p) now \(ctx.tv.characterIndexForInsertion(at: p)); caretRect now \(String(describing: ctx.tv.caretRect(at: last.location))); first responder is tv \(ctx.window.firstResponder === ctx.tv)")
                }
                ctx.expect(ctx.tv.multi?.ranges.count == 2, "multi", "⌘click on an existing caret: \(ctx.tv.multi?.ranges.count ?? 0) carets (expected 2)")
            }
            ctx.at("plain click ends multi")
            await ctx.clickExpect(at(8, 4), "plain click with multi carets")
            ctx.expect(ctx.tv.multi == nil, "multi", "a plain click left the multi-caret state on")
            ctx.at("undo the multi edit")
            // 되돌리기는 리본의 ↶ 단추 경로(model.send(.undo))로 — 코어의 shortcut("z") 는 앱이 비활성이면 메뉴가 "처리했다"고 답하지만 undo: 가 갈 키 창이 없어 아무 일도 하지 않는다
            ctx.model.send(.undo); await ctx.settle(50)
            ctx.expect(ctx.text.isEqual(to: original as String), "text", "undo after a three-caret insert did not restore the text (length \(ctx.length) vs \(original.length))")
            ctx.checkAllD("after undo")

            ctx.at("⌥drag a column block downwards")
            if let p1 = ctx.point(forOffset: at(2, 5)), let p2 = ctx.point(forOffset: at(6, 12)) {
                await ctx.dragWith(mods: [.option], from: p1, to: p2)
                let blk = ctx.tv.multi?.block
                ctx.expect(blk == ColumnBlock(topLineStart: ctx.lineStart(3), lineCount: 5, anchorCol: 5, headCol: 12, headIsBottom: true), "multi",
                           "⌥drag (line 3 col 5) → (line 7 col 12): block \(String(describing: blk))")
                ctx.expect(ctx.tv.multi?.ranges.map(\.length) == [7, 7, 0, 7, 7], "multi", "block range lengths \(ctx.tv.multi?.ranges.map(\.length) ?? []) (expected 7,7,0,7,7 — the third line is short)")
                ctx.expectBlockHighlighted("⌥drag block with a short line in the middle"); ctx.expectSelectionPainted("⌥drag block with a short line in the middle")
                ctx.checkLineHighlight("column block"); ctx.snap("column-block")
                ctx.at("type into the block")
                await ctx.type("#")
                ctx.expect(lineText(2).hasPrefix("02|ab#jkl") && lineText(4) == "04|ab#" && lineText(6).hasPrefix("06|ab#jkl"), "text",
                           "typing # into the block: lines \"\(lineText(2).prefix(12))\", \"\(lineText(4))\", \"\(lineText(6).prefix(12))\"")
                ctx.snap("column-typed")
                await ctx.key(.escape)
                ctx.expect(ctx.tv.multi == nil, "multi", "Esc did not leave the column block")
                ctx.model.send(.undo); await ctx.settle(50)
                ctx.expect(ctx.text.isEqual(to: original as String), "text", "undo after a block insert did not restore the text")
            } else { ctx.issue("other", "column drag points not visible") }

            ctx.at("⌥drag a column block upwards")
            if let p1 = ctx.point(forOffset: at(12, 8)), let p2 = ctx.point(forOffset: at(10, 3)) {
                await ctx.dragWith(mods: [.option], from: p1, to: p2)
                let blk = ctx.tv.multi?.block
                ctx.expect(blk == ColumnBlock(topLineStart: ctx.lineStart(11), lineCount: 3, anchorCol: 8, headCol: 3, headIsBottom: false), "multi",
                           "⌥drag (line 13 col 8) → (line 11 col 3): block \(String(describing: blk))")
                ctx.expectBlockHighlighted("⌥drag block upwards"); ctx.expectSelectionPainted("⌥drag block upwards")
                await ctx.key(.escape)
            }
            ctx.at("⌥drag from virtual space past a short line")
            if let end = ctx.tv.caretRect(at: ctx.lineEnd(15)), let p2 = ctx.point(forOffset: at(15, 9)) {
                let cw = ctx.tv.charWidth
                await ctx.dragWith(mods: [.option], from: NSPoint(x: end.minX + 6 * cw + 1, y: end.midY), to: p2)
                let blk = ctx.tv.multi?.block
                ctx.expect(blk?.anchorCol == 5 + 6 && blk?.headCol == 9 && blk?.lineCount == 2, "multi",
                           "⌥drag from 6 columns past the end of the short line 15 to (line 16 col 9): block \(String(describing: blk))")
                ctx.expectBlockHighlighted("block that starts on a short line (virtual space)"); ctx.expectSelectionPainted("block that starts on a short line (virtual space)")
                ctx.snap("column-virtual")
                await ctx.key(.escape)
                // 짧은 줄이 블록의 맨 아래일 때, 그리고 위·아래가 모두 짧은 줄일 때
                ctx.at("⌥drag blocks with short lines at the edges")
                if let q1 = ctx.point(forOffset: at(13, 6)), let e2 = ctx.tv.caretRect(at: ctx.lineEnd(15)) {
                    await ctx.dragWith(mods: [.option], from: q1, to: NSPoint(x: e2.minX + 5 * cw + 1, y: e2.midY))
                    ctx.expect(ctx.tv.multi?.block?.lineCount == 2 && ctx.tv.multi?.ranges.map(\.length) == [4, 0], "multi", "block (line 14 col 6) → (short line 15, virtual col 10): \(String(describing: ctx.tv.multi))")
                    ctx.expectBlockHighlighted("block that ends on a short line"); ctx.expectSelectionPainted("block that ends on a short line"); ctx.snap("column-short-bottom")
                    await ctx.key(.escape)
                }
                if let e1 = ctx.tv.caretRect(at: ctx.lineEnd(10)), let e3 = ctx.tv.caretRect(at: ctx.lineEnd(15)) {
                    await ctx.dragWith(mods: [.option], from: NSPoint(x: e1.minX + 3 * cw + 1, y: e1.midY), to: NSPoint(x: e3.minX + 9 * cw + 1, y: e3.midY))
                    ctx.expect(ctx.tv.multi?.block?.lineCount == 6 && ctx.tv.multi?.ranges.map(\.length) == [0, 6, 6, 6, 6, 0], "multi", "block between the short lines 10 and 15: \(String(describing: ctx.tv.multi))")
                    ctx.expectBlockHighlighted("block between two short lines"); ctx.expectSelectionPainted("block between two short lines"); ctx.snap("column-short-both")
                    ctx.at("type into a block whose first line is short")
                    await ctx.type("@"); await ctx.settle(50)
                    ctx.expect(lineText(9) == "09|ab   @" && lineText(10).hasPrefix("10|abcde@lmn") && lineText(14) == "14|ab   @", "text",
                               "typing @ into the block: \"\(lineText(9))\", \"\(lineText(10).prefix(14))\", \"\(lineText(14))\"")
                    await ctx.key(.escape)
                    ctx.model.send(.undo); await ctx.settle(50)
                    ctx.expect(ctx.text.isEqual(to: original as String), "text", "undo after typing into a ragged block did not restore the text")
                }
            }
            ctx.at("column mode: plain drag makes a block")
            ctx.model.columnMode = true; await ctx.settle(50)
            if let p1 = ctx.point(forOffset: at(20, 4)), let p2 = ctx.point(forOffset: at(23, 10)) {
                await ctx.mdrag(from: p1, to: p2)
                let blk = ctx.tv.multi?.block
                ctx.expect(blk?.lineCount == 4 && blk?.anchorCol == 4 && blk?.headCol == 10, "multi", "column mode drag (line 21 col 4) → (line 24 col 10): block \(String(describing: blk))")
                ctx.at("column mode: a click is a one-line block; typing lands on the clicked column")
                await ctx.mclick(offset: at(26, 7))
                ctx.expect(ctx.tv.multi?.block?.lineCount == 1 && ctx.tv.selectedRange() == NSRange(location: at(26, 7), length: 0), "multi",
                           "column mode click at line 27 col 7: block \(String(describing: ctx.tv.multi?.block)), selection \(ctx.tv.selectedRange())")
                await ctx.type("Q")
                ctx.expect(lineText(26).hasPrefix("26|abcdQe"), "text", "column mode: typed Q at line 27 col 7 → \"\(lineText(26).prefix(14))\"")
                ctx.at("column mode: ⇧↓ extends the block")
                await ctx.key(.down, [.shift], count: 2)
                ctx.expect(ctx.tv.multi?.block?.lineCount == 3, "multi", "⇧↓×2 in column mode: block \(String(describing: ctx.tv.multi?.block))")
                await ctx.key(.right, [.shift], count: 4)
                ctx.expect(ctx.tv.multi?.block?.width == 4 && ctx.tv.multi?.ranges.map(\.length) == [4, 4, 4], "multi", "⇧→×4 in column mode: \(String(describing: ctx.tv.multi))")
                ctx.expectBlockHighlighted("column mode ⇧arrows"); ctx.expectSelectionPainted("column mode ⇧arrows")
                ctx.snap("column-mode")
            }
            ctx.at("column mode off")
            ctx.model.columnMode = false; await ctx.settle(50)
            ctx.expect(ctx.tv.multi == nil && ctx.tv.selectedRange().length == 0, "multi", "leaving column mode left a block (\(String(describing: ctx.tv.multi)))")
            ctx.checkAllD("after column mode"); ctx.checkLineHighlight("after column mode")
            ctx.mouseSummary()
        },

        // 거터: 스크롤·줄을 넣고 빼는 편집·줄바꿈 전환·줄 번호 끄고 켜기 뒤에 번호가 본문과 같은 높이에 있는가
        Scenario(name: "mouse-gutter") { ctx in
            let wrap0 = ctx.model.wordWrap
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "mouse-gutter.md") }
            ctx.at("opened"); await ctx.settle(200); ctx.checkAllD("opened")
            ctx.at("go to line 9000")
            ctx.model.jump(toLine: 9000); await ctx.settle(300); ctx.checkAllD("go to line 9000")
            for (i, d) in [CGFloat(310), -95, 1240, -777, 33].enumerated() {
                ctx.at("scroll \(Int(d)) (\(i + 1))")
                await ctx.scrollBy(d); await ctx.settle(0); ctx.checkGutter("pixel scroll \(Int(d))")
            }
            ctx.at("return ×3 in the middle of the screen")
            ctx.ensureViewportRange("before the Returns")
            if let t = ctx.anchor() {
                await ctx.clickExpect(t.offset, "click a middle line")
                await ctx.key(.right, [.command])
                for i in 1...3 {
                    await ctx.key(.returnKey); await ctx.settle(0)
                    ctx.checkGutter("right after Return \(i)")
                }
                ctx.snap("after-returns")
                await ctx.settle(400); ctx.checkAllD("400 ms after the Returns")
                ctx.at("type on the new line")
                await ctx.type("새 줄 new line"); await ctx.settle(0); ctx.checkGutter("typing on the new line")
                ctx.at("backspace joins lines")
                await ctx.key(.delete, [.command]); await ctx.settle(0)
                for i in 1...3 {
                    await ctx.key(.delete); await ctx.settle(0)
                    ctx.checkGutter("right after Backspace \(i)")
                }
                await ctx.settle(400); ctx.checkAllD("400 ms after the Backspaces"); ctx.checkCaretVisible("after the Backspaces")
            }
            // 줄바꿈 전환: 1.3 MB 문서의 전체 재배치(수 초의 정지)와 보던 곳이 유지되는가는 레이아웃 영역의 몫 — 여기서는 전환 뒤 거터 번호가 본문과 맞는지만 본다
            ctx.at("wrap toggled")
            let top0 = ctx.topLine()
            await ctx.withRelaxedStalls(8000) { ctx.model.wordWrap = !wrap0; await ctx.settle(300) }
            ctx.checkAllD("wrap \(!wrap0 ? "on" : "off")"); ctx.checkInk("wrap toggled"); ctx.snap("wrap-toggled")
            ctx.note("top line before the wrap toggle \(top0), after \(ctx.topLine())")
            await ctx.clickGrid("after the wrap toggle", paragraphs: 8)
            await ctx.withRelaxedStalls(8000) { ctx.model.wordWrap = wrap0; await ctx.settle(300) }
            ctx.at("wrap restored"); ctx.checkAllD("wrap restored"); ctx.checkInk("wrap restored")
            ctx.at("line numbers off")
            ctx.model.showLineNumbers = false; await ctx.settle(200)
            ctx.checkLayout("line numbers off"); ctx.checkInk("line numbers off")
            await ctx.clickGrid("line numbers off", paragraphs: 8); ctx.snap("no-gutter")
            ctx.at("line numbers on")
            ctx.model.showLineNumbers = true; await ctx.settle(200)
            ctx.checkAllD("line numbers on"); ctx.checkInk("line numbers on")
            await ctx.clickGrid("line numbers back on", paragraphs: 8)
            ctx.mouseSummary()
        },

        // 줄 수가 9,999 → 10,000 을 넘어 거터가 넓어질 때 (본문 폭이 줄어 다시 감긴다)
        Scenario(name: "mouse-gutter-digits") { ctx in
            let body = (1...9997).map { "line \($0) 한글 text" }.joined(separator: "\n")
            await ctx.withRelaxedStalls { await ctx.open(text: body, name: "mouse-digits.txt") }   // 준비: 9,997줄 파일 열기
            ctx.at("opened at the end"); await ctx.settle(300)
            ctx.checkAllD("opened")
            let w0 = ctx.gutter?.thickness ?? 0
            ctx.at("append lines past 10000")
            for i in 1...5 {
                await ctx.key(.returnKey); await ctx.type("added \(i)"); await ctx.settle(0)
                ctx.checkGutter("appended line \(i)"); ctx.checkCaretVisible("appended line \(i)")
            }
            await ctx.settle(500)
            let w1 = ctx.gutter?.thickness ?? 0
            ctx.note("gutter thickness \(w0) → \(w1)")
            ctx.expect(w1 > w0, "gutter", "the gutter did not widen for a 5-digit line count (\(w0) → \(w1))")
            ctx.checkAllD("after the gutter widened"); ctx.checkInk("after the gutter widened"); ctx.checkCaretVisible("after the gutter widened")
            if let g = ctx.gutter { ctx.expect(abs(ctx.scroll.frame.minX - g.frame.maxX) < 0.5, "gutter", "the text area starts at x \(ctx.scroll.frame.minX) but the gutter ends at \(g.frame.maxX)") }
            await ctx.clickGrid("after the gutter widened"); ctx.snap("widened")
            ctx.at("delete back below 10000")
            for _ in 1...5 { await ctx.key(.delete, [.command]); await ctx.key(.delete) }
            await ctx.settle(500)
            ctx.checkAllD("after the gutter narrowed"); ctx.checkCaretVisible("after the gutter narrowed")
            ctx.note("gutter thickness now \(ctx.gutter?.thickness ?? 0)")
            await ctx.clickGrid("after the gutter narrowed")
            ctx.mouseSummary()
        },

        // 접기: 거터 화살표 클릭으로 접고 펴기, 표식 클릭, 접힌 뒤 클릭 위치, 캐럿 줄 접기, 접힌 머리 줄에서의 입력·방향키
        Scenario(name: "mouse-fold") { ctx in
            await ctx.open(text: RealUse.foldDoc(h1: false), name: "mouse-fold.md")
            await ctx.settle(600)   // 접기 후보 스캔(줄 인덱스 발행 뒤 백그라운드)
            await ctx.key(.up, [.command]); await ctx.settle(150)
            let h2 = RealUse.foldHeader(2), h1 = RealUse.foldHeader(1), h3 = RealUse.foldHeader(3)
            ctx.at("arrows are offered")
            ctx.expect(ctx.marker(atLine: h2) == .foldable && ctx.marker(atLine: h2 + 2) == .foldable && ctx.marker(atLine: h2 + 1) == nil, "fold",
                       "fold arrows: header \(String(describing: ctx.marker(atLine: h2))), item \(String(describing: ctx.marker(atLine: h2 + 2))), body \(String(describing: ctx.marker(atLine: h2 + 1)))")
            ctx.at("fold section 2 by its gutter arrow")
            if let p = ctx.foldArrowPoint(forLine: h2) {
                await ctx.clickGutter(at: p); await ctx.settle(100)
                ctx.expect(!ctx.hidden(line: h2) && ctx.hidden(line: h2 + 1) && ctx.hidden(line: h2 + 6) && !ctx.hidden(line: h2 + 7) && ctx.marker(atLine: h2) == .folded, "fold",
                           "arrow click on line \(h2): hidden(\(h2 + 1))=\(ctx.hidden(line: h2 + 1)) hidden(\(h2 + 6))=\(ctx.hidden(line: h2 + 6)) hidden(\(h2 + 7))=\(ctx.hidden(line: h2 + 7)) marker=\(String(describing: ctx.marker(atLine: h2)))")
                ctx.expect(ctx.pillRects().count == 1, "fold", "expected one ⋯ pill, drew \(ctx.tv.foldPillRects.count)")
                ctx.checkAllD("after folding section 2"); ctx.checkInk("after folding section 2"); ctx.snap("folded-2")
                await ctx.clickGrid("with section 2 folded", paragraphs: 30)
            } else { ctx.issue("fold", "no gutter row for line \(h2)") }
            ctx.at("fold the section right above a fold")
            if let p = ctx.foldArrowPoint(forLine: h1) {
                await ctx.clickGutter(at: p); await ctx.settle(100)
                ctx.expect(ctx.hidden(line: h1 + 1) && ctx.hidden(line: h2 + 1), "fold", "folding line \(h1) above a fold: hidden(\(h1 + 1))=\(ctx.hidden(line: h1 + 1)) hidden(\(h2 + 1))=\(ctx.hidden(line: h2 + 1))")
                ctx.checkAllD("two adjacent folds"); ctx.snap("folded-1-2")
            }
            ctx.at("unfold the lower fold by its arrow (row right below hidden lines)")
            if let p = ctx.foldArrowPoint(forLine: h2) {
                await ctx.clickGutter(at: p); await ctx.settle(100)
                ctx.expect(!ctx.hidden(line: h2 + 1) && ctx.hidden(line: h1 + 1) && ctx.marker(atLine: h2) == .foldable, "fold",
                           "arrow click on folded line \(h2): hidden(\(h2 + 1))=\(ctx.hidden(line: h2 + 1)) hidden(\(h1 + 1))=\(ctx.hidden(line: h1 + 1))")
                ctx.checkAllD("lower fold opened")
            } else { ctx.issue("fold", "no gutter row for line \(h2) while section 1 is folded") }
            ctx.at("fold the item right under an open header")
            if let p = ctx.foldArrowPoint(forLine: h2 + 2) {
                await ctx.clickGutter(at: p); await ctx.settle(100)
                ctx.expect(ctx.hidden(line: h2 + 3) && ctx.hidden(line: h2 + 4) && !ctx.hidden(line: h2 + 5), "fold", "item fold at line \(h2 + 2): hidden \(ctx.hidden(line: h2 + 3)) \(ctx.hidden(line: h2 + 4)) \(ctx.hidden(line: h2 + 5))")
                ctx.checkAllD("item folded"); await ctx.clickGrid("with a section and an item folded", paragraphs: 30)
            }
            ctx.at("click the ⋯ pill")
            let pills = ctx.pillRects()
            ctx.expect(pills.count == 2, "fold", "expected two pills (section 1, item of section 2), drew \(pills.count)")
            if let first = pills.first {
                let before = ctx.caret
                await ctx.mclick(atViewPoint: NSPoint(x: first.0.midX, y: first.0.midY)); await ctx.settle(100)
                ctx.expect(!ctx.hidden(line: h1 + 1), "fold", "clicking the pill of line \(h1) did not unfold it")
                ctx.expect(ctx.caret == before, "fold", "clicking a pill moved the caret from \(before) to \(ctx.caret)")
                ctx.checkAllD("pill clicked"); ctx.snap("pill-clicked")
            }
            ctx.at("caret inside, fold command")
            ctx.model.jump(toLine: h3 + 3); await ctx.settle(300)
            let body = ctx.lineStart(h3 + 3) + 8
            await ctx.clickExpect(body, "click a nested line of section 3")
            ctx.model.send(.fold); await ctx.settle(100)
            ctx.expectCaret(ctx.lineEnd(h3 + 2), "fold at caret: caret moves to the end of the item header")
            ctx.checkCaretVisible("fold at caret"); ctx.checkLineHighlight("fold at caret")
            ctx.model.send(.fold); await ctx.settle(100)
            ctx.expectCaret(ctx.lineEnd(h3), "second fold at caret: caret moves to the end of the section header")
            ctx.expect(ctx.hidden(line: h3 + 1) && ctx.hidden(line: h3 + 6), "fold", "second fold at caret did not hide section 3")
            ctx.checkAllD("section 3 folded by command"); ctx.checkLineHighlight("section 3 folded"); ctx.snap("folded-3")
            ctx.at("type at the end of a folded header")
            let lenBefore = ctx.length
            await ctx.type(" 메모x"); await ctx.settle(50)
            ctx.expect(ctx.length == lenBefore + 4 && ctx.caret == ctx.lineEnd(h3) && ctx.hidden(line: h3 + 1), "fold",
                       "typing at the end of the folded header: length \(lenBefore) → \(ctx.length), caret \(ctx.place(ctx.caret)), still folded \(ctx.hidden(line: h3 + 1))")
            await ctx.settle(450)   // 다시 스캔된 뒤에도 접힌 채인가
            ctx.expect(ctx.hidden(line: h3 + 1) && ctx.marker(atLine: h3) == .folded, "fold", "the fold under the edited header opened after the rescan")
            ctx.checkAllD("typed on a folded header")
            ctx.at("↓ skips the fold, ↑ returns")
            await ctx.key(.down)
            ctx.expect(ctx.liveLine(ctx.caret) == h3 + 7 && ctx.hidden(line: h3 + 1), "fold", "↓ from the folded header went to line \(ctx.liveLine(ctx.caret)) (expected \(h3 + 7)), folded \(ctx.hidden(line: h3 + 1))")
            await ctx.key(.up)
            ctx.expect(ctx.liveLine(ctx.caret) == h3 && ctx.hidden(line: h3 + 1), "fold", "↑ back went to line \(ctx.liveLine(ctx.caret)) (expected \(h3))")
            ctx.at("⇧↓ from a folded header")
            do {
                let start = ctx.caret
                await ctx.key(.down, [.shift]); await ctx.settle(50)
                let sel = ctx.tv.selectedRange()
                ctx.note("⇧↓ on the folded header at \(ctx.place(start)): selection {\(sel.location), \(sel.length)} ends at \(ctx.place(NSMaxRange(sel))), end hidden \(ctx.hidden(NSMaxRange(sel))), still folded \(ctx.hidden(line: h3 + 1))")
                // 첫 ⇧↓: 머리 줄 한 줄(개행까지)이 선택된다 — 끝이 숨김 구간의 시작에 딱 놓이므로 접힌 채로 둔다
                ctx.expect(sel == NSRange(location: start, length: ctx.lineStart(h3 + 1) - start) && ctx.hidden(line: h3 + 1), "fold",
                           "⇧↓ on a folded header (col 0): selection {\(sel.location), \(sel.length)}, expected the header line {\(start), \(ctx.lineStart(h3 + 1) - start)} with the fold kept (\(ctx.hidden(line: h3 + 1)))")
                ctx.snap("shift-down-fold")
                // 둘째 ⇧↓: 선택의 끝이 숨은 줄 안으로 들어간다 — 보이지 않는 채로 늘어나면 안 된다 (펼쳐져야 한다)
                await ctx.key(.down, [.shift]); await ctx.settle(100)
                let sel2 = ctx.tv.selectedRange()
                ctx.expect(sel2.length > sel.length && !ctx.hidden(NSMaxRange(sel2)) && !ctx.hidden(NSMaxRange(sel2) - 1), "fold",
                           "second ⇧↓ on a folded header: the selection {\(sel2.location), \(sel2.length)} ends at \(ctx.place(NSMaxRange(sel2))) on a hidden line — the key press shows nothing on screen")
                ctx.checkAllD("⇧↓ into a fold"); ctx.snap("shift-down-into-fold")
                await ctx.key(.left); await ctx.settle(50)
                if !ctx.hidden(line: h3 + 1) { ctx.note("section 3 opened by the collapsed selection — fold it again"); await ctx.mclick(offset: ctx.lineStart(h3) + 3); ctx.model.send(.fold); await ctx.settle(100) }
                await ctx.mclick(offset: ctx.lineStart(h3) + 3)
            }
            ctx.at("⇧↑ from the line below a fold")
            if ctx.hidden(line: h3 + 1), await ctx.clickExpect(ctx.lineStart(h3 + 7), "click the line below the fold") {
                await ctx.key(.up, [.shift]); await ctx.settle(100)
                let sel = ctx.tv.selectedRange()
                ctx.expect(sel.length > 0 && !ctx.hidden(sel.location), "fold",
                           "⇧↑ from the line below a fold: the selection {\(sel.location), \(sel.length)} starts at \(ctx.place(sel.location)) on a hidden line — nothing on screen shows it")
                ctx.checkAllD("⇧↑ into a fold"); ctx.snap("shift-up-into-fold")
                await ctx.key(.right); await ctx.settle(50)
                if !ctx.hidden(line: h3 + 1) { await ctx.mclick(offset: ctx.lineStart(h3) + 3); ctx.model.send(.fold); await ctx.settle(100) }
                await ctx.mclick(offset: ctx.lineStart(h3) + 3)
            }
            ctx.at("drag across a fold selects the hidden text too")
            if let pa = ctx.point(forOffset: ctx.lineStart(h3 - 1)), let pb = ctx.point(forOffset: ctx.lineStart(h3 + 8) + 4) {
                await ctx.mdrag(from: pa, to: pb)
                ctx.expectSelection(NSRange(location: ctx.lineStart(h3 - 1), length: ctx.lineStart(h3 + 8) + 4 - ctx.lineStart(h3 - 1)), "drag from the line above a fold to the header below it")
                ctx.expect(ctx.hidden(line: h3 + 1), "fold", "dragging a selection across a fold opened it")
                ctx.snap("drag-across-fold")
            }
            ctx.at("click a line below the folds")
            await ctx.clickGrid("with section 3 folded", paragraphs: 30)
            ctx.at("unfold all")
            ctx.model.send(.unfoldAll); await ctx.settle(150)
            ctx.expect(!ctx.foldsActive && ctx.pillRects().isEmpty, "fold", "unfold all left folds (\(ctx.tv.foldPillRects.count) pills)")
            ctx.checkAllD("unfold all"); ctx.checkInk("unfold all"); await ctx.clickGrid("after unfold all")
            ctx.mouseSummary()
        },

        // 단서: 모두 접기 뒤 캐럿이 숨은 줄에 남는가 — 가운데 본문 줄에 캐럿 → 모두 접기 → 캐럿 줄이 보이는가, 입력은 어디로 가는가
        Scenario(name: "mouse-foldall") { ctx in
            await ctx.open(text: RealUse.foldDoc(h1: false), name: "mouse-foldall.md")
            await ctx.settle(600)
            let h15 = RealUse.foldHeader(15)
            ctx.at("caret on a nested line in the middle")
            ctx.model.jump(toLine: h15 + 3); await ctx.settle(300)
            await ctx.clickExpect(ctx.lineStart(h15 + 3) + 9, "click a nested line of section 15")
            ctx.at("fold all")
            ctx.model.send(.foldAll); await ctx.settle(200)
            ctx.expect(ctx.foldsActive && ctx.hidden(line: h15 + 3), "fold", "fold all did not hide line \(h15 + 3)")
            ctx.expect(!ctx.hidden(ctx.caret), "fold", "fold all left the caret on a hidden line: \(ctx.place(ctx.caret))")
            ctx.expectCaret(ctx.lineEnd(h15), "fold all: caret moves to the end of its section header")
            await ctx.checkFramesStable("fold all, caret was in a body line")
            ctx.checkCaretVisible("fold all"); ctx.checkAllD("fold all"); ctx.checkInk("fold all"); ctx.checkLineHighlight("fold all"); ctx.snap("fold-all")
            ctx.at("type after fold all")
            let before = ctx.caret
            await ctx.type("Z"); await ctx.settle(50)
            ctx.expect(ctx.text.character(at: before) == 90 && ctx.caret == before + 1 && !ctx.hidden(ctx.caret) && ctx.hidden(line: h15 + 1), "fold",
                       "typing after fold all: caret \(ctx.place(ctx.caret)), char at the old caret \(ctx.text.character(at: before)), section still folded \(ctx.hidden(line: h15 + 1))")
            ctx.checkCaretVisible("typing after fold all")
            await ctx.settle(450)
            ctx.expect(ctx.hidden(line: h15 + 1), "fold", "the section under the typed header opened after the rescan")
            ctx.checkAllD("typed after fold all"); ctx.snap("typed")
            ctx.model.send(.undo); await ctx.settle(450)
            ctx.at("click headers with everything folded")
            await ctx.clickGrid("everything folded", paragraphs: 40)
            ctx.checkAllD("everything folded, after clicks")
            ctx.at("↓ ×4 over folds")
            await ctx.clickExpect(ctx.lineStart(h15) + 3, "click the header of section 15")
            await ctx.key(.down, count: 4)
            ctx.expect(ctx.liveLine(ctx.caret) == RealUse.foldHeader(17) && !ctx.hidden(ctx.caret) && ctx.hidden(line: h15 + 1), "fold",
                       "↓×4 from header 15 with everything folded: caret on line \(ctx.liveLine(ctx.caret)) (expected \(RealUse.foldHeader(17))), hidden=\(ctx.hidden(ctx.caret))")
            ctx.checkCaretVisible("↓ over folds")
            ctx.at("unfold all keeps the caret line in view")
            ctx.model.send(.unfoldAll); await ctx.settle(200)
            ctx.checkAllD("unfold all"); ctx.checkInk("unfold all"); ctx.checkCaretVisible("unfold all"); ctx.snap("unfold-all")

            // 캐럿이 숨지 않는 자리(머리 줄·구역 사이 빈 줄)에 있으면 모두 접기가 캐럿도 스크롤도 건드리지 않는다 — 그때도 화면의 글자가 레이아웃과 같은 자리에 있어야 한다
            for (what, line, col) in [("a section header", h15, 5), ("the blank line between sections", h15 + 7, 0), ("a header again after scrolling", RealUse.foldHeader(9), 2)] {
                ctx.at("fold all with the caret on \(what)")
                ctx.model.jump(toLine: line); await ctx.settle(300)
                if line == RealUse.foldHeader(9) { await ctx.scrollBy(-90); await ctx.settle(50) }
                await ctx.clickExpect(ctx.lineStart(line) + col, "click \(what)")
                let before = ctx.caret
                ctx.model.send(.foldAll); await ctx.settle(200)
                ctx.expectCaret(before, "fold all with the caret on \(what): the caret stays")
                await ctx.checkFramesStable("fold all, caret on \(what)")
                ctx.checkCaretVisible("fold all, caret on \(what)"); ctx.checkAllD("fold all, caret on \(what)"); ctx.checkInk("fold all, caret on \(what)")
                ctx.checkBandOnScreen("fold all, caret on \(what)"); ctx.checkLineHighlight("fold all, caret on \(what)"); ctx.snap("fold-all-caret-\(line)")
                await ctx.clickGrid("everything folded, caret was on \(what)", paragraphs: 40)
                ctx.model.send(.unfoldAll); await ctx.settle(200)
                ctx.checkAllD("unfold all, caret was on \(what)")
            }

            ctx.at("fold all with a selection inside a body")
            let s0 = ctx.lineStart(h15 + 3) + 4, s1 = ctx.lineStart(h15 + 4) + 10
            ctx.model.jump(toLine: h15 + 3); await ctx.settle(300)
            if let pa = ctx.point(forOffset: s0), let pb = ctx.point(forOffset: s1) {
                await ctx.mdrag(from: pa, to: pb)
                ctx.expectSelection(NSRange(location: s0, length: s1 - s0), "drag-select inside section 15")
                ctx.model.send(.foldAll); await ctx.settle(200)
                let sel = ctx.tv.selectedRange()
                let lost = ctx.hidden(sel.location) && (sel.length == 0 || ctx.hidden(NSMaxRange(sel) - 1))
                ctx.expect(!lost, "fold", "fold all with a selection: the whole selection {\(sel.location), \(sel.length)} is on hidden lines — nothing on screen shows where typing will go")
                ctx.expectCaret(ctx.lineEnd(h15), "fold all with a selection inside a section: the selection collapses to the end of the section header")
                ctx.checkCaretVisible("fold all with a selection"); ctx.checkLineHighlight("fold all with a selection"); ctx.snap("fold-all-selection")
                ctx.at("type with the selection folded away")
                let len0 = ctx.length
                await ctx.type("Q"); await ctx.settle(100)
                ctx.note("typed Q after fold all with a selection: length \(len0) → \(ctx.length), caret \(ctx.place(ctx.caret)), caret hidden \(ctx.hidden(ctx.caret)), section folded \(ctx.hidden(line: h15 + 1))")
                ctx.expect(ctx.length == len0 + 1 && ctx.hidden(line: h15 + 1) && !ctx.hidden(ctx.caret), "fold",
                           "typing after fold all with a selection: length \(len0) → \(ctx.length) (hidden text must not be replaced), caret \(ctx.place(ctx.caret)), section folded \(ctx.hidden(line: h15 + 1))")
                ctx.checkCaretVisible("typed after a folded selection"); await ctx.settle(450); ctx.checkAllD("typed after a folded selection"); ctx.snap("typed-over-selection")
                if ctx.length != len0 { ctx.model.send(.undo); await ctx.settle(450) }
                // 한쪽 끝만 숨는 선택: 머리 줄에서 시작해 숨은 줄에서 끝나면 보이는 부분(머리 줄 끝까지)만 남는다 — 숨은 부분의 띠가 다음 줄 위에 유령처럼 그려지지 않게
                ctx.at("fold with a selection that starts on the header")
                ctx.model.send(.unfoldAll); await ctx.settle(200)
                ctx.model.jump(toLine: h15); await ctx.settle(300)
                let t0 = ctx.lineStart(h15) + 3, t1 = ctx.lineStart(h15 + 2) + 4
                if let qa = ctx.point(forOffset: t0), let qb = ctx.point(forOffset: t1) {
                    await ctx.mdrag(from: qa, to: qb)
                    ctx.expectSelection(NSRange(location: t0, length: t1 - t0), "drag from the header into the body")
                    ctx.model.send(.foldAll); await ctx.settle(200)
                    ctx.expectSelection(NSRange(location: t0, length: ctx.lineStart(h15 + 1) - t0), "fold all trims a selection that ends on a hidden line to its visible part")
                    ctx.expectSelectionPainted("fold all with a partly visible selection")
                    ctx.expect(ctx.hidden(line: h15 + 1), "fold", "the section opened although the selection was trimmed to the header")
                    await ctx.checkFramesStable("fold all, partly visible selection")
                    ctx.checkAllD("fold all with a partly visible selection"); ctx.checkInk("fold all with a partly visible selection")
                    ctx.snap("fold-all-partial-selection")
                    await ctx.settle(300)
                    ctx.checkAllD("fold all with a partly visible selection, 300 ms later"); ctx.snap("fold-all-partial-selection-later")
                    await ctx.clickGrid("everything folded after a partly visible selection", paragraphs: 40)
                }
                ctx.at("fold with a selection that starts in the body and ends past the section")
                ctx.model.send(.unfoldAll); await ctx.settle(200)
                ctx.model.jump(toLine: h15 + 5); await ctx.settle(300)
                let u0 = ctx.lineStart(h15 + 5) + 2, u1 = ctx.lineStart(h15 + 8) + 6   // 본문 줄 → 다음 구역 머리 줄
                if let qa = ctx.point(forOffset: u0), let qb = ctx.point(forOffset: u1) {
                    await ctx.mdrag(from: qa, to: qb)
                    ctx.expectSelection(NSRange(location: u0, length: u1 - u0), "drag from a body line to the next header")
                    ctx.model.send(.foldAll); await ctx.settle(200)
                    let visibleStart = ctx.lineStart(h15 + 7)
                    ctx.expectSelection(NSRange(location: visibleStart, length: u1 - visibleStart), "fold all trims a selection that starts on a hidden line to the first visible line after the fold")
                    ctx.expectSelectionPainted("fold all with a selection that starts hidden"); ctx.checkAllD("fold all with a selection that starts hidden"); ctx.snap("fold-all-selection-tail")
                }
            }
            ctx.model.send(.unfoldAll); await ctx.settle(200)

            // 셀프테스트가 한 번 실패한 순서: 영역의 머리 줄을 지우고 → 되돌리고 → 모두 접기. 되돌린 직후에는 접기 후보가 아직 다시 스캔되지 않았다(250 ms + 백그라운드)
            for (what, gap) in [("400 ms after undo", UInt64(400)), ("right after undo", UInt64(0))] {
                ctx.at("delete a region header, undo, fold all (\(what))")
                ctx.model.send(.unfoldAll); await ctx.settle(300)
                ctx.model.jump(toLine: h15 + 2); await ctx.settle(300)
                let len0 = ctx.length
                ctx.model.textTool(.deleteLine); await ctx.settle(300)
                ctx.model.send(.undo)
                if gap > 0 { await ctx.settle(gap) }
                let afterUndo = ctx.tv.selectedRange()
                ctx.model.send(.foldAll); await ctx.settle(300)
                let sel = ctx.tv.selectedRange()
                ctx.note("selection after undo {\(afterUndo.location), \(afterUndo.length)} at \(ctx.place(afterUndo.location)); after fold all {\(sel.location), \(sel.length)} at \(ctx.place(sel.location)), hidden \(ctx.hidden(sel.location))")
                ctx.expect(ctx.length == len0, "text", "undo of delete line: length \(len0) → \(ctx.length)")
                ctx.expect(!ctx.hidden(sel.location) && (sel.length == 0 || !ctx.hidden(NSMaxRange(sel) - 1)), "fold",
                           "delete header → undo → fold all (\(what)): the selection {\(sel.location), \(sel.length)} at \(ctx.place(sel.location)) is on a hidden line")
                ctx.checkCaretVisible("fold all after undo (\(what))")
                await ctx.settle(600)   // 다시 스캔된 후보가 적용된 뒤에도
                let later = ctx.tv.selectedRange()
                ctx.expect(!ctx.hidden(later.location), "fold", "delete header → undo → fold all (\(what)), after the rescan: caret at \(ctx.place(later.location)) is on a hidden line")
                ctx.checkAllD("fold all after undo (\(what))"); ctx.checkCaretVisible("fold all after undo, after the rescan (\(what))")
            }
            ctx.model.send(.unfoldAll); await ctx.settle(300)

            ctx.at("fold all at the document end")
            await ctx.key(.down, [.command]); await ctx.settle(150)
            ctx.model.send(.foldAll); await ctx.settle(200)
            ctx.expect(!ctx.hidden(ctx.caret), "fold", "fold all at the document end: caret hidden at \(ctx.place(ctx.caret))")
            ctx.checkCaretVisible("fold all at the end"); ctx.checkAllD("fold all at the end"); ctx.checkInk("fold all at the end")
            ctx.checkLastLineNumber("fold all at the end"); ctx.checkLineHighlight("fold all at the end"); ctx.snap("fold-all-end")
            await ctx.clickGrid("everything folded, at the end", paragraphs: 40)
            ctx.model.send(.unfoldAll); await ctx.settle(200)
            ctx.checkAllD("unfold all at the end"); ctx.checkCaretVisible("unfold all at the end")

            // 문서 전체를 품는 # 제목: 모두 접으면 한 줄만 남는다 (셀프테스트가 실패했던 모양)
            ctx.at("top heading: fold all from the middle")
            await ctx.open(text: RealUse.foldDoc(h1: true), name: "mouse-foldall-h1.md")
            await ctx.settle(600)
            let k = RealUse.foldHeader(15, h1: true)
            ctx.model.jump(toLine: k + 3); await ctx.settle(300)
            await ctx.clickExpect(ctx.lineStart(k + 3) + 9, "click a nested line under the top heading")
            ctx.model.send(.foldAll); await ctx.settle(200)
            ctx.expect(!ctx.hidden(ctx.caret), "fold", "fold all under a top heading left the caret hidden at \(ctx.place(ctx.caret))")
            ctx.expectCaret(ctx.lineEnd(1), "fold all under a top heading: caret moves to the end of line 1")
            ctx.checkCaretVisible("fold all under a top heading"); ctx.checkAllD("fold all under a top heading"); ctx.checkInk("fold all under a top heading")
            ctx.checkLineHighlight("fold all under a top heading"); ctx.snap("fold-all-h1")
            await ctx.type("!"); await ctx.settle(450)
            ctx.expect(ctx.text.substring(with: NSRange(location: 0, length: ctx.lineEnd(1))) == "# Top title!" && ctx.hidden(line: 3), "fold",
                       "typing after fold all under a top heading: line 1 is \"\(ctx.text.substring(with: NSRange(location: 0, length: ctx.lineEnd(1))))\", folded \(ctx.hidden(line: 3))")
            ctx.checkAllD("typed under a top heading")
            ctx.model.send(.unfoldAll); await ctx.settle(200)
            ctx.checkAllD("unfold all (top heading)"); ctx.checkInk("unfold all (top heading)")
            ctx.mouseSummary()
        },

        // 현재 줄 강조와 캐럿 칸: 클릭·방향키·스크롤로 나갔다 들어오기·커서 스타일(막대/블록/밑줄)·감긴 문단
        Scenario(name: "mouse-caret") { ctx in
            let wrap0 = ctx.model.wordWrap, style0 = ctx.model.cursorStyle
            if !wrap0 { ctx.model.wordWrap = true }
            await ctx.open(text: RealUse.selectionDoc(lines: 600), name: "mouse-caret.txt")
            ctx.model.jump(toLine: 300); await ctx.settle(300)
            ctx.at("click sets the band")
            ctx.ensureViewportRange("after go to line 300")
            let v = ctx.visible
            let frags = ctx.viewportFragments().filter { $0.minY >= v.minY && $0.maxY <= v.maxY }
            for f in frags.prefix(8) {
                await ctx.clickExpect(f.offset, "click line \(ctx.liveLine(f.offset))")
                await ctx.settle(0)
                ctx.checkBandOnScreen("after clicking line \(ctx.liveLine(f.offset))"); ctx.checkLineHighlight("after clicking line \(ctx.liveLine(f.offset))")
            }
            ctx.snap("band")
            ctx.at("arrow keys move the band")
            for _ in 0..<6 { await ctx.key(.down); await ctx.settle(0); ctx.checkBandOnScreen("after ↓"); ctx.checkLineHighlight("after ↓") }
            ctx.at("band on the second visual line of a wrapped paragraph")
            // 지금 화면에 있는 문단에서 고른다 — 처음에 잡아 둔 목록은 방향키·휠로 화면이 움직이면(편집기가 낮을수록 쉽게) 화면 밖일 수 있다
            @MainActor func onScreen() -> [RealUseContext.Frag] { let v = ctx.visible; return ctx.viewportFragments().filter { $0.minY >= v.minY && $0.maxY <= v.maxY } }
            if let f = onScreen().first(where: { ctx.visualLines(ofParagraphAt: $0.offset).count >= 2 }) {
                let vls = ctx.visualLines(ofParagraphAt: f.offset)
                await ctx.clickExpect(vls[1].range.location + 6, "click the second visual line")
                await ctx.settle(0); ctx.checkLineHighlight("caret on the second visual line"); ctx.snap("band-wrapped")
                // 같은 문단 안에서 시각 줄만 바뀔 때 (줄 번호는 그대로) 거터의 띠도 따라오는가
                await ctx.key(.up); await ctx.settle(0); ctx.checkBandOnScreen("↑ within the paragraph"); ctx.checkLineHighlight("↑ to the first visual line of the same paragraph")
                await ctx.key(.down, count: 2); await ctx.settle(0); ctx.checkBandOnScreen("↓↓ within the paragraph"); ctx.checkLineHighlight("↓↓ within the same paragraph")
                await ctx.key(.right, [.shift], count: 3); await ctx.settle(0); ctx.checkBandOnScreen("⇧→ selects"); ctx.checkLineHighlight("⇧→ selects on the caret row")
                await ctx.key(.left); await ctx.settle(0); ctx.checkBandOnScreen("← collapses"); ctx.checkLineHighlight("← collapses the selection")
            } else { ctx.issue("other", "no wrapped paragraph on screen for the band test") }
            ctx.at("scroll the caret out and back")
            let y0 = ctx.visible.minY
            await ctx.scrollBy(2400); await ctx.settle(50)
            ctx.checkBandOnScreen("caret scrolled out of view"); ctx.checkLineHighlight("caret scrolled out of view"); ctx.snap("caret-out")
            await ctx.scrollBy(-2400); await ctx.settle(50)
            ctx.checkScrolled(from: y0, expected: 0, tolerance: 2, "scroll out and back")
            ctx.checkBandOnScreen("caret scrolled back into view"); ctx.checkLineHighlight("caret scrolled back into view")
            // 잘게 스크롤하는 동안에도 띠는 캐럿 줄에만
            for i in 1...12 { await ctx.scrollBy(i % 2 == 0 ? 61 : -37); await ctx.settle(0); ctx.checkBandOnScreen("small scroll \(i)") }
            ctx.at("cursor styles")
            for style in [CursorStyle.block, .underline, .bar] {
                ctx.model.cursorStyle = style; await ctx.settle(150)
                ctx.expect(ctx.tv.cursorStyle == style, "caret", "cursor style \(style.rawValue) did not reach the text view (\(ctx.tv.cursorStyle.rawValue))")
                // 글자 칸: 영문 한 칸, 한글 두 칸, 탭은 탭 폭, 줄 끝은 한 칸
                let cw = ctx.tv.charWidth
                let ns = ctx.text
                if let f = onScreen().first(where: { ns.substring(with: NSRange(location: $0.offset, length: $0.length)).contains("한글") }) {
                    let ko = ns.range(of: "한글", options: [], range: NSRange(location: f.offset, length: f.length)).location
                    await ctx.clickExpect(ko, "click a Hangul character (\(style.rawValue))")
                    if let cell = ctx.tv.caretCell(at: ko), let r = ctx.tv.caretRect(at: ko) {
                        // 한글 칸은 영문 한 칸보다 넓다 (글꼴 보정이 켜져 있으면 정확히 두 칸 — 글꼴 설정에 따라 다르므로 범위로 본다)
                        ctx.expect(abs(cell.minX - r.minX) < 0.5 && cell.width > cw * 1.4 && cell.width < cw * 2.6 && abs(cell.height - r.height) < 0.5, "caret",
                                   "\(style.rawValue) caret cell on a Hangul character: \(cell) (char width \(cw), caret rect \(r))")
                    }
                    let end = f.offset + f.length - 1
                    if let cell = ctx.tv.caretCell(at: end) { ctx.expect(abs(cell.width - cw) < 0.5, "caret", "\(style.rawValue) caret cell at the line end is \(cell.width) wide (expected \(cw))") }
                } else { ctx.issue("other", "no paragraph with Hangul on screen for the caret cell test (\(style.rawValue))") }
                await ctx.settle(0); ctx.checkLineHighlight("cursor style \(style.rawValue)"); ctx.snap("style-\(style.rawValue)")
            }
            ctx.model.cursorStyle = style0
            if !wrap0 { ctx.model.wordWrap = false }
            await ctx.settle(100)
            ctx.mouseSummary()
        },

        // 편집 직후의 캐럿 사각형: 여러 문단이 한꺼번에 바뀌는 편집(여러 줄 붙여넣기·되돌리기·줄 도구·멀티 캐럿) 직후 TextKit 2 는 아직 배치하지 않은
        // 문단들 아래의 조각 위치를 틀리게 답할 수 있다 — 편집기는 선택이 바뀌는 그 순간의 캐럿 사각형으로 현재 줄 띠를 다시 그릴 자리를 정한다
        Scenario(name: "mouse-band-edits") { ctx in
            let wrap0 = ctx.model.wordWrap
            if !wrap0 { ctx.model.wordWrap = true }
            await ctx.open(text: RealUse.selectionDoc(lines: 400), name: "mouse-band.txt")
            ctx.model.jump(toLine: 200); await ctx.settle(300)
            ctx.ensureViewportRange("after go to line 200")
            if let t = ctx.anchor() { await ctx.clickExpect(t.offset + 2, "click a middle line") }
            func same(_ a: NSRect?, _ b: NSRect?) -> Bool {
                guard let a, let b else { return a == nil && b == nil }
                return abs(a.minY - b.minY) < 1 && abs(a.height - b.height) < 1
            }
            @MainActor func d(_ r: NSRect?) -> String { r.map { String(format: "y %.0f h %.0f", $0.minY - ctx.visible.minY, $0.height) } ?? "nil" }
            @MainActor func probe(_ what: String, _ edit: () -> Void) async {
                ctx.at(what)
                edit()
                let now = ctx.tv.caretRect(at: ctx.caret)          // 편집 직후, 같은 턴 — 선택이 바뀌는 순간 편집기가 보는 값
                await ctx.settle(60)
                let settled = ctx.tv.caretRect(at: ctx.caret)
                if ctx.tv.selectedRange().length == 0, !same(now, settled) {
                    ctx.note("caret rectangle right after the edit was \(d(now)), settled at \(d(settled)) (transient TextKit 2 frame)")
                }
                ctx.checkBandOnScreen(what); ctx.checkLineHighlight(what); ctx.checkCaretVisible(what)
            }
            let none = NSRange(location: NSNotFound, length: 0)
            ctx.checkBandOnScreen("before the edits")
            await probe("type a character") { ctx.tv.insertText("x", replacementRange: none) }
            await probe("Return") { ctx.tv.doCommand(by: #selector(NSResponder.insertNewline(_:))) }
            await probe("Backspace joins") { ctx.tv.doCommand(by: #selector(NSResponder.deleteBackward(_:))) }
            await probe("insert five lines at once") { ctx.tv.insertText("p1\np2 한글 줄\np3\np4\np5", replacementRange: ctx.tv.selectedRange()) }
            ctx.snap("pasted")
            await probe("undo the five lines") { ctx.model.send(.undo) }
            await probe("redo the five lines") { ctx.model.send(.redo) }
            await probe("↑ after redo") { ctx.tv.doCommand(by: #selector(NSResponder.moveUp(_:))) }
            await probe("select three lines and type") {
                for _ in 0..<3 { ctx.tv.doCommand(by: #selector(NSResponder.moveDownAndModifySelection(_:))) }
                ctx.tv.insertText("y", replacementRange: none)
            }
            await probe("undo the replacement") { ctx.model.send(.undo) }
            await probe("→ collapses") { ctx.tv.doCommand(by: #selector(NSResponder.moveRight(_:))) }
            await probe("duplicate line") { ctx.model.textTool(.duplicateLine) }
            await probe("move line down") { ctx.model.textTool(.moveLineDown) }
            await probe("move line up") { ctx.model.textTool(.moveLineUp) }
            await probe("delete line") { ctx.model.textTool(.deleteLine) }
            await probe("undo delete line") { ctx.model.send(.undo) }
            // 장부가 어긋난 채로 캐럿만 옮긴다: 옛 띠가 화면에 남는가
            await probe("↓ after undo delete line") { ctx.tv.doCommand(by: #selector(NSResponder.moveDown(_:))) }
            await probe("↑↑ after undo delete line") { ctx.tv.doCommand(by: #selector(NSResponder.moveUp(_:))); ctx.tv.doCommand(by: #selector(NSResponder.moveUp(_:))) }
            await probe("delete line again") { ctx.model.textTool(.deleteLine) }
            await probe("undo, then click elsewhere") { ctx.model.send(.undo) }
            if let t = ctx.anchor() { await ctx.clickExpect(t.offset + 1, "click after undo"); await ctx.settle(30); ctx.checkBandOnScreen("click after undo"); ctx.checkLineHighlight("click after undo") }
            await probe("insert timestamp") { ctx.model.send(.insertTimestamp) }
            ctx.snap("timestamp")
            await probe("undo timestamp") { ctx.model.send(.undo) }
            await probe("↓ after undo") { ctx.tv.doCommand(by: #selector(NSResponder.moveDown(_:))) }
            // 멀티 캐럿 입력 뒤 Esc: 머리 캐럿 하나로 돌아왔을 때의 띠
            ctx.at("multi-caret typing then Esc")
            ctx.ensureViewportRange("multi-caret")
            let v = ctx.visible
            let lines = ctx.viewportFragments().filter { $0.minY >= v.minY && $0.maxY <= v.maxY && $0.length > 12 }
            if lines.count >= 6 {
                await ctx.clickExpect(lines[1].offset + 3, "first caret")
                await ctx.mclick(offset: lines[3].offset + 5, mods: [.command]); await ctx.mclick(offset: lines[5].offset + 2, mods: [.command])
                await probe("type at three carets") { ctx.tv.insertText("#", replacementRange: none) }
                await probe("Esc collapses to the head caret") { ctx.tv.doCommand(by: #selector(NSResponder.cancelOperation(_:))) }
                await probe("← after Esc") { ctx.tv.doCommand(by: #selector(NSResponder.moveLeft(_:))) }
                await probe("↑ after Esc") { ctx.tv.doCommand(by: #selector(NSResponder.moveUp(_:))) }
                await probe("undo the multi insert") { ctx.model.send(.undo) }
                await probe("↓ after the multi undo") { ctx.tv.doCommand(by: #selector(NSResponder.moveDown(_:))) }
            }
            await ctx.settle(400)   // 줄 인덱스(250 ms 디바운스)가 따라온 뒤 — 편집 직후의 거터 번호는 mouse-gutter 가 본다
            ctx.checkAllD("after the edits")
            if !wrap0 { ctx.model.wordWrap = false; await ctx.settle(100) }
            ctx.mouseSummary()
        },

        // 비밀 블록 가림막: 가려진 줄을 누르면 그 블록이 드러나고 캐럿은 누른 글자에, 밖을 누르면 다시 가려진다. 가림막을 가로질러 끌어 선택 (클립보드는 건드리지 않는다)
        Scenario(name: "mouse-secret") { ctx in
            var text = "notes before the block\nline two 둘째 줄\n\n```secret\npassword: hunter2\ntoken = abcdef123456\n한글 비밀 줄 secret\n```\n\nnotes after the block\n"
            for i in 1...40 { text += "filler line \(i) with some words\n" }
            await ctx.open(text: text, name: "mouse-secret.md")
            await ctx.key(.up, [.command]); await ctx.settle(400)
            @MainActor func masked(_ line: Int) -> Bool { ctx.tv.isOffsetMasked?(ctx.lineStart(line)) ?? false }
            ctx.at("masked as opened")
            guard ctx.model.secrets.maskEnabled else { ctx.note("secret masking is off in this configuration — skipped"); return }
            ctx.expect(masked(5) && masked(6) && masked(7) && !masked(4) && !masked(8), "secret",
                       "mask state of lines 4…8: \((4...8).map { masked($0) })")
            ctx.checkAllD("masked"); ctx.checkInk("masked"); ctx.snap("masked")
            ctx.at("click a masked line")
            await ctx.clickExpect(ctx.lineStart(6) + 4, "click a masked line at col 4"); await ctx.settle(100)
            ctx.expect(!masked(5) && !masked(6) && !masked(7), "secret", "clicking a masked line did not reveal its block: \((5...7).map { masked($0) })")
            ctx.checkAllD("revealed"); ctx.checkInk("revealed"); ctx.checkBandOnScreen("revealed"); ctx.checkLineHighlight("revealed"); ctx.snap("revealed")
            await ctx.clickGrid("block revealed", paragraphs: 12)
            ctx.at("click outside masks it again")
            await ctx.clickExpect(ctx.lineStart(1) + 3, "click the first line"); await ctx.settle(100)
            ctx.expect(masked(5) && masked(6) && masked(7), "secret", "leaving the block did not mask it again: \((5...7).map { masked($0) })")
            ctx.checkAllD("masked again"); ctx.checkBandOnScreen("masked again"); ctx.checkLineHighlight("masked again")
            ctx.at("drag across the masked block")
            let a = ctx.lineStart(2) + 2, b = ctx.lineStart(10) + 5
            if let pa = ctx.point(forOffset: a), let pb = ctx.point(forOffset: b) {
                await ctx.mdrag(from: pa, to: pb)
                ctx.expectSelection(NSRange(location: a, length: b - a), "drag from line 2 over the masked block to line 10")
                ctx.expect(masked(5) && masked(7), "secret", "a drag selection across the block revealed it: \((5...7).map { masked($0) })")
                ctx.checkLineHighlight("selection across the mask"); ctx.snap("drag-across")
            }
            ctx.at("clicks with the block masked")
            await ctx.clickExpect(ctx.lineStart(12) + 2, "click below the block"); await ctx.settle(100)
            ctx.expect(masked(5), "secret", "the block is not masked after clicking below it")
            await ctx.clickGrid("around a masked block (masked lines reveal when clicked)", paragraphs: 20)
            ctx.checkAllD("after clicks around the mask")
            ctx.mouseSummary()
        },

        // 가장자리: 왼쪽 여백·오른쪽 끝·맨 위 여백·마지막 줄 아래 빈 곳 클릭, 스크롤바 마커 띠와 본문이 겹치지 않는가
        Scenario(name: "mouse-edges") { ctx in
            let wrap0 = ctx.model.wordWrap
            if !wrap0 { ctx.model.wordWrap = true }
            await ctx.open(text: RealUse.selectionDoc(), name: "mouse-edges.txt")
            await ctx.key(.up, [.command]); await ctx.settle(150)
            ctx.at("left margin")
            if let r = ctx.tv.caretRect(at: ctx.lineStart(5)) {
                await ctx.mclick(atViewPoint: NSPoint(x: 2, y: r.midY))
                ctx.expectCaret(ctx.lineStart(5), "click in the left margin of line 5")
            }
            ctx.at("right edge of a short line")
            if let r = ctx.tv.caretRect(at: ctx.lineStart(7)) {
                await ctx.mclick(atViewPoint: NSPoint(x: ctx.visible.maxX - 3, y: r.midY))
                ctx.expectCaret(ctx.lineEnd(7), "click at the right edge of line 7")
            }
            ctx.at("right edge of an empty line")
            if let r = ctx.tv.caretRect(at: ctx.lineStart(9)) {
                await ctx.mclick(atViewPoint: NSPoint(x: ctx.visible.maxX - 3, y: r.midY))
                ctx.expectCaret(ctx.lineStart(9), "click at the right edge of the empty line 9")
            }
            ctx.at("right edge of a wrapped line")
            do {
                let vls = ctx.visualLines(ofParagraphAt: ctx.lineStart(4))
                if vls.count >= 2 {
                    await ctx.mclick(atViewPoint: NSPoint(x: ctx.visible.maxX - 3, y: vls[0].rect.midY))
                    let got = ctx.caret
                    let end = NSMaxRange(vls[0].range)
                    ctx.expect(ctx.tv.selectedRange().length == 0 && (got == end || got == end - 1), "click",
                               "click at the right edge of the first visual line of line 4: caret \(ctx.place(got)), the visual line ends at \(end)")
                    if let r = ctx.tv.caretRect(at: got) {
                        ctx.note("caret after the right-edge click is drawn at y \(Int(r.minY)) (first visual line y \(Int(vls[0].rect.minY)), second \(Int(vls[1].rect.minY)))")
                    }
                } else { ctx.note("line 4 did not wrap") }
            }
            ctx.at("top inset")
            await ctx.mclick(atViewPoint: NSPoint(x: 60, y: 3))
            ctx.expect(ctx.liveLine(ctx.caret) == 1 && ctx.tv.selectedRange().length == 0, "click", "click in the top inset: caret \(ctx.place(ctx.caret))")
            ctx.checkAllD("edge clicks at the top"); ctx.snap("top")
            ctx.at("marker band does not cover text")
            ctx.ensureViewportRange("marker band")
            if let c = ctx.coord.container, let band = c.markerView {
                var worst: CGFloat = 0
                for f in ctx.viewportFragments() {
                    for vl in ctx.visualLines(ofParagraphAt: f.offset) {
                        let right = c.convert(NSPoint(x: vl.rect.maxX, y: vl.rect.midY), from: ctx.tv).x
                        worst = max(worst, right)
                    }
                }
                ctx.expect(worst <= band.frame.minX + 0.5, "markers", "text reaches x \(worst) but the scrollbar marker band starts at \(band.frame.minX) (band \(band.frame))")
                ctx.note("text right edge \(worst), marker band from \(band.frame.minX), container width \(c.bounds.width)")
            }
            ctx.at("below the last line")
            await ctx.key(.down, [.command]); await ctx.settle(150)
            await ctx.clickExpect(ctx.lineStart(175) + 2, "click a line near the end")
            ctx.ensureViewportRange("below the last line")
            if let last = ctx.viewportFragments().last {
                let y = min(ctx.visible.maxY - 2, last.maxY + 30)
                if y > last.maxY + 1 {
                    await ctx.mclick(atViewPoint: NSPoint(x: 200, y: y))
                    ctx.expectCaret(ctx.length, "click \(Int(y - last.maxY)) pt below the last line")
                } else { ctx.note("no empty space below the last line (last fragment ends \(Int(last.maxY)), visible to \(Int(ctx.visible.maxY)))") }
            }
            ctx.checkAllD("edge clicks at the end"); ctx.checkCaretVisible("click below the last line")
            ctx.checkLastLineNumber("caret on the last empty line"); ctx.checkLineHighlight("caret on the last empty line"); ctx.snap("end")
            ctx.at("empty document")
            await ctx.open(text: "", name: "mouse-empty.txt")
            ctx.checkAllD("empty document"); ctx.checkLastLineNumber("empty document"); ctx.checkLineHighlight("empty document"); ctx.snap("empty")
            await ctx.type("가a"); await ctx.settle(400)
            ctx.checkAllD("typed into an empty document"); ctx.checkLineHighlight("typed into an empty document")
            await ctx.key(.returnKey); await ctx.settle(400)
            ctx.checkAllD("Return at the end of a one-line document"); ctx.checkLastLineNumber("Return at the end of a one-line document")
            ctx.checkLineHighlight("Return at the end of a one-line document"); ctx.snap("one-line-return")
            await ctx.key(.returnKey, count: 2); await ctx.settle(400)
            ctx.checkAllD("three Returns"); ctx.checkLastLineNumber("three Returns"); ctx.checkLineHighlight("three Returns")
            await ctx.key(.up); await ctx.settle(50)
            ctx.checkLastLineNumber("↑ from the last empty line"); ctx.checkLineHighlight("↑ from the last empty line")
            ctx.at("short document: far below the text")
            await ctx.open(text: "one\ntwo 둘\nthree", name: "mouse-short.txt")
            await ctx.clickExpect(1, "click inside the first line")
            let below = NSPoint(x: 300, y: ctx.visible.maxY - 20)
            await ctx.mclick(atViewPoint: below)
            ctx.expectCaret(ctx.length, "click far below a three-line document (view y \(Int(below.y)), text view height \(Int(ctx.tv.frame.height)))")
            await ctx.mclick(atViewPoint: NSPoint(x: 2, y: ctx.visible.maxY - 20))
            ctx.note("click in the bottom-left corner of a three-line document → caret \(ctx.place(ctx.caret)) (document length \(ctx.length))")
            ctx.expect(ctx.liveLine(ctx.caret) == 3 && ctx.tv.selectedRange().length == 0, "click", "click in the bottom-left corner of a three-line document: caret \(ctx.place(ctx.caret))")
            ctx.checkAllD("short document"); ctx.checkLineHighlight("short document"); ctx.snap("short")
            if !wrap0 { ctx.model.wordWrap = false; await ctx.settle(100) }
            ctx.mouseSummary()
        },
    ]
}
