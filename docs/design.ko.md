# HyperEdit 설계와 결정 이력

> HyperEdit가 왜 이런 모양인지, 무엇을 어떤 이유로 결정했는지, 그 과정에서 배운 기술적 사실은 무엇인지 기록하는 문서입니다. 사용법은 [README.ko.md](../README.ko.md), 기능 목록과 상태는 [features.md](features.md), 폰트는 [fonts.md](fonts.md), Zed 테마는 [zed.md](zed.md)를 보세요.

## 1. 한 문장 요약

**계속 길어지는 메모 파일 하나(수만 줄)를 끝에 덧붙이고 검색하는 습관을 그대로 살리면서, 고전 리본 에디터의 편집 도구(열 모드·북마크·검색 결과 창·텍스트 도구)와 현대 에디터의 가벼움을 macOS 네이티브로 구현한다.**

| 항목 | 현재 |
|---|---|
| 플랫폼 | macOS 15+ (유니버설). 엔진은 iOS 18 타깃도 선언하지만 iOS 앱은 아직 없음 |
| 스택 | Swift 6 툴체인 · Swift 5 언어 모드 · SwiftUI 셸 + AppKit `NSTextView`(TextKit 2) · 공유 패키지 `HyperCore` |
| 데이터 | 로컬 일반 텍스트 파일(UTF-8·EUC-KR·CP1252·Latin-1 무손실 판별). 파생 데이터는 Application Support 아래의 북마크 JSON과 스냅샷 사본뿐 |
| 동기화 | 없음(로컬 전용). iCloud 연동은 보류 (§7) |
| 테마 | 22종, `themes/palettes.json` 단일 소스 → 앱 테마 + Zed 테마. 이름은 모두 `Hyper ` 접두사, 기본값은 시스템 외형을 따르는 **Hyper Light / Hyper Dark** |
| UI | 고전 UltraEdit 리본 레이아웃에서 영감(리본 탭·그룹, 문서 탭, 사이드바, 하단 패널, 상태바). UltraEdit는 IDM Computer Solutions의 상표이며 HyperEdit는 무관한 독립 프로젝트 |
| 배포 | GitHub Releases DMG(Developer ID 서명·공증) + Homebrew tap. MIT 라이선스 |

## 2. 문제 정의

- 대상 문서는 "한 파일에 계속 append" 하는 메모다. 수만 줄, 1 MB 이상, 코드·로그·한글 메모·URL이 섞여 있고 마크다운 구조는 거의 없다. `#`으로 시작하는 줄은 헤딩보다 파이썬 주석일 때가 더 많다.
- 그런 파일에서 필요한 것은 ① 키 입력 지연이 없는 편집, ② 즉시 응답하는 검색과 결과 목록, ③ 구조 없는 텍스트에 사후적으로 구조를 부여하는 탐색(아웃라인·타임라인·북마크), ④ 표 형태 텍스트를 다루는 열 모드와 줄 단위 텍스트 도구다.
- 기존 도구는 각각 일부만 충족했다. 범용 코드 에디터는 가볍지만 북마크 패널·열 모드 숫자 채우기 같은 도구가 없고, 리본 에디터는 도구는 풍부하지만 macOS 네이티브가 아니거나 큰 파일에서 무겁다.

## 3. 확정 결정

