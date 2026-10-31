#!/usr/bin/env bash
# 성능 벤치마크. 사용: scripts/bench.sh [--compare <baseline.json>] [--skip-build] [--strict] [--launch-runs N] [--only <phases>]
#   Release 빌드 → 콜드 실행 시간 N회(기본 5, 첫 창까지) → `--bench` 하네스(Apps/mac/Bench.swift) → 번들/바이너리 크기
#   결과: build/bench/<git-sha>.json + .md (표는 stdout 에도 출력). --compare 는 기준 JSON 대비 변화율(%)을 표시하고 15 % 넘는 퇴행을 표시한다.
#   벤치는 임시 폴더의 자체 말뭉치와 휘발성 UserDefaults 만 쓴다 — 사용자의 문서·설정은 건드리지 않는다.
set -euo pipefail
cd "$(dirname "$0")/.."

BASELINE=""; SKIP_BUILD=0; STRICT=0; LAUNCH_RUNS=5; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --compare) BASELINE="$2"; shift 2 ;;
    --skip-build) SKIP_BUILD=1; shift ;;
    --strict) STRICT=1; shift ;;
    --launch-runs) LAUNCH_RUNS="$2"; shift 2 ;;
    --only) ONLY="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ "$SKIP_BUILD" = 0 ]; then scripts/build-mac.sh >/dev/null; fi
APP="$PWD/build/DerivedData/Build/Products/Release/HyperEdit.app"
BIN="$APP/Contents/MacOS/HyperEdit"
[ -x "$BIN" ] || { echo "no binary at $BIN (run scripts/build-mac.sh)" >&2; exit 1; }

SHA="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
OUT_DIR="$PWD/build/bench"; mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/$SHA.json"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/hyperedit-bench.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
printf '# bench start\n\nsmall start file\n' > "$TMP/start.md"
LAUNCH_LOG="$TMP/launch.log"

# 1. 콜드 실행 시간: 프로세스 시작(커널) → didFinishLaunching → 첫 ContentView → 첫 창. 첫 번째 실행은 캐시 워밍이라 버린다.
echo "launch ×$LAUNCH_RUNS …" >&2
for i in $(seq 0 "$LAUNCH_RUNS"); do
  "$BIN" --ephemeral --file "$TMP/start.md" --bench-launch-log "$LAUNCH_LOG" --quit-after-launch >/dev/null 2>&1 || true
  sleep 0.5
done

# 2. 벤치 하네스
echo "bench …" >&2
BENCH_ARGS=(--ephemeral --file "$TMP/start.md" --bench --bench-out "$OUT" --bench-commit "$SHA" --quit)
[ -n "$ONLY" ] && BENCH_ARGS+=(--bench-only "$ONLY")
"$BIN" "${BENCH_ARGS[@]}" 2> "$TMP/bench.stderr" || true
[ -f "$OUT" ] || { echo "bench produced no output; stderr:" >&2; tail -20 "$TMP/bench.stderr" >&2; exit 1; }

# 3. 크기 + 실행 시간을 JSON 에 합치고 표를 출력 (+ 비교)
BUNDLE_KB="$(du -sk "$APP" | cut -f1)"
BIN_KB="$(( $(stat -f %z "$BIN") / 1024 ))"
ARCHS="$(lipo -archs "$BIN" 2>/dev/null || echo unknown)"
python3 - "$OUT" "$LAUNCH_LOG" "$BUNDLE_KB" "$BIN_KB" "$ARCHS" "$BASELINE" "$STRICT" <<'EOF'
import json, re, sys, statistics
out, launch_log, bundle_kb, bin_kb, archs, baseline, strict = sys.argv[1:8]
r = json.load(open(out, encoding="utf-8"))

def metric(id, name, unit, samples, budget=None, budget_p95=None, info=False):
    s = sorted(samples)
    med = statistics.median(s)
    p95 = s[min(len(s) - 1, round((len(s) - 1) * 0.95))]
    ok = (budget is None or med <= budget) and (budget_p95 is None or p95 <= budget_p95)
    return {"id": id, "name": name, "unit": unit, "median": med, "p95": p95, "min": s[0], "max": s[-1], "n": len(s),
            "budgetMedian": budget, "budgetP95": budget_p95, "pass": ok, "informational": info}

# 실행 시간 (첫 줄 = 워밍업, 버림)
runs = []
try:
    for line in open(launch_log, encoding="utf-8"):
        kv = dict(re.findall(r"(\w+)=([\d.]+)", line))
        if "windowVisible" in kv: runs.append({k: float(v) for k, v in kv.items() if k != "pid"})
except FileNotFoundError:
    pass
runs = runs[1:] if len(runs) > 1 else runs
extra = []
if runs:
    extra.append(metric("launch.didFinishLaunching", "Cold launch → applicationDidFinishLaunching", "ms", [x["didFinishLaunching"] for x in runs], info=True))
    extra.append(metric("launch.contentView", "Cold launch → first ContentView.onAppear", "ms", [x["contentViewAppeared"] for x in runs], info=True))
    extra.append(metric("launch.window", "Cold launch → first window visible (process start → window)", "ms", [x["windowVisible"] for x in runs], budget=600))
extra.append(metric("size.bundle", "App bundle size (du -sk)", "MB", [int(bundle_kb) / 1024], budget=40, info=True))
extra.append(metric("size.binary", f"Executable size ({archs})", "MB", [int(bin_kb) / 1024], budget=30, info=True))
r["metrics"] = extra + r["metrics"]
r["allPass"] = all(m["pass"] or m["informational"] for m in r["metrics"])
json.dump(r, open(out, "w", encoding="utf-8"), indent=2, sort_keys=True, ensure_ascii=False)

