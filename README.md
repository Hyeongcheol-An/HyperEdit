<p align="center"><img src="docs/screenshots/app-icon-1024.png" width="120" alt="HyperEdit app icon"></p>

<h1 align="center">HyperEdit</h1>

<p align="center"><b>A fast, ribbon-style plain-text editor for macOS, built around one big notes file.</b></p>

<p align="center">
<a href="https://github.com/Hyeongcheol-An/HyperEdit/releases"><img alt="Release" src="https://img.shields.io/github/v/release/Hyeongcheol-An/HyperEdit?sort=semver"></a>
<a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/github/license/Hyeongcheol-An/HyperEdit"></a>
<a href="https://github.com/Hyeongcheol-An/HyperEdit/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/Hyeongcheol-An/HyperEdit/ci.yml?branch=main&label=CI"></a>
<img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-black">
</p>

<p align="center">English · <a href="README.ko.md">한국어</a> · <a href="docs/guide/USER_GUIDE.zh-Hans.md">简体中文</a> · <a href="docs/guide/USER_GUIDE.ja.md">日本語</a> · <a href="docs/guide/USER_GUIDE.vi.md">Tiếng Việt</a> · <a href="docs/guide/USER_GUIDE.hi.md">हिन्दी</a> · <a href="docs/guide/USER_GUIDE.de.md">Deutsch</a> · <a href="docs/guide/USER_GUIDE.fr.md">Français</a> · <a href="docs/guide/USER_GUIDE.es.md">Español</a> · <a href="docs/guide/USER_GUIDE.pt.md">Português</a> · <a href="docs/guide/USER_GUIDE.ar.md">العربية</a></p>

<p align="center"><a href="docs/guide/USER_GUIDE.md">User Guide</a> — the full manual, in all eleven languages</p>

HyperEdit is for people who keep a single, ever-growing text file — tens of thousands of lines of notes, logs and snippets — and spend the day appending to it and searching through it. A SwiftUI shell wraps an AppKit `NSTextView` on TextKit 2, so a multi-megabyte file still types like a small one, and the window follows the layout of a classic ribbon editor: ribbon tabs, a document tab bar, a sidebar, a bottom panel and a dense status bar.

| Hyper Light | Hyper Dark |
|---|---|
| ![HyperEdit in the Hyper Light theme](docs/screenshots/hyperedit-light.png) | ![HyperEdit in the Hyper Dark theme](docs/screenshots/hyperedit-dark.png) |

## Install

**Requirements:** macOS 15 (Sequoia) or later. One universal binary runs natively on Apple Silicon (arm64) and Intel (x86_64) Macs; the DMG is named `HyperEdit-x.y.z-universal.dmg`.

**Homebrew**

```sh
brew tap Hyeongcheol-An/tap
brew install --cask hyperedit
```

Homebrew 7 may ask you to trust the tap first: `brew trust Hyeongcheol-An/tap`.

**DMG**

