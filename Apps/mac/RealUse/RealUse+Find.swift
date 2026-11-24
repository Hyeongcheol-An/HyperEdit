import AppKit
import HyperCore

// 실사용 시뮬레이션 — 찾기: 빠른 찾기(입력 중 선택·강조), Enter 다음, 결과가 있는 채 스크롤·타이핑, Esc

// MARK: - 도우미

extension RealUseContext {
    /// 검색이 끝날 때까지 (결과가 그대로라 발행하지 않은 조용한 재검색도 완료 카운터는 오른다). 반환: 끝났는가
    @discardableResult
    func awaitSearch(after gen: Int, timeoutMs: Int = 6000) async -> Bool {
        var waited = 0
        while model.searchCompletionCount == gen, waited < timeoutMs { await settle(50); waited += 50 }
        let done = model.searchCompletionCount != gen
        await settle(150)   // 발행 → SwiftUI 갱신(updateNSView 가 강조 범위를 넘긴다) → 다음 턴의 가운데 맞춤
        return done
    }

    /// 찾기 입력창에 글자를 친 것처럼: 입력창의 값(FindFields)을 바꾸고 빠른 찾기에 알린다 — 뷰의 onChange 가 하는 일 그대로
    func typeQuery(_ q: String) {
        model.findFields.query = q
        model.quickFindTextChanged()
    }

    /// 검색어를 한 글자씩 친다 (`gapMs` 가 150 ms 디바운스보다 길면 글자마다 검색이 돈다). 마지막 검색이 끝날 때까지 기다린다
    @discardableResult
    func typeQuerySlowly(_ q: String, gapMs: UInt64) async -> Bool {
        var gen = model.searchCompletionCount
        var typed = ""
        for ch in q {
            gen = model.searchCompletionCount
            typed.append(ch)
            typeQuery(typed)
            await settle(gapMs)
        }
        if model.hitsQuery == q { await settle(150); return true }
        return await awaitSearch(after: gen)
    }

    /// 결과 목록(NSTableView)
    var resultsTable: SearchResultsCoordinatorBase? { SearchResultsCoordinatorBase.document }

    /// 선택이 통째로 화면 안에 있는가 (찾기로 옮겨 간 매치는 가장자리에 잘리지 않고 보여야 한다)
    func checkSelectionOnScreen(_ why: String) {
        let sel = tv.selectedRange()
        guard let r = tv.caretRect(at: sel.location) else { return }
        let v = visible
        if r.minY < v.minY - 1 || r.maxY > v.maxY + 1 {
            issue("caret-hidden", "\(why): the selected match at offset \(sel.location) is at y \(Int(r.minY))…\(Int(r.maxY)), outside the visible \(Int(v.minY))…\(Int(v.maxY))")
        } else {
            note(String(format: "%@: match at %.0f%% of the viewport height", why, (r.minY - v.minY) / max(1, v.height) * 100))
        }
    }

