# Batch Guide — Pre-Flight · 단일·배치·UP·신규 레포 통합

스크립트(`pre-flight-scan.sh`·`sync-skill.sh`)가 주인. 에이전트는 **진입 분기·컨펌 게이트·리포트**만 담당.

---

## 1. Pre-Flight Scan

```bash
bash "{repo_root}/git-sync/scripts/pre-flight-scan.sh" \
  "{plugin_skills_path}" "{repo_root}" "{github_user}"
# [--no-cache] 옵션: REMOTE 캐시 강제 재조회
```

**캐시:** `{repo_root}/git-sync/.remote-cache` (TTL 600초). 세션 끊겨도 살아남음.

**종료코드:** 0=정상 / 5=Cell 5 있음 STOP / 6=UNKNOWN 있음 재스캔 / 2=인자 오류

**출력:** TSV(name·origin·local·remote·cell·action) + stderr 요약 + `logs/preflight-{ts}.log`.

**Fast Path (단일 스킬 + 최근 스캔 존재):** `logs/preflight-*.log` 최신 파일 10분 이내면 재사용. 그 안에 해당 스킬이 Cell 1/3이면 **Pre-Flight 생략하고 §2 직행**. 아니면 스캔 재실행.

---

## 2. 단일 스킬 동기화 (Cell 1·3)

```bash
# v3 자동 모드 (DC 1회 완결 — ENV 자동 source)
bash "{repo_root}/git-sync/scripts/sync-skill.sh" \
  "{skill-name}" "Update {skill-name}: {변경요약}" --turbo

# 레거시 5인자 모드 (호환)
bash "{repo_root}/git-sync/scripts/sync-skill.sh" \
  "{skill-name}" "{plugin_skills_path}" "{repo_root}" "{github_user}" \
  "Update {skill-name}: {변경요약}"
```

**v3 변경:** ENV 자동 로딩(`.git-sync-env` 3단 폴백) → DC 호출 1회로 완결. `--turbo`시 dry-run 스킵(삭제 감지 불필요한 일반 업데이트에 사용). macOS timeout 폴백(perl) 내장.

**Cell 3 (로컬 미클론) 선행 clone:**
```bash
gh repo clone "{github_user}/{skill-name}" "{repo_root}/{skill-name}"
# 그다음 sync-skill.sh
```

**종료코드별 행동:**

| exit | 의미 | 에이전트 |
|:-:|---|---|
| 0 | 성공 | 리포트 전달 |
| 1 | 에러 (원본 없음·민감정보·push 2회 실패) | 메시지 보고 + STOP |
| 2 | 인자 오류 | 1회 재시도 |
| 3 | 삭제 감지 | 삭제 목록 형에게 → 확인 후 수동 |
| 4 | 변경 없음 | ".skill 설치 먼저" 안내 |

**삭제 감지 수동 진행:**
```bash
cd "{repo_root}/{skill-name}"
EXCL="scripts/rsync-exclude.txt"
[ -f "$EXCL" ] || EXCL="{repo_root}/git-sync/scripts/rsync-exclude.txt"
rsync -av --delete --exclude-from="$EXCL" "{plugin_skills_path}/{skill-name}/" ./
git add -A && git commit -m "..." && git push
```

---

## 3. 배치 (전체 동기화)

### 순서 (고정 — 생략·뒤집기 금지)

```
⓪ Pre-Flight → ① 분류 리포트+컨펌 → ② Cell 1·3 비파괴 일괄
   → ③ Cell 7 안내 → ④ Cell 2·4 건별 컨펌 → ⑤ Cell 5 선택 → ⑥ Cell 6 선택 → ⑦ UNKNOWN 리포트 → ⑧ 최종
```

비파괴가 먼저 끝나야 파괴적 에러가 전체를 블록하지 않는다.

### ① 분류 리포트 포맷

