#!/usr/bin/env bash
# DMG 패키징 (+ Developer ID 서명 · 공증 · 스테이플). 사용: scripts/make-dmg.sh [version]
#   서명 모드(자동 판별): Developer ID Application 인증서 → developer-id / Apple Development → dev(자동 서명) / 없음 → ad-hoc
#   공증(있을 때만): ASC_KEY_ID + ASC_ISSUER_ID + (ASC_KEY_P8_PATH | ASC_KEY_P8[base64]) 또는 keychain 프로필 NOTARY_PROFILE(기본 HyperEdit)
#   결과: dist/HyperEdit-<version>.dmg, dist/SHA256SUMS
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-$(cat VERSION)}"
DERIVED="$PWD/build/DerivedData"
[ -d HyperEdit.xcodeproj ] || scripts/bootstrap.sh
mkdir -p build dist

# ---------- 서명 모드 ----------
IDENTITY="${DEVELOPER_ID_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"' || true)"
fi
SIGN_ARGS=(); MODE=ad-hoc
if [ -n "$IDENTITY" ]; then
  MODE=developer-id
  TEAM="$(printf '%s' "$IDENTITY" | sed -E 's/.*\(([A-Z0-9]{10})\)$/\1/')"
  SIGN_ARGS=(CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="$TEAM" PROVISIONING_PROFILE_SPECIFIER= OTHER_CODE_SIGN_FLAGS=--timestamp CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
  MODE=dev
else
  SIGN_ARGS=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)
fi
echo "signing mode: $MODE ${IDENTITY:+($IDENTITY)}"

