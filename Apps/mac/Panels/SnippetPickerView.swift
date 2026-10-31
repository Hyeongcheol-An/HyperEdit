import SwiftUI
import HyperCore

/// 스니펫 선택창(⇧⌘I): 필터 상자 + 목록(제목·트리거·본문 첫 줄). Enter 로 삽입, Esc 로 닫기, ↑↓ 로 이동, 더블클릭 삽입.
struct SnippetPickerView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var store: SnippetStore
    @State private var filter = ""
    @State private var selected: String?
    @FocusState private var filterFocused: Bool

    private var filtered: [Snippet] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return store.snippets }
        return store.snippets.filter {
            $0.trigger.localizedCaseInsensitiveContains(q) || $0.title.localizedCaseInsensitiveContains(q) || $0.body.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Insert Snippet").font(.headline)
            TextField("Filter by trigger, title or text", text: $filter)
                .textFieldStyle(.roundedBorder)
                .focused($filterFocused)
                .onSubmit { insertSelected() }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
            List(filtered, selection: $selected) { s in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.title.isEmpty ? s.trigger : s.title).font(.system(size: 12, weight: .medium))
                        Text(preview(s.body)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(s.trigger)
                        .font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .tag(s.id)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.insertSnippet(s) }
                .onTapGesture { selected = s.id }
            }
            .frame(minHeight: 200)
            .overlay {   // 빈 상태: 스니펫이 하나도 없거나 필터에 맞는 것이 없을 때 (빈 목록만 보이지 않도록)
                if filtered.isEmpty {
                    Text(store.snippets.isEmpty ? "No snippets yet — Edit Snippets… adds the file" : "No snippets match the filter")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .onKeyPress(.return) { insertSelected(); return .handled }
            if let e = store.lastError {
                Text(e).font(.system(size: 11)).foregroundStyle(.red).lineLimit(2)
            } else {
                Text("Tip: type a trigger such as todo in the editor and press Tab. Tab / ⇧Tab move between $1 … $9 placeholders, Esc ends.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            HStack {
                Button("Edit Snippets…") { model.editSnippets() }
                    .help(store.fileURL.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                Spacer()
                Button("Cancel", role: .cancel) { model.showSnippetPicker = false }.keyboardShortcut(.cancelAction)
                Button("Insert") { insertSelected() }.disabled(selected == nil)
            }
        }
        .padding(16)
        .frame(width: 480, height: 400)
        .onAppear {
            store.reloadIfChanged()
            selected = filtered.first?.id
            filterFocused = true
        }
        .onChange(of: filter) { _, _ in
            if !filtered.contains(where: { $0.id == selected }) { selected = filtered.first?.id }
        }
    }

    private func preview(_ body: String) -> String {
        let first = body.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return body.contains("\n") ? first + " …" : first
    }

    private func move(_ step: Int) {
        let list = filtered
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == selected } ?? -1
        selected = list[max(0, min(list.count - 1, i + step))].id
    }

    private func insertSelected() {
        guard model.showSnippetPicker else { return }   // Enter 가 onSubmit 과 기본 버튼 양쪽으로 와도 한 번만
        guard let id = selected, let s = filtered.first(where: { $0.id == id }) ?? filtered.first else { return }
        model.insertSnippet(s)
    }
}
