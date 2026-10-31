#!/usr/bin/env bash
# macOS 앱 빌드. 사용: scripts/build-mac.sh [Release|Debug] [--run [--file <path>]]  (기본 Release — Debug 는 1.3MB 문서에서 체감될 만큼 느림)
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-Release}"; shift || true
[ -d HyperEdit.xcodeproj ] || scripts/bootstrap.sh
DERIVED="$PWD/build/DerivedData"
set -o pipefail
xcodebuild -project HyperEdit.xcodeproj -scheme HyperEdit-mac -configuration "$CONFIG" \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" build 2>&1 | grep -E 'error:|warning: unre|BUILD|Compiling|Ld ' | tail -40
APP="$DERIVED/Build/Products/$CONFIG/HyperEdit.app"
echo "APP: $APP"
if [ "${1:-}" = "--run" ]; then shift; open -n "$APP" --args "$@"; fi
