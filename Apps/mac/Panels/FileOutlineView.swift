import SwiftUI
import AppKit
import HyperCore

/// 파일 보기의 목록 — NSOutlineView 직접 사용 (perf).
///
/// 이전에는 SwiftUI `List` + `OutlineGroup` 에 폴더 3단계를 미리 다 읽어 넣었다. 최상위 5,300개인 폴더에서 탭을 오가면 전환마다 메인 스레드가
/// 1.6–2.0 s 멈췄고(읽기·정렬은 그중 일부, 나머지는 행 수천 개의 구성·비교), 그 폴더를 보이는 동안에는 모델이 무엇을 발행하든(하단 패널 켜기 등)
/// 1.5 s 가 걸렸다 (실사용 하네스 `fileview-switch`, 2026-11-24). 여기서는
///  - 폴더는 한 단계만, 백그라운드에서 읽는다. 하위 폴더는 펼칠 때 읽는다
///  - 본 폴더는 목록 뷰째로 기억해 둔다: 탭으로 돌아오면 그 뷰를 다시 끼우기만 하고(행 수와 무관), 뒤에서 다시 읽어 달라졌을 때만 고친다.
///    펼침·스크롤 위치·고른 행이 폴더별로 남는다
///  - NSOutlineView 는 보이는 행만 만든다. 현재 문서가 바뀌면 보이는 행의 표시만 고친다
struct FileOutline: NSViewRepresentable {
    let root: URL
    /// 현재 문서 (심볼릭 링크를 푼 경로)
    let currentID: String
    let theme: Theme
    /// 바뀌면 폴더를 다시 읽는다 (새로 고침 버튼)
    let refresh: Int
    let onOpen: (URL) -> Void

    func makeCoordinator() -> FileOutlineCoordinator { FileOutlineCoordinator() }

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        context.coordinator.container = container
        context.coordinator.configure(self)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) { context.coordinator.configure(self) }
}

/// 개요 뷰의 항목 (참조 — NSOutlineView 는 항목의 정체성으로 행·펼침을 기억한다).
/// 바뀌는 상태는 메인 스레드에서만 읽고 쓴다. 백그라운드 읽기는 항목을 들고 갔다가 그대로 돌려주며, 그동안 읽는 것은 불변인 `entry` 뿐이다 (그래서 @unchecked Sendable)
final class FileItem: NSObject, @unchecked Sendable {
    let entry: FileEntry
    /// 읽어 온 자식 (폴더만). nil = 아직 읽지 않았다 — 펼칠 때 읽는다
    var children: [FileItem]?
    var isLoading = false
    /// 다시 읽었더니 사라진 항목은 false — 늦게 온 읽기 결과를 얹지 않는다
    private(set) var isAttached = true
    /// 데이터 소스가 범위 밖 인덱스를 받았을 때 돌려주는 빈 항목 (일어나면 안 되지만 죽지는 않게)
    static let missing = FileItem(FileEntry(path: "", id: "", name: "", isDirectory: false, isText: true))

    init(_ entry: FileEntry) { self.entry = entry }

    func detach() {
        isAttached = false
        children?.forEach { $0.detach() }
    }
}

/// 파일 보기가 메인 스레드에서 쓴 시간(ms) — 실사용 하네스와 `--debug-perf` 만 잰다 (평소에는 재지 않는다)
@MainActor
enum FileViewStats {
    static let enabled = RealUse.enabled || Perf.enabled
    private(set) static var mainMs = 0.0
    private static var depth = 0

    static func reset() { mainMs = 0 }

    static func measure<T>(_ body: () -> T) -> T {
        guard enabled else { return body() }
        depth += 1
        let t = CFAbsoluteTimeGetCurrent()
        defer {
            depth -= 1
            if depth == 0 { mainMs += (CFAbsoluteTimeGetCurrent() - t) * 1000 }   // 겹친 호출(reloadData 안의 데이터 소스 호출)은 바깥 것만 센다
        }
        return body()
    }
}

