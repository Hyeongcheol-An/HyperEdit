import SwiftUI
import AppKit
import HyperCore

// 실사용 시뮬레이션 — 파일 보기(사이드바 File View): 파일이 많은 폴더의 탭과 다른 폴더의 탭을 오갈 때 메인 스레드가 멈추지 않는가,
// 목록이 문서를 따라가는가(현재 문서 강조·새로 생긴 파일), 행 클릭·방향키로 파일이 열리는가, 폴더 펼치기·새로 고침.
//
// 클릭은 창의 목록이 아니라 화면 밖의 활성화하지 않는 패널에 얹은 **파일 보기 사본**에 보낸다 (탭 줄의 사본과 같은 방식 — RealUse+Tabs.swift "탭 클릭").
// 키 창이 아닌 보통 창의 NSOutlineView 는 mouseDown 을 직접 받아도 행을 고르지 않고 펼침 버튼도 반응하지 않는다(실측 2026-11-24: 선택 0건, 0 ms 에 반환).
// 창을 키 창으로 만들려면 앱을 활성화해야 하고 그러면 사용자의 포커스를 뺏는다. 키 창이 될 수 없는 패널의 목록은 같은 이벤트에 반응한다 —
// 같은 뷰 코드(FileViewPanel · FileOutline)가 같은 모델을 움직이므로 히트 테스트·선택·펼침·열기 배선을 그대로 지난다. 방향키와 휠은 창의 목록에 직접 보낸다.
//
// 주의: 텍스트가 아닌 파일(확장자가 바이너리이거나 NUL 이 든 파일)을 고르면 앱이 그 파일을 기본 앱으로 연다(`AppModel.open(url:)` → NSWorkspace) —
// 다른 앱이 떠서 사용자의 화면을 가린다. 그래서 여기서는 그런 행을 절대 고르지 않는다(클릭·방향키 전에 대상 행이 보통 텍스트 파일인지 확인한다).

/// 메인 스레드가 한 번에 가장 오래 막힌 시간(ms)을 잰다 — 2 ms 간격으로 메인 큐에 핑을 넣고 실행될 때까지의 지연을 본다.
/// 코어의 정지 감시(50 ms 간격, 250 ms 문턱)는 "멈췄다/아니다"만 가리므로, 전환 한 번의 몫을 수치로 비교하려면 이것이 필요하다
final class MainLagProbe: @unchecked Sendable {
    private let queue = DispatchQueue(label: "realuse.fileview.lag")
    private var timer: DispatchSourceTimer?
    private let lock = NSLock()
    private var pending = false
    private var worst = 0.0

    func start() {
        lock.lock(); pending = false; worst = 0; lock.unlock()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(2), leeway: .microseconds(200))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            self.lock.lock()
            if self.pending { self.lock.unlock(); return }   // 앞선 핑이 아직 실행되지 않았다 — 그 핑이 막힌 시간 전체를 잰다
            self.pending = true
            self.lock.unlock()
            let sent = CFAbsoluteTimeGetCurrent()
            DispatchQueue.main.async {
                let lag = (CFAbsoluteTimeGetCurrent() - sent) * 1000
                self.lock.lock(); self.pending = false; if lag > self.worst { self.worst = lag }; self.lock.unlock()
            }
        }
        t.resume()
        timer = t
    }

    /// 재기를 끝낸다. 반환: start 뒤로 메인 스레드가 한 번에 가장 오래 막힌 시간(ms)
    func stop() -> Double {
        timer?.cancel(); timer = nil
        lock.lock(); defer { lock.unlock() }
        return worst
    }
}

extension RealUseContext {
    // MARK: 말뭉치

    /// 큰 폴더를 만든다(이미 있으면 그대로 쓴다): 최상위 파일 `files` 개 + 하위 폴더 `dirs` 개(폴더마다 파일 `perDir` 개). 한글·긴 이름이 섞여 있다
    func makeFolder(_ name: String, files: Int, dirs: Int, perDir: Int) -> URL {
        let fm = FileManager.default
        let root = dir.appendingPathComponent(name, isDirectory: true)
        if fm.fileExists(atPath: root.path) { return root.resolvingSymlinksInPath() }
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        let body = Data("x\n".utf8)
        for i in 0..<files {
            let n: String
            switch i % 10 {
            case 3: n = String(format: "회의록-%04d.md", i)
            case 7: n = String(format: "report-%04d-a-rather-long-file-name-that-does-not-fit-in-the-sidebar.txt", i)
            default: n = String(format: "file-%04d.txt", i)
            }
            fm.createFile(atPath: root.appendingPathComponent(n).path, contents: body)
        }
        for d in 0..<dirs {
            let sub = root.appendingPathComponent(String(format: "dir-%03d", d), isDirectory: true)
            try? fm.createDirectory(at: sub, withIntermediateDirectories: true)
            for i in 0..<perDir { fm.createFile(atPath: sub.appendingPathComponent("item-\(i).md").path, contents: body) }
        }
        return root.resolvingSymlinksInPath()
    }

    /// 번호 문서를 `folder` 안에 만든다 (열지는 않는다). 반환: 탭 목록에 들어가는(심볼릭 링크를 푼) 경로
    func writeNumbered(_ name: String, in folder: URL, lines: Int = 200) -> URL {
        let url = folder.appendingPathComponent(name)
        try? Self.numberedText((name as NSString).deletingPathExtension, lines: lines).write(to: url, atomically: true, encoding: .utf8)
        return url.resolvingSymlinksInPath()
    }

    // MARK: 재기

    static func median(_ xs: [Double]) -> Double {
        guard !xs.isEmpty else { return 0 }
        let s = xs.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    static func stats(_ xs: [Double]) -> String { String(format: "p50 %.1f · max %.1f ms (n=%d)", median(xs), xs.max() ?? 0, xs.count) }

    struct SwitchSample { let toFrame: Double; let block: Double; let view: Double }

    /// 탭을 바꾸고 잰다: 첫 화면이 그려질 때까지의 시간(`toFrame`), 그 뒤 `tail` ms 까지 포함해 메인 스레드가 한 번에 가장 오래 막힌 시간(`block`),
    /// 그동안 파일 보기가 메인 스레드에서 쓴 시간(`view` — 목록 갈아 끼우기·선택·읽기 결과 적용·행 그리기)
    func timedSwitch(to url: URL, tail: UInt64 = 350) async -> SwitchSample {
        let probe = MainLagProbe()
        probe.start()
        FileViewStats.reset()
        let t = CFAbsoluteTimeGetCurrent()
        model.activateTab(url)
        await settle(0)
        let frame = elapsedMs(since: t)
        await settle(tail)
        return SwitchSample(toFrame: frame, block: probe.stop(), view: FileViewStats.mainMs)
    }

    /// 사이드바를 파일 보기로 켠다. 반환: 원래 상태 (끝에 되돌린다)
    func showFileView() async -> (shown: Bool, tab: LeftTab) {
        let old = (model.showFileView, model.leftTab)
        if model.leftTab != .fileView { model.leftTab = .fileView }
        if !model.showFileView { model.showFileView = true }
        await settle(300)
        return old
    }

    /// 사이드바와 편집기를 나누는 분할 뷰 (창의 가장 바깥 좌우 분할)
    private func sidebarSplit() -> NSSplitView? {
        guard let root = window.contentView else { return nil }
        var found: NSSplitView?
        func walk(_ v: NSView) {
            if let sv = v as? NSSplitView, sv.isVertical, sv.arrangedSubviews.count >= 2 {
                let f = sv.convert(sv.bounds, to: nil)
                if f.minX < 1, f.width > root.bounds.width - 2, found == nil || f.height > found!.frame.height { found = sv }
            }
            for s in v.subviews { walk(s) }
        }
        walk(root)
        return found
    }

    var sidebarWidth: CGFloat? { sidebarSplit()?.arrangedSubviews.first?.frame.width }

    /// 사이드바의 폭을 맞춘다 (칸막이를 옮긴다). 사이드바를 껐다 켜면 폭이 190 pt 로 돌아오므로, 편집기 폭에 따라 달라지는 재현에는 폭을 정해 둬야 한다.
    /// 반환: 맞춘 뒤의 폭 (분할 뷰를 못 찾으면 nil)
    @discardableResult
    func setSidebarWidth(_ width: CGFloat) async -> CGFloat? {
        guard let split = sidebarSplit() else { return nil }
        split.setPosition(width, ofDividerAt: 0)
        await settle(300)
        return split.arrangedSubviews.first?.frame.width
    }

    func restoreSidebar(_ old: (shown: Bool, tab: LeftTab)) async {
        if model.leftTab != old.tab { model.leftTab = old.tab }
        if model.showFileView != old.shown { model.showFileView = old.shown }
        await settle(200)
    }

    /// 작은 폴더(이미 있으면 그대로 쓴다): 텍스트 파일 몇 개(한글·긴 이름 포함) + 텍스트가 아닌 파일 하나(흐리게 보여야 한다 — 고르지 않는다) + 하위 폴더 둘
    func makeSmallFolder(_ name: String) -> URL {
        let fm = FileManager.default
        let root = dir.appendingPathComponent(name, isDirectory: true)
        if fm.fileExists(atPath: root.path) { return root.resolvingSymlinksInPath() }
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        for n in ["alpha.md", "beta.md", "gamma.txt", "회의록 2026-11.md", "a-very-long-file-name-that-cannot-possibly-fit-in-a-sidebar-of-ordinary-width-and-has-to-be-truncated-somewhere.md"] {
            try? Self.numberedText((n as NSString).deletingPathExtension, lines: 120).write(to: root.appendingPathComponent(n), atomically: true, encoding: .utf8)
        }
        fm.createFile(atPath: root.appendingPathComponent("zz-image.png").path, contents: Data([0x89, 0x50, 0x4E, 0x47]))
        for (d, files) in [("docs", ["guide.md", "notes.txt", "todo.md"]), ("src", ["main.swift", "util.swift"])] {
            let sub = root.appendingPathComponent(d, isDirectory: true)
            try? fm.createDirectory(at: sub, withIntermediateDirectories: true)
            for f in files { try? Self.numberedText((f as NSString).deletingPathExtension, lines: 60).write(to: sub.appendingPathComponent(f), atomically: true, encoding: .utf8) }
        }
        // 숨김 파일(목록에 없어야 한다)과 심볼릭 링크(파일·폴더 — 폴더 링크는 파일처럼 보인다. 링크 행은 고르지 않는다)
        try? "hidden\n".write(to: root.appendingPathComponent(".hidden.md"), atomically: true, encoding: .utf8)
        try? fm.createSymbolicLink(at: root.appendingPathComponent("link-to-beta.md"), withDestinationURL: root.appendingPathComponent("beta.md"))
        try? fm.createSymbolicLink(at: root.appendingPathComponent("link-to-docs"), withDestinationURL: root.appendingPathComponent("docs", isDirectory: true))
        try? fm.createDirectory(at: root.appendingPathComponent("docs/deep/deeper", isDirectory: true), withIntermediateDirectories: true)
        try? Self.numberedText("leaf", lines: 40).write(to: root.appendingPathComponent("docs/deep/deeper/leaf.md"), atomically: true, encoding: .utf8)
        return root.resolvingSymlinksInPath()
    }

    /// 사이드바 둘레만 2배로 그려 PNG 로 (창 전체 스냅샷에서는 11.5 pt 글자가 너무 작다). 반환: 파일 이름
    @discardableResult
    func snapSidebar(_ name: String, height: CGFloat = 420) -> String? {
        guard let root = window.contentView else { return nil }
        // 사이드바는 창의 왼쪽, 문서 탭 줄 바로 아래에서 시작한다 (탭 줄의 위치는 탭 받이 뷰로 안다)
        let top: CGFloat
        if let f = tabFrames().first { let r = root.convert(f, from: nil); top = root.isFlipped ? r.maxY : root.bounds.height - r.minY } else { top = 184 }
        let width = min(470, root.bounds.width), h = min(height, root.bounds.height - top)
        let region = NSRect(x: 0, y: root.isFlipped ? top : root.bounds.height - top - h, width: width, height: h)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * 2), pixelsHigh: Int(h * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = region.size
        root.cacheDisplay(in: region, to: rep)
        FileViewTally.crops += 1
        let file = String(format: "F%02d-%@-%@.png", FileViewTally.crops, scenario, name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: " ", with: "_"))
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        try? data.write(to: out.appendingPathComponent(file))
        return file
    }
}