| 영역 | 결정 | 근거 | 시점 |
|---|---|---|---|
| 기술 스택 | Swift / SwiftUI 네이티브, 편집 뷰는 AppKit `NSTextView`(TextKit 2) | TextKit 2의 뷰포트 레이아웃이 대용량에 유리, iOS 공유 가능, 외부 런타임 없음 | 2026-10-30 |
| 데이터 모델 | 단일 일반 텍스트 파일. 인덱스·DB를 두지 않고 메모리 내 정규식 검색 | 1~2 MB는 수십 ms에 검색된다. 파일이 그대로라 grep·git·다른 에디터와 호환 | 2026-10-30 |
| 계승할 편집 도구 | 열 모드 · 북마크 패널 · 검색 결과 패널 · 텍스트 도구 전부 | 프로젝트의 존재 이유 | 2026-10-30 |
| UI 구조 | 리본(홈·편집·레이아웃·고급·창) → 문서 탭 → [사이드바 \| 편집기 / 하단 패널] → 상태바. 기본 배치는 좌 파일 트리·하단 찾기 결과 | 익숙한 구조를 그대로, 색만 테마로 | 2026-10-30 |
| 타임스탬프 | F7 → `## 2026-10-30 (금) 14:05`, 요일은 로케일 | 날짜 구분 줄이 생기면 타임라인이 공짜로 생긴다 | 2026-10-30 |
| 시작 위치 | 파일별 마지막 캐럿·스크롤 위치 복원(기록 없으면 끝) | append 습관 | 2026-10-30 |
| 폰트 | Fira Code + 한글 폴백 D2Coding, 한글 런 ×1.2 배율로 2:1 폭 정렬 | 리거처 유지 + 탭 표 정렬 (fonts.md) | 2026-10-30 |
| 테마 엔진 | `palettes.json` 한 곳에서 앱 테마와 Zed 테마를 생성, CI가 생성물 drift 검사 | 색을 한 번만 고치면 두 환경이 같이 바뀐다 | 2026-10-30 |
| 저장 안전장치 | 2초 자동 저장, 원자적 쓰기, 세션 첫 저장 전 스냅샷, 빈 버퍼 저장 차단, 외부 변경 감지 | 메모 파일은 백업이 없는 경우가 많다 | 2026-10-30 |
| 동기화 | iCloud 연동 **보류**, 로컬 파일만 | 범위를 좁혀 에디터 품질에 집중. v0.2.3에서 iCloud 보조 코드 제거 | 2026-10-30 |
| 바이너리 파일 | 에디터로 열지 않고 기본 앱으로 넘김 (확장자 + 앞 8 KB NUL 검사) | PDF·이미지를 본문에 올리면 TextKit 레이아웃에 수 초 걸림 | 2026-10-30 |
| 이름·라이선스 | 프로젝트명 **HyperEdit**, 오픈소스 **MIT**, 저장소 공개 | 상표 문제 없는 고유 이름, 커뮤니티 기여 가능 | 2026-10-31 |
| 테마 이름·기본값 | 모든 테마 `Hyper ` 접두사. 기본은 시스템 외형 따르기 — 라이트 **Hyper Light**, 다크 **Hyper Dark**. 직접 고르면 고정 | 첫 실행 경험이 시스템과 어울려야 한다 | 2026-10-31 |
| 기본 문서 | `~/Documents/HyperEdit/notes.md`, 없으면 영·한 환영 문서 생성. `--file` → 마지막 파일 → 기본 문서 순 | 첫 실행에 빈 화면을 보여주지 않는다 | 2026-10-31 |
| 배포 채널 | GitHub Releases DMG + Homebrew cask(`Hyeongcheol-An/homebrew-tap`), 릴리스마다 자동 갱신 | `brew install --cask hyperedit` 한 줄 | 2026-10-31 |
| 문서·UI 언어 | 영어 `README.md`가 1차, `README.ko.md`는 완역. UI는 영어가 소스(카탈로그 키)이고 한국어는 `Localizable.xcstrings` 번역 — 시스템 언어를 따름. `scripts/check-l10n.py`가 CI에서 키 누락을 검사 | 오픈소스 공개 | 2026-10-31 |
| 동기 저장 | 종료·창 닫기·파일 전환 시 직렬 쓰기 큐에서 동기 저장 | 2초 자동 저장 창에서의 편집 손실 제거 | 2026-10-31 |
| 인코딩 | UTF-8 → EUC-KR(CP949) → CP1252 → Latin-1 순 무손실 디코딩, 같은 인코딩으로 저장(BOM 보존), 표현 불가 문자는 UTF-8 변환, 판별 불가 파일은 열지 않음 | 옛 EUC-KR 메모를 손실 디코딩 뒤 자동 저장으로 망가뜨리지 않는다 | 2026-10-31 |
| 북마크 저장 위치 | `~/Library/Application Support/HyperEdit/bookmarks/<경로 해시>.json`. 옛 사이드카는 1회 읽어 이전, 쓰지 않음 | 문서 폴더에 숨김 파일을 만들지 않고 읽기 전용 볼륨도 북마크 가능 | 2026-10-31 |
| 스냅샷 보관 | 파일별 최신 20개 + 90일 | 무한 증가 방지 | 2026-10-31 |
| 리본 정리 | 코딩(Coding) 리본 탭과 비활성 자리표시자 제거, 용어를 사이드바·하단 패널·파일로 통일, ⌘N 새 문서 | UI에 "예정"을 보여주지 않는다 | 2026-10-31 |

