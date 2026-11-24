import AppKit
import HyperCore

// 실사용 시뮬레이션 — 스크롤 상태: 오래 굴린 뒤·탭을 오간 뒤에도 휠을 굴린 만큼 움직이는가, 방향키로 화면 가장자리를 넘을 때 한 줄씩만 밀리는가
//
// 배경(2026-11-24 조사, HyperTextView '스크롤 닻' 주석): TextKit 2 의 레이아웃 관리자는 배치한 조각을 2,000개까지만 붙들고, 넘으면 뷰포트 배치 때 뷰포트 밖의
// 조각을 전부 버린다. 버려진 문단의 높이는 추정값(실제의 1.4~1.6배)으로 돌아가는데 NSTextView 는 그 패스에서 스크롤 위치를 맞추지 않아 화면이 수백 줄 튄다.
// 조각 표의 항목 수에는 사라진 문단의 '죽은 항목'도 남아서, 탭 전환 등으로 그것이 2,000 을 넘기면 모든 배치 패스가 조각을 버린다 — 그 뒤로는 어느 문서에서나
// 휠 75 pt 에 화면이 51 / 27 / 0.3 pt 만 움직였다. 이 파일의 시나리오는 그 두 조건(한 문서에서 2,000 문단 넘게 / 탭을 오가며 죽은 항목 쌓기)을 직접 만든다.

extension RealUseContext {
    /// (TextKit 2 비공개 값) 레이아웃 관리자의 조각 표 항목 수와 캐시 상한. 읽을 수 없으면 nil — 이 값으로 판정하지는 않는다(로그와 재현 조건 맞추기에만 쓴다)
    var fragmentCache: (count: Int, limit: Int)? {
        guard let lm = tv.textLayoutManager, let iv = class_getInstanceVariable(NSTextLayoutManager.self, "_textLayoutFragmentTable"),
              let table = object_getIvar(lm, iv) as? NSMapTable<AnyObject, AnyObject>,
              lm.responds(to: NSSelectorFromString("maximumNumberOfCachedTextLayoutFragments")),
              let limit = lm.value(forKey: "maximumNumberOfCachedTextLayoutFragments") as? Int else { return nil }
        return (table.count, limit)
    }

    /// 캐시 상한을 정한다 (기본은 TextKit 2 의 기본값 2,000) — 앞선 시나리오가 올려 둔 값 때문에 '조각을 버리는 걸음'이 오지 않는 일이 없게. 반환: 바꿀 수 있었는가
    @discardableResult
    func setFragmentCacheLimit(_ limit: Int = 2_000) -> Bool {
        guard let lm = tv.textLayoutManager, lm.responds(to: NSSelectorFromString("setMaximumNumberOfCachedTextLayoutFragments:")) else { return false }
        lm.setValue(limit, forKey: "maximumNumberOfCachedTextLayoutFragments")
        return true
    }

    /// 조각을 `more` 개 더 배치하면 버리기가 일어나게 상한을 맞춘다 (짧은 구간에서 그 걸음을 지나가게)
    func armFragmentFlush(after more: Int) {
        guard let c = fragmentCache else { note("fragment cache not readable on this system — the flush will come whenever TextKit decides"); return }
        setFragmentCacheLimit(c.count + more)
    }

    func logFragmentCache(_ tag: String) {
        if let c = fragmentCache { note("\(tag): fragment table \(c.count) entries, cache limit \(c.limit)") }
    }

    /// "표의 항목 수가 늘 캐시 상한을 넘는" 상태를 만든다 — 죽은 항목이 상한을 넘긴 세션과 같은 조건이다(통합 기준선에서 3줄 문서의 표가 2,347개, 상한 2,000):
    /// 모든 배치 패스가 뷰포트 밖 조각을 버린다. 죽은 항목을 걸음 수로 쌓아 맞추기는 어렵다(표에 새 항목이 들어갈 때 일부가 걷힌다 — 1,900줄씩 세 문서를 훑어도
    /// 기준선에서 재현되지 않았다). 그래서 상한을 화면의 조각 수보다 작게 내려 같은 관계를 직접 만든다
    func pinFragmentCache() {
        guard let c = fragmentCache else { note("fragment cache not readable on this system — cannot put the table over its limit"); return }
        setFragmentCacheLimit(8)
        note("fragment table \(c.count) entries — cache limit lowered from \(c.limit) to 8 so that every layout pass flushes")
    }

