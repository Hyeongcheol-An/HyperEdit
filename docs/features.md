# 기능 목록과 상태

> HyperEdit가 다루려는 기능을 영역별로 정리하고 현재 상태를 표시한 문서입니다. 설계 배경은 [design.ko.md](design.ko.md), 사용법은 [README.ko.md](../README.ko.md)에 있습니다.
>
> **전제:** 대상 문서는 "한 파일에 계속 덧붙이는" 메모다 — 수만 줄, 1 MB 이상, 코드·로그·한글 메모·URL이 섞여 있고, 탭으로 맞춘 표와 `3+0.5+0.25 ⇒ 3.75` 같은 수기 계산 흔적이 있으며, 마크다운 구조는 거의 없다(`#` 줄은 헤딩보다 코드 주석일 때가 많다).
>
> **참고한 제품:** UltraEdit, Sublime Text, BBEdit, VS Code, Zed, Obsidian, Bear, Drafts, nvUltra, iA Writer, Typora, Marked 2, Day One, Apple Notes.
>
> **상태 표기:** ✅ 구현됨 · 🔜 예정(로드맵) · ⏸ 보류 · ✗ 제외. 미구현 기능은 UI에 비활성 자리표시자로 나타나지 않는다. 단축키는 `Apps/mac/HyperEditApp.swift`·`MacroUI.swift` 기준.

## A. 입력·캡처 (append 습관 강화)

| 상태 | 기능 | 메모 |
|---|---|---|
| ✅ | **마지막 본 위치 복원** — 파일별 캐럿·스크롤 저장, 기록이 없으면 끝으로. ⌃⌘E로 문서 끝 | `ViewStateStore` |
| ✅ | **타임스탬프 삽입** — F7 → `## 2026-10-30 (금) 14:05`, 요일은 시스템 로케일 | 날짜 줄이 생기면 B의 타임라인이 따라온다 |
| ✅ | **첫 실행 기본 문서** — `~/Documents/HyperEdit/notes.md`, 없으면 영·한 환영 문서 생성 | 사용자 파일은 덮어쓰지 않음 |
| ✅ | **새 문서** ⌘N — 이름과 위치를 고르면 빈 텍스트 파일을 만들어 연다(문서 탭 줄의 + 버튼, 홈 탭 파일 그룹) | 기본 폴더는 현재 문서의 폴더 |
| ✅ | **빠른 추가(Quick Append) 창** ⇧⌘N · 전역 ⌃⌥N — 앱을 활성화하지 않는 떠 있는 패널에 메모를 쓰고 ⌘↩ 로 문서 끝에 덧붙인다(타임스탬프 헤딩 옵션, 기본 켜짐). 바로 저장하고 undo 한 번으로 되돌릴 수 있으며, 닫으면 포커스가 이전 앱으로 돌아간다. Esc 로 닫으면 쓰던 글은 다음에 이어진다. 전역 단축키는 설정에서 끄기 / ⌃⌥N / ⌃⌥Space / ⌃⇧Space / ⌃⌥⌘N 중 선택(Carbon `RegisterEventHotKey`, 손쉬운 사용 권한 불필요). 홈 탭 삽입 그룹 · 파일 메뉴 | `QuickAppend/QuickAppendPanel.swift` · `QuickAppendController.swift` · `GlobalHotKey.swift` · `QuickAppendComposer`(HyperCore, 빈 줄·개행 규칙). 메뉴바 아이콘은 만들지 않음 |
| 🔜 | **붙여넣기 정리** — 채팅 앱 이모지 코드 제거, 연속 공백·빈 줄 정리, 스마트 따옴표 → 일반 | |
| ✅ | **스니펫/템플릿** — 트리거 단어 + Tab 으로 펼침(`todo` `date` `time` `now` `meeting` `table` `link` `code` 기본 제공), ⇧⌘I 선택창(필터·Enter 삽입), 변수 `${date}` `${time}` `${datetime}` `${selection}` `${clipboard}` `${filename}`, 탭스톱 `$1`…`$9`·`${1:자리표시자}`·`$0` 을 Tab / ⇧Tab 으로 이동(같은 번호는 멀티 캐럿), Esc·클릭으로 종료. "스니펫 편집…" 이 `~/Library/Application Support/HyperEdit/snippets.json` 을 HyperEdit 로 연다(저장하면 다음 확장 때 반영) | `SnippetTemplate`·`SnippetStore`(HyperCore `Text/Snippets.swift`) · `Editor/SnippetSession.swift`(탭스톱 보정은 `HyperTextView.shouldChangeText`) · `Panels/SnippetPickerView.swift`(⇧⌘I 선택창) · 홈 탭 삽입 그룹 "스니펫…". GUI 편집기는 없음 — JSON 을 직접 고친다 |
| 🔜 | 드래그&드롭 파일 → 경로 삽입 | |
| ⏸ | iOS 공유 시트·Shortcuts·받아쓰기 | iOS 타깃(M3)과 함께 |

