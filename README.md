<p align="center"><img src="docs/screenshots/app-icon-1024.png" width="120" alt="HyperEdit app icon"></p>

<h1 align="center">HyperEdit</h1>

<p align="center"><b>A fast, ribbon-style plain-text editor for macOS, built around one big notes file.</b></p>

<p align="center">
<a href="https://github.com/Hyeongcheol-An/HyperEdit/releases"><img alt="Release" src="https://img.shields.io/github/v/release/Hyeongcheol-An/HyperEdit?sort=semver"></a>
<a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/github/license/Hyeongcheol-An/HyperEdit"></a>
<a href="https://github.com/Hyeongcheol-An/HyperEdit/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/Hyeongcheol-An/HyperEdit/ci.yml?branch=main&label=CI"></a>
<img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-black">
</p>

<p align="center">English · <a href="README.ko.md">한국어</a></p>

HyperEdit is for people who keep a single, ever-growing text file — tens of thousands of lines of notes, logs and snippets — and spend the day appending to it and searching through it. A SwiftUI shell wraps an AppKit `NSTextView` on TextKit 2, so a multi-megabyte file still types like a small one, and the window follows the layout of a classic ribbon editor: ribbon tabs, a document tab bar, a sidebar, a bottom panel and a dense status bar.

| Hyper Light | Hyper Dark |
|---|---|
| ![HyperEdit in the Hyper Light theme](docs/screenshots/hyperedit-light.png) | ![HyperEdit in the Hyper Dark theme](docs/screenshots/hyperedit-dark.png) |

## Install

**Requirements:** macOS 15 (Sequoia) or later. Universal binary (Apple Silicon and Intel).

**Homebrew**

```sh
brew tap Hyeongcheol-An/tap
brew install --cask hyperedit
```

Homebrew 7 may ask you to trust the tap first: `brew trust Hyeongcheol-An/tap`.

**DMG**

