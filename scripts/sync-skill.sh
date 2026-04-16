#!/usr/bin/env bash
# sync-skill.sh — 스킬 단일 동기화. rsync 1회(itemize-changes) + secret-scan + commit + push.
#
# 사용: bash scripts/sync-skill.sh <skill-name> <plugin_skills_path> <repo_root> <github_user> <commit_msg>
#
# 설계 원칙 (v2):
#   1. rsync 단일 실행 — `-avn --delete --itemize-changes`로 diff·삭제 동시 판정 (기존 3회 → 1회)
#   2. push 재시도 30초 timeout — rebase 블록킹 원천 차단
#   3. git-sync 레포 pull 중복 제거 — 에이전트가 ENV resolve 시 이미 보장
#   4. exclude 3단 폴백 유지, secret-scan 2단 폴백 유지
#
# 종료코드: 0=성공, 1=에러, 2=인자 오류, 3=삭제 감지(확인 필요), 4=변경 없음

set -euo pipefail

# --- 인자 검증 ---
if [ $# -lt 5 ]; then
  echo "ERROR: 사용: sync-skill.sh <skill-name> <plugin_skills_path> <repo_root> <github_user> <commit_msg>"
  exit 2
fi

SKILL_NAME="$1"
PLUGIN_SKILLS_PATH="$2"
REPO_ROOT="$3"
GITHUB_USER="$4"
COMMIT_MSG="$5"

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
  local tmp
  tmp=$(mktemp)
  printf '.git/\n.gitignore\nREADME.md\nREADME.ko.md\nLICENSE\n.DS_Store\n__pycache__/\n*.pyc\nlogs/\n' > "$tmp"
  echo "WARN: exclude 파일 부재 — 인라인 폴백: $tmp" >&2
  echo "$tmp"
}
EXCL=$(resolve_exclude)

# --- 단일 rsync dry-run (삭제 + diff 동시 판정) ---
# --itemize-changes: 각 줄이 change-type으로 시작. *deleting=삭제, <>ch=변경
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

# --- rsync 실제 실행 ---
rsync -av --delete --exclude-from="$EXCL" "$SRC/" "$REPO/"

# --- secret-scan 2단 폴백 ---
SCAN="$REPO/scripts/secret-scan.sh"
[ -f "$SCAN" ] || SCAN="$GIT_SYNC_REPO/scripts/secret-scan.sh"

if [ -f "$SCAN" ]; then
  bash "$SCAN" "$REPO" || { echo "❌ 민감정보 발견 — STOP"; exit 1; }
else
  echo "WARN: secret-scan.sh 없음 — 스킵"
fi

# --- commit + push (timeout 30s per step) ---
cd "$REPO"
git add -A

if git diff --cached --quiet; then
  echo "변경 없음 — 이미 최신"
  exit 0
fi

git commit -m "$COMMIT_MSG"

# push → 실패시 1회 rebase + push, 각 단계 30s timeout (블록킹 차단)
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
