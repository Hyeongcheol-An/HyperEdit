# Draft: Secret blocks (masking + clipboard auto-clear) — for README / USER_GUIDE / features.md

Branch `feat/v08-secrets`. The integrator copies the sections below into the eleven language documents; nothing here is final wording.

## 1. English (README "Features › Editor" or a new "Secrets" bullet · USER_GUIDE section)

### Secret blocks

- **Mask secret blocks.** A fenced code block whose info string starts with `secret` (```` ```secret ````, ```` ```secret bank ````, ```` ~~~secret ````) is a *secret block*: every line between the fences is drawn as a rounded blank bar with `••••••••` instead of its text. The fence lines themselves stay visible, so you can see where a block is and what it is for. The rule is the same in Markdown and plain-text files (`.txt`, no extension). Nested fences follow CommonMark: a ```` ```python ```` block inside a ```` ````secret ```` block stays secret, and a ```` ```secret ```` line inside an ordinary ```` ```python ```` block is just code.
- **Reveal with the caret.** Move the caret into a secret line (click it, ↑/↓, Go to Line, a find result, a bookmark) and the whole block is shown and editable; move the caret out and it is masked again. Only the display changes: the text is still in the buffer, so Find, Replace, undo and saving work exactly as before.
- **Reveal Secrets ⌥⌘S** (Edit menu, toggles to *Mask Secrets*) shows every block at once. After **Settings › Secrets › Re-mask after** (10 / 30 / 60 s, default 30 s, or *Never*) they are masked again automatically; the Output panel logs both events and the status bar shows `REVEALED` while they are open (`•••• N` while N blocks are masked).
- **Everywhere else the text is redacted.** Find results list the match (line number and jump still work) but show `••••••••` as the line text; the Outline and Timeline skip lines inside secret blocks; the Markdown preview renders secret lines as `••••••••`; the Reveal state does not affect these.
- **Clipboard auto-clear.** When a copy or cut (including multi-caret and column-mode copies) overlaps a secret line, the clipboard is cleared after **Settings › Secrets › Clear clipboard after copying a secret** (Off / 10 / 30 / 60 s, default 30 s) — but only if nothing else was copied in the meantime (the pasteboard change count is unchanged). **Edit › Clear Clipboard** clears it immediately. The Output panel logs `Clipboard cleared (secret)`.
- **Settings › Secrets:** *Mask secret blocks* (default on — off shows the lines everywhere and disables the clipboard clearing), *Re-mask after*, *Clear clipboard after copying a secret*.
- Secret blocks fold like any fenced block (⌥⌘←); a folded block is hidden, an unfolded one is masked.

> **This is masking, not encryption.** The file is saved as plain text, and so are snapshots. Anyone with the file can read the secrets; the feature only keeps them off your screen (and off screenshots, find results and the preview) while you work.

### Shortcut table rows

| ⌥⌘S | Reveal Secrets / Mask Secrets (Edit menu) |

### Launch argument (README developer table)

| `--reveal-secrets` | Start with every secret block revealed (for screenshots; no automatic re-mask timer) |

## 2. 한국어 (README.ko / USER_GUIDE.ko)

### 비밀 블록

- **비밀 블록 가리기.** 펜스 코드 블록의 정보 문자열이 `secret` 로 시작하면(```` ```secret ````, ```` ```secret 은행 ````, ```` ~~~secret ````) *비밀 블록* 입니다. 펜스 사이의 모든 줄은 글자 대신 둥근 가림막과 `••••••••` 로 그려지고, 펜스 줄 자체는 그대로 보여서 블록이 어디에 있고 무엇인지 알 수 있습니다. 마크다운이 아닌 파일(`.txt`, 확장자 없음)에서도 같은 규칙입니다. 중첩은 CommonMark 를 따릅니다 — ```` ````secret ```` 안의 ```` ```python ```` 블록은 비밀로 남고, 일반 ```` ```python ```` 블록 안의 ```` ```secret ```` 줄은 그냥 코드입니다.
- **캐럿으로 드러내기.** 캐럿을 비밀 줄에 두면(클릭, ↑/↓, 줄 이동, 찾기 결과, 북마크) 그 블록 전체가 보이고 편집할 수 있으며, 캐럿이 나가면 다시 가려집니다. 바뀌는 것은 표시뿐 — 텍스트는 그대로 있어 찾기·바꾸기·undo·저장이 평소와 같습니다.
- **비밀 드러내기 ⌥⌘S** (편집 메뉴, 드러낸 뒤에는 *비밀 가리기*) 는 모든 블록을 한 번에 드러냅니다. **설정 › 비밀 › 다시 가리기까지** (10 / 30 / 60초, 기본 30초, 또는 *수동*) 가 지나면 자동으로 다시 가려지며, 출력 패널에 두 사건이 기록되고 상태바에는 드러낸 동안 `REVEALED`, 가린 동안 `•••• N`(블록 N개) 이 표시됩니다.
- **다른 곳에서는 가린 텍스트.** 찾기 결과는 매치(줄 번호·이동)는 그대로 두고 줄 텍스트를 `••••••••` 로 보여 주고, 아웃라인·타임라인은 비밀 블록 안의 줄을 건너뛰며, 마크다운 미리보기는 비밀 줄을 `••••••••` 로 렌더합니다. 드러내기 상태는 이들에 영향을 주지 않습니다.
- **클립보드 자동 비우기.** 복사·잘라내기(멀티 커서·열 모드 포함) 범위가 비밀 줄과 겹치면 **설정 › 비밀 › 비밀을 복사한 뒤 클립보드 비우기** (끔 / 10 / 30 / 60초, 기본 30초) 뒤에 클립보드를 비웁니다 — 단, 그 사이 다른 것을 복사하지 않았을 때만(페이스트보드 changeCount 가 그대로일 때). **편집 › 클립보드 비우기** 는 즉시 비웁니다. 출력 패널에 `클립보드 비움 (비밀)` 이 기록됩니다.
- **설정 › 비밀:** *비밀 블록 가리기*(기본 켜짐 — 끄면 모든 곳에서 줄이 보이고 클립보드 비우기도 하지 않음), *다시 가리기까지*, *비밀을 복사한 뒤 클립보드 비우기*.
- 비밀 블록도 다른 펜스 블록처럼 접힙니다(⌥⌘←). 접힌 블록은 숨겨지고, 펼친 블록은 가려집니다.