Download `HyperEdit-x.y.z.dmg` from [GitHub Releases](https://github.com/Hyeongcheol-An/HyperEdit/releases), open it and drag `HyperEdit.app` to `Applications`. Builds are Developer ID signed and notarized, so Gatekeeper opens them without warnings. To verify a download, put `SHA256SUMS` next to the DMG and run:

```sh
shasum -a 256 -c SHA256SUMS
```

### First launch

HyperEdit opens `~/Documents/HyperEdit/notes.md`, creating it with a short welcome text if it does not exist. ⌘N creates a new empty text file (you choose the name and folder), ⌘O opens any other text file, and the last opened file is remembered for the next launch. Binary files (images, PDFs, archives…) are never loaded into the editor; they open in their default app instead.

> The UI is available in English and Korean and follows the system language. The ribbon layout and shortcuts are the same on every system — translations for other languages are welcome (`Apps/mac/Localizable.xcstrings`).

## Features

### Editor
- Tuned for big files: about 3 ms per keystroke on a 1.3 MB / 34,000-line file, with viewport-based TextKit 2 layout.
- Line-number gutter, current-line highlight, word wrap (⌥Z), line numbers (⌥⌘L), zoom (⌘= / ⌘- / ⌘0).
- Last caret and scroll position restored per file; ⌃⌘E jumps to the end; ⌘L goes to a line.
- F7 inserts a timestamp heading such as `## 2026-10-30 (Fri) 14:05`. The weekday follows the system locale, e.g. `(금)` on Korean systems.
- **Split editor (⌘\\)** shows the same document in two editors, side by side or stacked (View › Split, or the Layout tab). Both views edit the same text and share one undo stack — type in one, ⌘Z in the other — but scroll independently; commands, the status bar and the Markdown preview follow the view you clicked last, and ⌥⌘\\ moves the focus to the other split. The status bar shows **SPLIT** while it is on.
- **Quick Append (⇧⌘N, or ⌃⌥N from any app):** a small floating panel that does not activate HyperEdit. Type a note, press ⌘↩ and it is appended to the end of the document — with a timestamp heading by default — saved at once, and undoable in one step; the panel then hides and focus returns to the app you were in. Esc closes the panel and keeps the draft for next time. The global shortcut (off / ⌃⌥N / ⌃⌥Space / ⌃⇧Space / ⌃⌥⌘N) is chosen in Settings and needs no Accessibility permission.
- **Syntax colors (⌃⌘H)**, chosen by file extension and shown in the status bar. Notes and Markdown get a deliberately light rule set — URLs, ISO dates and times, `#` headings, `[Title]` lines, list markers and `[ ]` / `[x]` task boxes, `#tags`, `key:` labels, `**bold**`, `` `code` `` and `⇒ → ->` arrows — and about 20 code languages (Swift, Python, JavaScript/TypeScript, JSON, shell, YAML, HTML/XML, CSS, C/C++/Objective-C, Go, Rust, SQL, Ruby, Java/Kotlin, TOML, INI) get comments, strings, numbers, keywords, function and type names. Colors come from the theme's `syntax` palette and are applied as TextKit 2 rendering attributes to visible lines only, so they never touch the file, undo history or typing speed. Tokenization is line-based: a block comment or string that spans lines is colored only where it opens.

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
- **Align Columns (⌃⌘T):** pads tab-separated columns (the selected lines, or the block of tab lines around the caret) so every column starts at the same display column, counting Hangul / CJK as two cells. Lines that all contain `|` are treated as a Markdown table instead: cells are padded inside ` | `, `---` rows are redrawn and `--:` columns right-aligned.

### Saving
- Autosave 2 seconds after typing stops. On quit, window close and when switching files the document is saved synchronously, so there is no 2-second loss window. Every write is atomic.
- A snapshot copy is taken before the first save of each session, under `~/Library/Application Support/HyperEdit/snapshots`; per file the newest 20 are kept and anything older than 90 days is pruned.
- External changes are detected: the file is reloaded when the buffer is clean (the caret stays where it was); when it is dirty the external version is snapshotted and a warning is shown.
- An empty buffer is never written over a non-empty file.
- Encoding is detected losslessly — UTF-8 first, then EUC-KR (CP949), CP1252 and Latin-1 — shown in the status bar and used again when saving (a UTF-8 BOM is preserved). If you type a character the original encoding cannot represent, the file is saved as UTF-8 and the status bar says so. A file that cannot be decoded in any of these encodings is not opened at all, rather than being corrupted by a lossy round-trip.
- The status bar shows Ln / Col (plus selection length; the character offset is a tooltip), line ending (UNIX / DOS / MAC), file encoding, a COL indicator, caret count, line count · size, the status message, the syntax language (dimmed while syntax colors are off), a theme picker (marked "· 시스템" while following the system appearance) and zoom %.

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
| ⌘1 | Sidebar | ⌘2 | Bottom panel |
| ⌘3 | Outline | ⌘4 | Timeline |
| ⌥⌘L | Line numbers | ⌥Z | Word wrap |
| ⌥⌘] / ⌥⌘[ | Next / previous theme | ⌘= / ⌘- / ⌘0 | Zoom in / out / reset |
| ⌘, | Settings | ⇧⌘P | Markdown preview |
| ⌃⌘H | Syntax colors | ⌘\\ | Split editor |
| ⌥⌘\\ | Focus other split | ⇧⌘N | Quick Append |
| ⌃⌥N | Quick Append from any app (global, configurable) | | |

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
| `--snapshot <png> [--snapshot-delay s] [--quit]` | Capture the window to PNG via ScreenCaptureKit (needs Screen Recording permission) |
| `--selftest [--selftest-out <txt>] [--quit]` | Run the built-in self-test on temporary files; never touches your documents |
| `--theme <id>` | Start with a palette id from `palettes.json`, e.g. `hyper-dark` |
| `--ribbon <home\|edit\|layout\|advanced\|window>` | Select a ribbon tab |
| `--left <files\|outline\|timeline>` · `--bottom <find\|bookmarks\|output>` | Show a sidebar / bottom-panel tab |
| `--search <text>` · `--replace [--replace-with <text>]` · `--find-in-files` | Pre-fill the Find panel |
| `--column` · `--goto <line>` · `--preview` | Turn column mode on / jump to a line / show the Markdown preview |
| `--split [vertical\|horizontal]` · `--quick-append` | Start with the editor split (side by side by default) / open the Quick Append panel |
| `--no-highlight` | Start with syntax colors off (for screenshot comparisons) |
| `--ephemeral` | Use throwaway preferences (theme, panels, remembered file) for this run — for manual testing |
| `--debug-perf [--debug-perf-log <path>]` | Log timings and main-thread stalls over 120 ms |

## Project layout

```
Apps/mac/            SwiftUI shell: ribbon, panels, settings, the AppKit editor in Editor/ and the WKWebView Markdown preview in Markdown/
Packages/HyperCore/  Engine (document, search, text tools, column-block math, outline/timeline, themes, fonts, Markdown → HTML) + tests
themes/              palettes.json (single source), build_zed_theme.py, build_preview.py, validate.py, dist/
docs/                features.md · fonts.md · zed.md · design.ko.md · theme-preview.html · screenshots/ · sample/
scripts/             bootstrap · build-mac · install-mac · make-dmg · make-icon.swift · set-version · setup-signing · update-cask · check-sensitive · install-hooks
Config/              Version.xcconfig (managed by semantic-release) · Signing.xcconfig defaults · Local.xcconfig.example
.github/workflows/   ci.yml (themes, sensitive-info check, commitlint, macOS build + tests) · release.yml (semantic-release → DMG → GitHub Release → Homebrew cask)
```

`HyperCore` is platform-neutral (macOS 15 / iOS 18 targets are declared), but only the macOS app exists today.

## Release process

Commits follow [Conventional Commits](https://www.conventionalcommits.org) (Korean or English subjects are fine). On every push to `main`, [semantic-release](https://semantic-release.gitbook.io) computes the next version from the commits, updates `CHANGELOG.md`, `VERSION` and `Config/Version.xcconfig`, builds, signs and notarizes the DMG, publishes a GitHub Release with `SHA256SUMS` and the Zed theme file, and updates the Homebrew cask in `Hyeongcheol-An/homebrew-tap`. `feat:` → minor, `fix:` / `perf:` → patch, `docs:` / `chore:` / `refactor:` → no release. The workflow refuses to publish without the Developer ID and notarization secrets (forks can set the repository variable `ALLOW_UNSIGNED_RELEASE=true` to allow unsigned builds). Install the local commit-message hook with `scripts/install-hooks.sh`.

## Roadmap and limitations

- UI in English and Korean (follows the system language); no other languages yet.
- Syntax colors are line-based (multi-line comments and strings are colored only on the line where they open) and there is no user-defined grammar. The Markdown preview (⇧⌘P) renders the current file but is a view, not an editor.
- Local files only; no cloud sync. No iOS app yet, although the engine is built to allow one.
- Planned editing tools — comment toggle, JSON tidy, macros — are on the roadmap but not implemented yet. The inline calculator and column alignment work on plain arithmetic and tab / pipe tables only (no variables, units or date math).

Design notes and the decision history are in [docs/design.ko.md](docs/design.ko.md) (Korean); the feature catalog with status is in [docs/features.md](docs/features.md).

## Contributing and security

Bug reports and ideas go to [GitHub Issues](https://github.com/Hyeongcheol-An/HyperEdit/issues) and [Discussions](https://github.com/Hyeongcheol-An/HyperEdit/discussions). See [CONTRIBUTING.md](CONTRIBUTING.md) for the development setup, commit convention and PR checklist, and [SECURITY.md](SECURITY.md) for reporting vulnerabilities privately. This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md).

## Trademark note

HyperEdit's layout is inspired by the classic UltraEdit ribbon. UltraEdit is a trademark of IDM Computer Solutions, Inc.; HyperEdit is an independent open-source project and is not affiliated with or endorsed by IDM.

## License

[MIT](LICENSE) © 2026 Hyeongcheol An

The Markdown preview is built with [swift-markdown](https://github.com/swiftlang/swift-markdown) and its [swift-cmark](https://github.com/swiftlang/swift-cmark) (cmark-gfm) dependency, both © Apple Inc. and contributors, licensed under the [Apache License 2.0](https://github.com/swiftlang/swift-markdown/blob/main/LICENSE.txt). They are fetched by Swift Package Manager at build time and linked into the app.
