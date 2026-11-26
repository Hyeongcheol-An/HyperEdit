import AppKit
import Combine
import HyperCore

// 접기(fold).
//
// 설계
// - 접힘 상태는 **문서(콘텐츠 스토리지) 하나에 하나**다: `FoldStore`. 분할된 두 편집기는 NSTextContentStorage 하나에 레이아웃 매니저만 따로 붙이므로(EditorSession)
//   접힘도 함께 쓴다 — 한쪽에서 접으면 양쪽이 접힌다. 편집기마다 있는 `FoldController` 는 그 뷰의 일(표식·거터 화살표·명령·캐럿·보던 곳 지키기)만 맡는다.
// - 숨김은 숨은 문단을 **콘텐츠 열거에서 빼는 것**으로 구현한다: `NSTextContentStorageDelegate.textContentManager(_:shouldEnumerate:options:)` 가 false 를 돌려준다
//   (`FoldEnumerationDelegate`). 레이아웃 매니저는 그 문단을 아예 보지 못하므로 조각도 높이 추정도 없고, 머리 줄 바로 아래에 다음 보이는 문단이 쌓인다.
//   2026-11-25 까지는 레이아웃 delegate 가 숨은 문단에 높이 0 조각을 돌려줬다. 그 0 은 배치된 조각에만 통한다: TextKit 2 는 배치하지 않은 구간의 높이를 문단
//   내용으로 어림하고(창 없는 실험: 30,000줄 중 27,000줄을 접은 문서의 끝을 실제 51,000 pt 가 아니라 537,651 pt 로 답했다 — 접지 않은 값 그대로), 배치한 조각은
//   2,000개까지만 붙든다(docs/design.ko.md 5절). 그래서 접힌 큰 문서는 스크롤·리플로 패스마다 좌표가 수만 pt 씩 바뀌었다. 열거에서 빼면 같은 문서가 52,760 pt 다.
// - 숨은 문단은 요소로 만들어지지도 않게 한다: 콘텐츠 스토리지(`FoldingContentStorage`)가 열거 중 숨은 구간을 만나면 그 끝에서 다시 시작한다.
//   delegate 만으로는 NSTextContentStorage 가 "숨길까" 를 물으려고 숨은 문단마다 요소를 만들어 캐시에 넣는데, 그 장부 정리가 접힌 큰 문서의 배치 시간을 차지했다.
// - 문서의 **마지막 문단만은 열거에 남긴다.** 마지막 문단이 열거에서 빠지면 NSTextView 가 문서 높이를 구하지 못한다(실측: 높이가 배치한 화면만큼만 잡히고 —
//   30,000줄 문서가 629 pt — End 키가 움직이지 않는다). 그 문단은 두 겹으로 숨긴다: 조각은 높이 0 이라 답하고 그리지 않으며(`FoldedLayoutFragment`,
//   레이아웃 delegate — 거터·닻이 숨은 줄로 알아본다), 문단 요소는 0.01 pt 짜리 표시용 문단으로 바꿔 준다(`textContentStorage(_:textParagraphWith:)`).
//   조각이 0 이라 답해도 문서 높이에는 실제로 배치된 높이가 들어가기 때문이다(실측: 네 줄로 감긴 마지막 문단을 접자 마지막 보이는 줄 아래에 68 pt 가 비었다).
// - 접힘이 바뀌면 그 범위에 `edited(.editedAttributes)` 를 알린다 (문자열·undo·dirty 에는 영향 없음). `invalidateLayout(for:)` 만으로도 요소는 다시 열거되지만
//   뷰포트 위쪽 구간의 높이 어림이 옛 값으로 남는다(실측: 문서 끝에서 모두 펴면 510,000 pt 문서를 56,275 pt 로, 가운데에서 모두 접으면 51,000 pt 를 299,264 pt 로
//   본다). 속성 편집 통지는 그 구간의 어림을 버리고, 이미 만든 조각도 다시 만들게 한다(마지막 문단의 숨김이 바뀔 때 필요하다).
// - 접힘 범위는 줄 번호가 아니라 문서 오프셋(UTF-16)으로 둔다: `hiddenStart`(첫 숨은 문단의 시작) ~ `hiddenEnd`(마지막 숨은 문단의 끝 = 다음 보이는 문단의 시작).
//   머리 줄은 `hiddenStart` 바로 앞 문단이다. 줄 인덱스는 편집 뒤 250 ms 동안 낡아 있는데, TextKit 2 는 편집 직후에 문단을 다시 열거하며 "이 문단을 숨길까" 를
//   묻는다 — 오프셋은 `HyperTextView.onTextWillChange`(모든 편집, 저장소 변경 직전)에서 즉시 옮기므로 그 틈이 없다.
// - 접기 후보(영역)는 `FoldScanner` 가 백그라운드에서 문서 스냅샷으로 계산한다 (`document.$lineIndex` 발행 = 입력 멈춤 250 ms 뒤). 키 입력마다 하는 일은 후보·접힘 오프셋 이동뿐.
// - 캐럿이 숨은 줄로 들어가면(검색·줄 이동·북마크·undo) 자동으로 펼친다. ↑/↓ 는 HyperTextView 가 접힌 구간을 건너뛴다.

/// 접힌 영역 하나 (문서 오프셋)
struct FoldSpan: Hashable {
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
    let headerEnd: Int      // 머리 줄 텍스트 끝 오프셋 (개행 앞 — \r\n 으로 끝나는 줄이면 \r 앞)
    let hiddenStart: Int    // 접힘 식별자
    let lines: Int
}

// MARK: - 문서 단위 상태

/// 문서(콘텐츠 스토리지) 하나의 접힘과 접기 후보. 그 문서를 보여 주는 편집기들(`FoldController`)이 함께 쓴다
@MainActor
final class FoldStore {
    private static var associationKey: UInt8 = 0

    /// 콘텐츠 스토리지에 딸린 상태 (없으면 만든다) — 스토리지가 살아 있는 동안 유지된다
    static func shared(for contentStorage: NSTextContentStorage) -> FoldStore {
        if let s = objc_getAssociatedObject(contentStorage, &associationKey) as? FoldStore { return s }
        let s = FoldStore(contentStorage: contentStorage)
        objc_setAssociatedObject(contentStorage, &associationKey, s, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return s
    }

    private weak var contentStorage: NSTextContentStorage?
    private(set) var folds: [FoldSpan] = []              // hiddenStart 오름차순
    private(set) var candidates: [FoldCandidate] = []    // headerStart 오름차순
    private var merged: [NSRange] = []                   // folds 의 숨김 구간 합집합 (정렬, 겹침 없음)
    // 탭을 오갈 때의 접힘: 탭 전환은 같은 저장소에 다른 파일을 다시 읽어 넣으므로(MemoDocument.switchTo) 접힘이 사라진다. 떠날 때 파일별로 적어 두고,
    // 돌아와 첫 영역 스캔이 끝나면 같은 자리의 영역을 다시 접는다 (실행 중에만 — 세션에는 저장하지 않는다)
    private var remembered: [URL: [FoldSpan]] = [:]
    private var pendingRestore: [FoldSpan] = []
    private weak var document: MemoDocument?
    private var cancellables = Set<AnyCancellable>()
    private var scanTask: Task<Void, Never>?
    private var editGeneration = 0
    private let hider = FoldEnumerationDelegate()
    private struct Attached { weak var controller: FoldController? }
    private var attached: [Attached] = []                // 등록 순서 (주 편집기가 먼저)
    /// 대표가 아닌 편집기가 shouldChangeText 로 알린 편집이 저장소에 반영되는 중 — 같은 편집을 대표 편집기가 사후 통지로 다시 전하면 한 번 건너뛴다
    private var skipsNextUntrackedEdit = false
    /// 편집이 없앤(펼친) 접힘의 범위 가운데 아직 다시 배치하지 않은 것 — **지금 글의 좌표**로 든다. 다시 배치는 저장소 편집 처리가 끝난 다음 턴에 하는데, 그 사이의
    /// 편집(같은 묶음의 앞쪽 범위들 — 모두 바꾸기, 같은 턴의 다음 편집 — 매크로)이 이 범위를 옮긴다 (shiftStale)
    private var stale: (lo: Int, hi: Int)?
    private var staleFlushScheduled = false

    private init(contentStorage: NSTextContentStorage) {
        self.contentStorage = contentStorage
    }

    // MARK: 편집기 · 문서 연결

    private var controllers: [FoldController] { attached.compactMap(\.controller) }

    /// 키 입력을 받고 있는 편집기 (첫 응답자). 편집·다시 스캔이 접힘을 펼 때 이 편집기는 캐럿 줄을 지킨다 — 거기서 쓰고 있다
    private var focusedController: FoldController? {
        controllers.first { c in c.textView.map { $0.window?.firstResponder === $0 } ?? false }
    }

    func attach(_ c: FoldController) {
        attached.removeAll { $0.controller == nil || $0.controller === c }
        attached.append(Attached(controller: c))
        c.updateLayoutDelegate()   // 이미 접힌 문서에 붙는 둘째 편집기(분할을 켤 때)
    }

    /// 편집기가 닫힐 때(분할 해제). 남은 편집기가 없으면 구독과 진행 중인 스캔을 끊는다
    func detach(_ c: FoldController) {
        attached.removeAll { $0.controller == nil || $0.controller === c }
        guard attached.isEmpty else { return }
        cancellables.removeAll()
        scanTask?.cancel(); scanTask = nil
        document = nil
    }

    /// 문서 연결 (파일 전환·다시 읽기·줄 인덱스 갱신을 구독). 분할의 둘째 편집기가 같은 문서로 다시 부르면 아무것도 하지 않는다 — 접힘은 그대로다
    func bind(document doc: MemoDocument) {
        guard document !== doc else { return }
        cancellables.removeAll()
        document = doc
        reset()
        doc.$lineIndex
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rescan() }
            .store(in: &cancellables)
        // @Published 는 willSet 에 발행 — 내용 교체 전에 접힘을 비운다 (새 파일의 영역은 lineIndex 발행으로 다시 계산)
        doc.$url.removeDuplicates().dropFirst()
            .sink { [weak self] newURL in
                guard let self else { return }
                // 아직 떠나는 파일(willSet). 그 파일의 접힘을 되살리기도 전에 다시 떠나는 길이면(빠르게 지나친 탭) 적어 둔 것을 그대로 둔다
                if let old = self.document?.url, self.pendingRestore.isEmpty { self.remembered[old] = self.folds.isEmpty ? nil : self.folds }
                self.reset()
                self.pendingRestore = self.remembered[newURL] ?? []
            }
            .store(in: &cancellables)
        doc.$reloadGeneration.dropFirst()
            .sink { [weak self] _ in self?.reset() }
            .store(in: &cancellables)
    }

    /// 접힘·후보 전부 비움 (파일 전환, 디스크에서 다시 읽기 — 내용이 통째로 바뀌므로 보던 곳은 지키지 않는다)
    func reset() {
        scanTask?.cancel()
        candidates = []
        stale = nil
        guard !folds.isEmpty else { controllers.forEach { $0.gutter?.needsDisplay = true }; return }
        folds = []
        rebuildMerged()
        invalidateLayout(from: 0, to: Int.max)
        controllers.forEach { $0.changed() }
    }

    // MARK: 질의

    var hasFolds: Bool { !folds.isEmpty }

    /// 편집마다 옮겨야 할 것이 있는가: 접힘, 접기 후보, 아직 다시 배치하지 않은 범위. 되돌리기·다시 실행은 닫힌 접힘이 없어도 이것이 참이면 전해져야 한다
    /// (HyperTextView.tracksUndoEdits) — 후보가 옛 오프셋에 남으면 거터 화살표가 사라지고 그사이의 접기 명령이 밀린 범위를 접는다
    var tracksEdits: Bool { !folds.isEmpty || !candidates.isEmpty || stale != nil }

    /// 문서 오프셋이 숨은 문단 안인가 (문단 시작 오프셋으로 묻는 것이 정확하다)
    func isOffsetHidden(_ offset: Int) -> Bool { hiddenSpan(containing: offset) != nil }

