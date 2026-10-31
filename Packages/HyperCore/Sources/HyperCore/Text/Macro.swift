import Foundation
import Combine

/// 매크로 한 단계 (UltraEdit 식 키 입력 기록). JSON 은 `{"type":"insert","value":"…"}` 꼴 —
/// 사용자가 "매크로 파일 편집…" 으로 직접 고칠 수 있게 합성 Codable 의 `{"insert":{"_0":…}}` 대신 평평한 형태를 쓴다.
public enum MacroStep: Codable, Equatable, Sendable {
    /// 글자 입력 — 타이핑·붙여넣기·IME 확정. 기록할 때 연속된 입력은 하나로 합쳐진다 (`MacroRecording`)
    case insert(String)
    /// NSResponder 동작 셀렉터 이름 (예: `moveRight:` `deleteBackward:` `insertNewline:` `moveToEndOfLine:`)
    case command(String)
    /// 텍스트 도구 (`TextTool` rawValue — `deleteLine` `upper` `sortAsc` …)
    case tool(String)
    /// 다음 찾기 — 캐럿 뒤에서 검색어를 찾아 선택한다. 못 찾으면 재생이 멈춘다 (반복 재생의 종료 조건)
    case find(String)

    private enum CodingKeys: String, CodingKey { case type, value }
    private enum Kind: String, Codable { case insert, command, tool, find }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .type)
        let value = try c.decodeIfPresent(String.self, forKey: .value) ?? ""
        switch kind {
        case .insert: self = .insert(value)
        case .command: self = .command(value)
        case .tool: self = .tool(value)
        case .find: self = .find(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let (kind, value): (Kind, String)
        switch self {
        case .insert(let s): (kind, value) = (.insert, s)
        case .command(let s): (kind, value) = (.command, s)
        case .tool(let s): (kind, value) = (.tool, s)
        case .find(let s): (kind, value) = (.find, s)
        }
        try c.encode(kind, forKey: .type)
        try c.encode(value, forKey: .value)
    }
}

public struct Macro: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var steps: [MacroStep]
    public var created: Date

    public init(id: UUID = UUID(), name: String, steps: [MacroStep], created: Date = Macro.now()) {
        self.id = id; self.name = name; self.steps = steps; self.created = created
    }

    /// 초 단위로 자른 현재 시각 — 저장 형식(ISO 8601, 소수 초 없음)과 왕복해도 같은 값이 되도록
    public static func now() -> Date { Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)) }
}

/// 기록 중인 단계 목록. 연속된 `.insert` 는 한 단계로 합친다 (키 한 번 = 단계 하나가 되지 않게).
public struct MacroRecording: Equatable, Sendable {
    public private(set) var steps: [MacroStep] = []
    public init() {}
    public var isEmpty: Bool { steps.isEmpty }

    public mutating func append(_ step: MacroStep) {
        if case .insert(let s) = step, case .insert(let prev)? = steps.last {
            steps[steps.count - 1] = .insert(prev + s)
        } else {
            steps.append(step)
        }
    }
}

/// 매크로 저장소 — `~/Library/Application Support/HyperEdit/macros/macros.json` 하나에 저장된 매크로 목록과
/// 마지막으로 기록한 매크로(이름 없음, "재생" 대상)를 함께 둔다. 폴더는 주입 가능(테스트·자동화 실행은 임시 폴더).
@MainActor
public final class MacroStore: ObservableObject {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("macros.json") }
    @Published public private(set) var macros: [Macro] = []
    @Published public private(set) var lastRecorded: Macro?
    /// 파일은 있는데 읽지 못했을 때 (사용자가 JSON 을 잘못 고친 경우). 메모리의 목록은 비우지 않고, 다음 저장 때 덮어쓴다
    @Published public private(set) var loadError: String?

    public nonisolated static var storeDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyperEdit/macros", isDirectory: true)
    }

    public init(directory: URL = MacroStore.storeDirectory) {
        self.directory = directory
        load()
    }

    private struct File: Codable {
        var macros: [Macro]
        var lastRecorded: Macro?
    }

    public func macro(id: UUID) -> Macro? { macros.first { $0.id == id } }

    /// 방금 기록한 매크로 (재시작 뒤에도 "재생" 이 되도록 함께 저장)
    public func setLastRecorded(_ macro: Macro?) {
        lastRecorded = macro
        save()
    }

    /// 매크로를 이름을 붙여 목록에 추가한다 (새 id). 이름이 비면 `Macro N`
    @discardableResult
    public func save(_ macro: Macro, name: String) -> Macro {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = Macro(name: trimmed.isEmpty ? "Macro \(macros.count + 1)" : trimmed, steps: macro.steps)
        macros.append(m)
        save()
        return m
    }

    public func rename(id: UUID, name: String) {
        guard let i = macros.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, macros[i].name != trimmed else { return }
        macros[i].name = trimmed
        save()
    }

    public func delete(id: UUID) {
        guard macros.contains(where: { $0.id == id }) else { return }
        macros.removeAll { $0.id == id }
        save()
    }

    /// 사용자가 JSON 을 편집기로 고친 뒤 다시 읽기
    public func reload() { load() }

    /// 편집기로 열 수 있도록 파일이 없으면 현재 상태(빈 목록)를 써 둔다
    public func ensureFileExists() {
        if !FileManager.default.fileExists(atPath: fileURL.path) { save() }
    }

    private func load() {
        loadError = nil
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        do {
            let f = try dec.decode(File.self, from: data)
            macros = f.macros
            lastRecorded = f.lastRecorded
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(File(macros: macros, lastRecorded: lastRecorded)) {
            try? data.write(to: fileURL, options: [.atomic])
        }
    }
}
