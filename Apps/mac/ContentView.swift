import SwiftUI
import AppKit
import HyperCore

/// UltraEdit(v26+ 리본) 레이아웃: 리본 → 문서 탭 → [File View | 편집기 / 하단 결과창] → 상태바
struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        let theme = model.themes.current
        VStack(spacing: 0) {
            RibbonView(theme: theme)
            DocumentTabBar(doc: model.document, theme: theme)
            HSplitView {
                if model.showFileView {
                    LeftDock(theme: theme)
                        .frame(minWidth: 190, idealWidth: 250, maxWidth: 460)
                }
                VSplitView {
                    EditorView(document: model.document, theme: theme, font: model.font)
                        .frame(minHeight: 160)
                    if model.showBottomPanel {
                        BottomPanel(theme: theme)
                            .frame(minHeight: 110, idealHeight: 210, maxHeight: 520)
                    }
                }
                .frame(minWidth: 480)
            }
            StatusBar(doc: model.document, caret: model.caret, theme: theme)
        }
        .background(theme.background.color)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        // 주의: .ignoresSafeArea(.top) 로 리본 탭 줄을 제목 표시줄 영역에 올리면 hiddenTitleBar 의 제목 표시줄이 탭을 가린다(실측) — 탭 줄은 그 아래에 둔다
        .frame(minWidth: 900, minHeight: 560)
        .alert("줄로 이동", isPresented: $model.showGoToLine) {
            TextField("1 ~ \(model.document.lineIndex.lineCount)", text: $model.goToLineText)
                .onSubmit { model.submitGoToLine() }
            Button("이동") { model.submitGoToLine() }
            Button("취소", role: .cancel) {}
        }
        .alert("숫자 채우기 (Insert Number)", isPresented: $model.showInsertNumber) {
            TextField("시작 값", text: $model.insertNumberStart)
            TextField("증가 값", text: $model.insertNumberStep)
            Button("채우기") { model.insertColumnNumbers() }
            Button("취소", role: .cancel) {}
        } message: {
            Text("열 선택(또는 멀티 커서)의 각 줄에 순번을 넣습니다. 자릿수는 0으로 맞춥니다.")
        }
        // 종료 시 저장은 AppDelegate.applicationShouldTerminate 가 동기로 처리한다 (willTerminate 시점의 비동기 저장은 실행될 기회가 없다)
        .task { if SelfTest.enabled { await SelfTest.run(model: model) } }
        .task { if SelfTest.openEnabled { await SelfTest.runOpen(model: model) } }
        .onAppear { if CommandLine.arguments.contains("--debug-startup") { FileHandle.standardError.write("[startup] ContentView appeared\n".data(using: .utf8)!) } }
    }
}

/// 문서 탭 (M1: 단일 문서)
struct DocumentTabBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var doc: MemoDocument
    let theme: Theme

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text").font(.system(size: 11))
                Text(doc.url.lastPathComponent).font(.system(size: 12, weight: .medium))
                if doc.isDirty { Circle().fill(theme.accent.color).frame(width: 7, height: 7) }
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            .background(theme.background.color)
            .overlay(alignment: .top) { theme.accent.color.frame(height: 2) }
            .overlay(alignment: .trailing) { theme.border.color.frame(width: 1) }
            .foregroundStyle(theme.foreground.color)
            .help(doc.url.path)
            Button { model.newDocument() } label: { Image(systemName: "plus").font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundStyle(theme.foregroundMuted.color).padding(.horizontal, 10).help("새 문서… (⌘N)")
            Button { model.presentOpenPanel() } label: { Image(systemName: "folder").font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundStyle(theme.foregroundMuted.color).padding(.trailing, 10).help("파일 열기… (⌘O)")
            Spacer()
        }
        .frame(height: 26)
        .background(theme.backgroundAlt.color)
        .overlay(alignment: .bottom) { theme.border.color.frame(height: 1) }
    }
}

/// UltraEdit 식 상태바: Ln/Col/C, 줄바꿈, 인코딩, INS, 크기, 상태, 테마, 줌
struct StatusBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var doc: MemoDocument
    @ObservedObject var caret: EditorCaret
    let theme: Theme

    var body: some View {
        HStack(spacing: 0) {
            cell(caret.selectionLength > 0
                 ? "Ln \(fmt(caret.line)), Col \(fmt(caret.column)), Sel \(fmt(caret.selectionLength))"
                 : "Ln \(fmt(caret.line)), Col \(fmt(caret.column))", width: 210)
                .help("문자 오프셋 \(fmt(caret.offset))")
            cell(doc.lineEnding, width: 50).help("줄바꿈 종류")
            cell(doc.encodingName, width: doc.hasBOM ? 90 : 64).help("파일 인코딩 — 읽은 그대로 저장합니다")
            cell("COL", width: 44).foregroundStyle(model.columnMode ? theme.accent.color : theme.foregroundDim.color)
                .help(model.columnMode ? "열 모드 켜짐 (⌥C 로 끄기)" : "열 모드 꺼짐 (⌥C 로 켜기)")
            if caret.multiCaretCount > 1 {
                cell("⌖ \(caret.multiCaretCount)", width: 60).foregroundStyle(theme.accent.color).help(caret.columnBlockActive ? "열 블록" : "멀티 커서")
            }
            cell("\(fmt(doc.lineIndex.lineCount))줄 · \(sizeString(doc.fileSize))", width: 150)
            if let e = doc.errorMessage {
                cell(e, width: nil).foregroundStyle(theme.errorColor.color)
            } else {
                cell(doc.status, width: nil).help("입력을 멈추면 2초 뒤 자동 저장됩니다 (⌘S 즉시 저장)")
            }
            if doc.externalChange != nil && doc.isDirty {
                cell("⚠ 외부 변경", width: 80).foregroundStyle(theme.warningColor.color)
            }
            Spacer(minLength: 0)
            Menu {
                Button { model.themes.setFollowsSystem(true) } label: {
                    if model.themes.followsSystem { Label("시스템 외형 따르기", systemImage: "checkmark") } else { Text("시스템 외형 따르기") }
                }
                Divider()
                ForEach(model.themes.themes) { t in
                    Button { model.themes.select(id: t.id) } label: {
                        if t.id == theme.id { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                    }
                }
            } label: {
                Label(theme.name + (model.themes.followsSystem ? " · 시스템" : ""), systemImage: "paintpalette")
            }
            .help("테마 — 시스템 외형 따르기를 켜면 라이트/다크에 맞춰 Hyper Light/Dark 로 자동 전환")
            .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 8)
            cell("\(model.zoomPercent)%", width: 54)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(theme.foregroundMuted.color)
        .frame(height: 22)
        .background(theme.backgroundAlt.color)
        .overlay(alignment: .top) { theme.border.color.frame(height: 1) }
    }

    private func cell(_ text: String, width: CGFloat?) -> some View {
        Text(text)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(width: width, alignment: .leading)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .trailing) { theme.border.color.frame(width: 1).padding(.vertical, 4) }
    }

    private func fmt(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func sizeString(_ bytes: Int) -> String {
        bytes < 1024 ? "\(bytes)B" : bytes < 1_048_576 ? String(format: "%.0fKB", Double(bytes) / 1024) : String(format: "%.1fMB", Double(bytes) / 1_048_576)
    }
}
