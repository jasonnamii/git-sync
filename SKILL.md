---
name: git-sync
description: |
  스킬·설정 GitHub 레포 생명주기 엔진. 이중 매트릭스(파일 3-way 8셀 + Git 상태 6셀) 결정적 분기. 단일은 캐시로 2단계 push, 배치는 Pre-Flight 후 비파괴→파괴적 순. 개별 레포({GITHUB_USER}/{skill-name}).
  P1: 깃동기화, 깃싱크, 깃푸시, 레포동기화, 깃허브동기화, 스킬동기화, 스킬업로드, 레포생성, 새레포, git sync.
  P2: 동기화해줘, 푸시해줘, 올려줘, sync, push, upload.
  P3: git sync, repo sync, github push, skill deployment, new repo.
  P4: skill-builder 패키징 완료 후, up-manager 수정 완료 후, 스킬 수정 완료 후.
  P5: git push 결과로, 동기화 리포트로.
  NOT: GitHub Pages 배포(→github-deploy), 스킬수정 자체(→skill-builder), git 일반작업(→직접수행).
vault_dependency: HARD
---

# Git Sync

스킬·UP → GitHub 레포 생명주기 관리. **이중 매트릭스 순차 게이트**(파일 3-way 8셀 + Git 상태 6셀) + **Fast Path** 캐시 활용.

**v6 (2026-04-18):** Git 상태 매트릭스(G1~G6) 추가. sync-skill.sh를 3-Phase 상태머신으로 재구성(scan → dispatch → execute). v5의 silent failure / auto-rebase detached HEAD / rebase 중단 감지 누락을 매트릭스 단계에서 전차단.

---

## ⛔ 절대 규칙 (7개)

| # | 규칙 | 이유 |
|---|------|------|
| 1 | **DC start_process로만 실행** — Cowork 샌드박스 Bash 금지 | 샌드박스는 로컬 git repo 접근 불가 |
| 2 | **원본→레포 단방향** — 역방향 금지 | 원본은 skills-plugin 관리 |
| 3 | **README/LICENSE/.gitignore 보호** — rsync exclude 필수 | 레포 전용 메타파일 |
| 4 | **파괴적 액션 게이트** — `gh repo create`·`rsync --delete`·로컬 `rm -rf`는 명시 컨펌. `gh repo delete`·`git push --force`(bare)는 절대 금지(복구 §F 예외). **`git push --force-with-lease`는 허용** — race-safe, 로컬이 원격보다 앞서고 원격 변경 이미 로컬에 반영된 경우(rename·rebase 직후) 컨펌 없이 실행 | 중복·유실 방지 + 과잉 방어 차단 |
| 5 | **새 레포 = README 2종 필수** — 초기 커밋에 README.md + README.ko.md | 매번 수동 생성 방지 |
| 6 | **Pre-Flight Scan 필수** — 배치 진입 전 3-way 상태 수집 완료 전 어떤 액션도 금지. 단일 스킬은 Fast Path 허용 | 2026-04-16 사고(3축 독립 수집 미비) 재발 방지 |
| 7 | **매트릭스 외 분기 금지** — `state-matrix.md` 8셀 + `git-state-matrix.md` 6셀 + UNKNOWN만 신뢰. 기억 재구성·추측 분기=FAIL | 상태 공간 완전 열거 |
| 8 | **이중 매트릭스 순차 게이트** — 파일 매트릭스(O·L·R) Cell 1·3 통과 → Git 매트릭스(HEAD·Rebase·Ahead·Behind) G1·G2 통과만 실행 진입. 한 축이라도 실패 = STOP | 파일은 정상이어도 로컬 git 상태가 비정상이면 push 파괴 |

---

## 진입 분기 (1회 판정)

```
요청 유형?
  ├─ 단일 스킬 (1개 명시)    → Fast Path
  ├─ 배치·전체·N개+          → Full Pipeline
  ├─ UP 수정 후               → UP 동기화 (→ batch-guide.md §4)
  └─ Cell 2/4/5/6 복구        → disaster-recovery.md
```

---

## Fast Path (단일 스킬)

**조건:** 1개 스킬 명시 + `.git-sync-env` 존재.

```
DC 1회 호출로 완결: sync-skill.sh가 ENV 자동 로딩 → rsync → push → 리포트
```

**DC 호출: 1회.** ENV 미존재시 Full Pipeline으로 자동 폴백.

```bash
# DC 1회 — ENV 자동 source + sync + push 완결 (기본 = turbo)
bash "{repo_root}/git-sync/scripts/sync-skill.sh" \
  "{skill-name}" "Update {skill-name}: {변경요약}"
```

