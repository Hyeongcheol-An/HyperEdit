import SwiftUI
import AppKit
import HyperCore

// 실사용 시뮬레이션 — 파일 탭: 여러 파일을 열어 탭마다 다른 위치로 스크롤 → 전환하며 보기 위치·내용 유지, 닫기, 많은 탭
//
// 탭 줄은 SwiftUI 뷰라 NSView 가 없다. 탭마다 깔려 있는 가운데 클릭 받이(`MiddleClickCatcher.CatcherView`)가 탭과 같은 크기의 NSView 이므로
// 그 프레임으로 탭의 창 좌표를 얻고(겹침·활성 탭 가시성 검사, 클릭 좌표), 탭 줄만 잘라 PNG 로 남긴다.
// 클릭은 창이 아니라 화면 밖의 활성화하지 않는 패널에 얹은 탭 줄 사본에 보낸다 (아래 "탭 클릭" 절) — 보통 창에 `window.sendEvent` 로 mouseDown 을 주면
// AppKit 이 그 창을 앞으로 올려 사용자의 화면을 가린다.
// + · 폴더 버튼, ▾ 목록, 우클릭 메뉴, 빈 곳 더블클릭은 패널·메뉴를 띄우므로 건드리지 않는다 (모델 함수를 직접 부른다).

@MainActor private enum TabsTally { static var checks = 0; static var crops = 0 }

/// 클릭 시험용 패널: 앱을 활성화하지 않고(.nonactivatingPanel) 키 창도 될 수 없다 — 사용자가 쓰고 있는 앱의 키보드 포커스를 가져오지 않는다
private final class ProbePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 클릭 시험용 탭 줄 사본 (RealUseContext.tabProbe) — 창의 탭 줄과 같은 뷰, 같은 모델
private struct ProbeTabBar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        DocumentTabBar(doc: model.document, theme: model.themes.current).environmentObject(model).frame(width: 1100, height: 26)
    }
}

extension RealUseContext {
    // MARK: 말뭉치

    /// 줄마다 번호가 있는 짧은 줄 문서 — 줄이 감기지 않아 "맨 위에 보이는 줄"이 정확히 비교된다. 머리글(#)이 섞여 접기 후보가 있다
    static func numberedText(_ tag: String, lines: Int) -> String {
        var s = "# \(tag)\n"
        s.reserveCapacity(lines * 48)
        for i in 2...max(2, lines) {
            if i % 50 == 0 { s += "## \(tag) section \(i)\n" } else { s += "\(tag) \(i) 번째 줄 — the quick brown fox\n" }
        }
        return s
    }

    /// 번호 문서를 만들어 탭으로 연다. 반환: 탭 목록에 들어가는(심볼릭 링크를 푼) 경로
    @discardableResult
    func openNumbered(_ name: String, lines: Int) async -> URL {
        let tag = (name as NSString).deletingPathExtension
        return await open(text: Self.numberedText(tag, lines: lines), name: name).resolvingSymlinksInPath()
    }

    func elapsedMs(since t: CFAbsoluteTime) -> Double { (CFAbsoluteTimeGetCurrent() - t) * 1000 }

    // MARK: 탭 줄의 좌표

    /// 탭마다 깔려 있는 가운데 클릭 받이 — 왼쪽 → 오른쪽 (= `model.tabs` 순서)
    func tabCatchers(in root: NSView? = nil) -> [MiddleClickCatcher.CatcherView] {
        var out: [MiddleClickCatcher.CatcherView] = []
        func walk(_ v: NSView) {
            if let c = v as? MiddleClickCatcher.CatcherView { out.append(c) }
            for s in v.subviews { walk(s) }
        }
        if let root = root ?? window.contentView { walk(root) }
        return out.sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
    }

    /// 탭들의 프레임 (창 좌표)
    func tabFrames() -> [NSRect] { tabCatchers().map { $0.convert($0.bounds, to: nil) } }

    func tabFrame(_ url: URL) -> NSRect? {
        let frames = tabFrames()
        guard frames.count == model.tabs.count, let i = model.tabs.firstIndex(of: url) else { return nil }
        return frames[i]
    }

    /// 탭 줄의 보이는 영역 (가로 스크롤 뷰, 창 좌표)
    func tabStripViewport() -> NSRect? {
        guard let sv = tabCatchers().first?.enclosingScrollView else { return nil }
        return sv.convert(sv.bounds, to: nil)
    }

    // MARK: 탭 검사

    /// 탭 목록과 문서의 일치: 활성 문서에 탭이 있는가, 중복이 없는가, 세션 저장이 탭 순서와 같은가, 최근 순서의 맨 앞이 활성 탭인가, 화면의 글이 디스크와 같은가
    func checkTabs(_ why: String) {
        TabsTally.checks += 1
        let tabs = model.tabs, active = model.document.url
        if !tabs.contains(active) { issue("tabs", "\(why): the active document \(active.lastPathComponent) has no tab (tabs: \(tabs.map(\.lastPathComponent)))") }
        if Set(tabs).count != tabs.count { issue("tabs", "\(why): duplicate tabs \(tabs.map(\.lastPathComponent))") }
        let saved = AppDefaults.store.stringArray(forKey: AppModel.openDocumentsKey) ?? []
        if saved != tabs.map(\.path) { issue("tabs", "\(why): the persisted session has \(saved.count) paths \(saved.map { ($0 as NSString).lastPathComponent }) but the tabs are \(tabs.map(\.lastPathComponent))") }
        if model.recentTabs.first != active { issue("tabs", "\(why): most recent tab is \(model.recentTabs.first?.lastPathComponent ?? "nil") but the active document is \(active.lastPathComponent)") }
        if window.title != active.lastPathComponent { issue("tabs", "\(why): window title '\(window.title)' but the active document is \(active.lastPathComponent)") }
        checkContentMatchesDisk(why)
    }

    /// 수정 중이 아니면 편집기의 글은 디스크의 파일과 같아야 한다 (탭 전환 = 디스크에서 다시 읽기)
    func checkContentMatchesDisk(_ why: String) {
        TabsTally.checks += 1
        let url = model.document.url
        guard model.document.isLoaded, !model.document.isDirty, length < 8_000_000, let disk = try? String(contentsOf: url, encoding: .utf8) else { return }
        if !text.isEqual(to: disk) {
            issue("text", "\(why): the editor shows \(length) UTF-16 units for \(url.lastPathComponent) but the file on disk has \((disk as NSString).length) (not dirty)")
        }
    }

    func expectTabs(_ expected: [URL], active: URL, _ why: String) {
        TabsTally.checks += 1
        if model.tabs != expected { issue("tabs", "\(why): tabs are [\(model.tabs.map(\.lastPathComponent).joined(separator: " "))], expected [\(expected.map(\.lastPathComponent).joined(separator: " "))]") }
        if model.document.url != active { issue("tabs", "\(why): active is \(model.document.url.lastPathComponent), expected \(active.lastPathComponent)") }
        checkTabs(why)
    }

    /// 탭 줄의 모양: 탭 수 = 탭 뷰 수, 탭끼리 겹치거나 벌어지지 않음, 활성 탭이 보이는 영역 안, 탭이 다 들어가면 스크롤 영역이 탭 폭에 맞음(+ · 폴더 버튼이 마지막 탭 바로 뒤)
    func checkTabBar(_ why: String) {
        TabsTally.checks += 1
        let frames = tabFrames(), tabs = model.tabs
        guard frames.count == tabs.count else { issue("tabbar", "\(why): \(frames.count) tab views on screen for \(tabs.count) tabs"); return }
        for (i, (a, b)) in zip(frames, frames.dropFirst()).enumerated() {
            if b.minX < a.maxX - 0.5 { issue("tabbar", "\(why): tab \(i + 1) '\(tabs[i].lastPathComponent)' (x \(Int(a.minX))…\(Int(a.maxX))) overlaps the next one (starts at \(Int(b.minX)))"); break }
            if b.minX > a.maxX + 0.5 { issue("tabbar", "\(why): \(String(format: "%.1f", b.minX - a.maxX)) pt gap after tab \(i + 1) '\(tabs[i].lastPathComponent)'"); break }
            if abs(a.minY - b.minY) > 0.5 || abs(a.height - b.height) > 0.5 { issue("tabbar", "\(why): tab \(i + 2) is at y \(b.minY) h \(b.height), the previous one at y \(a.minY) h \(a.height)"); break }
        }
        guard let vp = tabStripViewport(), let first = frames.first, let last = frames.last else { note("\(why): tab strip has no scroll view"); return }
        let contentW = last.maxX - first.minX
        if let i = tabs.firstIndex(of: model.document.url) {
            let f = frames[i]
            if f.minX < vp.minX - 0.5 || f.maxX > vp.maxX + 0.5 {
                issue("tabbar", "\(why): the active tab '\(tabs[i].lastPathComponent)' (\(i + 1) of \(tabs.count)) spans x \(Int(f.minX))…\(Int(f.maxX)) but the strip shows only \(Int(vp.minX))…\(Int(vp.maxX))")
            }
        }
        if contentW <= vp.width - 1 {
            issue("tabbar", "\(why): \(tabs.count) tabs need \(Int(contentW)) pt but the scrolling strip is \(Int(vp.width)) pt wide — the + / folder buttons sit \(Int(vp.width - contentW)) pt away from the last tab")
        }
    }

