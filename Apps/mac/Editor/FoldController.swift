import AppKit
import Combine
import HyperCore

// 접기(fold). 텍스트 뷰 하나에 FoldController 하나 — 분할 편집기는 편집기마다 따로 만든다.
//
// 설계
// - 접힘 상태는 줄 번호가 아니라 문서 오프셋(UTF-16)으로 둔다: `hiddenStart`(첫 숨은 문단의 시작) ~ `hiddenEnd`(마지막 숨은 문단의 끝 = 다음 보이는 문단의 시작).
//   머리 줄은 `hiddenStart` 바로 앞 문단이다. 줄 인덱스는 편집 뒤 250 ms 동안 낡아 있는데, TextKit 2 는 편집 직후에 문단을 다시 배치하며
//   delegate 에 "이 문단을 숨길까" 를 묻는다 — 오프셋은 `HyperTextView.onTextWillChange`(모든 편집, 저장소 변경 직전)에서 즉시 옮기므로 그 틈이 없다.
// - 접기 후보(영역)는 `FoldScanner` 가 백그라운드에서 문서 스냅샷으로 계산한다 (`document.$lineIndex` 발행 = 입력 멈춤 250 ms 뒤). 키 입력마다 하는 일은 후보·접힘 오프셋 이동뿐.
// - 숨김은 `NSTextLayoutManagerDelegate.textLayoutManager(_:textLayoutFragmentFor:in:)` 가 숨은 문단에 높이 0 프래그먼트(`FoldedLayoutFragment`)를 돌려주는 것으로 구현한다.
//   접힘이 바뀌면 그 범위에 `edited(.editedAttributes)` 를 알려 프래그먼트를 다시 만들게 한다 (EditorView.invalidateHighlight 와 같은 경로 — invalidateLayout 은 기존 프래그먼트를 재사용한다).
// - 캐럿이 숨은 줄로 들어가면(검색·줄 이동·북마크·undo) 자동으로 펼친다. ↑/↓ 는 HyperTextView 가 접힌 구간을 건너뛴다.

/// 접힌 영역 하나 (문서 오프셋)
struct FoldSpan: Equatable {
    var hiddenStart: Int
    var hiddenEnd: Int
    var lines: Int          // 숨은 줄 수
}

/// 접기 후보 영역 (스캔 결과, 문서 오프셋)
struct FoldCandidate: Equatable {
    var headerStart: Int
    var hiddenStart: Int
    var hiddenEnd: Int
    var lines: Int
}

/// 머리 줄 뒤에 그리는 `⋯ N lines` 표식
struct FoldPill {
    let headerEnd: Int      // 머리 줄 텍스트 끝 오프셋 (개행 위치)
    let hiddenStart: Int    // 접힘 식별자
    let lines: Int
}

@MainActor
final class FoldController {
    /// 비상 스위치: `--no-fold` 로 실행하면 delegate 를 설치하지 않는다 (접기 명령은 아무 일도 하지 않음)
    static let isEnabled = !CommandLine.arguments.contains("--no-fold")

    weak var textView: HyperTextView?
    weak var gutter: GutterView?
    var log: ((String) -> Void)?
    /// 접힘 집합이 바뀜 (스크롤 마커 등이 다시 그린다)
    var onChange: (() -> Void)?

    // secrets: 비밀 블록 마스킹이 같은 NSTextLayoutManagerDelegate 를 쓴다 (레이아웃 매니저의 delegate 는 하나) — SecretController 가 설치하는 훅.
    // 숨은 문단(접힘)이 우선이고, 그 다음에 "이 문단을 가릴까" 를 묻는다. 접힘이 없어도 가릴 줄이 있으면 delegate 를 유지한다 (updateLayoutDelegate).
    /// 가릴 줄이 하나라도 있는가
    var hasMasks: (() -> Bool)?
    /// 문단 시작 오프셋이 가릴 줄이면 그 문단의 프래그먼트(MaskedLayoutFragment)를, 아니면 nil
    var maskedFragment: ((_ paragraphStart: Int, _ element: NSTextElement, _ range: NSTextRange?) -> NSTextLayoutFragment?)?
    /// 편집 통지 전달 (편집 전 좌표, textWillChange 와 같은 인자) — 비밀 범위 오프셋 추적용
    var onEdit: ((_ edits: [(NSRange, String)], _ alreadyApplied: Bool) -> Void)?

