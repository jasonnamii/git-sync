# 스킬·설정 GitHub 동기화

> 🇺🇸 [English README](./README.md)

**스킬과 사용자 설정을 GitHub에 자동 동기화하는 엔진입니다.**

## 사전 요구사항

- **Obsidian Vault** — UP 소스 파일이 vault 내 `Agent-Ops/` 폴더에 저장되어 있어야 함
- **Desktop Commander MCP** — 로컬 파일 작업에 필수
- **GitHub CLI (`gh`)** — 대상 저장소에 push 권한을 가진 인증된 상태
- **Claude Cowork 또는 Claude Code** 환경

## 목적

git-sync는 스킬과 User Preferences(UP)의 GitHub 동기화를 자동화합니다. 스킬을 생성/수정하거나 UP를 변경하면, git-sync가 전용 GitHub 저장소로 자동 동기화합니다. 허브-스포크 아키텍처: 각 스킬이 독립적인 저장소에 위치합니다 ({GITHUB_USER}/{skill-name}).

## 사용 시점 및 방법

skill-builder가 스킬을 생성/수정하거나 up-manager가 설정을 변경한 후에 발동합니다. 소스 감지, rsync, commit, push를 처리합니다. 단일 스킬 동기화, UP 동기화(버전 인식), 또는 자동 변경 감지를 통한 배치 동기화를 지원합니다.

## 사용 예시

| 상황 | 프롬프트 | 결과 |
|---|---|---|
| 새 스킬 동기화 | (skill-builder 실행 후 자동) | 감지→{GITHUB_USER}/{name}으로 rsync→commit→push |
| 배치 동기화 | `"X, Y, Z 스킬을 동기화해."` | 변경사항 감지→모두 rsync→3개 commit→push |
| UP 동기화 | (up-manager 실행 후 자동) | 버전 변경 감지→rsync→commit→push |

## 핵심 기능

- 허브-스포크 저장소: 스킬당 {GITHUB_USER}/{skill-name}
- 자동 변경 감지 — 수동 파일 선택 불필요
- rsync + commit + push 일괄 처리
- 보호된 파일: README.md, LICENSE, .gitignore는 덮어쓰기 안 함
- push 전 민감한 정보 스크리닝
- 배치 동기화 및 개별 commit
- 버전 인식 UP 동기화

## 연관 스킬

- **[skill-builder](https://github.com/{GITHUB_USER}/skill-builder)** — 출력이 git-sync로 직접 연결됨
- **[up-manager](https://github.com/{GITHUB_USER}/up-manager)** — UP 변경사항이 git-sync로 전달됨
- **[autoloop](https://github.com/{GITHUB_USER}/autoloop)** — 최적화된 스킬이 변경 후 동기화됨

## 설치

```bash
git clone https://github.com/{GITHUB_USER}/git-sync.git ~/.claude/skills/git-sync
```

## 업데이트

```bash
cd ~/.claude/skills/git-sync && git pull
```

`~/.claude/skills/`에 배치된 스킬은 Claude Code 및 Cowork 세션에서 자동으로 사용할 수 있습니다.

## Cowork 스킬 생태계

25개 이상의 커스텀 스킬 중 하나입니다. 전체 카탈로그: [github.com/{GITHUB_USER}/cowork-skills](https://github.com/{GITHUB_USER}/cowork-skills)

## 라이선스

MIT 라이선스 — 자유롭게 사용, 수정, 공유하세요.