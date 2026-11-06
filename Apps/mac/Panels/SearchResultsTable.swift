import SwiftUI
import AppKit
import Combine
import HyperCore

/// 찾기 결과 목록의 한 행이 될 수 있는 것 (문서 매치 · 파일 매치)
protocol SearchResultRow {
    var rowLine: Int { get }
    var rowText: String { get }
    var rowMatch: NSRange { get }      // rowText 기준
    var rowFile: String? { get }      // 파일 검색이면 파일 이름
    var rowRange: NSRange? { get }    // 문서 매치의 문서 범위 (캐럿 추적용; 파일 매치는 nil)
}

extension SearchHit: SearchResultRow {
    var rowLine: Int { line }
    var rowText: String { lineText }
    var rowMatch: NSRange { matchInLine }
    var rowFile: String? { nil }
    var rowRange: NSRange? { range }
}

extension FileSearchHit: SearchResultRow {
    var rowLine: Int { line }
    var rowText: String { lineText }
    var rowMatch: NSRange { matchInLine }
    var rowFile: String? { fileName }
    var rowRange: NSRange? { nil }
}

/// 코디네이터의 제네릭이 아닌 부분 — 셀프테스트가 문서 결과 목록을 찾는 고리
@MainActor
class SearchResultsCoordinatorBase: NSObject {
    /// 문서 결과 목록(캐럿을 따라가는 쪽)의 코디네이터 (셀프테스트용)
    nonisolated(unsafe) static weak var document: SearchResultsCoordinatorBase?
    weak var table: NSTableView?
    /// 캐럿이 정확히 올라 있는 매치의 행 (없으면 nil)
    private(set) var currentIndex: Int?
    var rowCount: Int { table?.numberOfRows ?? 0 }
    fileprivate func setCurrent(_ i: Int?) { currentIndex = i }
}

/// 찾기 결과 목록 — NSTableView 직접 사용 (perf).
/// SwiftUI `List` 는 결과 1만 건이 같은 id 로 다시 발행될 때(편집 뒤 지연 재검색) 행 전부를 갱신해 메인 스레드를 ~230 ms 잡았고, 현재 행 강조를 위해 캐럿을
/// 구독하면 키 입력마다 1만 행을 다시 평가해 키 입력당 ~10 ms 를 더했다(28 MB 로그, 2026-11-06 벤치 `findui`). NSTableView 는 보이는 행만 만들고
/// `reloadData` 가 행 수와 무관하게 싸며, 현재 행은 바뀐 두 행만 다시 그린다.
struct SearchResultsTable<Item: SearchResultRow>: NSViewRepresentable {
    let items: [Item]
    let generation: Int           // 바뀌었을 때만 다시 읽는다 (같은 배열을 다시 넘겨도 비용 0)
    let resetScrollToken: Int     // 바뀌면 맨 위로 (새 검색). 편집 뒤 지연 재검색은 올리지 않아 스크롤 위치가 유지된다
    let theme: Theme
    let caret: EditorCaret?       // 문서 결과: 캐럿이 매치 위에 있으면 그 행 강조 (파일 결과는 nil)
    let onSelect: (Item) -> Void
    let tooltip: ((Item) -> String?)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .none
        table.allowsEmptySelection = true
        table.allowsMultipleSelection = false
        table.intercellSpacing = .zero
        table.rowHeight = SearchResultCellView.rowHeight
        table.gridStyleMask = []
        table.usesAlternatingRowBackgroundColors = false
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("hit"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.sizeLastColumnToFit()
        let c = context.coordinator
        table.dataSource = c
        table.delegate = c
        table.target = c
        table.action = #selector(Coordinator.rowClicked(_:))
        table.doubleAction = #selector(Coordinator.rowClicked(_:))
        let sv = NSScrollView()
        sv.documentView = table
        sv.hasVerticalScroller = true
        sv.hasHorizontalScroller = false
        sv.autohidesScrollers = true
        sv.drawsBackground = false
        sv.borderType = .noBorder
        c.table = table
        if caret != nil { SearchResultsCoordinatorBase.document = c }
        c.configure(self)
        return sv
    }