@MainActor private enum FileViewTally { static var crops = 0; static var checks = 0; static var clicks = 0; static var keys = 0 }


/// 합성 클릭의 mouseUp 을 누가 보낼지 — 먼저 잡은 쪽 하나만 (추적 루프에 넣어 주는 감시 스레드 / 바로 돌아온 mouseDown 뒤의 본문)
private final class ClickRelease: @unchecked Sendable {
    let up: NSEvent
    private let lock = NSLock()
    private var taken = false
    init(_ up: NSEvent) { self.up = up }
    func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if taken { return false }; taken = true; return true }
}

/// 클릭 시험용 패널: 앱을 활성화하지 않고(.nonactivatingPanel) 키 창도 될 수 없다 — 사용자가 쓰고 있는 앱의 키보드 포커스를 가져오지 않는다
private final class FileProbePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// 클릭 시험용 파일 보기 사본 — 창의 사이드바와 같은 뷰, 같은 모델
private struct ProbeFileView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        let theme = model.themes.current
        FileViewPanel(theme: theme).environmentObject(model)
            .frame(width: RealUseContext.fileProbeSize.width, height: RealUseContext.fileProbeSize.height)
            .background(theme.backgroundAlt.color)
    }
}

// MARK: - 파일 보기의 뷰를 직접 다루는 도우미

extension RealUseContext {
    private static func findOutline(_ v: NSView?) -> FileOutlineView? {
        guard let v else { return nil }
        if let o = v as? FileOutlineView { return o }
        for s in v.subviews { if let o = findOutline(s) { return o } }
        return nil
    }

    /// 사이드바의 파일 목록 (지금 보이는 폴더의 NSOutlineView). 사이드바가 꺼져 있거나 다른 탭이면 nil
    var fileOutline: FileOutlineView? { Self.findOutline(window.contentView) }

    var fileCoord: FileOutlineCoordinator? { fileOutline?.delegate as? FileOutlineCoordinator }

    // MARK: 사본 (클릭 시험용)

    static let fileProbeSize = NSSize(width: 300, height: 520)
    private static var fileProbePanel: NSPanel?
    private static var fileClickActivatedApp = false

    /// 파일 보기 사본의 목록 (사본이 없으면 만든다)
    func fileProbe() async -> FileOutlineView? {
        if Self.fileProbePanel == nil {
            let p = FileProbePanel(contentRect: NSRect(origin: NSPoint(x: -30_000, y: -31_000), size: Self.fileProbeSize), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.becomesKeyOnlyIfNeeded = true
            p.hidesOnDeactivate = false      // 앱이 비활성이어도 떠 있어야 SwiftUI 가 그린다
            p.isReleasedWhenClosed = false
            p.contentView = NSHostingView(rootView: ProbeFileView(model: model))
            p.orderBack(nil)
            Self.fileProbePanel = p
            await settleProbe(300)
            await waitFileView()
        }
        return probeOutline
    }

    var probeOutline: FileOutlineView? { Self.findOutline(Self.fileProbePanel?.contentView) }

    func closeFileProbe() { Self.fileProbePanel?.orderOut(nil); Self.fileProbePanel = nil }

    /// 사본 패널의 레이아웃·그리기를 끝낸다 (`settle` 은 창만 본다)
    func settleProbe(_ ms: UInt64 = 0) async {
        await settle(ms)
        guard let p = Self.fileProbePanel else { return }
        p.contentView?.layoutSubtreeIfNeeded()
        p.displayIfNeeded()
    }

    /// 사본을 2배로 그려 PNG 로. 반환: 파일 이름
    @discardableResult
    func snapProbe(_ name: String) -> String? {
        guard let root = Self.fileProbePanel?.contentView else { return nil }
        let size = root.bounds.size
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        root.cacheDisplay(in: root.bounds, to: rep)
        FileViewTally.crops += 1
        let file = String(format: "F%02d-%@-probe-%@.png", FileViewTally.crops, scenario, name.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: " ", with: "_"))
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        try? data.write(to: out.appendingPathComponent(file))
        return file
    }

    // MARK: 기다리기 · 행

    /// 파일 보기(창과 사본)의 백그라운드 읽기가 끝나고 화면에 반영될 때까지 기다린다. 반환: 걸린 시간(ms)
    @discardableResult
    func waitFileView(timeout: Double = 6000) async -> Double {
        let t0 = CFAbsoluteTimeGetCurrent()
        await settleProbe()   // SwiftUI 가 updateNSView 를 부를 기회
        func busy() -> Bool {
            for o in [fileOutline, probeOutline] {
                guard let c = o?.delegate as? FileOutlineCoordinator else { continue }
                if c.pendingLoads > 0 || c.folder?.loaded != true || c.folder?.key != model.rootDirectory.path { return true }
            }
            return false
        }
        while busy(), elapsedMs(since: t0) < timeout { try? await Task.sleep(nanoseconds: 3_000_000) }
        await settleProbe()
        return elapsedMs(since: t0)
    }

    /// 이름이 `name` 인 행 (없으면 nil). `level` 을 주면 그 깊이의 행만. `o` 를 주지 않으면 창의 목록
    func fileRow(_ name: String, level: Int? = nil, in o: FileOutlineView? = nil) -> Int? {
        guard let o = o ?? fileOutline else { return nil }
        for r in 0..<o.numberOfRows {
            guard let it = o.item(atRow: r) as? FileItem, it.entry.name == name else { continue }
            if let level, o.level(forRow: r) != level { continue }
            return r
        }
        return nil
    }

    func fileItem(_ name: String, level: Int? = nil, in o: FileOutlineView? = nil) -> FileItem? {
        guard let o = o ?? fileOutline else { return nil }
        return fileRow(name, level: level, in: o).flatMap { o.item(atRow: $0) as? FileItem }
    }

    func isExpanded(_ name: String, level: Int? = nil, in o: FileOutlineView? = nil) -> Bool {
        guard let o = o ?? fileOutline, let item = fileItem(name, level: level, in: o) else { return false }
        return o.isItemExpanded(item)
    }

    var fileListScrollY: CGFloat { fileOutline?.enclosingScrollView?.contentView.bounds.origin.y ?? -1 }

    // MARK: 검사

