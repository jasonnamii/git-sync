#!/usr/bin/env bash
# sync-skill.sh — 스킬 단일 동기화. rsync + exclude + secret-scan + commit + push.
#
# 사용: bash scripts/sync-skill.sh <skill-name> <plugin_skills_path> <repo_root> <github_user> <commit_msg>
#
# 설계 원칙:
#   1. SKILL.md의 코드블록을 에이전트가 재조립할 필요 없음 — 이 스크립트 1회 호출로 완결
#   2. exclude 3단 폴백: 레포 내 scripts/ → git-sync 레포 → 인라인 하드코딩
#   3. secret-scan 2단 폴백: 레포 내 scripts/ → git-sync 레포
#   4. git-sync 레포 로컬 부재 시 자동 clone
#   5. 삭제 감지 시 자동 중단 (안전 우선)
#   6. push 실패 1회 재시도 후 STOP
#
# 종료코드: 0=성공, 1=에러, 2=인자 오류, 3=삭제 감지(확인 필요), 4=변경 없음

set -euo pipefail

# --- 인자 검증 ---
if [ $# -lt 5 ]; then
  echo "ERROR: 인자 부족. 사용: sync-skill.sh <skill-name> <plugin_skills_path> <repo_root> <github_user> <commit_msg>"
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
if [ ! -d "$SRC" ]; then
  echo "ERROR: 원본 없음 — $SRC"
  exit 1
fi

if [ ! -d "$REPO/.git" ]; then
  echo "NEW_REPO_NEEDED: $REPO"
  exit 1
fi

# --- git-sync 레포 자동 보장 ---
if [ ! -d "$GIT_SYNC_REPO/.git" ]; then
  echo "INFO: git-sync 레포 로컬 부재 — 자동 clone"
  gh repo clone "$GITHUB_USER/git-sync" "$GIT_SYNC_REPO" 2>/dev/null || {
    echo "WARN: git-sync clone 실패 — 인라인 폴백 사용"
  }
fi

# --- exclude 3단 폴백 ---
resolve_exclude() {
  # 1단: 대상 레포 내
  if [ -f "$REPO/scripts/rsync-exclude.txt" ]; then
    echo "$REPO/scripts/rsync-exclude.txt"
    return
  fi
  # 2단: git-sync 레포
  if [ -f "$GIT_SYNC_REPO/scripts/rsync-exclude.txt" ]; then
    echo "$GIT_SYNC_REPO/scripts/rsync-exclude.txt"
    return
  fi
  # 3단: 인라인 하드코딩
  local tmp
  tmp=$(mktemp)
  printf '.git/\n.gitignore\nREADME.md\nREADME.ko.md\nLICENSE\n.DS_Store\n__pycache__/\n*.pyc\n' > "$tmp"
  echo "WARN: exclude 파일 부재 — 인라인 폴백 사용: $tmp" >&2
  echo "$tmp"
}

EXCL=$(resolve_exclude)

# --- PRE_SYNC_CHECK: 삭제 감지 ---
DELETES=$(rsync -avn --delete --exclude-from="$EXCL" "$SRC/" "$REPO/" 2>/dev/null | grep '^deleting ' || true)

if [ -n "$DELETES" ]; then
  echo "⚠️ 삭제 감지 — 확인 필요:"
  echo "$DELETES"
  exit 3
fi

# --- diff 체크 ---
DIFF_OUTPUT=$(rsync -avn --exclude-from="$EXCL" "$SRC/" "$REPO/" 2>/dev/null || true)
CHANGES=$(echo "$DIFF_OUTPUT" | grep -c -E '^[^.]' || true)

if [ "$CHANGES" -eq 0 ]; then
  echo "⚠️ 변경 없음 — .skill 미설치 가능성. 설치 후 재시도"
  exit 4
fi

# --- rsync 실행 ---
rsync -av --delete --exclude-from="$EXCL" "$SRC/" "$REPO/"

# --- secret-scan 2단 폴백 ---
SCAN="$REPO/scripts/secret-scan.sh"
[ -f "$SCAN" ] || SCAN="$GIT_SYNC_REPO/scripts/secret-scan.sh"

if [ -f "$SCAN" ]; then
  bash "$SCAN" "$REPO" || { echo "❌ 민감정보 발견 — STOP"; exit 1; }
else
  echo "WARN: secret-scan.sh 없음 — 스킵 (git-sync 레포 clone 권장)"
fi

# --- commit + push ---
cd "$REPO"
git add -A

if git diff --cached --quiet; then
  echo "변경 없음 — 이미 최신"
  exit 0
fi

git commit -m "$COMMIT_MSG"
git push || {
  echo "INFO: push 실패 — rebase 후 재시도"
  git pull --rebase && git push || {
    echo "❌ push 2회 실패 — STOP"
    exit 1
  }
}

# --- 리포트 ---
HASH=$(git rev-parse --short HEAD)
STAT=$(git diff --stat HEAD~1 2>/dev/null || echo "초기 커밋")
echo ""
echo "✅ $SKILL_NAME 동기화 완료"
echo "  커밋: $HASH"
echo "  URL: https://github.com/$GITHUB_USER/$SKILL_NAME"
echo "  $STAT"