    /// 탭 줄 둘레만 잘라 PNG 로 (창 전체 스냅샷에서는 26 pt 짜리 줄이 너무 작다). 반환: 파일 이름
    @discardableResult
    func snapTabBar(_ name: String) -> String? {
        guard let root = window.contentView, let f = tabFrames().first else { return nil }
        let r = root.convert(f, from: nil)
        let region = NSRect(x: 0, y: r.minY - 22, width: root.bounds.width, height: r.height + 44).intersection(root.bounds)
        guard let rep = root.bitmapImageRepForCachingDisplay(in: region) else { return nil }
        root.cacheDisplay(in: region, to: rep)
        TabsTally.crops += 1
        let file = String(format: "T%02d-%@-%@.png", TabsTally.crops, scenario, name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: " ", with: "_"))
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        try? data.write(to: out.appendingPathComponent(file))
        return file
    }

    // MARK: 탭 클릭 (실제 좌표)
    //
    // SwiftUI 의 탭 제스처(클릭·더블클릭·×)는 창의 sendEvent 를 거친 이벤트에만 반응한다 — 히트 테스트로 찾은 뷰나 호스팅 뷰에 mouseDown/Up 을 직접 줘도,
    // 앱 큐에 넣고 지역 모니터로 가로채 뷰에 줘도 반응이 없었다(실측). 그런데 비활성 앱의 보통 창에 mouseDown 을 sendEvent 하면 AppKit 이 그 창을 앞으로
    // 올리고 앱을 활성화하려 든다(사용자의 포커스를 뺏는다). 그래서 탭 줄을 하나 더 만들어 **활성화하지 않는 패널**(.nonactivatingPanel, 화면 밖)에 얹고
    // 거기에 클릭을 보낸다 — 같은 뷰 코드(DocumentTabBar · DocumentTab)가 같은 모델을 움직이므로 제스처 배선과 반응 시간을 그대로 잰다.

    enum TabSpot { case label, close }
    private static var probePanel: NSPanel?
    /// 클릭을 보낸 뒤 앱이 활성화된 적이 있는가 — 한 번이라도 그러면 더는 클릭을 보내지 않는다
    private(set) static var clickActivatedApp = false
    /// 마지막 clickTab 이 첫 누름부터 마지막 뗌까지 실제로 걸린 시간(ms) — 기계가 바빠 더블클릭 간격을 넘겼는지 가린다
    private(set) static var lastClickSpanMs = 0.0

    /// 탭 줄 사본을 얹은 화면 밖 패널 (없으면 만든다)
    @discardableResult
    func tabProbe() -> NSPanel {
        if let p = Self.probePanel { return p }
        let p = ProbePanel(contentRect: NSRect(x: -30_000, y: -30_000, width: 1100, height: 26), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.becomesKeyOnlyIfNeeded = true
        p.hidesOnDeactivate = false      // 앱이 비활성이어도 떠 있어야 SwiftUI 가 그린다
        p.isReleasedWhenClosed = false
        p.contentView = NSHostingView(rootView: ProbeTabBar(model: model))
        p.orderBack(nil)
        Self.probePanel = p
        return p
    }

    func closeTabProbe() { Self.probePanel?.orderOut(nil); Self.probePanel = nil }

    /// 탭 줄이 **처음 나타날 때** 활성 탭이 보이는가 (지난 세션의 탭이 많은 채 시작하는 경우 — 하네스는 앱을 다시 띄울 수 없으므로 사본 탭 줄을 새로 만들어 본다)
    func checkFreshTabBarShowsActiveTab(_ why: String) async {
        TabsTally.checks += 1
        closeTabProbe()
        let panel = tabProbe()
        await settle(600)
        panel.contentView?.layoutSubtreeIfNeeded()
        defer { closeTabProbe() }
        let cs = tabCatchers(in: panel.contentView)
        guard cs.count == model.tabs.count, let i = model.tabs.firstIndex(of: model.document.url), let sv = cs[i].enclosingScrollView else {
            note("\(why): the fresh tab bar is not ready (\(cs.count) of \(model.tabs.count) tabs)"); return
        }
        let f = cs[i].convert(cs[i].bounds, to: nil), vp = sv.convert(sv.bounds, to: nil)
        if f.minX < vp.minX - 0.5 || f.maxX > vp.maxX + 0.5 {
            issue("tabbar", "\(why): a tab bar that has just appeared shows x \(Int(vp.minX))…\(Int(vp.maxX)) but the active tab '\(model.tabs[i].lastPathComponent)' (\(i + 1) of \(cs.count)) is at \(Int(f.minX))…\(Int(f.maxX))", snap: false)
        }
    }

    private func probeMouse(_ type: NSEvent.EventType, _ p: NSPoint, clicks: Int, in panel: NSPanel) -> NSEvent? {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                           context: nil, eventNumber: 0, clickCount: clicks, pressure: type == .leftMouseUp ? 0 : 1)
    }

    /// 사본 탭 줄에서 탭의 이름(또는 × 버튼) 자리를 클릭한다. 반환: 클릭을 보냈는가
    @discardableResult
    func clickTab(_ url: URL, spot: TabSpot = .label, clicks: Int = 1) async -> Bool {
        guard !Self.clickActivatedApp else { return false }
        let panel = tabProbe()
        let cs = tabCatchers(in: panel.contentView)
        guard cs.count == model.tabs.count, let i = model.tabs.firstIndex(of: url) else { return false }
        let f = cs[i].convert(cs[i].bounds, to: nil)
        let p = NSPoint(x: spot == .label ? min(f.minX + 40, f.midX) : f.maxX - 14, y: f.midY)
        if let sv = cs[i].enclosingScrollView {
            let vp = sv.convert(sv.bounds, to: nil)
            guard p.x > vp.minX + 1, p.x < vp.maxX - 1 else { return false }   // 사본의 스크롤 영역 밖에 있는 탭
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        for n in 1...max(1, clicks) {
            guard let down = probeMouse(.leftMouseDown, p, clicks: n, in: panel), let up = probeMouse(.leftMouseUp, p, clicks: n, in: panel) else { return false }
            panel.sendEvent(down)
            try? await Task.sleep(nanoseconds: 30_000_000)   // 누르고 있는 시간
            panel.sendEvent(up)
            if n < clicks { try? await Task.sleep(nanoseconds: 60_000_000) }
        }
        Self.lastClickSpanMs = elapsedMs(since: t0)
        await turn()
        if NSApp.isActive {   // 일어나면 안 되는 일 — 바로 물러나고 더는 클릭하지 않는다
            Self.clickActivatedApp = true
            NSApp.deactivate()
            log("  a synthetic click on the probe panel activated the app — deactivated; no more clicks will be sent")
        }
        return true
    }

    /// 탭을 클릭하고 그 탭이 활성화될 때까지 걸린 시간(ms). 클릭을 못 보냈거나 `timeout` 안에 바뀌지 않으면 nil
    func clickTabAndWait(_ url: URL, timeout: Double = 1500) async -> Double? {
        let t0 = CFAbsoluteTimeGetCurrent()
        guard await clickTab(url) else { return nil }
        while model.document.url != url {
            if elapsedMs(since: t0) > timeout { return nil }
            try? await Task.sleep(nanoseconds: 4_000_000)
        }
        return elapsedMs(since: t0)
    }

    /// 탭을 가운데 버튼으로 누른다 (받이 뷰에 직접 — 받이의 hitTest 는 NSApp.currentEvent 를 보므로 합성 이벤트로는 지나갈 수 없다)
    @discardableResult
    func middleClickTab(_ url: URL) async -> Bool {
        let cs = tabCatchers()
        guard cs.count == model.tabs.count, let i = model.tabs.firstIndex(of: url) else { return false }
        let f = cs[i].convert(cs[i].bounds, to: nil)
        let onScreen = window.convertPoint(toScreen: NSPoint(x: f.midX, y: f.midY))
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        guard let cg = CGEvent(mouseEventSource: nil, mouseType: .otherMouseDown, mouseCursorPosition: CGPoint(x: onScreen.x, y: screenH - onScreen.y), mouseButton: .center),
              let e = NSEvent(cgEvent: cg) else { return false }
        cs[i].otherMouseDown(with: e)
        await turn()
        return true
    }

    /// ⌃Tab / ⌃⇧Tab — 앱의 이벤트 큐에 넣어 AppDelegate 의 지역 키 모니터를 지나게 한다 (다른 앱에는 가지 않는다)
    func controlTab(shift: Bool = false) async {
        var flags: NSEvent.ModifierFlags = [.control]
        if shift { flags.insert(.shift) }
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                       context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48) else { return }
        NSApp.postEvent(e, atStart: false)
        await settle(120)
    }

    // MARK: 보기 위치

    struct ViewMark { let caret: Int; let top: Int; let anchor: (offset: Int, y: CGFloat)?; let length: Int }

    func mark() -> ViewMark { ViewMark(caret: caret, top: topLine(), anchor: anchor(), length: length) }

    /// 탭으로 돌아왔을 때: 글 길이·캐럿이 그대로이고, 떠날 때 화면 가운데 있던 문단이 같은 높이에 있는가
    func checkReturned(to m: ViewMark, _ why: String) {
        TabsTally.checks += 1
        if length != m.length { issue("text", "\(why): document length \(length), was \(m.length) when the tab was left") }
        if caret != m.caret { issue("caret", "\(why): caret at offset \(caret), was \(m.caret) when the tab was left") }
        guard let a = m.anchor else { return }
        if let y = screenY(ofFragmentAt: a.offset) {
            if abs(y - a.y) > 2 { issue("viewport-jump", "\(why): the paragraph at offset \(a.offset) was \(Int(a.y)) pt below the top of the view and is now at \(Int(y)) pt (top line \(m.top) → \(topLine()))") }
        } else {
            issue("viewport-jump", "\(why): the view showed line \(m.top) at the top when the tab was left and shows line \(topLine()) now (the paragraph at offset \(a.offset) is no longer on screen)")
        }
    }

    func tallyNote() { log("  tabs: \(TabsTally.checks) tab checks so far, \(TabsTally.crops) tab-bar crops") }

    /// 검색이 끝날 때까지 (완료 횟수가 오를 때까지) 기다린다
    func waitSearch(after count: Int, timeout: Double = 3000) async {
        let t0 = CFAbsoluteTimeGetCurrent()
        while model.searchCompletionCount == count, elapsedMs(since: t0) < timeout { try? await Task.sleep(nanoseconds: 10_000_000) }
        await settle(60)
    }

    /// 접힌 영역 수 (머리 줄 뒤의 ⋯ 표식 수)
    func foldCount() -> Int { tv.foldPills?(NSRange(location: 0, length: length)).count ?? 0 }
}

// MARK: - 시나리오

