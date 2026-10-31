import SwiftUI
import HyperCore

/// UltraEdit 하단 도킹 창: 찾기 결과 / 북마크 / 출력
struct BottomPanel: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(BottomTab.allCases) { tab in
                    Button { model.bottomTab = tab } label: {
                        HStack(spacing: 5) {
                            Image(systemName: tab.systemImage).font(.system(size: 10))
                            Text(tab.label).font(.system(size: 11, weight: model.bottomTab == tab ? .semibold : .regular))
                            if tab == .findResults, !model.searchHits.isEmpty {
                                Text(verbatim: "\(model.searchHits.count)").font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 4).background(theme.accent.color.opacity(0.25)).clipShape(Capsule())
                            }
                        }
                        .padding(.horizontal, 10).frame(height: 24)
                        .foregroundStyle(model.bottomTab == tab ? theme.foreground.color : theme.foregroundMuted.color)
                        .background(model.bottomTab == tab ? theme.background.color : Color.clear)
                        .overlay(alignment: .bottom) { if model.bottomTab == tab { theme.accent.color.frame(height: 2) } }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button { model.showBottomPanel = false } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(theme.foregroundMuted.color).padding(.trailing, 8).help("Close (⌘2)")
            }
            .frame(height: 24)
            .background(theme.backgroundAlt.color)
            .overlay(alignment: .top) { theme.border.color.frame(height: 1) }

            switch model.bottomTab {
            case .findResults: SearchPanel(theme: theme)
            case .bookmarks: BookmarksPanel(theme: theme)
            case .output: OutputPanel(theme: theme)
            }
        }
        .background(theme.background.color)
    }
}

struct OutputPanel: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()

    var body: some View {
        ScrollViewReader { proxy in
            List(model.output) { line in
                HStack(alignment: .top, spacing: 8) {
                    Text(Self.time.string(from: line.time)).foregroundStyle(theme.foregroundDim.color)
                    Text(line.text).foregroundStyle(line.isError ? theme.errorColor.color : theme.foreground.color)
                }
                .font(.system(size: 11, design: .monospaced))
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                .id(line.id)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .onChange(of: model.output.count) { _, _ in
                if let last = model.output.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }
}