```
Pre-Flight 완료 (N개 스캔, REMOTE 캐시 HIT/MISS)

[비파괴]     Cell 1: M개 / Cell 3: K개 / Cell 7: A개
[파괴적]     Cell 2: B개 ⚠ / Cell 4: C개 ⚠ / Cell 5: D개 ⛔ / Cell 6: E개 ⚠
[보류]       UNKNOWN: F개

진행? [Cell 1·3 자동 → 이후 건별 컨펌]
```

**이 단계 컨펌 전 어떤 액션도 금지.**

### ② Cell 1·3 일괄

- push-only 6개 이하: 병렬 OK
- `gh api` 포함 3개 이하: 병렬
- 7개+ : 순차
- Cell 3가 많으면 clone 순차 일괄 → 이어서 sync 배치

```bash
# Cell 3 clone 일괄
for skill in {cell_3_list}; do
  gh repo clone "{github_user}/$skill" "{repo_root}/$skill"
done
# Cell 1+3 sync
for skill in {cell_1_and_3_list}; do
  bash "{repo_root}/git-sync/scripts/sync-skill.sh" "$skill" ...
done
```

### ③ Cell 7 — 1회 안내 + 스킵

### ④ Cell 2·4 — 건별 컨펌

**Cell 2 (원격 유실):** 복구/재조회/보류 선택. 복구시 `disaster-recovery.md §A`.

**Cell 4 (진짜 신규):** `gh repo create` 직전 경고 → 형 컨펌 → §5 실행.

### ⑤ Cell 5 — 원본 삭제 (기본 보류)

복구/아카이브/로컬만 아카이브/보류 — `disaster-recovery.md §B·C`.

### ⑥ Cell 6 — 고아 로컬 (기본 보류)

`disaster-recovery.md §D`.

---

## 4. UP 동기화 (정확히 DC 2회)

**UP Mini Pre-Flight:**
- ORIGIN: `$HOME/Library/CloudStorage/Dropbox/ObsidianVault/Agent-Ops/UP_user-preferences_v*.md`
- LOCAL: `{repo_root}/user-preferences/.git`
- REMOTE: `gh repo view {github_user}/user-preferences`

**Cell 1 (O✓L✓R✓)만 이 플로우. 그 외 → `disaster-recovery.md` / §5 (신규).**

### 호출 1 — 파일 탐색·복사·구버전 정리
```bash
UP_FILE=$(ls -1 "$HOME/Library/CloudStorage/Dropbox/ObsidianVault/Agent-Ops"/UP_user-preferences_v*.md | sort -V | tail -1) && \
STAB="$HOME/Library/CloudStorage/Dropbox/ObsidianVault/Agent-Ops/UP_stability.md" && \
REPO="{repo_root}/user-preferences" && \
cp "$UP_FILE" "$REPO/" && \
[ -f "$STAB" ] && cp "$STAB" "$REPO/" ; \
CURRENT=$(basename "$UP_FILE") && \
cd "$REPO" && \
ls UP_user-preferences_v*.md 2>/dev/null | grep -v "$CURRENT" | xargs rm -f
```

### 호출 2 — 민감정보 + commit + push
```bash
cd "{repo_root}/user-preferences" && \
bash "{repo_root}/git-sync/scripts/secret-scan.sh" . || exit 1 && \
git add -A && \
# macOS timeout 폴백 (coreutils timeout 없을 때)
command -v timeout &>/dev/null || timeout() { perl -e 'alarm shift; exec @ARGV' "$@"; }

(git diff --cached --quiet && echo "변경 없음") || \
(git commit -m "Update UP: {버전}" && \
 (timeout 30 git push || (timeout 30 git pull --rebase && timeout 30 git push)) || \
 { echo "❌ push 실패 — STOP"; exit 1; })
```

**주의:** 버전 rollback(v35.7→v35.6) 감지시 STOP. 원본 UP 유실(Cell 5)시 레포→원본 역복사 **절대 금지** — 형에게 원본 복구 요청.

---

## 5. 신규 레포 생성 (Cell 4 / Cell 2 복구)

