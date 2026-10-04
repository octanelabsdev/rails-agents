# frozen_string_literal: true

require "cgi/escape"
require_relative "source"
require_relative "config"

module QaReport
  # Scans a client file's text, attributes, title and file name for anything internal before it is written.
  class LeakCheck
    BUILT_IN = [
      %r{/Users/}i, /Obsidian Vault/i, %r{file://}i, /localhost/i, /127\.0\.0\.1/, /\b[\w-]+\.(?:test|local|internal)\b/i,
      /ApiToken/i, /Fizzy/i, /\.rb:\d+/i, %r{app/(?:models|controllers|views|components|services)/}i,
      %r{bin/rails}i, %r{db/schema}i
    ].freeze
    CONTEXT = 40
    MIN_TOKEN = 4
    # A hex token is public only when the client's own build or fixed-in text carries that exact token.
    COMMIT_HASH = /\A(?=.*\d)(?=.*[a-f])\h{7,40}\z/i

    # Chunks are runs of identifier characters, so quotes and brackets fall away.
    CHUNK = %r{[\w.@/:#-]+}
    # A chunk is an identifier if it has a digit, punctuation, CamelCase or an ALL-CAPS-ID shape.
    IDENTIFIER = %r{[\d.@/#_]|::|[a-z][A-Z]|\A[A-Z]+(?:-[A-Z0-9]+)+\z}
    URL_HOST = %r{\A\w+://([^/:?#]+)}

    # The one normaliser: matching catches accidental leaks, so folding width, invisibles, dashes, quotes and spacing is enough.
    def self.normalize(text)
      text.gsub(/\p{Cf}/, "").unicode_normalize(:nfkc).gsub(/[\p{Pd}‑]/, "-").gsub(/[‘’ʼ′]/, "'").gsub(/[“”″]/, '"').gsub(/[[:space:]]+/, " ")
    end

    def initialize(source, deny: [])
      @patterns = BUILT_IN + deny.filter_map { |entry| deny_pattern(entry) } + internal_tokens(source).map { |token| whole_identifier(token) }
    end

    def hits(html, file_name:)
      scan(decoded(html), "the client file") + scan(file_name, "the file name")
    end

    def check!(html, file_name:)
      found = hits(html, file_name: file_name)
      raise ClientBlocked, found unless found.empty?
    end

    private

    # The caller scans a rendering whose images and fonts are placeholders, so nothing here is exempt.
    def decoded(html)
      # CGI leaves &nbsp; alone, and a deny phrase must still match across any gap the reader sees as a space.
      CGI.unescapeHTML(html).gsub("&nbsp;", " ")
    end

    def scan(raw, where)
      text = self.class.normalize(raw)
      spans = @patterns.flat_map { |pattern| text.to_enum(:scan, pattern).map { span(pattern, Regexp.last_match) } }
      merge(spans).map { |start, finish| report(text, start, finish, where) }
    end

    # A zero-length match cannot say what to block, so fail closed rather than drop it.
    def span(pattern, match)
      start, finish = match.offset(0)
      raise ConfigError, ["deny pattern #{pattern.source.inspect} matches the empty string; make it match real text"] if start == finish

      [start, finish]
    end

    # Overlapping matches (a derived token and a built-in on the same text) are one hit.
    def merge(spans)
      spans.sort_by { |start, finish| [start, -finish] }.each_with_object([]) do |(start, finish), merged|
        if merged.any? && start < merged.last[1]
          merged.last[1] = [merged.last[1], finish].max
        else
          merged << [start, finish]
        end
      end
    end

    def report(text, start, finish, where)
      term = text[start...finish]
      before = text[[start - CONTEXT, 0].max...start]
      context = "#{before}#{term}#{text[finish, CONTEXT]}"
      "found #{term.inspect} in #{where}: ...#{context}..."
    end

    def deny_pattern(entry)
      pattern = entry.is_a?(Hash) ? entry["pattern"] : entry
      return if pattern.to_s.strip.empty?
      return literal(pattern.to_s) unless entry.is_a?(Hash)

      Config.deny_regexp(pattern).tap do |regexp|
        raise ConfigError, ["deny pattern #{pattern.inspect} matches the empty string; make it match real text"] if Config.zero_width?(regexp)
      end
    end

    # Bound on word chars only so adjacent punctuation still matches; an all-digit token also refuses to be part of a longer digit run like 1-2 or 1.2.
    def whole_identifier(token)
      text = self.class.normalize(token)
      digits_only = text.match?(/\A\d+\z/)
      before = digits_only ? "(?<!\\d[-.])" : ""
      after = digits_only ? "(?![-.]\\d)" : ""
      Regexp.new("(?<!\\w)#{before}#{Regexp.escape(text)}#{after}(?!\\w)", Regexp::IGNORECASE)
    end

    def literal(text) = Regexp.new(Regexp.escape(self.class.normalize(text)), Regexp::IGNORECASE)

    def internal_tokens(source)
      public_words = words(client_build_text(source))
      tested_on = source.data["tested_on"]
      exempt = [tested_on.iso8601, tested_on.year.to_s]
      words(self.class.normalize(source.internal_texts.join(" "))).select { |word| distinctive?(word, public_words) && !exempt.include?(word) }.uniq
    end

    def client_build_text(source)
      fixed = Array(source.data["issues"]).flat_map { |issue| Array(issue["fixed_in"]) }
      self.class.normalize([source.data["build_plain"], *fixed].join(" "))
    end

    def words(text)
      text.scan(CHUNK).flat_map { |chunk| [chunk, chunk[URL_HOST, 1]] }.compact.map { |word| word.gsub(%r{\A[.:/#-]+|[.:/#-]+\z}, "") }
    end

    def distinctive?(word, public_words)
      return false if word.length < MIN_TOKEN || (word.match?(COMMIT_HASH) && public_words.include?(word))

      word.match?(IDENTIFIER)
    end
  end
end
