import AppKit
import HyperCore

/// 줄 번호 거터. NSRulerView 는 TextKit 2 NSTextView 의 본문 렌더링을 막는 문제가 있어(실측, macOS 27 SDK)
/// 스크롤뷰 왼쪽에 독립 NSView 로 두고 클립뷰 bounds 변경에 맞춰 다시 그린다.
final class GutterView: NSView {
    weak var textView: NSTextView?
    weak var scrollView: NSScrollView?
    private let documentProvider: () -> MemoDocument?

    private(set) var thickness: CGFloat = 56
    private var numberFont: NSFont = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private var numberColor = NSColor.secondaryLabelColor
    private var currentColor = NSColor.labelColor
    private var bgColor = NSColor.windowBackgroundColor
    private var borderColor = NSColor.separatorColor
    private var lineHighlightColor = NSColor.clear
    /// appearance: 배경 투명도. 1 미만이면 배경을 칠하지 않고(컨테이너 레이어의 α 배경이 비친다) 현재 줄 강조에 같은 α 를 준다
    var surfaceAlpha: CGFloat = 1 { didSet { if surfaceAlpha != oldValue { needsDisplay = true } } }
    private var lastDigits = 0
    /// 한 번의 그리기에서 열거할 프래그먼트 상한 (보이는 줄 수백 + 접힌 높이 0 문단 수천)
    private static let maxFragmentsPerDraw = 5_000

    // fold: 접기 화살표 열 (FoldController 가 설치). 문단 범위(개행 포함)의 시작 오프셋과, 필요할 때만 계산하는 끝 오프셋으로 묻는다
    enum FoldMarker { case foldable, folded }
    static let foldColumnWidth: CGFloat = 14
    var foldMarker: ((_ paragraphStart: Int, _ paragraphEnd: () -> Int) -> FoldMarker?)?
    var onFoldMarkerClick: ((_ paragraphStart: Int, _ paragraphEnd: Int) -> Void)?
    /// 화살표는 두 선분 경로로 그린다 — 글꼴 폴백 글리프나 SF Symbol 렌더링 없이 µs 단위 (거터는 키 입력마다 다시 그려진다)
    private func drawChevron(folded: Bool, centerX: CGFloat, centerY: CGFloat) {
        let r = max(2.5, (numberFont.pointSize - 4) / 2)
        let path = NSBezierPath()
        if folded {   // ›
            path.move(to: NSPoint(x: centerX - r / 2, y: centerY - r))
            path.line(to: NSPoint(x: centerX + r / 2, y: centerY))
            path.line(to: NSPoint(x: centerX - r / 2, y: centerY + r))
        } else {      // ∨
            path.move(to: NSPoint(x: centerX - r, y: centerY - r / 2))
            path.line(to: NSPoint(x: centerX, y: centerY + r / 2))
            path.line(to: NSPoint(x: centerX + r, y: centerY - r / 2))
        }
        path.lineWidth = 1.5
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        (folded ? currentColor : numberColor).setStroke()
        path.stroke()
    }

