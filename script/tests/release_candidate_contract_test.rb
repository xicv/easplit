# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

class ReleaseCandidateContractTest < Minitest::Test
  SCRIPT = File.expand_path("../release_candidate_contract.rb", __dir__)
  SOURCE_COMMIT = "0123456789abcdef0123456789abcdef01234567"

  def setup
    @root = Dir.mktmpdir("easplit-release-contract")
    FileUtils.mkdir_p(File.join(@root, "docs/releases"))
    write_project(version: "0.2.0", build: 5)
    write_notes("0.2.0-beta.5")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_returns_the_exact_release_identity
    stdout, stderr, status = run_contract("0.2.0-beta.5", SOURCE_COMMIT)

    assert_predicate status, :success?, stderr
    contract = JSON.parse(stdout)
    assert_equal "0.2.0-beta.5", contract.fetch("releaseLabel")
    assert_equal "v0.2.0-beta.5", contract.fetch("tagName")
    assert_equal "0.2.0", contract.fetch("bundleVersion")
    assert_equal 5, contract.fetch("buildNumber")
    assert_equal SOURCE_COMMIT, contract.fetch("sourceCommit")
    assert_equal File.join(@root, "docs/releases/0.2.0-beta.5.md"), contract.fetch("releaseNotesPath")
  end

  def test_rejects_a_beta_number_that_does_not_match_the_build
    write_notes("0.2.0-beta.6")

    _stdout, stderr, status = run_contract("0.2.0-beta.6", SOURCE_COMMIT)

    refute_predicate status, :success?
    assert_includes stderr, "beta number 6 must match build number 5"
  end

  def test_rejects_missing_or_placeholder_release_notes
    File.write(File.join(@root, "docs/releases/0.2.0-beta.5.md"), "TBD\n")

    _stdout, stderr, status = run_contract("0.2.0-beta.5", SOURCE_COMMIT)

    refute_predicate status, :success?
    assert_includes stderr, "release notes contain a placeholder"
  end

  def test_rejects_a_non_exact_source_commit
    _stdout, stderr, status = run_contract("0.2.0-beta.5", "main")

    refute_predicate status, :success?
    assert_includes stderr, "source commit must be a full 40-character lowercase SHA"
  end

  def test_rejects_a_label_for_a_different_marketing_version
    write_notes("0.3.0-beta.5")

    _stdout, stderr, status = run_contract("0.3.0-beta.5", SOURCE_COMMIT)

    refute_predicate status, :success?
    assert_includes stderr, "release version 0.3.0 must match MARKETING_VERSION 0.2.0"
  end

  private

  def run_contract(label, source_commit)
    Open3.capture3(
      { "EASPLIT_ROOT" => @root },
      RbConfig.ruby,
      SCRIPT,
      label,
      source_commit
    )
  end

  def write_project(version:, build:)
    File.write(
      File.join(@root, "project.yml"),
      <<~YAML
        targets:
          eaSplit:
            settings:
              base:
                MARKETING_VERSION: #{version}
                CURRENT_PROJECT_VERSION: #{build}
      YAML
    )
  end

  def write_notes(label)
    File.write(
      File.join(@root, "docs/releases/#{label}.md"),
      "eaSplit #{label}\n\n- Verified release notes.\n"
    )
  end
end