> **가리는 것이지 암호화가 아닙니다.** 파일은 평문으로 저장되고 스냅샷도 마찬가지입니다. 파일을 가진 사람은 누구나 비밀을 읽을 수 있습니다 — 이 기능은 작업 중 화면(그리고 스크린샷·찾기 결과·미리보기)에서만 비밀을 치웁니다.

### 단축키 표 행

| ⌥⌘S | 비밀 드러내기 / 비밀 가리기 (편집 메뉴) |

### 실행 인자

| `--reveal-secrets` | 모든 비밀 블록을 드러낸 상태로 시작 (스크린샷용, 자동 재마스킹 없음) |

## 3. docs/features.md 표 행 (섹션 I. 보안·개인정보 — 기존 🔜 행을 대체)

| ✅ | **비밀 블록 마스킹** — 정보 문자열이 `secret` 로 시작하는 펜스 블록(```` ```secret 은행 ````)의 안쪽 줄을 편집기에서 둥근 가림막 + `••••••••` 로 그린다(펜스 줄은 보임, .txt 도 같은 규칙, 중첩은 CommonMark). 캐럿이 들어가면 그 블록만 드러나고 나가면 다시 가림. **비밀 드러내기 ⌥⌘S**(편집 메뉴)는 전부 드러냈다가 설정 시간(10/30/60초/수동, 기본 30초) 뒤 자동으로 다시 가림, 상태바 `•••• N` / `REVEALED`. 찾기 결과 줄 텍스트·아웃라인·타임라인·마크다운 미리보기도 가린 텍스트 사용. 설정 › 비밀 에서 끌 수 있음. 표시만 가리며 파일은 평문 | `SecretScanner`(HyperCore `Text/SecretScanner.swift`, O(n) 단일 패스, `blocks`·`redacted`) · `Editor/SecretController.swift`(뷰별, 오프셋 추적 + 250 ms 백그라운드 재스캔, 파일 열 때는 첫 그리기 전 동기 스캔) · `FoldController` 의 TextKit 2 layout delegate 를 공용으로 써서 가릴 문단에 `MaskedLayoutFragment`(높이 정상, 글리프 대신 가림막) · `SecretsUI.swift`(`SecretsStore`·메뉴·상태바) · `SecretsSettings.swift`. `--reveal-secrets` |
| ✅ | **클립보드 자동 소거** — 복사·잘라내기(멀티 커서·열 모드 포함) 범위가 비밀 줄과 겹치면 설정 지연(끔/10/30/60초, 기본 30초) 뒤 `NSPasteboard.general` 의 changeCount 가 그대로일 때만 비운다(그 사이 다른 복사가 있으면 건드리지 않음). 편집 › 클립보드 비우기 로 즉시. 출력 로그 "Clipboard cleared (secret)" | `HyperTextView.onDidCopy` 훅 → `SecretController` → `SecretsStore.scheduleClipboardClear` |

## 4. New launch argument

`--reveal-secrets` — start with `SecretsStore.revealedAll = true` (no re-mask timer). Add to the README developer table and to `docs/features.md` section H's argument list.

## 5. Known limitations

- Masking only: the file, autosaves and snapshots are plain text. Nothing is encrypted; there is no app lock.
- The mask bar is as wide as the hidden line (or at least the `••••••••` label), so line *lengths* are visible. Empty lines inside a block are drawn as a short bar too.
- Find in Files (⇧⌘F) shows raw lines of *other* files — the redaction covers only the open document's find results. The editor's scrollbar markers still mark lines with matches inside a secret block (positions, not text).
- When a document contains at least one secret block, the TextKit 2 layout delegate stays installed, which costs roughly 1 ms per keystroke on the fragment path (the same cost as having a fold open). Documents without secret blocks are unaffected.
- `--no-fold` disables the layout delegate and therefore also disables masking (the find-result / outline / preview redaction and the clipboard clearing still work).
- The block set is rescanned 250 ms after typing stops; between edits the ranges are shifted by the edit tracker. Typing a new fence line therefore masks its lines after that delay. When a file is opened or reloaded the scan is synchronous, before the first draw.
- Reveal Secrets does not change the find-results / outline / preview redaction, and the secondary (split) editor masks and reveals independently (the caret rule is per view; ⌥⌘S applies to both).
- Only `NSPasteboard.general` is cleared; drag-and-drop uses its own pasteboard and is not touched.
