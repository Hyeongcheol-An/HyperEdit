# HyperEdit User Guide

<p align="center">English · <a href="USER_GUIDE.ko.md">한국어</a> · <a href="USER_GUIDE.zh-Hans.md">简体中文</a> · <a href="USER_GUIDE.ja.md">日本語</a> · <a href="USER_GUIDE.vi.md">Tiếng Việt</a> · <a href="USER_GUIDE.hi.md">हिन्दी</a> · <a href="USER_GUIDE.de.md">Deutsch</a> · <a href="USER_GUIDE.fr.md">Français</a> · <a href="USER_GUIDE.es.md">Español</a> · <a href="USER_GUIDE.pt.md">Português</a> · <a href="USER_GUIDE.ar.md">العربية</a></p>

HyperEdit is a fast plain-text editor for macOS built around one big notes file — the kind you keep appending to for years. This guide explains everything you can do with it, in the order you are likely to meet it. Shortcuts are written with the Mac symbols ⌘ Command, ⇧ Shift, ⌥ Option, ⌃ Control.

## Contents

1. [Install and update](#1-install-and-update)
2. [First launch](#2-first-launch)
3. [Interface language](#3-interface-language)
4. [The window](#4-the-window)
5. [Editing basics](#5-editing-basics)
6. [Find and replace](#6-find-and-replace)
7. [Bookmarks](#7-bookmarks)
8. [Column mode and multi-caret](#8-column-mode-and-multi-caret)
9. [Line and text tools](#9-line-and-text-tools)
10. [Snippets](#10-snippets)
11. [Macros](#11-macros)
12. [Code folding and scrollbar markers](#12-code-folding-and-scrollbar-markers)
13. [Split editor](#13-split-editor)
14. [Quick Append](#14-quick-append)
15. [Markdown preview and syntax colors](#15-markdown-preview-and-syntax-colors)
16. [Themes, fonts and CJK text](#16-themes-fonts-and-cjk-text)
17. [Saving, snapshots and encodings](#17-saving-snapshots-and-encodings)
18. [Settings reference](#18-settings-reference)
19. [Keyboard shortcuts](#19-keyboard-shortcuts)
20. [Files HyperEdit writes](#20-files-hyperedit-writes)
21. [Troubleshooting](#21-troubleshooting)
22. [Known limitations](#22-known-limitations)
23. [Secret blocks and app lock](#23-secret-blocks-and-app-lock)
24. [Getting help](#24-getting-help)

## 1. Install and update

**Requirements:** macOS 15 (Sequoia) or later. The app is a universal binary (Apple Silicon and Intel), signed and notarized, so Gatekeeper opens it without warnings.

**Homebrew**

```sh
brew tap Hyeongcheol-An/tap
brew install --cask hyperedit
```

Update later with `brew upgrade --cask hyperedit`. Homebrew 7 may ask you to trust the tap first: `brew trust Hyeongcheol-An/tap`.

**DMG:** download `HyperEdit-x.y.z-universal.dmg` from [GitHub Releases](https://github.com/Hyeongcheol-An/HyperEdit/releases), open it and drag `HyperEdit.app` to `Applications`. To verify a download, put `SHA256SUMS` next to the DMG and run `shasum -a 256 -c SHA256SUMS`.

HyperEdit has no network code and no telemetry: it never phones home, and updates are something you do, not something it does.

## 2. First launch

HyperEdit opens `~/Documents/HyperEdit/notes.md`. If that file does not exist it is created with a short welcome text in your language — delete the text and start writing. The idea is that you keep one file and append to it, but nothing forces that:

- **⌘N** creates a new empty text file (you choose the name and folder).
- **⌘O** opens any other text file. The last opened file is remembered for the next launch.
- **File › Open Default Document** takes you back to `notes.md`.
- Binary files (images, PDFs, archives…) are never loaded into the editor; they open in their default app instead.

Your caret and scroll position are remembered per file, so reopening a 30,000-line file puts you where you left off. **⌃⌘E** jumps to the end of the document — the place you usually want in a notes file.

## 3. Interface language

The interface is available in eleven languages: English, 한국어 (Korean), 简体中文 (Simplified Chinese), 日本語 (Japanese), Tiếng Việt (Vietnamese), हिन्दी (Hindi), Deutsch (German), Français (French), Español (Spanish), Português (Portuguese, Brazilian spelling) and العربية (Arabic). Arabic text is written right-to-left, but the window layout — ribbon, sidebar, panels and editor — stays left-to-right, as in most code editors; the text you type follows its own direction.

By default HyperEdit follows the system language. To choose a different one:

1. Open **Settings (⌘,)** and look at the **Language** section at the top.
2. Pick a language from the **Interface language** menu. Each language is listed in its own script, so you can find yours even if the current language is unfamiliar. **System Default** shows which language the system setting would give you.
3. Click **Relaunch Now**. The document is saved first, then HyperEdit quits and reopens in the new language. (You can also keep working and relaunch later; the choice is already saved.)

The choice is stored in the same place as **System Settings › General › Language & Region › Applications**, so the two agree with each other. **Help › User Guide** and the **Open User Guide** button in Settings open this guide in the current interface language.

A language that is not in the list falls back to English (for example Traditional Chinese). Document text, file names and dates you insert are not affected by the interface language — the timestamp weekday follows the system locale.

## 4. The window

The layout follows a classic ribbon editor, with a hidden title bar.

- **Ribbon tabs** — **Home** (Clipboard, Find, Insert, Mode, File), **Edit** (Lines, Case, Sort, Whitespace, Column & Multi-Caret, Tools, Macro), **Layout** (Theme, Panels, Folding, Markdown, Font Size), **Advanced** (Settings, snapshot folder, reload, default document), **Window** (full screen, panels). When the window is narrow, groups fold to icons from the right; the icon's tooltip shows the label.
- **Document tab bar** — the current file name with New (⌘N) and Open (⌘O) buttons, plus quick-access Save / Undo / Redo.
- **Sidebar (⌘1)** — **Files** (the folder of the current file; one click opens a file), **Outline (⌘3)** (headings, `[Title]` lines and numbered items, with a filter box; the current item is highlighted), **Timeline (⌘4)** (timestamp headings grouped by month, newest first).
- **Bottom panel (⌘2)** — **Find Results**, **Bookmarks** and **Output**, a log of what the app did (saves, replacements, errors).
- **Status bar** — line and column (plus the selection length; hover for the character offset), line ending (UNIX / DOS / MAC), file encoding, **COL** while column mode is on, caret count, line count · file size, the latest status message, the syntax language (dimmed while syntax colors are off), a theme menu (marked "· System" while following the system appearance) and the zoom percentage. Most items are clickable.

## 5. Editing basics

- Plain typing stays fast in multi-megabyte files; only the visible part of the document is laid out.
- **Word wrap** ⌥Z · **Line numbers** ⌥⌘L · **Zoom** ⌘= / ⌘- / ⌘0 (also in the Layout tab).
- **Go to line** ⌘L · **End of document** ⌃⌘E.
- **Insert Date/Time** F7 inserts a timestamp heading such as `## 2026-10-31 (Sat) 14:05`. The weekday follows your system locale. Lines like this feed the Timeline.
- The current line is highlighted and the gutter shows its number in the text color.
- Undo and redo are unlimited within a session, and every tool below is a single undo step.

## 6. Find and replace

- **Find (⌘F)** opens the Find bar. Type a query and press Enter: every match is listed in the bottom panel with its line number, and the matches are highlighted in the editor while the list is open. Toggles: regex `.*`, match case `Aa`, whole word `W`. **F3 / ⇧F3** step to the next / previous match. The list refreshes itself about a second after you edit.
- **Replace (⌘R)** adds a replacement field: replace the current match and move on, or **Replace All**. With regex on, templates such as `$1` insert capture groups. Replace All is one undo step, even with thousands of matches.
- **Find in Files (⇧⌘F)** searches a folder (subfolders included). Pick the folder, optionally limit by masks such as `*.md;*.txt`, and click a hit to open that file at that line. Hidden files, packages, binary files and files over 20 MB are skipped.
- **Select All Matches (⌥⌘A)** turns every match into a caret — see multi-caret below.

## 7. Bookmarks

**⌘F2** bookmarks the current line (or removes the bookmark), **F2 / ⌥F2** jump to the next / previous bookmark, and the **Bookmarks** tab of the bottom panel lists them all; you can give a bookmark a name there. Bookmarks follow their lines as you edit: inserting or deleting lines above moves them, deleting a bookmarked line removes it, and undo brings them back. They are stored per document under `~/Library/Application Support/HyperEdit/bookmarks/`, so nothing is written next to your files.

## 8. Column mode and multi-caret

- **Column mode (⌥C)** — hold ⌥ and drag, or use ⇧ with the arrow keys, to select a rectangle. Typing and deleting then apply to every line of the block, short lines are padded with virtual space, and copy / paste work line by line. The status bar shows **COL**. ⌥C again turns it off.
- **Insert Number (⌥⌘N)** — fills a column selection (or every caret) with a sequence: choose the start and step; numbers are zero-padded to the same width.
- **Multi-caret** — ⌘-click adds a caret, **⌘D** adds the next occurrence of the selected text (or the word at the caret), **⌥⌘A** selects every search match. Typing goes to every caret; Esc returns to one. Every multi-caret edit is one undo step.

## 9. Line and text tools

These live in the **Edit** ribbon tab and in the **Line** menu. They act on the selected lines, or on the current line when nothing is selected.

| Group | Tools |
|---|---|
| Lines | Delete Line ⇧⌘K · Duplicate Line ⇧⌘D · Move Line Up / Down ⌥↑ / ⌥↓ · Join Lines ⇧⌘J · Reverse Lines · Number Lines |
| Case | Uppercase · Lowercase · Capitalize · Invert Case |
| Sort | Ascending · Descending · Numeric Sort (by the number at the start of each line) · Remove Duplicate Lines |
| Whitespace | Trim Trailing Whitespace · Trim Leading and Trailing Whitespace · Remove Blank Lines · Tabs → Spaces · Spaces → Tabs |

- **Calculate (⌃⌘=)** evaluates the selection, or the current line (the part after the last `=` if there is one), and appends ` ⇒ result`: `3+0.5+0.25` becomes `3+0.5+0.25 ⇒ 3.75`. Running it again on an edited line replaces the old result. Supported: `+ - * / % ^`, parentheses, `1,234` and `1_000` numbers, `sqrt abs round floor ceil min max`, `pi` and `e`. An expression that cannot be evaluated is reported in the Output panel and the text is left alone.
- **Align Columns (⌃⌘T)** pads tab-separated columns (the selected lines, or the block of tab lines around the caret) so every column starts at the same display column; Korean, Chinese and Japanese characters count as two cells. If every line contains `|`, the block is treated as a Markdown table instead: cells are padded inside ` | `, `---` rows are redrawn and `--:` columns are right-aligned.
- **Toggle Comment (⌘/)** comments or uncomments the lines with the marker of the file type: `//`, `#`, `--`… for code, `<!-- -->` for Markdown and HTML, `/* */` for CSS, `//` for plain notes. If every non-blank line is already commented they are all uncommented, otherwise all are commented, with the markers aligned at the shallowest indentation. Blank lines are skipped.
- **Format JSON (⌃⌘J) / Minify JSON** pretty-prints (2-space indent) or collapses the selection, or the whole document when nothing is selected. Key order and number text are preserved, non-ASCII text stays unescaped, and input may contain comments and trailing commas (JSONC). On a syntax error the text is left alone, the Output panel shows `line:column` and the caret jumps there.

## 10. Snippets

Type a trigger word and press **Tab** to expand it. Built-in triggers: `todo`, `date`, `time`, `now`, `meeting`, `table`, `link`, `code`. **Insert Snippet… (⇧⌘I)** lists them all with a filter box, and the Home tab has a Snippet… button.

A snippet body may contain variables — `${date}`, `${time}`, `${datetime}`, `${selection}`, `${clipboard}`, `${filename}` — and tabstops `$1` … `$9`, `${1:placeholder}` and `$0`. After expansion, Tab / ⇧Tab move between the tabstops (a number used twice becomes a multi-caret), and Esc or a click ends the session.

**Edit Snippets…** (Edit menu or Home tab) opens `~/Library/Application Support/HyperEdit/snippets.json` in HyperEdit itself. Each entry has a `trigger`, a `name` and a `body`; the file is re-read after you save it, so a new trigger works immediately.

## 11. Macros

A macro records what you type and replays it elsewhere.

1. **Record Macro (⇧⌘M)** starts recording; the status bar shows `● REC`. Typing (for Korean and other IMEs, the committed characters), caret movement, deletion, newlines, paste, the text tools and Find Next (F3, with its query) are recorded. Mouse clicks, selection changes and multi-caret edits are not.
2. **⇧⌘M** again stops recording.
3. **Play Macro (⌥⌘M)** replays it at the caret. **Play Macro Multiple Times…** repeats it up to 10,000 times and stops on its own when a Find step finds nothing or a run changes nothing — a convenient "do this to every line" tool. A whole run is one undo step.

The last recording stays in memory only until you quit, so anything sensitive you typed while recording never reaches the disk. **Save Last Macro As…** adds it to the **Macro** menu for good; saved macros live in `~/Library/Application Support/HyperEdit/macros/macros.json`, which **Edit Macros File…** opens in the editor.

## 12. Code folding and scrollbar markers

**Fold (⌥⌘←) / Unfold (⌥⌘→)** hide or show the region at the caret; **⌥⇧⌘← / ⌥⇧⌘→** fold or unfold everything. A region is:

- the lines indented under the current line (blank lines ignored),
- in Markdown, everything under a `#` heading up to the next heading of the same or higher level (fenced code blocks fold too),
- in code, a line ending in `{`, `[` or `(` through its closing bracket line.

Click the chevron in the gutter or the `⋯ N lines` pill after a folded line to toggle it with the mouse. Moving the caret into a folded line (find, go to line, bookmark, undo) unfolds it; ↑ / ↓ skip over folds. Folds follow your edits and last for the session.

**Scrollbar markers** — a thin strip at the editor's right edge shows search matches (accent color), bookmarks (warning color), the caret line and folded headers at their relative positions in the file. It is hidden when the whole document fits on screen. Turn it off in **View › Scrollbar Markers** or in the Layout tab's Folding group.

## 13. Split editor

**⌘\\** shows the same document in two editors, side by side; **View › Split › Split Stacked** puts them one above the other, and the Layout tab has the same buttons. Both views edit the same text and share one undo history — type in one, ⌘Z in the other — but scroll independently, so you can read one part of a file while writing in another. Commands, the status bar and the Markdown preview follow the editor you clicked last; **⌥⌘\\** moves the focus to the other one. The status bar shows **SPLIT** while the split is on; ⌘\\ again closes it.

## 14. Quick Append

**Quick Append (⇧⌘N)** opens a small floating panel for adding a note without leaving what you were doing. Type the note, press **⌘↩**, and it is appended to the end of the document — with a timestamp heading by default — saved at once and undoable in one step. The panel then hides and the focus returns to the app you were in. **Esc** closes the panel and keeps the draft for next time.

Because the panel does not activate HyperEdit, it also works from any other app through a **global shortcut**: **⌃⌥N** by default. In Settings you can switch it off or choose ⌃⌥Space, ⌃⇧Space or ⌃⌥⌘N instead, and turn the timestamp heading off. The shortcut uses the system hot-key service, so no Accessibility permission is needed. If another app already owns the combination, the Output panel says so at launch — pick a different one.

## 15. Markdown preview and syntax colors

- **Markdown Preview (⇧⌘P)** splits the window with a rendered view of the current file on the right: headings, lists and task lists, tables, fenced code, quotes, links and images, styled with the current theme. It follows the editor's scroll position and re-renders shortly after you stop typing. Links open in your browser; raw HTML in the file is shown as text, never executed. Files over 2 MB show a notice instead of a preview. The status bar shows **MD** while it is on.
- **Syntax Colors (⌃⌘H)** are chosen by file extension and shown in the status bar. Notes and Markdown get a light rule set — URLs, dates and times, headings, `[Title]` lines, list markers and `[ ]` / `[x]` task boxes, `#tags`, `key:` labels, `**bold**`, `` `code` `` and `⇒ → ->` arrows — and about 20 programming languages get comments, strings, numbers, keywords, function and type names. Colors are drawn on the visible lines only, so they never change the file or slow down typing. Constructs that span lines keep their color until they close: block comments (`/* */`, `<!-- -->`), multi-line strings (Swift and Python `"""`, JavaScript template literals, Go raw strings, Rust `r#"…"#`) and Markdown fenced code blocks, which are colored with the language named in the info string (```` ```python ````). Typing an opening or closing delimiter recolors the lines below immediately.
- **User-defined grammars.** To color a language HyperEdit does not know, or to change a built-in one, put a `*.json` file in `~/Library/Application Support/HyperEdit/grammars/`. HyperEdit creates the folder on first launch with an `example.json` you can copy and a README that explains every key — `name`, `extensions` or `filenames`, `mode`, `lineComments`, `blockComment`, `strings`, `multilineStrings`, `keywords`, `types`, `constants`, `builtins`, `caseInsensitive`. **File › Reload Grammars** applies your changes without restarting; the status bar shows the grammar's name, Toggle Comment (⌘/) uses its comment markers, and a file that fails to parse is skipped with a message in the Output panel.

## 16. Themes, fonts and CJK text

**Themes.** 22 palettes — 5 light, 17 dark — ship with the app. By default it follows the system appearance: **Hyper Light** in light mode, **Hyper Dark** in dark mode. Pick a theme from the Layout tab, the status-bar theme menu, **View › Theme** or ⌥⌘] / ⌥⌘[ to fix it; **Follow System Appearance** is in the same menus and in Settings. The same palettes are available for the Zed editor (`hyperedit-themes.json` on every release).

**Cursor and window opacity.** Settings › **Appearance** chooses the caret shape — **Bar** (the default), **Block** (the character cell is tinted with the cursor color so the glyph stays readable) or **Underline** — and whether it blinks; the extra carets of multi-caret and column mode use the same shape. **Window opacity** (50–100 %) makes the whole window translucent — editor, ribbon, panels and status bar alike — while text, icons and borders stay solid, and **Blur behind window** adds the system blur. View › Window Opacity has 100 / 90 / 80 / 70 % steps.

**Fonts.** HyperEdit uses **Fira Code** when it is installed and the system monospaced font otherwise. Korean text is drawn with a separate font — **D2Coding** by default, when installed — scaled so that one Hangul syllable is exactly two Latin cells wide, which keeps tab-aligned tables straight. Ligatures, line height, both font families and the Hangul scale are in Settings. Chinese and Japanese text uses the system fallback fonts and also counts as two cells in Align Columns.

## 17. Saving, snapshots and encodings

- **Autosave** runs two seconds after you stop typing (⌘S saves now). On quit, window close and when switching files the document is saved immediately, so nothing is lost in the two-second window. Every write is atomic.
- **Snapshots.** Before the first save of each session a copy of the file is stored under `~/Library/Application Support/HyperEdit/snapshots` (**File › Open Snapshot Folder**). The newest 20 per file are kept and anything older than 90 days is removed.
- **External changes.** If another program changes the file while it is open and you have no unsaved edits, HyperEdit reloads it and keeps your caret where it was. If you do have unsaved edits, the external version is snapshotted and a warning is shown; saving then overwrites it.
- **Safety.** An empty buffer is never written over a file that had content. If saving fails when you quit, an emergency copy is written to the snapshot folder and you are asked whether to quit anyway.
- **Encodings.** Files are read as UTF-8 first, then EUC-KR (CP949), CP1252 and Latin-1, and saved in the same encoding (a UTF-8 BOM is preserved). If you type a character the original encoding cannot store, the file is saved as UTF-8 and the status bar says so. A file that cannot be decoded in any of these encodings is not opened at all rather than being damaged.
- **Line endings** (UNIX / DOS / MAC) are detected and preserved; Quick Append and the text tools use the file's own.
- **Export.** **File › Export as HTML…** saves the document as one self-contained HTML file — Markdown rendered like the preview, notes and code as a syntax-colored block — and **File › Export as PDF…** prints the same page to a paginated PDF (Letter in the US, Canada and Mexico, A4 elsewhere; 36 pt margins; no header or footer). The save panel lets you choose the theme (current, Hyper Light, Hyper Dark) and, for notes and code, line numbers. The exported page contains no scripts and no stylesheets or fonts from the network; image URLs are kept as written, so a browser (and the PDF renderer) may fetch remote images, and relative image paths work when you save the HTML next to the Markdown file. PDF export works for files up to 2 MB. Secret blocks (section 23) are exported as `••••••••`.

## 18. Settings reference

Open Settings with **⌘,** or the Advanced tab.

| Section | What it controls |
|---|---|
| Language | Interface language (System Default or one of eleven languages), **Relaunch Now**, **Open User Guide** |
| Font | Latin font family, size, ligatures, line height |
| Hangul | Hangul font family, the 2:1 width fix, Hangul scale; shows whether the font is installed |
| Theme | Follow system appearance, theme picker |
| Files | The current file, the default document and the snapshot folder, with buttons to open them |
| Quick Append | Global shortcut (Off / ⌃⌥N / ⌃⌥Space / ⌃⇧Space / ⌃⌥⌘N), timestamp heading on/off |
| Appearance | Cursor style (Bar / Block / Underline), blink, window opacity 50–100 %, blur behind window |
| Secrets | Mask secret blocks, re-mask after (10 / 30 / 60 s / Never), clear clipboard after copying a secret (Off / 10 / 30 / 60 s) |
| App Lock | Require Touch ID or password to open HyperEdit (off), lock after inactivity (Never / 1 / 5 / 15 / 30 minutes), lock when the Mac sleeps or the screen locks (on; needs the first option) |

Panel visibility, word wrap, line numbers, syntax colors, scroll markers, the split and the ribbon tab are remembered automatically.

## 19. Keyboard shortcuts

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
| ⌃⌘= | Calculate | ⌃⌘T | Align columns |
| ⌘/ | Toggle comment | ⌃⌘J | Format JSON |
| ⇧⌘I | Insert snippet | Tab | Expand snippet / next tabstop |
| ⇧⌘M | Record / stop macro | ⌥⌘M | Play macro |
| ⌥⌘← / ⌥⌘→ | Fold / unfold | ⌥⇧⌘← / ⌥⇧⌘→ | Fold all / unfold all |
| ⌘\\ | Split editor | ⌥⌘\\ | Focus other split |
| ⇧⌘N | Quick Append | ⌃⌥N | Quick Append from any app (configurable) |
| ⌘1 | Sidebar | ⌘2 | Bottom panel |
| ⌘3 | Outline | ⌘4 | Timeline |
| ⌥⌘L | Line numbers | ⌥Z | Word wrap |
| ⇧⌘P | Markdown preview | ⌃⌘H | Syntax colors |
| ⌥⌘] / ⌥⌘[ | Next / previous theme | ⌘= / ⌘- / ⌘0 | Zoom in / out / reset |
| ⌥⌘S | Reveal / mask secret blocks | ⌘, | Settings |
| ⌃⌘L | Lock HyperEdit (Touch ID) | | |
| ⌘Q | Quit (saves first) | | |

## 20. Files HyperEdit writes

HyperEdit touches only the files you open and its own data:

| Path | Contents |
|---|---|
| `~/Documents/HyperEdit/notes.md` | The default document (created on first launch if missing) |
| `~/Library/Application Support/HyperEdit/snapshots/` | Pre-save snapshots and emergency copies |
| `~/Library/Application Support/HyperEdit/bookmarks/` | One JSON file per bookmarked document |
| `~/Library/Application Support/HyperEdit/snippets.json` | Your snippets |
| `~/Library/Application Support/HyperEdit/grammars/` | User-defined grammars (`*.json`), with `example.json` and a README |
| `~/Library/Application Support/HyperEdit/macros/macros.json` | Saved macros |
| `~/Library/Preferences/io.github.hyeongcheol-an.hyperedit.plist` | Preferences, including the interface language |

Nothing is written next to your documents, and nothing leaves your Mac.

## 21. Troubleshooting

- **The language did not change.** The new language applies after a relaunch — use **Relaunch Now** in Settings or quit and reopen. If the system language is one HyperEdit does not have, it shows English; choose a language explicitly in Settings.
- **A file will not open.** Binary files open in their default app on purpose. A text file in an encoding other than UTF-8, EUC-KR, CP1252 or Latin-1 is refused rather than damaged; convert it with another tool first.
- **The global Quick Append shortcut does nothing.** Another app may own the combination, or ⌃Space / ⌃⌥Space may be taken by input-source switching in System Settings › Keyboard. Choose ⌃⌥N or ⌃⌥⌘N in Settings. The Output panel reports the registration result at launch.
- **Korean text looks too wide or too narrow in tables.** Install D2Coding, or adjust the Hangul scale in Settings; the 2:1 width fix needs a monospaced Hangul font.
- **I saved something by mistake.** Open the snapshot folder (**File › Open Snapshot Folder**): the copy taken before the first save of the session is there, plus any copies made when external changes were detected.
- **The ribbon shows only icons.** The window is too narrow for that tab; widen it or hover an icon for its label.

## 22. Known limitations

- Syntax colors follow block comments, multi-line strings and Markdown fences across lines, but, apart from Rust raw strings, only same-open-and-close string delimiters and one block-comment pair per language are supported, and user grammars are word lists without regular-expression rules. The Markdown preview is a view, not an editor.
- Macros record keyboard editing only (no mouse, selection or multi-caret steps). Calculate and Align Columns handle plain arithmetic and tab / pipe tables only.
- Snippets, macros and user grammars are edited as JSON files; there is no graphical editor for them.
- Export writes the whole document only, without selection or multi-file export, page or font options, or a PDF table of contents.
- Secret blocks are masked on screen only: the file, autosaves and snapshots are plain text, the mask bar shows how long each line is, and VoiceOver still reads the text. A secret fence must start at the left margin (indented less than four spaces, not inside a list item or quote), and a fenced block nested inside a secret block needs four backticks on the outer fence. App lock hides the window and its contents from VoiceOver; it does not encrypt anything.
- Block comments do not nest, and files with classic Mac (CR-only) line endings are colored line by line. Inside a single paragraph longer than 20,000 characters the Block and Underline carets fall back to the standard bar caret.
- Folds last for the session and are not saved per file; a mouse drag across a folded line still selects the hidden text.
- Documents that are a single line of a megabyte or more are slow to open and move around in; Minify JSON warns before producing one.
- Local files only; no cloud sync and no iOS app yet.
- Languages other than the eleven listed fall back to English.

## 23. Secret blocks and app lock

**Secret blocks.** A fenced code block whose info string starts with `secret` is masked in the editor:

````markdown
```secret bank
login: me@example.com
password: hunter2
```
````

Every line between the fences is drawn as a blank bar with `••••••••`; the fence lines stay visible so you can see where the block is and what it is for. The rule is the same in Markdown and plain text files. Move the caret into the block — click it, use ↑ / ↓, Go to Line, a find result or a bookmark — and the whole block is revealed and editable; move the caret out and it is masked again. Only the display changes: the text is still in the file, so Find, Replace, undo and saving work exactly as before.

- **Reveal Secrets (⌥⌘S)** in the Edit menu shows every block at once; after **Settings › Secrets › Re-mask after** (10 / 30 / 60 s, default 30 s, or Never) they are masked again and the Output panel logs it. The status bar shows `REVEALED` meanwhile and `•••• N` while N blocks are masked. **Edit › Mask Secret Blocks** turns masking off entirely.
- Secret lines are shown as `••••••••` in the Find Results and Find in Files lists (the match and the line number still work) and in bookmark previews, skipped by the Outline and Timeline, and redacted in the Markdown preview and in HTML / PDF exports. Quitting HyperEdit runs a pending clipboard clear immediately.
- **Clipboard auto-clear.** When a copy or cut overlaps a secret line — including multi-caret and column-mode copies — the clipboard is cleared after **Settings › Secrets › Clear clipboard after copying a secret** (Off / 10 / 30 / 60 s, default 30 s), unless you copied something else in the meantime. **Edit › Clear Clipboard** clears it immediately, and turning masking off also turns the auto-clear off.
- Secret blocks fold like any fenced block (⌥⌘←).

> Masking is not encryption. The file, autosaves and snapshots are plain text, and anyone who has the file can read the secrets. The feature keeps them off your screen, screenshots, find results, preview and exports while you work.

**App lock (Touch ID).** **HyperEdit › Lock HyperEdit (⌃⌘L)** (the application menu, below Settings…) covers the whole window — ribbon, sidebar, editor, panels and status bar — with an opaque lock screen in the current theme, closes an open Settings window and hides the Quick Append panel. Nothing about the document, not even the file name, is shown while locked. Click **Unlock** (or press Return or Space) to authenticate with **Touch ID**; if Touch ID fails or the Mac has none, macOS falls back to your login password. Locking also closes any open sheet or alert, masks revealed secrets again and runs a pending clipboard clear at once. Cancelling keeps HyperEdit locked and the button retries.

- **Settings › App Lock.** *Require Touch ID or password to open HyperEdit* (off by default) starts the app locked: the document is loaded and autosave keeps working, but nothing is visible until you authenticate. *Lock after inactivity* (Never / 1 / 5 / 15 / 30 minutes, default Never) locks after that long without a key press or click in HyperEdit, independently of the launch option. *Lock when the Mac sleeps or the screen locks* (on by default) applies while the launch option is on and also covers the displays going to sleep. A caption tells you whether Touch ID is available on this Mac.
- While locked, keyboard input is swallowed and the menu bar cannot be opened; only ⌘Q, ⌘H / ⌥⌘H, ⌘M, ⌘W, ⌃⌘F and the Dock menu still work. The Quick Append global shortcut shows the unlock prompt instead of the panel and opens the panel once you have authenticated.
- This is a privacy lock for the screen, not encryption: the files on disk are unchanged and readable by any other app. The *Require…* option cannot be turned on while the Mac has neither Touch ID nor a login password, so you cannot lock yourself out.

## 24. Getting help

- Bug reports and ideas: [GitHub Issues](https://github.com/Hyeongcheol-An/HyperEdit/issues) and [Discussions](https://github.com/Hyeongcheol-An/HyperEdit/discussions).
- Security problems: see [SECURITY.md](../../SECURITY.md) for private reporting.
- Translations: the interface strings live in `l10n/ui.<language>.json` in the repository and this guide in `docs/guide/`; corrections are welcome as pull requests — see [CONTRIBUTING.md](../../CONTRIBUTING.md).

HyperEdit is free software under the MIT License. Its layout is inspired by the classic UltraEdit ribbon; UltraEdit is a trademark of IDM Computer Solutions, Inc., and HyperEdit is not affiliated with IDM.