    /// 검사 없이 한 문서를 훑는다: 맨 위에서 `lines` 줄쯤 아래로 (조각을 그만큼 배치해 둔다)
    func skim(lines: Int) async {
        await key(.up, [.command]); await settle(200)
        await wheelTo(steps: max(1, lines * 24 / 480), by: 480)
    }

    /// 방향키(와 그 조합)를 `count` 번 누르며 걸음마다 본다: 움직인 쪽 끝의 줄이 온전히 보이는가, 화면이 밀렸다면 가는 방향으로 `maxMove` 이내인가, 가장자리에서 먼
    /// 캐럿이 움직였는데 화면이 밀리지는 않았는가, 밀린 뒤 캐럿 줄이 넘어온 가장자리에 붙어 있는가 (`flush` — 필요한 만큼만 밀었다는 뜻). 반환: 화면이 밀린 걸음 수
    @discardableResult
    func arrowWalk(_ k: Key, _ mods: NSEvent.ModifierFlags = [], count: Int, _ label: String, maxMove: CGFloat? = nil, flush: Bool = true) async -> Int {
        let n0 = issues.count
        let up = k == .up || k == .left
        var scrolled = 0, worst: CGFloat = 0
        for i in 1...count {
            let v0 = visible
            let sel0 = tv.selectedRange()
            let lh = lineHeight
            let before = tv.caretRect(at: mods.contains(.shift) && sel0.length > 0 ? (up ? sel0.location : NSMaxRange(sel0)) : sel0.location).map { $0.minY - v0.minY }
            let a = anchor(nearScreenY: up ? 60 : v0.height - 90)
            await key(k, mods); await settle(0)
            let v = visible
            let sel = tv.selectedRange()
            let head = sel.length == 0 ? sel.location : (sel.location != sel0.location ? sel.location : NSMaxRange(sel))
            guard let r = tv.caretRect(at: head) else { continue }
            let cy = r.minY - v.minY
            if cy < -0.75 || cy + r.height > v.height + 0.75 {
                issue("caret-hidden", "\(label) #\(i): after the key the caret line is at screen y \(String(format: "%.1f", cy))…\(String(format: "%.1f", cy + r.height)) of a \(Int(v.height)) pt viewport — not fully visible")
            }
            if let m = moved(since: a), abs(m) > 0.5 {
                scrolled += 1; worst = max(worst, abs(m))
                // 드러난 줄 하나만큼 (문서 처음·끝에 닿으면 위·아래 여백까지)
                let inset = tv.textContainerInset.height
                let atEnd = up ? v.minY < 0.5 : v.maxY > tv.frame.height - 1
                let limit = maxMove ?? max(lh, r.height) + 1 + (atEnd ? inset + 4 : 0)
                let nearEdge = maxMove != nil || (before.map { up ? $0 < 2 * lh : $0 > v0.height - 3 * lh } ?? true)
                if !nearEdge || (up ? m > 0.5 : m < -0.5) || abs(m) > limit {
                    issue("viewport-jump", "\(label) #\(i): one key moved the content by \(String(format: "%.1f", m)) pt on screen (caret was at y \(before.map { String(Int($0)) } ?? "?"), now \(Int(cy)); at most \(String(format: "%.1f", limit)) pt toward the caret is expected)")
                }
                // 필요한 만큼만: 넘어온 쪽 가장자리에 캐럿 줄이 붙는다 (문서 처음·끝에서는 여백만큼 떨어진다)
                let gap = up ? cy : v.height - (cy + r.height)
                if flush, gap > inset + 4 { issue("viewport-jump", "\(label) #\(i): after scrolling for the caret, its line sits \(String(format: "%.1f", gap)) pt inside the \(up ? "top" : "bottom") edge — more was scrolled than needed") }
            }
            checkLayout("\(label) #\(i)")
            if i % 25 == 0 { checkGutter("\(label) #\(i)"); checkInk("\(label) #\(i)") }
            if tooManyIssues(since: n0) { break }
        }
        note(String(format: "%@: %d of %d presses scrolled the view, the largest by %.1f pt", label, scrolled, count, worst))
        return scrolled
    }
}

