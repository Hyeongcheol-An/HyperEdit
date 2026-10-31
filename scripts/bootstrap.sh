#!/usr/bin/env bash
# Xcode 프로젝트 생성 (XcodeGen). 사용: scripts/bootstrap.sh [--open]
set -euo pipefail
cd "$(dirname "$0")/.."
command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
xcodegen generate
echo "generated HyperEdit.xcodeproj"
if [ "${1:-}" = "--open" ]; then open HyperEdit.xcodeproj; fi
