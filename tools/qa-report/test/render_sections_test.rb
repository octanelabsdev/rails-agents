require_relative "test_helper"

# B-R3, B-R7 to B-R12, B-R23: Contents, 01 Summary, 02 What we checked and 03 Journeys.
class RenderSectionsTest < Minitest::Test
  EYEBROWS = ["01 · Summary", "02 · What we checked", "03 · Journeys"].freeze

  def heading(section) = text(element(section, "h2"))

  def contents(html) = element(html, "nav", /aria-label="Contents"/) || flunk("no Contents nav")

  def hrefs(fragment) = fragment.scan(/<a\b[^>]*\bhref="#([^"]+)"/).flatten

  # The nav repeats its list inside the small-screen <details>, so the desktop list is the nav minus that copy.
  def desktop_links(nav) = hrefs(nav.sub(element(nav, "details").to_s, ""))

  def ids(html) = html.scan(/\bid="([^"]+)"/).flatten

  def journey_rows(html)
    table = with_class(section(html, "03 · Journeys"), "j-table") || flunk("03 has no journeys table")
    elements(element(table, "tbody"), "tr")
  end

  def evidence_cell(row) = with_class(row, "c-ev") || flunk("journey row has no Evidence cell")

  # AC3 (B-R3)
  def test_landmarks_read_in_order_in_both_files
    [client_html(:fail), internal_html(:fail)].each do |html|
      positions = [html.index(/<header\b/), html.index(contents(html))] +
                  EYEBROWS.map { |eyebrow| html.index(section(html, eyebrow)) }

      assert_equal positions.sort, positions, "expected cover, Contents, 01, 02, 03 in that order"
    end
    internal = internal_html(:fail)
    banner = with_class(internal, "banner-int") || flunk("the internal file has no banner")
    assert_operator internal.index(banner), :<, internal.index(/<header\b/), "the banner comes before the cover"
  end

  # AC3 (B-R3): client copy says issues and requirements.
  def test_client_text_never_says_defect_or_ac
    [client_html(:fail), strip_internal(internal_html(:fail))].each do |html|
      words = text(html)

      refute_match(/\bdefects?\b/i, words)
      refute_match(/\bAC\b/, words)
    end
  end

  # AC13 and AC15 (B-R12)
  def test_contents_links_every_numbered_section_in_order_and_each_link_resolves
    html = client_html(:pass_with_notes)
    links = desktop_links(contents(html))
    sections = elements(html, "section").select { |candidate| text(candidate).match?(/\A\d\d · /) }

    assert_empty hrefs(contents(html)) - ids(html), "Contents links point at ids that are not in the file"
    assert_equal EYEBROWS, sections.first(3).map { |candidate| EYEBROWS.find { |eyebrow| text(candidate).start_with?(eyebrow) } }
    assert_equal (0...sections.size).to_a,
      links.map { |id| sections.index { |candidate| candidate.include?(%(id="#{id}")) } },
      "Contents must link every numbered section once, in order"
  end

  # AC13 (B-R12): below 640 px the same links sit in a collapsed "On this page" disclosure.
  def test_contents_has_a_collapsed_on_this_page_disclosure_with_the_same_links
    nav = contents(client_html(:pass_with_notes))
    disclosure = element(nav, "details") || flunk("Contents has no disclosure for small screens")

    refute_match(/<details\b[^>]*\bopen\b/, disclosure, "the disclosure starts collapsed")
    assert_equal "On this page", text(element(disclosure, "summary"))
    assert_equal desktop_links(nav), hrefs(disclosure)
  end

  # AC8 (B-R7)
  def test_pass_with_notes_section_headings
    html = client_html(:pass_with_notes)

    assert_equal "Everything works, with 2 notes", heading(section(html, "01 · Summary"))
    assert_equal "3 requirements, all met", heading(section(html, "02 · What we checked"))
    assert_equal "7 journeys, 6 passed and 1 observed", heading(section(html, "03 · Journeys"))
  end

  # AC8 (B-R7)
  def test_fail_section_headings
    html = client_html(:fail)

    assert_equal "Not ready yet, and here is why", heading(section(html, "01 · Summary"))
    assert_equal "15 requirements, 8 met", heading(section(html, "02 · What we checked"))
    assert_equal "10 journeys, 4 passed and 6 did not", heading(section(html, "03 · Journeys"))
  end

  # AC9 (B-R8)
  def test_summary_shows_the_lead_then_four_blocks_in_order
    summary = section(client_html(:pass_with_notes), "01 · Summary")
    words = text(summary)
    order = ["Everything we checked works.", "What we tested", "What we found", "What it means for you",
             "What happens next"].map { |phrase| words.index(phrase) || flunk("01 is missing #{phrase.inspect}") }

    assert_equal order.sort, order
    assert_equal ["What we tested", "What we found", "What it means for you", "What happens next"],
      elements(summary, "h3").map { |h3| text(h3) }
  end

  # AC9 (B-R8): authored text is escaped, never trusted as markup.
  def test_authored_summary_html_is_escaped
    source = source_from(:pass_with_notes) { |data| data["summary"]["found"] = "We saw <b>bold</b> text." }
    summary = section(client_html(source), "01 · Summary")

    assert_includes summary, "&lt;b&gt;bold&lt;/b&gt;"
    refute_includes summary, "<b>bold</b>"
    assert_includes text(summary), "We saw <b>bold</b> text."
  end

  # B-R8: authored client text renders as plain paragraphs.
  def test_a_blank_line_in_authored_text_starts_a_new_paragraph
    source = source_from(:pass_with_notes) { |data| data["summary"]["next"] = "First thing.\n\nSecond thing." }
    summary = section(client_html(source), "01 · Summary")
    block = summary[summary.index("What happens next")..]

    assert_equal ["First thing.", "Second thing."], elements(block, "p").first(2).map { |paragraph| text(paragraph) }
  end

  # AC10 (B-R9, B-R11)
  def test_requirements_are_a_numbered_list_with_badges_text_and_journey_links
    html = client_html(:pass_with_notes)
    list = element(section(html, "02 · What we checked"), "ol") || flunk("02 has no numbered requirements list")
    items = elements(list, "li")

    assert_equal 3, items.size
    items.each do |item|
      badge = with_class(item, "badge") || flunk("requirement has no result badge")
      assert_match(/<svg\b/, badge, "a requirement badge needs a glyph")
      assert_equal "MET", text(badge).upcase
    end
    assert_includes text(items[1]), "Opening the proposal as an administrator shows all of those"
    targets = hrefs(items[1])
    assert_equal 3, targets.size, "R2 links journeys 3, 4 and 6"
    targets.zip(["View the proposal as an administrator", "Add a roadmap section", "Light and phone display"])
           .each do |target, title|
             row = journey_rows(html).find { |candidate| candidate.include?(%(id="#{target}")) }
             assert row, "requirement link ##{target} does not land on a journey row"
             assert_includes text(row), title
           end
  end

  # AC10 (B-R9, B-R11)
  def test_coverage_table_has_only_the_source_columns_and_glyph_plus_word_cells
    checked = section(client_html(:pass_with_notes), "02 · What we checked")
    table = with_class(checked, "matrix") || flunk("02 has no coverage table")
    header = elements(element(table, "thead"), "th").map { |th| text(th) }

    assert_equal ["Light", "Dark", "Phone (390 px)"], header.drop(1)
    cells = elements(element(table, "tbody"), "td")
    assert_equal 9, cells.size
    cells.each do |cell|
      assert_match(/<svg\b/, cell, "every coverage cell needs a glyph")
      assert_includes ["PASS", "NOT TESTED", "OBSERVED"], text(cell).upcase
    end
  end

  # AC11 and AC12 (B-R10)
  def test_journeys_table_has_four_columns_and_keeps_authored_order
    html = client_html(:fail)
    table = with_class(section(html, "03 · Journeys"), "j-table")

    assert_equal ["#", "What we checked", "Result", "Evidence"], elements(element(table, "thead"), "th").map { |th| text(th) }
    rows = journey_rows(html)
    assert_equal (1..10).map(&:to_s), rows.map { |row| text(elements(row, "td").first) }
    assert_includes text(rows[0]), "Set up the proposal in steps"
    assert_includes text(rows[9]), "Use the Contents list"
  end

  # AC11 (B-R10, B-R11): failing rows carry the danger rule; every result shows a glyph and a word.
  def test_failing_journeys_are_marked_and_every_result_has_glyph_and_word
    rows = journey_rows(client_html(:fail))
    results = load_fixture(:fail).journeys.map { |journey| journey["result"] }

    rows.zip(results).each do |row, result|
      badge = with_class(with_class(row, "c-res") || row, "badge") || flunk("journey row has no result badge")
      assert_match(/<svg\b/, badge)
      assert_equal result, text(badge).upcase
      assert_equal result == "FAIL", classes(row).include?("is-fail"), "row #{text(row)[0, 30]} fail marker"
    end
    marked = css_rules(css(client_html(:fail))).select { |rule| rule.selectors.any? { |part| part.include?("is-fail") } }
    assert marked.any? { |rule| rule.declarations.values.join(" ").match?(/4px .*danger/) },
      "no style gives a failing row its 4 px danger left rule"
  end

  # AC11 and AC12 (B-R10): below 768 px each row reads as a card headed "JOURNEY {n}".
  def test_small_screens_turn_rows_into_journey_cards
    rules = css_rules(css(client_html(:fail)))
    phone = rules.select { |rule| rule.at_rules.any? { |at| at.include?("max-width: 767px") } }

    refute_empty phone, "no styles below 768 px"
    assert phone.any? { |rule| rule.value("content").to_s.match?(/\A"Journey "\z/i) },
      "the number cell must read JOURNEY {n} on small screens"
  end

  # AC11 (B-R10): internal adds 1 "Technical detail ↓" link per journey; the client has none.
  def test_technical_detail_links_appear_only_in_the_internal_file
    internal = journey_rows(internal_html(:fail))

    assert_equal 10, internal.count { |row| text(row).include?("Technical detail ↓") }
    assert internal.all? { |row| with_class(row, "int-link") }, "technical detail links need the int-link class"
    refute_includes client_html(:fail), "Technical detail"
  end

  # B-R10: evidence names each client screenshot.
  def test_evidence_cell_names_each_screenshot
    rows = journey_rows(client_html(:pass_with_notes))

    assert_includes text(evidence_cell(rows[2])), "Screenshot 1a"
    assert_includes text(evidence_cell(rows[2])), "Screenshot 1b"
    assert_equal "Confirmed in the saved proposal", text(evidence_cell(rows[0]))
  end

  # AC44 (B-R23): no screenshot shows a dash for sighted readers and "No screenshot" for screen readers.
  def test_a_journey_with_no_evidence_shows_a_hidden_dash_and_an_explanation_replaces_it
    source = source_from(:fail) do |data|
      data["journeys"][3].delete("evidence_note_plain")
      data["journeys"][4].merge!("evidence" => [], "evidence_note_plain" => "Could not be tried")
    end
    rows = journey_rows(renderer_for(source).internal_html)
    dash = evidence_cell(rows[3])

    marker = with_class(dash, "ev-none") || flunk("the empty Evidence cell has no .ev-none")
    assert_match(/\A<span\b[^>]*\baria-hidden="true"/, marker, "as in the approved mock, .ev-none is the hidden dash itself")
    assert_equal "—", text(marker)
    refute_includes marker, "sr-only", "\"No screenshot\" is a sibling of .ev-none, not inside it"
    assert_equal "No screenshot", text(with_class(dash.sub(marker, ""), "sr-only") || flunk("no sibling .sr-only"))
    assert_equal "Could not be tried", text(evidence_cell(rows[4]))
    refute_includes evidence_cell(rows[4]), "—"
  end

  # B-R16: element ids are unique, so every link lands on one place.
  def test_ids_are_unique_in_both_files
    [client_html(:fail), internal_html(:fail)].each do |html|
      duplicates = ids(html).tally.select { |_, count| count > 1 }.keys

      assert_empty duplicates
    end
  end
end