extension RealUse {
    @MainActor static let tabsScenarios: [Scenario] = [
        // 탭 줄의 모양: 탭 몇 개 · 수정됨 점 · 긴 이름 · 20개 넘는 탭 · 라이트/다크. 걸음마다 좌표 검사 + 탭 줄만 자른 PNG
        Scenario(name: "tabs-bar") { ctx in
            let m = ctx.model
            let theme0 = m.themes.current.id
            let start = m.document.url
            ctx.at("three tabs")
            let a = await ctx.openNumbered("alpha.md", lines: 400)
            _ = await ctx.openNumbered("beta.txt", lines: 400)
            _ = await ctx.openNumbered("gamma.log", lines: 400)
            await ctx.settle(200)
            ctx.log("  theme \(theme0), tab frames \(ctx.tabFrames().map { "\(Int($0.minX))…\(Int($0.maxX))" }), strip \(ctx.tabStripViewport().map { "\(Int($0.minX))…\(Int($0.maxX))" } ?? "nil"), window \(Int(ctx.window.frame.width))")
            ctx.checkTabBar("3 tabs, last active"); ctx.checkTabs("3 tabs"); ctx.snapTabBar("few-last-active"); ctx.snap("few")
            m.activateTab(a); await ctx.settle(300)
            ctx.checkTabBar("3 tabs, first of the new ones active"); ctx.snapTabBar("few-first-active")
            ctx.at("dirty dot")
            await ctx.type("x"); await ctx.settle(100)
            ctx.checkTabBar("active tab dirty"); ctx.snapTabBar("few-dirty")
            await ctx.key(.delete); await ctx.settle(100)
            for id in [ThemeStore.defaultLightID, ThemeStore.defaultDarkID] {
                ctx.at("three tabs · \(id)")
                m.themes.select(id: id); await ctx.settle(400)
                ctx.checkTabBar("3 tabs in \(id)"); ctx.snapTabBar("few-\(id)")
            }
            ctx.at("long names")
            _ = await ctx.openNumbered("회의록-2026-11-24-분기-계획-검토-및-후속-조치-정리-아주-긴-파일-이름의-예시-문서.md", lines: 40)
            let long2 = await ctx.openNumbered("a-very-long-file-name-that-keeps-going-and-going-to-see-how-the-tab-strip-copes-with-it-v2-final-FINAL.txt", lines: 40)
            await ctx.settle(200)
            ctx.checkTabBar("long names, last active"); ctx.snapTabBar("long-dark-last-active")
            m.activateTab(a); await ctx.settle(300)
            ctx.checkTabBar("long names, alpha active"); ctx.snapTabBar("long-dark-alpha-active")
            m.themes.select(id: ThemeStore.defaultLightID); await ctx.settle(400)
            ctx.snapTabBar("long-light-alpha-active")
            m.activateTab(long2); await ctx.settle(300)
            ctx.checkTabBar("long names, long2 active"); ctx.snapTabBar("long-light-last-active")
            ctx.at("many tabs")
            for i in 1...16 { _ = await ctx.openNumbered(String(format: "note-%02d.md", i), lines: 30) }
            await ctx.settle(300)
            ctx.note("\(m.tabs.count) tabs, strip \(ctx.tabStripViewport().map { "\(Int($0.minX))…\(Int($0.maxX))" } ?? "nil"), tabs span \(Int(ctx.tabFrames().first?.minX ?? 0))…\(Int(ctx.tabFrames().last?.maxX ?? 0))")
            ctx.checkTabBar("\(m.tabs.count) tabs, the newest (last) active"); ctx.snapTabBar("many-light-last-active"); ctx.snap("many-light")
            await ctx.checkFreshTabBarShowsActiveTab("\(m.tabs.count) tabs, the last one active")
            if let first = m.tabs.first { m.activateTab(first); await ctx.settle(300); ctx.checkTabBar("many tabs, first active"); ctx.snapTabBar("many-light-first-active") }
            let mid = m.tabs[m.tabs.count / 2]
            m.activateTab(mid); await ctx.settle(300); ctx.checkTabBar("many tabs, middle active"); ctx.snapTabBar("many-light-middle-active")
            ctx.at("cycle with next tab")
            for _ in 0..<m.tabs.count {
                m.nextTab(); await ctx.settle(150)
                ctx.checkTabBar("next tab → \(m.document.url.lastPathComponent)")
            }
            ctx.at("cycle with previous tab")
            for _ in 0..<6 { m.previousTab(); await ctx.settle(150); ctx.checkTabBar("previous tab → \(m.document.url.lastPathComponent)") }
            ctx.at("sort and move with many tabs")
            m.activateTab(a); await ctx.settle(300)
            m.sortTabs(by: .name); await ctx.settle(300)
            ctx.checkTabBar("after sort by name (active \(m.document.url.lastPathComponent))"); ctx.checkTabs("after sort by name")
            m.moveTab(a, to: m.tabs.count); await ctx.settle(300)
            ctx.checkTabBar("after moving the active tab to the end"); ctx.snapTabBar("many-light-moved-to-end")
            m.moveTab(a, to: 0); await ctx.settle(300)
            ctx.checkTabBar("after moving the active tab to the front")
            ctx.at("close with many tabs")
            m.moveTab(start, to: 0)   // 시작 문서는 닫지 않는다 (다음 시나리오의 바탕)
            if let last = m.tabs.last { m.activateTab(last); await ctx.settle(300) }
            for _ in 0..<5 { m.closeTab(m.document.url); await ctx.settle(200); ctx.checkTabBar("after closing the last tab (now \(m.tabs.count))") }
            m.themes.select(id: ThemeStore.defaultDarkID); await ctx.settle(400)
            ctx.checkTabBar("many tabs dark"); ctx.snapTabBar("many-dark"); ctx.snap("many-dark")
            m.themes.select(id: theme0); await ctx.settle(300)
            ctx.tallyNote()
        },

        // 탭마다 다른 곳으로 스크롤·캐럿 이동 → 오가며 내용·캐럿·보기 위치가 유지되는가 (기다렸다 전환 / 바로 전환 / 캐럿에서 멀리 스크롤한 채 전환)
        Scenario(name: "tabs-switch-keep") { ctx in
            let m = ctx.model
            ctx.at("open four files")
            let a = await ctx.openNumbered("keep-a.md", lines: 3000)
            var b = a
            await ctx.withRelaxedStalls { b = await ctx.open(.notes, name: "keep-notes.md").resolvingSymlinksInPath() }
            let c = await ctx.open(.wide, name: "keep-wide.md").resolvingSymlinksInPath()
            let d = await ctx.open(.small, name: "keep-small.md").resolvingSymlinksInPath()
            var marks: [URL: RealUseContext.ViewMark] = [:]
            @MainActor func go(_ u: URL, wait ms: UInt64 = 350) async {
                if u == b { await ctx.withRelaxedStalls { m.activateTab(u); await ctx.settle(ms) } } else { m.activateTab(u); await ctx.settle(ms) }
            }

            ctx.at("place: numbered file, line 1500")
            await go(a)
            m.jump(toLine: 1500); await ctx.settle(250)
            await ctx.key(.down, count: 7); await ctx.key(.right, count: 5); await ctx.settle(1000)
            marks[a] = ctx.mark(); ctx.checkAll("a placed"); ctx.checkCaretVisible("a placed")
            ctx.at("place: notes, 40 lines above the end")
            await go(b)
            await ctx.key(.down, [.command]); await ctx.settle(200)
            await ctx.key(.up, count: 40); await ctx.settle(1000)
            marks[b] = ctx.mark(); ctx.checkAll("notes placed"); ctx.checkCaretVisible("notes placed")
            ctx.at("place: wrapped file, line 900")
            await go(c)
            m.jump(toLine: 900); await ctx.settle(250)
            await ctx.key(.down, count: 3); await ctx.settle(1000)
            marks[c] = ctx.mark(); ctx.checkAll("wide placed"); ctx.checkCaretVisible("wide placed")
            ctx.at("place: small file, near the top")
            await go(d)
            await ctx.key(.up, [.command]); await ctx.key(.right, count: 30); await ctx.settle(1000)
            marks[d] = ctx.mark(); ctx.checkAll("small placed")
            for (u, mk) in [(a, marks[a]!), (b, marks[b]!), (c, marks[c]!), (d, marks[d]!)] {
                ctx.log("  placed \(u.lastPathComponent): caret \(mk.caret), top line \(mk.top), anchor \(mk.anchor.map { "\($0.offset)@\(Int($0.y))" } ?? "nil")")
            }

            // 1) 보기 위치가 저장된(0.8 s) 뒤에 오간다
            for (n, u) in [a, b, c, d, b, a, c, d].enumerated() {
                ctx.at("return #\(n + 1) to \(u.lastPathComponent) (after waiting)")
                await go(u, wait: 400)
                ctx.checkReturned(to: marks[u]!, "back on \(u.lastPathComponent)")
                ctx.checkAll("back on \(u.lastPathComponent)"); ctx.checkInk("back on \(u.lastPathComponent)"); ctx.checkTabs("back on \(u.lastPathComponent)")
                if n < 4 { ctx.snap("return-\(u.deletingPathExtension().lastPathComponent)") }
                await ctx.settle(700)
            }

            // 2) 캐럿을 옮기고 조금 스크롤한 뒤 0.8 s 가 지나기 전에 바로 전환
            for u in [a, c, d, b] {
                ctx.at("move and leave at once: \(u.lastPathComponent)")
                await go(u, wait: 400)
                await ctx.key(.down, count: 12); await ctx.scrollBy(54); await ctx.settle(0)
                marks[u] = ctx.mark()
            }
            for u in [a, c, d, b] {
                ctx.at("return to \(u.lastPathComponent) (left at once)")
                await go(u, wait: 400)
                ctx.checkReturned(to: marks[u]!, "back on \(u.lastPathComponent) after leaving at once")
                ctx.checkAll("back on \(u.lastPathComponent) (left at once)"); ctx.checkInk("back on \(u.lastPathComponent) (left at once)")
            }

            // 3) 휠로 캐럿에서 멀리 스크롤해 읽다가 전환 — 돌아오면 읽던 곳이어야 한다
            for u in [a, c] {
                ctx.at("scrolled away from the caret: \(u.lastPathComponent)")
                await go(u, wait: 400)
                for _ in 0..<10 { await ctx.scrollBy(300) }
                await ctx.settle(100)
                let away = ctx.mark()
                ctx.note("caret \(away.caret) is off screen; top line \(away.top)")
                await go(d, wait: 300)
                await go(u, wait: 500)
                ctx.checkReturned(to: away, "back on \(u.lastPathComponent) after reading away from the caret")
                ctx.checkAll("back on \(u.lastPathComponent) (scrolled away)"); ctx.checkInk("back on \(u.lastPathComponent) (scrolled away)")
                ctx.snap("scrolled-away-\(u.deletingPathExtension().lastPathComponent)")
            }
            ctx.tallyNote()
        },

        // 편집하고 바로 전환: 저장·복귀·undo, 한글 조합 중 전환, 자동 저장이 도는 중 전환, 밖에서 바뀐 파일
        Scenario(name: "tabs-edit-switch") { ctx in
            let m = ctx.model
            let a = await ctx.openNumbered("edit-a.md", lines: 500)
            let b = await ctx.openNumbered("edit-b.md", lines: 500)
            let none = NSRange(location: NSNotFound, length: 0)

            ctx.at("type and switch at once")
            m.jump(toLine: 100); await ctx.settle(200)
            await ctx.type("EDIT-1 바로 전환 ")
            let expect1 = ctx.text.copy() as! NSString
            let caret1 = ctx.caret
            if !m.document.isDirty { ctx.issue("dirty", "typed into edit-b.md but the document is not dirty") }
            m.activateTab(a)
            let disk1 = (try? String(contentsOf: b, encoding: .utf8)) ?? ""
            if !expect1.isEqual(to: disk1) { ctx.issue("save", "left the edited tab: the file on disk has \((disk1 as NSString).length) units, the editor had \(expect1.length)") }
            await ctx.settle(350)
            ctx.checkTabs("on a after leaving the edited b"); ctx.checkAll("on a after leaving the edited b")
            if !ctx.text.hasPrefix("# edit-a") { ctx.issue("text", "tab a shows '\(ctx.text.substring(to: min(12, ctx.length)))'") }
            m.activateTab(b); await ctx.settle(400)
            if !ctx.text.isEqual(to: expect1 as String) { ctx.issue("text", "back on b: \(ctx.length) units, expected the edited \(expect1.length)") }
            if ctx.caret != caret1 { ctx.issue("caret", "back on b: caret \(ctx.caret), was \(caret1) right after typing") }
            if m.document.isDirty { ctx.issue("dirty", "back on b: the document is dirty although nothing was typed since the switch") }
            ctx.checkCaretVisible("back on the edited tab"); ctx.checkAll("back on the edited tab")
            ctx.at("undo after coming back")
            await ctx.shortcut("z"); await ctx.settle(150)
            ctx.note("⌘Z after returning: length \(expect1.length) → \(ctx.length) (the undo stack is cleared on a switch)")
            if ctx.length != expect1.length, !ctx.text.hasPrefix("# edit-b") { ctx.issue("text", "⌘Z after returning to b replaced its content with something else (\(ctx.length) units, starts '\(ctx.text.substring(to: min(12, ctx.length)))')") }
            ctx.checkTabs("after ⌘Z on b")

            ctx.at("switch during hangul composition")
            m.jump(toLine: 200); await ctx.settle(200)
            await ctx.type("조합 ")
            for st in ["ㅎ", "하", "한"] {
                ctx.tv.setMarkedText(st, selectedRange: NSRange(location: (st as NSString).length, length: 0), replacementRange: none)
                await ctx.turn()
            }
            ctx.note("composing: hasMarkedText \(ctx.tv.hasMarkedText()), marked range \(ctx.tv.markedRange())")
            m.activateTab(a); await ctx.settle(350)
            if ctx.tv.hasMarkedText() { ctx.issue("ime", "after switching to \(m.document.url.lastPathComponent) the text view still has marked text \(ctx.tv.markedRange()) from the other file") }
            let lenA = ctx.length, caretA = ctx.caret
            let beforeA = ctx.text.copy() as! NSString
            await ctx.type("Z"); await ctx.settle(60)
            if ctx.length != lenA + 1 || caretA >= ctx.length || ctx.text.substring(with: NSRange(location: caretA, length: 1)) != "Z" {
                ctx.issue("ime", "typed one letter after switching away mid-composition: length \(lenA) → \(ctx.length), caret \(caretA) → \(ctx.caret)")
            }
            await ctx.key(.delete); await ctx.settle(60)
            if !ctx.text.isEqual(to: beforeA as String) { ctx.issue("text", "typing Z and deleting it on tab a did not give the original text back (\(beforeA.length) → \(ctx.length))") }
            let disk2 = (try? String(contentsOf: b, encoding: .utf8)) ?? ""
            ctx.note("edit-b.md on disk after the mid-composition switch \(disk2.contains("조합 한") ? "has" : "does not have") the composed syllable")
            m.activateTab(b); await ctx.settle(350)
            if ctx.tv.hasMarkedText() { ctx.issue("ime", "back on b the text view has marked text \(ctx.tv.markedRange())") }
            if !ctx.text.contains("조합 ") { ctx.issue("text", "back on b: the text typed before composing is gone") }
            ctx.checkTabs("back on b after the composition switch"); ctx.checkAll("back on b after the composition switch")

            ctx.at("switch while autosave is in flight")
            m.jump(toLine: 300); await ctx.settle(200)
            await ctx.type("AUTO-1 ")
            try? await Task.sleep(nanoseconds: 2_010_000_000)   // 자동 저장(2 s)이 막 시작됐을 때
            await ctx.type("AUTO-2 ", turnEvery: 100)
            let expect3 = ctx.text.copy() as! NSString
            m.activateTab(a)
            let disk3 = (try? String(contentsOf: b, encoding: .utf8)) ?? ""
            if !expect3.isEqual(to: disk3) { ctx.issue("save", "switched while the autosave was running: disk has \((disk3 as NSString).length) units, the editor had \(expect3.length) (AUTO-2 \(disk3.contains("AUTO-2") ? "saved" : "lost"))") }
            await ctx.settle(700)
            let disk3b = (try? String(contentsOf: b, encoding: .utf8)) ?? ""
            if !expect3.isEqual(to: disk3b) { ctx.issue("save", "0.7 s after the switch a late save changed edit-b.md on disk (\((disk3b as NSString).length) units, expected \(expect3.length))") }
            ctx.checkTabs("on a after the autosave race")
            m.activateTab(b); await ctx.settle(350)
            if !ctx.text.isEqual(to: expect3 as String) { ctx.issue("text", "back on b after the autosave race: \(ctx.length) units, expected \(expect3.length)") }
            ctx.checkTabs("back on b after the autosave race")

            ctx.at("inactive tab changed on disk")
            m.activateTab(a); await ctx.settle(1700)   // 우리 저장 직후 1.5 s 는 파일 감시가 무시한다
            let ext = (expect3 as String) + "EXTERNAL-INACTIVE\n"
            try? ext.write(to: b, atomically: true, encoding: .utf8)
            await ctx.settle(300)
            if !ctx.text.hasPrefix("# edit-a") { ctx.issue("text", "an external change to the inactive tab's file changed the active editor") }
            m.activateTab(b); await ctx.settle(350)
            if !ctx.text.hasSuffix("EXTERNAL-INACTIVE\n") { ctx.issue("text", "the inactive tab's file changed on disk but switching to it shows the old content") }
            ctx.checkTabs("on b after its file changed while inactive"); ctx.checkAll("on b after its file changed while inactive")

            ctx.at("active tab changed on disk")
            m.jump(toLine: 150); await ctx.settle(300)
            await ctx.key(.down, count: 4); await ctx.settle(900)
            let ext2 = ext + "EXTERNAL-ACTIVE\n"
            let beforeExternal = ctx.mark()
            try? ext2.write(to: b, atomically: true, encoding: .utf8)
            await ctx.settle(1200)
            if !ctx.text.hasSuffix("EXTERNAL-ACTIVE\n") { ctx.issue("text", "the active file changed on disk (not dirty) but the editor was not reloaded within 1.2 s") }
            // 다른 도구가 파일 끝에 덧붙였다 — 읽던 자리(캐럿·화면)는 그대로여야 한다
            if ctx.caret != beforeExternal.caret { ctx.issue("caret", "another program appended to the open file: the caret jumped from offset \(beforeExternal.caret) (line 154) to \(ctx.caret) of \(ctx.length)") }
            if let a = beforeExternal.anchor {
                if let y = ctx.screenY(ofFragmentAt: a.offset) { if abs(y - a.y) > 2 { ctx.issue("viewport-jump", "another program appended to the open file: the paragraph at offset \(a.offset) moved from \(Int(a.y)) pt to \(Int(y)) pt on screen") } }
                else { ctx.issue("viewport-jump", "another program appended to the open file: the view jumped from line \(beforeExternal.top) to line \(ctx.topLine())") }
            }
            ctx.checkTabs("after the active file changed on disk"); ctx.checkAll("after the active file changed on disk"); ctx.checkInk("after the active file changed on disk")
            ctx.tallyNote()
        },

        // 닫기 규칙·다시 열기·순환·직전 탭·이동·정렬·사라진 파일·마지막 탭 → 기본 문서. 메뉴 단축키(⌘W ⌘⇧T ⌘⇧] ⌘⇧[)와 ⌃Tab 은 실제 키 경로로
        Scenario(name: "tabs-close-rules") { ctx in
            let m = ctx.model
            let start = m.document.url
            let a = await ctx.openNumbered("rule-a.md", lines: 60)
            let b = await ctx.openNumbered("rule-b.txt", lines: 60)
            let c = await ctx.openNumbered("rule-c.md", lines: 60)
            let d = await ctx.openNumbered("rule-d.log", lines: 60)
            let e = await ctx.openNumbered("rule-e.md", lines: 60)
            ctx.at("opened five"); ctx.expectTabs([start, a, b, c, d, e], active: e, "five files opened")

            ctx.at("close active middle tab → left neighbour")
            m.activateTab(c); await ctx.settle(250)
            m.closeTab(c); await ctx.settle(300)
            ctx.expectTabs([start, a, b, d, e], active: b, "closed the active c"); ctx.checkAll("closed the active c")
            ctx.at("close inactive tab")
            m.closeTab(e); await ctx.settle(250)
            ctx.expectTabs([start, a, b, d], active: b, "closed the inactive e")
            ctx.at("close active leftmost tab → new first")
            m.activateTab(start); await ctx.settle(250)
            m.closeTab(start); await ctx.settle(300)
            ctx.expectTabs([a, b, d], active: a, "closed the active leftmost tab")
            ctx.at("reopen last closed ×4")
            m.reopenLastClosedTab(); await ctx.settle(300)
            ctx.expectTabs([a, b, d, start], active: start, "reopen #1")
            m.reopenLastClosedTab(); await ctx.settle(300)
            ctx.expectTabs([a, b, d, start, e], active: e, "reopen #2")
            m.reopenLastClosedTab(); await ctx.settle(300)
            ctx.expectTabs([a, b, d, start, e, c], active: c, "reopen #3")
            m.reopenLastClosedTab(); await ctx.settle(300)
            ctx.expectTabs([a, b, d, start, e, c], active: c, "reopen with nothing left to reopen")

            ctx.at("⌘W closes the active tab")
            let handledW = await ctx.shortcut("w")
            await ctx.turn()
            if ctx.model.session.primary?.textView?.window == nil { ctx.issue("tabs", "⌘W with six tabs closed the window instead of the tab", snap: false); return }
            await ctx.settle(300)
            if !handledW { ctx.note("⌘W key equivalent not handled by the menu (app inactive) — calling closeActiveTab()"); m.closeActiveTab(); await ctx.settle(300) }
            ctx.expectTabs([a, b, d, start, e], active: e, "⌘W on c")
            ctx.at("⌘⇧T reopens it")
            if !(await ctx.shortcut("t", [.command, .shift])) { ctx.note("⌘⇧T not handled by the menu — calling reopenLastClosedTab()"); m.reopenLastClosedTab() }
            await ctx.settle(300)
            ctx.expectTabs([a, b, d, start, e, c], active: c, "⌘⇧T")
            ctx.at("⌘⇧] wraps to the first, ⌘⇧[ back to the last")
            if !(await ctx.shortcut("]", [.command, .shift])) { ctx.note("⌘⇧] not handled by the menu — calling nextTab()"); m.nextTab() }
            await ctx.settle(300)
            ctx.expectTabs([a, b, d, start, e, c], active: a, "⌘⇧] from the last tab")
            if !(await ctx.shortcut("[", [.command, .shift])) { ctx.note("⌘⇧[ not handled by the menu — calling previousTab()"); m.previousTab() }
            await ctx.settle(300)
            ctx.expectTabs([a, b, d, start, e, c], active: c, "⌘⇧[ from the first tab")

            ctx.at("⌃Tab toggles between the two most recent")
            m.activateTab(b); await ctx.settle(250); m.activateTab(d); await ctx.settle(250)
            let lenD = ctx.length
            await ctx.controlTab()
            if m.document.url != b {
                ctx.note("⌃Tab posted to the app queue did not switch (now \(m.document.url.lastPathComponent), length \(lenD) → \(ctx.length)) — calling activateLastActiveTab()")
                if m.document.url == d, ctx.length != lenD { ctx.issue("tabs", "⌃Tab reached the editor as a key and changed the text (\(lenD) → \(ctx.length))") }
                m.activateLastActiveTab(); await ctx.settle(250)
            }
            ctx.expectTabs([a, b, d, start, e, c], active: b, "⌃Tab from d")
            await ctx.controlTab()
            if m.document.url != d { m.activateLastActiveTab(); await ctx.settle(250) }
            ctx.expectTabs([a, b, d, start, e, c], active: d, "⌃Tab again")
            await ctx.controlTab(shift: true)
            if m.document.url != b { m.previousTab(); await ctx.settle(250) }
            ctx.expectTabs([a, b, d, start, e, c], active: b, "⌃⇧Tab from d (previous in order)")
            ctx.at("last-active skips a closed tab")
            m.activateTab(e); await ctx.settle(200); m.activateTab(a); await ctx.settle(200)
            m.closeTab(e); await ctx.settle(200)          // 직전 탭이 닫혔다 → 그 앞에 보던 b 로
            m.activateLastActiveTab(); await ctx.settle(250)
            ctx.expectTabs([a, b, d, start, c], active: b, "last-active after the previous tab was closed")

            ctx.at("move")
            m.moveTab(c, to: 0); await ctx.settle(150)
            ctx.expectTabs([c, a, b, d, start], active: b, "moved c to the front")
            m.moveTab(c, to: 99); await ctx.settle(150)
            ctx.expectTabs([a, b, d, start, c], active: b, "moved c past the end")
            m.moveTab(e, to: 0); await ctx.settle(150)
            ctx.expectTabs([a, b, d, start, c], active: b, "moving a closed tab does nothing")
            ctx.at("sort")
            m.sortTabs(by: .name); await ctx.settle(150)
            let byName = [a, b, c, d, start].sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            ctx.expectTabs(byName, active: b, "sort by name")
            m.sortTabs(by: .ext); await ctx.settle(150)
            if m.tabs.map(\.pathExtension) != m.tabs.map(\.pathExtension).sorted() { ctx.issue("tabs", "sort by extension gave \(m.tabs.map(\.lastPathComponent))") }
            ctx.checkTabs("sort by extension")
            m.sortTabs(by: .path); await ctx.settle(150)
            if m.tabs.map(\.path) != m.tabs.map(\.path).sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) { ctx.issue("tabs", "sort by path gave \(m.tabs.map(\.path))") }
            ctx.checkTabs("sort by path")
            m.sortTabs(by: .modified); await ctx.settle(150)
            ctx.checkTabs("sort by modification date")
            m.sortTabs(by: .name); await ctx.settle(150)   // a b c d start

            ctx.at("close to the left / right")
            m.reopenLastClosedTab(); await ctx.settle(300)          // e 가 맨 끝에, 활성
            m.sortTabs(by: .name); await ctx.settle(150)            // a b c d e start
            m.activateTab(a); await ctx.settle(250)
            m.closeTabs(toLeftOf: c); await ctx.settle(300)         // a(활성) b 가 닫힌다 → c 로
            ctx.expectTabs([c, d, e, start], active: c, "close tabs to the left of c (the active a was among them)")
            m.activateTab(start); await ctx.settle(250)
            m.closeTabs(toRightOf: d); await ctx.settle(300)        // e start(활성) 가 닫힌다 → d 로
            ctx.expectTabs([c, d], active: d, "close tabs to the right of d (the active start was among them)")
            m.closeTabs(toLeftOf: c); m.closeTabs(toRightOf: d); await ctx.settle(150)
            ctx.expectTabs([c, d], active: d, "close to the left of the first / right of the last does nothing")

            ctx.at("close other tabs")
            m.open(url: a); await ctx.settle(300); m.open(url: b); await ctx.settle(300)   // c d a b, 활성 b
            m.closeOtherTabs(except: c); await ctx.settle(300)
            ctx.expectTabs([c], active: c, "close other tabs except the inactive c")
            m.open(url: a); await ctx.settle(300); m.open(url: b); await ctx.settle(300)   // c a b, 활성 b
            m.closeOtherTabs(); await ctx.settle(300)
            ctx.expectTabs([b], active: b, "close other tabs (keep the active b)")

            ctx.at("a tab whose file is gone")
            m.open(url: a); await ctx.settle(300); m.open(url: c); await ctx.settle(300); m.open(url: d); await ctx.settle(300)   // b a c d, 활성 d
            try? FileManager.default.removeItem(at: a)
            m.activateTab(a); await ctx.settle(300)
            if FileManager.default.fileExists(atPath: a.path) { ctx.issue("tabs", "clicking the tab of a deleted file created an empty file at its path") }
            ctx.expectTabs([b, c, d], active: d, "clicked the tab of a deleted file")
            try? FileManager.default.removeItem(at: c)          // 활성 d 의 왼쪽 이웃이 사라졌다
            m.closeTab(d); await ctx.settle(300)
            if FileManager.default.fileExists(atPath: c.path) { ctx.issue("tabs", "closing a tab re-created its deleted left neighbour as an empty file") }
            ctx.expectTabs([b], active: b, "closed d whose left neighbour's file was deleted")
            ctx.at("the active tab's file deleted, then switch away")
            m.open(url: d); await ctx.settle(300)               // b d, 활성 d (디스크에 있다)
            try? FileManager.default.removeItem(at: d)
            await ctx.settle(500)
            m.activateTab(b); await ctx.settle(300)
            if FileManager.default.fileExists(atPath: d.path) { ctx.issue("tabs", "leaving the (unedited) tab of a deleted file re-created the file") }
            ctx.note("after leaving the deleted d: tabs \(m.tabs.map(\.lastPathComponent)), active \(m.document.url.lastPathComponent)")
            ctx.checkTabs("after leaving the tab of a deleted file")
            m.activateTab(d); await ctx.settle(300)
            ctx.expectTabs([b], active: b, "clicked the stale tab of the deleted d")

            ctx.at("last tab → default document")
            let def = m.defaultDocumentURL
            m.closeTab(b); await ctx.settle(400)
            ctx.expectTabs([def], active: def, "closed the last tab")
            if !FileManager.default.fileExists(atPath: def.path) { ctx.issue("tabs", "the default document was not created") }
            ctx.checkAll("default document after closing the last tab"); ctx.checkInk("default document after closing the last tab")
            m.closeTab(def); await ctx.settle(200)
            ctx.expectTabs([def], active: def, "closing the default document when it is the only tab does nothing")
            ctx.at("close all tabs")
            m.open(url: b); await ctx.settle(300)
            _ = await ctx.openNumbered("rule-f.md", lines: 30)
            m.closeAllTabs(); await ctx.settle(400)
            ctx.expectTabs([def], active: def, "close all tabs")
            m.reopenLastClosedTab(); await ctx.settle(300)
            if m.tabs.count != 2 || m.document.url == def { ctx.issue("tabs", "reopen after close-all: tabs \(m.tabs.map(\.lastPathComponent)), active \(m.document.url.lastPathComponent)") }
            ctx.checkTabs("reopen after close all")
            // 처음 상태로: 시작 문서만
            m.open(url: start); await ctx.settle(300)
            m.closeOtherTabs(); await ctx.settle(300)
            ctx.expectTabs([start], active: start, "back to the start document")
            ctx.tallyNote()
        },