## 4. 아키텍처

```
HyperEdit/
├─ Packages/HyperCore/            Swift Package (macOS·iOS 공유), 단위 테스트 10개 스위트
│  ├─ Document/   MemoDocument(인코딩 판별·유지, 자동 저장 + 동기 저장, 스냅샷·보관 정책, 외부 변경 감지, 제자리 파일 전환)
│  │              MemoLocation(기본 문서·마지막 파일 결정) · TextFileDetector · ViewStateStore(파일별 위치)
│  ├─ Text/       LineIndex(줄↔오프셋) · TextTools(정렬·중복 제거·케이스·공백·탭…) · Timestamp · ColumnBlock(열 블록 수학)
│  ├─ Search/     SearchEngine(정규식·치환 템플릿) · FileSearch(폴더 검색·마스크·바이너리 제외)
│  ├─ Navigation/ BookmarkStore(Application Support JSON, 옛 사이드카 1회 이전) · OutlineScanner(아웃라인·타임라인 추출)
│  ├─ Font/       FontCascade(폰트 설정·캐스케이드) · HangulFontFixer(한글 런 2:1 보정)
│  └─ Theme/      palettes.json 디코더 → Theme(색 토큰) · ThemeStore(선택·시스템 따르기)
├─ Apps/mac/                      SwiftUI 셸
│  ├─ HyperEditApp.swift          메뉴·단축키 · AppDelegate(창 복구, --snapshot)
│  ├─ AppModel.swift              @MainActor 상태 모델, 실행 인자, 검색·바꾸기·북마크 명령
│  ├─ Editor/                     HyperTextView(TextKit 2 NSTextView: 멀티 커서·열 블록) · GutterView · EditorView(NSViewRepresentable)
│  ├─ Ribbon/ · Panels/           리본 5탭 · 사이드바(파일·아웃라인·타임라인) · 하단 패널(찾기 결과·북마크·출력)
│  └─ SelfTest.swift · Perf.swift 셀프테스트 · 성능 계측
├─ themes/                        palettes.json · build_zed_theme.py · build_preview.py · validate.py · dist/hyperedit-themes.json
├─ docs/                          이 문서 · features.md · fonts.md · zed.md · theme-preview.html · screenshots/ · sample/
├─ scripts/                       bootstrap · build-mac · install-mac · make-dmg · make-icon.swift · set-version · setup-signing · update-cask · check-sensitive · install-hooks
├─ Config/                        Version.xcconfig(semantic-release 갱신) · Signing.xcconfig(로컬 실행 기본) · Local.xcconfig.example
├─ project.yml                    XcodeGen 정의 → HyperEdit.xcodeproj (git 제외)
└─ .github/workflows/             ci.yml · release.yml · release-tag.yml
```

### 4.1 상태 흐름

- `AppModel`(메인 액터)이 UI 상태와 명령을 들고, 편집기에는 `PassthroughSubject<EditorCommand>`로 명령을 보낸다. 문서 상태(`MemoDocument`)는 AppModel을 거치지 않고 필요한 뷰가 직접 `@ObservedObject`로 구독한다.
- 키 입력마다 바뀌는 캐럿 정보는 `EditorCaret`라는 별도 객체로 발행한다. 상태바·아웃라인·타임라인만 구독하고 리본·패널은 다시 그려지지 않는다.
- 무거운 작업(검색, 줄 인덱스 재계산, 아웃라인 스캔, 파일 쓰기)은 텍스트의 불변 사본을 들고 `Task.detached`에서 돌린 뒤 결과만 메인 액터로 돌아온다.

