# frozen_string_literal: true

require "yaml"

ROOT = File.expand_path("../..", __dir__)
FORM_PATH = File.join(ROOT, ".github/ISSUE_TEMPLATE/beta-feedback.yml")

form = YAML.safe_load(File.read(FORM_PATH), aliases: false)
abort("Feedback form must be a YAML mapping") unless form.is_a?(Hash)
abort("Feedback form must apply the beta-feedback label") unless form.fetch("labels", []).include?("beta-feedback")

body = form.fetch("body")
abort("Feedback form body must be a non-empty list") unless body.is_a?(Array) && !body.empty?

fields = body.reject { |item| item["type"] == "markdown" }
ids = fields.map { |field| field["id"] }
abort("Every feedback field must have a string id") unless ids.all? { |id| id.is_a?(String) && !id.empty? }
abort("Feedback field ids must be unique") unless ids.uniq.length == ids.length

fields.select { |field| field["type"] == "dropdown" }.each do |field|
  options = field.dig("attributes", "options")
  abort("Dropdown #{field.fetch("id")} must have options") unless options.is_a?(Array) && !options.empty?
  abort("Dropdown #{field.fetch("id")} options must all be strings") unless options.all?(String)
end

privacy = fields.find { |field| field["id"] == "privacy" }
abort("Feedback form must include a privacy confirmation") unless privacy
privacy_options = privacy.dig("attributes", "options")
privacy_required = privacy_options.is_a?(Array) && privacy_options.any? do |option|
  option.is_a?(Hash) && option["required"] == true
end
abort("Feedback privacy confirmation must be required") unless privacy_required

puts "Beta feedback form contract passed."