    /// 이전 구현(FileTree.load)과 같은 방식으로 폴더 한 단계를 읽는다 — 항목마다 링크를 풀고, lastPathComponent 로 정렬. 새 구현의 결과와 견준다
    nonisolated static func referenceListing(_ dir: URL) -> [(id: String, name: String, isDir: Bool)] {
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        return items.map { u in (id: u.resolvingSymlinksInPath().path, name: u.lastPathComponent, isDir: (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) }
            .sorted { a, b in a.isDir != b.isDir ? a.isDir : a.name.localizedStandardCompare(b.name) == .orderedAscending }
    }

    /// 파일 보기의 불변식: 목록의 폴더 = 문서의 폴더, 행 = 지금 디스크의 내용(숨김 제외·폴더 먼저·이름순, 펼친 폴더는 자식까지), 현재 문서의 행이 선택돼 있고
    /// 그 행만 '현재'로 그려졌는가. 폴더 행을 일부러 골라 둔 걸음에서는 `selectionFollowsDocument: false`. `probe`: 창의 목록 대신 사본을 본다
    func checkFileView(_ why: String, selectionFollowsDocument: Bool = true, probe: Bool = false) async {
        FileViewTally.checks += 1
        let which = probe ? "the probe list" : "the list"
        guard let o = probe ? probeOutline : fileOutline, let c = o.delegate as? FileOutlineCoordinator else { issue("fileview", "\(why): there is no file list in the \(probe ? "probe panel" : "window")"); return }
        let root = model.rootDirectory, current = model.document.url.path
        guard c.folder?.key == root.path, o.folder === c.folder else {
            issue("fileview", "\(why): \(which) shows \(c.folder?.key ?? "nothing") but the document's folder is \(root.path)"); return
        }
        if c.currentID != current { issue("fileview", "\(why): \(which) thinks the document is \((c.currentID as NSString).lastPathComponent) but it is \((current as NSString).lastPathComponent)") }
        var problem: String?
        var currentRow = -1
        // 큰 폴더에서는 기대 목록을 만드는 데(항목마다 링크 풀기) 수십 ms 가 든다 — 하네스의 몫이므로 정지로 세지 않는다
        await withRelaxedStalls(5000) {
            var actual: [(id: String, level: Int, name: String)] = []
            var expanded = Set<String>()
            for r in 0..<o.numberOfRows {
                guard let it = o.item(atRow: r) as? FileItem else { continue }
                let level = o.level(forRow: r)
                actual.append((it.entry.id, level, it.entry.name))
                if it.entry.isDirectory, o.isItemExpanded(it) { expanded.insert(it.entry.id) }
                if level == 0, it.entry.id == current, currentRow < 0 { currentRow = r }
            }
            var expected: [(id: String, level: Int, name: String)] = []
            func walk(_ dir: URL, _ level: Int) {
                for e in Self.referenceListing(dir) {
                    expected.append((e.id, level, e.name))
                    if e.isDir, expanded.contains(e.id) { walk(URL(fileURLWithPath: e.id, isDirectory: true), level + 1) }
                }
            }
            walk(root, 0)
            if actual.count != expected.count {
                let a = Set(actual.map(\.id)), e = Set(expected.map(\.id))
                let extra = actual.filter { !e.contains($0.id) }.prefix(3).map(\.name), missing = expected.filter { !a.contains($0.id) }.prefix(3).map(\.name)
                problem = "\(which) has \(actual.count) rows but the folder has \(expected.count) entries to show (listed but gone: \(extra), on disk but not listed: \(missing))"
            } else if let i = actual.indices.first(where: { actual[$0].id != expected[$0].id || actual[$0].level != expected[$0].level }) {
                problem = "row \(i) of \(which) is '\(actual[i].name)' (level \(actual[i].level)) but should be '\(expected[i].name)' (level \(expected[i].level))"
            }
        }
        if let problem { issue("fileview", "\(why): \(problem)") }
        if selectionFollowsDocument, o.selectedRow != currentRow {
            let sel = (o.item(atRow: o.selectedRow) as? FileItem)?.entry.name ?? "nothing"
            issue("fileview", "\(why): the selected row of \(which) is \(o.selectedRow) (\(sel)) but the document \((current as NSString).lastPathComponent) is on row \(currentRow)")
        }
        // 보이는 행 가운데 현재 문서의 행만 '현재'로 그려져야 한다
        let rows = o.rows(in: o.visibleRect)
        for r in rows.location..<NSMaxRange(rows) {
            guard let it = o.item(atRow: r) as? FileItem, let cell = o.view(atColumn: 0, row: r, makeIfNecessary: false) as? FileRowCellView else { continue }
            if cell.isCurrent != (it.entry.id == current) {
                issue("fileview", "\(why): row \(r) '\(it.entry.name)' of \(which) is drawn as \(cell.isCurrent ? "the current document" : "an ordinary row") but the document is \((current as NSString).lastPathComponent)")
                break
            }
        }
    }

    /// 창의 목록과 사본 둘 다
    func checkFileViews(_ why: String, selectionFollowsDocument: Bool = true) async {
        await checkFileView(why)
        if probeOutline != nil { await checkFileView(why, selectionFollowsDocument: selectionFollowsDocument, probe: true) }
    }

    // MARK: 클릭 (사본, 실제 좌표) · 키 · 휠

    /// 고르면 편집기에서 열리는 보통 텍스트 파일인가. 아니면(바이너리 확장자·NUL·링크) 기본 앱이 뜨거나 엉뚱한 것이 열리므로 하네스는 그 행을 고르지 않는다
    static func safeToOpen(_ e: FileEntry) -> Bool {
        let url = URL(fileURLWithPath: e.path)
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { return false }
        return TextFileDetector.isLikelyText(url)
    }

    private func probeMouseEvent(_ type: NSEvent.EventType, _ p: NSPoint, in panel: NSPanel) -> NSEvent? {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                           context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)
    }

    private func noteIfActivated() {
        guard NSApp.isActive else { return }   // 일어나면 안 되는 일 — 바로 물러나고 더는 클릭하지 않는다
        Self.fileClickActivatedApp = true
        NSApp.deactivate()
        log("  a synthetic click on the file view probe activated the app — deactivated; no more clicks will be sent")
    }

    enum FileRowSpot { case name, disclosure }