### 4.2 문서와 저장

- `MemoDocument`가 `NSTextStorage`를 직접 소유해 텍스트 뷰와 공유한다(MB 단위 문자열 복사 회피).
- 저장: 입력이 멈추고 2초 뒤 자동 저장. 모든 디스크 쓰기는 하나의 직렬 큐를 지나며, 종료(`applicationShouldTerminate`)·창 닫기·파일 전환 시에는 `saveSynchronously()`로 같은 큐에서 동기 저장하므로 2초 창에서의 손실이 없다. 불변 사본을 원자적으로 쓴다. 세션 첫 저장 전 `~/Library/Application Support/HyperEdit/snapshots/<파일명>-<시각>-before-first-save.txt` 사본을 남기고, 스냅샷을 만들 때마다 파일별 최신 20개·90일 보관 정책으로 정리한다. 빈 버퍼를 내용이 있던 파일 위에 쓰려 하면 차단하고 상태바에 알린다.
- 인코딩: UTF-8(BOM은 떼어 기억) → EUC-KR(CP949) → CP1252 → Latin-1 순으로 **손실 없이** 디코딩되는 것을 고르고 저장도 같은 인코딩으로 한다. 원 인코딩에 없는 문자(예: EUC-KR 파일의 이모지)가 생기면 UTF-8로 변환 저장하고 상태바에 알린다. 어느 인코딩으로도 읽을 수 없는 데이터는 열지 않는다 — 손실 디코딩 뒤 자동 저장하면 파일이 망가지기 때문이다.
- 외부 변경: `DispatchSource`로 파일을 감시한다. 자기 쓰기 직후 1.5초는 무시하고, 다른 앱의 원자적 저장(삭제/이름 변경 이벤트)은 잠시 뒤 새 inode를 다시 감시한다. 버퍼가 깨끗하면 재로드하되 직전 캐럿 위치(클램프)를 복원해 읽던 자리를 잃지 않는다. 수정 중이면 외부본을 `-external` 스냅샷으로 보관하고 경고한다.
- 파일 전환: 새 `MemoDocument`를 만들지 않고 `switchTo(url:)`로 같은 객체·같은 `NSTextStorage`의 내용만 바꾼다(§5 성능 메모 2). 전환 직전 dirty면 동기 저장하고, 전환 전 시작된 저장 콜백은 `fileGeneration` 세대 가드로 무시한다.
- 북마크: `BookmarkStore`가 문서 경로의 SHA-256 해시를 이름으로 `~/Library/Application Support/HyperEdit/bookmarks/<해시>.json`에 저장한다. 문서 폴더에 숨김 파일을 만들지 않고 읽기 전용 볼륨의 파일도 북마크할 수 있다. 예전 버전이 문서 옆에 만들던 `.<파일명>.bookmarks.json` 사이드카는 읽기만 해서 1회 이전하고, 쓰지도 지우지도 않는다.

### 4.3 편집기

- `HyperTextView`는 TextKit 2 `NSTextView` 서브클래스. 멀티 커서와 열 블록은 추가 선택 범위 배열로 들고 있고, 모든 멀티 편집은 `shouldChangeText(inRanges:)` → `replaceCharacters` → `didChangeText` 경로를 타므로 ⌘Z 한 번으로 되돌려진다.
- 열 블록 수학(`ColumnBlock`)은 문자 열(UTF-16 오프셋) 기준이다. 줄이 짧으면 가상 공백으로 간주해 삽입 시 공백으로 채운다. 블록 안에서만 편집이 일어나므로 최상단 줄 시작 오프셋은 편집 중 변하지 않는다.
- 줄 번호 거터는 `NSRulerView`가 아니라 독립 `NSView`(`GutterView`)다(§5 기술 메모).
- 검색 결과가 있으면 매치 범위에 배경색 속성만 얹어 편집기 안에서 강조한다(최대 3,000개). 저장되는 문자열과 undo 스택에는 영향이 없다.
- 아웃라인·타임라인은 줄 인덱스가 바뀌고 1.2초 뒤 백그라운드에서 다시 스캔한다. 아웃라인은 `#` 헤딩·`[제목]`·`가./나.`·`1)`를 뽑되, 마크다운이 아닌 파일에서 코드 주석처럼 보이는 1단계 `#` 줄은 제외하고, 타임스탬프 헤딩은 타임라인으로 보낸다. 타임라인은 정확한 타임스탬프 헤딩과 날짜로 시작하는 느슨한 줄(연속 로그는 첫 줄만)을 모은다.

