require_relative "test_helper"

# B-R4 to B-R6, B-R11: the cover carries the verdict a client reads in 5 seconds.
class RenderCoverTest < Minitest::Test
  def cover(html)
    found = elements(html, "header", class_pattern("cover"))
    assert_equal 1, found.size, "expected exactly 1 cover header"
    found.first
  end

  def meta_rows(html)
    dl = element(cover(html), "dl")
    assert dl, "the cover has no meta list"
    elements(dl, "dt").zip(elements(dl, "dd")).to_h { |dt, dd| [text(dt), dd] }
  end

  def stat_strip(html)
    strip = with_class(cover(html), "stat-strip")
    assert strip, "the cover has no stat strip"
    all_with_class(strip, "stat", tag: "li").to_h do |stat|
      note = with_class(stat, "note")
      [text(with_class(stat, "label")), [text(with_class(stat, "value")), note && text(note)]]
    end
  end

  def verdict(html) = with_class(cover(html), "verdict") || flunk("the cover has no verdict panel")

  # AC4 (B-R4)
  def test_client_cover_shows_eyebrow_title_and_meta
    html = client_html(:pass_with_notes)
    rows = meta_rows(html)

    assert_equal "QA REPORT", text(with_class(cover(html), "eyebrow")).upcase
    assert_equal 1, html.scan(/<h1\b/).size, "a report has exactly 1 H1"
    assert_equal "Acceptance QA: Proposal sections keep their order", text(element(html, "h1"))
    assert_equal ["Prepared for", "Project", "Tested", "Build"], rows.keys
    assert_equal CLIENT_NAME, text(rows["Prepared for"])
    assert_equal "Proposal builder", text(rows["Project"])
    assert_includes text(rows["Tested"]), "October 2, 2026"
    assert_includes text(rows["Tested"]), "Pre-release test environment"
    assert_equal "PR #101 · commit 1a2b3c4", text(rows["Build"])
  end

  # AC4 (B-R4), owner decision 8: the client name only, no logo.
  def test_prepared_for_row_has_no_image
    row = meta_rows(client_html(:pass_with_notes))["Prepared for"]

    refute_match(/<(svg|img)\b/, row, "the Prepared for row must hold the client name only (decision 8)")
  end

  # AC4 (B-R4)
  def test_internal_cover_eyebrow_names_the_card
    assert_equal "QA REPORT · CARD #TRACKER-101", text(with_class(cover(internal_html(:pass_with_notes)), "eyebrow")).upcase
  end

  # B-R4: the date uses English month names from the authored date.
  def test_fail_fixture_tested_row_shows_its_own_date
    rows = meta_rows(client_html(:fail))

    assert_includes text(rows["Tested"]), "October 1, 2026"
    assert_equal "commit a1b2c3d", text(rows["Build"])
  end

  # AC5 (B-R5, B-R11)
  def test_pass_with_notes_verdict_panel_shows_glyph_word_and_explainer
    panel = verdict(client_html(:pass_with_notes))

    assert_match(/<svg\b/, panel, "the verdict needs a glyph, not colour alone")
    assert_equal "PASS WITH NOTES", text(with_class(panel, "v-label")).upcase
    assert_equal "All 3 requirements met. No issues found. 2 notes for you.", text(with_class(panel, "v-exp"))
  end

  # AC5 (B-R5c)
  def test_fail_verdict_panel_shows_the_fail_explainer
    panel = verdict(client_html(:fail))

    assert_match(/<svg\b/, panel)
    assert_equal "FAIL", text(with_class(panel, "v-label")).upcase
    assert_equal "Not ready yet. 4 issues are still open, including 3 major ones. 1 major fix is waiting to be " \
                 "re-tested. 8 of 15 requirements are met.", text(with_class(panel, "v-exp"))
  end

  # AC24 (B-R5a): the computed copy reaches the rendered cover, not just the copy object.
  def test_pass_verdict_panel_renders_the_pass_explainer
    panel = verdict(client_html(counted_source(met: 3)))

    assert_equal "PASS", text(with_class(panel, "v-label")).upcase
    assert_equal "All 3 requirements met. No issues found.", text(with_class(panel, "v-exp"))
  end

  # AC6 (B-R6)
  def test_pass_with_notes_stat_strip
    expected = {
      "Requirements met" => ["3 of 3", nil], "Journeys passed" => ["6 of 7", "1 observed"],
      "Open issues" => ["0", "0 found"], "Tested on" => ["Light · Phone", "Dark: not tested"]
    }

    assert_equal expected, stat_strip(client_html(:pass_with_notes))
  end

  # AC7 (B-R6)
  def test_fail_stat_strip
    expected = {
      "Requirements met" => ["8 of 15", "7 not met"], "Journeys passed" => ["4 of 10", "5 failed · 1 blocked"],
      "Open issues" => ["4", "8 found · 2 fixed"], "Tested on" => ["Light · Dark · PDF", nil]
    }

    assert_equal expected, stat_strip(client_html(:fail))
  end

  # B-R1: the cover numbers come from client-visible content, so both files agree.
  def test_internal_cover_shows_the_same_verdict_and_stats
    assert_equal stat_strip(client_html(:fail)), stat_strip(internal_html(:fail))
    assert_equal text(verdict(client_html(:fail))), text(verdict(internal_html(:fail)))
  end

  # AC16 (B-R13), CSS part: the report follows the OS colour scheme.
  def test_the_stylesheet_follows_the_os_colour_scheme
    rules = css_rules(css(client_html(:pass_with_notes)))

    assert rules.any? { |rule| rule.at_rules.any? { |at| at.include?("prefers-color-scheme: dark") } },
      "the report needs a prefers-color-scheme: dark block to follow the OS"
  end
end
