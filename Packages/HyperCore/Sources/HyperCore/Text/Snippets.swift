import Foundation
import Combine

/// 스니펫 하나. `trigger` 를 치고 Tab 을 누르면 `body` 가 펼쳐진다 (`id` 는 트리거 자체).
public struct Snippet: Codable, Identifiable, Hashable, Sendable {
    public var id: String { trigger }
    public var trigger: String
    public var title: String
    public var body: String
    public init(trigger: String, title: String, body: String) {
        self.trigger = trigger; self.title = title; self.body = body
    }

    private enum CodingKeys: String, CodingKey { case trigger, title, body }
    /// 손으로 쓴 snippets.json 은 `title` 을 생략할 수 있다 (선택창은 빈 제목이면 트리거를 보여 준다) — 없다고 파일 전체를 거부하지 않는다
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trigger = try c.decode(String.self, forKey: .trigger)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try c.decode(String.self, forKey: .body)
    }
}

/// 스니펫 본문을 펼친 결과. 범위는 모두 `text` 의 UTF-16 오프셋.
/// `tabstops` 는 번호 순(1…9)의 그룹 — 같은 번호가 본문에 두 번 나오면 한 그룹에 범위가 둘 들어가 편집기가 멀티 캐럿으로 함께 고친다.
/// `final` 은 `$0` 의 위치 (없으면 nil → 편집기가 텍스트 끝에 캐럿을 둔다).
public struct SnippetExpansion: Equatable, Sendable {
    public var text: String
    public var tabstops: [[NSRange]]
    public var final: Int?
    public init(text: String, tabstops: [[NSRange]] = [], final: Int? = nil) {
        self.text = text; self.tabstops = tabstops; self.final = final
    }
}

/// 스니펫 템플릿 문법 (VS Code 부분집합):
/// - 변수 `${date}` yyyy-MM-dd · `${time}` HH:mm · `${datetime}` 타임스탬프 본문(`2026-10-30 (금) 14:05`) · `${selection}` · `${clipboard}` · `${filename}`
/// - 탭스톱 `$1`…`$9`, 자리표시자 `${1:text}` (선택된 채로 펼쳐진다), `$0` 마지막 캐럿
/// - `\$` 는 글자 `$`, `\\` 는 `\`. 모르는 `${name}` 은 그대로 남긴다 (오타가 보이도록)
public enum SnippetTemplate {
    public static func render(_ body: String, now: Date = Date(), selection: String = "", clipboard: String = "", filename: String = "",
                              locale: Locale = .autoupdatingCurrent, timeZone: TimeZone = .current) -> SnippetExpansion {
        let src = Array(body.utf16)
        let n = src.count
        var out: [UInt16] = []
        out.reserveCapacity(n + 32)
        var stops: [Int: [NSRange]] = [:]
        var final: Int?

        func variable(_ name: String) -> String? {
            switch name {
            case "date": return format("yyyy-MM-dd", now, locale, timeZone)
            case "time": return format("HH:mm", now, locale, timeZone)
            case "datetime": return Timestamp.body(now, locale: locale, timeZone: timeZone)
            case "selection": return selection
            case "clipboard": return clipboard
            case "filename": return filename
            default: return nil
            }
        }
        @inline(__always) func isDigit(_ u: UInt16) -> Bool { u >= 0x30 && u <= 0x39 }

        var i = 0
        while i < n {
            let u = src[i]
            if u == 0x5C, i + 1 < n, src[i + 1] == 0x24 || src[i + 1] == 0x5C {   // \$  \\
                out.append(src[i + 1]); i += 2; continue
            }
            guard u == 0x24, i + 1 < n else { out.append(u); i += 1; continue }
            let next = src[i + 1]
            if isDigit(next) {                                                     // $N
                let k = Int(next - 0x30)
                if k == 0 { final = out.count } else { stops[k, default: []].append(NSRange(location: out.count, length: 0)) }
                i += 2; continue
            }
            if next == 0x7B, let close = src[(i + 2)...].firstIndex(of: 0x7D) {    // ${...}
                let inner = Array(src[(i + 2)..<close])
                if let first = inner.first, isDigit(first), inner.count == 1 || inner[1] == 0x3A {
                    let k = Int(first - 0x30)
                    let placeholder = inner.count > 2 ? Array(inner[2...]) : []
                    if k == 0 { final = out.count } else { stops[k, default: []].append(NSRange(location: out.count, length: placeholder.count)) }
                    out.append(contentsOf: placeholder)
                    i = close + 1; continue
                }
                let name = String(utf16CodeUnits: inner, count: inner.count)
                if let value = variable(name) {
                    out.append(contentsOf: Array(value.utf16))
                    i = close + 1; continue
                }
            }
            out.append(u); i += 1
        }
        let text = String(utf16CodeUnits: out, count: out.count)
        let groups = stops.keys.sorted().map { stops[$0]! }
        return SnippetExpansion(text: text, tabstops: groups, final: final)
    }

