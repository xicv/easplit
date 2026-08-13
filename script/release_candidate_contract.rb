# frozen_string_literal: true

require "json"
require "yaml"

class ReleaseCandidateContract
  class ContractError < StandardError; end

  LABEL_PATTERN = /\A(?<version>\d+\.\d+\.\d+)-beta\.(?<beta>[1-9]\d*)\z/
  SHA_PATTERN = /\A[0-9a-f]{40}\z/
  PLACEHOLDER_PATTERN = /\b(?:TODO|TBD|PLACEHOLDER)\b/i

  def initialize(root:, release_label:, source_commit:)
    @root = File.expand_path(root)
    @release_label = release_label
    @source_commit = source_commit
  end

  def call
    validate_source_commit
    label_match = LABEL_PATTERN.match(@release_label)
    raise ContractError, "release label must use X.Y.Z-beta.N" unless label_match

    settings = project_settings
    version = settings.fetch("MARKETING_VERSION").to_s
    build = positive_integer(settings.fetch("CURRENT_PROJECT_VERSION"), "CURRENT_PROJECT_VERSION")
    label_version = label_match["version"]
    beta_number = label_match["beta"].to_i

    unless label_version == version
      raise ContractError,
            "release version #{label_version} must match MARKETING_VERSION #{version}"
    end
    unless beta_number == build
      raise ContractError, "beta number #{beta_number} must match build number #{build}"
    end

    notes_path = File.join(@root, "docs/releases/#{@release_label}.md")
    validate_release_notes(notes_path)

    {
      "releaseLabel" => @release_label,
      "tagName" => "v#{@release_label}",
      "bundleVersion" => version,
      "buildNumber" => build,
      "sourceCommit" => @source_commit,
      "releaseNotesPath" => notes_path,
    }
  end

  private

  def validate_source_commit
    return if SHA_PATTERN.match?(@source_commit)

    raise ContractError, "source commit must be a full 40-character lowercase SHA"
  end

  def project_settings
    project_path = File.join(@root, "project.yml")
    raise ContractError, "missing project specification: #{project_path}" unless File.file?(project_path)

    project = YAML.safe_load(File.read(project_path), aliases: false)
    project.fetch("targets").fetch("eaSplit").fetch("settings").fetch("base")
  rescue KeyError => error
    raise ContractError, "project.yml is missing #{error.key}"
  rescue Psych::Exception => error
    raise ContractError, "project.yml is invalid YAML: #{error.message}"
  end

  def positive_integer(value, name)
    number = Integer(value.to_s, 10)
    raise ContractError, "#{name} must be a positive integer" unless number.positive?

    number
  rescue ArgumentError, TypeError
    raise ContractError, "#{name} must be a positive integer"
  end

  def validate_release_notes(path)
    raise ContractError, "missing release notes: #{path}" unless File.file?(path)

    notes = File.read(path)
    raise ContractError, "release notes are empty: #{path}" if notes.strip.empty?
    raise ContractError, "release notes contain a placeholder: #{path}" if PLACEHOLDER_PATTERN.match?(notes)
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    unless ARGV.length == 2
      warn "usage: #{$PROGRAM_NAME} RELEASE_LABEL SOURCE_COMMIT"
      exit 2
    end

    root = ENV.fetch("EASPLIT_ROOT", File.expand_path("..", __dir__))
    contract = ReleaseCandidateContract.new(
      root: root,
      release_label: ARGV.fetch(0),
      source_commit: ARGV.fetch(1)
    ).call
    puts JSON.generate(contract)
  rescue ReleaseCandidateContract::ContractError => error
    warn "Release candidate contract failed: #{error.message}"
    exit 1
  end
end
