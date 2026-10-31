#!/usr/bin/env python3
"""palettes.json -> Zed 테마 파일(hyperedit-themes.json) 생성기.

사용:  python3 build_zed_theme.py [--install]
  --install : 생성 결과를 ~/.config/zed/themes/hyperedit-themes.json 에도 복사 (Zed는 폴더를 감시하므로 즉시 반영)

팔레트의 소수 필수 색(bg/fg/accent/ansi/syntax)에서 Zed v0.2.0 스키마의 173개 스타일 키 + 102개 구문 키를 유도한다.
Swift 앱 쪽 테마 엔진도 같은 palettes.json 을 읽도록 설계되어 있어 두 환경의 색이 항상 일치한다.
"""
import json, os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "palettes.json")
OUT = os.path.join(HERE, "dist", "hyperedit-themes.json")
ZED_DIR = os.path.expanduser("~/.config/zed/themes")

# ---------- 색 유틸 ----------
def parse(c):
    c = c.lstrip("#")
    if len(c) == 3: c = "".join(ch * 2 for ch in c)
    r, g, b = int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)
    a = int(c[6:8], 16) / 255 if len(c) == 8 else 1.0
    return r, g, b, a

def hexa(r, g, b, a=1.0):
    s = "#%02x%02x%02x" % (round(r), round(g), round(b))
    return s + ("%02x" % round(a * 255) if a < 0.999 else "")

def mix(c1, c2, t):
    r1, g1, b1, _ = parse(c1); r2, g2, b2, _ = parse(c2)
    return hexa(r1 + (r2 - r1) * t, g1 + (g2 - g1) * t, b1 + (b2 - b1) * t)

def alpha(c, a):
    r, g, b, _ = parse(c)
    return hexa(r, g, b, a)

def opaque(c):
    r, g, b, _ = parse(c)
    return hexa(r, g, b)

TRANSPARENT = "#00000000"

# ---------- 구문 키 매핑 ----------
def syntax_map(s, p):
    fg, fg_dim, st = p["fg"], p["fg_dim"], p["status"]
    def e(color, style=None, weight=None):
        return {"color": color, "font_style": style, "font_weight": weight}
    m = {}
    def put(keys, color, style=None, weight=None):
        for k in keys.split(): m[k] = e(color, style, weight)
    put("variable primary parent embedded", s["variable"])
    put("variable.builtin variable.special symbol", s["constant"])
    put("variable.parameter parameter", s["variable"], "italic")
    put("variable.member field property", s["property"])
    put("constant constant.builtin constant.macro boolean number number.float float", s["number"])
    put("module namespace concept enum variant type type.builtin type.definition type.interface type.super constructor", s["type"])
    put("type.class.definition", s["type"], None, 700)
    put("label attribute selector.pseudo function.decorator preproc tag.attribute", s["attribute"])
    put("string string.documentation string.doc character text.literal", s["string"])
    put("string.regexp string.regex string.escape string.special string.special.path string.special.symbol character.special", s["special"])
    put("string.special.url link_uri", s["link"])
    put("link_text", s["link"], "italic")
    put("tag", s["tag"])
    put("tag.delimiter punctuation punctuation.delimiter punctuation.bracket punctuation.special punctuation.special.symbol", s["punctuation"])
    put("punctuation.list_marker", s["keyword"])
    put("function function.builtin function.call function.macro function.method function.method.call", s["function"])
    put("operator keyword.operator", s["operator"])
    put("keyword keyword.modifier keyword.type keyword.coroutine keyword.function keyword.import keyword.repeat keyword.return "
        "keyword.debug keyword.exception keyword.conditional keyword.conditional.ternary keyword.directive keyword.directive.define keyword.export", s["keyword"])
    put("comment comment.doc comment.documentation predoc tag.doctype", s["comment"], "italic")
    put("comment.info comment.note", st["info"], "italic")
    put("comment.error", st["error"], "italic")
    put("comment.warning comment.warn", st["warning"], "italic")
    put("comment.hint hint", st["hint"], "italic")
    put("comment.todo", st["warning"], None, 700)
    put("diff.plus", st["success"])
    put("diff.minus", st["error"])
    put("emphasis", fg, "italic")
    put("emphasis.strong", fg, None, 700)
    put("title", s["title"], None, 700)
    put("predictive", fg_dim, "italic")
    return m

