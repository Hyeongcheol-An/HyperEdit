<p align="center"><img src="docs/screenshots/app-icon-1024.png" width="120" alt="HyperEdit 앱 아이콘"></p>

<h1 align="center">HyperEdit</h1>

<p align="center"><b>계속 길어지는 메모 파일 하나를 위한, 빠른 리본 스타일 macOS 텍스트 에디터.</b></p>

<p align="center">
<a href="https://github.com/Hyeongcheol-An/HyperEdit/releases"><img alt="Release" src="https://img.shields.io/github/v/release/Hyeongcheol-An/HyperEdit?sort=semver"></a>
<a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/github/license/Hyeongcheol-An/HyperEdit"></a>
<a href="https://github.com/Hyeongcheol-An/HyperEdit/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/Hyeongcheol-An/HyperEdit/ci.yml?branch=main&label=CI"></a>
<img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-black">
</p>

<p align="center"><a href="README.md">English</a> · 한국어</p>

HyperEdit는 메모·로그·코드 조각이 수만 줄 쌓인 텍스트 파일 하나를 하루 종일 끝에 덧붙이고 검색하며 쓰는 사람을 위한 에디터입니다. SwiftUI 셸 안에 TextKit 2 기반 AppKit `NSTextView`를 넣어 수 MB 파일도 작은 파일처럼 타이핑되고, 창 구성은 고전적인 리본 에디터의 레이아웃 — 리본 탭, 문서 탭 줄, 사이드바, 하단 패널, 빽빽한 상태바 — 을 따릅니다.

| Hyper Light | Hyper Dark |
|---|---|
| ![Hyper Light 테마의 HyperEdit](docs/screenshots/hyperedit-light.png) | ![Hyper Dark 테마의 HyperEdit](docs/screenshots/hyperedit-dark.png) |

## 설치

**요구 사항:** macOS 15 (Sequoia) 이상. 유니버설 바이너리(Apple Silicon·Intel).

**Homebrew**

```sh
brew tap Hyeongcheol-An/tap
brew install --cask hyperedit
```

Homebrew 7에서는 먼저 tap 을 신뢰하라고 물을 수 있습니다: `brew trust Hyeongcheol-An/tap`.

**DMG**