    /// 지금 선택이 `index` 번째 결과와 같고, 화면에 보이며, 결과 목록의 현재 행도 그 행인가
    func expectSelectedHit(_ index: Int?, _ why: String) {
        let hits = model.searchHits
        let sel = tv.selectedRange()
        guard let i = index, i >= 0, i < hits.count else { issue("find", "\(why): expected a selected match, but there are \(hits.count) hits (index \(index.map(String.init) ?? "nil"))"); return }
        if sel != hits[i].range {
            let at = hits.firstIndex(where: { $0.range == sel })
            issue("find", "\(why): expected hit #\(i) \(hits[i].range) (line \(hits[i].line)) to be selected, but the selection is \(sel)\(at.map { " = hit #\($0)" } ?? " (not a hit)")")
            return
        }
        checkSelectionOnScreen(why)
        if model.showBottomPanel, model.bottomTab == .findResults, let t = resultsTable {
            if t.currentIndex != i { issue("find", "\(why): the results list marks row \(t.currentIndex.map(String.init) ?? "none") as current, expected row \(i)") }
            else if let table = t.table, !table.rows(in: table.visibleRect).contains(i) {
                issue("find", "\(why): the current row \(i) is not visible in the results list (visible rows \(table.rows(in: table.visibleRect)))")
            }
        }
    }

    /// 편집기가 든 강조 범위가 결과와 같은가 (검색이 끝난 직후)
    func checkHighlightsEqualHits(_ why: String) {
        let a = tv.matchHighlights, b = model.searchHits.map(\.range)
        if a != b {
            let firstDiff = zip(a, b).enumerated().first(where: { $0.element.0 != $0.element.1 })
            issue("highlight", "\(why): the editor holds \(a.count) highlight ranges but the results list has \(b.count)" + (firstDiff.map { " (first difference at #\($0.offset): \($0.element.0) vs \($0.element.1))" } ?? ""))
        }
    }

    /// 강조 범위마다 그 자리의 글자가 검색어인가 — 편집 뒤 범위가 글자를 따라갔는지 (재검색 전에도 성립해야 한다)
    func checkHighlightsSpell(_ query: String, _ why: String) {
        let ns = text
        let q = query.lowercased()
        var bad = 0, first: NSRange?
        for r in tv.matchHighlights {
            if NSMaxRange(r) > ns.length || ns.substring(with: r).lowercased() != q { bad += 1; if first == nil { first = r } }
        }
        if bad > 0, let f = first {
            let got = NSMaxRange(f) <= ns.length ? ns.substring(with: f) : "(beyond the end)"
            issue("highlight", "\(why): \(bad) of \(tv.matchHighlights.count) highlight ranges no longer cover the text '\(query)' (first \(f) covers '\(got)')")
        }
    }

    /// 보이는 매치의 강조 사각형 (텍스트 뷰 좌표) — 뷰가 칠할 때와 같은 레이아웃 질의
    func visibleMatchRects() -> [(range: NSRange, rects: [NSRect])] {
        guard let lm = tv.textLayoutManager, let cs = tv.textContentStorage, let vr = lm.textViewportLayoutController.viewportRange else { return [] }
        let start = cs.offset(from: cs.documentRange.location, to: vr.location), end = cs.offset(from: cs.documentRange.location, to: vr.endLocation)
        let origin = tv.textContainerOrigin
        var out: [(NSRange, [NSRect])] = []
        for r in tv.matchHighlights where NSMaxRange(r) > start && r.location < end && r.length > 0 && NSMaxRange(r) <= length {
            guard let a = cs.location(cs.documentRange.location, offsetBy: r.location), let b = cs.location(a, offsetBy: r.length), let tr = NSTextRange(location: a, end: b) else { continue }
            var rects: [NSRect] = []
            lm.enumerateTextSegments(in: tr, type: .highlight, options: [.rangeNotRequired]) { _, f, _, _ in
                rects.append(f.offsetBy(dx: origin.x, dy: origin.y)); return true
            }
            out.append((r, rects))
        }
        return out
    }

    /// 그려진 화면에서 강조를 확인한다: (1) 보이는 매치마다 그 글자 자리에 강조색이 칠해졌는가 (2) 매치가 없는 자리에 강조색이 남아 있지 않은가(잔상).
    /// 텍스트 뷰를 비트맵으로 그려 픽셀을 읽는다. 선택과 겹친 매치(선택색으로 보인다)는 뺀다. 반환: 확인한 매치 수
    @discardableResult
    func checkHighlightPaint(_ why: String) -> Int {
        let v = visible
        guard v.height > 10, let rep = tv.bitmapImageRepForCachingDisplay(in: v) else { return 0 }
        tv.cacheDisplay(in: v, to: rep)
        guard let data = rep.bitmapData, rep.bitsPerSample == 8, rep.samplesPerPixel >= 3, !rep.isPlanar else { return 0 }
        let w = rep.pixelsWide, h = rep.pixelsHigh, bpr = rep.bytesPerRow, spp = rep.samplesPerPixel
        let skip = rep.bitmapFormat.contains(.alphaFirst) ? 1 : 0
        let sx = CGFloat(w) / v.width, sy = CGFloat(h) / v.height
        func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int)? {
            guard x >= 0, y >= 0, x < w, y < h else { return nil }
            let p = data + y * bpr + x * spp + skip
            return (Int(p[0]), Int(p[1]), Int(p[2]))
        }
        func pixel(_ p: NSPoint) -> (Int, Int, Int)? { rgb(Int((p.x - v.minX) * sx), Int((p.y - v.minY) * sy)) }
        func dist(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Int { abs(a.0 - b.0) + abs(a.1 - b.1) + abs(a.2 - b.2) }

        let selected = tv.selectedRanges.map(\.rangeValue)
        let all = visibleMatchRects()
        var checked = 0, unpainted = 0, firstBad: (NSRange, NSRect)?
        var tints: [(Int, Int, Int)] = []
        var pixelRects: [CGRect] = []
        for (i, m) in all.enumerated() {
            for r in m.rects { pixelRects.append(CGRect(x: (r.minX - v.minX) * sx, y: (r.minY - v.minY) * sy, width: r.width * sx, height: r.height * sy).insetBy(dx: -3, dy: -3)) }
            // 선택과 닿은 매치, 바로 앞 매치와 붙은 매치는 '바깥' 기준색을 잡을 수 없어 건너뛴다
            if selected.contains(where: { NSIntersectionRange($0, m.range).length > 0 || NSMaxRange($0) == m.range.location }) { continue }
            if i > 0, NSMaxRange(all[i - 1].range) == m.range.location { continue }
            guard let r = m.rects.first, r.width >= 4, r.minY >= v.minY + 1, r.maxY <= v.maxY - 1, r.minX - 3 >= v.minX else { continue }
            // 줄 상자의 맨 위 줄(글자 잉크가 닿지 않는 높이)에서 안쪽 세 점과 왼쪽 바깥 한 점을 비교한다
            let y = r.minY + 1.5
            guard let outside = pixel(NSPoint(x: r.minX - 2.5, y: y)) else { continue }
            let inside = [r.minX + 1.5, r.midX, r.maxX - 1.5].compactMap { pixel(NSPoint(x: $0, y: y)) }
            checked += 1
            let painted = inside.filter { dist($0, outside) > 14 }
            if painted.count < 2 { unpainted += 1; if firstBad == nil { firstBad = (m.range, r) } } else { tints.append(painted[0]) }
        }
        if unpainted > 0, let (range, r) = firstBad {
            issue("highlight", "\(why): \(unpainted) of \(checked) visible matches have no highlight painted over their text (first \(range) at x \(Int(r.minX)) y \(Int(r.minY - v.minY)))")
        }
        // 잔상: 가장 흔한 강조색과 같은 픽셀이 어떤 매치 사각형에도 속하지 않는 곳에 뭉쳐 있는가
        if let tint = Dictionary(grouping: tints, by: { "\($0.0),\($0.1),\($0.2)" }).max(by: { $0.value.count < $1.value.count })?.value.first {
            var stray = 0, firstStray: (Int, Int)?
            var y = 1
            while y < h {
                var x = 1
                while x < w {
                    if let c = rgb(x, y), dist(c, tint) <= 3 {
                        let p = CGPoint(x: x, y: y)
                        if !pixelRects.contains(where: { $0.contains(p) }) { stray += 1; if firstStray == nil { firstStray = (x, y) } }
                    }
                    x += 2
                }
                y += 2
            }
            if stray > 40, let (x, y) = firstStray {
                issue("highlight", "\(why): \(stray) sampled pixels carry the match highlight colour outside every match (first at x \(Int(CGFloat(x) / sx)) y \(Int(CGFloat(y) / sy)))")
            }
        }
        return checked
    }

    /// 매치 하나가 강조돼 그려지는가 — 그 글자의 캐럿 사각형으로 자리를 구해 픽셀을 본다 (`checkHighlightPaint` 와 달리 매치를 직접 지정한다: 방금 떠난 매치,
    /// 캐럿 줄의 매치). 한 줄 안의 매치, 선택되지 않은 것만. 화면에 배치된 문단 안의 매치만 본다 — 화면 밖 글자의 사각형을 물으면 TextKit 2 가 그 문단을 새로
    /// 배치하며 뷰포트 범위를 끊어 놓는다(이 검사가 스스로 화면을 깨뜨린다: 처음에는 ±4000 자 안의 매치를 전부 물었다가 뒤따르는 검사들이 줄줄이 실패했다)
    @discardableResult
    func checkMatchPainted(_ range: NSRange, _ why: String) -> Bool {
        let v = visible
        let onScreen = viewportFragments().filter { $0.minY >= v.minY && $0.maxY <= v.maxY }
        guard let first = onScreen.first, let last = onScreen.last, range.location >= first.offset, NSMaxRange(range) <= last.offset + last.length else { return true }
        guard range.length > 0, NSMaxRange(range) <= length, NSIntersectionRange(tv.selectedRange(), range).length == 0,
              let a = tv.caretRect(at: range.location), let b = tv.caretRect(at: NSMaxRange(range)), abs(a.minY - b.minY) < 0.5, b.minX - a.minX >= 4 else { return true }
        guard a.minY >= v.minY + 1, a.maxY <= v.maxY - 1, a.minX - 3 >= v.minX, let rep = tv.bitmapImageRepForCachingDisplay(in: v) else { return true }
        tv.cacheDisplay(in: v, to: rep)
        func pixel(_ x: CGFloat, _ y: CGFloat) -> NSColor? {
            let px = Int((x - v.minX) * CGFloat(rep.pixelsWide) / v.width), py = Int((y - v.minY) * CGFloat(rep.pixelsHigh) / v.height)
            return px >= 0 && py >= 0 && px < rep.pixelsWide && py < rep.pixelsHigh ? rep.colorAt(x: px, y: py) : nil
        }
        func differs(_ p: NSColor?, _ q: NSColor?) -> Bool {
            guard let p, let q else { return false }
            return abs(p.redComponent - q.redComponent) + abs(p.greenComponent - q.greenComponent) + abs(p.blueComponent - q.blueComponent) > 0.055
        }
        let y = a.minY + 1.5
        let outside = pixel(a.minX - 2.5, y)
        let painted = [a.minX + 1.5, (a.minX + b.minX) / 2, b.minX - 1.5].filter { differs(pixel($0, y), outside) }.count
        if painted < 2 {
            issue("highlight", "\(why): the match \(range) is on screen (x \(Int(a.minX)) y \(Int(a.minY - v.minY))) but no highlight is painted over it (the editor holds \(tv.matchHighlights.count) ranges, \(visibleMatchRects().count) in the laid-out viewport)")
            return false
        }
        return true
    }

    /// 화면에 **실제로 남아 있는** 그림과 지금 다시 그린 그림을 매치 자리마다 비교한다 (잔상 탐지). `snap`·`checkHighlightPaint` 는 뷰를 새로 그리므로
    /// "강조 범위·선택이 바뀌었는데 그 자리를 다시 그리라고 하지 않아 옛 그림이 남은" 경우를 못 본다. 여기서는 클립 뷰의 레이어가 들고 있는 내용을
    /// 그대로 렌더해(다시 그리지 않는다) 매치마다 강조가 칠해져 있는지 읽고, 새로 그린 결과와 다르면 기록한다. 반환: 비교한 매치 수 (레이어를 못 읽으면 0)
    @discardableResult
    func checkHighlightsOnScreen(_ why: String) -> Int {
        window.displayIfNeeded()   // 다시 그리라고 한 곳은 반영된 뒤의 화면
        let clip = scroll.contentView
        let v = visible
        let scale = window.backingScaleFactor
        let w = Int(clip.bounds.width * scale), h = Int(clip.bounds.height * scale)
        guard let layer = clip.layer, w > 10, h > 10,
              let screen = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let g = NSGraphicsContext(bitmapImageRep: screen), let fresh = tv.bitmapImageRepForCachingDisplay(in: v) else { return 0 }
        let cg = g.cgContext
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: -layer.bounds.minX, y: -layer.bounds.minY)
        layer.render(in: cg)
        g.flushGraphics()
        tv.cacheDisplay(in: v, to: fresh)

        let selected = tv.selectedRanges.map(\.rangeValue)
        let all = visibleMatchRects()
        var list: [(range: NSRange, rect: NSRect)] = []
        for (i, m) in all.enumerated() {
            if selected.contains(where: { NSIntersectionRange($0, m.range).length > 0 || NSMaxRange($0) == m.range.location }) { continue }
            if i > 0, NSMaxRange(all[i - 1].range) == m.range.location { continue }
            guard let r = m.rects.first, r.width >= 4, r.minY >= v.minY + 1, r.maxY <= v.maxY - 1, r.minX - 3 >= v.minX else { continue }
            list.append((m.range, r))
        }
        let candidates = list

        /// 비트맵에서 매치마다 강조가 칠해졌는가 (줄 상자 맨 위 줄의 안쪽 세 점과 왼쪽 바깥 한 점을 비교 — checkHighlightPaint 와 같은 판정). flipped: 세로로 뒤집힌 비트맵
        func flags(_ rep: NSBitmapImageRep, flipped: Bool) -> [Bool]? {
            guard let data = rep.bitmapData, rep.bitsPerSample == 8, rep.samplesPerPixel >= 3, !rep.isPlanar else { return nil }
            let pw = rep.pixelsWide, ph = rep.pixelsHigh, bpr = rep.bytesPerRow, spp = rep.samplesPerPixel
            let skip = rep.bitmapFormat.contains(.alphaFirst) ? 1 : 0
            let sx = CGFloat(pw) / v.width, sy = CGFloat(ph) / v.height
            func pixel(_ p: NSPoint) -> (Int, Int, Int)? {
                let x = Int((p.x - v.minX) * sx)
                var y = Int((p.y - v.minY) * sy)
                if flipped { y = ph - 1 - y }
                guard x >= 0, y >= 0, x < pw, y < ph else { return nil }
                let q = data + y * bpr + x * spp + skip
                return (Int(q[0]), Int(q[1]), Int(q[2]))
            }
            var out: [Bool] = []
            for m in candidates {
                let y = m.rect.minY + 1.5
                guard let outside = pixel(NSPoint(x: m.rect.minX - 2.5, y: y)) else { out.append(false); continue }
                let inside = [m.rect.minX + 1.5, m.rect.midX, m.rect.maxX - 1.5].compactMap { pixel(NSPoint(x: $0, y: y)) }
                out.append(inside.filter { abs($0.0 - outside.0) + abs($0.1 - outside.1) + abs($0.2 - outside.2) > 14 }.count >= 2)
            }
            return out
        }
        guard !candidates.isEmpty, let want = flags(fresh, flipped: false), let a = flags(screen, flipped: false), let b = flags(screen, flipped: true) else { return 0 }
        func agree(_ x: [Bool]) -> Int { zip(x, want).filter { $0 == $1 }.count }
        let got = agree(a) >= agree(b) ? a : b
        // 레이어 내용을 읽지 못했으면(전부 빈 그림) 판단하지 않는다
        guard got.contains(true) || !want.contains(true) else { note("\(why): the layer contents could not be read — on-screen comparison skipped (\(candidates.count) matches)"); return 0 }
        let stale = zip(candidates, zip(got, want)).filter { $0.1.0 != $0.1.1 }
        if let first = stale.first {
            issue("highlight", "\(why): \(stale.count) of \(candidates.count) visible matches look different on screen than a fresh redraw (stale pixels) — first \(first.0.range) at x \(Int(first.0.rect.minX)) y \(Int(first.0.rect.minY - v.minY)): on screen \(first.1.0 ? "highlighted" : "not highlighted"), should be \(first.1.1 ? "highlighted" : "not highlighted")")
        }
        return candidates.count
    }
}

