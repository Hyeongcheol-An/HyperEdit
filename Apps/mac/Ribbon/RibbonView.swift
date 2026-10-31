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
                    RibbonTabButton(title: tab.rawValue, selected: model.ribbonTab == tab, theme: theme) { model.ribbonTab = tab }
                }
                Spacer()
                HStack(spacing: 2) {
                    QuickButton(systemImage: "square.and.arrow.down", help: "저장 (⌘S)", theme: theme) { model.saveNow() }
                    QuickButton(systemImage: "arrow.uturn.backward", help: "실행 취소 (⌘Z)", theme: theme) { model.send(.undo) }
                    QuickButton(systemImage: "arrow.uturn.forward", help: "다시 실행 (⇧⌘Z)", theme: theme) { model.send(.redo) }
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

private struct HomeTab: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    var body: some View {
        RibbonGroup(title: "클립보드", theme: theme) {
            RibbonBigButton(title: "붙여넣기", systemImage: "doc.on.clipboard", help: "⌘V", theme: theme) { model.send(.paste) }
            RibbonStack {
                RibbonSmallButton(title: "잘라내기", systemImage: "scissors", help: "⌘X", theme: theme) { model.send(.cut) }
                RibbonSmallButton(title: "복사", systemImage: "doc.on.doc", help: "⌘C", theme: theme) { model.send(.copy) }
                RibbonSmallButton(title: "모두 선택", systemImage: "selection.pin.in.out", help: "⌘A", theme: theme) { model.send(.selectAll) }
            }
        }
        RibbonGroup(title: "찾기", theme: theme) {
            RibbonBigButton(title: "찾기", systemImage: "magnifyingglass", help: "⌘F — 하단 '찾기 결과' 창에 결과 목록", theme: theme) { model.findInEditor() }
            RibbonStack {
                RibbonSmallButton(title: "바꾸기", systemImage: "arrow.left.arrow.right", help: "⌘R", theme: theme) { model.showReplace() }
                RibbonSmallButton(title: "파일에서 찾기", systemImage: "doc.text.magnifyingglass", help: "⇧⌘F — 폴더·마스크", theme: theme) { model.showFindInFiles() }
                RibbonSmallButton(title: "줄로 이동", systemImage: "arrow.right.to.line", help: "⌘L", theme: theme) { model.showGoToLine = true }
            }
        }
        RibbonGroup(title: "삽입", theme: theme) {
            RibbonBigButton(title: "날짜/시간", systemImage: "calendar.badge.clock", help: "타임스탬프 헤딩 삽입 — ## 2026-10-30 (금) 14:05 (F7)", theme: theme) { model.insertTimestamp() }
            RibbonStack {
                RibbonSmallButton(title: "북마크 토글", systemImage: "bookmark", help: "현재 줄 북마크 켜기/끄기 (⌘F2)", theme: theme) { model.toggleBookmarkAtCaret() }
                RibbonSmallButton(title: "다음 북마크", systemImage: "bookmark.fill", help: "다음 북마크로 (F2)", theme: theme) { model.nextBookmark() }
                RibbonSmallButton(title: "이전 북마크", systemImage: "bookmark.slash", help: "이전 북마크로 (⌥F2)", theme: theme) { model.previousBookmark() }
            }
        }
        RibbonGroup(title: "모드", theme: theme) {
            RibbonBigToggle(title: "열 모드", systemImage: "rectangle.split.3x1", help: "⌥C — 드래그/⇧방향키로 사각형 선택, 입력은 모든 줄에", isOn: $model.columnMode, theme: theme)
            RibbonStack {
                RibbonSmallToggle(title: "자동 줄바꿈", systemImage: "text.word.spacing", help: "자동 줄바꿈 (⌥Z)", isOn: $model.wordWrap, theme: theme)
                RibbonSmallToggle(title: "줄 번호", systemImage: "list.number", help: "줄 번호 거터 (⌥⌘L)", isOn: $model.showLineNumbers, theme: theme)
            }
        }
        RibbonGroup(title: "파일", theme: theme) {
            RibbonBigButton(title: "저장", systemImage: "square.and.arrow.down", help: "지금 저장 (⌘S) — 입력을 멈추면 2초 뒤 자동 저장", theme: theme) { model.saveNow() }
            RibbonStack {
                RibbonSmallButton(title: "새 문서…", systemImage: "doc.badge.plus", help: "빈 텍스트 파일을 만들어 연다 (⌘N)", theme: theme) { model.newDocument() }
                RibbonSmallButton(title: "열기…", systemImage: "folder", help: "텍스트 파일 열기 (⌘O)", theme: theme) { model.presentOpenPanel() }
                RibbonSmallButton(title: "Finder에서 보기", systemImage: "macwindow", help: "현재 파일을 Finder 에서 선택", theme: theme) { model.revealInFinder() }
            }
        }
    }
}

