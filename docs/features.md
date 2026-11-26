# 기능 목록과 상태

> HyperEdit가 다루려는 기능을 영역별로 정리하고 현재 상태를 표시한 문서입니다. 설계 배경은 [design.ko.md](design.ko.md), 사용법은 [README.ko.md](../README.ko.md)에 있습니다.
>
> **전제:** 대상 문서는 "한 파일에 계속 덧붙이는" 메모다 — 수만 줄, 1 MB 이상, 코드·로그·한글 메모·URL이 섞여 있고, 탭으로 맞춘 표와 `3+0.5+0.25 ⇒ 3.75` 같은 수기 계산 흔적이 있으며, 마크다운 구조는 거의 없다(`#` 줄은 헤딩보다 코드 주석일 때가 많다).
>
> **참고한 제품:** UltraEdit, Sublime Text, BBEdit, VS Code, Zed, Obsidian, Bear, Drafts, nvUltra, iA Writer, Typora, Marked 2, Day One, Apple Notes.
>
> **상태 표기:** ✅ 구현됨 · 🔜 예정(로드맵) · ⏸ 보류 · ✗ 제외. 미구현 기능은 UI에 비활성 자리표시자로 나타나지 않는다. 단축키는 `Apps/mac/HyperEditApp.swift`·`MacroUI.swift`·`SecretsUI.swift`·`AppLock/AppLockUI.swift` 기준.

## A. 입력·캡처 (append 습관 강화)

