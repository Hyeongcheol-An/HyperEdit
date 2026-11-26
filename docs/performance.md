# Performance

HyperEdit is judged on feel: typing, scrolling, search, file switching and launch must be instant on a multi-megabyte notes file, and the app must stay light when idle. This document describes the benchmark harness that measures that, the budgets each metric must meet, how to compare two builds, and the current baseline. A short Korean summary is at the end.

## Running the benchmark

```sh
scripts/bench.sh                       # Release build → cold-launch timing ×5 → in-app benchmark → bundle/binary size
scripts/bench.sh --compare build/bench/<before-sha>.json     # same, plus Δ% against a baseline and a list of >15 % regressions
scripts/bench.sh --skip-build --only typing,search          # reuse the existing build, run only some phases
scripts/bench.sh --strict                                   # exit 1 on any budget failure or regression
scripts/bench.sh --foreground                               # run in front, as before (needed to compare with docs/bench/baseline-0.6.0.json)
```

The bench runs **in the background**, like the self-test: when macOS activates the app it steps back at once and sends its window behind the others, so it does not take the keyboard from the app you are working in (an activity token keeps App Nap away). `--foreground` (`--bench-foreground` for the app) runs it in front, as every bench did before. The bench drives the model and the text view directly and does not depend on the key window or on events, but a window that is fully covered is not drawn, so each result records how it ran: `mode` in the JSON (`background`, `wasActive`, `occluded`) and a `Run:` line under the load average in the table, which says *not a baseline* when the window was fully covered at the start or the end of the run. **Compare background runs only with background runs** — result files written before the mode was recorded, `docs/bench/baseline-0.6.0.json` among them, are foreground runs.

Results land in `build/bench/<git-sha>.json` and `.md`, and the table is printed to stdout. Everything runs on a corpus that the harness generates in a temporary folder (small 2 KB, medium 200 KB, large 1.3 MB / ~25k lines, huge 8 MB / ~158k lines of mixed Korean, English, code, URLs, tab tables and log lines, from a fixed PRNG seed; plus, for the `findui` and `findquery` phases, log 28 MB / ~265k server-log lines with occasional stack traces and Korean messages) and with throwaway preferences (`--ephemeral`), so it never touches your documents or settings.

The in-app part is `Apps/mac/Bench.swift`, started with `--bench [--bench-out <json>] [--bench-strict] [--bench-only <phases>] [--bench-commit <sha>] [--quit]`. It drives the real editor (the same `NSTextView`, coordinator and model the user types into), repeats each measurement at least five times and reports the median and p95. Phases: `idle`, `open`, `memory`, `scroll`, `search`, `outline`, `theme`, `typing`, `findui`, `findquery`, `replace`, `save`.

Launch time is measured by `scripts/bench.sh` with `--quit-after-launch --bench-launch-log <file>`: the app records milliseconds from the kernel's process start time to `applicationDidFinishLaunching`, the first `ContentView.onAppear` and the first visible window, then quits. The first of the runs is discarded as warm-up. Because the benchmark execs the binary directly (no LaunchServices `oapp` event), launch-timing mode asks for the initial window 50 ms after `didFinishLaunching` instead of waiting for the app's 0.4 s "no window" fallback, which mirrors what a Dock or Finder launch does.

The `findui` phase (added 2026-11-06 after a report that a 28 MB log became hard to use once a search was open) measures the find UI end to end rather than the engine: it opens a generated 28 MB server log with the Find Results panel showing, searches for a common and a rare term, and then — with 10,000 results on screen — types at the end and in the middle, lets the 1.2 s re-search run both ways (an edit before every result republishes 10,000 rows; an edit at the end leaves the results unchanged and publishes nothing), scrolls, jumps to results and moves the caret. Typing at the end and caret movement each have a control without results, and the re-search gap is also measured with the panel hidden and with scroll markers off (both informational), so a regression points at the list, the markers or the editor. Run it alone with `scripts/bench.sh --skip-build --only findui`.

The `findquery` phase types into the find field itself (through the `FindFields` object the text field is bound to) with 10,000 results open and a 9,200-entry folder tree in the file view, plus controls with the file view hidden and with the results panel hidden. When the field was bound to the app model every keystroke re-evaluated the whole window (20–27 ms on the 28 MB log, the same with the sidebar or panel hidden); the budget is one frame.

