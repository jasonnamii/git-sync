---
name: git-sync
description: |
  스킬·설정 GitHub 레포 생명주기 엔진. 3-way 상태 매트릭스 기반 결정적 분기(8셀). 새 레포 생성·clone·동기화·재해복구를 단일 진입점에서 처리. 개별 레포 구조({GITHUB_USER}/{skill-name}) 기반.
  P1: 깃동기화, git sync, 깃싱크, 깃푸시, 레포동기화, 깃허브동기화, 스킬동기화, 스킬업로드, 레포생성, 새레포.
  P2: 동기화해줘, 푸시해줘, 올려줘, sync, push, upload.
  P3: git sync, repo sync, github push, skill deployment, new repo.
  P4: skill-builder 패키징 완료 후, up-manager 수정 완료 후, 스킬 수정 완료 후.
  P5: git push 결과로, 동기화 리포트로.
  NOT: GitHub Pages 배포(→github-deploy), 스킬수정 자체(→skill-builder), git 일반작업(→직접수행).
vault_dependency: HARD
---

# Git Sync

스킬·UP → GitHub 레포 생명주기 관리. **3-way 상태 매트릭스(8셀)로 분기 결정. 부분 상태 추론 금지.**

---

## ⛔ 절대 규칙 (7개)

| # | 규칙 | 이유 |
|---|------|------|
| 1 | **DC start_process로만 실행** — Cowork 샌드박스 Bash 금지 | 샌드박스는 로컬 git repo 접근 불가 |
| 2 | **원본→레포 단방향** — 역방향 금지 | 원본은 skills-plugin 관리. 역동기화=충돌 |
| 3 | **README/LICENSE/.gitignore 보호** — rsync exclude 필수 | 레포 전용 메타파일 |
| 4 | **파괴적 액션 게이트** — `gh repo create`·`rsync --delete`·로컬 `rm -rf`는 각각 명시 컨펌 필수. `gh repo delete`·`git push --force`는 절대 금지 (복구 예외 §H). 실패 시 1회 재시도. 2회 실패 → STOP + 에러 보고 | 중복 생성·유실 방지 |
| 5 | **새 레포 = README 필수** — 초기 커밋에 README.md + README.ko.md 포함 | 매번 수동 요청 구조 방지 |
| 6 | **Pre-Flight Scan 필수** — 동기화 진입 전 3-way 상태 수집(ORIGIN·LOCAL·REMOTE) 완료 전에는 어떤 액션도 금지 | 2026-04-16 사고(로컬 부재→원격 부재 오판) 재발 방지 |
| 7 | **매트릭스 외 분기 금지** — `references/state-matrix.md`의 8셀 테이블 조회 결과만 신뢰. 기억 재구성·추측 분기=FAIL. UNKNOWN은 자동 진행 금지 | 상태 공간 완전 열거·결정적 분기 |

---

## 진입 순서 (고정)

```
① ENV_CACHE resolve  →  ② Pre-Flight Scan  →  ③ 상태 매트릭스 조회  →  ④ 셀별 액션 (컨펌 게이트)  →  ⑤ 리포트
```

**어느 단계도 생략 금지.** 단일 스킬 경로는 ②를 "미니 스캔"(3축 조회 1회)으로 축소 허용 (→ `references/pre-flight-scan.md` §단일 스킬 경로).

---

## ENV_CACHE

첫 발동에서 resolve → 세션 컨텍스트 보관. 세션 종료 시 소멸. 2회차 호출 시 캐시 확인 → 없으면 재resolve.

| 필드 | 확인 방법 |
|------|----------|
| `github_user` | `gh api user --jq .login` |
| `user_home` | `echo $HOME` |
| `plugin_skills_path` | `find "$HOME/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin" -maxdepth 3 -name "skills" -type d` |
| `repo_root` | `$HOME/github-repos/skill-repos/` |
| `remote_repos` | `gh repo list {github_user} --limit 500 --json name -q '.[].name'` (세션 1회, Pre-Flight가 채움) |
| `auto_mode` | 기본 false. "앞으로 자동으로 해" → true (세션 내). **파괴적 액션은 auto_mode 무관 항상 컨펌** |

