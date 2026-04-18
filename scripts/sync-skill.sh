#!/usr/bin/env bash
# sync-skill.sh v6 — 상태 머신 구조. Git 상태 매트릭스 6셀 분기.
#
# 사용법:
#   bash sync-skill.sh <skill-name> [commit_msg] [--strict]
#   bash sync-skill.sh <skill-name> <plugin_skills_path> <repo_root> <github_user> <commit_msg> [--strict]
#
# v6 설계 원칙 (BREAKING: v5 silent failure·auto rebase 제거):
#   1. **3-phase 구조** — scan → dispatch → execute. 명령형 순차 실행 폐기
#   2. **6셀 매트릭스 분기** — references/git-state-matrix.md 참조. 셀 외 분기 = FAIL
#   3. **auto rebase 제거** — divergence(G3)는 STOP + 사용자 컨펌. 자동 복구 금지
#   4. **POST_CHECK 강제** — push 후 원격 반영 검증. silent failure 원천 차단
#   5. **rebase 중단 선감지** — Phase 1에서 `.git/rebase-{merge,apply}/` 체크. rsync 이전 STOP
#
# v5 보존: turbo 기본, --strict 옵션, ENV 자동 resolve, PLUGIN_SKILLS_PATH stale 복구, macOS perl timeout
#
# 종료코드:
#   0 = 성공 (G1·G2)
#   1 = 에러 (ENV·경로·rsync·push)
#   2 = 인자 오류
#   3 = --strict 삭제 감지
#   4 = --strict 변경 없음
#   5 = DIVERGED (G3) 또는 BEHIND (G4) — 사용자 컨펌 필요
#   6 = REBASE 중단 (G5) — rebase --abort 필요
#   7 = DETACHED HEAD (G6) — 수동 복구 필요
#   8 = POST_CHECK 실패 — 미푸시 커밋 잔존

set -euo pipefail

# ============================================================
# Phase 0: 인자 파싱 + ENV resolve (v5 로직 보존)
# ============================================================

# --- macOS timeout 폴백 ---
if ! command -v timeout &>/dev/null; then
  timeout() { local secs="$1"; shift; perl -e 'alarm shift; exec @ARGV' "$secs" "$@"; }
fi

# --- 플래그 파싱 ---
TURBO=1
ARGS=()
for arg in "$@"; do
  case "$arg" in
    --strict) TURBO=0 ;;
    --turbo)  TURBO=1 ;;
    *)        ARGS+=("$arg") ;;
  esac
done
set -- "${ARGS[@]}"

# --- ENV resolve (레거시 5인자 / 자동 1~2인자) ---
if [ $# -ge 5 ]; then
  SKILL_NAME="$1"; PLUGIN_SKILLS_PATH="$2"; REPO_ROOT="$3"; GITHUB_USER="$4"; COMMIT_MSG="$5"
elif [ $# -ge 1 ]; then
  SKILL_NAME="$1"
  COMMIT_MSG="${2:-Update $SKILL_NAME}"

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

  # v5: PLUGIN_SKILLS_PATH stale 자동 복구
  if [ ! -d "$PLUGIN_SKILLS_PATH/$SKILL_NAME" ]; then
    echo "⚠ PLUGIN_SKILLS_PATH stale — '$SKILL_NAME' 없음. 재스캔..." >&2
    _skp_root="$HOME/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin"
    if [ -d "$_skp_root" ]; then
      _best_path=""; _best_mtime=0
      while IFS= read -r _p; do
        [ -z "$_p" ] && continue
        [ -d "$_p/$SKILL_NAME" ] || continue
        if _m=$(stat -f %m "$_p/$SKILL_NAME" 2>/dev/null); then :
        elif _m=$(stat -c %Y "$_p/$SKILL_NAME" 2>/dev/null); then :
        else _m=""; fi
        [ -z "$_m" ] && continue
        if [ "$_m" -gt "$_best_mtime" ]; then
          _best_mtime="$_m"; _best_path="$_p"
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
        echo "✓ ENV 자동 갱신: PLUGIN_SKILLS_PATH → $_best_path" >&2
      else
        echo "❌ 자동 탐색 실패" >&2; exit 1
      fi
    else
      echo "❌ skills-plugin root 없음: $_skp_root" >&2; exit 1
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

[ -d "$SRC" ] || { echo "ERROR: 원본 없음 — $SRC"; exit 1; }
[ -d "$REPO/.git" ] || { echo "NEW_REPO_NEEDED: $REPO"; exit 1; }

# ============================================================
# Phase 1: git_state_scan() — 상태 스냅샷
# ============================================================
# 출력 전역변수: GIT_CELL, BRANCH, HEAD_STATE, REBASE_ACTIVE, AHEAD, BEHIND

git_state_scan() {
  cd "$REPO"

  # 축 1: HEAD 상태
  if BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null); then
    HEAD_STATE="on-branch"
  else
    HEAD_STATE="detached"
    BRANCH=""
  fi

  # 축 2: Rebase 중단 감지
  if [ -d .git/rebase-merge ] || [ -d .git/rebase-apply ]; then
    REBASE_ACTIVE=1
  else
    REBASE_ACTIVE=0
  fi

  # 우선 분기: rebase 중단 → G5, detached → G6
  if [ "$REBASE_ACTIVE" -eq 1 ]; then
    GIT_CELL="G5"; AHEAD="?"; BEHIND="?"
    return 0
  fi
  if [ "$HEAD_STATE" = "detached" ]; then
    GIT_CELL="G6"; AHEAD="?"; BEHIND="?"
    return 0
  fi

  # 축 4·5 전 필수: fetch
  if ! timeout 15 git fetch origin "$BRANCH" 2>/dev/null; then
    echo "⚠ fetch 실패 — 네트워크 또는 원격 브랜치 부재" >&2
    GIT_CELL="UNKNOWN"; AHEAD="?"; BEHIND="?"
    return 0
  fi

  # 축 4: Ahead
  AHEAD=$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo "?")
  # 축 5: Behind
  BEHIND=$(git rev-list --count "HEAD..origin/$BRANCH" 2>/dev/null || echo "?")

  if [ "$AHEAD" = "?" ] || [ "$BEHIND" = "?" ]; then
    GIT_CELL="UNKNOWN"
    return 0
  fi

  # 셀 판정
  if [ "$AHEAD" -eq 0 ] && [ "$BEHIND" -eq 0 ]; then
    GIT_CELL="G1"
  elif [ "$AHEAD" -gt 0 ] && [ "$BEHIND" -eq 0 ]; then
    GIT_CELL="G2"
  elif [ "$AHEAD" -gt 0 ] && [ "$BEHIND" -gt 0 ]; then
    GIT_CELL="G3"
  elif [ "$AHEAD" -eq 0 ] && [ "$BEHIND" -gt 0 ]; then
    GIT_CELL="G4"
  else
    GIT_CELL="UNKNOWN"
  fi
}