    private(set) var folds: [FoldSpan] = []              // hiddenStart 오름차순
    private(set) var candidates: [FoldCandidate] = []    // headerStart 오름차순
    private var merged: [NSRange] = []                   // folds 의 숨김 구간 합집합 (정렬, 겹침 없음)
    private weak var document: MemoDocument?
    private var cancellables = Set<AnyCancellable>()
    private var scanTask: Task<Void, Never>?
    private var editGeneration = 0
    private let layoutDelegate = FoldLayoutDelegate()

    init(textView: HyperTextView, gutter: GutterView?, log: ((String) -> Void)? = nil) {
        self.textView = textView
        self.gutter = gutter
        self.log = log
        guard Self.isEnabled else { return }
        layoutDelegate.controller = self
        // 레이아웃 delegate 는 접힘이 하나라도 있을 때만 설치한다 (rebuildMerged) — delegate 가 있으면 TextKit 이 키 입력마다 프래그먼트를 만드는 경로가
        // 느려진다 (실측 약 1 ms/키). 접힘이 생기거나 사라질 때는 어차피 그 범위의 프래그먼트를 다시 만든다.
        textView.onTextWillChange = { [weak self] edits, applied in self?.textWillChange(edits, alreadyApplied: applied) }
        textView.hasFolds = { [weak self] in self?.hasFolds ?? false }
        textView.isOffsetHidden = { [weak self] o in self?.isOffsetHidden(o) ?? false }
        textView.foldedSpan = { [weak self] o in self?.hiddenSpan(containing: o) }
        textView.foldPills = { [weak self] r in self?.pills(in: r) ?? [] }
        textView.onFoldPillClick = { [weak self] hs in self?.unfold(hiddenStart: hs, reason: nil) }
        gutter?.foldMarker = { [weak self] s, e in
            guard let self, !self.folds.isEmpty || !self.candidates.isEmpty else { return nil }
            return self.marker(paragraphStart: s, paragraphEnd: e())
        }
        gutter?.onFoldMarkerClick = { [weak self] s, e in self?.toggle(paragraphStart: s, paragraphEnd: e) }
    }

    /// 문서 연결 (파일 전환·다시 읽기·줄 인덱스 갱신을 구독). 같은 Coordinator 가 문서를 갈아끼우면 다시 부른다
    /// 편집기가 닫힐 때(분할 해제): 구독과 진행 중인 스캔을 끊는다 — 보관만 되는 코디네이터가 편집마다 재스캔하지 않도록
    func unbind() {
        cancellables.removeAll()
        scanTask?.cancel(); scanTask = nil
    }

