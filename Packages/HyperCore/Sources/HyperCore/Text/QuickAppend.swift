import Foundation

/// Quick Append 창이 문서 끝에 덧붙일 문자열을 만든다 (순수 로직 — 플랫폼 무관, 단위 테스트 대상).
///
/// 규칙
/// - 메모의 앞뒤 빈 줄·끝 공백은 정리하고, 결과는 항상 `\n` 으로 끝난다 (다음 추가가 새 줄에서 시작하도록).
/// - 타임스탬프 헤딩이 있으면 앞 내용과 헤딩 사이에 빈 줄 **하나** — 문서가 이미 빈 줄로 끝나면 더 넣지 않는다.
/// - 헤딩이 없으면 새 줄에서 시작하기만 한다 (문서가 `\n` 으로 끝나지 않으면 하나 넣는다).
/// - 빈 문서에는 구분 개행을 넣지 않는다. 메모가 비어 있으면 빈 문자열(호출자가 건너뜀).
public enum QuickAppendComposer {
    public static func insertion(trailingNewlines: Int, isEmptyDocument: Bool, note: String, heading: String?) -> String {
        let body = trimmed(note)
        guard !body.isEmpty else { return "" }
        let separator: String
        if isEmptyDocument {
            separator = ""
        } else if heading != nil {
            separator = String(repeating: "\n", count: max(0, 2 - trailingNewlines))
        } else {
            separator = trailingNewlines == 0 ? "\n" : ""
        }
        return separator + (heading.map { $0 + "\n" } ?? "") + body + "\n"
    }

    /// 문자열 끝의 연속된 개행 수 (`\r\n` 은 하나로 센다). 끝에서부터만 보므로 문서 크기와 무관.
    public static func trailingNewlineCount(of ns: NSString) -> Int {
        var count = 0
        var i = ns.length - 1
        while i >= 0 {
            let c = ns.character(at: i)
            if c == 10 {                                    // \n
                count += 1
                if i > 0, ns.character(at: i - 1) == 13 { i -= 1 }   // \r\n
            } else if c == 13 {                             // 홀로 쓰인 \r
                count += 1
            } else { break }
            i -= 1
        }
        return count
    }

    /// 앞의 빈 줄과 뒤의 공백·개행을 제거한다 (줄 안의 들여쓰기는 유지)
    public static func trimmed(_ s: String) -> String {
        var text = s.replacingOccurrences(of: "\r\n", with: "\n")
        while text.hasPrefix("\n") { text.removeFirst() }
        while let last = text.last, last == "\n" || last == " " || last == "\t" || last == "\r" { text.removeLast() }
        return text
    }
}
