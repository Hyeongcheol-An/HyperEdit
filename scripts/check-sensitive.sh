#!/usr/bin/env bash
# 커밋된 파일에 비밀 키·토큰·개인 경로·이메일이 섞이지 않았는지 검사한다 (CI 와 로컬 공용).
# 사용: scripts/check-sensitive.sh   → 문제가 있으면 줄을 출력하고 1 로 종료
set -uo pipefail
cd "$(dirname "$0")/.."
status=0

echo "== 비밀 파일 확장자 =="
if git ls-files | grep -E '\.(p8|p12|pem|key|mobileprovision|keychain-db)$|(^|/)AuthKey_|(^|/)\.env(\.|$)'; then
  echo "::error::비밀 파일이 커밋돼 있습니다"; status=1
fi

echo "== 키 자료 · 토큰 =="
pat='BEGIN (RSA |EC |OPENSSH |DSA )?PRIVATE KEY|MIGTAgEAMBMGByqGSM49|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abpers]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|[a-z0-9-]+\.slack\.com/|notion\.so/'
if git grep -n -I -E "$pat" -- . ':!scripts/check-sensitive.sh'; then
  echo "::error::키/토큰 패턴이 발견됐습니다"; status=1
fi

echo "== 금지 식별자 (개인 프로젝트 — 회사명·개인 폴더명) =="
if git grep -n -I -i -E 'aivis|dev_docs' -- . ':!scripts/check-sensitive.sh' ':!CHANGELOG.md'; then
  echo "::error::개인 프로젝트에 들어가면 안 되는 식별자가 있습니다"; status=1
fi

echo "== 개인 홈 경로 =="
if git grep -n -I -E '/Users/[A-Za-z0-9_.-]+/|/home/[A-Za-z0-9_.-]+/' -- . ':!scripts/check-sensitive.sh'; then
  echo "::error::개인 홈 디렉터리 경로가 있습니다 (~ 또는 \$HOME 으로 바꾸세요)"; status=1
fi

echo "== 이메일 주소 (GitHub noreply · example.com 제외) =="
if git grep -n -I -E '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' -- . ':!scripts/check-sensitive.sh' ':!CHANGELOG.md' \
   | grep -v -E 'users\.noreply\.github\.com|@example\.com|semantic-release-bot@martynus\.net|@users\.noreply|@[23]x\.(png|jpg)|git@github\.com'; then
  echo "::error::개인 이메일 주소가 있습니다"; status=1
fi

[ "$status" = 0 ] && echo "OK: 민감 정보 없음"
exit $status
