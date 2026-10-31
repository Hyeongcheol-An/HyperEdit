#!/usr/bin/env python3
"""UI 문자열 카탈로그 완전성 검사 (CI · 로컬).

Swift 소스에서 현지화 API 에 넘긴 문자열 리터럴을 찾아 String Catalog 와 대조한다.
  Apps/mac/**/*.swift                      → Apps/mac/Localizable.xcstrings
  Packages/HyperCore/Sources/**/*.swift    → Packages/HyperCore/Sources/HyperCore/Resources/Localizable.xcstrings

현지화 API 로 보는 것:
  Text / Button / Label / TextField / Section / Toggle / Menu / CommandMenu / Picker / LabeledContent 의 첫 인자,
  .help(...) / .alert(...) 의 첫 인자, title: / help: / localized: 이름 인자(리본 구성 요소, String(localized:)),
  `var x: LocalizedStringKey { switch … }` 안의 리터럴(탭 이름), SearchPanel 의 smallButton(제목, 도움말) / optionToggle(_, _, 도움말).
  `cond ? "A" : "B"` 꼴이면 양쪽 모두. Text(verbatim:) 와 systemImage: 등 다른 이름 인자는 제외.

보간 `\\(…)` 은 `specifier:` 가 있으면 그 서식, 없으면 %lld 또는 %@ 후보로 바꿔 카탈로그 키와 맞춘다.

번역 언어는 LANGUAGES (영어가 소스). 언어마다 누락 수를 세고, 자리표시자(%@ %lld %.2f)가 영어 키와 다르면 오류로 본다.
리본 버튼 제목(RibbonBigButton·RibbonSmallButton·RibbonSmallToggle 의 title:)은 폭이 고정이라 번역이 길면 잘린다 → 추정 폭으로 LONG 경고.
언어 목록이 Apps/mac/AppLanguage.swift 의 `supported`, 사용자 가이드(docs/guide/USER_GUIDE.<code>.md), 환영문(Resources/Welcome/welcome.<code>.md)과
맞는지도 검사한다.

종료 코드 1: 코드에 쓰인 키가 카탈로그에 없을 때, 자리표시자 불일치, 언어 목록·가이드·환영문 불일치. 번역 누락과 코드에서 안 쓰는 키는 경고
(`--strict` 를 주면 번역 누락도 오류 — 릴리스 전 검사용).
사용: python3 scripts/check-l10n.py [-v] [--strict]
"""
from __future__ import annotations

import itertools
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERBOSE = "-v" in sys.argv
STRICT = "--strict" in sys.argv

# 번역 언어 (소스 언어 en 제외). Apps/mac/AppLanguage.swift 의 `supported` 와 같아야 한다 — main() 이 대조한다.
LANGUAGES = ["ko", "zh-Hans", "ja", "vi", "hi", "de", "fr", "es", "pt", "ar"]
LANGUAGE_NAMES = {"en": "English", "ko": "한국어", "zh-Hans": "简体中文", "ja": "日本語", "vi": "Tiếng Việt", "hi": "हिन्दी",
                  "de": "Deutsch", "fr": "Français", "es": "Español", "pt": "Português (Brasil)", "ar": "العربية"}
APP_LANGUAGE_SWIFT = ROOT / "Apps/mac/AppLanguage.swift"
GUIDE_DIR = ROOT / "docs/guide"
WELCOME_DIR = ROOT / "Packages/HyperCore/Sources/HyperCore/Resources/Welcome"

# 소스 집합 → 카탈로그. 개발 전용 파일(셀프테스트·성능 로그·디버그)은 검사하지 않는다.
TARGETS = [
    {
        "name": "app",
        "sources": sorted((ROOT / "Apps/mac").rglob("*.swift")),
        "skip": {"SelfTest.swift", "Perf.swift", "AppDelegate.swift"},
        "catalog": ROOT / "Apps/mac/Localizable.xcstrings",
    },
    {
        "name": "HyperCore",
        "sources": sorted((ROOT / "Packages/HyperCore/Sources").rglob("*.swift")),
        "skip": set(),
        "catalog": ROOT / "Packages/HyperCore/Sources/HyperCore/Resources/Localizable.xcstrings",
    },
]

