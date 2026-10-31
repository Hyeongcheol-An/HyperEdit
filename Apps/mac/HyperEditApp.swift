import SwiftUI
import AppKit
import HyperCore

@main
struct HyperEditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    init() {
        // 스크린샷·셀프테스트 실행은 사용자 설정(테마·패널·마지막 파일)을 건드리지 않도록 휘발성 저장소를 쓴다 (`--ephemeral` 은 수동 테스트 실행용)
        if LaunchOptions.has("--snapshot") || LaunchOptions.has("--selftest") || LaunchOptions.has("--selftest-open") || LaunchOptions.has("--ephemeral") {
            AppDefaults.useEphemeral()
        }
    }

    var body: some Scene {
        WindowGroup("HyperEdit") {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.caret)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands { EditorCommands(model: model) }

        Settings {
            SettingsView().environmentObject(model)
        }
    }
}

/// 펑션 키 KeyEquivalent (F1~F12)
func fKey(_ n: Int) -> KeyEquivalent {
    KeyEquivalent(Character(UnicodeScalar(NSF1FunctionKey + (n - 1))!))
}

// UI 문자열은 영어가 소스(카탈로그 키)이고 한국어는 Apps/mac/Localizable.xcstrings 의 번역이다 (scripts/check-l10n.py 가 누락을 검사).
struct EditorCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("HyperEdit Help (GitHub)") { NSWorkspace.shared.open(URL(string: "https://github.com/Hyeongcheol-An/HyperEdit#readme")!) }
            Button("Report an Issue or Suggestion…") { NSWorkspace.shared.open(URL(string: "https://github.com/Hyeongcheol-An/HyperEdit/issues/new/choose")!) }
        }
        // 기본 '페이지 설정…'(⇧⌘P)·'프린트…'(⌘P) 는 쓰지 않는다 — ⇧⌘P 를 마크다운 미리보기에 준다
        CommandGroup(replacing: .printItem) {}
        CommandGroup(replacing: .newItem) {
            Button("New Document…") { model.newDocument() }.keyboardShortcut("n")
            Button("Open…") { model.presentOpenPanel() }.keyboardShortcut("o")
            Button("Open Default Document (~/Documents/HyperEdit/notes.md)") { model.openDefaultDocument() }
            Button("Save") { model.saveNow() }.keyboardShortcut("s")
            Button("Reveal in Finder") { model.revealInFinder() }
            Divider()
            Button("Open Snapshot Folder") { model.openSnapshotFolder() }
            Button("Reload from Disk") { model.reloadFromDisk() }
        }
        CommandGroup(replacing: .textEditing) {
            Button("Find…") { model.findInEditor() }.keyboardShortcut("f")
            Button("Replace…") { model.showReplace() }.keyboardShortcut("r")
            Button("Find in Files…") { model.showFindInFiles() }.keyboardShortcut("f", modifiers: [.command, .shift])
            Button("Find Next") { model.findNext() }.keyboardShortcut(fKey(3), modifiers: [])
            Button("Find Previous") { model.findPrevious() }.keyboardShortcut(fKey(3), modifiers: [.shift])
            Button("Go to Line…") { model.showGoToLine = true }.keyboardShortcut("l")
            Divider()
            Button(model.columnMode ? "Turn Column Mode Off" : "Turn Column Mode On") { model.columnMode.toggle() }.keyboardShortcut("c", modifiers: [.option])
            Button("Add Next Match (Multi-Caret)") { model.send(.addNextOccurrence) }.keyboardShortcut("d")
            Button("Select All Matches") { model.selectAllMatches() }.keyboardShortcut("a", modifiers: [.command, .option])
            Button("Insert Number…") { model.showInsertNumber = true }.keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("Insert Date/Time") { model.insertTimestamp() }.keyboardShortcut(fKey(7), modifiers: [])
            Button("Go to End of Document") { model.goToEnd() }.keyboardShortcut("e", modifiers: [.command, .control])
            Divider()
            Button("Toggle Bookmark") { model.toggleBookmarkAtCaret() }.keyboardShortcut(fKey(2), modifiers: [.command])
            Button("Next Bookmark") { model.nextBookmark() }.keyboardShortcut(fKey(2), modifiers: [])
            Button("Previous Bookmark") { model.previousBookmark() }.keyboardShortcut(fKey(2), modifiers: [.option])
        }
        CommandMenu("Line") {
            Button("Delete Line") { model.textTool(.deleteLine) }.keyboardShortcut("k", modifiers: [.command, .shift])
            Button("Duplicate Line") { model.textTool(.duplicateLine) }.keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Move Line Up") { model.textTool(.moveLineUp) }.keyboardShortcut(.upArrow, modifiers: [.option])
            Button("Move Line Down") { model.textTool(.moveLineDown) }.keyboardShortcut(.downArrow, modifiers: [.option])
            Button("Join Lines") { model.textTool(.joinLines) }.keyboardShortcut("j", modifiers: [.command, .shift])
            Divider()
            Menu("Case") {
                Button("Uppercase") { model.textTool(.upper) }
                Button("Lowercase") { model.textTool(.lower) }
                Button("Capitalize") { model.textTool(.capitalize) }
                Button("Invert Case") { model.textTool(.invertCase) }
            }
            Menu("Sort") {
                Button("Ascending") { model.textTool(.sortAsc) }
                Button("Descending") { model.textTool(.sortDesc) }
                Button("Numeric Sort") { model.textTool(.sortNumeric) }
                Button("Remove Duplicate Lines") { model.textTool(.dedupe) }
                Button("Reverse Lines") { model.textTool(.reverseLines) }
            }
            Menu("Whitespace") {
                Button("Trim Trailing Whitespace") { model.textTool(.trimTrailing) }
                Button("Trim Leading and Trailing Whitespace") { model.textTool(.trimBoth) }
                Button("Remove Blank Lines") { model.textTool(.removeBlank) }
                Button("Tabs → Spaces") { model.textTool(.tabsToSpaces) }
                Button("Spaces → Tabs") { model.textTool(.spacesToTabs) }
            }
            Button("Number Lines") { model.textTool(.numberLines) }
            Divider()
            Button("Calculate") { model.textTool(.calculate) }.keyboardShortcut("=", modifiers: [.control, .command])
            Button("Align Columns") { model.textTool(.alignColumns) }.keyboardShortcut("t", modifiers: [.control, .command])
        }
        CommandMenu("View") {
            Button(model.showFileView ? "Hide Sidebar" : "Show Sidebar") { model.showFileView.toggle() }.keyboardShortcut("1")
            Button(model.showBottomPanel ? "Hide Bottom Panel" : "Show Bottom Panel") { model.showBottomPanel.toggle() }.keyboardShortcut("2")
            Button("Outline") { model.showOutline() }.keyboardShortcut("3")
            Button("Timeline") { model.showTimeline() }.keyboardShortcut("4")
            Button(model.showLineNumbers ? "Hide Line Numbers" : "Show Line Numbers") { model.showLineNumbers.toggle() }.keyboardShortcut("l", modifiers: [.command, .option])
            Button(model.wordWrap ? "Turn Word Wrap Off" : "Turn Word Wrap On") { model.wordWrap.toggle() }.keyboardShortcut("z", modifiers: [.option])
            Toggle("Markdown Preview", isOn: $model.showMarkdownPreview).keyboardShortcut("p", modifiers: [.command, .shift])
            // ⌥⌘H 는 시스템 '기타 가리기(Hide Others)' 가 앱 메뉴에서 먼저 가로채므로 ⌃⌘H (⌃⌘E·⌃⌘F 와 같은 계열)
            Toggle("Syntax Colors", isOn: $model.syntaxHighlighting).keyboardShortcut("h", modifiers: [.command, .control])
            Divider()
            ForEach(RibbonTab.allCases) { tab in
                Button(tab.menuLabel) { model.ribbonTab = tab }
            }
            Divider()
            Menu("Theme") {
                Button {
                    model.themes.setFollowsSystem(true)
                } label: {
                    if model.themes.followsSystem { Label("Follow System Appearance (Hyper Light / Hyper Dark)", systemImage: "checkmark") }
                    else { Text("Follow System Appearance (Hyper Light / Hyper Dark)") }
                }
                Divider()
                ForEach(model.themes.themes) { t in
                    Button {
                        model.themes.select(id: t.id)
                    } label: {
                        if t.id == model.themes.current.id { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                    }
                }
            }
            Button("Next Theme") { model.themes.selectNext(step: 1) }.keyboardShortcut("]", modifiers: [.command, .option])
            Button("Previous Theme") { model.themes.selectNext(step: -1) }.keyboardShortcut("[", modifiers: [.command, .option])
            Divider()
            Button("Larger Text") { model.adjustFontSize(1) }.keyboardShortcut("=", modifiers: [.command])
            Button("Smaller Text") { model.adjustFontSize(-1) }.keyboardShortcut("-", modifiers: [.command])
            Button("Default Text Size") { model.resetFontSize() }.keyboardShortcut("0", modifiers: [.command])
        }
    }
}
