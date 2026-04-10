# 단일 스킬 동기화 파이프라인

```
턴3턴 압축:
  턴1: [ENV resolve(캐시시 스킵) + 대상확인 + PRE_SYNC_CHECK]
  턴2: [rsync + 민감정보 + commit + push]  ← && 체이닝, DC 1회 호출
  턴3: 리포트
```

---

## 턴1: 환경 + 대상확인 + PRE_SYNC_CHECK

### ① 대상 확인

원본과 레포 양쪽 디렉토리 존재 확인.

- 레포 미존재 → "레포가 없습니다. 생성할까요?" → `pipeline-batch.md` 새 레포 생성 절차
- 원본 미존재 → STOP + 알림

### ②-pre PRE_SYNC_CHECK (삭제 예정 파일 선확인)

```bash
rsync -avn --delete \
  --exclude='.git/' \
  --exclude='.gitignore' \
  --exclude='README.md' \
  --exclude='README.ko.md' \
  --exclude='LICENSE' \
  --exclude='.DS_Store' \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  "{skill원본}/{skill-name}/" "{repo루트}/{skill-name}/" \
  | grep '^deleting '
```

- 삭제 0건 → 통2 진행
- 삭제 예정 파일이 references/, scripts/, agents/ 내부 → **STOP** + 형에게 삭제 대상 표시 + 확인 요청
- 삭제 예정이 의도된 것(e.g. 구버전 정리) → 형 컨펌 후 진행

## 턴2: rsync + 민감정보 + commit + push

### ② rsync

```bash
rsync -av --delete \
  --exclude='.git/' \
  --exclude='.gitignore' \
  --exclude='README.md' \
  --exclude='README.ko.md' \
  --exclude='LICENSE' \
  --exclude='.DS_Store' \
  --exclude='__pycache__/' \
  --exclude='*.pyc' \
  "{스킬원본}/{skill-name}/" "{레포루트}/{skill-name}/"
```

`--delete`: 원본에서 삭제된 파일은 레포에서도 삭제. exclude 목록(8개)이 레포 메타파일 보호.

## ③ 민감정보 검사

```bash
grep -r -i \
  "{USER_EMAIL}\|oauth\|password=[^*]\|secret_key\|private_key\|Bearer " \
  "{레포루트}/{skill-name}/" \
  --include="*.md" --include="*.py" --include="*.json" \
  | grep -v "Possible hardcoded\|potential secret\|for pattern in"
```

- 매치 0건 → 통과
- 매치 있음 → **STOP** + 매치 표시 + 형 판단 요청. 자동 진행 ✗

### ④ diff + commit (통2에서 && 체이닝)

```bash
cd "{repo루트}/{skill-name}" && \
  git diff --stat && \
  git add -A && \
  git commit -m "Update {skill-name}: {변경 요약 1줄}" && \
  git push
```

변경 없음(diff 빈) → commit이 실패하므로 자연 종료. "이미 최신입니다" 보고.

커밋 메시지 예: `Update trigger-dictionary: modify protocol-edit4 reference`

## 턴3: 리포트

```
✅ {skill-name} 동기화 완료
  변경: {N}개 파일 수정, {M}개 추가, {K}개 삭제
  커밋: {hash 7자리}
  URL: https://github.com/{GITHUB_USER}/{skill-name}
```