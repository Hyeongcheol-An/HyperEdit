#!/usr/bin/env bash
# Homebrew cask 생성 (+ 선택: tap 저장소에 푸시).
#
#   scripts/update-cask.sh <version> [out-dir] [--push]
#
# sha256 은 dist/HyperEdit-<version>-universal.dmg 에서 계산하므로 scripts/make-dmg.sh 뒤에 실행한다.
# --push 와 HOMEBREW_TAP_DEPLOY_KEY(쓰기 권한 deploy key 의 개인키) 가 있으면
# github.com/Hyeongcheol-An/homebrew-tap 을 클론해 Casks/hyperedit.rb 를 갱신·푸시한다.
# 없으면 out-dir(기본 Casks/) 에 파일만 쓴다 — 저장소 자체도 `brew tap Hyeongcheol-An/hyperedit https://github.com/Hyeongcheol-An/HyperEdit` 로 tap 가능.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: update-cask.sh <version> [out-dir] [--push]}"
case "$VERSION" in *[!0-9A-Za-z.-]*|"") echo "invalid version: $VERSION"; exit 1 ;; esac
OUT="Casks"; PUSH=0
for a in "${@:2}"; do case "$a" in --push) PUSH=1 ;; *) OUT="$a" ;; esac; done
TAP_REPO="git@github.com:Hyeongcheol-An/homebrew-tap.git"
# GitHub 의 공개 SSH 호스트 키(ed25519) — 러너에서 처음 접속할 때 TOFU 대신 고정 검증
GITHUB_HOST_KEY="github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"

DMG="dist/HyperEdit-${VERSION}-universal.dmg"
[ -f "$DMG" ] || { echo "missing $DMG"; exit 1; }
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)

mkdir -p "$OUT"
CASK="$OUT/hyperedit.rb"
cat > "$CASK" <<RUBY
cask "hyperedit" do
  version "${VERSION}"
  sha256 "${SHA}"

  url "https://github.com/Hyeongcheol-An/HyperEdit/releases/download/v#{version}/HyperEdit-#{version}-universal.dmg"
  name "HyperEdit"
  desc "Ribbon-style plain-text editor for one large notes file"
  homepage "https://github.com/Hyeongcheol-An/HyperEdit"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sequoia

  app "HyperEdit.app"

  zap trash: [
    "~/Library/Application Support/HyperEdit",
    "~/Library/Caches/io.github.hyeongcheol-an.hyperedit",
    "~/Library/Preferences/io.github.hyeongcheol-an.hyperedit.plist",
    "~/Library/Saved Application State/io.github.hyeongcheol-an.hyperedit.savedState",
  ]
end
RUBY
echo "wrote $CASK (sha256 ${SHA:0:12}…)"

[ "$PUSH" = 1 ] || exit 0
if [ -z "${HOMEBREW_TAP_DEPLOY_KEY:-}" ]; then echo "HOMEBREW_TAP_DEPLOY_KEY 없음 → tap 푸시 건너뜀 (Casks/hyperedit.rb 만 갱신)"; exit 0; fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
KEY="$WORK/key"; KNOWN="$WORK/known_hosts"
(umask 077; printf '%s\n' "$HOMEBREW_TAP_DEPLOY_KEY" > "$KEY"; printf '%s\n' "$GITHUB_HOST_KEY" > "$KNOWN")
export GIT_SSH_COMMAND="ssh -i '$KEY' -o IdentitiesOnly=yes -o UserKnownHostsFile='$KNOWN' -o StrictHostKeyChecking=yes"
TAP="$WORK/tap"
git clone -q --depth 1 "$TAP_REPO" "$TAP"
mkdir -p "$TAP/Casks"
cp "$CASK" "$TAP/Casks/hyperedit.rb"
git -C "$TAP" add Casks/hyperedit.rb
if git -C "$TAP" diff --cached --quiet; then echo "cask unchanged"; exit 0; fi
git -C "$TAP" -c user.name="hyperedit-release-bot" -c user.email="hyperedit-release-bot@users.noreply.github.com" \
  commit -q -m "hyperedit ${VERSION}"
git -C "$TAP" push -q origin HEAD
echo "pushed Casks/hyperedit.rb ${VERSION} to homebrew-tap"
