#!/usr/bin/env ruby
require "json"
require "time"
require "date"

REFRESH_CMD = 'codex exec --skip-git-repo-check --sandbox read-only "ping"'.freeze
SNAPSHOT_PATH = File.expand_path("~/.codex/limit_tracker_daily_snapshot.json").freeze

def usage
  <<~TEXT
    Usage: ruby codex_limit_tracker.rb [--json] [--refresh] [--help]

    Options:
      --json      Output machine-readable JSON only.
      --refresh   Run a read-only codex exec turn before reading local session logs.
      -h, --help  Show this help message.
  TEXT
end

def parse_args(argv)
  options = { refresh: false, json: false }
  argv.each do |arg|
    case arg
    when "--json"
      options[:json] = true
    when "--refresh"
      options[:refresh] = true
    when "-h", "--help"
      puts usage
      exit 0
    else
      abort("Unknown option: #{arg}\n\n#{usage}")
    end
  end
  options
end

def refresh_snapshot
  ok = system(REFRESH_CMD, out: File::NULL, err: File::NULL)
  return if ok

  warn "Warning: refresh failed; using latest cached session data."
end

def latest_rate_limits
  files = Dir[File.expand_path("~/.codex/sessions/*/*/*/rollout-*.jsonl")]
  return nil if files.empty?

  latest = files.max_by { |p| File.mtime(p) }
  primary = nil
  secondary = nil

  File.foreach(latest) do |line|
    begin
      obj = JSON.parse(line)
    rescue JSON::ParserError
      next
    end

    rl = obj.dig("payload", "rate_limits") || {}
    pri = rl["primary"] || {}
    sec = rl["secondary"] || {}
    if pri.key?("used_percent") && pri.key?("resets_at")
      primary = pri
    end
    if sec.key?("used_percent") && sec.key?("resets_at")
      secondary = sec
    end
  end

  { "primary" => primary, "secondary" => secondary }
end

def snapshot_today?(snapshot)
  snapshot["snapshot_date"] == Date.today.strftime("%Y-%m-%d")
end

def snapshot_stale_for_weekly_reset?(snapshot)
  reset_epoch = snapshot["weekly_reset_epoch"]
  return false if reset_epoch.nil?

  Time.now.to_i >= reset_epoch.to_i
end

def load_daily_snapshot
  return nil unless File.file?(SNAPSHOT_PATH)

  begin
    raw = File.read(SNAPSHOT_PATH)
    snapshot = JSON.parse(raw)
  rescue Errno::ENOENT, JSON::ParserError
    return nil
  end

  return nil unless snapshot.is_a?(Hash)
  return nil unless snapshot_today?(snapshot)
  return nil if snapshot_stale_for_weekly_reset?(snapshot)

  snapshot
end

def snapshot_result(snapshot)
  reset_epoch = snapshot["weekly_reset_epoch"]
  reset_time_obj = reset_epoch.nil? ? nil : Time.at(reset_epoch.to_i)
  snapshot.merge("_reset_time_obj" => reset_time_obj)
end

def save_daily_snapshot(result)
  dir = File.dirname(SNAPSHOT_PATH)
  Dir.mkdir(dir) unless Dir.exist?(dir)

  payload = {
    "snapshot_date" => Date.today.strftime("%Y-%m-%d"),
    "captured_at" => Time.now.iso8601,
    "weekly_reset_date" => result["weekly_reset_date"],
    "weekly_reset_epoch" => result["_reset_time_obj"]&.to_i,
    "weekly_context_left_percent" => result["weekly_context_left_percent"],
    "days_until_weekly_reset" => result["days_until_weekly_reset"],
    "daily_context_budget_percent" => result["daily_context_budget_percent"],
    "weekly_context_after_today_budget_percent" => result["weekly_context_after_today_budget_percent"]
  }

  File.write(SNAPSHOT_PATH, JSON.pretty_generate(payload))
rescue Errno::EACCES, Errno::EPERM, Errno::ENOENT => e
  warn "Warning: could not persist daily snapshot (#{e.message}); continuing without cache."
end

def build_result(secondary)
  used_percent = secondary && secondary.key?("used_percent") ? secondary["used_percent"].to_f : nil
  reset_time = secondary && secondary.key?("resets_at") ? Time.at(secondary["resets_at"].to_i) : nil

  weekly_context_left_percent = used_percent.nil? ? nil : (100.0 - used_percent)
  weekly_reset_date = reset_time.nil? ? nil : reset_time.strftime("%Y-%m-%d")

  days_until_weekly_reset = nil
  if weekly_reset_date && weekly_context_left_percent
    reset_date = Date.parse(weekly_reset_date)
    today = Date.today
    days_until_weekly_reset = (reset_date - today).to_i + 1
  end

  daily_context_budget_percent = nil
  weekly_context_after_today_budget_percent = nil
  if !weekly_context_left_percent.nil? && !days_until_weekly_reset.nil? && days_until_weekly_reset > 0
    daily_context_budget_percent = weekly_context_left_percent / days_until_weekly_reset
    weekly_context_after_today_budget_percent = weekly_context_left_percent - daily_context_budget_percent
  end

  {
    "weekly_reset_date" => weekly_reset_date,
    "weekly_context_left_percent" => weekly_context_left_percent,
    "days_until_weekly_reset" => days_until_weekly_reset,
    "daily_context_budget_percent" => daily_context_budget_percent,
    "weekly_context_after_today_budget_percent" => weekly_context_after_today_budget_percent,
    "_reset_time_obj" => reset_time
  }