private struct EditTab: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    var body: some View {
        RibbonGroup(title: "줄", theme: theme) {
            RibbonBigButton(title: "줄 삭제", systemImage: "trash", help: "⇧⌘K", theme: theme) { model.textTool(.deleteLine) }
            RibbonStack {
                RibbonSmallButton(title: "줄 복제", systemImage: "plus.square.on.square", help: "⇧⌘D", theme: theme) { model.textTool(.duplicateLine) }
                RibbonSmallButton(title: "위로 이동", systemImage: "arrow.up", help: "⌥↑", theme: theme) { model.textTool(.moveLineUp) }
                RibbonSmallButton(title: "아래로 이동", systemImage: "arrow.down", help: "⌥↓", theme: theme) { model.textTool(.moveLineDown) }
            }
            RibbonStack {
                RibbonSmallButton(title: "줄 합치기", systemImage: "arrow.triangle.merge", help: "선택 줄을 한 줄로 (선택이 없으면 현재 줄 + 다음 줄) (⇧⌘J)", theme: theme) { model.textTool(.joinLines) }
                RibbonSmallButton(title: "줄 번호 붙이기", systemImage: "list.number", help: "선택 줄 앞에 1. 2. 3. 번호", theme: theme) { model.textTool(.numberLines) }
                RibbonSmallButton(title: "역순", systemImage: "arrow.up.arrow.down", help: "선택 줄 순서 뒤집기", theme: theme) { model.textTool(.reverseLines) }
            }
        }
        RibbonGroup(title: "대소문자", theme: theme) {
            RibbonStack {
                RibbonSmallButton(title: "대문자", systemImage: "textformat.size.larger", help: "선택(없으면 현재 줄)을 대문자로", theme: theme) { model.textTool(.upper) }
                RibbonSmallButton(title: "소문자", systemImage: "textformat.size.smaller", help: "선택(없으면 현재 줄)을 소문자로", theme: theme) { model.textTool(.lower) }
                RibbonSmallButton(title: "첫 글자 대문자", systemImage: "textformat", help: "단어 첫 글자만 대문자로", theme: theme) { model.textTool(.capitalize) }
            }
            RibbonStack {
                RibbonSmallButton(title: "대소문자 반전", systemImage: "arrow.2.squarepath", help: "대문자 ↔ 소문자 뒤집기", theme: theme) { model.textTool(.invertCase) }
            }
        }
        RibbonGroup(title: "정렬", theme: theme) {
            RibbonBigButton(title: "오름차순", systemImage: "arrow.up.arrow.down.square", help: "선택 줄을 가나다·ABC 순으로 정렬", theme: theme) { model.textTool(.sortAsc) }
            RibbonStack {
                RibbonSmallButton(title: "내림차순", systemImage: "arrow.down.square", help: "선택 줄을 역순으로 정렬", theme: theme) { model.textTool(.sortDesc) }
                RibbonSmallButton(title: "숫자 정렬", systemImage: "number.square", help: "줄 앞 숫자 크기 기준 정렬", theme: theme) { model.textTool(.sortNumeric) }
                RibbonSmallButton(title: "중복 줄 제거", systemImage: "rectangle.stack.badge.minus", help: "같은 줄은 첫 번째만 남김", theme: theme) { model.textTool(.dedupe) }
            }
        }
        RibbonGroup(title: "공백", theme: theme) {
            RibbonStack {
                RibbonSmallButton(title: "뒤 공백 제거", systemImage: "text.alignleft", help: "줄 끝의 공백·탭 제거", theme: theme) { model.textTool(.trimTrailing) }
                RibbonSmallButton(title: "앞뒤 공백 제거", systemImage: "text.aligncenter", help: "줄 앞뒤의 공백·탭 제거", theme: theme) { model.textTool(.trimBoth) }
                RibbonSmallButton(title: "빈 줄 제거", systemImage: "rectangle.compress.vertical", help: "비어 있거나 공백뿐인 줄 삭제", theme: theme) { model.textTool(.removeBlank) }
            }
            RibbonStack {
                RibbonSmallButton(title: "탭 → 공백", systemImage: "arrow.right.to.line.compact", help: "탭을 공백 4칸으로", theme: theme) { model.textTool(.tabsToSpaces) }
                RibbonSmallButton(title: "공백 → 탭", systemImage: "arrow.left.to.line.compact", help: "줄 앞 공백 4칸을 탭으로", theme: theme) { model.textTool(.spacesToTabs) }
            }
        }
        RibbonGroup(title: "열·멀티 커서", theme: theme) {
            RibbonBigButton(title: "숫자 채우기", systemImage: "number.square", help: "Insert Number — 열 선택(⌥C 후 ⇧↓)의 각 줄에 순번", theme: theme) { model.showInsertNumber = true }
            RibbonStack {
                RibbonSmallToggle(title: "열 모드", systemImage: "rectangle.split.3x1", help: "⌥C", isOn: $model.columnMode, theme: theme)
                RibbonSmallButton(title: "다음 매치 추가", systemImage: "plus.magnifyingglass", help: "⌘D — 선택과 같은 글자의 다음 등장을 커서에 추가", theme: theme) { model.send(.addNextOccurrence) }
                RibbonSmallButton(title: "매치 모두 선택", systemImage: "checkmark.circle", help: "⌥⌘A — 찾기 결과 전부를 멀티 커서로", enabled: !model.searchHits.isEmpty, theme: theme) { model.selectAllMatches() }
            }
        }
    }
}