    /// 숨김 구간(시작 `hiddenStart`) 앞 머리 줄의 내용 끝 — 캐럿·표식·닻이 놓이는 "머리 줄 끝". 줄이 \r\n 으로 끝나면 \r 앞이다: hiddenStart − 1 은 \r 과 \n
    /// 사이라, 접은 뒤 거기 놓인 캐럿에 친 글자가 줄 끝을 깨뜨린다 (실측: `):\rQ\n` — 혼자인 \r 이 줄을 하나 더 만든다). \n 으로만 끝나는 줄에서는 hiddenStart − 1 그대로다
    func headerEnd(before hiddenStart: Int) -> Int {
        let end = max(0, hiddenStart - 1)
        guard end > 0, let ns = contentStorage?.textStorage?.mutableString, end < ns.length, ns.character(at: end) == 10, ns.character(at: end - 1) == 13 else { return end }
        return end - 1
    }

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
        if let last = merged.last, offset == NSMaxRange(last), offset == (contentStorage?.textStorage?.length ?? -1) { return last }
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
            let headerEnd = self.headerEnd(before: f.hiddenStart)
            if headerEnd > NSMaxRange(visible) { break }
            if isOffsetHidden(headerEnd) { continue }
            out.append(FoldPill(headerEnd: headerEnd, hiddenStart: f.hiddenStart, lines: f.lines))
        }
        return out
    }

    /// 거터 화살표: 문단(개행 포함) 범위로 묻는다
    func marker(paragraphStart: Int, paragraphEnd: () -> Int) -> GutterView.FoldMarker? {
        guard !folds.isEmpty || !candidates.isEmpty else { return nil }
        if foldIndex(hiddenStart: paragraphEnd()) != nil { return .folded }
        if candidateIndex(headerStart: paragraphStart) != nil { return .foldable }
        return nil
    }

    /// 후보 영역이 오프셋을 품는가 (머리 줄 포함. 문서 끝에서 끝나는 영역은 끝 오프셋도)
    func contains(_ c: FoldCandidate, _ offset: Int) -> Bool {
        guard offset >= c.headerStart else { return false }
        if offset < c.hiddenEnd { return true }
        let len = contentStorage?.textStorage?.length ?? 0
        return offset == c.hiddenEnd && c.hiddenEnd == len   // 문서 끝에서 끝나는 영역의 끝에 캐럿
    }

    func foldIndex(hiddenStart: Int) -> Int? {
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

    // MARK: 접기 / 펼치기 (`by`: 명령을 내린 편집기 — 기록을 남기고, 캐럿이 숨으면 그 편집기만 캐럿을 따라 스크롤한다)

    func fold(_ c: FoldCandidate, by initiator: FoldController?) {
        guard foldIndex(hiddenStart: c.hiddenStart) == nil, c.hiddenEnd > c.hiddenStart else { return }
        if Perf.enabled { Perf.log("fold.fold \(c.headerStart)/\(c.hiddenStart)..<\(c.hiddenEnd) caret=\(initiator?.textView?.selectedRange().location ?? -1)") }
        var next = folds
        next.append(FoldSpan(hiddenStart: c.hiddenStart, hiddenEnd: c.hiddenEnd, lines: c.lines))
        next.sort { $0.hiddenStart < $1.hiddenStart }
        commit(next, by: initiator)
        if let idx = document?.lineIndex {
            let h = idx.lineNumber(forUTF16Offset: c.headerStart)
            initiator?.log?(String(localized: "Folded lines \(h)–\(h + c.lines)"))
        }
    }

    func unfold(hiddenStart: Int, reason: String?, by initiator: FoldController?) {
        guard let i = foldIndex(hiddenStart: hiddenStart) else { return }
        unfold(at: [i], reason: reason, by: initiator)
    }

    private func unfold(at indexes: [Int], reason: String?, by initiator: FoldController?) {
        guard !indexes.isEmpty else { return }
        let gone = indexes.map { folds[$0] }
        // 한 번에 걸러 낸다 — 하나씩 지우면 지울 때마다 뒤쪽을 당긴다 (실측: 접힘 15,000개의 앞 절반을 펼 때 26 ms → 0.4 ms)
        let dropped = Set(indexes)
        let next = folds.enumerated().filter { !dropped.contains($0.offset) }.map(\.element)
        if Perf.enabled { Perf.log("fold.unfold \(gone.map { "\($0.hiddenStart)..<\($0.hiddenEnd)" }) reason=\(reason ?? "command") caret=\(initiator?.textView?.selectedRange().location ?? -1)") }
        commit(next, by: initiator)
        guard let idx = document?.lineIndex else { return }
        // 한꺼번에 많이 펴졌으면(여러 캐럿이 놓인 접힘들) 접힘마다 적지 않는다 — 출력 패널에 수천 줄이 쌓인다
        if gone.count > 8 { initiator?.log?(String(localized: "Unfolded \(gone.count) regions") + (reason.map { " · \($0)" } ?? "")); return }
        for f in gone {
            let h = idx.lineNumber(forUTF16Offset: max(0, f.hiddenStart - 1))
            initiator?.log?(String(localized: "Unfolded lines \(h)–\(h + f.lines)") + (reason.map { " · \($0)" } ?? ""))
        }
    }

    /// 오프셋을 숨기고 있는 접힘을 전부 펼친다 (바깥 → 안쪽). 문서 끝까지 닿는 접힘은 끝 오프셋(= 문서 길이)도 숨긴 것으로 본다 — hiddenSpan 과 같은 규칙
    /// (⌘↓·문서 끝 이동으로 캐럿이 거기 놓이면 펼쳐져야 보인다)
    func unfoldAll(containing offset: Int, reason: String?, by initiator: FoldController?) {
        unfold(at: folds.indices.filter { hides(folds[$0], offset) }, reason: reason, by: initiator)
    }

    /// 오프셋들 가운데 하나라도 숨기는 접힘을 한 번에 펼친다 (열 블록의 행·여러 캐럿). 모두 접은 문서에서 모든 일치를 캐럿으로 고르면 접힘도 캐럿도 수천 개다 —
    /// 접힘마다 "그 시작 이후의 첫 캐럿"만 이분 탐색으로 본다
    func unfoldAll(containingAnyOf offsets: [Int], reason: String?, by initiator: FoldController?) {
        let inside = offsets.filter { isOffsetHidden($0) }.sorted()
        guard !inside.isEmpty else { return }
        unfold(at: folds.indices.filter { i in
            var lo = 0, hi = inside.count
            while lo < hi { let mid = (lo + hi) / 2; if inside[mid] < folds[i].hiddenStart { lo = mid + 1 } else { hi = mid } }
            return lo < inside.count && hides(folds[i], inside[lo])
        }, reason: reason, by: initiator)
    }

    private func hides(_ f: FoldSpan, _ offset: Int) -> Bool {
        f.hiddenStart <= offset && (offset < f.hiddenEnd || (offset == f.hiddenEnd && offset == (contentStorage?.textStorage?.length ?? -1)))
    }

    /// 거터 화살표·`toggleFold(line:)`: 접혀 있으면 펼치고, 후보면 접는다
    func toggle(paragraphStart: Int, paragraphEnd: Int, by initiator: FoldController?) {
        guard !isOffsetHidden(paragraphStart) else { return }
        if let i = foldIndex(hiddenStart: paragraphEnd) { unfold(at: [i], reason: nil, by: initiator); return }
        if let i = candidateIndex(headerStart: paragraphStart) { fold(candidates[i], by: initiator) }
    }

    /// `toggleFold(line:)` — 1-based 줄 (문서 줄 인덱스 기준)
    func toggle(line: Int, by initiator: FoldController?) {
        guard let idx = document?.lineIndex, line >= 1, line <= idx.lineCount else { return }
        let start = idx.lineStarts[line - 1]
        let end = line < idx.lineCount ? idx.lineStarts[line] : idx.utf16Count
        toggle(paragraphStart: start, paragraphEnd: end, by: initiator)
    }

    func foldAll(by initiator: FoldController?) {
        let before = folds.count
        var all = candidates.map { FoldSpan(hiddenStart: $0.hiddenStart, hiddenEnd: $0.hiddenEnd, lines: $0.lines) }
        all.sort { $0.hiddenStart < $1.hiddenStart }
        // 캐럿 줄이 보이고 있으면 그 높이를 지킨다 — 캐럿 줄이 접혀 사라지면 캐럿이 옮겨 갈 머리 줄이 그 높이에 온다 (FoldController.foldsDidChange).
        // 맨 위 줄을 지키면 그 사이의 영역이 접히는 만큼 캐럿의 머리 줄이 화면 위쪽으로 끌려 올라간다
        commit(all, by: initiator, anchorOnCaret: true)
        initiator?.log?(String(localized: "Folded \(folds.count - before) regions"))
    }

    func unfoldEverything(by initiator: FoldController?) {
        let n = folds.count
        // 펴기는 캐럿 줄을 지킨다: 맨 위 줄을 지키면 그 줄과 캐럿 사이의 접힘이 펴지며 캐럿 줄이 화면 아래로 밀려난다 (실측: 네 구역 아래의 캐럿이 576 pt)
        commit([], by: initiator, anchorOnCaret: true)
        initiator?.log?(String(localized: "Unfolded \(n) regions"))
    }

    /// 접힘 집합을 바꾼다. 달라진 접힘의 범위만 다시 배치하고, 이 문서를 보여 주는 편집기마다 보던 곳을 지킨다 (FoldController.foldsWillChange / foldsDidChange).
    /// - `anchorOnCaret`: 명령을 내린 편집기는 캐럿 줄이 보이고 있으면 그 줄을 지킨다 (아니면, 그리고 다른 편집기는 맨 위 줄)
    /// - `adjustsSelection`: 숨겨진 캐럿·선택을 보이는 자리로 옮긴다 (명령으로 접을 때). 스캔 보정·탭 복귀는 캐럿을 숨기는 접힘을 처음부터 뺀다 (sparingCarets)
    private func commit(_ newFolds: [FoldSpan], by initiator: FoldController?, anchorOnCaret: Bool = false, adjustsSelection: Bool = true) {
        let changed = Set(folds).symmetricDifference(newFolds)
        guard let lo = changed.map(\.hiddenStart).min(), let hi = changed.map(\.hiddenEnd).max() else { return }
        relayout(from: max(0, lo - 1), to: hi, by: initiator, anchorOnCaret: anchorOnCaret, adjustsSelection: adjustsSelection) {
            folds = newFolds
            rebuildMerged()
        }
    }

    /// `apply` 로 숨김을 바꾸고 [start, end) 의 배치를 다시 하게 한다. 그 앞뒤로 편집기마다 보던 곳을 잡았다가 되돌린다
    private func relayout(from start: Int, to end: Int, by initiator: FoldController?, anchorOnCaret: Bool = false, adjustsSelection: Bool, _ apply: () -> Void) {
        let views = controllers
        let kept = views.map { $0.foldsWillChange(anchorOnCaret: anchorOnCaret && $0 === initiator) }
        apply()
        invalidateLayout(from: start, to: end)
        for (c, k) in zip(views, kept) { c.foldsDidChange(k, isInitiator: c === initiator, adjustsSelection: adjustsSelection) }
    }

    /// 어느 편집기의 캐럿도, 선택의 끝도, 열 블록의 행·추가 캐럿도 숨기지 않는 접힘만 남긴다 (스캔 보정·탭 복귀: 쓰고 있는 자리가 접혀 사라지면 안 된다 —
    /// 머리 바로 아래에 새로 쓴 줄 등). 선택이 든 줄이 숨으면 다음 키가 보이지 않는 글을 바꾼다. 접힘을 통째로 가로지르는 선택(양 끝이 보인다)과, 끝이 숨김
    /// 구간의 시작(머리 줄의 개행 바로 뒤)에 딱 놓인 선택은 접힌 채 둔다 — FoldController.selectionDidChange 와 같은 규칙
    private func sparingCarets(_ spans: [FoldSpan]) -> [FoldSpan] {
        var carets: [Int] = [], ends: [Int] = []
        for c in controllers {
            guard let tv = c.textView else { continue }
            for r in tv.multi?.ranges ?? tv.selectedRanges.map(\.rangeValue) {
                carets.append(r.location)
                if r.length > 0 { ends.append(NSMaxRange(r)) }
            }
        }
        guard !carets.isEmpty else { return spans }
        // 접힘마다 "그 시작 이후의 첫 캐럿"만 본다 (unfoldAll(containingAnyOf:) 처럼) — 모든 쌍을 보면 접힘 15,000개 × 캐럿 3,000개에 41 ms (이분 탐색 0.5 ms)
        carets.sort(); ends.sort()
        func firstIndex(in sorted: [Int], where reached: (Int) -> Bool) -> Int {
            var lo = 0, hi = sorted.count
            while lo < hi { let mid = (lo + hi) / 2; if reached(sorted[mid]) { hi = mid } else { lo = mid + 1 } }
            return lo
        }
        return spans.filter { f in
            let c = firstIndex(in: carets) { $0 >= f.hiddenStart }
            if c < carets.count, hides(f, carets[c]) { return false }
            let e = firstIndex(in: ends) { $0 > f.hiddenStart }
            return !(e < ends.count && ends[e] < f.hiddenEnd)
        }
    }

    // MARK: 편집 추적 (편집 전 좌표. 보통 저장소 변경 직전, undo/redo 는 변경 직후 사후 통지)

    /// 편집기가 전하는 편집 통지. 분할 보기에서는 같은 편집이 편집기마다 온다 — 한 번만 옮긴다:
    /// · 추적된 편집(alreadyApplied == false)은 편집한 편집기만 알린다 (그 편집기는 자기 저장소 알림을 건너뛴다 — HyperTextView.expectingTrackedEdit).
    /// · 사후 통지(alreadyApplied — undo/redo, 그리고 다른 편집기가 추적한 편집의 저장소 알림)는 먼저 등록된 대표 편집기의 것만 받는다.
    ///   대표가 아닌 편집기가 추적한 편집이면 대표의 사후 통지는 같은 편집이므로 한 번 버린다
    func textWillChange(_ edits: [(NSRange, String)], alreadyApplied: Bool, from sender: FoldController) {
        let isRepresentative = controllers.first === sender
        if alreadyApplied {
            guard isRepresentative else { return }
            if skipsNextUntrackedEdit { skipsNextUntrackedEdit = false; return }
        } else if !isRepresentative {
            skipsNextUntrackedEdit = true
            DispatchQueue.main.async { [weak self] in self?.skipsNextUntrackedEdit = false }   // 편집이 취소돼 알림이 오지 않으면 다음 턴에 푼다
        }
        editGeneration &+= 1
        let tracking = !folds.isEmpty || !candidates.isEmpty
        guard tracking || stale != nil else { return }
        let before = folds
        for (r, s) in edits.sorted(by: { $0.0.location > $1.0.location }) {
            guard r.location != NSNotFound else { continue }
            let delta = (s as NSString).length - r.length
            shiftStale(edit: r, delta: delta)
            guard tracking else { continue }
            shiftFolds(edit: r, delta: delta)
            shiftCandidates(edit: r, replacement: s, delta: delta)
        }
        if Perf.enabled, alreadyApplied || folds != before {
            Perf.log("fold.edit applied=\(alreadyApplied) edits=\(edits.map { "\($0.0)→\(($0.1 as NSString).length)" }) folds \(before.map { "\($0.hiddenStart)..<\($0.hiddenEnd)" }) → \(folds.map { "\($0.hiddenStart)..<\($0.hiddenEnd)" }) candidates=\(candidates.count)")
        }
        if folds != before {
            rebuildMerged()   // 숨김 구간은 지금 옮긴다 — 편집 직후 TextKit 이 문단을 다시 열거할 때 새 오프셋으로 답해야 한다
            // 사후 통지(undo/redo)면 TextKit 이 편집된 문단을 옛 오프셋으로 이미 열거했을 수 있으므로 옮겨진 접힘 범위도 함께 다시 배치한다
            if alreadyApplied { for f in before + folds { markStale(f.hiddenStart, f.hiddenEnd) } }
        }
        // 펼쳐진 접힘의 문단은 다시 배치해야 보인다 (shiftFolds 가 적어 둔다). 지금은 저장소 편집 처리 중이라 이 턴이 끝난 뒤로 미룬다
        guard stale != nil, !staleFlushScheduled else { return }
        staleFlushScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.staleFlushScheduled = false
            guard let s = self.stale else { return }
            self.stale = nil
            // 쓰고 있는 편집기는 캐럿 줄을 지킨다 (화면에 보이고 있을 때) — 다시 스캔 쪽(apply)과 같은 규칙으로 둔다. 실측으로는 이 배치가 화면을 바꾼 경우를
            // 만들지 못했다: 편집이 편 접힘의 줄들은 편집 직후의 첫 배치에서 이미 놓이고, 여기서는 끝까지 닿던 접힘의 꼬리 문단을 다시 만들고 높이 어림을 버린다
            self.relayout(from: max(0, s.lo - 1), to: s.hi, by: self.focusedController, anchorOnCaret: true, adjustsSelection: false) {}
        }
    }

    private func markStale(_ lo: Int, _ hi: Int) {
        stale = stale.map { (min($0.lo, lo), max($0.hi, hi)) } ?? (lo, hi)
    }

    /// 아직 다시 배치하지 않은 범위를 편집(범위 R, 길이 변화 delta)만큼 옮긴다: 앞쪽의 편집은 통째로, 걸치는 편집은 그 편집까지 품게.
    /// 편집 전 오프셋으로 두면, 같은 묶음의 앞쪽 편집들이 글을 늘린 만큼 범위의 끝이 모자란다 — 문서 끝까지 닿던 접힘이면 마지막 문단이 무효화에서 빠져
    /// 높이 0 조각·0.01 pt 표시용 문단인 채로 남는다 (실측: 접힘 위·안의 일치를 함께 늘려 바꾸자 파일의 마지막 줄이 화면에 나오지 않았다)
    private func shiftStale(edit r: NSRange, delta: Int) {
        guard var s = stale else { return }
        let end = NSMaxRange(r)
        if end <= s.lo { s.lo += delta; s.hi += delta }
        else if r.location < s.hi { s.lo = min(s.lo, r.location); s.hi = max(s.hi, end) + delta }
        stale = (max(0, s.lo), max(s.lo, s.hi))
    }

    /// 접힘 이동 규칙 (편집 범위 R, 길이 변화 delta)
    /// 1. R 이 머리 줄의 개행(hiddenStart-1)을 지우면 → 머리와 첫 숨은 줄이 합쳐지므로 펼친다 (머리 줄 삭제 포함)
    /// 2. R 이 그 앞에서 끝나면 → 구간 전체를 delta 만큼 옮긴다 (머리 줄 안의 입력 포함 — 접힘 유지)
    /// 3. R 이 구간 뒤에서 시작하면 → 그대로
    /// 4. 그 밖(숨은 텍스트를 건드림) → 펼친다
    /// 펼친 접힘의 범위는 이 편집 **뒤**의 좌표로 적어 둔다 (markStale — 다음 턴에 다시 배치한다)
    private func shiftFolds(edit r: NSRange, delta: Int) {
        let end = NSMaxRange(r)
        var kept: [FoldSpan] = []
        kept.reserveCapacity(folds.count)
        func drop(_ f: FoldSpan) { markStale(min(f.hiddenStart, r.location), max(f.hiddenEnd, end) + delta) }
        for var f in folds {
            let nl = f.hiddenStart - 1
            if r.location <= nl && end > nl { drop(f); continue }
            if end < f.hiddenStart {
                f.hiddenStart += delta; f.hiddenEnd += delta
                if f.hiddenEnd <= f.hiddenStart || f.hiddenStart < 1 { markStale(max(0, min(f.hiddenStart, f.hiddenEnd)), max(f.hiddenStart, f.hiddenEnd)); continue }   // 이미 옮긴 좌표
                kept.append(f); continue
            }
            if r.location >= f.hiddenEnd { kept.append(f); continue }
            drop(f)
        }
        folds = kept   // 개수가 같아도 오프셋이 옮겨졌을 수 있다
    }

    /// 후보 이동: 영역 앞의 편집은 통째로, 숨은 구간 안의 편집은 끝만 옮긴다. 경계를 걸치는 편집은 후보를 버린다 (다음 스캔이 다시 만든다)
    private func shiftCandidates(edit r: NSRange, replacement s: String, delta: Int) {
        let end = NSMaxRange(r)
        let insertsNewline = r.length == 0 && s.utf16.contains(10)
        // 머리 줄 바로 앞까지를 바꾸는 편집: 줄 머리에서 시작해 통째로 지운 줄들(또는 개행으로 끝나는 글로 바꾼 것)이면 머리 줄은 여전히 줄 머리에서 시작한다 —
        // 그렇지 않으면 앞 줄과 합쳐진다. 편집 범위 앞의 글자는 편집 전후가 같으므로 사후 통지(undo/redo)에서도 같은 판단이다.
        // 이 구분이 없으면 영역 바로 위에 넣은 줄을 되돌릴 때마다 그 영역의 화살표가 다음 스캔까지 사라진다
        let keepsLineStart: Bool = {
            if let last = s.utf16.last { return last == 10 }
            guard r.location > 0 else { return true }
            guard let ns = contentStorage?.textStorage?.mutableString, r.location - 1 < ns.length else { return false }
            return ns.character(at: r.location - 1) == 10
        }()
        var kept: [FoldCandidate] = []
        kept.reserveCapacity(candidates.count)
        for var c in candidates {
            if end < c.hiddenStart {                                    // 숨은 구간 앞 (머리 줄 안 포함)
                if end <= c.headerStart {                               // 머리 줄 앞
                    let replacesUpToHeader = end == c.headerStart && r.length > 0
                    if replacesUpToHeader && !keepsLineStart { continue }                       // 앞 줄과 합쳐짐 — 버림
                    if end < c.headerStart || insertsNewline || replacesUpToHeader { c.headerStart += delta }   // 머리 줄 첫머리의 글자 입력은 시작을 바꾸지 않는다
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
        if kept != candidates { candidates = kept; controllers.forEach { $0.gutter?.needsDisplay = true } }
    }

    // MARK: 영역 스캔 (백그라운드)

    private func rescan() {
        guard FoldController.isEnabled, let doc = document else { return }
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
            Perf.measure("fold.apply candidates=\(found.count)") { self.apply(candidates: found) }
        }
    }

    /// 새 후보 적용 + 기존 접힘을 후보에 맞춰 보정 (머리 줄이 더 이상 영역을 거느리지 않으면 펼친다)
    private func apply(candidates found: [FoldCandidate]) {
        let before = candidates
        candidates = found
        if Perf.enabled { Perf.log("fold.scan candidates=\(found.count) folds=\(folds.map { "\($0.hiddenStart)..<\($0.hiddenEnd)" })") }
        if !folds.isEmpty, let ns = contentStorage?.textStorage?.mutableString {
            var kept: [FoldSpan] = []
            var changedFolds = false
            for f in folds {
                let headerStart = ns.paragraphRange(for: NSRange(location: max(0, min(f.hiddenStart - 1, ns.length)), length: 0)).location
                if let i = candidateIndex(headerStart: headerStart) {
                    let c = candidates[i]
                    let snapped = FoldSpan(hiddenStart: c.hiddenStart, hiddenEnd: c.hiddenEnd, lines: c.lines)
                    if snapped != f { changedFolds = true }
                    kept.append(snapped)
                } else {
                    if Perf.enabled { Perf.log("fold.scan drop fold \(f.hiddenStart)..<\(f.hiddenEnd) header@\(headerStart) — no candidate") }
                    changedFolds = true
                }
            }
            if changedFolds {
                var next: [FoldSpan] = []   // 정렬 + 같은 후보로 맞춰진 접힘은 하나로
                for f in kept.sorted(by: { $0.hiddenStart < $1.hiddenStart }) where next.last != f { next.append(f) }
                // 쓰고 있는 줄을 숨길 수 없어 접힘을 펴는 경우가 여기다 (구역 아래에 새로 쓴 줄 — sparingCarets): 쓰고 있는 편집기는 캐럿 줄을 지킨다.
                // 맨 위 줄을 지키면 입력 중인 줄이 펴진 구역의 높이만큼 내려간다 (실측: 60줄 구역 아래에서 치던 줄이 화면 아래 1,140 pt 로)
                commit(sparingCarets(next), by: focusedController, anchorOnCaret: true, adjustsSelection: false)
            }
        }
        if before != candidates { controllers.forEach { $0.gutter?.needsDisplay = true } }
        if !pendingRestore.isEmpty {
            let want = pendingRestore
            pendingRestore = []
            restoreFolds(want)
        }
    }

    /// 떠날 때 접혀 있던 영역 중 지금도 같은 자리에 같은 크기로 있는 것만 다시 접는다 (그 사이 파일이 밖에서 바뀌어 어긋난 것은 버린다)
    private func restoreFolds(_ want: [FoldSpan]) {
        guard folds.isEmpty else { return }
        let ends = Dictionary(candidates.map { ($0.hiddenStart, $0.hiddenEnd) }, uniquingKeysWith: { a, _ in a })
        let again = sparingCarets(want.filter { ends[$0.hiddenStart] == $0.hiddenEnd }.sorted { $0.hiddenStart < $1.hiddenStart })
        guard !again.isEmpty else { return }
        commit(again, by: nil, adjustsSelection: false)
        controllers.forEach { $0.onRestore?() }
    }

    // MARK: 내부

    private func rebuildMerged() {
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
        hider.hidden = out
        // 열거 delegate 는 접힘이 하나라도 있을 때만 단다 — 달려 있으면 요소 열거마다(문단마다) 불린다. 레이아웃 delegate(마지막 문단용)도 마찬가지다
        guard let cs = contentStorage else { return }
        if out.isEmpty {
            if cs.delegate === hider { cs.delegate = nil }
            (cs as? FoldingContentStorage)?.folds = nil
        } else {
            hider.contentStorage = cs
            hider.documentStart = cs.documentRange.location
            if cs.delegate !== hider { cs.delegate = hider }
            (cs as? FoldingContentStorage)?.folds = hider
        }
        controllers.forEach { $0.updateLayoutDelegate() }
    }

    /// 범위의 배치와 높이 어림을 버리게 한다 — 이 문서에 붙은 모든 레이아웃 매니저(분할의 두 편집기)에서. 다음 배치가 요소를 다시 열거하며 숨김을 다시 묻는다.
    /// 속성 편집 통지를 쓰는 까닭은 파일 머리말에 (문자열·undo·dirty 에는 영향 없음 — EditorView.invalidateHighlight 와 같은 경로)
    private func invalidateLayout(from start: Int, to end: Int) {
        guard let ts = contentStorage?.textStorage else { return }
        let len = ts.length
        let a = max(0, min(start, len)), b = max(a, min(end, len))
        guard b > a else { return }
        Perf.measure("fold.invalidate len=\(b - a)", threshold: 1) {
            ts.beginEditing()
            ts.edited(.editedAttributes, range: NSRange(location: a, length: b - a), changeInLength: 0)
            ts.endEditing()
        }
    }
}

// MARK: - 편집기 단위

/// 텍스트 뷰 하나의 접기: 명령·표식·거터 화살표·캐럿·보던 곳 지키기. 접힘 상태는 문서의 `FoldStore` 에 있다 — 분할 편집기는 편집기마다 따로 만든다
@MainActor
final class FoldController {
    /// 비상 스위치: `--no-fold` 로 실행하면 접기 명령은 아무 일도 하지 않고 비밀 줄 가림(레이아웃 delegate)도 없다
    static let isEnabled = !CommandLine.arguments.contains("--no-fold")

    weak var textView: HyperTextView?
    weak var gutter: GutterView?
    var log: ((String) -> Void)?
    /// 접힘 집합이 바뀜 (스크롤 마커 등이 다시 그린다)
    var onChange: (() -> Void)?

    // secrets: 비밀 블록 마스킹은 NSTextLayoutManagerDelegate 로 문단의 조각을 바꿔치기한다 (레이아웃 매니저의 delegate 는 하나) — SecretController 가 설치하는 훅.
    // 접혀서 숨은 문단은 열거되지 않으므로 묻지도 않는다 (열거에 남기는 마지막 문단만 접힘이 먼저다). 접힘이나 가릴 줄이 있을 때만 delegate 를 단다 (updateLayoutDelegate).
    /// 가릴 줄이 하나라도 있는가
    var hasMasks: (() -> Bool)?
    /// 문단 시작 오프셋이 가릴 줄이면 그 문단의 프래그먼트(MaskedLayoutFragment)를, 아니면 nil
    var maskedFragment: ((_ paragraphStart: Int, _ element: NSTextElement, _ range: NSTextRange?) -> NSTextLayoutFragment?)?
    /// 편집 통지 전달 (편집 전 좌표, textWillChange 와 같은 인자) — 비밀 범위 오프셋 추적용
    var onEdit: ((_ edits: [(NSRange, String)], _ alreadyApplied: Bool) -> Void)?

    /// 돌아온 탭의 접힘을 되살린 직후 — 화면보다 위가 접히면 글이 올라오므로 편집기가 보기 위치를 다시 맞춘다
    var onRestore: (() -> Void)?
    private var store: FoldStore?
    private let layoutDelegate = FoldLayoutDelegate()

    init(textView: HyperTextView, gutter: GutterView?, log: ((String) -> Void)? = nil) {
        self.textView = textView
        self.gutter = gutter
        self.log = log
        guard Self.isEnabled else { return }
        layoutDelegate.controller = self
        attachToStore()
        textView.onTextWillChange = { [weak self] edits, applied in self?.textWillChange(edits, alreadyApplied: applied) }
        textView.hasFolds = { [weak self] in self?.hasFolds ?? false }
        textView.tracksUndoEdits = { [weak self] in self?.store?.tracksEdits ?? false }
        textView.isOffsetHidden = { [weak self] o in self?.isOffsetHidden(o) ?? false }
        textView.foldedSpan = { [weak self] o in self?.hiddenSpan(containing: o) }
        textView.openFolds = { [weak self] offsets in self?.store?.unfoldAll(containingAnyOf: offsets, reason: String(localized: "caret"), by: self) }
        textView.foldPills = { [weak self] r in self?.store?.pills(in: r) ?? [] }
        textView.onFoldPillClick = { [weak self] hs in self?.store?.unfold(hiddenStart: hs, reason: nil, by: self) }
        gutter?.foldMarker = { [weak self] s, e in self?.store?.marker(paragraphStart: s, paragraphEnd: e) }
        gutter?.onFoldMarkerClick = { [weak self] s, e in self?.toggle(paragraphStart: s, paragraphEnd: e) }
    }

    /// 이 뷰의 콘텐츠 스토리지(분할 편집기와 공유)에 딸린 접힘 상태에 붙는다
    private func attachToStore() {
        if store == nil, let cs = textView?.textContentStorage { store = FoldStore.shared(for: cs) }
        store?.attach(self)
    }

    /// 편집기가 닫힐 때(분할 해제): 문서의 접힘 상태에서 빠진다 — 보관만 되는 코디네이터가 접힘 변경마다 일하지 않도록
    func unbind() {
        store?.detach(self)
    }

    /// 문서 연결. 같은 Coordinator 가 문서를 갈아끼우면 다시 부른다
    func bind(document doc: MemoDocument) {
        guard Self.isEnabled else { return }
        attachToStore()
        store?.bind(document: doc)
    }

    func apply(theme: Theme) {
        textView?.foldPillTextColor = theme.foregroundDim.nsColor
        textView?.foldPillFillColor = theme.backgroundElevated.nsColor
        textView?.needsDisplay = true
    }

    // MARK: 질의 (문서의 접힘 상태)

    var hasFolds: Bool { store?.hasFolds ?? false }
    var foldCount: Int { store?.folds.count ?? 0 }
    var regionCount: Int { store?.candidates.count ?? 0 }
    func isOffsetHidden(_ offset: Int) -> Bool { store?.isOffsetHidden(offset) ?? false }
    func hiddenSpan(containing offset: Int) -> NSRange? { store?.hiddenSpan(containing: offset) }
    func isLineHidden(_ line: Int) -> Bool { store?.isLineHidden(line) ?? false }
    var foldedHeaderLines: [Int] { store?.foldedHeaderLines ?? [] }

    // MARK: 명령

    func handle(_ cmd: EditorCommand) {
        guard Self.isEnabled, let tv = textView, let store else { return }
        let caret = tv.selectedRange().location
        if Perf.enabled { Perf.log("fold.command \(cmd) caret=\(caret) folds=\(store.folds.count) candidates=\(store.candidates.count)") }
        switch cmd {
        case .fold:
            // 캐럿 줄을 머리로 하거나 캐럿을 품은 가장 안쪽의 아직 안 접힌 영역
            let enclosing = store.candidates.filter { store.contains($0, caret) }
            guard let c = enclosing.reversed().first(where: { store.foldIndex(hiddenStart: $0.hiddenStart) == nil }) else {
                log?(String(localized: "Nothing to fold here")); return
            }
            store.fold(c, by: self)
        case .unfold:
            // 캐럿이 머리 줄에 있는 접힘 (숨은 줄에 캐럿이 있을 수는 없다 — 들어가는 순간 펼쳐진다)
            let ns = tv.string as NSString
            let para = ns.paragraphRange(for: NSRange(location: min(caret, ns.length), length: 0))
            if store.foldIndex(hiddenStart: NSMaxRange(para)) != nil {
                store.unfold(hiddenStart: NSMaxRange(para), reason: nil, by: self)
            } else if let span = store.hiddenSpan(containing: caret) {
                store.unfoldAll(containing: span.location, reason: nil, by: self)
            } else {
                log?(String(localized: "Nothing to unfold here"))
            }
        case .foldAll:
            store.foldAll(by: self)
        case .unfoldAll:
            store.unfoldEverything(by: self)
        case .toggleFold(let line):
            store.toggle(line: line, by: self)
        default:
            break
        }
    }

    /// 거터 화살표·`toggleFold(line:)`: 접혀 있으면 펼치고, 후보면 접는다
    func toggle(paragraphStart: Int, paragraphEnd: Int) {
        store?.toggle(paragraphStart: paragraphStart, paragraphEnd: paragraphEnd, by: self)
    }

    /// 선택이 바뀔 때 (Coordinator 가 부른다): 캐럿이 숨은 줄로 들어갔으면 그 접힘을 펼친다. 접힘을 통째로 가로지르는 선택(양 끝이 보이는 드래그·모두 선택)은
    /// 숨은 텍스트를 포함한 채 둔다. 선택의 한쪽 끝이 숨은 줄 안에 놓이면(접힌 머리 줄에서 ⇧↓·⇧→ 로 넓힐 때) 그 접힘을 펼친다 — 그대로 두면 키를 눌러도
    /// 화면에 변화가 없고, 보이지 않는 채로 늘어난 선택을 지우게 된다
    func selectionDidChange() {
        guard let store, store.hasFolds, let tv = textView else { return }
        // 열 블록의 행·추가 캐럿(⌥끌기, 열 모드의 ⇧↓, 모든 일치 선택, ⌘D)이 숨은 줄에 놓이면 그 접힘도 편다. 블록은 문자열의 줄을 세므로 접힘을 가로질러
        // 늘리면 숨은 줄마다 행이 생긴다 — 접힌 채 두면 다음 키가 화면에 없는 줄들을 고친다 (네이티브 선택에는 머리 캐럿만 있어 아래의 검사는 그것을 못 본다)
        // 그 범위들이 네이티브 선택과 맞을 때만 본다. 여러 캐럿의 편집 도중(저장소가 바뀐 직후 AppKit 이 선택을 고쳐 놓는 통지)에는 multi 가 아직 편집 전 오프셋이다 —
        // 접힘은 이미 편집 뒤 좌표라, 접힘 위의 글이 줄어들면 옛 오프셋이 숨김 구간에 들어 까닭 없이 펴진다 (실측: 머리 줄의 다섯 글자 일치와 머리 줄 끝의 캐럿에
        // 한 글자를 치자 그 접힘이 펴졌다). 맞지 않으면 아래에서 네이티브 선택을 본다 — 편집이 끝나면 새 범위로 다시 불린다
        if let multi = tv.multi, Self.matchesNativeSelection(multi, in: tv) {
            var offsets: [Int] = []
            for r in multi.ranges {
                offsets.append(r.location)
                let end = NSMaxRange(r)
                if r.length > 0, let span = store.hiddenSpan(containing: end), end > span.location, end < NSMaxRange(span) { offsets.append(end) }
            }
            store.unfoldAll(containingAnyOf: offsets, reason: String(localized: "caret"), by: self)
            return
        }
        let sel = tv.selectedRange()
        if sel.length == 0 {
            guard store.isOffsetHidden(sel.location) else { return }
            store.unfoldAll(containing: sel.location, reason: String(localized: "caret"), by: self)
            return
        }
        if store.isOffsetHidden(sel.location) { store.unfoldAll(containing: sel.location, reason: String(localized: "caret"), by: self) }
        // 끝 경계: 숨김 구간의 시작(머리 줄의 개행 바로 뒤)이나 끝에 딱 놓인 것은 보이는 글자만 고른 것이다 — 구간 안쪽일 때만 펼친다
        let end = NSMaxRange(sel)
        if let span = store.hiddenSpan(containing: end), end > span.location, end < NSMaxRange(span) { store.unfoldAll(containing: end, reason: String(localized: "caret"), by: self) }
    }

    /// 여러 캐럿·열 블록의 범위가 지금의 네이티브 선택과 같은 것인가 (HyperTextView.applyNativeSelection 이 넘기는 꼴: 길이 있는 범위들, 모두 길이 0 이면 머리 캐럿 하나)
    private static func matchesNativeSelection(_ multi: MultiSelection, in tv: HyperTextView) -> Bool {
        let native = tv.selectedRanges.map(\.rangeValue)
        let long = multi.ranges.filter { $0.length > 0 }
        guard !long.isEmpty else { return native.count == 1 && multi.ranges.contains(native[0]) }
        // 맞닿은 범위는 NSTextView 가 하나로 합쳐 돌려준다 — 양쪽을 같은 꼴로 만들어 견준다
        func merged(_ ranges: [NSRange]) -> [NSRange] {
            var out: [NSRange] = []
            for r in ranges.sorted(by: { $0.location < $1.location }) {
                if let last = out.last, r.location <= NSMaxRange(last) { out[out.count - 1] = NSUnionRange(last, r) } else { out.append(r) }
            }
            return out
        }
        return merged(native) == merged(long)
    }

    /// 점프(검색 매치·줄 이동·북마크·문서 끝)로 선택이 놓이기 전에 그 자리를 숨기는 접힘을 펼친다 — 길이 있는 선택(검색 매치)은 selectionDidChange 가 건드리지 않는다
    func reveal(range r: NSRange) {
        guard let store, store.hasFolds else { return }
        for o in Set([r.location, max(r.location, NSMaxRange(r) - 1)]) where store.isOffsetHidden(o) {
            store.unfoldAll(containing: o, reason: String(localized: "caret"), by: self)
        }
    }

    // MARK: 접힘이 바뀔 때 (FoldStore 가 이 문서를 보여 주는 편집기마다 부른다)

    /// 바뀌기 직전: 이 편집기가 보던 곳을 잡아 둔다 — 맨 위 줄, `anchorOnCaret` 이면 캐럿 줄이 보이고 있을 때 그 줄 (`onCaret`)
    /// `reading`: 캐럿 줄을 지키려는 변화(모두 접기·펴기)인데 화면이 따라갈 캐럿 — 여러 캐럿이면 문서 순서로 마지막인 머리 캐럿 — 이 그려 둔 화면 범위 밖에 있다:
    /// 사용자는 캐럿과 떨어진 곳을 읽고 있다. 그 범위를 모르면(줄바꿈 끔 등) false
    fileprivate func foldsWillChange(anchorOnCaret: Bool) -> (anchor: HyperTextView.ReadingAnchor?, onCaret: Bool, reading: Bool) {
        guard let tv = textView else { return (nil, false, false) }
        let anchor = tv.beginPreservingReadingPosition(preferCaret: anchorOnCaret)
        let sel = tv.selectedRange()
        let onCaret = anchorOnCaret && (anchor.map { !$0.pinnedToEnd && ($0.offset == sel.location || $0.offset == NSMaxRange(sel)) } ?? false)
        var reading = false
        if anchorOnCaret, let shown = tv.laidOutViewportRange() {
            var heads = [sel.location, NSMaxRange(sel)]
            if let multi = tv.multi, let first = multi.ranges.first, let last = multi.ranges.last { heads = multi.block != nil ? [first.location, last.location] : [last.location] }
            reading = !heads.contains { $0 >= shown.location && $0 <= NSMaxRange(shown) }
        }
        return (anchor, onCaret, reading)
    }

    /// 바뀐 직후: 보던 곳을 되돌린다. 지키던 줄이 접혀 사라졌으면 그 줄을 품은 머리 줄을 대신 둔다 (맨 위 줄이었으면 맨 위에, 캐럿 줄이었으면 캐럿이 있던 높이에).
    /// 그다음 숨겨진 캐럿·선택을 보이는 자리로 옮긴다 — 명령을 내린 편집기만 캐럿을 따라 스크롤한다 (다른 편집기는 보던 곳을 그대로 둔다)
    fileprivate func foldsDidChange(_ kept: (anchor: HyperTextView.ReadingAnchor?, onCaret: Bool, reading: Bool), isInitiator: Bool, adjustsSelection: Bool) {
        guard let tv = textView else { return }
        var anchor = kept.anchor
        if let a = anchor, let span = store?.hiddenSpan(containing: a.offset) {
            if kept.onCaret {
                anchor = .init(offset: store?.headerEnd(before: span.location) ?? max(0, span.location - 1), delta: a.delta, lineHeight: a.lineHeight, pinnedToEnd: false)
            } else {
                let header = tv.textStorage?.mutableString.paragraphRange(for: NSRange(location: max(0, span.location - 1), length: 0)).location ?? 0
                anchor = .init(offset: header, delta: 0, lineHeight: 0, pinnedToEnd: false)
            }
        }
        tv.endPreservingReadingPosition(anchor)
        // 모두 접기를 캐럿과 떨어진 곳을 읽다가 했으면(캐럿 줄이 화면 밖) 숨은 캐럿은 머리 줄로 옮기되 화면은 읽던 곳에 둔다 — 지킨 맨 위 줄을 캐럿 따라가기가 뒤집지 않게
        if adjustsSelection { moveCaretOutOfFolds(scrolls: isInitiator && !kept.reading) }
        changed()
    }

    /// 접은 뒤 캐럿이 숨겨졌으면 가장 바깥 머리 줄 끝으로 옮긴다 (Xcode 와 같음).
    /// 길이 있는 선택은 숨은 줄에 걸린 끝을 보이는 자리로 당긴다: 숨은 줄에서 시작하면 접힘 뒤 첫 보이는 줄 머리로, 숨은 줄 안에서 끝나면 머리 줄의 개행 뒤로.
    /// 그대로 두면 숨은 부분의 선택은 화면에 아무것도 남지 않은 채 다음 입력이 숨은 글자를 지운다. 당기고 나서 남는 것이 없으면(통째로 숨음) 캐럿처럼 머리 줄 끝으로
    /// 옮긴다. 접힘을 가로지르되 양 끝이 보이는 선택은 건드리지 않는다
    private func moveCaretOutOfFolds(scrolls: Bool) {
        guard let tv = textView, let store else { return }
        // 여러 캐럿·열 블록: 네이티브 선택(머리 캐럿)만 보면 나머지가 새 접힘 안에 남는다 — 그려지지 않는 채로 다음 키를 받아 숨은 줄을 고친다. 캐럿마다 같은 규칙으로
        // 옮긴다(숨은 캐럿은 머리 줄 끝으로, 겹치면 하나로; 보이는 캐럿은 그대로). 열 블록은 줄을 건너뛸 수 없으므로 행이 하나라도 숨으면 머리 캐럿 하나로 접는다.
        // 네이티브 선택을 먼저 건드리면 안 된다: 선택 통지가 올 때 multi 가 아직 옛 범위라 selectionDidChange 가 방금 접은 것을 도로 편다
        if let multi = tv.multi {
            let ns = tv.string as NSString
            let pulled = multi.ranges.map { outOfFolds($0, in: store) }
            guard pulled != multi.ranges else { return }
            var kept: [NSRange] = []
            let headMoved: Bool   // 머리 캐럿(네이티브 선택이 놓인 범위) 자신이 숨어서 옮겨졌는가
            if let block = multi.block {
                let head = NSRange(location: min(block.headOffset(in: ns), ns.length), length: 0)
                kept = [outOfFolds(head, in: store)]
                headMoved = kept[0] != head
            } else {
                headMoved = pulled.last != multi.ranges.last
                // 같은 자리로 모인 캐럿은 하나로. 머리 줄 끝으로 온 캐럿이 그 줄까지 당겨진 선택에 닿으면 캐럿을 버린다 — 겹친 범위를 한 번에 고치면 글이
                // 어긋난다 (performReplacements). 범위들은 서로 겹치지 않으므로 자리 순으로 놓고 이웃끼리만 견준다 (모든 일치를 고른 캐럿은 수천 개다)
                let sorted = pulled.sorted { $0.location != $1.location ? $0.location < $1.location : $0.length < $1.length }
                var reach = -1   // 지금까지 본 길이 있는 범위의 끝
                for (i, r) in sorted.enumerated() {
                    if r.length == 0 {
                        if r.location <= reach { continue }                                          // 앞의 선택 안이거나 그 끝에 닿았다
                        if i + 1 < sorted.count, sorted[i + 1].location == r.location { continue }   // 같은 자리에 캐럿이 더 있거나(마지막 것이 남는다) 거기서 시작하는 선택이 있다
                    } else {
                        if let last = kept.last, last == r { continue }
                        reach = max(reach, NSMaxRange(r))
                    }
                    kept.append(r)
                }
            }
            // 화면은 머리 캐럿이 옮겨졌을 때만, 명령을 내린 편집기에서만 그 캐럿을 따라간다. 머리 캐럿이 제자리면 — 화면 밖에 있더라도 — 보던 곳을 그대로 둔다:
            // 모든 일치를 고른 채(머리는 문서의 마지막 일치) 위쪽의 영역 하나를 접으면 화면이 마지막 일치로 가 버려 방금 접은 자리가 사라졌다
            let follows = scrolls && headMoved
            tv.setMulti(kept, reveal: follows)
            if follows, kept.count == 1, kept[0].length == 0 { scrollCaretIntoView(kept[0].location, retries: 3) }
            return
        }
        let sel = tv.selectedRange()
        var start = sel.location, end = NSMaxRange(sel)
        let startSpan = store.hiddenSpan(containing: start)
        if sel.length > 0 {
            if let s = startSpan { start = NSMaxRange(s) }
            if let e = store.hiddenSpan(containing: end), end > e.location, end < NSMaxRange(e) { end = e.location }
            if start < end {
                if start != sel.location || end != NSMaxRange(sel) { tv.setSelectedRange(NSRange(location: start, length: end - start)) }
                return
            }
        }
        guard let span = startSpan else { return }
        let target = store.headerEnd(before: span.location)
        tv.setSelectedRange(NSRange(location: target, length: 0))
        if scrolls { scrollCaretIntoView(target, retries: 3) }
    }

    /// 선택 하나를 접힘 밖으로: 숨은 캐럿은 가장 바깥 머리 줄 끝, 길이 있는 선택은 숨은 줄에 걸린 끝을 보이는 자리로 당긴다 (moveCaretOutOfFolds 의 규칙)
    private func outOfFolds(_ sel: NSRange, in store: FoldStore) -> NSRange {
        var start = sel.location, end = NSMaxRange(sel)
        let startSpan = store.hiddenSpan(containing: start)
        if sel.length > 0 {
            if let s = startSpan { start = NSMaxRange(s) }
            if let e = store.hiddenSpan(containing: end), end > e.location, end < NSMaxRange(e) { end = e.location }
            if start < end { return NSRange(location: start, length: end - start) }
        }
        guard let span = startSpan else { return sel }
        return NSRange(location: store.headerEnd(before: span.location), length: 0)
    }

    /// 접은 직후의 scrollRangeToVisible 은 배치가 끝나기 전의 좌표로 자리를 잡을 수 있다 → 배치가 돈 뒤 캐럿이 그대로 그 자리인데 안 보이면 다시 스크롤한다
    private func scrollCaretIntoView(_ target: Int, retries: Int) {
        guard let tv = textView else { return }
        tv.scrollRangeToVisible(NSRange(location: target, length: 0))
        guard retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak tv] in
            guard let self, let tv, tv.selectedRange() == NSRange(location: target, length: 0) else { return }   // 그 사이 캐럿이 옮겨졌으면 그만
            tv.layoutSubtreeIfNeeded()
            guard let r = tv.caretRect(at: target) else { return }
            let visible = tv.visibleRect
            if r.maxY < visible.minY || r.minY > visible.maxY { self.scrollCaretIntoView(target, retries: retries - 1) }
        }
    }

    /// 이 편집기를 다시 배치·다시 그리게 한다 (접힘이 바뀐 뒤)
    fileprivate func changed() {
        textView?.needsLayout = true
        textView?.needsDisplay = true
        gutter?.needsDisplay = true
        onChange?()
    }

    // MARK: 편집 추적

    private func textWillChange(_ edits: [(NSRange, String)], alreadyApplied: Bool) {
        onEdit?(edits, alreadyApplied)   // secrets: 비밀 범위는 편집기마다 따로 옮긴다
        store?.textWillChange(edits, alreadyApplied: alreadyApplied, from: self)
    }

    // MARK: 비밀 줄 가림 (secrets — 레이아웃 delegate)

    /// 레이아웃 delegate 는 접힘(문서의 마지막 문단을 높이 0 으로 숨긴다)이나 가릴 줄(secrets)이 하나라도 있을 때만 설치한다 — delegate 가 있으면 TextKit 이
    /// 키 입력마다 프래그먼트를 만드는 경로가 느려진다 (실측 약 1 ms/키). 접힘·마스크 집합이 비거나 생길 때 부른다 (FoldStore, SecretController)
    func updateLayoutDelegate() {
        guard Self.isEnabled, let lm = textView?.textLayoutManager else { return }
        let want: NSTextLayoutManagerDelegate? = (hasFolds || (hasMasks?() ?? false)) ? layoutDelegate : nil   // secrets
        if (lm.delegate as AnyObject?) !== (want as AnyObject?) { lm.delegate = want }
    }

    /// 범위의 레이아웃 프래그먼트를 다시 만들게 한다 — 가림 상태가 바뀐 문단에 SecretController 가 쓴다. 실측(macOS 27 TextKit 2): invalidateLayout(for:) 은
    /// 기존 프래그먼트 객체를 재사용해 레이아웃 delegate 를 다시 부르지 않으므로, 테마 적용과 같은 속성 편집 통지로 프래그먼트를 재생성한다
    /// (문자열·undo·dirty 에는 영향 없음)
    func invalidateLayout(from start: Int, to end: Int) {
        guard let tv = textView, let ts = tv.textStorage else { return }
        let len = ts.length
        let a = max(0, min(start, len)), b = max(a, min(end, len))
        guard b > a || len == 0 else { tv.needsDisplay = true; return }
        Perf.measure("secrets.invalidate len=\(b - a)", threshold: 1) {
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

/// 숨은 문단을 콘텐츠 열거에서 뺀다 → 레이아웃 매니저는 그 문단의 조각을 만들지도, 높이를 어림하지도 않는다.
/// 요소마다 불리는 뜨거운 경로다: 격리 없는 클래스에 정렬된 구간 배열만 두고 이분 탐색한다 (FoldLayoutDelegate 의 실측 참고). 접힘이 하나도 없으면 FoldStore 가
/// delegate 자체를 떼어 둔다. 값은 메인 스레드에서만 읽고 쓴다 (TextKit 2 의 열거는 메인 스레드에서 돈다)
final class FoldEnumerationDelegate: NSObject, NSTextContentStorageDelegate {
    /// 숨김 구간 (정렬, 겹침 없음)
    var hidden: [NSRange] = [] { didSet { tailLength = -1 } }
    weak var contentStorage: NSTextContentStorage?
    /// 문서의 첫 위치 — 요소마다 documentRange 를 새로 만들지 않으려고 적어 둔다 (NSTextContentStorage 의 위치는 문자 인덱스라 내용이 바뀌어도 같다)
    var documentStart: NSTextLocation?
    /// 0 보다 크면 FoldingContentStorage 가 열거를 직접 걸러 내는 중이다 — 여기서 또 거르지 않는다 (걸러 버리면 건너뛸 자리를 알 수 없다)
    var skippingDepth = 0
    /// 문서의 마지막 문단이 시작하는 오프셋 — 문서 길이가 `tailLength` 일 때 잰 값 (길이가 달라지면 다시 잰다. 끝까지 닿는 접힘이 있는 동안 그 뒤쪽은 편집될 수 없고,
    /// 접힘이 바뀌면 `hidden` 이 다시 놓이며 버려진다)
    private var tailStart = 0
    private var tailLength = -1
    /// 접힌 마지막 문단의 표시용 속성: 줄 높이 0.01 pt, 감기지 않게, 보이지 않게
    private static let collapsedAttributes: [NSAttributedString.Key: Any] = {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = 0.01
        style.maximumLineHeight = 0.01
        style.lineBreakMode = .byClipping
        return [.font: NSFont.systemFont(ofSize: 0.01), .paragraphStyle: style, .foregroundColor: NSColor.clear]
    }()

    /// 문단 시작 오프셋을 숨기는 구간. 숨지 않았으면, 그리고 숨었어도 열거에 남기는 문서의 마지막 문단이면 nil
    func span(hiding offset: Int) -> NSRange? {
        var lo = 0, hi = hidden.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let r = hidden[mid]
            if offset < r.location { hi = mid - 1 }
            else if offset >= NSMaxRange(r) { lo = mid + 1 }
            else {
                // 문서의 마지막 문단은 숨어 있어도 열거에 남긴다 — 빠지면 NSTextView 가 문서 높이를 구하지 못한다 (파일 머리말)
                if mid == hidden.count - 1, let tail = tailStart(of: r), offset >= tail { return nil }
                return r
            }
        }
        return nil
    }

    /// 구간이 문서 끝까지 닿으면 문서의 마지막 문단이 시작하는 오프셋 (아니면 nil)
    func tailStart(of span: NSRange) -> Int? {
        guard let ts = contentStorage?.textStorage else { return nil }
        let length = ts.length
        guard length > 0, NSMaxRange(span) >= length else { return nil }
        if tailLength != length {
            tailLength = length
            tailStart = ts.mutableString.paragraphRange(for: NSRange(location: length - 1, length: 0)).location
        }
        return tailStart
    }

    func textContentManager(_ textContentManager: NSTextContentManager, shouldEnumerate textElement: NSTextElement, options: NSTextContentManager.EnumerationOptions = []) -> Bool {
        guard skippingDepth == 0, !hidden.isEmpty, let location = textElement.elementRange?.location else { return true }
        return span(hiding: textContentManager.offset(from: documentStart ?? textContentManager.documentRange.location, to: location)) == nil
    }

    /// 문서의 마지막 문단이 접혀 있으면 높이가 없는 표시용 문단을 돌려준다 (저장소의 글자·속성은 그대로다). 글자 수는 같게 두되 끝의 개행은 공백으로 바꾼다 —
    /// 개행으로 끝나는 문서는 마지막 문단 조각에 빈 덧줄(보통 줄 높이)이 붙는다. 접힘이 바뀌면 그 범위의 속성 편집 통지가 문단 요소를 다시 만들게 한다
    func textContentStorage(_ textContentStorage: NSTextContentStorage, textParagraphWith range: NSRange) -> NSTextParagraph? {
        guard let last = hidden.last, range.length > 0, range.location >= last.location, let ts = textContentStorage.textStorage else { return nil }
        let length = ts.length
        guard NSMaxRange(range) == length, NSMaxRange(last) >= length else { return nil }
        let text = NSMutableAttributedString(string: ts.mutableString.substring(with: range), attributes: Self.collapsedAttributes)
        var contentsEnd = 0
        (text.string as NSString).getParagraphStart(nil, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: 0, length: 0))
        if contentsEnd < text.length {
            text.replaceCharacters(in: NSRange(location: contentsEnd, length: text.length - contentsEnd), with: String(repeating: " ", count: text.length - contentsEnd))
        }
        return NSTextParagraph(attributedString: text)
    }
}

