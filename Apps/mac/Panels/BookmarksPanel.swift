import SwiftUI
import HyperCore

struct BookmarksPanel: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button { model.toggleBookmarkAtCaret() } label: { Label("Bookmark Current Line", systemImage: "bookmark") }
                    .controlSize(.small)
                    .help("⌘F2 — toggle a bookmark on the current line")
                Spacer()
                Text("\(model.bookmarks.bookmarks.count) bookmarks")
                    .font(.caption).foregroundStyle(theme.foregroundMuted.color)
            }
            if model.bookmarks.bookmarks.isEmpty {
                Text("No bookmarks. Press ⌘F2 in the editor to bookmark the current line, then F2 / ⌥F2 to jump to the next / previous bookmark.")
                    .font(.caption).foregroundStyle(theme.foregroundMuted.color).padding(.top, 4)
                Spacer()
            } else {
                List {
                    ForEach(model.bookmarks.bookmarks) { b in
                        BookmarkRow(bookmark: b, theme: theme) { model.bookmarks.rename(id: b.id, name: $0) }
                            .contentShape(Rectangle())
                            .onTapGesture { model.jump(to: b) }
                            .contextMenu {
                                Button("Go") { model.jump(to: b) }
                                Button("Delete", role: .destructive) { model.bookmarks.remove(id: b.id) }
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
            Text(verbatim: "\(bookmark.line)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.foregroundDim.color)
                .frame(width: 52, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name (optional)", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.foreground.color)
                    .onSubmit { onRename(name) }
                    .onAppear { name = bookmark.name }
                Text(bookmark.preview.isEmpty ? String(localized: "(blank line)") : bookmark.preview)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.foregroundMuted.color)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
