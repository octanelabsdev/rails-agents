require_relative "test_helper"

# C-R15, C-R16, C-R18 as CSS text (print v3, decision 9). Page-level PDF checks belong to card E.
class FindingsPrintCssTest < Minitest::Test
  def print_rules(html) = css_rules(css(html)).select(&:in_print?)

  def print_value?(html, selector, property, value)
    print_rules(html).any? { |rule| rule.matches?(selector) && rule.value(property) == value }
  end

  def assert_print(html, selector, property, value)
    assert print_value?(html, selector, property, value), "print styles must set #{property}: #{value} on #{selector}"
  end

  # AC: an issue card, its status line and its Expected/Actual block never split (C-R15).
  def test_issue_cards_and_their_parts_never_split
    html = internal_html(:fail)

    %w[.issue .status-line .exp-act figure].each { |selector| assert_print(html, selector, "break-inside", "avoid") }
  end

  # AC: printed screenshots sit 3 to a row, centred, at 1/3 of the text width (C-R16).
  def test_printed_screenshots_sit_three_to_a_centred_row
    html = client_html(:pass_with_notes)

    assert_print(html, ".shots", "display", "flex")
    assert_print(html, ".shots", "flex-wrap", "wrap")
    assert_print(html, ".shots", "justify-content", "center")
    basis = print_rules(html).select { |rule| rule.matches?(".shots figure") }.filter_map { |rule| rule.value("flex") }
    assert basis.any? { |value| value.match?(%r{\A0 0 calc\(\(100% - [\d.]+rem\) / 3\)\z}) },
      "a printed figure must be fixed at a third of the row, got #{basis.inspect}"
  end

  # AC: each printed thumbnail is 3.25 in tall, cropped from the top (C-R16).
  def test_printed_thumbnails_are_3_25_in_tall_cropped_from_the_top
    html = client_html(:pass_with_notes)

    assert_print(html, "button.thumb img", "height", "3.25in")
    assert_print(html, "button.thumb img", "object-fit", "cover")
    assert_print(html, "button.thumb img", "object-position", "top")
  end

  # AC: Expand chips, flag chips and the lightbox do not print (C-R16).
  def test_expand_chips_flags_and_the_lightbox_do_not_print
    html = internal_html(:pass_with_notes)

    %w[.chip-x .flags dialog#lb].each { |selector| assert_print(html, selector, "display", "none") }
  end

  # AC: the appendix keeps its amber left rule in print (C-R18).
  def test_appendix_keeps_its_amber_left_rule_in_print
    rule = print_rules(internal_html(:fail)).find { |candidate| candidate.matches?(".appendix-box") && candidate.value("border-left") }

    assert rule, "print styles must give .appendix-box a left rule"
    assert_match(/\A4px solid var\(--color-amber-800\)\z/, rule.value("border-left"))
  end

  # AC: long preformatted lines wrap within the margins (C-R18).
  def test_preformatted_text_wraps_in_print
    assert_print(internal_html(:fail), "pre", "white-space", "pre-wrap")
  end

  # C-R18: the appendix styles live in the internal stylesheet only.
  def test_appendix_styles_are_internal_only
    refute_includes css(client_html(:fail)), ".appendix-box"
  end

  # QA at 390 px: long paths and URLs in the appendix wrap instead of pushing the page sideways.
  def test_appendix_text_wraps_long_tokens_on_screen
    rules = css_rules(css(internal_html(:fail))).reject(&:in_print?)
    wraps = ->(selector) { rules.any? { |rule| rule.matches?(selector) && %w[anywhere break-word].include?(rule.value("overflow-wrap")) } }

    [".appendix-box", ".appendix code"].each { |selector| assert wraps.call(selector), "#{selector} needs overflow-wrap: anywhere" }
    assert rules.any? { |rule| rule.matches?(".appendix pre") && rule.value("white-space") == "pre-wrap" },
      "appendix pre must wrap on screen too"
  end
end
