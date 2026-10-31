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
    private var lastDigits = 0

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
        let t = ceil(w) + 18
        if abs(t - thickness) > 0.5 {
            thickness = t
            superview?.needsLayout = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        Perf.measure("GutterView.draw", threshold: 2) { drawImpl(dirtyRect) }
    }

    private func drawImpl(_ dirtyRect: NSRect) {
        bgColor.setFill()
        bounds.fill()
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

        lm.enumerateTextLayoutFragments(from: startLocation, options: [.ensuresLayout]) { frag in
            let frame = frag.layoutFragmentFrame
            let yInTextView = frame.minY + origin.y
            if yInTextView > visible.maxY { return false }
            if yInTextView + frame.height < visible.minY { return true }
            let offset = cs.offset(from: cs.documentRange.location, to: frag.rangeInElement.location)
            let line = index.lineNumber(forUTF16Offset: offset)
            let firstLineHeight = frag.textLineFragments.first?.typographicBounds.height ?? frame.height
            let y = yInTextView - visible.minY
            if line == caretLine, tv.selectedRange().length == 0 {
                // 편집기의 현재 줄 강조가 거터까지 이어지도록 같은 색으로 행을 칠한다
                self.lineHighlightColor.setFill()
                NSRect(x: 0, y: y, width: self.bounds.width - 1, height: frame.height).fill()
            }
            let label = String(line) as NSString
            let size = label.size(withAttributes: attrs)
            let x = self.thickness - size.width - 10
            label.draw(at: NSPoint(x: x, y: y + (firstLineHeight - size.height) / 2), withAttributes: line == caretLine ? curAttrs : attrs)
            return true
        }
    }
}

/// [거터 | 스크롤뷰] 를 가로로 배치하는 컨테이너.
final class EditorContainerView: NSView {
    let gutter: GutterView
    let scrollView: NSScrollView

    init(gutter: GutterView, scrollView: NSScrollView) {
        self.gutter = gutter
        self.scrollView = scrollView
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(scrollView)
        addSubview(gutter)
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
    }
}