**기본 = turbo (v4~):** dry-run 스킵 + `--delete` 없음. 일반 업데이트 2배 빠름. 옵션 없이 기본 호출이 최속경로.

**`--strict`:** 파일 삭제가 포함된 업데이트일 때만 지정. dry-run으로 삭제 감지 후 실제 `--delete` 수행. 지정 안 하면 기본(turbo) 모드에서 레포에 고아 파일이 남을 수 있음.

**`--turbo`:** 하위호환 no-op. v4부터 기본이라 지정 불필요.

**레거시 5인자 호환:** `sync-skill.sh <name> <plugin_path> <repo_root> <gh_user> <msg> [--strict]` 도 동작.

세부 → `references/batch-guide.md §1·2`.

---

## Full Pipeline (배치)

```
⓪ ENV resolve+캐시  →  ① Pre-Flight Scan  →  ② 분류 리포트+컨펌  →  ③ 비파괴(Cell 1·3)  →  ④ 파괴적(Cell 2·4·5·6) 건별  →  ⑤ 최종 리포트
```

상세 → `references/batch-guide.md §1·3`.

---

## ENV_CACHE (파일 영속화)

**`{repo_root}/git-sync/.git-sync-env`** (shell 소스 가능)

```bash
export GITHUB_USER="jasonnamii"
export USER_HOME="$HOME"
export PLUGIN_SKILLS_PATH="$HOME/Library/.../skills"
export REPO_ROOT="$HOME/github-repos/skill-repos"
```

**resolve 우선순위:** 1) `.git-sync-env` 파일 → 2) 명령어로 1회 resolve 후 파일 작성 → 3) 실패시 STOP + 형에게 확인.

**v5 자동 복구 (stale 감지):** sync-skill.sh 실행 시 `$PLUGIN_SKILLS_PATH/$SKILL_NAME` 부재 감지 → skills-plugin root(`$HOME/.../skills-plugin`) 하위 `*/*/skills` 재스캔 → SKILL_NAME 포함 & mtime 최신 경로로 `.git-sync-env` 자동 갱신(백업 `.bak.<epoch>` 생성 후 sed). Cowork 재설치·UUID 변경에도 자동 복구.

| 필드 | 확인 명령 (파일 없을 때만) |
|------|-------------------|
| `GITHUB_USER` | `gh api user --jq .login` |
| `PLUGIN_SKILLS_PATH` | `find "$HOME/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin" -maxdepth 3 -name "skills" -type d` |
| `REPO_ROOT` | `$HOME/github-repos/skill-repos/` (고정) |

**REMOTE 목록:** `.remote-cache` 파일 (TTL 600초, pre-flight-scan.sh가 관리).

**auto_mode:** 기본 false. "앞으로 자동으로 해" → 세션 내 true. **파괴적 액션은 무관 항상 컨펌.**

---

## 경로 테이블

| 대상 | 원본 | 레포 | GitHub |
|------|------|------|--------|
| 스킬 | `$PLUGIN_SKILLS_PATH/{name}/` | `$REPO_ROOT/{name}/` | `github.com/$GITHUB_USER/{name}` |
| UP | `$HOME/.../Agent-Ops/UP_*.md` | `$REPO_ROOT/user-preferences/` | `github.com/$GITHUB_USER/user-preferences` |

---

## 상태 매트릭스 — 파일 3-way (8셀)

파일 존재 축. **O**rigin · **L**ocal · **R**emote 3-way.

| # | O | L | R | 의미 | 액션 | 컨펌 |
|---|:-:|:-:|:-:|---|---|:-:|
| 1 | ✓ | ✓ | ✓ | 정상 | sync-skill.sh | auto |
| 2 | ✓ | ✓ | ✗ | 원격 유실 | disaster §A | **필수** |
| 3 | ✓ | ✗ | ✓ | 로컬 미클론 | clone → sync | auto |
| 4 | ✓ | ✗ | ✗ | 진짜 신규 | batch-guide §5 | **필수** |
| 5 | ✗ | ✓ | ✓ | 원본 삭제 | STOP → disaster §B/C | **필수** |
| 6 | ✗ | ✓ | ✗ | 고아 로컬 | disaster §D | **필수** |
| 7 | ✗ | ✗ | ✓ | 외부 레포 | 스킵 | — |
| 8 | ✗ | ✗ | ✗ | 없음 | 스킵 | — |
| ? | UNKNOWN | | | 스캔 실패 | STOP + 재스캔 | — |