        // 탭 줄을 실제 좌표로 클릭: 전환(걸리는 시간) · × · 더블클릭 닫기 · 가운데 클릭 닫기. 클릭은 화면 밖 패널에 얹은 탭 줄 사본에 보낸다 (도우미의 설명 참고)
        Scenario(name: "tabs-click") { ctx in
            let m = ctx.model
            let a = await ctx.openNumbered("click-a.md", lines: 300)
            let b = await ctx.openNumbered("click-b.md", lines: 300)
            let c = await ctx.openNumbered("click-c.md", lines: 300)
            let panel = ctx.tabProbe()
            await ctx.settle(500)
            ctx.note("double-click interval \(Int(NSEvent.doubleClickInterval * 1000)) ms; probe panel shows \(ctx.tabCatchers(in: panel.contentView).count) tabs for \(m.tabs.count) (app active \(NSApp.isActive), panel key \(panel.isKeyWindow))")
            ctx.at("click a tab to switch")
            var reached = false
            var latencies: [Double] = []
            for (n, target) in [a, c, b, a, b].enumerated() {
                let ms = await ctx.clickTabAndWait(target)
                if let ms {
                    reached = true
                    latencies.append(ms)
                    ctx.note("click #\(n + 1) on \(target.lastPathComponent): active after \(Int(ms)) ms")
                } else if !reached && n == 0 {
                    ctx.note("the first synthetic click on the probe panel did nothing — no safe click route on this system; the click steps are skipped")
                    break
                } else {
                    ctx.issue("tab-click", "clicked the tab \(target.lastPathComponent) at its label but it did not become active within 1.5 s (active: \(m.document.url.lastPathComponent))", snap: false)
                    m.activateTab(target)
                }
                await ctx.settle(300)
                ctx.checkTabs("after clicking \(target.lastPathComponent)"); ctx.checkAll("after clicking \(target.lastPathComponent)"); ctx.checkTabBar("after clicking \(target.lastPathComponent)")
            }
            // 누름 30 ms + 전환 수십 ms 면 끝나야 한다. 한 번 클릭이 더블클릭 판정을 기다리면 **모든** 클릭에 더블클릭 간격(약 0.4 s)이 더해진다 — 그래서 가장 빠른
            // 클릭으로 가린다 (같은 Mac 에서 다른 작업이 CPU 를 쓰면 몇몇 클릭은 수백 ms 가 걸려, 개별 값으로 가리면 그 잡음이 결함으로 보인다)
            if let best = latencies.min(), best > 150 {
                ctx.issue("tab-click", "clicking a tab switches only after \(Int(best)) ms at best (clicks: \(latencies.map { Int($0) }) ms) — a single click seems to wait out the double-click interval", snap: false)
            }
            /// 더블클릭을 보낸다. 기계가 바빠 두 클릭 사이가 더블클릭 간격의 절반을 넘겼으면(더블클릭이 아니게 된다) 두 번까지 다시 한다. 반환: 제때 보낸 더블클릭이 있었는가
            @MainActor func doubleClick(_ url: URL) async -> Bool {
                for _ in 0..<3 {
                    guard m.tabs.contains(url) else { return true }
                    await ctx.clickTab(url, clicks: 2); await ctx.settle(900)
                    if RealUseContext.lastClickSpanMs < NSEvent.doubleClickInterval * 500 { return true }
                    ctx.note("double-click took \(Int(RealUseContext.lastClickSpanMs)) ms from first press to last release (the machine is busy) — sending it again")
                }
                return !m.tabs.contains(url)
            }
            if reached {
                ctx.at("click the × of the active tab")
                let active = m.document.url
                let t0 = CFAbsoluteTimeGetCurrent()
                await ctx.clickTab(active, spot: .close)
                while m.tabs.contains(active), ctx.elapsedMs(since: t0) < 1500 { try? await Task.sleep(nanoseconds: 4_000_000) }
                if m.tabs.contains(active) { ctx.issue("tab-click", "clicked the × of the active tab \(active.lastPathComponent) but it is still open", snap: false); m.closeTab(active) }
                else { ctx.note("× closed \(active.lastPathComponent) after \(Int(ctx.elapsedMs(since: t0))) ms; active is now \(m.document.url.lastPathComponent)") }
                await ctx.settle(400)
                ctx.checkTabs("after ×"); ctx.checkTabBar("after ×"); ctx.checkAll("after ×")

                ctx.at("double-click closes an inactive tab")
                let before = m.document.url
                guard let victim = [a, b, c].first(where: { $0 != before && m.tabs.contains($0) }) else { return }
                let timely = await doubleClick(victim)
                if !timely { ctx.note("no double-click could be sent within the double-click interval — skipped") }
                else if m.tabs.contains(victim) { ctx.issue("tab-click", "double-clicked the tab \(victim.lastPathComponent) but it is still open (active: \(m.document.url.lastPathComponent))", snap: false); m.closeTab(victim); await ctx.settle(300) }
                // 첫 클릭이 그 탭으로 전환하지만, 닫은 뒤에는 보고 있던 탭으로 돌아와야 한다 (AppModel.tabDoubleClicked)
                else if m.document.url != before { ctx.issue("tab-click", "double-click closed the background tab \(victim.lastPathComponent) but the editor is on \(m.document.url.lastPathComponent) instead of the tab that was being viewed (\(before.lastPathComponent))", snap: false) }
                ctx.note("double-click closed \(victim.lastPathComponent): active \(before.lastPathComponent) → \(m.document.url.lastPathComponent)")
                ctx.checkTabs("after double-click close"); ctx.checkTabBar("after double-click close"); ctx.checkAll("after double-click close")

                ctx.at("double-click closes the active tab")
                m.open(url: a); await ctx.settle(300); m.open(url: b); await ctx.settle(400)
                let active2 = m.document.url
                let timely2 = await doubleClick(active2)
                if !timely2 { ctx.note("no double-click could be sent within the double-click interval — skipped") }
                else if m.tabs.contains(active2) { ctx.issue("tab-click", "double-clicked the active tab \(active2.lastPathComponent) but it is still open", snap: false); m.closeTab(active2); await ctx.settle(300) }
                ctx.checkTabs("after double-click on the active tab"); ctx.checkAll("after double-click on the active tab")
            }
            ctx.closeTabProbe()
            ctx.at("middle click closes")
            m.open(url: a); await ctx.settle(300); m.open(url: b); await ctx.settle(300)
            let keep = m.document.url
            await ctx.middleClickTab(a); await ctx.settle(400)
            if m.tabs.contains(a) { ctx.issue("tab-click", "middle-clicked the tab \(a.lastPathComponent) but it is still open") }
            if m.document.url != keep { ctx.issue("tab-click", "middle-click on an inactive tab changed the active tab to \(m.document.url.lastPathComponent)") }
            ctx.checkTabs("after middle click"); ctx.checkTabBar("after middle click")
            ctx.tallyNote()
        },

