import SwiftUI
import HyperCore

/// UltraEdit 좌측 도킹: File View / 아웃라인 / 타임라인 탭
struct LeftDock: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(LeftTab.allCases) { tab in
                    Button { model.leftTab = tab } label: {
                        HStack(spacing: 4) {
                            Image(systemName: tab.systemImage).font(.system(size: 10))
                            Text(tab.label).font(.system(size: 11, weight: model.leftTab == tab ? .semibold : .regular))
                        }
                        .padding(.horizontal, 8).frame(height: 24)
                        .foregroundStyle(model.leftTab == tab ? theme.foreground.color : theme.foregroundMuted.color)
                        .background(model.leftTab == tab ? theme.background.color : Color.clear)
                        .overlay(alignment: .top) { if model.leftTab == tab { theme.accent.color.frame(height: 2) } }
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button { model.showFileView = false } label: { Image(systemName: "xmark").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(theme.foregroundMuted.color).padding(.trailing, 8).help("Close sidebar (⌘1)")
            }
            .frame(height: 24)
            .background(theme.backgroundAlt.color)
            .overlay(alignment: .bottom) { theme.border.color.frame(height: 1) }

            switch model.leftTab {
            case .fileView: FileViewPanel(theme: theme)
            case .outline: OutlinePanel(theme: theme)
            case .timeline: TimelinePanel(theme: theme)
            }
        }
        .background(theme.backgroundAlt.color)
        .overlay(alignment: .trailing) { theme.border.color.frame(width: 1) }
    }
}

/// 아웃라인: 헤딩 · [제목] · 가/나/다 · 번호 항목. 현재 줄 위의 가장 가까운 항목 강조.
struct OutlinePanel: View {
    @EnvironmentObject var model: AppModel
    /// 캐럿 줄만 따라간다 — EditorCaret 전체를 구독하면 키 입력(열 이동)마다 목록이 다시 평가된다 (perf)
    @State private var caretLine = 1
    let theme: Theme
    @State private var filter = ""

    var body: some View {
        let current = model.outline.lastIndexedLine(atOrBefore: caretLine)
        let items = filter.isEmpty ? model.outline : model.outline.filter { $0.title.localizedCaseInsensitiveContains(filter) }
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 10)).foregroundStyle(theme.foregroundMuted.color)
                TextField("Filter outline", text: $filter).textFieldStyle(.plain).font(.system(size: 11))
                Text(verbatim: "\(items.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.foregroundDim.color)
            }
            .padding(.horizontal, 8).frame(height: 24)
            ScrollViewReader { proxy in
                List(items) { item in
                    HStack(spacing: 4) {
                        Image(systemName: icon(item.kind)).font(.system(size: 9)).foregroundStyle(theme.foregroundDim.color).frame(width: 12)
                        Text(item.title).font(.system(size: 11.5, weight: item.level <= 2 ? .semibold : .regular)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(verbatim: "\(item.line)").font(.system(size: 10, design: .monospaced)).foregroundStyle(theme.foregroundDim.color)
                    }
                    .padding(.leading, CGFloat(max(0, item.level - 1)) * 10)
                    .foregroundStyle(theme.foreground.color)
                    .contentShape(Rectangle())
                    .onTapGesture { model.jump(toLine: item.line) }
                    .listRowBackground(item.id == current ? theme.accent.color.opacity(0.14) : Color.clear)
                    .listRowSeparator(.hidden)
                    .id(item.id)
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                .onChange(of: current) { _, c in if let c, filter.isEmpty { withAnimation { proxy.scrollTo(c, anchor: .center) } } }
            }
            if model.outline.isEmpty {
                Text("Headings (##), [Title] lines, 가./나. items and 1) items appear in the outline.")
                    .font(.system(size: 10.5)).foregroundStyle(theme.foregroundMuted.color).padding(8)
            }
        }
        .onReceive(model.caret.$line.removeDuplicates()) { caretLine = $0 }
    }

    private func icon(_ k: OutlineItem.Kind) -> String {
        switch k { case .heading: "number"; case .bracket: "tag"; case .hangul: "a.circle"; case .numbered: "1.circle" }
    }
}

/// 타임라인: 타임스탬프 헤딩(F7)과 날짜로 시작하는 줄을 연·월로 묶어 최신순 표시
struct TimelinePanel: View {
    @EnvironmentObject var model: AppModel
    @State private var caretLine = 1   // 캐럿 줄만 (perf — OutlinePanel 참고)
    let theme: Theme
    @State private var collapsed: Set<String> = []

    private var groups: [(key: String, items: [TimelineItem])] {
        let d = Dictionary(grouping: model.timeline, by: \.monthKey)
        return d.keys.sorted(by: >).map { ($0, d[$0]!.sorted { $0.line > $1.line }) }
    }

    var body: some View {
        let current = model.timeline.lastIndexedLine(atOrBefore: caretLine)
        VStack(spacing: 0) {
            HStack {
                Text("\(model.timeline.count) entries · \(groups.count) months").font(.system(size: 10.5, design: .monospaced)).foregroundStyle(theme.foregroundMuted.color)
                Spacer()
                Button("Insert Timestamp") { model.insertTimestamp() }.controlSize(.small).help("F7 — insert a `## date (weekday) hh:mm` heading at the caret").tint(theme.accent.color)
            }
            .padding(.horizontal, 8).frame(height: 24)
            List {
                ForEach(groups, id: \.key) { g in
                    Section {
                        if !collapsed.contains(g.key) {
                            ForEach(g.items) { item in
                                HStack(alignment: .top, spacing: 6) {
                                    VStack(alignment: .trailing, spacing: 0) {
                                        Text(String(item.dateLabel.suffix(5))).font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        if let t = item.timeLabel { Text(t).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(theme.foregroundDim.color) }
                                    }
                                    .frame(width: 40, alignment: .trailing)
                                    .foregroundStyle(item.id == current ? theme.foreground.color : (item.precise ? theme.accent.color : theme.foregroundMuted.color))
                                    Text(item.preview.isEmpty ? String(localized: "(no content)") : item.preview).font(.system(size: 11)).lineLimit(2)
                                        .foregroundStyle(theme.foreground.color)
                                    Spacer(minLength: 2)
                                    Text(verbatim: "\(item.line)").font(.system(size: 9.5, design: .monospaced)).foregroundStyle(theme.foregroundDim.color)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { model.jump(toLine: item.line) }
                                .listRowBackground(item.id == current ? theme.accent.color.opacity(0.14) : Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    } header: {
                        Button {
                            if collapsed.contains(g.key) { collapsed.remove(g.key) } else { collapsed.insert(g.key) }
                        } label: {
                            HStack {
                                Image(systemName: collapsed.contains(g.key) ? "chevron.right" : "chevron.down").font(.system(size: 9))
                                Text(g.key).font(.system(size: 11, weight: .bold, design: .monospaced))
                                Text(verbatim: "\(g.items.count)").font(.system(size: 10)).foregroundStyle(theme.foregroundDim.color)
                                Spacer()
                            }
                            .foregroundStyle(theme.foregroundMuted.color)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            if model.timeline.isEmpty {
                Text("Timestamp headings inserted with F7 (`## 2026-10-30 (Fri) 14:05`) and lines that start with a date are collected here.")
                    .font(.system(size: 10.5)).foregroundStyle(theme.foregroundMuted.color).padding(8)
            }
        }
        .onReceive(model.caret.$line.removeDuplicates()) { caretLine = $0 }
    }
}