@MainActor
final class FileOutlineCoordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
    /// 루트 폴더 하나: 읽어 온 항목과 그것을 보이는 목록 뷰. 탭을 오갈 때 다시 만들지 않으려고 폴더별로 기억한다.
    /// 메인 스레드에서만 읽고 쓴다 (백그라운드 읽기는 결과를 얹을 대상으로 들고 갔다가 돌려줄 뿐이다 — 그래서 @unchecked Sendable)
    final class Folder: @unchecked Sendable {
        let url: URL
        let key: String
        let outline: FileOutlineView
        let scrollView: NSScrollView
        var items: [FileItem] = []
        /// 최상위 항목: id → 항목 (현재 문서의 행을 찾는다 — 트리를 걷지 않는다)
        var top: [String: FileItem] = [:]
        var loaded = false
        /// 읽기가 진행 중인가 — 폴더마다 한 번에 하나만 읽는다 (느린 볼륨에서 탭을 오갈 때마다 읽기가 쌓이지 않게). 그동안 온 요청은 끝난 뒤 한 번 더 읽는다
        var scanning = false
        var rescanWanted = false
        /// 펼친 폴더의 id (목록을 다시 읽어 끼운 뒤 되살린다)
        var expanded: Set<String> = []
        var lastUsed = 0
        /// 목록에 없는 현재 문서 때문에 한 번 다시 읽은 id (숨김 파일처럼 끝내 목록에 없는 문서로 되풀이하지 않는다)
        var retriedFor: String?
        /// 지금 보이는 행들에 반영된 현재 문서·테마 (다른 폴더를 보는 동안 바뀐 것은 다시 보일 때 맞춘다)
        var shownCurrentID = ""
        var shownTheme: Theme?

        init(url: URL, outline: FileOutlineView, scrollView: NSScrollView) {
            self.url = url
            key = url.path
            self.outline = outline
            self.scrollView = scrollView
        }
    }

    weak var container: NSView?
    private(set) var folder: Folder?
    private(set) var currentID = ""
    /// 진행 중인 백그라운드 읽기 수 · 지금까지 시작한 읽기 수 (실사용 하네스가 끝나기를 기다리고, 되풀이해 읽지 않는지 본다)
    private(set) var pendingLoads = 0
    private(set) var loadCount = 0
    /// 목록의 구조를 고친 횟수 (실사용 하네스: 달라진 것이 없는 폴더를 다시 읽었을 때 목록을 건드리지 않는지 본다)
    private(set) var rebuildCount = 0
    private var folders: [String: Folder] = [:]
    /// 기억하고 있는 폴더 수 (실사용 하네스: 상한을 넘으면 잊는지 본다)
    var rememberedFolders: Int { folders.count }
    static var folderLimit: Int { maxFolders }
    private var tick = 0
    private var theme: Theme?
    private var onOpen: ((URL) -> Void)?
    private var refreshToken = 0
    private var latest: FileOutline?
    /// 프로그램이 선택·구조를 바꾸는 중 — 선택 알림으로 파일을 열지 않는다
    private var syncing = false
    private var deferred: [() -> Void] = []
    private static let queue = DispatchQueue(label: "hyperedit.fileview.scan", qos: .userInitiated, attributes: .concurrent)
    /// 기억해 두는 폴더 수 · 항목 수의 상한 (넘으면 오래 안 본 폴더부터 잊는다)
    private static let maxFolders = 12, maxItems = 120_000

    // MARK: 갱신 (SwiftUI → 여기)

    func configure(_ v: FileOutline) {
        onOpen = v.onOpen
        latest = v
        whenIdle { [weak self] in self?.update() }
    }

    private func update() {
        guard let v = latest else { return }
        FileViewStats.measure {
            theme = v.theme
            if folder?.key != v.root.path {
                show(v.root, current: v.currentID)
            } else if let f = folder {
                if v.refresh != refreshToken { reload(f) }
                let moved = v.currentID != currentID
                currentID = v.currentID
                syncRows(of: f, selectCurrent: moved)
                if moved { listCurrentIfMissing(in: f) }
            }
            refreshToken = v.refresh
        }
    }

    /// 목록이 마우스를 추적하는 동안(누르고 있는 동안)에는 목록을 갈아 끼우지 않는다 — 뗀 뒤에 한다
    private func whenIdle(_ work: @escaping () -> Void) {
        if folder?.outline.isTrackingMouse == true { deferred.append(work) } else { work() }
    }

    private func runDeferred() {
        let work = deferred
        deferred = []
        work.forEach { $0() }
    }

    // MARK: 폴더 전환

    private func makeFolder(_ url: URL) -> Folder {
        let outline = FileOutlineView()
        outline.headerView = nil
        outline.style = .plain
        outline.backgroundColor = .clear
        outline.selectionHighlightStyle = .regular
        outline.allowsEmptySelection = true
        outline.allowsMultipleSelection = false
        outline.allowsTypeSelect = false          // 글자를 치면 행을 고르는 기능 — 고르면 곧 열리므로 끈다 (이전 목록에도 없었다)
        outline.intercellSpacing = .zero
        outline.rowHeight = FileRowCellView.rowHeight
        outline.indentationPerLevel = FileRowCellView.indent
        outline.gridStyleMask = []
        outline.usesAlternatingRowBackgroundColors = false
        outline.focusRingType = .none
        outline.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outline.autoresizesOutlineColumn = false  // 펼친 항목에 맞춰 열을 넓히지 않는다 (가로 스크롤이 생긴다) — 긴 이름은 줄임표
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        col.resizingMask = .autoresizingMask
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.sizeLastColumnToFit()
        outline.dataSource = self
        outline.delegate = self
        outline.afterMouse = { [weak self] in self?.runDeferred() }
        let sv = NSScrollView()
        sv.documentView = outline
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.borderType = .noBorder
        sv.autoresizingMask = [.width, .height]
        let f = Folder(url: url, outline: outline, scrollView: sv)
        outline.folder = f
        folders[f.key] = f
        return f
    }

    private func show(_ root: URL, current id: String) {
        tick += 1
        let f = folders[root.path] ?? makeFolder(root)
        f.lastUsed = tick
        let old = folder
        folder = f
        currentID = id
        if old !== f {
            // 목록에 키보드 포커스가 있었으면(방향키로 고르는 중) 새 목록으로 넘긴다
            let hadFocus = old.map { $0.outline.window?.firstResponder === $0.outline } ?? false
            old?.scrollView.removeFromSuperview()
            if let container {
                f.scrollView.frame = container.bounds
                container.addSubview(f.scrollView)
            }
            if hadFocus { f.outline.window?.makeFirstResponder(f.outline) }
        }
        forgetOldFolders()
        syncRows(of: f, selectCurrent: true)
        reload(f)   // 기억한 목록이 있어도 뒤에서 다시 읽는다 — 달라졌을 때만 화면을 고친다
    }

    private func forgetOldFolders() {
        var total = folders.values.reduce(0) { $0 + $1.items.count }
        while folders.count > Self.maxFolders || total > Self.maxItems {
            guard let oldest = folders.values.filter({ $0 !== folder }).min(by: { $0.lastUsed < $1.lastUsed }) else { return }
            folders[oldest.key] = nil
            total -= oldest.items.count
        }
    }

    // MARK: 읽기 (백그라운드) → 적용 (메인)

    /// 백그라운드 읽기 하나의 결과. `entries` 가 nil 이면 알고 있던 목록과 같다
    private struct Scan: @unchecked Sendable {
        let item: FileItem?          // nil = 루트
        let entries: [FileEntry]?
        /// 처음 읽는 루트는 항목 객체와 id 사전까지 백그라운드에서 만들어 온다 (5,000개면 메인에서 몇 ms 가 든다)
        var built: (items: [FileItem], top: [String: FileItem])?
    }

    nonisolated private static func index(_ items: [FileItem]) -> [String: FileItem] {
        Dictionary(items.map { ($0.entry.id, $0) }, uniquingKeysWith: { a, _ in a })   // 같은 파일을 가리키는 링크가 있으면 먼저 오는 행
    }

    /// 루트와 이미 읽어 둔 하위 폴더를 다시 읽는다. 화면은 달라진 폴더만 고친다
    private func reload(_ f: Folder) {
        guard !f.scanning else { f.rescanWanted = true; return }
        f.scanning = true
        var jobs: [(item: FileItem?, url: URL, known: [FileItem]?)] = [(nil, f.url, f.loaded ? f.items : nil)]
        func collect(_ items: [FileItem]) {
            for item in items {
                guard item.entry.isDirectory else { break }   // 폴더가 먼저 온다
                guard let c = item.children else { continue }
                jobs.append((item, item.entry.url, c))
                collect(c)
            }
        }
        collect(f.items)
        pendingLoads += 1
        loadCount += 1
        Self.queue.async { [weak self] in
            let results = jobs.map { job -> Scan in
                var scan = Scan(item: job.item, entries: FileTree.rescan(job.url, known: job.known?.map(\.entry)))
                if job.item == nil, job.known == nil, let entries = scan.entries {
                    let items = entries.map(FileItem.init)
                    scan.built = (items, Self.index(items))
                }
                return scan
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.whenIdle {
                    self.pendingLoads -= 1
                    f.scanning = false
                    self.apply(results, to: f)
                    // 읽는 동안 온 요청(새로 고침·새 파일): 그 뒤의 디스크를 한 번 더 본다 (apply 가 이미 다시 읽기 시작했으면 그것으로 충분하다)
                    if f.rescanWanted {
                        f.rescanWanted = false
                        if !f.scanning { self.reload(f) }
                    }
                }
            }
        }
    }

    private func apply(_ results: [Scan], to f: Folder) {
        FileViewStats.measure {
            var rootChanged = false
            var changed: [FileItem] = []
            for scan in results {
                guard let entries = scan.entries else { continue }   // 달라진 것 없음
                if let item = scan.item {
                    guard item.isAttached else { continue }          // 그 사이 목록에서 빠진 폴더
                    item.children = merge(item.children ?? [], entries)
                    changed.append(item)
                } else {
                    if let built = scan.built, f.items.isEmpty {
                        f.items = built.items
                        f.top = built.top
                    } else {
                        f.items = merge(f.items, entries)
                        f.top = Self.index(f.items)
                    }
                    rootChanged = true
                }
            }
            f.loaded = true
            // 보고 있지 않은 폴더의 목록도 바로 고쳐 둔다 — 항목과 목록 뷰가 어긋나는 때가 없다
            if rootChanged {
                restructure(f) { outline in
                    outline.reloadData()
                    restoreExpansion(f.items, in: f)
                }
            } else if !changed.isEmpty {
                restructure(f) { outline in
                    for item in changed {
                        outline.reloadItem(item, reloadChildren: true)
                        restoreExpansion(item.children ?? [], in: f)
                    }
                }
            }
            listCurrentIfMissing(in: f)
        }
    }

    /// 새 목록의 항목을 만든다. 그대로인 항목은 옛 객체를 쓴다 — 펼침과 읽어 둔 자식이 유지된다
    private func merge(_ old: [FileItem], _ entries: [FileEntry]) -> [FileItem] {
        if old.isEmpty { return entries.map(FileItem.init) }
        var byName = [String: FileItem](minimumCapacity: old.count)   // 이름은 폴더 안에서 하나뿐이다
        for item in old { byName[item.entry.name] = item }
        var out: [FileItem] = []
        out.reserveCapacity(entries.count)
        for e in entries {
            if let kept = byName[e.name], kept.entry == e { out.append(kept); byName[e.name] = nil } else { out.append(FileItem(e)) }
        }
        byName.values.forEach { $0.detach() }
        return out
    }

    /// 폴더를 펼쳤는데 아직 읽지 않았다 → 읽어서 끼운다
    private func loadChildren(of item: FileItem, in f: Folder) {
        guard !item.isLoading else { return }
        item.isLoading = true
        let url = item.entry.url
        pendingLoads += 1
        loadCount += 1
        Self.queue.async { [weak self] in
            let entries = FileTree.list(url)
            DispatchQueue.main.async {
                guard let self else { return }
                self.whenIdle {
                    self.pendingLoads -= 1
                    self.finishLoad(of: item, entries, in: f)
                }
            }
        }
    }

    private func finishLoad(of item: FileItem, _ entries: [FileEntry], in f: Folder) {
        FileViewStats.measure {
            item.isLoading = false
            guard item.isAttached, item.children == nil else { return }
            let children = entries.map(FileItem.init)
            item.children = children
            restructure(f) { outline in
                outline.reloadItem(item, reloadChildren: true)
                restoreExpansion(children, in: f)
            }
        }
    }

    // MARK: 선택 · 현재 문서

    private func selectedItem(in f: Folder) -> FileItem? {
        f.outline.selectedRow >= 0 ? f.outline.item(atRow: f.outline.selectedRow) as? FileItem : nil
    }

    private func currentRow(in f: Folder) -> Int {
        guard f === folder, let item = f.top[currentID] else { return -1 }
        return f.outline.row(forItem: item)
    }

    /// 목록의 구조를 바꾼다: 그동안 선택 알림을 막고(파일을 열지 않게), 끝나면 고른 항목을 다시 고른다 (없어졌으면 현재 문서)
    private func restructure(_ f: Folder, _ body: (FileOutlineView) -> Void) {
        let kept = selectedItem(in: f)
        rebuildCount += 1
        syncing = true
        defer { syncing = false }
        body(f.outline)
        let row = kept.map { f.outline.row(forItem: $0) } ?? -1
        select(row: row >= 0 ? row : currentRow(in: f), in: f)
    }

    private func select(row: Int, in f: Folder) {
        let was = syncing
        syncing = true
        defer { syncing = was }
        if row < 0 {
            if f.outline.selectedRow >= 0 { f.outline.deselectAll(nil) }
        } else if f.outline.selectedRow != row {
            f.outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
    }

    /// 보이는 행들을 지금의 현재 문서·테마에 맞춘다 (바뀐 것이 없으면 아무것도 하지 않는다). `selectCurrent`: 현재 문서의 행을 고른다
    private func syncRows(of f: Folder, selectCurrent: Bool) {
        guard f === folder, let theme else { return }
        if f.shownCurrentID != currentID || f.shownTheme != theme {
            f.shownCurrentID = currentID
            f.shownTheme = theme
            let outline = f.outline, current = currentID
            outline.enumerateAvailableRowViews { rowView, row in
                guard let cell = rowView.view(atColumn: 0) as? FileRowCellView else { return }
                cell.theme = theme
                cell.isCurrent = (outline.item(atRow: row) as? FileItem)?.entry.id == current
            }
        }
        if selectCurrent { select(row: currentRow(in: f), in: f) }
    }

    /// 같은 폴더에 새로 만든 파일(⌘N)이나 목록을 읽은 뒤에 생긴 파일을 탭으로 열면 목록에 없다 → 한 번 다시 읽어 현재 파일이 보이게 한다
    private func listCurrentIfMissing(in f: Folder) {
        guard f === folder, f.loaded, f.top[currentID] == nil, f.retriedFor != currentID else { return }
        f.retriedFor = currentID
        reload(f)
    }

    private func restoreExpansion(_ items: [FileItem], in f: Folder) {
        guard !f.expanded.isEmpty else { return }
        for item in items {
            guard item.entry.isDirectory else { break }   // 폴더가 먼저 온다
            guard f.expanded.contains(item.entry.id) else { continue }
            f.outline.expandItem(item)
            if let c = item.children { restoreExpansion(c, in: f) }
        }
    }

    // MARK: NSOutlineViewDataSource

    private func children(of item: Any?, in outlineView: NSOutlineView) -> [FileItem] {
        if let item = item as? FileItem { return item.children ?? [] }
        return (outlineView as? FileOutlineView)?.folder?.items ?? []
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { children(of: item, in: outlineView).count }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let list = children(of: item, in: outlineView)
        return index < list.count ? list[index] : FileItem.missing
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? FileItem)?.entry.isDirectory ?? false }

    // MARK: NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        FileViewStats.measure { () -> NSView? in
            let id = NSUserInterfaceItemIdentifier("fileRow")
            let cell = (outlineView.makeView(withIdentifier: id, owner: nil) as? FileRowCellView) ?? { let v = FileRowCellView(); v.identifier = id; return v }()
            guard let item = item as? FileItem, let theme else { return cell }
            cell.userInterfaceLayoutDirection = outlineView.userInterfaceLayoutDirection
            cell.set(entry: item.entry, isCurrent: item.entry.id == currentID, theme: theme)
            return cell
        }
    }

    /// 한 번 클릭(또는 방향키로 고름)으로 파일을 연다. 폴더 행은 고르기만 한다
    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !syncing, let f = (notification.object as? FileOutlineView)?.folder, f === folder,
              let item = selectedItem(in: f), item !== FileItem.missing, !item.entry.isDirectory, item.entry.id != currentID else { return }
        onOpen?(item.entry.url)
    }

    func outlineViewItemWillExpand(_ notification: Notification) {
        guard let f = (notification.object as? FileOutlineView)?.folder, let item = notification.userInfo?["NSObject"] as? FileItem, item.children == nil else { return }
        loadChildren(of: item, in: f)
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard let f = (notification.object as? FileOutlineView)?.folder, let item = notification.userInfo?["NSObject"] as? FileItem else { return }
        f.expanded.insert(item.entry.id)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        // 목록을 다시 읽어 끼우는 중의 알림은 사용자가 접은 것이 아니다
        guard !syncing, let f = (notification.object as? FileOutlineView)?.folder, let item = notification.userInfo?["NSObject"] as? FileItem else { return }
        f.expanded.remove(item.entry.id)
    }
}

