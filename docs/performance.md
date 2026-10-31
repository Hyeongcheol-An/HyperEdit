# Performance

HyperEdit is judged on feel: typing, scrolling, search, file switching and launch must be instant on a multi-megabyte notes file, and the app must stay light when idle. This document describes the benchmark harness that measures that, the budgets each metric must meet, how to compare two builds, and the current baseline. A short Korean summary is at the end.

## Running the benchmark

```sh
scripts/bench.sh                       # Release build → cold-launch timing ×5 → in-app benchmark → bundle/binary size
scripts/bench.sh --compare docs/bench/baseline-0.5.1.json   # same, plus Δ% against a baseline and a list of >15 % regressions
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

Apple silicon laptop (2023, 12 cores, 64 GB), macOS 27.2, Release build. **Provisional:** this table was recorded while four other Xcode builds were running on the machine (1-minute load average 25–60 on 12 cores), so absolute numbers are inflated and will be replaced by an idle-machine run of `scripts/bench.sh` after integration; the JSON for comparison is `docs/bench/baseline-0.5.1.json`.

<!-- BENCH TABLE -->

## What the harness found (v0.5.1) and what was changed

Profiling (Time Profiler / `sample` on the Release binary) during the harness's typing, replace and launch phases showed:

- **Undo of a 5,000-match Replace All took 1.7 s** (p95 3.9 s): AppKit's undo for `shouldChangeText(inRanges:)` replays every range with its own `replaceCharacters`, and each one memmoves the attribute-run array (60 % of samples in `NSMutableRLEArray insertObject:range:`). `HyperTextView.performReplacements` now registers its own undo that reverts all ranges in one batched edit (redo takes the same path); measured 1,663 → 249 ms back-to-back.
- **Per keystroke, about a third of main-thread time was SwiftUI view-graph updates** and another fifth the AppKit layout passes they trigger: `MemoDocument.textDidChange()` re-assigned `isDirty = true` on every keystroke (a `@Published` set publishes even when the value is unchanged), `SearchPanel` observed the whole `EditorCaret` so its segmented control and button row were re-evaluated and re-laid-out on every caret move, and the outline/timeline panels did the same. Now `isDirty` is set once, only the hit list observes the caret, and the outline/timeline track the caret line through `onReceive(caret.$line.removeDuplicates())`.
- **`NSFontManager.availableFontFamilies` was called three times per theme/font application and on every file open** (12 % of launch samples, ~60 ms); `FontCascade.isInstalled(family:)` now caches the installed set and invalidates it on `kCTFontManagerRegisteredFontsChangedNotification`.
- The syntax highlighter allocated a `[unichar]` buffer per laid-out line; `LanguageGrammar.tokens(in:range:)` now uses `withUnsafeTemporaryAllocation` (stack for ordinary lines).
- `LineIndex.updated(replacing:with:)` (HyperCore, unit-tested) rebuilds the line-start table incrementally from an edit's range in O(lines) instead of copying and rescanning the whole text; wiring it into `MemoDocument` is a recommended follow-up (see the integration notes in the pull request).
- Launch: a direct exec does not receive LaunchServices' `oapp` event, so the first window only appeared through the app's 0.4 s reopen fallback; launch-timing mode now requests the window after 50 ms. Of the remaining launch CPU, roughly half is SwiftUI computing the hosting view's size constraints and key-view loop (several full `sizeThatFits` passes over the ribbon and the `HSplitView`/`VSplitView` hierarchy); the memo-document load, theme decoding and font setup are a small share.

Everything else measured — file open, search, scrolling, theme switch, memory plateau after repeated switches, idle CPU — was within budget on the first run.

## 한국어 요약

- `scripts/bench.sh` 가 Release 빌드 → 콜드 실행 시간 5회 → `--bench` 하네스(`Apps/mac/Bench.swift`) → 번들·바이너리 크기를 재서 `build/bench/<sha>.json`·`.md` 로 남긴다. `--compare <기준.json>` 은 변화율과 15 % 넘는 퇴행을 표시하고, `--strict` 는 예산 실패 시 종료 코드 1.
- 임시 폴더의 자체 말뭉치(2 KB·200 KB·1.3 MB·8 MB)와 휘발성 설정만 쓰므로 사용자 문서·설정은 건드리지 않는다.
- 예산: 타이핑 중앙값 8 ms / p95 16 ms, 큰 파일 열기 150 ms, 검색 60 ms, 테마 전환 300 ms, 유휴 CPU 1 % 미만, 8 MB 로드 뒤 RSS 400 MB 등. 예산은 제품 요구치이므로 그날의 측정값에 맞춰 느슨하게 하지 않는다. 표 머리에 부하 평균이 찍히며 코어 수를 넘으면 "measured under load" 로 표시된다.
- 이번에 고친 것: 모두 바꾸기 5,000건의 ⌘Z 1.7 s → 0.25 s(일괄 undo 직접 등록), 키 입력마다 일어나던 SwiftUI 재평가 제거(`isDirty` 중복 발행, 검색 패널·아웃라인의 캐럿 구독), `availableFontFamilies` 캐시, 하이라이터 줄 버퍼 할당 제거, `LineIndex` 증분 갱신(배선은 후속 권고).
- CI 에는 벤치를 넣지 않는다(GitHub 러너는 너무 시끄럽다). 성능에 민감한 변경은 로컬에서 `--compare` 로 전후를 비교해 PR 에 붙인다.
