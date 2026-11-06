# 찾기 동작 모델 — UltraEdit 를 따라서

2026-11-06, 28 MB 로그에서 찾기 입력이 느리다는 보고 뒤 "실제 UltraEdit 의 로직을 조사해 따르라"는 요청으로 정리했다. UltraEdit 공식 wiki·파워 팁·체인지로그와 포럼(모더레이터 답변 스니펫)을 읽고 추론한 것이며, 확실하지 않은 항목은 (추정) 으로 표시한다.

## UltraEdit 이 하는 일

| 사용자 동작 | UltraEdit | 실제로 도는 작업 |
|---|---|---|
| Quick Find(Ctrl+F / Mac ⌘F) 입력창에 글자 입력 | 키마다 즉시 검색. 첫 매치 선택(캐럿부터, 끝이면 처음부터 — 추정), 나머지 전부 "Highlight all items" 색으로 강조, 상태바에 `Find "…" – N matches`. 리터럴(정규식·단어 단위·대소문자 옵션 없음 — 대소문자 무시는 추정). 히스토리에 저장하지 않음 | 전체 문서 스캔(강조·개수) + 첫 매치 선택. 긴 작업은 Esc 로 취소(v26.20) |
| Enter | 다음 매치로. 포커스는 Quick Find 에 남아 반복 가능. 문자열을 히스토리에 저장 | 캐럿 기준 증분 이동 |
| Ctrl+Enter(이전) | 이전 매치 | 역방향 증분. 2024.3 부터 Find 대화상자 안에서는 Shift+Enter 가 이전 |
| Esc | Quick Find 닫힘. "All match highlighting is cleared … The active match selection remains" | 강조 세트 폐기 |
| F3 / Ctrl+F3 (Mac ⌘G / ⇧⌘G) | 마지막 검색(Quick Find 또는 Find 대화상자)을 캐럿부터 앞/뒤로 반복, 끝에서 wrap("Continue find at end of file" 기본 on) | 증분, 전체 재스캔 없음 |
| Find 대화상자(Alt+F3 / Mac ⌘F3) | Match case · Match whole word · Regular expressions(Perl/Unix/UltraEdit) · In column · 선택 영역 · Highlight all items found(기본 off, sticky) · List lines containing string · Count all · Close after find · Filter lines | Next 를 누를 때 1회 |
| List lines containing string | Next 한 번에 전체 파일 스캔 → "Find String List" 창(줄 텍스트, 선택적 줄 번호, 더블클릭/Enter/Goto 로 이동, Bookmark all, Copy, Refresh List) | 전체 스캔 1회, 정적 스냅샷. 편집해도 자동 갱신 없음(수동 Refresh List). 결과 수 제한 없음(빈번한 문자열은 비권장) |
| Highlight all items found | Next 때 문서 전체 강조, 검색 뒤 유지(persistent 설정). Esc(v26+) 또는 View › Highlight all selected(Ctrl+.)로 해제 | 전체 스캔 1회. 2026.1: 편집 뒤에도 강조가 자리를 따라감 |
| 문서 편집(결과 표시 중) | 자동 재스캔 없음. Quick Find 가 열려 있으면 다음 입력에서 재검색(추정) | — |
| 대용량 파일 | 임계값(파워 팁의 예시 50 MB — 기본값은 미기재)을 넘는 파일은 임시 파일 없이 열고, 줄 번호·접기·구문 색·LCI 를 끄도록 권고(설정 목록). 포럼 권고: 빈번한 문자열에 List lines 비권장, Replace All 은 Replace in Files 로 | — |

## HyperEdit 에 옮긴 것

