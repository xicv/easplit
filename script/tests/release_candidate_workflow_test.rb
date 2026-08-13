# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"

class ReleaseCandidateWorkflowTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)
  WORKFLOW_PATH = File.join(ROOT, ".github/workflows/release-candidate.yml")
  DRAFT_SCRIPT = File.join(ROOT, "script/draft_github_release.sh")
  CREDENTIAL_SCRIPT = File.join(ROOT, "script/prepare_ci_release_credentials.sh")
  RELEASE_SCRIPT = File.join(ROOT, "script/release.sh")
  DMG_SCRIPT = File.join(ROOT, "script/package_dmg.sh")
  CI_EXPORT_OPTIONS = File.join(ROOT, "script/ExportOptionsCI.plist")
  GITIGNORE = File.join(ROOT, ".gitignore")

  REQUIRED_SECRETS = %w[
    EASPLIT_DEVELOPER_ID_P12_BASE64
    EASPLIT_DEVELOPER_ID_P12_PASSWORD
    EASPLIT_NOTARY_KEY_P8_BASE64
    EASPLIT_NOTARY_KEY_ID
    EASPLIT_NOTARY_ISSUER_ID
  ].freeze

  def test_workflow_is_manual_exact_commit_and_draft_only
    workflow = File.read(WORKFLOW_PATH)
    trigger_block = workflow[/^on:\n(?<body>(?:^  .*\n?)*)/, :body]

    assert_includes trigger_block, "workflow_dispatch:"
    refute_match(/^  (push|pull_request|schedule):/, trigger_block)
    assert_includes workflow, "source_commit:"
    assert_includes workflow, "confirm_unpublished_draft:"
    assert_includes workflow, '$GITHUB_SHA'
    assert_includes workflow, "git ls-remote origin refs/heads/main"
    assert_includes workflow, "environment: release-candidate"
    assert_includes workflow, "contents: write"
    assert_includes workflow, "./script/draft_github_release.sh"
    refute_includes workflow, "publish_github_release.sh"
    REQUIRED_SECRETS.each { |name| assert_includes workflow, "secrets.#{name}" }
  end

  def test_draft_script_cannot_push_or_publish
    script = File.read(DRAFT_SCRIPT)

    assert_includes script, "--draft"
    assert_includes script, "--prerelease"
    assert_includes script, "--latest=false"
    assert_includes script, '--target "$SOURCE_COMMIT"'
    refute_match(/\bgit\s+push\b/, script)
    refute_includes script, "--verify-tag"
  end

  def test_ci_credential_setup_fails_before_mutation_when_secrets_are_missing
    environment = REQUIRED_SECRETS.to_h { |name| [name, ""] }
    Dir.mktmpdir("easplit-credential-test") do |directory|
      keychain = File.join(directory, "release.keychain-db")
      _stdout, stderr, status = Open3.capture3(
        environment,
        "/bin/bash",
        CREDENTIAL_SCRIPT,
        keychain
      )

      refute_predicate status, :success?
      REQUIRED_SECRETS.each { |name| assert_includes stderr, name }
      assert_includes stderr, "Release credentials are incomplete"
      refute File.exist?(keychain), "credential preflight must not create a keychain"
    end
  end

  def test_release_scripts_support_an_isolated_output_and_notary_keychain
    release_script = File.read(RELEASE_SCRIPT)
    dmg_script = File.read(DMG_SCRIPT)

    assert_includes release_script, "EASPLIT_RELEASE_DIR"
    assert_includes release_script, "EASPLIT_NOTARY_KEYCHAIN"
    assert_includes dmg_script, "EASPLIT_NOTARY_KEYCHAIN"
    assert_includes release_script, "EASPLIT_EXPORT_OPTIONS"
    assert_match(/<key>signingStyle<\/key>\s*<string>manual<\/string>/, File.read(CI_EXPORT_OPTIONS))
  end

  def test_private_release_credentials_are_ignored
    patterns = File.readlines(GITIGNORE, chomp: true)

    %w[*.keychain *.keychain-db *.p12 *.p8].each do |pattern|
      assert_includes patterns, pattern
    end
  end
end
