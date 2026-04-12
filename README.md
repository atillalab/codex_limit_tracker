# README

- `prompt-v4.txt` -> latest prompt to use directly from Codex CLI
- `weekly_limit.rb` -> reads weekly limit data from local Codex session logs (`~/.codex/sessions`)

## weekly_limit.rb

Usage:

```bash
ruby weekly_limit.rb
```

- Fast mode.
- Uses latest cached session snapshot.

```bash
ruby weekly_limit.rb --refresh
```

- Refresh mode.
- Runs `codex exec --skip-git-repo-check --sandbox read-only "ping"` first, then reads logs.
- If refresh fails, script warns and falls back to cached data.

```bash
ruby weekly_limit.rb --help
```

- Shows available options.
