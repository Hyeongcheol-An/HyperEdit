import SwiftUI
import AppKit
import Combine
import HyperCore

/// 분할 보기 — 같은 문서를 보여 주는 편집기 배치
enum SplitMode: String, CaseIterable {
    case none, vertical, horizontal
}

/// 편집기 역할. 주 편집기는 창 제목·보기 위치 저장·검색 강조(스토리지 속성)·테마 전체 적용을 맡고, 보조 편집기는 분할이 켜질 때만 존재한다.
enum EditorRole { case primary, secondary }

/// 같은 문서를 여러 텍스트 뷰로 보여 주기 위한 공유 상태 (TextKit 2: NSTextContentStorage 하나 ← NSTextLayoutManager 여럿).
/// - NSTextStorage 는 TextKit 2 관찰자(NSTextContentStorage)를 하나만 허용하므로 문서 스토리지에 콘텐츠 스토리지를 하나만 붙이고, 뷰마다 레이아웃 매니저만 붙인다.
/// - undo 는 하나의 NSUndoManager 를 모든 뷰가 쓴다 (A 에서 입력, B 에서 ⌘Z). 뷰 사이에 포커스가 옮겨지면 입력 그룹 병합을 끊는다.
/// - 명령(`EditorCommand`)·캐럿 상태는 마지막으로 포커스/클릭된 '활성' 편집기 기준. 아직 없으면 주 편집기.
@MainActor
final class EditorSession: ObservableObject {
    let contentStorage = NSTextContentStorage()
    let undoManager = UndoManager()
    /// 마지막으로 포커스/클릭된 편집기 — 명령·캐럿 상태는 이 편집기 기준
    var activeEditorID: UUID?
    @Published var splitMode: SplitMode {
        didSet {
            AppDefaults.store.set(splitMode.rawValue, forKey: "ui.splitMode")
            if splitMode != .none { lastOrientation = splitMode }
        }
    }
    /// 분할을 다시 켤 때 쓸 마지막 방향 (기본 좌우)
    private(set) var lastOrientation: SplitMode = .vertical

    private struct Entry { weak var coordinator: EditorView.Coordinator? }
    private var entries: [Entry] = []          // 등록 순서 (주 편집기가 먼저)
    /// 분할을 닫은 보조 편집기 — 공유 undo 스택에 그 뷰가 만든 항목이 남아 있는 동안 살려 둔다 (`retire` 참고)
    private var retired: [EditorView.Coordinator] = []
    private var retiredViews: [HyperTextView] = []

    init() {
        let raw = AppDefaults.store.string(forKey: "ui.splitMode") ?? ""
        splitMode = SplitMode(rawValue: raw) ?? .none
        if splitMode != .none { lastOrientation = splitMode }
    }

    // MARK: 등록

    func register(_ c: EditorView.Coordinator) {
        entries.removeAll { $0.coordinator == nil || $0.coordinator === c }
        entries.append(Entry(coordinator: c))
        registry.append(Entry(coordinator: c))
    }

    // MARK: 진단 (셀프테스트 · --debug-perf) — 분할을 여닫을 때 코디네이터·텍스트 뷰가 새는지 센다. 약한 참조뿐이라 비용은 없다.

    /// 지금까지 등록된 모든 코디네이터의 약한 참조 (해제된 항목은 셀 때 걷어낸다)
    private var registry: [Entry] = []
    func liveCoordinatorCount() -> Int { registry.removeAll { $0.coordinator == nil }; return registry.count }
    func liveTextViewCount() -> Int { registry.compactMap(\.coordinator).filter { $0.textView != nil }.count }
    /// 공유 undo 항목 때문에 보관 중인 닫힌 보조 편집기 수
    var retiredCount: Int { retired.count }

    /// 살아 있는 편집기들 (주 편집기 먼저)
    var coordinators: [EditorView.Coordinator] { entries.compactMap(\.coordinator).filter { $0.textView != nil } }
    var primary: EditorView.Coordinator? { coordinators.first { $0.role == .primary } }
    var secondary: EditorView.Coordinator? { coordinators.first { $0.role == .secondary } }
    /// 활성 편집기 — 없거나 사라졌으면 주 편집기
    var active: EditorView.Coordinator? {
        if let id = activeEditorID, let c = coordinators.first(where: { $0.id == id }) { return c }
        return primary
    }
    func isActive(_ c: EditorView.Coordinator) -> Bool { active === c }

    /// 포커스/클릭으로 활성 편집기가 바뀜. 다른 뷰의 입력 undo 그룹을 끊어 두 뷰의 입력이 한 undo 항목으로 섞이지 않게 한다.
    func activate(_ c: EditorView.Coordinator) {
        guard activeEditorID != c.id else { return }
        for other in coordinators where other !== c { other.textView?.breakUndoCoalescing() }
        activeEditorID = c.id
    }

    /// 문서 스토리지를 공유 콘텐츠 스토리지에 연결 — 뷰가 몇 개든 한 번만 (반복 교체는 TextKit 2 레이아웃을 퇴화시킨다, MemoDocument.switchTo 주석)
    func bind(textStorage: NSTextStorage) {
        guard contentStorage.textStorage !== textStorage else { return }
        contentStorage.textStorage = textStorage
    }

