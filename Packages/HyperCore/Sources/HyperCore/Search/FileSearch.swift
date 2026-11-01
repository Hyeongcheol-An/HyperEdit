import Foundation

public struct FileSearchHit: Identifiable, Hashable, Sendable {
    public let url: URL
    public let line: Int
    public let column: Int
    public let lineText: String
    public let matchInLine: NSRange
    public var id: String { "\(url.path):\(line):\(column)" }
    public var fileName: String { url.lastPathComponent }
}

public struct FileSearchResult: Sendable {
    public var hits: [FileSearchHit] = []
    public var filesScanned = 0
    public var filesMatched = 0
    public var truncated = false
    public init() {}
}

/// UltraEdit "Find in Files": 폴더(하위 포함)의 텍스트 파일에서 검색. 마스크는 `*.md;*.txt` 식(`;` 구분, 비우면 전체).
public enum FileSearch {
    public static func matches(mask: String, fileName: String) -> Bool {
        let parts = mask.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if parts.isEmpty || parts == ["*"] || parts == ["*.*"] { return true }
        return parts.contains { p in
            let pattern = "^" + NSRegularExpression.escapedPattern(for: p).replacingOccurrences(of: "\\*", with: ".*").replacingOccurrences(of: "\\?", with: ".") + "$"
            return fileName.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    static func looksBinary(_ data: Data) -> Bool {
        let head = data.prefix(8192)
        return head.contains(0)
    }

    public static func search(_ query: String, in directory: URL, mask: String = "", options: SearchOptions, recursive: Bool = true,
                              maxFileSize: Int = 20_000_000, limit: Int = 5000, perFileLimit: Int = 500,
                              redactSecrets: Bool = false, isCancelled: () -> Bool = { false }) throws -> FileSearchResult {
        var result = FileSearchResult()
        guard !query.isEmpty else { return result }
        _ = try SearchEngine.search(query, in: "", index: LineIndex(), options: options)   // 정규식 검증
        let fm = FileManager.default
        var opts: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !recursive { opts.insert(.skipsSubdirectoryDescendants) }
        guard let en = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey], options: opts) else { return result }
        for case let url as URL in en {
            if isCancelled() { result.truncated = true; break }
            guard let rv = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), rv.isRegularFile == true else { continue }
            if let size = rv.fileSize, size > maxFileSize { continue }
            guard matches(mask: mask, fileName: url.lastPathComponent) else { continue }
            guard let data = try? Data(contentsOf: url), !looksBinary(data) else { continue }
            result.filesScanned += 1
            let text = String(decoding: data, as: UTF8.self)
            var hits = (try? SearchEngine.search(query, in: text, index: LineIndex(text: text), options: options, limit: perFileLimit)) ?? []
            // secrets: 비밀 블록 안의 줄은 결과 목록에 평문으로 올리지 않는다 (줄 번호·일치 위치는 그대로) — 펜스가 있을 때만 스캔
            if redactSecrets, !hits.isEmpty, text.contains("secret") { hits = SecretScanner.redacting(hits: hits, in: text) }
            if !hits.isEmpty {
                result.filesMatched += 1
                for h in hits {
                    result.hits.append(FileSearchHit(url: url, line: h.line, column: h.column, lineText: h.lineText, matchInLine: h.matchInLine))
                    if result.hits.count >= limit { result.truncated = true; return result }
                }
            }
        }
        return result
    }
}