## B. 탐색 (수만 줄에서 길 찾기)

| 상태 | 기능 | 메모 |
|---|---|---|
| ✅ | **북마크 + 북마크 패널** — ⌘F2 토글, F2 / ⌥F2 이동, 이름 선택. 편집으로 줄이 늘거나 줄면 북마크 줄 번호가 따라간다(북마크한 줄을 지우면 제거, undo/redo 도 추적, 디스크에서 다시 읽으면 줄 수에 맞춤). `~/Library/Application Support/HyperEdit/bookmarks/<경로 해시>.json`에 문서별 저장 | `HyperTextView.shouldChangeText` → `BookmarkStore.shift`. 문서 옆에 파일을 만들지 않는다. 예전 버전의 `.<파일명>.bookmarks.json` 사이드카는 한 번 읽어 옮기고 다시 쓰지 않음. 마지막 북마크를 지우면 JSON도 삭제 |
| ✅ | **줄 이동** ⌘L | |
| ✅ | **타임라인** ⌘4 — 타임스탬프 헤딩 + 날짜로 시작하는 느슨한 줄, 월별 그룹, 최신순, 연속된 같은 날짜(로그 덤프)는 첫 줄만 | `OutlineScanner.timeline` |
| ✅ | **아웃라인** ⌘3 — `#` 헤딩, `[제목]`, `가./나./다.`, `1)`·`1.` 번호 항목. 비마크다운 파일의 코드 주석형 `#` 줄과 로그 태그(`[INFO]`, `[id=…]`)는 제외. 필터 상자, 현재 항목 강조 | `OutlineScanner.outline` |
| ✅ | **파일**(사이드바 첫 탭) ⌘1 — 현재 파일 폴더의 트리(숨김 파일 제외, 폴더 먼저), 한 번 클릭으로 열기, 바이너리는 기본 앱으로 | `TextFileDetector` |
| 🔜 | 앞으로/뒤로(편집 위치 히스토리) | |
| ✅ | **스크롤바 마커** — 편집기 오른쪽 가장자리 12pt 띠에 검색 매치(강조색 눈금)·북마크(경고색)·캐럿 줄(본문색 선)·접힌 머리 줄(흐린 눈금)을 줄 번호 비율로 표시. 문서가 한 화면에 다 들어가면 숨김. 보기 메뉴 "스크롤바 마커" · 레이아웃 탭 접기 그룹 "스크롤바 마커" 토글(기본 켜짐, `ui.scrollMarkers`) | `ScrollMarkerView` — `hitTest` nil 이라 오버레이 스크롤러는 그대로 동작. 캐럿 갱신은 60 ms 스로틀. 수정 위치 마커는 없음 |
| ✅ | **접기** ⌥⌘← / ⌥⌘→, 모두 접기·펼치기 ⌥⇧⌘← / ⌥⇧⌘→ — 영역은 (1) 들여쓰기: 더 깊이 들여쓴 줄들을 거느린 줄(빈 줄 무시, 탭 = 4칸), (2) `.md` 의 `#` 헤딩: 같거나 높은 레벨의 다음 헤딩 직전까지, 펜스(```) 블록, (3) 코드의 `{ [ (` 로 끝나는 줄: 닫는 괄호만 있는 줄까지. 거터 화살표(∨/›) 클릭, 머리 줄 뒤 `⋯ N lines` 표식 클릭으로도 접고 펼침. 캐럿이 숨은 줄로 들어가면(검색·줄 이동·북마크·undo) 자동으로 펼치고, ↑/↓ 는 접힌 구간을 건너뜀. 머리 줄 안의 입력·위쪽 줄 삽입/삭제·undo 에도 접힘이 따라감. 세션 안에서만 유지(파일별 저장 없음) | `FoldScanner`(HyperCore, O(줄 수) UTF-16 스캔, 입력 멈춤 250 ms 뒤 백그라운드) · `FoldController`(오프셋 추적) · TextKit 2 `NSTextLayoutManagerDelegate` 가 숨은 문단에 높이 0 프래그먼트. 리본 레이아웃 탭 "접기" 그룹. 드래그 선택은 숨은 텍스트를 포함한 채 둔다 |
| 🔜 | 미니맵, 고정 헤더 | |

## C. 검색

| 상태 | 기능 | 메모 |
|---|---|---|
| ✅ | **찾기** ⌘F — Enter로 실행, 전체 매치를 줄 번호와 함께 목록으로, 매치 수 표시, 클릭으로 이동, F3 / ⇧F3. 목록이 있는 동안 편집기 안의 매치도 배경색으로 강조 | 하단 패널 "찾기 결과" 탭. 메모리 내 정규식(1~2 MB에 수십 ms) |
| ✅ | 정규식 `.*` · 대소문자 `Aa` · 단어 단위 `W` | 옵션을 바꾸면 즉시 재검색 |
| ✅ | **매치 모두 선택 → 멀티 커서** ⌥⌘A | |
| ✅ | **바꾸기** ⌘R — 현재 매치 바꾸고 다음으로 / 모두 바꾸기. 정규식 템플릿 `$1`. 모두 바꾸기는 ⌘Z 한 번 | |
| ✅ | **파일에서 찾기** ⇧⌘F — 폴더 선택, 마스크 `*.md;*.txt`, 하위 폴더 포함, 숨김 파일·패키지·바이너리·20 MB 초과 파일 제외, 결과 클릭으로 해당 줄 열기 | 파일당 500건·전체 5,000건 상한 |
| 🔜 | 한글 초성 검색 | |
| 🔜 | 필터 모드(매치되는 줄만 표시) | |
| 🔜 | 검색 히스토리, 저장된 검색 | |
| 🔜 | 날짜 범위 검색, `#태그` 검색 | |
| ✗ | 별도 검색 인덱스(FTS) | 메모리 내 검색이 충분히 빠르다. iOS 타깃에서 재검토 |

## D. 편집

| 상태 | 기능 | 메모 |
|---|---|---|
| ✅ | **열(블록) 모드** ⌥C — ⌥드래그 / ⇧방향키로 사각형 선택, 입력·삭제가 모든 줄에 적용, 짧은 줄은 가상 공백 패딩, 줄 단위 복사·잘라내기·붙여넣기 | `ColumnBlock` + `HyperTextView` |
| ✅ | **숫자 채우기(Insert Number)** ⌥⌘N — 시작값·증가값, 자릿수 0 패딩 | 열 선택 또는 멀티 커서의 각 줄 |
| ✅ | **멀티 커서** — ⌘클릭 추가, ⌘D 다음 매치 추가(선택이 없으면 단어 선택), ⌥⌘A 매치 모두. 모든 멀티 편집은 undo 한 단계 | |
| ✅ | **줄 도구** — 삭제 ⇧⌘K, 복제 ⇧⌘D, 위/아래 이동 ⌥↑ / ⌥↓, 합치기 ⇧⌘J, 역순, 줄 번호 붙이기 | 편집 탭 · "줄" 메뉴 |
| ✅ | **정렬** — 오름차순 / 내림차순 / 숫자(줄 앞 숫자 기준), 중복 줄 제거 | |
| ✅ | **공백** — 뒤 공백 제거, 앞뒤 공백 제거, 빈 줄 제거, 탭 → 공백(폭 4), 공백 → 탭(줄 앞 공백만) | |
| ✅ | **대소문자** — 대문자 / 소문자 / 첫 글자 대문자 / 반전 | |
| ✅ | 자동 줄바꿈 ⌥Z, 줄 번호 ⌥⌘L, 구문 색 ⌃⌘H, 확대/축소 ⌘= / ⌘- / ⌘0 | ⌥⌘H 는 시스템 '기타 가리기' 가 가로채므로 ⌃⌘H |
| ✅ | 대용량 성능 — 1.3 MB·3만 4천 줄에서 키 입력당 약 3 ms. v0.6: 모두 바꾸기 5,000건의 undo 1.7 s → 0.25 s(일괄 undo 직접 등록), 키 입력마다의 SwiftUI 재평가 제거, 폰트 목록 캐시, Release 심볼 스트립(바이너리 13.5 → 6.5 MB) | design.ko.md §5 · [performance.md](performance.md) |
| ✅ | **주석 토글** ⌘/ — 선택한 줄(없으면 현재 줄)에 파일 종류의 주석 기호를 넣거나 뺀다(VS Code 방식: 전부 주석이면 해제, 아니면 모두 주석. 가장 얕은 들여쓰기에 맞춰 기호를 세로로 정렬, 빈 줄은 건너뜀, 탭·공백 유지). 코드는 `CodeLanguage` 의 주석 정의(`//` `#` `--` …), 마크다운·HTML/XML 은 `<!-- -->`, CSS 는 `/* */` 를 줄마다, 메모는 `//` | `TextTools.toggleLineComment` · `CommentRegistry` · 편집 탭 도구 그룹 |
| ✅ | **즉석 계산** ⌃⌘= — 선택 또는 현재 줄(마지막 `=` 뒤)을 평가해 줄 끝에 `⇒ 결과` 삽입, 옛 결과는 교체. `+ - * / % ^`, 괄호, `1,234`·`1_000`, `sqrt abs round floor ceil min max`, `pi` `e`. 정수는 소수점 없이, 아니면 6자리까지 | `TextTools.evaluate` 재귀 하강 파서(NSExpression 미사용). 수식이 아니면 출력 패널에 알림 |
| ✅ | **열 맞춤** ⌃⌘T — 탭 표(선택 또는 캐럿 주변 탭 줄 묶음)를 표시 폭(한글·CJK 2칸) 기준 공백 패딩으로 맞춤. 줄마다 `\|` 가 있으면 마크다운 표로: ` \| ` 안 패딩, `---` 재생성, `--:` 오른쪽 정렬 | `TextTools.alignColumns` · `displayWidth`. 결과에 탭이 남지 않는다 |
| ✅ | **JSON 정리** ⌃⌘J / **JSON 한 줄로** — 선택(없으면 문서 전체)을 들여쓰기 2칸으로 정리하거나 한 줄로. 키 순서·숫자 표기(`1.0`, 큰 정수) 유지, 문자열은 의미 그대로 다시 이스케이프(한글·이모지는 그대로). 입력은 BOM·뒤따르는 쉼표·`//` `/* */` 주석(JSONC)을 받고 출력은 엄격한 JSON. 문법 오류면 텍스트를 두고 출력 패널에 `줄:열` 을 알린 뒤 캐럿을 그 자리로. 5.6 MB 를 31 ms(릴리스) | `JSONFormatter` 자체 재귀 하강 파서(JSONSerialization 미사용 — 키 순서가 바뀐다) · 편집 탭 도구 그룹 |
| 🔜 | Base64/URL 인코딩, Unix time ↔ 날짜 같은 변환 도구 | 로드맵 |
| 🔜 | 공백 문자 표시 | 로드맵 |
| ✅ | **매크로** ⇧⌘M 기록/중지 · ⌥⌘M 재생 — 타이핑(IME 는 확정 글자만)·이동/삭제/줄바꿈 명령·붙여넣기(당시 클립보드 문자열)·텍스트 도구·F3 다음 찾기(검색어 포함)를 기록해 재생. "여러 번 재생…"(최대 10,000회, 찾기 실패·무변화면 중단), 전체 재생이 undo 한 단계. "이름 붙여 저장" 으로 매크로 메뉴에 등록, `~/Library/Application Support/HyperEdit/macros/macros.json`(편집기로 열어 직접 수정 가능). 상태바 `● REC` / `▶ MACRO`, 편집 탭 "매크로" 그룹 | `MacroStep`/`MacroStore`(HyperCore `Text/Macro.swift`) · `Editor/MacroRecorder.swift` · `MacroUI.swift`. 마우스 클릭·선택 변경·모두 바꾸기·숫자 채우기 등 멀티 캐럿 편집은 기록되지 않음. 1.3 MB 문서에서 10단계 ×100 재생 ≈ 0.8 s |
| 🔜 | 선택 영역 통계 표시 | `TextTools.stats`는 있음, UI 없음 |
| ✗ | 16진수 편집, 두 파일 비교 | 필요성 낮음 |

## E. 마크다운·표시

| 상태 | 기능 | 메모 |
|---|---|---|
| ✅ | 일반 텍스트 렌더링, 현재 줄 강조, 줄 번호 거터 | |
| ✅ | **라이트 하이라이트(메모·마크다운)** ⌃⌘H — URL, ISO 날짜·시각, `#` 헤딩(메모 모드에서 코드 주석처럼 보이는 `# from x import` 는 주석색), `[제목]`, 목록 기호·`[ ]`/`[x]` 체크박스, `#태그`, `키:` 라벨, `**굵게**`, `` `코드` ``, `⇒ → ->` 화살표. `.txt`·`.md`·확장자 없는 파일의 기본 | `PlainNotesGrammar`. 보이는 줄만 계산(TextKit 2 `renderingAttributesValidator`), 스토리지 속성·undo·한글 폰트 런·검색 강조와 분리. 상태바에 언어 이름, 홈 탭 모드 그룹·보기 메뉴에 토글 |
| ✅ | **코드 구문 색 20여 종** — Swift, Python, JS/TS, JSON, 셸, YAML, HTML/XML, CSS, C/C++/Objective-C, Go, Rust, SQL, Ruby, Java/Kotlin, TOML, INI. 주석·문자열·숫자·키워드·함수·타입·속성(데코레이터)·구두점·연산자 | `CodeGrammar(language:)` + `GrammarRegistry`(확장자 → 문법). 줄 단위 토큰화라 여러 줄 블록 주석·문자열은 시작한 줄만. 색은 테마 `syntax` 팔레트 |
| ✅ | **마크다운 분할 미리보기** ⇧⌘P — 좌 편집 / 우 렌더(GFM: 헤딩·목록·체크리스트·표·코드 블록·인용·링크·이미지), 현재 테마 색으로 스타일, 편집기 → 미리보기 스크롤 동기화(보이는 첫 줄 기준, `data-line`), 입력 멈춤 300 ms 뒤 다시 렌더(스크롤 위치 유지), 2 MB 초과 파일은 안내만. 링크는 기본 브라우저로, 원문 HTML은 이스케이프해 글자로(실행 안 함), 상대 경로 이미지는 문서 폴더 기준. 레이아웃 탭 "마크다운" 그룹 · 보기 메뉴 · 상태바 **MD** 표시 | swift-markdown 0.9.0(Apache-2.0) · `MarkdownHTML`(HyperCore) · `MarkdownPreviewView`(WKWebView). 미리보기 → 편집기 역방향 동기화는 없음 |
| ✅ | **편집기 분할(분할 보기)** ⌘\ — 같은 문서를 두 편집기로(좌우 또는 상하, 보기 메뉴 "분할" 하위 메뉴·레이아웃 탭 패널 그룹). 두 뷰는 같은 텍스트·undo 스택을 공유하고(A 에서 입력, B 에서 ⌘Z) 따로 스크롤한다. 명령·상태바·미리보기 동기화는 마지막으로 클릭/포커스한 편집기 기준, ⌥⌘\ 로 다른 분할로 포커스. 상태바 **SPLIT** 표시, 마크다운 미리보기와 함께 켤 수 있음 | TextKit 2: `NSTextContentStorage` 하나에 뷰마다 `NSTextLayoutManager`(`EditorSession`). `Editor/EditorSession.swift` · `EditorView.swift`(role). 보조 편집기는 위치 저장·창 제목·검색 강조(스토리지 속성)를 맡지 않는다. `--split [vertical\|horizontal]` |
| 🔜 | HTML/PDF 내보내기 | |
| 🔜 | 여러 줄 블록 주석·문자열 상태 추적, 사용자 정의 문법·키워드 | |

## F. 저장·백업

| 상태 | 기능 | 메모 |
|---|---|---|
| ✅ | **자동 저장** — 입력 멈춤 2초 뒤. 종료·창 닫기·파일 전환 시에는 동기 저장(직렬 쓰기 큐). 원자적 쓰기 | 2초 창에서의 손실 없음 |
| ✅ | **스냅샷** — 세션 첫 저장 전, 외부 변경 감지 시(수정 중일 때) `~/Library/Application Support/HyperEdit/snapshots`에 사본 | 파일별 최신 20개 유지, 90일 지난 것 삭제 |
| ✅ | **외부 변경 감지** — 깨끗하면 재로드(캐럿 위치 유지), 수정 중이면 스냅샷 + 경고 | 다른 앱의 원자적 저장도 추적 |
| ✅ | **빈 버퍼 저장 차단** — 내용이 있던 파일을 빈 내용으로 덮어쓰지 않음 | |
| ✅ | **인코딩 감지·유지** — UTF-8 → EUC-KR(CP949) → CP1252 → Latin-1 순 무손실 디코딩, 상태바에 표시, 같은 인코딩으로 저장(UTF-8 BOM 보존). 원 인코딩에 없는 문자는 UTF-8로 변환 저장하고 알림. 판별 불가 파일은 열지 않음 | `MemoDocument.decode` |
| ✅ | 상태바에 줄바꿈 종류(UNIX / DOS / MAC)·인코딩·크기 표시 | |
| 🔜 | 스냅샷 버전 브라우저 | |
| 🔜 | Git 자동 커밋 옵션 | |
| ⏸ | iCloud Drive 동기화·충돌 병합 | 로컬 전용으로 결정, 보류 |
| ✗ | 자체 서버 동기화 | |

## G. iOS

| 상태 | 기능 |
|---|---|
| ⏸ | iOS 앱 전체 — 마지막 위치 복원, 검색, 빠른 추가, 생체 인증 잠금, 키보드 툴바, 위젯. 엔진(`HyperCore`)은 iOS 18 타깃을 선언해 두었다 |

## H. 자동화·통합

| 상태 | 기능 | 메모 |
|---|---|---|
| ✅ | 개발용 실행 인자 — `--file`, `--ephemeral`, `--snapshot` `--snapshot-delay` `--snapshot-activate` `--snapshot-panel` `--window-width` `--quit`, `--selftest` `--selftest-out` `--selftest-split-big` `--show-snippet-picker` `--show-macro-recording` `--snapshot-sheet` `--selftest-open`, `--theme` `--follow-system-theme`, `--ribbon`, `--left` `--bottom` `--hide-left` `--hide-bottom`, `--search` `--replace` `--replace-with` `--find-in-files`, `--column`, `--goto`, `--preview`, `--split`, `--quick-append`, `--no-highlight`, `--fold` `--fold-all` `--no-fold`, `--debug-perf` `--debug-perf-log`, `--debug-startup` `--debug-startup-log` `--debug-preview-log` `--debug-no-apply`, `--bench` `--bench-out` `--bench-strict` `--bench-only` `--bench-commit`, `--quit-after-launch` `--bench-launch-log` | README "개발용 실행 인자" 표 참고. `--snapshot`·`--selftest`·`--bench`·`--ephemeral` 은 휘발성 설정과 임시 폴더만 쓴다 |
| ✅ | 성능 벤치마크 하네스 — `--bench` / `scripts/bench.sh`: 열기·타이핑·검색·바꾸기·스크롤·테마·메모리·유휴 CPU·실행 시간을 예산과 비교(PASS/FAIL), `--compare` 로 JSON 기준선과 비교. CI 에는 넣지 않는다(러너가 시끄러움) | `Apps/mac/Bench.swift` · `docs/bench/baseline-0.6.0.json` · [performance.md](performance.md) |
| 🔜 | URL 스킴, App Intents(Shortcuts), macOS 서비스 메뉴 | |
| 🔜 | CLI(`add`, `grep`, `tail`) | |
| 🔜 | Spotlight 인덱싱 | |

## I. 보안·개인정보

| 상태 | 기능 | 메모 |
|---|---|---|
| ✅ | 네트워크 코드 없음, 텔레메트리 없음 | SECURITY.md |
| ✅ | 사용자가 연 파일과 자체 파일(기본 문서, ⌘N으로 만든 파일, Application Support의 북마크 JSON·스냅샷·`snippets.json`·`macros/macros.json`, 환경설정)만 읽고 씀. 빠른 추가는 현재 문서 끝에 덧붙여 바로 저장 | 샌드박스는 아님. 전역 단축키는 Carbon `RegisterEventHotKey` 라 손쉬운 사용 권한이 필요 없고 다른 키 입력을 보지 않는다 |
| 🔜 | 비밀 블록 마스킹, 클립보드 자동 소거 | |
| 🔜 | 앱 잠금(Touch ID) | |

## J. 테마·외관

| 상태 | 기능 | 메모 |
|---|---|---|
| ✅ | **22종 테마**, `themes/palettes.json` 단일 소스 → 앱 테마 + Zed 테마 + 미리보기 HTML | 이름은 모두 `Hyper ` 접두사 |
| ✅ | **시스템 외형 따르기** 기본 — 라이트 Hyper Light / 다크 Hyper Dark. 직접 고르면 고정 | 레이아웃 탭·상태바·보기 메뉴의 테마 메뉴와 설정에서 켜고 끔. ⌥⌘] / ⌥⌘[ 순환 |
| ✅ | **리본 UI** — 홈(클립보드·찾기·삽입·모드·파일) / 편집(줄·대소문자·정렬·공백·열·멀티 커서·도구) / 레이아웃(테마·패널·마크다운 미리보기·글꼴) / 고급(설정·스냅샷 폴더·다시 읽기·기본 문서) / 창(전체 화면·패널). 문서 탭 줄(새 문서·열기 버튼), 빠른 실행 저장·실행 취소·다시 실행. 창이 좁으면 작은 버튼이 아이콘만 남는 접힘 모드 | 비활성 자리표시자 없음 — 미구현 기능은 UI에 나타나지 않음 |
| ✅ | **상태바** — Ln / Col(+ 선택 길이, 문자 오프셋은 툴팁), 줄바꿈, 인코딩, COL, MD(미리보기 켜짐), 구문 언어(색이 꺼져 있으면 흐리게), 커서 수, 줄 수·크기, 상태, 테마(시스템 따르기 중이면 "· 시스템"), 확대 % | |
| ✅ | **폰트** — Fira Code(없으면 시스템 고정폭), 한글 폴백 D2Coding ×1.2로 2:1 폭, 리거처 토글, 줄 높이 | 설정 ⌘, · [fonts.md](fonts.md) |
| ✅ | **UI 언어** — 영어·한국어, 시스템 언어를 따름. 영어가 소스(카탈로그 키), 한국어는 `Apps/mac/Localizable.xcstrings` · `Packages/HyperCore/…/Localizable.xcstrings` 번역 | `scripts/check-l10n.py`가 CI에서 키 누락 검사. 다른 언어 기여 환영 |
| 🔜 | 커서 스타일(블록·바·밑줄), 배경 투명도, 공백 표시 | |

## K. 제외·보류

- 노트 분할·위키링크·그래프 뷰(Obsidian류): "한 파일에 append" 습관과 충돌 → 보류.
- 실시간 협업: 1인 사용 전제 → 제외.
- 구문 강조는 줄 단위의 가벼운 규칙으로 구현(E 참조). 트리시터 같은 완전한 파서·여러 줄 상태 추적은 메모 파일 성능을 위해 하지 않는다.
- 클라우드 동기화·자체 서버: 로컬 전용으로 결정 → 보류.
