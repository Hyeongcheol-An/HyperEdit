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
    /// JSON 이 놓이는 폴더 (기본 Application Support, 테스트는 임시 폴더)
    public let directory: URL
    @Published public private(set) var bookmarks: [Bookmark] = []

    public init(fileURL: URL, storeDirectory: URL = BookmarkStore.storeDirectory) {
        self.fileURL = fileURL
        directory = storeDirectory
        storeURL = Self.storeURL(for: fileURL, in: storeDirectory)
        load()
    }

    public nonisolated static var storeDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("HyperEdit/bookmarks", isDirectory: true)
    }

    public nonisolated static func storeURL(for fileURL: URL, in directory: URL = BookmarkStore.storeDirectory) -> URL {
        let path = fileURL.standardizedFileURL.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32)
        return directory.appendingPathComponent("\(digest).json")
    }

    static func legacySidecar(for fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("." + fileURL.lastPathComponent + ".bookmarks.json")
    }

    /// 다른 파일의 북마크로 전환 (객체 유지)
    public func switchTo(fileURL newURL: URL) {
        fileURL = newURL
        storeURL = Self.storeURL(for: newURL, in: directory)
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

    // MARK: 줄 추적 (편집으로 줄이 늘거나 줄면 북마크 줄 번호를 따라 옮긴다)

    /// 편집기가 줄 수를 바꾸기 직전에 호출. `atLine` 보다 뒤의 북마크는 `delta` 만큼 이동하고,
    /// 삭제(delta < 0)로 사라지는 줄 `atLine+1 ... atLine-delta` 의 북마크는 제거된다. `atLine` 자체는 움직이지 않는다
    /// (줄 머리에서 시작하는 편집은 호출 측이 `atLine - 1` 을 넘겨 그 줄까지 밀거나 지운다).
    public func shift(fromLine atLine: Int, delta: Int) {
        guard delta != 0, !bookmarks.isEmpty else { return }
        var out: [Bookmark] = []
        out.reserveCapacity(bookmarks.count)
        for var b in bookmarks {
            if b.line <= atLine { out.append(b); continue }
            if delta < 0, b.line <= atLine - delta { continue }        // 지워지는 줄 안
            b.line += delta
            out.append(b)
        }
        let deduped = Self.dedupe(out)
        guard deduped != bookmarks else { return }
        bookmarks = deduped
        save()
    }

    /// 파일을 다시 읽은 뒤: 줄 수를 넘는 북마크는 마지막 줄로 당기고 같은 줄의 중복은 하나만 남긴다
    public func clamp(toLineCount count: Int) {
        let limit = max(1, count)
        guard bookmarks.contains(where: { $0.line > limit }) else { return }
        let clamped = Self.dedupe(bookmarks.map { var b = $0; b.line = min(b.line, limit); return b })
        guard clamped != bookmarks else { return }
        bookmarks = clamped
        save()
    }

    /// 같은 줄은 먼저 온 것만 남긴다 (정렬 유지)
    private static func dedupe(_ list: [Bookmark]) -> [Bookmark] {
        var seen = Set<Int>()
        return list.sorted { $0.line < $1.line }.filter { seen.insert($0.line).inserted }
    }

    private func load() {
        if let list = Self.read(storeURL) { bookmarks = list; return }
        if let list = Self.read(Self.legacySidecar(for: fileURL)) {   // 1회 이전: 사이드카 → Application Support
            bookmarks = list
            save()
        }
    }

    private static func read(_ url: URL) -> [Bookmark]? {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601     // save() 가 iso8601 로 쓰므로 같은 전략으로 읽어야 한다
        guard let data = try? Data(contentsOf: url),
              let list = try? dec.decode([Bookmark].self, from: data) else { return nil }
        return list.sorted { $0.line < $1.line }
    }

    private func save() {
        let fm = FileManager.default
        if bookmarks.isEmpty { try? fm.removeItem(at: storeURL); return }
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(bookmarks) { try? data.write(to: storeURL, options: [.atomic]) }
    }
}