# 호출 이름 → LocalizedStringKey 를 받는 위치 인자 번호
POSITIONAL_APIS = {
    "Text": {0}, "Button": {0}, "Label": {0}, "TextField": {0}, "Section": {0}, "Toggle": {0},
    "Menu": {0}, "CommandMenu": {0}, "Picker": {0}, "LabeledContent": {0},
    ".help": {0}, ".alert": {0},
    "smallButton": {0, 1}, "optionToggle": {2},
}
# 이름 인자: String(localized:) 는 어디서나, title:/help: 는 리본 구성 요소 호출 안에서만 키로 본다 (OutlineItem(title:) 같은 모델 인자는 제외)
NAMED_ARGS_ANY = {"localized"}
NAMED_ARGS_IN = {"title", "help"}
NAMED_ARG_CALLERS = {"RibbonBigButton", "RibbonSmallButton", "RibbonSmallToggle", "RibbonBigToggle", "RibbonGroup", "RibbonTabButton", "QuickButton"}


def strip_comments(src: str) -> str:
    """문자열 리터럴 밖의 // 및 /* */ 주석을 같은 길이의 공백으로 바꾼다 (위치 보존)."""
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            i = skip_string(src, i)
            continue
        if src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if src.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith("/*", j):
                    depth += 1; j += 2
                elif src.startswith("*/", j):
                    depth -= 1; j += 2
                else:
                    j += 1
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
            continue
        i += 1
    return "".join(out)


def skip_string(src: str, i: int) -> int:
    """src[i] == '"' 인 리터럴의 끝 다음 인덱스. 보간 \\(…) 안의 중첩 문자열과 괄호를 처리한다."""
    n = len(src)
    if src.startswith('"""', i):
        j = src.find('"""', i + 3)
        return n if j < 0 else j + 3
    j = i + 1
    while j < n:
        c = src[j]
        if c == "\\":
            if src.startswith("\\(", j):
                j = skip_interpolation(src, j + 2)
                continue
            j += 2
            continue
        if c == '"':
            return j + 1
        if c == "\n":   # 닫히지 않은 리터럴 — 안전하게 줄 끝에서 끝낸다
            return j
        j += 1
    return n


def skip_interpolation(src: str, j: int) -> int:
    """\\( 다음 위치 j 에서 짝이 맞는 ) 다음 인덱스."""
    depth, n = 1, len(src)
    while j < n and depth:
        c = src[j]
        if c == '"':
            j = skip_string(src, j); continue
        if c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
        j += 1
    return j


def literals(src: str) -> list[tuple[int, int, str, bool]]:
    """최상위 문자열 리터럴 (start, end, 내용(따옴표 제외), multiline)."""
    res, i, n = [], 0, len(src)
    while i < n:
        if src[i] == '"':
            end = skip_string(src, i)
            multi = src.startswith('"""', i)
            body = src[i + 3:end - 3] if multi else src[i + 1:end - 1]
            res.append((i, end, body, multi))
            i = end
        else:
            i += 1
    return res


def unescape(s: str) -> str:
    return s.replace('\\"', '"').replace("\\\\", "\\").replace("\\n", "\n").replace("\\t", "\t")


def format_candidates(body: str) -> list[str]:
    """보간을 서식 지정자로 바꾼 키 후보들 (specifier: 가 없으면 %lld / %@ 모두)."""
    parts: list[list[str]] = []
    i, n = 0, len(body)
    cur = ""
    while i < n:
        if body.startswith("\\(", i):
            j = skip_interpolation(body, i + 2)
            expr = body[i + 2:j - 1]
            parts.append([unescape(cur)]); cur = ""
            m = re.search(r'specifier:\s*"([^"]*)"', expr)
            parts.append([m.group(1)] if m else ["%lld", "%@"])
            i = j
            continue
        if body[i] == "\\" and i + 1 < n:
            cur += body[i:i + 2]; i += 2; continue
        cur += body[i]; i += 1
    parts.append([unescape(cur)])
    return ["".join(p) for p in itertools.product(*parts)]


