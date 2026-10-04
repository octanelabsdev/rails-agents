# frozen_string_literal: true

require "erb"
require "yaml"

module QaReport
  # Who the report is from: name, contact, wordmark artwork and embedded fonts. Everything else is the shared design.
  class Brand
    Font = Struct.new(:family, :weight, :data)
    SAFE_FAMILY = /\A[\w .-]+\z/

    attr_reader :name, :contact_email, :view_box, :wordmark_on_dark, :wordmark_on_light, :fonts

    def self.default
      new(name: "Example Studio", contact_email: "hello@example.com",
          wordmark_on_dark: default_wordmark("#FFFFFF"), wordmark_on_light: default_wordmark("#0F1115"),
          view_box: "0 0 580 100")
    end

    def self.load(path)
      config = YAML.safe_load_file(path) || {}
      raise ArgumentError, "must be a mapping of keys" unless config.is_a?(Hash)

      dir = File.dirname(File.expand_path(path))
      wordmark = config.fetch("wordmark")
      raise ArgumentError, "wordmark must be a mapping of keys" unless wordmark.is_a?(Hash)

      new(name: text(config, "name"), contact_email: text(config, "contact_email"),
          wordmark_on_dark: read_svg(dir, text(wordmark, "on_dark")),
          wordmark_on_light: read_svg(dir, text(wordmark, "on_light")),
          view_box: text(wordmark, "view_box"), fonts: load_fonts(config.fetch("fonts", []), dir))
    rescue KeyError, ArgumentError, TypeError, SystemCallError, Psych::Exception => e
      raise ArgumentError, "brand config #{path}: #{e.message}"
    end

    def self.text(hash, key)
      value = hash.fetch(key)
      raise ArgumentError, "#{key} must be text" unless value.is_a?(String)

      value
    end

    def self.read_svg(dir, file)
      svg = File.read(File.join(dir, file), encoding: Encoding::UTF_8)
      raise ArgumentError, "#{file} has no <svg> element" unless svg.match?(%r{<svg\b[^>]*>.*</svg>}m)

      svg
    end

    def self.load_fonts(list, dir)
      raise ArgumentError, "fonts must be a list" unless list.is_a?(Array)

      list.map do |font|
        raise ArgumentError, "each font must be a mapping of keys" unless font.is_a?(Hash)

        family = text(font, "family")
        raise ArgumentError, "font family #{family.inspect} may only use letters, digits, spaces, dots and dashes" unless family.match?(SAFE_FAMILY)

        Font.new(family, Integer(font.fetch("weight")), [File.binread(File.join(dir, text(font, "file")))].pack("m0"))
      end
    end

    def self.default_wordmark(fill)
      %(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 580 100"><text x="0" y="68" font-family="Arial, Helvetica, sans-serif" ) +
        %(font-size="56" font-weight="800" fill="#{fill}">EXAMPLE STUDIO</text></svg>)
    end

    def initialize(name:, contact_email:, wordmark_on_dark:, wordmark_on_light:, view_box:, fonts: [])
      @name = name
      @contact_email = contact_email
      @view_box = view_box
      @wordmark_on_dark = wordmark_on_dark
      @wordmark_on_light = wordmark_on_light
      @fonts = fonts
    end

    # The artwork's own canvas rect is dropped and the configured crop applied, so the mark sits on any background.
    def wordmark(variant, class_name:, decorative: false)
      svg = variant == :dark ? wordmark_on_dark : wordmark_on_light
      tag = svg[/<svg\b[^>]*>/m]
      canvas = canvas_size(tag)
      body = svg[%r{<svg\b[^>]*>(.*)</svg>}m, 1].gsub(%r{<rect\b[^>]*?(?:/>|>\s*</rect>)}m) do |rect|
        full_bleed?(rect, canvas) ? "" : rect
      end
      label = decorative ? %(aria-hidden="true") : %(role="img" aria-label="#{ERB::Util.html_escape(name)}")
      %(<svg xmlns="http://www.w3.org/2000/svg" class="#{class_name}" viewBox="#{ERB::Util.html_escape(@view_box)}" #{label}>#{body}</svg>)
    end

    def font_family = fonts.first&.family

    private

    def canvas_size(tag)
      view_box = tag[/\bviewBox="([^"]*)"/, 1].to_s.split.map(&:to_f)
      width = tag[/\swidth="([\d.]+)/, 1]&.to_f || view_box[2]
      height = tag[/\sheight="([\d.]+)/, 1]&.to_f || view_box[3]
      [width, height]
    end

    def full_bleed?(rect, canvas)
      attribute = ->(key) { rect[/\s#{key}="([\d.]+)/, 1]&.to_f }
      attribute.call("width") == canvas[0] && attribute.call("height") == canvas[1] &&
        attribute.call("x").to_f.zero? && attribute.call("y").to_f.zero?
    end
  end
end