# ============================================================
# Phase 2: dispatch_matrix() — 셀 외 분기 차단
# ============================================================

dispatch_matrix() {
  case "$GIT_CELL" in
    G1|G2)
      return 0
      ;;
    G3)
      echo ""
      echo "❌ DIVERGED (G3) — local $AHEAD ahead, $BEHIND behind"
      echo ""
      echo "로컬 미푸시 커밋:"
      git -C "$REPO" log "origin/$BRANCH..HEAD" --oneline | sed 's/^/  /'
      echo ""
      echo "원격 미당김 커밋:"
      git -C "$REPO" log "HEAD..origin/$BRANCH" --oneline | sed 's/^/  /'
      echo ""
      echo "복구 옵션 (사용자 수동 선택):"
      echo "  1) cd $REPO && git pull --rebase    (원격 먼저 반영)"
      echo "  2) cd $REPO && git push --force-with-lease    (원격 덮어쓰기 — 원격 변경이 로컬에 반영된 경우만)"
      echo "  3) 수동 머지"
      echo ""
      echo "선택 후 sync-skill.sh 재실행."
      exit 5
      ;;
    G4)
      echo ""
      echo "❌ BEHIND (G4) — local 0 ahead, $BEHIND behind"
      echo ""
      echo "원격이 앞섬. rsync 진입 시 원격 업데이트 유실 위험 — STOP."
      echo ""
      echo "복구:"
      echo "  cd $REPO && git pull    (fast-forward)"
      echo ""
      echo "pull 후 sync-skill.sh 재실행."
      exit 5
      ;;
    G5)
      echo ""
      echo "❌ REBASE 중단 (G5) — .git/rebase-{merge|apply}/ 감지"
      echo ""
      echo "이전 세션의 rebase가 완료되지 않음. rsync 진입 금지."
      echo ""
      echo "복구:"
      echo "  cd $REPO && git rebase --abort"
      echo ""
      echo "abort 후 sync-skill.sh 재실행."
      exit 6
      ;;
    G6)
      echo ""
      echo "❌ DETACHED HEAD (G6)"
      echo ""
      echo "현재 HEAD: $(git -C "$REPO" rev-parse --short HEAD 2>/dev/null)"
      echo "브랜치 후보:"
      git -C "$REPO" branch --contains HEAD 2>/dev/null | sed 's/^/  /' || echo "  (없음)"
      echo ""
      echo "복구:"
      echo "  cd $REPO && git checkout main    (또는 적절한 브랜치)"
      echo ""
      echo "checkout 후 sync-skill.sh 재실행."
      exit 7
      ;;
    UNKNOWN|*)
      echo "❌ UNKNOWN 상태 — git_state_scan 실패. fetch 재시도 또는 수동 진단 필요"
      echo "  HEAD=$HEAD_STATE, BRANCH=$BRANCH, REBASE=$REBASE_ACTIVE, AHEAD=$AHEAD, BEHIND=$BEHIND"
      exit 1
      ;;
  esac
}

