#!/usr/bin/env bash
# sync-skill.sh v5 — 스킬 단일 동기화. DC 1회 호출 완결.
#
# 사용법:
#   bash sync-skill.sh <skill-name> [commit_msg] [--strict]
#   bash sync-skill.sh <skill-name> <plugin_skills_path> <repo_root> <github_user> <commit_msg> [--strict]
#
# v5 추가: PLUGIN_SKILLS_PATH stale 자동 감지·복구
#   - skills-plugin UUID 변경 시 ENV 자동 갱신 (수동 편집 불필요)
#   - 탐색: skills-plugin root 하위 */*/skills 중 SKILL_NAME 포함 & mtime 최신
#   - .git-sync-env 백업(.bak.<epoch>) 후 sed 치환
#
# v4 설계 원칙 (BREAKING: 기본값 반전):
#   1. **기본 = turbo** — dry-run 스킵 + --delete 없음. 일반 업데이트 2배 빠름
#   2. --strict 옵션 — 삭제 감지 필요시에만 dry-run + --delete 수행
#   3. --turbo 플래그는 no-op(하위호환) — 이제 기본이므로 무시
#   4. ENV 자동 resolve — .git-sync-env 자동 source. 인자 5개 모드도 호환 유지
#   5. macOS 네이티브 — timeout 폴백(perl), stat 호환
#   6. DC 1회 호출 완결 — ENV resolve를 별도 DC 호출 불필요
#
# 종료코드: 0=성공, 1=에러, 2=인자 오류, 3=삭제 감지(--strict), 4=변경 없음(--strict)

set -euo pipefail

# --- macOS timeout 폴백 ---
if ! command -v timeout &>/dev/null; then
  timeout() { local secs="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$secs" "$@"; }
fi

# --- 플래그 파싱 (기본 turbo, --strict 지정 시 엄격 모드) ---
TURBO=1
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --strict) TURBO=0 ;;
    --turbo)  TURBO=1 ;;   # 하위호환 no-op
    *)        ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]}"

