#!/usr/bin/env python3
"""palettes.json -> docs/theme-preview.html (20종 테마 카드: 에디터 샘플 + 터미널 ANSI 스와치). 외부 리소스·JS 없음."""
import json, os, html
HERE = os.path.dirname(os.path.abspath(__file__))
src = json.load(open(os.path.join(HERE, "palettes.json"), encoding="utf-8"))
OUT = os.path.join(HERE, "..", "docs", "theme-preview.html")
SAMPLE = [
    ("comment", "# 2026-10-30 (금) 14:05  주간 메모 · weekly notes"),
    ("title", "## Release checklist"),
    ("plain", "Ship 0.3.0, then write the notes  →  "), ("link", "https://github.com/Hyeongcheol-An/HyperEdit"),
    ("keyword", "def "), ("function", "calc"), ("punctuation", "("), ("variable", "a"), ("punctuation", ", "), ("variable", "b"), ("punctuation", "):"),
    ("newline", ""),
    ("plain", "    "), ("keyword", "return "), ("variable", "a"), ("operator", " + "), ("variable", "b"), ("operator", " * "), ("number", "0.25"), ("plain", "   "), ("string", "'3+0.5+0.25 ⇒ 3.75'"),
    ("newline", ""),
    ("type", "SELECT"), ("plain", " "), ("property", "title"), ("punctuation", ", "), ("property", "created"), ("plain", " "), ("type", "FROM"), ("plain", " "), ("tag", "notes"), ("plain", " "), ("type", "WHERE"), ("plain", " "), ("attribute", "year"), ("operator", " = "), ("constant", "2026"), ("punctuation", ";"),
]
def card(t):
    s, a = t["syntax"], t["ansi"]
    fg, bg = t["fg"], t["bg"]
    def span(kind, text):
        if kind == "newline": return "<br>"
        col = {"plain": fg}.get(kind) or s.get(kind, fg)
        style = f"color:{col}" + (";font-style:italic" if kind == "comment" else "") + (";font-weight:700" if kind == "title" else "")
        return f'<span style="{style}">{html.escape(text)}</span>'
    code = "".join(span(k, v) for k, v in SAMPLE)
    sw = "".join(f'<i title="{k}" style="background:{a[k]}"></i>' for k in "black red green yellow blue magenta cyan white".split())
    swb = "".join(f'<i title="bright_{k}" style="background:{a["bright_"+k]}"></i>' for k in "black red green yellow blue magenta cyan white".split())
    sel = t.get("selection", t["accent"])
    return f'''
<section class="card" style="background:{bg};color:{fg};border-color:{t.get("border", t["accent"])}">
  <header style="background:{t.get("bg_alt", bg)};border-bottom:1px solid {t.get("border", t["accent"])}">
    <b>{html.escape(t["name"])}</b> <small>{t["appearance"]}</small>
    <span class="dot" style="background:{t["accent"]}" title="accent"></span>
    <span class="dot" style="background:{t.get("cursor", t["accent"])}" title="cursor"></span>
  </header>
  <pre style="background:{bg}"><span class="ln" style="color:{t.get("fg_dim", fg)}">34523<br>34524<br>34525<br>34526</span><code>{code}</code></pre>
  <div class="sel" style="background:{sel};color:{fg}">선택 영역 selection</div>
  <div class="ansi">{sw}</div><div class="ansi">{swb}</div>
  <footer style="color:{t.get("fg_muted", fg)}">{html.escape(t.get("origin", ""))}</footer>
</section>'''
page = f'''<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>HyperEdit Themes Preview</title>
<style>
:root {{ color-scheme: light dark; }}
body {{ margin:0; padding:16px; font:14px/1.5 -apple-system, "Pretendard", system-ui, sans-serif; background:#111; color:#ddd; }}
h1 {{ font-size:18px; margin:0 0 12px; }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill, minmax(420px, 1fr)); gap:14px; }}
.card {{ border:1px solid; border-radius:10px; overflow:hidden; }}
.card header {{ padding:8px 12px; display:flex; gap:8px; align-items:center; }}
.card header small {{ opacity:.7; }}
.dot {{ width:12px; height:12px; border-radius:50%; display:inline-block; margin-left:auto; }}
.dot + .dot {{ margin-left:4px; }}
pre {{ margin:0; padding:10px 12px; font:12.5px/1.6 "Fira Code", "D2Coding", ui-monospace, Menlo, monospace; display:flex; gap:12px; overflow:auto; }}
.ln {{ text-align:right; user-select:none; }}
.sel {{ margin:0 12px 8px; padding:2px 8px; border-radius:4px; font:12px "Fira Code", ui-monospace, monospace; display:inline-block; }}
.ansi {{ display:flex; gap:3px; padding:0 12px 6px; }} .ansi i {{ width:22px; height:14px; border-radius:3px; display:inline-block; }}
footer {{ padding:0 12px 10px; font-size:11.5px; }}
@media (max-width:480px) {{ .grid {{ grid-template-columns:1fr; }} }}
</style></head><body>
<h1>HyperEdit Themes — {len(src["themes"])}종 미리보기 <small style="opacity:.6">(themes/palettes.json → build_preview.py)</small></h1>
<div class="grid">{"".join(card(t) for t in src["themes"])}</div>
</body></html>'''
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, "w", encoding="utf-8").write(page)
print("wrote", os.path.normpath(OUT), f"({len(page)//1024} KB)")
