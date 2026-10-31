import AppKit
import HyperCore

/// 스니펫 탭스톱 세션. 펼친 직후 시작되어 Tab / ⇧Tab 으로 탭스톱 그룹을 오가고, 마지막 Tab 은 `$0` 으로 간다.
/// 범위는 문서 절대 UTF-16 오프셋이며, 모든 편집이 지나는 `HyperTextView.shouldChangeText` 에서 편집 직전 좌표로 보정한다
/// (입력·삭제·붙여넣기·멀티 편집·undo 모두). 활성 그룹의 범위는 경계에 붙여 쓴 글자를 흡수해 자라고, 다른 범위는 밀린다.
final class SnippetSession {
    private(set) var stops: [[NSRange]]
    private(set) var final: Int
    var index = 0
    /// 범위를 가로지르는 편집(탭스톱 바깥에서 안으로 지우기 등)이 있었으면 true — 세션을 끝낸다
    private(set) var broken = false

    init(stops: [[NSRange]], final: Int) {
        self.stops = stops
        self.final = final
    }

    var current: [NSRange] { stops.indices.contains(index) ? stops[index] : [] }
    var isLast: Bool { index >= stops.count - 1 }

    /// 편집 직전 좌표의 (범위, 치환 문자열) 목록. 뒤쪽 편집부터 적용하면 앞쪽 편집의 좌표가 흔들리지 않는다.
    func textWillChange(_ edits: [(NSRange, String)]) {
        for (r, s) in edits.sorted(by: { $0.0.location > $1.0.location }) {
            guard r.location != NSNotFound else { continue }
            let delta = (s as NSString).length - r.length
            adjust(x: r.location, y: NSMaxRange(r), delta: delta)
        }
    }

    private func adjust(x: Int, y: Int, delta: Int) {
        let insertion = x == y
        for g in stops.indices {
            let active = g == index
            for k in stops[g].indices {
                let a = stops[g][k].location, b = NSMaxRange(stops[g][k])
                if y < a || (y == a && (!insertion || !active)) {
                    stops[g][k].location += delta                           // 앞쪽 편집 → 밀림
                } else if x > b || (x == b && (!insertion || !active)) {
                    continue                                                 // 뒤쪽 편집 → 그대로
                } else if x >= a && y <= b {
                    stops[g][k].length += delta                             // 범위 안(경계 포함) → 길이 변화
                } else {
                    broken = true                                            // 범위를 가로지름
                }
            }
        }
        if y <= final { final += delta } else if x < final { final = x; broken = true }
    }
}

extension HyperTextView {
    /// 트리거 단어 글자: 영숫자(한글 포함)·`_`
    private static func isTriggerChar(_ u: unichar) -> Bool {
        if u == 0x5F { return true }
        guard let s = UnicodeScalar(u) else { return false }
        return CharacterSet.alphanumerics.contains(s)
    }

    /// Tab: 캐럿 바로 앞 단어가 스니펫 트리거면 펼치고 true. 선택·멀티 캐럿·IME 조합 중이면 false (일반 Tab)
    func expandSnippetAtCaret() -> Bool {
        guard !hasMarkedText(), let provider = snippetProvider else { return false }
        let sel = selectedRange()
        guard sel.length == 0 else { return false }
        let ns = string as NSString
        var start = sel.location
        while start > 0, Self.isTriggerChar(ns.character(at: start - 1)) { start -= 1 }
        guard start < sel.location else { return false }
        let range = NSRange(location: start, length: sel.location - start)
        let trigger = ns.substring(with: range)
        guard let expansion = provider(trigger) else { return false }
        insertSnippet(expansion, replacing: range, trigger: trigger)
        return true
    }

    /// 펼침 결과를 `range` 에 넣고(undo 한 단계) 첫 탭스톱을 선택하거나 `$0` 에 캐럿을 둔다
    func insertSnippet(_ expansion: SnippetExpansion, replacing range: NSRange, trigger: String) {
        endSnippetSession()
        clearMulti()
        breakUndoCoalescing()
        insertText(expansion.text, replacementRange: range)
        let base = range.location
        let end = base + (expansion.text as NSString).length
        let final = expansion.final.map { $0 + base } ?? end
        let stops = expansion.tabstops.map { group in group.map { NSRange(location: $0.location + base, length: $0.length) } }
        if stops.isEmpty {
            setSelectedRange(NSRange(location: final, length: 0))
        } else {
            let session = SnippetSession(stops: stops, final: final)
            snippetSession = session
            selectSnippetStops(session.current)
        }
        onSnippetExpanded?(trigger)
    }