def enclosing_context(src: str, lits: list[tuple[int, int, str, bool]], start: int) -> tuple[str, int] | None:
    """리터럴 앞을 거슬러 올라가 (호출 이름, 위치 인자 번호) 또는 ("LocalizedStringKey", 0). 없으면 None."""
    lit_by_end = {e: s for s, e, _, _ in lits}
    i = start - 1
    depth_paren = depth_brace = depth_bracket = 0
    commas = 0
    while i >= 0:
        if i + 1 in lit_by_end:          # 앞선 리터럴은 통째로 건너뛴다
            i = lit_by_end[i + 1] - 1
            continue
        c = src[i]
        if c == ")": depth_paren += 1
        elif c == "]": depth_bracket += 1
        elif c == "}": depth_brace += 1
        elif c == "(":
            if depth_paren: depth_paren -= 1
            else:
                m = re.search(r"([.\w]+)\s*$", src[:i])
                return (m.group(1) if m else "", commas)
        elif c == "[":
            if depth_bracket: depth_bracket -= 1
            else: return None
        elif c == "{":
            if depth_brace: depth_brace -= 1
            else:
                line_start = src.rfind("\n", 0, i) + 1
                head = src[line_start:i]
                if re.search(r":\s*LocalizedStringKey\s*$", head):
                    return ("LocalizedStringKey", 0)
                if "switch" in head:          # switch 블록이면 바깥 선언으로 계속
                    i -= 1; continue
                return None
        elif c == "," and not (depth_paren or depth_brace or depth_bracket):
            commas += 1
        i -= 1
    return None


def collect_keys(path: pathlib.Path) -> list[tuple[list[str], int, str]]:
    """파일에서 현지화 키 후보 목록 [(후보들, 줄 번호, 문맥)]. 문맥은 호출 이름("Button", ".help", "String(localized:)", "RibbonSmallButton.title" …)."""
    raw = path.read_text(encoding="utf-8")
    src = strip_comments(raw)
    lits = literals(src)
    found = []
    for start, end, body, multi in lits:
        if multi or body == "":
            continue
        pre = src[:start].rstrip()
        line_no = src.count("\n", 0, start) + 1
        m = re.search(r"(?<![.\w])(\w+):\s*$", pre)
        if m:                                  # 이름 인자
            arg = m.group(1)
            if arg in NAMED_ARGS_ANY:
                found.append((format_candidates(body), line_no, "String(localized:)"))
            elif arg in NAMED_ARGS_IN:
                ctx = enclosing_context(src, lits, start)
                if ctx and ctx[0] in NAMED_ARG_CALLERS:
                    found.append((format_candidates(body), line_no, f"{ctx[0]}.{arg}"))
            continue
        ctx = enclosing_context(src, lits, start)
        if ctx is None:
            continue
        name, index = ctx
        if name == "LocalizedStringKey" or (name in POSITIONAL_APIS and index in POSITIONAL_APIS[name]):
            found.append((format_candidates(body), line_no, name))
    return found


# ── 자리표시자 · 리본 라벨 폭 ─────────────────────────────────────────────────────────────────────

PLACEHOLDER_RE = re.compile(r"%(\d+\$)?(lld|ld|d|@|\.\d+f|f|%)")


def placeholders(s: str) -> tuple[list[str], bool]:
    """서식 지정자 목록(정렬, 위치 번호 제외)과 위치 번호(%1$@) 사용 여부. %% 는 제외."""
    specs, positional = [], False
    for m in PLACEHOLDER_RE.finditer(s):
        if m.group(2) == "%":
            continue
        specs.append(m.group(2))
        positional = positional or bool(m.group(1))
    return sorted(specs), positional


def placeholder_problem(key: str, value: str) -> str | None:
    """번역의 자리표시자가 키와 다르면 설명, 같으면 None."""
    k, _ = placeholders(key)
    v, pos = placeholders(value)
    if k != v:
        return f"placeholders {k} → {v}"
    if pos and len(set(re.findall(r"%(\d+)\$", value))) != len(v):
        return "mixed positional / non-positional placeholders"
    return None


def estimate_width(text: str, size: float) -> float:
    """시스템 글꼴 기준의 대략적인 표시 폭(pt). CJK 1em, 데바나가리 결합 기호 0, 그 외 자모 0.62em, 라틴 소문자 0.52em 등 — 스크린샷 검증을 대신하지 않는 어림값."""
    w = 0.0
    for ch in text:
        o = ord(ch)
        if 0x0900 <= o <= 0x097F:                      # Devanagari
            w += 0 if (0x093A <= o <= 0x094F or 0x0951 <= o <= 0x0957 or o in (0x0962, 0x0963, 0x0901, 0x0902)) else 0.62
        elif 0x0600 <= o <= 0x06FF:                    # Arabic (연결체라 글자당 폭이 좁다; 하라카트 등 결합 기호는 0)
            w += 0 if (0x064B <= o <= 0x065F or o == 0x0670 or 0x06D6 <= o <= 0x06ED) else 0.5
        elif 0x1100 <= o <= 0x11FF or 0x2E80 <= o <= 0x9FFF or 0xAC00 <= o <= 0xD7AF or 0xF900 <= o <= 0xFAFF or 0xFF00 <= o <= 0xFF60:
            w += 1.0                                   # 한글·한자·가나·전각
        elif ch == " ":
            w += 0.28
        elif ch in ".,:;'|!il":
            w += 0.3
        elif ch in "…·-–":
            w += 0.5
        elif ch.isdigit():
            w += 0.58
        elif ch.isupper():
            w += 0.68
        elif ch.islower():
            w += 0.52
        else:
            w += 0.6
    return w * size


