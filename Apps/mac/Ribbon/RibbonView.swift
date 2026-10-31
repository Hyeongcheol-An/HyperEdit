import SwiftUI
import HyperCore

/// UltraEdit v26+ 리본: 탭 스트립(+빠른 실행) / 그룹별 큰 버튼·작은 버튼
struct RibbonView: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: 6)    // 탭 줄은 제목 표시줄(신호등) 아래에 놓이므로 큰 여백이 필요 없다
                ForEach(RibbonTab.allCases) { tab in
                    RibbonTabButton(title: tab.label, selected: model.ribbonTab == tab, theme: theme) { model.ribbonTab = tab }
                }
                Spacer()
                HStack(spacing: 2) {
                    QuickButton(systemImage: "square.and.arrow.down", help: "Save (⌘S)", theme: theme) { model.saveNow() }
                    QuickButton(systemImage: "arrow.uturn.backward", help: "Undo (⌘Z)", theme: theme) { model.send(.undo) }
                    QuickButton(systemImage: "arrow.uturn.forward", help: "Redo (⇧⌘Z)", theme: theme) { model.send(.redo) }
                }
                .padding(.trailing, 6)
                // 문서 이름은 문서 탭에 있으므로 여기엔 폴더를 보여 준다 (전체 경로는 툴팁)
                Text(model.rootDirectory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.system(size: 11)).foregroundStyle(theme.foregroundMuted.color)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 320, alignment: .trailing)
                    .help(model.document.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .padding(.trailing, 12)
            }
            .frame(height: 30)
            .background(theme.backgroundAlt.color)

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    switch model.ribbonTab {
                    case .home: HomeTab(theme: theme)
                    case .edit: EditTab(theme: theme)
                    case .layout: LayoutTab(theme: theme)
                    case .advanced: AdvancedTab(theme: theme)
                    case .window: WindowTab(theme: theme)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .frame(height: 96)
            .background(theme.background.color)
            .overlay(alignment: .bottom) { theme.border.color.frame(height: 1) }
        }
    }
}

// MARK: - 탭 내용
// title/help 는 LocalizedStringKey — 영어 리터럴이 카탈로그 키, 한국어는 Localizable.xcstrings 의 번역.
// 작은 버튼은 128pt 한 줄이므로 영어 제목은 16자 안팎으로 유지한다.

private struct HomeTab: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    var body: some View {
        RibbonGroup(title: "Clipboard", theme: theme) {
            RibbonBigButton(title: "Paste", systemImage: "doc.on.clipboard", help: "⌘V", theme: theme) { model.send(.paste) }
            RibbonStack {
                RibbonSmallButton(title: "Cut", systemImage: "scissors", help: "⌘X", theme: theme) { model.send(.cut) }
                RibbonSmallButton(title: "Copy", systemImage: "doc.on.doc", help: "⌘C", theme: theme) { model.send(.copy) }
                RibbonSmallButton(title: "Select All", systemImage: "selection.pin.in.out", help: "⌘A", theme: theme) { model.send(.selectAll) }
            }
        }
        RibbonGroup(title: "Find", theme: theme) {
            RibbonBigButton(title: "Find", systemImage: "magnifyingglass", help: "⌘F — results are listed in the 'Find Results' panel below", theme: theme) { model.findInEditor() }
            RibbonStack {
                RibbonSmallButton(title: "Replace", systemImage: "arrow.left.arrow.right", help: "⌘R", theme: theme) { model.showReplace() }
                RibbonSmallButton(title: "Find in Files", systemImage: "doc.text.magnifyingglass", help: "⇧⌘F — folder and file mask", theme: theme) { model.showFindInFiles() }
                RibbonSmallButton(title: "Go to Line", systemImage: "arrow.right.to.line", help: "⌘L", theme: theme) { model.showGoToLine = true }
            }
        }
        RibbonGroup(title: "Insert", theme: theme) {
            RibbonBigButton(title: "Date/Time", systemImage: "calendar.badge.clock", help: "Insert a timestamp heading — ## 2026-10-30 (Fri) 14:05 (F7)", theme: theme) { model.insertTimestamp() }
            RibbonStack {
                RibbonSmallButton(title: "Toggle Bookmark", systemImage: "bookmark", help: "Bookmark the current line on/off (⌘F2)", theme: theme) { model.toggleBookmarkAtCaret() }
                RibbonSmallButton(title: "Next Bookmark", systemImage: "bookmark.fill", help: "Go to the next bookmark (F2)", theme: theme) { model.nextBookmark() }
                RibbonSmallButton(title: "Prev. Bookmark", systemImage: "bookmark.slash", help: "Go to the previous bookmark (⌥F2)", theme: theme) { model.previousBookmark() }
            }
        }
        RibbonGroup(title: "Mode", theme: theme) {
            RibbonBigToggle(title: "Column Mode", systemImage: "rectangle.split.3x1", help: "⌥C — drag or ⇧arrows select a rectangle; typing applies to every line", isOn: $model.columnMode, theme: theme)
            RibbonStack {
                RibbonSmallToggle(title: "Word Wrap", systemImage: "text.word.spacing", help: "Word wrap (⌥Z)", isOn: $model.wordWrap, theme: theme)
                RibbonSmallToggle(title: "Line Numbers", systemImage: "list.number", help: "Line number gutter (⌥⌘L)", isOn: $model.showLineNumbers, theme: theme)
            }
        }
        RibbonGroup(title: "File", theme: theme) {
            RibbonBigButton(title: "Save", systemImage: "square.and.arrow.down", help: "Save now (⌘S) — autosaves 2 seconds after you stop typing", theme: theme) { model.saveNow() }
            RibbonStack {
                RibbonSmallButton(title: "New Document…", systemImage: "doc.badge.plus", help: "Create and open an empty text file (⌘N)", theme: theme) { model.newDocument() }
                RibbonSmallButton(title: "Open…", systemImage: "folder", help: "Open a text file (⌘O)", theme: theme) { model.presentOpenPanel() }
                RibbonSmallButton(title: "Reveal in Finder", systemImage: "macwindow", help: "Select the current file in Finder", theme: theme) { model.revealInFinder() }
            }
        }
    }
}

