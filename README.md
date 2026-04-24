# README

- `codex_limit_tracker.rb` -> unified weekly limit tool for human text and `--json` machine output

## codex_limit_tracker.rb

Usage:

```bash
ruby codex_limit_tracker.rb
```

- Default human mode.
- Shows the current weekly limit live from the latest session logs.
- Uses the daily snapshot from `~/.codex/limit_tracker_daily_snapshot.json` only as the frozen morning baseline for daily-budget math.
- Reads 5h limit live from latest session logs in `~/.codex/sessions`.
- Freezes the day’s budget from the first successful run of that local day.
- Stores the frozen baseline in `~/.codex/limit_tracker_daily_snapshot.json`.
- Highlights `Today's budget` first and spells out how much of today's budget is already used.

### Example Output

```bash
$ ruby codex_limit_tracker.rb
Codex usage
  Today's budget: 23% spent, 77% left today (3% of 13% daily budget used)
  Weekly limit now: 48% left (resets 21:02 on 16 Apr)
  Morning baseline: 64% left (captured 08:14)
  Daily budget: 13%
  5h limit: 87% left (resets 14:05)
```

### Usage Examples

```bash
ruby codex_limit_tracker.rb --json
```

- Machine mode.
- Outputs only JSON:
  `{"weekly_reset_date":"YYYY-MM-DD","weekly_context_left_percent":number,"baseline_weekly_reset_date":"YYYY-MM-DD","baseline_weekly_context_left_percent":number,"days_until_weekly_reset":number,"daily_context_budget_percent":number,"weekly_context_after_today_budget_percent":number}`

```bash
ruby codex_limit_tracker.rb --refresh
```

- Refresh mode.
- On first run of a local day without a saved daily snapshot, the script refreshes once with `codex exec --skip-git-repo-check --sandbox read-only "ping"` before locking the daily baseline.
- The `--refresh` flag is currently accepted for CLI compatibility, but does not change behavior.
- If refresh fails, script warns and falls back to cached data.

```bash
ruby codex_limit_tracker.rb --help
```

- Shows available options.

#### macOS System-Wide Usage

```bash
ln -sf ~/Documents/path-to-codex_limit_tracker/codex_limit_tracker.rb /usr/local/bin/codex-limit-tracker
chmod +x ~/Documents/path-to-codex_limit_tracker/codex_limit_tracker.rb

codex-limit-tracker
```

- macOS system-wide usage via symlink so `codex-limit-tracker` can be run from anywhere.
- `chmod +x` makes the script executable and avoids `zsh: permission denied: codex-limit-tracker`.
- If `/usr/local/bin` is not writable for your user, run the `ln` command with `sudo`.