[GitHub Releases](https://github.com/Hyeongcheol-An/HyperEdit/releases)에서 `HyperEdit-x.y.z.dmg`를 내려받아 열고 `HyperEdit.app`을 `Applications`로 드래그합니다. Developer ID로 서명·공증된 빌드라 Gatekeeper 경고 없이 바로 열립니다. 내려받은 파일을 검증하려면 `SHA256SUMS`를 DMG 옆에 두고 실행하세요.

```sh
shasum -a 256 -c SHA256SUMS
```

### 첫 실행

HyperEdit는 `~/Documents/HyperEdit/notes.md`를 엽니다. 파일이 없으면 짧은 환영 문서로 새로 만듭니다. ⌘N으로 이름과 폴더를 골라 빈 텍스트 파일을 새로 만들 수 있고, ⌘O로 다른 텍스트 파일을 열 수 있으며, 마지막으로 연 파일은 다음 실행 때 기억됩니다. 바이너리 파일(이미지·PDF·압축 파일 등)은 에디터로 불러오지 않고 기본 앱으로 엽니다.

> UI는 영어와 한국어를 지원하며 시스템 언어를 따릅니다. 리본 구성과 단축키는 모든 시스템에서 같습니다 — 다른 언어 번역 기여를 환영합니다(`Apps/mac/Localizable.xcstrings`).

## 기능

### 편집기
- 큰 파일에 맞춘 성능: 1.3 MB / 34,000줄 파일에서 키 입력당 약 3 ms, 뷰포트 기반 TextKit 2 레이아웃.
- 줄 번호 거터, 현재 줄 강조, 자동 줄바꿈(⌥Z), 줄 번호 표시(⌥⌘L), 확대/축소(⌘= / ⌘- / ⌘0).
- 파일별로 마지막 캐럿·스크롤 위치 복원. ⌃⌘E로 문서 끝으로, ⌘L로 줄 이동.
- F7은 `## 2026-10-30 (금) 14:05` 같은 타임스탬프 헤딩을 삽입합니다. 요일은 시스템 로케일을 따릅니다(영어 환경이면 `(Fri)`).
- **구문 색(⌃⌘H)** — 파일 확장자로 언어를 고르고 상태바에 표시합니다. 메모·마크다운은 일부러 가벼운 규칙만 — URL, ISO 날짜·시각, `#` 헤딩, `[제목]` 줄, 목록 기호와 `[ ]` / `[x]` 체크박스, `#태그`, `키:` 라벨, `**굵게**`, `` `코드` ``, `⇒ → ->` 화살표 — 를 칠하고, 코드 20여 종(Swift, Python, JavaScript/TypeScript, JSON, 셸, YAML, HTML/XML, CSS, C/C++/Objective-C, Go, Rust, SQL, Ruby, Java/Kotlin, TOML, INI)은 주석·문자열·숫자·키워드·함수·타입 이름을 칠합니다. 색은 테마의 `syntax` 팔레트에서 오고 TextKit 2 렌더링 속성으로 보이는 줄에만 입히므로 파일·undo·타이핑 속도에 영향이 없습니다. 줄 단위 토큰화라 여러 줄에 걸친 블록 주석·문자열은 시작한 줄만 칠해집니다.

### 마크다운 미리보기
- **⇧⌘P**로 편집기를 분할하면 현재 파일을 GFM으로 렌더링한 화면이 오른쪽에 나타납니다(헤딩, 목록과 체크리스트, 표, 코드 블록, 인용, 링크, 이미지). 색은 현재 테마에서 가져오고, 본문은 시스템 글꼴, 코드는 편집기와 같은 고정폭 글꼴을 씁니다.
- 미리보기는 편집기의 스크롤 위치를 따라가고, 입력이 멈추고 300 ms 뒤 다시 렌더링하되 보던 위치를 유지합니다. 링크는 기본 브라우저로 열리고, 원문의 HTML은 실행하지 않고 글자로 보여 주며, 상대 경로 이미지는 파일이 있는 폴더 기준으로 찾습니다. 2 MB가 넘는 파일은 미리보기 대신 안내 문구만 표시합니다.
- 렌더링에는 Apple의 [swift-markdown](https://github.com/swiftlang/swift-markdown)(Apache-2.0)을 씁니다. 미리보기가 켜져 있으면 상태바에 **MD**가 표시됩니다.

### 리본과 패널
- 리본 탭 **홈 / 편집 / 레이아웃 / 고급 / 창**, 새 문서(⌘N)·열기(⌘O) 버튼이 있는 문서 탭 줄, 빠른 실행 저장 / 실행 취소 / 다시 실행.
- **사이드바(⌘1)** — **파일**(현재 파일 폴더의 트리, 한 번 클릭으로 열기), **아웃라인**(⌘3: `##` 헤딩, `[제목]` 줄, `가./나.` 항목, `1)` 번호 항목. 필터 상자와 현재 항목 강조. 코드 주석처럼 보이는 `# …` 줄은 제외), **타임라인**(⌘4: `## YYYY-MM-DD (요일) HH:MM` 타임스탬프 헤딩과 날짜로 시작하는 느슨한 줄을 월별로 묶어 최신순 표시).
- **하단 패널(⌘2)** — **찾기 결과**, **북마크**, **출력** 로그.

### 찾기·바꾸기·북마크
- **찾기(⌘F):** 검색어를 입력하고 Enter를 누르면 모든 매치가 줄 번호와 함께 나열되고, 목록이 열려 있는 동안 편집기 안의 매치도 강조됩니다. 정규식 `.*`, 대소문자 `Aa`, 단어 단위 `W` 토글. F3 / ⇧F3으로 매치 이동, ⌥⌘A로 모든 매치를 멀티 커서로 전환.
- **바꾸기(⌘R):** 현재 매치 바꾸기 / 모두 바꾸기, `$1` 같은 정규식 템플릿 지원. 모두 바꾸기는 ⌘Z 한 번으로 되돌립니다.
- **파일에서 찾기(⇧⌘F):** 폴더를 고르고 `*.md;*.txt` 같은 마스크를 지정합니다. 바이너리 파일은 건너뛰고, 결과를 클릭하면 해당 줄로 엽니다.
- **북마크:** ⌘F2 토글, F2 / ⌥F2 다음 / 이전, 이름은 선택. 북마크는 편집을 따라갑니다 — 위에 줄을 넣거나 지우면 함께 움직이고, 북마크한 줄을 지우면 사라지며, 실행 취소·다시 실행도 따라옵니다. `~/Library/Application Support/HyperEdit/bookmarks/`에 문서별로 저장되므로 문서 옆에는 아무 파일도 만들지 않습니다. 예전 버전이 문서 옆에 만든 `.<파일명>.bookmarks.json` 사이드카는 한 번 읽어 옮깁니다.

### 열 모드와 멀티 커서
- **열 모드(⌥C):** ⌥-드래그 또는 ⇧+방향키로 사각형을 선택하면 입력·삭제가 모든 줄에 적용됩니다. 짧은 줄은 가상 공백으로 채워지고, 복사·붙여넣기는 줄 단위로 동작하며, **숫자 채우기(⌥⌘N)**로 순번을 넣습니다.
- **멀티 커서:** ⌘-클릭으로 커서 추가, ⌘D로 선택과 같은 문자열의 다음 등장 추가, ⌥⌘A로 모든 검색 매치 선택. 모든 멀티 편집은 실행 취소 한 단계입니다.

### 텍스트 도구(편집 탭과 "줄" 메뉴)
줄 삭제 ⇧⌘K · 줄 복제 ⇧⌘D · 위/아래 이동 ⌥↑ / ⌥↓ · 줄 합치기 ⇧⌘J · 역순 · 줄 번호 붙이기 · 오름차순 / 내림차순 / 숫자 정렬 · 중복 줄 제거 · 빈 줄 제거 · 뒤 공백 / 앞뒤 공백 제거 · 탭 → 공백 · 공백 → 탭 · 대문자 / 소문자 / 첫 글자 대문자 / 대소문자 반전.

- **계산(⌃⌘=):** 선택 영역, 없으면 현재 줄(`=`이 있으면 마지막 `=` 뒤)을 계산해 줄 끝에 ` ⇒ 결과`를 붙입니다 — `3+0.5+0.25`는 `3+0.5+0.25 ⇒ 3.75`가 되고, 수식을 고친 뒤 다시 실행하면 옛 결과를 바꿉니다. 산술식만: `+ - * / % ^`, 괄호, `1,234` / `1_000` 숫자, `sqrt abs round floor ceil min max`, `pi`·`e`. 수식이 아니면 출력 패널에 알리고 텍스트는 그대로 둡니다.
- **열 맞춤(⌃⌘T):** 탭으로 구분된 열(선택한 줄, 없으면 캐럿 주변의 탭 줄 묶음)을 공백으로 채워 모든 열이 같은 표시 열에서 시작하게 합니다. 한글·CJK는 두 칸으로 셉니다. 줄마다 `|`가 있으면 마크다운 표로 보고 ` | ` 안을 채우며, `---` 줄은 다시 그리고 `--:` 열은 오른쪽 정렬합니다.

### 저장
- 입력이 멈추고 2초 뒤 자동 저장. 종료·창 닫기·파일 전환 시에는 동기로 저장하므로 2초 사이의 편집이 사라지지 않습니다. 모든 쓰기는 원자적입니다.
- 세션마다 첫 저장 전에 스냅샷 사본을 `~/Library/Application Support/HyperEdit/snapshots`에 남깁니다. 파일별로 최신 20개를 유지하고 90일이 지난 것은 지웁니다.
- 외부 변경을 감지합니다. 버퍼가 깨끗하면 다시 읽고(캐럿 위치는 유지), 수정 중이면 외부본을 스냅샷으로 보관한 뒤 경고합니다.
- 빈 버퍼를 내용이 있는 파일 위에 덮어쓰지 않습니다.
- 인코딩은 UTF-8 → EUC-KR(CP949) → CP1252 → Latin-1 순으로 손실 없이 판별해 상태바에 표시하고, 저장할 때도 같은 인코딩을 씁니다(UTF-8 BOM 보존). 원 인코딩으로 표현할 수 없는 문자를 입력하면 UTF-8로 저장하고 상태바에 알립니다. 어느 인코딩으로도 읽을 수 없는 파일은 망가뜨리지 않도록 아예 열지 않습니다.
- 상태바에 Ln / Col(선택 중이면 선택 길이, 문자 오프셋은 툴팁), 줄바꿈 종류(UNIX / DOS / MAC), 파일 인코딩, COL 표시, 커서 수, 줄 수 · 크기, 상태 메시지, 구문 언어(구문 색이 꺼져 있으면 흐리게), 테마 선택(시스템 따르기 중이면 "· 시스템" 표시), 확대 비율이 표시됩니다.

## 단축키

| 단축키 | 동작 | 단축키 | 동작 |
|---|---|---|---|
| ⌘N | 새 문서 | ⌘O | 열기 |
| ⌘S | 저장 | ⌘F | 찾기 |
| ⌘R | 바꾸기 | ⇧⌘F | 파일에서 찾기 |
| F3 / ⇧F3 | 다음 / 이전 매치 | ⌘L | 줄로 이동 |
| ⌃⌘E | 문서 끝으로 | ⌥C | 열 모드 |
| ⌘D | 다음 매치 추가 | ⌥⌘A | 매치 모두 선택 |
| ⌥⌘N | 숫자 채우기 | F7 | 타임스탬프 삽입 |
| ⌘F2 | 북마크 토글 | F2 / ⌥F2 | 다음 / 이전 북마크 |
| ⇧⌘K | 줄 삭제 | ⇧⌘D | 줄 복제 |
| ⌥↑ / ⌥↓ | 줄 위 / 아래로 이동 | ⇧⌘J | 줄 합치기 |
| ⌃⌘= | 계산(⇒ 결과 붙이기) | ⌃⌘T | 열 맞춤 |
| ⌘1 | 사이드바 | ⌘2 | 하단 패널 |
| ⌘3 | 아웃라인 | ⌘4 | 타임라인 |
| ⌥⌘L | 줄 번호 | ⌥Z | 자동 줄바꿈 |
| ⌥⌘] / ⌥⌘[ | 다음 / 이전 테마 | ⌘= / ⌘- / ⌘0 | 확대 / 축소 / 기본 |
| ⌘, | 설정 | ⇧⌘P | 마크다운 미리보기 |
| ⌃⌘H | 구문 색 | | |

## 테마

22개 팔레트가 [`themes/palettes.json`](themes/palettes.json) 한 곳에 정의되어 앱 테마와 [Zed](https://zed.dev) 테마를 함께 만듭니다. 기본값은 시스템 외형 따르기 — 라이트 모드면 **Hyper Light**, 다크 모드면 **Hyper Dark** 입니다. 테마를 직접 고르면(레이아웃 탭, 상태바 메뉴, 보기 메뉴, ⌥⌘] / ⌥⌘[) 그 테마로 고정되고, 같은 세 메뉴와 설정(⌘,)에서 "시스템 외형 따르기"를 다시 켤 수 있습니다.

| 라이트 (5) | 다크 (17) |
|---|---|
| Hyper Light · Hyper Gruvbox Light · Hyper Solarized Light · Hyper Catppuccin Latte · Hyper GitHub Light | Hyper Dark · Hyper Homebrew Terminal · Hyper Green Blue Contrast · Hyper Xcode High Contrast Dark · Hyper One Dark · Hyper Dracula · Hyper Gruvbox Dark · Hyper Solarized Dark · Hyper Nord · Hyper Catppuccin Mocha · Hyper Tokyo Night · Hyper GitHub Dark · Hyper Monokai · Hyper Night Owl · Hyper Rosé Pine · Hyper Everforest Dark · Hyper Ayu Mirage |

전체 미리보기는 [`docs/theme-preview.html`](docs/theme-preview.html)에 있습니다. **Zed:** 같은 팔레트가 `themes/dist/hyperedit-themes.json`으로 내보내지며 모든 릴리스에도 첨부됩니다. `python3 themes/build_zed_theme.py --install`로 설치한 뒤 ⌘K ⌘T에서 `Hyper …` 테마를 고르세요. 자세한 내용은 [docs/zed.md](docs/zed.md).

## 폰트와 한글

HyperEdit는 **Fira Code**가 설치되어 있으면 그것을, 없으면 시스템 고정폭 폰트를 씁니다. 한글은 별도의 폴백 폰트 — 설치되어 있으면 기본 **D2Coding** — 로 ×1.2 배율로 그려, 한글 한 글자가 정확히 영문 두 칸 폭이 되게 합니다. 덕분에 탭으로 맞춘 표가 어긋나지 않습니다. 리거처, 줄 높이, 두 폰트 패밀리, 한글 배율은 모두 설정(⌘,)에 있습니다. 자세한 내용과 대안: [docs/fonts.md](docs/fonts.md).

## 소스에서 빌드

macOS 15의 Xcode 16 이상과 [XcodeGen](https://github.com/yonaskolb/XcodeGen)이 필요합니다.

```sh
brew install xcodegen
scripts/bootstrap.sh                                   # HyperEdit.xcodeproj 생성 (git 제외)
scripts/build-mac.sh --run                             # Release 빌드 후 실행 (첫 빌드는 swift-markdown 을 내려받음)
scripts/build-mac.sh Debug --run --file path/to/file   # Debug 는 큰 파일에서 눈에 띄게 느림
swift test --package-path Packages/HyperCore           # 엔진 단위 테스트
scripts/install-mac.sh --open                          # ~/Applications 에 설치
scripts/make-dmg.sh                                    # DMG (+ 자격 증명이 있으면 서명·공증·스테이플)
```

서명 기본값은 Xcode의 "Sign to Run Locally"라 Apple 팀 없이도 빌드·실행할 수 있습니다. 본인 팀으로 서명하려면 `Config/Local.xcconfig.example`을 `Config/Local.xcconfig`(git 제외)로 복사해 팀 ID를 채우세요. `scripts/make-dmg.sh`는 Developer ID 인증서와 공증 자격 증명이 있으면 자동으로 서명·공증하며, `scripts/setup-signing.sh`가 그 설정을 도와줍니다.

### 개발용 실행 인자

스크린샷·자동화·디버깅에 씁니다. `open -n HyperEdit.app --args …` 또는 `scripts/build-mac.sh --run …` 뒤에 붙입니다.

| 인자 | 효과 |
|---|---|
| `--file <path>` | 기억된 파일 대신 이 파일을 연다 |
| `--snapshot <png> [--snapshot-delay s] [--quit]` | ScreenCaptureKit으로 창을 PNG로 캡처(화면 녹화 권한 필요) |
| `--selftest [--selftest-out <txt>] [--quit]` | 임시 파일에서 내장 셀프테스트 실행. 사용자 문서는 건드리지 않음 |
| `--theme <id>` | `palettes.json`의 팔레트 id로 시작, 예: `hyper-dark` |
| `--ribbon <home\|edit\|layout\|advanced\|window>` | 리본 탭 선택 |
| `--left <files\|outline\|timeline>` · `--bottom <find\|bookmarks\|output>` | 사이드바 / 하단 패널 탭 표시 |
| `--search <text>` · `--replace [--replace-with <text>]` · `--find-in-files` | 찾기 창 미리 채우기 |
| `--column` · `--goto <line>` · `--preview` | 열 모드 켜기 / 줄로 이동 / 마크다운 미리보기 표시 |
| `--no-highlight` | 구문 색을 끈 채 시작 (스크린샷 비교용) |
| `--debug-perf [--debug-perf-log <path>]` | 구간 시간과 120 ms 이상 메인 스레드 정지 기록 |

## 저장소 구성

```
Apps/mac/            SwiftUI 셸: 리본, 패널, 설정, Editor/ 의 AppKit 편집기, Markdown/ 의 WKWebView 마크다운 미리보기
Packages/HyperCore/  엔진(문서, 검색, 텍스트 도구, 열 블록 수학, 아웃라인/타임라인, 테마, 폰트, 마크다운 → HTML) + 테스트
themes/              palettes.json(단일 소스), build_zed_theme.py, build_preview.py, validate.py, dist/
docs/                features.md · fonts.md · zed.md · design.ko.md · theme-preview.html · screenshots/ · sample/
scripts/             bootstrap · build-mac · install-mac · make-dmg · make-icon.swift · set-version · setup-signing · update-cask · check-sensitive · install-hooks
Config/              Version.xcconfig(semantic-release 가 관리) · Signing.xcconfig 기본값 · Local.xcconfig.example
.github/workflows/   ci.yml(테마, 민감 정보 검사, commitlint, macOS 빌드+테스트) · release.yml(semantic-release → DMG → GitHub Release → Homebrew cask)
```

`HyperCore`는 플랫폼 중립(macOS 15 / iOS 18 타깃 선언)이지만, 현재는 macOS 앱만 있습니다.

## 릴리스 과정

커밋은 [Conventional Commits](https://www.conventionalcommits.org/ko/)를 따릅니다(제목은 한국어·영어 모두 가능). `main`에 push될 때마다 [semantic-release](https://semantic-release.gitbook.io)가 커밋으로 다음 버전을 계산하고 `CHANGELOG.md`·`VERSION`·`Config/Version.xcconfig`를 갱신한 뒤, DMG를 빌드·서명·공증하고, `SHA256SUMS`와 Zed 테마 파일을 첨부한 GitHub Release를 만들고, `Hyeongcheol-An/homebrew-tap`의 Homebrew cask를 갱신합니다. `feat:` → 마이너, `fix:` / `perf:` → 패치, `docs:` / `chore:` / `refactor:` → 릴리스 없음. 워크플로는 Developer ID·공증 시크릿이 없으면 릴리스를 만들지 않습니다(포크는 저장소 변수 `ALLOW_UNSIGNED_RELEASE=true`로 서명 없는 빌드를 허용할 수 있습니다). 로컬 커밋 메시지 훅은 `scripts/install-hooks.sh`로 설치합니다.

## 로드맵과 제한

- UI는 영어·한국어(시스템 언어를 따름). 다른 언어는 아직 없습니다.
- 구문 색은 줄 단위라 여러 줄에 걸친 주석·문자열은 시작한 줄만 칠해지고, 사용자 정의 문법은 없습니다. 마크다운 미리보기(⇧⌘P)는 현재 파일을 렌더링해 보여 주는 보기 전용 화면입니다.
- 로컬 파일만 다룹니다. 클라우드 동기화 없음. 엔진은 iOS를 염두에 두고 만들었지만 iOS 앱은 아직 없습니다.
- 예정된 편집 도구 — 주석 토글, JSON 정리, 매크로, 분할 보기 — 는 로드맵에 있지만 아직 구현되지 않았습니다. 즉석 계산과 열 맞춤은 산술식과 탭 / 파이프 표에만 동작합니다(변수·단위·날짜 계산 없음).

설계 메모와 결정 이력은 [docs/design.ko.md](docs/design.ko.md)에, 상태가 표시된 기능 목록은 [docs/features.md](docs/features.md)에 있습니다.

## 기여와 보안

버그 신고와 아이디어는 [GitHub Issues](https://github.com/Hyeongcheol-An/HyperEdit/issues)와 [Discussions](https://github.com/Hyeongcheol-An/HyperEdit/discussions)로 보내 주세요. 개발 환경, 커밋 규약, PR 체크리스트는 [CONTRIBUTING.md](CONTRIBUTING.md)에, 취약점을 비공개로 신고하는 방법은 [SECURITY.md](SECURITY.md)에 있습니다. 이 프로젝트는 [Contributor Covenant](CODE_OF_CONDUCT.md)를 따릅니다.

## 상표 고지

HyperEdit의 레이아웃은 고전 UltraEdit 리본에서 영감을 받았습니다. UltraEdit는 IDM Computer Solutions, Inc.의 상표이며, HyperEdit는 IDM과 무관한 독립 오픈소스 프로젝트로 IDM의 보증을 받지 않았습니다.

## 라이선스

[MIT](LICENSE) © 2026 Hyeongcheol An

마크다운 미리보기는 [swift-markdown](https://github.com/swiftlang/swift-markdown)과 그 의존성 [swift-cmark](https://github.com/swiftlang/swift-cmark)(cmark-gfm)로 만들었습니다. 둘 다 © Apple Inc. 및 기여자, [Apache License 2.0](https://github.com/swiftlang/swift-markdown/blob/main/LICENSE.txt)이며, 빌드 시 Swift Package Manager가 내려받아 앱에 링크합니다.
