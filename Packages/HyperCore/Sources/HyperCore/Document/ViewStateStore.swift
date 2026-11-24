import Foundation

/// "마지막 본 곳" 복원용 (사용자 확정: Mac·iOS 모두 마지막 위치에서 시작)
public struct EditorViewState: Codable, Equatable, Sendable {
    public var cursor: Int
    public var scrollY: Double?
    /// 화면 맨 위에 걸쳐 있던 문단의 시작 오프셋(UTF-16)과, 그 문단의 위 가장자리가 화면 위 가장자리보다 얼마나 위에 있었는가(pt).
    /// 문서 좌표 `scrollY` 는 다시 읽은 문서에서 같은 글을 가리키지 않는다(TextKit 2 는 아직 배치하지 않은 문단의 높이를 추정한다) —
    /// 보기 위치는 이 닻으로 되살린다. 예전 버전이 저장한 상태에는 없다(nil → 캐럿 줄을 화면에 맞춘다)
    public var topOffset: Int?
    public var topInset: Double?
    public var savedAt: Date
    public init(cursor: Int, scrollY: Double? = nil, topOffset: Int? = nil, topInset: Double? = nil, savedAt: Date = Date()) {
        self.cursor = cursor; self.scrollY = scrollY; self.topOffset = topOffset; self.topInset = topInset; self.savedAt = savedAt
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
