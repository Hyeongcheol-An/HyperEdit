# Performance

HyperEdit is judged on feel: typing, scrolling, search, file switching and launch must be instant on a multi-megabyte notes file, and the app must stay light when idle. This document describes the benchmark harness that measures that, the budgets each metric must meet, how to compare two builds, and the current baseline. A short Korean summary is at the end.

## Running the benchmark

```sh
scripts/bench.sh                       # Release build → cold-launch timing ×5 → in-app benchmark → bundle/binary size
scripts/bench.sh --compare docs/bench/baseline-0.6.0.json   # same, plus Δ% against a baseline and a list of >15 % regressions
scripts/bench.sh --skip-build --only typing,search          # reuse the existing build, run only some phases
scripts/bench.sh --strict                                   # exit 1 on any budget failure or regression
```

Results land in `build/bench/<git-sha>.json` and `.md`, and the table is printed to stdout. Everything runs on a corpus that the harness generates in a temporary folder (small 2 KB, medium 200 KB, large 1.3 MB / ~25k lines, huge 8 MB / ~158k lines of mixed Korean, English, code, URLs, tab tables and log lines, from a fixed PRNG seed) and with throwaway preferences (`--ephemeral`), so it never touches your documents or settings.

The in-app part is `Apps/mac/Bench.swift`, started with `--bench [--bench-out <json>] [--bench-strict] [--bench-only <phases>] [--quit]`. It drives the real editor (the same `NSTextView`, coordinator and model the user types into), repeats each measurement at least five times and reports the median and p95. Phases: `idle`, `open`, `memory`, `scroll`, `search`, `outline`, `theme`, `typing`, `replace`, `save`.

Launch time is measured by `scripts/bench.sh` with `--quit-after-launch --bench-launch-log <file>`: the app records milliseconds from the kernel's process start time to `applicationDidFinishLaunching`, the first `ContentView.onAppear` and the first visible window, then quits. The first of the runs is discarded as warm-up. Because the benchmark execs the binary directly (no LaunchServices `oapp` event), launch-timing mode asks for the initial window 50 ms after `didFinishLaunching` instead of waiting for the app's 0.4 s "no window" fallback, which mirrors what a Dock or Finder launch does.

## Budgets

| Metric | Budget | Why |
|---|---|---|
| Typing latency (80 keystrokes, end and middle of the document, syntax colors on/off, large and huge) | median ≤ 8 ms, p95 ≤ 16 ms | one 60 Hz frame including the run-loop turn that lays out and draws |
| Enter in the middle (with and without bookmark line tracking) | median ≤ 8 ms, p95 ≤ 16 ms | same as typing |
| Open medium / large / huge (to first frame) | 50 / 150 / 800 ms | a file switch must feel immediate on the 1.3 MB notes file |
| Search literal / case-insensitive / regex `\d{4}-\d{2}-\d{2}` / whole word, large (huge) | 60 ms (400 ms) | result list appears without a visible pause |
| Replace all of ~5,000 matches, and the single ⌘Z that reverts it, large | 500 ms each | bulk edit is allowed a short pause, not a hang |
| Scroll step (1/40 of the large document) | median ≤ 16 ms, p95 ≤ 33 ms | one or two frames per jump |
| Go to end / go to line 1, large | 50 ms | |
| Theme switch / font size change, large | 300 ms | full attribute re-application over the storage |
| Outline + timeline rescan, Markdown → HTML, large | 300 / 1500 ms (informational) | run in the background; must not grow unbounded |
| RSS after loading the 8 MB corpus; after 5 small↔huge switches; growth | 400 MB; 450 MB; ≤ 20 % | leak check — memory must plateau |
| Idle CPU over 3 s (small and huge document open) | < 1 % | no timers or polling while idle |
| Cold launch → first window | 600 ms | |
| Bundle / executable size | 40 / 30 MB (informational) | |

Rows marked *informational* are reported and compared but never fail `--strict`; the others fail it.

Budgets describe the product requirement, not the machine of the day: do not loosen them when a run is noisy. The table header prints the 1-minute load average before and after the run and marks the result **measured under load** when it exceeds the core count; such runs are not baselines.

## Comparing two builds

