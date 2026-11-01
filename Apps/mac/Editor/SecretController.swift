import AppKit
import Combine
import HyperCore

// 비밀 블록 마스킹 (secrets). 텍스트 뷰 하나에 SecretController 하나 — 분할 편집기는 편집기마다 따로 만든다 (FoldController 와 같다).
//
// 설계
// - 비밀 줄은 ```secret 펜스 안쪽 줄 (`SecretScanner`, HyperCore). 실제 텍스트는 저장소에 그대로 있다 — 검색·저장·undo 는 평소대로.
// - 가림은 접기와 같은 메커니즘: FoldController 의 NSTextLayoutManagerDelegate 가 "숨길까" 다음에 이 컨트롤러에 "가릴까" 를 묻고,
//   가릴 문단에는 `MaskedLayoutFragment`(높이는 정상, 글리프 대신 둥근 가림막 + ••••••••) 를 돌려준다.
// - 범위는 문서 오프셋(UTF-16)으로 두고 편집마다 옮긴다 (FoldController.onEdit — shouldChangeText 직전 좌표, undo/redo 는 사후 통지).
//   블록 집합 자체는 줄 인덱스 발행(입력 멈춤 250 ms 뒤)마다 백그라운드로 다시 스캔하고, 파일을 열 때는 첫 그리기 전에 동기로 스캔한다 (평문 노출 없이).
// - 드러내기: 캐럿이 비밀 줄 안이면 그 블록 전체를 드러낸다 (편집 가능), 나가면 다시 가린다. ⌥⌘S(SecretsStore.revealedAll)는 전부 드러낸다.
// - 복사·잘라내기 범위가 비밀 줄과 겹치면 SecretsStore 가 클립보드 소거를 예약한다.

/// 가림 구간 하나: 비밀 내용 줄들 [start, end). 닫히지 않은 블록은 end == 문서 길이이고 끝 오프셋도 안으로 본다
struct SecretSpan: Hashable {
    var start: Int
    var end: Int
    var closed: Bool
}

/// 가림막 그리기 색·글꼴 (테마 적용 때 갱신, 프래그먼트가 그릴 때 읽는다)
final class MaskStyle {
    var fill = NSColor.secondaryLabelColor.withAlphaComponent(0.25)
    var text = NSColor.secondaryLabelColor
    var font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
    let label = SecretScanner.defaultMask
}

@MainActor
final class SecretController {
    weak var textView: HyperTextView?
    weak var fold: FoldController?
    let store: SecretsStore
    var log: ((String) -> Void)?

    private(set) var spans: [SecretSpan] = []      // start 오름차순
    /// 캐럿이 든 블록 (spans 의 인덱스) — 편집으로 옮겨도 같은 블록을 가리키도록 인덱스로 둔다
    private var revealedIndex: Int?
    private weak var document: MemoDocument?
    private var cancellables = Set<AnyCancellable>()
    private var storeCancellables = Set<AnyCancellable>()
    private var scanTask: Task<Void, Never>?
    private var editGeneration = 0
    let style = MaskStyle()

