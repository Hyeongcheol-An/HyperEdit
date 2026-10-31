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

**Unit tests** live in the `HyperCore` Swift package and cover the line index, search engine and replacement templates, timestamp format, theme loading, Hangul font fixer, text tools, column-block math, outline/timeline scanner, default-document resolution and file search:

```sh
swift test --package-path Packages/HyperCore
```

**Self-test** exercises the whole app — search, bookmarks, ⌘D multi-caret, column mode, Insert Number, Replace All with a single undo, Find in Files, outline/timeline, timestamp, saving and a typing-latency benchmark. It creates its own sample files in a temporary folder and never touches your documents:

```sh
scripts/build-mac.sh --run --selftest --selftest-out /tmp/hyperedit-selftest.txt --quit
cat /tmp/hyperedit-selftest.txt     # every line is PASS/FAIL; ends with ALL PASS
```

`--selftest-open` is a file-switching benchmark that edits the files it is pointed at; only run it on copies, together with `--file`.

**Performance** can be inspected with `--debug-perf [--debug-perf-log <path>]`, which logs section timings and any main-thread stall over 120 ms. `--snapshot out.png [--snapshot-delay 3] [--quit]` captures the window via ScreenCaptureKit (Screen Recording permission required) for screenshots and visual checks.

Before opening a PR, please also run the same checks CI runs:

```sh
python3 themes/build_zed_theme.py && python3 themes/build_preview.py && python3 themes/validate.py
git diff --exit-code -- themes/dist docs/theme-preview.html Packages/HyperCore/Sources/HyperCore/Resources/palettes.json
bash scripts/check-sensitive.sh
```

## Commit convention

Commits follow [Conventional Commits](https://www.conventionalcommits.org) because [semantic-release](https://semantic-release.gitbook.io) derives versions and the changelog from them. Subjects may be in Korean or English.

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

English is the source language; Korean ships as a translation in two String Catalogs:

- `Apps/mac/Localizable.xcstrings` — everything in the app target
- `Packages/HyperCore/Sources/HyperCore/Resources/Localizable.xcstrings` — engine messages (`String(localized:bundle: .module)`)

Rules of thumb:

1. Write UI strings as **English literals**. SwiftUI views (`Text`, `Button`, `Label`, `Toggle`, `Menu`, `.help`, `TextField` prompts, alert titles) take `LocalizedStringKey`, so the literal becomes the catalog key. Ribbon components (`RibbonBigButton`, `RibbonSmallButton`, …) also take `LocalizedStringKey`. Strings built outside SwiftUI use `String(localized: "…")`.
2. Interpolations become format placeholders in the key: `Text("\(count) hits")` → key `%lld hits`; a `String` argument → `%@`; keep explicit specifiers (`%.2f`). Numbers-only text uses `Text(verbatim:)` so it is not looked up.
3. Add the Korean value for every new key. Easiest: put `{ "English key": "한국어" }` in a JSON file and run `python3 scripts/l10n-add.py that.json` — it finds which target uses each key and inserts the `ko` translation into the right catalog. You can also edit the catalogs by hand (they are plain JSON).
4. `python3 scripts/check-l10n.py` must pass (it runs in CI): every key used in code exists in a catalog, every entry has a `ko` value, no unused entries.
5. To test a language without changing your system: `scripts/build-mac.sh --run -AppleLanguages '("en")'` or `'("ko")'` (the `-AppleLanguages` argument must come first).

## Code style

- **Swift 5 language mode** on a Swift 6 toolchain (`swiftLanguageMode(.v5)` in `Package.swift`, `SWIFT_VERSION 5.0` with `SWIFT_STRICT_CONCURRENCY minimal` in `project.yml`). Keep it compiling without warnings under those settings.
- **`@MainActor` model.** `AppModel`, `MemoDocument`, `BookmarkStore` and `ThemeStore` are main-actor classes. Heavy work (search, line indexing, outline scans) runs in `Task.detached` on an immutable snapshot of the text and hops back to the main actor to publish results. Disk writes go through one serial queue, so asynchronous autosaves and the synchronous save on quit / file switch never reorder; keep new write paths on that queue.
- **AppKit stays in `Apps/mac/Editor/`.** `HyperTextView` (TextKit 2 `NSTextView` subclass), `GutterView` and the `NSViewRepresentable` in `EditorView.swift` are the only places that touch AppKit text machinery. Everything else is SwiftUI or platform-neutral `HyperCore`.
- **`HyperCore` must stay platform-neutral.** It declares macOS 15 and iOS 18 targets; guard AppKit/UIKit with `#if canImport(...)` as the existing files do, and keep new logic unit-testable without a window.
- **Performance first.** The editor is judged on a 1 MB+ file. Avoid per-keystroke work on the whole document, avoid `String` grapheme scans over megabytes (use `NSString`/UTF-8 byte scans as the code does), and don't add observers that redraw the ribbon on every caret move. Run the self-test and watch the `perf typing` line.
- Comments and UI strings are currently Korean; English is equally welcome in new code. Don't mix a rename of existing strings into an unrelated change.
- No personal data in the repository: no home-directory paths (use `~` or `$HOME`), no email addresses, no credentials. `scripts/check-sensitive.sh` runs in CI and will reject them.

## Pull request checklist

- [ ] The change is scoped to one thing and described in the PR body (what, why, how to try it).
- [ ] `swift test --package-path Packages/HyperCore` passes.
- [ ] The app builds in Release and the self-test (`--selftest`) still ends with `ALL PASS`.
- [ ] If you touched `themes/palettes.json`: generated files regenerated, `python3 themes/validate.py` passes, outputs committed.
- [ ] `bash scripts/check-sensitive.sh` passes; no personal paths, emails or secrets.
- [ ] Commit messages follow Conventional Commits.
- [ ] If you changed `package.json`, the updated `package-lock.json` is committed too (CI installs with `npm ci`).
- [ ] User-facing changes are noted in `README.md` and `README.ko.md` (both — the Korean README is a full translation, not a summary) and, when relevant, in `docs/features.md`.
- [ ] Screenshots or a short recording for UI changes.

CI runs theme validation, the sensitive-info check, commitlint, `swift test` and an unsigned `xcodebuild` on `macos-latest`. Every GitHub Action is pinned to a commit SHA, and Node tooling is installed with `npm ci --ignore-scripts` from the committed `package-lock.json`. Releases are cut automatically from `main`, so there is nothing to do for versioning — just use the right commit type. The release workflow refuses to run without the Developer ID and notarization secrets (a fork can set the repository variable `ALLOW_UNSIGNED_RELEASE=true` to allow unsigned builds), and it pushes the Homebrew cask in a separate final step — the only step that sees `HOMEBREW_TAP_DEPLOY_KEY`. Maintainers register the five signing secrets with `scripts/setup-signing.sh ci-secrets <cert.p12> <AuthKey.p8> <KEY_ID> <ISSUER_ID> [owner/repo]`, which prompts for the `.p12` password and calls `gh secret set`, so no secret value touches the screen or shell history.

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE) that covers the project.