    /// 사본의 행을 클릭한다 (이름 자리 또는 펼침 화살표 자리). 목록의 추적 루프가 mouseUp 을 기다리므로 먼저 큐에 넣고 mouseDown 을 패널에 보낸다.
    /// 반환: 클릭을 보냈는가
    @discardableResult
    func clickFileRow(_ name: String, level: Int? = nil, spot: FileRowSpot = .name) async -> Bool {
        guard !Self.fileClickActivatedApp, let o = await fileProbe(), let panel = Self.fileProbePanel, let root = panel.contentView,
              let row = fileRow(name, level: level, in: o), let item = o.item(atRow: row) as? FileItem else { return false }
        if spot == .name, !item.entry.isDirectory, !Self.safeToOpen(item.entry) { note("not clicking '\(item.entry.name)' — it is not a plain text file"); return false }
        o.scrollRowToVisible(row)
        await settleProbe(20)
        let rr = o.rect(ofRow: row)
        let p: NSPoint
        switch spot {
        case .name: p = NSPoint(x: min(rr.maxX - 12, 70 + CGFloat(o.level(forRow: row)) * o.indentationPerLevel), y: rr.midY)
        case .disclosure:
            let f = o.frameOfOutlineCell(atRow: row)
            guard f.width > 0 else { return false }
            p = NSPoint(x: f.midX, y: f.midY)
        }
        guard o.visibleRect.contains(p) else { return false }
        let w = o.convert(p, to: nil)
        guard let target = root.hitTest(root.superview?.convert(w, from: nil) ?? w), target === o || target.isDescendant(of: o) else {
            issue("fileview", "row \(row) '\(item.entry.name)' cannot be clicked at \(p) — another view is on top of it"); return false
        }
        guard let down = probeMouseEvent(.leftMouseDown, w, in: panel), let up = probeMouseEvent(.leftMouseUp, w, in: panel) else { return false }
        FileViewTally.clicks += 1
        // 누르고 40 ms 뒤에 뗀다. 목록의 행은 mouseDown 안에서 추적 루프를 돌며 mouseUp 을 기다리므로(큐에 없으면 영영 돌아오지 않는다) 다른 스레드가 40 ms 뒤에
        // 큐에 넣어 준다. 펼침 화살표는 추적 루프 없이 바로 돌아오고 mouseUp 이 와야 펼친다(실측) — 그때는 여기서 직접 보낸다
        // 화살표는 추적 루프가 없으니 다른 스레드의 mouseUp 은 mouseDown 이 돌아오지 않을 때의 안전망일 뿐이다 — 0.4 s 뒤로 미룬다 (40 ms 로 두면 mouseDown 이
        // 그보다 오래 걸린 날 안전망이 먼저 떼어 그 mouseUp 이 이벤트 큐에서 기다린다). 다만 전체 묶음의 끝에서만 나오는 '첫 화살표 클릭 무시'의 원인은 이것이
        // 아니었다 (실측: 안전망을 미룬 뒤에도 재현, mouseDown 은 30 ms 안에 돌아왔다) — mouseDown 이 걸린 시간은 계속 기록해 둔다
        let release = ClickRelease(up)
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(spot == .disclosure ? 400 : 40)) { if release.claim() { NSApp.postEvent(release.up, atStart: false) } }
        let t0 = CFAbsoluteTimeGetCurrent()
        panel.sendEvent(down)
        let downMs = elapsedMs(since: t0)
        if release.claim() {
            try? await Task.sleep(nanoseconds: 30_000_000)
            panel.sendEvent(up)
        } else if spot == .disclosure {
            try? await Task.sleep(nanoseconds: 200_000_000)   // 안전망이 큐에 넣은 mouseUp 이 처리될 시간
        }
        if spot == .disclosure, downMs > 30 { note(String(format: "the mouseDown on the arrow of '%@' took %.0f ms to return", item.entry.name, downMs)) }
        await settleProbe(20)
        noteIfActivated()
        return true
    }

    /// 사본의 새로 고침 버튼(목록 위 줄의 오른쪽 끝)을 클릭한다. SwiftUI 버튼이므로 mouseDown · mouseUp 을 패널의 sendEvent 로 따로 보낸다. 반환: 사본이 폴더를 다시 읽기 시작했는가
    func clickProbeRefresh() async -> Bool {
        guard !Self.fileClickActivatedApp, let o = await fileProbe(), let panel = Self.fileProbePanel, let c = o.delegate as? FileOutlineCoordinator else { return false }
        let loads = c.loadCount
        // 버튼은 10 pt 그림 하나다 — 줄의 오른쪽 여백(8 pt) 안쪽에서 조금씩 옮겨 가며 맞힌다
        for dx in [13.0, 11.0, 15.0, 9.0, 17.0] {
            let p = NSPoint(x: Self.fileProbeSize.width - dx, y: Self.fileProbeSize.height - 12)
            guard let down = probeMouseEvent(.leftMouseDown, p, in: panel), let up = probeMouseEvent(.leftMouseUp, p, in: panel) else { return false }
            panel.sendEvent(down)
            try? await Task.sleep(nanoseconds: 30_000_000)
            panel.sendEvent(up)
            await settleProbe(60)
            noteIfActivated()
            if c.loadCount > loads { return true }
        }
        return false
    }

    /// 창의 파일 목록에 포커스를 두고 방향키를 누른다 (keyDown 경로). ↑/↓ 로 고르게 될 행이 텍스트가 아닌 파일이면 누르지 않는다. 반환: 눌렀는가
    @discardableResult
    func fileKey(_ k: Key) async -> Bool {
        guard let o = fileOutline else { return false }
        if k == .up || k == .down {
            let next = o.selectedRow + (k == .down ? 1 : -1)
            guard next >= 0, next < o.numberOfRows, let item = o.item(atRow: next) as? FileItem, item.entry.isDirectory || Self.safeToOpen(item.entry) else {
                note("not pressing \(k) — the next row is not a plain text file or a folder"); return false
            }
        }
        if window.firstResponder !== o { window.makeFirstResponder(o) }
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.function, .numericPad], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, characters: k.chars, charactersIgnoringModifiers: k.chars, isARepeat: false, keyCode: k.code) else { return false }
        FileViewTally.keys += 1
        o.keyDown(with: e)
        await turn()
        return true
    }

    /// 창의 파일 목록을 픽셀 휠로 굴린다 (양수 = 아래로)
    func scrollFileList(by points: CGFloat) async {
        guard let sv = fileOutline?.enclosingScrollView, let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32((-points).rounded()), wheel2: 0, wheel3: 0) else { return }
        cg.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        cg.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(-points))
        cg.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: Double(-points))
        if let e = NSEvent(cgEvent: cg) { sv.scrollWheel(with: e) }
        await settle(40)
    }

    /// 창의 목록에서 폴더를 펼친다 — 클릭은 사본에만 보낼 수 있으므로 여기서는 NSOutlineView 의 expandItem 을 부른다 (펼칠 때 읽기·알림은 클릭과 같은 길)
    @discardableResult
    func expandInWindow(_ name: String, level: Int? = nil) async -> Bool {
        guard let o = fileOutline, let item = fileItem(name, level: level, in: o) else { return false }
        o.expandItem(item)
        await waitFileView()
        return o.isItemExpanded(item)
    }

    func fileViewTallyNote() { log("  fileview: \(FileViewTally.checks) list checks, \(FileViewTally.clicks) clicks, \(FileViewTally.keys) keys, \(FileViewTally.crops) crops so far") }
}

// MARK: - 시나리오

