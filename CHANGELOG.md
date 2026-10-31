# Changelog

모든 변경은 [Conventional Commits](https://www.conventionalcommits.org/ko/) 기반으로 semantic-release가 자동 생성합니다.

## [0.6.0](https://github.com/Hyeongcheol-An/HyperEdit/compare/v0.5.1...v0.6.0) (2026-10-31)

### ✨ 기능

* **app:** --ephemeral 실행 인자 — 수동 테스트가 사용자 설정을 건드리지 않게 ([43ca05f](https://github.com/Hyeongcheol-An/HyperEdit/commit/43ca05f066b943ee2eb0152b7e164949cd0d9a0e))
* **app:** --ephemeral 실행 인자 — 수동 테스트가 사용자 설정을 건드리지 않게 ([a97fb17](https://github.com/Hyeongcheol-An/HyperEdit/commit/a97fb17779412377d6afcee487b133fe8c00f85f))
* **app:** --ephemeral 실행 인자 — 수동 테스트가 사용자 설정을 건드리지 않게 ([935e86a](https://github.com/Hyeongcheol-An/HyperEdit/commit/935e86ac81083c989c4e1a3a905ac18bc2b3c545))
* **app:** --ephemeral 실행 인자 — 수동 테스트가 사용자 설정을 건드리지 않게 ([1c5c186](https://github.com/Hyeongcheol-An/HyperEdit/commit/1c5c1864f971b94bc811483aab8fbf02775daa91))
* **app:** --ephemeral 실행 인자 — 수동 테스트가 사용자 설정을 건드리지 않게 ([2b22590](https://github.com/Hyeongcheol-An/HyperEdit/commit/2b22590b646c51ae50b8858ebabdb4083c5c1952))
* **bench:** 성능 벤치마크 하네스 — --bench 모드, scripts/bench.sh, docs/performance.md ([8a09a2e](https://github.com/Hyeongcheol-An/HyperEdit/commit/8a09a2e8921922b3056a586c4032660502892a1a))
* **core:** FoldScanner — 들여쓰기·마크다운 헤딩·괄호·펜스 접기 영역 스캐너 ([edf797c](https://github.com/Hyeongcheol-An/HyperEdit/commit/edf797c655247688ed36e2340a85a720913cadbf))
* **core:** 매크로 모델·저장소 — MacroStep/Macro Codable, 연속 입력 합치기, macros.json 저장소 ([47b0b55](https://github.com/Hyeongcheol-An/HyperEdit/commit/47b0b55bb015649ca2afdcb86bfba9b7b2431f87))
* **core:** 주석 토글·JSON 정리·스니펫 엔진 (HyperCore) + 단위 테스트 27개 ([0464da7](https://github.com/Hyeongcheol-An/HyperEdit/commit/0464da75553425c30c260f5db5c58892fb7a2ae2))
* **editor:** 분할 보기(⌘\)와 Quick Append 창(⇧⌘N · 전역 ⌃⌥N) ([cf39759](https://github.com/Hyeongcheol-An/HyperEdit/commit/cf3975998063bdf9352d531b35ab16664ddbf4af))
* **editor:** 접기(⌥⌘← / ⌥⌘→, 모두 ⌥⇧⌘← / →)·스크롤바 마커, undo/redo 편집 추적 보강 ([faac142](https://github.com/Hyeongcheol-An/HyperEdit/commit/faac14239048204d9a3ea125b27f6dea6962dd91))
* **editor:** 주석 토글 ⌘/ · JSON 정리 ⌃⌘J · 스니펫 ⇧⌘I/Tab 확장 ([19df15c](https://github.com/Hyeongcheol-An/HyperEdit/commit/19df15c97417f7c8ba7d98dd3a5eefc418178ee7))
* **macro:** 키 입력 매크로 기록·재생 — ⇧⌘M 기록/중지, ⌥⌘M 재생, 여러 번 재생, 이름 저장 ([31de6b5](https://github.com/Hyeongcheol-An/HyperEdit/commit/31de6b57b206a8e6a95d911bfc106d86009e0fec))
* **ribbon:** 그룹별 단계적 접힘 — 좁은 창에서 오른쪽 그룹부터 아이콘만 남긴다 · 레거시 스크롤러면 마커 띠를 스크롤러 왼쪽에 · 설정 창 높이 ([ee65a7f](https://github.com/Hyeongcheol-An/HyperEdit/commit/ee65a7fd234fcac08120e8514759a665745485f2))

### 🐛 수정

* **app:** 종료 시 저장 실패면 비상 사본을 남기고 확인 알림 · 분할 보관 한도 20 · CRLF 문서 Quick Append 줄바꿈 · 비활성 상태 전역 단축키로 패널 닫기 ([0d98f6e](https://github.com/Hyeongcheol-An/HyperEdit/commit/0d98f6e80831baa16f631a025c999750cd5ddcfd))
* **bench:** --strict 실패 시에도 Markdown 표를 쓰고 종료 코드를 돌려주도록 ([3c2fd74](https://github.com/Hyeongcheol-An/HyperEdit/commit/3c2fd74622d5ae803a46c73ae1fcccbb2dca27ad))
* **core:** 주석 토글이 CRLF 줄 끝의 \r 을 기호 밖에 두도록 ([25408aa](https://github.com/Hyeongcheol-An/HyperEdit/commit/25408aa955289f9ace0ab70a4498f5188a5e42d6))
* **document:** 저장이 끝나면 외부 변경 표시를 지운다 — 다음 편집에서 ⚠ 외부 변경 경고가 되살아나지 않도록 ([078fbd8](https://github.com/Hyeongcheol-An/HyperEdit/commit/078fbd8532029f8d8a04c15503479d6c5544f599))
* **document:** 텍스트 뷰를 거치지 않는 undo/redo 도 dirty·자동 저장·줄 인덱스 갱신을 걸도록 저장소 알림에서 처리 ([191adcf](https://github.com/Hyeongcheol-An/HyperEdit/commit/191adcfe60504a029ef4570a99da9007e795402b))
* **editor:** JSON 문법 오류처럼 아무것도 바꾸지 못한 텍스트 도구가 문서를 dirty 로 만들지 않도록 ([170a803](https://github.com/Hyeongcheol-An/HyperEdit/commit/170a803c2db9815d169288872fd09879874fbb48))
* **editor:** 거대 한 줄(2만 자↑)에서는 캐럿 사각형·가운데 정렬 계산을 건너뛴다 · JSON 한 줄로 결과가 매우 길면 경고 · 셀프테스트 타이밍 보강 ([53798a6](https://github.com/Hyeongcheol-An/HyperEdit/commit/53798a6a982d8fcb39e769257b064a3b4866196a))
* **editor:** 보관 뷰 알림 해제 범위 한정 · undo 뒤 didChangeText 복원 · 로드 직후 가짜 편집 무시 ([991cd91](https://github.com/Hyeongcheol-An/HyperEdit/commit/991cd91ba20f4c8c2b3391a19832951851c85db4))
* **editor:** 분할 보기에서 보조 편집기의 모두 바꾸기를 되돌릴 때 북마크가 두 번 밀리던 문제 ([2c4d293](https://github.com/Hyeongcheol-An/HyperEdit/commit/2c4d293f8a90c2100879b4271dc811d9d015b66b))
* **editor:** 분할을 닫은 뷰의 편집 관찰자·접기/마커 구독을 끊어 편집 속도 유지 · 파일 전환 직후 dirty 회귀 수정 · HyperTextView deinit 병합 ([98b1e69](https://github.com/Hyeongcheol-An/HyperEdit/commit/98b1e6929faf116af66fa1e56389e2e8eeb8cf93))
* **editor:** 코드 리뷰 반영 — 마지막 매크로 기록은 메모리에만, perform 의 중복 dirty 호출 제거, undo/redo 시 스니펫 세션 종료, 좌우 분할 최소 창 폭 1180 ([ec57d53](https://github.com/Hyeongcheol-An/HyperEdit/commit/ec57d5376399a8f972a05e88e479d22c16548210))
* **fold:** 점프 목적지가 접힌 안이면 먼저 펼치고, EOF 까지 닿는 접힘에서 캐럿이 숨은 끝에 남지 않게 ([d761d60](https://github.com/Hyeongcheol-An/HyperEdit/commit/d761d60433abfd09ba7aad377ae12f47a504ed2a))
* **json:** 중첩 깊이 512 제한 — 수만 단계 중첩 입력의 스택 오버플로 크래시를 문법 오류로 보고 ([e8fa284](https://github.com/Hyeongcheol-An/HyperEdit/commit/e8fa2849fa78d86d23150042a9d17333c526a7bb))
* **l10n:** v0.6 신규 한국어 문자열 용어 통일 — 필터·스크롤바 마커·분할 해제 ([245bac1](https://github.com/Hyeongcheol-An/HyperEdit/commit/245bac10dd2c4f8715907d9398ed6a3bf82e7d12))
* **macro:** N번 재생 횟수에 천 단위 쉼표 허용 · 매크로 파일 다시 읽기의 경로 비교를 심볼릭 링크 풀어서 ([b32d2f0](https://github.com/Hyeongcheol-An/HyperEdit/commit/b32d2f0941224013ddc157b26a05774443251705))
* **macro:** 재생 중 키·마우스 입력을 버려 열어 둔 undo 그룹이 닫히지 않게 ([abdf63b](https://github.com/Hyeongcheol-An/HyperEdit/commit/abdf63b592c784efaf979b4381eba91f63760f80))
* **ribbon:** 레이아웃 탭 그룹 제목이 잘리던 문제 — 스크롤 마커 토글을 접기 그룹으로 ([1fbfb53](https://github.com/Hyeongcheol-An/HyperEdit/commit/1fbfb53c6c9c3db8ca32d695410353f313bc4b35))
* **ribbon:** 레이아웃 탭 필요 폭 1195 로 실측 갱신, 접기 셀프테스트의 모두 접기 기대값 보정 ([3a44c5c](https://github.com/Hyeongcheol-An/HyperEdit/commit/3a44c5ce8b02c9419ee34a49fe45bf9597f835ef))
* **ribbon:** 삽입 그룹의 스니펫·Quick Append 버튼을 한 스택으로 (병합 보정) ([af319fd](https://github.com/Hyeongcheol-An/HyperEdit/commit/af319fdd2a4a0ecf63dbc2807d26b4b9664d84eb))
* **ribbon:** 스크롤바 마커 토글 제목을 보기 메뉴와 같은 'Scrollbar Markers' 로 통일 ([189a14b](https://github.com/Hyeongcheol-An/HyperEdit/commit/189a14bfee4039029ee5e7d2845c0464b6b6349c))
* **snippets:** ${clipboard} 를 쓰는 스니펫만 클립보드를 읽고 기본 스니펫 상수를 nonisolated 로 ([225ed9d](https://github.com/Hyeongcheol-An/HyperEdit/commit/225ed9dfcfc85f275dfffd9575ca133fd9c61212))
* **snippets:** 손으로 쓴 snippets.json 에서 title 생략 허용 ([0e20c0f](https://github.com/Hyeongcheol-An/HyperEdit/commit/0e20c0f62665f0aa070373709849b4e9d9aa4c00))
* **ui:** 레이아웃 탭 그룹 제목 잘림 수정, Quick Append 문구, 스니펫 선택창 빈 상태, 아이콘 중복 정리 ([b02ddf8](https://github.com/Hyeongcheol-An/HyperEdit/commit/b02ddf82c209b84321cddf4ca509440748040393))

### ⚡ 성능

* **core:** 줄 인덱스 증분 갱신 · 폰트 목록 캐시 · 키 입력마다 발행되던 isDirty 제거 ([0761dbc](https://github.com/Hyeongcheol-An/HyperEdit/commit/0761dbc7824bfce849bfac53ef6064dee1b53a9c))
* **editor:** 모두 바꾸기 undo 일괄 처리 · 검색/아웃라인 패널의 키 입력마다 재평가 제거 ([36b76d9](https://github.com/Hyeongcheol-An/HyperEdit/commit/36b76d932035c08526196ed84f9a90c14c6ef1a6))
* **gutter:** 전체 속성 재적용 직후 거터가 문서 전체를 배치하며 열거하던 회귀 수정 (8 MB 테마 전환 18.7 s → 0.26 s) ([ec001d2](https://github.com/Hyeongcheol-An/HyperEdit/commit/ec001d2cd350a3c61dab10dd43083fc7f19ea23f))

### 📝 문서

* **bench:** 잠정 기준선(baseline-0.5.1.json)과 측정 표 · 후속 권고 5건 · Bench 경고 수정 ([3b04db2](https://github.com/Hyeongcheol-An/HyperEdit/commit/3b04db2fa3bbe37d859aa67c156535c3f3ff343c))
* **macro:** 매크로 기능 설명·단축키 표 (README 영/한, features.md D 편집 ✅) ([02afb61](https://github.com/Hyeongcheol-An/HyperEdit/commit/02afb61113099703a74436773f3f96137bd1cbdc))
* **screenshots:** README 다크 스크린샷을 v0.6 UI 로 교체 — 레이아웃 탭(접기·분할·스크롤 마커), 접힌 영역 표식 ([44dd9b5](https://github.com/Hyeongcheol-An/HyperEdit/commit/44dd9b5a59e7cd309f99f4b6e653c5719919c5b0))
* **screenshots:** README 라이트 스크린샷 v0.6 교체 (스니펫·빠른 추가·접기 화살표·스크롤바 마커) ([0121e2d](https://github.com/Hyeongcheol-An/HyperEdit/commit/0121e2d39bec8462b5e2334c8f8b60e1c99f9f31))
* v0.6 문서 정합성 — README 영/한 1:1, 실행 인자 표, 로드맵·제한, 설계 이력, CONTRIBUTING·SECURITY, 릴리스 노트 초안 ([c3a86c5](https://github.com/Hyeongcheol-An/HyperEdit/commit/c3a86c5b5685d47d714d96e2849a403d690b898e))
* 벤치 기준선 파일명 참조 갱신 (baseline-0.6.0.json) ([b5c7262](https://github.com/Hyeongcheol-An/HyperEdit/commit/b5c726234221bca6c3afc73ffb6fc2fbccae882b))
* 접기·스크롤바 마커 기능 문서화 (features.md ✅, README 단축키·기능·실행 인자) ([0268841](https://github.com/Hyeongcheol-An/HyperEdit/commit/02688414bbbb225a1f4a40f779447558ffcc29c7))
* 테스트 수 갱신 (단위 196 · 셀프테스트 393) ([a9a28f8](https://github.com/Hyeongcheol-An/HyperEdit/commit/a9a28f8fb12a92ab46797251c65c1e2c9cd0d841))

## [0.5.1](https://github.com/Hyeongcheol-An/HyperEdit/compare/v0.5.0...v0.5.1) (2026-10-31)

### 🐛 수정

* **l10n:** v0.5 신규 문자열 19키의 한국어 번역 카탈로그 커밋 누락 수정 ([8619ad6](https://github.com/Hyeongcheol-An/HyperEdit/commit/8619ad60ca71474281c4ae9db52df0df87cbfd15))

## [0.5.0](https://github.com/Hyeongcheol-An/HyperEdit/compare/v0.4.0...v0.5.0) (2026-10-31)

### ✨ 기능

* **editor:** 구문 하이라이트 — 노트/마크다운 라이트 규칙 + 코드 20종, TextKit 2 렌더링 속성 (⌃⌘H) ([03dc5fe](https://github.com/Hyeongcheol-An/HyperEdit/commit/03dc5fec40339995b114850c21b50b7b6d8577b5))
* **editor:** 구문 하이라이트 병합 — 메모/마크다운 라이트 규칙 + 코드 21종, TextKit 2 렌더링 속성 (⌃⌘H) ([6c13db7](https://github.com/Hyeongcheol-An/HyperEdit/commit/6c13db77ed1a74affcaaf3005809452b47e15805))
* **editor:** 북마크 줄 추적, 즉석 계산(⌃⌘=), 열 맞춤(⌃⌘T) ([c5ba3c6](https://github.com/Hyeongcheol-An/HyperEdit/commit/c5ba3c6715ac1d94f1bceca819e590ec1b73eb31))
* **editor:** 북마크 줄 추적, 즉석 계산(⌃⌘=), 열 맞춤(⌃⌘T) 병합 ([4783b90](https://github.com/Hyeongcheol-An/HyperEdit/commit/4783b90fa0546e564a3ecd241f99d99cc4fac567))
* **markdown:** 분할 미리보기 — swift-markdown 렌더, 테마 CSS, 스크롤 동기화 (⇧⌘P) ([a1ed999](https://github.com/Hyeongcheol-An/HyperEdit/commit/a1ed99943f9e14f8357b453826f1c2feb6496044))
* **markdown:** 분할 미리보기 병합 — swift-markdown 0.9 렌더, 테마 CSS, 편집기→미리보기 스크롤 동기화 (⇧⌘P) ([b9fef2a](https://github.com/Hyeongcheol-An/HyperEdit/commit/b9fef2a6a374b6ac420cab9aa711b13087998a1e))
* **ribbon:** 좁은 창에서 리본 접힘 — 작은 버튼을 아이콘만 표시, 제목은 툴팁으로 ([1ef6800](https://github.com/Hyeongcheol-An/HyperEdit/commit/1ef6800f9fdcb45027a437b7e4147f2f96ae587d))

### 🐛 수정

* **ribbon:** 탭별 필요 폭을 실측값으로 갱신 (편집 1520 · 레이아웃 920) ([b71c73c](https://github.com/Hyeongcheol-An/HyperEdit/commit/b71c73cad8966e75cef3d094aa7a162dfbb09b33))

### 📝 문서

* **contributing:** 로컬라이즈 절차와 scripts/l10n-add.py(한국어 번역 카탈로그 추가 도우미) ([05e0f07](https://github.com/Hyeongcheol-An/HyperEdit/commit/05e0f07a7349dd857e44d75655b20cabbdca0b42))
* **screenshots:** v0.5 UI 로 교체 — 구문 색, 마크다운 미리보기, 타임라인 ([a205a96](https://github.com/Hyeongcheol-An/HyperEdit/commit/a205a96b08c792635610d02a5f26d85ce1659ff4))

## [0.4.0](https://github.com/Hyeongcheol-An/HyperEdit/compare/v0.3.1...v0.4.0) (2026-10-31)

### ✨ 기능

* **l10n:** UI 를 영어 원본 + 한국어 번역(String Catalog)으로 전환 ([fce8641](https://github.com/Hyeongcheol-An/HyperEdit/commit/fce86417ae9f3eac2a3e4f49b94ff681f1ee48b0))
* **l10n:** UI 문자열을 영어 소스 + 한국어 String Catalog 번역으로 전환 ([06fad1f](https://github.com/Hyeongcheol-An/HyperEdit/commit/06fad1fac6d876fc5c885d45a85c413c87e8c266))

### 📝 문서

* **screenshots:** README 스크린샷을 영어 UI 로 교체 (Hyper Light / Hyper Dark) ([5a21b9d](https://github.com/Hyeongcheol-An/HyperEdit/commit/5a21b9dec7d3ff1bb1d28e7c98ca75a128c2d606))

## [0.3.1](https://github.com/Hyeongcheol-An/HyperEdit/compare/v0.3.0...v0.3.1) (2026-10-31)

### 🐛 수정

* **release:** conventionalcommits 프리셋을 writer 8 호환 버전(^8)으로 고정 ([81a6efc](https://github.com/Hyeongcheol-An/HyperEdit/commit/81a6efce1791ca861a23357108c9ac7721b6dfd1))
* **search:** 편집 후 검색 결과 자동 갱신, 파일 검색 취소 전파, 테마 대비 린트 ([aef70ee](https://github.com/Hyeongcheol-An/HyperEdit/commit/aef70eef91e175e6b83900707b9436ce827ac779))

## [0.3.0](https://github.com/Hyeongcheol-An/HyperEdit/compare/v0.2.3...v0.3.0) (2026-10-31)

### ✨ 기능

* HyperEdit — macOS 리본형 텍스트 에디터 공개 첫 버전 ([6ad172b](https://github.com/Hyeongcheol-An/HyperEdit/commit/6ad172b829d4224bdaab7afe73e7b6073bb0cdc0))

> 0.3.0 이전(비공개 개발 기간, 2026-10-30)의 이력은 2026-10-31 공개 전환 때 정리했습니다.