세부 → `state-matrix.md`. **매트릭스 외 분기 = FAIL.**

---

## 상태 매트릭스 — Git 상태 (6셀)

브랜치·커밋 축. **HEAD**·**Rebase**·**Ahead**·**Behind** 4축 스냅샷.

| 셀 | HEAD | Rebase | Ahead | Behind | 액션 | 종료코드 |
|----|------|--------|:-:|:-:|---|:-:|
| G1 | on-branch | ✗ | 0 | 0 | **clean sync** — rsync→add→(staged)commit→push→POST_CHECK | 0 |
| G2 | on-branch | ✗ | N | 0 | **push-only** — 미푸시 커밋 함께 상승 (v5 silent failure 차단) | 0 |
| G3 | on-branch | ✗ | N | M | **DIVERGED — STOP** — 자동 rebase 금지, 사용자 컨펌 | 5 |
| G4 | on-branch | ✗ | 0 | M | **BEHIND — STOP** — fast-forward pull 필요 | 5 |
| G5 | * | ✓ | * | * | **REBASE 중단 — STOP** — `git rebase --abort` 안내 | 6 |
| G6 | detached | ✗ | * | * | **DETACHED — STOP** — 수동 복구 안내 | 7 |
| ? | UNKNOWN | | | | 스캔 실패 — 재시도 | 8 |

**POST_CHECK:** G1·G2 실행 후 `git rev-list --count origin/$BRANCH..HEAD == 0` 확인. 미일치시 exit 8.

세부 → `git-state-matrix.md`. **이중 게이트 원칙:** 파일 매트릭스(Cell 1·3) **AND** Git 매트릭스(G1·G2) 모두 통과만 실행.

---

## 배치 처리 순서

1. **Cell 1·3 비파괴:** push-only 6개 이하 병렬 / `gh api` 포함 3개 이하 / 7개+ 순차
2. **Cell 7:** 1회 안내 스킵
3. **Cell 2·4:** 건별 컨펌 → 순차
4. **Cell 5:** 건별 선택 (기본 보류)
5. **Cell 6:** 건별 선택 (기본 보류)
6. **UNKNOWN:** 리포트만

비파괴가 먼저 끝나야 파괴적 에러가 전체를 블록하지 않음.

---

## Scripts