    init(textView: NSTextView, scrollView: NSScrollView, documentProvider: @escaping () -> MemoDocument?) {
        self.textView = textView
        self.scrollView = scrollView
        self.documentProvider = documentProvider
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    func apply(theme: Theme, baseFont: NSFont) {
        numberFont = NSFont(descriptor: baseFont.fontDescriptor, size: max(9, baseFont.pointSize - 2)) ?? baseFont
        numberColor = theme.foregroundDim.nsColor
        currentColor = theme.foreground.nsColor
        bgColor = theme.background.nsColor
        borderColor = theme.border.nsColor
        lineHighlightColor = theme.lineHighlight.nsColor
        lastDigits = 0
        updateThickness()
        needsDisplay = true
    }

    /// 자릿수에 맞춰 폭 갱신. 바뀌면 컨테이너 재배치.
    func updateThickness() {
        let count = documentProvider()?.lineIndex.lineCount ?? 1
        let digits = max(4, String(count).count)
        guard digits != lastDigits else { return }
        lastDigits = digits
        let w = (String(repeating: "8", count: digits) as NSString).size(withAttributes: [.font: numberFont]).width
        let t = ceil(w) + 18 + Self.foldColumnWidth   // fold: 왼쪽에 화살표 열
        if abs(t - thickness) > 0.5 {
            thickness = t
            superview?.needsLayout = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Perf.measure("GutterView.draw", threshold: 2) { drawImpl(dirtyRect) }
    }

    private func drawImpl(_ dirtyRect: NSRect) {
        if surfaceAlpha >= 1 {   // appearance: 반투명이면 컨테이너 레이어가 배경을 맡는다
            bgColor.setFill()
            bounds.fill()
        }
        defer {
            borderColor.setFill()
            NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
        }
        guard let tv = textView, let lm = tv.textLayoutManager, let cs = tv.textContentStorage,
              let doc = documentProvider() else { return }
        updateThickness()
        let index = doc.lineIndex
        let visible = tv.visibleRect
        let origin = tv.textContainerOrigin
        let caretLine = index.lineNumber(forUTF16Offset: tv.selectedRange().location)
        let attrs: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: numberColor]
        let curAttrs: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: currentColor]
        let startPoint = CGPoint(x: 0, y: max(0, visible.minY - origin.y))
        let startLocation = lm.textLayoutFragment(for: startPoint)?.rangeInElement.location ?? lm.documentRange.location
        // 보이는 영역의 끝 문단: 전체 속성 재적용 직후에는 프래그먼트 프레임이 추정값(높이 0·엉뚱한 y)이라 프레임만으로는 멈출 수 없다 —
        // 점 질의로 끝 위치를 구해 그 문단을 지나면 멈춘다 (안 그러면 문서 끝까지 배치하며 열거해 8 MB 문서의 테마 전환이 20 s 걸린다, 실측)
        let endPoint = CGPoint(x: 0, y: max(0, visible.maxY - origin.y))
        let endLocation = lm.textLayoutFragment(for: endPoint)?.rangeInElement.endLocation
        // 전체 속성 재적용 직후 프레임 y 는 추정값이라 '보이는 영역을 지났다' 판정이 안 걸릴 수 있다(실측: 5,000개까지 열거) →
        // 시작 문단부터 누적한 높이가 보이는 높이를 넘으면 멈춘다. 추정 프레임으로 그린 번호는 TextKit 이 배치를 마친 뒤의 다음 그리기가 바로잡는다.
        let maxAccumulatedHeight = visible.height + 4 * max(1, (tv.font?.pointSize ?? 14) * 2)
        var visited = 0, zeroHeight = 0
        var accumulated: CGFloat = 0
        lm.enumerateTextLayoutFragments(from: startLocation, options: [.ensuresLayout]) { frag in
            visited += 1
            if visited > Self.maxFragmentsPerDraw { return false }   // 안전장치: 어떤 경우에도 한 번의 그리기가 문서 전체를 배치하지 않게
            if let end = endLocation, frag.rangeInElement.location.compare(end) != .orderedAscending { return false }
            let frame = frag.layoutFragmentFrame
            let yInTextView = frame.minY + origin.y
            if yInTextView > visible.maxY || accumulated > maxAccumulatedHeight { return false }
            accumulated += frame.height
            if frame.height <= 0 { zeroHeight += 1; return true }   // fold: 접힌(높이 0) 문단은 번호를 건너뛴다
            if yInTextView + frame.height < visible.minY { return true }
            let offset = cs.offset(from: cs.documentRange.location, to: frag.rangeInElement.location)
            let line = index.lineNumber(forUTF16Offset: offset)
            let firstLineHeight = frag.textLineFragments.first?.typographicBounds.height ?? frame.height
            let y = yInTextView - visible.minY
            if line == caretLine, tv.selectedRange().length == 0 {
                // 편집기의 현재 줄 강조가 거터까지 이어지도록 같은 색으로 행을 칠한다
                (self.surfaceAlpha < 1 ? self.lineHighlightColor.withAlphaComponent(self.surfaceAlpha) : self.lineHighlightColor).setFill()   // appearance
                NSRect(x: 0, y: y, width: self.bounds.width - 1, height: frame.height).fill(using: .sourceOver)
            }
            let label = String(line) as NSString
            let size = label.size(withAttributes: attrs)
            let x = self.thickness - size.width - 10
            label.draw(at: NSPoint(x: x, y: y + (firstLineHeight - size.height) / 2), withAttributes: line == caretLine ? curAttrs : attrs)
            // fold: 접기 화살표 (∨ 접을 수 있음 · › 접힘)
            if let marker = self.foldMarker?(offset, { cs.offset(from: cs.documentRange.location, to: frag.rangeInElement.endLocation) }) {
                self.drawChevron(folded: marker == .folded, centerX: Self.foldColumnWidth / 2 + 2, centerY: y + firstLineHeight / 2)
            }
            return true
        }
        if Perf.enabled { Perf.log("GutterView.draw visited=\(visited) zeroHeight=\(zeroHeight)") }
    }

    // fold: 화살표 열 클릭 → 그 문단의 접기 토글
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard p.x <= Self.foldColumnWidth + 4, let click = onFoldMarkerClick, let tv = textView,
              let lm = tv.textLayoutManager, let cs = tv.textContentStorage else { super.mouseDown(with: event); return }
        let docY = p.y + tv.visibleRect.minY - tv.textContainerOrigin.y
        guard let frag = lm.textLayoutFragment(for: CGPoint(x: 0, y: docY)), frag.layoutFragmentFrame.height > 0 else { return }
        click(cs.offset(from: cs.documentRange.location, to: frag.rangeInElement.location),
              cs.offset(from: cs.documentRange.location, to: frag.rangeInElement.endLocation))
    }
}

/// [거터 | 스크롤뷰] 를 가로로 배치하는 컨테이너.
final class EditorContainerView: NSView {
    let gutter: GutterView
    let scrollView: NSScrollView
    /// 스크롤바 마커 띠 — 오른쪽 가장자리, 스크롤뷰 위에 겹친다 (markers)
    var markerView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let v = markerView { addSubview(v, positioned: .above, relativeTo: scrollView) }
            needsLayout = true
        }
    }

    init(gutter: GutterView, scrollView: NSScrollView) {
        self.gutter = gutter
        self.scrollView = scrollView
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(scrollView)
        addSubview(gutter)
        NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.needsLayout = true   // markers: 스크롤러 스타일이 바뀌면 띠 위치 재계산
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let t = gutter.isHidden ? 0 : gutter.thickness
        gutter.frame = NSRect(x: 0, y: 0, width: t, height: bounds.height)
        scrollView.frame = NSRect(x: t, y: 0, width: max(0, bounds.width - t), height: bounds.height)
        // markers: 오버레이 스크롤러는 띠 아래로 비치지만, '스크롤 막대 항상 보기'(레거시) 설정이면 트랙이 가려지므로 스크롤러 왼쪽에 둔다
        let scrollerInset = scrollView.scrollerStyle == .legacy && scrollView.hasVerticalScroller
            ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
        markerView?.frame = NSRect(x: bounds.maxX - scrollerInset - ScrollMarkerView.width, y: 0, width: ScrollMarkerView.width, height: bounds.height)
    }
}