    func bind(document doc: MemoDocument) {
        cancellables.removeAll()
        document = doc
        reset()
        guard Self.isEnabled else { return }
        doc.$lineIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rescan() }
            .store(in: &cancellables)
        // @Published 는 willSet 에 발행 — 내용 교체 전에 접힘을 비운다 (새 파일의 영역은 lineIndex 발행으로 다시 계산)
        doc.$url.removeDuplicates().dropFirst()
            .sink { [weak self] _ in self?.reset() }
            .store(in: &cancellables)
        doc.$reloadGeneration.dropFirst()
            .sink { [weak self] _ in self?.reset() }
            .store(in: &cancellables)
    }

    func apply(theme: Theme) {
        textView?.foldPillTextColor = theme.foregroundDim.nsColor
        textView?.foldPillFillColor = theme.backgroundElevated.nsColor
        textView?.needsDisplay = true
    }

    /// 접힘·후보 전부 비움 (파일 전환, 디스크에서 다시 읽기)
    func reset() {
        scanTask?.cancel()
        candidates = []
        guard !folds.isEmpty else { gutter?.needsDisplay = true; return }
        folds = []
        rebuildMerged()
        invalidateLayout(from: 0, to: Int.max)
        onChange?()
    }

    // MARK: 질의

    var hasFolds: Bool { !folds.isEmpty }
    var foldCount: Int { folds.count }
    var regionCount: Int { candidates.count }

    /// 문서 오프셋이 숨은 문단 안인가 (문단 시작 오프셋으로 묻는 것이 정확하다)
    func isOffsetHidden(_ offset: Int) -> Bool { hiddenSpan(containing: offset) != nil }

    /// 오프셋을 포함하는 (겹침을 합친) 숨김 구간 [hiddenStart, hiddenEnd). 문서 끝까지 닿는 구간은 끝 오프셋(= 문서 길이)도 숨은 것으로 본다 —
    /// 마지막 숨은 줄 끝에 캐럿이 보이지 않게 남지 않도록
    func hiddenSpan(containing offset: Int) -> NSRange? {
        var lo = 0, hi = merged.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let r = merged[mid]
            if offset < r.location { hi = mid - 1 }
            else if offset >= NSMaxRange(r) { lo = mid + 1 }
            else { return r }
        }
        if let last = merged.last, offset == NSMaxRange(last), offset == (textView?.textStorage?.length ?? -1) { return last }
        return nil
    }

    /// 1-based 줄이 숨겨져 있는가 (셀프테스트·마커용 — 문서 줄 인덱스 기준)
    func isLineHidden(_ line: Int) -> Bool {
        guard let idx = document?.lineIndex, line >= 1, line <= idx.lineCount else { return false }
        return isOffsetHidden(idx.lineStarts[line - 1])
    }

    /// 접힌 머리 줄 번호들 (1-based, 문서 줄 인덱스 기준)
    var foldedHeaderLines: [Int] {
        guard let idx = document?.lineIndex else { return [] }
        return folds.map { idx.lineNumber(forUTF16Offset: max(0, $0.hiddenStart - 1)) }
    }

    /// 보이는 범위 안의 접힌 머리 줄 표식 (머리 줄 자체가 바깥 접힘에 숨겨진 안쪽 접힘은 제외)
    func pills(in visible: NSRange) -> [FoldPill] {
        guard !folds.isEmpty else { return [] }
        var out: [FoldPill] = []
        // hiddenStart 오름차순이므로 보이는 범위의 시작은 이분 탐색으로 건너뛴다 (모두 접힌 큰 문서에서 수천 개를 훑지 않도록)
        var lo = 0, hi = folds.count
        while lo < hi { let mid = (lo + hi) / 2; if folds[mid].hiddenStart - 1 < visible.location { lo = mid + 1 } else { hi = mid } }
        for f in folds[lo...] {
            let headerEnd = f.hiddenStart - 1
            if headerEnd > NSMaxRange(visible) { break }
            if isOffsetHidden(headerEnd) { continue }
            out.append(FoldPill(headerEnd: headerEnd, hiddenStart: f.hiddenStart, lines: f.lines))
        }
        return out
    }

    /// 거터 화살표: 문단(개행 포함) 범위로 묻는다
    func marker(paragraphStart: Int, paragraphEnd: Int) -> GutterView.FoldMarker? {
        if foldIndex(hiddenStart: paragraphEnd) != nil { return .folded }
        if candidateIndex(headerStart: paragraphStart) != nil { return .foldable }
        return nil
    }

    // MARK: 명령

    func handle(_ cmd: EditorCommand) {
        guard Self.isEnabled, let tv = textView else { return }
        let caret = tv.selectedRange().location
        if Perf.enabled { Perf.log("fold.command \(cmd) caret=\(caret) folds=\(folds.count) candidates=\(candidates.count)") }
        switch cmd {
        case .fold:
            // 캐럿 줄을 머리로 하거나 캐럿을 품은 가장 안쪽의 아직 안 접힌 영역
            let enclosing = candidates.filter { contains($0, caret) }
            guard let c = enclosing.reversed().first(where: { foldIndex(hiddenStart: $0.hiddenStart) == nil }) else {
                log?(String(localized: "Nothing to fold here")); return
            }
            fold(c)
        case .unfold:
            // 캐럿이 머리 줄에 있는 접힘 (숨은 줄에 캐럿이 있을 수는 없다 — 들어가는 순간 펼쳐진다)
            let ns = tv.string as NSString
            let para = ns.paragraphRange(for: NSRange(location: min(caret, ns.length), length: 0))
            if let i = foldIndex(hiddenStart: NSMaxRange(para)) {
                unfold(at: i, reason: nil)
            } else if let span = hiddenSpan(containing: caret) {
                unfoldAll(containing: span.location, reason: nil)
            } else {
                log?(String(localized: "Nothing to unfold here"))
            }
        case .foldAll:
            let before = folds.count
            folds = candidates.map { FoldSpan(hiddenStart: $0.hiddenStart, hiddenEnd: $0.hiddenEnd, lines: $0.lines) }
            folds.sort { $0.hiddenStart < $1.hiddenStart }
            rebuildMerged()
            invalidateLayout(from: 0, to: Int.max)
            moveCaretOutOfFolds()
            log?(String(localized: "Folded \(folds.count - before) regions"))
            changed()
        case .unfoldAll:
            let n = folds.count
            folds = []
            rebuildMerged()
            invalidateLayout(from: 0, to: Int.max)
            log?(String(localized: "Unfolded \(n) regions"))
            changed()
        case .toggleFold(let line):
            guard let idx = document?.lineIndex, line >= 1, line <= idx.lineCount else { return }
            let start = idx.lineStarts[line - 1]
            let end = line < idx.lineCount ? idx.lineStarts[line] : idx.utf16Count
            toggle(paragraphStart: start, paragraphEnd: end)
        default:
            break
        }
    }

    /// 거터 화살표·`toggleFold(line:)`: 접혀 있으면 펼치고, 후보면 접는다
    func toggle(paragraphStart: Int, paragraphEnd: Int) {
        guard !isOffsetHidden(paragraphStart) else { return }
        if let i = foldIndex(hiddenStart: paragraphEnd) { unfold(at: i, reason: nil); return }
        if let i = candidateIndex(headerStart: paragraphStart) { fold(candidates[i]) }
    }

    /// 선택이 바뀔 때 (Coordinator 가 부른다): 캐럿이 숨은 줄로 들어갔으면 그 접힘을 펼친다. 드래그 선택(길이 > 0)은 숨은 텍스트를 포함한 채 둔다
    func selectionDidChange() {
        guard !folds.isEmpty, let tv = textView else { return }
        let sel = tv.selectedRange()
        guard sel.length == 0, isOffsetHidden(sel.location) else { return }
        unfoldAll(containing: sel.location, reason: String(localized: "caret"))
    }

    /// 점프(검색 매치·줄 이동·북마크·문서 끝)로 선택이 놓이기 전에 그 자리를 숨기는 접힘을 펼친다 — 길이 있는 선택(검색 매치)은 selectionDidChange 가 건드리지 않는다
    func reveal(range r: NSRange) {
        guard !folds.isEmpty else { return }
        for o in Set([r.location, max(r.location, NSMaxRange(r) - 1)]) where isOffsetHidden(o) {
            unfoldAll(containing: o, reason: String(localized: "caret"))
        }
    }

    // MARK: 접기 / 펼치기

    private func fold(_ c: FoldCandidate) {
        guard foldIndex(hiddenStart: c.hiddenStart) == nil, c.hiddenEnd > c.hiddenStart else { return }
        if Perf.enabled { Perf.log("fold.fold \(c.headerStart)/\(c.hiddenStart)..<\(c.hiddenEnd) caret=\(textView?.selectedRange().location ?? -1)") }
        folds.append(FoldSpan(hiddenStart: c.hiddenStart, hiddenEnd: c.hiddenEnd, lines: c.lines))
        folds.sort { $0.hiddenStart < $1.hiddenStart }
        rebuildMerged()
        invalidateLayout(from: c.headerStart, to: c.hiddenEnd)
        moveCaretOutOfFolds()
        if let idx = document?.lineIndex {
            let h = idx.lineNumber(forUTF16Offset: c.headerStart)
            log?(String(localized: "Folded lines \(h)–\(h + c.lines)"))
        }
        changed()
    }

    private func unfold(hiddenStart: Int, reason: String?) {
        guard let i = foldIndex(hiddenStart: hiddenStart) else { return }
        unfold(at: i, reason: reason)
    }

    private func unfold(at i: Int, reason: String?) {
        let f = folds.remove(at: i)
        if Perf.enabled { Perf.log("fold.unfold \(f.hiddenStart)..<\(f.hiddenEnd) reason=\(reason ?? "command") caret=\(textView?.selectedRange().location ?? -1)") }
        rebuildMerged()
        invalidateLayout(from: max(0, f.hiddenStart - 1), to: f.hiddenEnd)
        if let idx = document?.lineIndex {
            let h = idx.lineNumber(forUTF16Offset: max(0, f.hiddenStart - 1))
            log?(String(localized: "Unfolded lines \(h)–\(h + f.lines)") + (reason.map { " · \($0)" } ?? ""))
        }
        changed()
    }

    /// 오프셋을 숨기고 있는 접힘을 전부 펼친다 (바깥 → 안쪽). 문서 끝까지 닿는 접힘은 끝 오프셋(= 문서 길이)도 숨긴 것으로 본다 — hiddenSpan 과 같은 규칙
    /// (⌘↓·문서 끝 이동으로 캐럿이 거기 놓이면 펼쳐져야 보인다)
    private func unfoldAll(containing offset: Int, reason: String?) {
        let length = textView?.textStorage?.length ?? -1
        var i = 0
        while i < folds.count {
            let f = folds[i]
            if f.hiddenStart <= offset && (offset < f.hiddenEnd || (offset == f.hiddenEnd && offset == length)) { unfold(at: i, reason: reason) } else { i += 1 }
        }
    }

    /// 접은 뒤 캐럿이 숨겨졌으면 가장 바깥 머리 줄 끝으로 옮긴다 (Xcode 와 같음)
    private func moveCaretOutOfFolds() {
        guard let tv = textView, tv.selectedRange().length == 0, let span = hiddenSpan(containing: tv.selectedRange().location) else { return }
        let target = max(0, span.location - 1)
        tv.setSelectedRange(NSRange(location: target, length: 0))
        tv.scrollRangeToVisible(NSRange(location: target, length: 0))
    }

    private func changed() {
        gutter?.needsDisplay = true
        textView?.needsDisplay = true
        onChange?()
    }

    // MARK: 편집 추적 (편집 전 좌표. 보통 저장소 변경 직전, undo/redo 는 변경 직후 사후 통지)

    private func textWillChange(_ edits: [(NSRange, String)], alreadyApplied: Bool) {
        editGeneration &+= 1
        onEdit?(edits, alreadyApplied)   // secrets: 비밀 범위도 같은 통지로 옮긴다
        guard !folds.isEmpty || !candidates.isEmpty else { return }
        let before = folds
        var dropped: [FoldSpan] = []
        for (r, s) in edits.sorted(by: { $0.0.location > $1.0.location }) {
            guard r.location != NSNotFound else { continue }
            let delta = (s as NSString).length - r.length
            shiftFolds(edit: r, delta: delta, dropped: &dropped)
            shiftCandidates(edit: r, replacement: s, delta: delta)
        }
        if Perf.enabled, alreadyApplied || folds != before {
            Perf.log("fold.edit applied=\(alreadyApplied) edits=\(edits.map { "\($0.0)→\(($0.1 as NSString).length)" }) folds \(before.map { "\($0.hiddenStart)..<\($0.hiddenEnd)" }) → \(folds.map { "\($0.hiddenStart)..<\($0.hiddenEnd)" }) candidates=\(candidates.count)")
        }
        guard folds != before else { return }
        rebuildMerged()
        // 펼쳐진(dropped) 접힘의 문단은 다시 만들어야 보인다. 사후 통지(undo/redo)면 TextKit 이 편집된 문단을 옛 오프셋으로 이미 배치했을 수 있으므로
        // 옮겨진 접힘 범위도 함께 다시 만든다. 지금은 저장소 편집 처리 중이라 프래그먼트 재생성은 이 턴이 끝난 뒤로 미룬다.
        var lo = Int.max, hi = 0
        for f in dropped { lo = min(lo, f.hiddenStart); hi = max(hi, f.hiddenEnd) }
        if alreadyApplied { for f in before + folds { lo = min(lo, f.hiddenStart); hi = max(hi, f.hiddenEnd) } }
        guard hi > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.invalidateLayout(from: max(0, lo - 1), to: hi)
            self?.changed()
        }
    }

    /// 접힘 이동 규칙 (편집 범위 R, 길이 변화 delta)
    /// 1. R 이 머리 줄의 개행(hiddenStart-1)을 지우면 → 머리와 첫 숨은 줄이 합쳐지므로 펼친다 (머리 줄 삭제 포함)
    /// 2. R 이 그 앞에서 끝나면 → 구간 전체를 delta 만큼 옮긴다 (머리 줄 안의 입력 포함 — 접힘 유지)
    /// 3. R 이 구간 뒤에서 시작하면 → 그대로
    /// 4. 그 밖(숨은 텍스트를 건드림) → 펼친다
    private func shiftFolds(edit r: NSRange, delta: Int, dropped: inout [FoldSpan]) {
        let end = NSMaxRange(r)
        var kept: [FoldSpan] = []
        kept.reserveCapacity(folds.count)
        for var f in folds {
            let nl = f.hiddenStart - 1
            if r.location <= nl && end > nl { dropped.append(f); continue }
            if end < f.hiddenStart {
                f.hiddenStart += delta; f.hiddenEnd += delta
                if f.hiddenEnd <= f.hiddenStart || f.hiddenStart < 1 { dropped.append(f); continue }
                kept.append(f); continue
            }
            if r.location >= f.hiddenEnd { kept.append(f); continue }
            dropped.append(f)
        }
        folds = kept   // 개수가 같아도 오프셋이 옮겨졌을 수 있다
    }

    /// 후보 이동: 영역 앞의 편집은 통째로, 숨은 구간 안의 편집은 끝만 옮긴다. 경계를 걸치는 편집은 후보를 버린다 (다음 스캔이 다시 만든다)
    private func shiftCandidates(edit r: NSRange, replacement s: String, delta: Int) {
        let end = NSMaxRange(r)
        let insertsNewline = r.length == 0 && s.utf16.contains(10)
        var kept: [FoldCandidate] = []
        kept.reserveCapacity(candidates.count)
        for var c in candidates {
            if end < c.hiddenStart {                                    // 숨은 구간 앞 (머리 줄 안 포함)
                if end <= c.headerStart {                               // 머리 줄 앞
                    if end == c.headerStart && r.length > 0 { continue }                        // 앞 줄과 합쳐짐 — 버림
                    if end < c.headerStart || insertsNewline { c.headerStart += delta }         // 머리 줄 첫머리의 글자 입력은 시작을 바꾸지 않는다
                } else if r.location < c.headerStart { continue }                               // 머리 줄 시작을 걸침 — 버림
                c.hiddenStart += delta; c.hiddenEnd += delta
            } else if r.location >= c.hiddenEnd {
                // 뒤쪽 편집 — 그대로
            } else if r.location >= c.hiddenStart && end <= c.hiddenEnd {
                c.hiddenEnd += delta
                if c.hiddenEnd <= c.hiddenStart { continue }
            } else {
                continue
            }
            kept.append(c)
        }
        if kept != candidates { candidates = kept; gutter?.needsDisplay = true }
    }

    // MARK: 영역 스캔 (백그라운드)

    private func rescan() {
        guard Self.isEnabled, let doc = document else { return }
        scanTask?.cancel()
        let text = doc.textStorage.string
        let isMD = ["md", "markdown"].contains(doc.url.pathExtension.lowercased())
        let gen = editGeneration
        scanTask = Task { [weak self] in
            let found = await Task.detached(priority: .utility) { () -> [FoldCandidate] in
                let ns = text as NSString
                let idx = LineIndex(nsString: ns)
                let regions = Perf.measure("fold.scan.regions lines=\(idx.lineCount)", threshold: 0) { FoldScanner.regions(in: ns, index: idx, isMarkdown: isMD) }
                let n = idx.lineCount
                return regions.compactMap { r in
                    guard r.startLine >= 1, r.endLine <= n, r.startLine < r.endLine else { return nil }
                    let headerStart = idx.lineStarts[r.startLine - 1]
                    let hiddenStart = idx.lineStarts[r.startLine]
                    let hiddenEnd = r.endLine < n ? idx.lineStarts[r.endLine] : idx.utf16Count
                    return FoldCandidate(headerStart: headerStart, hiddenStart: hiddenStart, hiddenEnd: hiddenEnd, lines: r.endLine - r.startLine)
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            // 스캔 중에 편집이 있었으면 버린다 — 그 편집이 lineIndex 를 다시 발행해 새 스캔이 돈다
            guard gen == self.editGeneration else { return }
            self.apply(candidates: found)
        }
    }

    /// 새 후보 적용 + 기존 접힘을 후보에 맞춰 보정 (머리 줄이 더 이상 영역을 거느리지 않으면 펼친다)
    private func apply(candidates found: [FoldCandidate]) {
        let before = candidates
        candidates = found
        if Perf.enabled { Perf.log("fold.scan candidates=\(found.count) folds=\(folds.map { "\($0.hiddenStart)..<\($0.hiddenEnd)" })") }
        var changedFolds = false
        if !folds.isEmpty, let ns = textView?.string as NSString? {
            var kept: [FoldSpan] = []
            var lo = Int.max, hi = 0
            for f in folds {
                let headerStart = ns.paragraphRange(for: NSRange(location: max(0, min(f.hiddenStart - 1, ns.length)), length: 0)).location
                if let i = candidateIndex(headerStart: headerStart) {
                    let c = candidates[i]
                    let snapped = FoldSpan(hiddenStart: c.hiddenStart, hiddenEnd: c.hiddenEnd, lines: c.lines)
                    if snapped != f { changedFolds = true; lo = min(lo, min(f.hiddenStart, c.hiddenStart)); hi = max(hi, max(f.hiddenEnd, c.hiddenEnd)) }
                    kept.append(snapped)
                } else {
                    if Perf.enabled { Perf.log("fold.scan drop fold \(f.hiddenStart)..<\(f.hiddenEnd) header@\(headerStart) — no candidate") }
                    changedFolds = true; lo = min(lo, f.hiddenStart); hi = max(hi, f.hiddenEnd)
                }
            }
            if changedFolds {
                folds = kept.sorted { $0.hiddenStart < $1.hiddenStart }
                rebuildMerged()
                invalidateLayout(from: max(0, lo - 1), to: hi)
                // 보정으로 캐럿이 숨겨졌으면(머리 바로 아래에 새로 쓴 줄 등) 그 접힘을 펼친다
                if let tv = textView, tv.selectedRange().length == 0, isOffsetHidden(tv.selectedRange().location) {
                    unfoldAll(containing: tv.selectedRange().location, reason: nil)
                }
                changed()
            }
        }
        if before != candidates { gutter?.needsDisplay = true }
    }

    // MARK: 내부

    private func contains(_ c: FoldCandidate, _ offset: Int) -> Bool {
        guard offset >= c.headerStart else { return false }
        if offset < c.hiddenEnd { return true }
        let len = textView?.textStorage?.length ?? 0
        return offset == c.hiddenEnd && c.hiddenEnd == len   // 문서 끝에서 끝나는 영역의 끝에 캐럿
    }

    private func foldIndex(hiddenStart: Int) -> Int? {
        var lo = 0, hi = folds.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if folds[mid].hiddenStart == hiddenStart { return mid }
            if folds[mid].hiddenStart < hiddenStart { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }

    private func candidateIndex(headerStart: Int) -> Int? {
        var lo = 0, hi = candidates.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if candidates[mid].headerStart == headerStart { return mid }
            if candidates[mid].headerStart < headerStart { lo = mid + 1 } else { hi = mid - 1 }
        }
        return nil
    }

    /// 레이아웃 delegate 는 접힘이나 가릴 줄(secrets)이 하나라도 있을 때만 설치한다 — delegate 가 있으면 TextKit 이 키 입력마다 프래그먼트를 만드는 경로가
    /// 느려진다 (실측 약 1 ms/키). 접힘·마스크 집합이 비거나 생길 때 부른다 (SecretController 도 부른다)
    func updateLayoutDelegate() {
        guard Self.isEnabled, let lm = textView?.textLayoutManager else { return }
        let want: NSTextLayoutManagerDelegate? = (folds.isEmpty && !(hasMasks?() ?? false)) ? nil : layoutDelegate   // secrets
        if (lm.delegate as AnyObject?) !== (want as AnyObject?) { lm.delegate = want }
    }

    private func rebuildMerged() {
        updateLayoutDelegate()
        var out: [NSRange] = []
        out.reserveCapacity(folds.count)
        for f in folds {
            if let last = out.last, f.hiddenStart <= NSMaxRange(last) {
                out[out.count - 1] = NSRange(location: last.location, length: max(NSMaxRange(last), f.hiddenEnd) - last.location)
            } else {
                out.append(NSRange(location: f.hiddenStart, length: f.hiddenEnd - f.hiddenStart))
            }
        }
        merged = out
    }

    /// 범위의 레이아웃 프래그먼트를 다시 만들게 한다. 실측(macOS 27 TextKit 2): invalidateLayout(for:) 은 기존 프래그먼트 객체를 재사용해
    /// delegate 를 다시 부르지 않으므로, 테마 적용과 같은 속성 편집 통지로 보이는 프래그먼트를 재생성한다 (문자열·undo·dirty 에는 영향 없음).
    /// SecretController 도 가림 상태가 바뀐 문단을 다시 만들 때 쓴다 (secrets)
    func invalidateLayout(from start: Int, to end: Int) {
        guard let tv = textView, let ts = tv.textStorage else { return }
        let len = ts.length
        let a = max(0, min(start, len)), b = max(a, min(end, len))
        guard b > a || len == 0 else { tv.needsDisplay = true; return }
        Perf.measure("fold.invalidate len=\(b - a)", threshold: 1) {
            ts.beginEditing()
            ts.edited(.editedAttributes, range: NSRange(location: a, length: b - a), changeInLength: 0)
            ts.endEditing()
        }
        tv.needsLayout = true
        tv.needsDisplay = true
        gutter?.needsDisplay = true
    }
}

// MARK: - TextKit 2

/// 숨은 문단: 높이 0, 아무것도 그리지 않는다 → 다음 문단이 머리 줄 바로 아래에 쌓인다
final class FoldedLayoutFragment: NSTextLayoutFragment {
    override var layoutFragmentFrame: CGRect {
        var f = super.layoutFragmentFrame
        f.size.height = 0
        return f
    }
    override var renderingSurfaceBounds: CGRect { .zero }
    override func draw(at point: CGPoint, in context: CGContext) {}
}

/// 문단마다 "숨길까" 를 FoldController 에 묻고 (NSTextView 는 기본 delegate 를 두지 않는다 — 실측), 숨기지 않으면 "가릴까"(secrets) 를 묻는다
final class FoldLayoutDelegate: NSObject, NSTextLayoutManagerDelegate {
    weak var controller: FoldController?

    func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
        let range = textElement.elementRange
        return MainActor.assumeIsolated { () -> NSTextLayoutFragment in
            guard let c = controller, let cs = textLayoutManager.textContentManager as? NSTextContentStorage else {
                return NSTextLayoutFragment(textElement: textElement, range: range)
            }
            let offset = cs.offset(from: cs.documentRange.location, to: location)
            if c.hasFolds, c.isOffsetHidden(offset) { return FoldedLayoutFragment(textElement: textElement, range: range) }
            if let masked = c.maskedFragment?(offset, textElement, range) { return masked }   // secrets: 비밀 줄
            return NSTextLayoutFragment(textElement: textElement, range: range)
        }
    }
}