    private static func format(_ pattern: String, _ date: Date, _ locale: Locale, _ tz: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = locale; f.timeZone = tz; f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

/// 스니펫 저장소 — `~/Library/Application Support/HyperEdit/snippets.json` (사용자가 HyperEdit 로 직접 고치는 평범한 JSON 배열).
/// 파일이 없으면 첫 로드 때 기본 스니펫을 써 둔다. 파일의 수정 시각이 바뀌었을 때만 다시 읽는다 (`reloadIfChanged`).
@MainActor
public final class SnippetStore: ObservableObject {
    public let fileURL: URL
    @Published public private(set) var snippets: [Snippet] = []
    /// 마지막 로드가 실패했을 때의 이유 (JSON 문법 오류 등). 성공하면 nil
    @Published public private(set) var lastError: String?
    private var loadedModification: Date?

    public init(directory: URL = SnippetStore.storeDirectory) {
        fileURL = directory.appendingPathComponent("snippets.json")
        load()
    }

    public nonisolated static var storeDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyperEdit", isDirectory: true)
    }

    /// 기본 스니펫 (값 타입 상수 — 어느 격리에서나 읽을 수 있게 nonisolated; 테스트가 메인 액터 밖에서 참조한다)
    public nonisolated static let defaults: [Snippet] = [
        Snippet(trigger: "date", title: "Date", body: "${date}"),
        Snippet(trigger: "time", title: "Time", body: "${time}"),
        Snippet(trigger: "now", title: "Date and time", body: "${datetime}"),
        Snippet(trigger: "todo", title: "To-do item", body: "- [ ] $0"),
        Snippet(trigger: "meeting", title: "Meeting notes / 회의록",
                body: "## ${date} ${1:회의 제목 / Meeting title}\n- 참석 / Attendees: ${2:}\n- 안건 / Agenda:\n  - $3\n- 결정 / Decisions:\n  - $4\n- 할 일 / Action items:\n  - [ ] $0"),
        Snippet(trigger: "table", title: "Markdown table (3 columns)",
                body: "| ${1:Column 1} | ${2:Column 2} | ${3:Column 3} |\n|---|---|---|\n| $0 |  |  |"),
        Snippet(trigger: "link", title: "Markdown link", body: "[${1:text}](${2:url})$0"),
        Snippet(trigger: "code", title: "Fenced code block", body: "```${1:lang}\n$0\n```"),
    ]

    public func snippet(forTrigger trigger: String) -> Snippet? {
        snippets.first { $0.trigger == trigger }
    }

    /// 디스크의 수정 시각이 로드 시점과 다르면 다시 읽는다 (Tab 확장·선택창 열기 직전에 호출 — stat 한 번 비용)
    public func reloadIfChanged() {
        let mod = Self.modificationDate(fileURL)
        guard mod != loadedModification else { return }
        load()
    }

    public func reload() { load() }

    private func load() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            snippets = Self.defaults
            lastError = nil
            write(Self.defaults)
            loadedModification = Self.modificationDate(fileURL)
            return
        }
        loadedModification = Self.modificationDate(fileURL)
        do {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            let strict = try JSONFormatter.minify(text)          // 주석·뒤따르는 쉼표 허용
            var list = try JSONDecoder().decode([Snippet].self, from: Data(strict.utf8))
            list = list.filter { !$0.trigger.isEmpty }
            snippets = list
            lastError = nil
        } catch let e as JSONFormatter.SyntaxError {
            lastError = "snippets.json \(e.line):\(e.column) \(e.message)"
        } catch {
            lastError = "snippets.json: \(error.localizedDescription)"
        }
    }

    /// 트리거·제목·본문 순서를 지킨 읽기 쉬운 JSON 으로 쓴다
    private func write(_ list: [Snippet]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var text = "[\n"
        for (i, s) in list.enumerated() {
            text += "  { \"trigger\": \(JSONFormatter.quote(s.trigger)), \"title\": \(JSONFormatter.quote(s.title)), \"body\": \(JSONFormatter.quote(s.body)) }"
            text += i == list.count - 1 ? "\n" : ",\n"
        }
        text += "]\n"
        try? Data(text.utf8).write(to: fileURL, options: [.atomic])
    }

    private nonisolated static func modificationDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
