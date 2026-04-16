#!/usr/bin/env bash
# pre-flight-scan.sh — 3-way 상태 수집 + 8셀 분류
# Usage: pre-flight-scan.sh <plugin_skills_path> <repo_root> <github_user>
# Output: TSV (name, origin, local, remote, cell, action) + 분류 요약

set -o pipefail

PLUGIN_PATH="${1:?plugin_skills_path required}"
REPO_ROOT="${2:?repo_root required}"
GH_USER="${3:?github_user required}"

[ -d "$PLUGIN_PATH" ] || { echo "❌ plugin_skills_path not found: $PLUGIN_PATH" >&2; exit 2; }
[ -d "$REPO_ROOT" ] || { echo "❌ repo_root not found: $REPO_ROOT" >&2; exit 2; }

# --- 제외 목록 (매트릭스 대상 아님)
#  Built-in Claude 스킬: 원본 있어도 내 레포로 push 금지
#  UP 레포: up-sync.md 전용 플로우 (별도 처리)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXCLUDE_FILE="$SCRIPT_DIR/excluded-names.txt"
DEFAULT_EXCLUDES=(
  "docx" "pdf" "pptx" "xlsx"
  "schedule" "consolidate-memory" "setup-cowork"
  "user-preferences"
)

if [ -f "$EXCLUDE_FILE" ]; then
  # bash 3.2 호환 (macOS 기본 bash) — mapfile 사용 금지
  EXCLUDES=()
  while IFS= read -r line; do
    [ -n "$line" ] && EXCLUDES+=("$line")
  done < <(grep -v '^#' "$EXCLUDE_FILE" | grep -v '^$')
  # 파일은 있지만 전부 빈/주석 라인이라 배열이 비는 경우 폴백
  [ ${#EXCLUDES[@]} -eq 0 ] && EXCLUDES=("${DEFAULT_EXCLUDES[@]}")
else
  EXCLUDES=("${DEFAULT_EXCLUDES[@]}")
fi

is_excluded() {
  local n="$1"
  for e in "${EXCLUDES[@]}"; do
    [ "$n" = "$e" ] && return 0
  done
  return 1
}

# --- 로그 디렉터리
LOG_DIR="$REPO_ROOT/git-sync/logs"
mkdir -p "$LOG_DIR" 2>/dev/null
TS=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/preflight-$TS.log"

# --- 1. REMOTE 스캔 (세션 1회, gh API)
REMOTE_RAW=$(gh repo list "$GH_USER" --limit 500 --json name -q '.[].name' 2>/dev/null)
REMOTE_STATUS=$?
if [ $REMOTE_STATUS -ne 0 ]; then
  REMOTE_UNKNOWN=1
  echo "⚠  REMOTE 스캔 실패 — UNKNOWN 처리" >&2
else
  REMOTE_UNKNOWN=0
fi

# --- 2. ORIGIN, LOCAL 스캔
ORIGIN_RAW=$(ls -1 "$PLUGIN_PATH" 2>/dev/null | grep -v '^\.' | while read n; do
  [ -f "$PLUGIN_PATH/$n/SKILL.md" ] && echo "$n"
done)

LOCAL_RAW=$(ls -1 "$REPO_ROOT" 2>/dev/null | grep -v '^\.' | grep -v '^_archive' | while read n; do
  [ -d "$REPO_ROOT/$n/.git" ] && echo "$n"
done)

# --- 3. 합집합 생성 (제외 목록 필터링 포함)
ALL_NAMES_RAW=$(printf "%s\n%s\n%s\n" "$ORIGIN_RAW" "$LOCAL_RAW" "$REMOTE_RAW" | sort -u | grep -v '^$')

ALL_NAMES=""
EXCLUDED_NAMES=""
while IFS= read -r NAME; do
  [ -z "$NAME" ] && continue
  if is_excluded "$NAME"; then
    EXCLUDED_NAMES="${EXCLUDED_NAMES}${NAME}
"
  else
    ALL_NAMES="${ALL_NAMES}${NAME}
"
  fi
done <<< "$ALL_NAMES_RAW"

# --- 4. 3축 결합 + 셀 분류
declare -a CELLS
CELLS=(0 0 0 0 0 0 0 0 0)  # index 1~8, UNKNOWN=0

HEADER=$'name\torigin\tlocal\tremote\tcell\taction'
BODY=""

while IFS= read -r NAME; do
  [ -z "$NAME" ] && continue

  O=$(echo "$ORIGIN_RAW" | grep -Fx "$NAME" > /dev/null && echo 1 || echo 0)
  L=$(echo "$LOCAL_RAW" | grep -Fx "$NAME" > /dev/null && echo 1 || echo 0)

  if [ $REMOTE_UNKNOWN -eq 1 ]; then
    R="?"
  else
    R=$(echo "$REMOTE_RAW" | grep -Fx "$NAME" > /dev/null && echo 1 || echo 0)
  fi

  # 셀 분류
  if [ "$R" = "?" ]; then
    CELL=0; ACTION="UNKNOWN"
  else
    case "$O$L$R" in
      "111") CELL=1; ACTION="sync" ;;
      "110") CELL=2; ACTION="REMOTE_LOST_CONFIRM" ;;
      "101") CELL=3; ACTION="clone+sync" ;;
      "100") CELL=4; ACTION="CREATE_NEW_CONFIRM" ;;
      "011") CELL=5; ACTION="ORIGIN_LOST_STOP" ;;
      "010") CELL=6; ACTION="ORPHAN_LOCAL_CONFIRM" ;;
      "001") CELL=7; ACTION="external_skip" ;;
      "000") CELL=8; ACTION="none_skip" ;;
      *) CELL=0; ACTION="UNKNOWN" ;;
    esac
  fi

  CELLS[$CELL]=$((${CELLS[$CELL]} + 1))
  BODY="${BODY}${NAME}	${O}	${L}	${R}	${CELL}	${ACTION}
