# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"

class BetaFeedbackReportTest < Minitest::Test
  SCRIPT = File.expand_path("../beta_feedback_report.rb", __dir__)
  NOW = "2026-08-13T00:00:00Z"

  def test_summarizes_feedback_and_sanitizes_public_text
    issues = [
      issue(
        number: 12,
        title: "Foreground <script>alert(1)</script> [break](https://bad.test)",
        state: "open",
        created_at: "2026-08-12T05:00:00Z",
        comments: 0,
        reuse: "Yes, most days",
        purchase: "Yes"
      ),
      issue(
        number: 9,
        title: "Older layout report",
        state: "open",
        created_at: "2026-08-01T05:00:00Z",
        comments: 2,
        reuse: "Occasionally",
        purchase: "Maybe"
      ),
      issue(
        number: 7,
        title: "Resolved installation report",
        state: "closed",
        created_at: "2026-07-30T05:00:00Z",
        closed_at: "2026-08-09T05:00:00Z",
        comments: 3,
        reuse: "Not yet",
        purchase: "No"
      ),
      issue(
        number: 6,
        title: "Pull request returned by the issues endpoint",
        state: "open",
        created_at: "2026-08-12T05:00:00Z",
        comments: 0,
        reuse: "Yes, most days",
        purchase: "Yes",
        pull_request: { "url" => "https://api.github.com/repos/xicv/easplit/pulls/6" }
      )
    ]

    stdout, stderr, status = render(issues)

    assert_predicate status, :success?, stderr
    assert_includes stdout, "# eaSplit weekly beta report"
    assert_includes stdout, "New reports | 1"
    assert_includes stdout, "Open reports | 2"
    assert_includes stdout, "Closed this week | 1"
    assert_includes stdout, "Open with no replies | 1"
    assert_includes stdout, "Open longer than 7 days | 1"
    assert_includes stdout, "Yes, most days | 1"
    assert_includes stdout, "Occasionally | 1"
    assert_includes stdout, "Not yet | 1"
    assert_includes stdout, "Yes | 1"
    assert_includes stdout, "Maybe | 1"
    assert_includes stdout, "No | 1"
    assert_includes stdout, "https://github.com/xicv/easplit/issues/12"
    assert_includes stdout, "#12"
    refute_includes stdout, "<script>"
    refute_includes stdout, "https://bad.test"
    refute_includes stdout, "pulls/6"
  end

  def test_handles_an_empty_feedback_inbox
    stdout, stderr, status = render([])

    assert_predicate status, :success?, stderr
    assert_includes stdout, "No beta feedback has been submitted yet."
    assert_includes stdout, "New reports | 0"
    assert_includes stdout, "Open reports | 0"
  end

  def test_rejects_invalid_json
    _stdout, stderr, status = Open3.capture3(
      report_environment,
      RbConfig.ruby,
      SCRIPT,
      stdin_data: "not-json"
    )

    refute_predicate status, :success?
    assert_includes stderr, "Unable to read beta feedback JSON"
  end

  private

  def render(issues)
    Open3.capture3(
      report_environment,
      RbConfig.ruby,
      SCRIPT,
      stdin_data: JSON.generate(issues)
    )
  end

  def report_environment
    {
      "REPORT_NOW" => NOW,
      "GITHUB_SERVER_URL" => "https://github.com",
      "GITHUB_REPOSITORY" => "xicv/easplit",
    }
  end

  def issue(number:, title:, state:, created_at:, comments:, reuse:, purchase:, closed_at: nil, pull_request: nil)
    {
      "number" => number,
      "title" => title,
      "state" => state,
      "created_at" => created_at,
      "updated_at" => created_at,
      "closed_at" => closed_at,
      "comments" => comments,
      "body" => <<~BODY,
        ### Would you use eaSplit in a normal week?

        #{reuse}

        ### Would a polished version be worth a one-time purchase?

        #{purchase}
      BODY
      "pull_request" => pull_request,
    }.compact
  end
end