end

options = parse_args(ARGV)
snapshot = load_daily_snapshot
rate_limits = latest_rate_limits
abort("No session files found.") if rate_limits.nil?
primary = rate_limits["primary"]
if snapshot
  current_result = build_result(rate_limits["secondary"])
  abort("No weekly rate limit found.") if current_result["weekly_context_left_percent"].nil? || current_result["_reset_time_obj"].nil?
  baseline_result = snapshot_result(snapshot)
else
  # First calculation of the day is anchored to fresh session data.
  refresh_snapshot

  rate_limits = latest_rate_limits
  abort("No session files found.") if rate_limits.nil?
  secondary = rate_limits["secondary"]
  primary = rate_limits["primary"]
  abort("No session files found.") if secondary.nil?

  current_result = build_result(secondary)
  abort("No weekly rate limit found.") if current_result["weekly_context_left_percent"].nil? || current_result["_reset_time_obj"].nil?
  baseline_result = current_result
  save_daily_snapshot(baseline_result)
end

if options[:json]
  output = {
    "weekly_reset_date" => current_result["weekly_reset_date"],
    "weekly_context_left_percent" => current_result["weekly_context_left_percent"],
    "baseline_weekly_reset_date" => baseline_result["weekly_reset_date"],
    "baseline_weekly_context_left_percent" => baseline_result["weekly_context_left_percent"],
    "days_until_weekly_reset" => baseline_result["days_until_weekly_reset"],
    "daily_context_budget_percent" => baseline_result["daily_context_budget_percent"],
    "weekly_context_after_today_budget_percent" => baseline_result["weekly_context_after_today_budget_percent"]
  }
  puts JSON.generate(output)
  exit 0
end

current_left = current_result["weekly_context_left_percent"]
current_reset_time_obj = current_result["_reset_time_obj"]
baseline_left = baseline_result["weekly_context_left_percent"]
baseline_captured_at = if snapshot && snapshot["captured_at"]
  begin
    Time.parse(snapshot["captured_at"])
  rescue ArgumentError, TypeError
    nil
  end
end
daily_budget = baseline_result["daily_context_budget_percent"]
after_today = baseline_result["weekly_context_after_today_budget_percent"]
five_hour_left = primary && primary.key?("used_percent") ? (100.0 - primary["used_percent"].to_f) : nil
five_hour_reset_time = primary && primary.key?("resets_at") ? Time.at(primary["resets_at"].to_i) : nil
five_hour_segment =
  if five_hour_left.nil? || five_hour_reset_time.nil?
    "5h limit unavailable"
  else
    format(
      "5h limit: %.0f%% left (resets %s)",
      five_hour_left.round,
      five_hour_reset_time.strftime("%H:%M")
    )
  end

if after_today.nil?
  if daily_budget.nil?
    puts format(
      "Weekly limit now: %.0f%% left (resets %s) - morning baseline: %.0f%% left%s - %s - today's budget is unavailable",
      current_left.round,
      current_reset_time_obj.strftime("%H:%M on %d %b"),
      baseline_left.round,
      baseline_captured_at.nil? ? "" : format(" (captured %s)", baseline_captured_at.strftime("%H:%M")),
      five_hour_segment
    )
  else
    puts format(
      "Weekly limit now: %.0f%% left (resets %s) - morning baseline: %.0f%% left%s - %.0f%% daily budget - %s - today's budget is unavailable",
      current_left.round,
      current_reset_time_obj.strftime("%H:%M on %d %b"),
      baseline_left.round,
      baseline_captured_at.nil? ? "" : format(" (captured %s)", baseline_captured_at.strftime("%H:%M")),
      daily_budget.round,
      five_hour_segment
    )
  end
else
  puts format(
    "Weekly limit now: %.0f%% left (resets %s) - morning baseline: %.0f%% left%s - %.0f%% daily budget - %s - today's budget is until %.0f%% is left",
    current_left.round,
    current_reset_time_obj.strftime("%H:%M on %d %b"),
    baseline_left.round,
    baseline_captured_at.nil? ? "" : format(" (captured %s)", baseline_captured_at.strftime("%H:%M")),
    daily_budget.round,
    five_hour_segment,
    after_today.round
  )
end
