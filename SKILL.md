---
name: git-sync
description: |
  스킬·설정 GitHub 레포 생명주기 엔진. 3-way 상태 매트릭스(8셀) + Fast Path 결정적 분기. 단일은 캐시로 2단계 push, 배치는 Pre-Flight 후 비파괴→파괴적 순. 개별 레포({GITHUB_USER}/{skill-name}).
  P1: 깃동기화, 깃싱크, 깃푸시, 레포동기화, 깃허브동기화, 스킬동기화, 스킬업로드, 레포생성, 새레포, git sync.
  P2: 동기화해줘, 푸시해줘, 올려줘, sync, push, upload.
  P3: git sync, repo sync, github push, skill deployment, new repo.
  P4: skill-builder 패키징 완료 후, up-manager 수정 완료 후, 스킬 수정 완료 후.
  P5: git push 결과로, 동기화 리포트로.
  NOT: GitHub Pages 배포(→github-deploy), 스킬수정 자체(→skill-builder), git 일반작업(→직접수행).
vault_dependency: HARD
---

# Git Sync

스킬·UP → GitHub 레포 생명주기 관리. **3-way 상태 매트릭스(8셀)** 결정적 분기 + **Fast Path** 캐시 활용.

---

## ⛔ 절대 규칙 (7개)

| # | 규칙 | 이유 |
|---|------|------|
| 1 | **DC start_process로만 실행** — Cowork 샌드박스 Bash 금지 | 샌드박스는 로컬 git repo 접근 불가 |
| 2 | **원본→레포 단방향** — 역방향 금지 | 원본은 skills-plugin 관리 |
| 3 | **README/LICENSE/.gitignore 보호** — rsync exclude 필수 | 레포 전용 메타파일 |
| 4 | **파괴적 액션 게이트** — `gh repo create`·`rsync --delete`·로컬 `rm -rf`는 명시 컨펌. `gh repo delete`·`git push --force`는 절대 금지(복구 §F 예외) | 중복·유실 방지 |
| 5 | **새 레포 = README 2종 필수** — 초기 커밋에 README.md + README.ko.md | 매번 수동 생성 방지 |
| 6 | **Pre-Flight Scan 필수** — 배치 진입 전 3-way 상태 수집 완료 전 어떤 액션도 금지. 단일 스킬은 Fast Path 허용 | 2026-04-16 사고(3축 독립 수집 미비) 재발 방지 |
| 7 | **매트릭스 외 분기 금지** — `state-matrix.md` 8셀 + UNKNOWN만 신뢰. 기억 재구성·추측 분기=FAIL | 상태 공간 완전 열거 |

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

**조건:** 1개 스킬 명시 + `.remote-cache` 또는 `logs/preflight-*.log` 10분 이내 존재.

```
① ENV 확인 (1회) → ② sync-skill.sh 호출 → ③ 리포트
```

**DC 호출: 최대 2회.** 캐시 미스 또는 10분 초과시 Full Pipeline으로 자동 폴백.

```bash
# ① ENV + 캐시 확인
source "{repo_root}/git-sync/.git-sync-env" 2>/dev/null || \
  { echo "ENV 캐시 없음 — Full Pipeline 폴백"; exit 10; }

# ② 단일 sync (rsync 단일 실행 + push timeout 내장)
bash "{repo_root}/git-sync/scripts/sync-skill.sh" \
  "{skill-name}" "$PLUGIN_SKILLS_PATH" "$REPO_ROOT" "$GITHUB_USER" \
  "Update {skill-name}: {변경요약}"
```

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

## 상태 매트릭스 — 8셀 요약

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

## 배치 처리 순서

1. **Cell 1·3 비파괴:** push-only 6개 이하 병렬 / `gh api` 포함 3개 이하 / 7개+ 순차
2. **Cell 7:** 1회 안내 스킵
3. **Cell 2·4:** 건별 컨펌 → 순차
4. **Cell 5:** 건별 선택 (기본 보류)
5. **Cell 6:** 건별 선택 (기본 보류)
6. **UNKNOWN:** 리포트만

비파괴가 먼저 끝나야 파괴적 에러가 전체를 블록하지 않음.

---

## Scripts (v2 최적화)

| 스크립트 | 역할 | v2 개선 |
|---|---|---|
| `pre-flight-scan.sh` | 3-way 스캔 + 8셀 분류 | REMOTE TTL 캐시(10분) + `--no-cache` 플래그 |
| `sync-skill.sh` | Cell 1·3 동기화 | **rsync 3회→1회** (itemize-changes) + push timeout 30s |
| `secret-scan.sh` | 민감정보 검사 | — |
| `rsync-exclude.txt` | exclude 패턴 | `logs/` `.remote-cache` 추가 |
| `excluded-names.txt` | Pre-Flight 제외 목록 | — |

---

## References

- `state-matrix.md` — 8셀 결정 테이블 + 셀별 세부 액션
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
| push 멈춤·뺑뺑이 | timeout 30s 내장. rebase 블록 시 exit 1 |
| ENV resolve 반복 | `.git-sync-env` 영속화. 세션 유실에도 유지 |
| auto_mode=true에서 Cell 2·4·5·6 자동 | 금지. auto_mode는 Cell 1·3만 |
| REMOTE UNKNOWN을 '없음'으로 해석 | 금지. 재스캔 또는 UNKNOWN 유지 |
| 로그·캐시가 rsync에 섞임 | `logs/`·`.remote-cache` exclude 필수(v2 기본) |
| 에이전트가 rsync·git 직접 조립 | 금지. 스크립트 호출. 재조립 금지 |
| skills-plugin UUID 변경 | `.git-sync-env`의 PLUGIN_SKILLS_PATH 갱신 → `disaster-recovery.md §G` |