# 리본 구성 요소의 글자 폭 한계 (RibbonView.swift 의 고정 프레임에서 아이콘·패딩을 뺀 값)
RIBBON_LIMITS = {
    "RibbonBigButton.title": ("ribbon-big", 10.5),     # 60pt × 2줄 — 단어 하나가 58pt 를 넘으면 글자 단위로 잘린다
    "RibbonBigToggle.title": ("ribbon-big", 10.5),
    "RibbonSmallButton.title": ("ribbon-small", 11),   # 128 − 패딩 10 − 아이콘 16 − 간격 5 = 97pt
    "RibbonSmallToggle.title": ("ribbon-toggle", 11),  # 위에서 체크 표시 14pt 를 더 뺀 83pt
}


def ribbon_kind(contexts: set[str]) -> str | None:
    kinds = [RIBBON_LIMITS[c][0] for c in contexts if c in RIBBON_LIMITS]
    if not kinds:
        return None
    for k in ("ribbon-big", "ribbon-toggle", "ribbon-small"):   # 가장 엄격한 것
        if k in kinds:
            return k
    return kinds[0]


def label_overflow(text: str, kind: str) -> str | None:
    """리본 라벨이 프레임을 넘을 것 같으면 설명, 아니면 None."""
    if kind == "ribbon-big":
        words = text.split()
        longest = max((estimate_width(w, 10.5) for w in words), default=0)
        total = estimate_width(text, 10.5)
        if longest > 58:
            return f"word ≈{longest:.0f}pt > 58pt (big button is 60pt wide)"
        if total > 112:
            return f"≈{total:.0f}pt > 2 lines of a 60pt big button"
        return None
    limit = 83 if kind == "ribbon-toggle" else 97
    w = estimate_width(text, 11)
    return f"≈{w:.0f}pt > {limit}pt ({kind})" if w > limit else None


def load_catalog(path: pathlib.Path) -> dict:
    if not path.exists():
        print(f"!! 카탈로그 없음: {path.relative_to(ROOT)}")
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("sourceLanguage") != "en":
        print(f"!! {path.relative_to(ROOT)}: sourceLanguage 가 en 이 아님 ({data.get('sourceLanguage')})")
    return data.get("strings", {})


def translation(entry: dict, lang: str) -> str:
    return entry.get("localizations", {}).get(lang, {}).get("stringUnit", {}).get("value", "") or ""


def key_contexts(target: dict) -> dict[str, dict]:
    """타깃의 소스에서 키 → {"where": {문맥}, "files": {파일 이름}} (scripts/l10n-export.py 가 번역 문맥 파일을 만들 때 쓴다)."""
    strings = load_catalog(target["catalog"])
    out: dict[str, dict] = {}
    for f in target["sources"]:
        if f.name in target["skip"]:
            continue
        for candidates, line, ctx in collect_keys(f):
            hit = next((c for c in candidates if c in strings), None)
            if hit is None:
                continue
            e = out.setdefault(hit, {"where": set(), "files": set()})
            e["where"].add(ctx)
            e["files"].add(f.name)
    return out


def swift_supported_languages() -> list[str]:
    """Apps/mac/AppLanguage.swift 의 `case` 선언에서 언어 코드를 읽는다 (system 제외)."""
    if not APP_LANGUAGE_SWIFT.exists():
        return []
    src = APP_LANGUAGE_SWIFT.read_text(encoding="utf-8")
    body = src.split("enum AppLanguage", 1)[1].split("static let supported", 1)[0]
    codes: list[str] = []
    for m in re.finditer(r"^\s*case\s+([^\n]+)$", body, re.M):
        for part in m.group(1).split(","):
            part = part.strip()
            raw = re.search(r'=\s*"([^"]+)"', part)
            name = part.split("=")[0].strip()
            codes.append(raw.group(1) if raw else name)
    return [c for c in codes if c != "system"]