        // 찾기 결과가 떠 있을 때 전환(결과·강조가 지워지는가, F3 는 새 파일에서 찾는가) · 분할 보기에서 전환
        Scenario(name: "tabs-find-split") { ctx in
            let m = ctx.model
            let a = await ctx.openNumbered("find-a.md", lines: 800)
            let b = await ctx.open(text: (1...600).map { "beta row \($0) — needle only on every seventh\($0 % 7 == 0 ? " needle" : "")" }.joined(separator: "\n") + "\n", name: "find-b.md").resolvingSymlinksInPath()
            ctx.at("find in b, then switch")
            var n0 = m.searchCompletionCount
            m.findFields.query = "needle"; m.submitFind()
            await ctx.waitSearch(after: n0)
            let hitsB = m.searchHits.count
            if hitsB == 0 || ctx.tv.matchHighlights.isEmpty { ctx.issue("find", "searching 'needle' in find-b.md: \(hitsB) hits, \(ctx.tv.matchHighlights.count) highlights") }
            ctx.snap("find-b-results")
            m.activateTab(a); await ctx.settle(350)
            if !m.searchHits.isEmpty { ctx.issue("find", "after switching to find-a.md the results list still has \(m.searchHits.count) hits from find-b.md") }
            if !ctx.tv.matchHighlights.isEmpty { ctx.issue("find", "after switching to find-a.md \(ctx.tv.matchHighlights.count) match highlights from find-b.md are still drawn") }
            ctx.checkTabs("on a with the find panel open"); ctx.checkAll("on a with the find panel open"); ctx.snap("find-a-after-switch")
            ctx.at("F3 on the new tab searches the new file")
            n0 = m.searchCompletionCount
            m.findFields.query = "section"; m.findNext()
            await ctx.waitSearch(after: n0); await ctx.settle(200)
            let expectA = (ctx.text as String).components(separatedBy: "section").count - 1
            if m.searchHits.count != expectA { ctx.issue("find", "F3 for 'section' on find-a.md: \(m.searchHits.count) hits, the text has \(expectA)") }
            let sel = ctx.tv.selectedRange()
            if sel.length != 7 || ctx.text.substring(with: sel) != "section" { ctx.issue("find", "F3 on find-a.md selected \(sel) '\(sel.length > 0 && NSMaxRange(sel) <= ctx.length ? ctx.text.substring(with: sel) : "")'") }
            ctx.at("switch away while a search is running")
            n0 = m.searchCompletionCount
            m.findFields.query = "fox"; m.submitFind()
            m.activateTab(b)                                   // 검색이 끝나기 전에
            await ctx.settle(600)
            if !m.searchHits.isEmpty { ctx.issue("find", "a search started on find-a.md finished after the switch and put \(m.searchHits.count) hits on find-b.md") }
            if m.isSearching { ctx.issue("find", "the search spinner is still on after the switch cancelled the search") }
            ctx.checkTabs("on b after cancelling a search")
            m.findFields.query = ""; m.commitFindFields(); await ctx.settle(200)

            ctx.at("split view, then switch")
            m.setSplit(.vertical); await ctx.settle(700)
            guard let second = m.session.secondary?.textView else { ctx.issue("split", "split editor did not appear"); m.setSplit(.none); return }
            ctx.snap("split-b")
            m.activateTab(a); await ctx.settle(500)
            let primaryTV = m.session.primary?.textView
            if (second.string as NSString).length != (primaryTV?.string as NSString?)?.length { ctx.issue("split", "after the switch the two editors show different lengths") }
            if !(second.string as NSString).hasPrefix("# find-a") { ctx.issue("split", "the second editor still shows '\((second.string as NSString).substring(to: min(12, (second.string as NSString).length)))' after switching to find-a.md") }
            let s2 = second.selectedRange()
            if NSMaxRange(s2) > (second.string as NSString).length { ctx.issue("selection", "second editor selection \(s2) outside the new document") }
            // 보조 편집기는 주 편집기의 캐럿 줄에서 시작한다 (EditorView.restoreViewStateIfNeeded) — 탭을 바꾼 뒤에도
            if let p1 = primaryTV?.selectedRange().location, s2.location != p1 {
                let idx = LineIndex(nsString: second.string as NSString)
                ctx.issue("split", "after switching tabs the second editor's caret is on line \(idx.lineNumber(forUTF16Offset: s2.location)) but the first editor's is on line \(idx.lineNumber(forUTF16Offset: p1))")
            }
            let v2 = second.visibleRect
            if v2.minY < -0.5 || v2.maxY > second.frame.height + 0.5 { ctx.issue("viewport-jump", "second editor shows \(Int(v2.minY))…\(Int(v2.maxY)) of a \(Int(second.frame.height)) pt document after the switch") }
            ctx.checkTabs("split, on a"); ctx.checkAll("split, on a"); ctx.checkInk("split, on a"); ctx.snap("split-a")
            ctx.at("type in the second editor, switch, come back")
            second.window?.makeFirstResponder(second)
            await ctx.turn()
            second.setSelectedRange(NSRange(location: 0, length: 0))
            second.insertText("SPLIT-EDIT ", replacementRange: NSRange(location: NSNotFound, length: 0))
            await ctx.settle(100)
            m.activateTab(b); await ctx.settle(500)
            let diskA = (try? String(contentsOf: a, encoding: .utf8)) ?? ""
            if !diskA.hasPrefix("SPLIT-EDIT ") { ctx.issue("save", "an edit made in the second editor was not saved when the tab was left") }
            ctx.checkTabs("split, back on b"); ctx.checkAll("split, back on b")
            m.activateTab(a); await ctx.settle(500)
            if !ctx.text.hasPrefix("SPLIT-EDIT ") { ctx.issue("text", "back on a: the edit from the second editor is missing") }
            ctx.checkTabs("split, back on a"); ctx.checkAll("split, back on a")
            ctx.at("close the split")
            m.setSplit(.none); await ctx.settle(500)
            if let p = m.session.primary?.textView { p.window?.makeFirstResponder(p) }
            await ctx.settle(100)
            m.activateTab(b); await ctx.settle(350)
            ctx.checkTabs("after closing the split"); ctx.checkAll("after closing the split"); ctx.checkInk("after closing the split")
            ctx.tallyNote()
        },