extension RealUse {
    @MainActor static let fileViewScenarios: [Scenario] = [
        // 사이드바의 모습: 작은 폴더(한글·긴 이름·텍스트가 아닌 파일·링크·하위 폴더), 현재 문서 강조, 폴더 펼치기(3단계보다 깊게), 밝은/어두운 테마 — PNG 를 눈으로 본다
        Scenario(name: "fileview-look") { ctx in
            let m = ctx.model
            let old = await ctx.showFileView()
            let theme0 = m.themes.current.id
            let small = ctx.makeSmallFolder("fv-look")
            ctx.at("small folder, dark theme")
            m.themes.select(id: ThemeStore.defaultDarkID)
            m.open(url: small.appendingPathComponent("alpha.md")); await ctx.settle(400); await ctx.waitFileView()
            ctx.checkTabs("alpha opened"); ctx.checkAll("alpha opened"); await ctx.checkFileView("alpha opened")
            ctx.snapSidebar("dark-alpha")
            ctx.at("row tooltip and accessibility label")
            if let o = ctx.fileOutline, let r = ctx.fileRow("beta.md"), let cell = o.view(atColumn: 0, row: r, makeIfNecessary: false) as? FileRowCellView {
                let path = small.appendingPathComponent("beta.md").path
                if cell.toolTip != path { ctx.issue("fileview", "the tooltip of the beta.md row is '\(cell.toolTip ?? "nil")', expected the full path \(path)") }
                if cell.accessibilityLabel() != "beta.md" { ctx.issue("fileview", "the accessibility label of the beta.md row is '\(cell.accessibilityLabel() ?? "nil")'") }
            } else { ctx.issue("fileview", "there is no visible row for beta.md") }
            if ctx.fileRow(".hidden.md") != nil { ctx.issue("fileview", "the hidden file .hidden.md is listed") }
            ctx.at("another file in the same folder")
            m.open(url: small.appendingPathComponent("gamma.txt")); await ctx.settle(400); await ctx.waitFileView()
            await ctx.checkFileView("gamma opened")
            ctx.snapSidebar("dark-gamma")
            // 펼치기: docs → deep → deeper → leaf.md (이전 구현은 3단계까지만 읽어 deeper 가 비어 보였다)
            for (i, name) in ["docs", "deep", "deeper"].enumerated() {
                ctx.at("expand \(name)")
                guard await ctx.expandInWindow(name, level: i) else { ctx.issue("fileview", "the folder \(name) (level \(i)) could not be expanded"); break }
                await ctx.checkFileView("\(name) expanded")
            }
            if ctx.fileRow("leaf.md", level: 3) == nil { ctx.issue("fileview", "docs/deep/deeper/leaf.md is not listed after expanding three levels") }
            if m.document.url.lastPathComponent != "gamma.txt" { ctx.issue("fileview", "expanding folders changed the document to \(m.document.url.lastPathComponent)") }
            ctx.snapSidebar("dark-expanded")
            ctx.at("light theme")
            m.themes.select(id: ThemeStore.defaultLightID); await ctx.settle(500)
            await ctx.checkFileView("light theme")
            ctx.snapSidebar("light-expanded")
            ctx.snap("light-window")
            // 목록에 키보드 포커스가 있을 때의 선택 행(강조색 바탕) — 창이 키 창이 아니라 저절로는 그렇게 그려지지 않으므로 행 뷰에 직접 켠다 (모양만 본다)
            ctx.at("selection with keyboard focus")
            if let o = ctx.fileOutline, o.selectedRow >= 0, let rv = o.rowView(atRow: o.selectedRow, makeIfNecessary: false) {
                rv.isEmphasized = true; await ctx.settle(60)
                ctx.snapSidebar("light-focused")
                m.themes.select(id: ThemeStore.defaultDarkID); await ctx.settle(400)
                o.rowView(atRow: o.selectedRow, makeIfNecessary: false)?.isEmphasized = true; await ctx.settle(60)
                ctx.snapSidebar("dark-focused")
                o.rowView(atRow: o.selectedRow, makeIfNecessary: false)?.isEmphasized = false
            }
            // 오른쪽에서 왼쪽으로 쓰는 UI(아랍어): 앱의 언어를 실행 중에 바꿀 수 없으므로 목록의 방향만 뒤집어 모양을 본다 (화살표·아이콘이 오른쪽, 이름은 오른쪽 정렬)
            ctx.at("right-to-left layout")
            if let o = ctx.fileOutline {
                // 행을 다시 배치시키려고 목록을 직접 다시 읽힌다 — NSOutlineView 는 reloadData 에서 선택을 잃으므로(앱에서는 코디네이터가 되살린다) 여기서도 되살린다
                @MainActor func relayout(_ direction: NSUserInterfaceLayoutDirection) async {
                    let selected = o.selectedRowIndexes
                    o.userInterfaceLayoutDirection = direction
                    o.reloadData()
                    o.selectRowIndexes(selected, byExtendingSelection: false)
                    await ctx.settle(150)
                }
                await relayout(.rightToLeft)
                ctx.snapSidebar("dark-rtl")
                if let r = ctx.fileRow("docs", level: 0), let c = ctx.fileRow("beta.md", level: 0) {
                    let arrow = o.frameOfOutlineCell(atRow: r), cell = o.frameOfCell(atColumn: 0, row: c)
                    if arrow.midX < o.bounds.midX { ctx.issue("fileview", "right-to-left: the disclosure arrow of docs is at x \(Int(arrow.minX)), on the left half of a \(Int(o.bounds.width)) pt list") }
                    if cell.minX > 1 || cell.maxX > arrow.minX + 0.5 { ctx.issue("fileview", "right-to-left: the row of beta.md spans x \(Int(cell.minX))…\(Int(cell.maxX)), it should run from the left edge up to the arrow column (\(Int(arrow.minX)))") }
                }
                await relayout(.leftToRight)
                await ctx.checkFileView("back to left-to-right")
            }
            m.themes.select(id: theme0); await ctx.settle(300)
            await ctx.restoreSidebar(old)
            ctx.fileViewTallyNote()
        },

        // 행 클릭으로 파일 열기(사본에 실제 좌표 클릭): 파일 행 · 이미 현재인 행 · 폴더 행 · 화살표로 펼치기/접기 · 펼친 폴더 안의 파일(목록이 그 폴더로 바뀐다) ·
        // 탭으로 돌아오면 펼침이 그대로. 걸음마다 창의 목록도 문서를 따라갔는지 본다
        Scenario(name: "fileview-click") { ctx in
            let m = ctx.model
            let old = await ctx.showFileView()
            let small = ctx.makeSmallFolder("fv-click")
            let alpha = small.appendingPathComponent("alpha.md")
            m.open(url: alpha); await ctx.settle(400)
            guard let po = await ctx.fileProbe() else { ctx.issue("fileview", "the file view probe could not be made"); return }
            await ctx.waitFileView()
            await ctx.checkFileViews("alpha opened")
            ctx.snapProbe("start")
            for name in ["beta.md", "gamma.txt", "회의록 2026-11.md", "alpha.md"] {
                ctx.at("click \(name)")
                guard await ctx.clickFileRow(name) else { ctx.issue("fileview", "could not click the row of \(name)"); continue }
                if m.document.url.lastPathComponent != name { ctx.issue("fileview", "clicked the row of \(name) but the document is \(m.document.url.lastPathComponent)") }
                await ctx.settle(200); await ctx.waitFileView()
                ctx.checkTabs("after clicking \(name)"); ctx.checkAll("after clicking \(name)"); await ctx.checkFileViews("after clicking \(name)")
            }
            ctx.snapProbe("clicked"); ctx.snapSidebar("clicked")
            ctx.at("click the row of the current document")
            let gen = m.document.reloadGeneration, tabs0 = m.tabs
            if await ctx.clickFileRow("alpha.md") {
                await ctx.settle(150)
                if m.document.reloadGeneration != gen { ctx.issue("fileview", "clicking the row of the document that is already open reloaded it from disk") }
                if m.tabs != tabs0 { ctx.issue("fileview", "clicking the current row changed the tabs") }
            } else { ctx.issue("fileview", "could not click the current row") }
            ctx.at("click a folder row")
            if await ctx.clickFileRow("src", level: 0) {
                await ctx.settle(150); await ctx.waitFileView()
                if m.document.url.lastPathComponent != "alpha.md" { ctx.issue("fileview", "clicking a folder row changed the document to \(m.document.url.lastPathComponent)") }
                if po.selectedRow != ctx.fileRow("src", level: 0, in: po) { ctx.issue("fileview", "clicked the folder row src but row \(po.selectedRow) is selected") }
                if ctx.isExpanded("src", level: 0, in: po) { ctx.issue("fileview", "clicking a folder's name expanded it (only the arrow should)") }
                await ctx.checkFileViews("folder row selected", selectionFollowsDocument: false)
                ctx.snapProbe("folder-selected")
            } else { ctx.issue("fileview", "could not click the folder row src") }
            ctx.at("expand and collapse with the arrow")
            for round in 1...4 {
                // 같은 화살표를 다시 누르기까지 사람은 수백 ms 가 걸린다. 0.1 s 안에 다시 누르면 NSOutlineView 가 펼치는 애니메이션 중이라 두 번째 클릭을 받지 않는다
                // (실측 2026-11-24: 0.3 s 간격은 매번 반응, 바로 이어 누르면 무시) — 그것은 AppKit 의 동작이라 여기서는 사람의 간격으로 누른다.
                // 미해결: 전체 묶음의 끝에서는 첫 번째 화살표 클릭(바로 앞 걸음이 같은 행의 이름을 눌렀다)이 통째로 무시되는 일이 있다 (다섯 번 중 세 번. 1초를 기다려도
                // 반영되지 않고 다음 클릭부터는 정상, 단독 실행에서는 안 나온다). 원인을 모르는 채 기다림을 넣어 가리지 않는다 — 아래의 진단 기록을 볼 것
                if round > 1 { try? await Task.sleep(nanoseconds: 400_000_000) }
                guard await ctx.clickFileRow("src", level: 0, spot: .disclosure) else { ctx.issue("fileview", "could not click the disclosure arrow of src"); break }
                await ctx.waitFileView()
                let want = round % 2 == 1
                if ctx.isExpanded("src", level: 0, in: po) != want {
                    ctx.issue("fileview", "clicked the arrow of src (\(want ? "to expand" : "to collapse")) but it is \(want ? "collapsed" : "expanded")")
                    // 진단: 클릭이 무시된 것인가, 늦게 반영되는 것인가
                    let t = CFAbsoluteTimeGetCurrent()
                    var late: Double?
                    for _ in 0..<20 { try? await Task.sleep(nanoseconds: 50_000_000); if ctx.isExpanded("src", level: 0, in: po) == want { late = ctx.elapsedMs(since: t); break } }
                    ctx.note(late.map { String(format: "the arrow click took effect %.0f ms after the check", $0) } ?? "the arrow click had no effect within 1 s of the check")
                }
                if (ctx.fileRow("main.swift", level: 1, in: po) != nil) != want { ctx.issue("fileview", "src is \(want ? "expanded but its files are not listed" : "collapsed but its files are still listed")") }
                if m.document.url.lastPathComponent != "alpha.md" { ctx.issue("fileview", "clicking a disclosure arrow changed the document") }
                await ctx.checkFileViews("src arrow #\(round)", selectionFollowsDocument: false)
            }
            ctx.at("expand docs and open a file in it")
            if await ctx.clickFileRow("docs", level: 0, spot: .disclosure) {
                await ctx.waitFileView()
                if !ctx.isExpanded("docs", level: 0, in: po) { ctx.issue("fileview", "clicked the arrow of docs but it is not expanded") }
                await ctx.checkFileViews("docs expanded", selectionFollowsDocument: false)
                ctx.snapProbe("docs-expanded")
                if await ctx.clickFileRow("guide.md", level: 1) {
                    if m.document.url.lastPathComponent != "guide.md" { ctx.issue("fileview", "clicked docs/guide.md but the document is \(m.document.url.lastPathComponent)") }
                    await ctx.settle(250); await ctx.waitFileView()
                    // 문서의 폴더가 docs 가 됐으므로 목록도 docs 를 보인다 (이전과 같은 동작)
                    ctx.checkTabs("docs/guide.md opened"); ctx.checkAll("docs/guide.md opened"); await ctx.checkFileViews("docs/guide.md opened")
                    ctx.snapProbe("in-docs")
                } else { ctx.issue("fileview", "could not click docs/guide.md") }
            } else { ctx.issue("fileview", "could not click the disclosure arrow of docs") }
            ctx.at("back to alpha by tab")
            m.activateTab(alpha.resolvingSymlinksInPath()); await ctx.settleProbe()
            // 기억해 둔 목록이 첫 화면에 바로 보여야 한다 (다시 읽기를 기다리지 않고), docs 는 펼친 채로
            if let now = ctx.probeOutline {
                if now.numberOfRows == 0 { ctx.issue("fileview", "coming back to a folder that was listed before shows an empty list on the first frame") }
                if !ctx.isExpanded("docs", level: 0, in: now) { ctx.issue("fileview", "docs was expanded when this folder was left but is collapsed after coming back") }
            }
            if ctx.fileOutline?.numberOfRows == 0 { ctx.issue("fileview", "the window's list is empty on the first frame after coming back to a folder that was listed before") }
            await ctx.settle(200); await ctx.waitFileView()
            await ctx.checkFileViews("back on alpha")
            ctx.snapProbe("back-expanded")
            ctx.at("click a file that already has a tab")
            let n = m.tabs.count
            if await ctx.clickFileRow("beta.md", level: 0) {
                await ctx.settle(200); await ctx.waitFileView()
                if m.document.url.lastPathComponent != "beta.md" { ctx.issue("fileview", "clicked beta.md (already a tab) but the document is \(m.document.url.lastPathComponent)") }
                if m.tabs.count != n { ctx.issue("fileview", "clicking a file that already has a tab changed the tab count \(n) → \(m.tabs.count)") }
                ctx.checkTabs("beta by click"); await ctx.checkFileViews("beta by click")
            } else { ctx.issue("fileview", "could not click beta.md") }
            ctx.closeFileProbe()
            await ctx.restoreSidebar(old)
            ctx.fileViewTallyNote()
        },

        // 방향키(창의 목록): 고르면 열린다 (폴더 행은 열지 않는다), → 로 펼치고 ← 로 접는다
        Scenario(name: "fileview-keys") { ctx in
            let m = ctx.model
            let old = await ctx.showFileView()
            let small = ctx.makeSmallFolder("fv-keys")
            m.open(url: small.appendingPathComponent("alpha.md")); await ctx.settle(400); await ctx.waitFileView()
            await ctx.checkFileView("alpha opened")
            guard let o = ctx.fileOutline else { ctx.issue("fileview", "no file list"); return }
            var focus: [String] = []   // 걸음마다 키보드 포커스가 어디 있었나 (기록)
            // 한 걸음: 키를 누르고, 고른 행이 파일이면 그 파일이 열렸는지 · 폴더면 문서가 그대로인지 본다
            @MainActor func step(_ k: RealUseContext.Key) async -> Bool {
                let before = o.selectedRow, doc = m.document.url
                ctx.at("\(k) from row \(before)")
                guard await ctx.fileKey(k) else { return false }
                let now = o.selectedRow
                guard now == before + (k == .down ? 1 : -1), let item = o.item(atRow: now) as? FileItem else {
                    ctx.issue("fileview", "pressed \(k) on row \(before) but the selection is on row \(now)"); return false
                }
                if item.entry.isDirectory {
                    if m.document.url != doc { ctx.issue("fileview", "moving the selection onto the folder \(item.entry.name) changed the document to \(m.document.url.lastPathComponent)") }
                } else if m.document.url.path != item.entry.id {
                    ctx.issue("fileview", "selected \(item.entry.name) with \(k) but the document is \(m.document.url.lastPathComponent)")
                }
                await ctx.settle(150); await ctx.waitFileView()
                focus.append(ctx.window.firstResponder === o ? "list" : (ctx.window.firstResponder === ctx.tv ? "editor" : "other"))
                ctx.checkTabs("after \(k)"); ctx.checkAll("after \(k)")
                await ctx.checkFileView("after \(k)", selectionFollowsDocument: !item.entry.isDirectory)
                return true
            }
            var moved = 0
            for k in [RealUseContext.Key.down, .down, .up, .up] { if await step(k) { moved += 1 } }
            // 위로 올라가 폴더 행까지 (폴더는 맨 위에 모여 있다)
            var tries = 0
            while o.selectedRow > 0, tries < 12, let item = o.item(atRow: o.selectedRow) as? FileItem, !item.entry.isDirectory {
                tries += 1
                if await step(.up) { moved += 1 } else { break }
            }
            ctx.note("\(moved) arrow-key moves on the file list; keyboard focus after each: \(focus)")
            if moved == 0 { ctx.issue("fileview", "arrow keys did not move the selection in the file list") }
            ctx.snapSidebar("on-folder")
            if let item = o.item(atRow: o.selectedRow) as? FileItem, item.entry.isDirectory {
                let doc = m.document.url
                ctx.at("→ expands the folder")
                await ctx.fileKey(.right); await ctx.waitFileView()
                if !o.isItemExpanded(item) { ctx.issue("fileview", "→ on the folder \(item.entry.name) did not expand it") }
                await ctx.checkFileView("→ on a folder", selectionFollowsDocument: false)
                ctx.snapSidebar("expanded-by-key")
                // 펼친 폴더 안으로 ↓: 그 안의 파일이 열리고, 문서의 폴더가 바뀌므로 목록도 그 폴더로 바뀐다 — 키보드 포커스는 새 목록으로 넘어가야 한다
                ctx.at("↓ into the expanded folder")
                if let child = o.item(atRow: o.selectedRow + 1) as? FileItem, !child.entry.isDirectory, RealUseContext.safeToOpen(child.entry) {
                    await ctx.fileKey(.down)
                    if m.document.url.path != child.entry.id { ctx.issue("fileview", "↓ onto \(child.entry.name) inside the expanded folder but the document is \(m.document.url.lastPathComponent)") }
                    await ctx.settle(200); await ctx.waitFileView()
                    await ctx.checkFileView("↓ into a subfolder")
                    // 문서가 열리면 편집기가 키보드 포커스를 가져간다 (EditorView.restoreViewStateIfNeeded → select(focus:) — 파일 보기를 바꾸기 전에도 같았다). 기록만 한다
                    let fr = ctx.window.firstResponder
                    ctx.note("keyboard focus after the list changed to the subfolder: \(fr === ctx.fileOutline ? "file list" : (fr === ctx.tv ? "editor" : "other"))")
                    ctx.snapSidebar("in-subfolder-by-key")
                    m.activateTab(doc); await ctx.settle(200); await ctx.waitFileView()
                    await ctx.checkFileView("back from the subfolder")
                } else { ctx.note("the row under the expanded folder is not a plain file — ↓ into the folder not exercised") }
                ctx.at("← collapses the folder")
                if let back = ctx.fileOutline, let row = ctx.fileRow(item.entry.name, level: 0) {
                    back.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)   // 폴더 행을 고른다 (폴더라 아무것도 열리지 않는다)
                    await ctx.fileKey(.left); await ctx.waitFileView()
                    if ctx.isExpanded(item.entry.name, level: 0) { ctx.issue("fileview", "← on the folder \(item.entry.name) did not collapse it") }
                    if m.document.url != doc { ctx.issue("fileview", "←/→ on a folder changed the document") }
                    await ctx.checkFileView("← on a folder", selectionFollowsDocument: false)
                }
            } else { ctx.note("the selection did not reach a folder row — ←/→ not exercised") }
            // 편집기로 돌아가 글을 칠 수 있는가
            ctx.at("back to the editor")
            ctx.window.makeFirstResponder(ctx.tv)
            let len = ctx.length
            await ctx.type("x")
            if ctx.length != len + 1 { ctx.issue("fileview", "typing in the editor after using the file list changed the length \(len) → \(ctx.length)") }
            await ctx.shortcut("z")
            await ctx.restoreSidebar(old)
            ctx.fileViewTallyNote()
        },

