import AppKit
import Combine
import HyperCore

/// 스크롤바 마커: 편집기 오른쪽 가장자리 12pt 띠에 검색 매치·북마크·캐럿 줄·접힌 머리 줄을 줄 번호 비율로 표시한다.
/// 상호작용 없음(`hitTest` nil) — 아래의 오버레이 스크롤러는 그대로 동작한다. 문서가 한 화면에 다 들어가거나 끈 상태면 투명.
/// 텍스트 뷰 하나에 하나 — EditorContainerView.layout() 이 오른쪽 가장자리에 놓는다.
@MainActor
final class ScrollMarkerView: NSView {
    static let width: CGFloat = 12

    weak var scrollView: NSScrollView?
    private let model: AppModel
    private let documentProvider: () -> MemoDocument?
    /// 접힌 머리 줄들 (FoldController 가 제공)
    var foldLines: (() -> [Int])?

    private var cancellables = Set<AnyCancellable>()
    private var docCancellables = Set<AnyCancellable>()
    private var searchColor = NSColor.controlAccentColor
    private var bookmarkColor = NSColor.systemYellow
    private var caretColor = NSColor.labelColor
    private var foldColor = NSColor.secondaryLabelColor

    init(model: AppModel, scrollView: NSScrollView, documentProvider: @escaping () -> MemoDocument?) {
        self.model = model
        self.scrollView = scrollView
        self.documentProvider = documentProvider
        super.init(frame: .zero)
        wantsLayer = true
        model.$searchHits.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        model.bookmarks.$bookmarks.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        model.$showScrollMarkers.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        // 캐럿 줄은 키 입력마다 바뀐다 — 60 ms 로 묶는다 (publishFirstVisibleLine 과 같은 간격)
        model.caret.$line.removeDuplicates()
            .throttle(for: .milliseconds(60), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        // 문서 높이가 바뀌면(편집·줄바꿈·창 크기) "한 화면에 들어가는가" 가 달라진다
        if let doc = scrollView.documentView {
            NotificationCenter.default.publisher(for: NSView.frameDidChangeNotification, object: doc)
                .throttle(for: .milliseconds(100), scheduler: RunLoop.main, latest: true)
                .sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); needsDisplay = true }

    /// 줄 수 갱신을 구독 (문서를 갈아끼우면 다시 부른다)
    /// 편집기가 닫힐 때: 모델·문서 구독 해제
    func unbind() { cancellables.removeAll(); docCancellables.removeAll() }

    func bind(document doc: MemoDocument) {
        docCancellables.removeAll()
        doc.$lineIndex.receive(on: RunLoop.main).sink { [weak self] _ in self?.needsDisplay = true }.store(in: &docCancellables)
    }

    func apply(theme: Theme) {
        searchColor = theme.accent.nsColor
        bookmarkColor = theme.warningColor.nsColor
        caretColor = theme.foreground.nsColor
        foldColor = theme.foregroundDim.nsColor
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard model.showScrollMarkers, let sv = scrollView, let docView = sv.documentView, let doc = documentProvider() else { return }
        // 스크롤할 것이 없으면 아무것도 그리지 않는다 (투명)
        guard docView.frame.height > sv.contentView.bounds.height + 1 else { return }
        let idx = doc.lineIndex
        let length = doc.textStorage.length
        let lineCount = max(1, idx.lineCount)
        let stale = idx.utf16Count != length          // 편집 직후 250 ms: 줄 인덱스가 낡음 → 검색·캐럿은 문자 오프셋 비율로
        let top: CGFloat = 2
        let h = max(1, bounds.height - 4)
        let w = bounds.width
        func y(line: Int) -> CGFloat { top + CGFloat(max(0, line - 1)) / CGFloat(max(1, lineCount - 1)) * h }
        func y(offset: Int) -> CGFloat { top + CGFloat(max(0, min(offset, length))) / CGFloat(max(1, length)) * h }

        // 접힌 머리 줄: 흐린 1pt 눈금 (오른쪽 절반)
        if let folds = foldLines?(), !folds.isEmpty {
            foldColor.setFill()
            for l in folds { NSRect(x: 4, y: y(line: l), width: w - 5, height: 1).fill() }
        }
        // 검색 매치: 강조색 2pt 눈금 (오른쪽 절반), 최대 3000개
        if !model.searchHits.isEmpty {
            searchColor.setFill()
            for hit in model.searchHits.prefix(3000) {
                let yy = stale ? y(offset: hit.range.location) : y(line: hit.line)
                NSRect(x: 4, y: yy - 1, width: w - 5, height: 2).fill()
            }
        }
        // 북마크: 경고색 3×3 (왼쪽)
        let bms = model.bookmarks.bookmarks
        if !bms.isEmpty {
            bookmarkColor.setFill()
            for b in bms { NSRect(x: 0, y: y(line: b.line) - 1, width: 3, height: 3).fill() }
        }
        // 캐럿 줄: 본문색 1pt 가로선 전체 폭
        let caretY = stale ? y(offset: model.caret.offset) : y(line: model.caret.line)
        caretColor.setFill()
        NSRect(x: 0, y: caretY, width: w, height: 1).fill()
    }
}
