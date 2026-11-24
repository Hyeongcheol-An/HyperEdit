import SwiftUI
import AppKit
import HyperCore
import UniformTypeIdentifiers

/// UltraEdit 식 파일 탭 바 (docs/tabs-model.ko.md): 열린 파일마다 탭 하나. 클릭 전환, × · 더블클릭 · 가운데 클릭으로 닫기, 드래그로 순서 바꾸기,
/// 우클릭 메뉴, 툴팁은 전체 경로·크기·수정 시각, 빈 곳 더블클릭은 새 문서, 오른쪽 끝 ▾ 는 열린 탭 목록(탭이 둘 이상일 때).
/// 탭은 파일 경로(`AppModel.tabs`)이고 살아 있는 문서는 하나다 — 탭을 바꾸면 그 문서가 파일을 갈아탄다(`MemoDocument.switchTo`).
/// 그래서 수정됨 표시는 활성 탭에만 있다 (다른 탭은 떠날 때 저장됐다)
extension UTType {
    /// 탭 순서 바꾸기 드래그 전용 타입 (project.yml 의 UTExportedTypeDeclarations). 경로를 일반 텍스트로 실으면 탭을 편집기 위에 놓았을 때 그 경로가
    /// 문서에 삽입되고, 편집기에서 끌어온 글이 탭 위에서 '이동'으로 받아들여진다 — 이 앱의 탭 줄만 알아보는 타입으로 싣는다
    static let hyperEditTab = UTType(exportedAs: "io.github.hyeongcheol-an.hyperedit.tab")
}

struct DocumentTabBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var doc: MemoDocument   // 활성 파일(url)·수정됨이 바뀌면 탭 줄을 다시 그린다
    let theme: Theme
    /// 탭을 다 늘어놓은 폭. 스크롤 영역은 이만큼만 차지한다 — 탭이 다 들어가면 + · 폴더 버튼이 마지막 탭 바로 뒤에 붙고, 넘치면 남은 폭을 다 쓰고 스크롤한다
    /// (가로 ScrollView 는 주는 폭을 다 받으므로 그대로 두면 탭이 두세 개여도 버튼이 오른쪽 끝으로 밀린다)
    @State private var tabsWidth: CGFloat = .infinity

    /// 탭에 적을 이름. 같은 이름의 파일이 둘 이상 열려 있으면 상위 폴더를 붙여 구별한다 (`notes.md — work`)
    private func title(_ url: URL, among duplicated: Set<String>) -> String {
        let name = url.lastPathComponent
        return duplicated.contains(name) ? name + " — " + url.deletingLastPathComponent().lastPathComponent : name
    }

    var body: some View {
        let duplicated = Set(Dictionary(grouping: model.tabs, by: \.lastPathComponent).filter { $0.value.count > 1 }.keys)
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(model.tabs, id: \.self) { url in
                            DocumentTab(url: url, title: title(url, among: duplicated), isActive: url == doc.url, isDirty: url == doc.url && doc.isDirty, theme: theme).id(url)
                        }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tabsWidth = $0.rounded(.up) }
                }
                .onChange(of: doc.url) { _, u in proxy.scrollTo(u) }   // 활성 탭이 보이게
                .onChange(of: model.tabs) { _, _ in proxy.scrollTo(doc.url) }   // 정렬·이동·닫기로 활성 탭의 자리만 바뀌었을 때도
                .onAppear { proxy.scrollTo(doc.url) }   // 지난 세션의 탭이 많은 채 시작하면 활성 탭이 스크롤 영역 밖일 수 있다
            }
            .frame(maxWidth: tabsWidth)
            .layoutPriority(1)
            Button { model.newDocument() } label: { Image(systemName: "plus").font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundStyle(theme.foregroundMuted.color).padding(.horizontal, 10).help("New Document… (⌘N)")
            Button { model.presentOpenPanel() } label: { Image(systemName: "folder").font(.system(size: 11)) }
                .buttonStyle(.plain).foregroundStyle(theme.foregroundMuted.color).padding(.trailing, 10).help("Open File… (⌘O)")
            Color.clear.contentShape(Rectangle())   // 빈 곳 더블클릭 → 새 문서 (UltraEdit)
                .onTapGesture(count: 2) { model.newDocument() }
            if model.tabs.count > 1 {
                Menu {
                    ForEach(model.tabs, id: \.self) { url in
                        Button { model.activateTab(url) } label: { Text(verbatim: (url == doc.url ? "• " : "") + title(url, among: duplicated)) }
                    }
                } label: { Image(systemName: "chevron.down").font(.system(size: 10)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .foregroundStyle(theme.foregroundMuted.color).padding(.horizontal, 8).help("Open Tabs").accessibilityLabel(Text("Open Tabs"))
            }
        }
        .frame(height: 26)
        .background(model.surfaceColor(theme.backgroundAlt))   // appearance
        .overlay(alignment: .bottom) { theme.border.color.frame(height: 1) }
    }
}

/// 탭 하나: 아이콘 · 파일 이름 · (수정됨 점 | 닫기 ×). × 는 활성 탭과 마우스가 올라간 탭에 보인다
struct DocumentTab: View {
    @EnvironmentObject var model: AppModel
    let url: URL
    let title: String
    let isActive: Bool
    let isDirty: Bool
    let theme: Theme
    @State private var hovering = false
    /// 툴팁(경로·크기·수정 시각). 파일 속성을 읽으므로 마우스가 올라올 때만 만든다 — body 는 모델이 발행할 때마다 모든 탭에서 다시 돈다
    @State private var tip = ""