// MARK: - HyperTextView 쪽 그리기·이동 (훅만 쓴다 — 접힘 상태는 모른다)

extension HyperTextView {
    /// 접힌 머리 줄 끝에 `⋯ N lines` 표식을 그린다 (drawBackground 에서 — 글자가 없는 자리라 본문 아래 그려도 같다). 클릭 판정용 사각형을 남긴다
    func drawFoldPills() {
        foldPillRects = []
        guard hasFolds?() == true, let provider = foldPills, let lm = textLayoutManager, let cs = textContentStorage else { return }
        let visible = visibleRect
        let origin = textContainerOrigin
        let length = textStorage?.length ?? 0
        func fragment(atY y: CGFloat) -> NSTextLayoutFragment? { lm.textLayoutFragment(for: CGPoint(x: 0, y: max(0, y - origin.y))) }
        let start = fragment(atY: visible.minY).map { cs.offset(from: cs.documentRange.location, to: $0.rangeInElement.location) } ?? 0
        let end = fragment(atY: visible.maxY).map { cs.offset(from: cs.documentRange.location, to: $0.rangeInElement.endLocation) } ?? length
        guard end >= start else { return }
        let pills = provider(NSRange(location: start, length: end - start))
        guard !pills.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: max(9, ((typingAttributes[.font] as? NSFont)?.pointSize ?? 13) - 3), weight: .medium)
        for p in pills {
            guard let r = caretRect(at: p.headerEnd) else { continue }
            let label = String(localized: "⋯ \(p.lines) lines") as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foldPillTextColor]
            let size = label.size(withAttributes: attrs)
            let h = min(r.height - 2, size.height + 4)
            let rect = NSRect(x: r.maxX + 8, y: r.midY - h / 2, width: size.width + 12, height: h)
            let path = NSBezierPath(roundedRect: rect, xRadius: h / 2, yRadius: h / 2)
            foldPillFillColor.setFill(); path.fill()
            foldPillTextColor.withAlphaComponent(0.5).setStroke(); path.lineWidth = 1; path.stroke()
            label.draw(at: NSPoint(x: rect.minX + 6, y: rect.midY - size.height / 2), withAttributes: attrs)
            foldPillRects.append((rect, p.hiddenStart))
        }
    }

    /// ↑/↓: 목적지 줄이 숨겨져 있으면 접힌 구간을 건너뛴다. 처리했으면 true
    func moveAcrossFold(down: Bool) -> Bool {
        guard let hidden = isOffsetHidden, let span = foldedSpan, selectedRange().length == 0 else { return false }
        let ns = string as NSString
        let caret = min(selectedRange().location, ns.length)
        let cur = ns.lineRange(for: NSRange(location: caret, length: 0))
        let col = caret - cur.location
        var targetLine: NSRange
        if down {
            let next = NSMaxRange(cur)
            guard next < ns.length, hidden(next), let s = span(next) else { return false }
            if NSMaxRange(s) >= ns.length {
                // 접힘이 문서 끝까지 닿으면 들어갈 보이는 줄이 없다 — AppKit 의 마지막 줄 ↓ 처럼 머리 줄 끝에 머문다 (숨은 끝 오프셋에 둔 캐럿은 보이지 않는다)
                var contentEnd = NSMaxRange(cur)
                if cur.length > 0, ns.character(at: contentEnd - 1) == 10 { contentEnd -= 1 }
                setSelectedRange(NSRange(location: contentEnd, length: 0)); scrollRangeToVisible(selectedRange()); return true
            }
            targetLine = ns.lineRange(for: NSRange(location: NSMaxRange(s), length: 0))
        } else {
            guard cur.location > 0 else { return false }
            let prevStart = ns.lineRange(for: NSRange(location: cur.location - 1, length: 0)).location
            guard hidden(prevStart), let s = span(prevStart), s.location > 0 else { return false }
            targetLine = ns.lineRange(for: NSRange(location: s.location - 1, length: 0))
        }
        var content = targetLine.length
        if content > 0, ns.character(at: NSMaxRange(targetLine) - 1) == 10 { content -= 1 }
        let target = targetLine.location + min(col, content)
        setSelectedRange(NSRange(location: target, length: 0))
        scrollRangeToVisible(NSRange(location: target, length: 0))
        return true
    }
}