final class FileOutlineView: NSOutlineView {
    /// 이 목록이 보이는 폴더 (데이터 소스가 어느 폴더의 항목을 줄지 안다)
    weak var folder: FileOutlineCoordinator.Folder?
    /// mouseDown 의 추적 루프 안인가 — 그동안에는 코디네이터가 목록을 갈아 끼우지 않는다
    private(set) var isTrackingMouse = false
    var afterMouse: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        isTrackingMouse = true
        super.mouseDown(with: event)
        isTrackingMouse = false
        afterMouse?()
    }

    override func layout() {
        FileViewStats.measure { super.layout() }
    }

    /// 행의 앞쪽 여백 (화살표 앞)
    private static let leading: CGFloat = 3

    /// 펼침 화살표의 자리 (이전 SwiftUI 목록과 같은 자리). 오른쪽에서 왼쪽으로 쓰는 UI(아랍어)에서는 오른쪽 끝에서부터
    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        let r = super.frameOfOutlineCell(atRow: row)
        guard r.width > 0 else { return r }
        let lead = Self.leading + CGFloat(level(forRow: row)) * indentationPerLevel, w = FileRowCellView.disclosureWidth
        return NSRect(x: userInterfaceLayoutDirection == .rightToLeft ? bounds.maxX - lead - w : lead, y: r.minY, width: w, height: r.height)
    }

    /// 셀은 화살표 자리 바로 뒤부터 행의 끝까지 — 화살표가 없는 파일 행도 같은 자리에서 시작해 아이콘이 한 줄로 선다
    override func frameOfCell(atColumn column: Int, row: Int) -> NSRect {
        var r = super.frameOfCell(atColumn: column, row: row)
        let lead = Self.leading + FileRowCellView.disclosureWidth + CGFloat(max(0, level(forRow: row))) * indentationPerLevel
        let full = rect(ofColumn: column)
        r.origin.x = userInterfaceLayoutDirection == .rightToLeft ? full.minX : full.minX + lead
        r.size.width = max(0, full.width - lead)
        return r
    }
}