        // 북마크·접기가 파일별로 유지되는가
        Scenario(name: "tabs-fold-bookmark") { ctx in
            let m = ctx.model
            let a = await ctx.openNumbered("mark-a.md", lines: 600)
            let b = await ctx.openNumbered("mark-b.md", lines: 600)
            ctx.at("bookmarks per file")
            m.activateTab(a); await ctx.settle(300)
            m.jump(toLine: 120); await ctx.settle(200); m.toggleBookmarkAtCaret()
            m.jump(toLine: 333); await ctx.settle(200); m.toggleBookmarkAtCaret()
            m.activateTab(b); await ctx.settle(300)
            if !m.bookmarks.bookmarks.isEmpty { ctx.issue("bookmarks", "mark-b.md shows \(m.bookmarks.bookmarks.map(\.line)) — bookmarks of mark-a.md") }
            m.jump(toLine: 77); await ctx.settle(200); m.toggleBookmarkAtCaret()
            m.activateTab(a); await ctx.settle(300)
            if m.bookmarks.bookmarks.map(\.line) != [120, 333] { ctx.issue("bookmarks", "back on mark-a.md the bookmarks are \(m.bookmarks.bookmarks.map(\.line)), expected [120, 333]") }
            ctx.snap("bookmarks-a")
            m.activateTab(b); await ctx.settle(300)
            if m.bookmarks.bookmarks.map(\.line) != [77] { ctx.issue("bookmarks", "back on mark-b.md the bookmarks are \(m.bookmarks.bookmarks.map(\.line)), expected [77]") }
            ctx.at("edit above a bookmark, switch, come back")
            m.jump(toLine: 10); await ctx.settle(200)
            await ctx.key(.returnKey); await ctx.key(.returnKey); await ctx.settle(150)
            let afterInsert = m.bookmarks.bookmarks.map(\.line)
            m.activateTab(a); await ctx.settle(300); m.activateTab(b); await ctx.settle(300)
            if m.bookmarks.bookmarks.map(\.line) != afterInsert || afterInsert != [79] { ctx.issue("bookmarks", "bookmark on line 77 after inserting two lines above and switching: \(afterInsert) → \(m.bookmarks.bookmarks.map(\.line)), expected [79]") }
            ctx.checkTabs("bookmarks, back on b")

            ctx.at("folds per file")
            m.activateTab(a); await ctx.settle(400)
            m.jump(toLine: 100); await ctx.settle(300)          // "## mark-a section 100"
            m.send(.fold); await ctx.settle(300)
            let folded = ctx.foldCount()
            if folded != 1 { ctx.note("fold at line 100 gave \(folded) folded regions (expected 1)") }
            ctx.snap("fold-a")
            let lineAfterFold = m.caretLine
            m.activateTab(b); await ctx.settle(400)
            if ctx.foldCount() != 0 { ctx.issue("fold", "mark-b.md shows \(ctx.foldCount()) folded regions that belong to mark-a.md") }
            ctx.checkAll("on b after folding in a")
            m.activateTab(a); await ctx.settle(700)
            if folded == 1, ctx.foldCount() != 1 { ctx.issue("fold", "folded the section at line 100 of mark-a.md, switched to another tab and back: \(ctx.foldCount()) regions folded, expected 1 (caret line \(lineAfterFold) → \(m.caretLine))") }
            ctx.checkAll("back on a after folding"); ctx.checkInk("back on a after folding"); ctx.snap("fold-a-after-return")
            ctx.at("a fold above the view")
            m.jump(toLine: 300); await ctx.settle(300)          // 접힌 100~149 줄보다 아래를 읽는다
            await ctx.key(.down, count: 6); await ctx.settle(900)
            let below = ctx.mark()
            m.activateTab(b); await ctx.settle(400)
            m.activateTab(a); await ctx.settle(700)
            if folded == 1, ctx.foldCount() != 1 { ctx.issue("fold", "second round trip: \(ctx.foldCount()) regions folded in mark-a.md, expected 1") }
            ctx.checkReturned(to: below, "back on mark-a.md, reading below a folded section")
            ctx.checkAll("back on a below a fold"); ctx.checkInk("back on a below a fold"); ctx.snap("fold-a-below")
            ctx.at("fold all, switch, come back")
            m.send(.foldAll); await ctx.settle(400)
            let allFolded = ctx.foldCount()
            let afterFoldAll = ctx.mark()
            m.activateTab(b); await ctx.settle(400)
            if ctx.foldCount() != 0 { ctx.issue("fold", "mark-b.md shows \(ctx.foldCount()) folded regions after fold-all in mark-a.md") }
            m.activateTab(a); await ctx.settle(700)
            if ctx.foldCount() != allFolded { ctx.issue("fold", "fold all in mark-a.md gave \(allFolded) visible fold marks; after a round trip to another tab there are \(ctx.foldCount())") }
            if ctx.caret != afterFoldAll.caret { ctx.issue("caret", "fold all, round trip: caret \(afterFoldAll.caret) → \(ctx.caret)") }
            // 문서 전체가 첫 머리글 아래로 접혀 한 줄만 보인다 — 코어의 덮임 검사는 접혀서 높이 0 인 조각을 세지 않아 "아래가 비었다"고 하므로 거터·잉크만 본다
            ctx.checkGutter("back on a after fold all"); ctx.checkInk("back on a after fold all"); ctx.snap("fold-a-all")
            ctx.at("pass through a tab quickly")
            m.activateTab(b); m.activateTab(a); m.activateTab(b); await ctx.settle(400)   // a 의 접힘을 되살리기도 전에 다시 떠난다
            m.activateTab(a); await ctx.settle(700)
            if ctx.foldCount() != allFolded { ctx.issue("fold", "after passing through mark-a.md without waiting, its folds are \(ctx.foldCount()), expected \(allFolded)") }
            m.send(.unfoldAll); await ctx.settle(200)

            // 흔적 지우기: 북마크 JSON 은 비면 지워진다
            ctx.at("clean up bookmarks")
            for u in [a, b] {
                m.activateTab(u); await ctx.settle(300)
                for bm in m.bookmarks.bookmarks { m.bookmarks.remove(id: bm.id) }
            }
            ctx.tallyNote()
        },

