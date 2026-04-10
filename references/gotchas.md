# Gotchas — 주의사항

| # | 함정 | 대응 |
|---|------|------|
| 1 | **Cowork 샌드박스:** `Bash` tool은 샌드박스 내 실행. 로컬 git repo 접근 불가 | 로컬 터미널(DC `start_process`)로 실행 |
| 2 | **rsync --delete:** exclude 빠뜨리면 README.md/README.ko.md/LICENSE/gitignore 삭제 | exclude 리스트 항상 8개 전부 포함 확인 |
| 3 | **skills-plugin UUID 변경:** Cowork 재설치 시 UUID 변경 가능 | `find` 동적 탐색 후 확인: `find "{USER_HOME}/Library/Application Support/Claude/local-agent-mode-sessions/skills-plugin" -maxdepth 3 -name "skills" -type d` |
| 4 | **동시 push 제한:** GitHub rate limit | 3개 이하 병렬 OK, 4개 이상 순차 |
| 5 | **커밋 author:** 로컬 git config 따름 | `git config user.name` / `git config user.email` 확인 |
| 6 | **UP 버전 파일명:** 버전 범프 시 파일명 변경 | glob `v*.md`로 탐색, 구버전 자동 정리 |
| 7 | **이중언어 README 동기:** README.md와 README.ko.md 내용 불일치 | 생성·수정 시 항상 양쪽 동시 작업. `references/readme-templates.md` 템플릿 사용 |