base = {}
if baseline:
    try:
        base = {m["id"]: m for m in json.load(open(baseline, encoding="utf-8"))["metrics"]}
    except Exception as e:
        print(f"cannot read baseline {baseline}: {e}", file=sys.stderr)

def fmt(v, unit):
    if v is None: return "—"
    return (f"{v:.0f}" if v >= 100 else f"{v:.2f}") if unit == "ms" else f"{v:.1f}"

m = r["machine"]
print(f"## HyperEdit bench · v{r['version']} · {r['commit']} · {r['date']}\n")
print(f"Machine: {m['model']} · {m['cores']} cores · {m['memoryGB']} GB · {m['os']}  ")
ld = r.get("load", {})
if ld:
    under = max(ld["before"], ld["after"]) > ld["cores"]
    print(f"Load average (1 min) before/after: {ld['before']:.1f} / {ld['after']:.1f}" + (" — **measured under load, not a baseline**" if under else "") + "  ")
c = r["corpus"]
print("Corpus: " + " · ".join(f"{k} {v['bytes']//1024} KB / {v['lines']} lines" for k, v in sorted(c.items(), key=lambda kv: kv[1]["bytes"])) + "\n")
hdr = "| Metric | median | p95 | n | budget | result |" + (" Δ vs baseline |" if base else "")
print(hdr); print("|---|---:|---:|---:|---|---|" + ("---:|" if base else ""))
regressions = []
for x in r["metrics"]:
    bm, bp = x.get("budgetMedian"), x.get("budgetP95")   # Swift 의 JSONEncoder 는 nil 키를 생략한다
    b = fmt(bm, x["unit"]) + (" " + x["unit"] if bm is not None else "")
    if bp is not None: b += f" / p95 {fmt(bp, x['unit'])}"
    res = "PASS" if x["pass"] else ("over (info)" if x["informational"] else "FAIL")
    row = f"| {x['name']} `{x['id']}` | {fmt(x['median'], x['unit'])} {x['unit']} | {fmt(x['p95'], x['unit'])} | {x['n']} | {b} | {res} |"
    if base:
        d = ""
        if x["id"] in base and base[x["id"]]["median"] > 0:
            pct = (x["median"] - base[x["id"]]["median"]) / base[x["id"]]["median"] * 100
            flag = " REGRESSION" if pct > 15 and x["unit"] in ("ms", "MB", "%") and x["median"] - base[x["id"]]["median"] > 0.5 else ""
            d = f"{pct:+.0f}%{flag}"
            if flag: regressions.append(x["id"])
        row += f" {d} |"
    print(row)
fails = [x["id"] for x in r["metrics"] if not x["pass"] and not x["informational"]]
print("\n" + ("All budgets PASS." if not fails else "Budget failures: " + ", ".join(fails)))
if base: print("Regressions > 15 % vs baseline: " + (", ".join(regressions) if regressions else "none"))
print(f"\nJSON: {out}")
if strict == "1" and (fails or regressions): sys.exit(1)
EOF
STATUS=$?
# Markdown 표도 같은 이름으로 저장 (하네스가 쓴 .md 를 통합본으로 덮어쓴다)
python3 - "$OUT" <<'EOF' > "${OUT%.json}.md"
import json, sys
r = json.load(open(sys.argv[1], encoding="utf-8"))
def fmt(v, unit):
    if v is None: return "—"
    return (f"{v:.0f}" if v >= 100 else f"{v:.2f}") if unit == "ms" else f"{v:.1f}"
m = r["machine"]
print(f"## HyperEdit bench · v{r['version']} · {r['commit']} · {r['date']}\n")
print(f"Machine: {m['model']} · {m['cores']} cores · {m['memoryGB']} GB · {m['os']}  ")
ld = r.get("load", {})
if ld:
    under = max(ld["before"], ld["after"]) > ld["cores"]
    print(f"Load average (1 min) before/after: {ld['before']:.1f} / {ld['after']:.1f}" + (" — **measured under load, not a baseline**" if under else "") + "  ")
c = r["corpus"]
print("Corpus: " + " · ".join(f"{k} {v['bytes']//1024} KB / {v['lines']} lines" for k, v in sorted(c.items(), key=lambda kv: kv[1]["bytes"])) + "\n")
print("| Metric | median | p95 | n | budget | result |"); print("|---|---:|---:|---:|---|---|")
for x in r["metrics"]:
    bm, bp = x.get("budgetMedian"), x.get("budgetP95")   # Swift 의 JSONEncoder 는 nil 키를 생략한다
    b = fmt(bm, x["unit"]) + (" " + x["unit"] if bm is not None else "")
    if bp is not None: b += f" / p95 {fmt(bp, x['unit'])}"
    res = "PASS" if x["pass"] else ("over (info)" if x["informational"] else "FAIL")
    print(f"| {x['name']} `{x['id']}` | {fmt(x['median'], x['unit'])} {x['unit']} | {fmt(x['p95'], x['unit'])} | {x['n']} | {b} | {res} |")
fails = [x["id"] for x in r["metrics"] if not x["pass"] and not x["informational"]]
print("\n" + ("All budgets PASS." if not fails else "Budget failures: " + ", ".join(fails)))
EOF
exit $STATUS
