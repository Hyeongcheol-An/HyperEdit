# App Lock (Touch ID) — 문서 초안 (통합 담당이 README · README.ko · USER_GUIDE · features.md 에 반영)

브랜치 `feat/v08-applock`. 구현: `Apps/mac/AppLock/AppLockController.swift`(상태 머신·유휴 타이머·알림 구독·인증기·잠긴 동안의 키/메뉴 차단) · `AppLock/LockOverlay.swift`(오버레이) · `AppLock/AppLockUI.swift`(메뉴) · `Apps/mac/AppLockSettings.swift`(설정 섹션) · `SelfTest+AppLock.swift`.

## 1. English (README "Features" → new sub-section after Quick Append; USER_GUIDE section)

### App Lock (Touch ID)
- **Lock HyperEdit (⌃⌘L)** covers the whole window — ribbon, sidebar, editor, panels and status bar — with an opaque lock screen in the current theme, closes an open Settings window and hides the Quick Append panel. Nothing about the document (not even the file name) is shown while locked. Click **Unlock** (or press Return) to authenticate with **Touch ID**; if Touch ID fails or the Mac has none, macOS falls back to your login password. Cancelling keeps HyperEdit locked; the button retries.
- **Settings (⌘,) › App Lock:** *Require Touch ID or password to open HyperEdit* (off by default) starts the app locked — the document is loaded and autosave keeps working, but nothing is visible until you authenticate. *Lock after inactivity* (Never / 1 / 5 / 15 / 30 minutes, default Never) locks after that long without a key press or click in HyperEdit, independently of the launch option. *Lock when the Mac sleeps or the screen locks* (on by default) applies when the launch option is on.
- While locked, keyboard input is swallowed and the menu bar cannot be opened — only ⌘Q (Quit), ⌘H / ⌥⌘H (Hide), ⌘M, ⌘W and ⌃⌘F still work, and the Dock menu. The Quick Append global shortcut shows the unlock prompt instead of the panel and opens the panel once you have authenticated.
- This is a privacy lock for the screen, not encryption: the files on disk are unchanged and readable by any other app. The *Require…* option cannot be turned on while the Mac has neither Touch ID nor a login password, so you cannot lock yourself out.

Shortcut table row: `| ⌃⌘L | Lock HyperEdit | … |`

Settings paragraph (USER_GUIDE): the App Lock section sits below Quick Append in Settings; a caption tells you whether Touch ID is available on this Mac.

Developer launch flag (README table): `--locked` — Start locked (for screenshots; the real authenticator is used, so nothing prompts until you click Unlock). Automation runs (`--selftest`, `--snapshot`, `--bench`, `--quit-after-launch`) never start locked unless `--locked` is given.

## 2. 한국어 (README.ko · USER_GUIDE.ko)

### 앱 잠금 (Touch ID)
- **HyperEdit 잠금(⌃⌘L)** 은 리본·사이드바·편집기·패널·상태바까지 창 전체를 현재 테마 색의 불투명한 잠금 화면으로 가리고, 열려 있던 설정 창을 닫고 빠른 추가 패널을 숨깁니다. 잠긴 동안에는 파일 이름을 포함해 문서에 관한 어떤 것도 보이지 않습니다. **잠금 해제** 버튼(또는 Return)을 누르면 **Touch ID** 로 인증하고, Touch ID 가 실패하거나 없는 Mac 에서는 macOS 가 로그인 암호 입력으로 대신합니다. 취소하면 잠긴 채 유지되며 버튼으로 다시 시도할 수 있습니다.
- **설정(⌘,) › 앱 잠금:** *HyperEdit 를 열 때 Touch ID 또는 암호 요구*(기본 꺼짐)를 켜면 앱이 잠긴 상태로 시작합니다 — 문서는 읽히고 자동 저장도 계속되지만 인증 전에는 아무것도 보이지 않습니다. *입력이 없으면 잠금*(안 함 / 1 / 5 / 15 / 30분, 기본 안 함)은 HyperEdit 안에서 키 입력이나 클릭이 그 시간 동안 없으면 잠그며, 시작 옵션과 무관하게 동작합니다. *Mac 이 잠자기에 들어가거나 화면이 잠기면 잠금*(기본 켜짐)은 시작 옵션이 켜져 있을 때 적용됩니다.
- 잠긴 동안 키 입력은 버려지고 메뉴 막대는 열리지 않습니다 — ⌘Q(종료), ⌘H / ⌥⌘H(가리기), ⌘M, ⌘W, ⌃⌘F 와 Dock 메뉴만 동작합니다. 빠른 추가 전역 단축키는 패널 대신 잠금 해제 프롬프트를 띄우고, 인증이 끝나면 패널을 엽니다.
- 화면을 가리는 프라이버시 잠금이지 암호화가 아닙니다. 디스크의 파일은 그대로이며 다른 앱에서 읽을 수 있습니다. Touch ID 도 로그인 암호도 없는 Mac 에서는 *요구…* 옵션이 켜지지 않으므로 스스로 잠겨 버리는 일은 없습니다.

단축키 표 행: `| ⌃⌘L | HyperEdit 잠금 | … |`