private struct EditTab: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    var body: some View {
        RibbonGroup(title: "Lines", theme: theme) {
            RibbonBigButton(title: "Delete Line", systemImage: "trash", help: "⇧⌘K", theme: theme) { model.textTool(.deleteLine) }
            RibbonStack {
                RibbonSmallButton(title: "Duplicate Line", systemImage: "plus.square.on.square", help: "⇧⌘D", theme: theme) { model.textTool(.duplicateLine) }
                RibbonSmallButton(title: "Move Up", systemImage: "arrow.up", help: "⌥↑", theme: theme) { model.textTool(.moveLineUp) }
                RibbonSmallButton(title: "Move Down", systemImage: "arrow.down", help: "⌥↓", theme: theme) { model.textTool(.moveLineDown) }
            }
            RibbonStack {
                RibbonSmallButton(title: "Join Lines", systemImage: "arrow.triangle.merge", help: "Join the selected lines into one (with no selection: current line + next line) (⇧⌘J)", theme: theme) { model.textTool(.joinLines) }
                RibbonSmallButton(title: "Number Lines", systemImage: "list.number", help: "Prefix the selected lines with 1. 2. 3.", theme: theme) { model.textTool(.numberLines) }
                RibbonSmallButton(title: "Reverse", systemImage: "arrow.up.arrow.down", help: "Reverse the order of the selected lines", theme: theme) { model.textTool(.reverseLines) }
            }
        }
        RibbonGroup(title: "Case", theme: theme) {
            RibbonStack {
                RibbonSmallButton(title: "Uppercase", systemImage: "textformat.size.larger", help: "Selection (or current line) to uppercase", theme: theme) { model.textTool(.upper) }
                RibbonSmallButton(title: "Lowercase", systemImage: "textformat.size.smaller", help: "Selection (or current line) to lowercase", theme: theme) { model.textTool(.lower) }
                RibbonSmallButton(title: "Capitalize", systemImage: "textformat", help: "Capitalize the first letter of each word", theme: theme) { model.textTool(.capitalize) }
            }
            RibbonStack {
                RibbonSmallButton(title: "Invert Case", systemImage: "arrow.2.squarepath", help: "Swap uppercase ↔ lowercase", theme: theme) { model.textTool(.invertCase) }
            }
        }
        RibbonGroup(title: "Sort", theme: theme) {
            RibbonBigButton(title: "Ascending", systemImage: "arrow.up.arrow.down.square", help: "Sort the selected lines alphabetically", theme: theme) { model.textTool(.sortAsc) }
            RibbonStack {
                RibbonSmallButton(title: "Descending", systemImage: "arrow.down.square", help: "Sort the selected lines in reverse order", theme: theme) { model.textTool(.sortDesc) }
                RibbonSmallButton(title: "Numeric Sort", systemImage: "number.square", help: "Sort by the number at the start of each line", theme: theme) { model.textTool(.sortNumeric) }
                RibbonSmallButton(title: "Deduplicate", systemImage: "rectangle.stack.badge.minus", help: "Keep only the first of identical lines", theme: theme) { model.textTool(.dedupe) }
            }
        }
        RibbonGroup(title: "Whitespace", theme: theme) {
            RibbonStack {
                RibbonSmallButton(title: "Trim Trailing", systemImage: "text.alignleft", help: "Remove spaces and tabs at the end of lines", theme: theme) { model.textTool(.trimTrailing) }
                RibbonSmallButton(title: "Trim Both Ends", systemImage: "text.aligncenter", help: "Remove spaces and tabs at both ends of lines", theme: theme) { model.textTool(.trimBoth) }
                RibbonSmallButton(title: "Remove Blanks", systemImage: "rectangle.compress.vertical", help: "Delete empty or whitespace-only lines", theme: theme) { model.textTool(.removeBlank) }
            }
            RibbonStack {
                RibbonSmallButton(title: "Tabs → Spaces", systemImage: "arrow.right.to.line.compact", help: "Tabs to 4 spaces", theme: theme) { model.textTool(.tabsToSpaces) }
                RibbonSmallButton(title: "Spaces → Tabs", systemImage: "arrow.left.to.line.compact", help: "Leading groups of 4 spaces to tabs", theme: theme) { model.textTool(.spacesToTabs) }
            }
        }
        RibbonGroup(title: "Column & Multi-Caret", theme: theme) {
            RibbonBigButton(title: "Insert Number", systemImage: "number.square", help: "Insert Number — a sequence number on each line of the column selection (⌥C then ⇧↓)", theme: theme) { model.showInsertNumber = true }
            RibbonStack {
                RibbonSmallToggle(title: "Column Mode", systemImage: "rectangle.split.3x1", help: "⌥C", isOn: $model.columnMode, theme: theme)
                RibbonSmallButton(title: "Add Next Match", systemImage: "plus.magnifyingglass", help: "⌘D — add the next occurrence of the selection as a caret", theme: theme) { model.send(.addNextOccurrence) }
                RibbonSmallButton(title: "Select Matches", systemImage: "checkmark.circle", help: "⌥⌘A — turn every find result into a caret", enabled: !model.searchHits.isEmpty, theme: theme) { model.selectAllMatches() }
            }
        }
        RibbonGroup(title: "Tools", theme: theme) {
            RibbonBigButton(title: "Calculate", systemImage: "plus.forwardslash.minus", help: "Evaluate the selection or current line and append ⇒ result (⌃⌘=)", theme: theme) { model.textTool(.calculate) }
            RibbonStack {
                RibbonSmallButton(title: "Align Columns", systemImage: "tablecells", help: "Pad tab- or pipe-separated columns so they line up (⌃⌘T)", theme: theme) { model.textTool(.alignColumns) }
            }
        }
    }
}

