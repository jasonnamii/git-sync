# 이중언어 README 템플릿

새 레포 생성 및 기존 레포 README 세팅 시 사용. SKILL.md에서 정보를 추출하여 아래 템플릿에 적용.

---

## 정보 추출 규칙

| 추출 대상 | 소스 | 변환 |
|----------|------|------|
| `{skill-name}` | YAML `name:` | 그대로 |
| `{desc-en}` | description 첫 문장 + SKILL.md 본문 참조하여 자연스러운 영어로 작성 (1-2줄) | 번역체 금지 |
| `{desc-ko}` | description 첫 문장 (한글 원문) | 그대로 |
| `{goal-en}` | SKILL.md 핵심 목적을 2-3문장 영어로 | 왜 이 스킬이 필요한지, 무엇을 해결하는지 |
| `{goal-ko}` | 위와 동일 한글 | |
| `{when-how-en}` | 발동 조건 + 사용 방법 2-3문장 | |
| `{use-cases}` | 3-4행 테이블: Scenario / Prompt / What Happens | 실제 프롬프트 예시 포함 |
| `{features}` | SKILL.md 본문에서 핵심 기능/아키텍처 3-5개 추출 | 불릿 리스트 |
| `{works-with}` | SKILL.md 연동 스킬 목록 | GitHub 링크 포함 |

---

## README.md (English) 템플릿

```markdown
# {skill-name}

> 🇰🇷 [한국어 README](./README.ko.md)

**{desc-en}**

## Prerequisites

- **Claude Cowork or Claude Code** environment
{추가 요구사항이 있으면 항목 추가: Obsidian Vault, Web search 등}

## Goal

{goal-en — 2-3문장. 이 스킬이 해결하는 문제와 접근법}

## When & How to Use

{when-how-en — 발동 조건, 사용 방법, 다른 스킬과의 차이점}

## Use Cases

| Scenario | Prompt | What Happens |
|---|---|---|
| {상황1} | `"{프롬프트1}"` | {동작 설명} |
| {상황2} | `"{프롬프트2}"` | {동작 설명} |
| {상황3} | `"{프롬프트3}"` | {동작 설명} |

## Key Features

{features — 불릿 리스트. 볼드 키워드 + 1줄 설명}

## Works With

- **[{연동스킬1}](https://github.com/jasonnamii/{연동스킬1})** — {관계 설명}
- **[{연동스킬2}](https://github.com/jasonnamii/{연동스킬2})** — {관계 설명}

## Installation

\`\`\`bash
git clone https://github.com/jasonnamii/{skill-name}.git ~/.claude/skills/{skill-name}
\`\`\`

## Update

\`\`\`bash
cd ~/.claude/skills/{skill-name} && git pull
\`\`\`

Skills placed in `~/.claude/skills/` are automatically available in Claude Code and Cowork sessions.

## Part of Cowork Skills

This is one of 25+ custom skills. See the full catalog: [github.com/jasonnamii/cowork-skills](https://github.com/jasonnamii/cowork-skills)

## License

MIT License — feel free to use, modify, and share.
```

---

## README.ko.md (한국어) 템플릿

```markdown
# {skill-name}

> 🇺🇸 [English README](./README.md)

**{desc-ko}**

## 사전 요구

- **Claude Cowork 또는 Claude Code** 환경
{추가 요구사항}

## 목표

{goal-ko — 2-3문장}

## 사용 시점 & 방법

{when-how-ko — 발동 조건, 사용 방법}

## 사용 사례

| 상황 | 프롬프트 | 동작 |
|---|---|---|
| {상황1} | `"{프롬프트1}"` | {동작 설명} |
| {상황2} | `"{프롬프트2}"` | {동작 설명} |
| {상황3} | `"{프롬프트3}"` | {동작 설명} |

## 주요 기능

{features-ko — 불릿 리스트}

## 연동 스킬

- **[{연동스킬1}](https://github.com/jasonnamii/{연동스킬1})** — {관계 설명}
- **[{연동스킬2}](https://github.com/jasonnamii/{연동스킬2})** — {관계 설명}

## 설치

\`\`\`bash
git clone https://github.com/jasonnamii/{skill-name}.git ~/.claude/skills/{skill-name}
\`\`\`

## 업데이트

\`\`\`bash
cd ~/.claude/skills/{skill-name} && git pull
\`\`\`

`~/.claude/skills/`에 배치된 스킬은 Claude Code 및 Cowork 세션에서 자동으로 사용 가능합니다.

## Cowork Skills

25개 이상의 커스텀 스킬 중 하나입니다. 전체 카탈로그: [github.com/jasonnamii/cowork-skills](https://github.com/jasonnamii/cowork-skills)

## 라이선스

MIT License — 자유롭게 사용, 수정, 공유 가능합니다.
```

---

## 작성 원칙

| # | 원칙 | 이유 |
|---|------|------|
| 1 | **영문은 번역체 금지** — 자연스러운 영어로 새로 작성 | 한글 직역 = 어색 |
| 2 | **한글은 SKILL.md 톤 유지** — 간결·단정 | 이미 확립된 톤 |
| 3 | **양쪽 구조 동일** — 섹션 순서·개수 일치 | 전환 시 혼란 방지 |
| 4 | **상단 언어 전환 링크 필수** — blockquote 형태 | 발견성 보장 |
| 5 | **SKILL.md 내용과 충돌 금지** — README는 외부용 요약 | 상세는 SKILL.md에 |
| 6 | **기술 용어는 양쪽 동일** — rsync, commit, push 등 | 번역하면 오히려 혼란 |
