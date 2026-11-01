import SwiftUI
import AppKit
import HyperCore

// 비밀 블록(```secret 펜스) 셀프테스트 (runLanguage 뒤에 돈다). 임시 샘플 끝에 블록(펜스 + 내용 3줄 + 펜스 + 뒤 1줄)을 붙여
// 범위 인식·MaskedLayoutFragment·캐럿 진입/이탈·편집 뒤 오프셋 추적·undo·Reveal Secrets 토글과 자동 재마스킹(0.5초 주입)·
// 클립보드 자동 소거(0.3초 주입, 복사·멀티 캐럿·잘라내기, 다른 복사는 건드리지 않음)·찾기 결과/아웃라인 redaction·접기 공존·설정 끄기·분할 보기·
// 타이핑 지연을 검사한 뒤 블록을 지우고 클립보드를 복원한다.
extension SelfTest {
    @MainActor
    static func runSecrets(model: AppModel, check: (Bool, String) -> Void, log: (String) -> Void) async {
        func wait(_ ms: UInt64) async { pumpEvent(); try? await Task.sleep(nanoseconds: ms * 1_000_000) }   // 이벤트를 흘려 undo 그룹을 닫는다
        func text() -> NSString { model.document.textStorage.string as NSString }
        func lineStart(_ line: Int) -> Int {
            let idx = LineIndex(nsString: text())
            return idx.lineStarts[max(0, min(line - 1, idx.lineCount - 1))]
        }
        /// 줄의 글자 범위 (개행 제외)
        func lineRange(_ line: Int) -> NSRange {
            let ns = text()
            var r = NSIntersectionRange(LineIndex(nsString: ns).range(ofLine: line), NSRange(location: 0, length: ns.length))
            if r.length > 0, ns.character(at: NSMaxRange(r) - 1) == 10 { r.length -= 1 }
            return r
        }
        func activeTV() -> HyperTextView? { model.session.active?.textView }
        func masked(_ line: Int, in tv: HyperTextView? = nil) -> Bool { (tv ?? activeTV())?.isOffsetMasked?(lineStart(line)) ?? false }
        /// 줄의 레이아웃 프래그먼트 종류: masked / folded / plain
        func fragmentKind(_ line: Int, in tv: HyperTextView? = nil) -> String {
            guard let tv = tv ?? activeTV(), let lm = tv.textLayoutManager, let cs = tv.textContentStorage,
                  let loc = cs.location(cs.documentRange.location, offsetBy: lineStart(line)) else { return "none" }
            lm.ensureLayout(for: NSTextRange(location: loc))
            guard let f = lm.textLayoutFragment(for: loc) else { return "none" }
            if f is MaskedLayoutFragment { return "masked" }
            if f is FoldedLayoutFragment { return "folded" }
            return "plain"
        }
        func fragmentHeight(_ line: Int) -> CGFloat {
            guard let tv = activeTV(), let lm = tv.textLayoutManager, let cs = tv.textContentStorage,
                  let loc = cs.location(cs.documentRange.location, offsetBy: lineStart(line)) else { return -1 }
            lm.ensureLayout(for: NSTextRange(location: loc))
            return lm.textLayoutFragment(for: loc)?.layoutFragmentFrame.height ?? -1
        }
        func recentOutput(_ n: Int) -> [String] { model.output.suffix(n).map(\.text) }
        /// 복사 흉내: 선택 뒤 copy(_:) (멀티 캐럿은 setMulti)
        func copyLine(_ line: Int) { model.send(.perform { tv in tv.setSelectedRange(lineRange(line)); tv.copy(nil) }) }

        let store = model.secrets
        let pb = NSPasteboard.general
        let savedClipboard = pb.string(forType: .string)
        store.maskEnabled = true
        store.remaskAll(automatic: false, quiet: true)
        store.remaskDelayOverride = 0.5
        store.clipboardClearDelayOverride = 0.3
        model.send(.unfoldAll)
        model.jump(toLine: 1); await wait(200)

        // 0. 블록 추가 (undo 경계는 runFold 와 같이 undo → redo 한 쌍)
        let insertAt = text().length
        let block = "\n```secret bank\nPIN 1234\nACCOUNT 9876\n## Secret heading\n```\nafter-secret"
        model.send(.perform { tv in tv.breakUndoCoalescing(); tv.insertText(block, replacementRange: NSRange(location: insertAt, length: 0)) })
        await wait(500)
        model.send(.undo); await wait(300); model.send(.redo); await wait(900)   // 줄 인덱스 250 ms + 백그라운드 스캔
        model.jump(toLine: 1); await wait(200)
        let total = LineIndex(nsString: text()).lineCount
        let fence = total - 5, pin = total - 4, acct = total - 3, heading = total - 2, closing = total - 1, after = total
        log("secrets: appended block, fence line \(fence), \(store.blockCount) block(s)")
        check(store.blockCount == 1, "secrets: controller recognises one block (count \(store.blockCount))")
        check(masked(pin) && masked(acct) && masked(heading) && !masked(fence) && !masked(closing) && !masked(after),
              "secrets: content lines masked, fence lines and the line after stay visible")
        check(fragmentKind(pin) == "masked" && fragmentKind(fence) == "plain",
              "secrets: TextKit 2 fragment of a secret line is MaskedLayoutFragment (pin \(fragmentKind(pin)), fence \(fragmentKind(fence)))")
        check(fragmentHeight(pin) > 0 && abs(fragmentHeight(pin) - fragmentHeight(fence)) < 0.5,
              "secrets: masked fragment keeps the normal line height (\(fragmentHeight(pin)) vs \(fragmentHeight(fence)))")
        check((text() as String).contains("PIN 1234"), "secrets: storage text is untouched (display only)")

        // 1. 캐럿 진입 → 블록 전체 드러남, 이탈 → 다시 가림
        model.jump(toLine: pin); await wait(300)
        check(!masked(pin) && !masked(acct) && !masked(heading) && fragmentKind(pin) == "plain" && fragmentKind(heading) == "plain",
              "secrets: caret inside a secret line reveals the whole block")
        model.jump(toLine: 1); await wait(300)
        check(masked(pin) && masked(acct) && fragmentKind(pin) == "masked", "secrets: caret leaving the block masks it again")

        // 2. 블록 안에서 줄 추가 → 새 줄도 비밀 (스캔 전 오프셋 추적 + 스캔 뒤), undo 로 복구
        model.jump(toLine: acct); await wait(200)
        model.send(.perform { tv in
            let r = lineRange(acct)
            tv.setSelectedRange(NSRange(location: NSMaxRange(r), length: 0))
            tv.insertText("\nTOKEN abc", replacementRange: tv.selectedRange())
        })
        await wait(100)
        model.jump(toLine: 1); await wait(100)   // 스캔(250 ms) 전 — 편집 추적만으로 가려져야 한다
        check(masked(acct + 1) && masked(heading + 1) && !masked(closing + 1), "secrets: a line typed inside the block is masked before the rescan")
        await wait(900)
        check(masked(acct + 1) && masked(heading + 1) && !masked(closing + 1) && store.blockCount == 1, "secrets: …and after the rescan")
        model.send(.undo); await wait(600)
        model.jump(toLine: 1); await wait(200)
        check(LineIndex(nsString: text()).lineCount == total && masked(heading) && !masked(closing), "secrets: undo removes the line, block offsets follow (post-edit tracking)")

        // 3. 위에 줄 삽입 → 범위가 따라 내려감 (스캔 전), undo → 제자리
        model.send(.perform { tv in tv.insertText("inserted\n", replacementRange: NSRange(location: 0, length: 0)) }); await wait(100)
        check(masked(pin + 1) && !masked(fence + 1) && masked(heading + 1), "secrets: inserting a line above shifts the block down")
        model.send(.undo); await wait(600)
        model.jump(toLine: 1); await wait(200)
        check(masked(pin) && !masked(fence) && masked(heading), "secrets: undo moves the block back")

        // 4. Reveal Secrets (⌥⌘S) → 전부 드러남, 0.5 초 뒤 자동 재마스킹 · 수동 토글
        store.toggleRevealAll(); await wait(200)
        check(store.revealedAll && !masked(pin) && fragmentKind(pin) == "plain", "secrets: Reveal Secrets shows every block")
        await wait(900)
        check(!store.revealedAll && masked(pin) && fragmentKind(pin) == "masked", "secrets: masked again automatically after the delay")
        let out = recentOutput(8)
        check(out.contains { $0.localizedCaseInsensitiveContains("revealed") || $0.contains("드러") } && out.contains { $0.contains("masked again") || $0.contains("다시 가") },
              "secrets: reveal and automatic re-mask are logged")
        store.remaskDelayOverride = 0   // Never
        store.toggleRevealAll(); await wait(200)
        check(store.revealedAll && !masked(acct), "secrets: with Re-mask after = Never the reveal stays")
        store.toggleRevealAll(); await wait(200)
        check(!store.revealedAll && masked(acct) && fragmentKind(acct) == "masked", "secrets: toggling again masks at once")
        store.remaskDelayOverride = 0.5

        // 5. 클립보드 자동 소거 (0.3 초 주입)
        pb.clearContents(); pb.setString("before", forType: .string)
        copyLine(pin)
        check(pb.string(forType: .string) == "PIN 1234" && store.clipboardClearPending, "secrets: copying a secret line puts it on the clipboard and schedules clearing")
        await wait(700)
        check(pb.string(forType: .string) == nil && !store.clipboardClearPending, "secrets: clipboard cleared after the delay (now: \(pb.string(forType: .string) ?? "nil"))")
        check(recentOutput(4).contains { $0.contains("Clipboard cleared") || $0.contains("클립보드") }, "secrets: clipboard clearing is logged")
        copyLine(pin)
        copyLine(after)   // 지연 중 비밀이 아닌 복사 → 건드리지 않는다
        await wait(700)
        check(pb.string(forType: .string) == "after-secret", "secrets: a later non-secret copy is left alone (\(pb.string(forType: .string) ?? "nil"))")
        copyLine(after)
        check(!store.clipboardClearPending, "secrets: copying a non-secret line schedules nothing")
        model.send(.perform { tv in tv.setMulti([lineRange(after), lineRange(acct)]); tv.copy(nil); tv.clearMulti() })   // 멀티 캐럿 복사 경로
        check(pb.string(forType: .string)?.contains("ACCOUNT 9876") == true && store.clipboardClearPending, "secrets: multi-caret copy containing a secret schedules clearing")
        await wait(700)
        check(pb.string(forType: .string) == nil, "secrets: multi-caret copy is cleared too")
        model.send(.perform { tv in tv.setSelectedRange(lineRange(pin)); tv.cut(nil) }); await wait(200)   // 잘라내기 경로
        check(!(text() as String).contains("PIN 1234") && pb.string(forType: .string) == "PIN 1234", "secrets: cut removes the secret line and puts it on the clipboard")
        await wait(600)
        check(pb.string(forType: .string) == nil, "secrets: cut secret is cleared")
        model.send(.undo); await wait(600)
        model.jump(toLine: 1); await wait(200)
        check((text() as String).contains("PIN 1234") && masked(pin), "secrets: undo restores the cut line, still masked")

        // 6. 찾기 결과 redaction (매치·줄 번호는 그대로, 미리보기 텍스트만 마스크)
        model.searchQuery = "9876"; model.runSearch(); await wait(700)
        let hit = model.searchHits.first
        check(model.searchHits.count == 1 && hit?.lineText == SecretScanner.defaultMask && hit?.line == acct,
              "secrets: find result of a secret line shows •••••••• (\(hit?.lineText ?? "none"), line \(hit?.line ?? 0))")
        model.searchQuery = "after-secret"; model.runSearch(); await wait(700)
        check(model.searchHits.first?.lineText.contains("after-secret") == true, "secrets: non-secret result text is unchanged")

        // 7. 아웃라인: 블록 안 헤딩 제외 · redacted 텍스트
        model.rescanStructure(); await wait(500)
        check(!model.outline.contains { $0.title.contains("Secret heading") } && model.outline.contains { $0.title.contains("Real heading") },
              "secrets: heading inside a secret block is left out of the outline")
        let redacted = SecretScanner.redacted(text() as String)
        check(!redacted.contains("PIN 1234") && !redacted.contains("Secret heading") && redacted.contains("after-secret") && LineIndex(text: redacted).lineCount == total,
              "secrets: redacted text keeps line count and hides secret lines")

        // 8. 접기 공존: 펜스 영역을 접으면 높이 0 (접힘 우선), 펼치면 다시 가림
        model.jump(toLine: fence); await wait(300)
        model.send(.fold); await wait(300)
        check((activeTV()?.isOffsetHidden?(lineStart(pin)) ?? false) && fragmentKind(pin) == "folded",
              "secrets: a secret block folds like any fence (hidden fragment wins, \(fragmentKind(pin)))")
        model.send(.unfoldAll); await wait(300)
        model.jump(toLine: 1); await wait(200)
        check(masked(pin) && fragmentKind(pin) == "masked", "secrets: unfolded block is masked again")

        // 9. 설정 끄기 / 켜기
        store.maskEnabled = false; await wait(300)
        check(!masked(pin) && fragmentKind(pin) == "plain" && store.blockCount == 0, "secrets: masking off shows the lines")
        check(AppDefaults.store.object(forKey: SecretsStore.maskKey) as? Bool == false, "secrets: setting persisted to secrets.mask")
        store.maskEnabled = true; await wait(300)
        check(masked(pin) && fragmentKind(pin) == "masked" && store.blockCount == 1, "secrets: masking on masks them again at once")

        // 10. 분할 보기: 보조 편집기도 같은 블록을 가린다 (뷰별 컨트롤러)
        let session = model.session
        session.splitMode = .vertical; await wait(700)
        let secondaryTV = session.secondary?.textView
        check(secondaryTV != nil && masked(pin, in: secondaryTV) && fragmentKind(pin, in: secondaryTV) == "masked",
              "secrets: secondary editor masks the block too (\(fragmentKind(pin, in: secondaryTV)))")
        session.splitMode = .none; await wait(500)
        model.jump(toLine: 1); await wait(200)

        // 11. 성능: 가림이 있는 상태에서 타이핑 40타 (layout delegate 가 문단마다 호출된다)
        model.goToEnd(); await wait(200)
        let t1 = CFAbsoluteTimeGetCurrent()
        for _ in 0..<40 {
            model.send(.perform { tv in tv.insertText("a", replacementRange: tv.selectedRange()) })
            await wait(1)
        }
        let typingMs = (CFAbsoluteTimeGetCurrent() - t1) * 1000 / 40 - 1
        log(String(format: "perf typing with secrets %.2f ms/keystroke (incl. run loop)", typingMs))
        check(typingMs < 16, "secrets: typing latency under one frame with the mask delegate installed")
        model.jump(toLine: 1); await wait(200)
        check(masked(pin), "secrets: typing after the block keeps it masked")

        // 12. 설정 섹션 렌더 — 설정 창은 800 pt 고정이라 아래쪽 섹션이 스크롤 밖에 있다: 작은 창에 따로 그려 확인하고 --selftest-out 옆에 PNG 로 남긴다
        let settingsHost = NSHostingView(rootView: Form { SecretsSettingsSection(store: store) }.formStyle(.grouped).frame(width: 560))
        let settingsWindow = NSWindow(contentRect: NSRect(x: 40, y: 80, width: 560, height: 340), styleMask: [.titled], backing: .buffered, defer: false)
        settingsWindow.title = "Settings · Secrets"
        settingsWindow.contentView = settingsHost
        settingsWindow.orderFront(nil); await wait(400)
        let fit = settingsHost.fittingSize
        check(fit.height > 150 && fit.height < 700, "secrets: settings section renders (\(Int(fit.width))×\(Int(fit.height)) pt)")
        if let outPath, let rep = settingsHost.bitmapImageRepForCachingDisplay(in: settingsHost.bounds) {
            settingsHost.cacheDisplay(in: settingsHost.bounds, to: rep)
            let png = (outPath as NSString).deletingPathExtension + "-settings.png"
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: png))
            log("secrets: settings section rendered to \(png)")
        }
        settingsWindow.orderOut(nil); settingsWindow.contentView = nil

        // 원상복구: 블록(+타이핑)을 지우고 클립보드·지연 주입을 되돌린다
        model.send(.perform { tv in
            let len = (tv.string as NSString).length
            tv.breakUndoCoalescing()
            tv.insertText("", replacementRange: NSRange(location: insertAt, length: len - insertAt))
        }); await wait(700)
        check(text().length == insertAt && store.blockCount == 0, "secrets: sample restored (length \(text().length), blocks \(store.blockCount))")
        pb.clearContents()
        if let s = savedClipboard { pb.setString(s, forType: .string) }
        store.remaskDelayOverride = nil
        store.clipboardClearDelayOverride = nil
    }
}
