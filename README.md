# README

- `codex_limit_tracker.rb` -> unified weekly limit tool for human text and `--json` machine output

## codex_limit_tracker.rb

Usage:

```bash
ruby codex_limit_tracker.rb
```

- Default human mode.
- Uses latest cached session snapshot from `~/.codex/sessions`.
- Freezes the day’s budget from the first successful run of that local day.
- Stores the frozen baseline in `~/.codex/limit_tracker_daily_snapshot.json`.
- Output example:
  `Weekly limit: 64% left (resets 21:02 on 16 Apr) - 13% daily budget - today's budget is until 51% is left`

```bash
ruby codex_limit_tracker.rb --json
```

- Machine mode.
- Outputs only JSON:
  `{"weekly_reset_date":"YYYY-MM-DD","weekly_context_left_percent":number,"days_until_weekly_reset":number,"daily_context_budget_percent":number,"weekly_context_after_today_budget_percent":number}`

```bash
ruby codex_limit_tracker.rb --refresh
```

- Refresh mode.
- On first run of a local day, the script always refreshes once with `codex exec --skip-git-repo-check --sandbox read-only "ping"` before locking the daily baseline.
- `--refresh` remains available, but the frozen same-day baseline is reused once created.
- If refresh fails, script warns and falls back to cached data.

```bash
ruby codex_limit_tracker.rb --help
```

- Shows available options.