Download `HyperEdit-x.y.z-universal.dmg` from [GitHub Releases](https://github.com/Hyeongcheol-An/HyperEdit/releases), open it and drag `HyperEdit.app` to `Applications`. Builds are Developer ID signed and notarized, so Gatekeeper opens them without warnings. To verify a download, put `SHA256SUMS` next to the DMG and run:

```sh
shasum -a 256 -c SHA256SUMS
```

### First launch

HyperEdit opens `~/Documents/HyperEdit/notes.md`, creating it with a short welcome text if it does not exist. ⌘N creates a new empty text file (you choose the name and folder), ⌘O opens any other text file, and the last opened file is remembered for the next launch. Binary files (images, PDFs, archives…) are never loaded into the editor; they open in their default app instead.

> The interface is available in eleven languages — English, Korean, Simplified Chinese, Japanese, Vietnamese, Hindi, German, French, Spanish, Portuguese and Arabic (right-to-left text; the window layout stays left-to-right) — and follows the system language by default. Pick a different one in **Settings (⌘,) › Language** and click **Relaunch Now**; the choice is shared with System Settings › General › Language & Region › Applications. **Help › User Guide** opens the [user guide](docs/guide/USER_GUIDE.md) in the current language. Translations live in `l10n/ui.<language>.json` — corrections are welcome.

## Features

### Editor
- Tuned for big files: about 3 ms per keystroke on a 1.3 MB / 34,000-line file, with viewport-based TextKit 2 layout. A benchmark harness (`scripts/bench.sh`) measures typing, file open, search, scrolling, memory, idle CPU and launch against fixed budgets — see [docs/performance.md](docs/performance.md). v0.6 cut the single undo of a 5,000-match Replace All from 1.7 s to 0.25 s, stopped the per-keystroke SwiftUI re-evaluation of the panels and cached the installed-font list.
- Line-number gutter, current-line highlight, word wrap (⌥Z), line numbers (⌥⌘L), zoom (⌘= / ⌘- / ⌘0).
- Last caret and scroll position restored per file; ⌃⌘E jumps to the end; ⌘L goes to a line.
- **Code folding (⌥⌘← / ⌥⌘→, all regions ⌥⇧⌘← / ⌥⇧⌘→):** a line folds the lines indented under it (blank lines ignored), a Markdown `#` heading folds everything up to the next heading of the same or higher level (fenced code blocks fold too), and in code a line ending in `{`, `[` or `(` folds through its closing bracket line. Click the gutter chevron or the `⋯ N lines` pill to toggle. Moving the caret into a folded line (find, go to line, bookmarks, undo) unfolds it; ↑ / ↓ skip over folds. Folds follow edits — typing in the header, inserting or deleting lines above, undo — and last for the session.
- **Scrollbar markers:** a 12 pt strip at the editor's right edge shows search matches (accent ticks), bookmarks (warning color), the caret line and folded headers at their relative positions; hidden when the document fits on one screen. View menu → Scrollbar Markers, or the Layout tab's Folding group.
- F7 inserts a timestamp heading such as `## 2026-10-30 (Fri) 14:05`. The weekday follows the system locale, e.g. `(금)` on Korean systems.
- **Split editor (⌘\\)** shows the same document in two editors, side by side or stacked (View › Split, or the Layout tab). Both views edit the same text and share one undo stack — type in one, ⌘Z in the other — but scroll independently; commands, the status bar and the Markdown preview follow the view you clicked last, and ⌥⌘\\ moves the focus to the other split. The status bar shows **SPLIT** while it is on.
- **Quick Append (⇧⌘N, or ⌃⌥N from any app):** a small floating panel that does not activate HyperEdit. Type a note, press ⌘↩ and it is appended to the end of the document — with a timestamp heading by default — saved at once, and undoable in one step; the panel then hides and focus returns to the app you were in. Esc closes the panel and keeps the draft for next time. The global shortcut (off / ⌃⌥N / ⌃⌥Space / ⌃⇧Space / ⌃⌥⌘N) is chosen in Settings and needs no Accessibility permission.
- **Syntax colors (⌃⌘H)**, chosen by file extension and shown in the status bar. Notes and Markdown get a deliberately light rule set — URLs, ISO dates and times, `#` headings, `[Title]` lines, list markers and `[ ]` / `[x]` task boxes, `#tags`, `key:` labels, `**bold**`, `` `code` `` and `⇒ → ->` arrows — and about 20 code languages (Swift, Python, JavaScript/TypeScript, JSON, shell, YAML, HTML/XML, CSS, C/C++/Objective-C, Go, Rust, SQL, Ruby, Java/Kotlin, TOML, INI) get comments, strings, numbers, keywords, function and type names. Colors come from the theme's `syntax` palette and are applied as TextKit 2 rendering attributes to visible lines only, so they never touch the file, undo history or typing speed. Block comments (`/* */`, `<!-- -->`), multi-line strings (Swift and Python `"""`, JavaScript template literals, Go raw strings, Rust `r#"…"#`) and Markdown fenced code blocks keep their color across lines until they close — a fence is colored with the language named in its info string — and typing a delimiter recolors the lines below at once. A per-line state table makes this cost about 10 ms for a 34k-line file and nothing noticeable per keystroke.
- **User-defined grammars:** drop a `*.json` file into `~/Library/Application Support/HyperEdit/grammars/` to add a language or override a built-in one — name, extensions or file names, comment markers, string delimiters and keyword lists. **File › Open Grammars Folder…** creates the folder with an `example.json` and a README that documents the schema; **File › Reload Grammars** applies changes without restarting, the status bar shows the grammar's name and Toggle Comment (⌘/) uses its markers.
- **Cursor style and window opacity (Settings › Appearance):** a Bar, Block or Underline caret with blinking on or off — extra carets from multi-caret and column mode use the same style — and a window opacity of 50–100 % that makes the editor, ribbon, panels and status bar translucent while text stays opaque, with an optional system blur behind the window. View › Window Opacity offers 100 / 90 / 80 / 70 % steps.

### Markdown preview
- **⇧⌘P** splits the editor: the rendered GFM view of the current file appears on the right (headings, lists and task lists, tables, fenced code, block quotes, links, images) styled from the active theme, with the system font for prose and the editor's monospace stack for code.
- The preview follows the editor's scroll position and re-renders 300 ms after you stop typing, keeping its own scroll position. Links open in the default browser; raw HTML in the source is shown escaped, never executed; relative image paths resolve against the file's folder. Files over 2 MB show a short notice instead of a preview.
- Rendered with Apple's [swift-markdown](https://github.com/swiftlang/swift-markdown) (Apache-2.0). The status bar shows **MD** while the preview is on.

### Ribbon and panels
- Ribbon tabs **Home / Edit / Layout / Advanced / Window**, a document tab bar with New (⌘N) and Open (⌘O) buttons, and quick-access Save / Undo / Redo.
- **Sidebar (⌘1)** — **Files** (folder tree of the current file's folder; a single click opens a file), **Outline** (⌘3: `##` headings, `[Title]` lines, Korean `가./나.` items and `1)` numbered items, with a filter box and the current item highlighted; `# …` lines that look like code comments are excluded), **Timeline** (⌘4: `## YYYY-MM-DD (weekday) HH:MM` timestamp headings plus loose date-prefixed lines, grouped by month, newest first).
- **Bottom panel (⌘2)** — **Find Results**, **Bookmarks** and an **Output** log.

### Find, replace, bookmarks
- **Find (⌘F):** type a query and press Enter to list every match with line numbers, with the matches highlighted in the editor while the list is open; toggles for regex `.*`, case `Aa` and whole word `W`; F3 / ⇧F3 step through matches; ⌥⌘A turns all matches into multi-carets.
- **Replace (⌘R):** replace current or replace all, with regex templates such as `$1`. Replace All is a single undo step.
- **Find in Files (⇧⌘F):** pick a folder and optional masks like `*.md;*.txt`; binary files are skipped; click a hit to open the file at that line.
- **Bookmarks:** ⌘F2 toggles, F2 / ⌥F2 jump next / previous, optional names. Bookmarks follow their lines as you edit — inserting or deleting lines above moves them, deleting a bookmarked line removes it, and undo/redo moves them back. Stored per document under `~/Library/Application Support/HyperEdit/bookmarks/`, so nothing is written next to your files; a legacy `.<filename>.bookmarks.json` sidecar from older versions is read once and migrated.

### Column mode and multi-caret
- **Column mode (⌥C):** ⌥-drag or ⇧+arrows select a rectangle; typing and deleting apply to every line; short lines are padded with virtual space; copy and paste work line-wise; **Insert Number (⌥⌘N)** fills a sequence.
- **Multi-caret:** ⌘-click adds a caret, ⌘D adds the next occurrence of the selection, ⌥⌘A selects every search match. Every multi-edit is one undo step.

### Text tools (Edit tab and the Line menu)
Delete line ⇧⌘K · duplicate ⇧⌘D · move up / down ⌥↑ / ⌥↓ · join ⇧⌘J · reverse · number lines · sort ascending / descending / numeric · remove duplicate lines · remove blank lines · trim trailing / both · tabs → spaces · spaces → tabs · UPPER / lower / Capitalize / iNVERT case.

- **Calculate (⌃⌘=):** evaluates the selection, or the current line (the part after the last `=` if there is one), and appends ` ⇒ result` — `3+0.5+0.25` becomes `3+0.5+0.25 ⇒ 3.75`; running it again on an edited line replaces the old result. Plain arithmetic only: `+ - * / % ^`, parentheses, `1,234` / `1_000` numbers, `sqrt abs round floor ceil min max`, `pi` and `e`. Invalid expressions are reported in the Output panel and leave the text alone.
- **Macros (⇧⌘M record / stop, ⌥⌘M play):** records typing (for Korean IME, only the committed syllables), caret movement, deletion and newline commands, paste (as the clipboard text at the time), the text tools above and Find Next (F3, with its query), then replays them at the caret. "Play Macro Multiple Times…" repeats up to 10,000 times and stops on its own when a Find step finds nothing or a run changes nothing; a whole run is one undo step. The last recording is kept in memory only until you quit (so passwords typed while recording never reach the disk); "Save Last Macro As…" adds it to the Macro menu, and the saved list lives in `~/Library/Application Support/HyperEdit/macros/macros.json`, which "Edit Macros File…" opens in the editor. Mouse clicks, selection changes and multi-caret edits (Replace All, Insert Number) are not recorded. The status bar shows `● REC` while recording.
- **Align Columns (⌃⌘T):** pads tab-separated columns (the selected lines, or the block of tab lines around the caret) so every column starts at the same display column, counting Hangul / CJK as two cells. Lines that all contain `|` are treated as a Markdown table instead: cells are padded inside ` | `, `---` rows are redrawn and `--:` columns right-aligned.
- **Toggle Comment (⌘/):** comments or uncomments the selected lines (or the current line) with the file type's marker — `//`, `#`, `--`, … for code, `<!-- -->` for Markdown and HTML/XML, `/* */` for CSS, `//` for plain notes. VS Code semantics: if every non-blank line is already commented they are all uncommented, otherwise all are commented, with the markers aligned at the shallowest indentation; blank lines are skipped and tabs stay tabs.
- **Format JSON (⌃⌘J) / Minify JSON:** pretty-prints (2-space indent) or collapses the selection, or the whole document when nothing is selected. Key order and number text (`1.0`, big integers) are preserved, strings are re-escaped minimally (Korean and emoji stay as-is). Input may contain a BOM, trailing commas and `//` / `/* */` comments (JSONC); the output is always strict JSON. On a syntax error the text is left alone, the Output panel shows `line:column` and the caret jumps there. A 5.6 MB document formats in about 30 ms.
- **Snippets:** type a trigger such as `todo`, `date`, `time`, `now`, `meeting`, `table`, `link` or `code` and press Tab, or pick one from **Insert Snippet… (⇧⌘I)**. Bodies support `${date}`, `${time}`, `${datetime}`, `${selection}`, `${clipboard}`, `${filename}` and tabstops `$1` … `$9`, `${1:placeholder}` and `$0`; Tab / ⇧Tab move between tabstops (a number used twice becomes a multi-caret), Esc or a click ends the session. **Edit Snippets…** opens `~/Library/Application Support/HyperEdit/snippets.json` in HyperEdit itself; it is re-read after you save.

### Saving
- Autosave 2 seconds after typing stops. On quit, window close and when switching files the document is saved synchronously, so there is no 2-second loss window. Every write is atomic.
- A snapshot copy is taken before the first save of each session, under `~/Library/Application Support/HyperEdit/snapshots`; per file the newest 20 are kept and anything older than 90 days is pruned.
- External changes are detected: the file is reloaded when the buffer is clean (the caret stays where it was); when it is dirty the external version is snapshotted and a warning is shown.
- An empty buffer is never written over a non-empty file.
- Encoding is detected losslessly — UTF-8 first, then EUC-KR (CP949), CP1252 and Latin-1 — shown in the status bar and used again when saving (a UTF-8 BOM is preserved). If you type a character the original encoding cannot represent, the file is saved as UTF-8 and the status bar says so. A file that cannot be decoded in any of these encodings is not opened at all, rather than being corrupted by a lossy round-trip.
- The status bar shows Ln / Col (plus selection length; the character offset is a tooltip), line ending (UNIX / DOS / MAC), file encoding, a COL indicator, caret count, line count · size, the status message, the syntax language (dimmed while syntax colors are off), a theme picker (marked "· 시스템" while following the system appearance) and zoom %.

### Export (HTML / PDF)
- **File › Export as HTML…** writes the document as one self-contained HTML file; **File › Export as PDF…** prints the same page to a paginated PDF. The save panel opens in the document's folder and offers a **Theme** (current, Hyper Light or Hyper Dark) and, for notes and code, **Line numbers**.
- Markdown files are rendered exactly like the preview (headings, lists and task lists, tables, fenced code, quotes, links, images) with the theme inlined as CSS; raw HTML stays escaped and the page contains no scripts and loads nothing external. Notes and code become a `<pre>` block colored with the file's syntax rules, including multi-line comments and strings.
- PDFs use Letter paper in the US, Canada and Mexico and A4 elsewhere, 36 pt margins and no header or footer; headings stay with the text below them and tables and code blocks are kept on one page when they fit. PDF export is available up to 2 MB, like the preview. The Output panel and status bar report `Exported HTML · ~/path` or an error.

### Secret blocks
- A fenced code block whose info string starts with `secret` (```` ```secret ````, ```` ```secret bank ````) is a **secret block**: in the editor its lines are drawn as a blank bar with `••••••••` while the fence lines stay visible, so you can keep passwords, keys and tokens in your notes without showing them on screen. Move the caret into the block (click, ↑ / ↓, Go to Line, a find result, a bookmark) and it is revealed and editable; move out and it is masked again. The text itself is untouched — Find, Replace, undo and saving work as before — and this is masking, not encryption: the file and its snapshots are plain text.
- **Reveal Secrets (⌥⌘S)** shows every block and masks them again after Settings › Secrets › *Re-mask after* (10 / 30 / 60 s or never); the status bar shows `REVEALED` meanwhile, and `•••• N` while N blocks are masked. Find results, the Outline, the Timeline, the Markdown preview and HTML / PDF exports show secret lines as `••••••••`.
- **Clipboard auto-clear:** copying or cutting text that overlaps a secret line clears the clipboard after 10 / 30 / 60 s (default 30 s) unless you copied something else in the meantime; **Edit › Clear Clipboard** clears it at once.

## Keyboard shortcuts

| Shortcut | Action | Shortcut | Action |
|---|---|---|---|
| ⌘N | New document | ⌘O | Open |
| ⌘S | Save | ⌘F | Find |
| ⌘R | Replace | ⇧⌘F | Find in files |
| F3 / ⇧F3 | Next / previous match | ⌘L | Go to line |
| ⌃⌘E | End of document | ⌥C | Column mode |
| ⌘D | Add next occurrence | ⌥⌘A | Select all matches |
| ⌥⌘N | Insert numbers | F7 | Insert timestamp |
| ⌘F2 | Toggle bookmark | F2 / ⌥F2 | Next / previous bookmark |
| ⇧⌘K | Delete line | ⇧⌘D | Duplicate line |
| ⌥↑ / ⌥↓ | Move line up / down | ⇧⌘J | Join lines |
| ⌃⌘= | Calculate (append ⇒ result) | ⌃⌘T | Align columns |
| ⌘/ | Toggle comment | ⌃⌘J | Format JSON |
| ⇧⌘I | Insert snippet | Tab | Expand snippet trigger / next tabstop |
| ⌘1 | Sidebar | ⌘2 | Bottom panel |
| ⌘3 | Outline | ⌘4 | Timeline |
| ⌥⌘L | Line numbers | ⌥Z | Word wrap |
| ⌥⌘] / ⌥⌘[ | Next / previous theme | ⌘= / ⌘- / ⌘0 | Zoom in / out / reset |
| ⌘, | Settings | ⇧⌘P | Markdown preview |
| ⌃⌘H | Syntax colors | ⌘\\ | Split editor |
| ⌥⌘\\ | Focus other split | ⇧⌘N | Quick Append |
| ⌃⌥N | Quick Append from any app (global, configurable) | ⇧⌘M | Record / stop macro |
| ⌥⌘M | Play macro | ⌥⌘← / ⌥⌘→ | Fold / unfold |
| ⌥⇧⌘← / ⌥⇧⌘→ | Fold all / unfold all | ⌥⌘S | Reveal / mask secret blocks |

## Themes

22 palettes are defined once in [`themes/palettes.json`](themes/palettes.json) and drive both the app and the generated [Zed](https://zed.dev) themes. By default the app follows the system appearance — **Hyper Light** in light mode, **Hyper Dark** in dark mode. Picking a theme (Layout tab, status-bar menu, View menu, or ⌥⌘] / ⌥⌘[) fixes it; "Follow system appearance" is one click away in the same three menus and in Settings (⌘,).

| Light (5) | Dark (17) |
|---|---|
| Hyper Light · Hyper Gruvbox Light · Hyper Solarized Light · Hyper Catppuccin Latte · Hyper GitHub Light | Hyper Dark · Hyper Homebrew Terminal · Hyper Green Blue Contrast · Hyper Xcode High Contrast Dark · Hyper One Dark · Hyper Dracula · Hyper Gruvbox Dark · Hyper Solarized Dark · Hyper Nord · Hyper Catppuccin Mocha · Hyper Tokyo Night · Hyper GitHub Dark · Hyper Monokai · Hyper Night Owl · Hyper Rosé Pine · Hyper Everforest Dark · Hyper Ayu Mirage |

Preview them all in [`docs/theme-preview.html`](docs/theme-preview.html). **Zed:** the same palettes are exported to `themes/dist/hyperedit-themes.json`, which is also attached to every release. Install with `python3 themes/build_zed_theme.py --install`, then pick a `Hyper …` theme with ⌘K ⌘T. See [docs/zed.md](docs/zed.md).

## Fonts and CJK

HyperEdit uses **Fira Code** when it is installed and the system monospaced font otherwise. Hangul (Korean) is drawn with a separate fallback font — **D2Coding** by default, when installed — scaled ×1.2 so that one Hangul syllable is exactly two Latin cells wide, which keeps tab-aligned tables straight. Ligatures, line height, both font families and the CJK scale live in Settings (⌘,). Details and alternatives: [docs/fonts.md](docs/fonts.md).

## Build from source

Requires Xcode 16 or later on macOS 15 and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen
scripts/bootstrap.sh                                   # generates HyperEdit.xcodeproj (git-ignored)
scripts/build-mac.sh --run                             # Release build, then launch (the first build fetches swift-markdown)
scripts/build-mac.sh Debug --run --file path/to/file   # Debug is much slower on big files
swift test --package-path Packages/HyperCore           # engine unit tests
scripts/install-mac.sh --open                          # install to ~/Applications
scripts/make-dmg.sh                                    # DMG (+ sign / notarize / staple when credentials exist)
```

Signing defaults to Xcode's "Sign to Run Locally", so no Apple team is needed to build and run. To sign with your own team, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (git-ignored) and fill in your team ID. `scripts/make-dmg.sh` signs and notarizes automatically when a Developer ID certificate and notarization credentials are present; `scripts/setup-signing.sh` walks through setting them up.

### Developer launch flags

Useful for screenshots, automation and debugging. Pass them after `open -n HyperEdit.app --args …` or `scripts/build-mac.sh --run …`.

| Flag | Effect |
|---|---|
| `--file <path>` | Open this file instead of the remembered one |
| `--snapshot <png> [--snapshot-delay s] [--snapshot-activate] [--quit]` · `--snapshot-panel <png>` · `--window-width <pt>` | Capture the window to PNG via ScreenCaptureKit (needs Screen Recording permission); `--snapshot-panel` captures the floating Quick Append panel opened by `--quick-append`. Snapshot runs use a 1280 pt window unless a width is given |
| `--selftest [--selftest-out <txt>] [--quit]` · `--selftest-split-big <file>` · `--show-snippet-picker` · `--show-macro-recording` · `--snapshot-sheet <png>` | Run the built-in self-test (393 checks) on temporary files; never touches your documents. `--selftest-split-big` adds a split-editor typing-latency check that types into and restores the given file (use a copy); `--show-snippet-picker` leaves the Insert Snippet sheet open for screenshots. `--selftest-open` is a file-switching benchmark that edits the files it is pointed at — copies only |
| `--theme <id>` · `--follow-system-theme` | Start with a palette id from `palettes.json`, e.g. `hyper-dark` / start following the system appearance |
| `--ribbon <home\|edit\|layout\|advanced\|window>` | Select a ribbon tab |
| `--left <files\|outline\|timeline>` · `--bottom <find\|bookmarks\|output>` · `--hide-left` · `--hide-bottom` | Show a sidebar / bottom-panel tab, or hide the sidebar / bottom panel |
| `--search <text>` · `--replace [--replace-with <text>]` · `--find-in-files` | Pre-fill the Find panel |
| `--column` · `--goto <line>` · `--preview` | Turn column mode on / jump to a line / show the Markdown preview |
| `--show-settings` · `--snapshot-settings <png>` | Open the Settings window after launch / capture it to PNG (with `--snapshot`) — used for the per-language screenshots |
| `--split [vertical\|horizontal]` · `--quick-append` | Start with the editor split (side by side by default) / open the Quick Append panel |
| `--no-highlight` | Start with syntax colors off (for screenshot comparisons) |
| `--fold <line>` · `--fold-all` · `--no-fold` | Fold the region headed by a line / fold everything once regions are scanned / disable folding entirely |
| `--cursor <bar\|block\|underline>` · `--no-cursor-blink` · `--opacity <0.5–1.0>` · `--blur` | Start with that caret style / blinking off / the window at that opacity / blur behind the translucent window |
| `--reveal-secrets` | Start with every secret block revealed (no re-mask timer) |
| `--ephemeral` | Use throwaway preferences (theme, panels, remembered file, snippets, macros, grammars) for this run — for manual testing |
| `--debug-perf [--debug-perf-log <path>]` | Log timings and main-thread stalls over 120 ms |
| `--debug-startup [--debug-startup-log <file>]` · `--debug-preview-log <file>` · `--debug-no-apply` | Diagnostics: log window creation during launch to stderr (and a file) / log Markdown preview renders and navigation / skip theme and font attribute application |
| `--bench [--bench-out <json>] [--bench-strict] [--bench-only <phases>] [--bench-commit <sha>] [--quit]` | Performance benchmark on a generated corpus (2 KB–8 MB); writes JSON + Markdown with PASS/FAIL budgets — see [docs/performance.md](docs/performance.md). Phases: `idle open memory scroll search outline theme typing replace save`. `scripts/bench.sh` wraps it |
| `--quit-after-launch [--bench-launch-log <file>]` | Quit ~0.1 s after the first window and append launch milestones (process start → window) to the log |

## Project layout

```
Apps/mac/            SwiftUI shell: ribbon, panels, settings, menus (HyperEditApp.swift, MacroUI.swift, SecretsUI.swift, GrammarUI.swift, Appearance.swift), Export/, Bench.swift, SelfTest*.swift
  Editor/            AppKit editor: HyperTextView (TextKit 2, caret styles), GutterView, EditorSession (split), FoldController, SecretController, ScrollMarkerView, SnippetSession, MacroRecorder
  QuickAppend/       Non-activating NSPanel, controller and the Carbon global hot key
  Panels/ Markdown/  Sidebar and bottom panels, SnippetPickerView · WKWebView Markdown preview
Packages/HyperCore/  Engine (document, line index, search, text tools, comment toggle, JSON formatter, snippets, macro model, Quick Append composer, column-block math, outline/timeline, fold scanner, secret-block scanner, syntax grammars with line-state tracking and user grammars, HTML export, themes, fonts, Markdown → HTML, per-language welcome text) + 200 unit tests
themes/              palettes.json (single source), build_zed_theme.py, build_preview.py, validate.py, dist/
docs/                guide/ (USER_GUIDE.md + 10 translations) · features.md · performance.md · fonts.md · zed.md · design.ko.md · theme-preview.html · bench/ · release-notes/ · screenshots/ · sample/
l10n/                ui.<language>.json — one flat dictionary per language (exported by scripts/l10n-export.py, merged by scripts/l10n-add.py) · context.json
scripts/             bootstrap · build-mac · install-mac · make-dmg · bench · make-icon.swift · set-version · setup-signing · update-cask · check-sensitive · check-l10n · l10n-export · l10n-add · install-hooks
Config/              Version.xcconfig (managed by semantic-release) · Signing.xcconfig defaults · Local.xcconfig.example
.github/workflows/   ci.yml (themes, sensitive-info check, commitlint, macOS build + tests) · release.yml (semantic-release → DMG → GitHub Release → Homebrew cask)
```

`HyperCore` is platform-neutral (macOS 15 / iOS 18 targets are declared), but only the macOS app exists today.

## Release process

Commits follow [Conventional Commits](https://www.conventionalcommits.org); subjects are written in English because semantic-release turns them into the release notes (bodies may be Korean). On every push to `main`, [semantic-release](https://semantic-release.gitbook.io) computes the next version from the commits, updates `CHANGELOG.md`, `VERSION` and `Config/Version.xcconfig`, builds, signs and notarizes the DMG, publishes a GitHub Release (English notes from the commits plus `docs/release-notes/vX.Y.Z.md` when that file exists) with `SHA256SUMS` and the Zed theme file, and updates the Homebrew cask in `Hyeongcheol-An/homebrew-tap`. `feat:` → minor, `fix:` / `perf:` → patch, `docs:` / `chore:` / `refactor:` → no release. The workflow refuses to publish without the Developer ID and notarization secrets (forks can set the repository variable `ALLOW_UNSIGNED_RELEASE=true` to allow unsigned builds). Release builds strip symbols and dead code (`project.yml`: `DEAD_CODE_STRIPPING`, `STRIP_INSTALLED_PRODUCT`, `STRIP_STYLE: all`), which took the universal binary from 13.5 MB to 6.5 MB in v0.6. Install the local commit-message hook with `scripts/install-hooks.sh`.

## Roadmap and limitations

- The interface is translated into eleven languages; any other system language falls back to English (Traditional Chinese, for example). Changing the language needs a relaunch, which the Settings button does for you.
- Syntax colors track block comments, multi-line strings and Markdown fences across lines, but only same-open-and-close string delimiters and one block-comment pair per language are supported, and user grammars are word lists (no regular-expression rules). The Markdown preview (⇧⌘P) renders the current file but is a view, not an editor.
- Local files only; no cloud sync. No iOS app yet, although the engine is built to allow one.
- Macros record keyboard editing only (no mouse, selection or multi-caret steps). The inline calculator and column alignment work on plain arithmetic and tab / pipe tables only (no variables, units or date math). Toggle Comment is line-based (no block-comment selection), and the JSON formatter has no sort or schema features.
- Snippets, macros and user grammars are edited as JSON files (`snippets.json`, `macros/macros.json`, `grammars/*.json` under Application Support); there is no GUI editor for them.
- Export writes the whole document only (no selection or multi-file export, no page-size or font options, no PDF table of contents). Secret blocks are masked on screen only — the file, autosaves, snapshots and Find in Files results of other files are plain text, and the mask bar reveals line lengths.
- Code folding lasts for the session only (folds are not saved per file), and a mouse drag across a folded header still selects the hidden text.
- The Quick Append global shortcut uses the system hot-key API, so the ⌃Space / ⌃⌥Space variants lose silently to input-source switching when that is enabled in System Settings › Keyboard; pick ⌃⌥N or ⌃⌥⌘N instead.

Design notes and the decision history are in [docs/design.ko.md](docs/design.ko.md) (Korean); the feature catalog with status is in [docs/features.md](docs/features.md).

## Contributing and security

Bug reports and ideas go to [GitHub Issues](https://github.com/Hyeongcheol-An/HyperEdit/issues) and [Discussions](https://github.com/Hyeongcheol-An/HyperEdit/discussions). See [CONTRIBUTING.md](CONTRIBUTING.md) for the development setup, commit convention and PR checklist, and [SECURITY.md](SECURITY.md) for reporting vulnerabilities privately. This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).

## Trademark note

HyperEdit's layout is inspired by the classic UltraEdit ribbon. UltraEdit is a trademark of IDM Computer Solutions, Inc.; HyperEdit is an independent open-source project and is not affiliated with or endorsed by IDM.

## License

[MIT](LICENSE) © 2026 Hyeongcheol An

The Markdown preview is built with [swift-markdown](https://github.com/swiftlang/swift-markdown) and its [swift-cmark](https://github.com/swiftlang/swift-cmark) (cmark-gfm) dependency, both © Apple Inc. and contributors, licensed under the [Apache License 2.0](https://github.com/swiftlang/swift-markdown/blob/main/LICENSE.txt). They are fetched by Swift Package Manager at build time and linked into the app.
