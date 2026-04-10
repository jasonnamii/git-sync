# UP 동기화 파이프라인

스킬과 달리 디렉토리가 아닌 **개별 파일** 단위. 버전 번호가 파일명에 포함.

```
①대상 파일 탐색 → ②파일 복사 + 구버전 정리 → ③민감정보 검사 → ④diff → ⑤commit → ⑥push → ⑦리포트
```

---

## ① 대상 파일 탐색

```bash
# 최신 버전 파일 자동 탐색 (버전 번호 변경 대응)
ls "{UP원본}"/UP_user-preferences_v*.md
ls "{UP원본}"/UP_stability.md
```

- 파일 없음 → STOP + 알림
- 여러 버전 존재 → 가장 높은 버전만 동기화

## ② 파일 복사

rsync 대신 개별 cp. 레포의 README/LICENSE/.gitignore 보호.

```bash
cp "{UP원본}/UP_user-preferences_v{N}.md" "{UP레포}/"
cp "{UP원본}/UP_stability.md" "{UP레포}/"
```

**구버전 정리:** 버전이 올라갔으면(v29→v30) 레포 내 이전 버전 파일 삭제.

```bash
cd "{UP레포}"
ls UP_user-preferences_v*.md | grep -v "v{현재버전}" | xargs rm -f
```

## ③ 민감정보 검사

스킬 동기화와 동일 패턴. 대상 경로만 `{UP레포}/`로 변경.

```bash
grep -r -i \
  "{USER_EMAIL}\|oauth\|password=[^*]\|secret_key\|private_key\|Bearer " \
  "{UP레포}/" \
  --include="*.md" \
  | grep -v "Possible hardcoded\|potential secret\|for pattern in"
```

## ④ diff 확인

```bash
cd "{UP레포}" && git diff --stat
```

## ⑤ commit

```bash
cd "{UP레포}"
git add -A
git commit -m "Update UP: v{이전} → v{현재}"
```

버전 변경 없이 내용만 수정된 경우: `Update UP: minor edit v{N}`

## ⑥ push

```bash
git push
```

## ⑦ 리포트

```
✅ user-preferences 동기화 완료
  변경: UP_user-preferences_v{N}.md 수정
  커밋: {hash 7자리}
  URL: https://github.com/{GITHUB_USER}/user-preferences
```