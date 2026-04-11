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

# Git Sync

원본 → GitHub 레포로 rsync → commit → push. 선형 흐름, DC 호출 최소화.

---

## ⛔ 절대 규칙 (4개)

| # | 규칙 | 이유 |
|---|------|------|
| 1 | **DC start_process로만 실행** — Cowork 샌드박스 Bash 금지 | 샌드박스는 로컬 git repo 접근 불가 |
| 2 | **원본→레포 단방향** — 역방향 금지 | 원본은 skills-plugin 관리. 역동기화=충돌 |
| 3 | **README/LICENSE/.gitignore 보호** — rsync exclude 필수 | 레포 전용 메타파일 |
| 4 | **에러 하드캡** — push/rsync 실패 시 1회 재시도. 2회 실패 → STOP + 에러 보고. 자동 복구 루프 금지 | 무한 재시도 방지 |

---

## ENV_CACHE

첫 발동에서 resolve → **에이전트 대화 컨텍스트에 보관**. 세션 종료 시 소멸. 2회차 호출 시 캐시 존재 확인 → 없으면 재resolve.

| 필드 | 확인 방법 |
|------|----------|
| `github_user` | `gh api user --jq .login` |
| `user_home` | `echo $HOME` |
| `plugin_skills_path` | `find "$HOME/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin" -maxdepth 3 -name "skills" -type d` |
| `repo_root` | `$HOME/github-repos/skill-repos/` |
| `auto_mode` | 기본 false. "앞으로 자동으로 해" → true (세션 내) |

**resolve 실패 시:** 해당 필드 보고 + STOP. 추측으로 진행 금지.

```
❌ ENV resolve 실패
  실패 필드: {필드명}
  실행 명령: {시도한 명령}
  에러: {에러 메시지}
  → {필드별 복구 안내}
```

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

## 공통 rsync exclude

모든 rsync 호출이 이 변수를 참조한다. **단일 수정점(Single Point of Truth).**

```bash
EXCLUDES="--exclude='.git/' --exclude='.gitignore' \
  --exclude='README.md' --exclude='README.ko.md' \
  --exclude='LICENSE' --exclude='.DS_Store' \
  --exclude='__pycache__/' --exclude='*.pyc'"
```

---

## 단일 스킬 동기화

**DC 호출 수:** ENV 캐시 유무 × 모드에 따라 결정.

| 조건 | DC 호출 | 설명 |
|------|---------|------|
| ENV 캐시 없음 (첫 호출) | 2회 | 호출 1: ENV + PRE_SYNC_CHECK → 호출 2: rsync + commit + push |
| ENV 캐시 있음 + auto_mode=false | 2회 | 호출 1: PRE_SYNC_CHECK → 호출 2: rsync + commit + push |
| ENV 캐시 있음 + auto_mode=true | **1회** | 통합: PRE_SYNC_CHECK + rsync + commit + push (삭제 감지 시 자동 중단) |

### 호출 1: ENV + PRE_SYNC_CHECK

```bash
# ENV resolve (캐시 있으면 이 부분 스킵)
GITHUB_USER=$(gh api user --jq .login) && \
REPO="{repo_root}/{skill-name}" && \
SRC="{plugin_skills_path}/{skill-name}" && \

# 원본·레포 존재 확인
[ -d "$SRC" ] || { echo "ERROR: 원본 없음"; exit 1; } && \
[ -d "$REPO/.git" ] || { echo "ERROR: 레포 없음 — gh repo create 필요"; exit 1; } && \

# PRE_SYNC_CHECK: 삭제 예정 파일 확인
eval rsync -avn --delete $EXCLUDES "$SRC/" "$REPO/" | grep '^deleting '
```

**판정:**
- 삭제 0건 → 호출 2 진행
- references/scripts/agents 내 삭제 → **STOP + 형 확인**
- 기타 삭제 → 삭제 목록 표시 + 형 확인 후 진행

### 호출 2: rsync + 민감정보 검사 + commit + push

```bash
cd "{repo_root}/{skill-name}" && \

# rsync
eval rsync -av --delete $EXCLUDES "{plugin_skills_path}/{skill-name}/" ./ && \

# 민감정보 검사 → scripts/secret-scan.sh (패턴·제외·호환성 로직 일원화)
bash scripts/secret-scan.sh . || exit 1 && \

# commit + push (push 실패 시 1회 재시도)
git add -A && \
git diff --cached --quiet && echo "변경 없음 — 이미 최신" || \
(git commit -m "Update {skill-name}: {변경요약}" && \
 git push || (git pull --rebase && git push) || { echo "❌ push 2회 실패 — STOP"; exit 1; })
```

### 통합 1회 호출 (ENV 캐시 + auto_mode=true)

