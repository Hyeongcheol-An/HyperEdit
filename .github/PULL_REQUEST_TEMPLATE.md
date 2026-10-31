<!-- Thanks for the PR. Korean or English is fine. · 한국어·영어 모두 괜찮습니다. -->

## What · 무엇을

<!-- One or two sentences. Link the issue or discussion: "Closes #123". -->

## Why · 왜

<!-- The problem this solves for someone editing one big notes file. -->

## How to try it · 확인 방법

<!-- Steps a reviewer can follow: which file to open, which shortcut / ribbon button, what to expect.
     Screenshots or a short recording for anything visible (light and dark theme if colors changed). -->

## Checklist · 체크리스트

- [ ] Commit messages follow Conventional Commits (`feat:`, `fix:`, `perf:`, `docs:`, `chore:` …; the subject may be Korean). · 커밋 메시지가 Conventional Commits 형식입니다.
- [ ] `swift test --package-path Packages/HyperCore` passes. · 단위 테스트 통과.
- [ ] Release build runs and the self-test ends with `ALL PASS`: `scripts/build-mac.sh --run --selftest --selftest-out /tmp/r.txt --quit`. · 셀프테스트 통과.
- [ ] `bash scripts/check-sensitive.sh` passes — no home-directory paths, emails, keys or personal file contents. · 개인 정보·비밀 없음.
- [ ] If `themes/palettes.json` changed: ran `python3 themes/build_zed_theme.py && python3 themes/build_preview.py && python3 themes/validate.py` and committed the generated files. · 테마 생성물 재생성·커밋.
- [ ] If user-facing behaviour changed: updated **both** `README.md` and `README.ko.md` (and `docs/features.md` if a feature's status changed). · 영문·한국어 README 모두 갱신.
- [ ] No new per-keystroke work on the whole document; checked the `perf typing` line in the self-test output for editor changes. · 편집기 변경 시 타이핑 지연 확인.
- [ ] AppKit code stays in `Apps/mac/Editor/`; `HyperCore` stays platform-neutral. · 레이어 경계 유지.

## Notes for the reviewer · 리뷰어에게

<!-- Trade-offs, things you were unsure about, follow-ups you left out on purpose. -->
