#!/usr/bin/env bash
# 사용: scripts/set-version.sh 0.2.0 [build_number]
set -euo pipefail
v="${1:?version required}"; b="${2:-1}"
root="$(cd "$(dirname "$0")/.." && pwd)"
echo "$v" > "$root/VERSION"
cfg="$root/Config/Version.xcconfig"
tmp="$(mktemp)"
sed -E "s/^MARKETING_VERSION = .*/MARKETING_VERSION = $v/" "$cfg" > "$tmp"
if [ -n "$b" ]; then sed -E -i.bak "s/^CURRENT_PROJECT_VERSION = .*/CURRENT_PROJECT_VERSION = $b/" "$tmp" && rm -f "$tmp.bak"; fi
mv "$tmp" "$cfg"
echo "version -> $v${b:+ (build $b)}"
