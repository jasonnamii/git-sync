# 단일 스킬 동기화 파이프라인

```
①대상 확인 → ②rsync → ③민감정보 검사 → ④diff 확인 → ⑤commit → ⑥push → ⑦리포트
```

---

## ① 대상 확인

DC `list_directory`로 원본과 레포 양쪽 존재 확인.

- 레포 미존재 → "레포가 없습니다. 생성할까요?" → `pipeline-batch.md` 새 레포 생성 절차
- 원본 미존재 → STOP + 알림

## ② rsync

```bash
rsync -av --delete \
  --exclude='.git/' \
  --exclude='.gitignore' \
  --exclude='README.md' \
  --exclude='LICENSE' \
  --exclude='.DS_Store' \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  "{스킬원본}/{skill-name}/" "{레포루트}/{skill-name}/"
```

`--delete`: 원본에서 삭제된 파일은 레포에서도 삭제. exclude 목록이 레포 메타파일 보호.

## ③ 민감정보 검사

```bash
grep -r -i \
  "jasoncnh@gmail\|oauth\|password=[^*]\|secret_key\|private_key\|Bearer " \
  "{레포루트}/{skill-name}/" \
  --include="*.md" --include="*.py" --include="*.json" \
  | grep -v "Possible hardcoded\|potential secret\|for pattern in"
```

- 매치 0건 → 통과
- 매치 있음 → **STOP** + 매치 표시 + 형 판단 요청. 자동 진행 ✗

## ④ diff 확인

```bash
cd "{레포루트}/{skill-name}" && git diff --stat
```

변경 없음 → "이미 최신입니다" + 종료.

## ⑤ commit

```bash
cd "{레포루트}/{skill-name}"
git add -A
git commit -m "Update {skill-name}: {변경 요약 1줄}"
```

커밋 메시지 예: `Update trigger-dictionary: modify protocol-edit4 reference`

## ⑥ push

```bash
git push
```

## ⑦ 리포트

```
✅ {skill-name} 동기화 완료
  변경: {N}개 파일 수정, {M}개 추가, {K}개 삭제
  커밋: {hash 7자리}
  URL: https://github.com/jasonnamii/{skill-name}
```