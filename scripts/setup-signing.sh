#!/usr/bin/env bash
# Developer ID 서명·공증 1회 설정 도우미 (유료 Apple Developer 계정 필요)
# 사용:
#   scripts/setup-signing.sh status                                     # 현재 상태 점검
#   scripts/setup-signing.sh notary-key <AuthKey_XXXX.p8> <KEY_ID> <ISSUER_ID>   # App Store Connect API 키로 notarytool 프로필(HyperEdit) 저장
#   scripts/setup-signing.sh notary-apple-id <apple-id> <TEAM_ID>       # Apple ID + 앱 암호(프롬프트)로 프로필 저장
#   scripts/setup-signing.sh ci-secrets <cert.p12> <AuthKey.p8> <KEY_ID> <ISSUER_ID> [owner/repo]
#       → .p12 암호를 프롬프트로 받아 GitHub Actions 시크릿 5개를 `gh secret set` 으로 바로 등록 (값을 화면·셸 기록에 남기지 않음)
set -euo pipefail
cmd="${1:-status}"
case "$cmd" in
  status)
    echo "== Developer ID Application 인증서 =="; security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" || echo "  없음 → Xcode ▸ Settings ▸ Accounts ▸ (유료 팀) ▸ Manage Certificates ▸ + ▸ Developer ID Application"
    echo "== Apple Development 인증서 =="; security find-identity -v -p codesigning 2>/dev/null | grep "Apple Development" || echo "  없음"
    echo "== notarytool 프로필(HyperEdit) =="; xcrun notarytool history --keychain-profile HyperEdit >/dev/null 2>&1 && echo "  있음" || echo "  없음 → notary-key 또는 notary-apple-id 로 저장"
    echo "== 로컬 서명 설정 =="; [ -f Config/Local.xcconfig ] && echo "  Config/Local.xcconfig 있음 (팀 서명)" || echo "  Config/Local.xcconfig 없음 → 로컬 실행용 ad-hoc 서명 (Local.xcconfig.example 참고)" ;;
  notary-key)
    xcrun notarytool store-credentials HyperEdit --key "$2" --key-id "$3" --issuer "$4"; echo "저장됨: keychain 프로필 HyperEdit (scripts/make-dmg.sh 가 자동 사용)" ;;
  notary-apple-id)
    xcrun notarytool store-credentials HyperEdit --apple-id "$2" --team-id "$3"; echo "저장됨: keychain 프로필 HyperEdit" ;;
  ci-secrets)
    P12="${2:?cert.p12}"; P8="${3:?AuthKey.p8}"; KEY_ID="${4:?KEY_ID}"; ISSUER="${5:?ISSUER_ID}"; REPO="${6:-}"
    command -v gh >/dev/null || { echo "gh CLI 가 필요합니다 (brew install gh && gh auth login)"; exit 1; }
    R=(); [ -n "$REPO" ] && R=(-R "$REPO")
    read -rs -p ".p12 암호: " P12PW; echo
    base64 < "$P12" | tr -d '\n' | gh secret set DEVELOPER_ID_CERT_P12 "${R[@]}"
    printf '%s' "$P12PW" | gh secret set P12_PASSWORD "${R[@]}"
    base64 < "$P8" | tr -d '\n' | gh secret set ASC_KEY_P8 "${R[@]}"
    printf '%s' "$KEY_ID" | gh secret set ASC_KEY_ID "${R[@]}"
    printf '%s' "$ISSUER" | gh secret set ASC_ISSUER_ID "${R[@]}"
    unset P12PW
    echo "등록 완료: DEVELOPER_ID_CERT_P12 P12_PASSWORD ASC_KEY_P8 ASC_KEY_ID ASC_ISSUER_ID"; gh secret list "${R[@]}" ;;
  *) echo "unknown: $cmd"; exit 1 ;;
esac