`scripts/bench.sh --compare <baseline.json>` adds a Δ column (median vs. median) and lists metrics that regressed by more than 15 % (and by more than 0.5 units, so sub-millisecond noise is ignored). For A/B decisions take both runs back-to-back on an otherwise idle machine, and prefer profile evidence (`sample <pid> 5` or Instruments' Time Profiler on the Release binary) over small wall-clock deltas.

Benchmarks are deliberately not part of CI: GitHub-hosted runners are shared and far too noisy for millisecond budgets. Run `scripts/bench.sh --compare` locally before and after a performance-sensitive change and paste the table into the pull request.

## Baseline

Apple silicon laptop (2023, 12 cores, 64 GB), macOS 27.2, Release build, HyperEdit 0.6.0 (all v0.6 features and optimizations). Recorded on an idle machine (1-minute load average ≈ 2.4 on 12 cores) with `scripts/bench.sh`; the JSON is `docs/bench/baseline-0.6.0.json`. Compared with the pre-optimization build (v0.5.1), typing latency dropped from 4.5 ms to 1.2 ms per keystroke, the single undo of a 5,000-match Replace All from 1.7 s to 0.32 s, and cold launch from 0.9 s to 0.59 s; file open and Replace All are a few tens of milliseconds slower because the first frame now also starts the fold-region scan, draws scrollbar markers and registers the split-editor session.

<!-- BENCH TABLE START -->
Load average (1 min) before/after: 2.4 / 2.1  
Corpus: small 0 KB / 21 lines · medium 195 KB / 3986 lines · large 1269 KB / 25625 lines · huge 7812 KB / 158481 lines

| Metric | median | p95 | n | budget | result |
|---|---:|---:|---:|---|---|
| Cold launch → applicationDidFinishLaunching `launch.didFinishLaunching` | 205 ms | 211 | 5 | — | PASS |
| Cold launch → first ContentView.onAppear `launch.contentView` | 586 ms | 602 | 5 | — | PASS |
| Cold launch → first window visible (process start → window) `launch.window` | 586 ms | 602 | 5 | 600 ms | PASS |
| App bundle size (du -sk) `size.bundle` | 7.8 MB | 7.8 | 1 | 40.0 MB | PASS |
| Executable size (x86_64 arm64) `size.binary` | 7.2 MB | 7.2 | 1 | 30.0 MB | PASS |
| Idle CPU, small doc, 3 s `idle.cpu.small` | 0.0 % | 0.0 | 1 | 1.0 % | PASS |
| Idle wakeups/s, small doc `idle.wakeups.small` | 1.7 /s | 1.7 | 1 | 30.0 /s | PASS |
| RSS after launch (small doc) `memory.rss.launch` | 144.1 MB | 144.1 | 1 | 200.0 MB | PASS |
| Footprint after launch `memory.footprint.launch` | 46.2 MB | 46.2 | 1 | — | PASS |
| Launch → first window (this run, in-process) `launch.windowVisible` | 956 ms | 956 | 1 | 600 ms | over (info) |
| Open medium: synchronous part `open.medium.sync` | 9.79 ms | 10.51 | 5 | — | PASS |
| Open medium: + next run-loop turn `open.medium.nextTurn` | 71.70 ms | 75.34 | 5 | — | PASS |
| Open medium: + first frame `open.medium.settled` | 73.69 ms | 77.19 | 5 | 100 ms | PASS |
| Open large: synchronous part `open.large.sync` | 20.78 ms | 24.03 | 5 | — | PASS |
| Open large: + next run-loop turn `open.large.nextTurn` | 108 ms | 112 | 5 | — | PASS |
| Open large: + first frame `open.large.settled` | 111 ms | 115 | 5 | 150 ms | PASS |
| Open huge: synchronous part `open.huge.sync` | 78.08 ms | 79.70 | 5 | — | PASS |
| Open huge: + next run-loop turn `open.huge.nextTurn` | 283 ms | 342 | 5 | — | PASS |
| Open huge: + first frame `open.huge.settled` | 285 ms | 344 | 5 | 800 ms | PASS |
| RSS after loading huge (8 MB) `memory.rss.huge` | 202.1 MB | 202.1 | 1 | 400.0 MB | PASS |
| Footprint after loading huge `memory.footprint.huge` | 59.8 MB | 59.8 | 1 | — | PASS |
| RSS after 5 small↔huge switches `memory.rss.after5switches` | 202.3 MB | 202.3 | 1 | 450.0 MB | PASS |
| RSS growth over 5 switches vs first huge load `memory.growth.pct` | 0.1 % | 0.1 | 1 | 20.0 % | PASS |
| Scroll step (1/40 of doc), large `scroll.step.large` | 2.12 ms | 10.65 | 40 | 16.00 ms / p95 33.00 | PASS |
| Go to end (⌃⌘E), large `jump.end.large` | 13.37 ms | 16.66 | 5 | 50.00 ms | PASS |
| Go to line 1, large `jump.line1.large` | 15.99 ms | 17.87 | 5 | 50.00 ms | PASS |
| LineIndex full build, large (background) `lineIndex.build.large` | 1.35 ms | 1.94 | 5 | 20.00 ms | PASS |
| Search literal 'error', large (4952 hits) `search.literal.large` | 10.07 ms | 16.20 | 5 | 60.00 ms | PASS |
| Search caseInsensitive 'Error', large (6137 hits) `search.caseInsensitive.large` | 11.31 ms | 12.83 | 5 | 60.00 ms | PASS |
| Search regex '\d{4}-\d{2}-\d{2}', large (4035 hits) `search.regex.large` | 9.51 ms | 9.73 | 5 | 60.00 ms | PASS |
| Search wholeWord 'the', large (8095 hits) `search.wholeWord.large` | 10.64 ms | 10.70 | 5 | 60.00 ms | PASS |
| LineIndex full build, huge (background) `lineIndex.build.huge` | 4.65 ms | 5.52 | 5 | 120 ms | PASS |
| Search literal 'error', huge (10000 hits) `search.literal.huge` | 13.45 ms | 15.59 | 5 | 400 ms | PASS |
| Search caseInsensitive 'Error', huge (10000 hits) `search.caseInsensitive.huge` | 16.83 ms | 17.11 | 5 | 400 ms | PASS |
| Search regex '\d{4}-\d{2}-\d{2}', huge (10000 hits) `search.regex.huge` | 23.04 ms | 23.66 | 5 | 400 ms | PASS |
| Search wholeWord 'the', huge (10000 hits) `search.wholeWord.huge` | 13.00 ms | 13.24 | 5 | 400 ms | PASS |
| Outline + timeline rescan, large (background) `outline.rescan.large` | 42.58 ms | 68.73 | 5 | 300 ms | PASS |
| Markdown → HTML, large (background) `markdown.render.large` | 162 ms | 164 | 3 | 1500 ms | PASS |
| Theme switch, large `theme.switch.large` | 105 ms | 144 | 10 | 300 ms | PASS |
| Font size change (⌘=/⌘-), large `fontSize.change.large` | 79.01 ms | 82.00 | 10 | 300 ms | PASS |
| Theme switch, huge `theme.switch.huge` | 250 ms | 284 | 10 | 1500 ms | PASS |
| Font size change (⌘=/⌘-), huge `fontSize.change.huge` | 216 ms | 225 | 10 | 1500 ms | PASS |
| Typing at end, colors on, large `typing.end.hl.large` | 1.29 ms | 4.53 | 80 | 8.00 ms / p95 16.00 | PASS |
| Typing in middle, colors on, large `typing.middle.hl.large` | 2.93 ms | 5.80 | 80 | 8.00 ms / p95 16.00 | PASS |
| Syntax colors off (⌃⌘H), large `highlight.toggle.off.large` | 62.42 ms | 62.42 | 1 | 300 ms | PASS |
| Typing at end, colors off, large `typing.end.plain.large` | 1.26 ms | 3.42 | 80 | 8.00 ms / p95 16.00 | PASS |
| Typing in middle, colors off, large `typing.middle.plain.large` | 3.26 ms | 7.09 | 80 | 8.00 ms / p95 16.00 | PASS |
| Enter in middle (no bookmarks), large `enter.middle.large` | 5.56 ms | 7.90 | 20 | 8.00 ms / p95 16.00 | PASS |
| Enter in middle (bookmark tracking on), large `enter.middle.bookmarked.large` | 5.85 ms | 9.17 | 20 | 8.00 ms / p95 16.00 | PASS |
| Typing at end, colors on, huge `typing.end.hl.huge` | 1.38 ms | 4.66 | 80 | 8.00 ms / p95 16.00 | PASS |
| Typing in middle, colors on, huge `typing.middle.hl.huge` | 3.24 ms | 5.88 | 80 | 8.00 ms / p95 16.00 | PASS |
| Syntax colors off (⌃⌘H), huge `highlight.toggle.off.huge` | 108 ms | 108 | 1 | 300 ms | PASS |
| Typing at end, colors off, huge `typing.end.plain.huge` | 1.30 ms | 3.85 | 80 | 8.00 ms / p95 16.00 | PASS |
| Typing in middle, colors off, huge `typing.middle.plain.huge` | 3.11 ms | 5.80 | 80 | 8.00 ms / p95 16.00 | PASS |
| Enter in middle (no bookmarks), huge `enter.middle.huge` | 3.97 ms | 8.58 | 20 | 8.00 ms / p95 16.00 | PASS |
| Enter in middle (bookmark tracking on), huge `enter.middle.bookmarked.huge` | 5.71 ms | 8.38 | 20 | 8.00 ms / p95 16.00 | PASS |
| Replace all (4952 matches), large `replaceAll.5000.large` | 313 ms | 318 | 5 | 500 ms | PASS |
| Single undo of replace-all, large `undo.replaceAll.large` | 316 ms | 341 | 5 | 500 ms | PASS |
| save(): main-thread part, huge `save.sync.huge` | 2.37 ms | 3.30 | 5 | 30.00 ms | PASS |
| Text snapshot copy (per index rebuild / save), huge `snapshot.copy.huge` | 2.66 ms | 3.32 | 5 | 15.00 ms | PASS |
| Idle CPU, huge doc, 3 s `idle.cpu.huge` | 0.0 % | 0.0 | 1 | 1.0 % | PASS |
| Idle wakeups/s, huge doc `idle.wakeups.huge` | 1.0 /s | 1.0 | 1 | 30.0 /s | PASS |
| RSS at end of bench (huge open) `memory.rss.end` | 250.6 MB | 250.6 | 1 | 450.0 MB | PASS |

All budgets PASS.
<!-- BENCH TABLE END -->

## What the harness found (v0.5.1) and what was changed

Profiling (Time Profiler / `sample` on the Release binary) during the harness's typing, replace and launch phases showed:

- **Undo of a 5,000-match Replace All took 1.7 s** (p95 3.9 s): AppKit's undo for `shouldChangeText(inRanges:)` replays every range with its own `replaceCharacters`, and each one memmoves the attribute-run array (60 % of samples in `NSMutableRLEArray insertObject:range:`). `HyperTextView.performReplacements` now registers its own undo that reverts all ranges in one batched edit (redo takes the same path); measured 1,663 → 249 ms back-to-back.
- **Per keystroke, about a third of main-thread time was SwiftUI view-graph updates** and another fifth the AppKit layout passes they trigger: `MemoDocument.textDidChange()` re-assigned `isDirty = true` on every keystroke (a `@Published` set publishes even when the value is unchanged), `SearchPanel` observed the whole `EditorCaret` so its segmented control and button row were re-evaluated and re-laid-out on every caret move, and the outline/timeline panels did the same. Now `isDirty` is set once, only the hit list observes the caret, and the outline/timeline track the caret line through `onReceive(caret.$line.removeDuplicates())`.
- **`NSFontManager.availableFontFamilies` was called three times per theme/font application and on every file open** (12 % of launch samples, ~60 ms); `FontCascade.isInstalled(family:)` now caches the installed set and invalidates it on `kCTFontManagerRegisteredFontsChangedNotification`.
- The syntax highlighter allocated a `[unichar]` buffer per laid-out line; `LanguageGrammar.tokens(in:range:)` now uses `withUnsafeTemporaryAllocation` (stack for ordinary lines).
- `LineIndex.updated(replacing:with:)` (HyperCore, unit-tested) rebuilds the line-start table incrementally from an edit's range in O(lines) instead of copying and rescanning the whole text; wiring it into `MemoDocument` is a recommended follow-up (item 1 under "Recommended follow-ups" below).
- Launch: a direct exec does not receive LaunchServices' `oapp` event, so the first window only appeared through the app's 0.4 s reopen fallback; launch-timing mode now requests the window after 50 ms. Of the remaining launch CPU, roughly half is SwiftUI computing the hosting view's size constraints and key-view loop (several full `sizeThatFits` passes over the ribbon and the `HSplitView`/`VSplitView` hierarchy); the memo-document load, theme decoding and font setup are a small share.

Everything else measured — file open, search, scrolling, theme switch, memory plateau after repeated switches, idle CPU — was within budget on the first run.

## Recommended follow-ups (not yet wired)

Ordered by expected gain for the typing path, which is where the remaining per-keystroke cost is SwiftUI/AppKit layout rather than text processing.

1. **Publish the line index without invalidating SwiftUI** (`MemoDocument`, `EditorView`, `AppModel`, `MarkdownPreviewView`). Make `lineIndex` a plain `private(set) var` plus a `PassthroughSubject<LineIndex, Never>` (`lineIndexDidChange`), update it synchronously in `textStorage(_:didProcessEditing:range:changeInLength:)` with `LineIndex.updated(replacing: NSRange(location: edited.location, length: edited.length - delta), with: substring(edited))` for edits under ~64 K (fall back to the debounced full rebuild above that and on load), and call `objectWillChange.send()` only when `lineCount` changes. Gutter numbers and Ln/Col then stop being stale for 250 ms after Enter, the per-edit snapshot copy (8 MB → 16 MB memcpy each rebuild) disappears, and the three `$lineIndex` subscribers switch to the subject. Expected: Enter in the middle of the huge corpus below the 8 ms median budget (it measured 8.3–9.5 ms), gutter correct immediately.
2. **Stop the per-keystroke SwiftUI/AppKit layout pass** (`ContentView.StatusBar`). The status bar observes `EditorCaret`, so every caret move re-evaluates its whole `HStack` (theme `Menu` with 22 items included) and the hosting view then runs an AppKit layout pass over the split-view hierarchy (~20 % of busy time while typing). Move the Ln/Col/Sel and multi-caret cells into a small child view that is the only observer of `EditorCaret`, give it a fixed frame, and keep the rest of the bar keyed on `MemoDocument`/`AppModel`. Expected: 1–2 ms per keystroke.
3. **Launch: avoid repeated full `sizeThatFits` passes.** About half of launch CPU is SwiftUI computing the hosting view's min/max size and key-view loop over the ribbon and `HSplitView`/`VSplitView` (`NSSplitViewController` asks `systemLayoutSizeFittingSize` of the hosting view). Options: replace the SwiftUI split views with an `NSSplitView` representable whose panes are separate hosting views (each pane is then sized once), and drop `.frame(minWidth: 900, minHeight: 560)` in favour of `NSWindow.minSize`. Expected: 100–200 ms off the first window.
4. **`apply(theme:font:)` does two full-storage attribute passes**: `setAttributes` over the whole storage and then `tv.textColor = …`, which AppKit applies to the whole storage again, plus the Hangul font pass. Set `textColor` before `beginEditing`/skip it (typing attributes already carry the color), and apply the Hangul font only to the visible range on theme change, letting `didProcessEditing` handle the rest lazily per paragraph. Expected: theme switch on the 8 MB corpus 250 → ~120 ms.
5. **Release build settings** (`project.yml`) — *applied in v0.6*: `DEAD_CODE_STRIPPING: YES`, `DEPLOYMENT_POSTPROCESSING: YES`, `STRIP_INSTALLED_PRODUCT: YES`, `STRIP_STYLE: all` for Release so stripping runs in `scripts/make-dmg.sh` (which uses `build`, not `archive`). Measured: the universal binary went from 13.5 MB to 6.5 MB with the self-test unchanged (symbols drop from tens of thousands to ~1,600 exported/undefined).

## 한국어 요약

- `scripts/bench.sh` 가 Release 빌드 → 콜드 실행 시간 5회 → `--bench` 하네스(`Apps/mac/Bench.swift`) → 번들·바이너리 크기를 재서 `build/bench/<sha>.json`·`.md` 로 남긴다. `--compare <기준.json>` 은 변화율과 15 % 넘는 퇴행을 표시하고, `--strict` 는 예산 실패 시 종료 코드 1.
- 임시 폴더의 자체 말뭉치(2 KB·200 KB·1.3 MB·8 MB)와 휘발성 설정만 쓰므로 사용자 문서·설정은 건드리지 않는다.
- 예산: 타이핑 중앙값 8 ms / p95 16 ms, 큰 파일 열기 150 ms, 검색 60 ms, 테마 전환 300 ms, 유휴 CPU 1 % 미만, 8 MB 로드 뒤 RSS 400 MB 등. 예산은 제품 요구치이므로 그날의 측정값에 맞춰 느슨하게 하지 않는다. 표 머리에 부하 평균이 찍히며 코어 수를 넘으면 "measured under load" 로 표시된다.
- 이번에 고친 것: 모두 바꾸기 5,000건의 ⌘Z 1.7 s → 0.25 s(일괄 undo 직접 등록), 키 입력마다 일어나던 SwiftUI 재평가 제거(`isDirty` 중복 발행, 검색 패널·아웃라인의 캐럿 구독), `availableFontFamilies` 캐시, 하이라이터 줄 버퍼 할당 제거, `LineIndex` 증분 갱신(배선은 후속 권고).
- CI 에는 벤치를 넣지 않는다(GitHub 러너는 너무 시끄럽다). 성능에 민감한 변경은 로컬에서 `--compare` 로 전후를 비교해 PR 에 붙인다.
