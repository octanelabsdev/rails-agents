# frozen_string_literal: true

require "yaml"
require_relative "source"
require_relative "brand"

module QaReport
  class ConfigError < Error
    SUMMARY = "Invalid qa-report.yml."
  end

  # Per-project settings, found by walking up from a source to the nearest qa-report.yml.
  class Config
    FILE = "qa-report.yml"
    VARIANTS = %w[internal client].freeze
    PROBE = "Ab cd, e-f. (g) 0 1_2 abcdefghijklmnopqrstuvwxyz ABC"
    attr_reader :dir, :variants, :client, :paper, :deny

    # The scan and the config check must compile a pattern identically, or they disagree on what it matches.
    def self.deny_regexp(pattern) = Regexp.new(pattern.to_s, Regexp::IGNORECASE)

    def self.zero_width?(regexp)
      regexp.match?("") || PROBE.to_enum(:scan, regexp).any? { Regexp.last_match[0].empty? }
    end

    def self.find(start)
      dir = File.expand_path(start)
      dir = File.dirname(dir) unless File.directory?(dir)
      loop do
        path = File.join(dir, FILE)
        return load(path) if File.file?(path)

        parent = File.dirname(dir)
        raise ConfigError, ["no #{FILE} found in or above #{start}"] if parent == dir

        dir = parent
      end
    end

    def self.load(path)
      data = YAML.safe_load_file(path) || {}
      raise ConfigError, ["#{path} must be a mapping of keys"] unless data.is_a?(Hash)

      new(data, File.dirname(path))
    rescue SystemCallError, Psych::Exception => e
      raise ConfigError, ["#{path}: #{e.message}"]
    end

    def initialize(data, dir)
      @dir = dir
      @brand_path = data["brand"] && File.expand_path(data["brand"].to_s, dir)
      @variants = data.fetch("variants", ["internal"])
      @client = data["client"]
      @paper = data.fetch("paper", "letter")
      @deny = data.fetch("deny", [])
      problems = validate
      raise ConfigError, problems unless problems.empty?
    end

    def client_variant? = variants.include?("client")

    # Separate from load so tooling that only reads the project (not builds) can still open a config with a bad pattern.
    def check_usable!
      problems = unmatchable_deny + empty_matching_deny
      raise ConfigError, problems unless problems.empty?
    end

    def brand
      @brand ||= @brand_path ? Brand.load(@brand_path) : Brand.default
    rescue ArgumentError => e
      raise ConfigError, [e.message]
    end

    private

    def validate
      problems = []
      problems << "variants must be a list of #{VARIANTS.join(" and ")}" unless variants.is_a?(Array) && (variants - VARIANTS).empty? && variants.any?
      problems << "client is required when variants includes client" if client_variant_listed? && client.to_s.strip.empty?
      problems.concat(deny_problems)
    end

    def deny_problems
      return ["deny must be a list of strings or {pattern:} entries"] unless deny.is_a?(Array)

      deny.filter_map { |entry| deny_problem(entry) }
    end

    def deny_problem(entry)
      return if entry.is_a?(String)
      return "deny must be a list of strings or {pattern:} entries" unless entry.is_a?(Hash) && entry.key?("pattern")

      self.class.deny_regexp(entry["pattern"])
      nil
    rescue RegexpError, TypeError => e
      "deny pattern #{entry["pattern"].to_s.inspect} is not a valid regex: #{e.message}"
    end

    # Checked at build time rather than load, so tooling that only reads the project can still open the config.
    def unmatchable_deny
      return [] unless deny.is_a?(Array)

      deny.filter_map { |entry| unmatchable_problem(entry["pattern"].to_s) if entry.is_a?(Hash) && entry.key?("pattern") && valid_deny?(entry) }
    end

    # The scan matches one normalised line of text, so these patterns can never match what the operator meant.
    def unmatchable_problem(pattern)
      require_relative "leak_check"
      return "deny pattern #{pattern.inspect} can never match: it uses an anchor, a newline, a carriage return or a tab" if bare_anchor_or_whitespace?(pattern)
      return "deny pattern #{pattern.inspect} can never match: it escapes a character the scan rewrites" if escaped_folded?(pattern)
      return unless LeakCheck.normalize(pattern) != pattern

      "deny pattern #{pattern.inspect} can never match: the scan rewrites characters in it (such as a non-breaking space or a full-width letter)"
    end

    # An escaped \\u or \\x character is rewritten by the scan just like a literal one, so decode the source and test it.
    def escaped_folded?(pattern)
      decoded = pattern.gsub(/\\u\{([\h ]+)\}|\\u(\h{4})/) { ($1 || $2).split.map { |hex| [hex.hex].pack("U") }.join }
                       .gsub(/(?:\\x\h\h)+/) { |bytes| bytes.scan(/\h\h/).map(&:hex).pack("C*").force_encoding("UTF-8") }
      decoded.valid_encoding? && decoded.each_char.any? { |char| LeakCheck.normalize(char) != char }
    end

    # A ^ or $ inside a character class or after a backslash is a plain character, so only a bare one is an anchor.
    def bare_anchor_or_whitespace?(pattern)
      return true if pattern.match?(/[\n\r\t]/)

      escaped = in_class = false
      pattern.each_char do |char|
        if escaped
          return true if "nrt".include?(char)

          escaped = false
        elsif char == "\\" then escaped = true
        elsif in_class then in_class = false if char == "]"
        elsif char == "[" then in_class = true
        elsif "^$".include?(char) then return true
        end
      end
      false
    end

    def client_variant_listed? = variants.is_a?(Array) && variants.include?("client")

    # A zero-length match would flag every position of the page, so it blocks every client file.
    def empty_matching_deny
      return [] unless deny.is_a?(Array)

      deny.filter_map do |entry|
        next unless entry.is_a?(Hash) && valid_deny?(entry)

        pattern = entry["pattern"]
        "deny pattern #{pattern.inspect} matches the empty string; make it match real text" if self.class.zero_width?(self.class.deny_regexp(pattern))
      end
    end

    def valid_deny?(entry)
      return entry.is_a?(String) unless entry.is_a?(Hash)

      self.class.deny_regexp(entry.fetch("pattern")) && true
    rescue KeyError, RegexpError, TypeError
      false
    end
  end
end
