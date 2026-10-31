import AppKit
import HyperCore

extension SelfTest {
    /// 문서 dirty 추적: 텍스트 뷰를 거치지 않는 undo/redo(macOS 27 TextKit 2) 뒤에도 저장소 변경 알림으로 dirty 가 켜지고 저장이 따라와야 한다.
    @MainActor
    static func runDocumentTracking(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { pumpEvent(); try? await Task.sleep(nanoseconds: ms * 1_000_000) }   // 이벤트를 흘려 undo 그룹을 닫는다
        func disk() -> String { (try? String(contentsOf: model.document.url, encoding: .utf8)) ?? "" }
        let marker = "UNDO-DIRTY-\(Int(Date().timeIntervalSince1970))"
        model.goToEnd(); await wait(200)
        model.send(.perform { tv in tv.breakUndoCoalescing(); tv.insertText("\n" + marker, replacementRange: tv.selectedRange()) }); await wait(150)
        model.saveNow(); await wait(600)
        check(!model.document.isDirty && disk().contains(marker), "typed + saved → clean, marker on disk")
        model.send(.undo); await wait(300)
        let gone = !(model.document.textStorage.string as NSString).contains(marker)
        check(gone && model.document.isDirty, "undo after save → text reverted (\(gone)) and document dirty (\(model.document.isDirty))")
        model.saveNow(); await wait(600)
        check(!disk().contains(marker), "save after undo → marker removed from disk")
        // 원상복구: redo 로 마커를 되살리지 않는다 (샘플 끝 상태는 이후 검사에 영향 없음)
        _ = marker
    }
}
