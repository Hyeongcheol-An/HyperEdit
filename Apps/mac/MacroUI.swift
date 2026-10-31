import SwiftUI
import HyperCore

// 매크로 UI: "매크로" 메뉴 · 편집 탭 리본 그룹 · 상태바 셀 · 알림창. 로직은 Editor/MacroRecorder.swift.
// UI 문자열은 영어 키(LocalizedStringKey) + Localizable.xcstrings 의 한국어 번역 (l10n/macro.ko.json).

/// `CommandMenu("Macro")` — HyperEditApp 의 "Line" 메뉴 다음
struct MacroCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandMenu("Macro") {
            MacroMenuItems(model: model, recorder: model.macros)
        }
    }
}

private struct MacroMenuItems: View {
    let model: AppModel
    @ObservedObject var recorder: MacroRecorder

    var body: some View {
        Button(recorder.isRecording ? "Stop Recording" : "Record Macro") { model.toggleMacroRecording() }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(recorder.isPlaying)
        Button("Play Macro") { model.playLastMacro() }
            .keyboardShortcut("m", modifiers: [.command, .option])
            .disabled(!recorder.hasLast || recorder.state != .idle)
        Button("Play Macro Multiple Times…") { recorder.showRepeatAlert = true }
            .disabled(!recorder.hasLast || recorder.state != .idle)
        Divider()
        Button("Save Last Macro As…") { recorder.saveName = ""; recorder.showSaveAlert = true }
            .disabled(!recorder.hasLast)
        if !recorder.store.macros.isEmpty {
            Divider()
            ForEach(recorder.store.macros) { m in
                Button(m.name) { model.playMacro(id: m.id, times: 1) }.disabled(recorder.state != .idle)
            }
            Divider()
            Menu("Delete Macro") {
                ForEach(recorder.store.macros) { m in
                    Button(m.name) { model.deleteMacro(id: m.id) }
                }
            }
        }
        Button("Edit Macros File…") { model.editMacrosFile() }
    }
}

/// 편집 탭 "매크로" 그룹: 큰 기록 버튼(기록 중 빨강) + 재생 / 여러 번 재생 / 이름 저장
struct MacroRibbonGroup: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    var body: some View { MacroRibbonGroupBody(model: model, recorder: model.macros, theme: theme) }
}

private struct MacroRibbonGroupBody: View {
    let model: AppModel
    @ObservedObject var recorder: MacroRecorder
    let theme: Theme
    @State private var hover = false

    var body: some View {
        RibbonGroup(title: "Macro", theme: theme) {
            Button { model.toggleMacroRecording() } label: {
                VStack(spacing: 3) {
                    Image(systemName: recorder.isRecording ? "stop.circle.fill" : "record.circle")
                        .font(.system(size: 22)).frame(height: 30)
                        .foregroundStyle(recorder.isRecording ? theme.errorColor.color : theme.foreground.color)
                    (recorder.isRecording ? Text("Stop") : Text("Record"))
                        .font(.system(size: 10.5)).multilineTextAlignment(.center).lineLimit(2)
                }
                .frame(width: 60, height: 64)
                .background(recorder.isRecording ? theme.errorColor.color.opacity(0.15) : (hover ? theme.backgroundElevated.color : Color.clear))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(recorder.isRecording ? theme.errorColor.color : Color.clear, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.foreground.color)
            .disabled(recorder.isPlaying)
            .onHover { hover = $0 }
            .help(recorder.isRecording ? "Stop recording (⇧⌘M)" : "Record typing, editing commands and text tools as a macro (⇧⌘M)")
            RibbonStack {
                RibbonSmallButton(title: "Play", systemImage: "play.fill", help: "Play the last recorded macro (⌥⌘M)", enabled: recorder.hasLast && recorder.state == .idle, theme: theme) { model.playLastMacro() }
                RibbonSmallButton(title: "Play N Times…", systemImage: "repeat", help: "Play the last macro several times — stops when a Find step finds nothing or a run changes nothing", enabled: recorder.hasLast && recorder.state == .idle, theme: theme) { recorder.showRepeatAlert = true }
                RibbonSmallButton(title: "Save As…", systemImage: "square.and.arrow.down.on.square", help: "Name the last recorded macro — it appears in the Macro menu", enabled: recorder.hasLast, theme: theme) { recorder.saveName = ""; recorder.showSaveAlert = true }
            }
        }
    }
}

/// 상태바: 기록 중 "● REC" (오류색), 재생 중 "▶ MACRO" (강조색). 유휴 상태에는 아무것도 그리지 않는다
struct MacroStatusCell: View {
    @ObservedObject var recorder: MacroRecorder
    let theme: Theme

    var body: some View {
        if recorder.state != .idle {
            let token = recorder.isRecording ? "● REC" : "▶ MACRO"   // COL · MD 처럼 번역하지 않는 상태 토큰
            Text(verbatim: token)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .frame(maxHeight: .infinity)
                .foregroundStyle(recorder.isRecording ? theme.errorColor.color : theme.accent.color)
                .overlay(alignment: .trailing) { theme.border.color.frame(width: 1).padding(.vertical, 4) }
                .help(recorder.isRecording ? "Recording a macro — ⇧⌘M stops" : "Playing a macro")
        }
    }
}

/// "여러 번 재생…" / "이름 저장…" 알림창 (ContentView 에 .modifier 로 붙인다)
struct MacroAlerts: ViewModifier {
    let model: AppModel
    @ObservedObject var recorder: MacroRecorder

    func body(content: Content) -> some View {
        content
            .alert("Play Macro Multiple Times", isPresented: $recorder.showRepeatAlert) {
                TextField("Times (1 ~ 10,000)", text: $recorder.repeatText)
                    .onSubmit { model.playLastMacroRepeated() }
                Button("Play") { model.playLastMacroRepeated() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Plays the last recorded macro the given number of times. Playback stops early when a Find step finds nothing or a run changes nothing. The whole run is one undo step.")
            }
            .alert("Save Macro", isPresented: $recorder.showSaveAlert) {
                TextField("Name", text: $recorder.saveName)
                    .onSubmit { model.saveLastMacro(name: recorder.saveName) }
                Button("Save") { model.saveLastMacro(name: recorder.saveName) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Saved macros are listed in the Macro menu and kept in ~/Library/Application Support/HyperEdit/macros/macros.json.")
            }
    }
}
