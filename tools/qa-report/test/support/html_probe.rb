# frozen_string_literal: true

require "cgi/escape"

# Stdlib-only reading of rendered HTML and its CSS: balanced-tag extraction, visible text, and a nesting-aware CSS walk.
module HtmlProbe
  CssRule = Struct.new(:chain, :prelude, :declarations) do
    def selectors = prelude.split(",").map { |part| HtmlProbe.normalize_selector(part) }

    def at_rules = chain + [prelude]

    def in_print? = at_rules.any? { |at| at.start_with?("@media") && at.include?("print") }

    def matches?(selector)
      wanted = HtmlProbe.normalize_selector(selector)
      selectors.any? { |part| part == wanted || part.end_with?(" #{wanted}") }
    end

    def value(property) = declarations[property]
  end

  module_function

  def normalize_selector(text) = text.strip.gsub(/\s*>\s*/, " > ").gsub(/\s+/, " ")

  # Every non-nested element of `tag` whose opening tag matches `pattern`, open tag through its matching close tag.
  def elements(html, tag, pattern = //)
    found = []
    offset = 0
    while (start = html.index(/<#{tag}\b[^>]*>/m, offset))
      open_tag = html[start..][/\A<#{tag}\b[^>]*>/m]
      if open_tag.match?(pattern)
        finish = closing_index(html, tag, start)
        found << html[start...finish]
        offset = finish
      else
        offset = start + open_tag.length
      end
    end
    found
  end

  def element(html, tag, pattern = //) = elements(html, tag, pattern).first

  def class_pattern(css_class) = /\bclass="(?:[^"]*\s)?#{Regexp.escape(css_class)}(?:\s[^"]*)?"/

  def with_class(html, css_class)
    tag = html[/<(\w+)\b[^>]*#{class_pattern(css_class)}/m, 1]
    tag && element(html, tag, class_pattern(css_class))
  end

  def all_with_class(html, css_class, tag:) = elements(html, tag, class_pattern(css_class))

  def classes(fragment) = fragment[/\A<\w+\b[^>]*?\bclass="([^"]*)"/m, 1].to_s.split

  def closing_index(html, tag, start)
    depth = 0
    html.to_enum(:scan, %r{<(/?)#{tag}\b[^>]*>}m).each do
      match = Regexp.last_match
      next if match.begin(0) < start

      depth += match[1].empty? ? 1 : -1
      return match.end(0) if depth.zero?
    end
    raise "unclosed <#{tag}> at #{start}"
  end

  # Text a reader sees: no style, script or comments, entities decoded, whitespace collapsed.
  def text(fragment)
    stripped = fragment.gsub(%r{<(style|script)\b.*?</\1>}m, " ").gsub(/<!--.*?-->/m, " ").gsub(/<[^>]+>/m, " ")
    CGI.unescapeHTML(stripped).gsub(/[[:space:]]+/, " ").strip
  end

  # The body section whose eyebrow reads e.g. "01 · Summary".
  def section(html, eyebrow)
    elements(html, "section").find { |candidate| text(candidate).start_with?(eyebrow) } ||
      raise("no section with eyebrow #{eyebrow.inspect}")
  end

  def css(html) = html.scan(%r{<style\b[^>]*>(.*?)</style>}m).flatten.join("\n")

  # Quote- and paren-aware so data: URIs and content strings never split a declaration.
  def css_rules(css)
    rules = []
    stack = []
    buffer = +""
    quote = nil
    parens = 0
    css.gsub(%r{/\*.*?\*/}m, "").each_char do |char|
      if quote
        buffer << char
        quote = nil if char == quote
        next
      end

      case char
      when '"', "'"
        quote = char
        buffer << char
      when "("
        parens += 1
        buffer << char
      when ")"
        parens -= 1
        buffer << char
      when ";"
        if parens.zero?
          stack.last[:declarations] << buffer.strip if stack.any? && !buffer.strip.empty?
          buffer = +""
        else
          buffer << char
        end
      when "{"
        stack.push(prelude: buffer.strip.gsub(/\s+/, " "), declarations: [], chain: stack.map { |frame| frame[:prelude] })
        buffer = +""
      when "}"
        frame = stack.pop
        frame[:declarations] << buffer.strip unless buffer.strip.empty?
        buffer = +""
        rules << CssRule.new(frame[:chain], frame[:prelude], declarations(frame[:declarations]))
      else
        buffer << char
      end
    end
    rules
  end

  def declarations(list)
    list.filter_map do |declaration|
      property, value = declaration.split(":", 2)
      [property.strip.downcase, value.strip.sub(/\s*!important\z/, "")] if value
    end.to_h
  end
end
