# Draft: Appearance — cursor style · window opacity (v0.8, branch feat/v08-appearance)

통합 담당이 README / README.ko / USER_GUIDE(11개 언어) / docs/features.md 에 옮겨 넣기 위한 초안. 코드는 `Apps/mac/Appearance.swift`(값·실행 인자·창 적용기·메뉴), `Apps/mac/AppearanceSettings.swift`(설정 섹션), `Apps/mac/Editor/HyperTextView.swift`(캐럿 그리기), `Apps/mac/Editor/EditorView.swift`(편집기 배경 α), `Apps/mac/SelfTest+Appearance.swift`.

## 1. English (README › Features / USER_GUIDE)

### Cursor style

Settings › **Appearance** › **Cursor style** chooses how the caret is drawn: **Bar** (default, the native 2 pt insertion bar), **Block** (the character cell under the caret is filled with the theme's cursor color at about 55 % opacity, so the glyph stays readable), or **Underline** (a 2 pt line under the character cell). At the end of a line or on an empty line the cell is one space wide; Hangul, CJK and tab cells use their real width. Extra carets from multi-caret editing (⌘D, ⌘-click) and column mode (⌥C, including virtual space past the line end) use the same style and do not blink. **Blink** (default on) turns caret blinking off when unchecked — for the Bar style this uses the system insertion indicator's steady mode; Block and Underline blink on a 0.5 s timer that pauses while you type. The caret color always comes from the theme's `cursor` color.

### Window opacity and blur

Settings › **Appearance** › **Window opacity** (50–100 %, default 100 %) makes the whole window translucent: the editor, gutter, ribbon, document tab bar, sidebar, bottom panel, status bar and the Markdown preview all show what is behind the window at the same opacity, while text, icons, borders and the current-line highlight stay readable (the highlight takes the same alpha). **Blur behind window** (default off) adds a system blur behind the translucent window; it only applies while the opacity is below 100 %. Both change instantly and survive theme changes, split editors and full screen. View › **Window Opacity** offers 100 / 90 / 80 / 70 % presets and the blur toggle. Stored in `ui.backgroundOpacity` / `ui.backgroundBlur`; the cursor settings in `ui.cursorStyle` / `ui.cursorBlink`.

## 2. 한국어 (README.ko › 기능 / 사용자 가이드)

### 커서 스타일

설정 › **외형** › **커서 스타일**에서 캐럿 모양을 고릅니다: **막대**(기본, 시스템 2 pt 삽입 막대), **블록**(캐럿이 놓인 글자 칸을 테마 커서색 약 55 % 로 채워 글자가 그대로 보임), **밑줄**(글자 칸 아래 2 pt 선). 줄 끝과 빈 줄에서는 공백 한 칸 폭이고, 한글·CJK·탭 칸은 실제 폭을 씁니다. 멀티 커서(⌘D, ⌘-클릭)와 열 모드(⌥C, 줄 끝 너머 가상 공백 포함)의 보조 캐럿도 같은 스타일로 그려지며 깜빡이지 않습니다. **깜빡임**(기본 켜짐)을 끄면 캐럿이 깜빡이지 않습니다 — 막대는 시스템 삽입 표시기의 고정 표시 모드를 쓰고, 블록·밑줄은 0.5 초 타이머로 깜빡이되 입력 중에는 멈춥니다. 캐럿 색은 항상 테마의 `cursor` 색입니다.

### 창 투명도와 블러

설정 › **외형** › **창 투명도**(50–100 %, 기본 100 %)를 낮추면 창 전체가 반투명해집니다: 편집기·거터·리본·문서 탭 줄·사이드바·하단 패널·상태바·마크다운 미리보기가 같은 투명도로 창 뒤를 비추고, 글자·아이콘·구분선·현재 줄 강조는 읽을 수 있게 유지됩니다(강조는 같은 α). **창 뒤 블러**(기본 꺼짐)를 켜면 반투명 창 뒤를 시스템 블러로 흐립니다 — 투명도가 100 % 미만일 때만 적용됩니다. 둘 다 즉시 반영되고 테마 전환·편집기 분할·전체 화면에서도 유지됩니다. 보기 › **창 투명도** 메뉴에 100 / 90 / 80 / 70 % 단계와 블러 토글이 있습니다. 저장 키는 `ui.backgroundOpacity` / `ui.backgroundBlur`, 커서 설정은 `ui.cursorStyle` / `ui.cursorBlink`.

## 3. docs/features.md 표 행 (한국어)

섹션 **J. 테마·외관**(시스템 외형 따르기 행 아래)에:

| 상태 | 기능 | 메모 |
|---|---|---|
| ✅ | **커서 스타일** — 설정 › 외형: 막대(기본)·블록(글자 칸을 커서색 α 0.55 로, 글자는 보임)·밑줄(칸 아래 2 pt), 깜빡임 끄기. 멀티 커서·열 모드(가상 공백) 보조 캐럿도 같은 스타일(깜빡임 없음). 줄 끝·빈 줄은 공백 한 칸, 한글·탭은 실제 폭 | `HyperTextView` — macOS 14+ 는 머리 캐럿을 `NSTextInsertionIndicator` 하위 뷰로 그리고 `drawInsertionPoint` 를 부르지 않는다(macOS 27 실측). 막대는 표시기 그대로(깜빡임 끄기 = `displayMode = .visible`), 블록·밑줄은 표시기를 `.hidden` 으로 두고(AppKit 이 `.automatic` 으로 되돌리면 KVO → 다음 턴에 다시; KVO 안에서 바로 설정하면 setter 와 재진입해 무한 재귀 — 실측) `drawBackground` 에서 글자 아래에 그림. 표시 여부는 AppKit 과 같은 규칙(키 창 + 첫 응답자 + 선택 없음)으로 직접 판단(`headCaretVisible`). 보조 캐럿도 키 창·첫 응답자일 때만. `ui.cursorStyle` `ui.cursorBlink` |
| ✅ | **창 투명도·블러** — 설정 › 외형 슬라이더 50–100 %(기본 100), 보기 › 창 투명도 100/90/80/70 %. 창·편집기·거터·리본·탭 줄·사이드바·하단 패널·상태바·미리보기가 같은 α, 글자·아이콘·구분선은 불투명. '창 뒤 블러'(기본 꺼짐)는 투명도 < 1 일 때만 | `WindowChromeView`(창 `isOpaque=false`·배경 clear, 블러는 내용 맨 뒤 `NSVisualEffectView` .behindWindow/.underWindowBackground). 편집기는 컨테이너 레이어 하나만 테마 배경 α 로 칠하고 스크롤뷰·텍스트뷰·거터 배경은 비움(겹치면 (1-α)² 만 비쳐 더 불투명). SwiftUI 표면은 `model.surfaceColor` 로 같은 α, 바탕은 비움. 미리보기는 `WKWebView` `drawsBackground=false`(SPI, 없으면 불투명 유지) + 페이지 배경 transparent. `ui.backgroundOpacity` `ui.backgroundBlur` |

## 4. README 실행 인자 표 (추가 행)

| Flag | Effect |
|---|---|
| `--cursor <bar\|block\|underline>` · `--no-cursor-blink` | Start with that caret style / with caret blinking off (screenshots) |
| `--opacity <0.5–1.0>` · `--blur` | Start with the window at that opacity (clamped to 0.5–1.0) / with blur behind the translucent window |

(README.ko) `--cursor <bar|block|underline>` · `--no-cursor-blink` — 그 캐럿 스타일로 시작 / 깜빡임 끄고 시작(스크린샷용); `--opacity <0.5~1.0>` · `--blur` — 그 투명도로 시작(0.5~1.0 으로 잘림) / 반투명 창 뒤 블러 켜고 시작.

## 5. 알려진 제한

- 블록·밑줄 캐럿은 20,000자가 넘는 한 문단(압축 JSON 등) 안에서는 그려지지 않는다 — 기존 현재 줄 강조·멀티 캐럿과 같은 `hugeParagraphLength` 보호(TextKit 2 가 문단 전체를 배치하므로). 막대 캐럿(네이티브)은 그대로 보인다.
- 보조 캐럿(멀티 커서·열 모드)은 깜빡이지 않는다(막대 스타일의 머리 캐럿은 네이티브가 깜빡이므로 박자를 맞출 수 없어 고정 표시로 통일). v0.7 까지의 보조 캐럿 그리기(`drawInsertionPoint` 오버라이드)는 macOS 14+ 에서 호출되지 않아 실제로는 그려지지 않았다 — 이번에 `drawBackground` 로 옮겨 복구됐다.
- 스크린샷 자동화 메모: `--goto` 는 init 0.8 s 뒤 한 번만 실행되는데, 머신 부하가 높으면 창 생성·`restoreViewStateIfNeeded`(저장된 위치 없음 → 문서 끝)가 그 뒤에 와서 덮는다(기존 동작, 이 기능과 무관). 또 `--ephemeral`/`--snapshot`/`--selftest` 가 쓰는 휘발성 suite `hyperedit.automation` 은 같은 머신의 동시 자동화 실행끼리 공유되어 서로의 값(`ui.splitMode` 등)이 섞일 수 있다(동시 에이전트 작업 중 관찰).
- 막대 + 깜빡임 끄기는 `NSTextInsertionIndicator.displayMode = .visible` 에 의존한다(macOS 14+ 공개 API). 시스템이 표시기를 다시 보일 때 `.automatic` 으로 되돌리므로 KVO 로 즉시 재적용한다.
- 창 투명도는 `NSWindow.isOpaque=false` 라 글자 안티에일리어싱이 서브픽셀에서 회색조로 바뀐다(모든 반투명 macOS 창과 동일).
- 마크다운 미리보기 투명화는 WebKit 의 `drawsBackground` KVC(SPI)에 기대며, 해당 셀렉터가 없는 환경에서는 미리보기만 불투명으로 남는다(`--debug-preview-log` 에 기록).
- 리본 버튼의 호버·선택 배경(`backgroundElevated`, 강조색)은 작은 강조라 α 를 입히지 않았다(불투명 유지).
