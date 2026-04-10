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
    --exclude='README.md' --exclude='README.ko.md' --exclude='LICENSE' \
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

- 스킬 → 허브 SKILL.md의 「단일 스킬 동기화」 절차
- UP → 허브 SKILL.md의 「UP 동기화」 절차
- 3개 이하: 병렬 OK (로컬 터미널 동시 호출)
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

# 3. 이중언어 README 생성 → references/readme-templates.md 참조
# README.md (English) + README.ko.md (한국어) 동시 생성
# SKILL.md의 name, description, 본문에서 정보 추출 → 템플릿 적용

# 4. git init + GitHub 레포 생성 + push
cd "{레포루트}/{new-skill}"
git init
git add -A
git commit -m "Initial commit: {new-skill}"
gh repo create "{GITHUB_USER}/{new-skill}" \
  --public --source=. --push \
  --description "{영문 설명}"
```

---

## 기존 레포 README 일괄 생성

"README 생성", "이중언어 README", "README 세팅" 요청 시. README가 없거나 영문만 있는 레포에 이중언어 README 세팅.

```
①대상 스캔 → ②리스트 출력 + 컨펌 → ③각 레포에 README 생성 → ④commit + push → ⑤리포트
```

### ① 대상 스캔

```bash
for skill in $(ls "{레포루트}" | grep -v ".DS_Store"); do
  has_en=$([ -f "{레포루트}/$skill/README.md" ] && echo "Y" || echo "N")
  has_ko=$([ -f "{레포루트}/$skill/README.ko.md" ] && echo "Y" || echo "N")
  echo "$skill  EN=$has_en  KO=$has_ko"
done
```

### ② 리스트 출력

```
README 현황:
  trigger-dictionary  EN=Y  KO=N  → README.ko.md 생성 필요
  hit-skill           EN=N  KO=N  → README.md + README.ko.md 생성 필요
  biz-skill           EN=Y  KO=Y  → 스킵
  (총 {N}개 대상)

{N}개 레포에 README를 생성합니다. 진행할까요?
```

### ③ README 생성

각 대상 레포에 대해:

1. 해당 스킬의 SKILL.md를 읽어 name, description, 핵심 기능 추출
2. `references/readme-templates.md` 템플릿 적용
3. README.md (영문) / README.ko.md (한글) 생성 — 필요한 쪽만

### ④ commit + push

```bash
cd "{레포루트}/{skill-name}"
git add README.md README.ko.md
git commit -m "Add bilingual README (EN/KO)"
git push
```

3개 이하 병렬 OK, 4개 이상 순차.