| 스크립트 | 역할 | 최신 개선 |
|---|---|---|
| `pre-flight-scan.sh` | 파일 3-way 스캔 + 8셀 분류 | REMOTE TTL 캐시(10분) + `--no-cache` 플래그 |
| `sync-skill.sh` | Cell 1·3 동기화 | **v6 (2026-04-18): 3-Phase 상태머신** — Phase 1 `git_state_scan()` 5축 스냅샷 → Phase 2 `dispatch_matrix()` 6셀 분기 → Phase 3 `execute_cell()` G1·G2만 실행 + POST_CHECK. v5 silent failure / auto-rebase detached HEAD / rebase 중단 감지 누락 3대 결함 전차단. v5 stale 경로 자동 복구·turbo 기본·macOS perl 폴백 승계 |
| `secret-scan.sh` | 민감정보 검사 | v2: allowlist 지원 — `secret-scan-allowlist.txt` 정규식 FP 허용 |
| `secret-scan-allowlist.txt` | FP 허용 목록 | 라인 단위 정규식. 주석(#)·빈 줄 무시 |
| `rsync-exclude.txt` | exclude 패턴 | `logs/` `.remote-cache` 포함 |
| `excluded-names.txt` | Pre-Flight 제외 목록 | — |

---

## References

- `state-matrix.md` — 파일 3-way 8셀 결정 테이블 + 셀별 세부 액션
- `git-state-matrix.md` — **v6** Git 상태 6셀 매트릭스 (HEAD·Rebase·Ahead·Behind) + POST_CHECK
- `batch-guide.md` — Pre-Flight·단일·배치·UP·신규 레포 통합 프로토콜
- `readme-templates.md` — 이중언어 README 템플릿
- `disaster-recovery.md` — Cell 2·5·6 복구 + 사고 롤백

---

## Gotchas

| 함정 | 대응 |
|------|------|
| Cowork Bash로 git push | 샌드박스 실패. DC start_process만 |
| 단일 스킬에 Full Pipeline 강제 | Fast Path 존재. 캐시 10분 이내면 Pre-Flight 스킵 |
| sync-skill.sh rsync 여러번 | v2부터 itemize-changes 단일. 3회 동작 시 스크립트 업데이트 누락 |
| `gh repo list --limit 500` 매번 | `.remote-cache` TTL 600초. `--no-cache`로만 강제 |
| ENV resolve 반복 | `.git-sync-env` 영속화. 세션 유실에도 유지 |
| auto_mode=true에서 Cell 2·4·5·6 자동 | 금지. auto_mode는 Cell 1·3만 |
| REMOTE UNKNOWN을 '없음'으로 해석 | 금지. 재스캔 또는 UNKNOWN 유지 |
| 로그·캐시가 rsync에 섞임 | `logs/`·`.remote-cache` exclude 필수(v2 기본) |
| 에이전트가 rsync·git 직접 조립 | 금지. 스크립트 호출. 재조립 금지 |
| skills-plugin UUID 변경 | v5부터 **자동 감지·갱신**. SKILL_NAME 부재 시 skills-plugin root 재스캔 후 mtime 최신 경로로 ENV 자동 치환(백업 생성). 수동 수정 불요 |
| macOS에 `timeout` 없음 | sync-skill.sh에 perl 기반 폴백 내장. `brew install coreutils`(gtimeout) 불요 |
| DC 호출 2회+ 느림 | v4 기본 turbo 모드로 DC 1회 완결. 옵션 없이 `sync-skill.sh <name> <msg>` |
| 매번 dry-run 느림 | v4부터 기본이 dry-run 스킵. `--strict` 지정 시에만 dry-run + --delete. 삭제 감지 필요할 때만 |
| 파일 삭제했는데 레포에 남음 | 기본 turbo 모드는 --delete 없음. 삭제 포함 업데이트는 `--strict` 지정 필수 |
| force-with-lease 과잉 방어 | race-safe(원격 변경 감지 시 자동 거부). rename·rebase 후 diverge 시 컨펌 없이 실행. `--force`(bare)만 금지 |
| rename 후 diverge 컨펌 요청 | 원격 변경이 이미 로컬에 반영됐다면(SKILL.md 재작성 등) force-with-lease 즉시 실행. 질문 루프 금지 |
| secret-scan false positive (api_key 언급·메타 패턴 리스트 등) | `scripts/secret-scan-allowlist.txt` 에 해당 라인 정규식 추가. 코드 수정·bypass 금지. 허용 건수는 스캔 결과에 표시됨 |
| push 성공했다는데 원격에 반영 안 됨 | **v6 POST_CHECK 필수.** `origin/$BRANCH..HEAD == 0` 검증 후에만 성공 처리. 네트워크·branch protection·race로 push RC=0여도 반영 안 될 수 있음 |
| 로컬 미푸시 커밋 있는데 "변경 없음" 종료 | v5 silent failure. v6에서 **G2 셀**로 강제 push — rsync diff 유무와 무관하게 로컬이 원격보다 앞서면 push 실행 |
| push rejected 받고 auto rebase | 금지. **v6에서 G3 셀 = STOP + 사용자 컨펌.** v5의 `git pull --rebase` 자동 실행은 timeout 시 detached HEAD 잔존 위험 → 제거 |
| 이전 세션의 rebase 중단 상태로 rsync | working tree 오염. **v6에서 G5 셀 = Phase 1에서 선차단.** `.git/rebase-{merge,apply}/` 감지 시 exit 6 + abort 안내 |
| detached HEAD에서 commit | 고아 커밋 생성. **v6에서 G6 셀 = 자동 복구 금지, 수동 판단 강제.** `git symbolic-ref HEAD` 실패 시 exit 7 |
| fetch 없이 Ahead/Behind 측정 | origin/$BRANCH가 stale → G1~G4 오분류. **v6 Phase 1에서 `git fetch origin` 1회 필수** (timeout 15s) |

---

## Version

| 버전 | 날짜 | 변경 |
|------|------|------|
| v6 | 2026-04-18 | **Git 상태 매트릭스 6셀 신설** (G1~G6 + UNKNOWN). `sync-skill.sh` 3-Phase 상태머신 재구성(scan→dispatch→execute). POST_CHECK 추가. v5 silent failure / auto-rebase detached HEAD / rebase 중단 감지 누락 3대 결함 전차단. `references/git-state-matrix.md` 추가. 이중 매트릭스 순차 게이트 원칙(절대규칙 8) 추가. |
| v5 | — | PLUGIN_SKILLS_PATH stale 자동 감지·복구 |
| v4 | — | 기본 turbo 모드 (dry-run·--delete 스킵) |
| v2 | — | pre-flight TTL 캐시, secret-scan allowlist, itemize-changes 단일 |
