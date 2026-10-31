import SwiftUI
import AppKit
import HyperCore

/// UltraEdit(v26+ 리본) 레이아웃: 리본 → 문서 탭 → [File View | (편집기 | 마크다운 미리보기) / 하단 결과창] → 상태바
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
                    // 편집기는 항상 HSplitView 안에 둔다 — 미리보기를 켜고 끌 때 EditorView 의 정체성이 유지되어 텍스트 뷰·undo 스택이 다시 만들어지지 않는다
                    GeometryReader { geo in
                        HSplitView {
                            EditorView(document: model.document, theme: theme, font: model.font)
                                .frame(minWidth: 320)
                            if model.showMarkdownPreview {
                                MarkdownPreviewView(document: model.document, caret: model.caret, theme: theme)
                                    .frame(minWidth: 280, idealWidth: max(280, geo.size.width * 0.45))
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                    }
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
        .alert("Go to Line", isPresented: $model.showGoToLine) {
            TextField("1 ~ \(model.document.lineIndex.lineCount)", text: $model.goToLineText)
                .onSubmit { model.submitGoToLine() }
            Button("Go") { model.submitGoToLine() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Insert Sequence Numbers", isPresented: $model.showInsertNumber) {
            TextField("Start value", text: $model.insertNumberStart)
            TextField("Step", text: $model.insertNumberStep)
            Button("Fill") { model.insertColumnNumbers() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Inserts a sequence number on each line of the column selection (or at each caret). Numbers are zero-padded to the same width.")
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
                .buttonStyle(.plain).foregroundStyle(theme.foregroundMuted.color).padding(.horizontal, 10).help("New Document… (⌘N)")
            Button { model.presentOpenPanel() } label: { Image(systemName: "folder").font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundStyle(theme.foregroundMuted.color).padding(.trailing, 10).help("Open File… (⌘O)")
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
            // 셀 문자열은 String 이므로 String(localized:) 로 카탈로그를 거친다 (Ln/Col 처럼 두 언어가 같은 것도 키로 둔다)
            cell(caret.selectionLength > 0
                 ? String(localized: "Ln \(fmt(caret.line)), Col \(fmt(caret.column)), Sel \(fmt(caret.selectionLength))")
                 : String(localized: "Ln \(fmt(caret.line)), Col \(fmt(caret.column))"), width: 210)
                .help("Character offset \(fmt(caret.offset))")
            cell(doc.lineEnding, width: 50).help("Line ending")
            cell(doc.encodingName, width: doc.hasBOM ? 90 : 64).help("File encoding — saved exactly as it was read")
            cell("COL", width: 44).foregroundStyle(model.columnMode ? theme.accent.color : theme.foregroundDim.color)
                .help(model.columnMode ? "Column mode on (⌥C to turn off)" : "Column mode off (⌥C to turn on)")
            if model.showMarkdownPreview {
                cell("MD", width: 40).foregroundStyle(theme.accent.color).help("Markdown preview on (⇧⌘P)")
            }
            if caret.multiCaretCount > 1 {
                cell("⌖ \(caret.multiCaretCount)", width: 60).foregroundStyle(theme.accent.color).help(caret.columnBlockActive ? "Column block" : "Multiple carets")
            }
            cell(String(localized: "\(fmt(doc.lineIndex.lineCount)) lines · \(sizeString(doc.fileSize))"), width: 165)
            if let e = doc.errorMessage {
                cell(e, width: nil).foregroundStyle(theme.errorColor.color)
            } else {
                cell(doc.status, width: nil).help("Autosaves 2 seconds after you stop typing (⌘S saves now)")
            }
            if doc.externalChange != nil && doc.isDirty {
                cell(String(localized: "⚠ External change"), width: nil).foregroundStyle(theme.warningColor.color)
            }
            Spacer(minLength: 0)
            Menu {
                Button { model.themes.setFollowsSystem(true) } label: {
                    if model.themes.followsSystem { Label("Follow System Appearance", systemImage: "checkmark") } else { Text("Follow System Appearance") }
                }
                Divider()
                ForEach(model.themes.themes) { t in
                    Button { model.themes.select(id: t.id) } label: {
                        if t.id == theme.id { Label(t.name, systemImage: "checkmark") } else { Text(t.name) }
                    }
                }
            } label: {
                Label(model.themes.followsSystem ? String(localized: "\(theme.name) · System") : theme.name, systemImage: "paintpalette")
            }
            .help("Theme — with Follow System Appearance on, Hyper Light/Dark follow the system light/dark setting")
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
