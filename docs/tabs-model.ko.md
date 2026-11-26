# 파일 탭 동작 모델 — UltraEdit 를 따라서

2026-11-06 사용자 요청("상단에 탭을 여러 개 띄울 수 있어야 하지 않나 — 이전과 동일하게 UltraEdit 과 동일하게 개편할 것")으로 UltraEdit 의 파일 탭 바를 조사해 옮겼다. 출처는 공식 wiki·파워 팁·체인지로그와 포럼 스니펫이며 확실하지 않은 것은 (추정) 으로 표시한다.

## UltraEdit 이 하는 일

| 항목 | UltraEdit (Windows · Mac) |
|---|---|
| 탭 | 열린 파일당 탭 하나, 편집 영역 위. 파일명 + 상태 아이콘(수정됨·저장됨·읽기 전용; 아이콘을 끄면 `*`). 활성 탭은 굵게(추정). 툴팁에 전체 경로·크기·생성·수정 시각. 폭은 이름 길이에 맞춤 |
| 넘칠 때 | 한 줄 스크롤(양끝 화살표) / 한 줄 + 오른쪽 ▾ 파일 목록 / 여러 줄 중 선택. 28.20 부터 휠 스크롤 |
| 새 탭 위치 | 맨 끝 (`Sort tabs on file open` 이 켜져 있으면 정렬) |
| 새 문서 | Ctrl+N / ⌘N → "Edit1", "Edit2"… 이름 없는 문서. 탭 바 빈 곳 더블클릭도 새 파일. 별도 "+" 버튼 없음 |
| 열기 | 이미 열린 파일을 다시 열면 기존 탭 활성화(Mac 2025.0 개선). Finder 드래그 앤 드롭 |
| 닫기 | Windows Ctrl+F4 · Mac ⌘W, 모두 닫기 ⇧⌘W. 탭의 ×, **더블클릭**, **가운데 클릭**(둘 다 기본 켜짐). 닫은 뒤 포커스는 설정(`After current tab is closed, move to`, 기본 왼쪽 이웃 — 추정). File 메뉴 Close all / Close all except, 탭 메뉴 Close all to left/right(v24), Open last-closed tab(v28), Save and Close(v28). 미저장이면 저장 여부를 묻는다. 마지막 탭을 닫으면 빈 편집 영역(추정) |
| 전환 | Windows Ctrl+F6 / Ctrl+Shift+F6 = 최근 활성 순서(MRU), Alt+↓ / Alt+↑ = 탭 순서, v26 부터 Ctrl+Tab 재매핑 가능. Mac: Alt+↓ 다음 창, Alt+↑ / ⇧⌘[ 이전 창, ⌘⌃Tab 이전 활성 문서, ⌃⇧Tab 다음 활성 문서. Window 목록 대화상자 |
| 순서 | 드래그로 이동. 메뉴 Sort tabs by Name / Extension / Path / Modification date(v27), Mac 2025.0 Sort File Tabs |
| 우클릭 | Close all to left/right · Open last-closed tab · Save and Close · Rename(이름 없는 탭) · Compare · Add to Favorite/Project · Revert to saved · File tabs ▸ (Dockable / 한 줄·▾·여러 줄 / Sort / Show tooltips / Tabs at bottom) · Customize |
| 세션 | `Reload files previously open on startup`: 종료 때 경로 저장 → 재시작 때 다시 연다. `Remember and reload unsaved changes` 는 미저장 내용까지 복원. 커서 위치는 종료 때 열려 있던 파일만 복원. 2026.1 탭 순서 유지 |
| 분할 | Split window(한 탭 안 2뷰), Duplicate window(같은 파일을 `name:2` 새 탭으로) |

## HyperEdit 에 옮긴 것 (v0.10.0)

**구조:** 탭은 열린 파일의 경로 목록(`AppModel.tabs`)이고 살아 있는 문서 객체(`MemoDocument` + `NSTextStorage`)는 하나다. 탭을 바꾸면 그 문서가 파일을 갈아탄다(`MemoDocument.switchTo`: 떠나는 파일의 미저장 편집을 동기로 저장 → 새 파일을 읽어 같은 스토리지에 넣는다). 처음에는 탭마다 문서·스토리지를 따로 두고 `NSTextContentStorage.textStorage` 를 갈아끼웠는데, TextKit 2 레이아웃이 퇴화해 "-[NSTextView layout] failed to converge after 5 iterations" 뒤 몇 분 만에 화면 갱신 중 충돌했다(2026-11-24 셀프테스트). 그래서 UltraEdit 과 달리 다른 탭의 내용은 메모리에 없고, 실행 취소 기록은 탭을 떠나면 비워지며, 수정됨 표시는 활성 탭에만 있다.

| 동작 | HyperEdit | 비고 |
|---|---|---|
| 탭 | 열린 파일(`AppModel.tabs`)마다 탭. 아이콘 · 파일명(활성은 굵게, 240 pt 를 넘는 긴 이름은 가운데를 줄임) · 수정됨 점(강조색, 활성 탭만) 또는 × (활성·마우스 올린 탭). 툴팁: 전체 경로 · 크기 · 수정 시각 | 상태 아이콘 대신 점 하나. 다른 탭은 떠날 때 저장되므로 수정됨 상태가 없다 |
| 넘칠 때 | 탭이 다 들어가면 + · 폴더 버튼이 마지막 탭 바로 뒤에 붙는다. 넘치면 가로 스크롤(전환·정렬·이동·닫기 뒤에도 활성 탭이 보이게 따라감) + 오른쪽 끝 ▾ 열린 탭 목록(탭이 둘 이상일 때) | 여러 줄 모드 없음 |
| 새 탭 | 맨 끝. `open(url:)` 이 이미 열린 파일이면 그 탭 활성화. 밖에서 연 파일 — Finder '다음으로 열기', Dock 아이콘에 끌어다 놓기, `open -a HyperEdit <파일>`, 실행 인자 — 도 같은 창의 탭으로 연다(`ExternalOpen` → `AppModel.openExternal`): 여러 개면 파일마다 탭을 만들고 마지막 것을 보이며, 이미 열린 파일이면 그 탭으로 가고, 보고 있는 파일이면 다시 읽지 않는다. 폴더·없는 경로·텍스트가 아닌 파일은 열지 않고 출력 패널에 적는다. 잠금 중·시트나 모달 패널이 떠 있는 동안·매크로 재생 중·빠른 추가 패널에 쓰던 메모가 있는 동안에는 미뤘다가 연다(빈 빠른 추가 패널은 미루지 않는다) | v0.10.7 까지는 받는 곳이 없어, 켜져 있는 앱에 Finder 로 파일을 넘기면 그 파일은 열리지 않고 같은 문서를 보이는 창이 하나 더 생겼다(SwiftUI `WindowGroup` 이 열기 이벤트마다 창을 만든다 → `.handlesExternalEvents(matching: [])`). 창은 하나다 |
| 새 문서 | ⌘N · 탭 줄 + · 빈 탭 줄 더블클릭 → 저장 패널에서 이름·위치를 고르면 빈 파일을 만들어 탭으로 | 자동 저장 문서라 이름 없는 "Edit1" 대신 파일 |
| 닫기 | ⌘W · × · 더블클릭 · 가운데 클릭. 더블클릭은 첫 클릭에 그 탭으로 전환한 뒤 두 번째 클릭에 닫는다(한 번 클릭이 더블클릭 판정을 기다리지 않게 — UltraEdit 도 누른 탭이 먼저 활성화된다). 보고 있지 않던 탭을 더블클릭해 닫으면 왼쪽 이웃이 아니라 **보고 있던 탭**으로 돌아온다(`AppModel.tabDoubleClicked` — 그 탭으로 전환한 클릭과 닫는 클릭의 이벤트 시각이 더블클릭 간격 안일 때만; 한참 보던 탭을 더블클릭하면 평소대로 왼쪽 이웃). 미저장 편집은 동기로 저장하고 닫는다(묻지 않음 — 자동 저장 문서). 저장이 실패하면(쓰기 불가 폴더·가득 찬 디스크) 메모리의 내용을 스냅샷 폴더에 비상 사본으로 남기고 출력 패널에 경로를 적은 뒤 떠나고, 비상 사본도 못 쓰면 **전환·닫기를 거절**해 그 탭에 머문다(`MemoDocument.lastLeaveOutcome`). 활성 탭을 닫으면 **왼쪽 이웃**. ⇧⌘W 모두 닫기. 마지막 탭을 닫으면 기본 문서(`~/Documents/HyperEdit/notes.md`)가 대신 열린다; 마지막 탭이 기본 문서면 ⌘W 는 창을 닫는다. 파일이 밖에서 지워진 탭은 누르면 걷어낸다(빈 파일을 만들지 않는다) | 편집기는 항상 문서를 하나 든다 |
| 전환 | ⇧⌘] / ⇧⌘[ 탭 순서(끝에서 순환), ⌃Tab 직전에 보던 탭(최근 활성 순서 — 두 탭 사이를 오간다), ⌃⇧Tab 이전 탭, 클릭, ▾ 목록 | ⌘1·⌘2 는 사이드바·패널이라 번호 단축키 없음 |
| 순서 | 드래그로 이동(놓은 탭 자리로). 우클릭 Sort Tabs ▸ 이름 / 경로 / 확장자 / 수정일 | |
| 우클릭 | Close Tab · Close Other Tabs · Close Tabs to the Left/Right · Close All Tabs · Reopen Last Closed Tab(⇧⌘T, 최근 10개) · Save · Save and Close · Revert to Saved · Copy Path · Reveal in Finder · Sort Tabs | |
| 세션 | 열린 탭 경로 목록(`ui.openDocuments`)과 마지막 파일을 저장. 복원은 앞에서 30개까지(`maxRestoredDocuments`; 마지막에 보던 파일이 그 밖이면 덧붙인다), 없어진 파일·텍스트가 아닌 파일은 건너뛴다. 다음 실행 때 탭을 만들어 두고 내용은 탭을 누를 때 읽는다. 캐럿·스크롤은 파일별 보기 상태로 복원 — 떠날 때 화면 맨 위에 있던 문단이 같은 높이에 오게(캐럿이 화면 밖이었으면 밖에 둔 채) | 미저장 내용 복원은 필요 없다(자동 저장) |
| 접기 | 탭을 오가도 파일별 접힘이 유지된다(실행 중에만 — 떠날 때 적어 두고 돌아와 영역 스캔 뒤 같은 자리를 다시 접는다). 북마크는 파일별 JSON(기존) | 세션에는 저장하지 않는다 |
| 분할 | 기존 분할 편집(⌘\\)은 같은 문서의 두 뷰 — 탭을 바꾸면 둘 다 따라간다. 접힘도 문서 단위라 두 뷰가 같이 쓴다(한쪽에서 접으면 양쪽이 접힌다) | Duplicate window 없음 |

## 출처

- 공식 wiki: https://wiki.ultraedit.com/File_tabs · https://wiki.ultraedit.com/Settings:Application_layout:File_tabs:Miscellaneous · https://wiki.ultraedit.com/Settings:Application_layout:File_tabs:Operation · https://wiki.ultraedit.com/Settings:Application_layout:File_tabs:Colors · https://wiki.ultraedit.com/Settings:File_handling:Session_options · https://wiki.ultraedit.com/Settings:File_handling:Miscellaneous · https://wiki.ultraedit.com/Keyboard_shortcuts · https://wiki.ultraedit.com/Category:Window_tab · https://wiki.ultraedit.com/Windows · https://wiki.ultraedit.com/Split_window · https://wiki.ultraedit.com/Duplicate_window · https://wiki.ultraedit.com/Category:File_menu
- 파워 팁·블로그·체인지로그: https://www.ultraedit.com/support/tutorials-power-tips/ultraedit/file-tabs/ · https://www.ultraedit.com/support/tutorials-power-tips/ultraedit/mac-keyboard-shortcuts/ · https://www.ultraedit.com/support/tutorials-power-tips/ultraedit/vertical-horizontal-split-editing/ · https://www.ultraedit.com/products/mac-text-editor/latest-changes/ · https://www.ultraedit.com/blog/new-release-ultraedit-2025-0-macos-linux/ · https://www.ultraedit.com/products/mac-text-editor/features/
- 포럼(스니펫): https://forums.ultraedit.com/file-modified-red-dot-t17356.html · https://forums.ultraedit.com/status-icons-on-open-file-tabs-t10838.html · https://forums.ultraedit.com/how-do-you-make-it-so-opening-a-new-file-tab-alway-t18810.html · https://forums.ultraedit.com/configure-default-new-file-name-t16435.html · https://forums.ultraedit.com/navigation-between-different-file-tabs-t2382.html · https://forums.ultraedit.com/how-to-remember-previous-caret-position-t15443.html · https://forums.ultraedit.com/which-methods-exist-to-close-a-file-and-to-close-u-t16394.html