/// 한 행: 아이콘(11 pt) 이름(11.5 pt, 넘치면 …). 현재 문서는 굵게·강조색, 텍스트가 아닌 파일은 흐리게
final class FileRowCellView: NSTableCellView {
    static let rowHeight: CGFloat = 24
    static let indent: CGFloat = 16
    static let disclosureWidth: CGFloat = 16
    /// 셀 안에서 아이콘이 시작하는 x
    private static let iconX: CGFloat = 7
    private static let font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
    private static let currentFont = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
    private static func paragraph(_ alignment: NSTextAlignment) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byTruncatingTail
        p.alignment = alignment
        return p
    }
    private static let leftParagraph = paragraph(.left), rightParagraph = paragraph(.right)
    private static var symbols: [String: NSImage] = [:]

    private var entry: FileEntry?
    var isCurrent = false { didSet { if isCurrent != oldValue { needsDisplay = true } } }
    var theme: Theme? { didSet { if theme != oldValue { needsDisplay = true } } }

    override var isFlipped: Bool { true }
    /// 선택된 행이 강조색으로 칠해지면(목록에 포커스) 글자를 흰색으로 바꿔 그린다
    override var backgroundStyle: NSView.BackgroundStyle { didSet { if backgroundStyle != oldValue { needsDisplay = true } } }

    func set(entry: FileEntry, isCurrent: Bool, theme: Theme) {
        self.entry = entry
        self.isCurrent = isCurrent
        self.theme = theme
        toolTip = entry.path
        setAccessibilityLabel(entry.name)
        needsDisplay = true
    }

    override func isAccessibilityElement() -> Bool { true }

    private static func symbol(_ name: String, color: NSColor, key: String) -> NSImage? {
        let key = name + key
        if let img = symbols[key] { return img }
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular).applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }
        if symbols.count > 64 { symbols.removeAll() }
        symbols[key] = img
        return img
    }

    override func draw(_ dirtyRect: NSRect) {
        FileViewStats.measure {
            guard let entry, let theme else { return }
            // 선택된 행이 강조색 바탕이면 시스템이 정한 글자색(흰색)으로 — 테마 강조색 글자는 강조색 바탕에서 읽히지 않는다
            let emphasized = backgroundStyle == .emphasized
            // 오른쪽에서 왼쪽으로 쓰는 UI 에서는 아이콘이 오른쪽, 이름은 그 왼쪽에 오른쪽 정렬로
            let rtl = userInterfaceLayoutDirection == .rightToLeft
            let h = bounds.height, w = bounds.width
            var used = Self.iconX   // 앞쪽 가장자리에서부터 쓴 폭
            let iconTheme = entry.isDirectory ? theme.accent : theme.foregroundMuted
            let name = entry.isDirectory ? "folder" : (entry.isText ? "doc.text" : "doc")
            if let img = Self.symbol(name, color: emphasized ? .alternateSelectedControlTextColor : iconTheme.nsColor, key: emphasized ? "selected" : iconTheme.hexString) {
                let s = img.size
                img.draw(in: NSRect(x: rtl ? w - used - s.width : used, y: ((h - s.height) / 2).rounded(), width: s.width, height: s.height), from: .zero, operation: .sourceOver,
                         fraction: 1, respectFlipped: true, hints: nil)
                used += s.width + 5
            }
            let font = isCurrent ? Self.currentFont : Self.font
            let color: NSColor = emphasized ? .alternateSelectedControlTextColor
                : (isCurrent ? theme.accent : (entry.isText || entry.isDirectory ? theme.foreground : theme.foregroundMuted)).nsColor
            let textH = ceil(font.ascender - font.descender + font.leading), textW = max(0, w - used - 10)
            NSAttributedString(string: entry.name, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: rtl ? Self.rightParagraph : Self.leftParagraph])
                .draw(with: NSRect(x: rtl ? 10 : used, y: ((h - textH) / 2).rounded(), width: textW, height: textH), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
        }
    }
}