```bash
cd "{repo_root}/{skill-name}" && \

# PRE_SYNC_CHECK 인라인 — 삭제 감지 시 자동 중단
DELETES=$(eval rsync -avn --delete $EXCLUDES \
  "{plugin_skills_path}/{skill-name}/" ./ | grep '^deleting ' || true) && \

if [ -n "$DELETES" ]; then
  echo "⚠️ 삭제 감지 — auto_mode에서도 중단:"; echo "$DELETES"; exit 1
fi && \

# rsync 실행
eval rsync -av --delete $EXCLUDES "{plugin_skills_path}/{skill-name}/" ./ && \

# 민감정보 검사 → scripts/secret-scan.sh
bash scripts/secret-scan.sh . || exit 1 && \

# commit + push (push 실패 시 1회 재시도)
git add -A && \
git diff --cached --quiet && echo "변경 없음 — 이미 최신" || \
(git commit -m "Update {skill-name}: {변경요약}" && \
 git push || (git pull --rebase && git push) || { echo "❌ push 2회 실패 — STOP"; exit 1; })
```

**에러 처리:** push 재시도 로직이 코드블록에 내장. 2회 실패 → STOP.

**배치:** push-only 6개 이하 병렬. `gh api` 호출 포함 시 3개 이하. 7개+ 순차.

### 리포트

```
✅ {skill-name} 동기화 완료
  변경: {N}파일 수정, {M}추가, {K}삭제
  커밋: {hash 7자리}
  URL: https://github.com/{github_user}/{skill-name}
```

---

## UP 동기화 — DC 2회 호출

**정확히 2회의 DC start_process만 사용한다.** 민감정보 검사·commit·push는 호출 2의 단일 bash 스크립트 안에서 `&&`로 체이닝한다. 3회 이상으로 분할하지 마라.

### 호출 1: 파일 탐색 + 복사

```bash
# 최신 UP 파일 찾기
UP_FILE=$(ls -1 "$HOME/Library/CloudStorage/Dropbox/ObsidianVault/Agent-Ops"/UP_user-preferences_v*.md | sort -V | tail -1) && \
STAB="$HOME/Library/CloudStorage/Dropbox/ObsidianVault/Agent-Ops/UP_stability.md" && \
REPO="{repo_root}/user-preferences" && \

# 복사
cp "$UP_FILE" "$REPO/" && \
[ -f "$STAB" ] && cp "$STAB" "$REPO/" ; \

# 구버전 정리: 현재 버전 외 삭제
CURRENT=$(basename "$UP_FILE") && \
cd "$REPO" && \
ls UP_user-preferences_v*.md 2>/dev/null | grep -v "$CURRENT" | xargs rm -f
```

### 호출 2: 민감정보 + commit + push

```bash
cd "{repo_root}/user-preferences" && \

# 민감정보 검사 → git-sync 레포의 secret-scan.sh 사용 (UP 레포에는 scripts/ 없음)
bash "{repo_root}/git-sync/scripts/secret-scan.sh" . || exit 1 && \

# commit + push (push 실패 시 1회 재시도)
git add -A && \
git diff --cached --quiet && echo "변경 없음" || \
(git commit -m "Update UP: {버전정보}" && \
 git push || (git pull --rebase && git push) || { echo "❌ push 2회 실패 — STOP"; exit 1; })
```

**참고:** UP 레포에는 SKILL.md가 없으므로 secret-scan.sh의 SKILL.md 제외 로직이 자연스럽게 무해(no-op)하다. 별도 플래그 불필요 — 동일 스크립트, 동일 패턴.

**리포트:** UP 동기화도 동일한 표준 리포트 형식을 출력한다:
```
✅ user-preferences 동기화 완료
  변경: {N}파일 수정, {M}추가, {K}삭제
  커밋: {hash 7자리}
  URL: https://github.com/{github_user}/user-preferences
```

---

## 전체 동기화 / 새 레포 / README → `references/pipeline-batch.md`

배치 동기화, 새 레포 생성(gh repo create), README 일괄 생성은 references 참조.

## README 템플릿 → `references/readme-templates.md`

이중언어 README 생성 시 참조.

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
| 민감정보 검사 | **스킬:** `bash scripts/secret-scan.sh .` (레포 내 스크립트). **UP:** `bash "{repo_root}/git-sync/scripts/secret-scan.sh" .` (git-sync 레포 참조). 인라인 grep 금지 — SKILL.md 자기참조 false positive + BSD/GNU grep 호환성 + exit code 꼬임 |
| rsync exclude 중복 | `$EXCLUDES` 공통 변수 참조. 개별 블록에 직접 나열 금지 — 수정 시 불일치 발생 |