    func snippetTabForward() {
        guard let s = snippetSession, !s.broken else { endSnippetSession(); return }
        if s.isLast {
            let f = min(s.final, (string as NSString).length)
            endSnippetSession()
            clearMulti()
            setSelectedRange(NSRange(location: f, length: 0))
            scrollRangeToVisible(selectedRange())
        } else {
            s.index += 1
            selectSnippetStops(s.current)
        }
    }

    func snippetTabBackward() {
        guard let s = snippetSession, !s.broken else { endSnippetSession(); return }
        guard s.index > 0 else { return }
        s.index -= 1
        selectSnippetStops(s.current)
    }

    func endSnippetSession() {
        snippetSession = nil
    }

    /// shouldChangeText 에서 — 세션 범위 보정
    func snippetTextWillChange(_ edits: [(NSRange, String)]) {
        guard let s = snippetSession else { return }
        s.textWillChange(edits)
        if s.broken { endSnippetSession() }
    }

    /// 방향키 이동 뒤: 캐럿이 활성 탭스톱 밖으로 나갔으면 세션 종료
    func snippetCaretMoved() {
        guard let s = snippetSession else { return }
        let sel = selectedRange()
        let inside = s.current.contains { sel.location >= $0.location && NSMaxRange(sel) <= NSMaxRange($0) }
        if !inside { endSnippetSession() }
    }

    private func selectSnippetStops(_ ranges: [NSRange]) {
        let len = (string as NSString).length
        let valid = ranges.filter { $0.location >= 0 && NSMaxRange($0) <= len }
        guard !valid.isEmpty else { endSnippetSession(); return }
        if valid.count == 1 {
            clearMulti()
            setSelectedRange(valid[0])
            scrollRangeToVisible(valid[0])
        } else {
            setMulti(valid)   // 같은 번호의 탭스톱 둘 이상 → 멀티 캐럿으로 함께 편집
        }
    }
}

/// 스니펫 렌더링 — 선택 텍스트·클립보드·파일 이름을 변수로 넘긴다 (Tab 확장과 선택창 삽입이 함께 쓴다)
enum SnippetRendering {
    @MainActor
    static func expansion(for snippet: Snippet, in tv: HyperTextView, filename: String) -> SnippetExpansion {
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        let selection = sel.length > 0 && NSMaxRange(sel) <= ns.length ? ns.substring(with: sel) : ""
        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        return SnippetTemplate.render(snippet.body, selection: selection, clipboard: clipboard, filename: filename)
    }
}

extension SnippetStore {
    /// 자동화 실행(`--selftest` `--snapshot` `--ephemeral`)은 임시 폴더를 써 사용자의 snippets.json 을 건드리지 않는다
    static var launchDirectory: URL {
        if LaunchOptions.has("--selftest") || LaunchOptions.has("--selftest-open") || LaunchOptions.has("--snapshot") || LaunchOptions.has("--ephemeral") {
            return FileManager.default.temporaryDirectory.appendingPathComponent("hyperedit-ephemeral-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        }
        return storeDirectory
    }
}

extension AppModel {
    /// 선택창(⇧⌘I)에서 고른 스니펫을 캐럿(선택이 있으면 그 자리)에 삽입
    func insertSnippet(_ snippet: Snippet) {
        showSnippetPicker = false
        let filename = document.url.lastPathComponent
        send(.perform { tv in
            let expansion = SnippetRendering.expansion(for: snippet, in: tv, filename: filename)
            tv.insertSnippet(expansion, replacing: tv.selectedRange(), trigger: snippet.trigger)
            tv.window?.makeFirstResponder(tv)
        })
    }

    /// snippets.json 을 HyperEdit 자신으로 연다 — 저장하면 다음 Tab 확장·선택창 열기 때 다시 읽는다
    func editSnippets() {
        showSnippetPicker = false
        snippets.reloadIfChanged()   // 파일이 없으면 기본값을 써 둔다
        open(url: snippets.fileURL)
        log(String(localized: "Editing snippets — save, then type a trigger and press Tab"))
    }
}