private struct LayoutTab: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    var body: some View {
        RibbonGroup(title: "Theme", theme: theme) {
            Menu {
                Button { model.themes.setFollowsSystem(true) } label: {
                    if model.themes.followsSystem { Label("Follow System Appearance (Hyper Light / Dark)", systemImage: "checkmark") } else { Text("Follow System Appearance (Hyper Light / Dark)") }
                }
                Divider()
                Section("Light") {
                    ForEach(model.themes.lightThemes) { t in
                        Button { model.themes.select(id: t.id) } label: {
                            if t.id == theme.id { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                        }
                    }
                }
                Section("Dark") {
                    ForEach(model.themes.darkThemes) { t in
                        Button { model.themes.select(id: t.id) } label: {
                            if t.id == theme.id { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                        }
                    }
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "paintpalette").font(.system(size: 22)).frame(height: 30)
                    Text("Theme").font(.system(size: 10.5))
                }
                .frame(width: 60, height: 64)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .foregroundStyle(theme.foreground.color)
            RibbonStack {
                RibbonSmallButton(title: "Next Theme", systemImage: "chevron.right", help: "Next theme (⌥⌘])", theme: theme) { model.themes.selectNext(step: 1) }
                RibbonSmallButton(title: "Previous Theme", systemImage: "chevron.left", help: "Previous theme (⌥⌘[)", theme: theme) { model.themes.selectNext(step: -1) }
                Text(model.themes.followsSystem ? String(localized: "\(theme.name) · System") : theme.name).font(.system(size: 10)).foregroundStyle(theme.foregroundMuted.color).frame(width: 118, alignment: .leading).lineLimit(1)
            }
        }
        RibbonGroup(title: "Panels", theme: theme) {
            RibbonStack {
                RibbonSmallToggle(title: "Sidebar", systemImage: "sidebar.left", help: "Sidebar — Files, Outline, Timeline (⌘1)", isOn: $model.showFileView, theme: theme)
                RibbonSmallToggle(title: "Bottom Panel", systemImage: "rectangle.bottomthird.inset.filled", help: "Bottom panel — Find Results, Bookmarks, Output (⌘2)", isOn: $model.showBottomPanel, theme: theme)
                RibbonSmallToggle(title: "Line Numbers", systemImage: "list.number", help: "Line number gutter (⌥⌘L)", isOn: $model.showLineNumbers, theme: theme)
            }
            RibbonStack {
                RibbonSmallButton(title: "File View", systemImage: "folder", help: "File tree of the current document's folder (⌘1)", theme: theme) { model.leftTab = .fileView; model.showFileView = true }
                RibbonSmallButton(title: "Outline", systemImage: "list.bullet.indent", help: "Headings, [Title] lines, 가./나. and numbered items (⌘3)", theme: theme) { model.showOutline() }
                RibbonSmallButton(title: "Timeline", systemImage: "calendar", help: "Timestamp and date lines grouped by month (⌘4)", theme: theme) { model.showTimeline() }
            }
            RibbonStack {
                RibbonSmallToggle(title: "Word Wrap", systemImage: "text.word.spacing", help: "Word wrap (⌥Z)", isOn: $model.wordWrap, theme: theme)
            }
        }
        RibbonGroup(title: "Font Size", theme: theme) {
            RibbonBigButton(title: "Larger", systemImage: "textformat.size.larger", help: "Larger text (⌘=)", theme: theme) { model.adjustFontSize(1) }
            RibbonStack {
                RibbonSmallButton(title: "Smaller", systemImage: "textformat.size.smaller", help: "Smaller text (⌘-)", theme: theme) { model.adjustFontSize(-1) }
                RibbonSmallButton(title: "Default (14pt)", systemImage: "1.magnifyingglass", help: "Reset to the default size (⌘0)", theme: theme) { model.resetFontSize() }
                RibbonSmallButton(title: "Font Settings…", systemImage: "gearshape", help: "Font and Hangul width settings (⌘,)", theme: theme) { model.openSettings() }
            }
        }
    }
}

private struct AdvancedTab: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    var body: some View {
        RibbonGroup(title: "Settings", theme: theme) {
            RibbonBigButton(title: "Settings", systemImage: "gearshape", help: "Preferences (⌘,)", theme: theme) { model.openSettings() }
            RibbonStack {
                RibbonSmallButton(title: "Snapshot Folder", systemImage: "clock.arrow.circlepath", help: "Open the folder of automatic pre-save backups", theme: theme) { model.openSnapshotFolder() }
                RibbonSmallButton(title: "Reload from Disk", systemImage: "arrow.clockwise", help: "Re-read the file — unsaved changes are discarded", theme: theme) { model.reloadFromDisk() }
                RibbonSmallButton(title: "Default Document", systemImage: "house", help: "Open ~/Documents/HyperEdit/notes.md", theme: theme) { model.openDefaultDocument() }
            }
        }
    }
}