def main() -> int:
    errors = 0
    for t in TARGETS:
        strings = load_catalog(t["catalog"])
        used: set[str] = set()
        contexts: dict[str, set[str]] = {}
        missing: list[tuple[str, str, int]] = []
        for f in t["sources"]:
            if f.name in t["skip"]:
                continue
            for candidates, line, ctx in collect_keys(f):
                hit = next((c for c in candidates if c in strings), None)
                if hit is None:
                    missing.append((str(f.relative_to(ROOT)), candidates[0], line))
                else:
                    used.add(hit)
                    contexts.setdefault(hit, set()).add(ctx)
                    if VERBOSE:
                        print(f"   {f.name}:{line}  {hit!r}  [{ctx}]")
        unused = sorted(set(strings) - used)
        untranslated = {lang: sorted(k for k, v in strings.items() if not translation(v, lang)) for lang in LANGUAGES}
        bad_placeholders: list[tuple[str, str, str]] = []
        long_labels: list[tuple[str, str, str]] = []
        for k, v in strings.items():
            kind = ribbon_kind(contexts.get(k, set()))
            for lang in LANGUAGES:
                val = translation(v, lang)
                if not val:
                    continue
                if (p := placeholder_problem(k, val)):
                    bad_placeholders.append((lang, k, p))
                if kind and (p := label_overflow(val, kind)):
                    long_labels.append((lang, k, f"{val!r} {p}"))
            if kind and (p := label_overflow(k, kind)):
                long_labels.append(("en", k, p))
        rel = t["catalog"].relative_to(ROOT)
        coverage = " · ".join(f"{lang} {len(strings) - len(untranslated[lang])}/{len(strings)}" for lang in LANGUAGES)
        print(f"[{t['name']}] {rel}: 키 {len(strings)}개 · 코드에서 사용 {len(used)}개 · 누락 {len(missing)}개 · 미사용 {len(unused)}개")
        print(f"   번역: {coverage}")
        for file, key, line in missing:
            print(f"  MISSING  {file}:{line}  {key!r}")
        for lang, key, prob in bad_placeholders:
            print(f"  PLACEHOLDER [{lang}] {key!r}: {prob}")
        for lang, key, prob in long_labels:
            print(f"  LONG [{lang}] {key!r}: {prob}")
        for lang in LANGUAGES:
            keys = untranslated[lang]
            if not keys:
                continue
            shown = keys if (VERBOSE or len(keys) <= 15) else keys[:15]
            for k in shown:
                print(f"  NO-{lang}  {k!r}")
            if len(shown) < len(keys):
                print(f"  NO-{lang}  … {len(keys) - len(shown)}개 더 (-v 로 전부)")
        for k in unused:
            print(f"  UNUSED   {k!r}")
        errors += len(missing) + len(bad_placeholders)
        if STRICT:
            errors += sum(len(v) for v in untranslated.values())

    # 언어 목록 · 가이드 · 환영문 일치
    swift_langs = swift_supported_languages()
    expected = ["en"] + LANGUAGES
    if swift_langs != expected:
        print(f"!! AppLanguage.swift 의 언어 {swift_langs} 가 LANGUAGES {expected} 와 다릅니다")
        errors += 1
    for code in expected:
        guide = GUIDE_DIR / ("USER_GUIDE.md" if code == "en" else f"USER_GUIDE.{code}.md")
        if not guide.exists() or guide.stat().st_size < 2000:
            print(f"!! 사용자 가이드 없음/너무 짧음: {guide.relative_to(ROOT)}")
            errors += 1
        welcome = WELCOME_DIR / f"welcome.{code}.md"
        if not welcome.exists() or welcome.stat().st_size < 200:
            print(f"!! 환영문 없음/너무 짧음: {welcome.relative_to(ROOT)}")
            errors += 1
    print(f"언어 {len(expected)}개: {' '.join(expected)} — AppLanguage.swift · docs/guide · Resources/Welcome 일치")

    if errors:
        print(f"\n{errors}개 문제. 카탈로그 키·자리표시자·언어 파일을 확인하세요 (번역 추가: l10n/ui.<code>.json → python3 scripts/l10n-add.py).")
        return 1
    print("\nOK — 코드의 모든 현지화 키가 카탈로그에 있고 자리표시자·언어 파일이 일치합니다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