/// 접힌 구간을 건너뛰며 문단 요소를 열거하는 콘텐츠 스토리지 — 문서마다 하나 (EditorSession 이 만든다).
/// 숨김 자체는 열거 delegate(`shouldEnumerate`)만으로 된다. 그런데 NSTextContentStorage 는 delegate 에 물으려고 숨은 문단마다 요소를 만들어 캐시에 넣는다:
/// 접힌 1.3 MB 메모(25,000줄이 숨음)에서는 그 장부 정리가 배치 패스 시간의 대부분이었다 (sample: `__NSTextContentStorageFlushUncachedTextElements` →
/// `_NSBlockNumberForIndex`; 휠 한 걸음 18 ms, 글자 크기 변경 600 ms). 여기서는 숨은 문단을 만나는 순간 열거를 멈추고 그 구간의 끝에서 다시 시작한다 —
/// 숨은 문단은 만들어지지도 않는다 (창 없는 실험: 29,990줄 접힘에 걸친 뷰포트 배치 8 ms → 0.13 ms).
/// 레이아웃 매니저가 이 공개 메서드를 거치지 않는 경로가 있더라도 delegate 가 같은 답을 하므로 숨김은 유지된다
final class FoldingContentStorage: NSTextContentStorage {
    /// 접힘이 있을 때 FoldStore 가 건다 (없으면 nil — 아래의 재정의는 곧장 super 로 간다)
    weak var folds: FoldEnumerationDelegate?