extension RealUse {
    @MainActor static let scrollStateScenarios: [Scenario] = [
        // 한 문서에서 2,000 문단 넘게: 조각을 버리는 걸음에서도 휠을 굴린 만큼만 움직이고, 같은 만큼 올라오면 처음이다. Page Down/Up 도 같은 쪽
        Scenario(name: "scroll-long-run") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "longrun.md") }
            ctx.setFragmentCacheLimit()
            await ctx.key(.up, [.command]); await ctx.settle(200)
            ctx.logFragmentCache("at the top")
            ctx.at("wheel down 300 × 250")
            await ctx.wheelRun("long wheel down", steps: 300, by: 250, deepEvery: 60)
            ctx.logFragmentCache("after 75,000 pt down")
            // 75,000 pt 는 24 pt 줄로 3,125 줄 — 감긴 문단을 빼도 2,600 문단은 넘는다. 훨씬 못 미치면 어느 걸음에서 뒤로 튄 것이다
            let reached = ctx.topLine()
            if reached < 2_600 || reached > 3_200 { ctx.issue("scroll-delta", "300 × 250 pt down from the top ended at line \(reached), expected about 2,800") }
            ctx.snap("long-down")
            ctx.at("wheel up 300 × 250")
            await ctx.wheelRun("long wheel up", steps: 300, by: -250, deepEvery: 60)
            ctx.expectTop("after 300 × 250 pt down and back up"); ctx.checkAll("back at the top"); ctx.checkInk("back at the top")
            // Page Down: 버리기가 구간 안에서 일어나게 맞춰 두고(조각 300개 뒤), 쪽마다 같은 크기로 넘어가는지 본다
            ctx.at("Page Down × 40 across a flush")
            ctx.model.jump(toLine: 6_000); await ctx.settle(450)
            ctx.armFragmentFlush(after: 300)
            let line0 = ctx.topLine()
            let ref = ctx.anchor()
            var amounts: [CGFloat] = []
            for i in 1...40 {
                let a = ctx.edgeAnchor(bottom: true)
                let top0 = ctx.topLine()
                await ctx.key(.pageDown); await ctx.settle(300)
                if let m = ctx.moved(since: a) { amounts.append(m) } else { ctx.issue("scroll-delta", "Page Down #\(i): the paragraph at the bottom edge of the previous page is not on screen any more (top line \(top0) → \(ctx.topLine()))") }
                if ctx.topLine() <= top0 { ctx.issue("scroll-delta", "Page Down #\(i): top line went from \(top0) to \(ctx.topLine())") }
                ctx.checkLayout("Page Down #\(i)")
                if ctx.issues.count > 12 { break }
            }
            if let mn = amounts.min(), let mx = amounts.max(), mx - mn > 2 { ctx.issue("scroll-delta", "Page Down moved by \(String(format: "%.1f", mn))…\(String(format: "%.1f", mx)) pt — pages should be the same size") }
            ctx.logFragmentCache("after 40 pages")
            ctx.at("Page Up × 40 back")
            ctx.armFragmentFlush(after: 300)
            for i in 1...40 {
                await ctx.key(.pageUp); await ctx.settle(300)
                ctx.checkLayout("Page Up #\(i)")
            }
            if let m = ctx.moved(since: ref) {
                if abs(m) > 2 { ctx.issue("scroll-delta", "40 × Page Down then 40 × Page Up from line \(line0): the content ended \(String(format: "%.1f", m)) pt away from where it started") }
            } else { ctx.issue("scroll-delta", "40 × Page Down then 40 × Page Up from line \(line0) ended at line \(ctx.topLine()) — the starting paragraph is not on screen") }
            ctx.checkAll("after the page round trip"); ctx.checkInk("after the page round trip")
            ctx.snap("end")
        },

        // 탭을 오가며 훑은 뒤(사라진 문단의 죽은 항목이 조각 표에 쌓인다): 새로 연 문서에서도, 돌아온 탭에서도 휠을 굴린 만큼만 움직인다
        Scenario(name: "scroll-after-switch") { ctx in
            ctx.logWindowState()
            ctx.setFragmentCacheLimit()
            var first: URL?
            for name in ["switch-a.md", "switch-b.md", "switch-c.md"] {
                var opened: URL?
                await ctx.withRelaxedStalls { opened = await ctx.open(.notes, name: name) }
                if first == nil { first = opened }
                await ctx.skim(lines: 1_900)
                ctx.logFragmentCache("after skimming \(name)")
            }
            await ctx.open(.small, name: "switch-small.md")
            ctx.logFragmentCache("on a 20-line document")
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "switch-d.md") }
            await ctx.key(.up, [.command]); await ctx.settle(300)
            ctx.pinFragmentCache()
            ctx.at("fresh document: wheel down 60 × 75")
            await ctx.wheelRun("after the switches: down", steps: 60, by: 75)
            ctx.at("fresh document: wheel up 60 × 75")
            await ctx.wheelRun("after the switches: up", steps: 60, by: -75)
            ctx.expectTop("after the switches: 60 × 75 pt down and back up")
            ctx.at("fresh document: rested wheels")
            await ctx.wheelTo(steps: 8, by: 300)
            await ctx.restedSteps("after the switches")
            ctx.at("fresh document: from the end")
            await ctx.key(.down, [.command]); await ctx.settle(300)
            ctx.expectBottom("after the switches: ⌘↓"); ctx.checkCaretVisible("after the switches: ⌘↓")
            await ctx.wheelRun("after the switches: up from the end", steps: 60, by: -50)
            await ctx.wheelRun("after the switches: back to the end", steps: 70, by: 50)
            ctx.expectBottom("after the switches: wheeling back to the end"); ctx.checkInk("after the switches: back at the end")
            ctx.at("fresh document: type, then wheel")
            await ctx.wheelTo(steps: 20, by: -400); await ctx.settle(200)
            if let target = ctx.anchor() {
                await ctx.click(offset: target.offset)
                await ctx.type("typed after the switches 전환 뒤 입력 ")
                await ctx.settle(60)
                if let m = ctx.moved(since: target), abs(m) > 1 { ctx.issue("viewport-jump", "typing moved the paragraph being typed in by \(String(format: "%.1f", m)) pt on screen") }
                await ctx.wheelChecked(-150, "after the switches: wheel up right after typing")
                await ctx.wheelChecked(300, "after the switches: wheel down right after typing")
                await ctx.settle(400)
                await ctx.wheelRun("after the switches: away after typing", steps: 30, by: 75)
            }
            ctx.snap("fresh-document")
            // 처음 탭으로 돌아가서 (읽던 자리가 되살아난다)
            ctx.at("back on the first tab")
            if let first {
                await ctx.withRelaxedStalls { ctx.model.activateTab(first); await ctx.settle(700) }
                ctx.tv.window?.makeFirstResponder(ctx.tv)
                ctx.logFragmentCache("back on the first tab")
                let home = ctx.anchor()
                await ctx.wheelRun("first tab: down", steps: 40, by: 75)
                await ctx.wheelRun("first tab: up", steps: 40, by: -75)
                if let m = ctx.moved(since: home) {
                    if abs(m) > 1.5 { ctx.issue("scroll-delta", "first tab: 40 × 75 pt down and back up ended \(String(format: "%.1f", m)) pt from where it started") }
                } else { ctx.issue("scroll-delta", "first tab: 40 × 75 pt down and back up — the starting paragraph is not on screen (top line \(ctx.topLine()))") }
                ctx.checkAll("first tab"); ctx.checkInk("first tab")
            }
            ctx.snap("end")
        },

        // 캐시 상한 조정 없이(비공개 값이 없는 시스템에서처럼) '스크롤 닻'만으로: 한 문서에서 2,000 문단을 넘기는 걸음은 닻만으로도 화면이 맞아야 한다.
        // 닻만으로 안 되는 것(실측 2026-11-24): 표의 항목 수가 늘 상한을 넘는 상태(pinFragmentCache)에서는 걸음마다 조각이 버려지고 AppKit 이 스크롤 위치를
        // 엉뚱하게 당겨 75 pt 휠 6걸음에 5번 어긋났다(−165 / 51 / −141 pt) — 그 상태는 상한을 다시 잡아야 풀린다(scroll-after-switch 가 본다)
        Scenario(name: "scroll-anchor-only") { ctx in
            ctx.logWindowState()
            HyperTextView.adjustsFragmentCacheLimit = false
            defer { HyperTextView.adjustsFragmentCacheLimit = true }
            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "anchor.md") }
            await ctx.key(.up, [.command]); await ctx.settle(300)
            // 앞선 시나리오들이 남긴 죽은 항목 위로 2,000개 — 죽은 항목이 없는 세션에서 한 문서를 2,000 문단 훑는 것과 같은 조건
            // (상한을 그냥 2,000 으로 두면 묶음 실행에서는 죽은 항목만으로 이미 넘어 있어, 닻만으로는 못 푸는 상태를 재게 된다)
            ctx.armFragmentFlush(after: 2_000)
            ctx.at("long run 230 × 250")
            await ctx.wheelRun("anchor only: long down", steps: 230, by: 250, deepEvery: 60)
            let reached = ctx.topLine()
            if reached < 2_000 || reached > 2_450 { ctx.issue("scroll-delta", "anchor only: 230 × 250 pt down from the top ended at line \(reached), expected about 2,150") }
            await ctx.wheelRun("anchor only: long up", steps: 230, by: -250, deepEvery: 60)
            ctx.expectTop("anchor only: 230 × 250 pt down and back up")
            ctx.logFragmentCache("at the end of the run")
            ctx.snap("end")
        },

        // 방향키로 화면 가장자리 넘기: 감긴 문단, ⇧선택 늘리기, 줄 끝에서 ←/→, ⌥↑/⌥↓, 한글 조합 뒤, 열 모드, 멀티 캐럿, 멀리 굴려 둔 채 누르기
        Scenario(name: "scroll-arrow-edges") { ctx in
            ctx.logWindowState()
            await ctx.withRelaxedStalls { await ctx.open(.wide, name: "arrows-wide.md") }
            ctx.at("wrapped paragraphs: ↓ × 60")
            ctx.model.jump(toLine: 2_000); await ctx.settle(450)
            if await ctx.arrowWalk(.down, count: 60, "wrapped ↓") == 0 { ctx.issue("other", "wrapped ↓: 60 presses never reached the bottom edge") }
            ctx.at("wrapped paragraphs: ↑ × 90")
            await ctx.arrowWalk(.up, count: 90, "wrapped ↑")
            ctx.snap("wrapped-up")
            ctx.at("wrapped paragraphs: ⇧↓ × 40, ⇧↑ × 60")
            await ctx.arrowWalk(.down, [.shift], count: 40, "wrapped ⇧↓")
            if ctx.tv.selectedRange().length == 0 { ctx.issue("selection", "⇧↓ × 40 left no selection") }
            await ctx.arrowWalk(.up, [.shift], count: 60, "wrapped ⇧↑")
            ctx.at("wrapped paragraphs: ⌥↓ × 12, ⌥↑ × 16")
            await ctx.key(.right); await ctx.settle(0)
            // 문단 끝·처음으로: 한 번에 문단 하나(여러 시각 줄)를 건넌다 — 한 화면 이내, 가는 방향으로만
            await ctx.arrowWalk(.down, [.option], count: 12, "wrapped ⌥↓", maxMove: ctx.visible.height)
            await ctx.arrowWalk(.up, [.option], count: 16, "wrapped ⌥↑", maxMove: ctx.visible.height)

            await ctx.withRelaxedStalls { await ctx.open(.notes, name: "arrows-notes.md") }
            ctx.at("→ past line ends at the bottom edge")
            ctx.model.jump(toLine: 7_000); await ctx.settle(450)
            await ctx.arrowWalk(.down, count: 16, "to the bottom edge")
            for i in 1...6 {
                await ctx.key(.right, [.command]); await ctx.settle(0)   // 줄 끝
                await ctx.arrowWalk(.right, count: 1, "→ across line end #\(i)")
            }
            ctx.at("← past line starts at the top edge")
            await ctx.arrowWalk(.up, count: 22, "to the top edge")
            for i in 1...6 {
                await ctx.key(.left, [.command]); await ctx.settle(0)    // 줄 처음
                await ctx.arrowWalk(.left, count: 1, "← across line start #\(i)")
            }
            ctx.at("after composing Hangul at the bottom edge")
            await ctx.arrowWalk(.down, count: 22, "to the bottom edge again")
            let y0 = ctx.visible.minY
            await ctx.composeHangul("한글 조합"); await ctx.settle(60)
            ctx.checkViewportStable(from: y0, "composing on the bottom line"); ctx.checkCaretVisible("composing on the bottom line")
            await ctx.arrowWalk(.down, count: 6, "↓ after composing")
            await ctx.arrowWalk(.up, count: 24, "↑ after composing")
            // 조합 중(확정 전)의 방향키는 입력기 몫이다 — 여기서는 조합 중인 글자가 있는 채로 화면이 튀지 않는지만 본다
            ctx.at("arrow while a syllable is still marked")
            ctx.tv.setMarkedText("ㅎ", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            await ctx.settle(0)
            let y1 = ctx.visible.minY
            await ctx.key(.up); await ctx.settle(30)
            ctx.checkViewportStable(from: y1, "↑ while composing"); ctx.checkCaretVisible("↑ while composing"); ctx.checkLayout("↑ while composing")
            ctx.tv.unmarkText(); await ctx.settle(30)

            ctx.at("column mode: ⇧↓ × 30 past the bottom edge")
            ctx.model.jump(toLine: 9_000); await ctx.settle(450)
            let column0 = ctx.model.columnMode
            ctx.model.columnMode = true; await ctx.settle(60)
            for i in 1...30 {
                await ctx.key(.down, [.shift]); await ctx.settle(0)
                guard let m = ctx.tv.multi, let block = m.block else { ctx.issue("selection", "column ⇧↓ #\(i): no column block"); break }
                let headRange = m.ranges[block.headIsBottom ? m.ranges.count - 1 : 0]
                if let r = ctx.tv.caretRect(at: headRange.location) {
                    let cy = r.minY - ctx.visible.minY
                    if cy < -0.75 || cy + r.height > ctx.visible.height + 0.75 { ctx.issue("caret-hidden", "column ⇧↓ #\(i): the block's moving end is at screen y \(String(format: "%.1f", cy)) — not visible"); break }
                }
                ctx.checkLayout("column ⇧↓ #\(i)")
            }
            if (ctx.tv.multi?.ranges.count ?? 0) < 25 { ctx.issue("selection", "column ⇧↓ × 30 selected \(ctx.tv.multi?.ranges.count ?? 0) lines") }
            ctx.model.columnMode = column0; await ctx.settle(60)

            ctx.at("multi caret, then ↓")
            ctx.model.jump(toLine: 9_100); await ctx.settle(450)
            let c = ctx.caret
            ctx.tv.setMulti([NSRange(location: c, length: 0), NSRange(location: c + 3, length: 0), NSRange(location: c + 9, length: 0)])
            await ctx.settle(30)
            await ctx.arrowWalk(.down, count: 20, "↓ from three carets")
            if ctx.tv.multi != nil { ctx.issue("selection", "↓ kept the extra carets") }

            ctx.at("arrow key with the caret far off screen")
            await ctx.wheelTo(steps: 6, by: 700); await ctx.settle(200)
            await ctx.key(.down); await ctx.settle(60)
            ctx.checkCaretVisible("↓ after wheeling 4,200 pt away from the caret"); ctx.checkAll("↓ after wheeling away")
            await ctx.arrowWalk(.down, count: 14, "↓ after coming back")

            ctx.at("document ends")
            await ctx.key(.down, [.command]); await ctx.settle(300)
            ctx.expectBottom("⌘↓ after the arrow walks"); ctx.checkCaretVisible("⌘↓")
            await ctx.arrowWalk(.up, count: 30, "↑ from the last line")
            await ctx.arrowWalk(.down, count: 34, "↓ back to the last line")
            ctx.expectBottom("after ↓ back to the last line")
            await ctx.key(.up, [.command]); await ctx.settle(300)
            ctx.expectTop("⌘↑"); ctx.checkCaretVisible("⌘↑")
            await ctx.arrowWalk(.down, count: 30, "↓ from the first line")
            await ctx.arrowWalk(.up, count: 34, "↑ back to the first line")
            ctx.expectTop("after ↑ back to the first line")
            ctx.checkInk("at the top")
            ctx.snap("end")
        },

        // 처음 여는 파일(저장된 보기 위치 없음)은 문서 끝을 보여 준다: 끝을 지나쳐 빈 화면이 되면 안 된다. 줄마다 한글이 든 120줄 문서 — 추정 높이가 실제보다
        // 훨씬 커서(파일 보기 영역이 넘긴 재현: 편집기 폭 757 pt 에서 visible 4277…4737, 문서 높이 4331) 추정 기준의 끝으로 간 스크롤이 남는지 본다
        Scenario(name: "scroll-first-open-end") { ctx in
            let folder = ctx.dir.appendingPathComponent("first-open", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for name in ["alpha.md", "beta.md", "gamma.txt", "회의록 2026-11.md", "메모 한글 줄.md"] {
                ctx.at("first open of \(name)")
                let url = folder.appendingPathComponent(name)
                try? RealUseContext.numberedText((name as NSString).deletingPathExtension, lines: 120).write(to: url, atomically: true, encoding: .utf8)
                ctx.model.open(url: url); await ctx.settle(400)
                ctx.tv.window?.makeFirstResponder(ctx.tv)
                let v = ctx.visible
                ctx.note(String(format: "editor width %.0f: visible %.0f…%.0f, document height %.0f, top line %d", ctx.scroll.frame.width, v.minY, v.maxY, ctx.tv.frame.height, ctx.topLine()))
                ctx.checkLayout("first open of \(name)"); ctx.checkInk("first open of \(name)"); ctx.checkCaretVisible("first open of \(name)")
                ctx.expectBottom("first open of \(name)")
                await ctx.settle(1_200)
                ctx.checkLayout("first open of \(name), 1.2 s later"); ctx.expectBottom("first open of \(name), 1.2 s later")
            }
            ctx.snap("end")
        },

        // 줄 높이: 한글이 든 줄도 다른 줄과 같아야 한다 (문단 스타일의 고정 줄 높이 — 글꼴의 leading 이 더해지면 한글 줄만 1.3 pt 높아진다)
        Scenario(name: "scroll-line-height") { ctx in
            for (corpus, name) in [(RealUseContext.Corpus.notes, "lineheight-notes.md"), (.wide, "lineheight-wide.md")] {
                await ctx.withRelaxedStalls { await ctx.open(corpus, name: name) }
                let lines = LineIndex(nsString: ctx.text).lineCount
                for n in [1, lines / 2, lines] {
                    ctx.at("\(name) line \(n)")
                    ctx.model.jump(toLine: n); await ctx.settle(450)
                    guard let lm = ctx.tv.textLayoutManager, let cs = ctx.tv.textContentStorage else { return }
                    let want = ctx.tv.defaultParagraphStyle?.maximumLineHeight ?? 0
                    guard want > 0 else { ctx.issue("other", "no fixed line height in the default paragraph style"); return }
                    var seen = 0, hangul = 0
                    for f in ctx.viewportFragments() {
                        guard let loc = cs.location(cs.documentRange.location, offsetBy: f.offset), let frag = lm.textLayoutFragment(for: loc) else { continue }
                        let text = ctx.text.substring(with: NSRange(location: f.offset, length: f.length))
                        if HangulFontFixer.containsHangul(text) { hangul += 1 }
                        for line in frag.textLineFragments where line.characterRange.length > 0 {
                            seen += 1
                            if abs(line.typographicBounds.height - want) > 0.01 {
                                ctx.issue("gap", "\(name) line \(n): a visual line of the paragraph at offset \(f.offset) is \(String(format: "%.2f", line.typographicBounds.height)) pt high, the fixed line height is \(String(format: "%.2f", want))"); return
                            }
                        }
                    }
                    ctx.note("\(seen) visual lines on screen (\(hangul) paragraphs with Hangul), all \(String(format: "%.2f", want)) pt")
                    ctx.checkAll("\(name) line \(n)"); ctx.checkInk("\(name) line \(n)")
                }
            }
        },
    ]
}