| 동작 | HyperEdit (v0.9.0) | 비고 |
|---|---|---|
| 입력창에 글자 입력 | 150 ms 디바운스 뒤 검색(백그라운드, ASCII 빠른 경로) → 결과 목록·강조·개수 갱신, 앵커(⌘F 를 누르거나 입력을 시작할 때의 캐럿) 뒤 첫 매치를 선택(`EditorCommand.selectMatch`: 포커스는 입력창에, 찾기 풍선 없음). 입력창은 `FindFields` 라 글자마다 창 전체가 다시 평가되지 않는다 | UltraEdit 은 디바운스 없이 즉시·동기. 우리는 백그라운드 + 취소라 입력이 끊기지 않는다. 옵션(Aa·W·.*)은 Quick Find 에도 적용(UltraEdit 은 Quick Find 에서 무시) |
| Enter | 결과가 지금 검색어의 것이면(`hitsQuery`) 다음 매치, 아니면 검색 뒤 첫 매치. 포커스 유지 | `submitFind()` |
| ⇧Enter | 이전 매치 | `.onKeyPress(.return)` 의 shift 판정 |
| Esc | 패널 닫기 + 결과·강조 제거, 선택 유지 | `closeQuickFind()` |
| F3 / ⇧F3 | 캐럿부터 다음/이전, 끝에서 처음으로. 결과가 없거나 지금 입력창의 검색어가 아니면(`hitsQuery`) 먼저 검색하고 첫 매치로 | 결과 목록을 재사용(증분 스캔 아님 — 목록이 이미 있다) |
| 결과 목록 | 패널의 NSTableView — UltraEdit 의 Find String List 에 해당. 클릭으로 이동, 현재 행 강조 | 상한 10,000 건 |
| 문서 편집 | 1.2 s 뒤 조용한 재검색(발행은 바뀐 것이 있을 때만, 강조는 편집을 따라감) | UltraEdit 은 정적 — 우리는 싸게 만들었으므로 유지 |
| 대용량 | 6,400만 자(UTF-16 단위, ASCII 기준 약 64 MB)를 넘는 문서는 입력 중 스캔 없이 Enter 때만 | UltraEdit 대용량 파일 권고와 같은 취지 |

## 출처

- 공식 wiki: https://wiki.ultraedit.com/Quick_find · https://wiki.ultraedit.com/Find · https://wiki.ultraedit.com/Find_next · https://wiki.ultraedit.com/Find_previous · https://wiki.ultraedit.com/Find_string_list · https://wiki.ultraedit.com/Find_in_files · https://wiki.ultraedit.com/Keyboard_shortcuts · https://wiki.ultraedit.com/Settings:Search:Miscellaneous · https://wiki.ultraedit.com/Settings:Search:Advanced · https://wiki.ultraedit.com/Handle_large_files · https://wiki.ultraedit.com/Status_bar
- 파워 팁·블로그: https://www.ultraedit.com/support/tutorials-power-tips/ultraedit/find-replace/ · https://www.ultraedit.com/support/tutorials-power-tips/ultraedit/incremental-search/ · https://www.ultraedit.com/support/tutorials-power-tips/ultraedit/list-lines-containing-string/ · https://www.ultraedit.com/support/tutorials-power-tips/ultraedit/large-file-handling/ · https://www.ultraedit.com/support/tutorials-power-tips/ultraedit/mac-keyboard-shortcuts/ · https://www.ultraedit.com/blog/master-ultraedits-flexible-search-functions/ · https://www.ultraedit.com/products/ultraedit/latest-changes/ · https://www.ultraedit.com/products/mac-text-editor/latest-changes/
- 포럼(스니펫): https://forums.ultraedit.com/quick-find-versus-find-and-how-to-customize-the-us-t14793.html · https://forums.ultraedit.com/find-next-f3-not-working-with-last-quick-find-sear-t14790.html · https://forums.ultraedit.com/quick-find-backwards-with-keystrokes-t17957.html · https://forums.ultraedit.com/turning-off-clear-highlighting-left-over-from-high-t14761.html · https://forums.ultraedit.com/list-lines-containing-string-enhancements-t2775.html · https://forums.ultraedit.com/how-to-prevent-wrap-on-a-find-t15820.html