    func updateNSView(_ sv: NSScrollView, context: Context) { context.coordinator.configure(self) }

    static func dismantleNSView(_ sv: NSScrollView, coordinator: Coordinator) { coordinator.tearDown() }

    @MainActor
    final class Coordinator: SearchResultsCoordinatorBase, NSTableViewDataSource, NSTableViewDelegate {
        private(set) var items: [Item] = []
        private var generation = Int.min
        private var resetToken = Int.min
        private var theme: Theme?
        private var onSelect: ((Item) -> Void)?
        private var tooltip: ((Item) -> String?)?
        private weak var caret: EditorCaret?
        private var caretCancellable: AnyCancellable?
        private var caretUpdateScheduled = false

        func configure(_ v: SearchResultsTable) {
            onSelect = v.onSelect
            tooltip = v.tooltip
            if caret !== v.caret { bindCaret(v.caret) }
            // 스크롤 리셋 토큰은 reload 와 무관하게 바로 소비한다 — 결과가 같아 reload 가 없던 사용자 검색의 토큰이 남아 있다가
            // 나중의 조용한 재검색(스크롤 유지가 목적)에서 뒤늦게 맨 위로 튀지 않도록
            let reset = v.resetScrollToken != resetToken
            resetToken = v.resetScrollToken
            var reload = false
            if v.generation != generation { generation = v.generation; items = v.items; reload = true }
            if theme != v.theme { theme = v.theme; reload = true }
            guard let table else { return }
            if reload {
                setCurrent(indexUnderCaret())   // 셀을 만들기 전에 — reloadData 가 현재 행을 바로 강조한다
                Perf.measure("findResults.reload rows=\(items.count)") { table.reloadData() }
            }
            if reset, !items.isEmpty { table.scrollRowToVisible(0) }
        }

        func tearDown() {
            caretCancellable = nil
            if SearchResultsCoordinatorBase.document === self { SearchResultsCoordinatorBase.document = nil }
        }

        // MARK: 현재 행 (캐럿 추적)

        private func bindCaret(_ c: EditorCaret?) {
            caret = c
            caretCancellable = nil
            guard let c else { setCurrent(nil); return }
            // @Published 는 두 값을 따로 보내므로 한 턴 뒤에 한 번만 다시 계산한다 (offset 과 selectionLength 가 둘 다 새 값일 때)
            caretCancellable = c.$offset.map { _ in () }.merge(with: c.$selectionLength.map { _ in () })
                .sink { [weak self] in self?.scheduleCaretUpdate() }
        }

        private func scheduleCaretUpdate() {
            guard !caretUpdateScheduled else { return }
            caretUpdateScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.caretUpdateScheduled = false
                self.applyCurrent(self.indexUnderCaret(), scroll: true)
            }
        }

        /// 캐럿(선택)이 정확히 한 매치와 같으면 그 행 — 결과는 문서 순서라 이진 탐색
        private func indexUnderCaret() -> Int? {
            guard let c = caret, !items.isEmpty, items[0].rowRange != nil else { return nil }
            let off = c.offset, len = c.selectionLength
            var lo = 0, hi = items.count
            while lo < hi { let m = (lo + hi) / 2; if (items[m].rowRange?.location ?? 0) < off { lo = m + 1 } else { hi = m } }
            var i = lo
            while i < items.count, let r = items[i].rowRange, r.location == off {
                if r.length == len { return i }
                i += 1
            }
            return nil
        }

