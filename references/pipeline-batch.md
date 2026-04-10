# 전체 동기화 + 새 레포 생성

---

## 전체 동기화 (일괄)

"전체 동기화", "다 푸시해" 요청 시.

```
①전체 diff 스캔(스킬+UP) → ②변경 리스트 출력 + 컨펌 → ③각각 파이프라인 실행
```

### ① 스킬 diff 스캔

```bash
for skill in $(ls "{스킬원본}" | grep -v ".DS_Store"); do
  diff -rq \
    --exclude='.git' --exclude='.gitignore' \
    --exclude='README.md' --exclude='LICENSE' \
    --exclude='.DS_Store' --exclude='__pycache__' \
    "{스킬원본}/$skill/" "{레포루트}/$skill/" 2>/dev/null
done
```

### ① -2 UP diff 스캔

```bash
diff -q "{UP원본}/UP_user-preferences_v{N}.md" \
       "{UP레포}/UP_user-preferences_v{N}.md" 2>/dev/null
diff -q "{UP원본}/UP_stability.md" \
       "{UP레포}/UP_stability.md" 2>/dev/null
```

### ② 변경 리스트 출력

```
변경 감지:
  trigger-dictionary — SKILL.md 수정
  hit-skill — references/layer2-formulas.md 수정, rx-new.md 추가
  user-preferences — UP_user-preferences_v29.5.md 수정
  (나머지 23개 — 변경 없음)

3개 대상을 동기화합니다. 진행할까요?
```

### ③ 실행

- 스킬 → `pipeline-skill.md` 절차
- UP → `pipeline-up.md` 절차
- 3개 이하: 병렬 OK (DC start_process 동시 호출)
- 4개 이상: 순차 실행 (GitHub rate limit 방지)

---

## 새 스킬 레포 생성

원본에 존재하나 레포가 없는 스킬 감지 시.

```bash
# 1. 로컬 레포 구조 생성
mkdir -p "{레포루트}/{new-skill}"
rsync -av --exclude='.DS_Store' --exclude='__pycache__/' \
  "{스킬원본}/{new-skill}/" "{레포루트}/{new-skill}/"

# 2. 메타 파일 복사
cp "{레포루트}/trigger-dictionary/.gitignore" "{레포루트}/{new-skill}/"
cp "{레포루트}/trigger-dictionary/LICENSE" "{레포루트}/{new-skill}/"

# 3. README.md 생성
# SKILL.md description에서 영문 사용법 자동 작성

# 4. git init + GitHub 레포 생성 + push
cd "{레포루트}/{new-skill}"
git init
git add -A
git commit -m "Initial commit: {new-skill}"
gh repo create "{GITHUB_USER}/{new-skill}" \
  --public --source=. --push \
  --description "{영문 설명}"
```