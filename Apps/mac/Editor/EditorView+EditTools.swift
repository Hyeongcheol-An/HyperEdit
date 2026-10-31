import AppKit
import HyperCore

// 주석 토글(⌘/) · JSON 정리(⌃⌘J) · 스니펫 공급자 — EditorView.Coordinator.applyTextTool / attach 에서 호출. 모두 insertText 경유라 ⌘Z 한 번.
extension EditorView.Coordinator {
    /// 주석 토글: 선택한 줄들(없으면 현재 줄)에 파일 종류의 주석 기호를 넣거나 뺀다. 선택이 있으면 결과를 다시 선택하고,
    /// 없으면 캐럿을 같은 줄의 같은 글자 뒤에 둔다 (기호 삽입·제거만큼 열을 옮김).
    func toggleComment(_ tv: HyperTextView, _ sel: NSRange, _ lineRange: NSRange) {
        let syntax = CommentRegistry.syntax(for: document.url)
        guard syntax.isUsable else { return }
        let ns = tv.string as NSString
        var text = ns.substring(with: lineRange)
        let hadNewline = text.hasSuffix("\n")
        if hadNewline { text.removeLast() }
        let lines = text.components(separatedBy: "\n")
        let out = Perf.measure("toggleComment.core lines=\(lines.count)") { TextTools.toggleLineComment(lines: lines, syntax: syntax) }
        guard out != lines else { return }
        var result = out.joined(separator: "\n")
        if hadNewline { result += "\n" }
        // 문서 전체(1.3 MB) 교체는 여기(TextKit 2 재배치·구문 색)가 거의 전부다 — --debug-perf 로 core 와 따로 본다
        Perf.measure("toggleComment.insertText len=\((result as NSString).length)") { tv.insertText(result, replacementRange: lineRange) }
        if sel.length > 0 {
            tv.setSelectedRange(NSRange(location: lineRange.location, length: (result as NSString).length))
        } else {
            let col = Self.adjustedColumn(sel.location - lineRange.location, old: lines[0] as NSString, new: out[0] as NSString)
            tv.setSelectedRange(NSRange(location: lineRange.location + col, length: 0))
        }
    }

    /// 한 줄이 old → new 로 바뀐 뒤의 캐럿 열: 공통 접두 앞이면 그대로, 공통 접미 안이면 길이 차만큼.
    /// 바뀐 가운데 구간(`<!-- beta -->` ↔ `beta` 처럼 한쪽이 다른 쪽을 품는 경우)은 품은 위치에 맞춰 옮기고, 아니면 그 안에서 클램프.
    static func adjustedColumn(_ col: Int, old: NSString, new: NSString) -> Int {
        var p = 0
        while p < old.length, p < new.length, old.character(at: p) == new.character(at: p) { p += 1 }
        var s = 0
        while s < old.length - p, s < new.length - p, old.character(at: old.length - 1 - s) == new.character(at: new.length - 1 - s) { s += 1 }
        if col <= p { return col }
        if col >= old.length - s { return col + (new.length - old.length) }
        let oldMid = old.substring(with: NSRange(location: p, length: old.length - s - p)) as NSString
        let newMid = new.substring(with: NSRange(location: p, length: new.length - s - p)) as NSString
        let c = col - p
        if oldMid.length > 0, case let r = newMid.range(of: oldMid as String), r.location != NSNotFound { return p + r.location + c }   // 감쌈
        if newMid.length > 0, case let r = oldMid.range(of: newMid as String), r.location != NSNotFound { return p + max(0, min(c - r.location, newMid.length)) }   // 벗김
        return p + min(c, newMid.length)
    }

    /// JSON 정리: 선택(없으면 문서 전체)을 보기 좋게 / 한 줄로. 문법 오류면 텍스트는 두고 출력 패널에 줄:열을 알린 뒤 캐럿을 그 자리로 옮긴다.
    func formatJSON(_ tv: HyperTextView, _ sel: NSRange, minify: Bool) {
        let ns = tv.string as NSString
        let range = sel.length > 0 ? sel : NSRange(location: 0, length: ns.length)
        let input = ns.substring(with: range)
        do {
            let result = try Perf.measure("formatJSON.core len=\(range.length)") { minify ? try JSONFormatter.minify(input) : try JSONFormatter.format(input) }
            let len = (result as NSString).length
            if result != input { Perf.measure("formatJSON.insertText len=\(len)") { tv.insertText(result, replacementRange: range) } }
            if sel.length > 0 {
                tv.setSelectedRange(NSRange(location: range.location, length: len))
            } else {
                tv.setSelectedRange(NSRange(location: 0, length: 0))
                tv.scrollRangeToVisible(NSRange(location: 0, length: 0))
            }
            if minify {
                model.log(String(localized: "Minified JSON · \(len) characters"))
            } else {
                let lines = result.utf8.reduce(0) { $0 + ($1 == 10 ? 1 : 0) } + (result.hasSuffix("\n") ? 0 : 1)
                model.log(String(localized: "Formatted JSON · \(lines) lines"))
            }
        } catch let e as JSONFormatter.SyntaxError {
            // 문서 기준 줄·열 (선택 안의 위치 + 선택 시작). 문서 인덱스는 편집 뒤 250 ms 동안 낡을 수 있어 문자열에서 직접 센다
            let at = min(range.location + e.offset, ns.length)
            let line = LineIndex.countNewlines(in: ns, range: NSRange(location: 0, length: at)) + 1
            let lineStart = ns.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: at))
            let column = at - (lineStart.location == NSNotFound ? 0 : NSMaxRange(lineStart)) + 1
            model.log(String(localized: "JSON error · line \(line), column \(column) · \(e.message)"), isError: true)
            model.showBottomPanel = true
            model.bottomTab = .output
            tv.setSelectedRange(NSRange(location: at, length: 0))
            tv.scrollRangeToVisible(NSRange(location: at, length: 0))
        } catch {
            model.log(error.localizedDescription, isError: true)
        }
    }

    /// 스니펫 공급자: Tab 앞 단어 → 저장소(수정됐으면 다시 읽음) → 렌더링. 펼침은 출력 패널에 기록
    func installSnippets(on tv: HyperTextView) {
        tv.snippetProvider = { [weak self, weak tv] trigger in
            guard let self, let tv else { return nil }
            let store = self.model.snippets
            store.reloadIfChanged()
            guard let snippet = store.snippet(forTrigger: trigger) else { return nil }
            return SnippetRendering.expansion(for: snippet, in: tv, filename: self.document.url.lastPathComponent)
        }
        tv.onSnippetExpanded = { [weak self] trigger in self?.model.log(String(localized: "Snippet · \(trigger)")) }
    }
}