        private func applyCurrent(_ new: Int?, scroll: Bool) {
            guard new != currentIndex else { return }
            let old = currentIndex
            setCurrent(new)
            guard let table else { return }
            var rows = IndexSet()
            if let o = old, o < table.numberOfRows { rows.insert(o) }
            if let n = new, n < table.numberOfRows { rows.insert(n) }
            if !rows.isEmpty { table.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0)) }
            if scroll, let n = new { table.scrollRowToVisible(n) }
        }

        // MARK: NSTableView

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let id = NSUserInterfaceItemIdentifier("hitCell")
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? SearchResultCellView) ?? { let v = SearchResultCellView(); v.identifier = id; return v }()
            guard row < items.count, let theme else { return cell }
            let item = items[row]
            cell.set(item: item, isCurrent: row == currentIndex, theme: theme)
            cell.toolTip = tooltip?(item)
            cell.onPress = { [weak self] in self?.onSelect?(item) }   // VoiceOver 의 VO-Space (접근성 활성화)
            return cell
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }   // 선택 상태 없음 — 현재 행은 캐럿이 정한다

        @objc func rowClicked(_ sender: Any?) {
            guard let table, table.clickedRow >= 0, table.clickedRow < items.count else { return }
            onSelect?(items[table.clickedRow])
        }
    }
}

/// 한 행: [파일 이름 140pt] · 줄 번호(56pt, 오른쪽 정렬) · 본문 한 줄(매치는 굵게 + 선택색 배경, 넘치면 … )
final class SearchResultCellView: NSView {
    static let rowHeight: CGFloat = 18
    private static let numberFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private static let textFont = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular)
    private static let boldFont = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .bold)
    private var line = 0
    private var text = ""
    private var match = NSRange(location: 0, length: 0)
    private var file: String?
    private var isCurrent = false
    private var theme: Theme?
    var onPress: (() -> Void)?

    override var isFlipped: Bool { true }

    func set<Item: SearchResultRow>(item: Item, isCurrent: Bool, theme: Theme) {
        line = item.rowLine; text = item.rowText; match = item.rowMatch; file = item.rowFile
        self.isCurrent = isCurrent
        self.theme = theme
        setAccessibilityLabel([file, String(line), text].compactMap { $0 }.joined(separator: " "))
        needsDisplay = true
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .staticText }
    override func accessibilityPerformPress() -> Bool { guard let onPress else { return false }; onPress(); return true }

    override func draw(_ dirtyRect: NSRect) {
        guard let theme else { return }
        if isCurrent { theme.selection.nsColor.withAlphaComponent(0.5).setFill(); bounds.fill() }
        let h = bounds.height
        var x: CGFloat = 8
        if let file {
            let ps = NSMutableParagraphStyle(); ps.lineBreakMode = .byTruncatingMiddle
            NSAttributedString(string: file, attributes: [.font: Self.numberFont, .foregroundColor: theme.accent.nsColor, .paragraphStyle: ps])
                .draw(with: NSRect(x: x, y: (h - 14) / 2, width: 140, height: 14), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            x += 148
        }
        let np = NSMutableParagraphStyle(); np.alignment = .right; np.lineBreakMode = .byClipping
        NSAttributedString(string: String(line), attributes: [.font: Self.numberFont, .foregroundColor: (isCurrent ? theme.accent : theme.foregroundDim).nsColor, .paragraphStyle: np])
            .draw(with: NSRect(x: x, y: (h - 14) / 2, width: 56, height: 14), options: [.usesLineFragmentOrigin])
        x += 64
        let tp = NSMutableParagraphStyle(); tp.lineBreakMode = .byTruncatingTail
        tp.alignment = .left   // RTL UI 에서도 열이 어긋나지 않게 (쓰기 방향은 natural 그대로)
        let s = NSMutableAttributedString(string: text, attributes: [.font: Self.textFont, .foregroundColor: theme.foreground.nsColor, .paragraphStyle: tp])
        let safe = NSIntersectionRange(match, NSRange(location: 0, length: s.length))
        if safe.length > 0 { s.addAttributes([.font: Self.boldFont, .backgroundColor: theme.selection.nsColor], range: safe) }
        s.draw(with: NSRect(x: x, y: (h - 15) / 2, width: max(0, bounds.width - x - 8), height: 15), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