    /// 어느 뷰에서든 편집이 일어나면: 주 편집기의 검색 강조(스토리지 속성)는 낡았으니 걷어내고, 다른 뷰의 거터를 다시 그린다
    func didEdit(from c: EditorView.Coordinator) {
        for other in coordinators where other !== c {
            other.gutter?.needsDisplay = true
            if other.role == .primary { other.clearMatchHighlights() }
        }
    }

    /// 보조 편집기가 사라질 때. 그 뷰에서 한 편집의 undo 항목이 공유 스택에 남아 있을 수 있으므로 텍스트 뷰·레이아웃 매니저를 바로 버리지 않고
    /// 다음 `clearUndo()`(파일 전환·다시 읽기)까지 보관한다 — AppKit 의 undo 항목은 편집한 뷰를 통해 되돌리기 때문.
    /// undo 스택이 비어 있으면 바로 놓아 주고, 보관이 `maxRetired`(20) 를 넘으면(파일 전환 없이 분할을 아주 여러 번 여닫음) 스택을 비우고 전부 놓아 준다.
    func retire(_ c: EditorView.Coordinator) {
        entries.removeAll { $0.coordinator == nil || $0.coordinator === c }
        if activeEditorID == c.id { activeEditorID = primary?.id }
        if let tv = c.textView {
            if undoManager.canUndo || undoManager.canRedo {
                tv.retireFromEditing()   // undo 재생용으로만 보관 — 편집 관찰자·훅을 끊어 편집 비용이 늘지 않게
                retired.append(c)
                retiredViews.append(tv)
                if retiredViews.count > Self.maxRetired { clearUndo() }
            } else if let lm = tv.textLayoutManager, lm.textContentManager === contentStorage {
                contentStorage.removeTextLayoutManager(lm)
            }
        }
        if let p = primary?.textView, p.window?.firstResponder !== p { p.window?.makeFirstResponder(p) }
    }
    static let maxRetired = 20   // 보관 뷰 하나는 수백 KB — 분할을 자주 여닫아도 undo 스택을 지우지 않도록 넉넉히

    /// 공유 undo 스택 비우기 (파일 전환·디스크에서 다시 읽기). 이때 보관하던 옛 보조 뷰도 놓아 준다.
    func clearUndo() {
        undoManager.removeAllActions()
        for tv in retiredViews {
            if let lm = tv.textLayoutManager, lm.textContentManager === contentStorage { contentStorage.removeTextLayoutManager(lm) }
        }
        retiredViews.removeAll()
        retired.removeAll()
    }
}

// MARK: - 분할 명령 (AppModel)

extension AppModel {
    /// ⌘\ — 끄기 ↔ 마지막 방향(기본 좌우)
    func toggleSplit() {
        setSplit(session.splitMode == .none ? session.lastOrientation : .none)
    }

    func setSplit(_ mode: SplitMode) {
        guard session.splitMode != mode else { return }
        session.splitMode = mode
        switch mode {
        case .none: log(String(localized: "Split editor off"))
        case .vertical: log(String(localized: "Split editor: side by side"))
        case .horizontal: log(String(localized: "Split editor: stacked"))
        }
    }

    /// 리본의 방향 버튼: 좌우 ↔ 상하 (꺼져 있으면 마지막 방향과 반대가 아니라 마지막 방향으로 켠다)
    func cycleSplitOrientation() {
        switch session.splitMode {
        case .none: setSplit(session.lastOrientation)
        case .vertical: setSplit(.horizontal)
        case .horizontal: setSplit(.vertical)
        }
    }

    /// ⌥⌘\ — 다른 분할로 포커스 이동 (분할이 꺼져 있으면 켠다)
    func focusOtherSplit() {
        if session.splitMode == .none { toggleSplit(); return }
        let cs = session.coordinators
        guard cs.count > 1 else { return }
        let target = cs.first { !session.isActive($0) } ?? cs[0]
        if let tv = target.textView { tv.window?.makeFirstResponder(tv) }
    }

    /// `--split [vertical|horizontal]` (스크린샷용)
    func applySplitLaunchOptions() {
        guard LaunchOptions.has("--split") else { return }
        let v = LaunchOptions.value("--split") ?? ""
        setSplit(SplitMode(rawValue: v).flatMap { $0 == .none ? nil : $0 } ?? .vertical)
    }
}

// MARK: - 편집 영역 (주 편집기 + 선택적 보조 편집기)

/// 주 편집기는 항상 `HSplitView > VSplitView` 의 첫 자식 — 분할을 켜고 끄거나 방향을 바꿔도 SwiftUI 정체성이 유지되어
/// 텍스트 뷰·undo 스택이 다시 만들어지지 않는다 (ContentView 의 미리보기 트릭과 같은 원리). 보조 편집기만 생겼다 사라진다.
struct SplitEditorArea: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: EditorSession
    let theme: Theme
    let font: FontSettings

    var body: some View {
        HSplitView {
            VSplitView {
                EditorView(document: model.document, theme: theme, font: font, role: .primary)
                    .frame(minWidth: 280, minHeight: 120)
                if session.splitMode == .horizontal {
                    EditorView(document: model.document, theme: theme, font: font, role: .secondary)
                        .frame(minWidth: 280, minHeight: 120)
                }
            }
            if session.splitMode == .vertical {
                EditorView(document: model.document, theme: theme, font: font, role: .secondary)
                    .frame(minWidth: 280, minHeight: 120)
            }
        }
    }
}
