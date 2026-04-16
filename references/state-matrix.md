# 상태 매트릭스 — 8셀 결정 테이블

git-sync의 유일한 분기 기준. **에이전트는 이 테이블 조회 외의 방식으로 액션을 추론하지 말 것.** 기억 재구성·추측 분기=FAIL.

---

## 상태 벡터

각 스킬(또는 UP)은 3축 상태 벡터를 가진다:

```
STATE := (ORIGIN, LOCAL, REMOTE) ∈ {✓, ✗}³
```

| 축 | ✓ 판정 기준 | ✗ 판정 기준 |
|---|---|---|
| ORIGIN | `{plugin_skills_path}/{name}/SKILL.md` 존재 | 파일 없음 |
| LOCAL | `{repo_root}/{name}/.git/` 존재 | .git 디렉터리 없음 |
| REMOTE | `{name}` ∈ REMOTE_REPOS (Pre-Flight 스캔 결과) | 목록에 없음 |

**UNKNOWN 판정:** 위 3축 중 1개라도 스캔 실패(API 에러·네트워크·권한) → `?` 마크. UNKNOWN 포함 벡터는 어떤 셀로도 분류하지 않는다.

---

## 8셀 결정 테이블

| # | ORIGIN | LOCAL | REMOTE | 의미 | 액션 | 컨펌 | 파괴적? |
|---|:-:|:-:|:-:|---|---|:-:|:-:|
| 1 | ✓ | ✓ | ✓ | 정상 동기화 | → `skill-sync.md` (sync-skill.sh 호출) | auto_mode 허용 | ✗ |
| 2 | ✓ | ✓ | ✗ | 원격 유실/미등록 | → `new-repo-init.md` (§Cell 2 플로우) | **필수** | ✓ (gh repo create) |
| 3 | ✓ | ✗ | ✓ | 로컬 미클론 | `gh repo clone` → `skill-sync.md` | auto_mode 허용 | ✗ |
| 4 | ✓ | ✗ | ✗ | 진짜 신규 | → `new-repo-init.md` (§Cell 4 플로우) | **필수** | ✓ (gh repo create) |
| 5 | ✗ | ✓ | ✓ | 원본 삭제됨 (의도 불명) | **STOP** + 사용자 확인 | **필수** | ✓ (잠재 삭제) |
| 6 | ✗ | ✓ | ✗ | 고아 로컬 | 정리 제안 (로컬 삭제 또는 유지) | **필수** | ✓ (로컬 rm) |
| 7 | ✗ | ✗ | ✓ | 외부 레포 (git-sync 범위 밖) | 스킵 + 1회 안내 | — | ✗ |
| 8 | ✗ | ✗ | ✗ | 해당 없음 | 스킵 (무시) | — | ✗ |

---

## 셀별 세부 액션

### Cell 1: 정상 동기화 (✓✓✓)

```bash
bash "{repo_root}/git-sync/scripts/sync-skill.sh" \
  "{name}" "{plugin_skills_path}" "{repo_root}" "{github_user}" "{commit-msg}"
```

- exit 0 → 리포트
- exit 3 (삭제 감지) → Cell 5와 유사 처리 (형 확인)
- exit 4 (변경 없음) → 스킵

### Cell 2: 원격 유실/미등록 (✓✓✗)

위험 시그널. 원격 레포가 있어야 하는데 없음 — 2가지 가능성:
- a) 실수로 원격 삭제됨
- b) 로컬 .git이 다른 origin을 가리킴 (외부 fork·이동)

액션:
1. `cd {repo_root}/{name} && git remote -v` 로 origin 확인
2. origin이 `github.com/{github_user}/{name}`을 가리키면 → 원격 삭제됨 (복구 플로우)
3. origin이 다르면 → Cell 7로 재분류 (외부 레포)

복구 플로우 (컨펌 필수):

```bash
cd "{repo_root}/{name}"
gh repo create "{github_user}/{name}" --public \
  --description "{SKILL.md 영문 설명}"
git push -u origin main
```