# --- ENV resolve (2모드: 인자 5개 레거시 / 인자 1~2개 자동) ---
if [ $# -ge 5 ]; then
  # 레거시 모드: 인자로 직접 전달
  SKILL_NAME="$1"
  PLUGIN_SKILLS_PATH="$2"
  REPO_ROOT="$3"
  GITHUB_USER="$4"
  COMMIT_MSG="$5"
elif [ $# -ge 1 ]; then
  # 자동 모드: .git-sync-env에서 로딩
  SKILL_NAME="$1"
  COMMIT_MSG="${2:-Update $SKILL_NAME}"

  # ENV 파일 탐색 (3단 폴백)
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ENV_FILE=""
  for candidate in \
    "$SCRIPT_DIR/../.git-sync-env" \
    "$HOME/github-repos/skill-repos/git-sync/.git-sync-env" \
    "$HOME/.git-sync-env"; do
    [ -f "$candidate" ] && { ENV_FILE="$candidate"; break; }
  done

  if [ -z "$ENV_FILE" ]; then
    echo "❌ .git-sync-env 없음 — 5인자 모드 사용 또는 ENV 파일 생성 필요"
    exit 2
  fi

  source "$ENV_FILE"
  : "${PLUGIN_SKILLS_PATH:?}" "${REPO_ROOT:?}" "${GITHUB_USER:?}"

  # --- v5: PLUGIN_SKILLS_PATH stale 자동 감지·복구 ---
  # SKILL_NAME 디렉토리가 없으면 skills-plugin root 재스캔 → mtime 최신 경로로 갱신
  if [ ! -d "$PLUGIN_SKILLS_PATH/$SKILL_NAME" ]; then
    echo "⚠ PLUGIN_SKILLS_PATH stale — '$SKILL_NAME' 없음. skills-plugin 재스캔..." >&2
    _skp_root="$HOME/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin"
    if [ -d "$_skp_root" ]; then
      _best_path=""
      _best_mtime=0
      while IFS= read -r _p; do
        [ -z "$_p" ] && continue
        [ -d "$_p/$SKILL_NAME" ] || continue
        if _m=$(stat -f %m "$_p/$SKILL_NAME" 2>/dev/null); then :
        elif _m=$(stat -c %Y "$_p/$SKILL_NAME" 2>/dev/null); then :
        else _m=""; fi
        [ -z "$_m" ] && continue
        if [ "$_m" -gt "$_best_mtime" ]; then
          _best_mtime="$_m"
          _best_path="$_p"
        fi
      done < <(find "$_skp_root" -maxdepth 3 -name "skills" -type d 2>/dev/null)

      if [ -n "$_best_path" ]; then
        cp "$ENV_FILE" "$ENV_FILE.bak.$(date +%s)"
        if sed --version >/dev/null 2>&1; then
          sed -i "s|^export PLUGIN_SKILLS_PATH=.*|export PLUGIN_SKILLS_PATH=\"$_best_path\"|" "$ENV_FILE"
        else
          sed -i '' "s|^export PLUGIN_SKILLS_PATH=.*|export PLUGIN_SKILLS_PATH=\"$_best_path\"|" "$ENV_FILE"
        fi
        PLUGIN_SKILLS_PATH="$_best_path"
        echo "✓ ENV 자동 갱신: PLUGIN_SKILLS_PATH → $_best_path (백업: $ENV_FILE.bak.*)" >&2
      else
        echo "❌ 자동 탐색 실패 — '$SKILL_NAME' 있는 skills 경로 없음" >&2
        exit 1
      fi
    else
      echo "❌ skills-plugin root 없음: $_skp_root" >&2
      exit 1
    fi
  fi
else
  echo "ERROR: sync-skill.sh <skill-name> [commit_msg] [--strict]"
  echo "       sync-skill.sh <skill-name> <plugin_skills_path> <repo_root> <github_user> <commit_msg> [--strict]"
  exit 2
fi

SRC="$PLUGIN_SKILLS_PATH/$SKILL_NAME"
REPO="$REPO_ROOT/$SKILL_NAME"
GIT_SYNC_REPO="$REPO_ROOT/git-sync"

# --- 원본·레포 존재 확인 ---
[ -d "$SRC" ] || { echo "ERROR: 원본 없음 — $SRC"; exit 1; }
[ -d "$REPO/.git" ] || { echo "NEW_REPO_NEEDED: $REPO"; exit 1; }

# --- exclude 3단 폴백 ---
resolve_exclude() {
  [ -f "$REPO/scripts/rsync-exclude.txt" ] && { echo "$REPO/scripts/rsync-exclude.txt"; return; }
  [ -f "$GIT_SYNC_REPO/scripts/rsync-exclude.txt" ] && { echo "$GIT_SYNC_REPO/scripts/rsync-exclude.txt"; return; }
  local tmp; tmp=$(mktemp)
  printf '.git/\n.gitignore\nREADME.md\nREADME.ko.md\nLICENSE\n.DS_Store\n__pycache__/\n*.pyc\nlogs/\n' > "$tmp"
  echo "WARN: exclude 파일 부재 — 인라인 폴백: $tmp" >&2
  echo "$tmp"
}
EXCL=$(resolve_exclude)

# --- rsync (turbo vs 표준) ---
if [ "$TURBO" -eq 1 ]; then
  # turbo: dry-run 스킵 + --delete 없음 → 단일 rsync로 끝
  rsync -av --exclude-from="$EXCL" "$SRC/" "$REPO/"
else
  # 표준: dry-run으로 삭제 감지 → 실제 실행
  DRY=$(rsync -avn --delete --itemize-changes --exclude-from="$EXCL" "$SRC/" "$REPO/" 2>/dev/null || true)
  DELETES=$(echo "$DRY" | grep '^\*deleting' || true)
  CHANGES=$(echo "$DRY" | grep -cE '^[<>ch.][fdLDS]' || echo 0)

  if [ -n "$DELETES" ]; then
    echo "⚠️ 삭제 감지 — 확인 필요:"
    echo "$DELETES"
    exit 3
  fi
  if [ "$CHANGES" -eq 0 ]; then
    echo "⚠️ 변경 없음 — .skill 미설치 가능성. 설치 후 재시도"
    exit 4
  fi
  rsync -av --delete --exclude-from="$EXCL" "$SRC/" "$REPO/"
fi

# --- secret-scan 2단 폴백 ---
SCAN="$REPO/scripts/secret-scan.sh"
[ -f "$SCAN" ] || SCAN="$GIT_SYNC_REPO/scripts/secret-scan.sh"
if [ -f "$SCAN" ]; then
  bash "$SCAN" "$REPO" || { echo "❌ 민감정보 발견 — STOP"; exit 1; }
else
  echo "WARN: secret-scan.sh 없음 — 스킵"
fi

# --- commit + push ---
cd "$REPO"
git add -A

if git diff --cached --quiet; then
  echo "변경 없음 — 이미 최신"
  exit 0
fi

git commit -m "$COMMIT_MSG"

if ! timeout 30 git push 2>&1; then
  echo "INFO: push 실패 — rebase 후 재시도 (30s timeout)"
  timeout 30 git pull --rebase || { echo "❌ rebase 실패 — STOP"; exit 1; }
  timeout 30 git push || { echo "❌ push 2회 실패 — STOP"; exit 1; }
fi

# --- 리포트 ---
HASH=$(git rev-parse --short HEAD)
STAT=$(git diff --stat HEAD~1 2>/dev/null || echo "초기 커밋")
echo ""
echo "✅ $SKILL_NAME 동기화 완료"
echo "  커밋: $HASH"
echo "  URL: https://github.com/$GITHUB_USER/$SKILL_NAME"
echo "  $STAT"
