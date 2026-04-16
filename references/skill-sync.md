# 단일 스킬 동기화 (Cell 1·3)

**Cell 1 = (O✓ L✓ R✓) 정상 / Cell 3 = (O✓ L✗ R✓) 로컬 미클론.**

sync-skill.sh 1회 호출로 완결. **Pre-Flight Scan(또는 Mini Pre-Flight)로 Cell 1·3 확정이 진입 전제.**

---

## ⛔ 진입 전제

| # | 조건 | 위배 시 |
|---|------|---------|
| 1 | Pre-Flight 또는 Mini Pre-Flight 통과 | 진입 금지 |
| 2 | 해당 스킬 셀이 1 또는 3 | Cell 2·4·5·6·7은 각 전용 경로로 |
| 3 | REMOTE 축이 UNKNOWN이 아님 | REMOTE 재스캔 후 재분류 |
| 4 | (Cell 3의 경우) clone 대상 레포 URL 확정 | `gh repo view`로 확인 |

배치 컨텍스트에서는 Pre-Flight가 이 전제를 이미 만족시킨다. 단일 스킬 요청 시에는 → Mini Pre-Flight (`references/pre-flight-scan.md §단일 스킬 경로`).

---

## Cell 1 실행

```bash
# DC start_process로 실행 (Cowork 샌드박스 Bash 금지)
bash "{repo_root}/git-sync/scripts/sync-skill.sh" \
  "{skill-name}" \
  "{plugin_skills_path}" \
  "{repo_root}" \
  "{github_user}" \
  "Update {skill-name}: {변경요약}"
```

**DC 호출 수:** ENV 캐시 유무 무관하게 **1회**. 스크립트가 PRE_SYNC_CHECK + rsync + secret-scan + commit + push를 모두 내장.

---

## Cell 3 실행 (로컬 미클론)

**선행 clone 후 Cell 1과 동일 스크립트.**

```bash
# 1. 원격 clone
gh repo clone "{github_user}/{skill-name}" "{repo_root}/{skill-name}"

# 2. Cell 1과 동일
bash "{repo_root}/git-sync/scripts/sync-skill.sh" \
  "{skill-name}" \
  "{plugin_skills_path}" \
  "{repo_root}" \
  "{github_user}" \
  "Update {skill-name}: {변경요약}"
```

**Cell 3 주의:** clone 직후 원본과 레포 내용이 다를 수 있다. sync-skill.sh 내장 `PRE_SYNC_CHECK`가 삭제 감지 시 exit 3 → 형에게 보고.

---

## 종료코드별 에이전트 행동

| exit code | 의미 | 에이전트 행동 |
|-----------|------|-------------|
| 0 | 성공 | 스크립트 출력의 리포트를 형에게 전달 |
| 1 | 에러 (원본 없음, 민감정보, push 2회 실패) | 에러 메시지 보고 + STOP |
| 2 | 인자 오류 | 인자 확인 후 재시도 (1회만) |
| 3 | 삭제 감지 | 삭제 목록을 형에게 표시 → 확인 후 수동 진행 or 중단 |
| 4 | 변경 없음 | ".skill 설치 먼저 해주세요" 안내 + STOP |

---

## 스크립트 내장 로직 (에이전트가 재현할 필요 없음)

1. **exclude 3단 폴백:** 레포 내 `scripts/rsync-exclude.txt` → `{repo_root}/git-sync/scripts/rsync-exclude.txt` → 인라인 하드코딩(tmpfile + 경고)
2. **git-sync 레포 자동 clone:** 로컬에 없으면 `gh repo clone` 시도
3. **PRE_SYNC_CHECK:** `rsync -avn --delete`로 삭제 예정 파일 감지 → exit 3
4. **diff 0건 체크:** 변경 없으면 .skill 미설치 경고 → exit 4
5. **secret-scan 2단 폴백:** 레포 내 → git-sync 레포
6. **push 재시도:** 1회 `pull --rebase` 후 재시도. 2회 실패 → exit 1

---

## 삭제 감지 시 수동 진행

exit 3 발생 시:

```bash
# 형이 확인 후 삭제 허용 — rsync --delete 직접 실행
cd "{repo_root}/{skill-name}"
EXCL="scripts/rsync-exclude.txt"; [ -f "$EXCL" ] || EXCL="{repo_root}/git-sync/scripts/rsync-exclude.txt"
rsync -av --delete --exclude-from="$EXCL" "{plugin_skills_path}/{skill-name}/" ./
git add -A && git commit -m "Update {skill-name}: {변경요약}" && git push
```

---

## 배치

push-only 6개 이하: 병렬 OK. `gh api` 호출 포함 3개 이하. 7개+: 순차.

**배치 프리체크:** 복수 스킬 동시 push 시, sync-skill.sh의 exit 4(변경 없음)로 자동 필터링. 별도 dry-run 불필요.

**Cell 3 일괄 처리:** Cell 3가 많은 경우(예: 첫 구축 후 25개+), clone을 먼저 순차 일괄 → 이어서 Cell 1과 함께 sync-skill.sh 병렬 배치.

```bash
# 1단계: Cell 3 clone 일괄 (순차)
for skill in {cell_3_list}; do
  gh repo clone "{github_user}/$skill" "{repo_root}/$skill"
done

# 2단계: Cell 1+3 sync 배치 (push-only 6개 이하 병렬 규칙 적용)
```

---

## 리포트

스크립트가 자동 출력:

```
✅ {skill-name} 동기화 완료 (Cell {1|3})
  커밋: {hash 7자리}
  URL: https://github.com/{github_user}/{skill-name}
  {diff stat}
```

---

## Gotchas

| 함정 | 대응 |
|------|------|
| Pre-Flight 없이 단일 스킬 호출 | Mini Pre-Flight 필수 — 3축 1회 조회 |
| Cell 3로 분류됐는데 clone 생략 | clone 선행 필수. sync-skill.sh는 로컬 clone 전제 |
| REMOTE UNKNOWN 상태에서 Cell 1로 오분류 | REMOTE 재스캔. 실패 시 UNKNOWN 유지 + 배치에서 제외 |
| clone 직후 sync에서 대량 삭제 감지 | exit 3 — 원본과 레포 구조 불일치. 수동 조사 필수 |