# ============================================================
# Phase 3: execute_cell() — G1·G2 처방 실행
# ============================================================

resolve_exclude() {
  [ -f "$REPO/scripts/rsync-exclude.txt" ] && { echo "$REPO/scripts/rsync-exclude.txt"; return; }
  [ -f "$GIT_SYNC_REPO/scripts/rsync-exclude.txt" ] && { echo "$GIT_SYNC_REPO/scripts/rsync-exclude.txt"; return; }
  local tmp; tmp=$(mktemp)
  printf '.git/\n.gitignore\nREADME.md\nREADME.ko.md\nLICENSE\n.DS_Store\n__pycache__/\n*.pyc\nlogs/\n' > "$tmp"
  echo "WARN: exclude 파일 부재 — 인라인 폴백: $tmp" >&2
  echo "$tmp"
}

execute_cell() {
  EXCL=$(resolve_exclude)

  # --- rsync ---
  if [ "$TURBO" -eq 1 ]; then
    rsync -av --exclude-from="$EXCL" "$SRC/" "$REPO/"
  else
    DRY=$(rsync -avn --delete --itemize-changes --exclude-from="$EXCL" "$SRC/" "$REPO/" 2>/dev/null || true)
    DELETES=$(echo "$DRY" | grep '^\*deleting' || true)
    CHANGES=$(echo "$DRY" | grep -cE '^[<>ch.][fdLDS]' || echo 0)

    if [ -n "$DELETES" ]; then
      echo "⚠️ 삭제 감지 — 확인 필요:"; echo "$DELETES"; exit 3
    fi
    # G2(미푸시 커밋 있음)에서는 CHANGES=0이어도 push 필요 → --strict는 G1만 차단
    if [ "$CHANGES" -eq 0 ] && [ "$GIT_CELL" = "G1" ]; then
      echo "⚠️ 변경 없음 — .skill 미설치 가능성. 설치 후 재시도"; exit 4
    fi
    rsync -av --delete --exclude-from="$EXCL" "$SRC/" "$REPO/"
  fi

  # --- secret-scan ---
  SCAN="$REPO/scripts/secret-scan.sh"
  [ -f "$SCAN" ] || SCAN="$GIT_SYNC_REPO/scripts/secret-scan.sh"
  if [ -f "$SCAN" ]; then
    bash "$SCAN" "$REPO" || { echo "❌ 민감정보 발견 — STOP"; exit 1; }
  else
    echo "WARN: secret-scan.sh 없음 — 스킵"
  fi

  # --- commit ---
  cd "$REPO"
  git add -A

  if git diff --cached --quiet; then
    if [ "$GIT_CELL" = "G1" ]; then
      echo "변경 없음 — 이미 최신 (G1, 미푸시 커밋도 없음)"
      exit 0
    fi
    # G2: staged 변경 없지만 미푸시 커밋 존재 → push 진행
    echo "ℹ staged 변경 없음 — 기존 미푸시 커밋 $AHEAD 개만 push"
  else
    git commit -m "$COMMIT_MSG"
  fi

  # --- push (auto rebase 제거) ---
  if ! timeout 30 git push 2>&1; then
    echo "❌ push 실패 — 원격 상태 변경 감지 가능. 재실행 시 재scan → G3 처리"
    echo "   수동 확인: cd $REPO && git fetch origin && git status"
    exit 1
  fi

  # --- POST_CHECK: 실제 원격 반영 검증 (결함 A 차단) ---
  REMAINING=$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo "?")
  if [ "$REMAINING" != "0" ]; then
    echo ""
    echo "❌ POST_CHECK 실패 — 로컬에 미푸시 커밋 $REMAINING 개 잔존"
    git log "origin/$BRANCH..HEAD" --oneline | sed 's/^/  /'
    echo ""
    echo "push는 성공 리턴했지만 실제 반영 안 됨. 원격 branch protection·race condition 가능성."
    exit 8
  fi

  # --- 리포트 ---
  HASH=$(git rev-parse --short HEAD)
  STAT=$(git diff --stat HEAD~1 2>/dev/null || echo "초기 커밋")
  echo ""
  echo "✅ $SKILL_NAME 동기화 완료 (Cell: $GIT_CELL)"
  echo "  커밋: $HASH"
  echo "  URL: https://github.com/$GITHUB_USER/$SKILL_NAME"
  echo "  $STAT"
}

# ============================================================
# Main — 3-phase 직선 실행
# ============================================================

git_state_scan
dispatch_matrix
execute_cell
