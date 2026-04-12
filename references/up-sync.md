# UP 동기화

**정확히 2회의 DC start_process만 사용한다.** 민감정보 검사·commit·push는 호출 2의 단일 bash 스크립트 안에서 `&&`로 체이닝한다. 3회 이상으로 분할하지 마라.

---

## 호출 1: 파일 탐색 + 복사

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

---

## 호출 2: 민감정보 + commit + push

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

**참고:** UP 레포에는 SKILL.md가 없으므로 secret-scan.sh의 SKILL.md 제외 로직이 자연스럽게 무해(no-op)하다. 별도 플래그 불필요.

---

## 리포트

```
✅ user-preferences 동기화 완료
  변경: {N}파일 수정, {M}추가, {K}삭제
  커밋: {hash 7자리}
  URL: https://github.com/{github_user}/user-preferences
```
