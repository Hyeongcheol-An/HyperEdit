# Export as HTML / PDF — 문서 초안 (v0.8, 브랜치 feat/v08-export)

통합 담당이 README / README.ko / USER_GUIDE(11개 언어) / docs/features.md 에 반영할 원고. 코드와 셀프테스트가 확인한 동작만 적었다.

## 1. English (README › Features › Saving 뒤, 또는 새 "Export" 절 · USER_GUIDE)

### Export (HTML / PDF)
- **File › Export as HTML…** writes the current document as a single, self-contained HTML file; **File › Export as PDF…** prints the same page to a paginated PDF. Neither has a keyboard shortcut. The save panel opens in the document's folder with the document's name and the new extension, and has two options: **Theme** (Current, Hyper Light or Hyper Dark) and **Line numbers** (for notes and code; off by default, disabled for Markdown). The choices are remembered.
- **Markdown files** (`.md`, `.markdown`, …) are rendered exactly like the Markdown preview (GFM headings, lists and task lists, tables, fenced code, quotes, links, images) with the theme's colors inlined as CSS. Raw HTML in the source stays escaped text and nothing runs in the exported page: it contains no scripts and loads no external resources. Relative image paths are kept as written, so save the HTML next to the Markdown file (or copy the images along) and they resolve.
- **Notes and code files** are exported as a `<pre>` block colored with the file type's syntax rules — the same tokens you see in the editor (`⌃⌘H`), with the theme's `syntax` palette as CSS classes (`tok-keyword`, `tok-string`, …), the editor's monospace stack (Fira Code · D2Coding · SF Mono · Menlo), and long lines wrapped. With **Line numbers** on, each line gets a numbered gutter.
- **PDF** uses Letter paper when the system region is US, Canada or Mexico and A4 otherwise, with 36 pt margins, no header or footer, and the page background in the chosen theme. Long documents are split across pages; headings are kept with the text below them, and tables and code blocks are kept on one page when they fit. PDF export is available for files up to 2 MB (the same limit as the preview); HTML export has no size limit.
- When the export finishes, the status bar and the Output panel show `Exported HTML · ~/path/file.html` (or `Exported PDF · …`); a failure is logged in red in the Output panel.

### Keyboard shortcuts table
No new rows (no shortcuts).

### Roadmap and limitations (add)
- Export writes the whole document; there is no selection-only or multi-file export, no page-size / margin / font-size options, and the PDF has no clickable table of contents or bookmarks. Syntax colors in exported code are line-based, like the editor.

## 2. 한국어 (README.ko · USER_GUIDE.ko)

### 내보내기 (HTML / PDF)
- **파일 › HTML로 내보내기…** 는 현재 문서를 독립된 HTML 파일 하나로 저장하고, **파일 › PDF로 내보내기…** 는 같은 페이지를 쪽이 나뉘는 PDF 로 찍는다. 단축키는 없다. 저장 패널은 문서 폴더에서 문서 이름 + 새 확장자로 열리며, 옵션은 **테마**(현재 테마 / Hyper Light / Hyper Dark) 와 **줄 번호**(메모·코드용, 기본 꺼짐, 마크다운에서는 비활성) 두 가지다. 선택은 기억된다.
- **마크다운 파일**(`.md`, `.markdown` …)은 마크다운 미리보기와 똑같이 렌더링된다(GFM 제목·목록·체크리스트·표·코드 블록·인용·링크·이미지). 테마 색은 CSS 로 인라인되고, 원문의 HTML 은 글자로만 보이며 내보낸 페이지에는 스크립트도 외부 리소스도 없다. 상대 이미지 경로는 그대로 두므로 HTML 을 마크다운 파일 옆에 저장하면(또는 이미지를 함께 복사하면) 맞는다.
- **메모·코드 파일**은 파일 종류의 구문 규칙으로 색을 입힌 `<pre>` 블록으로 나간다 — 편집기(`⌃⌘H`)에서 보는 토큰 그대로, 테마의 `syntax` 팔레트가 CSS 클래스(`tok-keyword`, `tok-string` …)로 들어가고, 편집기와 같은 모노스페이스 스택(Fira Code · D2Coding · SF Mono · Menlo), 긴 줄은 접힌다. **줄 번호**를 켜면 줄마다 번호 열이 붙는다.
- **PDF** 용지는 시스템 지역이 미국·캐나다·멕시코면 Letter, 그 밖에는 A4, 여백 36 pt, 머리글·바닥글 없음, 페이지 배경은 고른 테마 색. 긴 문서는 여러 쪽으로 나뉘고 제목은 아래 본문과 떨어지지 않게, 표·코드 블록은 한 쪽에 들어가면 나누지 않는다. PDF 내보내기는 2 MB 이하 파일에서 쓸 수 있고(미리보기와 같은 기준) HTML 은 크기 제한이 없다.
- 끝나면 상태바와 출력 패널에 `HTML 내보내기 완료 · ~/경로/파일.html`(또는 `PDF 내보내기 완료 · …`)이 보이고, 실패는 출력 패널에 빨간색으로 남는다.

