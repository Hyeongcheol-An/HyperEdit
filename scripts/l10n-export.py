#!/usr/bin/env python3
"""번역 작업 파일을 String Catalog 에서 내보낸다 (번역자·에이전트용).

사용:  python3 scripts/l10n-export.py [code ...]        (기본: 모든 번역 언어)

1. 코드에서 쓰는데 카탈로그에 없는 영어 키를 카탈로그에 먼저 넣는다 (번역 없이 — 그래야 아래 파일에 나타난다).
2. 언어마다 l10n/ui.<code>.json 을 쓴다: { "English key": "번역 또는 \"\"" } — 두 카탈로그(앱·HyperCore)의 모든 키, 정렬.
   비어 있는 값이 번역할 곳이다. 채운 뒤 `python3 scripts/l10n-add.py l10n/ui.<code>.json` 으로 카탈로그에 넣는다.
3. l10n/context.json 을 쓴다: 키마다 쓰이는 곳(문맥: "Button", ".help", "RibbonSmallButton.title" …), 파일, 한국어 참고 번역,
   리본 라벨 길이 제한(limit: ribbon-big / ribbon-small / ribbon-toggle).
"""
from __future__ import annotations

import importlib.util
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
spec = importlib.util.spec_from_file_location("check_l10n", HERE / "check-l10n.py")
chk = importlib.util.module_from_spec(spec)
spec.loader.exec_module(chk)   # type: ignore[union-attr]


def save_catalog(path: pathlib.Path, data: dict) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def add_missing_keys() -> int:
    added = 0
    for t in chk.TARGETS:
        data = json.loads(t["catalog"].read_text(encoding="utf-8"))
        strings = data.setdefault("strings", {})
        for f in t["sources"]:
            if f.name in t["skip"]:
                continue
            for candidates, _line, _ctx in chk.collect_keys(f):
                if any(c in strings for c in candidates):
                    continue
                # 보간의 서식을 모르면 %@ 와 %lld 후보가 모두 나온다 — 소스를 보고 고를 수 없으므로 %@ 를 우선한다
                # (Int 보간은 코드에서 specifier: 나 String(…) 없이 쓰이는 일이 드물다). 틀리면 check-l10n 이 MISSING 으로 알려 준다.
                key = next((c for c in candidates if "%lld" not in c), candidates[0])
                strings[key] = {}
                added += 1
                print(f"+ {t['name']}: {key!r}")
        save_catalog(t["catalog"], data)
    return added


def export(codes: list[str]) -> None:
    catalogs = {t["name"]: chk.load_catalog(t["catalog"]) for t in chk.TARGETS}
    all_keys = sorted({k for s in catalogs.values() for k in s})
    out_dir = ROOT / "l10n"
    out_dir.mkdir(exist_ok=True)
    for code in codes:
        d = {}
        for k in all_keys:
            val = ""
            for s in catalogs.values():
                if k in s and (v := chk.translation(s[k], code)):
                    val = v
            d[k] = val
        path = out_dir / f"ui.{code}.json"
        path.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        filled = sum(1 for v in d.values() if v)
        print(f"{path.relative_to(ROOT)}: {filled}/{len(d)} 번역됨")
    # 문맥 파일
    ctx: dict[str, dict] = {}
    for t in chk.TARGETS:
        for k, e in chk.key_contexts(t).items():
            c = ctx.setdefault(k, {"where": set(), "files": set(), "target": t["name"]})
            c["where"] |= e["where"]
            c["files"] |= e["files"]
    result = {}
    for k in all_keys:
        c = ctx.get(k, {"where": set(), "files": set(), "target": "app"})
        ko = ""
        for s in catalogs.values():
            if k in s:
                ko = chk.translation(s[k], "ko") or ko
        specs, _ = chk.placeholders(k)
        result[k] = {
            "where": sorted(c["where"]), "files": sorted(c["files"]), "target": c["target"],
            "ko": ko, "placeholders": specs, "limit": chk.ribbon_kind(c["where"]),
        }
    (out_dir / "context.json").write_text(json.dumps(result, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"l10n/context.json: {len(result)}개 키")


if __name__ == "__main__":
    codes = [a for a in sys.argv[1:] if not a.startswith("-")] or chk.LANGUAGES
    bad = [c for c in codes if c not in chk.LANGUAGES]
    if bad:
        print(f"알 수 없는 언어 코드 {bad} — 가능: {chk.LANGUAGES}")
        sys.exit(2)
    n = add_missing_keys()
    if n:
        print(f"카탈로그에 영어 키 {n}개 추가")
    export(codes)
