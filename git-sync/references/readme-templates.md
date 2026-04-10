# 이중언어 README 템플릿

새 레포 생성 및 기존 레포 README 세팅 시 사용. SKILL.md에서 정보를 추출하여 아래 템플릿에 적용.

---

## 정보 추출 규칙

| 추출 대상 | 소스 | 변환 |
|----------|------|------|
| `{skill-name}` | YAML `name:` | 그대로 |
| `{title-en}` | name을 Title Case로 | `hit-skill` → `Hit Skill` |
| `{title-ko}` | SKILL.md 첫 번째 `#` 제목에서 한글 부분 | `# Git Sync — 스킬·설정 GitHub 동기화` → `스킬·설정 GitHub 동기화` |
| `{desc-en}` | description의 첫 문장을 영어로 요약 (1-2줄) | SKILL.md 본문 참조하여 작성 |
| `{desc-ko}` | description의 첫 문장 (한글 원문) | 그대로 |
| `{features}` | SKILL.md 본문에서 핵심 기능 3-5개 추출 | 불릿 리스트 |
| `{structure}` | 디렉토리 `tree` 출력 | `tree -I '.git' "{레포루트}/{skill-name}"` |

---

## README.md (English) 템플릿

```markdown
# {title-en}

> 🇰🇷 [한국어 README](./README.ko.md)

{desc-en}

## What It Does

{features-en — bulleted list}

## Structure

```
{structure}
```

## Part Of

This skill is part of a Claude Cowork skill ecosystem. For more information on Claude Cowork skills, see [Anthropic's documentation](https://docs.claude.com).

## License

MIT
```

---

## README.ko.md (한국어) 템플릿

```markdown
# {title-ko}

> 🇺🇸 [English README](./README.md)

{desc-ko}

## 주요 기능

{features-ko — bulleted list}

## 구조

```
{structure}
```

## 소속

이 스킬은 Claude Cowork 스킬 생태계의 일부입니다. Claude Cowork 스킬에 대한 자세한 정보는 [Anthropic 문서](https://docs.claude.com)를 참조하세요.

## 라이선스

MIT
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
