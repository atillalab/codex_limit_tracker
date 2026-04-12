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

def latest_secondary_rate_limit
  files = Dir[File.expand_path("~/.codex/sessions/*/*/*/rollout-*.jsonl")]
  return nil if files.empty?

  latest = files.max_by { |p| File.mtime(p) }
  secondary = nil

  File.foreach(latest) do |line|
    begin
      obj = JSON.parse(line)
    rescue JSON::ParserError
      next
    end

    rl = obj.dig("payload", "rate_limits") || {}
    sec = rl["secondary"] || {}
    if sec.key?("used_percent") && sec.key?("resets_at")
      secondary = sec
    end
  end

  secondary
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
if snapshot
  reset_epoch = snapshot["weekly_reset_epoch"]
  reset_time_obj = reset_epoch.nil? ? nil : Time.at(reset_epoch.to_i)
  result = snapshot.merge("_reset_time_obj" => reset_time_obj)
else
  # First calculation of the day is anchored to fresh session data.
  refresh_snapshot

  secondary = latest_secondary_rate_limit
  abort("No session files found.") if secondary.nil?

  result = build_result(secondary)
  save_daily_snapshot(result)
end

if options[:json]
  output = result.reject { |k, _| k.start_with?("_") }
  puts JSON.generate(output)
  exit 0
end

left = result["weekly_context_left_percent"]
after_today = result["weekly_context_after_today_budget_percent"]
reset_time_obj = result["_reset_time_obj"]

abort("No weekly rate limit found.") if left.nil? || reset_time_obj.nil?

if after_today.nil?
  puts format(
    "Weekly limit: %.0f%% left (resets %s) - today's budget is unavailable",
    left.round,
    reset_time_obj.strftime("%H:%M on %d %b")
  )
else
  puts format(
    "Weekly limit: %.0f%% left (resets %s) - today's budget is until %.0f%% is left",
    left.round,
    reset_time_obj.strftime("%H:%M on %d %b"),
    after_today.round
  )
end