## Budgets

| Metric | Budget | Why |
|---|---|---|
| Typing latency (80 keystrokes, end and middle of the document, syntax colors on/off, large and huge) | median ≤ 8 ms, p95 ≤ 16 ms | one 60 Hz frame including the run-loop turn that lays out and draws |
| Enter in the middle (with and without bookmark line tracking) | median ≤ 8 ms, p95 ≤ 16 ms | same as typing |
| Open medium / large / huge (to first frame) | 100 / 150 / 800 ms | a file switch must feel immediate on the 1.3 MB notes file |
| Search literal / case-insensitive / regex `\d{4}-\d{2}-\d{2}` / whole word, large (huge) | 60 ms (400 ms) | result list appears without a visible pause |
| Replace all of ~5,000 matches, and the single ⌘Z that reverts it, large | 500 ms each | bulk edit is allowed a short pause, not a hang |
| Scroll step (1/40 of the large document) | median ≤ 16 ms, p95 ≤ 33 ms | one or two frames per jump |
| Go to end / go to line 1, large | 50 ms | |
| Find on the 28 MB log, results panel open: Enter → results listed and drawn (10,000 and 9 hits; `find.e2e`) | 600 / 400 ms | the whole search, including the SwiftUI commit of 10,000 rows, must feel immediate (`find.publish` and `find.frame` split it, informational) |
| Typing in the find field with 10,000 results open and a 9,200-entry file tree (`findquery`) | median ≤ 8 ms, p95 ≤ 16 ms | a keystroke in the find field must not re-evaluate the window |
| With 10,000 find results open, log: typing at end / middle, caret ↓ (`findui`) | median ≤ 8 ms, p95 ≤ 16 ms | the list follows the caret, but must not add per-keystroke cost (controls: the same without results) |
| Re-search after an edit (1.2 s debounce), log: longest run-loop gap until the pass completes — an edit before all results (10,000 rows republished) and an edit at the end (results unchanged, nothing published) (`findui`; panel-hidden and markers-off variants of the republishing case are informational) | 50 ms each | republishing 10,000 results must not freeze typing, and an unchanged pass must cost nothing |
| Scroll step with results open; jump to a result from the list, log (`findui`) | 16 / 33 ms; 50 ms | |
| Theme switch / font size change, large | 300 ms | full attribute re-application over the storage |
| Outline + timeline rescan, Markdown → HTML, large | 300 / 1500 ms (informational) | run in the background; must not grow unbounded |
| RSS after loading the 8 MB corpus; after 5 small↔huge switches; growth | 400 MB; 450 MB; ≤ 20 % | leak check — memory must plateau |
| Idle CPU over 3 s (small and huge document open) | < 1 % | no timers or polling while idle |
| Cold launch → first window | 600 ms | |
| Bundle / executable size | 40 / 30 MB (informational) | |

Rows marked *informational* are reported and compared but never fail `--strict`; the others fail it.

Budgets describe the product requirement, not the machine of the day: do not loosen them when a run is noisy. The table header prints the 1-minute load average before and after the run and marks the result **measured under load** when it exceeds the core count; such runs are not baselines.

## Comparing two builds

