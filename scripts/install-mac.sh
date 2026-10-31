#!/usr/bin/env bash
# Release 빌드 후 ~/Applications/HyperEdit.app 으로 설치. 사용: scripts/install-mac.sh [--open]
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d HyperEdit.xcodeproj ] || scripts/bootstrap.sh
DERIVED="$PWD/build/DerivedData"
set -o pipefail
xcodebuild -project HyperEdit.xcodeproj -scheme HyperEdit-mac -configuration Release \
  -destination 'platform=macOS' -derivedDataPath "$DERIVED" build 2>&1 | grep -E 'error:|BUILD' | tail -5
SRC="$DERIVED/Build/Products/Release/HyperEdit.app"
DEST="$HOME/Applications/HyperEdit.app"
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$SRC" "$DEST"
echo "installed → $DEST"
if [ "${1:-}" = "--open" ]; then open "$DEST"; fi