### 4.4 테마 엔진

- `themes/palettes.json`의 각 항목은 배경·전경·강조·선택·ANSI 16색·구문 색 등 소수의 필수 색만 가진다. `build_zed_theme.py`가 거기서 Zed 테마 스키마의 모든 스타일 키와 구문 키를 유도하고, Swift 쪽 `Theme`도 같은 JSON(패키지 리소스로 복사)을 읽는다.
- `build_preview.py`는 22개 카드가 들어간 `docs/theme-preview.html`을 만든다(외부 리소스·JS 없음). `validate.py`는 생성된 Zed 테마가 스키마 키를 모두 갖추고 색 형식이 맞는지 검사한다.
- CI는 생성물을 다시 만들어 커밋본과 비교한다. 팔레트를 고치고 생성물을 커밋하지 않으면 실패한다.
- `ThemeStore`: 저장된 선택이 없으면 시스템 외형 따르기(라이트 → `hyper-light`, 다크 → `hyper-dark`). 직접 고르면 고정되고, 레이아웃 탭·상태바·보기 메뉴의 테마 메뉴와 설정에서 다시 켤 수 있다(따르는 중이면 테마 이름 옆에 "· 시스템"). 앱은 `NSApplication.effectiveAppearance`를 구독해 시스템 전환을 전달한다.

### 4.5 폰트

- 본문 폰트는 Fira Code(없으면 시스템 고정폭), 캐스케이드에 한글 폰트를 끼운다. 한글 런에는 `HangulFontFixer`가 한글 폰트 ×1.2 크기를 속성으로 직접 입힌다. 줄 높이는 본문 폰트 기준으로 고정해 한글 폰트가 커도 줄 간격이 들쭉날쭉하지 않다. 근거와 대안은 [fonts.md](fonts.md).

## 5. 기술 메모 (실측·실수에서 배운 것)

### TextKit 2
- **`NSRulerView`를 TextKit 2 `NSTextView`에 붙이면 본문이 그려지지 않는다**(macOS 15 SDK 이후 실측). 줄 번호 거터는 스크롤 뷰 왼쪽에 독립 `NSView`로 두고 클립 뷰 bounds 변경에 맞춰 다시 그린다.
- TextKit 2 본문은 GPU 서피스로 합성되어 `cacheDisplay(in:to:)`로는 캡처되지 않는다. 화면 검증(`--snapshot`)은 **ScreenCaptureKit**으로 실제 창을 캡처한다(화면 녹화 권한 필요).
- 선택이 바뀔 때 전체 `needsDisplay`를 켜면 서피스 재합성이 일어난다. 현재 줄 강조는 이전·현재 줄 두 영역만 무효화한다.
- `NSTextContentStorage.textStorage`를 파일마다 갈아끼우면 TextKit 2 레이아웃 질의(`endEditing`·`scrollRangeToVisible`·거터 그리기)가 전환을 반복할수록 2 KB 문서에서도 50 ms대로 퇴화한다. 문서 객체와 스토리지를 유지한 채 전체 범위 `replaceCharacters`로 내용만 바꾸면 정상 편집 경로라 수 ms다.

### 한글 폭 보정
- AppKit은 캐스케이드 리스트에 지정한 폴백 폰트의 **크기를 무시한다**(실측). 그래서 한글 런마다 `.font` 속성으로 ×1.2 폰트를 직접 지정한다.
- MB 단위 텍스트에서 `NSRegularExpression`으로 한글 런을 찾으면 느리다. `unichar`를 64 K 청크로 직접 스캔해 런마다 `addAttribute`한다.
- 줄바꿈 종류 판별도 `String.contains("\r")`는 grapheme 단위라 1.3 MB에 80 ms가 들었다. UTF-8 바이트 스캔으로 1 ms 미만.

