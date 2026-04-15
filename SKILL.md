---
name: git-sync
description: |
  스킬·설정 GitHub 레포 생명주기 엔진. 새 레포 생성(README 자동 포함)부터 rsync→commit→push 동기화까지 원스톱. UP 수정 후에도 동기화. 개별 레포 구조({GITHUB_USER}/{skill-name}) 기반.
  P1: 깃동기화, git sync, 깃싱크, 깃푸시, 레포동기화, 깃허브동기화, 스킬동기화, 스킬업로드, 레포생성, 새레포.
  P2: 동기화해줘, 푸시해줘, 올려줘, sync, push, upload.
  P3: git sync, repo sync, github push, skill deployment, new repo.
  P4: skill-builder 패키징 완료 후, up-manager 수정 완료 후, 스킬 수정 완료 후.
  P5: git push 결과로, 동기화 리포트로.
  NOT: GitHub Pages 배포(→github-deploy), 스킬수정 자체(→skill-builder), git 일반작업(→직접수행).
---

# Git Sync

스킬·UP → GitHub 레포 생명주기 관리. 새 레포 생성 + 동기화를 단일 진입점에서 처리.

---

## ⛔ 절대 규칙 (5개)

| # | 규칙 | 이유 |
|---|------|------|
| 1 | **DC start_process로만 실행** — Cowork 샌드박스 Bash 금지 | 샌드박스는 로컬 git repo 접근 불가 |
| 2 | **원본→레포 단방향** — 역방향 금지 | 원본은 skills-plugin 관리. 역동기화=충돌 |
| 3 | **README/LICENSE/.gitignore 보호** — rsync exclude 필수 | 레포 전용 메타파일 |
| 4 | **에러 하드캡** — push/rsync 실패 시 1회 재시도. 2회 실패 → STOP + 에러 보고. 자동 복구 루프 금지 | 무한 재시도 방지 |
| 5 | **새 레포 = README 필수** — 초기 커밋에 README.md + README.ko.md 포함. README 없는 초기 커밋 금지 | 매번 수동 요청 구조 방지 |

---

## ENV_CACHE

첫 발동에서 resolve → **에이전트 대화 컨텍스트에 보관**. 세션 종료 시 소멸. 2회차 호출 시 캐시 존재 확인 → 없으면 재resolve.

**ENV resolve 폴백 자동화:** 1차 resolve 실패 시 마지막 성공값(세션 내 캐시 또는 .git-sync-env 파일)으로 자동 폴백. 폴백값도 없으면 형에게 확인 요청. '추측 진행 금지' 원칙은 유지하되, 검증된 폴백값 사용은 추측이 아님.

| 필드 | 확인 방법 |
|------|----------|
| `github_user` | `gh api user --jq .login` |
| `user_home` | `echo $HOME` |
| `plugin_skills_path` | `find "$HOME/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin" -maxdepth 3 -name "skills" -type d` |
| `repo_root` | `$HOME/github-repos/skill-repos/` |
| `auto_mode` | 기본 false. "앞으로 자동으로 해" → true (세션 내) |

**git-sync 레포 자동 보장 (ENV resolve 직후, 필수):**
```bash
[ -d "{repo_root}/git-sync/.git" ] || gh repo clone {github_user}/git-sync "{repo_root}/git-sync"
```
이유: `sync-skill.sh`와 `secret-scan.sh`가 이 레포에 있다. 로컬에 없으면 스크립트 실행 자체가 불가. sync-skill.sh 내부에도 자동 clone이 있지만, ENV resolve 시점에 선행 보장하는 것이 확실.

**resolve 실패 시:** 해당 필드 보고 + STOP. 추측으로 진행 금지.

`plugin_skills_path` find 실패 시: Cowork 재설치로 UUID 변경 가능성 안내. `github_user` 실패 시: `gh auth status`로 인증 상태 확인 안내.

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
| skill-builder 패키징 완료 | 동기화 제안 (auto_mode=true면 바로 실행) |
| up-manager 수정 완료 | UP 동기화 제안 |
| 형이 직접 요청 | 즉시 실행 |
| "전체 동기화" | → `references/pipeline-batch.md` |

---

## 핵심 실행 — scripts/sync-skill.sh

