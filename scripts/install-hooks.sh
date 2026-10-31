#!/usr/bin/env bash
# 로컬 커밋 메시지 검사 훅 설치 (Node 불필요)
set -e
cd "$(dirname "$0")/.."
git config core.hooksPath .githooks
chmod +x .githooks/*
echo "hooks installed: core.hooksPath=.githooks"
