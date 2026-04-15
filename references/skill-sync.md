# 단일 스킬 동기화

기존 레포가 있는 스킬의 rsync → commit → push 절차.

---

## DC 호출 수

| 조건 | DC 호출 | 설명 |
|------|---------|------|
| ENV 캐시 없음 (첫 호출) | 2회 | 호출 1: ENV + PRE_SYNC_CHECK → 호출 2: rsync + commit + push |
| ENV 캐시 있음 + auto_mode=false | 2회 | 호출 1: PRE_SYNC_CHECK → 호출 2: rsync + commit + push |
| ENV 캐시 있음 + auto_mode=true | **1회** | 통합: PRE_SYNC_CHECK + rsync + commit + push (삭제 감지 시 자동 중단) |

---

## 호출 1: ENV + PRE_SYNC_CHECK

```bash
# ENV resolve (캐시 있으면 이 부분 스킵)
GITHUB_USER=$(gh api user --jq .login) && \
REPO="{repo_root}/{skill-name}" && \
SRC="{plugin_skills_path}/{skill-name}" && \

# 원본·레포 존재 확인
[ -d "$SRC" ] || { echo "ERROR: 원본 없음"; exit 1; } && \
[ -d "$REPO/.git" ] || { echo "NEW_REPO_NEEDED: $REPO"; exit 0; } && \

# PRE_SYNC_CHECK: 삭제 예정 파일 확인
EXCL="$REPO/scripts/rsync-exclude.txt"
[ -f "$EXCL" ] || EXCL="{repo_root}/git-sync/scripts/rsync-exclude.txt"
if [ ! -f "$EXCL" ]; then echo "⚠️ exclude 부재 — 인라인 폴백" >&2; EXCL=$(mktemp); printf '.git/\n.gitignore\nREADME.md\nREADME.ko.md\nLICENSE\n.DS_Store\n__pycache__/\n*.pyc\n' > "$EXCL"; fi
rsync -avn --delete --exclude-from="$EXCL" "$SRC/" "$REPO/" | grep '^deleting '
```

**판정:**
- `NEW_REPO_NEEDED` 출력 → `references/new-repo-init.md`로 분기
- 삭제 0건 + rsync diff 0건 → "변경 없음" 보고. ⚠ 세션에서 편집했는데 diff 0건이면 **.skill 미설치 가능성** → "`.skill 설치 먼저 해주세요`" 안내 + STOP
- 삭제 0건 + diff 있음 → 호출 2 진행
- references/scripts/agents 내 삭제 → **STOP + 형 확인**
- 기타 삭제 → 삭제 목록 표시 + 형 확인 후 진행

---

## 호출 2: rsync + 민감정보 검사 + commit + push

```bash
cd "{repo_root}/{skill-name}" && \

# rsync
EXCL="scripts/rsync-exclude.txt"
[ -f "$EXCL" ] || EXCL="{repo_root}/git-sync/scripts/rsync-exclude.txt"
if [ ! -f "$EXCL" ]; then echo "⚠️ exclude 부재 — 인라인 폴백" >&2; EXCL=$(mktemp); printf '.git/\n.gitignore\nREADME.md\nREADME.ko.md\nLICENSE\n.DS_Store\n__pycache__/\n*.pyc\n' > "$EXCL"; fi
rsync -av --delete --exclude-from="$EXCL" "{plugin_skills_path}/{skill-name}/" ./ && \

# 민감정보 검사 → 레포 내 scripts/ 우선, 없으면 git-sync 레포 폴백
SCAN="scripts/secret-scan.sh"; [ -f "$SCAN" ] || SCAN="{repo_root}/git-sync/scripts/secret-scan.sh"
bash "$SCAN" . || exit 1 && \

# commit + push (push 실패 시 1회 재시도)
git add -A && \
git diff --cached --quiet && echo "변경 없음 — 이미 최신" || \
(git commit -m "Update {skill-name}: {변경요약}" && \
 git push || (git pull --rebase && git push) || { echo "❌ push 2회 실패 — STOP"; exit 1; })
```

---

## 통합 1회 호출 (ENV 캐시 + auto_mode=true)

```bash
cd "{repo_root}/{skill-name}" && \

# PRE_SYNC_CHECK 인라인 — 삭제 감지 시 자동 중단
EXCL="scripts/rsync-exclude.txt"
[ -f "$EXCL" ] || EXCL="{repo_root}/git-sync/scripts/rsync-exclude.txt"
if [ ! -f "$EXCL" ]; then echo "⚠️ exclude 부재 — 인라인 폴백" >&2; EXCL=$(mktemp); printf '.git/\n.gitignore\nREADME.md\nREADME.ko.md\nLICENSE\n.DS_Store\n__pycache__/\n*.pyc\n' > "$EXCL"; fi
DELETES=$(rsync -avn --delete --exclude-from="$EXCL" "{plugin_skills_path}/{skill-name}/" ./ | grep '^deleting ' || true) && \

if [ -n "$DELETES" ]; then
  echo "⚠️ 삭제 감지 — auto_mode에서도 중단:"; echo "$DELETES"; exit 1
fi && \

# diff 0건 체크 — .skill 미설치 감지
CHANGES=$(rsync -avn --exclude-from="$EXCL" "{plugin_skills_path}/{skill-name}/" ./ 2>/dev/null | grep -c '^[^.]' || true) && \
if [ "$CHANGES" -eq 0 ]; then
  echo "⚠️ 변경 없음 — .skill 미설치 가능성. 설치 후 재시도"; exit 1
fi && \

# rsync 실행
rsync -av --delete --exclude-from="$EXCL" "{plugin_skills_path}/{skill-name}/" ./ && \

# 민감정보 검사 → 레포 내 scripts/ 우선, 없으면 git-sync 레포 폴백
SCAN="scripts/secret-scan.sh"; [ -f "$SCAN" ] || SCAN="{repo_root}/git-sync/scripts/secret-scan.sh"
bash "$SCAN" . || exit 1 && \

# commit + push (push 실패 시 1회 재시도)
git add -A && \
git diff --cached --quiet && echo "변경 없음 — 이미 최신" || \
(git commit -m "Update {skill-name}: {변경요약}" && \
 git push || (git pull --rebase && git push) || { echo "❌ push 2회 실패 — STOP"; exit 1; })
```

**에러 처리:** push 재시도 로직이 코드블록에 내장. 2회 실패 → STOP.

**배치:** push-only 6개 이하 병렬. `gh api` 호출 포함 시 3개 이하. 7개+ 순차.

**배치 프리체크:** 복수 스킬 동시 push 시, rsync dry-run(`rsync -avn`)으로 변경 없는 스킬을 선제 제거한 뒤 변경 있는 스킬만 push 대상으로 진행. 변경 없는 스킬에 불필요한 secret-scan·commit 시도 방지.

---

## 리포트

```
✅ {skill-name} 동기화 완료
  변경: {N}파일 수정, {M}추가, {K}삭제
  커밋: {hash 7자리}
  URL: https://github.com/{github_user}/{skill-name}
```
