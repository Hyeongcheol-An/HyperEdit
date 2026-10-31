import Foundation

/// 텍스트로 열어도 되는 파일인지 판별. 확장자가 명백한 바이너리가 아니고, 앞 8KB 에 NUL 바이트가 없어야 한다.
/// (PDF·이미지를 본문으로 올리면 TextKit 레이아웃이 수 초 걸리고 내용도 의미가 없다.)
public enum TextFileDetector {
    public static let binaryExtensions: Set<String> = [
        "pdf", "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "svgz", "ico", "icns",
        "zip", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg", "pkg", "app",
        "mov", "mp4", "m4v", "mp3", "m4a", "wav", "aac", "flac",
        "pptx", "docx", "xlsx", "doc", "xls", "ppt", "key", "numbers", "pages",
        "sqlite", "db", "bin", "o", "a", "dylib", "so", "class", "jar", "pyc",
        "ttf", "otf", "ttc", "woff", "woff2",
    ]

    public static func hasBinaryExtension(_ url: URL) -> Bool {
        binaryExtensions.contains(url.pathExtension.lowercased())
    }

    public static func isLikelyText(_ url: URL) -> Bool {
        if hasBinaryExtension(url) { return false }
        guard let h = try? FileHandle(forReadingFrom: url) else { return true }
        defer { try? h.close() }
        let head = (try? h.read(upToCount: 8192)) ?? Data()
        return !head.contains(0)
    }
}
