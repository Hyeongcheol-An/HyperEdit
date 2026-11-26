import SwiftUI
import AppKit
import HyperCore

@main
struct HyperEditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    init() {
        // 사용자의 것과 떨어져 도는 실행(스크린샷·셀프테스트·벤치·실사용 하네스, 손으로 시험하는 `--ephemeral` — AutomationRun.swift)은 사용자 설정(테마·패널·
        // 마지막 파일)을 건드리지 않도록 휘발성 저장소를 쓴다.
        // `--ephemeral-suite <name>` 은 여러 자동화 인스턴스를 동시에 띄울 때 서로의 설정·스냅샷·기본 문서 폴더가 섞이지 않게 한다
        if AutomationRun.isIsolated {
            AppDefaults.useEphemeral(suiteName: LaunchOptions.value("--ephemeral-suite") ?? "hyperedit.automation")
            // macOS 의 '저장된 창 상태'는 번들 ID 별이라 설치된 HyperEdit 과 모든 자동화 실행이 한 폴더를 같이 쓴다. 자동화 실행이 거기에 자기 창을 적으면
            // (실측: 시작 30초쯤 뒤 windows.plist · window_N.data · data.data) 사용자 앱의 상태를 덮어쓰고, 그 실행이 강제 종료되면 남은 상태를 다음에 뜨는
            // 인스턴스가 — 사용자의 앱도 — 복원한다 (실측: 강제 종료된 실행 하나가 남긴 창 47개를 그 뒤에 뜬 실행들이 모두 복원했다).
            // 이 값을 켜면 시작할 때 저장된 상태를 읽지 않고, 실행 중에도 적지 않는다(실측 macOS 27). 창도 복원 대상에서 뺀다(아래 restorationBehavior).
            // 등록 도메인은 우선순위가 가장 낮아 같은 키가 이미 저장돼 있으면 진다 — 실행 스크립트들은 인자로도 넘긴다 (`-ApplePersistenceIgnoreState YES`)
            UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
            // 창 프레임 저장값(`NSWindow Frame …` — 이것도 번들 ID 의 설정에 적힌다)은 위의 둘로 막히지 않는다 → 따로 막는다
            AutomationRun.keepWindowFramesOutOfDefaults()
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
        // 창은 하나다 (모델·문서·편집기가 하나). SwiftUI 는 밖에서 온 열기 이벤트(Finder "다음으로 열기"·Dock·`open -a` → `application(_:open:)`)마다
        // 이 장면의 창을 하나 더 만든다(실측) — 같은 모델에 편집기가 둘 붙는다. 그런 이벤트로는 창을 만들지 않고, 파일은 AppDelegate 가 탭으로 연다
        .handlesExternalEvents(matching: [])
        .restorationBehavior(AutomationRun.isIsolated ? .disabled : .automatic)   // 자동화 실행의 창은 저장된 창 상태에 넣지 않는다 (init 의 주석)
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
            Button("User Guide") { model.openUserGuide() }   // 지금 보이는 언어의 docs/guide/USER_GUIDE.<code>.md
            Button("HyperEdit Help (GitHub)") { NSWorkspace.shared.open(URL(string: "https://github.com/Hyeongcheol-An/HyperEdit#readme")!) }
            Button("Report an Issue or Suggestion…") { NSWorkspace.shared.open(URL(string: "https://github.com/Hyeongcheol-An/HyperEdit/issues/new/choose")!) }
        }
        // 기본 '페이지 설정…'(⇧⌘P)·'프린트…'(⌘P) 는 쓰지 않는다 — ⇧⌘P 를 마크다운 미리보기에 준다
        CommandGroup(replacing: .printItem) {}
        CommandGroup(replacing: .newItem) {
            Button("New Document…") { model.newDocument() }.keyboardShortcut("n")
            Button("Open…") { model.presentOpenPanel() }.keyboardShortcut("o")
            Button("Quick Append…") { model.quickAppend.show() }.keyboardShortcut("n", modifiers: [.command, .shift])   // quick append
            Button("Open Default Document (~/Documents/HyperEdit/notes.md)") { model.openDefaultDocument() }
            Button("Save") { model.saveNow() }.keyboardShortcut("s")
            Button("Reveal in Finder") { model.revealInFinder() }
            Divider()
            // 파일 탭 (UltraEdit 식 — docs/tabs-model.ko.md). ⌃Tab(마지막 파일) / ⌃⇧Tab(이전 탭) 은 AppDelegate 의 키 모니터가 처리한다
            Button("Close Tab") { model.closeActiveTab() }.keyboardShortcut("w")
            Button("Close Other Tabs") { model.closeOtherTabs() }
            Button("Close All Tabs") { model.closeAllTabs() }.keyboardShortcut("w", modifiers: [.command, .shift])
            Button("Reopen Last Closed Tab") { model.reopenLastClosedTab() }.keyboardShortcut("t", modifiers: [.command, .shift])
            Button("Next Tab") { model.nextTab() }.keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Previous Tab") { model.previousTab() }.keyboardShortcut("[", modifiers: [.command, .shift])
            Button("Last Active Tab") { model.activateLastActiveTab() }
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
            Button("Insert Snippet…") { model.showSnippetPicker = true }.keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Edit Snippets…") { model.editSnippets() }
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
            Divider()
            Button("Toggle Comment") { model.textTool(.toggleComment) }.keyboardShortcut("/", modifiers: [.command])
            Button("Format JSON") { model.textTool(.formatJSON) }.keyboardShortcut("j", modifiers: [.control, .command])
            Button("Minify JSON") { model.textTool(.minifyJSON) }
        }
        FeatureCommands(model: model)   // macro · export · secrets · grammar · applock (CommandsBuilder 는 자식 10개 제한 — CI 의 Xcode 에서 "extra argument in call")
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
            // split: ⌘\ 토글 + 방향 하위 메뉴, ⌥⌘\ 다른 분할로 포커스
            Toggle("Split Editor", isOn: Binding(get: { model.session.splitMode != .none }, set: { _ in model.toggleSplit() })).keyboardShortcut("\\")
            Menu("Split") {
                Button("Split Side by Side") { model.setSplit(.vertical) }
                Button("Split Stacked") { model.setSplit(.horizontal) }
                Button("Single Editor") { model.setSplit(.none) }
                Divider()
                Button("Focus Other Split") { model.focusOtherSplit() }.keyboardShortcut("\\", modifiers: [.command, .option])
            }
            Toggle("Scrollbar Markers", isOn: $model.showScrollMarkers)   // markers
            Divider()   // fold: Xcode 와 같은 ⌥⌘← / ⌥⌘→ (전체는 ⇧ 추가)
            Button("Fold") { model.send(.fold) }.keyboardShortcut(.leftArrow, modifiers: [.option, .command])
            Button("Unfold") { model.send(.unfold) }.keyboardShortcut(.rightArrow, modifiers: [.option, .command])
            Button("Fold All") { model.send(.foldAll) }.keyboardShortcut(.leftArrow, modifiers: [.option, .command, .shift])
            Button("Unfold All") { model.send(.unfoldAll) }.keyboardShortcut(.rightArrow, modifiers: [.option, .command, .shift])
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
            AppearanceMenuItems(model: model)   // appearance: 창 투명도 하위 메뉴 (100/90/80/70%) · 창 뒤 블러
        }
    }
}

/// v0.6–v0.8 기능 메뉴 묶음 — `EditorCommands.body` 의 자식 수를 CommandsBuilder 한도(10) 아래로 유지한다
struct FeatureCommands: Commands {
    @ObservedObject var model: AppModel
    var body: some Commands {
        MacroCommands(model: model)   // macro
        ExportCommands(model: model)   // export: 파일 › Export as HTML… / PDF…
        SecretsCommands(model: model)   // secrets: 편집 메뉴 끝 — Reveal Secrets ⌥⌘S · Mask Secret Blocks · Clear Clipboard
        GrammarCommands(model: model)   // grammar: 파일 메뉴 — 문법 폴더 열기 · 문법 다시 읽기
        AppLockCommands(model: model)   // applock: 앱 메뉴 Settings… 아래 "Lock HyperEdit" ⌃⌘L
    }
}