private struct WindowTab: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    var body: some View {
        RibbonGroup(title: "Window", theme: theme) {
            RibbonBigButton(title: "Full Screen", systemImage: "arrow.up.left.and.arrow.down.right", help: "Toggle full screen (⌃⌘F)", theme: theme) { model.toggleFullScreen() }
            RibbonStack {
                RibbonSmallToggle(title: "Sidebar", systemImage: "sidebar.left", help: "Sidebar (⌘1)", isOn: $model.showFileView, theme: theme)
                RibbonSmallToggle(title: "Bottom Panel", systemImage: "rectangle.bottomthird.inset.filled", help: "Bottom panel (⌘2)", isOn: $model.showBottomPanel, theme: theme)
                RibbonSmallToggle(title: "Line Numbers", systemImage: "list.number", help: "Line number gutter (⌥⌘L)", isOn: $model.showLineNumbers, theme: theme)
            }
        }
    }
}

// MARK: - 구성 요소

struct RibbonTabButton: View {
    let title: LocalizedStringKey
    let selected: Bool
    let theme: Theme
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? theme.foreground.color : theme.foregroundMuted.color)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(selected ? theme.background.color : Color.clear, ignoresSafeAreaEdges: [])
                .overlay(alignment: .top) { if selected { theme.accent.color.frame(height: 2) } }
        }
        .buttonStyle(.plain)
    }
}

