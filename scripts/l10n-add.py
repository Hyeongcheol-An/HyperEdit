#!/usr/bin/env python3
"""새 문자열의 한국어 번역을 String Catalog 에 추가한다.

사용:  python3 scripts/l10n-add.py l10n/<feature>.ko.json [...]

입력은 평평한 JSON  { "English key": "한국어" } .  각 키가 어느 타깃 코드에서 쓰이는지
(Apps/mac → Apps/mac/Localizable.xcstrings, Packages/HyperCore → HyperCore 카탈로그) 를 소스에서 찾아
해당 카탈로그에 "ko" 번역(state: translated)을 넣는다.  이미 있는 키는 번역만 갱신한다.
어느 소스에서도 못 찾은 키는 경고로 알리고 앱 카탈로그에 넣는다 (scripts/check-l10n.py 가 미사용으로 잡아 준다).
"""
import json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, ".."))
APP_CAT = os.path.join(ROOT, "Apps", "mac", "Localizable.xcstrings")
CORE_CAT = os.path.join(ROOT, "Packages", "HyperCore", "Sources", "HyperCore", "Resources", "Localizable.xcstrings")


def swift_sources(subdir):
    out = []
    for dirpath, _, files in os.walk(os.path.join(ROOT, subdir)):
        for f in files:
            if f.endswith(".swift"):
                out.append(os.path.join(dirpath, f))
    return out


def literal_pattern(key):
    """코드 리터럴에는 보간(\\(…)) 이 들어가므로 포맷 자리표시자를 와일드카드로 바꿔 찾는다."""
    parts = re.split(r"%(?:lld|@|\.\df|d|f)", key)
    return re.compile(r'"' + r".*?".join(re.escape(p) for p in parts) + r'"')


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def save(path, data):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2, sort_keys=True)
        fh.write("\n")


def main(paths):
    app_src = "\n".join(open(p, encoding="utf-8").read() for p in swift_sources("Apps/mac"))
    core_src = "\n".join(open(p, encoding="utf-8").read() for p in swift_sources("Packages/HyperCore/Sources"))
    cats = {APP_CAT: load(APP_CAT), CORE_CAT: load(CORE_CAT)}
    added = {APP_CAT: 0, CORE_CAT: 0}
    for path in paths:
        for key, ko in load(path).items():
            pat = literal_pattern(key)
            in_app, in_core = bool(pat.search(app_src)), bool(pat.search(core_src))
            targets = [t for t, hit in ((APP_CAT, in_app), (CORE_CAT, in_core)) if hit] or [APP_CAT]
            if not (in_app or in_core):
                print(f"WARN 코드에서 못 찾음 (앱 카탈로그에 넣음): {key!r}")
            for t in targets:
                entry = cats[t]["strings"].setdefault(key, {})
                loc = entry.setdefault("localizations", {})
                loc["ko"] = {"stringUnit": {"state": "translated", "value": ko}}
                added[t] += 1
    for t, data in cats.items():
        save(t, data)
        print(f"{os.path.relpath(t, ROOT)}: {added[t]}개 추가/갱신 → 총 {len(data['strings'])}개")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(2)
    main(sys.argv[1:])
