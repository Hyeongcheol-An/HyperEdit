import SwiftUI
import HyperCore

struct FileNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]?
    /// 심볼릭 링크를 푼 경로 — 문서 url(resolvingSymlinksInPath) 과 같은 기준으로 비교·선택한다
    let id: String
    var name: String { url.lastPathComponent }

    init(url: URL, isDirectory: Bool, children: [FileNode]?) {
        self.url = url; self.isDirectory = isDirectory; self.children = children
        id = url.resolvingSymlinksInPath().path
    }

    var isText: Bool { !TextFileDetector.hasBinaryExtension(url) }

    func find(_ id: String) -> FileNode? {
        if self.id == id { return self }
        for c in children ?? [] { if let f = c.find(id) { return f } }
        return nil
    }
}

enum FileTree {
    /// 숨김 파일 제외, 폴더 먼저, 이름순. depth 만큼 하위 폴더 미리 로드.
    static func load(_ dir: URL, depth: Int = 2) -> [FileNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        let nodes: [FileNode] = items.map { u in
            let isDir = (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return FileNode(url: u, isDirectory: isDir, children: isDir ? (depth > 0 ? load(u, depth: depth - 1) : []) : nil)
        }
        return nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }
}

/// UltraEdit File View: 현재 문서 폴더 트리. 한 번 클릭(또는 방향키 선택)으로 바로 연다 — Zed 와 같은 동작.
/// (이전의 더블탭+싱글탭 제스처 조합은 싱글 클릭 반응이 더블클릭 판정 대기(0.5s) 뒤에야 오고, 파일은 더블클릭해야만 열렸다.)
struct FileViewPanel: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    @State private var nodes: [FileNode] = []
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(model.rootDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 10)).foregroundStyle(theme.foregroundDim.color).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button { reload() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(theme.foregroundMuted.color).help("Refresh")
            }
            .padding(.horizontal, 8).frame(height: 24)

            List(selection: $selected) {
                OutlineGroup(nodes, children: \.children) { node in
                    HStack(spacing: 5) {
                        Image(systemName: node.isDirectory ? "folder" : (node.isText ? "doc.text" : "doc"))
                            .font(.system(size: 11))
                            .foregroundStyle(node.isDirectory ? theme.accent.color : theme.foregroundMuted.color)
                        Text(node.name)
                            .font(.system(size: 11.5, weight: node.id == currentID ? .semibold : .regular))
                            .foregroundStyle(node.id == currentID ? theme.accent.color : (node.isText || node.isDirectory ? theme.foreground.color : theme.foregroundMuted.color))
                            .lineLimit(1)
                    }
                    .tag(node.id)
                    .listRowSeparator(.hidden)
                    .help(node.url.path)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: selected) { _, id in
                guard let id, let node = nodes.lazy.compactMap({ $0.find(id) }).first, !node.isDirectory else { return }
                if id != currentID { model.open(url: node.url) }
            }
            .onChange(of: currentID) { _, id in if selected != id { selected = id } }
        }
        .onAppear { reload(); selected = currentID }
        .onChange(of: model.rootDirectory) { _, _ in reload() }
    }

    private var currentID: String { model.document.url.path }
    private func reload() { nodes = FileTree.load(model.rootDirectory) }
}