### 로드맵·제한 (추가)
- 문서 전체만 내보낸다 — 선택 영역·여러 파일 내보내기, 용지 크기·여백·글자 크기 옵션, PDF 목차·책갈피는 없다. 코드의 구문 색은 편집기처럼 줄 단위다.

## 3. docs/features.md 표 행 (한국어)

| HTML/PDF 내보내기 | 완료 (v0.8) | 파일 › HTML로 내보내기… / PDF로 내보내기…. 저장 패널 액세서리로 테마(현재·Hyper Light·Hyper Dark)·줄 번호 선택. 마크다운은 `MarkdownHTML` 독립 문서(미리보기 스크립트 없음·인쇄 CSS), 메모·코드는 `HTMLExporter`(HyperCore `Export/`) 가 문법 토큰을 `tok-*` span 으로 입힌 `<pre>` + 테마 syntax CSS. PDF 는 화면 밖 WKWebView 에 같은 HTML 을 올려 `printOperation`(jobDisposition .save, Letter/A4, 여백 36 pt, 머리글·바닥글 없음)으로 쪽 나뉜 파일을 만들고, 실패 시 `createPDF`(한 장) 폴백. 2 MB 초과는 PDF 만 거절. 결과는 상태바(`MemoDocument.showStatus`)·출력 로그 |

## 4. 새 실행 인자
없음. (셀프테스트 `--selftest` 에 내보내기 검사 23개가 추가됐다: HTML 구조·테마 색·스크립트 없음, 긴 마크다운 PDF 의 쪽 수 ≥ 2·용지 크기·본문 텍스트·10초 제한, .py HTML 의 토큰 span·줄 번호 열, 2 MB 초과 PDF 거절, 파일 메뉴 항목.)

## 5. 알려진 제한 · 구현 메모
- PDF 1순위 경로(`WKWebView.printOperation` → `.save`)는 화면 밖 borderless NSWindow 에 붙인 웹뷰에서 `runModal(for:)` 로 돌린다. 20초 안에 끝나지 않거나 파일이 생기지 않으면 `createPDF(configuration:)`(한 장짜리, 쪽 없음) 로 폴백하고 출력 로그 대신 `--debug-perf` 로그에 사유를 남긴다. 셀프테스트 로그의 `method print|createPDF` 로 어느 경로였는지 알 수 있다.
- 내보낸 마크다운 HTML 은 미리보기 HTML 과 본문이 같지만 미리보기용 스크립트(스크롤 동기화·링크 가로채기)는 빼고 인쇄 CSS 를 더한다 — 스크립트가 있으면 브라우저에서 링크 클릭이 막힌다. 그래서 `MarkdownHTML.html(for:theme:baseURL:title:includeScript:)` 변형이 생겼고, 기존 호출(미리보기)은 그대로다.
- 코드 HTML 의 줄 번호 열은 `display: block` 줄 블록 + 절대 위치 번호(`.ln`, 선택 불가)라서 브라우저에서 복사해도 번호가 따라오지 않는다. 줄 번호를 끄면 토큰 span 과 실제 개행만 있어 원문 그대로 복사된다.
- 비밀 블록 가림(secrets 기능)은 `AppModel.exportSourceText()` 한 곳에서 연결한다 (`// secrets:` TODO 주석).
- 2 MB 판정은 디스크 크기와 현재 버퍼 UTF-8 크기 중 큰 쪽.
