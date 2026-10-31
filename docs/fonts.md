# 폰트 — "Fira Code 느낌 + 한글 지원"

> HyperEdit의 폰트 기본값이 왜 Fira Code + D2Coding인지, 대안은 무엇이고 앱이 한글 폭을 어떻게 맞추는지 정리한 설계 메모입니다. 설정은 앱의 설정(⌘,) → 폰트 / 한글 섹션에 있습니다.

## 문제

영문 고정폭 폰트 대부분은 한글 글리프가 없어 시스템 폴백(Apple SD Gothic Neo 등)으로 그려진다. 폴백 폰트의 한글은 보통 1.0 em, Fira Code의 반각은 0.6 em이라 **한글 : 영문 = 1 : 1.67**이 되고, 공백으로 맞춘 ASCII 표나 한·영이 섞인 열이 어긋난다. 탭으로 맞춘 표는 탭 스톱이 고정이라 덜 어긋나지만, 한 줄에 한글과 영문이 섞이면 결국 틀어진다.

## 결론 (추천 순)

1. **Fira Code 그대로 + 한글 폴백 D2Coding** ← HyperEdit 기본값
   - 영문·리거처는 Fira Code, 한글만 D2Coding(고정폭)으로 그린다.
   - 앱은 한글 런을 **×1.2 크기**로 그려 1.2 em = 2 × 0.6 em → **정확한 2:1 정렬**이 된다. 두 폰트 중 하나라도 없으면 시스템 폰트로 자연스럽게 떨어진다.
   - Zed에서는 `"buffer_font_fallbacks": ["D2Coding"]` 한 줄로 같은 조합을 쓸 수 있지만, 폴백 크기를 바꿀 수 없어 비율은 1 : 1.67로 남는다.
2. **Sarasa Mono K** — 단일 폰트. Iosevka(영문, 리거처 있음) + 본고딕(한글), 정확한 2:1. `brew install --cask font-sarasa-gothic` (패키지가 매우 커서 수백 MB). 영문 글꼴이 Fira Code보다 좁고 날카롭다.
3. **D2Coding 단독(리거처판)** — 네이버, OFL. 1.3부터 리거처·Powerline 글리프 포함. 한글 가독성 최상, 영문은 Fira Code보다 평범하다.
4. **Monoplex KR** — IBM Plex Mono + IBM Plex Sans KR 합성, Nerd Font 판 있음, 한글 폭을 로마자 2칸에 맞춤. brew 미등록(GitHub에서 수동 설치).
5. **Noto Sans Mono CJK KR** — 정확한 2:1, 리거처 없음, 무난하다.
6. **JetBrains Mono + 폴백** — 1번과 같은 구조, 글꼴 취향 차이.

어느 조합이든 앱 설정의 "영문 폰트"·"한글 폰트" 칸에 패밀리 이름을 넣으면 된다. 한글 배율(기본 1.20)은 영문 폰트의 반각 폭에 맞춰 조정할 수 있다 — 반각 0.5 em 폰트(JetBrains Mono 등)와 1.0 em 한글이면 ×1.0이 2:1이다.

## 설치

```sh
# Fira Code
brew install --cask font-fira-code

# D2Coding — brew cask 에 없으므로 GitHub 릴리스에서 직접 설치. URL 은 실행 전에 한 번 확인할 것
cd "$(mktemp -d)" \
  && curl -LO https://github.com/naver/d2codingfont/releases/download/VER1.3.2/D2Coding-Ver1.3.2-20180524.zip \
  && unzip -q D2Coding-Ver1.3.2-20180524.zip \
  && cp -v D2Coding/*.ttc D2CodingLigature/*.ttc ~/Library/Fonts/ 2>/dev/null
ls ~/Library/Fonts | grep -i d2

# Sarasa Mono K (큼)
brew install --cask font-sarasa-gothic

# Fira Code Nerd Font (아이콘 글리프가 필요해지면)
brew install --cask font-fira-code-nerd-font
```

설치 후 HyperEdit 설정의 한글 섹션에 "설치됨"이 표시되면 보정이 켜진 것이다. 설치되지 않았으면 "시스템 폴백 사용"으로 표시되고 2:1 보정은 적용되지 않는다.

## Zed 설정 예시

```jsonc
"buffer_font_family": "Fira Code",
"buffer_font_fallbacks": ["D2Coding"],
"buffer_font_features": { "calt": true },   // 리거처
"terminal": { "font_family": "Fira Code", "font_fallbacks": ["D2Coding"] }
```

Zed는 지정한 폴백을 OS 기본 폴백 앞에 끼워 넣는다. UI 폰트는 별도(`ui_font_family`)로 두는 편이 낫다.

## 앱 구현 메모

- **본문 폰트**(`FontCascade.baseFont`): 영문 패밀리가 설치되어 있으면 `NSFontDescriptor`의 `cascadeList`에 한글 패밀리를 넣어 만든다. 없으면 `NSFont.monospacedSystemFont`. 리거처를 끄면 `calt`·공통 리거처 기능을 descriptor 수준에서 끈다.
- **2:1 보정**(`HangulFontFixer`): AppKit은 캐스케이드 폴백에 지정한 크기를 무시한다(실측). 그래서 한글 런(음절·자모·호환 자모·확장 자모)마다 `.font` 속성으로 한글 폰트 × 배율을 직접 입힌다. 파일을 처음 올릴 때 전체 범위에 한 번, 편집 뒤에는 바뀐 문단 범위만 다시 적용한다(`NSTextStorageDelegate`).
- **성능**: MB 단위 텍스트에서 정규식으로 한글 런을 찾으면 느려서 `unichar`를 64 K 청크로 직접 스캔한다.
- **줄 높이**(`FontCascade.lineHeight`): 한글 폰트가 더 커도 줄 간격이 들쭉날쭉하지 않도록 본문 폰트 기준으로 고정한다(기본 ×1.35, 설정에서 1.0~2.0).
- **탭 폭**: 본문 폰트의 `"0"` 폭을 기준으로 계산한다. 한글이 정확히 두 칸이므로 탭 표가 유지된다.
- 같은 코드가 `#if canImport(UIKit)`로 iOS에서도 동작하도록 작성되어 있다.

## 출처

- D2Coding 1.3 리거처/Powerline, OFL: https://docs.hamonikr.org/hamonikr/tips/cli-tools/d2coding-regular-font-korean-font
- Sarasa Mono K(Iosevka + 본고딕, 리거처, 2:1): https://wikidocs.net/381030
- Zed `buffer_font_fallbacks`(플랫폼 기본 폴백과 병합): https://git.secluded.site/zed/commit/2aae3ab448d83ac920406e5aaec103818827b941
- Monoplex KR: https://github.com/y-kim/monoplex
- Fira Code: https://github.com/tonsky/FiraCode
