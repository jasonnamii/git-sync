# git-sync

**Skill & Settings GitHub Sync Engine** for Claude Cowork.

Automatically syncs your Cowork skills and User Preferences (UP) to individual GitHub repositories via `rsync → commit → push`.

## What It Does

- **One-command sync**: After editing or creating a skill, sync it to its dedicated GitHub repo
- **UP sync**: User Preferences files (versioned `.md`) synced to their own repo with automatic old-version cleanup
- **Batch sync**: Scan all skills for changes, show diff summary, sync only what changed
- **New repo creation**: Detects new skills without repos and creates them via `gh repo create`
- **Safety first**: Mandatory sensitive-info grep scan before every commit; blocks on match

## Hub-Spoke Architecture

- `SKILL.md` — Core rules, path mappings, trigger conditions, pipeline overview
- `references/pipeline-skill.md` — Single skill sync: rsync with `--delete` + excludes
- `references/pipeline-up.md` — UP sync: file-level copy with version-aware cleanup
- `references/pipeline-batch.md` — Batch sync + new repo creation flow
- `references/gotchas.md` — Common pitfalls (sandbox trap, rsync dangers, rate limits)

## Key Rules

1. **Desktop Commander only** — Cowork sandbox cannot access local git repos
2. **One-way sync** — Source → repo only, never reverse
3. **Protect repo metadata** — README, LICENSE, .gitignore excluded from rsync
4. **Block sensitive data** — Grep scan mandatory before every push

## Trigger Examples

```
"깃 동기화"     → sync the last modified skill
"push해줘"      → same
"전체 동기화"    → batch scan + sync all changed skills & UP
```

## Pipeline Flow

### Single Skill
```
① Verify source & repo exist
② rsync --delete (with excludes)
③ Sensitive info scan
④ git diff --stat
⑤ git add -A && commit
⑥ git push
⑦ Report
```

### UP (User Preferences)
```
① Find latest version file (glob)
② cp files + remove old versions
③ Sensitive info scan
④ git diff → commit → push → report
```

## License

MIT