실행 인자: `--locked` — 잠긴 상태로 시작(스크린샷용. 실제 인증기를 쓰므로 잠금 해제 버튼을 누르기 전에는 아무 프롬프트도 뜨지 않음). 자동화 실행(`--selftest`, `--snapshot`, `--bench`, `--quit-after-launch`)은 `--locked` 가 없으면 잠긴 채 시작하지 않는다.

## 3. docs/features.md 표 행 (한국어) — "F. 저장·파일·보안" 또는 적절한 영역에

| ✅ | **앱 잠금(Touch ID)** ⌃⌘L — 창 전체(리본·사이드바·편집기·패널·상태바)를 테마 색 불투명 오버레이로 가리고 파일 이름도 보이지 않는다. "잠금 해제" 버튼(또는 Return)으로 `LocalAuthentication` `.deviceOwnerAuthentication`(Touch ID → 실패/미지원 시 시스템 암호 폴백) 인증. 설정 › 앱 잠금: 열 때 요구(기본 꺼짐, 켜면 잠긴 채 시작·문서는 로드·자동 저장 계속) · 입력이 없으면 잠금(안 함/1/5/15/30분, 시작 옵션과 독립) · 잠자기/화면 잠금 시 잠금(기본 켜짐, 시작 옵션이 켜져 있을 때만). 잠긴 동안 키 입력은 버려지고(⌘Q·⌘H·⌥⌘H·⌘M·⌘W·⌃⌘F 만 통과) 메뉴는 열리자마자 닫히며(`NSMenu.didBeginTrackingNotification` → `cancelTracking`), 설정 창은 닫히고 빠른 추가(전역 단축키 포함)는 패널 대신 해제 프롬프트. 자동화 실행은 시작 잠금을 하지 않음(`--locked` 로 강제) | `AppLock/AppLockController.swift`(상태 머신 · `Authenticator` 프로토콜로 셀프테스트가 성공/실패/취소 주입 · 유휴는 입력당 시각만 기록하는 로컬 모니터 + 한 번 울리는 타이머 · `NSWorkspace.willSleepNotification`/`screensDidSleepNotification` · 분산 알림 `com.apple.screenIsLocked`) · `LockOverlay.swift`(표식 NSView `applock.overlay` 로 셀프테스트가 찾는다) · `AppLockUI.swift` · `AppLockSettings.swift`. SwiftUI 는 NSPrincipalClass 를 무시하고 자체 `AppKitApplication` 을 쓰므로 `sendAction` 가로채기는 불가능(실측) — 그래서 키 허용 목록 + 메뉴 추적 취소 방식. 화면 가림이지 파일 암호화가 아님 · Hardened Runtime 그대로, 엔타이틀먼트 추가 없음 |

## 4. 새 실행 인자

| `--locked` | 잠긴 상태로 시작한다 (스크린샷용). 인증기는 실제 LocalAuthentication 이며 "잠금 해제" 를 누르기 전에는 프롬프트가 뜨지 않는다. `--snapshot` 과 함께 쓸 수 있다 |

## 5. 알려진 제한

- 화면 가림(프라이버시) 잠금이다. 파일은 암호화되지 않으며 Finder·다른 앱·스냅샷 폴더에서 그대로 읽힌다. 잠긴 동안에도 자동 저장·외부 변경 감지·스냅샷은 계속 동작한다.
- 잠그는 순간 떠 있던 시트/알림(줄 이동·숫자 채우기·스니펫 선택 등)은 창에 붙어 있어 오버레이 위에 남는다. 문서 본문을 보여 주지는 않지만 닫히지는 않는다.
- 유휴 판정은 HyperEdit 가 받는 키·마우스 이벤트 기준이다(다른 앱에서의 활동은 모른다). 빠른 추가 패널 입력은 HyperEdit 이벤트라 유휴 시간을 되돌린다.
- 화면 잠금 감지는 loginwindow 의 분산 알림 `com.apple.screenIsLocked` 에 의존한다(비공개 알림이지만 수년째 유지). 잠자기는 `NSWorkspace.willSleepNotification`·`screensDidSleepNotification`.
- Touch ID 프롬프트는 시스템 UI 라 앱이 비활성일 때(전역 단축키로 빠른 추가를 열려 할 때) 다른 앱 위에 뜬다.
- 잠긴 동안 메뉴 막대가 아예 열리지 않으므로(마우스로 연 메뉴는 즉시 닫힘) 종료는 ⌘Q 또는 Dock 메뉴로 한다. Dock 메뉴·시스템 서비스로의 접근은 막지 않는다(문서 내용을 드러내는 경로는 없음). 프로그램적으로 메뉴 항목을 실행하는 경로(`performActionForItem`)는 막지 않는다 — 사용자 입력 경로(키 등가물·메뉴 추적)만 차단. 창 제목(파일 이름)은 그대로 — 숨김 제목 표시줄이라 창에는 보이지 않지만 Mission Control·Dock 미리보기에는 보인다.
- 로그인 암호도 Touch ID 도 없는 Mac 에서는 "열 때 요구" 를 켤 수 없고, 잠긴 뒤 인증 수단이 사라진 경우(예외 상황)에는 출력 패널에 경고를 남기고 해제한다 — 가릴 수단이 없는 Mac 에서 영구히 잠기지 않게 하기 위함.
