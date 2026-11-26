#!/usr/bin/env bash
# 실사용 시뮬레이션 (Apps/mac/RealUse). 사용: scripts/realuse.sh [--skip-build] [--only <scenarios>] [--out <dir>] [--suite <name>] [--timeout <sec>] [--height <pt>] [-- <앱 인자…>]
#   창은 1280 × 972 pt 로 고정한다 (`--height` 로 높이를 바꿔 다른 화면 구성을 흉내 낸다). 기본 창 높이는 화면의 쓸 수 있는 높이를 따르므로 고정하지 않으면
#   모니터·Dock 배치에 따라 편집기 높이가 달라져 결과를 견줄 수 없다.
#   `--` 뒤의 인자는 앱에 그대로 넘긴다 (예: `-- -AppleLanguages '("ar")'` 로 다른 언어·글 방향에서 돌린다).
#   Release 빌드 → 임시 시작 파일·휘발성 설정으로 앱을 띄워 `--realuse` 하네스를 돌린다. 키·스크롤·마우스 이벤트를 실제 창에 보내고
#   불변식(레이아웃 틈·겹침, 뷰포트, 캐럿, 거터, 잉크, 정지)을 검사한다. 결과: <out>/report.md · report.json · log.txt · PNG.
#   앱을 활성화하지 않으므로 쓰고 있는 다른 앱의 포커스를 뺏지 않는다. 끝나지 않으면, 그리고 이 스크립트가 중간에 끝나면(Ctrl-C·종료 신호·오류)
#   이 스크립트가 띄운 PID 만 종료한다.
#   `open-launch`(명령줄로 넘긴 파일이 탭으로 열리는가)는 앱이 뜰 때의 일이라 따로 한 번 더 띄운다: 전체 실행이거나 `--only` 에 `open-launch` 가 있으면,
#   임시 폴더에 만든 파일들을 맨 인자로 준 짧은 실행을 덧붙이고 그 결과를 <out>/open-launch/ 에 남긴다 (보고서는 이어서 출력한다). 다른 시나리오의
#   실행에는 맨 인자를 주지 않는다 — 시작할 때의 탭이 달라진다.
#   실행이 자기 폴더 밖의 파일이라며 열지 않은 것(`[automation] not opened …` — 도는 중에 Finder 에서 연 파일이 이 인스턴스로 왔을 때)은 보고서 뒤에 적는다.
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
# 스크립트가 어떻게 끝나든 띄운 앱을 남기지 않는다. 앱은 비대화형 셸의 백그라운드 작업이라 SIGINT 를 무시한 채 뜬다 — Ctrl-C 로는 스크립트만 죽고
# 테스트 인스턴스는 시작 파일이 지워진 채 뒤에서 계속 돈다. 신호를 받으면 EXIT 로 넘겨 거기서 정리한다 (이 스크립트가 띄운 PID 만)
APP_PID=""
cleanup() {
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$APP_PID" 2>/dev/null || break; sleep 0.2; done
    kill -9 "$APP_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP
printf '# real-use start\n\nsmall start file\n' > "$TMP/start.md"
# `-ApplePersistenceIgnoreState YES`: 저장된 창 상태(번들 ID 공용 — 설치된 HyperEdit 과 같이 쓴다)를 읽지도 쓰지도 않는다. 앱도 같은 값을 기본값으로 등록하지만
# 등록 도메인은 우선순위가 가장 낮다 → 인자로도 넘긴다. Foundation 은 한 줄표로 시작하는 인자와 그 뒤의 한 줄표로 시작하지 않는 인자를 `-키 값` 으로 짝짓는다
# (실측 macOS 27) — 값 없는 `--옵션` 바로 뒤에 와도 짝은 맞는다 (`--quit -AppleLanguages '("ar")'` 는 아랍어로 돈다. 정말 먹었는지는 로그의
# `launch: language=` 줄로 본다). 짝이 어긋나는 것은 값 없는 옵션 바로 뒤에 맨 인자가 올 때다 (`--quit a.md` — 아래 open-launch 가 일부러 그렇게 준다)
ARGS=(-ApplePersistenceIgnoreState YES --ephemeral --ephemeral-suite "$SUITE" --file "$TMP/start.md" --realuse --realuse-out "$OUT" --window-width 1280 --window-height "$HEIGHT" --quit)
[ -n "$ONLY" ] && ARGS+=(--realuse-only "$ONLY")
[ ${#EXTRA[@]} -gt 0 ] && ARGS+=("${EXTRA[@]}")

# run_app <out> <제한 시간(초)> <인자…>: 앱을 띄우고 끝나기를 기다린다. 끝나지 않으면 그 PID 만 종료한다
run_app() {
  local out="$1" limit="$2"; shift 2
  "$BIN" "$@" > "$out/stderr.txt" 2>&1 &
  APP_PID=$!
  for _ in $(seq 1 $((limit / 2))); do sleep 2; kill -0 "$APP_PID" 2>/dev/null || break; done
  if kill -0 "$APP_PID" 2>/dev/null; then echo "TIMEOUT after ${limit}s — killing pid $APP_PID" | tee -a "$out/stderr.txt"; kill "$APP_PID" 2>/dev/null || true; sleep 2; kill -9 "$APP_PID" 2>/dev/null || true; fi
  APP_PID=""
}

# refused <out>: 이 실행이 열지 않은 밖의 파일. `open-external` 시나리오가 일부러 넘기는 것(그 시나리오 구간의 줄)은 뺀다
refused() {
  local lines
  lines="$(awk '/^\[realuse\] === scenario open-external/ { own = 1 } /^\[realuse\] === end open-external/ { own = 0 } !own && /^\[automation\] not opened/' "$1/stderr.txt" 2>/dev/null || true)"
  [ -z "$lines" ] || { echo; echo "files this run did not open (they came from outside its folders — open them again once the run is over):"; echo "$lines"; }
}

run_app "$OUT" "$TIMEOUT" "${ARGS[@]}"
if [ -f "$OUT/report.md" ]; then cat "$OUT/report.md"; else echo "no report (crash or timeout) — last log lines:"; tail -15 "$OUT/stderr.txt"; exit 1; fi
refused "$OUT"

# open-launch 를 파일과 함께: 텍스트 파일 둘(하나는 한글 이름) · 폴더 · 없는 파일. 값이 없는 옵션(`--quit`) 바로 뒤에 둔다 — AppKit 은 그 자리의 첫 파일을
# 옵션의 값으로 삼켜 넘기지 않는다(앱이 실행 인자를 직접 가려 연다). 시나리오는 무엇이 넘어갔는지를 환경 변수로 받아, 앱의 인자 해석과 따로 견준다
case ",$ONLY," in
  ,,|*,open-launch,*)
    mkdir -p "$OUT/open-launch" "$TMP/launch-folder"
    printf '# first file given at launch\n\none\n' > "$TMP/launch one.md"
    printf '# 실행할 때 넘긴 둘째 파일\n\n둘\n' > "$TMP/실행 메모.md"
    FILES=("$TMP/launch one.md" "$TMP/launch-folder" "$TMP/launch-missing.md" "$TMP/실행 메모.md")
    LAUNCH=(-ApplePersistenceIgnoreState YES --ephemeral --ephemeral-suite "$SUITE" --file "$TMP/start.md" --realuse --realuse-out "$OUT/open-launch" --realuse-only open-launch
            --window-width 1280 --window-height "$HEIGHT")
    [ ${#EXTRA[@]} -gt 0 ] && LAUNCH+=("${EXTRA[@]}")
    LAUNCH+=(--quit "${FILES[@]}")
    export REALUSE_LAUNCH_FILES; REALUSE_LAUNCH_FILES="$(printf '%s\n' "${FILES[@]}")"
    # 시나리오 하나짜리 짧은 실행이다(몇 초) — 전체 실행의 제한 시간을 그대로 주지 않는다
    run_app "$OUT/open-launch" "$((TIMEOUT < 120 ? TIMEOUT : 120))" "${LAUNCH[@]}"
    echo; echo "--- open-launch, launched with files ($OUT/open-launch)"
    if [ -f "$OUT/open-launch/report.md" ]; then cat "$OUT/open-launch/report.md"; else echo "no report (crash or timeout) — last log lines:"; tail -15 "$OUT/open-launch/stderr.txt"; exit 1; fi
    refused "$OUT/open-launch"
    ;;
esac