        // 목록이 디스크를 따라가는가: 목록을 읽은 뒤에 생긴 파일을 열 때 · 다른 탭에 가 있는 동안 바뀐 폴더 · 새로 고침 · 펼친 폴더의 변화 · 숨김 파일이 문서일 때
        Scenario(name: "fileview-sync") { ctx in
            let m = ctx.model
            let fm = FileManager.default
            let old = await ctx.showFileView()
            let small = ctx.makeSmallFolder("fv-sync")
            let alpha = small.appendingPathComponent("alpha.md").resolvingSymlinksInPath()
            m.open(url: alpha); await ctx.settle(400)
            guard let po = await ctx.fileProbe() else { ctx.issue("fileview", "the file view probe could not be made"); return }
            await ctx.waitFileView()
            await ctx.checkFileViews("alpha opened")
            // 달라진 것이 없는 폴더로 돌아오면 뒤에서 다시 읽기만 하고 목록은 건드리지 않아야 한다 (이 폴더에는 같은 파일을 가리키는 링크도 있다)
            ctx.at("come back to an unchanged folder")
            let elsewhere = await ctx.openNumbered("fv-unchanged-elsewhere.md", lines: 40)
            await ctx.waitFileView()
            let rebuilds0 = ctx.fileCoord?.rebuildCount ?? -1, loads0u = ctx.fileCoord?.loadCount ?? -1
            for _ in 0..<3 {
                m.activateTab(alpha); await ctx.settle(120); await ctx.waitFileView()
                m.activateTab(elsewhere); await ctx.settle(120); await ctx.waitFileView()
            }
            m.activateTab(alpha); await ctx.settle(120); await ctx.waitFileView()
            if let c = ctx.fileCoord {
                if c.rebuildCount != rebuilds0 { ctx.issue("fileview", "coming back to unchanged folders rebuilt the list \(c.rebuildCount - rebuilds0) times in 7 tab switches (it should only re-read them in the background)") }
                if c.loadCount - loads0u != 7 { ctx.note("7 tab switches between two folders started \(c.loadCount - loads0u) folder reads") }
            }
            await ctx.checkFileViews("back on the unchanged folder")
            ctx.at("open a file created after the list was read")
            let fresh = ctx.writeNumbered("fresh.md", in: small, lines: 50)
            if ctx.fileRow("fresh.md") != nil { ctx.note("fresh.md is already listed before it was opened (a re-read happened in between)") }
            m.open(url: fresh); await ctx.settle(300); await ctx.waitFileView()
            if ctx.fileRow("fresh.md") == nil { ctx.issue("fileview", "a file created after the list was read was opened as a tab but is not listed") }
            ctx.checkTabs("fresh opened"); await ctx.checkFileViews("fresh opened")
            ctx.snapSidebar("fresh")
            ctx.at("the folder changes while another tab is in front")
            if !(await ctx.expandInWindow("src", level: 0)) { ctx.issue("fileview", "src could not be expanded in the window's list") }
            if await ctx.clickFileRow("src", level: 0, spot: .disclosure) { await ctx.waitFileView() } else { ctx.issue("fileview", "could not click the disclosure arrow of src") }
            let other = await ctx.openNumbered("fv-elsewhere.md", lines: 80)
            await ctx.waitFileView()
            await ctx.checkFileViews("elsewhere opened")
            _ = ctx.writeNumbered("added.md", in: small, lines: 20)
            try? fm.removeItem(at: small.appendingPathComponent("gamma.txt"))
            try? fm.createDirectory(at: small.appendingPathComponent("zeta"), withIntermediateDirectories: true)
            _ = ctx.writeNumbered("extra.swift", in: small.appendingPathComponent("src"), lines: 20)
            m.activateTab(alpha); await ctx.settle(200); await ctx.waitFileView()
            for (which, o) in [("the window's list", ctx.fileOutline), ("the probe list", ctx.probeOutline)] {
                if ctx.fileRow("added.md", in: o) == nil { ctx.issue("fileview", "\(which): a file added while another tab was in front is not listed after coming back") }
                if ctx.fileRow("gamma.txt", in: o) != nil { ctx.issue("fileview", "\(which): a file deleted while another tab was in front is still listed after coming back") }
                if !ctx.isExpanded("src", level: 0, in: o) { ctx.issue("fileview", "\(which): src was expanded when the folder was left but is collapsed after coming back") }
                if ctx.fileRow("extra.swift", level: 1, in: o) == nil { ctx.issue("fileview", "\(which): a file added to an expanded subfolder while another tab was in front is not listed after coming back") }
            }
            ctx.checkTabs("back after changes"); await ctx.checkFileViews("back after changes")
            ctx.snapSidebar("after-changes")
            // 새로 고침 버튼은 사본의 것을 누른다 — 사본의 목록만 다시 읽는다 (창의 목록은 그대로여야 한다: 버튼을 누르지 않았으므로)
            ctx.at("refresh button")
            _ = ctx.writeNumbered("refreshed.md", in: small, lines: 20)
            _ = ctx.writeNumbered("refreshed-inside.swift", in: small.appendingPathComponent("src"), lines: 20)
            await ctx.settleProbe(150)
            if ctx.fileRow("refreshed.md", in: po) != nil { ctx.note("refreshed.md is listed before the refresh button was pressed") }
            if await ctx.clickProbeRefresh() {
                await ctx.waitFileView()
                let now = ctx.probeOutline
                if ctx.fileRow("refreshed.md", in: now) == nil { ctx.issue("fileview", "clicked Refresh but a file created just before is not listed") }
                if ctx.fileRow("refreshed-inside.swift", level: 1, in: now) == nil { ctx.issue("fileview", "clicked Refresh but a file created in an expanded subfolder is not listed") }
                if !ctx.isExpanded("src", level: 0, in: now) { ctx.issue("fileview", "Refresh collapsed the expanded folder src") }
                await ctx.checkFileView("after Refresh", probe: true)
                ctx.snapProbe("refreshed")
            } else { ctx.issue("fileview", "clicking the Refresh button of the probe did not make the list re-read its folder") }
            ctx.at("an expanded folder disappears")
            try? fm.removeItem(at: small.appendingPathComponent("src"))
            m.activateTab(other); await ctx.settle(150); await ctx.waitFileView()
            m.activateTab(alpha); await ctx.settle(150); await ctx.waitFileView()
            if ctx.fileRow("src") != nil || ctx.fileRow("main.swift") != nil { ctx.issue("fileview", "a deleted folder (or its files) is still listed after coming back") }
            await ctx.checkFileViews("expanded folder deleted")
            // 숨김 파일은 목록에 없다 — 그 파일이 문서여도 목록을 되풀이해 읽지 않는다
            ctx.at("a hidden file is the document")
            let hidden = small.appendingPathComponent(".hidden.md").resolvingSymlinksInPath()
            let loads0 = ctx.fileCoord?.loadCount ?? 0
            m.open(url: hidden); await ctx.settle(500); await ctx.waitFileView(); await ctx.settle(300)
            let loads = (ctx.fileCoord?.loadCount ?? 0) - loads0
            if loads > 2 { ctx.issue("fileview", "opening a hidden file made the list re-read its folder \(loads) times") }
            if let o = ctx.fileOutline, o.selectedRow >= 0 { ctx.issue("fileview", "the document is a hidden file (not listed) but row \(o.selectedRow) is selected") }
            ctx.checkTabs("hidden file opened"); await ctx.checkFileViews("hidden file opened")
            ctx.note("opening a hidden file: \(loads) folder reads")
            ctx.closeFileProbe()
            await ctx.restoreSidebar(old)
            ctx.fileViewTallyNote()
        },

