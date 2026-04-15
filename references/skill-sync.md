# 단일 스킬 동기화

기존 레포가 있는 스킬의 동기화. **sync-skill.sh 1회 호출로 완결.**

---

## 실행

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

---

## 리포트

스크립트가 자동 출력:
```
✅ {skill-name} 동기화 완료
  커밋: {hash 7자리}
  URL: https://github.com/{github_user}/{skill-name}
  {diff stat}
```
