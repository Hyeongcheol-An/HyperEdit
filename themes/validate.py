#!/usr/bin/env python3
"""dist/hyperedit-themes.json 이 Zed v0.2.0 테마 스키마 키 세트를 모두 갖추고 색 형식이 올바른지 검사."""
import json, os, re, sys
HERE = os.path.dirname(os.path.abspath(__file__))
out = json.load(open(os.path.join(HERE, "dist", "hyperedit-themes.json"), encoding="utf-8"))
keys = json.load(open(os.path.join(HERE, "zed_schema_keys.json"), encoding="utf-8"))
style_keys, syntax_keys = set(keys["style"]), set(keys["syntax"])
hexre = re.compile(r"^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$")
names = [t["name"] for t in out["themes"]]
assert len(names) == len(set(names)), "duplicate theme names"
for t in out["themes"]:
    st = t["style"]; have = {k for k in st if k not in ("syntax", "players", "accents")}
    assert style_keys <= have, (t["name"], "missing style keys", sorted(style_keys - have))
    assert syntax_keys <= set(st["syntax"]), (t["name"], "missing syntax keys", sorted(syntax_keys - set(st["syntax"])))
    assert len(st["players"]) == 8, (t["name"], "players")
    for k, v in st.items():
        if isinstance(v, str) and v.startswith("#"): assert hexre.match(v), (t["name"], k, v)
    for k, v in st["syntax"].items(): assert hexre.match(v["color"]), (t["name"], k, v)
print(f"OK: {len(names)} themes valid ({sum(1 for t in out['themes'] if t['appearance']=='light')} light)")