    init(textView: HyperTextView, fold: FoldController, store: SecretsStore, log: ((String) -> Void)? = nil) {
        self.textView = textView
        self.fold = fold
        self.store = store
        self.log = log
        guard FoldController.isEnabled else { return }   // --no-fold 는 레이아웃 delegate 를 두지 않는다 → 가림도 없다
        fold.hasMasks = { [weak self] in self?.hasMasks ?? false }
        fold.maskedFragment = { [weak self] off, element, range in self?.fragment(paragraphStart: off, element: element, range: range) }
        fold.onEdit = { [weak self] edits, applied in self?.textWillChange(edits, alreadyApplied: applied) }
        textView.hasMasks = { [weak self] in self?.hasMasks ?? false }
        textView.isOffsetMasked = { [weak self] off in self?.isMasked(paragraphStart: off) ?? false }
        textView.secretHitTest = { [weak self] ranges in self?.copyHitsSecret(ranges) ?? false }
        textView.onDidCopySecret = { [weak self] in
            guard let self, self.store.maskEnabled else { return }
            // 클립보드 관리자(Paste·Maccy 등)가 기록하지 않도록 표식 — nspasteboard.org 관례
            NSPasteboard.general.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
            self.store.scheduleClipboardClear()
        }
        // @Published 는 willSet 에 발행 — 값이 바뀐 뒤(다음 턴)에 프래그먼트를 다시 만든다
        store.$revealedAll.dropFirst().removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.invalidateAllSpans() } }
            .store(in: &storeCancellables)
        store.$maskEnabled.dropFirst().removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.maskEnabledChanged() } }
            .store(in: &storeCancellables)
    }

    /// 문서 연결 (파일 전환·다시 읽기·줄 인덱스 갱신 구독). 이미 올라온 내용은 지금 동기로 스캔한다 — 첫 그리기 전에 가려지도록
    func bind(document doc: MemoDocument) {
        cancellables.removeAll()
        document = doc
        guard FoldController.isEnabled else { return }
        scanNow(synchronous: true)
        doc.$lineIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.scanNow(synchronous: false) }
            .store(in: &cancellables)
        // 내용 교체(파일 전환·디스크에서 다시 읽기)는 replaceAll 이 저장소를 바꾼 직후 reloadGeneration 을 발행한다 — 그 자리에서 동기 스캔 (그리기 전)
        doc.$reloadGeneration.dropFirst()
            .sink { [weak self] _ in self?.scanNow(synchronous: true) }
            .store(in: &cancellables)
    }

    /// 편집기가 닫힐 때(분할 해제): 구독과 진행 중인 스캔을 끊는다
    func unbind() {
        cancellables.removeAll()
        scanTask?.cancel(); scanTask = nil
    }

    func apply(theme: Theme) {
        style.fill = theme.foregroundDim.nsColor.withAlphaComponent(0.25)
        style.text = theme.foregroundMuted.nsColor
        let base = (textView?.typingAttributes[.font] as? NSFont) ?? textView?.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        style.font = NSFont.monospacedSystemFont(ofSize: max(9, base.pointSize - 1), weight: .medium)
        invalidateAllSpans()
    }

    // MARK: 질의

    var hasMasks: Bool { !spans.isEmpty }
    var blockCount: Int { spans.count }

    /// 문단 시작 오프셋이 지금 가려져 있는가 (설정 켜짐 · 전부 드러내기 아님 · 캐럿이 든 블록 아님)
    func isMasked(paragraphStart offset: Int) -> Bool {
        guard store.maskEnabled, !store.revealedAll, let i = spanIndex(containing: offset) else { return false }
        return i != revealedIndex
    }

    /// 오프셋을 품은 구간의 인덱스 (이분 탐색)
    private func spanIndex(containing offset: Int) -> Int? {
        guard !spans.isEmpty else { return nil }
        var lo = 0, hi = spans.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if spans[mid].start > offset { hi = mid - 1 } else { lo = mid + 1 }
        }
        let i = hi   // start <= offset 인 마지막 구간
        guard i >= 0 else { return nil }
        let s = spans[i]
        if offset < s.end { return i }
        if offset == s.end, !s.closed, s.end == (textView?.textStorage?.length ?? -1) { return i }   // 문서 끝까지 닿는 블록의 끝 캐럿
        return nil
    }

    private func fragment(paragraphStart offset: Int, element: NSTextElement, range: NSTextRange?) -> NSTextLayoutFragment? {
        guard isMasked(paragraphStart: offset) else { return nil }
        return MaskedLayoutFragment(textElement: element, range: range, style: style)
    }

    // MARK: 캐럿 드러내기 / 복사

    /// 선택이 바뀔 때 (Coordinator 가 부른다): 캐럿이 든 블록을 드러내고, 떠난 블록을 다시 가린다
    func selectionDidChange() {
        guard !spans.isEmpty, let tv = textView else { return }
        let caret = tv.selectedRange().location
        let now = spanIndex(containing: caret)
        guard now != revealedIndex else { return }
        let before = revealedIndex
        revealedIndex = now
        guard store.maskEnabled, !store.revealedAll else { return }
        if let b = before, b < spans.count { invalidate(spans[b]) }
        if let n = now { invalidate(spans[n]) }
    }

    /// 복사·잘라내기 **전** 판정: 복사 범위가 비밀 줄과 겹치는가. 길이 0 범위는 아무것도 복사하지 않으므로 겹침으로 보지 않는다
    /// (캐럿만 블록 안에 둔 ⌘C 를 겹침으로 보면 다른 앱이 넣어 둔 클립보드를 지우게 된다 — QA)
    private func copyHitsSecret(_ ranges: [NSRange]) -> Bool {
        guard store.maskEnabled, !spans.isEmpty else { return false }
        return ranges.contains { r in
            r.length > 0 && spans.contains { s in s.end > s.start && r.location < s.end && NSMaxRange(r) > s.start }
        }
    }

    // MARK: 편집 추적 (편집 전 좌표 — FoldController.onEdit)

    private func textWillChange(_ edits: [(NSRange, String)], alreadyApplied: Bool) {
        editGeneration &+= 1
        // 붙여넣기·undo 로 펜스가 통째로 들어오면 디바운스(250 ms) 스캔을 기다리지 않고 다음 턴에 동기 스캔 — 새 블록이 평문으로 보이는 시간을 없앤다.
        // 검사는 UTF-8 바이트로 (String.contains 는 자소 단위라 2.7 MB 교체에서 수백 ms — 셀프테스트 실측), 10자 미만 교체(타이핑)는 건너뛴다
        if store.maskEnabled, edits.contains(where: { $0.1.utf8.count >= 10 && Self.mentionsSecretFence($0.1) }) {
            DispatchQueue.main.async { [weak self] in self?.scanNow(synchronous: true) }
        }
        guard !spans.isEmpty else { return }
        let before = spans
        for (r, s) in edits.sorted(by: { $0.0.location > $1.0.location }) where r.location != NSNotFound {
            shift(edit: r, replacementLength: (s as NSString).length)
        }
        guard alreadyApplied, spans != before else { return }
        // 사후 통지(undo/redo): TextKit 이 편집된 문단을 옛 오프셋으로 이미 배치했을 수 있다 → 바뀐 구간을 다시 만든다 (저장소 편집 처리 중이라 다음 턴에)
        let changed = Set(before.filter { !spans.contains($0) } + spans.filter { !before.contains($0) })
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for s in changed { self.invalidate(s) }
            self.fold?.updateLayoutDelegate()
        }
    }

    /// "secret"(대소문자 무시 — 스캐너와 같은 규칙) 과 펜스 기호가 모두 들어 있는가 — UTF-8 바이트 검색
    private static func mentionsSecretFence(_ s: String) -> Bool {
        var s = s
        return s.withUTF8 { buf -> Bool in
            func has(_ needle: StaticString) -> Bool {
                needle.withUTF8Buffer { n -> Bool in
                    guard buf.count >= n.count, let base = buf.baseAddress, let nb = n.baseAddress else { return false }
                    return memmem(base, buf.count, nb, n.count) != nil
                }
            }
            guard has("```") || has("~~~") else { return false }
            let word: [UInt8] = Array("secret".utf8)
            guard buf.count >= word.count else { return false }
            for i in 0...(buf.count - word.count) {
                var j = 0
                while j < word.count, (buf[i + j] | 0x20) == word[j] { j += 1 }   // ASCII 소문자화 (| 0x20)
                if j == word.count { return true }
            }
            return false
        }
    }

    /// 구간 이동 규칙 (편집 범위 [a, b), 길이 변화 delta)
    /// 1. b < start (여는 펜스 줄 안 포함) → 구간 전체 이동   2. a ≥ end (닫는 펜스부터) → 그대로 (닫히지 않은 블록의 끝 입력은 내용)
    /// 3. 내용 안 → end 만 이동 (새로 쓴 줄도 비밀)   4. 경계를 걸침 → 안전한 쪽으로: 펜스가 훼손되면 그 자리부터 가리고, 다음 스캔이 바로잡는다
    private func shift(edit r: NSRange, replacementLength: Int) {
        let a = r.location, b = NSMaxRange(r)
        let delta = replacementLength - r.length
        var kept: [SecretSpan] = []
        kept.reserveCapacity(spans.count)
        var newRevealed: Int?
        for (i, var s) in spans.enumerated() {
            if b < s.start {
                s.start += delta; s.end += delta
            } else if a >= s.end, !(a == s.end && !s.closed) {
                // 뒤쪽 편집 — 그대로
            } else if a >= s.start, b <= s.end {
                s.end += delta
            } else {
                if a < s.start { s.start = a }
                s.end = b >= s.end ? max(s.start, a + replacementLength) : max(s.start, s.end + delta)
            }
            if s.end < s.start || s.start < 0 { continue }
            if revealedIndex == i { newRevealed = kept.count }
            kept.append(s)
        }
        spans = kept
        revealedIndex = newRevealed
    }

    // MARK: 스캔

    /// 설정 켜고 끔: 켜면 바로 스캔, 끄면 전부 걷어낸다
    private func maskEnabledChanged() {
        if store.maskEnabled { scanNow(synchronous: true) } else { apply(spans: []) }
    }

    private func scanNow(synchronous: Bool) {
        guard FoldController.isEnabled, let doc = document else { return }
        scanTask?.cancel()
        guard store.maskEnabled else { apply(spans: []); return }
        let text = doc.textStorage.string
        if synchronous {
            let found = Perf.measure("secrets.scan.sync", threshold: 2) { SecretScanner.blocks(in: text) }
            apply(spans: Self.spans(from: found, length: (text as NSString).length))
            return
        }
        let gen = editGeneration
        scanTask = Task { [weak self] in
            let found = await Task.detached(priority: .utility) { () -> [SecretBlock] in
                Perf.measure("secrets.scan", threshold: 0) { SecretScanner.blocks(in: text) }
            }.value
            guard let self, !Task.isCancelled else { return }
            guard gen == self.editGeneration else { return }   // 스캔 중 편집 — 그 편집이 줄 인덱스를 다시 발행해 새 스캔이 돈다
            self.apply(spans: Self.spans(from: found, length: (text as NSString).length))
        }
    }

    private static func spans(from blocks: [SecretBlock], length: Int) -> [SecretSpan] {
        blocks.map { SecretSpan(start: $0.contentRange.location, end: NSMaxRange($0.contentRange), closed: $0.isClosed) }
    }

    /// 새 구간 적용: 바뀐 구간의 문단만 다시 만든다. 캐럿이 든 블록은 캐럿 위치로 다시 정한다
    private func apply(spans new: [SecretSpan]) {
        if store.blockCount != new.count { store.blockCount = new.count }
        let old = spans
        let oldRevealed = revealedIndex.flatMap { $0 < old.count ? old[$0] : nil }
        spans = new
        let caret = textView?.selectedRange().location ?? -1
        revealedIndex = caret >= 0 ? spanIndex(containing: caret) : nil
        let newRevealed = revealedIndex.map { new[$0] }
        guard old != new || oldRevealed != newRevealed else { return }
        fold?.updateLayoutDelegate()
        var dirty: [SecretSpan] = old.filter { !new.contains($0) } + new.filter { !old.contains($0) }
        if oldRevealed != newRevealed { if let o = oldRevealed { dirty.append(o) }; if let n = newRevealed { dirty.append(n) } }
        for s in dirty { invalidate(s) }
        if Perf.enabled { Perf.log("secrets.apply blocks=\(new.count) revealed=\(String(describing: revealedIndex))") }
    }

    private func invalidateAllSpans() {
        for s in spans { invalidate(s) }
        textView?.needsDisplay = true
    }

    /// 구간의 문단 프래그먼트를 다시 만들게 한다 (FoldController.invalidateLayout — 속성 편집 통지)
    private func invalidate(_ s: SecretSpan) {
        guard s.end > s.start else { return }
        fold?.invalidateLayout(from: s.start, to: s.end)
    }
}