    override func enumerateTextElements(from textLocation: NSTextLocation?, options: NSTextContentManager.EnumerationOptions = [], using block: (NSTextElement) -> Bool) -> NSTextLocation? {
        guard let folds, !folds.hidden.isEmpty else { return super.enumerateTextElements(from: textLocation, options: options, using: block) }
        let reverse = options.contains(.reverse)
        let start = folds.documentStart ?? documentRange.location
        var location = textLocation
        var edge: NSTextLocation?
        var restarts = 0
        var lastResume = -1, delivered = false, steppedBack = false
        while true {
            var resume: Int?    // 숨은 구간을 만났다 — 이 오프셋에서 다시 시작한다
            delivered = false
            folds.skippingDepth += 1
            let reached = super.enumerateTextElements(from: location, options: options) { element in
                if let first = element.elementRange?.location, let span = folds.span(hiding: self.offset(from: start, to: first)) {
                    // 끝까지 닿는 구간을 앞으로 건너뛸 때는 열거에 남기는 마지막 문단 앞에서 멈춘다
                    resume = reverse ? span.location : (folds.tailStart(of: span) ?? NSMaxRange(span))
                    return false
                }
                delivered = true
                // 부른 쪽의 블록이 도는 동안은 delegate 가 다시 숨김을 답한다 — 그 안에서 이 재정의를 거치지 않는 열거가 시작돼도 숨은 문단이 나오지 않게
                folds.skippingDepth -= 1
                defer { folds.skippingDepth += 1 }
                return block(element)
            }
            folds.skippingDepth -= 1
            if let reached { edge = reached }
            guard var offset = resume else { break }                                   // 부른 쪽이 멈췄거나 문서의 끝·처음에 닿았다
            // 진전이 없으면(요소를 하나도 넘기지 못한 채 같은 구간에서 다시 멈췄다) 그 구간의 바깥 문단 안에서 한 번 더 시작해 보고, 그래도 안 되면 그만둔다.
            // 뒤로 열거할 때 "문단이 시작하는 자리에서 시작하면 그 앞 문단부터"(실측) 라는 성질에 기대고 있다 — 그것이 달라져도 위쪽 배치가 말없이 끊기지 않게
            if offset == lastResume, !delivered {
                guard reverse, offset > 0, !steppedBack else { break }
                steppedBack = true
                offset -= 1
            } else { steppedBack = false }
            lastResume = resume ?? -1
            restarts += 1
            guard restarts <= 2 * folds.hidden.count + 2, let next = self.location(start, offsetBy: offset) else { break }
            location = next
        }
        return edge
    }
}

