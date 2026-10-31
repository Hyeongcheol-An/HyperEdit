import SwiftUI
import AppKit
import HyperCore

// 셀프테스트: 주석 토글(⌘/) · JSON 정리(⌃⌘J) · 스니펫 Tab 확장. 샘플 끝에 줄을 덧붙여 검사하고 끝에 원상복구한다.
extension SelfTest {
    @MainActor
    static func runEditTools(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { try? await Task.sleep(nanoseconds: ms * 1_000_000) }
        func text() -> NSString { model.document.textStorage.string as NSString }
        func lastLines(_ n: Int) -> [String] { Array((text() as String).components(separatedBy: "\n").suffix(n)) }
        func caret() -> Int { var loc = -1; model.send(.perform { tv in loc = tv.selectedRange().location }); return loc }
        func append(_ s: String) {
            model.send(.perform { tv in
                tv.breakUndoCoalescing()
                tv.insertText(s, replacementRange: NSRange(location: (tv.string as NSString).length, length: 0))
                tv.setSelectedRange(NSRange(location: (tv.string as NSString).length, length: 0))   // 캐럿을 끝으로 (교체 범위 삽입은 캐럿을 옮기지 않을 수 있다)
            })
        }
        func selectTail(_ count: Int) { model.send(.perform { tv in let n = (tv.string as NSString).length; tv.setSelectedRange(NSRange(location: n - count, length: count)) }) }
        let originalLength = text().length

        // 1. 주석 토글 — sample.md 는 마크다운이라 `<!-- … -->` 를 줄마다 감싼다. 두 줄 선택 → 토글(기호는 가장 얕은 들여쓰기 = 0열에 정렬) → 다시 토글하면 원문
        append("\nalpha\n  beta"); await wait(200)
        selectTail("alpha\n  beta".utf16.count)
        model.textTool(.toggleComment); await wait(300)
        check(lastLines(2) == ["<!-- alpha -->", "<!--   beta -->"], "toggle comment (md block style, aligned at column 0) → \(lastLines(2))")
        model.textTool(.toggleComment); await wait(300)
        check(lastLines(2) == ["alpha", "  beta"], "toggle comment again → original \(lastLines(2))")
        // 선택 없이 캐럿만: 같은 줄, 기호 길이(5)만큼 밀린 열
        model.send(.perform { tv in tv.setSelectedRange(NSRange(location: (tv.string as NSString).length - 2, length: 0)) })   // "  be|ta"
        let before = caret()
        model.textTool(.toggleComment); await wait(300)
        check(lastLines(1) == ["  <!-- beta -->"] && caret() == before + 5, "caret-only toggle keeps caret on same text (\(caret() - before) shift)")
        // (⌘Z 한 단계 검사는 하지 않는다 — 셀프테스트의 프로그램적 insertText 들은 한 '입력' undo 그룹으로 합쳐진다. 실제 메뉴·단축키 호출은 이벤트마다 따로 묶인다)
        model.textTool(.toggleComment); await wait(300)
        check(lastLines(2) == ["alpha", "  beta"], "caret-only toggle again → original \(lastLines(2))")

        // 2. JSON 정리: 선택 범위를 보기 좋게 → 한 줄로 → 깨진 JSON 은 그대로 두고 오류 위치 보고
        let json = #"{"b":1,"a":[1,2]}"#
        append("\n" + json); await wait(200)
        selectTail(json.utf16.count)
        model.textTool(.formatJSON); await wait(300)
        let pretty = "{\n  \"b\": 1,\n  \"a\": [\n    1,\n    2\n  ]\n}"
        check(lastLines(7).joined(separator: "\n") == pretty && model.output.last?.text.contains("7") == true, "format JSON selection → 7 lines, output '\(model.output.last?.text ?? "")'")
        model.textTool(.minifyJSON); await wait(300)   // 선택은 정리 결과 전체로 남아 있다
        check(lastLines(1) == [json], "minify JSON → '\(lastLines(1).first ?? "")'")
        let broken = #"{"a":1,,}"#
        append("\n" + broken); await wait(200)
        selectTail(broken.utf16.count)
        let lengthBefore = text().length, outputCount = model.output.count
        model.textTool(.formatJSON); await wait(300)
        // 편집 뒤 자동 재검색 로그가 끼어들 수 있으므로 이번에 추가된 출력 중 오류 줄을 찾는다
        let err = model.output.dropFirst(outputCount).last { $0.isError }
        let errorOffset = text().length - broken.utf16.count + 7   // 두 번째 쉼표
        let errorLine = LineIndex(text: text() as String).lineNumber(forUTF16Offset: errorOffset)
        check(text().length == lengthBefore && lastLines(1) == [broken], "invalid JSON leaves text unchanged")
        check(err != nil && (err?.text.contains("\(errorLine)") ?? false) && (err?.text.contains("8") ?? false),
              "invalid JSON → error with line:column (\(errorLine):8) in output '\(err?.text ?? "")'")
        check(caret() == errorOffset, "caret moved to error position (\(caret()) vs \(errorOffset))")

        // 3. 스니펫: `todo` + Tab → `- [ ] ` 와 캐럿 끝 (공급자 경로 = 임시 저장소의 기본 스니펫)
        append("\ntodo"); await wait(200)
        model.send(.perform { tv in tv.doCommand(by: #selector(NSResponder.insertTab(_:))) }); await wait(300)
        check(lastLines(1) == ["- [ ] "] && caret() == text().length, "snippet 'todo' + Tab → '\(lastLines(1).first ?? "")' caret at end")
        check(model.output.last?.text.contains("todo") == true, "snippet expansion logged '\(model.output.last?.text ?? "")'")
        // 탭스톱 세션: link → [text](url) 에서 text 선택, 입력 후 Tab → url 선택, Tab → $0
        append("\nlink"); await wait(200)
        model.send(.perform { tv in tv.doCommand(by: #selector(NSResponder.insertTab(_:))) }); await wait(200)
        var selectedText = ""
        model.send(.perform { tv in selectedText = (tv.string as NSString).substring(with: tv.selectedRange()) })
        check(lastLines(1) == ["[text](url)"] && selectedText == "text", "snippet 'link' selects first placeholder '\(selectedText)'")
        model.send(.perform { tv in tv.insertText("HyperEdit", replacementRange: tv.selectedRange()) }); await wait(200)
        model.send(.perform { tv in tv.doCommand(by: #selector(NSResponder.insertTab(_:))) }); await wait(200)
        model.send(.perform { tv in selectedText = (tv.string as NSString).substring(with: tv.selectedRange()) })
        check(lastLines(1) == ["[HyperEdit](url)"] && selectedText == "url", "typing + Tab → second placeholder '\(selectedText)' (ranges adjusted)")
        model.send(.perform { tv in tv.doCommand(by: #selector(NSResponder.insertTab(_:))) }); await wait(200)
        var sessionActive = true
        model.send(.perform { tv in sessionActive = tv.snippetSession != nil })
        check(caret() == text().length && !sessionActive, "last Tab → $0 and session ends")
        // 트리거가 아닌 단어 + Tab 은 일반 탭
        append("\nnotatrigger"); await wait(200)
        model.send(.perform { tv in tv.doCommand(by: #selector(NSResponder.insertTab(_:))) }); await wait(200)
        check(lastLines(1) == ["notatrigger\t"], "non-trigger word + Tab inserts a tab")

        // 원상복구
        model.send(.perform { tv in
            let n = (tv.string as NSString).length
            tv.insertText("", replacementRange: NSRange(location: originalLength, length: n - originalLength))
        }); await wait(200)
        check(text().length == originalLength, "edit-tools sample restored")
        // 스크린샷용: `--show-snippet-picker` 와 함께 실행하면 스니펫 선택창을 띄운 채 둔다 (`--snapshot … --snapshot-delay 28` 로 캡처)
        if LaunchOptions.has("--show-snippet-picker") { model.showSnippetPicker = true }
    }
}
