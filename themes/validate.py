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

# ---- 대비 린트 (WCAG 상대 휘도, 경고만 — 원본 테마를 충실히 재현한 팔레트는 기준 미달이어도 유지) ----
def lum(h):
    h = h.lstrip("#")[:6]
    def ch(c):
        c = int(c, 16) / 255
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = ch(h[0:2]), ch(h[2:4]), ch(h[4:6])
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
def contrast(a, b):
    la, lb = lum(a), lum(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)
src = json.load(open(os.path.join(HERE, "palettes.json"), encoding="utf-8"))
warns = 0
for t in src["themes"]:
    bg, bg_alt = t["bg"], t.get("bg_alt", t["bg"])
    checks = [("fg", t["fg"], bg, 4.5), ("fg", t["fg"], bg_alt, 4.5),
              ("fg_muted", t.get("fg_muted", t["fg"]), bg, 4.5), ("fg_muted", t.get("fg_muted", t["fg"]), bg_alt, 4.5),
              ("fg_dim", t.get("fg_dim", t["fg"]), bg, 3.0)]
    for name, fg, back, need in checks:
        c = contrast(fg, back)
        if c < need:
            warns += 1
            print(f"WARN {t['id']}: {name} {fg} on {back} = {c:.2f} (< {need})")
print(f"contrast lint: {warns} warning(s)")
