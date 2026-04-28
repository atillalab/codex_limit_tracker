# README

- `codex_limit_tracker.rb` -> unified weekly limit tool for human text and `--json` machine output

## codex_limit_tracker.rb

Usage:

```bash
ruby codex_limit_tracker.rb
```

- Default human mode.
- Tries Codex `app-server` first for live 5h + weekly rate limits.
- Falls back to the latest local session logs if `app-server` is unavailable, slow, or incomplete.
- Uses the daily snapshot from `~/.codex/limit_tracker_daily_snapshot.json` only as the frozen morning baseline for daily-budget math.
- Reads fallback data from latest session logs in `~/.codex/sessions`.
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

TIP
  Token budgets are “use it or lose it.” Unused weekly capacity may reset,
  and 5-hour limits can prevent accumulated budget from being fully used.
```

The final `TIP` section shows one randomly selected tip from the built-in tip pool.

### Usage Examples

```bash
ruby codex_limit_tracker.rb --json
```

- Machine mode.
- Outputs only JSON:
  `{"weekly_reset_date":"YYYY-MM-DD","weekly_context_left_percent":number,"baseline_weekly_reset_date":"YYYY-MM-DD","baseline_weekly_context_left_percent":number,"days_until_weekly_reset":number,"daily_context_budget_percent":number,"weekly_context_after_today_budget_percent":number,"today_spent_percent":number,"today_left_percent":number}`

```bash
ruby codex_limit_tracker.rb --refresh
```

- Refresh mode.
- On first run of a local day without a saved daily snapshot, the script refreshes once with `codex exec --skip-git-repo-check --sandbox read-only "ping"` before locking the daily baseline.
- The `--refresh` flag is currently accepted for CLI compatibility, but does not change behavior.
- If refresh fails, script warns and falls back to cached data.

### Data source order

1. `codex -s read-only -a never app-server`
2. Latest local session log in `~/.codex/sessions/*/*/*/rollout-*.jsonl`

- The script uses a short timeout for `app-server` and falls back automatically if the RPC path does not return complete rate-limit data quickly enough.
- Human and `--json` output formats are unchanged regardless of which source succeeds.

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


## Example integration

[`drop_zone:`](https://github.com/atillalab/drop_zone) can be used by other CLI tools to get a stable app-specific
folder inside iCloud Drive.

```zsh
# profile.d/codex-limit-snapshot.sh
#
# Saves the latest Codex limit status as JSON into iCloud Drive.
# This acts as a lightweight snapshot bridge between codex-limit-tracker,
# drop-zone, and Apple Shortcuts / Apple Watch automations.
# Output: iCloud Drive/Drop Zone/codex_limit_tracker/latest.json

codex-limit-snapshot() {
  local app_dir
  app_dir="$(drop-zone ensure codex_limit_tracker)" || return 1
  codex-limit-tracker --json > "$app_dir/latest.json"
  echo "Saved: $app_dir/latest.json"
}
```

## TODO

- Consider providing a Homebrew tap later for easier installation and updates.
