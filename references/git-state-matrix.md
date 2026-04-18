# Git 상태 매트릭스 — 6셀

sync-skill.sh v6의 진입 분기. Phase 1 `git_state_scan()`이 스냅샷을 찍고 이 매트릭스로 분기한다.

파일 3-way 매트릭스(`state-matrix.md`)가 **파일 존재** 축이라면, 이 매트릭스는 **git 브랜치 상태** 축. 두 매트릭스는 대칭 — Pre-Flight는 두 축 모두 통과해야 한다.

---

## 스캔 축 (5개)

Phase 1에서 순서대로 수집:

| # | 축 | 수집 명령 | 값 |
|---|----|----------|----|
| 1 | HEAD 상태 | `git symbolic-ref --short HEAD 2>/dev/null \|\| echo detached` | branch명 or `detached` |
| 2 | Rebase 중단 | `[ -d .git/rebase-merge ] \|\| [ -d .git/rebase-apply ]` | true/false |
| 3 | Working tree | `git status --porcelain` | empty=clean / lines=dirty |
| 4 | Ahead | `git rev-list --count origin/$BRANCH..HEAD` | 정수 |
| 5 | Behind | `git rev-list --count HEAD..origin/$BRANCH` | 정수 |

**전제:** 축 4·5 수집 전 `git fetch origin` 1회 필수. stale 트래킹으로 잘못된 분기 방지.

---

## 6셀 분기표

| 셀 | HEAD | Rebase | Ahead | Behind | 처방 | 종료코드 |
|----|------|--------|-------|--------|------|---------|
| G1 | on branch | ✗ | 0 | 0 | **clean sync** — rsync → add → (staged 있으면) commit → push → post-check | 0 |
| G2 | on branch | ✗ | N | 0 | **push-only** — rsync → add → commit(변경시) → push → post-check. 미푸시 커밋 함께 상승 | 0 |
| G3 | on branch | ✗ | N | M | **DIVERGED — STOP** — 사용자 컨펌 필요. 자동 rebase 금지 | 5 |
| G4 | on branch | ✗ | 0 | M | **BEHIND — STOP** — fast-forward pull 필요. rsync 전에 해결 | 5 |
| G5 | * | ✓ | * | * | **REBASE 중단 — STOP** — `git rebase --abort` 안내 후 재시도 | 6 |
| G6 | detached | ✗ | * | * | **DETACHED — STOP** — 원인 리포트 + 수동 복구 안내 | 7 |
| ? | UNKNOWN | | | | 스캔 실패 — 재시도 | 8 |

**규칙:** 셀 외 분기 = FAIL. 8셀 파일 매트릭스와 동일한 철학.

---

## 셀별 처방 상세

### G1 — Clean Sync (정상 경로 1)

**조건:** 로컬이 원격과 완전 동기. working tree만 체크.
**처방:**
```
rsync SRC → REPO
secret-scan
git add -A
if staged: git commit -m "$MSG"
git push
POST_CHECK: git rev-list --count origin/$BRANCH..HEAD == 0
```
**빈도:** 일상의 90%+.

### G2 — Push-Only (정상 경로 2)

**조건:** 로컬에 미푸시 커밋 N개 존재. 원격 뒤처짐 없음. **결함 A의 핵심 셀.**
**처방:** G1과 동일. 단 commit 유무 무관 push 실행. 미푸시 커밋들이 함께 올라감.
**이유:** v5 이하에서 `git diff --cached --quiet` → "변경 없음" 오판정으로 여기서 silent failure 발생했음.

### G3 — Diverged (STOP)

**조건:** 로컬과 원격이 서로 다른 커밋 보유. **결함 B의 핵심 셀.**
**처방:**
- 자동 rebase **금지** (v5 이하의 auto `git pull --rebase` 제거)
- 리포트:
  ```
  ❌ DIVERGED: local N ahead, M behind
  로컬 미푸시 커밋:
    <git log origin/$BRANCH..HEAD --oneline>
  원격 미당김 커밋:
    <git log HEAD..origin/$BRANCH --oneline>

  복구 옵션:
    1) git pull --rebase (원격 먼저 반영 후 로컬 올리기)
    2) git push --force-with-lease (원격 덮어쓰기 — 원격 변경이 로컬에 이미 반영된 경우만)
    3) 수동 머지
  선택 후 재실행.
  ```
- 종료코드 5. 사용자 컨펌 후 수동 실행.

### G4 — Behind (STOP)