### 성능 메모 1 — 키 입력 지연
- 증상: 리본·패널이 키 입력마다 다시 그려졌다. 원인은 문서 상태를 `AppModel`을 통해 전달한 것.
- 조치: 캐럿 상태를 `EditorCaret`로 분리해 상태바·아웃라인·타임라인만 구독. 줄 인덱스는 `NSString` 버퍼 스캔, 저장은 불변 사본으로 백그라운드 쓰기. 셀프테스트에 `perf typing … ms/keystroke` 벤치마크 포함.
- 결과: 1.3 MB·3만 4천 줄 벤치마크 문서에서 키 입력당 약 3 ms(런루프 포함).

### 성능 메모 2 — 파일 전환
- 증상: 사이드바에서 파일을 바꿀 때 큰 문서는 120 ms 이상, 몇 번 전환하면 2 KB 파일도 600~800 ms 멈췄다.
- 원인 두 가지: ① 줄바꿈 판별의 grapheme 스캔(위), ② 파일마다 새 스토리지를 만들어 갈아끼운 것(위).
- 조치: `MemoDocument.switchTo(url:)` / `BookmarkStore.switchTo`로 제자리 전환. 계측 도구 `--debug-perf [--debug-perf-log <path>]`(구간 시간 + 메인 스레드 120 ms 이상 정지 감시), `--selftest-open`(작은 파일↔큰 파일 전환 벤치 + dirty 상태 전환 저장 정확성 검사, 가리킨 파일을 수정하므로 사본에서만).
- 결과: 큰 문서 전환 170~770 ms → 약 100 ms, 2 KB 파일 약 90 ms, 반복 전환 시 정지 0. 남은 비용 약 70 ms는 텍스트 뷰 뷰포트 레이아웃(CoreText 셰이핑).

### 창 복구
- 같은 앱 인스턴스가 떠 있는 상태에서 LaunchServices가 새 인스턴스를 띄우면 SwiftUI가 기본 창을 만들지 않는 경우가 있다. `AppDelegate`가 0.4초 뒤 창이 없으면 '다시 열기(`rapp`)' 애플 이벤트를 자신에게 보내 `WindowGroup` 창을 연다.

### 파일 트리 클릭
- 더블탭+싱글탭 제스처 조합은 싱글 클릭 반응이 더블클릭 판정 대기(0.5 s) 뒤에야 오고, 파일은 더블클릭해야만 열렸다. 한 번 클릭(또는 방향키 선택)으로 바로 여는 방식으로 바꿨다.

### 서명·공증
- 공증 통과 조건: hardened runtime, timestamp 서명, 그리고 **Release 구성에 `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`**. 이것이 없으면 `get-task-allow` 엔타이틀먼트가 주입되어 공증이 거절된다(실제 거절 사례). `scripts/make-dmg.sh`는 서명 뒤 엔타이틀먼트를 검사해 남아 있으면 실패시킨다.
- `scripts/make-dmg.sh`의 서명 모드는 자동 판별: 키체인에 Developer ID Application 인증서가 있으면 developer-id, Apple Development만 있으면 dev, 없으면 ad-hoc. 공증 자격 증명(App Store Connect API 키 또는 `notarytool` 키체인 프로필)이 있을 때만 앱(zip)과 DMG를 공증하고 스테이플한다.
- CI 시크릿은 인증서 `.p12`(base64)와 비밀번호, API 키 `.p8`(base64)·키 ID·발급자 ID, Homebrew tap 쓰기용 deploy key. `main`의 릴리스 워크플로는 서명·공증 시크릿이 없으면 첫 단계에서 실패한다(포크는 저장소 변수 `ALLOW_UNSIGNED_RELEASE=true`로 서명 없는 릴리스를 허용). `scripts/setup-signing.sh ci-secrets <cert.p12> <AuthKey.p8> <KEY_ID> <ISSUER_ID> [owner/repo]`가 .p12 암호를 프롬프트로 받아 `gh secret set`으로 시크릿 5개를 바로 등록한다(값이 화면·셸 기록에 남지 않음). 키 파일 패턴(`*.p8`, `*.p12`, `AuthKey_*`)은 `.gitignore`와 `scripts/check-sensitive.sh`가 막는다.

