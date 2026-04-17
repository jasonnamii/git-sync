#!/usr/bin/env bash
# secret-scan.sh v2 — 민감정보 검사 + allowlist 지원. git-sync 전용.
# 사용: bash scripts/secret-scan.sh [검사경로]
# 종료코드: 0=clean, 1=민감정보 발견, 2=인자 오류
#
# v2 변경:
#   - 라인 단위 히트 수집(-n)으로 false positive 식별 정밀화
#   - secret-scan-allowlist.txt 지원 — 정규식 한 줄씩, 주석(#) 허용
#   - allowlist로 모든 히트가 허용되면 exit 0 + 허용 건수 표시
#
# 설계 원칙:
#   1. grep 패턴은 SKILL.md 밖에 정의 (false positive 원천 차단)
#   2. SKILL.md 자체는 검사 대상에서 제외 (자기참조 방지)
#   3. BSD/GNU grep 모두 동작
#   4. exit code 명시적 관리

set -euo pipefail

TARGET="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALLOWLIST="$SCRIPT_DIR/secret-scan-allowlist.txt"

if [ ! -d "$TARGET" ]; then
  echo "ERROR: 디렉토리 없음 — $TARGET"
  exit 2
fi

# 민감정보 패턴 (grep -E 확장 정규식)
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

COMBINED=$(IFS='|'; echo "${PATTERNS[*]}")

# 라인 단위 히트 수집: "path:lineno:line-content"
RAW_HITS=$(grep -r -i -n \
  --include="*.md" --include="*.py" --include="*.json" --include="*.yaml" --include="*.yml" \
  -E "$COMBINED" "$TARGET" 2>/dev/null \
  | grep -v '/SKILL\.md:' || true)

if [ -z "$RAW_HITS" ]; then
  echo "✅ 민감정보 없음"
  exit 0
fi

# allowlist 필터링
FILTERED_HITS="$RAW_HITS"
ALLOWED_COUNT=0
if [ -f "$ALLOWLIST" ]; then
  ALLOW_PATTERNS=$(grep -vE '^\s*(#|$)' "$ALLOWLIST" 2>/dev/null || true)
  if [ -n "$ALLOW_PATTERNS" ]; then
    ALLOW_COMBINED=$(echo "$ALLOW_PATTERNS" | paste -sd '|' -)
    FILTERED_HITS=$(echo "$RAW_HITS" | grep -vE "$ALLOW_COMBINED" || true)
    TOTAL=$(echo "$RAW_HITS" | grep -c '' || echo 0)
    REMAIN=$(echo "$FILTERED_HITS" | grep -c '' 2>/dev/null || echo 0)
    [ -z "$FILTERED_HITS" ] && REMAIN=0
    ALLOWED_COUNT=$((TOTAL - REMAIN))
  fi
fi

if [ -n "$FILTERED_HITS" ]; then
  echo "$FILTERED_HITS"
  echo ""
  echo "⚠️ 민감정보 발견 — STOP"
  echo "  False positive? → $ALLOWLIST 에 정규식 추가"
  exit 1
fi

if [ "$ALLOWED_COUNT" -gt 0 ]; then
  echo "✅ 민감정보 없음 (allowlist로 ${ALLOWED_COUNT}건 허용)"
else
  echo "✅ 민감정보 없음"
fi
exit 0