"
done <<< "$ALL_NAMES"

# --- 5. 출력 (TSV)
echo "$HEADER"
printf "%s" "$BODY"

# --- 6. 분류 요약 (stderr)
EXCLUDED_COUNT=$(echo "$EXCLUDED_NAMES" | grep -c '^.' || echo 0)
{
  echo ""
  echo "─── Pre-Flight 스캔 요약 ───"
  echo "✅ Cell 1 (정상):        ${CELLS[1]}개 — auto sync"
  echo "⚠  Cell 2 (원격 유실):  ${CELLS[2]}개 ← 컨펌 필요"
  echo "🔵 Cell 3 (clone 필요): ${CELLS[3]}개 — auto clone+sync"
  echo "⚠  Cell 4 (신규 생성):  ${CELLS[4]}개 ← 컨펌 필요"
  echo "⚠  Cell 5 (원본 삭제):  ${CELLS[5]}개 ← STOP"
  echo "⚠  Cell 6 (고아 로컬):  ${CELLS[6]}개 ← 컨펌 필요"
  echo "ℹ  Cell 7 (외부 레포):  ${CELLS[7]}개 — skip"
  echo "—  Cell 8 (없음):        ${CELLS[8]}개"
  echo "❓ UNKNOWN:              ${CELLS[0]}개"
  echo "🚫 제외:                  ${EXCLUDED_COUNT}개 (built-in 스킬 + UP 레포)"
  echo ""
  echo "로그: $LOG_FILE"
} >&2

# --- 7. 로그 저장
{
  echo "# Pre-Flight Scan — $TS"
  echo "# plugin_skills_path=$PLUGIN_PATH"
  echo "# repo_root=$REPO_ROOT"
  echo "# github_user=$GH_USER"
  echo "# remote_scan=$([ $REMOTE_UNKNOWN -eq 1 ] && echo FAILED || echo OK)"
  echo "# excluded_count=$EXCLUDED_COUNT"
  echo ""
  echo "# Excluded names:"
  printf "%s" "$EXCLUDED_NAMES" | sed 's/^/#   /'
  echo ""
  echo "$HEADER"
  printf "%s" "$BODY"
} > "$LOG_FILE"

# --- 8. 종료코드
# 0 = 정상 (파괴적 액션 없음 or 필요한 것만 분류됨)
# 5 = Cell 5 존재 (STOP 필요)
# 6 = UNKNOWN 존재 (재스캔 필요)

if [ ${CELLS[0]} -gt 0 ]; then exit 6; fi
if [ ${CELLS[5]} -gt 0 ]; then exit 5; fi
exit 0
