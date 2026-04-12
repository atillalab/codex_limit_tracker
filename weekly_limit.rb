#!/usr/bin/env ruby
require "json"
require "time"

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