extension RealUse {
    @MainActor static let findScenarios: [Scenario] = [
        // 빠른 찾기 기본: ⌘F → 글자를 치는 동안 첫 매치 선택·강조 → Enter 다음 / ⇧Enter 이전 → 끝에서 처음으로 → Esc
        Scenario(name: "find-quick") { ctx in
            let saved = ViewDefaults(ctx)
            let m = ctx.model
            await ctx.withRelaxedStalls { await ctx.open(.notes) }
            await ctx.look(atLine: middleLine(ctx), wheel: 400, click: true)
            let startCaret = ctx.caret
            ctx.at("⌘F")
            var p = ctx.place()
            m.findInEditor(); await ctx.settle(300)
            ctx.checkSamePlace(p, "⌘F with the bottom panel already open", strictPt: 2)
            ctx.note("find field focused: first responder is \(type(of: ctx.window.firstResponder as Any))")

            // 천천히 한 글자씩 — 글자마다 검색이 돌고 첫 매치로 간다 (앵커는 ⌘F 를 누른 때의 캐럿)
            var typed = ""
            for ch in "budget" {
                typed.append(ch)
                ctx.at("type '\(typed)'")
                let gen = m.searchCompletionCount
                ctx.typeQuery(typed)
                let done = await ctx.awaitSearch(after: gen)
                if !done { ctx.issue("find", "typed '\(typed)' in the find field but no search finished within 6 s"); continue }
                let hits = m.searchHits
                if hits.isEmpty { ctx.issue("find", "'\(typed)' found nothing in the notes corpus"); continue }
                let want = hits.firstIndex(where: { $0.range.location >= startCaret }) ?? 0
                ctx.expectSelectedHit(want, "quick find '\(typed)' (\(hits.count) hits)")
                ctx.checkHighlightsEqualHits("quick find '\(typed)'"); ctx.checkHighlightsSpell(typed, "quick find '\(typed)'")
                ctx.checkAll("quick find '\(typed)'"); ctx.checkInk("quick find '\(typed)'")
                let n = ctx.checkHighlightPaint("quick find '\(typed)'")
                ctx.note("'\(typed)': \(hits.count) hits, selected #\(want), \(n) visible matches checked on screen")
                if typed == "b" || typed == "budget" { ctx.snap("typed-\(typed)") }
            }
            let total = m.searchHits.count
            guard total > 3, var cur = m.searchHits.firstIndex(where: { $0.range == ctx.tv.selectedRange() }) else { ctx.issue("find", "no selected match after typing 'budget' (\(total) hits)"); await saved.restore(ctx); return }

            ctx.at("Enter ×6")
            for i in 1...6 {
                let left = m.searchHits[cur].range   // 방금까지 선택돼 있던 매치 — 떠나면 강조가 돌아와야 한다
                m.submitFind(); await ctx.settle(150)
                cur = (cur + 1) % total
                ctx.expectSelectedHit(cur, "Enter #\(i)")
                ctx.checkMatchPainted(left, "Enter #\(i): the match just left")
                let onScreen = ctx.checkHighlightsOnScreen("Enter #\(i)")   // 방금 떠난 매치에 강조가 돌아왔는가 (화면에 남은 그림 기준)
                if i == 1 { ctx.note("on-screen comparison covers \(onScreen) matches") }
                ctx.checkAll("Enter #\(i)"); ctx.checkInk("Enter #\(i)"); ctx.checkHighlightPaint("Enter #\(i)")
            }
            ctx.snap("after-enters")
            ctx.at("⇧Enter ×3")
            for i in 1...3 {
                m.findPrevious(focusEditor: false); await ctx.settle(150)
                cur = (cur - 1 + total) % total
                ctx.expectSelectedHit(cur, "⇧Enter #\(i)")
                ctx.checkHighlightsOnScreen("⇧Enter #\(i)")
                ctx.checkAll("⇧Enter #\(i)"); ctx.checkHighlightPaint("⇧Enter #\(i)")
            }
            // 빠르게 연타: 걸음 사이에 기다리지 않는다
            ctx.at("Enter ×25 fast")
            for _ in 1...25 { m.submitFind(); await ctx.turn(); cur = (cur + 1) % total }
            await ctx.settle(200)
            ctx.expectSelectedHit(cur, "25 fast Enters"); ctx.checkHighlightsOnScreen("25 fast Enters"); ctx.checkAll("25 fast Enters"); ctx.checkInk("25 fast Enters"); ctx.checkHighlightPaint("25 fast Enters")
            ctx.snap("after-fast-enters")

            // 끝에서 처음으로, 처음에서 끝으로
            ctx.at("wrap around")
            m.jump(to: m.searchHits[total - 1]); await ctx.settle(450)
            ctx.expectSelectedHit(total - 1, "clicked the last result row")
            ctx.checkAll("last result"); ctx.checkInk("last result")
            m.findInEditor(); await ctx.settle(150)
            m.submitFind(); await ctx.settle(450)
            ctx.expectSelectedHit(0, "Enter on the last match wraps to the first")
            ctx.checkAll("wrapped to the first"); ctx.checkInk("wrapped to the first"); ctx.checkHighlightPaint("wrapped to the first")
            ctx.snap("wrapped-first")
            m.findPrevious(focusEditor: false); await ctx.settle(450)
            ctx.expectSelectedHit(total - 1, "⇧Enter on the first match wraps to the last")
            ctx.checkAll("wrapped to the last"); ctx.checkInk("wrapped to the last")

            // Esc: 패널이 닫히고 강조·결과가 사라진다. 선택은 남고, 편집기 위쪽은 제자리
            ctx.at("Esc")
            m.jump(to: m.searchHits[total / 2]); await ctx.settle(450)
            let sel = ctx.tv.selectedRange()
            p = ctx.place()
            m.findInEditor(); await ctx.settle(150)
            m.closeQuickFind(); await ctx.settle(400)
            if !m.searchHits.isEmpty || !ctx.tv.matchHighlights.isEmpty { ctx.issue("find", "Esc left \(m.searchHits.count) results and \(ctx.tv.matchHighlights.count) highlight ranges") }
            if m.showBottomPanel { ctx.issue("find", "Esc did not close the bottom panel") }
            if ctx.tv.selectedRange() != sel { ctx.issue("find", "Esc changed the selection from \(sel) to \(ctx.tv.selectedRange())") }
            if ctx.window.firstResponder !== ctx.tv { ctx.issue("find", "after Esc the editor is not the first responder (\(type(of: ctx.window.firstResponder as Any)))") }
            ctx.checkSamePlace(p, "Esc closed the find panel", strictPt: 2)
            ctx.checkAll("Esc"); ctx.checkInk("Esc"); ctx.snap("after-esc")
            // 닫은 뒤 바로 타이핑 (선택된 매치를 대체한다)
            await ctx.typeProbe("Esc")
            // 다시 ⌘F: 패널이 열리며 편집기가 줄어든다 — 위쪽은 제자리
            ctx.at("⌘F again")
            p = ctx.place()
            m.findInEditor(); await ctx.settle(400)
            ctx.checkSamePlace(p, "⌘F opened the bottom panel", strictPt: 2)
            ctx.checkAll("⌘F again"); ctx.snap("reopened")
            m.closeQuickFind(); await ctx.settle(300)
            await saved.restore(ctx)
        },

        // 결과가 떠 있는 채로 스크롤: 강조가 글자를 따라가는가 (4 MB 로그, 결과 수천 건)
        Scenario(name: "find-scroll") { ctx in
            let saved = ViewDefaults(ctx)
            let m = ctx.model
            await ctx.withRelaxedStalls { await ctx.open(.log) }
            await ctx.look(atLine: middleLine(ctx), wheel: 300, click: true)
            ctx.at("type 'ERROR' slowly in a 4 MB log")
            m.findInEditor(); await ctx.settle(200)
            let ok = await ctx.typeQuerySlowly("ERROR", gapMs: 220)
            if !ok || m.searchHits.isEmpty { ctx.issue("find", "'ERROR' search did not finish or found nothing (\(m.searchHits.count) hits)"); await saved.restore(ctx); return }
            ctx.note("\(m.searchHits.count) hits")
            ctx.checkHighlightsEqualHits("'ERROR'"); ctx.checkSelectionOnScreen("'ERROR'")
            ctx.checkAll("'ERROR'"); ctx.checkInk("'ERROR'"); ctx.checkHighlightPaint("'ERROR'"); ctx.snap("results")

            ctx.at("pixel wheel")
            for (i, d) in [60, 140, 300, -90, 500, 37, -260, 800, -800, 1200].enumerated() {
                let a = ctx.anchor()
                await ctx.scrollBy(CGFloat(d)); await ctx.settle(30)
                ctx.checkContentMoved(anchor: a, expected: CGFloat(d), tolerance: 3, "wheel \(d) with results showing")
                ctx.checkLayout("wheel \(d)"); ctx.checkHighlightsOnScreen("wheel \(d)"); ctx.checkHighlightPaint("wheel \(d)")
                if i == 4 { ctx.checkInk("wheel \(d)"); ctx.snap("wheel") }
            }
            ctx.at("flick")
            await ctx.flick(total: 4000); ctx.checkAll("flick down 4000"); ctx.checkInk("flick down 4000"); ctx.checkHighlightPaint("flick down 4000"); ctx.snap("flick-down")
            await ctx.flick(total: -2500); ctx.checkAll("flick up 2500"); ctx.checkInk("flick up 2500"); ctx.checkHighlightPaint("flick up 2500")
            ctx.at("line wheel")
            for _ in 1...3 { await ctx.wheelLines(4); ctx.checkLayout("line wheel"); ctx.checkHighlightPaint("line wheel") }
            ctx.at("page keys")
            for _ in 1...3 { await ctx.key(.pageDown); await ctx.settle(60); ctx.checkAll("page down"); ctx.checkHighlightPaint("page down") }
            for _ in 1...2 { await ctx.key(.pageUp); await ctx.settle(60); ctx.checkAll("page up"); ctx.checkHighlightPaint("page up") }
            ctx.at("document end / start")
            await ctx.key(.down, [.command]); await ctx.settle(250)
            ctx.checkAll("⌘↓ with results"); ctx.checkInk("⌘↓ with results"); ctx.checkHighlightPaint("⌘↓ with results"); ctx.snap("end")
            await ctx.key(.up, [.command]); await ctx.settle(250)
            ctx.checkAll("⌘↑ with results"); ctx.checkInk("⌘↑ with results"); ctx.checkHighlightPaint("⌘↑ with results"); ctx.snap("start")
            m.closeQuickFind(); await ctx.settle(300)
            await saved.restore(ctx)
        },

        // 결과가 떠 있는 채로 편집: 강조가 편집을 따라가고, 1.2 s 뒤 조용한 재검색이 화면을 흔들지 않는가
        Scenario(name: "find-edit") { ctx in
            let saved = ViewDefaults(ctx)
            let m = ctx.model
            let q = "budget"
            await ctx.withRelaxedStalls { await ctx.open(.notes) }
            await ctx.look(atLine: middleLine(ctx), wheel: 400, click: true)
            m.findInEditor(); await ctx.settle(200)
            ctx.at("search")
            var gen = m.searchCompletionCount
            ctx.typeQuery(q)
            guard await ctx.awaitSearch(after: gen), m.searchHits.count > 10 else { ctx.issue("find", "'\(q)' search did not finish (\(m.searchHits.count) hits)"); await saved.restore(ctx); return }
            let n0 = m.searchHits.count
            // 결과 행을 눌러 가운데 매치로
            ctx.at("click a result row")
            let k = n0 / 2
            m.jump(to: m.searchHits[k]); await ctx.settle(450)
            ctx.expectSelectedHit(k, "clicked result row \(k)")
            let hit = m.searchHits[k].range
            let line = ctx.text.paragraphRange(for: hit)

            /// 지금 문서에 검색어가 몇 번 나오는가 (대소문자 무시 — 찾기의 기본 옵션과 같다): 재검색 결과 수의 기준
            @MainActor func occurrences() -> Int {
                let ns = ctx.text
                var n = 0, from = 0
                while from < ns.length {
                    let r = ns.range(of: q, options: [.caseInsensitive, .literal], range: NSRange(location: from, length: ns.length - from))
                    if r.location == NSNotFound { break }
                    n += 1; from = NSMaxRange(r)
                }
                return n
            }
            /// 편집 직후(재검색 전): 강조가 글자를 따라갔는가 · 화면이 그대로인가. 그리고 조용한 재검색 뒤: 결과 수 · 강조 = 결과 · 화면 그대로
            /// `caretMayMove`: 편집이 캐럿을 화면 밖의 자리로 옮기는 경우(화면 위로 넘어간 선택을 지움 · 되돌리기) — 화면이 캐럿을 따라 움직이는 것이 정상이라 위치는 재지 않는다
            @MainActor func afterEdit(_ why: String, expectHighlightsNow: Int?, place p: RealUseContext.Place?, gen: Int, caretMayMove: Bool = false) async {
                let expectHits = occurrences()
                await ctx.settle(60)
                if !caretMayMove { ctx.checkSamePlace(p, why, tolLines: 0, strictPt: 2); ctx.checkCaretVisible(why) }
                ctx.checkHighlightsSpell(q, "\(why) (before the re-search)")
                if let e = expectHighlightsNow, ctx.tv.matchHighlights.count != e { ctx.issue("highlight", "\(why): expected \(e) highlight ranges right after the edit, the editor holds \(ctx.tv.matchHighlights.count)") }
                // 줄 번호는 줄 인덱스(편집 250 ms 뒤 갱신)로 그려져 그 사이에는 캐럿 아래 번호가 잠깐 어긋난다(입력 영역의 문제로 보고) — 거터는 재검색 뒤에 본다
                ctx.checkHighlightsOnScreen("\(why) (before the re-search)")
                ctx.checkLayout(why); ctx.checkHighlightPaint("\(why) (before the re-search)")
                // 캐럿 근처(화면에 보이는)의 매치 몇 개는 뷰포트 범위와 무관하게 직접 확인한다 — 편집 직후 강조가 통째로 안 그려지는 경우를 잡는다
                let near = ctx.tv.matchHighlights.filter { abs($0.location - ctx.caret) < 4000 }.prefix(12)
                for r in near where !ctx.checkMatchPainted(r, "\(why) (before the re-search)") { break }
                let p2 = ctx.place()
                if !(await ctx.awaitSearch(after: gen, timeoutMs: 5000)) { ctx.issue("find", "\(why): the delayed re-search never ran (results stay stale)"); return }
                if m.searchHits.count != expectHits { ctx.issue("find", "\(why): expected \(expectHits) hits after the re-search, got \(m.searchHits.count)") }
                ctx.checkHighlightsEqualHits("\(why) (after the re-search)"); ctx.checkHighlightsSpell(q, "\(why) (after the re-search)")
                ctx.checkHighlightsOnScreen("\(why) (after the re-search)")
                for r in ctx.tv.matchHighlights.filter({ abs($0.location - ctx.caret) < 4000 }).prefix(12) where !ctx.checkMatchPainted(r, "\(why) (after the re-search)") { break }
                ctx.checkSamePlace(p2, "\(why): the delayed re-search", tolLines: 0, strictPt: 2)
                ctx.checkAll("\(why) (after the re-search)"); ctx.checkInk("\(why) (after the re-search)"); ctx.checkHighlightPaint("\(why) (after the re-search)")
            }

            // a. 같은 줄, 매치 앞에 입력
            ctx.at("type before the match")
            await ctx.click(offset: line.location); await ctx.settle(80)
            var p = ctx.place(); gen = m.searchCompletionCount
            var held = ctx.tv.matchHighlights.count   // 편집 직전에 편집기가 든 강조 수 — 편집 직후의 기대값은 여기서 센다
            await ctx.type("ab ")
            await afterEdit("typed 3 characters before a match on its line", expectHighlightsNow: held, place: p, gen: gen)
            ctx.snap("typed-before")
            // b. 매치 안에 입력 → 그 강조는 바로 사라지고 재검색 뒤 결과도 하나 준다
            ctx.at("type inside the match")
            let inside = hit.location + 3 + 3   // 앞에 3 글자를 넣었다
            await ctx.click(offset: inside); await ctx.settle(80)
            if ctx.caret != inside { ctx.note("click inside the match landed at \(ctx.caret), wanted \(inside)"); ctx.tv.setSelectedRange(NSRange(location: inside, length: 0)) }
            p = ctx.place(); gen = m.searchCompletionCount
            held = ctx.tv.matchHighlights.count
            await ctx.type("X")
            await afterEdit("typed inside a match", expectHighlightsNow: held - 1, place: p, gen: gen)
            ctx.snap("typed-inside")
            // c. ⌘Z 로 되돌림 → 재검색 뒤 다시 n0
            ctx.at("undo")
            p = ctx.place(); gen = m.searchCompletionCount
            // 되돌리기는 리본의 되돌리기 버튼 경로(모델 명령)로 — 편집 메뉴의 ⌘Z 는 키 창의 첫 응답자에게 가는 표준 동작이라 창이 키가 아닌 하네스에서는 닿지 않는다
            let before = ctx.length
            m.send(.undo); await ctx.turn()
            if ctx.length == before { ctx.issue("other", "undo after typing changed nothing") }
            else if ctx.length != before - 1 { ctx.note("undo removed \(before - ctx.length) characters (the typing before the click and the one after it came back as one undo step)") }
            await afterEdit("⌘Z after typing inside a match", expectHighlightsNow: nil, place: p, gen: gen, caretMayMove: true)
            // d. 그 줄 끝에서 Enter 후 검색어가 든 새 줄을 한글과 함께
            ctx.at("new line with the query")
            let lineNow = ctx.text.paragraphRange(for: NSRange(location: line.location, length: 0))
            let eol = NSMaxRange(lineNow) - 1
            await ctx.click(offset: eol); await ctx.settle(80)
            if ctx.caret != eol { ctx.tv.setSelectedRange(NSRange(location: eol, length: 0)) }
            p = ctx.place(); gen = m.searchCompletionCount
            held = ctx.tv.matchHighlights.count
            await ctx.type("\n")
            await ctx.composeHangul("예산")
            await ctx.type(" budget ")
            await ctx.composeHangul("검토")
            await afterEdit("typed a new line containing the query", expectHighlightsNow: held, place: p, gen: gen)   // 새 매치의 강조는 재검색이 넣는다
            ctx.snap("new-line")
            // e. 매치가 든 줄을 통째로 삭제 (⌘⇧K)
            ctx.at("delete the line")
            p = ctx.place(); gen = m.searchCompletionCount
            held = ctx.tv.matchHighlights.count
            let caretLine = ctx.text.paragraphRange(for: NSRange(location: min(ctx.caret, ctx.length), length: 0))
            let onLine = ctx.tv.matchHighlights.filter { NSIntersectionRange($0, caretLine).length > 0 }.count
            if !(await ctx.shortcut("K", [.command, .shift])) { ctx.note("⌘⇧K key equivalent not handled — sending the delete-line tool"); m.textTool(.deleteLine) }
            await afterEdit("deleted the new line holding \(onLine) match(es) (⌘⇧K)", expectHighlightsNow: held - onLine, place: p, gen: gen)
            // f. 여러 줄을 선택해 지우고 되돌린다 (매치 여러 개를 걸친다)
            ctx.at("delete a selection spanning matches")
            let from = ctx.caret
            await ctx.key(.down, [.shift], count: 12); await ctx.settle(60)
            let selRange = ctx.tv.selectedRange()
            let inSel = ctx.tv.matchHighlights.filter { NSIntersectionRange($0, selRange).length > 0 }.count
            p = ctx.place(); gen = m.searchCompletionCount
            held = ctx.tv.matchHighlights.count
            await ctx.key(.delete)
            // ⇧↓ 12 번이 선택 끝을 따라 화면을 내렸을 수 있다 — 지우면 캐럿이 선택의 처음(화면 위쪽)으로 돌아가 화면이 따라 올라간다
            await afterEdit("deleted 12 selected lines holding \(inSel) matches", expectHighlightsNow: held - inSel, place: p, gen: gen, caretMayMove: true)
            ctx.checkCaretVisible("deleted 12 selected lines")
            p = ctx.place(); gen = m.searchCompletionCount
            m.send(.undo); await ctx.turn()
            await afterEdit("⌘Z after deleting 12 lines", expectHighlightsNow: nil, place: p, gen: gen, caretMayMove: true)
            if let r = ctx.tv.caretRect(at: ctx.caret), !ctx.visible.insetBy(dx: 0, dy: -2).intersects(r) {
                ctx.note("after ⌘Z the caret (end of the restored lines, offset \(ctx.caret)) is \(Int(r.minY - ctx.visible.maxY)) pt below the screen — the restored lines start on screen (undo does not scroll to the caret; reported to the typing area)")
            }
            _ = from
            ctx.snap("end")
            m.closeQuickFind(); await ctx.settle(300)
            await saved.restore(ctx)
        },

        // 결과 행을 눌러 멀리 떨어진 매치로: 화면 위치·빈 영역·바로 이어지는 스크롤
        Scenario(name: "find-jump") { ctx in
            let saved = ViewDefaults(ctx)
            let m = ctx.model
            for corpus in [RealUseContext.Corpus.notes, .wide] {
                let tag = corpus == .notes ? "notes" : "wide"
                let q = corpus == .notes ? "fox" : "한글 글꼴"
                await ctx.withRelaxedStalls { await ctx.open(corpus) }
                await ctx.look(atLine: middleLine(ctx), wheel: 300, click: true)
                m.findInEditor(); await ctx.settle(200)
                ctx.at("\(tag): search '\(q)'")
                let gen = m.searchCompletionCount
                ctx.typeQuery(q)
                guard await ctx.awaitSearch(after: gen), m.searchHits.count > 20 else { ctx.issue("find", "\(tag): '\(q)' search did not finish (\(m.searchHits.count) hits)"); continue }
                let n = m.searchHits.count
                ctx.checkHighlightsEqualHits("\(tag): '\(q)'"); ctx.checkHighlightPaint("\(tag): '\(q)'"); ctx.snap("\(tag)-results")
                for (i, k) in [n - 1, 0, n / 2, n / 2 + 1, n / 4, 3 * n / 4, 5, n - 3].enumerated() {
                    ctx.at("\(tag): result row \(k) of \(n)")
                    m.jump(to: m.searchHits[k]); await ctx.settle(450)
                    ctx.expectSelectedHit(k, "\(tag): clicked result row \(k)")
                    ctx.checkAll("\(tag): row \(k)"); ctx.checkInk("\(tag): row \(k)"); ctx.checkHighlightPaint("\(tag): row \(k)")
                    if i < 3 { ctx.snap("\(tag)-row-\(k)") }
                    await ctx.scrollProbe("\(tag): row \(k)", by: 120)
                }
                // 매치 위에서 Enter 로 이어 간다 (감긴 문단 안의 매치)
                ctx.at("\(tag): Enter ×8 after a row click")
                var cur = n - 3
                m.findInEditor(); await ctx.settle(100)
                for i in 1...8 {
                    m.submitFind(); await ctx.settle(200)
                    cur = (cur + 1) % n
                    ctx.expectSelectedHit(cur, "\(tag): Enter #\(i) after row click")
                    ctx.checkAll("\(tag): Enter #\(i)"); ctx.checkInk("\(tag): Enter #\(i)")
                }
                ctx.snap("\(tag)-end")
                m.closeQuickFind(); await ctx.settle(300)
            }
            await saved.restore(ctx)
        },

        // 결과가 떠 있는 채로 레이아웃을 바꾼다: 강조가 다시 감긴 글자를 따라가는가
        Scenario(name: "find-reflow") { ctx in
            let saved = ViewDefaults(ctx)
            let m = ctx.model
            await ctx.withRelaxedStalls { await ctx.open(.wide) }
            await ctx.look(atLine: middleLine(ctx), wheel: 500, click: true)
            m.findInEditor(); await ctx.settle(200)
            ctx.at("search")
            let gen = m.searchCompletionCount
            ctx.typeQuery("lazy dog")
            guard await ctx.awaitSearch(after: gen), !m.searchHits.isEmpty else { ctx.issue("find", "'lazy dog' search did not finish"); await saved.restore(ctx); return }
            ctx.checkHighlightPaint("'lazy dog'"); ctx.snap("results")
            let steps: [(String, () -> Void)] = [
                ("wrap off", { m.wordWrap = false }), ("wrap on", { m.wordWrap = true }),
                ("larger text", { m.adjustFontSize(2) }), ("default text size", { m.font.size = saved.fontSize }),
                ("sidebar closed", { m.showFileView = false }), ("sidebar open", { m.showFileView = true }),
                ("line numbers off", { m.showLineNumbers = false }), ("line numbers on", { m.showLineNumbers = true }),
            ]
            for (label, action) in steps {
                await ctx.change("results showing: \(label)", then: .nothing, action)
                let n = ctx.checkHighlightPaint("results showing: \(label)")
                ctx.note("\(n) visible matches checked")
                if label == "wrap off" || label == "larger text" { ctx.snap(label.replacingOccurrences(of: " ", with: "-")) }
                await ctx.scrollProbe("results showing: \(label)")
                ctx.checkHighlightPaint("results showing: \(label) → wheel")
            }
            m.closeQuickFind(); await ctx.settle(300)
            await saved.restore(ctx)
        },

        // 하단 패널을 여닫을 때: 문서 끝에서 쓰고 있을 때와 가운데를 보고 있을 때
        Scenario(name: "find-panel") { ctx in
            let saved = ViewDefaults(ctx)
            let m = ctx.model
            await ctx.withRelaxedStalls { await ctx.open(.notes) }
            // 패널을 닫아 둔 채 문서 끝에서 쓰다가 ⌘F
            ctx.at("panel closed, typing at the end")
            m.showBottomPanel = false; await ctx.settle(300)
            await ctx.key(.down, [.command]); await ctx.settle(200)
            await ctx.type("\n끝에서 쓰는 중 budget")
            await ctx.settle(350)   // 줄 인덱스가 갱신된 뒤 (그 전의 줄 번호 어긋남은 입력 영역의 문제)
            ctx.checkCaretVisible("typing at the end"); ctx.checkAll("typing at the end"); ctx.snap("end-typing")
            ctx.at("⌘F at the end")
            var p = ctx.place()
            m.findInEditor(); await ctx.settle(400)
            ctx.checkSamePlace(p, "⌘F opened the panel while at the end of the document", strictPt: 2)
            ctx.checkAll("⌘F at the end"); ctx.checkInk("⌘F at the end"); ctx.snap("end-panel-open")
            ctx.at("Esc without searching")
            p = ctx.place()
            m.closeQuickFind(); await ctx.settle(400)
            ctx.checkSamePlace(p, "Esc closed the panel at the end of the document", strictPt: 2)
            ctx.checkCaretVisible("Esc at the end"); ctx.checkAll("Esc at the end"); ctx.snap("end-panel-closed")
            await ctx.typeProbe("Esc at the end")
            // ⌘F → 검색어 → Esc 를 가운데에서 여러 번 (패널이 매번 생겼다 사라진다)
            await ctx.look(atLine: middleLine(ctx), wheel: 300, click: true)
            for round in 1...3 {
                ctx.at("round \(round): ⌘F")
                p = ctx.place()
                m.findInEditor(); await ctx.settle(350)
                ctx.checkSamePlace(p, "round \(round): ⌘F opened the panel", strictPt: 2)
                let gen = m.searchCompletionCount
                ctx.typeQuery(round == 2 ? "회의" : "review")
                if !(await ctx.awaitSearch(after: gen)) { ctx.issue("find", "round \(round): the search did not finish") }
                ctx.checkSelectionOnScreen("round \(round): first match"); ctx.checkAll("round \(round): first match"); ctx.checkHighlightPaint("round \(round): first match")
                if round == 2 { ctx.snap("round2-korean") }
                ctx.at("round \(round): Esc")
                p = ctx.place()
                m.closeQuickFind(); await ctx.settle(350)
                ctx.checkSamePlace(p, "round \(round): Esc closed the panel", strictPt: 2)
                ctx.checkAll("round \(round): Esc"); ctx.checkInk("round \(round): Esc")
            }
            await saved.restore(ctx)
        },
    ]
}
