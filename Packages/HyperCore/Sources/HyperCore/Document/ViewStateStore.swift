import Foundation

/// "마지막 본 곳" 복원용 (사용자 확정: Mac·iOS 모두 마지막 위치에서 시작)
public struct EditorViewState: Codable, Equatable, Sendable {
    public var cursor: Int
    public var scrollY: Double?
    public var savedAt: Date
    public init(cursor: Int, scrollY: Double? = nil, savedAt: Date = Date()) {
        self.cursor = cursor; self.scrollY = scrollY; self.savedAt = savedAt
    }
}

public enum ViewStateStore {
    private static func key(_ url: URL) -> String { "hyperedit.viewstate:" + url.standardizedFileURL.path }

    public static func load(for url: URL, defaults: UserDefaults = AppDefaults.store) -> EditorViewState? {
        guard let data = defaults.data(forKey: key(url)) else { return nil }
        return try? JSONDecoder().decode(EditorViewState.self, from: data)
    }

    public static func save(_ state: EditorViewState, for url: URL, defaults: UserDefaults = AppDefaults.store) {
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: key(url)) }
    }
}