        // 폴더별 상태: 큰 폴더에서 목록을 굴리고 폴더를 펼친 뒤 다른 탭에 다녀오면 그대로인가 · 빠른 왕복 · 처음 보는 큰 폴더를 읽는 도중에 떠나기
        Scenario(name: "fileview-state") { ctx in
            let m = ctx.model
            let old = await ctx.showFileView()
            var big = ctx.dir, cold = ctx.dir
            ctx.at("build folders")
            await ctx.withRelaxedStalls(120_000) {
                big = ctx.makeFolder("fv-big", files: 5000, dirs: 300, perDir: 6)
                cold = ctx.makeFolder("fv-cold", files: 20_000, dirs: 100, perDir: 1)
            }
            let small = ctx.makeSmallFolder("fv-state")
            let bigDoc = ctx.writeNumbered("main.md", in: big, lines: 300)
            let coldDoc = ctx.writeNumbered("main.md", in: cold, lines: 100)
            let smallDoc = small.appendingPathComponent("alpha.md").resolvingSymlinksInPath()
            m.open(url: smallDoc); await ctx.settle(400); await ctx.waitFileView()
            ctx.at("first visit to the big folder")
            m.open(url: bigDoc)
            await ctx.settle(0)
            let listed = await ctx.waitFileView()
            ctx.note(String(format: "the 5301-entry folder is listed %.0f ms after its first file was opened (%d rows)", listed, ctx.fileOutline?.numberOfRows ?? -1))
            await ctx.checkFileView("big folder listed")
            guard let o = ctx.fileOutline else { ctx.issue("fileview", "no file list"); return }
            ctx.at("scroll the list and expand a folder")
            for _ in 0..<5 { await ctx.scrollFileList(by: 400) }
            let y0 = ctx.fileListScrollY
            if abs(y0 - 2000) > 2 { ctx.issue("fileview", "five 400 pt wheel steps moved the list to \(y0), expected 2000") }
            if await ctx.expandInWindow("dir-090", level: 0) {
                if ctx.fileRow("item-3.md", level: 1) == nil { ctx.issue("fileview", "dir-090 was expanded but its files are not listed") }
            } else { ctx.issue("fileview", "dir-090 could not be expanded") }
            let y1 = ctx.fileListScrollY, rows1 = o.numberOfRows
            await ctx.checkFileView("big folder scrolled and expanded")
            ctx.snapSidebar("big-scrolled")
            for round in 1...3 {
                ctx.at("leave and come back #\(round)")
                m.activateTab(smallDoc); await ctx.settle(150); await ctx.waitFileView()
                await ctx.checkFileView("small folder #\(round)")
                m.activateTab(bigDoc); await ctx.settle(0)
                // 첫 화면에서 이미 떠날 때의 목록 그대로여야 한다 (다시 읽기를 기다리지 않는다)
                guard let back = ctx.fileOutline else { ctx.issue("fileview", "no file list after coming back"); break }
                if back !== o { ctx.issue("fileview", "back on the big folder #\(round): the list view was rebuilt instead of the remembered one being shown again") }
                if back.numberOfRows != rows1 { ctx.issue("fileview", "back on the big folder #\(round): \(back.numberOfRows) rows on the first frame, \(rows1) when it was left") }
                if abs(ctx.fileListScrollY - y1) > 1 { ctx.issue("fileview", "back on the big folder #\(round): the list is scrolled to \(ctx.fileListScrollY), was \(y1) when it was left") }
                if !ctx.isExpanded("dir-090", level: 0) { ctx.issue("fileview", "back on the big folder #\(round): dir-090 is collapsed, it was expanded when the folder was left") }
                await ctx.settle(150); await ctx.waitFileView()
                if abs(ctx.fileListScrollY - y1) > 1 { ctx.issue("fileview", "back on the big folder #\(round): the list moved to \(ctx.fileListScrollY) after the re-read (was \(y1))") }
                await ctx.checkFileView("big folder #\(round)")
            }
            ctx.snapSidebar("big-back")
            ctx.at("rapid switching")
            for i in 0..<30 { m.activateTab(i % 2 == 0 ? smallDoc : bigDoc); await ctx.turn() }
            await ctx.settle(300); await ctx.waitFileView()
            ctx.checkTabs("after rapid switching"); ctx.checkAll("after rapid switching"); await ctx.checkFileView("after rapid switching")
            // 처음 보는 큰 폴더(20,101개 — 읽고 정렬하는 데 0.1 s 넘게 걸린다)의 파일을 열자마자 다른 탭으로: 늦게 온 읽기 결과가 지금 보이는 폴더를 덮으면 안 된다
            ctx.at("leave a folder while it is still being read")
            m.open(url: coldDoc); await ctx.settle(0)
            m.activateTab(smallDoc); await ctx.settle(0)
            let pending = ctx.fileCoord?.pendingLoads ?? 0
            await ctx.checkFileView("small folder right after leaving a folder mid-read")
            let waited = await ctx.waitFileView()
            await ctx.settle(300)
            ctx.note(String(format: "left the 20101-entry folder with %d folder reads still in flight; they finished %.0f ms later", pending, waited))
            if pending == 0 { ctx.note("the folder read had already finished — the late-result path was not exercised in this run") }
            await ctx.checkFileView("small folder after the late result arrived")
            ctx.at("come back to the folder that was left mid-read")
            let s = await ctx.timedSwitch(to: coldDoc)
            ctx.note(String(format: "back on the 20101-entry folder: %d rows on screen, first frame %.0f ms, longest block %.0f ms, the file view's own time %.1f ms", ctx.fileOutline?.numberOfRows ?? -1, s.toFrame, s.block, s.view))
            await ctx.waitFileView()
            ctx.checkTabs("cold folder"); await ctx.checkFileView("cold folder")
            // 기억하는 폴더 수에는 상한이 있다: 그보다 많은 폴더를 돌고 나서 처음 폴더로 돌아와도(잊힌 폴더는 다시 읽는다) 목록이 맞아야 한다
            ctx.at("more folders than the list remembers")
            let limit = FileOutlineCoordinator.folderLimit
            var docs: [URL] = []
            for i in 0..<(limit + 4) {
                let folder = ctx.makeFolder("fv-many-\(i)", files: 3, dirs: 1, perDir: 1)
                docs.append(ctx.writeNumbered("note-\(i).md", in: folder, lines: 20))
            }
            for d in docs { m.open(url: d); await ctx.settle(60); await ctx.waitFileView() }
            await ctx.checkFileView("last of \(docs.count) folders")
            if let c = ctx.fileCoord, c.rememberedFolders > limit { ctx.issue("fileview", "the list remembers \(c.rememberedFolders) folders, the limit is \(limit)") }
            for d in [docs[0], smallDoc, bigDoc, docs[docs.count - 1]] {
                m.activateTab(d); await ctx.settle(120); await ctx.waitFileView()
                await ctx.checkFileView("back on \(d.deletingLastPathComponent().lastPathComponent) after visiting \(docs.count) folders")
            }
            ctx.note("after \(docs.count + 4) more folder visits the list remembers \(ctx.fileCoord?.rememberedFolders ?? -1) folders (limit \(limit))")
            await ctx.restoreSidebar(old)
            ctx.fileViewTallyNote()
        },

