#!/usr/bin/env bash
# secret-scan.sh — 민감정보 검사. git-sync 전용.
# 사용: bash scripts/secret-scan.sh [검사경로]
# 종료코드: 0=clean, 1=민감정보 발견, 2=인자 오류
#
# 설계 원칙:
#   1. grep 패턴을 SKILL.md 밖에 두어 false positive 원천 차단
#   2. SKILL.md 자체는 검사 대상에서 제외 (자기참조 방지)
#   3. BSD/GNU grep 모두 동작하는 파이프 필터 방식
#   4. exit code를 명시적으로 관리하여 && 체인 꼬임 방지

set -euo pipefail

TARGET="${1:-.}"

if [ ! -d "$TARGET" ]; then
  echo "ERROR: 디렉토리 없음 — $TARGET"
  exit 2
fi

# 민감정보 패턴 (한 줄에 하나씩, grep -E 확장 정규식)
PATTERNS=(
  'oauth'
  'password=[^*]'
  'secret_key'
  'private_key'
  'Bearer '
  'api_key'
  'api_secret'
  'AKIA[0-9A-Z]{16}'
  'ghp_[a-zA-Z0-9]{36}'
  'sk-[a-zA-Z0-9]{20}'
  'gho_'
  'glpat-'
  'xox[bpoas]-'
)

# 패턴을 | 로 결합
COMBINED=$(IFS='|'; echo "${PATTERNS[*]}")

# 검사 실행:
#   1. --include로 대상 파일 지정
#   2. 파이프로 SKILL.md 제외 (BSD/GNU grep 호환)
#   3. 결과가 있으면 출력 후 exit 1
HITS=$(grep -r -i -l \
  --include="*.md" --include="*.py" --include="*.json" --include="*.yaml" --include="*.yml" \
  -E "$COMBINED" "$TARGET" 2>/dev/null \
  | grep -v 'SKILL\.md$' || true)

if [ -n "$HITS" ]; then
  echo "$HITS"
  echo "⚠️ 민감정보 발견 — STOP"
  exit 1
fi

echo "✅ 민감정보 없음"
exit 0