**ENV resolve 폴백:** 1차 실패 시 세션 캐시 또는 `.git-sync-env` 파일 폴백. 둘 다 없으면 STOP + 형에게 확인.

**git-sync 레포 자동 보장 (ENV resolve 직후):**

```bash
if [ -d "{repo_root}/git-sync/.git" ]; then
  cd "{repo_root}/git-sync" && git pull --ff-only 2>/dev/null || true
else
  gh repo clone {github_user}/git-sync "{repo_root}/git-sync"
fi
```

이유: `sync-skill.sh`·`secret-scan.sh`·`pre-flight-scan.sh`가 이 레포에 있다.

---

## 경로 테이블

| 대상 | 원본 | 레포 | GitHub |
|------|------|------|--------|
| 스킬 | `{plugin_skills_path}/{name}/` | `{repo_root}/{name}/` | `github.com/{github_user}/{name}` |
| UP | `$HOME/Library/CloudStorage/Dropbox/ObsidianVault/Agent-Ops/UP_*.md` | `{repo_root}/user-preferences/` | `github.com/{github_user}/user-preferences` |

---

## 발동 조건

| 조건 | 행동 |
|------|------|
| skill-builder 패키징 완료 | Pre-Flight 후 동기화 제안 (auto_mode=true면 Cell 1·3만 자동, 2·4·5·6은 컨펌) |
| up-manager 수정 완료 | UP 동기화 제안 (→ `references/up-sync.md`) |
| 형이 직접 요청 (전체) | → `references/pipeline-batch.md` |
| 형이 직접 요청 (단일) | Mini Pre-Flight → `references/skill-sync.md` |

---

## 상태 매트릭스 — 핵심 분기

Pre-Flight Scan이 각 스킬에 상태 벡터 `(ORIGIN, LOCAL, REMOTE)`를 부여. 8개 셀 × 액션:

| # | O | L | R | 의미 | 액션 | 컨펌 |
|---|:-:|:-:|:-:|---|---|:-:|
| 1 | ✓ | ✓ | ✓ | 정상 | → `skill-sync.md` | auto |
| 2 | ✓ | ✓ | ✗ | 원격 유실 | → `disaster-recovery.md §A` | **필수** |
| 3 | ✓ | ✗ | ✓ | 로컬 미클론 | clone → `skill-sync.md` | auto |
| 4 | ✓ | ✗ | ✗ | 진짜 신규 | → `new-repo-init.md` | **필수** |
| 5 | ✗ | ✓ | ✓ | 원본 삭제 | STOP → `disaster-recovery.md §B/C` | **필수** |
| 6 | ✗ | ✓ | ✗ | 고아 로컬 | → `disaster-recovery.md §D` | **필수** |
| 7 | ✗ | ✗ | ✓ | 외부 레포 | 스킵 + 안내 | — |
| 8 | ✗ | ✗ | ✗ | 없음 | 스킵 | — |
| ? | any UNKNOWN | | | 스캔 실패 | STOP + 재스캔 요청 | **필수** |

**세부 액션은 `references/state-matrix.md` 전담.** 매트릭스에 없는 상태 = UNKNOWN = STOP.

---

## Pre-Flight Scan — scripts/pre-flight-scan.sh 1회 호출

```bash
bash "{repo_root}/git-sync/scripts/pre-flight-scan.sh" \
  "{plugin_skills_path}" "{repo_root}" "{github_user}"
```

출력: TSV(name·origin·local·remote·cell·action) + 요약(stderr) + 로그 저장.

종료코드:
- 0 = 정상 (모든 셀 확정, 파괴적 액션 있어도 분류만)
- 5 = Cell 5 존재 → STOP 트리거
- 6 = UNKNOWN 존재 → 재스캔 필요
- 2 = 인자 오류

상세는 → `references/pre-flight-scan.md`.

---

## 동기화 실행 — scripts/sync-skill.sh (Cell 1·3 공통)

