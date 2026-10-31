import SwiftUI
import HyperCore

struct BookmarksPanel: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { model.toggleBookmarkAtCaret() } label: { Label("현재 줄 북마크", systemImage: "bookmark") }
                    .controlSize(.small)
                    .help("⌘F2 — 현재 줄 북마크 토글")
                Spacer()
                Text("\(model.bookmarks.bookmarks.count)개")
                    .font(.caption).foregroundStyle(theme.foregroundMuted.color)
            }
            if model.bookmarks.bookmarks.isEmpty {
                Text("북마크가 없습니다. 편집기에서 ⌘F2 로 현재 줄을 북마크하고, F2 / ⌥F2 로 다음·이전 북마크로 이동하세요.")
                    .font(.caption).foregroundStyle(theme.foregroundMuted.color).padding(.top, 4)
                Spacer()
            } else {
                List {
                    ForEach(model.bookmarks.bookmarks) { b in
                        BookmarkRow(bookmark: b, theme: theme) { model.bookmarks.rename(id: b.id, name: $0) }
                            .contentShape(Rectangle())
                            .onTapGesture { model.jump(to: b) }
                            .contextMenu {
                                Button("이동") { model.jump(to: b) }
                                Button("삭제", role: .destructive) { model.bookmarks.remove(id: b.id) }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(8)
        .tint(theme.accent.color)
    }
}

struct BookmarkRow: View {
    let bookmark: Bookmark
    let theme: Theme
    let onRename: (String) -> Void
    @State private var name = ""

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(bookmark.line)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.foregroundDim.color)
                .frame(width: 52, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                TextField("이름 (선택)", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.foreground.color)
                    .onSubmit { onRename(name) }
                    .onAppear { name = bookmark.name }
                Text(bookmark.preview.isEmpty ? "(빈 줄)" : bookmark.preview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.foregroundMuted.color)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