// MARK: - TextKit 2

/// 가려진 문단: 높이는 정상, 글리프 대신 줄 폭만큼의 둥근 가림막과 •••••••• 를 그린다. 자동 줄바꿈으로 여러 줄이면 줄마다 가림막, 표식은 첫 줄에만
final class MaskedLayoutFragment: NSTextLayoutFragment {
    let style: MaskStyle

    init(textElement: NSTextElement, range: NSTextRange?, style: MaskStyle) {
        self.style = style
        super.init(textElement: textElement, range: range)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var labelAttributes: [NSAttributedString.Key: Any] { [.font: style.font, .foregroundColor: style.text] }
    private var minWidth: CGFloat { (style.label as NSString).size(withAttributes: labelAttributes).width + 16 }

    override var renderingSurfaceBounds: CGRect {
        // 빈 줄의 가림막은 글자 폭보다 넓다 — 그리는 영역을 넓혀 잘리지 않게
        super.renderingSurfaceBounds.union(CGRect(x: 0, y: 0, width: minWidth + 8, height: layoutFragmentFrame.height))
    }

    override func draw(at point: CGPoint, in context: CGContext) {
        let lines = textLineFragments
        guard !lines.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let attrs = labelAttributes
        let label = style.label as NSString
        let labelSize = label.size(withAttributes: attrs)
        let maxWidth = max(minWidth, layoutFragmentFrame.width)
        for (i, line) in lines.enumerated() {
            let tb = line.typographicBounds
            let width = min(max(tb.width, minWidth), maxWidth - tb.minX)
            let rect = CGRect(x: point.x + tb.minX, y: point.y + tb.minY + 1, width: width, height: max(2, tb.height - 2))
            let path = NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4)
            style.fill.setFill()
            path.fill()
            if i == 0 {
                label.draw(at: NSPoint(x: rect.minX + 8, y: rect.midY - labelSize.height / 2), withAttributes: attrs)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}
