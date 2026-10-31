# Changelog

모든 변경은 [Conventional Commits](https://www.conventionalcommits.org/ko/) 기반으로 semantic-release가 자동 생성합니다.

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