/// 열거에 남긴 숨은 문단(문서의 마지막 문단): 높이 0 이라 답하고 아무것도 그리지 않는다
final class FoldedLayoutFragment: NSTextLayoutFragment {
    override var layoutFragmentFrame: CGRect {
        var f = super.layoutFragmentFrame
        f.size.height = 0
        return f
    }
    override var renderingSurfaceBounds: CGRect { .zero }
    override func draw(at point: CGPoint, in context: CGContext) {}
}

/// 문단마다 "숨길까"(열거에 남긴 마지막 문단), 아니면 "가릴까"(secrets) 를 묻는다 (NSTextView 는 기본 delegate 를 두지 않는다 — 실측).
/// 접힘이나 가릴 줄이 있을 때만 설치된다
final class FoldLayoutDelegate: NSObject, NSTextLayoutManagerDelegate {
    weak var controller: FoldController?

    // 문단마다 불리는 뜨거운 경로 — @MainActor 클래스 + @preconcurrency 적합으로 바꿨더니 호출마다 격리 검사가 들어가 큰 편집(24,000줄 주석 해제)이 4배 느려졌다(셀프테스트 실측).
    // 그래서 비격리 클래스 + assumeIsolated 를 유지한다 (NSTextLayoutFragment Sendable 경고는 Swift 5 모드에서 무해).
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

/// `⋯ N lines` 표식의 글과 크기. 모두 접은 화면에서는 표식 수십 개가 스크롤 걸음마다 다시 그려진다 — 걸음마다 현지화 문자열을 만들고 크기를 재는 대신
/// 줄 수·글꼴 크기별로 적어 둔다 (실측: 표식 16개인 화면에서 표식 그리기가 걸음당 약 3 ms)
@MainActor
private enum FoldPillLabels {
    private struct Key: Hashable { let lines: Int; let pointSize: CGFloat }
    private static var cache: [Key: (NSString, NSSize)] = [:]

