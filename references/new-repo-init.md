# 새 레포 초기화 (Cell 4 전용)

**Cell 4 = (ORIGIN=✓, LOCAL=✗, REMOTE=✗) — 원본 존재, 로컬·원격 모두 없음.**

이 파일은 **Pre-Flight Scan이 Cell 4를 확정하고, 형이 건별 컨펌한 이후에만** 호출된다.

---

## ⛔ 진입 전제 (하나라도 위배되면 FAIL)

| # | 조건 | 위배 시 |
|---|------|---------|
| 1 | Pre-Flight Scan 완료 (`scripts/pre-flight-scan.sh` 실행 후 TSV 수집) | 진입 금지 — Pre-Flight부터 |
| 2 | 해당 스킬이 Cell 4로 분류됨 (ORIGIN=✓, LOCAL=✗, REMOTE=✗) | 진입 금지 — 매트릭스 재확인 |
| 3 | REMOTE 축이 UNKNOWN이 아님 (`gh api` 성공) | 진입 금지 — REMOTE 재스캔 |
| 4 | 형에게 건별 컨펌 받음 ("신규 생성 진행?" → "예") | 진입 금지 — auto_mode=true여도 건별 컨펌 |
| 5 | `gh repo create` 실행 직전 한 번 더 경고 출력 | 파괴적 액션 가드 위반 |

**README 생성이 초기 커밋의 필수 단계 — README 없는 초기 커밋 = 금지 (절대규칙 #5).**

---

## 플로우

```
⓪진입 전제 재확인 → ①메타파일 복사 + rsync → ②이중언어 README 생성 → ③민감정보 검사 → ④git init + commit + gh repo create + push
```

---

## ⓪ 진입 전제 재확인

파이프라인 진입 직전 출력:

```
⚠ 새 레포 생성 (gh repo create) 직전 확인

대상: {skill-name}
매트릭스: Cell 4 (O✓ L✗ R✗)
GitHub URL: https://github.com/{github_user}/{skill-name}
이후 되돌리려면 gh repo delete 필요 (절대규칙 #4로 금지됨)

진행? [y/N]
```

**N 또는 무응답 → STOP.** 로그에 "Cell 4 abort: {skill-name}" 기록.

---

## ① 메타파일 + rsync

```bash
mkdir -p "{repo_root}/{skill-name}" && \
cp "{repo_root}/trigger-dictionary/.gitignore" "{repo_root}/{skill-name}/" && \
cp "{repo_root}/trigger-dictionary/LICENSE" "{repo_root}/{skill-name}/" && \

# exclude 3단 폴백 (sync-skill.sh와 동일 로직)
EXCL="{repo_root}/{skill-name}/scripts/rsync-exclude.txt"
[ -f "$EXCL" ] || EXCL="{repo_root}/git-sync/scripts/rsync-exclude.txt"
if [ ! -f "$EXCL" ]; then
  EXCL=$(mktemp); printf '.git/\n.gitignore\nREADME.md\nREADME.ko.md\nLICENSE\n.DS_Store\n__pycache__/\n*.pyc\n' > "$EXCL"
fi
rsync -av --exclude-from="$EXCL" "{plugin_skills_path}/{skill-name}/" "{repo_root}/{skill-name}/"
```

---

## ② 이중언어 README 생성 (필수)

`references/readme-templates.md` 템플릿 참조. 절차:

1. 해당 스킬의 SKILL.md를 읽어 name·description·핵심 기능·연동 스킬 추출
2. 템플릿의 추출 규칙에 따라 각 플레이스홀더 채움
3. DC write_file로 README.md (영문) + README.ko.md (한글) 동시 생성
4. 영문은 번역체 금지 — 자연스러운 영어로 새로 작성
5. 한글은 SKILL.md 톤 유지 — 간결·단정

**이 단계를 건너뛰면 git-sync 절대규칙 #5 위반.**

---

## ③ 민감정보 검사 + init + push

```bash
cd "{repo_root}/{skill-name}" && \
SCAN="scripts/secret-scan.sh"; [ -f "$SCAN" ] || SCAN="{repo_root}/git-sync/scripts/secret-scan.sh"
bash "$SCAN" . || exit 1 && \
git init && git checkout -b main && \
git add -A && \
git commit -m "Initial commit: {skill-name}" && \
gh repo create "{github_user}/{skill-name}" \
  --public --source=. --push \
  --description "{SKILL.md description 첫 문장 영문}"
```

---

## ④ Post-Create 검증

`gh repo create` 성공 직후 즉시:

```bash
# 1. 원격 존재 확인
gh repo view "{github_user}/{skill-name}" --json name -q .name

# 2. 방금 push한 커밋이 origin/main에 올라갔는지
cd "{repo_root}/{skill-name}"
git log origin/main --oneline -1

# 3. README 2개 모두 존재
[ -f README.md ] && [ -f README.ko.md ] && echo "README OK"
```

세 확인 모두 통과해야 Cell 4 완료로 마킹. 하나라도 실패 → `disaster-recovery.md §E` (의도치 않은 신규 레포 롤백 루트).

---

## 리포트

```
✅ {skill-name} 새 레포 생성 + 동기화 완료 (Cell 4)
  파일: {N}개 (SKILL.md + references + README.md + README.ko.md)
  커밋: {hash 7자리}
  URL: https://github.com/{github_user}/{skill-name}
  검증: 원격 존재 ✓ / origin/main 일치 ✓ / README 2종 ✓
```

---

## Gotchas

| 함정 | 대응 |
|------|------|
| Pre-Flight 없이 이 파일 직행 | 진입 전제 #1 위반 — FAIL |
| REMOTE=UNKNOWN 상태에서 Cell 4로 오분류 | Pre-Flight 재실행. REMOTE API 재시도 |
| `gh repo create`에 `--private` 기본값 기대 | 본 스킬은 `--public` 기본. 변경 시 명시 플래그 필수 |
| README 생성 누락한 초기 커밋 | 절대규칙 #5 위반. 롤백 필요 시 §E |
| auto_mode=true라 건별 컨펌 스킵 | Cell 2·4·5·6은 auto_mode 무관 컨펌 강제 |