**모든 스킬 동기화는 이 스크립트 1회 호출로 완결한다.** 에이전트가 rsync/exclude/secret-scan/commit/push를 직접 조립하지 않는다.

```bash
# DC start_process로 실행 (Cowork 샌드박스 Bash 금지)
bash "{repo_root}/git-sync/scripts/sync-skill.sh" \
  "{skill-name}" "{plugin_skills_path}" "{repo_root}" "{github_user}" "{커밋 메시지}"
```

**스크립트 내장 로직:**
- exclude 3단 폴백 (레포 내 → git-sync 레포 → 인라인 하드코딩)
- git-sync 레포 로컬 부재 시 자동 clone
- 삭제 감지 시 자동 중단 (exit 3)
- 변경 없음 감지 + .skill 미설치 경고 (exit 4)
- secret-scan 2단 폴백
- push 실패 1회 rebase 재시도

**종료코드:** 0=성공, 1=에러, 2=인자 오류, 3=삭제 감지(확인 필요), 4=변경 없음

**에이전트 행동:**
- exit 0 → 리포트 출력
- exit 3 → 삭제 목록 형에게 표시 + 확인 후 수동 진행
- exit 4 → ".skill 설치 먼저 해주세요" 안내
- exit 1/2 → 에러 보고 + STOP

**exclude 패턴 수정:** `scripts/rsync-exclude.txt`가 유일 원본. 패턴 추가·삭제는 이 파일 1곳만.

⚠ `plugin_skills_path`에 공백(`Application Support`)이 포함되어 있다. `eval` + 문자열 변수 조합 **금지**. sync-skill.sh 내부에서 인자를 따옴표로 보호하므로 안전.

---

## 진입점 — 대상별 분기

| 대상 | 레포 존재? | 경로 |
|------|-----------|------|
| 스킬 | ✅ 있음 | → `references/skill-sync.md` (기존 레포 동기화) |
| 스킬 | ❌ 없음 (`NEW_REPO_NEEDED`) | → `references/new-repo-init.md` (새 레포 생성 + README + push) |
| UP | — | → `references/up-sync.md` (UP 동기화) |
| 전체/배치 | — | → `references/pipeline-batch.md` (일괄 동기화 + 새 레포 + README 일괄) |
| README만 | — | → `references/readme-templates.md` (이중언어 README 템플릿) |

**레포 존재 판별:** 호출 1에서 `[ -d "$REPO/.git" ]` 체크. 없으면 `NEW_REPO_NEEDED` 시그널 출력 → new-repo-init.md 플로우 자동 분기.

---

## Gotchas

| 함정 | 대응 |
|------|------|
| Cowork Bash로 git push | 샌드박스라 실패. DC start_process만 사용 |
| rsync --delete에서 exclude 누락 | README/LICENSE/.gitignore 8개 항목 항상 포함 |
| skills-plugin UUID 변경 | Cowork 재설치 시 변경 가능. find로 동적 탐색 |
| 동시 push 6개+ | push-only 6개 이하 병렬, API 호출 포함 3개 이하, 7개+ 순차 |
| UP 버전 파일명 변경 | glob `v*.md`로 탐색, 구버전 자동 정리 |
| push 실패 뺑뺑이 | 1회 재시도 후 STOP. 자동 복구 루프 금지 |
| ENV resolve 실패 | 추측 진행 금지. 실패 필드 보고 + STOP |
| 새 레포 README 누락 | 절대규칙 #5 위반. `NEW_REPO_NEEDED` → new-repo-init.md → README 필수 생성 |
| **에이전트가 rsync를 직접 조립** | **금지.** 반드시 `sync-skill.sh`를 호출. 에이전트가 인라인 --exclude로 우회하면 exclude 패턴 누락·불일치 발생. 스크립트가 3단 폴백·secret-scan·push 재시도를 모두 내장 |
| **git-sync 레포 로컬 미존재** | ENV resolve 직후 자동 clone. sync-skill.sh 내부에도 이중 보장. 이 체크 없이 동기화 진행 금지 |
| exclude 패턴 수정 | `scripts/rsync-exclude.txt`가 유일 원본. 패턴 추가·삭제는 이 파일 1곳만 |
