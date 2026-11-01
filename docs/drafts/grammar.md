# grammar — multi-line syntax state + user-defined grammars (v0.8 draft)

통합 담당용 초안. (1) README / USER_GUIDE 에 넣을 영어 문단, (2) 같은 내용 한국어, (3) `docs/features.md` 표 행, (4) 실행 인자, (5) 알려진 제한.
소스: `Packages/HyperCore/Sources/HyperCore/Highlight/{LanguageGrammar,CodeGrammar,PlainNotesGrammar,GrammarRegistry,LineStateIndex,UserGrammarStore}.swift`,
`Document/MemoDocument.swift`(grammar MARK), `Apps/mac/GrammarUI.swift`, `Apps/mac/Editor/EditorView.swift`(`// grammar:` 주석), `Apps/mac/SelfTest+Grammar.swift`.

## 1. English (README › Features, USER_GUIDE › Syntax colors)

### Multi-line syntax state

Syntax colors now follow constructs that span lines. A block comment (`/* … */`, `<!-- … -->`), a multi-line string
(Swift and Python `"""` / `'''`, JavaScript/TypeScript template literals and Go raw strings in backticks, Rust `r"…"` / `r#"…"#`)
and a Markdown fenced code block keep their color on every line until they close, and typing the opening or closing delimiter
recolors the lines below immediately. Markdown fences are colored with the language named in the info string — ```` ```swift ````,
```` ```python ````, ```` ```bash ````, ```` ```json ```` and the other built-in or user-defined languages (GitHub-style; the fence
language can also be a user grammar's name or extension). A fence with an unknown or missing language turns the Notes rules off inside it,
so `# heading` or `- [ ]` inside code is left uncolored. HTML comments in Markdown also span lines.

The editor keeps a per-line "entering state" table (`LineStateIndex`) for the open document: computing it for a 34k-line / 2.8 MB file
takes about 10 ms, and each keystroke rescans only the edited line(s) and stops as soon as the next line's state is unchanged — usually one
or two lines, so typing latency is unaffected. Languages without multi-line constructs (YAML, TOML, INI, shell, Ruby, plain Notes) skip the
table entirely. Lines whose state changed outside the edited line are repainted on the next run-loop turn; the colors live in TextKit 2
rendering attributes only, never in the file or the undo history.

### User-defined grammars

Put a `*.json` file in `~/Library/Application Support/HyperEdit/grammars/` to add a language or override a built-in one.
**File › Open Grammars Folder…** opens the folder (creating it with `example.json` — a tiny language for `*.example` files — and a `README.md`
describing the schema), and **File › Reload Grammars** re-reads it without restarting; the open document switches to the new grammar and the
status bar shows the grammar's `name`. The Output panel logs `Grammars reloaded · N` and one `Grammar file skipped · <file>: <reason>` line per
file that failed to parse (the file is skipped, the others still load). Comments and trailing commas are allowed in the JSON.
Toggle Comment (⌘/) uses the grammar's `lineComments` (first entry) or `blockComment`.

| Key | Type | Required | Meaning |
|---|---|---|---|
| `name` | string | yes | Language name for the status bar; also matches a Markdown fence info string (```` ```name ````). |
| `extensions` | [string] | one of extensions / filenames | File extensions without the dot (case-insensitive). User grammars win over built-ins. |
| `filenames` | [string] | one of extensions / filenames | Exact file names such as `Makefile` or `.myrc` (case-insensitive). |
| `mode` | string | no (`code`) | `code`, `markup` (tags, `<!-- -->`), `css`, `data` (`key:` values like JSON/YAML), `shell` (command position, `$VAR`, `--flags`). |
| `lineComments` | [string] | no | Line comment starters, e.g. `["#"]`, `["//", "--"]`. |
| `blockComment` | [open, close] | no | e.g. `["/*", "*/"]`. Spans lines. |
| `strings` | [string] | no (`"` `'`) | Single-character quotes (backslash escapes honored). `[]` = no strings. |
| `multilineStrings` | [string] | no | Same-open-and-close delimiters that may span lines, e.g. `["\"\"\""]`, `["`"]`. |
| `keywords` / `types` / `constants` | [string] | no | Word lists colored as keyword / type / constant. |
| `builtins` | [string] | no | Word list colored as function (built-in functions or commands). |
| `caseInsensitive` | bool | no (`false`) | Match word lists ignoring case (SQL-like). |

Example (`example.json`, written on first launch):

```json
{
  "name": "Example",
  "extensions": ["example"],
  "filenames": ["Examplefile"],
  "lineComments": ["#"],
  "blockComment": ["/*", "*/"],
  "strings": ["\"", "'"],
  "multilineStrings": ["\"\"\""],
  "keywords": ["let", "fn", "if", "else", "for", "in", "while", "return", "import"],
  "types": ["Int", "String", "Bool", "List"],
  "constants": ["true", "false", "nil"],
  "builtins": ["print", "len", "range"]
}
```

Numbers, operators, punctuation, `name(` (function), capitalized identifiers (type / constant) and `@attribute` are colored by the shared
scanner for every grammar; colors come from the theme's `syntax` palette. When two files claim the same extension, the later one in
file-name order wins. Automation runs (`--ephemeral`, `--selftest`, `--snapshot`) use a temporary grammars folder.

README "Known limits" replacement for the old sentence: *Syntax colors are line-based (…) and there is no user-defined grammar.* →
*Block comments, multi-line strings and Markdown fences are tracked across lines; only same-open-and-close multi-line string delimiters,
one block-comment pair per language and word-list based user grammars (no regular-expression rules) are supported.*

## 2. 한국어 (README.ko / USER_GUIDE.ko)

### 여러 줄 구문 상태

구문 색이 이제 줄을 넘어가는 구문을 따라간다. 블록 주석(`/* … */`, `<!-- … -->`), 여러 줄 문자열(Swift·Python 의 `"""` / `'''`,
JavaScript/TypeScript 템플릿 리터럴과 Go raw 문자열의 백틱, Rust `r"…"` / `r#"…"#`), 마크다운 펜스 코드 블록은 닫힐 때까지 모든 줄이 그 색을
유지하고, 여는/닫는 기호를 입력하면 아래 줄들이 바로 다시 칠해진다. 마크다운 펜스는 정보 문자열의 언어로 칠한다 — ```` ```swift ````,
```` ```python ````, ```` ```bash ````, ```` ```json ```` 등 내장·사용자 정의 언어(GitHub 처럼; 사용자 문법의 이름이나 확장자도 된다).
언어를 모르거나 없는 펜스 안에서는 메모 규칙을 꺼서 코드 속 `# 헤딩`·`- [ ]` 가 칠해지지 않는다. 마크다운의 HTML 주석도 여러 줄이다.

편집기는 열린 문서의 줄별 "진입 상태" 표(`LineStateIndex`)를 든다. 34k 줄 / 2.8 MB 파일의 전체 계산이 약 10 ms, 키 입력마다 편집된 줄만
다시 스캔하고 다음 줄의 상태가 이전과 같아지면 바로 멈춘다(보통 1~2줄) — 타이핑 지연은 그대로다. 여러 줄 구문이 없는 언어(YAML·TOML·INI·셸·Ruby·메모)는
표를 아예 만들지 않는다. 편집 줄 밖에서 상태가 바뀐 줄은 다음 런루프 턴에 다시 칠한다. 색은 TextKit 2 렌더링 속성에만 있어 파일·undo 에 영향이 없다.

### 사용자 정의 문법

`~/Library/Application Support/HyperEdit/grammars/` 에 `*.json` 을 두면 언어를 추가하거나 내장 언어를 덮어쓸 수 있다.
**파일 › 문법 폴더 열기…** 가 폴더를 연다(없으면 `example.json` — `*.example` 용 작은 언어 — 과 스키마 설명 `README.md` 를 만들어 둔다).
**파일 › 문법 다시 읽기** 는 재실행 없이 폴더를 다시 읽고, 열린 문서가 새 문법으로 바뀌며 상태바에 문법의 `name` 이 보인다.
출력 패널에 `문법 다시 읽음 · N개` 와, 읽지 못한 파일마다 `문법 파일 건너뜀 · <파일>: <이유>` 한 줄이 남는다(그 파일만 건너뛰고 나머지는 읽는다).
JSON 에 주석·뒤따르는 쉼표를 써도 된다. 주석 토글(⌘/)은 문법의 `lineComments`(첫 항목) 또는 `blockComment` 를 쓴다.

| 키 | 형 | 필수 | 뜻 |
|---|---|---|---|
| `name` | string | 예 | 상태바 언어 이름. 마크다운 펜스 정보 문자열(```` ```name ````)과도 맞춘다 |
| `extensions` | [string] | extensions / filenames 중 하나 | 점 없는 확장자(대소문자 무시). 사용자 문법이 내장보다 우선 |
| `filenames` | [string] | extensions / filenames 중 하나 | 정확한 파일 이름 (`Makefile`, `.myrc`; 대소문자 무시) |
| `mode` | string | 아니오 (`code`) | `code`, `markup`(태그·`<!-- -->`), `css`, `data`(JSON/YAML 식 `key:`), `shell`(명령 위치·`$VAR`·`--flag`) |
| `lineComments` | [string] | 아니오 | 줄 주석 시작 기호, 예 `["#"]`, `["//", "--"]` |
| `blockComment` | [열기, 닫기] | 아니오 | 예 `["/*", "*/"]`. 여러 줄 |
| `strings` | [string] | 아니오 (`"` `'`) | 한 글자 따옴표(백슬래시 이스케이프 처리). `[]` 면 문자열 없음 |
| `multilineStrings` | [string] | 아니오 | 여는/닫는 기호가 같은 여러 줄 문자열 구분자, 예 `["\"\"\""]`, `["`"]` |
| `keywords` / `types` / `constants` | [string] | 아니오 | 키워드 / 타입 / 상수 색 단어 목록 |
| `builtins` | [string] | 아니오 | 함수 색 단어 목록(내장 함수·명령) |
| `caseInsensitive` | bool | 아니오 (`false`) | 단어 목록을 대소문자 무시로 맞춤(SQL 류) |

숫자·연산자·구두점·`이름(`(함수)·대문자 식별자(타입/상수)·`@속성` 은 모든 문법에서 공용 스캐너가 칠한다. 색은 테마의 `syntax` 팔레트.
같은 확장자를 두 파일이 쓰면 파일 이름순으로 뒤의 것이 이긴다. 자동화 실행(`--ephemeral` `--selftest` `--snapshot`)은 임시 문법 폴더를 쓴다.

## 3. `docs/features.md` 표 행 (E. 마크다운·표시)

기존 🔜 행 `여러 줄 블록 주석·문자열 상태 추적, 사용자 정의 문법·키워드` 를 아래 두 행으로 바꾸고, "코드 구문 색 20여 종" 행의 메모
"줄 단위 토큰화라 여러 줄 블록 주석·문자열은 시작한 줄만" 과 K 절의 "여러 줄 상태 추적은 … 하지 않는다" 문장을 지운다.

| ✅ | **여러 줄 구문 상태 추적** — 블록 주석(`/* */` `<!-- -->`), 여러 줄 문자열(Swift/Python `"""` `'''`, JS/TS·Go 백틱, Rust `r#"…"#`), 마크다운 펜스(```/~~~)가 닫힐 때까지 모든 줄에 색. 펜스는 정보 문자열의 언어(내장·사용자 문법)로 중첩 토큰화, 모르는 언어면 색 없음. 마크다운 HTML 주석도 여러 줄. `/*` `*/` 입력 시 아래 줄 즉시 재도색 | `LineState`·`LanguageGrammar.scanLine(entering:)`·`LineStateIndex`(줄별 진입 상태, 전체 34k 줄 ≈ 10 ms, 키 입력당 편집 줄부터 수렴까지만 재스캔) · `MemoDocument.lineStates/liveLineIndex`(didProcessEditing 증분) · `EditorView` 가 `lineStatesChanged` 범위만 `edited(.editedAttributes)` 로 재생성. 여러 줄 구문이 없는 언어·메모는 표 없음 |
| ✅ | **사용자 정의 문법** — `~/Library/Application Support/HyperEdit/grammars/*.json`(name·extensions·filenames·mode·lineComments·blockComment·strings·multilineStrings·keywords·types·constants·builtins·caseInsensitive). 내장 확장자 덮어쓰기, 파일 메뉴 "문법 폴더 열기…"(첫 생성 시 `example.json`·`README.md`)·"문법 다시 읽기"(열린 문서 갱신·상태바 이름·출력 "문법 다시 읽음 · N개"), 잘못된 파일은 출력에 파일명·이유 후 건너뜀, ⌘/ 주석 토글 연동 | `UserGrammarStore`(HyperCore, JSON → `CodeLanguage`) · `GrammarRegistry` 가 사용자 문법 우선 · `GrammarUI.swift`(`GrammarCommands`, `AppModel.reloadGrammars`). 정규식 규칙·GUI 편집기는 없음 |

## 4. 새 실행 인자

없음. (`--ephemeral` `--selftest` `--snapshot` 은 기존대로 임시 폴더 `…/hyperedit-ephemeral-<pid>/grammars` 를 쓴다.)

## 5. 알려진 제한

- 여러 줄 문자열은 여는/닫는 구분자가 같은 것만(`"""` `'''` `` ` ``, Rust raw). C 계열의 `"…"` 줄 이어쓰기, 셸 heredoc·여러 줄 따옴표, Lua `[[ ]]` 같은 비대칭 구분자는 추적하지 않는다.
- 언어당 블록 주석 한 쌍. 중첩 블록 주석(Swift/Rust 의 `/* /* */ */`)은 첫 `*/` 에서 닫힌 것으로 본다.
- 마크다운 펜스는 들여쓰기 깊이를 보지 않는다(목록 안 4칸 이상 들여쓴 펜스도 펜스로 본다). 펜스 안 언어가 `md`/`markdown` 이면 중첩하지 않는다(색 없음). 메모(.txt) 모드는 여전히 상태가 없다 — 펜스·HTML 주석을 줄 단위로만 본다.
- 사용자 문법은 단어 목록·구분자 기반이다. 정규식 규칙, 스코프 중첩, 문법별 색 지정은 없다(색은 테마 팔레트). 폴더 변경은 자동 감지하지 않는다 — "문법 다시 읽기" 를 누른다.
- 편집 줄 밖의 재도색은 다음 런루프 턴에 일어나므로(저장소 편집 알림 안에서는 다시 알릴 수 없음) `/*` 를 입력한 바로 그 프레임에는 아래 줄이 이전 색일 수 있다(실측으로는 보이지 않음).
- 분할 보기에서 재도색 알림은 주 편집기만 처리한다(스토리지 속성 편집은 두 레이아웃 매니저에 모두 전달되므로 결과는 같다).