# ---------- 스타일 키 유도 ----------
def build_theme(t):
    dark = t["appearance"] == "dark"
    bg, fg = t["bg"], t["fg"]
    black, white = "#000000", "#ffffff"
    p = {
        "bg": bg, "fg": fg,
        "bg_alt": t.get("bg_alt") or (mix(bg, black, .18) if dark else mix(bg, black, .04)),
        "bg_elev": t.get("bg_elev") or mix(bg, fg, .08),
        "fg_muted": t.get("fg_muted") or mix(fg, bg, .35),
        "fg_dim": t.get("fg_dim") or mix(fg, bg, .55),
        "border": t.get("border") or mix(bg, fg, .15),
        "line_hl": t.get("line_hl") or mix(bg, fg, .05),
        "accent": t["accent"],
        "cursor": t.get("cursor") or t["accent"],
        "selection": t.get("selection") or alpha(t["accent"], .30),
    }
    a = t["ansi"]
    for k in ("black red green yellow blue magenta cyan white").split():
        a.setdefault("bright_" + k, mix(a[k], white if dark else black, .15))
    s = t["syntax"]
    st = t.get("status", {})
    st = {"error": st.get("error", a["bright_red"] if dark else a["red"]),
          "warning": st.get("warning", a["bright_yellow"] if dark else a["yellow"]),
          "info": st.get("info", a["bright_blue"] if dark else a["blue"]),
          "success": st.get("success", a["bright_green"] if dark else a["green"]),
          "hint": st.get("hint", mix(p["fg_muted"], a["blue"], .4))}
    p["status"] = st
    sel = p["selection"]
    hover_src = white if dark else black
    style = {
        "background.appearance": "opaque",
        "border": p["border"], "border.variant": alpha(p["border"], .6), "border.focused": p["accent"],
        "border.selected": p["accent"], "border.transparent": TRANSPARENT, "border.disabled": alpha(p["border"], .4),
        "elevated_surface.background": p["bg_elev"], "surface.background": p["bg_alt"], "background": p["bg_alt"],
        "element.background": p["bg_alt"], "element.hover": alpha(hover_src, .08), "element.active": alpha(hover_src, .14),
        "element.selected": alpha(p["accent"], .22), "element.disabled": TRANSPARENT,
        "drop_target.background": alpha(p["accent"], .20),
        "ghost_element.background": TRANSPARENT, "ghost_element.hover": alpha(hover_src, .07), "ghost_element.active": alpha(hover_src, .12),
        "ghost_element.selected": alpha(p["accent"], .18), "ghost_element.disabled": TRANSPARENT,
        "text": fg, "text.muted": p["fg_muted"], "text.placeholder": p["fg_dim"], "text.disabled": p["fg_dim"], "text.accent": p["accent"],
        "icon": fg, "icon.muted": p["fg_muted"], "icon.disabled": p["fg_dim"], "icon.placeholder": p["fg_dim"], "icon.accent": p["accent"],
        "status_bar.background": p["bg_alt"], "title_bar.background": p["bg_alt"], "title_bar.inactive_background": p["bg_alt"],
        "toolbar.background": bg, "tab_bar.background": p["bg_alt"], "tab.inactive_background": p["bg_alt"], "tab.active_background": bg,
        "search.match_background": alpha(a["yellow"] if not dark else a["bright_yellow"], .35),
        "search.active_match_background": alpha(a["yellow"] if not dark else a["bright_yellow"], .65),
        "panel.background": p["bg_alt"], "panel.focused_border": p["accent"], "panel.indent_guide": alpha(p["border"], .7),
        "panel.indent_guide_active": p["fg_muted"], "panel.indent_guide_hover": p["fg_muted"], "panel.overlay_background": p["bg_alt"],
        "pane.focused_border": p["accent"], "pane_group.border": p["border"],
        "scrollbar.thumb.background": alpha(fg, .18), "scrollbar.thumb.hover_background": alpha(fg, .30),
        "scrollbar.thumb.active_background": alpha(fg, .40), "scrollbar.thumb.border": TRANSPARENT,
        "scrollbar.track.background": TRANSPARENT, "scrollbar.track.border": alpha(p["border"], .4),
        "minimap.thumb.background": alpha(fg, .12), "minimap.thumb.hover_background": alpha(fg, .20),
        "minimap.thumb.active_background": alpha(fg, .28), "minimap.thumb.border": TRANSPARENT,
        "editor.foreground": fg, "editor.background": bg, "editor.gutter.background": bg, "editor.subheader.background": p["bg_alt"],
        "editor.active_line.background": p["line_hl"], "editor.highlighted_line.background": p["line_hl"],
        "editor.line_number": p["fg_dim"], "editor.active_line_number": fg,
        "editor.invisible": alpha(fg, .18),  # show_whitespaces: all 사용자를 위해 아주 은은하게
        "editor.wrap_guide": p["border"], "editor.active_wrap_guide": p["fg_muted"],
        "editor.document_highlight.bracket_background": alpha(p["accent"], .25),
        "editor.document_highlight.read_background": alpha(p["accent"], .16),
        "editor.document_highlight.write_background": alpha(p["accent"], .28),
        "editor.indent_guide": alpha(p["border"], .8), "editor.indent_guide_active": p["fg_muted"],
        "editor.debugger_active_line.background": alpha(a["yellow"], .15),
        "terminal.background": bg, "terminal.ansi.background": bg, "terminal.foreground": fg,
        "terminal.dim_foreground": p["fg_muted"], "terminal.bright_foreground": fg if dark else p["fg"],
        "link_text.hover": p["accent"],
        "debugger.accent": st["error"],
        "version_control.added": st["success"], "version_control.deleted": st["error"], "version_control.modified": st["warning"],
        "version_control.renamed": st["info"], "version_control.conflict": a["bright_magenta"] if dark else a["magenta"],
        "version_control.conflict_marker.ours": alpha(st["success"], .25), "version_control.conflict_marker.theirs": alpha(st["info"], .25),
        "version_control.ignored": p["fg_dim"],
        "vim.mode.text": bg, "vim.normal.foreground": bg, "vim.helix_normal.foreground": bg, "vim.visual.foreground": bg,
        "vim.helix_select.foreground": bg, "vim.insert.foreground": bg, "vim.visual_line.foreground": bg, "vim.visual_block.foreground": bg,
        "vim.replace.foreground": bg, "vim.normal.background": a["blue"], "vim.helix_normal.background": a["blue"],
        "vim.visual.background": a["magenta"], "vim.helix_select.background": a["magenta"], "vim.insert.background": a["green"],
        "vim.visual_line.background": a["magenta"], "vim.visual_block.background": a["magenta"], "vim.replace.background": a["red"],
    }
    for k in "black white red green yellow blue magenta cyan".split():
        style["terminal.ansi." + k] = a[k]
        style["terminal.ansi.bright_" + k] = a["bright_" + k]
        style["terminal.ansi.dim_" + k] = mix(a[k], bg, .45)
    semantic = {"conflict": style["version_control.conflict"], "created": st["success"], "deleted": st["error"], "hidden": p["fg_dim"],
                "hint": st["hint"], "ignored": p["fg_dim"], "modified": st["warning"], "predictive": p["fg_dim"], "renamed": st["info"],
                "info": st["info"], "warning": st["warning"], "error": st["error"], "success": st["success"], "unreachable": p["fg_dim"]}
    for k, c in semantic.items():
        style[k] = c; style[k + ".border"] = alpha(c, .40); style[k + ".background"] = alpha(c, .14)
    player_colors = [p["cursor"], a["bright_red"], a["bright_green"], a["bright_yellow"], a["bright_blue"], a["bright_magenta"], a["bright_cyan"], s["special"]]
    style["players"] = [{"cursor": c, "background": c, "selection": (sel if i == 0 else alpha(c, .24))} for i, c in enumerate(player_colors)]
    style["accents"] = [s["keyword"], s["function"], s["string"], s["number"], s["type"], s["special"], s["tag"]]
    style["syntax"] = syntax_map(s, p)
    return {"name": t["name"], "appearance": t["appearance"], "style": style}

def main():
    src = json.load(open(SRC, encoding="utf-8"))
    out = {"$schema": "https://zed.dev/schema/themes/v0.2.0.json", "name": src["family"], "author": src["author"],
           "themes": [build_theme(t) for t in src["themes"]]}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    json.dump(out, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(f"wrote {OUT}: {len(out['themes'])} themes")
    # Swift 패키지 리소스에도 동일 팔레트를 복사 (앱 테마 엔진의 단일 소스 유지)
    pkg = os.path.join(HERE, "..", "Packages", "HyperCore", "Sources", "HyperCore", "Resources", "palettes.json")
    if os.path.isdir(os.path.dirname(pkg)):
        shutil.copyfile(SRC, pkg); print("synced ->", os.path.normpath(pkg))
    if "--install" in sys.argv:
        os.makedirs(ZED_DIR, exist_ok=True)
        dst = os.path.join(ZED_DIR, "hyperedit-themes.json"); shutil.copyfile(OUT, dst); print("installed ->", dst)

if __name__ == "__main__":
    main()