### 진입 전제 (모두 충족)
1. Pre-Flight로 Cell 4 확정 (또는 Cell 2 복구 의도 확정)
2. REMOTE가 UNKNOWN이 아님
3. 형에게 건별 컨펌 ("신규 생성 진행?" → "예")
4. auto_mode=true여도 건별 컨펌 강제

### 경고 출력
```
⚠ 새 레포 생성 (gh repo create) 직전 확인
대상: {skill-name} (Cell 4: O✓ L✗ R✗)
URL: https://github.com/{github_user}/{skill-name}
되돌리려면 gh repo delete 필요 (절대규칙 #4로 금지)
진행? [y/N]
```

### 실행
```bash
mkdir -p "{repo_root}/{skill-name}" && \
cp "{repo_root}/trigger-dictionary/.gitignore" "{repo_root}/{skill-name}/" && \
cp "{repo_root}/trigger-dictionary/LICENSE" "{repo_root}/{skill-name}/" && \
EXCL="{repo_root}/git-sync/scripts/rsync-exclude.txt" && \
rsync -av --exclude-from="$EXCL" "{plugin_skills_path}/{skill-name}/" "{repo_root}/{skill-name}/"
```

### README 2종 생성 (필수 — 절대규칙 #5)
`readme-templates.md` 참조. SKILL.md에서 name·description·핵심 기능 추출 → 영문(자연스럽게)·한글(SKILL.md 톤) 2개 작성.

### init + push + 검증
```bash
cd "{repo_root}/{skill-name}" && \
SCAN="scripts/secret-scan.sh"; [ -f "$SCAN" ] || SCAN="{repo_root}/git-sync/scripts/secret-scan.sh"
bash "$SCAN" . || exit 1 && \
git init && git checkout -b main && \
git add -A && git commit -m "Initial commit: {skill-name}" && \
gh repo create "{github_user}/{skill-name}" --public --source=. --push \
  --description "{SKILL.md description 첫 문장 영문}"

# 검증 3종
gh repo view "{github_user}/{skill-name}" --json name -q .name
git log origin/main --oneline -1
[ -f README.md ] && [ -f README.ko.md ] && echo "README OK"
```

하나라도 실패 → `disaster-recovery.md §E`.

---

## 6. 기존 레포 README 일괄 생성

Cell 1 레포 중 README 부재 탐지 → 템플릿 적용 → commit + push.

```bash
for skill in $(ls "{repo_root}" | grep -v ".DS_Store" | grep -v '^_'); do
  has_en=$([ -f "{repo_root}/$skill/README.md" ] && echo Y || echo N)
  has_ko=$([ -f "{repo_root}/$skill/README.ko.md" ] && echo Y || echo N)
  echo "$skill  EN=$has_en  KO=$has_ko"
done
```

대상 스킬별로 SKILL.md 읽고 `readme-templates.md` 적용 → 커밋 → push.

---

## 7. 최종 리포트 포맷

```
✅ 배치 완료 ({경과})

Cell 1·3:  {M+K}개 동기화 / {x}개 변경 없음 / {y}개 실패
Cell 2:    {B'}/{B} 복구
Cell 4:    {C'}/{C} 생성
Cell 5:    {D'}/{D} 처리 (나머지 보류)
Cell 6:    {E'}/{E} 처리 (나머지 보류)
Cell 7:    {A}개 스킵
UNKNOWN:   {F}개 이월

로그: {repo_root}/git-sync/logs/
```

---

## Gotchas

| 함정 | 대응 |
|---|---|
| Pre-Flight 없이 배치 진입 | 절대규칙 #6 위반. 단일은 Fast Path(§1 말미), 배치는 필수 |
| Cell 2/4/5/6 자동 실행 | 건별 컨펌 강제. auto_mode 무관 |
| REMOTE UNKNOWN을 '없음'으로 해석 | 금지. UNKNOWN 유지 |
| Cell 3 clone 생략 | sync-skill.sh는 로컬 clone 전제 |
| rebase 무한 블록 | timeout 30s 내장 |
| UP 역복사 (레포→원본) | 절대 금지. Cell 5는 형에게 원본 복구 요청 |