    static func label(lines: Int, font: NSFont) -> (NSString, NSSize) {
        let key = Key(lines: lines, pointSize: font.pointSize)
        if let hit = cache[key] { return hit }
        if cache.count > 2_000 { cache.removeAll(keepingCapacity: true) }
        let label = String(localized: "⋯ \(lines) lines") as NSString
        let made = (label, label.size(withAttributes: [.font: font]))
        cache[key] = made
        return made
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
        // 그려 둔 뷰포트 범위를 쓴다 — 점 질의는 전체 무효화(모두 접기·펴기) 직후 조각 프레임을 옮길 수 있다 (HyperTextView.coveringViewport 주석). 그것을 쓸 수 없을 때만 점 질의로
        let laidOut = laidOutViewportRange()
        let start = laidOut?.location ?? fragment(atY: visible.minY).map { cs.offset(from: cs.documentRange.location, to: $0.rangeInElement.location) } ?? 0
        let end = laidOut.map { NSMaxRange($0) } ?? fragment(atY: visible.maxY).map { cs.offset(from: cs.documentRange.location, to: $0.rangeInElement.endLocation) } ?? length
        guard end >= start else { return }
        let pills = provider(NSRange(location: start, length: end - start))
        guard !pills.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: max(9, ((typingAttributes[.font] as? NSFont)?.pointSize ?? 13) - 3), weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: foldPillTextColor]
        for p in pills {
            guard let r = caretRect(at: p.headerEnd) else { continue }
            let (label, size) = FoldPillLabels.label(lines: p.lines, font: font)
            let h = min(r.height - 2, size.height + 4)
            let rect = NSRect(x: r.maxX + 8, y: r.midY - h / 2, width: size.width + 12, height: h)
            let path = NSBezierPath(roundedRect: rect, xRadius: h / 2, yRadius: h / 2)
            foldPillFillColor.setFill(); path.fill()
            foldPillTextColor.withAlphaComponent(0.5).setStroke(); path.lineWidth = 1; path.stroke()
            label.draw(at: NSPoint(x: rect.minX + 6, y: rect.midY - size.height / 2), withAttributes: attrs)
            foldPillRects.append((rect, p.hiddenStart))
        }
    }

