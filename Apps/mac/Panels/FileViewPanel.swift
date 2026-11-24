import SwiftUI
import HyperCore

/// 폴더의 항목 하나 (값 — 백그라운드에서 읽어 메인으로 넘긴다)
struct FileEntry: Hashable, Sendable {
    /// 폴더 경로 + 이름
    let path: String
    /// 심볼릭 링크를 푼 경로 — 문서 url(resolvingSymlinksInPath) 과 같은 기준으로 비교·선택한다
    let id: String
    let name: String
    let isDirectory: Bool
    /// 확장자로 본 텍스트 여부 (아니면 흐리게)
    let isText: Bool

    var url: URL { URL(fileURLWithPath: path, isDirectory: isDirectory) }
}

enum FileTree {
    /// 폴더 한 단계: 숨김 파일 제외, 폴더 먼저, 이름순. 하위 폴더는 읽지 않는다 (펼칠 때 따로 읽는다)
    static func list(_ dir: URL) -> [FileEntry] { sorted(scan(dir)) }

    /// 폴더를 다시 읽는다. 알고 있던 목록(`known`)과 같으면 nil — 정렬도 하지 않는다 (탭으로 돌아올 때마다 부르므로 싸야 한다)
    static func rescan(_ dir: URL, known: [FileEntry]?) -> [FileEntry]? {
        let found = scan(dir)
        if let known, known.count == found.count {
            var byName = [String: FileEntry](minimumCapacity: known.count)   // 이름은 폴더 안에서 하나뿐이다 (id 는 같은 파일을 가리키는 링크끼리 겹친다)
            for e in known { byName[e.name] = e }
            if found.allSatisfy({ byName[$0.name] == $0 }) { return nil }
        }
        return sorted(found)
    }

    /// 정렬하지 않은 한 단계 목록
    private static func scan(_ dir: URL) -> [FileEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return [] }
        func join(_ base: String, _ name: String) -> String { base.hasSuffix("/") ? base + name : base + "/" + name }
        let base = dir.path, resolved = dir.resolvingSymlinksInPath().path
        return urls.map { u in
            let values = try? u.resourceValues(forKeys: keys)
            let name = u.lastPathComponent
            let path = join(base, name)
            // 링크가 아닌 항목의 푼 경로는 "폴더의 푼 경로 + 이름" 이다 — 항목마다 resolvingSymlinksInPath 를 부르면 5,000개에 수십 ms 가 든다
            let id = values?.isSymbolicLink == true ? u.resolvingSymlinksInPath().path : (resolved == base ? path : join(resolved, name))
            return FileEntry(path: path, id: id, name: name, isDirectory: values?.isDirectory ?? false, isText: !TextFileDetector.hasBinaryExtension(u))
        }
    }

    private static func sorted(_ entries: [FileEntry]) -> [FileEntry] {
        entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

/// UltraEdit File View: 현재 문서 폴더 트리. 한 번 클릭(또는 방향키 선택)으로 바로 연다 — Zed 와 같은 동작.
/// (이전의 더블탭+싱글탭 제스처 조합은 싱글 클릭 반응이 더블클릭 판정 대기(0.5s) 뒤에야 오고, 파일은 더블클릭해야만 열렸다.)
/// 목록은 `FileOutline`(NSOutlineView) 이 그린다 — 폴더 읽기·기억·선택 동기화도 거기서 한다.
struct FileViewPanel: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    @State private var refresh = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(model.rootDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 10)).foregroundStyle(theme.foregroundDim.color).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button { refresh &+= 1 } label: { Image(systemName: "arrow.clockwise").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(theme.foregroundMuted.color).help("Refresh")
            }
            .padding(.horizontal, 8).frame(height: 24)

            FileOutline(root: model.rootDirectory, currentID: model.document.url.path, theme: theme, refresh: refresh) { [model] url in
                // 목록을 읽은 뒤 밖에서 지워진 파일 — 열면 빈 파일이 새로 만들어지므로 열지 않는다 (목록은 다음 다시 읽기에서 그 항목을 뺀다)
                guard FileManager.default.fileExists(atPath: url.path) else { return }
                model.open(url: url)
            }
        }
    }
}
