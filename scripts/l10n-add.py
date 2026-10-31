#!/usr/bin/env python3
"""번역 파일을 String Catalog 에 넣는다.

사용:  python3 scripts/l10n-add.py [--check] [--lang <code>] l10n/ui.<code>.json [...]

입력은 평평한 JSON  { "English key": "번역" } . 언어는 파일 이름의 `.<code>.json` 에서 읽는다 (`--lang` 으로 지정 가능).
각 키가 어느 타깃 코드에서 쓰이는지(Apps/mac → Apps/mac/Localizable.xcstrings, Packages/HyperCore → HyperCore 카탈로그)를
카탈로그와 소스에서 찾아 해당 카탈로그에 번역(state: translated)을 넣는다. 이미 있는 키는 번역만 갱신하고, 빈 값("")은 건너뛴다.
어느 소스에서도 못 찾은 키는 경고로 알리고 앱 카탈로그에 넣는다 (scripts/check-l10n.py 가 미사용으로 잡아 준다).

`--check` 는 쓰지 않고 검사만 한다: 빈 값 수, 자리표시자 불일치(오류), 리본 라벨 길이(경고), 카탈로그에 없는 키.
번역자는 파일을 채운 뒤 `--check` 로 먼저 확인한다.
"""
from __future__ import annotations

import importlib.util
import json
import os
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
spec = importlib.util.spec_from_file_location("check_l10n", HERE / "check-l10n.py")
chk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(chk)   # type: ignore[union-attr]

CATALOGS = {t["name"]: t["catalog"] for t in chk.TARGETS}


def swift_sources(subdir: str) -> str:
    out = []
    for dirpath, _, files in os.walk(ROOT / subdir):
        for f in files:
            if f.endswith(".swift"):
                out.append((pathlib.Path(dirpath) / f).read_text(encoding="utf-8"))
    return "\n".join(out)


def literal_pattern(key: str) -> re.Pattern:
    """코드 리터럴에는 보간(\\(…)) 이 들어가므로 포맷 자리표시자를 와일드카드로 바꿔 찾는다."""
    parts = re.split(r"%(?:lld|@|\.\df|d|f)", key)
    return re.compile(r'"' + r".*?".join(re.escape(p) for p in parts) + r'"')


def lang_of(path: str, override: str | None) -> str:
    if override:
        return override
    m = re.search(r"\.([A-Za-z]{2,3}(?:-[A-Za-z]{2,4})?)\.json$", path)
    if not m or m.group(1) not in chk.LANGUAGES:
        sys.exit(f"{path}: 파일 이름에서 언어 코드를 읽을 수 없습니다 (ui.<code>.json, code ∈ {chk.LANGUAGES}) — --lang 으로 지정하세요")
    return m.group(1)


def main(argv: list[str]) -> int:
    check_only = "--check" in argv
    override = None
    if "--lang" in argv:
        override = argv[argv.index("--lang") + 1]
    paths = [a for a in argv if a.endswith(".json")]
    if not paths:
        print(__doc__)
        return 2
    app_src, core_src = swift_sources("Apps/mac"), swift_sources("Packages/HyperCore/Sources")
    cats = {name: json.loads(p.read_text(encoding="utf-8")) for name, p in CATALOGS.items()}
    contexts: dict[str, set[str]] = {}
    for t in chk.TARGETS:
        for k, e in chk.key_contexts(t).items():
            contexts.setdefault(k, set()).update(e["where"])
    errors = 0
    for path in paths:
        lang = lang_of(path, override)
        data = json.loads(pathlib.Path(path).read_text(encoding="utf-8"))
        empty, added, unknown, long_labels = 0, {n: 0 for n in cats}, [], 0
        for key, val in data.items():
            if not isinstance(val, str):
                print(f"ERROR {path}: {key!r} 값이 문자열이 아닙니다"); errors += 1; continue
            if val == "":
                empty += 1
                continue
            if (p := chk.placeholder_problem(key, val)):
                print(f"ERROR [{lang}] {key!r}: {p}  ← {val!r}"); errors += 1; continue
            if (kind := chk.ribbon_kind(contexts.get(key, set()))) and (p := chk.label_overflow(val, kind)):
                print(f"LONG  [{lang}] {key!r}: {val!r} {p}"); long_labels += 1
            in_cat = [n for n, c in cats.items() if key in c["strings"]]
            if not in_cat:
                pat = literal_pattern(key)
                in_cat = [n for n, hit in (("app", pat.search(app_src)), ("HyperCore", pat.search(core_src))) if hit] or ["app"]
                unknown.append(key)
            if check_only:
                continue
            for n in in_cat:
                entry = cats[n]["strings"].setdefault(key, {})
                entry.setdefault("localizations", {})[lang] = {"stringUnit": {"state": "translated", "value": val}}
                added[n] += 1
        for k in unknown:
            print(f"WARN  [{lang}] 카탈로그에 없는 키 (코드에서 찾아 넣음): {k!r}")
        status = f"{path} [{lang}]: {len(data)}개 중 빈 값 {empty}개 · 리본 길이 경고 {long_labels}개 · 카탈로그 밖 {len(unknown)}개"
        if not check_only:
            status += " → " + ", ".join(f"{n} {c}개" for n, c in added.items())
        print(status)
    if not check_only and not errors:
        for n, data in cats.items():
            CATALOGS[n].write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
            print(f"{CATALOGS[n].relative_to(ROOT)}: 총 {len(data['strings'])}개 키")
    if errors:
        print(f"\n{errors}개 오류 — 카탈로그를 바꾸지 않았습니다." if not check_only else f"\n{errors}개 오류")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