### semantic-release
- `@semantic-release/exec` 명령 문자열은 lodash 템플릿으로 먼저 해석된다. `${VAR:-x}` 같은 중괄호 셸 문법을 쓰면 템플릿과 충돌해 릴리스가 실패한다(실제 사고). 셸 로직은 스크립트 파일(`scripts/set-version.sh`, `scripts/update-cask.sh`)로 빼고 exec에는 인자만 넘긴다.
- semantic-release는 태그가 없으면 1.0.0부터 시작하므로 0.x를 유지하려고 첫 태그 `v0.1.0`은 수동으로 만들었다. `release-tag.yml`은 수동 태그에 DMG·릴리스를 만드는 보조 워크플로이며, 이미 릴리스가 있으면 건너뛴다(멱등).

## 6. 저장소 운영

- **브랜치**: `main`이 릴리스 브랜치. 기능은 브랜치 → PR → squash merge.
- **커밋 규약**: Conventional Commits. `feat` → 마이너, `fix`/`perf` → 패치, `feat!`/`BREAKING CHANGE` → 메이저, `docs`/`chore`/`refactor`/`test`/`ci`/`style`/`build` → 릴리스 없음, `(themes)` 스코프 → 패치. 제목은 한국어도 허용(commitlint `subject-case` 해제, 헤더 100자). 로컬 훅 `scripts/install-hooks.sh`, PR에서는 commitlint 액션.
- **CI (`ci.yml`)**: 테마 생성·drift 검사·스키마 검증(ubuntu) · 민감 정보 검사 `scripts/check-sensitive.sh`(비밀 파일 확장자, 키·토큰 패턴, 홈 디렉터리 경로, 이메일) · commitlint(PR 커밋 전부, 저장소 devDependency를 `npm ci --ignore-scripts`로 설치해 실행) · `swift test` + XcodeGen + 서명 없는 `xcodebuild`(macOS). 모든 액션은 커밋 SHA로 고정하고 `persist-credentials: false`로 체크아웃한다.
- **릴리스 (`release.yml`, macOS 러너)**: `main` push → 서명·공증 시크릿 확인(없으면 실패, 저장소 변수 `ALLOW_UNSIGNED_RELEASE=true`로만 우회) → `npm ci --ignore-scripts`(락파일 고정) → 임시 키체인에 인증서 가져오기 → semantic-release가 버전 계산 → `CHANGELOG.md`·`VERSION`·`Config/Version.xcconfig` 갱신 → 테마 생성 → `scripts/make-dmg.sh`(서명·공증) → `scripts/update-cask.sh`로 `Casks/hyperedit.rb` 생성 → `chore(release): x.y.z [skip ci]` 커밋 + `vx.y.z` 태그 → GitHub Release(DMG·`SHA256SUMS`·`hyperedit-themes.json`, 영·한 설치 안내) → **별도 단계**에서 버전이 바뀐 경우에만 `HOMEBREW_TAP_DEPLOY_KEY`로 tap 저장소에 cask 푸시(키는 이 단계에만 노출) → 임시 키체인·키 파일 정리. 빌드 번호(`CURRENT_PROJECT_VERSION`)는 `github.run_number`.
- **설치 채널**: Homebrew `brew tap Hyeongcheol-An/tap && brew install --cask hyperedit`, 또는 DMG. cask의 `zap`은 Application Support·Caches·Preferences·Saved State를 정리한다.

## 7. 로드맵

