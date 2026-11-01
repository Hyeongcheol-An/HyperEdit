# Contributing to HyperEdit

Thanks for taking the time to help. HyperEdit is a small project with one maintainer (Hyeongcheol An, GitHub `@Hyeongcheol-An`), so clear issues and focused pull requests go a long way. This guide covers the development setup, how tests and the self-test run, the commit convention, how themes are edited, and what a pull request should contain. A short Korean summary is at the end.

## Where to discuss

- **Bugs and concrete feature requests:** open a [GitHub Issue](https://github.com/Hyeongcheol-An/HyperEdit/issues/new/choose) using the templates.
- **Ideas, questions, "would this fit?":** start a thread in [GitHub Discussions](https://github.com/Hyeongcheol-An/HyperEdit/discussions) before writing code for anything larger than a small fix.
- **Security problems:** do not open a public issue; follow [SECURITY.md](SECURITY.md).

English and Korean are both fine everywhere — issues, discussions, commit messages and code comments.

## Development setup

Requirements: macOS 15 or later, Xcode 16 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen), and Python 3 for the theme scripts. Node.js 22 is only needed if you want to run commitlint or semantic-release locally (`npm ci --ignore-scripts` installs them from the committed `package-lock.json`).

```sh
git clone https://github.com/Hyeongcheol-An/HyperEdit.git
cd HyperEdit
brew install xcodegen
scripts/bootstrap.sh            # generates HyperEdit.xcodeproj from project.yml (git-ignored)
scripts/build-mac.sh --run      # Release build, then launch from DerivedData
scripts/install-hooks.sh        # commit-message hook (Conventional Commits), no Node needed
```

`scripts/bootstrap.sh --open` also opens the generated project in Xcode. Regenerate the project whenever `project.yml` changes; never edit `HyperEdit.xcodeproj` by hand, since it is not committed.

Signing defaults to Xcode's "Sign to Run Locally", so you can build and run without an Apple developer team. To sign with your own team, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` (git-ignored) and fill in `DEVELOPMENT_TEAM`.

For debugging, `scripts/build-mac.sh Debug --run --file path/to/some.txt` builds a Debug configuration and opens a specific file. Debug builds are noticeably slower on large files; use Release when measuring performance.

## Running tests

**Unit tests** (196 across 13 files) live in the `HyperCore` Swift package and cover the line index (including its incremental update), search engine and replacement templates, timestamp format, theme loading, Hangul font fixer, text tools (calculator and column alignment included), column-block math, outline/timeline scanner, default-document resolution, file search, the syntax-highlighting grammars, Markdown → HTML, comment toggle, JSON formatter, snippet templates and store, macro model and store, Quick Append composer and the fold scanner:

```sh
swift test --package-path Packages/HyperCore
```

**Self-test** (393 checks, ending in `ALL PASS`) exercises the whole app — search, bookmarks and bookmark line tracking, ⌘D multi-caret, column mode, Insert Number, Replace All with a single undo, Find in Files, outline/timeline, timestamp, saving, the Markdown preview HTML, calculator and column alignment, comment toggle, JSON format/minify with error reporting, snippet expansion, the split editor (shared storage and undo in both directions), Quick Append, macros (record, replay, IME, Find steps, save/delete, a ×100 replay on a 1.3 MB file), folding, and typing-latency benchmarks (plain, while recording a macro, with folds). It creates its own sample files in a temporary folder, uses throwaway preferences and never touches your documents:

```sh
scripts/build-mac.sh --run --selftest --selftest-out /tmp/hyperedit-selftest.txt --quit
cat /tmp/hyperedit-selftest.txt     # every line is PASS/FAIL; ends with ALL PASS
```

The self-test edits programmatically, and AppKit closes an automatic undo group only when it finishes processing an `NSEvent` — a `Task.sleep` or a run-loop turn is not enough. Every `wait()` in the self-test therefore calls `SelfTest.pumpEvent()`, which posts an empty `applicationDefined` event, so consecutive edits land in separate undo groups exactly as they would for a user. Keep that in mind when adding checks that depend on ⌘Z granularity.

`--selftest-open` is a file-switching benchmark that edits the files it is pointed at; only run it on copies, together with `--file`. `--selftest-split-big <file>` adds a split-editor typing check that types into and restores the given file — again, a copy.

**Performance** is measured by `scripts/bench.sh` (Release build → cold-launch timing → the in-app `--bench` harness → bundle size). It writes `build/bench/<sha>.json` and `.md`, and `--compare docs/bench/baseline-0.6.0.json` adds Δ% against the baseline and lists regressions over 15 %; budgets, phases and the current baseline are in [docs/performance.md](docs/performance.md). Run it before and after any change to the typing, layout or document path and paste the table into the PR — benchmarks are deliberately not part of CI. `--debug-perf [--debug-perf-log <path>]` logs section timings and any main-thread stall over 120 ms. `--snapshot out.png [--snapshot-delay 3] [--quit]` captures the window via ScreenCaptureKit (Screen Recording permission required) for screenshots and visual checks.

**Manual testing** should use `--ephemeral --file <copy>`: the app then keeps its preferences, remembered file, snippets and macros in throwaway locations, so your own settings and `~/Documents/HyperEdit/notes.md` are left alone (the self-test, snapshot and bench modes do this automatically).

Before opening a PR, please also run the same checks CI runs:

```sh
python3 themes/build_zed_theme.py && python3 themes/build_preview.py && python3 themes/validate.py
git diff --exit-code -- themes/dist docs/theme-preview.html Packages/HyperCore/Sources/HyperCore/Resources/palettes.json
bash scripts/check-sensitive.sh
```

## Commit convention

Commits follow [Conventional Commits](https://www.conventionalcommits.org) because [semantic-release](https://semantic-release.gitbook.io) derives versions and the changelog from them. **Write the subject in English** — it is copied verbatim into the GitHub release notes and `CHANGELOG.md`; the body may be Korean or English. Hand-written notes for a release go in `docs/release-notes/v<version>.md` (English) and are appended to the release body automatically.

| Type | Effect on release | Example |
|---|---|---|
| `feat` | minor version | `feat(editor): add column-mode line-wise paste` |
| `fix`, `perf` | patch version | `fix(search): whole-word match at end of line` |
| `docs`, `chore`, `refactor`, `test`, `ci`, `style`, `build` | no release | `docs: clarify snapshot location` |
| `feat!:` or `BREAKING CHANGE:` footer | major version | — |

Commits scoped `(themes)` also trigger a patch release so that palette fixes ship to Zed users. Allowed scopes are lowercase (`editor`, `search`, `themes`, `release`, `ribbon`, …); the header is limited to 100 characters.

Two checks enforce this: `scripts/install-hooks.sh` installs a local `commit-msg` hook that validates the format, and the `commitlint` job in CI runs the repository's own `@commitlint/cli` devDependency (installed with `npm ci --ignore-scripts` from the committed lockfile) over every commit in a pull request, using `commitlint.config.js`. Squash-merge is fine as long as the final subject follows the convention.

## Editing themes

All 22 themes come from **one file**, `themes/palettes.json`. Each entry gives a handful of required colors (background, foreground, accent, selection, ANSI set, syntax set); `themes/build_zed_theme.py` derives the full Zed theme (every style and syntax key) and the Swift app reads the same palette through `Packages/HyperCore/Sources/HyperCore/Resources/palettes.json`.

- Edit `themes/palettes.json` only. Do not hand-edit `themes/dist/hyperedit-themes.json`, `docs/theme-preview.html` or the copy under `Packages/HyperCore/.../Resources/`.
- Regenerate after every change:

  ```sh
  python3 themes/build_zed_theme.py && python3 themes/build_preview.py
  python3 themes/validate.py
  ```

- Commit the regenerated files together with the palette change. The `themes` CI job rebuilds them and **fails if the committed output differs** from what the palette produces.
- New themes are prefixed `Hyper ` and need a unique `id` and `name`, plus `appearance` set to `light` or `dark`. Keep the two defaults (`hyper-light`, `hyper-dark`) in place; the app falls back to them when it follows the system appearance.
- `python3 themes/build_zed_theme.py --install` copies the result into `~/.config/zed/themes/` so you can check it in Zed immediately.

## Localization

English is the source language. Ten translations ship in two String Catalogs — Korean (`ko`), Simplified Chinese (`zh-Hans`), Japanese (`ja`), Vietnamese (`vi`), Hindi (`hi`), German (`de`), French (`fr`), Spanish (`es`), Portuguese (`pt`, Brazilian) and Arabic (`ar`, right-to-left: measured on macOS 15/26 the window structure — ribbon groups, sidebar, editor, panels — stays left-to-right while labels and settings rows follow Arabic reading order; nothing in the code forces a direction, so check `-AppleLanguages '("ar")'` screenshots when touching layout):

- `Apps/mac/Localizable.xcstrings` — everything in the app target
- `Packages/HyperCore/Sources/HyperCore/Resources/Localizable.xcstrings` — engine messages (`String(localized:bundle: .module)`)

The editable form of each language is the flat dictionary `l10n/ui.<code>.json` (`{ "English key": "translation" }`, `""` = not translated yet). `l10n/context.json` says where every key is used (menu item, tooltip, ribbon label, settings…), its placeholders and the ribbon length limit, so translators do not have to read Swift.

Rules of thumb:

1. Write UI strings as **English literals**. SwiftUI views (`Text`, `Button`, `Label`, `Toggle`, `Menu`, `.help`, `TextField` prompts, alert titles) take `LocalizedStringKey`, so the literal becomes the catalog key. Ribbon components (`RibbonBigButton`, `RibbonSmallButton`, …) also take `LocalizedStringKey`. Strings built outside SwiftUI use `String(localized: "…")`.
2. Interpolations become format placeholders in the key: `Text("\(count) hits")` → key `%lld hits`; a `String` argument → `%@`; keep explicit specifiers (`%.2f`). Numbers-only text uses `Text(verbatim:)` so it is not looked up.
3. After adding strings run `python3 scripts/l10n-export.py`. It inserts the new English keys into the catalogs and rewrites every `l10n/ui.<code>.json` (new keys appear with `""`) and `l10n/context.json`. Fill in the translations you can — at least Korean, and ideally every language; a machine or AI draft that respects the rules below is better than a blank — then run `python3 scripts/l10n-add.py --check l10n/ui.<code>.json` and, when it is clean, `python3 scripts/l10n-add.py l10n/ui.<code>.json` to merge into the catalogs. Commit the JSON files together with the catalogs.
4. Translation rules: keep placeholders identical in kind and count (use positional `%1$@ %2$lld` for *all* of them if the order must change); keep product and format names (HyperEdit, Markdown, JSON, UTF-8), file names, paths, shortcut glyphs, `…` endings and `·` separators as in the English key; follow the platform's macOS terminology (Undo/Redo/Paste/Settings/Sidebar as Apple writes them in that language); menu titles are noun phrases, tooltips and log lines are sentences. Reuse the vocabulary already in the file — the feature names (Quick Append, Outline, Timeline, Column Mode, Multi-Caret, Fold, Split Editor, Snippet, Macro, Syntax Colors, Scrollbar Markers, Snapshot…) must be translated the same way everywhere, including the user guide.
5. **Ribbon labels are width-limited** (fixed 60 pt big buttons with two lines, 128 pt small buttons with one line). `check-l10n.py` and `l10n-add.py --check` print `LONG` warnings from an estimated text width; shorten the label (the tooltip carries the full wording) rather than accepting a truncated button, and confirm with a screenshot: `scripts/build-mac.sh --run -AppleLanguages '("de")' --ephemeral --ribbon edit` (the `-AppleLanguages` argument must come first).
6. `python3 scripts/check-l10n.py` must pass (it runs in CI): every key used in code exists in a catalog, placeholders match in every translation, the language list in `Apps/mac/AppLanguage.swift` matches the script's `LANGUAGES`, and every language has a user guide (`docs/guide/USER_GUIDE.<code>.md`) and a welcome text (`Packages/HyperCore/Sources/HyperCore/Resources/Welcome/welcome.<code>.md`). Missing translations are reported as warnings (`--strict` turns them into errors before a release).
7. **Adding a language:** add the case to `AppLanguage` (raw value = the `.lproj` code, plus `nativeName`), add the code to `LANGUAGES` in `scripts/check-l10n.py`, run `l10n-export.py <code>` and translate `l10n/ui.<code>.json`, translate `docs/guide/USER_GUIDE.md` to `USER_GUIDE.<code>.md` (keep the heading structure and rebuild the table-of-contents anchors) and `welcome.en.md` to `welcome.<code>.md`, add the link to the language bar at the top of both READMEs and every guide, then merge and run the checker and the self-test (`--selftest` verifies the language appears in both bundles).
8. To test a language without changing your system: `scripts/build-mac.sh --run -AppleLanguages '("ja")' --ephemeral`, or choose it in Settings › Language and click Relaunch Now (that writes `AppleLanguages` into the app's own preferences domain, the same key System Settings uses for per-app languages).

## Code style

- **Swift 5 language mode** on a Swift 6 toolchain (`swiftLanguageMode(.v5)` in `Package.swift`, `SWIFT_VERSION 5.0` with `SWIFT_STRICT_CONCURRENCY minimal` in `project.yml`). Keep it compiling without warnings under those settings.
- **`@MainActor` model.** `AppModel`, `MemoDocument`, `BookmarkStore` and `ThemeStore` are main-actor classes. Heavy work (search, line indexing, outline scans) runs in `Task.detached` on an immutable snapshot of the text and hops back to the main actor to publish results. Disk writes go through one serial queue, so asynchronous autosaves and the synchronous save on quit / file switch never reorder; keep new write paths on that queue.
- **AppKit text machinery stays in `Apps/mac/Editor/`.** `HyperTextView` (TextKit 2 `NSTextView` subclass), `GutterView`, `EditorSession` (the shared `NSTextContentStorage` and undo manager behind the split editor), `FoldController`, `ScrollMarkerView` and the `NSViewRepresentable` in `EditorView.swift` are the only places that touch it; the non-activating Quick Append `NSPanel` and the Carbon hot key live in `Apps/mac/QuickAppend/`. Everything else is SwiftUI or platform-neutral `HyperCore`.
- **`HyperCore` must stay platform-neutral.** It declares macOS 15 and iOS 18 targets; guard AppKit/UIKit with `#if canImport(...)` as the existing files do, and keep new logic unit-testable without a window.
- **Performance first.** The editor is judged on a 1 MB+ file. Avoid per-keystroke work on the whole document, avoid `String` grapheme scans over megabytes (use `NSString`/UTF-8 byte scans as the code does), and don't add observers that redraw the ribbon on every caret move. Run the self-test and watch the `perf typing` line.
- Code comments are mostly Korean; English is equally welcome in new code. UI strings are English literals (see Localization). Don't mix a rename of existing strings or comments into an unrelated change.
- No personal data in the repository: no home-directory paths (use `~` or `$HOME`), no email addresses, no credentials. `scripts/check-sensitive.sh` runs in CI and will reject them.

## Pull request checklist

- [ ] The change is scoped to one thing and described in the PR body (what, why, how to try it).
- [ ] `swift test --package-path Packages/HyperCore` passes.
- [ ] The app builds in Release and the self-test (`--selftest`) still ends with `ALL PASS`.
- [ ] If you touched `themes/palettes.json`: generated files regenerated, `python3 themes/validate.py` passes, outputs committed.
- [ ] `bash scripts/check-sensitive.sh` passes; no personal paths, emails or secrets.
- [ ] Commit messages follow Conventional Commits.
- [ ] If you changed `package.json`, the updated `package-lock.json` is committed too (CI installs with `npm ci`).
- [ ] New UI strings are translated (`python3 scripts/l10n-export.py`, fill `l10n/ui.<code>.json`, `python3 scripts/l10n-add.py`) — at least Korean, ideally all ten — and `python3 scripts/check-l10n.py` passes with no `LONG` warnings for ribbon labels.
- [ ] If you touched the typing, layout or document path: `scripts/bench.sh --compare docs/bench/baseline-0.6.0.json` shows no regression (paste the table).
- [ ] User-facing changes are noted in `README.md` and `README.ko.md` (both — the Korean README is a full translation, not a summary) and, when relevant, in `docs/features.md`.
- [ ] Screenshots or a short recording for UI changes.

CI runs theme validation, the sensitive-info check, commitlint, `swift test` and an unsigned `xcodebuild` on `macos-latest`. Every GitHub Action is pinned to a commit SHA, and Node tooling is installed with `npm ci --ignore-scripts` from the committed `package-lock.json`. Releases are cut automatically from `main`, so there is nothing to do for versioning — just use the right commit type. The release workflow refuses to run without the Developer ID and notarization secrets (a fork can set the repository variable `ALLOW_UNSIGNED_RELEASE=true` to allow unsigned builds), and it pushes the Homebrew cask in a separate final step — the only step that sees `HOMEBREW_TAP_DEPLOY_KEY`. Maintainers register the five signing secrets with `scripts/setup-signing.sh ci-secrets <cert.p12> <AuthKey.p8> <KEY_ID> <ISSUER_ID> [owner/repo]`, which prompts for the `.p12` password and calls `gh secret set`, so no secret value touches the screen or shell history.

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE) that covers the project.

---

## 한국어 요약

- **논의 장소:** 버그·구체적 기능 요청은 GitHub Issues(템플릿 사용), 아이디어·질문은 GitHub Discussions, 보안 문제는 공개 이슈 대신 [SECURITY.md](SECURITY.md)의 비공개 신고 절차. 한국어·영어 모두 환영합니다.
- **개발 환경:** macOS 15 + Xcode 16 이상, `brew install xcodegen` → `scripts/bootstrap.sh`(프로젝트 생성) → `scripts/build-mac.sh --run`. 서명 기본값은 "Sign to Run Locally"라 Apple 팀이 없어도 됩니다. 본인 팀으로 서명하려면 `Config/Local.xcconfig.example`을 `Config/Local.xcconfig`로 복사.
- **테스트:** 단위 테스트 196개 `swift test --package-path Packages/HyperCore`. 앱 전체 셀프테스트(393개 검사)는 `scripts/build-mac.sh --run --selftest --selftest-out /tmp/r.txt --quit`(임시 폴더에서만 동작, 사용자 문서 무관). 셀프테스트의 `wait()` 는 `SelfTest.pumpEvent()` 로 빈 NSEvent 를 하나 흘립니다 — AppKit 은 이벤트 처리가 끝나야 undo 그룹을 닫기 때문. 성능은 `scripts/bench.sh --compare docs/bench/baseline-0.6.0.json`([performance.md](docs/performance.md)), 수동 테스트는 `--ephemeral --file <사본>` 으로. `--selftest-open`은 가리킨 파일을 수정하는 벤치라 사본에서만 실행.
- **커밋 규약:** Conventional Commits. `feat` → 마이너, `fix`/`perf` → 패치, `docs`/`chore`/`refactor` → 릴리스 없음, `(themes)` 스코프는 패치 릴리스. 제목은 한국어도 됩니다. `scripts/install-hooks.sh`로 로컬 훅 설치, PR에서는 commitlint가 검사.
- **테마 수정:** `themes/palettes.json`만 고치고 `python3 themes/build_zed_theme.py && python3 themes/build_preview.py`로 재생성한 뒤 `python3 themes/validate.py`. 생성물이 팔레트와 어긋나면 CI가 실패합니다. 새 테마 이름은 `Hyper ` 접두사.
- **코드 스타일:** Swift 5 언어 모드, `@MainActor` 모델과 백그라운드 `Task.detached`, AppKit 편집기는 `Apps/mac/Editor/`에만, `HyperCore`는 플랫폼 중립 유지, 큰 파일 성능 우선. 저장소에 개인 경로·이메일·비밀 금지(`scripts/check-sensitive.sh`).
- **PR 체크리스트:** 테스트 통과, 셀프테스트 `ALL PASS`, 테마 생성물 커밋, `bash scripts/check-sensitive.sh` 통과, 커밋 규약 준수, `package.json`을 바꿨으면 `package-lock.json`도 커밋, 새 UI 문자열은 번역(`l10n/ui.<code>.json`, 최소 한국어)과 `python3 scripts/check-l10n.py` 통과, 입력·레이아웃·문서 경로를 건드렸으면 벤치 비교표 첨부, `README.md`와 `README.ko.md` 둘 다 갱신, UI 변경은 스크린샷 첨부.
- **CI·릴리스:** 모든 액션은 커밋 SHA로 고정, Node 도구는 `npm ci --ignore-scripts`로 설치. 릴리스 워크플로는 서명·공증 시크릿이 없으면 실패하며(포크는 저장소 변수 `ALLOW_UNSIGNED_RELEASE=true`로 허용), Homebrew cask는 마지막 별도 단계에서만 `HOMEBREW_TAP_DEPLOY_KEY`로 푸시합니다. 시크릿 등록은 `scripts/setup-signing.sh ci-secrets <cert.p12> <AuthKey.p8> <KEY_ID> <ISSUER_ID> [owner/repo]`(.p12 암호는 프롬프트, `gh secret set`으로 바로 등록).
- **로컬라이즈:** UI 문자열은 영어 리터럴로 쓰고(카탈로그 키), 번역은 10개 언어(ko·zh-Hans·ja·vi·hi·de·fr·es·pt·ar)를 `l10n/ui.<code>.json` 에 둡니다. 새 문자열을 넣은 뒤 `python3 scripts/l10n-export.py`(카탈로그에 영어 키 추가 + 언어 파일 갱신, 빈 값이 번역할 곳) → 파일을 채우고 `python3 scripts/l10n-add.py --check l10n/ui.<code>.json` → 이상 없으면 `--check` 없이 실행해 `Localizable.xcstrings` 두 개에 병합하고 JSON 과 카탈로그를 함께 커밋합니다. 자리표시자(%@ %lld)는 종류·개수를 지키고, 기존 용어(북마크·열 모드·멀티 커서·캐럿·찾기 결과·출력·접기/펼치기·편집기 분할·빠른 추가·스니펫·매크로·구문 색·미리보기·스냅샷)를 그대로 쓰며, 메뉴 제목은 명사형, 대화상자를 여는 항목은 "…" 로 끝냅니다. 리본 라벨은 폭이 고정이라 `LONG` 경고가 나오면 줄입니다. 언어 추가 절차와 테스트 방법은 위 영어 Localization 절 7·8 항. 언어 테스트는 `-AppleLanguages '("ja")'` 실행 인자(첫 인자) 또는 설정 › 언어 › 지금 재실행.