        // 빠른 연속 전환 50회 + ⌃Tab 연타: 정지·메모리·끝난 뒤의 화면
        Scenario(name: "tabs-rapid") { ctx in
            let m = ctx.model
            var urls: [URL] = []
            for i in 1...4 { urls.append(await ctx.openNumbered("rapid-\(i).md", lines: 1500 * i)) }
            urls.append(await ctx.open(.wide, name: "rapid-wide.md").resolvingSymlinksInPath())
            urls.append(await ctx.open(.small, name: "rapid-small.md").resolvingSymlinksInPath())
            await ctx.settle(500)
            ctx.at("50 switches, one per run-loop turn")
            let mem0 = Bench.memoryMB()
            var times: [Double] = []
            for i in 0..<50 {
                let u = urls[(i * 5 + 1) % urls.count]
                let t = CFAbsoluteTimeGetCurrent()
                m.activateTab(u)
                await ctx.turn()
                ctx.window.layoutIfNeeded(); ctx.window.displayIfNeeded()
                times.append(ctx.elapsedMs(since: t))
                if i % 10 == 9 {
                    await ctx.settle(250)
                    ctx.checkTabs("rapid switch #\(i + 1)"); ctx.checkAll("rapid switch #\(i + 1)"); ctx.checkInk("rapid switch #\(i + 1)")
                }
            }
            await ctx.settle(600)
            let mem1 = Bench.memoryMB()
            let sorted = times.sorted()
            ctx.note(String(format: "50 switches: median %.1f ms, p90 %.1f ms, max %.1f ms; footprint %.0f → %.0f MB", sorted[25], sorted[45], sorted[49], mem0.footprint, mem1.footprint))
            if mem1.footprint - mem0.footprint > 150 { ctx.issue("memory", String(format: "footprint grew %.0f MB over 50 tab switches (%.0f → %.0f MB)", mem1.footprint - mem0.footprint, mem0.footprint, mem1.footprint), snap: false) }
            ctx.checkTabs("after 50 switches"); ctx.checkAll("after 50 switches"); ctx.checkInk("after 50 switches"); ctx.checkTabBar("after 50 switches"); ctx.snap("after-50")

            ctx.at("another 50 without waiting for a turn")
            // 사람이 낼 수 없는 속도(한 턴에 50번) — 일부러 메인 스레드를 잡으므로 정지 감시는 풀어 두고, 끝난 뒤의 상태(탭·내용·화면·보기 위치 저장)가 멀쩡한지만 본다
            var tBurst = 0.0
            await ctx.withRelaxedStalls {
                let t = CFAbsoluteTimeGetCurrent()
                for i in 0..<50 { m.activateTab(urls[(i * 7 + 3) % urls.count]) }
                tBurst = ctx.elapsedMs(since: t)
            }
            ctx.note(String(format: "50 back-to-back switches took %.0f ms in one turn", tBurst))
            await ctx.settle(700)
            let mem2 = Bench.memoryMB()
            ctx.note(String(format: "after 50 back-to-back switches: footprint %.0f MB", mem2.footprint))
            ctx.checkTabs("after 50 back-to-back switches"); ctx.checkAll("after 50 back-to-back switches"); ctx.checkInk("after 50 back-to-back switches"); ctx.checkCaretVisible("after 50 back-to-back switches")

            ctx.at("⌃Tab ×20")
            m.activateTab(urls[0]); await ctx.settle(200); m.activateTab(urls[1]); await ctx.settle(200)
            for _ in 0..<20 { m.activateLastActiveTab(); await ctx.turn() }
            await ctx.settle(400)
            if m.document.url != urls[1] { ctx.issue("tabs", "20 last-active toggles between two tabs ended on \(m.document.url.lastPathComponent), expected \(urls[1].lastPathComponent)") }
            ctx.checkTabs("after 20 last-active toggles"); ctx.checkAll("after 20 last-active toggles")

            ctx.at("type right after a switch")
            m.activateTab(urls[2]); await ctx.turn()
            await ctx.type("바로 입력 ")
            await ctx.settle(200)
            ctx.checkCaretVisible("typing right after a switch"); ctx.checkAll("typing right after a switch")
            let typed = ctx.text.copy() as! NSString
            m.activateTab(urls[3]); await ctx.settle(300); m.activateTab(urls[2]); await ctx.settle(300)
            if !ctx.text.isEqual(to: typed as String) { ctx.issue("text", "text typed right after a switch was lost on the next switch (\(typed.length) → \(ctx.length))") }
            ctx.tallyNote()
        },