private struct LayoutTab: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    var body: some View {
        RibbonGroup(title: "테마", theme: theme) {
            Menu {
                Button { model.themes.setFollowsSystem(true) } label: {
                    if model.themes.followsSystem { Label("시스템 외형 따르기 (Hyper Light / Dark)", systemImage: "checkmark") } else { Text("시스템 외형 따르기 (Hyper Light / Dark)") }
                }
                Divider()
                Section("라이트") {
                    ForEach(model.themes.lightThemes) { t in
                        Button { model.themes.select(id: t.id) } label: {
                            if t.id == theme.id { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                        }
                    }
                }
                Section("다크") {
                    ForEach(model.themes.darkThemes) { t in
                        Button { model.themes.select(id: t.id) } label: {
                            if t.id == theme.id { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                        }
                    }
                }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "paintpalette").font(.system(size: 22)).frame(height: 30)
                    Text("테마").font(.system(size: 10.5))
                }
                .frame(width: 60, height: 64)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .foregroundStyle(theme.foreground.color)
            RibbonStack {
                RibbonSmallButton(title: "다음 테마", systemImage: "chevron.right", help: "다음 테마 (⌥⌘])", theme: theme) { model.themes.selectNext(step: 1) }
                RibbonSmallButton(title: "이전 테마", systemImage: "chevron.left", help: "이전 테마 (⌥⌘[)", theme: theme) { model.themes.selectNext(step: -1) }
                Text(theme.name + (model.themes.followsSystem ? " · 시스템" : "")).font(.system(size: 10)).foregroundStyle(theme.foregroundMuted.color).frame(width: 118, alignment: .leading).lineLimit(1)
            }
        }
        RibbonGroup(title: "패널", theme: theme) {
            RibbonStack {
                RibbonSmallToggle(title: "사이드바", systemImage: "sidebar.left", help: "사이드바 — 파일·아웃라인·타임라인 (⌘1)", isOn: $model.showFileView, theme: theme)
                RibbonSmallToggle(title: "하단 패널", systemImage: "rectangle.bottomthird.inset.filled", help: "하단 패널 — 찾기 결과·북마크·출력 (⌘2)", isOn: $model.showBottomPanel, theme: theme)
                RibbonSmallToggle(title: "줄 번호", systemImage: "list.number", help: "줄 번호 거터 (⌥⌘L)", isOn: $model.showLineNumbers, theme: theme)
            }
            RibbonStack {
                RibbonSmallButton(title: "파일 보기", systemImage: "folder", help: "현재 문서 폴더의 파일 트리 (⌘1)", theme: theme) { model.leftTab = .fileView; model.showFileView = true }
                RibbonSmallButton(title: "아웃라인", systemImage: "list.bullet.indent", help: "헤딩·[제목]·가나다·번호 항목 (⌘3)", theme: theme) { model.showOutline() }
                RibbonSmallButton(title: "타임라인", systemImage: "calendar", help: "타임스탬프·날짜 줄을 월별로 (⌘4)", theme: theme) { model.showTimeline() }
            }
            RibbonStack {
                RibbonSmallToggle(title: "자동 줄바꿈", systemImage: "text.word.spacing", help: "자동 줄바꿈 (⌥Z)", isOn: $model.wordWrap, theme: theme)
            }
        }
        RibbonGroup(title: "글꼴", theme: theme) {
            RibbonBigButton(title: "크게", systemImage: "textformat.size.larger", help: "글자 크게 (⌘=)", theme: theme) { model.adjustFontSize(1) }
            RibbonStack {
                RibbonSmallButton(title: "작게", systemImage: "textformat.size.smaller", help: "글자 작게 (⌘-)", theme: theme) { model.adjustFontSize(-1) }
                RibbonSmallButton(title: "기본 크기 (14pt)", systemImage: "1.magnifyingglass", help: "기본 크기로 (⌘0)", theme: theme) { model.resetFontSize() }
                RibbonSmallButton(title: "글꼴 설정…", systemImage: "gearshape", help: "글꼴·한글 폭 보정 설정 (⌘,)", theme: theme) { model.openSettings() }
            }
        }
    }
}

