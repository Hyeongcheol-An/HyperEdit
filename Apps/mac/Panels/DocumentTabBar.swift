import SwiftUI
import AppKit
import HyperCore
import UniformTypeIdentifiers

/// UltraEdit 식 파일 탭 바 (docs/tabs-model.ko.md): 열린 파일마다 탭 하나. 클릭 전환, × · 더블클릭 · 가운데 클릭으로 닫기, 드래그로 순서 바꾸기,
/// 우클릭 메뉴, 툴팁은 전체 경로·크기·수정 시각, 빈 곳 더블클릭은 새 문서, 오른쪽 끝 ▾ 는 열린 탭 목록(탭이 넘칠 때).
/// 탭은 파일 경로(`AppModel.tabs`)이고 살아 있는 문서는 하나다 — 탭을 바꾸면 그 문서가 파일을 갈아탄다(`MemoDocument.switchTo`).
/// 그래서 수정됨 표시는 활성 탭에만 있다 (다른 탭은 떠날 때 저장됐다)
struct DocumentTabBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var doc: MemoDocument   // 활성 파일(url)·수정됨이 바뀌면 탭 줄을 다시 그린다
    let theme: Theme

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(model.tabs, id: \.self) { url in
                            DocumentTab(url: url, isActive: url == doc.url, isDirty: url == doc.url && doc.isDirty, theme: theme).id(url)
                        }
                    }
                }
                .onChange(of: doc.url) { _, u in proxy.scrollTo(u) }   // 활성 탭이 보이게
            }
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
                        Button { model.activateTab(url) } label: { Text((url == doc.url ? "• " : "") + url.lastPathComponent) }
                    }
                } label: { Image(systemName: "chevron.down").font(.system(size: 10)) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .foregroundStyle(theme.foregroundMuted.color).padding(.horizontal, 8).help("Open Tabs")
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
    let isActive: Bool
    let isDirty: Bool
    let theme: Theme
    @State private var hovering = false

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
            Text(url.lastPathComponent).font(.system(size: 12, weight: isActive ? .semibold : .regular)).lineLimit(1)
            ZStack {
                if isDirty && !hovering { Circle().fill(theme.accent.color).frame(width: 7, height: 7) }
                if hovering || (isActive && !isDirty) {
                    Button { model.closeTab(url) } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 12, height: 12) }
                        .buttonStyle(.plain).foregroundStyle(theme.foregroundMuted.color).help("Close Tab (⌘W)")
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
        .onTapGesture(count: 2) { model.closeTab(url) }   // 더블클릭 닫기 (UltraEdit 기본)
        .onTapGesture { model.activateTab(url) }
        .overlay { MiddleClickCatcher { model.closeTab(url) } }   // 가운데 클릭 닫기
        .onHover { hovering = $0 }
        .help(tooltip)
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
        .onDrag { NSItemProvider(object: url.path as NSString) }
        .onDrop(of: [.text], delegate: DocumentTabDrop(model: model, target: url))
    }
}

/// 탭 드래그 앤 드롭: 끌어온 탭(경로)을 놓은 탭의 자리로
struct DocumentTabDrop: DropDelegate {
    let model: AppModel
    let target: URL

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        guard let item = info.itemProviders(for: [.text]).first else { return false }
        item.loadObject(ofClass: NSString.self) { obj, _ in
            guard let path = obj as? String else { return }
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
