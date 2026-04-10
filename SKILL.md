---
name: git-sync
description: |
  스킬·설정 GitHub 동기화 엔진. 스킬 수정/생성 후 해당 레포에 자동 rsync→commit→push. UP 수정 후에도 동기화. 개별 레포 구조({GITHUB_USER}/{skill-name}) 기반.
  P1: 깃동기화, git sync, 깃싱크, 깃푸시, 레포동기화, 깃허브동기화, 스킬동기화, 스킬업로드.
  P2: 동기화해줘, 푸시해줘, 올려줘, sync, push, upload.
  P3: git sync, repo sync, github push, skill deployment.
  P4: skill-builder 패키징 완료 후, up-manager 수정 완료 후, 스킬 수정 완료 후.
  P5: git push 결과로, 동기화 리포트로.
  NOT: 레포생성(→직접수행), GitHub Pages 배포(→github-deploy), 스킬수정 자체(→skill-builder), git 일반작업(→직접수행).
---

# Git Sync — 스킬·설정 GitHub 동기화

원본 파일 → GitHub 개별 레포로 rsync → commit → push. 스킬과 UP 모두 지원.

---

## ⛔ 절대 규칙

| # | 규칙 | 이유 |
|---|------|------|
| 1 | **로컬 터미널로만 실행** — Cowork 샌드박스 Bash 금지 | 샌드박스는 로컬 git repo 접근 불가. DC `start_process` 사용 |
| 2 | **원본→레포 단방향만** — 역방향 금지 | 원본은 skills-plugin이 관리. 역동기화=충돌 |
| 3 | **README.md·README.ko.md·LICENSE·.gitignore 덮어쓰기 금지** | 레포 전용 메타파일 보호 |
| 4 | **민감정보 push 전 차단** — grep 검사 필수 | 개인정보·토큰 유출 방지 |

---

## 경로 매핑

### 환경 변수 (실행 시 resolve)

| 변수 | 설명 | 확인 방법 |
|------|------|----------|
| `{GITHUB_USER}` | GitHub 계정명 | `gh api user --jq .login` |
| `{USER_HOME}` | macOS 홈 디렉토리 | `echo $HOME` |
| `{USER_EMAIL}` | git/계정 이메일 | `git config user.email` |
| `{VAULT_PATH}` | Obsidian 볼트 루트 경로 | CLAUDE.md MOUNT 설정 참조 |
| `{PLUGIN_SKILLS_PATH}` | Cowork 스킬 플러그인의 skills/ 경로 | `find "{USER_HOME}/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin" -maxdepth 3 -name "skills" -type d` |

### 경로 테이블

| 항목 | 값 |
|------|-----|
| GitHub 계정 | `{GITHUB_USER}` |
| 스킬 원본 | `{PLUGIN_SKILLS_PATH}` |
| 레포 루트 | `{USER_HOME}/github-repos/skill-repos/` |
| 카탈로그 레포 | `{USER_HOME}/github-repos/cowork-skills/` |
| UP 원본 | `{VAULT_PATH}/Agent-Ops/` |
| UP 레포 | `{USER_HOME}/github-repos/skill-repos/user-preferences/` |

| 대상 | 원본 | 레포 | GitHub URL |
|------|------|------|-----------|
| 스킬 | `{스킬원본}/{name}/` | `{레포루트}/{name}/` | `github.com/{GITHUB_USER}/{name}` |
| UP | `{UP원본}/UP_user-preferences_v*.md` + `UP_stability.md` | `{UP레포}/` | `github.com/{GITHUB_USER}/user-preferences` |

---

## 발동 조건

| 조건 | 행동 |
|------|------|
| skill-builder 패키징 완료 직후 | 해당 스킬 동기화 제안 (컨펌 후 실행) |
| up-manager 수정 완료 직후 | UP 동기화 제안 |
| 형이 직접 요청 | "깃 동기화", "push해줘", "sync" 등 |
| "전체 동기화" | 변경된 모든 대상 일괄 동기화 |

**자동 실행 ✗** — 항상 컨펌 후 실행. "앞으로 자동으로 해" → 해당 세션 내 자동 전환.

---

## 파이프라인 개요

3가지 모드. 상세 코드와 절차는 각 references/ 파일 참조.

### 1. 단일 스킬 동기화 → `references/pipeline-skill.md`

```
①대상 확인 → ②rsync → ③민감정보 검사 → ④diff → ⑤commit → ⑥push → ⑦리포트
```

핵심: rsync `--delete` + exclude(README.md/README.ko.md/LICENSE/.gitignore). 민감정보 매치 시 STOP.

### 2. UP 동기화 → `references/pipeline-up.md`

```
①파일 탐색(glob) → ②cp + 구버전 정리 → ③민감정보 검사 → ④diff → ⑤commit → ⑥push → ⑦리포트
```

핵심: 디렉토리가 아닌 개별 파일 복사. 버전 번호 포함 파일명 → 구버전 자동 제거.

### 3. 전체 동기화 + 새 레포 생성 → `references/pipeline-batch.md`

```
①전체 diff 스캔(스킬+UP) → ②변경 리스트 출력 + 컨펌 → ③각각 파이프라인 실행
```

핵심: 3개 이하 병렬 OK, 4개 이상 순차(rate limit). 새 스킬은 gh repo create.

### 4. 기존 레포 README 일괄 생성 → `references/pipeline-batch.md`

```
①대상 스캔(EN/KO 유무) → ②리스트 출력 + 컨펌 → ③README 생성 → ④commit + push
```

핵심: README.md(EN) + README.ko.md(KO) 이중언어. 템플릿 → `references/readme-templates.md`.

---

## 주의사항 → `references/gotchas.md`

샌드박스 함정, rsync --delete 위험, UUID 변경, 동시 push 제한, 커밋 author 등.
