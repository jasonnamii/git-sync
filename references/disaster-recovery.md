# 재해 복구 플레이북

비정상 상태(Cell 2·5·6·UNKNOWN) 복구 절차 + 의도치 않은 파괴적 액션 감지·롤백.

---

## 플레이북 인덱스

| 시나리오 | 트리거 | 플레이북 |
|---|---|---|
| 원격 레포 실수 삭제 | Cell 2 (✓✓✗) + origin 일치 | §A |
| 원본 실수 삭제 | Cell 5 (✗✓✓) + 복원 의도 | §B |
| 스킬 완전 폐기 | Cell 5 + 삭제 의도 | §C |
| 고아 로컬 정리 | Cell 6 (✗✓✗) | §D |
| 의도치 않은 신규 레포 생성 감지 | 직후 리포트에 의심 레포 N개 등장 | §E |
| push 사고 (force push·brach loss) | 로컬과 원격 diverge | §F |
| Cowork 재설치로 UUID 변경 | plugin_skills_path resolve 실패 | §G |

---

## §A. 원격 레포 복구 (Cell 2 → 재등록)

**전제:** `git remote -v`가 `github.com/{github_user}/{name}`을 가리킴, 원격만 없어짐.

```bash
cd "{repo_root}/{name}"
# 1. 원격 재생성 (public + README 없어도 무관 — 로컬에 이미 있음)
gh repo create "{github_user}/{name}" --public \
  --description "{SKILL.md description 첫 문장 영문}"

# 2. push (로컬 history 그대로)
git push -u origin main
```

**확인:**
- README.md / README.ko.md 존재 여부 → 없으면 `readme-templates.md`로 생성 + 별도 커밋
- 재생성된 레포 URL을 형에게 리포트

---

## §B. 원본 실수 삭제 → 로컬에서 복원 (Cell 5 → 복원)

**전제:** 로컬 `{repo_root}/{name}/`에는 완전한 파일이 있고, 원본만 사라짐.

```bash
# 1. 로컬 → 원본 복원 (rsync reverse)
EXCL="{repo_root}/git-sync/scripts/rsync-exclude.txt"
rsync -av --exclude-from="$EXCL" \
  "{repo_root}/{name}/" "{plugin_skills_path}/{name}/"

# 2. 원본 복원 검증
[ -f "{plugin_skills_path}/{name}/SKILL.md" ] && echo "✅ 원본 복원 완료"

# 3. 이후 동기화는 Cell 1로 정상 처리 (재스캔)
```

**주의:** `--exclude-from`으로 README·.gitignore·LICENSE 제외. 원본에 레포 전용 메타파일 역유입 방지.

---

## §C. 스킬 완전 폐기 (Cell 5 → 삭제)

**전제:** 원본 이미 삭제됨. 로컬·원격·아카이브 전부 정리.

```bash
# 1. 로컬 → _archive/ 이동 (즉시 삭제 대신 보존)
mkdir -p "{repo_root}/_archive/{name}-$(date +%Y%m%d)"
mv "{repo_root}/{name}" "{repo_root}/_archive/{name}-$(date +%Y%m%d)/"

# 2. 원격 아카이브 (삭제 대신 archive 처리)
gh repo archive "{github_user}/{name}" --yes

# 3. README에 deprecation 노트 (선택)
```

**`gh repo delete` 금지.** archive로 복구 여지 남김. 영구 삭제는 형이 GitHub UI에서 직접.

---

## §D. 고아 로컬 정리 (Cell 6)

```bash
# 옵션 a) _archive/ 이동 (권장)
mkdir -p "{repo_root}/_archive/orphan-$(date +%Y%m%d)"
mv "{repo_root}/{name}" "{repo_root}/_archive/orphan-$(date +%Y%m%d)/"

# 옵션 b) 즉시 삭제 (명시 2회 컨펌 필요)
rm -rf "{repo_root}/{name}"
```

로컬 .git 히스토리에 중요 정보가 있을 수 있으므로 a 권장.

---

## §E. 의도치 않은 신규 레포 생성 감지·롤백

**증상:** 동기화 후 리포트에 예상 못 한 `gh repo create` 결과가 N개 등장.

**감지 방법:**
1. 세션 시작 시 REMOTE_REPOS 스냅샷 확보 (`pre-flight-scan.sh` 출력)
2. 세션 종료 시 현재 REMOTE_REPOS와 diff
3. 의도한 Cell 4 컨펌 건 외 증가분 = 의심 레포

**롤백:**

```bash
# 각 의심 레포에 대해
REPO_NAME="suspicious-repo"
gh repo view "{github_user}/$REPO_NAME" --json createdAt,description
# 생성 시각·설명 확인 → 실수 맞으면:
gh repo archive "{github_user}/$REPO_NAME" --yes
# 영구 삭제는 GitHub UI에서 수동
```

**예방:** 절대규칙 #7 준수. Cell 4는 auto_mode=true여도 건별 명시 컨펌.

---

## §F. push 사고

### F-1. force push로 원격 커밋 유실

```bash
cd "{repo_root}/{name}"
# reflog로 유실 커밋 SHA 찾기
git reflog --all | head -20
# 복구
git reset --hard {lost-sha}
git push --force  # 주의: 이중 force는 상황 악화 가능
```

**원칙:** `--force` 대신 `--force-with-lease` 사용 권장. force push는 절대규칙 범위 밖(금지) — 복구용 외 사용 금지.

### F-2. 로컬·원격 divergence

sync-skill.sh 내부 `pull --rebase` 1회 재시도 실패 시 exit 1 → STOP.

수동 복구:
```bash
cd "{repo_root}/{name}"
git fetch origin
git log --oneline HEAD..origin/main  # 원격 전용 커밋
git log --oneline origin/main..HEAD  # 로컬 전용 커밋
# 3-way merge 또는 rebase로 수렴 후 push
```

---

## §G. plugin_skills_path resolve 실패

**증상:** ENV_CACHE의 `plugin_skills_path` resolve 실패 — Cowork 재설치로 UUID 변경 가능성.

```bash
# 새 경로 탐색
find "$HOME/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin" \
  -maxdepth 3 -name "skills" -type d

# 다중 결과 시: 최신 mtime 선택
find "$HOME/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin" \
  -maxdepth 3 -name "skills" -type d -exec stat -f "%m %N" {} \; | sort -rn | head -1
```

확인 후 `.git-sync-env` 파일 업데이트(있으면) + 세션 캐시 갱신.

---

## §H. 로그 기반 사후 분석

`{repo_root}/git-sync/logs/` 조회:

```bash
ls -lt "{repo_root}/git-sync/logs/" | head -20
# preflight-YYYYMMDD-HHMMSS.log — 스캔 시점 상태
# sync-YYYYMMDD-HHMMSS.log — 동기화 결정·실행 결과
```

사고 재현 가능. 로그 역추적으로 원인 특정 → 재발 방지 규칙 추가.

---

## 공통 원칙

1. **archive > delete** — 실수 여지를 항상 남긴다
2. **수동 > 자동** — 복구 과정은 사용자 확인 후 한 단계씩
3. **로그 먼저** — 복구 전 로그·snapshot 확보
4. **절대규칙 재확인** — 복구 중에도 #6·#7 적용 (스캔 후 컨펌)
