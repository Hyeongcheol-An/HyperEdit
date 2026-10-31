import SwiftUI
import AppKit
import HyperCore

@main
struct HyperEditApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    init() {
        // 스크린샷·셀프테스트 실행은 사용자 설정(테마·패널·마지막 파일)을 건드리지 않도록 휘발성 저장소를 쓴다
        if LaunchOptions.has("--snapshot") || LaunchOptions.has("--selftest") || LaunchOptions.has("--selftest-open") {
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

struct EditorCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("HyperEdit 도움말 (GitHub)") { NSWorkspace.shared.open(URL(string: "https://github.com/Hyeongcheol-An/HyperEdit#readme")!) }
            Button("문제 신고·제안…") { NSWorkspace.shared.open(URL(string: "https://github.com/Hyeongcheol-An/HyperEdit/issues/new/choose")!) }
        }
        CommandGroup(replacing: .newItem) {
            Button("새 문서…") { model.newDocument() }.keyboardShortcut("n")
            Button("열기…") { model.presentOpenPanel() }.keyboardShortcut("o")
            Button("기본 문서 열기 (~/Documents/HyperEdit/notes.md)") { model.openDefaultDocument() }
            Button("저장") { model.saveNow() }.keyboardShortcut("s")
            Button("Finder에서 보기") { model.revealInFinder() }
            Divider()
            Button("스냅샷 폴더 열기") { model.openSnapshotFolder() }
            Button("디스크에서 다시 읽기") { model.reloadFromDisk() }
        }
        CommandGroup(replacing: .textEditing) {
            Button("찾기…") { model.findInEditor() }.keyboardShortcut("f")
            Button("바꾸기…") { model.showReplace() }.keyboardShortcut("r")
            Button("파일에서 찾기…") { model.showFindInFiles() }.keyboardShortcut("f", modifiers: [.command, .shift])
            Button("다음 찾기") { model.findNext() }.keyboardShortcut(fKey(3), modifiers: [])
            Button("이전 찾기") { model.findPrevious() }.keyboardShortcut(fKey(3), modifiers: [.shift])
            Button("줄로 이동…") { model.showGoToLine = true }.keyboardShortcut("l")
            Divider()
            Button(model.columnMode ? "열 모드 끄기" : "열 모드 켜기") { model.columnMode.toggle() }.keyboardShortcut("c", modifiers: [.option])
            Button("다음 매치 추가 (멀티 커서)") { model.send(.addNextOccurrence) }.keyboardShortcut("d")
            Button("매치 모두 선택") { model.selectAllMatches() }.keyboardShortcut("a", modifiers: [.command, .option])
            Button("숫자 채우기…") { model.showInsertNumber = true }.keyboardShortcut("n", modifiers: [.command, .option])
            Divider()
            Button("날짜/시간 삽입") { model.insertTimestamp() }.keyboardShortcut(fKey(7), modifiers: [])
            Button("문서 끝으로") { model.goToEnd() }.keyboardShortcut("e", modifiers: [.command, .control])
            Divider()
            Button("북마크 토글") { model.toggleBookmarkAtCaret() }.keyboardShortcut(fKey(2), modifiers: [.command])
            Button("다음 북마크") { model.nextBookmark() }.keyboardShortcut(fKey(2), modifiers: [])
            Button("이전 북마크") { model.previousBookmark() }.keyboardShortcut(fKey(2), modifiers: [.option])
        }
        CommandMenu("줄") {
            Button("줄 삭제") { model.textTool(.deleteLine) }.keyboardShortcut("k", modifiers: [.command, .shift])
            Button("줄 복제") { model.textTool(.duplicateLine) }.keyboardShortcut("d", modifiers: [.command, .shift])
            Button("줄 위로 이동") { model.textTool(.moveLineUp) }.keyboardShortcut(.upArrow, modifiers: [.option])
            Button("줄 아래로 이동") { model.textTool(.moveLineDown) }.keyboardShortcut(.downArrow, modifiers: [.option])
            Button("줄 합치기") { model.textTool(.joinLines) }.keyboardShortcut("j", modifiers: [.command, .shift])
            Divider()
            Menu("대소문자") {
                Button("대문자") { model.textTool(.upper) }
                Button("소문자") { model.textTool(.lower) }
                Button("첫 글자 대문자") { model.textTool(.capitalize) }
                Button("대소문자 반전") { model.textTool(.invertCase) }
            }
            Menu("정렬") {
                Button("오름차순") { model.textTool(.sortAsc) }
                Button("내림차순") { model.textTool(.sortDesc) }
                Button("숫자 정렬") { model.textTool(.sortNumeric) }
                Button("중복 줄 제거") { model.textTool(.dedupe) }
                Button("역순") { model.textTool(.reverseLines) }
            }
            Menu("공백") {
                Button("뒤 공백 제거") { model.textTool(.trimTrailing) }
                Button("앞뒤 공백 제거") { model.textTool(.trimBoth) }
                Button("빈 줄 제거") { model.textTool(.removeBlank) }
                Button("탭 → 공백") { model.textTool(.tabsToSpaces) }
                Button("공백 → 탭") { model.textTool(.spacesToTabs) }
            }
            Button("줄 번호 붙이기") { model.textTool(.numberLines) }
        }
        CommandMenu("보기") {
            Button(model.showFileView ? "사이드바 숨기기" : "사이드바 보이기") { model.showFileView.toggle() }.keyboardShortcut("1")
            Button(model.showBottomPanel ? "하단 패널 숨기기" : "하단 패널 보이기") { model.showBottomPanel.toggle() }.keyboardShortcut("2")
            Button("아웃라인") { model.showOutline() }.keyboardShortcut("3")
            Button("타임라인") { model.showTimeline() }.keyboardShortcut("4")
            Button(model.showLineNumbers ? "줄 번호 숨기기" : "줄 번호 보이기") { model.showLineNumbers.toggle() }.keyboardShortcut("l", modifiers: [.command, .option])
            Button(model.wordWrap ? "자동 줄바꿈 끄기" : "자동 줄바꿈 켜기") { model.wordWrap.toggle() }.keyboardShortcut("z", modifiers: [.option])
            Divider()
            ForEach(RibbonTab.allCases) { tab in
                Button("리본: \(tab.rawValue)") { model.ribbonTab = tab }
            }
            Divider()
            Menu("테마") {
                Button {
                    model.themes.setFollowsSystem(true)
                } label: {
                    if model.themes.followsSystem { Label("시스템 외형 따르기 (Hyper Light / Hyper Dark)", systemImage: "checkmark") }
                    else { Text("시스템 외형 따르기 (Hyper Light / Hyper Dark)") }
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
            Button("다음 테마") { model.themes.selectNext(step: 1) }.keyboardShortcut("]", modifiers: [.command, .option])
            Button("이전 테마") { model.themes.selectNext(step: -1) }.keyboardShortcut("[", modifiers: [.command, .option])
            Divider()
            Button("글자 크게") { model.adjustFontSize(1) }.keyboardShortcut("=", modifiers: [.command])
            Button("글자 작게") { model.adjustFontSize(-1) }.keyboardShortcut("-", modifiers: [.command])
            Button("기본 크기") { model.resetFontSize() }.keyboardShortcut("0", modifiers: [.command])
        }
    }
}
