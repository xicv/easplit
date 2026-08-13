#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"

REUSE_HEADING = "Would you use eaSplit in a normal week?"
PURCHASE_HEADING = "Would a polished version be worth a one-time purchase?"
REUSE_OPTIONS = ["Yes, most days", "Yes, once or twice a week", "Occasionally", "Not yet"].freeze
PURCHASE_OPTIONS = ["Yes", "Maybe", "No", "Prefer not to answer"].freeze
LIST_LIMIT = 20

def abort_with(message)
  warn message
  exit 1
end

def parse_time(value, field:, issue_number:)
  Time.iso8601(String(value)).utc
rescue ArgumentError
  abort_with("Issue ##{issue_number} has an invalid #{field} timestamp.")
end

def form_value(body, heading)
  pattern = /^### #{Regexp.escape(heading)}\s*$\n+(.*?)(?=^### |\z)/m
  match = String(body).match(pattern)
  return nil unless match

  value = match[1].strip
  value.empty? ? nil : value
end

def sanitize_markdown(value)
  text = String(value).encode("UTF-8", invalid: :replace, undef: :replace, replace: "�")
  text = text.gsub(/[\r\n\t]+/, " ").gsub(%r{https?://\S+}, "[link removed]")
  text = text.gsub("<", "&lt;").gsub(">", "&gt;")
  text = text.gsub(/([\\`*_\[\]()#|])/, '\\\\1').strip
  text.length > 160 ? "#{text[0, 157]}..." : text
end

def issue_link(issue, server_url:, repository:)
  number = Integer(issue.fetch("number"))
  "#{server_url}/#{repository}/issues/#{number}"
rescue ArgumentError, TypeError, KeyError
  abort_with("A beta feedback record has an invalid issue number.")
end

def issue_line(issue, server_url:, repository:)
  number = Integer(issue.fetch("number"))
  title = sanitize_markdown(issue.fetch("title", "Untitled report"))
  created = issue.fetch("parsed_created_at").strftime("%Y-%m-%d")
  comments = Integer(issue.fetch("comments", 0))
  state = sanitize_markdown(issue.fetch("state"))
  "- [##{number} #{title}](#{issue_link(issue, server_url: server_url, repository: repository)}) — #{state}, #{comments} replies, opened #{created}"
end

def append_issue_list(lines, issues, server_url:, repository:)
  issues.first(LIST_LIMIT).each do |issue|
    lines << issue_line(issue, server_url: server_url, repository: repository)
  end
  remaining = issues.length - LIST_LIMIT
  lines << "- …and #{remaining} more." if remaining.positive?
end

def append_signal_table(lines, heading, options, issues, field_heading)
  counts = Hash.new(0)
  issues.each do |issue|
    value = form_value(issue["body"], field_heading)
    counts[options.include?(value) ? value : "Unavailable"] += 1
  end

  lines << "### #{heading}"
  lines << ""
  lines << "| Response | Count |"
  lines << "| --- | ---: |"
  options.each { |option| lines << "| #{option} | #{counts[option]} |" }
  lines << "| Unavailable | #{counts['Unavailable']} |" if counts["Unavailable"].positive?
  lines << ""
end

raw_input = $stdin.read
begin
  records = JSON.parse(raw_input)
rescue JSON::ParserError => error
  abort_with("Unable to read beta feedback JSON: #{error.message}")
end
abort_with("Beta feedback JSON must be an array.") unless records.is_a?(Array)

begin
  now = Time.iso8601(ENV.fetch("REPORT_NOW", Time.now.utc.iso8601)).utc
  window_days = Integer(ENV.fetch("REPORT_WINDOW_DAYS", "7"))
rescue ArgumentError => error
  abort_with("Invalid beta report configuration: #{error.message}")
end
abort_with("REPORT_WINDOW_DAYS must be between 1 and 365.") unless (1..365).cover?(window_days)

server_url = ENV.fetch("GITHUB_SERVER_URL", "https://github.com").sub(%r{/+\z}, "")
repository = ENV.fetch("GITHUB_REPOSITORY", "xicv/easplit")
abort_with("GITHUB_REPOSITORY must use owner/repository format.") unless repository.match?(%r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z})

issues = records.reject { |record| record.is_a?(Hash) && record["pull_request"] }.map do |record|
  abort_with("Every beta feedback record must be an object.") unless record.is_a?(Hash)

  number = record["number"]
  record.merge(
    "parsed_created_at" => parse_time(record["created_at"], field: "created_at", issue_number: number),
    "parsed_closed_at" => record["closed_at"] && parse_time(record["closed_at"], field: "closed_at", issue_number: number)
  )
end

cutoff = now - (window_days * 86_400)
open_issues = issues.select { |issue| issue["state"] == "open" }
new_issues = issues.select { |issue| issue["parsed_created_at"] >= cutoff && issue["parsed_created_at"] <= now }
closed_this_week = issues.select do |issue|
  closed_at = issue["parsed_closed_at"]
  closed_at && closed_at >= cutoff && closed_at <= now
end
without_replies = open_issues.select { |issue| Integer(issue.fetch("comments", 0)).zero? }
aging = open_issues.select { |issue| issue["parsed_created_at"] < cutoff }

new_issues.sort_by! { |issue| issue["parsed_created_at"] }.reverse!
open_issues.sort_by! { |issue| issue["parsed_created_at"] }.reverse!
without_replies.sort_by! { |issue| issue["parsed_created_at"] }
aging.sort_by! { |issue| issue["parsed_created_at"] }

lines = []
lines << "# eaSplit weekly beta report"
lines << ""
lines << "Generated #{now.strftime('%Y-%m-%d %H:%M UTC')} from public issues labeled `beta-feedback`."
lines << ""
lines << "## Snapshot"
lines << ""
lines << "| Metric | Count |"
lines << "| --- | ---: |"
lines << "| New reports | #{new_issues.length} |"
lines << "| Open reports | #{open_issues.length} |"
lines << "| Closed this week | #{closed_this_week.length} |"
lines << "| Open with no replies | #{without_replies.length} |"
lines << "| Open longer than #{window_days} days | #{aging.length} |"
lines << ""

if issues.empty?
  lines << "No beta feedback has been submitted yet."
  lines << ""
else
  lines << "## Product signals"
  lines << ""
  append_signal_table(lines, "Expected weekly use", REUSE_OPTIONS, issues, REUSE_HEADING)
  append_signal_table(lines, "One-time purchase intent", PURCHASE_OPTIONS, issues, PURCHASE_HEADING)

  lines << "## New reports"
  lines << ""
  if new_issues.empty?
    lines << "No new reports in the last #{window_days} days."
  else
    append_issue_list(lines, new_issues, server_url: server_url, repository: repository)
  end
  lines << ""

  lines << "## Open backlog"
  lines << ""
  if open_issues.empty?
    lines << "No open beta reports."
  else
    append_issue_list(lines, open_issues, server_url: server_url, repository: repository)
  end
  lines << ""

  lines << "## Attention"
  lines << ""
  if without_replies.empty? && aging.empty?
    lines << "No open report is unanswered or older than #{window_days} days."
  else
    unless without_replies.empty?
      lines << "### No replies yet"
      lines << ""
      append_issue_list(lines, without_replies, server_url: server_url, repository: repository)
      lines << ""
    end
    unless aging.empty?
      lines << "### Open longer than #{window_days} days"
      lines << ""
      append_issue_list(lines, aging, server_url: server_url, repository: repository)
      lines << ""
    end
  end
end

lines << "## Human decision"
lines << ""
lines << "Use this report to choose the next investigation. The automation does not prioritize, close, reply to, or modify feedback."
lines << ""

puts lines.join("\n")
