# HyperEdit 테마를 Zed에서 쓰기

HyperEdit의 22개 테마는 [Zed](https://zed.dev) 테마로도 내보내집니다. 앱과 Zed가 같은 `themes/palettes.json`에서 생성되므로 두 환경의 색이 항상 일치합니다. 테마 이름은 모두 `Hyper ` 접두사입니다(예: `Hyper Dark`, `Hyper Homebrew Terminal`, `Hyper Catppuccin Latte`).

## 설치

**릴리스 파일로:**

1. [GitHub Releases](https://github.com/Hyeongcheol-An/HyperEdit/releases)에서 `hyperedit-themes.json`을 내려받는다.
2. `~/.config/zed/themes/` 폴더에 넣는다(없으면 만든다). Zed는 이 폴더를 감시하므로 재시작 없이 바로 반영된다.
3. Zed에서 `⌘K ⌘T`(테마 선택기)를 열고 `Hyper …` 테마를 고른다. 라이트 5종·다크 17종이 Zed의 외형 필터에 맞게 나뉘어 있다.

**저장소에서 직접:**

```sh
git clone https://github.com/Hyeongcheol-An/HyperEdit.git
cd HyperEdit
python3 themes/build_zed_theme.py --install   # dist/ 에 생성 + ~/.config/zed/themes/hyperedit-themes.json 복사
```

`--install` 없이 실행하면 `themes/dist/hyperedit-themes.json`만 만든다.

## 시스템 외형에 따라 자동 전환

HyperEdit 앱의 기본 동작(라이트 → Hyper Light, 다크 → Hyper Dark)을 Zed에서도 재현하려면 `settings.json`에 다음을 넣는다.

```jsonc
"theme": {
  "mode": "system",
  "light": "Hyper Light",
  "dark": "Hyper Dark"
}
```

고정하려면 `"theme": "Hyper Dark"`처럼 문자열 하나로 쓰면 된다.

## 함께 쓰면 좋은 설정

HyperEdit의 폰트 구성([fonts.md](fonts.md))과 큰 메모 파일에 어울리는 Zed 설정 예시다. 필요한 것만 골라 쓰면 된다.

```jsonc
{
  "buffer_font_family": "Fira Code",
  "buffer_font_fallbacks": ["D2Coding"],        // 한글만 D2Coding 고정폭으로, 영문·리거처는 Fira Code 유지
  "buffer_font_features": { "calt": true },
  "buffer_line_height": "comfortable",
  "current_line_highlight": "all",
  "scrollbar": { "cursors": true, "search_results": true, "selected_text": true },
  "search": { "regex": true, "case_sensitive": false },
  "terminal": { "font_family": "Fira Code", "font_fallbacks": ["D2Coding"] },
  "file_types": { "Markdown": ["notes"] }        // 확장자 없는 메모 파일을 Markdown 으로 취급하려면
}
```

Zed는 폴백 폰트의 크기를 바꿀 수 없어 한글 : 영문 폭이 1 : 1.67로 남는다. HyperEdit 앱은 한글 런을 ×1.2로 그려 정확히 2:1을 맞춘다.

## 메모 파일에 쓸 만한 Zed 기능

- `⌘⇧F` 프로젝트 검색: 메모 폴더를 프로젝트로 열면 결과 패널(줄·컨텍스트·클릭 이동)이 HyperEdit의 "파일에서 찾기"와 같은 역할을 한다.
- 멀티 커서: `⌘D`(다음 매치 추가), `⌘⇧L`(모든 매치), `⌥` 드래그는 열 선택. HyperEdit의 ⌘D · ⌥⌘A · ⌥C와 대응한다.
- Zed에는 북마크 패널이 없다. 임시로 `@@이름` 같은 마커를 넣고 검색으로 점프하거나, HyperEdit에서 같은 파일을 열어 북마크를 쓰면 된다(북마크는 `~/Library/Application Support/HyperEdit/bookmarks/` 에 저장되므로 문서 폴더와 Zed 쪽 파일에는 영향이 없다).

## 테마가 만들어지는 방식

- `themes/palettes.json`의 각 테마는 배경·전경·강조·선택·테두리, ANSI 16색, 구문 색 등 소수의 필수 색만 가진다.
- `themes/build_zed_theme.py`가 그 색에서 Zed 테마 스키마(v0.2.0)의 스타일 키 전부와 구문 키 전부를 유도한다. 플레이어 색 8종, 터미널 ANSI, 편집기 거터·스크롤바·검색 하이라이트 등은 기본 색을 섞어 만든다.
- `themes/validate.py`가 생성된 파일이 스키마 키를 모두 갖추고 색 형식(`#RRGGBB` 또는 `#RRGGBBAA`)이 맞는지 검사한다. CI는 팔레트에서 다시 생성한 결과가 커밋본과 같은지도 확인한다.
- `themes/build_preview.py`는 22개 테마 카드가 있는 [`docs/theme-preview.html`](theme-preview.html)을 만든다. 브라우저에서 열어 고르면 된다.

## 테마 추가·수정

1. `themes/palettes.json`에 항목을 추가하거나 색을 고친다. `id`는 소문자-하이픈, `name`은 `Hyper ` 접두사, `appearance`는 `light` 또는 `dark`.
2. `python3 themes/build_zed_theme.py && python3 themes/build_preview.py && python3 themes/validate.py`
3. 생성물(`themes/dist/hyperedit-themes.json`, `docs/theme-preview.html`, `Packages/HyperCore/Sources/HyperCore/Resources/palettes.json`)을 함께 커밋한다.
4. 커밋 스코프를 `(themes)`로 두면 패치 릴리스가 만들어져 릴리스 자산의 테마 파일도 갱신된다.

자세한 기여 절차는 [CONTRIBUTING.md](../CONTRIBUTING.md)를 참고.