---

## 한국어 요약

- **논의 장소:** 버그·구체적 기능 요청은 GitHub Issues(템플릿 사용), 아이디어·질문은 GitHub Discussions, 보안 문제는 공개 이슈 대신 [SECURITY.md](SECURITY.md)의 비공개 신고 절차. 한국어·영어 모두 환영합니다.
- **개발 환경:** macOS 15 + Xcode 16 이상, `brew install xcodegen` → `scripts/bootstrap.sh`(프로젝트 생성) → `scripts/build-mac.sh --run`. 서명 기본값은 "Sign to Run Locally"라 Apple 팀이 없어도 됩니다. 본인 팀으로 서명하려면 `Config/Local.xcconfig.example`을 `Config/Local.xcconfig`로 복사.
- **테스트:** 단위 테스트 `swift test --package-path Packages/HyperCore`. 앱 전체 셀프테스트는 `scripts/build-mac.sh --run --selftest --selftest-out /tmp/r.txt --quit`(임시 폴더에서만 동작, 사용자 문서 무관). `--selftest-open`은 가리킨 파일을 수정하는 벤치라 사본에서만 실행.
- **커밋 규약:** Conventional Commits. `feat` → 마이너, `fix`/`perf` → 패치, `docs`/`chore`/`refactor` → 릴리스 없음, `(themes)` 스코프는 패치 릴리스. 제목은 한국어도 됩니다. `scripts/install-hooks.sh`로 로컬 훅 설치, PR에서는 commitlint가 검사.
- **테마 수정:** `themes/palettes.json`만 고치고 `python3 themes/build_zed_theme.py && python3 themes/build_preview.py`로 재생성한 뒤 `python3 themes/validate.py`. 생성물이 팔레트와 어긋나면 CI가 실패합니다. 새 테마 이름은 `Hyper ` 접두사.
- **코드 스타일:** Swift 5 언어 모드, `@MainActor` 모델과 백그라운드 `Task.detached`, AppKit 편집기는 `Apps/mac/Editor/`에만, `HyperCore`는 플랫폼 중립 유지, 큰 파일 성능 우선. 저장소에 개인 경로·이메일·비밀 금지(`scripts/check-sensitive.sh`).
- **PR 체크리스트:** 테스트 통과, 셀프테스트 `ALL PASS`, 테마 생성물 커밋, `bash scripts/check-sensitive.sh` 통과, 커밋 규약 준수, `package.json`을 바꿨으면 `package-lock.json`도 커밋, `README.md`와 `README.ko.md` 둘 다 갱신, UI 변경은 스크린샷 첨부.
- **CI·릴리스:** 모든 액션은 커밋 SHA로 고정, Node 도구는 `npm ci --ignore-scripts`로 설치. 릴리스 워크플로는 서명·공증 시크릿이 없으면 실패하며(포크는 저장소 변수 `ALLOW_UNSIGNED_RELEASE=true`로 허용), Homebrew cask는 마지막 별도 단계에서만 `HOMEBREW_TAP_DEPLOY_KEY`로 푸시합니다. 시크릿 등록은 `scripts/setup-signing.sh ci-secrets <cert.p12> <AuthKey.p8> <KEY_ID> <ISSUER_ID> [owner/repo]`(.p12 암호는 프롬프트, `gh secret set`으로 바로 등록).
- **로컬라이즈:** UI 문자열은 영어 리터럴로 쓰고(카탈로그 키), 한국어는 `Apps/mac/Localizable.xcstrings`·HyperCore 카탈로그에 넣습니다. `{ "English key": "한국어" }` JSON 을 만들어 `python3 scripts/l10n-add.py 파일.json` 으로 추가하고, `python3 scripts/check-l10n.py` 로 누락을 확인하세요. 언어 테스트는 `-AppleLanguages '("en")'` 실행 인자.
