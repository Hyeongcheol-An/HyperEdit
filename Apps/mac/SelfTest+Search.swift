import SwiftUI
import AppKit
import HyperCore

// 셀프테스트: 찾기 결과가 떠 있는 큰 문서에서 편집해도 뷰포트가 튀지 않는지, 강조 범위가 편집을 따라가는지 (search)
// 사용자 보고(2026-11-02): 1.3 MB 메모에서 찾기 결과 102건을 띄운 채 마지막 줄에 입력하면 화면이 문서 맨 위로 올라갔다.
// 원인: 매치 강조가 NSTextStorage 의 .backgroundColor 속성이라 편집마다(문서 전체 걷어내기)·지연 재검색마다(첫 매치~끝 매치)
// TextKit 2 가 그 범위의 레이아웃을 무효화했고, 뷰포트 위쪽의 추정 높이가 바뀌며 스크롤 위치가 날아갔다.
extension SelfTest {
    @MainActor
    static func runSearchHighlight(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { pumpEvent(); try? await Task.sleep(nanoseconds: ms * 1_000_000) }
        /// 지연 재검색(250 ms 줄 인덱스 + 1.2 s 디바운스 + 검색)이 끝나 결과가 새로 발행될 때까지 — 고정 대기 대신 폴링 (느린 머신에서 플레이크 방지)
        func awaitResearch(from generation: Int, timeoutMs: Int = 6000) async -> Bool {
            var waited = 0
            while model.searchGeneration == generation, waited < timeoutMs { await wait(100); waited += 100 }
            let changed = model.searchGeneration != generation
            await wait(150)   // 결과 발행 뒤 SwiftUI 가 updateNSView 로 텍스트 뷰에 새 범위를 넘길 틱을 준다
            return changed
        }
        guard let coord = model.session.primary, let tv = coord.textView else {
            check(false, "search: primary editor available"); return
        }
        let previous = model.document.url
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hyperedit-search-\(UUID().uuidString.prefix(8))", isDirectory: true)
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        catch { check(false, "search: cannot create the sample folder: \(error)"); return }
        func write(_ name: String, _ body: String) -> URL? {
            let u = dir.appendingPathComponent(name)
            do { try body.write(to: u, atomically: true, encoding: .utf8); return u } catch { check(false, "search: cannot write \(name): \(error)"); return nil }
        }
        let lineH = tv.caretRect(at: 0)?.height ?? 20

        // A. 30,000 줄(약 1 MB, 짧은 ASCII 줄), 300 줄마다 매치 하나 → 100건
        var body = ""
        body.reserveCapacity(1_100_000)
        for i in 1...30_000 { body += i % 300 == 0 ? "line \(i) NEEDLE-HL match here\n" : "line \(i) lorem ipsum dolor sit amet\n" }
        guard let big = write("big.md", body) else { return }
        model.open(url: big); await wait(1000)
        check(model.document.lineIndex.lineCount == 30_001, "search: big sample loaded lines=\(model.document.lineIndex.lineCount)")
        model.showBottomPanel = true; model.bottomTab = .findResults
        var gen = model.searchGeneration
        model.searchQuery = "NEEDLE-HL"; model.runSearch()
        _ = await awaitResearch(from: gen, timeoutMs: 3000)
        check(model.searchHits.count == 100, "search: 100 hits in the big sample (\(model.searchHits.count))")

        // 1. 마지막 줄에 입력 → 뷰포트 유지 (즉시, 그리고 지연 재검색 뒤)
        model.goToEnd(); await wait(600)
        let y0 = tv.visibleRect.minY
        check(y0 > 1000, "search: viewport is near the end (minY \(Int(y0)))")
        gen = model.searchGeneration
        model.send(.perform { tv in tv.insertText("x", replacementRange: tv.selectedRange()) }); await wait(150)
        let y1 = tv.visibleRect.minY
        check(abs(y1 - y0) <= lineH * 2, "search: typing on the last line keeps the viewport (minY \(Int(y0)) → \(Int(y1)))")
        check(await awaitResearch(from: gen), "search: the delayed re-search ran after typing")
        let y2 = tv.visibleRect.minY
        check(model.searchHits.count == 100, "search: delayed re-search still finds 100 hits (\(model.searchHits.count))")
        check(abs(y2 - y0) <= lineH * 2, "search: viewport survives the delayed re-search (minY \(Int(y0)) → \(Int(y2)))")

        // 2. 가운데 매치로 이동한 뒤 그 앞에 입력 → 그대로
        if let mid = model.searchHits.dropFirst(50).first {
            model.jump(to: mid); await wait(500)
            let y3 = tv.visibleRect.minY
            gen = model.searchGeneration
            model.send(.perform { tv in tv.insertText("y", replacementRange: NSRange(location: tv.selectedRange().location, length: 0)) }); await wait(150)
            check(abs(tv.visibleRect.minY - y3) <= lineH * 2, "search: typing at a middle match keeps the viewport (minY \(Int(y3)) → \(Int(tv.visibleRect.minY)))")
            _ = await awaitResearch(from: gen)
            check(abs(tv.visibleRect.minY - y3) <= lineH * 2, "search: viewport survives the re-search after a middle edit (minY \(Int(y3)) → \(Int(tv.visibleRect.minY)))")
            check(model.searchHits.count == 100, "search: the edited match still matches (\(model.searchHits.count))")
        }

        // 3. 강조 범위는 편집을 따라 즉시 움직인다 (재검색 전): 맨 앞에 2자 삽입 → 전부 +2, 매치 하나 지우기 → 즉시 하나 줄고 재검색도 99, undo → 재검색 뒤 100
        let before = tv.matchHighlights
        check(before.count == 100, "search: text view holds 100 match highlights (\(before.count))")
        model.send(.perform { tv in tv.insertText("ab", replacementRange: NSRange(location: 0, length: 0)) }); await wait(100)
        check(tv.matchHighlights.count == 100 && tv.matchHighlights.first?.location == (before.first?.location ?? -10) + 2,
              "search: highlights shift by +2 after inserting before them (first \(before.first?.location ?? -1) → \(tv.matchHighlights.first?.location ?? -1))")
        if let first = tv.matchHighlights.first {
            gen = model.searchGeneration
            model.send(.perform { tv in tv.insertText("", replacementRange: first) }); await wait(100)
            check(tv.matchHighlights.count == 99, "search: deleting a match drops its highlight at once (\(tv.matchHighlights.count))")
            _ = await awaitResearch(from: gen)
            check(model.searchHits.count == 99 && tv.matchHighlights.count == 99, "search: re-search agrees after the deletion (hits \(model.searchHits.count), highlights \(tv.matchHighlights.count))")
            gen = model.searchGeneration
            model.send(.perform { tv in tv.undoManager?.undo() })   // undo 는 shouldChangeText 를 거치지 않는 저장소 알림 경로
            _ = await awaitResearch(from: gen)
            check(model.searchHits.count == 100 && tv.matchHighlights.count == 100, "search: undo brings the match and its highlight back (hits \(model.searchHits.count), highlights \(tv.matchHighlights.count))")
        }

        // B. 한글 긴 줄(자동 줄바꿈으로 2~3줄씩 감김) 3,000줄 — 보고된 문서처럼 추정 높이와 실측이 크게 다른 경우. 매치는 줄 가운데(그 줄 끝에 입력해도 살아 있어야 한다)
        var ko = ""
        ko.reserveCapacity(600_000)
        let filler = "오늘 회의에서 정리한 내용을 길게 적어 둔다. 자동 줄바꿈이 두세 번 일어날 만큼 문장을 이어 가며 한글 글꼴 보정 경로도 함께 지나간다. "
        for i in 1...3_000 { ko += i % 30 == 0 ? "\(i)번째 줄 — \(filler)표식-HL 뒤에도 글이 이어진다. \(filler)\n" : "\(i)번째 줄 — \(filler)\(filler)\n" }
        if let koURL = write("big-ko.md", ko) {
            model.open(url: koURL); await wait(1000)
            log("search: hangul fixer \(coord.document.hangulFont == nil ? "off (no Hangul font)" : "on")")
            gen = model.searchGeneration
            model.searchQuery = "표식-HL"; model.runSearch()
            _ = await awaitResearch(from: gen, timeoutMs: 3000)
            check(model.searchHits.count == 100, "search(ko): 100 hits (\(model.searchHits.count))")
            model.goToEnd(); await wait(600)
            let k0 = tv.visibleRect.minY
            gen = model.searchGeneration
            model.send(.perform { tv in tv.insertText("가", replacementRange: tv.selectedRange()) }); await wait(150)
            check(abs(tv.visibleRect.minY - k0) <= lineH * 2, "search(ko): typing on the last wrapped line keeps the viewport (minY \(Int(k0)) → \(Int(tv.visibleRect.minY)))")
            _ = await awaitResearch(from: gen)
            check(abs(tv.visibleRect.minY - k0) <= lineH * 2 && model.searchHits.count == 100, "search(ko): viewport survives the re-search (minY \(Int(k0)) → \(Int(tv.visibleRect.minY)), hits \(model.searchHits.count))")
            // 매치가 있는 줄의 끝에 입력 → 같은 줄의 강조가 즉시 사라지지 않는다 (편집 전 좌표로 옮기므로; 한글 폭 보정이 문단 전체를 속성 편집해도)
            if let mid = model.searchHits.dropFirst(50).first {
                model.jump(to: mid); await wait(500)
                let k1 = tv.visibleRect.minY
                let countBefore = tv.matchHighlights.count
                model.send(.perform { tv in
                    let ns = tv.string as NSString
                    let para = ns.paragraphRange(for: tv.selectedRange())
                    var end = NSMaxRange(para); if end > 0, ns.character(at: end - 1) == 10 { end -= 1 }
                    tv.setSelectedRange(NSRange(location: end, length: 0))
                    tv.insertText("한", replacementRange: tv.selectedRange())
                }); await wait(150)
                check(tv.matchHighlights.count == countBefore, "search(ko): typing at the end of a match's line keeps its highlight (\(countBefore) → \(tv.matchHighlights.count))")
                check(abs(tv.visibleRect.minY - k1) <= lineH * 2, "search(ko): typing mid-document keeps the viewport (minY \(Int(k1)) → \(Int(tv.visibleRect.minY)))")
            }
        }

        // 정리: 검색을 비우고 원래 문서로 (전환 시 샘플의 편집은 임시 파일에 저장된다), 임시 폴더 삭제
        model.searchQuery = ""; model.runSearch()
        model.open(url: previous); await wait(800)
        try? FileManager.default.removeItem(at: dir)
        check(model.document.url.lastPathComponent == previous.lastPathComponent, "search: back on \(previous.lastPathComponent)")
        check(tv.matchHighlights.isEmpty, "search: highlights cleared after switching documents (\(tv.matchHighlights.count))")
    }
}
