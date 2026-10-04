require_relative "test_helper"

# B-R19 to B-R22 as CSS text (print v3, decision 9). Real page checks on a PDF belong to card E.
class RenderPrintCssTest < Minitest::Test
  def rules(html) = css_rules(css(html))

  def print_rules(html) = rules(html).select(&:in_print?)

  def print_rule_for?(html, selector)
    print_rules(html).select { |rule| rule.matches?(selector) }.any? { |rule| yield rule }
  end

  def page_rules(html) = rules(html).select { |rule| rule.at_rules.any? { |at| at.start_with?("@page") } }

  def assert_print(html, selector, property, value)
    assert print_rule_for?(html, selector) { |rule| rule.value(property) == value },
      "print styles must set #{property}: #{value} on #{selector}"
  end

  # AC41 (B-R20): rows, requirement items, the legend and the verdict never split.
  def test_rows_requirements_legend_and_verdict_avoid_breaking_inside
    html = internal_html(:fail)

    ["tr", "ol.reqs li", ".key", ".verdict"].each { |selector| assert_print(html, selector, "break-inside", "avoid") }
  end

  # AC41 (B-R20): the tall tables may continue, with the header row repeated.
  def test_tables_may_continue_with_a_repeated_header_row
    html = internal_html(:fail)

    assert_print(html, "thead", "display", "table-header-group")
    %w[table .j-wrap .scroll-region].each do |selector|
      refute print_rule_for?(html, selector) { |rule| rule.value("break-inside") == "avoid" },
        "#{selector} must be allowed to continue onto the next page"
    end
  end

  # AC42 (B-R21): eyebrows, headings and section heads stay with what follows.
  def test_eyebrows_and_headings_keep_with_the_next_content
    html = client_html(:pass_with_notes)

    [".eyebrow", "h2", "h3", ".sec-head"].each { |selector| assert_print(html, selector, "break-after", "avoid") }
  end

  # AC38 to AC40 (B-R19), as CSS: only sections marked pb force a page; the renderer marks 02 and 03, never 01.
  def test_forced_breaks_come_only_from_the_pb_marker
    html = internal_html(:fail)
    forcing = print_rules(html).select do |rule|
      rule.value("break-before") == "page" || rule.value("page-break-before") == "always"
    end

    refute_empty forcing
    assert_equal ["main > section.pb"], forcing.flat_map(&:selectors).uniq,
      "a page break may be forced only through the pb marker the renderer sets on 02, 03, A and 04 with issues"
    assert_includes classes(section(html, "02 · What we checked")), "pb"
    assert_includes classes(section(html, "03 · Journeys")), "pb"
    refute_includes classes(section(html, "01 · Summary")), "pb", "page 1 holds the cover and the whole Summary"
  end

  # AC39 (B-R19): sections carry no top border in print.
  def test_sections_have_no_top_border_in_print
    html = internal_html(:fail)
    borders = print_rules(html).select { |rule| rule.selectors.any? { |part| part.include?("section") } }
                               .filter_map { |rule| rule.value("border-top") }

    assert_print(html, "main > section", "border-top", "none")
    assert_empty borders - %w[none 0], "a print rule draws a section top border"
  end

  # AC43 (B-R22): Contents, the banner, chips, technical-detail links and back-links are hidden in print.
  def test_screen_only_parts_are_hidden_in_print
    html = internal_html(:fail)

    %w[.contents-sec .banner-int .chip-x .vchip .int-link .backlink].each do |selector|
      assert print_rule_for?(html, selector) { |rule| rule.value("display") == "none" }, "#{selector} prints"
    end
    assert_includes classes(with_class(html, "contents-sec").to_s), "contents-sec"
    assert_match(/aria-label="Contents"/, with_class(html, "contents-sec").to_s, "the Contents block carries contents-sec")
  end

  # AC43 (B-R22): the INTERNAL page header is static CSS in the internal file only, page 1 included.
  def test_internal_page_header_is_internal_only_and_starts_on_page_1
    internal = internal_html(:fail)
    client = client_html(:fail)
    header = page_rules(internal).find do |rule|
      rule.prelude == "@top-center" && rule.value("content").to_s.match?(/INTERNAL (\\2014|—) +NOT FOR CLIENT DISTRIBUTION/)
    end

    assert header, "the internal file needs an @page top-center INTERNAL header"
    assert_match(/\A@page \w+/, header.chain.last.to_s, "the header belongs to a named page")
    assert_match(/\bpage:\s*#{header.chain.last.split.last}\b/, css(internal), "nothing uses the named INTERNAL page")
    refute page_rules(internal).any? { |rule| rule.chain.last.to_s.include?(":first") && rule.prelude == "@top-center" },
      "page 1 must keep the INTERNAL header"
    refute_includes client, "NOT FOR CLIENT DISTRIBUTION"
    refute_match(/\bpage:\s*internal\b/, css(client))
  end

  # AC43 (B-R22): the running footer starts on page 2 in both files.
  def test_running_footer_starts_on_page_2
    [client_html(:fail), internal_html(:fail)].each do |html|
      pages = page_rules(html)

      assert pages.any? { |rule| rule.prelude == "@bottom-center" && rule.value("content").to_s.include?("counter(page)") }
      assert pages.any? { |rule| rule.chain.last.to_s.include?(":first") && rule.prelude == "@bottom-center" &&
                                 rule.value("content") == "none" }, "page 1 must have no running footer"
    end
  end

  # B-R21: the colophon never sits alone on the last printed page.
  def test_the_footer_stays_with_the_content_before_it_in_print
    html = client_html(:fail)
    kept = print_rules(html).select { |rule| rule.selectors.any? { |part| part.match?(/(\A| )footer(\.[\w-]+)*\z/) } }

    assert kept.any? { |rule| rule.value("break-before") == "avoid" || rule.value("page-break-before") == "avoid" },
      "print styles must set break-before: avoid on the footer"
  end

  # AC14 (B-R11): magenta is brand colour, never a status colour.
  def test_status_styles_never_use_magenta
    status = rules(client_html(:fail)).select do |rule|
      rule.selectors.any? { |part| part.match?(/\.(badge|cell|verdict|v-label|t-[\w-]+|v-[\w-]+)\b/) }
    end

    refute_empty status
    status.each { |rule| refute_match(/magenta/i, rule.declarations.values.join(" "), rule.prelude) }
  end
end