    /// 캐럿을 한 걸음 옮기는 키 **앞**에 부른다 (doCommand). 그 걸음이 다 편 문서에서 닿을 글자 가운데 숨은 것이 있으면 그 접힘을 먼저 편다 — 그러면 AppKit 이
    /// 숨은 줄이 있는 배치에서 걸음을 계산한다(편 문서에서 같은 키를 누른 것과 같은 자리, 선택의 방향도 그대로).
    /// AppKit 의 걸음은 배치(열거된 문단)를 따라간다. 숨은 문단은 열거에 없으므로 단어 걸음은 닫힌 접힘을 통째로 넘는다 — 실측: 접힌 머리 줄 `def third(z):` 의
    /// z 뒤에서 ⇧⌥→ 가 접힘 아래 줄의 첫 낱말까지 고르고(접힘은 닫힌 채), 이어진 ⌫ 가 숨은 두 줄을 지웠다. 걸음 뒤에 바로잡는 stepIntoFold 는 바로 이웃한
    /// 글자(±1)만 보므로 그것을 못 본다. 걸음이 닿을 범위는 문자열에서 구한다(배치에 묻지 않는다): 글자 ±1, 낱말의 끝·머리, 줄·문단의 끝·머리, ⇧↑/⇧↓ 는 이웃 문단.
    /// 머리 줄의 개행까지만 닿는 걸음(머리 줄 끝의 ⇧→)은 숨은 글자에 닿지 않으므로 펴지 않는다 — 그 선택은 접힌 채 둔다 (FoldController.selectionDidChange 의 경계 규칙)
    func openFoldsInReach(of selector: Selector) {
        guard let hidden = isOffsetHidden, let span = foldedSpan, let open = openFolds else { return }
        let name = NSStringFromSelector(selector)
        let ns = string as NSString
        let sel = selectedRange()
        guard NSMaxRange(sel) <= ns.length else { return }
        let extending = name.hasSuffix("AndModifySelection:")
        let namedForward = ["moveDown", "moveRight", "moveForward", "moveWordRight", "moveWordForward", "moveParagraphForward", "moveToEndOf", "moveToRightEndOfLine"].contains { name.hasPrefix($0) }
        // ←/→ 로 이름 붙은 명령은 화면에서의 방향이다 — 오른쪽→왼쪽 문단에서는 "왼쪽"이 글의 뒤쪽으로 나아가는 쪽이다
        let visual = ["moveLeft", "moveRight", "moveWordLeft", "moveWordRight", "moveToLeftEndOfLine", "moveToRightEndOfLine"].contains { name.hasPrefix($0) }
        enum Step { case character, word, line, lineEnd, paragraph }
        let step: Step = name.hasPrefix("moveWord") ? .word : name.hasPrefix("moveParagraph") ? .paragraph : name.hasPrefix("moveTo") ? .lineEnd
            : (name.hasPrefix("moveUp") || name.hasPrefix("moveDown")) ? .line : .character
        // 걸음이 시작하는 끝. 선택을 늘리는 중이면 직전 걸음이 옮긴 끝(머리)이다 — 그것을 모르면(끌어서 고른 선택 등) 두 끝 모두 본다: 한쪽만 보다가 틀리면
        // 닫힌 접힘을 넘는 걸음을 놓친다. 선택이 있을 때의 ←/→ 는 선택을 접을 뿐이다
        let origins: [Int]
        if sel.length == 0 { origins = [sel.location] }
        else if extending {
            if let known = caretStepHead, known.selection == sel { origins = [known.head] } else { origins = [sel.location, NSMaxRange(sel)] }
        }
        else if step == .character { return }
        else { origins = [namedForward ? NSMaxRange(sel) : sel.location] }
        func paragraph(_ o: Int) -> NSRange { ns.paragraphRange(for: NSRange(location: min(o, ns.length), length: 0)) }
        func contentsEnd(_ p: NSRange) -> Int {
            var end = NSMaxRange(p)
            if p.length > 0, ns.character(at: end - 1) == 10 { end -= 1 }
            if end > p.location, ns.character(at: end - 1) == 13 { end -= 1 }
            return end
        }
        var found: [Int] = []
        /// [a, b) 에 든 숨은 글자를 적는다. `landing`: 선택 없이 옮겨 가는 캐럿이 놓일 자리 — 숨은 자리면 그것도.
        /// 선택을 늘리는 걸음은 그 사이의 글자를 모두 고르게 되므로 지나는 숨은 문단을 **전부** 적는다: 겹쳐 접힌 영역에서 합쳐진 구간의 첫 문단만 적으면 그것을
        /// 숨기는 바깥 접힘만 펴지고, 걸음이 닿는 더 깊은 줄을 숨기는 안쪽 접힘은 닫힌 채 남는다 (실측: 모두 접은 JSON 의 `[` 끝에서 ⇧⌥→ 가 안쪽 `{` 의 접힘들을
        /// 닫힌 채 넘어 문서 끝까지 골랐다). 선택 없는 걸음은 지나친 접힘을 닫힌 채 두고 놓일 자리만 본다 — 구간마다 첫 문단 하나면 된다
        func scan(_ a: Int, _ b: Int, landing: Int? = nil) {
            if b > a {
                if hidden(a) { found.append(a) }
                var p = NSMaxRange(paragraph(a)), n = 0
                while p < b, p < ns.length, n < 4_096 {   // 숨김 구간은 문단 머리에서 시작한다. 낱말 걸음이 닿는 범위는 4,096 자까지라 문단도 그만큼이 끝이다
                    if hidden(p) {
                        found.append(p)
                        if !extending, let s = span(p) { p = max(NSMaxRange(s), p + 1); n += 1; continue }
                    }
                    p = NSMaxRange(paragraph(p)); n += 1
                }
            }
            if let landing, !extending, hidden(landing) { found.append(landing) }
        }
        for o in origins {
            // 화면 방향 명령: 문단이 오른쪽→왼쪽이면 뒤집고, 두 방향의 글자가 섞인 문단에서는 캐럿이 놓인 조각에 따라 달라지므로 두 방향 모두 본다
            var directions = [namedForward]
            if visual {
                let d = writingDirections(ofParagraphAt: o)
                directions = d.mixed ? [true, false] : [d.rightToLeft ? !namedForward : namedForward]
            }
            for forward in directions {
                switch step {
                case .character:
                    if forward { let next = min(Self.offset(after: o, in: ns), ns.length); scan(o, next, landing: next) } else if o > 0 { scan(Self.offset(before: o, in: ns), o) }
                case .word:
                    // AppKit 처럼: 앞으로는 다음 낱말의 끝, 뒤로는 앞 낱말의 머리 (낱말 안이면 그 낱말의). 가까이에 낱말이 없으면 살핀 데까지
                    let limit = 4_096
                    if forward {
                        var end = min(ns.length, o + limit)
                        ns.enumerateSubstrings(in: NSRange(location: o, length: end - o), options: [.byWords, .substringNotRequired]) { _, r, _, stop in end = NSMaxRange(r); stop.pointee = true }
                        scan(o, end, landing: end)
                    } else {
                        var start = max(0, o - limit)
                        ns.enumerateSubstrings(in: NSRange(location: start, length: o - start), options: [.byWords, .reverse, .substringNotRequired]) { _, r, _, stop in start = r.location; stop.pointee = true }
                        scan(start, o)
                    }
                case .lineEnd:
                    let p = paragraph(o)
                    if forward { scan(o, contentsEnd(p)) } else { scan(p.location, o) }
                case .paragraph:
                    let p = paragraph(o)
                    if forward {
                        if o < contentsEnd(p) { scan(o, contentsEnd(p)) } else if NSMaxRange(p) < ns.length { scan(o, contentsEnd(paragraph(NSMaxRange(p)))) }
                    } else if o > p.location { scan(p.location, o) } else if p.location > 0 { scan(paragraph(p.location - 1).location, o) }
                case .line:
                    // 선택 없는 ↑/↓ 는 접힘을 건너뛴다 (moveAcrossFold — 여기까지 오지 않는다). 선택의 끝이 숨은 자리에 놓여 있을 때만 편다 (AppKit 이 거기서 줄을 세지 못한다)
                    guard extending else { if hidden(o) { found.append(o) }; continue }
                    // ⇧↑/⇧↓: 이웃 줄의 같은 열까지. 감긴 문단의 가운데 화면 줄에서는 같은 문단 안에서 움직인다. 열 0 에서의 ⇧↓ 는 머리 줄만 고른다(다음 줄의 머리까지) — 펴지 않는다
                    let p = paragraph(o)
                    let here = screenLine(at: o)
                    let column = o - (here?.range.location ?? p.location)
                    if forward {
                        if let here, here.index < here.count - 1 { continue }
                        guard NSMaxRange(p) < ns.length else { if hidden(o) { found.append(o) }; continue }
                        let next = paragraph(NSMaxRange(p))
                        scan(o, next.location + min(column, contentsEnd(next) - next.location))
                    } else {
                        if let here, here.index > 0 { continue }
                        guard p.location > 0 else { continue }
                        let previous = paragraph(p.location - 1)
                        scan(previous.location + min(column, contentsEnd(previous) - previous.location), o)
                    }
                }
            }
        }
        if !found.isEmpty { open(found) }
    }

    /// 그 오프셋이 든 문단의 쓰기 방향: 문단 스타일이 정해 두었으면 그것, 아니면 첫 강한 방향 글자 (유니코드 양방향 알고리즘의 문단 방향 규칙 — TextKit 의 '자연' 방향).
    /// `mixed`: 두 방향의 글자가 섞여 있다. 문단의 앞 2,000 자까지만 본다. ←/→ 키마다 불리므로 왼쪽→오른쪽 문단에서는 첫 글자를 찾은 뒤로 구역 비교만 한다
    func writingDirections(ofParagraphAt offset: Int) -> (rightToLeft: Bool, mixed: Bool) {
        let ns = string as NSString
        let p = ns.paragraphRange(for: NSRange(location: min(offset, ns.length), length: 0))
        let end = min(NSMaxRange(p), p.location + 2_000)
        var first: Bool?, sawLeft = false, sawRight = false
        var i = p.location
        while i < end, !(sawLeft && sawRight) {
            let c = ns.character(at: i)
            i += 1
            // 히브리·아랍 계열과 그 표현형, 보조 평면의 오른쪽→왼쪽 구역(앞쪽 대리 문자로 가린다). 그 구역의 숫자(아랍-인도 숫자)는 강한 방향이 아니다
            let right = (0x0590...0x08FF).contains(c) || (0xFB1D...0xFDFF).contains(c) || (0xFE70...0xFEFF).contains(c) || (0xD802...0xD803).contains(c) || (0xD83A...0xD83B).contains(c)
            if right {
                if (0x0660...0x0669).contains(c) || (0x06F0...0x06F9).contains(c) { continue }
                if first == nil { first = true }
                sawRight = true
            } else if !sawLeft, c >= 0x41 {   // 왼쪽→오른쪽 글자를 아직 못 봤을 때만 글자인지 따진다
                let letter: Bool
                if c < 0x80 { letter = (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) }
                else if UTF16.isLeadSurrogate(c) || UTF16.isTrailSurrogate(c) { letter = false }
                else { letter = Unicode.Scalar(UInt32(c))?.properties.isAlphabetic ?? false }
                if letter { if first == nil { first = false }; sawLeft = true }
            }
        }
        var rightToLeft = first ?? false
        if p.length > 0, let style = textStorage?.attribute(.paragraphStyle, at: p.location, effectiveRange: nil) as? NSParagraphStyle, style.baseWritingDirection != .natural {
            rightToLeft = style.baseWritingDirection == .rightToLeft
        }
        return (rightToLeft, sawLeft && sawRight)
    }

