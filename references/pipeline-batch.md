# 전체 동기화 배치 (Pre-Flight 기반)

"전체 동기화", "다 푸시해" 요청 시. **반드시 Pre-Flight Scan부터.**

---

## 절대 순서

```
⓪ Pre-Flight Scan (필수)
 ↓
① 셀별 분류 리포트 + 전체 컨펌
 ↓
② Cell 1·3 비파괴 일괄 (자동)
 ↓
③ Cell 7 안내 + 스킵
 ↓
④ Cell 2·4 건별 컨펌 → 순차
 ↓
⑤ Cell 5 건별 사용자 선택 (⛔ 가장 위험)
 ↓
⑥ Cell 6 건별 사용자 선택
 ↓
⑦ UNKNOWN 리포트 (액션 없음)
 ↓
⑧ 최종 리포트
```

**어떤 셀도 생략 금지. 순서 뒤집기 금지.** 비파괴가 먼저 끝나야 파괴적 에러가 전체를 블록하지 않음.

---

## ⓪ Pre-Flight Scan

```bash
bash "{repo_root}/git-sync/scripts/pre-flight-scan.sh" \
  "{plugin_skills_path}" "{repo_root}" "{github_user}"
```

출력: TSV(name·origin·local·remote·cell·action) + stderr 요약 + 로그 파일.

종료코드:
- 0 정상 (파괴적 액션 있어도 분류만 완료)
- 5 Cell 5 존재 → STOP 경고 (계속 여부 컨펌 필요)
- 6 UNKNOWN 존재 → 재스캔/수동 해결
- 2 인자 오류

**exit 5 또는 6 발생 시 형에게 상황 보고 → 지시 대기.**

상세 프로토콜 → `references/pre-flight-scan.md`.

---

## ① 셀별 분류 리포트 + 전체 컨펌

Pre-Flight 결과를 형에게 정리 제시:

```
Pre-Flight 완료 ({N}개 스킬 스캔)

[비파괴 — 자동 진행 대상]
  Cell 1 정상 동기화:      {M}개 (exit 4로 변경 없음 자동 필터)
  Cell 3 로컬 미클론:      {K}개 (clone 후 자동 동기화)
  Cell 7 외부 레포:        {A}개 (스킵 + 안내)

[파괴적 — 건별 컨펌 필수]
  Cell 2 원격 유실:        {B}개 ⚠
  Cell 4 진짜 신규:        {C}개 ⚠ (gh repo create)
  Cell 5 원본 삭제:        {D}개 ⛔ (STOP 권고)
  Cell 6 고아 로컬:        {E}개 ⚠

[보류]
  UNKNOWN:                 {F}개 (스캔 실패)

변경 감지된 대상 (Cell 1·3에서 커밋 발생 예상):
  - trigger-dictionary (Cell 1)
  - hit-skill (Cell 1)
  - skill-builder (Cell 3, 신규 clone 포함)

진행할까요? [Cell 1·3 자동 → 이후 파괴적 셀은 건별 컨펌]
```

**이 단계 컨펌 전에는 어떤 액션도 금지.** 형이 "진행"이라고 해도 Cell 2·4·5·6은 각 건별로 또 컨펌받는다.

---

## ② Cell 1·3 비파괴 일괄

### Cell 3 (로컬 미클론) — 선행 clone

```bash
for skill in {cell_3_list}; do
  gh repo clone "{github_user}/$skill" "{repo_root}/$skill"
done
```

- 25개 이상: 순차 (REST API rate limit 회피)
- 6개 이하: 병렬 OK (clone은 git protocol, rate limit 대상 아님)

### Cell 1·3 공통 — sync-skill.sh 호출

```bash
bash "{repo_root}/git-sync/scripts/sync-skill.sh" \
  "{skill-name}" "{plugin_skills_path}" "{repo_root}" "{github_user}" \
  "Update {skill-name}: {변경요약}"
```

**배치 규칙:**
- push-only 6개 이하: 병렬 OK (git protocol은 API rate limit 대상 아님)
- `gh api` 포함 3개 이하: 병렬 (REST API rate limit 방지)
- 7개 이상: 순차 실행
- **exit 4(변경 없음)로 자동 필터링 — 별도 dry-run 불필요**

상세 → `references/skill-sync.md`.

---

## ③ Cell 7 안내 + 스킵

원본·로컬에 없고 GitHub에만 존재 → 외부 레포(다른 용도) 또는 과거 폐기 스킬.

```
Cell 7 (외부 레포, {A}개):
  - {repo_name_1}
  - {repo_name_2}

이 레포들은 원본·로컬에 없습니다. 의도적 외부 레포인지 확인하세요. (배치에서는 스킵)
```

**액션 없음. 스킵.**

---

## ④ Cell 2·4 건별 컨펌

### Cell 2 (원격 유실)

```
⚠ Cell 2: {skill-name}
  로컬·원본은 있으나 GitHub에 없음.
  원인 후보: (a) 레포 삭제됨, (b) rename, (c) API 일시 실패

  조치:
    [1] 원격 레포 새로 생성 + push (disaster-recovery §A)
    [2] API 재조회 후 재판정
    [3] 보류
  선택?
```