```bash
bash "{repo_root}/git-sync/scripts/sync-skill.sh" \
  "{skill-name}" "{plugin_skills_path}" "{repo_root}" "{github_user}" "{커밋 메시지}"
```

Cell 3의 경우 선행 clone:

```bash
gh repo clone "{github_user}/{skill-name}" "{repo_root}/{skill-name}"
# 그 다음 위의 sync-skill.sh 호출
```

스크립트 내장 로직은 → `references/skill-sync.md`.

---

## 배치 순서 (결정적)

Pre-Flight 분류 후 **이 순서를 지켜 비파괴→파괴적 순으로 진행**:

1. Cell 1·3 (비파괴): 일괄 진행 (push-only 6개 이하 병렬, gh api 포함 3개 이하, 7개+ 순차)
2. Cell 7: 1회 안내 후 스킵
3. Cell 2·4: 건별 컨펌 → 컨펌된 것만 순차
4. Cell 5: 건별 사용자 선택 (삭제/복원/아카이브/보류)
5. Cell 6: 건별 사용자 선택
6. UNKNOWN: 리포트만, 액션 금지

비파괴를 먼저 완료해야 파괴적 액션 오류가 전체를 블록하지 않음.

---

## Gotchas

| 함정 | 대응 |
|------|------|
| Cowork Bash로 git push | 샌드박스라 실패. DC start_process만 |
| 로컬 clone 부재 ≠ 원격 레포 부재 | Pre-Flight Scan으로 3축 독립 수집. `-d .git` 단독 판별=FAIL (2026-04-16 사고) |
| auto_mode=true에서 새 레포 자동 생성 | **금지**. auto_mode는 Cell 1·3만. Cell 2·4·5·6은 항상 컨펌 |
| 매트릭스 미정의 상태 추측 진행 | UNKNOWN 선언 + STOP. 재스캔 요청 |
| rsync --delete에서 exclude 누락 | `scripts/rsync-exclude.txt` 필수. sync-skill.sh 내장 3단 폴백 |
| skills-plugin UUID 변경 | Cowork 재설치 시 → `disaster-recovery.md §G` |
| 동시 push 6개+ | push-only 6개 이하 병렬, API 포함 3개 이하, 7개+ 순차 |
| UP 버전 파일명 변경 | glob `v*.md`로 탐색, 구버전 자동 정리 |
| push 실패 뺑뺑이 | 1회 재시도 후 STOP. 자동 복구 루프 금지 |
| ENV resolve 실패 | 추측 금지. 실패 필드 보고 + STOP |
| 새 레포 README 누락 | 절대규칙 #5 위반. Cell 4는 README 필수 생성 |
| 에이전트가 rsync 직접 조립 | 금지. `sync-skill.sh` 호출. 3단 폴백·secret-scan·push 재시도 내장 |
| exclude 패턴 수정 | `scripts/rsync-exclude.txt` 유일 원본 |
| Pre-Flight 생략하고 단일 스킬 처리 | Mini Pre-Flight(3축 1회 조회) 필수. 완전 생략 불가 |
| `gh repo list` API 실패 | REMOTE 축 UNKNOWN 마크. 절대 "없음"으로 해석 금지 |

---

## References

- `references/state-matrix.md` — 8셀 결정 테이블 (분기 기준)
- `references/pre-flight-scan.md` — 3-way 스캔 프로토콜
- `references/skill-sync.md` — Cell 1·3 동기화 실행
- `references/new-repo-init.md` — Cell 4 신규 레포 생성
- `references/up-sync.md` — UP 동기화 전용 플로우
- `references/pipeline-batch.md` — 전체 동기화 배치 플로우
- `references/readme-templates.md` — 이중언어 README 템플릿
- `references/disaster-recovery.md` — Cell 2·5·6 + 재해 복구 플레이북

## Scripts

- `scripts/pre-flight-scan.sh` — 3-way 스캔 + 8셀 분류
- `scripts/sync-skill.sh` — Cell 1·3 동기화 실행 (rsync + secret-scan + commit + push)
- `scripts/secret-scan.sh` — 민감정보 검사
- `scripts/rsync-exclude.txt` — exclude 패턴 (유일 원본)
