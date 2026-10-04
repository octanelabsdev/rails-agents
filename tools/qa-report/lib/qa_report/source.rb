# frozen_string_literal: true

require "date"
require "digest"
require "yaml"

module QaReport
  class Error < StandardError
    SUMMARY = "QA report problems."
    EXIT_CODE = 1

    attr_reader :problems

    def initialize(problems)
      @problems = problems.freeze
      super("#{self.class::SUMMARY}\n#{problems.map { |problem| "  - #{problem}" }.join("\n")}")
    end

    def exit_code = self.class::EXIT_CODE
  end

  class InvalidSource < Error
    SUMMARY = "Invalid QA source; nothing was produced."
  end

  class ClientBlocked < Error
    SUMMARY = "Client view blocked; the internal view is still produced."
    EXIT_CODE = 2
  end

  # A parsed, validated QA source. Every key is classed :client or :internal and typed; anything else is rejected.
  class Source
    Field = Struct.new(:klass, :type, :required)

    def self.client(type, optional: false) = Field.new(:client, type, !optional).freeze
    def self.internal(type, optional: false) = Field.new(:internal, type, !optional).freeze

    IDS = [:list, :id].freeze
    TEXTS = [:list, :text].freeze

    SCHEMA = {
      top: {
        "schema_version" => internal(:id), "card" => internal(:id),
        "feature_title_plain" => client(:text), "project_plain" => client(:text),
        "tested_on" => client(:date), "status_as_of" => client(:date, optional: true),
        "environment_label" => client(:text), "build_plain" => client(:text),
        "summary" => client([:shape, :summary]), "how_we_tested_plain" => client(:text),
        "requirements" => client([:list, :requirement]), "coverage" => client([:shape, :coverage]),
        "journeys" => client([:list, :journey]), "issues" => client([:list, :issue]),
        "notes" => client([:list, :note]), "screenshots" => client([:list, :screenshot]),
        "verdict_override" => internal([:shape, :verdict_override], optional: true),
        "internal" => internal([:shape, :internal])
      },
      summary: %w[lead tested found means next].to_h { |key| [key, client(:text)] },
      requirement: {
        "id" => client(:id), "text_plain" => client(:text), "result" => client(:text), "journeys" => client(IDS)
      },
      coverage: { "columns" => client(TEXTS), "rows" => client([:list, :coverage_row]) },
      coverage_row: { "area_plain" => client(:text), "cells" => client(TEXTS) },
      journey: {
        "id" => client(:id), "title_plain" => client(:text), "description_plain" => client(:text),
        "result" => client(:text), "evidence" => client(IDS),
        "evidence_note_plain" => client(:text, optional: true),
        "technical_detail" => internal(:text, optional: true)
      },
      issue: {
        "id" => client(:id), "severity" => client(:text), "status" => client(:text),
        "title_plain" => client(:text), "impact_plain" => client(:text), "steps_plain" => client(TEXTS),
        "expected_plain" => client(:text), "actual_plain" => client(:text),
        "screenshot" => client(:id, optional: true), "fixed_in" => client(TEXTS, optional: true),
        "retested_on" => client(:date, optional: true), "status_reason_plain" => client(:text, optional: true),
        "root_cause" => internal(:text, optional: true)
      },
      note: {
        "id" => client(:id), "title_plain" => client(:text), "body_plain" => client(:text),
        "recommendation_plain" => client(:text, optional: true),
        "coverage_column" => client(:text, optional: true),
        "client_facing" => internal(:bool, optional: true)
      },
      screenshot: {
        "id" => client(:id), "file" => client(:text), "group_plain" => client(:text),
        "variant" => client(:text), "caption" => client(:text),
        "alt" => client(:text, optional: true), "focal" => client(:text, optional: true),
        "dpr" => client(:positive_integer, optional: true),
        "visibility" => internal(:text, optional: true), "pixels_clean" => internal(:bool, optional: true),
        "internal_reason" => internal(:text, optional: true)
      },
      verdict_override: { "verdict" => internal(:text), "reason" => internal(:text, optional: true) },
      internal: {
        "environment" => internal(:text, optional: true), "process_notes" => internal(TEXTS, optional: true),
        "cleanup" => internal(:text, optional: true), "sources" => internal(:text, optional: true)
      }
    }.freeze

    SCALARS = {
      text: [->(value) { value.is_a?(String) }, "text"],
      id: [->(value) { value.is_a?(String) || value.is_a?(Integer) }, "an id"],
      date: [->(value) { value.is_a?(Date) }, "a date"],
      bool: [->(value) { [true, false].include?(value) }, "true or false"],
      positive_integer: [->(value) { value.is_a?(Integer) && value.positive? }, "a positive whole number"]
    }.freeze

    SEVERITIES = %w[BLOCKER MAJOR MINOR TRIVIAL].freeze
    OPEN = "OPEN"
    FIXED_UNVERIFIED = "FIXED · NOT YET RE-TESTED"
    FIXED_VERIFIED = "FIXED & VERIFIED"
    DEFERRED = "DEFERRED"
    WONT_FIX = "WON'T FIX"
    STATUSES = [OPEN, FIXED_VERIFIED, FIXED_UNVERIFIED, DEFERRED, WONT_FIX].freeze
    REQUIREMENT_RESULTS = ["MET", "NOT MET", "BLOCKED"].freeze
    JOURNEY_RESULTS = ["PASS", "FAIL", "BLOCKED", "OBSERVED", "NOT TESTED"].freeze
    VERDICTS = ["PASS", "PASS WITH NOTES", "FAIL"].freeze
    ENUMS = {
      "requirements" => { "result" => REQUIREMENT_RESULTS },
      "journeys" => { "result" => JOURNEY_RESULTS },
      "issues" => { "severity" => SEVERITIES, "status" => STATUSES }
    }.freeze

    PLACEHOLDER_MESSAGE = "is not a key in the schema (owner decision 6: no placeholder screenshots " \
                          "in either variant; retake the capture)"
    PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b
    JPEG_SIGNATURE = "\xFF\xD8\xFF".b
    HEADER_BYTES = 12
    PNG_MIN_BYTES = 24
    WEBP_MIN_BYTES = 30

    attr_reader :data, :root, :sha256

    def self.load(path)
      new(YAML.safe_load_file(path, permitted_classes: [Date]), root: File.dirname(path),
          sha256: Digest::SHA256.file(path).hexdigest)
    rescue SystemCallError, Psych::Exception => e
      raise InvalidSource, ["(file) #{path}: #{e.message}"]
    end

    # The one rule that turns an authored id into a DOM id; the renderer uses it too, so the two cannot drift.
    def self.slug(id) = id.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|-\z/, "")

    def self.blank?(value) = value.nil? || (value.respond_to?(:empty?) && value.empty?) || (value.is_a?(String) && value.strip.empty?)

    def self.client_keys(kind) = SCHEMA.fetch(kind).select { |_, field| field.klass == :client }.keys

    def self.label(collection, item, index)
      id = item["id"] if item.is_a?(Hash)
      "#{collection}[#{id.is_a?(String) || id.is_a?(Integer) ? id : index}]"
    end

    def initialize(data, root:, sha256: nil)
      @data = without_blank_optionals(data)
      @root = File.expand_path(root)
      @sha256 = sha256
      problems = validate
      raise InvalidSource, problems unless problems.empty?
    end

    %w[requirements journeys issues notes screenshots].each do |name|
      define_method(name) { @data.fetch(name) }
    end

    def verdict = override ? override["verdict"] : computed_verdict

    def override = @data["verdict_override"]

    def computed_verdict
      return "FAIL" if failing?

      noteworthy? ? "PASS WITH NOTES" : "PASS"
    end

    def open_issue_count = issues.count { |issue| issue["status"] == OPEN }

    def counts
      {
        requirements_met: requirements.count { |item| item["result"] == "MET" },
        requirements_total: requirements.size,
        journeys_passed: journeys.count { |item| item["result"] == "PASS" },
        journeys_total: journeys.size,
        issues_open: open_issue_count,
        issues_found: issues.size,
        issues_fixed: issues.count { |issue| [FIXED_VERIFIED, FIXED_UNVERIFIED].include?(issue["status"]) }
      }
    end

    # sort_by is not stable in Ruby, so the authored index is the final tiebreak.
    def ordered_issues
      issues.sort_by.with_index do |issue, index|
        [SEVERITIES.index(issue["severity"]), issue["status"] == OPEN ? 0 : 1, index]
      end
    end

    def screenshot_path(shot) = File.expand_path(shot["file"], @root)

    # Everything the client file must never repeat: internal-classed fields plus the client-classed text of internal-only records.
    def internal_texts
      texts = schema_texts(:top, @data)
      texts += screenshots.reject { |shot| shot["visibility"] == "client" }.flat_map { |shot| shot.values_at("caption", "alt").compact }
      texts + notes.reject { |note| note["client_facing"] == true }.flat_map { |note| strings(note) }
    end

    private

    def schema_texts(kind, hash)
      SCHEMA.fetch(kind).flat_map do |key, field|
        value = hash[key]
        next [] if value.nil?

        field.klass == :internal ? strings(value) : nested_texts(field.type, value)
      end
    end

    def nested_texts(type, value)
      kind, item_kind = type
      return schema_texts(item_kind, value) if kind == :shape
      return [] unless kind == :list && SCHEMA.key?(item_kind)

      value.flat_map { |item| schema_texts(item_kind, item) }
    end

    def strings(value)
      case value
      when Hash then value.values.flat_map { |child| strings(child) }
      when Array then value.flat_map { |child| strings(child) }
      when String then [value]
      when Integer then [value.to_s]
      else []
      end
    end

    def failing?
      requirements.any? { |item| item["result"] != "MET" } ||
        issues.any? { |issue| %w[BLOCKER MAJOR].include?(issue["severity"]) && unresolved?(issue) }
    end

    def noteworthy?
      issues.any? { |issue| unresolved?(issue) || issue["status"] == "DEFERRED" } ||
        notes.any? { |note| note["client_facing"] == true }
    end

    def unresolved?(issue) = [OPEN, FIXED_UNVERIFIED].include?(issue["status"])

    # The skeleton leaves optional keys blank or empty; those mean absent, so they are dropped before any check or render.
    def without_blank_optionals(data)
      return data unless data.is_a?(Hash)

      data.reject do |key, value|
        field = SCHEMA[:top][key]
        field && !field.required && Source.blank?(value)
      end
    end

    # Shape problems come first: the semantic checks assume every value already has its declared type.
    def validate
      problems = check_shape(@data, :top, "")
      return problems unless problems.empty?

      [check_requirements_present, check_enums, check_override, check_duplicate_ids, check_references,
       check_failing_journeys, check_visibility, check_status_reasons, check_note_columns, check_internal_reasons,
       check_images].flatten
    end

    def check_shape(hash, kind, path)
      return ["#{path.empty? ? "(source)" : path} must be a mapping of keys"] unless hash.is_a?(Hash)

      schema = SCHEMA.fetch(kind)
      known = schema.slice(*hash.keys)
      unknown_keys(hash.keys - schema.keys, path) + missing_keys(schema, hash, path) +
        known.flat_map { |key, field| check_value(hash[key], field.type, field_path(path, key)) }
    end

    def unknown_keys(keys, path)
      keys.map do |key|
        field = field_path(path, key)
        key == "placeholder" ? "#{field} #{PLACEHOLDER_MESSAGE}" : "#{field} is not a key in the schema"
      end
    end

    def missing_keys(schema, hash, path)
      schema.filter_map { |key, field| "#{field_path(path, key)} is required" if field.required && !hash.key?(key) }
    end

    def field_path(path, key) = path.empty? ? key.to_s : "#{path}.#{key}"

    # Messages name the expected type, never the offending value, so a smuggled value is not echoed.
    def check_value(value, type, path)
      kind, item_type = type
      case kind
      when :shape then check_shape(value, item_type, path)
      when :list then check_list(value, item_type, path)
      else
        valid, description = SCALARS.fetch(kind)
        valid.call(value) ? [] : ["#{path} must be #{description}"]
      end
    end

    def check_list(value, item_type, path)
      return ["#{path} must be a list"] unless value.is_a?(Array)

      type = SCHEMA.key?(item_type) ? [:shape, item_type] : item_type
      value.each_with_index.flat_map { |item, index| check_value(item, type, Source.label(path, item, index)) }
    end

    def check_requirements_present = requirements.empty? ? ["requirements must not be empty"] : []

    def check_enums
      ENUMS.flat_map do |name, rules|
        @data[name].each_with_index.flat_map do |item, index|
          rules.filter_map do |key, allowed|
            next if allowed.include?(item[key])

            "#{Source.label(name, item, index)}.#{key} must be one of #{allowed.join(", ")}"
          end
        end
      end
    end

    def check_override
      return [] if override.nil? || VERDICTS.include?(override["verdict"])

      ["verdict_override.verdict must be one of #{VERDICTS.join(", ")}"]
    end

    def check_duplicate_ids
      %w[requirements journeys issues notes screenshots].flat_map do |name|
        slugs = @data[name].map { |item| Source.slug(item["id"]) }
        @data[name].each_with_index.filter_map do |item, index|
          label = Source.label(name, item, index)
          if slugs[index].empty?
            "#{label}.id must contain a letter or digit"
          elsif slugs.count(slugs[index]) > 1
            "#{label}.id duplicates another id once made into a page anchor"
          end
        end
      end
    end

    def check_references
      shot_ids = screenshots.map { |shot| shot["id"] }
      journey_ids = journeys.map { |journey| journey["id"] }
      [["journeys", "evidence", shot_ids], ["requirements", "journeys", journey_ids],
       ["issues", "screenshot", shot_ids]].flat_map do |name, key, known|
        @data[name].each_with_index.filter_map do |item, index|
          next unless item.key?(key) && ([item[key]].flatten - known).any?

          "#{Source.label(name, item, index)}.#{key} names ids that do not exist"
        end
      end
    end

    def check_failing_journeys
      unmet = requirements.reject { |item| item["result"] == "MET" }.flat_map { |item| item["journeys"] }
      journeys.each_with_index.filter_map do |journey, index|
        next unless %w[FAIL BLOCKED].include?(journey["result"]) && !unmet.include?(journey["id"])

        "#{Source.label("journeys", journey, index)}.result: a failing journey must trace to an unmet requirement"
      end
    end

    # A missing or mistyped value would drop the screenshot from both the body and the appendix.
    def check_visibility
      screenshots.each_with_index.filter_map do |shot, index|
        next if %w[client internal].include?(shot["visibility"])

        "#{Source.label("screenshots", shot, index)}.visibility must be client or internal"
      end
    end

    def check_status_reasons
      issues.each_with_index.filter_map do |issue, index|
        next unless issue["status"] == WONT_FIX && issue["status_reason_plain"].to_s.strip.empty?

        "#{Source.label("issues", issue, index)}.status_reason_plain is required when the status is #{WONT_FIX}"
      end
    end

    def check_note_columns
      columns = @data["coverage"]["columns"]
      notes.each_with_index.filter_map do |note, index|
        next if !note.key?("coverage_column") || columns.include?(note["coverage_column"])

        "#{Source.label("notes", note, index)}.coverage_column must be one of the coverage columns"
      end
    end

    def check_internal_reasons
      screenshots.each_with_index.filter_map do |shot, index|
        next unless shot["visibility"] == "internal" && shot["internal_reason"].to_s.strip.empty?

        "#{Source.label("screenshots", shot, index)}.internal_reason is required when visibility is internal"
      end
    end

    def check_images
      screenshots.each_with_index.filter_map do |shot, index|
        image_problem(shot, Source.label("screenshots", shot, index))
      end
    end

    def image_problem(shot, path)
      file = contained_file(shot["file"])
      return "#{path}.file must be an existing file inside the source folder" unless file

      header = File.binread(file, HEADER_BYTES).to_s
      return "#{path}.file is too small to be an image" if header.bytesize < HEADER_BYTES
      # The width sits at byte 16..19, so a shorter PNG cannot be sized.
      return "#{path}.file is too small to be a PNG" if header.start_with?(PNG_SIGNATURE) && File.size(file) < PNG_MIN_BYTES

      return "#{path}.file is not a PNG, JPEG or WebP image" unless image?(header)

      # VP8 width is read at byte 26..27, VP8L at 21..24, VP8X at 24..26.
      "#{path}.file is too small to be a WebP" if header.byteslice(0, 4) == "RIFF" && File.size(file) < WEBP_MIN_BYTES
    end

    # realpath, not the path text, so a symlink pointing outside the folder is caught.
    def contained_file(name)
      return if name.start_with?("/")

      real = File.realpath(File.expand_path(name, @root))
      real if real.start_with?("#{File.realpath(@root)}/") && File.file?(real)
    rescue SystemCallError, ArgumentError # ArgumentError: NUL byte or unknown ~user in the path
      nil
    end

    def image?(header)
      header.start_with?(PNG_SIGNATURE, JPEG_SIGNATURE) ||
        (header.byteslice(0, 4) == "RIFF" && header.byteslice(8, 4) == "WEBP")
    end
  end
end