형 선택 → `references/disaster-recovery.md §A` 실행.

### Cell 4 (진짜 신규)

```
⚠ Cell 4: {skill-name}
  원본 존재, 로컬·원격 모두 없음 → 새 레포 생성 필요.

  조치: → references/new-repo-init.md (README 필수 생성)
  진행?
```

형 컨펌 → `references/new-repo-init.md` 실행.

**절대 자동 진행 금지.** Cell 4는 파괴적 액션(`gh repo create`) 포함. auto_mode=true여도 건별 컨펌.

---

## ⑤ Cell 5 건별 선택 (원본 삭제) — ⛔ 가장 위험

**원본은 없는데 GitHub·로컬에는 남은 상태. 원본 유실일 수도 있고 의도적 폐기일 수도 있다.**

```
⛔ Cell 5: {skill-name}
  원본 없음. 로컬·원격 모두 존재.
  원인 후보: (a) 의도적 폐기, (b) 원본 유실 (복구 필요), (c) rename 직후

  조치:
    [1] 원본 복구 → 로컬에서 원본으로 복사 (§B)
    [2] 원본 유실 확인 → 원격 아카이브 (§C, gh repo archive만, delete 금지)
    [3] 유지 + 로컬만 _archive/로 이동
    [4] 보류 (아무것도 안함) ← 기본값
  선택?
```

**기본 선택은 [4] 보류.** 절대 자동 삭제/아카이브 금지. `gh repo delete`는 절대규칙 #4에 의해 금지.

---

## ⑥ Cell 6 건별 선택 (고아 로컬)

```
⚠ Cell 6: {skill-name}
  원본·원격 모두 없음. 로컬 clone만 존재 (과거 작업 잔존).

  조치:
    [1] 로컬 _archive/로 이동 (disaster-recovery §D)
    [2] 로컬 완전 삭제 (⛔ 되돌릴 수 없음)
    [3] 보류 ← 기본값
  선택?
```

**기본 선택은 [3] 보류.**

---

## ⑦ UNKNOWN 리포트

```
❓ UNKNOWN ({F}개):
  - {skill-name-1} — {실패 이유, 예: gh api 500 에러}
  - {skill-name-2} — ...

조치 권고:
  1. Pre-Flight 재실행 (scripts/pre-flight-scan.sh)
  2. 해당 스킬 건별 수동 조사
  3. 이 배치에서는 스킵 (다음 배치로 이월)
```

**UNKNOWN에는 절대 액션 금지.** 상태 확정 전 분기=FAIL.

---

## ⑧ 최종 리포트

```
✅ 배치 완료 ({경과 시간})

Cell 1·3 동기화: {M+K}개 성공, {x}개 변경 없음, {y}개 실패
Cell 2 원격 복구: {B'}개 / {B}개
Cell 4 신규 생성: {C'}개 / {C}개
Cell 5 처리:     {D'}건 / {D}건 (나머지 보류)
Cell 6 처리:     {E'}건 / {E}건 (나머지 보류)
Cell 7 스킵:     {A}개
UNKNOWN 이월:    {F}개

실패/에러: {err_list}
```

로그: `{repo_root}/git-sync/logs/batch-{ts}.log`

---

## UP 동기화 포함 시

배치에 UP 동기화도 함께라면:

1. Pre-Flight Scan 이후 UP 축은 별도 조회 (UP는 단일 타겟 — 매트릭스 외)
2. 스킬 Cell 1·3 처리가 끝난 뒤 UP 동기화 실행 → `references/up-sync.md`
3. UP는 Pre-Flight 매트릭스에 포함되지 않음 — 별도 ENV 축

---

## 기존 레포 README 일괄 생성

"README 생성", "이중언어 README", "README 세팅" 요청 시. **Cell 1 상태인 레포 중 README 부재 탐지 → 생성.** Pre-Flight와 독립 실행 가능.

### 대상 스캔

```bash
for skill in $(ls "{repo_root}" | grep -v ".DS_Store"); do
  has_en=$([ -f "{repo_root}/$skill/README.md" ] && echo "Y" || echo "N")
  has_ko=$([ -f "{repo_root}/$skill/README.ko.md" ] && echo "Y" || echo "N")
  echo "$skill  EN=$has_en  KO=$has_ko"
done
```

### 리스트 + 컨펌

```
README 현황:
  trigger-dictionary  EN=Y  KO=N  → README.ko.md 생성 필요
  hit-skill           EN=N  KO=N  → README.md + README.ko.md 생성 필요
  biz-skill           EN=Y  KO=Y  → 스킵
  (총 {N}개 대상)

{N}개 레포에 README를 생성합니다. 진행할까요?
```

### 생성 + commit + push

각 대상 레포에 대해:

1. 해당 스킬의 SKILL.md를 읽어 name·description·핵심 기능 추출
2. `references/readme-templates.md` 템플릿 적용
3. 필요한 쪽만 생성 (영문·한글)
4. commit + push

```bash
cd "{repo_root}/{skill-name}"
git add README.md README.ko.md
git commit -m "Add bilingual README (EN/KO)"
git push
```

push-only 6개 이하 병렬 OK, `gh api` 포함 3개 이하, 7개+ 순차.