struct QuickButton: View {
    let systemImage: String
    let help: LocalizedStringKey
    let theme: Theme
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 12)).frame(width: 24, height: 22)
        }
        .buttonStyle(.plain).foregroundStyle(theme.foregroundMuted.color).help(help)
    }
}

struct RibbonGroup<Content: View>: View {
    let title: LocalizedStringKey
    let theme: Theme
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(spacing: 2) {
            HStack(alignment: .top, spacing: 2) { content() }
                .frame(maxHeight: .infinity, alignment: .top)
            Text(title).font(.system(size: 10)).foregroundStyle(theme.foregroundMuted.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .overlay(alignment: .trailing) { theme.border.color.frame(width: 1).padding(.vertical, 8) }
    }
}

struct RibbonStack<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { VStack(alignment: .leading, spacing: 1) { content() } }
}

struct RibbonBigButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var help: LocalizedStringKey = ""
    var enabled: Bool = true
    let theme: Theme
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage).font(.system(size: 22)).frame(height: 30)
                Text(title).font(.system(size: 10.5)).multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(width: 60, height: 64)
            .background(hover && enabled ? theme.backgroundElevated.color : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? theme.foreground.color : theme.foregroundDim.color)
        .disabled(!enabled)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct RibbonSmallButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var help: LocalizedStringKey = ""
    var enabled: Bool = true
    let theme: Theme
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 11)).frame(width: 16)
                Text(title).font(.system(size: 11)).lineLimit(1)
            }
            .padding(.horizontal, 5)
            .frame(width: 128, height: 20, alignment: .leading)
            .background(hover && enabled ? theme.backgroundElevated.color : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? theme.foreground.color : theme.foregroundDim.color)
        .disabled(!enabled)
        .onHover { hover = $0 }
        .help(help)
    }
}

struct RibbonSmallToggle: View {
    let title: LocalizedStringKey
    let systemImage: String
    var help: LocalizedStringKey = ""
    @Binding var isOn: Bool
    let theme: Theme
    @State private var hover = false
    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 11)).frame(width: 16)
                Text(title).font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 0)
                if isOn { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.accent.color) }
            }
            .padding(.horizontal, 5)
            .frame(width: 128, height: 20, alignment: .leading)
            .background(isOn ? theme.accent.color.opacity(0.18) : (hover ? theme.backgroundElevated.color : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.foreground.color)
        .onHover { hover = $0 }
        .help(help)
    }
}


struct RibbonBigToggle: View {
    let title: LocalizedStringKey
    let systemImage: String
    var help: LocalizedStringKey = ""
    @Binding var isOn: Bool
    let theme: Theme
    @State private var hover = false
    var body: some View {
        Button { isOn.toggle() } label: {
            VStack(spacing: 3) {
                Image(systemName: systemImage).font(.system(size: 22)).frame(height: 30)
                Text(title).font(.system(size: 10.5)).multilineTextAlignment(.center).lineLimit(2)
            }
            .frame(width: 60, height: 64)
            .background(isOn ? theme.accent.color.opacity(0.22) : (hover ? theme.backgroundElevated.color : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(isOn ? theme.accent.color : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.foreground.color)
        .onHover { hover = $0 }
        .help(help)
    }
}