README.md / README.ko.md 존재 확인. 없으면 Cell 4 README 생성 단계 병행.

### Cell 3: 로컬 미클론 (✓✗✓)

2026-04-16 사고의 실제 케이스. 오판 금지.

```bash
gh repo clone "{github_user}/{name}" "{repo_root}/{name}"
bash "{repo_root}/git-sync/scripts/sync-skill.sh" \
  "{name}" "{plugin_skills_path}" "{repo_root}" "{github_user}" "Update {name}: {변경요약}"
```

auto_mode=true에서 자동 실행 허용. 단 25개↑ 일괄 clone은 순차(API rate limit 보호).

### Cell 4: 진짜 신규 (✓✗✗)

파괴적 액션 — 사용자 명시 컨펌 필수.

진입 전제:
- Pre-Flight Scan 완료 + REMOTE_REPOS에 `{name}` 부재 확인
- ORIGIN에 SKILL.md 존재 확인
- 사용자가 명시적으로 "신규 레포 생성" 컨펌

→ `new-repo-init.md` 플로우 실행.

### Cell 5: 원본 삭제됨 (✗✓✓)

STOP. 의도 불명 상태는 자동 진행 금지.

표시 예:
```
⚠ Cell 5 감지: {name}
  - 원본: 없음 ({plugin_skills_path}/{name} 부재)
  - 로컬: 있음 ({repo_root}/{name}/.git)
  - 원격: 있음 (github.com/{github_user}/{name})

의도 확인 필요:
  a) 스킬 삭제 — 로컬·원격·archive 모두 정리
  b) 원본만 실수 삭제 — 로컬에서 원본으로 복원
  c) 아카이브 — 원격 유지, 로컬 _archive/ 이동
  d) 보류 — 이번 동기화 스킵
```

각 선택지별 절차는 `disaster-recovery.md` 참조.

### Cell 6: 고아 로컬 (✗✓✗)

원격에도 없고 원본에도 없지만 로컬에만 있음. 과거 작업 잔여물 가능성.

```
⚠ Cell 6 감지: {name}
  로컬만 존재. 정리 제안:
  a) 로컬 _archive/ 이동 (권장)
  b) 즉시 삭제
  c) 유지 (무시)
```

컨펌 후 a는 `mv`, b는 `rm -rf` (명시 컨펌 2회), c는 skip.

### Cell 7: 외부 레포 (✗✗✓)

git-sync가 관리하는 원본이 없음. 다른 프로젝트 레포. 1회 안내 후 스킵.

```
ℹ Cell 7: {name} — git-sync 범위 밖 (외부 레포). 건너뜁니다.
```

### Cell 8: 해당 없음 (✗✗✗)

세 축 모두 없음. 무시. 로그도 남기지 않음.

---

## UNKNOWN 처리

상태 수집 중 1축이라도 실패하면 UNKNOWN:

```
❓ UNKNOWN: {name}
  ORIGIN=✓ LOCAL=? REMOTE=✓
  실패 원인: 로컬 스캔 에러 (permission denied)

이 스킬은 자동 처리하지 않습니다. 원인 해결 후 재스캔해주세요.
```

UNKNOWN 포함 건은 배치에서 제외. 나머지만 진행.

---

## 파괴적 액션 인벤토리

| 액션 | 발생 셀 | 컨펌 방식 |
|---|:-:|---|
| `gh repo create` | 2, 4 | 건당 명시 컨펌 (auto_mode 무시) |
| `rsync --delete` | 1(sync-skill.sh 내부) | exit 3 감지 시 형 확인 |
| 로컬 `rm -rf` | 6 | 2회 확인 (a/b/c 선택 + 재확인) |
| `git push --force` | 절대 금지 | — |
| `gh repo delete` | 절대 금지 | — |

---

## 테이블 유지 원칙

- 신규 셀 필요시 = SKILL.md 수정 사안. 매트릭스를 암묵 확장 금지
- 셀 번호는 고정(1~8). 추가 차원이 필요하면 별도 표로 교차
- 매트릭스 자체가 결정적 — 에이전트 해석 여지 금지
