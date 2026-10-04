# frozen_string_literal: true

require "yaml"
require_relative "copy"

module QaReport
  # The {stem}.md note: fixed front matter and a short body, with no clock reads so a rebuild is byte-identical.
  class Markdown
    ISSUE_STATUSES = [Source::OPEN, Source::DEFERRED].freeze

    def initialize(source, config:, stem:, client_status:, files:, client_file: nil)
      @source = source
      @config = config
      @stem = stem
      @client_status = client_status
      @files = files
      @client_file = client_file
      @copy = Copy.new(source)
    end

    def to_s = "---\n#{YAML.dump(front_matter).delete_prefix("---\n")}---\n\n#{body}\n"

    private

    def data = @source.data

    def front_matter
      {
        "title" => data["feature_title_plain"], "date" => data["tested_on"], "card" => data["card"],
        "project" => data["project_plain"], "verdict" => @source.verdict, "verdict_overridden" => !@source.override.nil?,
        "client" => (@config.client if @config.client_variant?), "variants" => @config.variants,
        "client_status" => @client_status, "source" => "#{@stem}.qa.yml", "source_sha256" => @source.sha256,
        "schema_version" => data["schema_version"], "files" => @files,
        "tags" => ["qa-report", "verdict/#{@source.verdict.downcase.tr(" ", "-")}"]
      }
    end

    def body
      [["# QA report: #{data["feature_title_plain"]}", "**#{@source.verdict}**. #{@copy.explainer}", stat_line,
        links, section("Open and known issues", issue_lines), section("Notes", note_lines)]].flatten.join("\n\n")
    end

    def stat_line
      stats = @copy.stats
      "#{stats[:requirements][0]} requirements met · #{stats[:journeys][0]} journeys passed · " \
        "#{stats[:open_issues][0]} open issues"
    end

    def links
      reports = [["Internal report", "#{@stem}-internal"]]
      reports << ["Client report", File.basename(@client_file, ".html")] if @client_file
      lines = reports.map { |label, base| "- [#{label} (HTML)](#{base}.html)" }
      "## Reports\n\n#{lines.join("\n")}"
    end

    def issue_lines
      @source.ordered_issues.select { |issue| ISSUE_STATUSES.include?(issue["status"]) }
             .map { |issue| "- #{issue["id"]} · #{issue["severity"]} · #{issue["title_plain"]}" }
    end

    def note_lines = @source.notes.select { |note| note["client_facing"] == true }.map { |note| "- #{note["title_plain"]}" }

    def section(heading, lines) = lines.empty? ? [] : "## #{heading}\n\n#{lines.join("\n")}"
  end
end
