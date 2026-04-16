# UP 동기화

**UP는 단일 타겟 레포(`user-preferences`). 8셀 매트릭스와 동일 3축을 가지지만 단일 레포라 배치가 아닌 직선 플로우.**

**정확히 2회의 DC start_process만 사용한다.** 민감정보 검사·commit·push는 호출 2의 단일 bash 스크립트 안에서 `&&`로 체이닝한다. 3회 이상으로 분할하지 마라.

---

## ⛔ 진입 전제 (UP Mini Pre-Flight)

UP 전용 3축 확인 1회:

| 축 | 확인 | 결과 |
|----|------|------|
| ORIGIN | `ls $HOME/Library/CloudStorage/Dropbox/ObsidianVault/Agent-Ops/UP_user-preferences_v*.md` | ✓ / ✗ |
| LOCAL | `[ -d "{repo_root}/user-preferences/.git" ]` | ✓ / ✗ |
| REMOTE | `gh repo view {github_user}/user-preferences --json name` | ✓ / ✗ |

**Cell 1 (O✓ L✓ R✓) → 이 파일 진행.** 그 외 셀은 → `references/disaster-recovery.md` 또는 `references/new-repo-init.md`로 우회.

**UNKNOWN 발생 시 STOP.** UP는 원본이기 때문에 추측 진행 금지.

---

## 호출 1: 파일 탐색 + 복사

```bash
# 최신 UP 파일 찾기
UP_FILE=$(ls -1 "$HOME/Library/CloudStorage/Dropbox/ObsidianVault/Agent-Ops"/UP_user-preferences_v*.md | sort -V | tail -1) && \
STAB="$HOME/Library/CloudStorage/Dropbox/ObsidianVault/Agent-Ops/UP_stability.md" && \
REPO="{repo_root}/user-preferences" && \

# 복사
cp "$UP_FILE" "$REPO/" && \
[ -f "$STAB" ] && cp "$STAB" "$REPO/" ; \

# 구버전 정리: 현재 버전 외 삭제
CURRENT=$(basename "$UP_FILE") && \
cd "$REPO" && \
ls UP_user-preferences_v*.md 2>/dev/null | grep -v "$CURRENT" | xargs rm -f
```

---

## 호출 2: 민감정보 + commit + push

```bash
cd "{repo_root}/user-preferences" && \

# 민감정보 검사 → git-sync 레포의 secret-scan.sh 사용 (UP 레포에는 scripts/ 없음)
bash "{repo_root}/git-sync/scripts/secret-scan.sh" . || exit 1 && \

# commit + push (push 실패 시 1회 재시도)
git add -A && \
git diff --cached --quiet && echo "변경 없음" || \
(git commit -m "Update UP: {버전정보}" && \
 git push || (git pull --rebase && git push) || { echo "❌ push 2회 실패 — STOP"; exit 1; })
```

**참고:** UP 레포에는 SKILL.md가 없으므로 secret-scan.sh의 SKILL.md 제외 로직이 자연스럽게 무해(no-op)하다. 별도 플래그 불필요.

---

## UP Cell별 우회 플로우

| UP Mini Pre-Flight 결과 | 의미 | 우회 |
|------|------|------|
| O✓ L✓ R✓ (Cell 1) | 정상 | 이 파일 진행 |
| O✓ L✓ R✗ (Cell 2) | GitHub UP 레포 유실 | `disaster-recovery.md §A` |
| O✓ L✗ R✓ (Cell 3) | 로컬 clone 필요 | `gh repo clone` → 이 파일 진행 |
| O✓ L✗ R✗ (Cell 4) | UP 레포 신규 생성 | `new-repo-init.md` (대상=`user-preferences`) |
| O✗ L? R? (Cell 5·6) | 원본 UP 파일 유실 | **STOP. 원본 복구 선행 필수** |
| 기타 UNKNOWN | 스캔 실패 | 재스캔 |

---

## 리포트

```
✅ user-preferences 동기화 완료
  변경: {N}파일 수정, {M}추가, {K}삭제
  커밋: {hash 7자리}
  URL: https://github.com/{github_user}/user-preferences
```

---

## Gotchas

| 함정 | 대응 |
|------|------|
| UP Mini Pre-Flight 생략 | 셀 확정 없이 복사·push=FAIL. 반드시 3축 확인 |
| 원본 UP 파일 유실(Cell 5) 감지 | 절대 레포→원본 역복사 금지. 형에게 원본 복구 요청 |
| 버전 번호 rollback (v35.7→v35.6) 감지 | 호출 2에서 `git diff --cached`로 확인, 이상 시 STOP |
| `UP_stability.md` 미존재 | `[ -f "$STAB" ]` 가드로 무해. 건너뜀 |
| 구버전 파일 잔존 | 호출 1의 `xargs rm -f`가 현재 버전 외 자동 정리 |
