# 새 레포 초기화 (NEW_REPO 플로우)

`skill-sync.md` 호출 1에서 `NEW_REPO_NEEDED` 출력 시 자동 분기.
**README 생성이 초기 커밋의 필수 단계 — README 없는 초기 커밋 = 금지.**

---

## 플로우

```
①메타파일 복사 + rsync → ②이중언어 README 생성 → ③민감정보 검사 → ④git init + commit + gh repo create + push
```

---

## ① 메타파일 + rsync

```bash
mkdir -p "{repo_root}/{skill-name}" && \
cp "{repo_root}/trigger-dictionary/.gitignore" "{repo_root}/{skill-name}/" && \
cp "{repo_root}/trigger-dictionary/LICENSE" "{repo_root}/{skill-name}/" && \
EXCL="{repo_root}/git-sync/scripts/rsync-exclude.txt"
rsync -av --exclude-from="$EXCL" "{plugin_skills_path}/{skill-name}/" "{repo_root}/{skill-name}/"
```

---

## ② 이중언어 README 생성 (필수)

`references/readme-templates.md` 템플릿 참조. 절차:

1. 해당 스킬의 SKILL.md를 읽어 name, description, 핵심 기능, 연동 스킬 추출
2. 템플릿의 추출 규칙에 따라 각 플레이스홀더 채움
3. DC write_file로 README.md (영문) + README.ko.md (한글) 동시 생성
4. 영문은 번역체 금지 — 자연스러운 영어로 새로 작성
5. 한글은 SKILL.md 톤 유지 — 간결·단정

**이 단계를 건너뛰면 git-sync 절대규칙 위반.**

---

## ③ 민감정보 검사 + init + push

```bash
cd "{repo_root}/{skill-name}" && \
SCAN="scripts/secret-scan.sh"; [ -f "$SCAN" ] || SCAN="{repo_root}/git-sync/scripts/secret-scan.sh"
bash "$SCAN" . || exit 1 && \
git init && git checkout -b main && \
git add -A && \
git commit -m "Initial commit: {skill-name}" && \
gh repo create "{github_user}/{skill-name}" \
  --public --source=. --push \
  --description "{SKILL.md description 첫 문장 영문}"
```

---

## 리포트

```
✅ {skill-name} 새 레포 생성 + 동기화 완료
  파일: {N}개 (SKILL.md + references + README.md + README.ko.md)
  커밋: {hash 7자리}
  URL: https://github.com/{github_user}/{skill-name}
```