private struct AdvancedTab: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    var body: some View {
        RibbonGroup(title: "설정", theme: theme) {
            RibbonBigButton(title: "설정", systemImage: "gearshape", help: "환경설정 (⌘,)", theme: theme) { model.openSettings() }
            RibbonStack {
                RibbonSmallButton(title: "스냅샷 폴더", systemImage: "clock.arrow.circlepath", help: "저장 전 자동 백업이 쌓이는 폴더 열기", theme: theme) { model.openSnapshotFolder() }
                RibbonSmallButton(title: "디스크에서 다시 읽기", systemImage: "arrow.clockwise", help: "파일을 다시 읽음 — 저장 안 한 변경은 버림", theme: theme) { model.reloadFromDisk() }
                RibbonSmallButton(title: "기본 문서 열기", systemImage: "house", help: "~/Documents/HyperEdit/notes.md 열기", theme: theme) { model.openDefaultDocument() }
            }
        }
    }
}

private struct WindowTab: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    var body: some View {
        RibbonGroup(title: "창", theme: theme) {
            RibbonBigButton(title: "전체 화면", systemImage: "arrow.up.left.and.arrow.down.right", help: "전체 화면 전환 (⌃⌘F)", theme: theme) { model.toggleFullScreen() }
            RibbonStack {
                RibbonSmallToggle(title: "사이드바", systemImage: "sidebar.left", help: "사이드바 (⌘1)", isOn: $model.showFileView, theme: theme)
                RibbonSmallToggle(title: "하단 패널", systemImage: "rectangle.bottomthird.inset.filled", help: "하단 패널 (⌘2)", isOn: $model.showBottomPanel, theme: theme)
                RibbonSmallToggle(title: "줄 번호", systemImage: "list.number", help: "줄 번호 거터 (⌥⌘L)", isOn: $model.showLineNumbers, theme: theme)
            }
        }
    }
}

// MARK: - 구성 요소

struct RibbonTabButton: View {
    let title: String
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
    let help: String
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
    let title: String
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
    let title: String
    let systemImage: String
    var help: String = ""
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
    let title: String
    let systemImage: String
    var help: String = ""
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
    let title: String
    let systemImage: String
    var help: String = ""
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
    let title: String
    let systemImage: String
    var help: String = ""
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