# ---------- 공증 자격 증명 ----------
NOTARY_ARGS=()
if [ -n "${ASC_KEY_ID:-}" ] && [ -n "${ASC_ISSUER_ID:-}" ]; then
  KEYFILE="${ASC_KEY_P8_PATH:-}"
  if [ -z "$KEYFILE" ] && [ -n "${ASC_KEY_P8:-}" ]; then
    KEYFILE="$PWD/build/AuthKey_$ASC_KEY_ID.p8"
    (umask 077; printf '%s' "$ASC_KEY_P8" | base64 --decode > "$KEYFILE")
    trap 'rm -f build/AuthKey_*.p8' EXIT   # 스크립트가 어떻게 끝나든 키 파일은 지운다
  fi
  [ -f "$KEYFILE" ] && NOTARY_ARGS=(--key "$KEYFILE" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
elif xcrun notarytool history --keychain-profile "${NOTARY_PROFILE:-HyperEdit}" >/dev/null 2>&1; then
  NOTARY_ARGS=(--keychain-profile "${NOTARY_PROFILE:-HyperEdit}")
fi
if [ "$MODE" = developer-id ] && [ ${#NOTARY_ARGS[@]} -gt 0 ]; then NOTARIZE=1; echo "notarization: on"; else NOTARIZE=0; echo "notarization: off (${MODE} 서명 또는 자격 증명 없음)"; fi

notarize() { # $1 파일 → Accepted 아니면 실패
  local out id status
  out="$(xcrun notarytool submit "$1" "${NOTARY_ARGS[@]}" --wait --timeout 25m --output-format json 2>&1)" || { echo "$out"; return 1; }
  id="$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read().splitlines()[-1]); print(d.get("id",""))' 2>/dev/null || true)"
  status="$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.loads(sys.stdin.read().splitlines()[-1]); print(d.get("status",""))' 2>/dev/null || true)"
  echo "notarytool: $(basename "$1") → $status ($id)"
  if [ "$status" != "Accepted" ]; then [ -n "$id" ] && xcrun notarytool log "$id" "${NOTARY_ARGS[@]}" || true; return 1; fi
}

# ---------- 빌드 ----------
set -o pipefail
xcodebuild -project HyperEdit.xcodeproj -scheme HyperEdit-mac -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" "${SIGN_ARGS[@]}" build 2>&1 | grep -E 'error:|BUILD' | tail -5
APP="$DERIVED/Build/Products/Release/HyperEdit.app"
[ -d "$APP" ] || { echo "app not built"; exit 1; }
echo "app version: $(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
# `cmd && echo ok` 는 set -e 아래에서 실패를 삼킨다 → 실패는 명시적으로 중단
codesign --verify --deep --strict "$APP" || { echo "::error::codesign verify 실패"; exit 1; }; echo "codesign verify: OK"
if codesign -d --entitlements :- "$APP" 2>/dev/null | grep -q get-task-allow; then echo "::error::get-task-allow 엔타이틀먼트가 남아 있음 (공증 불가)"; exit 1; fi
ARCHS="$(lipo -archs "$APP/Contents/MacOS/HyperEdit")"
case "$ARCHS" in *arm64*x86_64*|*x86_64*arm64*) echo "archs: $ARCHS (universal)";; *) echo "::error::유니버설 바이너리가 아님: $ARCHS (cask 는 하나의 DMG 를 두 아키텍처에 쓴다)"; exit 1;; esac

# ---------- 앱 공증 + 스테이플 ----------
if [ "$NOTARIZE" = 1 ]; then
  rm -f build/HyperEdit.zip; ditto -c -k --keepParent "$APP" build/HyperEdit.zip
  notarize build/HyperEdit.zip
  xcrun stapler staple "$APP" >/dev/null || { echo "::error::stapler 실패 (app)"; exit 1; }; echo "stapled: app"
fi

# ---------- 볼륨 아이콘 ----------
ICONSET="$PWD/build/VolumeIcon.iconset"; rm -rf "$ICONSET"; mkdir -p "$ICONSET"
cp Apps/mac/Assets.xcassets/AppIcon.appiconset/icon_*.png "$ICONSET/"
iconutil -c icns "$ICONSET" -o build/VolumeIcon.icns

# ---------- DMG ----------
STAGE="$PWD/build/dmg-stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/HyperEdit.app"
ln -s /Applications "$STAGE/Applications"
cp build/VolumeIcon.icns "$STAGE/.VolumeIcon.icns"
OUT="dist/HyperEdit-$VERSION.dmg"; rm -f "$OUT" build/rw.dmg
hdiutil create -volname "HyperEdit $VERSION" -srcfolder "$STAGE" -ov -format UDRW -fs HFS+ build/rw.dmg >/dev/null 2>&1
MOUNT_DIR="$(hdiutil attach build/rw.dmg -readwrite -noverify -noautoopen -nobrowse 2>/dev/null | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)"
[ -n "$MOUNT_DIR" ] || { echo "::error::hdiutil attach 실패"; exit 1; }
SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
SetFile -a V "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
sync
for i in 1 2 3 4 5; do hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null && break; [ "$i" = 5 ] && { echo "::error::hdiutil detach 실패"; exit 1; }; sleep 2; done
hdiutil convert build/rw.dmg -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null 2>&1 || { echo "::error::hdiutil convert 실패"; exit 1; }
rm -f build/rw.dmg
if [ "$MODE" = developer-id ]; then codesign --sign "$IDENTITY" --timestamp "$OUT" || { echo "::error::DMG 서명 실패"; exit 1; }; echo "signed: dmg"; fi
if [ "$NOTARIZE" = 1 ]; then
  notarize "$OUT"
  xcrun stapler staple "$OUT" >/dev/null || { echo "::error::stapler 실패 (dmg)"; exit 1; }; echo "stapled: dmg"
  spctl -a -t open --context context:primary-signature -v "$OUT" 2>&1 | tail -1
fi
( cd dist && shasum -a 256 "HyperEdit-$VERSION.dmg" > SHA256SUMS )
echo "dmg: $OUT ($(du -h "$OUT" | cut -f1)) · mode=$MODE notarized=$NOTARIZE"; cat dist/SHA256SUMS