    /// 캐럿 걸음 뒤에 부른다 (doCommand): 선택을 늘리는 걸음이 옮긴 끝(머리)을 적어 둔다. 걸음 전후에 그대로인 끝이 닻이고 다른 쪽 끝이 머리다 —
    /// 걸음 전의 머리를 알고 있으면 닻은 그 반대쪽 끝 하나다 (닻을 넘어 뒤집힌 선택도 가른다). 가를 수 없으면 적지 않는다 (다음 걸음은 두 끝 모두 본다).
    /// `stepped`: AppKit 이 그 걸음으로 놓은 선택 — 그 뒤에 이쪽에서 선택을 다시 놓았으면(stepIntoFold) AppKit 이 아는 머리와 다를 수 있으므로 적지 않는다
    func rememberCaretStepHead(from before: NSRange, stepped: NSRange) {
        let after = selectedRange()
        guard after.length > 0, after == stepped else { caretStepHead = nil; return }
        let known = caretStepHead.flatMap { $0.selection == before ? $0.head : nil }
        if after == before {   // 움직이지 않았다 — 알던 머리는 그대로다
            caretStepHead = known.map { (selection: after, head: $0) }
            return
        }
        let anchors: [Int] = before.length == 0 ? [before.location]
            : known.map { [$0 == before.location ? NSMaxRange(before) : before.location] } ?? [before.location, NSMaxRange(before)]
        let startStays = anchors.contains(after.location), endStays = anchors.contains(NSMaxRange(after))
        if startStays != endStays { caretStepHead = (selection: after, head: startStays ? NSMaxRange(after) : after.location) } else { caretStepHead = nil }
    }

    /// 글자 한 걸음 뒤·앞의 오프셋. \r\n 은 한 걸음이다 — 그 사이는 캐럿이 놓일 자리가 아니다 (AppKit 의 ←/→ 도 그렇게 간다)
    static func offset(after o: Int, in ns: NSString) -> Int {
        o >= 0 && o + 1 < ns.length && ns.character(at: o) == 13 && ns.character(at: o + 1) == 10 ? o + 2 : o + 1
    }
    static func offset(before o: Int, in ns: NSString) -> Int {
        o >= 2 && o <= ns.length && ns.character(at: o - 1) == 10 && ns.character(at: o - 2) == 13 ? o - 2 : o - 1
    }

    /// 오프셋이 놓인 화면 줄(자동 줄바꿈으로 감긴 줄)의 문서 범위와, 그 문단의 몇째 화면 줄인지. 배치를 알 수 없으면(숨은 문단, 거대 문단) nil
    func screenLine(at offset: Int, caretAffinity: Bool = true) -> (range: NSRange, index: Int, count: Int)? {
        guard !isInHugeParagraph(offset), let lm = textLayoutManager, let cs = textContentStorage,
              let loc = cs.location(cs.documentRange.location, offsetBy: min(offset, textStorage?.length ?? 0)),
              let fragment = lm.textLayoutFragment(for: loc) else { return nil }
        let lines = fragment.textLineFragments
        guard let lastLine = lines.last else { return nil }
        let start = cs.offset(from: cs.documentRange.location, to: fragment.rangeInElement.location)
        let local = offset - start
        guard var index = lines.firstIndex(where: { NSLocationInRange(local, $0.characterRange) }) ?? (local >= NSMaxRange(lastLine.characterRange) ? lines.count - 1 : nil) else { return nil }
        // 감긴 자리의 캐럿은 앞줄 끝에 그려질 수 있다 (줄 끝으로 가는 키 뒤 — affinity)
        if caretAffinity, index > 0, local == lines[index].characterRange.location, selectedRange().length == 0, selectionAffinity == .upstream { index -= 1 }
        let r = lines[index].characterRange
        return (NSRange(location: start + r.location, length: r.length), index, lines.count)
    }

    /// 캐럿(선택을 늘리는 중이면 움직인 쪽 끝)을 한 걸음 옮기는 키 뒤에 부른다 (doCommand). 숨은 문단은 배치에 없어서 AppKit 의 이동은 접힌 구간을 통째로
    /// 건너뛴다 — ← 는 접힘 아래 줄 머리에서 머리 줄 끝으로, ⇧↓ 는 머리 줄에서 접힘 다음 줄로 간다(접힌 내용이 보이지 않는 채 선택에 들어간다).
    /// 논리적으로 이웃한 자리(가로 이동은 앞·뒤 글자, ⇧↑/⇧↓ 는 앞·뒤 줄의 같은 열)가 숨어 있는데 AppKit 이 그것을 건너뛰었으면 그 자리에 놓는다 — 그러면 선택 변경
    /// 감시가 그 접힘을 펼친다 (FoldController.selectionDidChange; 선택의 끝이 숨김 구간의 시작에 딱 놓인 것은 접힌 채 둔다).
    /// 선택 없는 ↑/↓ 는 doCommand 가 먼저 가로채 접힘을 건너뛴다 (moveAcrossFold)
    func stepIntoFold(after selector: Selector, from before: NSRange) {
        guard let hidden = isOffsetHidden, let span = foldedSpan else { return }
        let after = selectedRange()
        let name = NSStringFromSelector(selector)
        let extending = name.hasSuffix("AndModifySelection:")
        if !extending, before.length > 0 { return }   // 선택이 있을 때의 이동은 선택을 접을 뿐이다
        let namedForward = ["moveDown", "moveRight", "moveForward", "moveWordRight", "moveWordForward", "moveParagraphForward", "moveToEndOf", "moveToRightEndOfLine"].contains { name.hasPrefix($0) }
        // 움직인 끝(head)과 그 전 자리(prevHead), 그대로인 끝(anchor)
        let prevHead: Int, head: Int, anchor: Int
        if after == before {            // 움직이지 못했다 (숨은 자리에 놓인 끝은 AppKit 이 옮기지 못할 수 있다)
            // 줄·문단의 끝이나 머리로 가는 명령(⌘→ ⌘← ⌃E ⌃A 와 ⇧ 변형)이 제자리면 캐럿이 이미 거기 있는 것이다 — 이웃한 자리로 한 걸음 가는 명령이 아니므로
            // 접힘 안으로 들여놓지 않는다. 들여놓으면 접힌 머리 줄 끝에서 ⌘→ 를 한 번 더 누른 것만으로 접힘이 펴지고 캐럿이 첫 숨은 줄 머리로 간다
            if name.hasPrefix("moveTo") || name.hasPrefix("moveParagraph") { return }
            prevHead = namedForward ? NSMaxRange(before) : before.location
            head = prevHead
            anchor = namedForward ? before.location : NSMaxRange(before)
        } else if !extending {
            guard after.length == 0 else { return }
            head = after.location; anchor = head
            prevHead = head <= before.location ? before.location : NSMaxRange(before)
        } else if NSMaxRange(after) == NSMaxRange(before) {
            prevHead = before.location; head = after.location; anchor = NSMaxRange(before)
        } else if after.location == before.location {
            prevHead = NSMaxRange(before); head = NSMaxRange(after); anchor = before.location
        } else { return }               // 닻을 넘어 뒤집힌 선택
        let forward = head != prevHead ? head > prevHead : namedForward
        let ns = string as NSString
        guard prevHead <= ns.length else { return }
        // 논리적으로 이웃한 자리
        let target: Int, probe: Int
        if name.hasPrefix("moveUp") || name.hasPrefix("moveDown") {
            let cur = ns.lineRange(for: NSRange(location: prevHead, length: 0))
            let line: NSRange
            if forward {
                guard NSMaxRange(cur) < ns.length else { return }
                line = ns.lineRange(for: NSRange(location: NSMaxRange(cur), length: 0))
            } else {
                guard cur.location > 0 else { return }
                line = ns.lineRange(for: NSRange(location: cur.location - 1, length: 0))
            }
            var content = line.length
            if content > 0, ns.character(at: NSMaxRange(line) - 1) == 10 { content -= 1 }
            if content > 0, ns.character(at: line.location + content - 1) == 13 { content -= 1 }   // \r\n 으로 끝나는 줄: \r 앞까지가 내용이다
            probe = line.location
            target = line.location + min(prevHead - cur.location, content)
        } else {
            target = forward ? Self.offset(after: prevHead, in: ns) : Self.offset(before: prevHead, in: ns)
            probe = target
        }
        guard probe >= 0, probe <= ns.length, hidden(probe), let s = span(probe) else { return }
        // AppKit 이 그 구간을 건너뛰었거나 움직이지 못한 때만 — 구간 안에 이미 놓았거나(→ 는 내용 순서로 간다) 같은 문단 안에서 옮긴 것(감긴 줄)은 그대로 둔다
        guard head == prevHead || (forward ? head >= NSMaxRange(s) : head < s.location) else { return }
        setSelectedRange(extending ? NSRange(location: min(anchor, target), length: abs(anchor - target)) : NSRange(location: target, length: 0))
        scrollRangeToVisible(NSRange(location: target, length: 0))
    }

    /// ↑/↓: 목적지 줄이 숨겨져 있으면 접힌 구간을 건너뛴다. 처리했으면 true
    func moveAcrossFold(down: Bool) -> Bool {
        guard let hidden = isOffsetHidden, let span = foldedSpan, selectedRange().length == 0 else { return false }
        let ns = string as NSString
        let caret = min(selectedRange().location, ns.length)
        let cur = ns.lineRange(for: NSRange(location: caret, length: 0))
        // 자동 줄바꿈으로 감긴 문단의 가운데 화면 줄에서는 같은 문단 안에서 움직인다 — AppKit 에 맡긴다. 접힘은 문단의 마지막(↓)·첫(↑) 화면 줄에서만 건너뛴다
        // (문자열의 줄로만 보면 감긴 접힌 머리 줄의 첫 화면 줄에서 ↓ 한 번에 접힘 아래로 간다 — 머리 줄의 나머지 화면 줄에는 키보드로 갈 수 없었다)
        // 이웃 줄이 숨어 있는지부터 문자열로 본다 — 접힘과 상관없는 ↑/↓ 는 배치에 묻지 않고 여기서 끝난다
        if down { guard NSMaxRange(cur) < ns.length, hidden(NSMaxRange(cur)) else { return false } }
        else { guard cur.location > 0, hidden(ns.lineRange(for: NSRange(location: cur.location - 1, length: 0)).location) else { return false } }
        let here = screenLine(at: caret)
        if let here, down ? here.index < here.count - 1 : here.index > 0 { return false }
        let col = caret - (here?.range.location ?? cur.location)   // 화면 줄 안에서의 칸
        var targetLine: NSRange
        if down {
            let next = NSMaxRange(cur)
            guard next < ns.length, hidden(next), let s = span(next) else { return false }
            if NSMaxRange(s) >= ns.length {
                // 접힘이 문서 끝까지 닿으면 들어갈 보이는 줄이 없다 — AppKit 의 마지막 줄 ↓ 처럼 머리 줄 끝에 머문다 (숨은 끝 오프셋에 둔 캐럿은 보이지 않는다)
                var contentEnd = NSMaxRange(cur)
                if cur.length > 0, ns.character(at: contentEnd - 1) == 10 { contentEnd -= 1 }
                if contentEnd > cur.location, ns.character(at: contentEnd - 1) == 13 { contentEnd -= 1 }   // \r\n: \r 앞
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
        if content > 0, ns.character(at: targetLine.location + content - 1) == 13 { content -= 1 }   // \r\n 으로 끝나는 줄: 캐럿은 \r 앞까지
        // 목적지 문단이 감겨 있으면 그 첫(↓)·마지막(↑) 화면 줄의 같은 칸으로. 마지막이 아닌 화면 줄의 끝 자리는 다음 화면 줄의 머리이므로 한 칸 앞까지
        var rowStart = targetLine.location, rowLength = content
        if let there = screenLine(at: down ? targetLine.location : targetLine.location + content, caretAffinity: false), there.count > 1 {
            rowStart = there.range.location
            rowLength = there.index == there.count - 1 ? targetLine.location + content - rowStart : max(0, there.range.length - 1)
        }
        let target = rowStart + min(col, max(0, rowLength))
        setSelectedRange(NSRange(location: target, length: 0))
        scrollRangeToVisible(NSRange(location: target, length: 0))
        return true
    }
}