        // 28 MB 로그가 낀 전환: 걸리는 시간·메모리 (기록), 전환 뒤의 화면
        Scenario(name: "tabs-big") { ctx in
            let m = ctx.model
            let small = await ctx.openNumbered("big-neighbour.md", lines: 400)
            let bigURL = ctx.dir.appendingPathComponent("big-28mb.log")
            var big = bigURL
            ctx.at("open 28 MB")
            let mem0 = Bench.memoryMB()
            var tOpen = 0.0
            await ctx.withRelaxedStalls(30_000) {
                try? Bench.makeLogCorpus(targetBytes: 28_000_000, seed: 77).text.write(to: bigURL, atomically: true, encoding: .utf8)
                let t = CFAbsoluteTimeGetCurrent()
                m.open(url: bigURL)
                await ctx.settle(0)
                tOpen = ctx.elapsedMs(since: t)
                await ctx.settle(800)
            }
            big = m.document.url
            ctx.note(String(format: "open 28 MB: %.0f ms until the first frame; length %d", tOpen, ctx.length))
            ctx.checkLayout("28 MB opened"); ctx.checkGutter("28 MB opened"); ctx.checkInk("28 MB opened"); ctx.checkTabs("28 MB opened")
            ctx.at("place in the middle of 28 MB")
            await ctx.withRelaxedStalls(30_000) { m.jump(toLine: 130_000); await ctx.settle(1200) }
            let mk = ctx.mark()
            ctx.checkLayout("28 MB line 130000"); ctx.checkCaretVisible("28 MB line 130000")
            var away: [Double] = [], back: [Double] = []
            for round in 1...3 {
                ctx.at("28 MB → small #\(round)")
                await ctx.withRelaxedStalls(30_000) {
                    let t = CFAbsoluteTimeGetCurrent()
                    m.activateTab(small); await ctx.settle(0)
                    away.append(ctx.elapsedMs(since: t))
                    await ctx.settle(400)
                }
                ctx.checkAll("small after 28 MB #\(round)"); ctx.checkInk("small after 28 MB #\(round)"); ctx.checkTabs("small after 28 MB #\(round)")
                ctx.at("small → 28 MB #\(round)")
                await ctx.withRelaxedStalls(30_000) {
                    let t = CFAbsoluteTimeGetCurrent()
                    m.activateTab(big); await ctx.settle(0)
                    back.append(ctx.elapsedMs(since: t))
                    await ctx.settle(900)
                }
                ctx.checkReturned(to: mk, "back on 28 MB #\(round)")
                ctx.checkLayout("back on 28 MB #\(round)"); ctx.checkGutter("back on 28 MB #\(round)"); ctx.checkInk("back on 28 MB #\(round)"); ctx.checkCaretVisible("back on 28 MB #\(round)")
            }
            let mem1 = Bench.memoryMB()
            ctx.note("28 MB → small: \(away.map { Int($0) }) ms; small → 28 MB: \(back.map { Int($0) }) ms; footprint \(Int(mem0.footprint)) → \(Int(mem1.footprint)) MB")
            ctx.snap("big-back")
            ctx.at("type in 28 MB and leave")
            await ctx.type("big edit ")
            let lenBig = ctx.length
            var tSave = 0.0
            await ctx.withRelaxedStalls(30_000) {
                let t = CFAbsoluteTimeGetCurrent()
                m.activateTab(small); await ctx.settle(0)
                tSave = ctx.elapsedMs(since: t)
                await ctx.settle(400)
            }
            ctx.note(String(format: "leaving the edited 28 MB tab (synchronous save + load small): %.0f ms", tSave))
            let attrs = try? FileManager.default.attributesOfItem(atPath: big.path)
            ctx.note("28 MB file on disk after leaving: \((attrs?[.size] as? Int) ?? -1) bytes (editor had \(lenBig) UTF-16 units)")
            ctx.checkTabs("small after leaving the edited 28 MB")
            await ctx.withRelaxedStalls(30_000) { m.closeTab(big); await ctx.settle(500) }
            let mem2 = Bench.memoryMB()
            ctx.note("after closing the 28 MB tab: footprint \(Int(mem2.footprint)) MB")
            ctx.tallyNote()
        },

        // 파일이 많은 폴더의 탭과 다른 폴더의 탭을 오갈 때 (파일 보기가 폴더를 다시 읽는다) 정지가 없는가
        Scenario(name: "tabs-folders") { ctx in
            let m = ctx.model
            let fm = FileManager.default
            let proj = ctx.dir.appendingPathComponent("project", isDirectory: true)
            ctx.at("build a folder with many files")
            await ctx.withRelaxedStalls(30_000) {
                try? fm.createDirectory(at: proj, withIntermediateDirectories: true)
                for i in 0..<1500 { fm.createFile(atPath: proj.appendingPathComponent(String(format: "file-%04d.txt", i)).path, contents: Data("x\n".utf8)) }
                for d in 0..<120 {
                    let sub = proj.appendingPathComponent(String(format: "dir-%03d", d), isDirectory: true)
                    try? fm.createDirectory(at: sub, withIntermediateDirectories: true)
                    for i in 0..<40 { fm.createFile(atPath: sub.appendingPathComponent("item-\(i).md").path, contents: Data("y\n".utf8)) }
                }
            }
            let main = proj.appendingPathComponent("main.md")
            try? RealUseContext.numberedText("main", lines: 300).write(to: main, atomically: true, encoding: .utf8)
            let other = await ctx.openNumbered("elsewhere.md", lines: 300)
            var tFirst = 0.0
            await ctx.withRelaxedStalls(30_000) {
                let t = CFAbsoluteTimeGetCurrent()
                m.open(url: main); await ctx.settle(0)
                tFirst = ctx.elapsedMs(since: t)
                await ctx.settle(500)
            }
            let mainURL = m.document.url
            ctx.note(String(format: "first open of a file in a 6300-entry folder: %.0f ms (file view %@)", tFirst, m.showFileView ? "shown" : "hidden"))
            var times: [Double] = []
            for i in 0..<6 {
                ctx.at("switch between folders #\(i + 1)")
                let t = CFAbsoluteTimeGetCurrent()
                m.activateTab(i % 2 == 0 ? other : mainURL)
                await ctx.settle(0)
                times.append(ctx.elapsedMs(since: t))
                await ctx.settle(300)
                ctx.checkTabs("folder switch #\(i + 1)"); ctx.checkAll("folder switch #\(i + 1)")
            }
            ctx.note("switches between a small folder and a 6300-entry folder: \(times.map { Int($0) }) ms (even = to the small folder)")
            ctx.at("where the time goes")
            var tLoad = 0.0, topLevel = 0
            await ctx.withRelaxedStalls(30_000) {
                let t = CFAbsoluteTimeGetCurrent()
                topLevel = FileTree.load(proj).count
                tLoad = ctx.elapsedMs(since: t)
            }
            let shown = m.showFileView
            var hidden: [Double] = []
            await ctx.withRelaxedStalls(30_000) {
                m.showFileView = false; await ctx.settle(300)
                for i in 0..<4 {
                    let t = CFAbsoluteTimeGetCurrent()
                    m.activateTab(i % 2 == 0 ? other : mainURL)
                    await ctx.settle(0)
                    hidden.append(ctx.elapsedMs(since: t))
                    await ctx.settle(200)
                }
                m.showFileView = shown; await ctx.settle(500)
            }
            ctx.note(String(format: "reading the folder tree alone (FileTree.load, %d top-level entries): %.0f ms; the same switches with the file view hidden: ", topLevel, tLoad) + "\(hidden.map { Int($0) }) ms")
            ctx.snap("folders")
            ctx.tallyNote()
        },
    ]
}