    private static let dateFormat: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f }()
    private var tooltip: String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int).map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? ""
        let modified = (attrs?[.modificationDate] as? Date).map { Self.dateFormat.string(from: $0) } ?? ""
        return [url.path, [size, modified].filter { !$0.isEmpty }.joined(separator: " · ")].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text").font(.system(size: 11))
            Text(verbatim: title).font(.system(size: 12, weight: isActive ? .semibold : .regular)).lineLimit(1)
                .truncationMode(.middle).frame(maxWidth: 240)   // 아주 긴 이름 하나가 탭 줄을 다 차지하지 않게 (가운데를 줄여 확장자는 남긴다; 전체 경로는 툴팁)
                .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { model.activateTab(url) }
            ZStack {
                if isDirty && !hovering { Circle().fill(theme.accent.color).frame(width: 7, height: 7) }
                if hovering || (isActive && !isDirty) {
                    Button { model.closeTab(url) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 12, height: 12) }
                        .buttonStyle(.plain).foregroundStyle(theme.foregroundMuted.color).help("Close Tab (⌘W)").accessibilityLabel(Text("Close Tab"))
                }
            }
            .frame(width: 12, height: 12)
        }
        .padding(.leading, 12).padding(.trailing, 8)
        .frame(height: 26)
        .background(isActive ? model.surfaceColor(theme.background) : Color.clear)   // appearance
        .overlay(alignment: .top) { if isActive { theme.accent.color.frame(height: 2) } }
        .overlay(alignment: .trailing) { theme.border.color.frame(width: 1) }
        .foregroundStyle(isActive ? theme.foreground.color : theme.foregroundMuted.color)
        .contentShape(Rectangle())
        // 클릭은 바로 전환, 더블클릭은 닫기(UltraEdit 기본). 더블클릭을 먼저 건 `.onTapGesture(count: 2)` + `.onTapGesture` 조합은 한 번 클릭이 더블클릭
        // 판정(시스템 더블클릭 간격, 보통 0.5 s)을 기다린 뒤에야 온다 — 탭 전환도 × 버튼도 0.4 s 늦었다(실사용 하네스 실측). 동시 인식으로 두면 첫 클릭에
        // 바로 전환하고 두 번째 클릭에 닫는다. 보고 있지 않던 탭을 더블클릭했으면 닫은 뒤 보던 탭으로 돌아간다 (`AppModel.tabDoubleClicked`)
        .onTapGesture { model.tabClicked(url) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { model.tabDoubleClicked(url) })
        .overlay { MiddleClickCatcher { model.closeTab(url) } }   // 가운데 클릭 닫기
        .onHover { hovering = $0; if $0 { tip = tooltip } }
        .help(tip)
        .contextMenu {
            Button("Close Tab") { model.closeTab(url) }
            Button("Close Other Tabs") { model.closeOtherTabs(except: url) }
            Button("Close Tabs to the Left") { model.closeTabs(toLeftOf: url) }
            Button("Close Tabs to the Right") { model.closeTabs(toRightOf: url) }
            Button("Close All Tabs") { model.closeAllTabs() }
            Button("Reopen Last Closed Tab") { model.reopenLastClosedTab() }.disabled(model.closedTabs.isEmpty)
            Divider()
            Button("Save") { model.saveNow() }.disabled(!isActive)   // 다른 탭은 떠날 때 저장됐다
            Button("Save and Close") { model.saveAndCloseTab(url) }
            Button("Revert to Saved") { model.reloadFromDisk() }.disabled(!isActive)
            Divider()
            Button("Copy Path") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string) }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Divider()
            Menu("Sort Tabs") {
                Button("By Name") { model.sortTabs(by: .name) }
                Button("By Path") { model.sortTabs(by: .path) }
                Button("By Extension") { model.sortTabs(by: .ext) }
                Button("By Modification Date") { model.sortTabs(by: .modified) }
            }
        }
        .onDrag {
            let provider = NSItemProvider()
            let path = Data(url.path.utf8)
            provider.registerDataRepresentation(forTypeIdentifier: UTType.hyperEditTab.identifier, visibility: .ownProcess) { done in done(path, nil); return nil }
            return provider
        }
        .onDrop(of: [.hyperEditTab], delegate: DocumentTabDrop(model: model, target: url))
    }
}

/// 탭 드래그 앤 드롭: 끌어온 탭(경로)을 놓은 탭의 자리로
struct DocumentTabDrop: DropDelegate {
    let model: AppModel
    let target: URL

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [.hyperEditTab]).first else { return false }
        _ = item.loadDataRepresentation(forTypeIdentifier: UTType.hyperEditTab.identifier) { data, _ in
            guard let data, let path = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                guard let src = model.tabs.first(where: { $0.path == path }), src != target, let to = model.tabs.firstIndex(of: target) else { return }
                model.moveTab(src, to: to)
            }
        }
        return true
    }
}

/// 가운데 클릭만 받는 투명 뷰 — hitTest 때 현재 이벤트가 가운데 버튼이면 자신을, 아니면 nil 을 돌려 SwiftUI 제스처(클릭·드래그)를 가리지 않는다
struct MiddleClickCatcher: NSViewRepresentable {
    let onMiddleClick: () -> Void

    func makeNSView(context: Context) -> CatcherView { let v = CatcherView(); v.onMiddleClick = onMiddleClick; return v }
    func updateNSView(_ v: CatcherView, context: Context) { v.onMiddleClick = onMiddleClick }

    final class CatcherView: NSView {
        var onMiddleClick: (() -> Void)?
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let e = NSApp.currentEvent, e.type == .otherMouseDown || e.type == .otherMouseUp || e.type == .otherMouseDragged, e.buttonNumber == 2 else { return nil }
            return super.hitTest(point)
        }
        override func otherMouseDown(with event: NSEvent) { if event.buttonNumber == 2 { onMiddleClick?() } else { super.otherMouseDown(with: event) } }
    }
}
