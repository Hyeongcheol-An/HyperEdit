import Foundation
import Combine
import CryptoKit

public struct Bookmark: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var line: Int
    public var name: String
    public var preview: String
    public var created: Date
    public init(line: Int, name: String = "", preview: String = "") {
        id = UUID(); self.line = line; self.name = name; self.preview = preview; created = Date()
    }
}

/// 북마크 저장소. 파일별 JSON 을 `~/Library/Application Support/HyperEdit/bookmarks/<경로 해시>.json` 에 둔다
/// (사용자 문서 폴더에 숨김 파일을 만들지 않고, 읽기 전용 볼륨의 파일도 북마크할 수 있게).
/// 예전 버전이 문서 옆에 만들던 `.<파일명>.bookmarks.json` 사이드카는 읽기만 하고(1회 이전) 지우지 않는다.
@MainActor
public final class BookmarkStore: ObservableObject {
    public private(set) var fileURL: URL
    public private(set) var storeURL: URL
    @Published public private(set) var bookmarks: [Bookmark] = []

    public init(fileURL: URL) {
        self.fileURL = fileURL
        storeURL = Self.storeURL(for: fileURL)
        load()
    }

    public static var storeDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyperEdit/bookmarks", isDirectory: true)
    }

    public static func storeURL(for fileURL: URL) -> URL {
        let path = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32)
        return storeDirectory.appendingPathComponent("\(digest).json")
    }

    static func legacySidecar(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("." + fileURL.lastPathComponent + ".bookmarks.json")
    }

    /// 다른 파일의 북마크로 전환 (객체 유지)
    public func switchTo(fileURL newURL: URL) {
        fileURL = newURL
        storeURL = Self.storeURL(for: newURL)
        bookmarks = []
        load()
    }

    public func contains(line: Int) -> Bool { bookmarks.contains { $0.line == line } }

    @discardableResult
    public func toggle(line: Int, preview: String) -> Bool {
        if let i = bookmarks.firstIndex(where: { $0.line == line }) {
            bookmarks.remove(at: i); save(); return false
        }
        bookmarks.append(Bookmark(line: line, preview: preview))
        bookmarks.sort { $0.line < $1.line }
        save(); return true
    }

    public func remove(id: UUID) { bookmarks.removeAll { $0.id == id }; save() }

    public func rename(id: UUID, name: String) {
        guard let i = bookmarks.firstIndex(where: { $0.id == id }) else { return }
        bookmarks[i].name = name; save()
    }

    private func load() {
        if let list = Self.read(storeURL) { bookmarks = list; return }
        if let list = Self.read(Self.legacySidecar(for: fileURL)) {   // 1회 이전: 사이드카 → Application Support
            bookmarks = list
            save()
        }
    }

    private static func read(_ url: URL) -> [Bookmark]? {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Bookmark].self, from: data) else { return nil }
        return list.sorted { $0.line < $1.line }
    }

    private func save() {
        let fm = FileManager.default
        if bookmarks.isEmpty { try? fm.removeItem(at: storeURL); return }
        try? fm.createDirectory(at: Self.storeDirectory, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(bookmarks) { try? data.write(to: storeURL, options: [.atomic]) }
    }
}
