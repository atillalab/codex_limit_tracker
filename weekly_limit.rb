#!/usr/bin/env ruby
require "json"
require "time"

REFRESH_CMD = 'codex exec --skip-git-repo-check --sandbox read-only "ping"'.freeze

def usage
  <<~TEXT
    Usage: ruby weekly_limit.rb [--refresh] [--help]

    Options:
      --refresh   Run a read-only codex exec turn before reading local session logs.
      -h, --help  Show this help message.
  TEXT
end

def parse_args(argv)
  refresh = false
  argv.each do |arg|
    case arg
    when "--refresh"
      refresh = true
    when "-h", "--help"
      puts usage
      exit 0
    else
      abort("Unknown option: #{arg}\n\n#{usage}")
    end
  end
  refresh
end

def refresh_snapshot
  ok = system(REFRESH_CMD, out: File::NULL, err: File::NULL)
  return if ok

  warn "Warning: refresh failed; using latest cached session data."
end

refresh = parse_args(ARGV)
refresh_snapshot if refresh

files = Dir[File.expand_path("~/.codex/sessions/*/*/*/rollout-*.jsonl")]
abort("No session files found.") if files.empty?

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

abort("No weekly rate limit found.") unless secondary

left = 100.0 - secondary["used_percent"].to_f
reset_time = Time.at(secondary["resets_at"].to_i)
puts format("Weekly limit: %.0f%% left (resets %s)", left, reset_time.strftime("%H:%M on %d %b"))