| 상태 | 기능 | 메모 |
|---|---|---|
| ✅ | **마지막 본 위치 복원** — 파일별 캐럿·스크롤 저장, 기록이 없으면 끝으로. ⌃⌘E로 문서 끝 | `ViewStateStore` |
| ✅ | **타임스탬프 삽입** — F7 → `## 2026-10-30 (금) 14:05`, 요일은 시스템 로케일 | 날짜 줄이 생기면 B의 타임라인이 따라온다 |
| ✅ | **첫 실행 기본 문서** — `~/Documents/HyperEdit/notes.md`, 없으면 인터페이스 언어(11개)의 환영 문서 생성 | 사용자 파일은 덮어쓰지 않음 |
| ✅ | **새 문서** ⌘N — 이름과 위치를 고르면 빈 텍스트 파일을 만들어 연다(문서 탭 줄의 + 버튼, 홈 탭 파일 그룹) | 기본 폴더는 현재 문서의 폴더 |
| ✅ | **파일 탭**(UltraEdit 식, docs/tabs-model.ko.md) — 연 파일마다 탭, 클릭 전환, ⌘W·×·더블클릭·가운데 클릭 닫기(미저장은 먼저 저장, 보던 탭을 닫으면 왼쪽 이웃 — 보고 있지 않던 탭을 더블클릭해 닫으면 보던 탭에 그대로), 드래그 순서 바꾸기, 빈 탭 줄 더블클릭 = 새 문서, 우클릭 메뉴(다른 탭·왼쪽·오른쪽 닫기, 마지막으로 닫은 탭 다시 열기 ⇧⌘T, 저장 후 닫기, 저장된 내용으로 되돌리기, 경로 복사, Finder, 이름·경로·확장자·수정일 정렬), ⇧⌘] / ⇧⌘[ 순서 전환, ⌃Tab 직전에 본 탭(최근 활성 순서), ⌃⇧Tab 이전 탭, ⇧⌘W 모두 닫기, 오른쪽 끝 ▾ 열린 탭 목록, 툴팁에 경로·크기·수정 시각, 파일마다 캐럿·보기 위치·접힘 유지(실행 중), 열린 탭은 다음 실행 때 30개까지 복원(내용은 탭을 누를 때 읽음), 파일이 지워진 탭은 누르면 사라짐. **밖에서 연 파일도 같은 창의 탭으로**: Finder '다음으로 열기'·Dock 아이콘에 끌어다 놓기·`open -a HyperEdit <파일>`·실행 인자로 넘긴 파일 — 여러 개면 파일마다 탭이 생기고 마지막 것이 보이며, 이미 열린 파일이면 그 탭으로 간다. 폴더·없는 경로·텍스트가 아닌 파일은 열지 않고 출력 패널에 적는다. 잠겨 있거나 시트·모달 패널이 떠 있거나 매크로를 재생하는 중이면 그것이 끝난 뒤에, 빠른 추가 패널에 쓰던 메모가 있으면 그 메모를 붙이거나 패널을 닫은 뒤에 연다(빈 빠른 추가 패널은 미루지 않는다) | `AppModel.tabs`(파일 경로 목록) + 살아 있는 문서 하나(`document.switchTo`), `Panels/DocumentTabBar.swift`. 밖에서 온 열기 요청은 `ExternalOpen.swift` 가 받아 열어도 되는 때 `AppModel.openExternal` 로 넘긴다; 창은 하나다(SwiftUI 가 열기 이벤트마다 창을 만들던 것을 `.handlesExternalEvents(matching: [])` 로 막음). 같은 파일은 표기(대소문자, 한글의 조합형·분해형)가 달라도 탭 하나다 — 탭은 디스크에 적힌 표기로 견준다. 알려진 한계: 설정 창만 떠 있을 때(편집기 창을 닫은 뒤) 밖에서 파일을 열면 편집기 창은 돌아오지만 탭 줄이 갱신되지 않을 수 있다(사람 손으로는 미확인 — design.ko.md §5 '창 복구'). 탭을 떠나면 그 파일이 저장되고 실행 취소 기록이 비워진다; 수정됨 점은 활성 탭만. 마지막 탭을 닫으면 기본 문서가 대신 열린다(편집기는 항상 문서를 하나 든다) |
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
| ✅ | **파일**(사이드바 첫 탭) ⌘1 — 현재 파일 폴더의 트리(숨김 파일 제외, 폴더 먼저), 한 번 클릭·방향키로 열기, 바이너리는 기본 앱으로. 폴더는 한 단계씩 뒤에서 읽고 하위 폴더는 펼칠 때 읽는다(깊이 제한 없음). 본 폴더마다 펼침·스크롤 위치·선택이 남고, 탭으로 돌아오면 바뀐 것만 반영한다 — 항목 5,000개 폴더에서도 탭 전환이 멈추지 않는다 | `Panels/FileOutlineView.swift`(`NSOutlineView`, 폴더별 뷰 기억 12개 / 12만 항목) · `TextFileDetector` |
| 🔜 | 앞으로/뒤로(편집 위치 히스토리) | |
| ✅ | **스크롤바 마커** — 편집기 오른쪽 가장자리 12pt 띠에 검색 매치(강조색 눈금)·북마크(경고색)·캐럿 줄(본문색 선)·접힌 머리 줄(흐린 눈금)을 줄 번호 비율로 표시. 문서가 한 화면에 다 들어가면 숨김. 보기 메뉴 "스크롤바 마커" · 레이아웃 탭 접기 그룹 "스크롤바 마커" 토글(기본 켜짐, `ui.scrollMarkers`) | `ScrollMarkerView` — `hitTest` nil 이라 오버레이 스크롤러는 그대로 동작. 캐럿 갱신은 60 ms 스로틀. 수정 위치 마커는 없음 |
| ✅ | **세로 스크롤바 손잡이** — 손잡이의 자리가 문서에서의 줄 위치다(화면 위로 지나간 문단 수 ÷ 화면 밖에 있는 문단 수 전체): 스크롤하는 방향으로만 움직이고, 줄로 이동·찾기 점프 뒤에는 그 줄의 비율 자리에 놓이며, 손잡이를 끌면 같은 기준으로 그 자리의 문단이 화면 맨 위에 온다(트랙 맨 위·맨 아래로 끌면 문서 처음·끝). 자동 줄바꿈이 켜져 있고 접힌 문단이 없을 때 — 그 밖에는 AppKit 의 좌표 기준 그대로 | `Editor/EditorScrollView.swift`(`EditorScroller` · `EditorScrollView`, 줄 수는 `MemoDocument.liveLineIndex`). TextKit 2 는 뷰포트를 배치할 때마다 문서 높이를 다시 어림해(1.3 MB 메모: 847,845 … 1,157,051 pt, 실제 약 70만) 좌표 기준 손잡이가 800 pt 휠 250걸음 중 95번 거꾸로 갔다(최대 14.6 pt / 382 pt 트랙) → 0.9 pt. 대가: 여러 줄로 감긴 문단도 한 줄로 센다(긴 문단이 몰린 곳에서 손잡이가 느리게 간다). 남은 한계: 한 화면을 넘는 휠 걸음이 조각 캐시 버리기(2,000 문단마다)와 겹치면 내용 자체가 22~61줄 거꾸로 간다 — 손잡이는 내용을 그대로 따른다 |
| ✅ | **접기** ⌥⌘← / ⌥⌘→, 모두 접기·펼치기 ⌥⇧⌘← / ⌥⇧⌘→ — 영역은 (1) 들여쓰기: 더 깊이 들여쓴 줄들을 거느린 줄(빈 줄 무시, 탭 = 4칸), (2) `.md` 의 `#` 헤딩: 같거나 높은 레벨의 다음 헤딩 직전까지, 펜스(```) 블록, (3) 코드의 `{ [ (` 로 끝나는 줄: 닫는 괄호만 있는 줄까지. 거터 화살표(∨/›) 클릭, 머리 줄 뒤 `⋯ N lines` 표식 클릭으로도 접고 펼침. 캐럿이 숨은 줄로 들어가면(검색·줄 이동·북마크·undo) 자동으로 펼치고 — 열 블록의 행이나 추가 캐럿이 숨은 줄에 놓여도 —, ↑/↓ 는 접힌 구간을 건너뜀(감긴 머리 줄에서는 화면 줄을 하나씩 지난 뒤에). 글자·단어·줄 끝으로 옮기거나 선택을 늘리는 키가 숨은 글자에 닿으면 그 접힘이 먼저 펴져, 편 문서에서 같은 키를 누른 것과 같은 자리에 간다(접힌 머리 줄에서 ⌥→·⇧⌥→ — 접힌 채 넘어가 숨은 줄이 선택·삭제되는 일이 없다). 접힌 머리 줄 끝에서 ⌘→ 처럼 캐럿이 움직이지 않는 줄 끝·줄 머리 키는 접힘을 건드리지 않는다. 겹친 접힘은 선택이 지나는 것마다 펴지고, 오른쪽→왼쪽 문단에서는 ←/→ 가 글의 쓰기 방향대로 살핀다. 접을 때 그 안에 있던 캐럿은 여러 개여도 모두 머리 줄 끝으로 나온다(열 블록은 머리 캐럿 하나로; 줄이 CR LF 로 끝나면 `\r` 앞) — 화면은 머리 캐럿이 옮겨졌을 때만 따라가고, 모두 접기를 캐럿이 화면 밖에 있을 때 하면 읽던 곳에 남는다. 문서 끝까지 닿는 접힘 안으로 ⌘↓ 하면 펴지며 화면이 끝으로 간다. 다시 스캔은 캐럿·선택·열 블록이 놓인 줄을 접어 숨기지 않으며, 그러느라 구역이 펴질 때 쓰고 있던 줄은 제자리에 남는다. 머리 줄 안의 입력·위쪽 줄 삽입/삭제·undo 에도 접힘이 따라감. 모두 접기·펼치기는 캐럿 줄이 화면에 있으면 그 줄(접혀 사라지면 그 머리 줄)을 같은 높이에 둔다. 접힘은 문서 단위라 분할한 두 편집기가 같이 쓴다. 실행 중에는 파일별로 유지(탭을 오가도 그대로), 다음 실행까지는 저장하지 않음 | `FoldScanner`(HyperCore, O(줄 수) UTF-16 스캔, 입력 멈춤 250 ms 뒤 백그라운드) · `FoldStore`(문서마다 하나 — 접힘·후보·오프셋 추적) + `FoldController`(편집기마다 — 표식·거터·명령·보던 곳 지키기) · 숨은 문단은 **콘텐츠 열거에서 뺀다**(`FoldingContentStorage` + `NSTextContentStorageDelegate` 의 `shouldEnumerate`; 문서의 마지막 문단만 열거에 남겨 높이 0 조각 + 0.01 pt 표시용 문단으로 숨김). 높이 0 조각으로 숨기던 때에는 배치되지 않은 숨은 문단을 TextKit 2 가 보통 줄로 어림해 접힌 큰 문서의 높이·스크롤이 틀렸다(51,000 pt 문서를 537,651 pt 로; 접힌 1.3 MB 메모의 휠 걸음 평균 28 ms·최악 1.2 s → 약 8 ms). 리본 레이아웃 탭 "접기" 그룹. 드래그 선택은 숨은 텍스트를 포함한 채 둔다. 스크롤바 옆의 마커 띠는 크기가 바뀔 때만 다시 그린다(접힘 15,000개 문서의 휠 걸음 13.7~16.3 ms → 5.1 ms). 남은 한계: 모두 접은 화면의 휠 걸음은 접지 않은 문서의 2~3배(그 문서에서 5.1 ms 대 1.7 ms — 접힘 사이를 건너는 뷰포트 배치). 두 방향의 글자가 섞인 문단에서는 ←/→ 걸음이 필요 이상으로 펼 수 있다(양쪽을 다 살핀다). 마우스로 끌어 고른 선택에서 이어지는 ⇧ 걸음은 어느 끝이 움직이는지 몰라 양 끝을 다 살핀다(닻 옆의 접힘도 펴질 수 있다). 혼자인 `\r` 줄 끝(옛 Mac 형식)의 접힘은 다루지 않는다 |
| 🔜 | 미니맵, 고정 헤더 | |

## C. 검색

| 상태 | 기능 | 메모 |
|---|---|---|
| ✅ | **찾기** ⌘F — 빠른 찾기(UltraEdit Quick Find 식): 글자를 치면 150 ms 뒤 검색해 캐럿(앵커) 뒤 첫 매치를 선택하고 전체 매치를 줄 번호와 함께 목록·강조·개수 표시(64 MB 초과 문서는 Enter 때만). Enter 다음 / ⇧Enter 이전(포커스는 입력창), Esc 닫기+강조 제거, 클릭으로 이동, F3 / ⇧F3. 목록이 있는 동안 편집기 안의 매치도 배경색으로 강조(입력 중에도 자리를 따라가고 화면은 움직이지 않음) | 동작 모델은 docs/find-model.ko.md. 입력창은 `FindFields`(모델과 분리) — 글자마다 창 전체가 다시 평가되지 않음(28 MB 로그에서 키 입력당 20 → 2.5 ms). 하단 패널 "찾기 결과" 탭. ASCII 일반 검색은 64K 청크 스캔 빠른 경로(28 MB ≈ 수십 ms), 정규식·단어 단위·비ASCII 는 NSRegularExpression(28 MB ≈ 200 ms). 빠른 경로의 대소문자 무시는 A–Z 만 접으므로 켈빈 기호 K·긴 s(ſ)·ß↔ss 같은 유니코드 접기는 매치하지 않음. 편집 뒤 1.2 s 재검색은 조용히(스피너·로그 없이) 돌고 결과가 같으면 아무것도 발행하지 않는다. 강조는 스토리지 속성이 아니라 뷰가 보이는 매치만 그림(`HyperTextView.matchHighlights`). 결과 목록은 NSTableView(`SearchResultsTable`) — 1만 건에서도 재발행·캐럿 추적 비용이 행 수와 무관 |
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
| ✅ | 자동 줄바꿈 ⌥Z, 줄 번호 ⌥⌘L, 구문 색 ⌃⌘H, 확대/축소 ⌘= / ⌘- / ⌘0 — 레이아웃이 통째로 바뀌어도(확대·테마·줄바꿈·줄 번호·사이드바·미리보기·분할·창 폭·밖에서 바뀐 파일 다시 읽기) 보던 곳을 지킨다: 캐럿이 화면에 있으면 캐럿 줄, 아니면 맨 위 줄이 같은 높이에 남는다. 줄바꿈을 끄면 가로로 스크롤한다 — 가로 범위는 지금까지 화면에 배치해 본 가장 넓은 줄까지이고 더 긴 줄이 화면에 오면 넓어지며(줄어들지는 않는다), 캐럿·찾기 점프·열 블록의 머리 칸이 가로로 따라가고, 글자 크기를 바꾸거나 밖에서 바뀐 파일을 다시 읽어도 가로 위치가 남는다 | ⌥⌘H 는 시스템 '기타 가리기' 가 가로채므로 ⌃⌘H. `HyperTextView.captureReadingAnchor`/`restoreReadingAnchor`. 줄바꿈 끔에서는 텍스트 뷰의 폭을 앱이 직접 정한다(`Editor/HyperTextView+NoWrap.swift`): 컨테이너가 뷰 폭을 따르지 않으면 `-[NSTextView textContainerOrigin]` 이 읽힐 때마다 문서 전체를 배치하던 것을 재정의로 건너뛰어, 1.3 MB 문서에서 줄바꿈 끄기 1.7~3.4 s 정지 → 250 ms 넘는 정지 없음, 줄바꿈을 끈 4 MB 로그 열기 15 s → 0.35 s. 문서 끝에서의 리플로 정지(0.47~0.81 s)는 `enterDocumentBeforeViewportLayout` 으로 없앴다. 남은 한계: 다른 파일로 바뀌면 잰 폭을 버리므로 탭으로 돌아오면 가로 위치가 처음 열이다 |
| ✅ | **캐럿 따라가기** — 방향키·입력·Enter·삭제·한글 조합으로 캐럿이 화면 가장자리를 넘으면 반 화면이 아니라 넘은 만큼만(보통 한 줄) 스크롤한다 — 자동 줄바꿈이든 줄바꿈 끔이든(끔의 가로: 왼쪽 가장자리를 넘으면 넘은 만큼, 오른쪽이면 보이는 폭의 가운데로). 큰 붙여넣기 뒤에는 캐럿이 정말 보이는지 다음 턴에 한 번 더 본다. 줄바꿈 끔에서 편집이 남긴 선택(스니펫 자리표시자)은 범위 전체가 보이게 한다. 매크로 재생 중에는 걸음마다가 아니라 화면을 갱신할 때와 끝에서만 따라간다. 트랙패드로 문서 끝을 넘겨 당기면 한 번 늘었다가 정확히 끝으로 돌아오고, 관성이 남아 있는 동안 친 글자의 캐럿은 관성이 끝난 뒤 다시 보이게 한다 | `HyperTextView.revealCaretStep(afterEdit:)` · `editRevealDepth`(382 pt 화면의 맨 아랫줄 Enter 213 pt → 24 pt) · `liveScrollDidEnd`. `revealNoWrapColumn`(줄바꿈 끔의 가로) · `revealCaretAfterRelayout`(큰 붙여넣기 뒤) · `revealCaretAfterReplaySteps`(매크로 재생 — 10단계 ×100 재생 844~880 ms → 645~652 ms). AppKit 의 가운데 맞춤에 그대로 맡기는 것: 캐럿이 한 화면 넘게 가거나 편집 시작에서 64 문단 넘게 떨어진 큰 편집, 화면 위에서 시작한 편집(화면 밖의 멀티 캐럿), 문서의 마지막 줄에서의 입력, 실행 취소·찾기 점프·줄로 이동·Page Up/Down. 문서를 통째로 바꾸는 편집은 처음 64 문단에 2만 자 넘는 문단이 끼어 있으면 AppKit 에 맡긴다(화면에서 시작한 편집은 그런 줄 바로 뒤의 Enter 도 한 줄만 민다 — 202 pt → 24 pt). 제스처 중에 적어 둔 '캐럿 보이기'는 그 제스처 안에서만 산다(다음 스크롤이 시작되거나 문서가 바뀌면 버린다; 탭으로 돌아와 읽던 곳을 되살리는 스크롤은 세지 않는다) |
| ✅ | 대용량 성능 — 1.3 MB·3만 4천 줄에서 키 입력당 약 3 ms. v0.6: 모두 바꾸기 5,000건의 undo 1.7 s → 0.25 s(일괄 undo 직접 등록), 키 입력마다의 SwiftUI 재평가 제거, 폰트 목록 캐시, Release 심볼 스트립(바이너리 13.5 → 6.5 MB). 긴 문서의 끝을 보다가 더 짧은 문서로 바꾸거나 같은 파일이 짧아져 다시 읽힐 때의 정지(17.5 s·16.2 s)를 없앴다 | design.ko.md §5 · [performance.md](performance.md). 큰 범위를 바꾸는 텍스트 도구(주석 토글·JSON 정리·열 맞춤·줄/선택 변환)의 되돌리기·다시 실행: 1.3 MB 전체 주석 토글의 ⌘Z·⇧⌘Z 5.3 s → 0.26 s, 1.7 MB JSON 정리의 ⌘Z 0.85 s → 0.21 s — 16,384 UTF-16 단위 이상의 범위는 `insertText` 대신 모두 바꾸기와 같은 일괄 편집으로 넣는다(`HyperTextView.replaceForTool`; 그 길에서는 화면이 제자리에 남고 되돌리면 도구 전의 선택이 돌아온다). 남은 한계: 그 문턱 아래의 범위와 일반 입력의 큰 되돌리기(모두 선택 뒤 입력·붙여넣기의 ⌘Z)는 여전히 AppKit 의 입력 되돌리기라, 지운 글이 클수록 느리다 |
| ✅ | **주석 토글** ⌘/ — 선택한 줄(없으면 현재 줄)에 파일 종류의 주석 기호를 넣거나 뺀다(VS Code 방식: 전부 주석이면 해제, 아니면 모두 주석. 가장 얕은 들여쓰기에 맞춰 기호를 세로로 정렬, 빈 줄은 건너뜀, 탭·공백 유지). 코드는 `CodeLanguage` 의 주석 정의(`//` `#` `--` …), 마크다운·HTML/XML 은 `<!-- -->`, CSS 는 `/* */` 를 줄마다, 메모는 `//` | `TextTools.toggleLineComment` · `CommentRegistry` · 편집 탭 도구 그룹 |
| ✅ | **즉석 계산** ⌃⌘= — 선택 또는 현재 줄(마지막 `=` 뒤)을 평가해 줄 끝에 `⇒ 결과` 삽입, 옛 결과는 교체. `+ - * / % ^`, 괄호, `1,234`·`1_000`, `sqrt abs round floor ceil min max`, `pi` `e`. 정수는 소수점 없이, 아니면 6자리까지 | `TextTools.evaluate` 재귀 하강 파서(NSExpression 미사용). 수식이 아니면 출력 패널에 알림 |
| ✅ | **열 맞춤** ⌃⌘T — 탭 표(선택 또는 캐럿 주변 탭 줄 묶음)를 표시 폭(한글·CJK 2칸) 기준 공백 패딩으로 맞춤. 줄마다 `\|` 가 있으면 마크다운 표로: ` \| ` 안 패딩, `---` 재생성, `--:` 오른쪽 정렬 | `TextTools.alignColumns` · `displayWidth`. 결과에 탭이 남지 않는다 |
| ✅ | **JSON 정리** ⌃⌘J / **JSON 한 줄로** — 선택(없으면 문서 전체)을 들여쓰기 2칸으로 정리하거나 한 줄로. 키 순서·숫자 표기(`1.0`, 큰 정수) 유지, 문자열은 의미 그대로 다시 이스케이프(한글·이모지는 그대로). 입력은 BOM·뒤따르는 쉼표·`//` `/* */` 주석(JSONC)을 받고 출력은 엄격한 JSON. 문법 오류면 텍스트를 두고 출력 패널에 `줄:열` 을 알린 뒤 캐럿을 그 자리로. 5.6 MB 를 31 ms(릴리스) | `JSONFormatter` 자체 재귀 하강 파서(JSONSerialization 미사용 — 키 순서가 바뀐다) · 편집 탭 도구 그룹 |
| 🔜 | Base64/URL 인코딩, Unix time ↔ 날짜 같은 변환 도구 | 로드맵 |
| 🔜 | 공백 문자 표시 | 로드맵 |
| ✅ | **매크로** ⇧⌘M 기록/중지 · ⌥⌘M 재생 — 타이핑(IME 는 확정 글자만)·이동/삭제/줄바꿈 명령·붙여넣기(당시 클립보드 문자열)·텍스트 도구·F3 다음 찾기(검색어 포함)를 기록해 재생. "여러 번 재생…"(최대 10,000회, 찾기 실패·무변화면 중단), 전체 재생이 undo 한 단계. "이름 붙여 저장" 으로 매크로 메뉴에 등록, `~/Library/Application Support/HyperEdit/macros/macros.json`(편집기로 열어 직접 수정 가능). 상태바 `● REC` / `▶ MACRO`, 편집 탭 "매크로" 그룹 | `MacroStep`/`MacroStore`(HyperCore `Text/Macro.swift`) · `Editor/MacroRecorder.swift` · `MacroUI.swift`. 마우스 클릭·선택 변경·모두 바꾸기·숫자 채우기 등 멀티 캐럿 편집은 기록되지 않음. 1.2 MB 문서에서 10단계 ×100 재생 ≈ 0.65 s(재생 중에는 걸음마다 캐럿을 따라 스크롤하지 않는다) |
| 🔜 | 선택 영역 통계 표시 | `TextTools.stats`는 있음, UI 없음 |
| ✗ | 16진수 편집, 두 파일 비교 | 필요성 낮음 |

## E. 마크다운·표시

| 상태 | 기능 | 메모 |
|---|---|---|
| ✅ | 일반 텍스트 렌더링, 현재 줄 강조, 줄 번호 거터 | |
| ✅ | **라이트 하이라이트(메모·마크다운)** ⌃⌘H — URL, ISO 날짜·시각, `#` 헤딩(메모 모드에서 코드 주석처럼 보이는 `# from x import` 는 주석색), `[제목]`, 목록 기호·`[ ]`/`[x]` 체크박스, `#태그`, `키:` 라벨, `**굵게**`, `` `코드` ``, `⇒ → ->` 화살표. `.txt`·`.md`·확장자 없는 파일의 기본 | `PlainNotesGrammar`. 보이는 줄만 계산(TextKit 2 `renderingAttributesValidator`), 스토리지 속성·undo·한글 폰트 런·검색 강조와 분리. 상태바에 언어 이름, 홈 탭 모드 그룹·보기 메뉴에 토글 |
| ✅ | **코드 구문 색 20여 종** — Swift, Python, JS/TS, JSON, 셸, YAML, HTML/XML, CSS, C/C++/Objective-C, Go, Rust, SQL, Ruby, Java/Kotlin, TOML, INI. 주석·문자열·숫자·키워드·함수·타입·속성(데코레이터)·구두점·연산자 | `CodeGrammar(language:)` + `GrammarRegistry`(확장자 → 문법). 블록 주석·여러 줄 문자열·펜스는 줄 상태 추적(아래 행)으로 줄 너머까지 색이 이어진다. 색은 테마 `syntax` 팔레트 |
| ✅ | **마크다운 분할 미리보기** ⇧⌘P — 좌 편집 / 우 렌더(GFM: 헤딩·목록·체크리스트·표·코드 블록·인용·링크·이미지), 현재 테마 색으로 스타일, 편집기 → 미리보기 스크롤 동기화(보이는 첫 줄 기준, `data-line`), 입력 멈춤 300 ms 뒤 다시 렌더(스크롤 위치 유지), 2 MB 초과 파일은 안내만. 링크는 기본 브라우저로, 원문 HTML은 이스케이프해 글자로(실행 안 함), 상대 경로 이미지는 문서 폴더 기준. 레이아웃 탭 "마크다운" 그룹 · 보기 메뉴 · 상태바 **MD** 표시 | swift-markdown 0.9.0(Apache-2.0) · `MarkdownHTML`(HyperCore) · `MarkdownPreviewView`(WKWebView). 미리보기 → 편집기 역방향 동기화는 없음 |
| ✅ | **편집기 분할(분할 보기)** ⌘\ — 같은 문서를 두 편집기로(좌우 또는 상하, 보기 메뉴 "분할" 하위 메뉴·레이아웃 탭 패널 그룹). 두 뷰는 같은 텍스트·undo 스택·접힘을 공유하고(A 에서 입력, B 에서 ⌘Z; 한쪽에서 접으면 양쪽이 접힌다 — 다른 쪽은 보던 곳을 그대로 둔다) 따로 스크롤한다. 명령·상태바·미리보기 동기화는 마지막으로 클릭/포커스한 편집기 기준, ⌥⌘\ 로 다른 분할로 포커스. 상태바 **SPLIT** 표시, 마크다운 미리보기와 함께 켤 수 있음 | TextKit 2: `NSTextContentStorage` 하나에 뷰마다 `NSTextLayoutManager`(`EditorSession`) — 접힘은 콘텐츠 열거에서 빼는 방식이라 스토리지 단위다(`FoldStore`). `Editor/EditorSession.swift` · `EditorView.swift`(role). 보조 편집기는 위치 저장·창 제목을 맡지 않는다(검색 강조는 뷰마다 직접 그린다). `--split [vertical\|horizontal]` |
| ✅ | **HTML/PDF 내보내기** — 파일 › HTML로 내보내기… / PDF로 내보내기…. 저장 패널 액세서리로 테마(현재·Hyper Light·Hyper Dark)·줄 번호 선택. 마크다운은 미리보기와 같은 본문의 독립 HTML(미리보기 스크립트 없음·인쇄 CSS), 메모·코드는 문법 토큰을 `tok-*` span 으로 입힌 `<pre>`(여러 줄 상태 포함) + 테마 syntax CSS. PDF 는 화면 밖 WKWebView 에 같은 HTML 을 올려 `printOperation`(.save, Letter/A4, 여백 36 pt, 머리글·바닥글 없음)으로 쪽 나뉜 파일, 실패 시 `createPDF` 폴백. 2 MB 초과는 PDF 만 거절. 비밀 블록은 `••••••••` 로 | `HTMLExporter`(HyperCore `Export/`) · `Apps/mac/Export/Exporter.swift`·`ExportUI.swift`. 선택 영역·여러 파일·용지 옵션·PDF 목차 없음 |
| ✅ | **여러 줄 구문 상태 추적** — 블록 주석(`/* */`, `<!-- -->`), 여러 줄 문자열(Swift·Python `"""`/`'''`, JS/TS·Go 백틱, Rust `r#"…"#`), 마크다운 펜스(정보 문자열 언어로 중첩 토큰화, 모르는 언어면 메모 규칙 off), 마크다운 HTML 주석이 닫힐 때까지 모든 줄에 색. 여는/닫는 기호 입력 시 아래 줄 즉시 재도색 | `LineState`·`LineStateIndex`(HyperCore `Highlight/`): 줄별 진입 상태 표, 전체 계산 34k 줄 ≈10 ms, 편집 뒤 수렴까지만 증분(보통 1~2줄). `MemoDocument` 가 소유, `EditorView` validator 가 `scanLine(entering:)` 사용. 상태 없는 문법(메모·YAML·INI·셸)은 표를 만들지 않음. 제한: 여는/닫는 구분자가 같은 문자열만, 언어당 블록 주석 1쌍, 중첩 주석 없음 |
| ✅ | **사용자 정의 문법** — `~/Library/Application Support/HyperEdit/grammars/*.json`(name·extensions·filenames·mode·lineComments·blockComment·strings·multilineStrings·keywords·types·constants·builtins·caseInsensitive, 주석·뒤 쉼표 허용). 내장 확장자 덮어쓰기. 파일 › 문법 폴더 열기…(첫 생성 시 `example.json`+`README.md`) · 문법 다시 읽기(출력 "Grammars reloaded · N", 잘못된 파일은 건너뛰고 알림). 상태바 언어 이름, ⌘/ 주석 토글 연동 | `UserGrammarStore`·`GrammarRegistry`(사용자 문법 우선). 단어 목록 기반(정규식 없음), 폴더 변경 자동 감지 없음 |

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
| ✅ | 개발용 실행 인자 — `--file`, `--ephemeral` `--ephemeral-suite`, `--realuse` `--realuse-only` `--realuse-out`(실사용 시뮬레이션, `scripts/realuse.sh`), `--snapshot` `--snapshot-delay` `--snapshot-activate` `--snapshot-panel` `--window-width` `--window-height` `--quit`, `--selftest` `--selftest-out` `--selftest-foreground` `--selftest-split-big` `--show-snippet-picker` `--show-macro-recording` `--snapshot-sheet` `--selftest-open`, `--theme` `--follow-system-theme`, `--ribbon`, `--left` `--bottom` `--hide-left` `--hide-bottom`, `--search` `--replace` `--replace-with` `--find-in-files`, `--column`, `--goto`, `--preview`, `--show-settings` `--snapshot-settings` `--settings-height`, `--cursor` `--no-cursor-blink` `--opacity` `--blur`, `--reveal-secrets`, `--locked`, `--selftest-markers-big`, `--split`, `--quick-append`, `--no-highlight`, `--fold` `--fold-all` `--no-fold`, `--debug-perf` `--debug-perf-log`, `--debug-startup` `--debug-startup-log` `--debug-preview-log` `--debug-no-apply`, `--bench` `--bench-out` `--bench-strict` `--bench-only` `--bench-commit` `--bench-foreground`, `--quit-after-launch` `--bench-launch-log`. 옵션도 옵션의 값도 아닌 맨 인자는 어디에 있든 탭으로 연다(`HyperEdit a.md --ephemeral b.md` → a.md, b.md; 값을 받는 옵션은 `LaunchOptions.valueOptions` 에 있어야 한다) | README "개발용 실행 인자" 표 참고. 자동화 실행의 뜻은 둘이다(`AutomationRun.swift`). **떨어져 도는 실행**(`isIsolated`: 아래의 스크립트 실행 + `--ephemeral`)은 휘발성 설정과 임시 폴더만 쓰고, 저장된 창 상태와 창 프레임 저장값(`NSWindow Frame …`)을 읽지도 쓰지도 않는다 — 둘 다 번들 ID 별이라 테스트 빌드가 설치된 앱과 같이 쓴다. **스크립트가 모는 실행**(`isScripted`: `--selftest`·`--selftest-open`·`--bench`·`--realuse`·`--snapshot`·`--quit-after-launch`·`--bench-launch-log`)은 거기에 더해 활성화될 때마다 물러나 뒤에서 돌고(`--selftest-foreground`·`--bench-foreground`·`--snapshot-activate` 가 앞에서), 전역 단축키를 시스템에 등록하지 않으며, 밖에서 온 파일은 자기 픽스처(임시 폴더 바로 아래 `hyperedit-…` 폴더 안, `--file` 폴더의 직속 파일)만 연다. 셀프테스트·벤치·하네스는 프로세스당 한 번만 돈다 |
| ✅ | 성능 벤치마크 하네스 — `--bench` / `scripts/bench.sh`: 열기·타이핑·검색·바꾸기·스크롤·테마·메모리·유휴 CPU·실행 시간을 예산과 비교(PASS/FAIL), `--compare` 로 JSON 기준선과 비교. 앱을 앞으로 가져오지 않고 뒤에서 돈다(`scripts/bench.sh --foreground` / `--bench-foreground` 가 예전 방식) — 어떻게 돌았는지가 결과에 남고(JSON `mode`, 표의 `Run:` 줄) 뒤에서 잰 값은 뒤에서 잰 기준선과만 견준다. CI 에는 넣지 않는다(러너가 시끄러움) | `Apps/mac/Bench.swift` · `docs/bench/baseline-0.6.0.json`(앞에서 잰 것) · [performance.md](performance.md) |
| 🔜 | URL 스킴, App Intents(Shortcuts), macOS 서비스 메뉴 | |
| 🔜 | CLI(`add`, `grep`, `tail`) | |
| 🔜 | Spotlight 인덱싱 | |

## I. 보안·개인정보

| 상태 | 기능 | 메모 |
|---|---|---|
| ✅ | 네트워크 코드 없음, 텔레메트리 없음 | SECURITY.md |
| ✅ | 사용자가 연 파일과 자체 파일(기본 문서, ⌘N으로 만든 파일, Application Support의 북마크 JSON·스냅샷·`snippets.json`·`macros/macros.json`·`grammars/`, 환경설정)만 읽고 씀. 빠른 추가는 현재 문서 끝에 덧붙여 바로 저장 | 샌드박스는 아님. 전역 단축키는 Carbon `RegisterEventHotKey` 라 손쉬운 사용 권한이 필요 없고 다른 키 입력을 보지 않는다 |
| ✅ | **비밀 블록 마스킹** — 정보 문자열이 `secret` 로 시작하는 펜스 블록(```` ```secret 은행 ````)의 안쪽 줄을 편집기에서 가림막 + `••••••••` 로 그린다(펜스 줄은 보임, .txt 도 같은 규칙, 중첩은 CommonMark). 캐럿이 들어가면 그 블록만 드러나고 나가면 다시 가림. **비밀 드러내기 ⌥⌘S**(편집 메뉴)는 전부 드러냈다가 설정 시간(10/30/60초/안 함, 기본 30초) 뒤 자동으로 다시 가림, 상태바 `•••• N` / `REVEALED`. 찾기 결과 줄 텍스트·마크다운 미리보기·HTML/PDF 내보내기도 가린 텍스트, 아웃라인·타임라인은 비밀 줄을 건너뜀. 설정 › 비밀 에서 끌 수 있음. 파일에서 찾기·북마크 미리보기도 마스크, 앱 잠금 시 재마스킹 + 예약된 클립보드 소거 즉시, 종료 시 예약 소거 즉시, 비밀 복사에 `org.nspasteboard.ConcealedType` 표식. 표시만 가리며 파일·스냅샷은 평문(VoiceOver 는 읽음). 펜스는 왼쪽 여백에서 시작해야 함(목록·인용 안 미인식) | `SecretScanner`(HyperCore `Text/`) · `Editor/SecretController.swift`(`MaskedLayoutFragment`, FoldController 의 layout delegate 공용) · `SecretsUI.swift`. 가림막 폭 = 줄 폭(길이는 보임), 북마크 미리보기는 만들 때 가리기가 켜져 있어야 마스크, CR 전용 줄바꿈 파일은 블록 미인식, `--no-fold` 면 가림도 꺼짐 |
| ✅ | **클립보드 자동 소거** — 복사·잘라내기(멀티 커서·열 모드 포함) 범위가 비밀 줄과 겹치면 설정 지연(끔/10/30/60초, 기본 30초) 뒤 changeCount 가 그대로일 때만 비운다. 편집 › 클립보드 비우기 로 즉시. 출력 로그 "Clipboard cleared (secret)" | `HyperTextView.secretHitTest`(편집 전 판정) + `onDidCopySecret` → `SecretsStore.scheduleClipboardClear`. 드래그 페이스트보드는 대상 아님 |
| ✅ | **앱 잠금(Touch ID)** ⌃⌘L(앱 메뉴 Settings… 아래) — 창 전체(리본·사이드바·편집기·패널·상태바)를 테마 색 불투명 오버레이로 가리고 파일 이름도 보이지 않는다. "잠금 해제" 버튼(또는 Return / Space)으로 `LocalAuthentication` `.deviceOwnerAuthentication`(Touch ID → 실패/미지원 시 시스템 암호 폴백) 인증. 설정 › 앱 잠금: 열 때 요구(기본 꺼짐, 켜면 잠긴 채 시작·문서는 로드·자동 저장 계속) · 입력이 없으면 잠금(안 함/1/5/15/30분, 시작 옵션과 독립) · 잠자기/화면 잠금 시 잠금(기본 켜짐, 시작 옵션이 켜져 있을 때만). 잠긴 동안 키 입력은 버려지고(⌘Q·⌘H·⌥⌘H·⌘M·⌘W·⌃⌘F 만 통과) 메뉴는 열리자마자 닫히며(`NSMenu.didBeginTrackingNotification` → `cancelTracking`), 설정 창·시트·알림은 닫히고 편집기는 첫 응답자에서 내려오며(받아쓰기 차단) 접근성 트리에서도 숨겨지고, 드러낸 비밀은 다시 가려지고 예약된 클립보드 소거는 즉시 실행, 빠른 추가(전역 단축키 포함)는 패널 대신 해제 프롬프트(인증 중 요청은 큐). 자동화 실행은 시작 잠금을 하지 않음(`--locked` 로 강제) | `AppLock/AppLockController.swift`(상태 머신 · `Authenticator` 프로토콜로 셀프테스트가 성공/실패/취소 주입 · 유휴는 입력당 시각만 기록하는 로컬 모니터 + 한 번 울리는 타이머 · `NSWorkspace.willSleepNotification`/`screensDidSleepNotification` · 분산 알림 `com.apple.screenIsLocked`) · `LockOverlay.swift`(표식 NSView `applock.overlay`) · `AppLockUI.swift` · `AppLockSettings.swift`. SwiftUI 는 NSPrincipalClass 를 무시해 `sendAction` 가로채기가 불가능(실측) → 키 허용 목록 + 메뉴 추적 취소 방식. 화면 가림이지 파일 암호화가 아님 · 엔타이틀먼트 추가 없음. 셀프테스트는 실제 메뉴를 띄우지 않고(OS 전체 키보드를 가로챔) 알림만 흉내 냄 |

## J. 테마·외관

| 상태 | 기능 | 메모 |
|---|---|---|
| ✅ | **22종 테마**, `themes/palettes.json` 단일 소스 → 앱 테마 + Zed 테마 + 미리보기 HTML | 이름은 모두 `Hyper ` 접두사 |
| ✅ | **시스템 외형 따르기** 기본 — 라이트 Hyper Light / 다크 Hyper Dark. 직접 고르면 고정 | 레이아웃 탭·상태바·보기 메뉴의 테마 메뉴와 설정에서 켜고 끔. ⌥⌘] / ⌥⌘[ 순환 |
| ✅ | **리본 UI** — 홈(클립보드·찾기·삽입·모드·파일) / 편집(줄·대소문자·정렬·공백·열·멀티 커서·도구·매크로) / 레이아웃(테마·패널·접기·마크다운 미리보기·글꼴) / 고급(설정·스냅샷 폴더·다시 읽기·기본 문서) / 창(전체 화면·패널). 파일 탭 줄(연 파일마다 탭 + 새 문서·열기 버튼, 아래 '파일 탭' 행), 빠른 실행 저장·실행 취소·다시 실행. 창이 좁으면 작은 버튼이 아이콘만 남는 접힘 모드 | 비활성 자리표시자 없음 — 미구현 기능은 UI에 나타나지 않음 |
| ✅ | **상태바** — Ln / Col(+ 선택 길이, 문자 오프셋은 툴팁), 줄바꿈, 인코딩, COL, MD(미리보기 켜짐), 구문 언어(색이 꺼져 있으면 흐리게), 커서 수, 줄 수·크기, 상태, 테마(시스템 따르기 중이면 "· 시스템"), 확대 % | |
| ✅ | **폰트** — Fira Code(없으면 시스템 고정폭), 한글 폴백 D2Coding ×1.2로 2:1 폭, 리거처 토글, 줄 높이 | 설정 ⌘, · [fonts.md](fonts.md) |
| ✅ | **UI 언어** — 11개 언어(영어·한국어·중국어 간체·일본어·베트남어·힌디어·독일어·프랑스어·스페인어·포르투갈어·아랍어 — RTL 글; 실측상 창 구조(리본 그룹·사이드바·편집기·패널)는 좌→우 그대로이고 라벨·설정 행만 아랍어 읽기 방향을 따름), 기본은 시스템 언어. 설정(⌘,) › 언어 에서 선택 → "지금 재실행"(문서 저장 후 종료·재실행). 선택은 앱 도메인의 `AppleLanguages` 에 저장돼 시스템 설정 › 언어 및 지역 › 응용 프로그램 과 같은 값을 본다. 도움말 › 사용자 가이드 = 현재 언어의 `docs/guide/USER_GUIDE.<code>.md`. 첫 실행 환영문도 언어별(`Resources/Welcome/welcome.<code>.md`) | `AppLanguage`(Apps/mac) · 영어가 소스(카탈로그 키), 번역은 `l10n/ui.<code>.json` → `scripts/l10n-add.py` → 두 `Localizable.xcstrings`. `scripts/check-l10n.py`(CI)가 키 누락·자리표시자·리본 라벨 길이·언어 목록/가이드/환영문 일치를 검사. 미지원 언어(중국어 번체 등)는 영어로 폴백 |
| ✅ | **커서 스타일** — 설정 › 외형: 막대(기본)·블록(글자 칸을 커서색 α 0.55 로, 글자는 보임)·밑줄(칸 아래 2 pt), 깜빡임 끄기. 멀티 커서·열 모드(가상 공백) 보조 캐럿도 같은 스타일(깜빡임 없음). 2만 자 넘는 문단 안에서는 시스템 막대 캐럿으로 폴백. 줄 끝·빈 줄은 공백 한 칸, 한글·탭은 실제 폭. `--cursor` `--no-cursor-blink` | `HyperTextView` — macOS 14+ 는 머리 캐럿을 `NSTextInsertionIndicator` 가 그리고 `drawInsertionPoint` 를 부르지 않는다(실측) → 막대는 표시기(깜빡임 끄기 = `displayMode = .visible`), 블록·밑줄은 표시기를 `.hidden` 으로 두고 `drawBackground` 에서 그림(KVO 재적용은 다음 런루프 턴 — KVO 안에서 즉시 설정하면 재귀 크래시). 2만 자 초과 문단에서는 생략 |
| ✅ | **창 투명도·블러** — 설정 › 외형 슬라이더 50–100 %(기본 100), 보기 › 창 투명도 100/90/80/70 %. 창·편집기·거터·리본·탭 줄·사이드바·하단 패널·상태바·미리보기가 같은 α, 글자·아이콘·구분선은 불투명. "창 뒤 블러"(기본 꺼짐)는 투명도 < 1 일 때만. `--opacity` `--blur` | `WindowChromeView`(창 `isOpaque=false`, 블러 `NSVisualEffectView` .behindWindow). 표면당 한 겹만 α(겹치면 더 불투명). 미리보기는 WebKit `drawsBackground` SPI 가 있을 때만 투명 |
| 🔜 | 공백 문자 표시 | |

## K. 제외·보류

- 노트 분할·위키링크·그래프 뷰(Obsidian류): "한 파일에 append" 습관과 충돌 → 보류.
- 실시간 협업: 1인 사용 전제 → 제외.
- 구문 강조는 가벼운 토큰 규칙 + 줄별 진입 상태(블록 주석·여러 줄 문자열·펜스)로 구현(E 참조). 트리시터 같은 완전한 파서는 메모 파일 성능을 위해 하지 않는다.
- 클라우드 동기화·자체 서버: 로컬 전용으로 결정 → 보류.