        // 파일 보기 시나리오가 찾은 **편집기** 결함의 재현 (파일 보기와 무관 — 사이드바를 아웃라인 탭에 두어 파일 목록이 아예 없다):
        // 처음 여는 파일은 문서 끝으로 스크롤하는데, 줄마다 한글이 많은 문서에서는 그때의 문서 높이(추정)가 곧 줄어들고 스크롤 위치는 그대로 남아
        // 화면이 문서 끝을 지나친다 — 마지막 줄만 맨 위에 보이고 아래는 빈 화면 (2026-11-24: 편집기 폭 757 pt 에서 406 pt 지나침, 1.5 s 뒤에도 그대로)
        Scenario(name: "fileview-editor-end") { ctx in
            let m = ctx.model
            let old = await ctx.showFileView()
            m.leftTab = .outline; await ctx.settle(300)
            // 편집기 폭에 달렸다: 사이드바 460 pt(창을 띄운 직후의 폭, 편집기 757 pt)에서 난다. 사이드바 190 pt(편집기 1027 pt)나 사이드바를 껐을 때는 나지 않았다
            let width0 = ctx.sidebarWidth
            let sidebar = await ctx.setSidebarWidth(460)
            ctx.note("sidebar width \(width0.map { String(Int($0)) } ?? "?") → \(sidebar.map { String(Int($0)) } ?? "unknown (no split view found)") pt")
            let small = ctx.makeSmallFolder("fv-editor-end")
            for name in ["alpha.md", "beta.md", "gamma.txt", "회의록 2026-11.md"] {
                ctx.at("first open of \(name)")
                m.open(url: small.appendingPathComponent(name)); await ctx.settle(400)
                let v = ctx.visible
                ctx.note(String(format: "editor width %.0f: visible %.0f…%.0f, document height %.0f, top line %d", ctx.scroll.frame.width, v.minY, v.maxY, ctx.tv.frame.height, ctx.topLine()))
                ctx.checkLayout("first open of \(name)"); ctx.checkInk("first open of \(name)"); ctx.checkCaretVisible("first open of \(name)")
            }
            ctx.snap("end")
            if let width0 { await ctx.setSidebarWidth(width0) }
            await ctx.restoreSidebar(old)
        },

        // 큰 폴더(최상위 5,000 파일 + 하위 폴더 300개) ↔ 작은 폴더 탭 왕복: 전환 시간과 메인 스레드 정지. 파일 보기를 껐을 때와 비교해 파일 보기의 몫을 본다.
        // (사이드바를 껐다 켜므로 맨 마지막에 둔다 — 다시 켠 사이드바는 폭이 달라져 뒤따르는 시나리오의 그림이 달라진다)
        Scenario(name: "fileview-switch") { ctx in
            let m = ctx.model
            let old = await ctx.showFileView()
            ctx.at("build folders")
            var big = ctx.dir, small = ctx.dir
            await ctx.withRelaxedStalls(60_000) {
                big = ctx.makeFolder("fv-big", files: 5000, dirs: 300, perDir: 6)
                small = ctx.makeFolder("fv-small", files: 6, dirs: 2, perDir: 3)
            }
            let bigDoc = ctx.writeNumbered("main.md", in: big, lines: 300)
            let smallDoc = ctx.writeNumbered("alpha.md", in: small, lines: 300)
            m.open(url: smallDoc); await ctx.settle(500)
            ctx.at("first open in the big folder")
            let lag = MainLagProbe()
            var tFirst = 0.0, firstBlock = 0.0
            await ctx.withRelaxedStalls(30_000) {
                lag.start()
                let t = CFAbsoluteTimeGetCurrent()
                m.open(url: bigDoc); await ctx.settle(0)
                tFirst = ctx.elapsedMs(since: t)
                await ctx.settle(800)
                firstBlock = lag.stop()
            }
            ctx.note(String(format: "first open of a file in the 5300-entry folder: %.0f ms to the first frame, longest main-thread block %.0f ms", tFirst, firstBlock))
            ctx.checkTabs("big folder opened"); ctx.checkAll("big folder opened")
            ctx.snap("big-folder")

            var toSmall: [RealUseContext.SwitchSample] = [], toBig: [RealUseContext.SwitchSample] = []
            for i in 0..<12 {
                ctx.at("switch #\(i + 1) → \(i % 2 == 0 ? "small" : "big") folder")
                let s = await ctx.timedSwitch(to: i % 2 == 0 ? smallDoc : bigDoc)
                if i % 2 == 0 { toSmall.append(s) } else { toBig.append(s) }
                ctx.checkTabs("folder switch #\(i + 1)"); ctx.checkAll("folder switch #\(i + 1)")
            }
            ctx.note("file view shown — to the small folder: first frame \(RealUseContext.stats(toSmall.map(\.toFrame))), longest block \(RealUseContext.stats(toSmall.map(\.block)))")
            ctx.note("file view shown — to the big folder:   first frame \(RealUseContext.stats(toBig.map(\.toFrame))), longest block \(RealUseContext.stats(toBig.map(\.block)))")
            ctx.note("the file view's own main-thread time per switch — to the small folder: \(RealUseContext.stats(toSmall.map(\.view))), to the big folder: \(RealUseContext.stats(toBig.map(\.view)))")
            // 목표: 전환 한 번에 파일 보기의 몫이 한 프레임(16 ms) 이하
            if let worst = (toSmall + toBig).map(\.view).max(), worst > 16 {
                ctx.issue("fileview-perf", String(format: "the file view spent %.1f ms on the main thread in one tab switch (goal: 16 ms or less)", worst), snap: false)
            }
            await ctx.checkFileView("after the switches")
            ctx.snap("after-switches")

            // 모델이 무엇이든 발행하면 파일 보기의 body 가 다시 평가된다 — 큰 폴더를 보이는 채로 다른 패널을 켜고 끌 때
            ctx.at("unrelated model change with the big folder shown")
            var publish: [Double] = [], publishView: [Double] = []
            for _ in 0..<6 {
                let p = MainLagProbe(); p.start()
                FileViewStats.reset()
                m.showBottomPanel.toggle()
                await ctx.settle(250)
                publish.append(p.stop()); publishView.append(FileViewStats.mainMs)
            }
            ctx.note("toggling the bottom panel with the big folder shown — longest block \(RealUseContext.stats(publish)), the file view's own time \(RealUseContext.stats(publishView))")

            ctx.at("same switches with the file view hidden")
            m.showFileView = false; await ctx.settle(400)
            var hiddenSmall: [RealUseContext.SwitchSample] = [], hiddenBig: [RealUseContext.SwitchSample] = []
            for i in 0..<12 {
                let s = await ctx.timedSwitch(to: i % 2 == 0 ? smallDoc : bigDoc)
                if i % 2 == 0 { hiddenSmall.append(s) } else { hiddenBig.append(s) }
            }
            ctx.note("file view hidden — to the small folder: first frame \(RealUseContext.stats(hiddenSmall.map(\.toFrame))), longest block \(RealUseContext.stats(hiddenSmall.map(\.block)))")
            ctx.note("file view hidden — to the big folder:   first frame \(RealUseContext.stats(hiddenBig.map(\.toFrame))), longest block \(RealUseContext.stats(hiddenBig.map(\.block)))")
            let shareSmall = RealUseContext.median(toSmall.map(\.toFrame)) - RealUseContext.median(hiddenSmall.map(\.toFrame))
            let shareBig = RealUseContext.median(toBig.map(\.toFrame)) - RealUseContext.median(hiddenBig.map(\.toFrame))
            ctx.note(String(format: "file view's share of a switch (shown p50 − hidden p50): to small %.1f ms, to big %.1f ms", shareSmall, shareBig))
            // 파일 보기를 다시 켤 때(⌘1)도 큰 폴더를 읽는다
            ctx.at("show the file view again on the big folder")
            let p = MainLagProbe(); p.start()
            FileViewStats.reset()
            m.showFileView = true
            await ctx.settle(600); await ctx.waitFileView()
            ctx.note(String(format: "showing the file view on the big folder: longest block %.0f ms, the file view's own time %.1f ms, sidebar width %.0f pt", p.stop(), FileViewStats.mainMs,
                            ctx.fileOutline?.enclosingScrollView?.frame.width ?? -1))
            await ctx.checkFileView("file view shown again")
            await ctx.restoreSidebar(old)
            ctx.fileViewTallyNote()
        },
    ]
}
