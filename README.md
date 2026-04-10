# git-sync

**Skill & settings GitHub sync engine.**

## Goal

git-sync automates GitHub synchronization for skills and User Preferences. After any skill is created/modified or UP is changed, git-sync syncs to dedicated GitHub repositories. Hub-spoke architecture: each skill in its own repo ({GITHUB_USER}/{skill-name}).

## When & How to Use

Trigger after skill-builder creates/modifies skills or up-manager modifies preferences. Handles: source detection, rsync, commit, push. Supports single skill sync, UP sync (version-aware), or batch sync with auto change detection.

## Use Cases

| Scenario | Prompt | What Happens |
|---|---|---|
| Sync new skill | (Auto after skill-builder) | Detect→rsync to {GITHUB_USER}/{name}→commit→push |
| Batch sync | `"Sync skills X, Y, Z."` | Detect changes→rsync all→3 commits→push |
| UP sync | (Auto after up-manager) | Detect version bump→rsync→commit→push |

## Key Features

- Hub-spoke repos: {GITHUB_USER}/{skill-name} per skill
- Automatic change detection — no manual file selection
- rsync + commit + push in one call
- Protected files: README.md, LICENSE, .gitignore never overwritten
- Sensitive info screening before push
- Batch sync with individual commits
- Version-aware UP sync

## Works With

- **[skill-builder](https://github.com/{GITHUB_USER}/skill-builder)** — outputs feed directly to git-sync
- **[up-manager](https://github.com/{GITHUB_USER}/up-manager)** — UP changes flow to git-sync
- **[autoloop](https://github.com/{GITHUB_USER}/autoloop)** — optimized skills synced after mutation

## Installation

```bash
git clone https://github.com/{GITHUB_USER}/git-sync.git ~/.claude/skills/git-sync
```

## Update

```bash
cd ~/.claude/skills/git-sync && git pull
```

Skills placed in `~/.claude/skills/` are automatically available in Claude Code and Cowork sessions.

## Part of Cowork Skills

This is one of 25+ custom skills. See the full catalog: [github.com/{GITHUB_USER}/cowork-skills](https://github.com/{GITHUB_USER}/cowork-skills)

## License

MIT License — feel free to use, modify, and share.
