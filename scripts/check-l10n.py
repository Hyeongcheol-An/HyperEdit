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

종료 코드 1: 코드에 쓰인 키가 카탈로그에 없을 때. ko 번역 누락과 코드에서 안 쓰는 키는 경고로만 출력한다.
사용: python3 scripts/check-l10n.py [-v]
"""
from __future__ import annotations

import itertools
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERBOSE = "-v" in sys.argv

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


def collect_keys(path: pathlib.Path) -> list[tuple[list[str], int]]:
    """파일에서 현지화 키 후보 목록 [(후보들, 줄 번호)]."""
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
                found.append((format_candidates(body), line_no))
            elif arg in NAMED_ARGS_IN:
                ctx = enclosing_context(src, lits, start)
                if ctx and ctx[0] in NAMED_ARG_CALLERS:
                    found.append((format_candidates(body), line_no))
            continue
        ctx = enclosing_context(src, lits, start)
        if ctx is None:
            continue
        name, index = ctx
        if name == "LocalizedStringKey" or (name in POSITIONAL_APIS and index in POSITIONAL_APIS[name]):
            found.append((format_candidates(body), line_no))
    return found


def load_catalog(path: pathlib.Path) -> dict:
    if not path.exists():
        print(f"!! 카탈로그 없음: {path.relative_to(ROOT)}")
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("sourceLanguage") != "en":
        print(f"!! {path.relative_to(ROOT)}: sourceLanguage 가 en 이 아님 ({data.get('sourceLanguage')})")
    return data.get("strings", {})


def main() -> int:
    missing_total = 0
    for t in TARGETS:
        strings = load_catalog(t["catalog"])
        used: set[str] = set()
        missing: list[tuple[str, str, int]] = []
        for f in t["sources"]:
            if f.name in t["skip"]:
                continue
            for candidates, line in collect_keys(f):
                hit = next((c for c in candidates if c in strings), None)
                if hit is None:
                    missing.append((str(f.relative_to(ROOT)), candidates[0], line))
                else:
                    used.add(hit)
                    if VERBOSE:
                        print(f"   {f.name}:{line}  {hit!r}")
        no_ko = sorted(k for k, v in strings.items()
                       if not v.get("localizations", {}).get("ko", {}).get("stringUnit", {}).get("value"))
        unused = sorted(set(strings) - used)
        rel = t["catalog"].relative_to(ROOT)
        print(f"[{t['name']}] {rel}: 키 {len(strings)}개 · 코드에서 사용 {len(used)}개 · 누락 {len(missing)}개 · ko 없음 {len(no_ko)}개 · 미사용 {len(unused)}개")
        for file, key, line in missing:
            print(f"  MISSING  {file}:{line}  {key!r}")
        for k in no_ko:
            print(f"  NO-KO    {k!r}")
        for k in unused:
            print(f"  UNUSED   {k!r}")
        missing_total += len(missing)
    if missing_total:
        print(f"\n{missing_total}개 키가 카탈로그에 없습니다. Localizable.xcstrings 에 영어 키와 ko 번역을 추가하세요.")
        return 1
    print("\nOK — 코드의 모든 현지화 키가 카탈로그에 있습니다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
