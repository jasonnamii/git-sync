# Pre-Flight Scan — 3-way 상태 수집 프로토콜

**동기화 진입 전 필수 선행 단계.** 모든 대상 스킬의 상태 벡터를 수집 완료하기 전까지 어떤 파괴적·비파괴적 액션도 금지.

---

## 목적

각 스킬에 대해 `(ORIGIN, LOCAL, REMOTE)` 상태 벡터를 수집 → `state-matrix.md`의 8셀 중 1개로 분류 → 셀별 액션 결정.

**이 단계를 생략하면 2026-04-16 사고 재발.** 절대규칙 #6 위반.

---

## 실행 — scripts/pre-flight-scan.sh 1회 호출

```bash
bash "{repo_root}/git-sync/scripts/pre-flight-scan.sh" \
  "{plugin_skills_path}" "{repo_root}" "{github_user}"
```

출력: tab-separated 테이블 (stdout) + 분류 요약

```
# Format: name<TAB>origin<TAB>local<TAB>remote<TAB>cell<TAB>action
biz-skill	1	1	1	1	sync
hit-skill	1	0	1	3	clone+sync
foo-legacy	0	1	1	5	STOP_CONFIRM
new-skill	1	0	0	4	CREATE_NEW_CONFIRM
...
```

---

## 스캔 로직 (스크립트 내장)

### 1. ORIGIN 스캔

```bash
ORIGIN_LIST=$(ls "{plugin_skills_path}" | grep -v '^\.' | while read n; do
  [ -f "{plugin_skills_path}/$n/SKILL.md" ] && echo "$n"
done)
```

### 2. LOCAL 스캔

```bash
LOCAL_LIST=$(ls "{repo_root}" | grep -v '^\.' | while read n; do
  [ -d "{repo_root}/$n/.git" ] && echo "$n"
done)
```

### 3. REMOTE 스캔 (세션 1회, gh API)

```bash
REMOTE_LIST=$(gh repo list "{github_user}" --limit 500 --json name -q '.[].name')
```

**실패 시:** REMOTE 축을 `?` (UNKNOWN) 마크. 다른 축은 정상 수집 시도.

### 4. 3-way 결합 + 셀 분류

모든 스킬 이름의 합집합 → 각 이름의 3축 조회 → state-matrix 테이블 조회 → 셀 번호 + 액션 할당.

### 5. 분류 요약 출력

```
[Pre-Flight 스캔 완료 — N개 스킬 분류]

✅ Cell 1 (정상):      12개 — auto push 가능
🔵 Cell 3 (clone 필요): 25개 — auto clone+push 가능 (순차)
⚠  Cell 2 (원격 유실):  0개
⚠  Cell 4 (신규 생성):  2개 ← 개별 컨펌 필요
⚠  Cell 5 (원본 삭제):  1개 ← STOP 트리거
⚠  Cell 6 (고아 로컬):  0개
ℹ  Cell 7 (외부 레포):  3개 — 스킵
❓ UNKNOWN:             0개

파괴적 액션 포함 3건. 건별 컨펌 필요.
진행할까요?
```

---

## 캐싱

- REMOTE_LIST는 세션 1회 조회 후 ENV_CACHE의 `remote_repos` 필드에 저장
- 동일 세션 내 재스캔 시 캐시 사용
- 명시적 "원격 재스캔" 요청 시 무효화

---

## UNKNOWN 처리 플로우

스캔 중 축 1개 이상 실패:

```
❓ UNKNOWN: {skill-name}
  축별 상태: ORIGIN=✓ LOCAL=? REMOTE=✓
  실패: LOCAL 스캔 중 permission denied

대응:
  a) 원인 해결 후 재스캔 (권장)
  b) 이 스킬 제외하고 나머지 진행
  c) 전체 중단
```

UNKNOWN 포함 건은 배치에서 **자동 제외** — 나머지만 진행 옵션 제공.

---

## 배치 진입 순서 (결정적)

스캔 완료 후 처리 순서:

1. **Cell 1·3 (비파괴)**: 일괄 진행 가능 (병렬/순차 규칙은 pipeline-batch.md §배치 참조)
2. **Cell 7 (스킵)**: 1회 안내 출력
3. **Cell 2·4 (신규 생성)**: 건별 컨펌 → 컨펌된 것만 순차
4. **Cell 5 (원본 삭제)**: 건별 사용자 선택 → `disaster-recovery.md`
5. **Cell 6 (고아 로컬)**: 건별 사용자 선택
6. **UNKNOWN**: 리포트만 + 사용자 결정 대기

**순서 변경 금지.** Cell 1·3을 먼저 완료해 비파괴 변경 사항을 분리 push → 파괴적 액션 오류 시에도 일반 동기화는 완료된 상태 유지.

---

## 에이전트 행동 규칙

| 상황 | 행동 |
|------|------|
| Pre-Flight 미완료 상태 액션 시도 | 절대규칙 #6 위반 — STOP + 보고 |
| Cell 2/4/5/6 자동 실행 | 절대규칙 #7 위반 — STOP + 보고 |
| REMOTE 스캔 실패 후 '원격 없음' 가정 | 금지. UNKNOWN 마크 유지 |
| 스캔 결과와 다른 셀로 분류 | 금지. 테이블 조회 결과만 신뢰 |
| 스캔 생략하고 단일 스킬 처리 | 허용 (단일 스킬 `git-sync {name}` 경로): 그 1개만 3축 조회 후 진행 |

---

## 단일 스킬 경로 (최소 스캔)

"form-skill 동기화" 같은 단일 명시 요청은 전체 N개 스캔 불필요. 해당 1개만 3축 조회 → 셀 분류 → 액션.

```bash
# Mini Pre-Flight
NAME="biz-skill"
O=$([ -f "{plugin_skills_path}/$NAME/SKILL.md" ] && echo 1 || echo 0)
L=$([ -d "{repo_root}/$NAME/.git" ] && echo 1 || echo 0)
R=$(gh repo view "{github_user}/$NAME" --json name -q .name 2>/dev/null | grep -q "$NAME" && echo 1 || echo 0)
# (O,L,R) → state-matrix 조회 → 액션
```

단일 스킬 REMOTE 체크는 `gh repo view` 1회 호출 (가벼움).

---

## 출력 로그

스캔 결과는 `{repo_root}/git-sync/logs/preflight-{timestamp}.log`에 기록. 디렉터리 없으면 생성.

형식: 스캔 시각 + 3축 raw 데이터 + 분류 결과 + 에이전트가 내린 결정.

사고 발생 시 로그 역추적으로 원인 특정 가능.