| 단계 | 내용 | 상태 |
|---|---|---|
| M0 | 분석·결정, 테마 팔레트 단일 소스, Zed 테마 배포, 릴리스 파이프라인 | 완료 (v0.1.0) |
| M1 | Xcode 프로젝트(HyperCore + mac), TextKit 2 편집기, 거터, 테마·폰트(한글 2:1), 리본 UI, 파일 트리, 찾기 결과 패널, 북마크, 텍스트 도구, 자동 줄바꿈, F7 타임스탬프, 위치 복원, 원자적 저장·스냅샷·외부 변경 감지, 셀프테스트 | 완료 (v0.2.0) |
| M2-a | 열 모드·멀티 커서·숫자 채우기, 바꾸기(정규식 템플릿, 모두 바꾸기 단일 undo), 파일에서 찾기, 사이드바 탭(파일 / 아웃라인 / 타임라인), 앱 아이콘, 성능 패스 | 완료 (v0.2.0) |
| M2-release | CI에서 Developer ID 서명·공증·스테이플 DMG 자동 산출, Gatekeeper 경고 없음 | 완료 (v0.2.1) |
| M2-perf | 파일 전환 지연 제거, 한 번 클릭 열기, 바이너리 파일 기본 앱으로, 로컬 전용 정리 | 완료 (v0.2.2–0.2.3) |
| 안전·정리 | 종료·전환 시 동기 저장, 인코딩 판별·유지, 북마크 Application Support 이전, 스냅샷 보관 정책, 검색 매치 편집기 강조, 외부 재로드 캐럿 유지, ⌘N 새 문서, 코딩(Coding) 리본 탭·자리표시자 제거와 용어 정리(사이드바·하단 패널·파일), CI 액션 SHA 고정·락파일 | 진행 중 |
| 공개 | HyperEdit로 개명, MIT 오픈소스, Hyper Light/Dark 기본 테마, Homebrew tap, 영문 문서 | 진행 중 |
| 현지화 | UI 영어·한국어(시스템 언어를 따름), String Catalog 기반 | 완료 — 다른 언어 기여 환영 |
| M2-b | 스냅샷 버전 브라우저, (보류 중인) iCloud 연동 | 보류 |
| M3 | iOS 타깃: 마지막 위치 복원, 검색, 빠른 추가 | 예정 |
| M4 | 마크다운 분할 미리보기, 즉석 계산, 탭 표 정렬, 붙여넣기 정리, 주석 토글 | 예정 |
| M5 | 매크로, URL 스킴·CLI, Spotlight, 분할 보기 → v1.0.0 | 예정 |

구현되지 않은 항목은 UI에 나타나지 않는다(비활성 자리표시자 없음). 구문 강조는 현재 계획에 없다(일반 텍스트 전용).

## 8. 결정 이력

- **2026-10-30** — 1차: 스택(Swift/SwiftUI + TextKit 2), 단일 텍스트 파일, 계승할 편집 도구 4종. 2차: 테마 단일 소스(20종), 폰트(Fira Code + D2Coding ×1.2), 타임스탬프 형식, 마지막 위치 복원. 3차: 리본 레이아웃과 기본 패널 배치 확정. 같은 날 M1·M2-a 구현, Developer ID 서명·공증 파이프라인 가동(v0.2.1), 성능 패스(v0.2.2), 로컬 전용으로 정리하고 iCloud 연동 보류(v0.2.3).
- **2026-10-31** — 프로젝트명 HyperEdit, MIT 라이선스로 공개. 테마 이름을 `Hyper ` 접두사로 통일하고 Hyper Light / Hyper Dark를 추가해 22종, 기본값은 시스템 외형 따르기. 기본 문서 `~/Documents/HyperEdit/notes.md`와 환영 문서. Homebrew tap 배포. 영어 README를 1차 문서로 하고 한국어판 완역. 개인 정보 검사(`scripts/check-sensitive.sh`)를 CI에 추가. 같은 날 후속: 종료·창 닫기·파일 전환 시 동기 저장(직렬 쓰기 큐), 인코딩 판별·유지(UTF-8·EUC-KR·CP1252·Latin-1), 북마크를 Application Support로 이전(옛 사이드카 1회 읽기), 스냅샷 보관 정책(파일별 20개·90일), 검색 매치 편집기 강조, 외부 재로드 시 캐럿 유지, ⌘N 새 문서, 코딩(Coding) 리본 탭과 비활성 자리표시자 제거, 용어를 사이드바·하단 패널·파일로 통일, 시스템 따르기를 모든 테마 메뉴에 노출, CI 액션 SHA 고정·`npm ci --ignore-scripts`·서명 시크릿 필수화·cask 푸시 분리.
