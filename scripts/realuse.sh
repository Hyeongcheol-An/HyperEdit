#!/usr/bin/env bash
# 실사용 시뮬레이션 (Apps/mac/RealUse). 사용: scripts/realuse.sh [--skip-build] [--only <scenarios>] [--out <dir>] [--suite <name>] [--timeout <sec>] [--height <pt>] [-- <앱 인자…>]
#   창은 1280 × 972 pt 로 고정한다 (`--height` 로 높이를 바꿔 다른 화면 구성을 흉내 낸다). 기본 창 높이는 화면의 쓸 수 있는 높이를 따르므로 고정하지 않으면
#   모니터·Dock 배치에 따라 편집기 높이가 달라져 결과를 견줄 수 없다.
#   `--` 뒤의 인자는 앱에 그대로 넘긴다 (예: `-- -AppleLanguages '("ar")'` 로 다른 언어·글 방향에서 돌린다).
#   Release 빌드 → 임시 시작 파일·휘발성 설정으로 앱을 띄워 `--realuse` 하네스를 돌린다. 키·스크롤·마우스 이벤트를 실제 창에 보내고
#   불변식(레이아웃 틈·겹침, 뷰포트, 캐럿, 거터, 잉크, 정지)을 검사한다. 결과: <out>/report.md · report.json · log.txt · PNG.
#   앱을 활성화하지 않으므로 쓰고 있는 다른 앱의 포커스를 뺏지 않는다. 끝나지 않으면 이 스크립트가 띄운 PID 만 종료한다.
set -euo pipefail
cd "$(dirname "$0")/.."
SKIP_BUILD=0; ONLY=""; OUT="$PWD/build/realuse"; SUITE="hyperedit.realuse"; TIMEOUT=900; HEIGHT=972; EXTRA=()
while [ $# -gt 0 ]; do
  case "$1" in
    --skip-build) SKIP_BUILD=1; shift ;;
    --only) ONLY="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --suite) SUITE="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --height) HEIGHT="$2"; shift 2 ;;
    --) shift; EXTRA=("$@"); break ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done
if [ "$SKIP_BUILD" = 0 ]; then scripts/build-mac.sh >/dev/null; fi
BIN="$PWD/build/DerivedData/Build/Products/Release/HyperEdit.app/Contents/MacOS/HyperEdit"
[ -x "$BIN" ] || { echo "no binary at $BIN (run scripts/build-mac.sh)" >&2; exit 1; }
rm -rf "$OUT"; mkdir -p "$OUT"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/hyperedit-realuse-start.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
printf '# real-use start\n\nsmall start file\n' > "$TMP/start.md"
# `-ApplePersistenceIgnoreState YES`: 저장된 창 상태(번들 ID 공용 — 설치된 HyperEdit 과 같이 쓴다)를 읽지도 쓰지도 않는다. 앱도 같은 값을 기본값으로 등록하지만
# 등록 도메인은 우선순위가 가장 낮다 → 인자로도 넘긴다. `-키 값` 쌍으로 읽히도록 맨 앞에 둔다 (값 없는 `--옵션` 바로 뒤에 두면 그 옵션의 값으로 짝지어진다)
ARGS=(-ApplePersistenceIgnoreState YES --ephemeral --ephemeral-suite "$SUITE" --file "$TMP/start.md" --realuse --realuse-out "$OUT" --window-width 1280 --window-height "$HEIGHT" --quit)
[ -n "$ONLY" ] && ARGS+=(--realuse-only "$ONLY")
[ ${#EXTRA[@]} -gt 0 ] && ARGS+=("${EXTRA[@]}")
"$BIN" "${ARGS[@]}" > "$OUT/stderr.txt" 2>&1 &
PID=$!
for _ in $(seq 1 $((TIMEOUT / 2))); do sleep 2; kill -0 "$PID" 2>/dev/null || break; done
if kill -0 "$PID" 2>/dev/null; then echo "TIMEOUT after ${TIMEOUT}s — killing pid $PID" | tee -a "$OUT/stderr.txt"; kill "$PID" 2>/dev/null || true; sleep 2; kill -9 "$PID" 2>/dev/null || true; fi
if [ -f "$OUT/report.md" ]; then cat "$OUT/report.md"; else echo "no report (crash or timeout) — last log lines:"; tail -15 "$OUT/stderr.txt"; exit 1; fi