`scripts/bench.sh --compare <baseline.json>` adds a Δ column (median vs. median) and lists metrics that regressed by more than 15 % (and by more than 0.5 units, so sub-millisecond noise is ignored). Both runs must have been taken the same way — check the `Run:` line of each table: a background run is not comparable with a foreground one, and a run whose window was fully covered is not a baseline at all. For A/B decisions take both runs back-to-back on an otherwise idle machine, and prefer profile evidence (`sample <pid> 5` or Instruments' Time Profiler on the Release binary) over small wall-clock deltas.

Benchmarks are deliberately not part of CI: GitHub-hosted runners are shared and far too noisy for millisecond budgets. Run `scripts/bench.sh` locally before a performance-sensitive change and `scripts/bench.sh --compare build/bench/<before-sha>.json` after it, in the same mode, and paste the table into the pull request.

## Baseline

Apple silicon laptop (2023, 12 cores, 64 GB), macOS 27.2, Release build, HyperEdit 0.6.0 (all v0.6 features and optimizations). Recorded on an idle machine (1-minute load average ≈ 2.4 on 12 cores) with `scripts/bench.sh`, in the foreground (the JSON predates the `mode` field, so the table has no `Run:` line); the JSON is `docs/bench/baseline-0.6.0.json`. To compare a build with it, run `scripts/bench.sh --foreground --compare docs/bench/baseline-0.6.0.json`. Compared with the pre-optimization build (v0.5.1), typing latency dropped from 4.5 ms to 1.2 ms per keystroke, the single undo of a 5,000-match Replace All from 1.7 s to 0.32 s, and cold launch from 0.9 s to 0.59 s; file open and Replace All are a few tens of milliseconds slower because the first frame now also starts the fold-region scan, draws scrollbar markers and registers the split-editor session.

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

## Layout and scrolling stalls found by the real-use harness

The bench above measures steady-state cost; the stalls below only showed up when the real-use harness (`scripts/realuse.sh`, see [CONTRIBUTING.md](../CONTRIBUTING.md)) drove the editor the way a person does — it reports every main-thread block over 250 ms and the time of each wheel step. Numbers were taken on a 12-core Mac with the harness window at 1280 × 972 pt (382 pt of editor), on the harness's 1.3 MB notes corpus and a 4 MB log.

| What | Before | After | Cause and fix |
|---|---|---|---|
| Turning word wrap off, 1.3 MB note | blocked 1.7–3.4 s | no stall over 250 ms | With a text container that does not track the view's width, every read of `-[NSTextView textContainerOrigin]` lays out the whole document (22–26 ms a call once laid out, 2.1–2.4 s after a full invalidation). Its value is always the container inset, so `HyperTextView` returns the inset directly while wrap is off |
| 4 MB log with word wrap off: open / one wheel step | 15 s / 13–17 s | 0.35 s / 3.7 ms | same — the 2,000-fragment cache threw the whole-document layout away on every step |
| Smaller text, closing the sidebar or the split at the end of the 1.3 MB note | blocked 0.47–0.81 s | no stall over 250 ms | When a reflow shrinks the height estimate, the old scroll position lies past the new end; `layoutViewport()` there walks every paragraph from the top (and runs the syntax-color validator on each). `enterDocumentBeforeViewportLayout` moves the view back inside the document first |
| Turning word wrap off at the end of the 4 MB log | 2.2 s | 50 ms | same |
| The open file is rewritten with half its lines (24,002 → 12,002) while you look at its end; Format JSON right after | reload 16.2 s; 3.2 s | 272 ms; 147 ms | The same trap again, on a reload: the text is replaced but the position is kept, and the first layout pass runs before the reading position is restored. The view notes a wholesale replacement away from the top and, before the next layout pass, asks where the document ends and steps inside if it is past it (`contentReplacedBeforeLayout`). A file that grew stays where it was |
| Undo / redo of Toggle Comment on every line of a 1.3 MB document; undo of Format JSON on 1.7 MB | 5.3 s / 5.3 s; 0.85 s | 0.26 s / 0.26 s; 0.21 s | The tools inserted their result with `insertText`, so AppKit registered a typing undo that puts the removed text back as an attributed string; inserting its attribute runs into the storage's run array costs the runs inserted times the runs after them (nearly all of it `memmove` in `NSMutableRLEArray`). A range of 16,384 UTF-16 units or more now goes through `performReplacements`, which registers its own undo and swaps plain characters in one batch edit — the path Replace All already used (`HyperTextView.replaceForTool`). The tools themselves were fast already (about 0.3 s and 0.15 s) |
| ⌘Z that leaves the whole 1.3 MB document selected | 7.5 s to bring the selection into view | the view stays where it is | AppKit lays out the entire range it is asked to reveal. A selection of 16,384 units or more is not handed to the reveal whole: nothing is done when the view is already inside it, and only its start is revealed otherwise |
| Return right after a 26,000-character line that ends on the bottom line of the screen | the view jumped 202 pt | 23–24 pt (one line) | not a stall but found the same way: the skip of very long paragraphs when the caret line is measured after an edit also applied to edits that start on screen; it is now limited to edits that replace the document |
| 100 runs of a 10-step macro, 1.2 MB document | 844–880 ms | 645–652 ms | A replay repeats edits and caret moves inside one run-loop turn; with no layout pass in between the caret line is measured below where it is (192 pt after eight edited lines), so following the caret on every step scrolled there, laid the viewport out and scrolled back. The caret is now followed once per screen update and once at the end (`revealCaretAfterReplaySteps`) |
| Opening a 12,002-line JSON file while looking at the end of a 24,000-line file; Format JSON right after | 17.5 s in one layout pass; 3.1 s | 160 ms; 166 ms | The same trap at a document switch: the text is replaced in place but the scroll position is still that of the previous document, past the end of a shorter one. With every paragraph then carrying rendering attributes, large edits were slow afterwards. The view goes to the start of the document just before another document comes in (`leaveScrollPositionForNewDocument`); the reading position is restored right after, as before |
| Wheel step in the fully folded 1.3 MB note (down / up / up from the end) | 28 / 17 / 44 ms average, worst 1.2 s | 8.2 / 6.4 / 8.1 ms | Folded paragraphs were zero-height fragments, which TextKit 2 honours only once laid out: a document 51,000 pt tall was estimated at 537,651 pt. They are now left out of the content storage's element enumeration (`FoldingContentStorage`), and the fold pill labels are cached |
| Text size, sidebar or window width with everything folded | blocked up to 1 s | no stall over 250 ms | same |

Not solved yet:

- A wheel step larger than the visible height (800 pt in a 382 pt editor) that falls on the step where the layout manager discards its fragment cache can move the content 22–61 lines against the scroll direction. The scroll anchor needs a fragment that stays on screen across the step, and there is none.
- A fully folded screen still costs two to three times an unfolded one per wheel step: 5.1 ms against 1.7 ms in a document with 15,000 two-line regions, all folded. What is left is the viewport layout restarting the element enumeration across the folds. (That document wheeled at 13.7–16.3 ms a step until the marker strip beside the scroll bar stopped redrawing on every step — it draws a tick per folded header, about 10 ms a redraw with 15,000 of them, and the editor container assigned it the same frame on every layout pass.)
- With word wrap off, the measured content width is dropped when the document changes, so coming back to a tab starts at the first column.
- Undo of a large edit that did not come from a text tool is still AppKit's typing undo, which puts the removed text back as an attributed string and pays for every attribute run it inserts: ⌘Z after Select All and typing or pasting over a large document, and tool edits below the 16,384-unit threshold (60–72 ms for 12,000 characters at the start of a 1.3 MB document — the cost grows with the text put back and with the document behind it).

## What the harness found (v0.5.1) and what was changed

Profiling (Time Profiler / `sample` on the Release binary) during the harness's typing, replace and launch phases showed:

- **Undo of a 5,000-match Replace All took 1.7 s** (p95 3.9 s): AppKit's undo for `shouldChangeText(inRanges:)` replays every range with its own `replaceCharacters`, and each one memmoves the attribute-run array (60 % of samples in `NSMutableRLEArray insertObject:range:`). `HyperTextView.performReplacements` now registers its own undo that reverts all ranges in one batched edit (redo takes the same path); measured 1,663 → 249 ms back-to-back.
- **Per keystroke, about a third of main-thread time was SwiftUI view-graph updates** and another fifth the AppKit layout passes they trigger: `MemoDocument.textDidChange()` re-assigned `isDirty = true` on every keystroke (a `@Published` set publishes even when the value is unchanged), `SearchPanel` observed the whole `EditorCaret` so its segmented control and button row were re-evaluated and re-laid-out on every caret move, and the outline/timeline panels did the same. Now `isDirty` is set once, only the hit list observes the caret, and the outline/timeline track the caret line through `onReceive(caret.$line.removeDuplicates())`.
- **`NSFontManager.availableFontFamilies` was called three times per theme/font application and on every file open** (12 % of launch samples, ~60 ms); `FontCascade.isInstalled(family:)` now caches the installed set and invalidates it on `kCTFontManagerRegisteredFontsChangedNotification`.
- The syntax highlighter allocated a `[unichar]` buffer per laid-out line; `LanguageGrammar.tokens(in:range:)` now uses `withUnsafeTemporaryAllocation` (stack for ordinary lines).
- `LineIndex.updated(replacing:with:)` (HyperCore, unit-tested) rebuilds the line-start table incrementally from an edit's range in O(lines) instead of copying and rescanning the whole text; `MemoDocument.liveLineIndex` is updated with it synchronously on every edit, and the status bar (Ln/Col, line count), the gutter and line jumps read that live index — so they are no longer stale for the 250 ms debounce after Enter. The published `lineIndex` (preview, outline, find) is still the debounced full rebuild; moving its subscribers off `@Published` remains the follow-up (item 1 under "Recommended follow-ups" below).
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
- 벤치는 셀프테스트처럼 **뒤에서** 돈다(활성화되면 바로 물러나고 창을 맨 뒤로 — 쓰고 있는 앱의 포커스를 뺏지 않는다). `--foreground`(앱 인자는 `--bench-foreground`)가 예전처럼 앞에서 도는 방식이다. 어떻게 돌았는지는 JSON 의 `mode` 와 표의 `Run:` 줄에 남고, 창이 완전히 가려져 있었으면 기준선으로 쓰지 말라고 표시된다. **뒤에서 잰 값은 뒤에서 잰 기준선과만 견준다** — `docs/bench/baseline-0.6.0.json` 은 앞에서 잰 것이라 `--foreground --compare` 로 견준다.
- 임시 폴더의 자체 말뭉치(2 KB·200 KB·1.3 MB·8 MB·`findui`·`findquery` 단계의 28 MB 로그)와 휘발성 설정만 쓰므로 사용자 문서·설정은 건드리지 않는다.
- 예산: 타이핑 중앙값 8 ms / p95 16 ms, 큰 파일 열기 150 ms, 검색 60 ms, 테마 전환 300 ms, 유휴 CPU 1 % 미만, 8 MB 로드 뒤 RSS 400 MB 등. 예산은 제품 요구치이므로 그날의 측정값에 맞춰 느슨하게 하지 않는다. 표 머리에 부하 평균이 찍히며 코어 수를 넘으면 "measured under load" 로 표시된다.
- 이번에 고친 것: 모두 바꾸기 5,000건의 ⌘Z 1.7 s → 0.25 s(일괄 undo 직접 등록), 키 입력마다 일어나던 SwiftUI 재평가 제거(`isDirty` 중복 발행, 검색 패널·아웃라인의 캐럿 구독), `availableFontFamilies` 캐시, 하이라이터 줄 버퍼 할당 제거, `LineIndex` 증분 갱신(이후 `liveLineIndex` 로 배선 — 상태바·거터·줄 이동이 편집 직후에도 맞는 줄 번호를 쓴다; 발행되는 `lineIndex` 의 구독자 전환은 후속 권고).
- 실사용 하네스가 찾은 정지(위 "Layout and scrolling stalls" 표): 줄바꿈 끔(1.3 MB 에서 1.7~3.4 s → 250 ms 넘는 정지 없음, 4 MB 로그 열기 15 s → 0.35 s), 문서 끝에서의 리플로(0.47~0.81 s → 없음), 접힌 문서의 휠(평균 28 ms·최악 1.2 s → 약 8 ms). 문서 전환(긴 문서의 끝을 보다가 짧은 문서를 열면 17.5 s → 160 ms)과 짧아진 파일 다시 읽기(16.2 s → 0.27 s)도 같은 함정이었다. 매크로 10단계 ×100 재생 844~880 ms → 645~652 ms. 큰 범위를 바꾸는 도구(전체 주석 토글·JSON 정리)의 되돌리기·다시 실행 5.3 s·5.3 s·0.85 s → 0.26 s·0.26 s·0.21 s(16,384 단위 이상은 일괄 편집으로). 남은 것: 문턱 아래의 범위와 일반 입력의 큰 되돌리기(모두 선택 뒤 입력의 ⌘Z)는 여전히 AppKit 의 입력 되돌리기, 한 화면을 넘는 휠 걸음이 조각 캐시 버리기와 겹치면 내용이 22~61줄 거꾸로 감, 모두 접은 화면의 걸음당 시간이 접지 않은 문서의 2~3배(접힘 15,000개 문서에서 5.1 ms 대 1.7 ms), 줄바꿈 끔에서 탭으로 돌아오면 가로 위치가 처음 열.
- CI 에는 벤치를 넣지 않는다(GitHub 러너는 너무 시끄럽다). 성능에 민감한 변경은 로컬에서 같은 방식으로 전후를 재고 `--compare` 로 비교해 PR 에 붙인다.