**조건:** 원격만 앞섬. 로컬은 stale.
**처방:** `git pull` 또는 `git pull --rebase` 안내. rsync 진입 금지(덮어쓰기 위험).
**이유:** 원격의 변경을 로컬에 반영 안 하고 rsync하면 원격 업데이트가 유실됨.

### G5 — Rebase 중단 (STOP)

**조건:** `.git/rebase-merge/` 또는 `.git/rebase-apply/` 존재. **결함 C의 핵심 셀.**
**처방:**
- 리포트: `❌ REBASE 중단 감지 — .git/rebase-{merge|apply}/ 존재`
- 안내: `cd $REPO && git rebase --abort` 후 재실행
- 종료코드 6.
**이유:** rebase 중단 상태에서 rsync 진입 시 working tree가 오염됨. Phase 1에서 선차단.

### G6 — Detached HEAD (STOP)

**조건:** `git symbolic-ref HEAD` 실패 (현재 브랜치 없음).
**처방:**
- 리포트: 현재 HEAD hash + 브랜치 후보 (`git branch --contains HEAD`)
- 안내: `git checkout main` 또는 브랜치 생성
- 종료코드 7.
**이유:** detached 상태에서 commit하면 고아 커밋 생성. 자동 복구 불가 — 수동 판단 필요.

---

## POST_CHECK — Silent Failure 차단

G1·G2 처방 마지막 단계. **결함 A 재발 방지의 핵심**.

```bash
REMAINING=$(git rev-list --count "origin/$BRANCH..HEAD" 2>/dev/null || echo "?")
if [ "$REMAINING" != "0" ]; then
  echo "❌ POST_CHECK 실패 — 로컬에 미푸시 커밋 $REMAINING 개 잔존"
  git log "origin/$BRANCH..HEAD" --oneline
  exit 8
fi
```

**왜 필요한가:** push 명령 자체는 성공해도, 네트워크 중단·branch protection·타 race 등으로 실제 원격 반영이 안 될 수 있음. push 후 반드시 `origin/$BRANCH..HEAD` 차이 = 0 확인.

---

## v5 → v6 동작 변화 요약

| 케이스 | v5 (결함) | v6 (수정) |
|--------|-----------|-----------|
| 로컬 미푸시 커밋 존재 + rsync diff 없음 | "변경 없음 — 이미 최신" (silent failure) | G2 셀 → push 강제 실행 |
| push rejected (diverge) | auto `git pull --rebase` → timeout 시 detached HEAD 잔존 | G3 셀 → STOP + 사용자 컨펌 |
| 이전 세션의 rebase 중단 상태 | rsync 강행 → working tree 오염 | G5 셀 → STOP + abort 안내 |
| detached HEAD | 인식 안 함 → 고아 커밋 생성 위험 | G6 셀 → STOP |
| push 후 실제 원격 반영 여부 | 미검증 | POST_CHECK → exit 8 |

---

## 파일 매트릭스와의 관계

두 매트릭스는 **순차 게이트**. Pre-Flight Scan 흐름:

```
1. 파일 3-way 매트릭스 (state-matrix.md)
   → Cell 1·3만 통과 (O·L·R 파일 존재·정상)

2. Git 상태 매트릭스 (이 파일)
   → G1·G2만 통과 (로컬이 원격과 호환되는 상태)

3. Phase 3 실행 (rsync·commit·push)
```

어느 한 매트릭스라도 비정상 셀이면 STOP. 두 매트릭스의 공통 원칙:
- 결정적 분기 (UNKNOWN 제외 완전 열거)
- 자동 복구는 컨펌 불필요 셀만
- 파괴적 액션은 전부 컨펌 또는 매트릭스 외 수동

---

## Gotchas

| 함정 | 대응 |
|------|------|
| fetch 없이 Ahead/Behind 측정 | origin/$BRANCH가 stale → 잘못된 셀 분류. Phase 1 시작에 `git fetch origin` 1회 필수 |
| G3에서 `--force-with-lease` 자동 실행 | 원격 변경 유실 가능 → 금지. 항상 사용자 컨펌 |
| G5 abort 후 working tree 손실 착각 | abort는 rebase 시작 지점으로 복원. 원본 커밋은 reflog에 보존 |
| POST_CHECK 누락 | v5 silent failure 재발. Phase 3 마지막 단계 필수 |
| detached HEAD를 G3로 오분류 | HEAD 축이 먼저. G5·G6은 Ahead/Behind 측정 의미 없음 |
