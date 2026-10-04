require_relative "test_helper"

# C-R1 to C-R5, C-R9, C-R17: 04 Issues found, Notes (not issues), 06 How we tested and the section numbering.
class RenderFindingsTest < Minitest::Test
  ISSUES = "04 · Issues found"

  def issue_cards(html) = all_with_class(section(html, ISSUES), "issue", tag: "article")

  def card(html, id)
    issue_cards(html).find { |candidate| text(candidate).start_with?("Issue #{id}") } || flunk("no card for issue #{id}")
  end

  def status_line(card) = text(with_class(card, "status-line") || flunk("issue card has no status line"))

  def notes_block(html)
    block = with_class(section(html, ISSUES), "notes-block") || flunk("04 has no Notes (not issues) block")
    assert_equal "Notes (not issues)", text(element(block, "h3"))
    block
  end

  def note_cards(html) = all_with_class(notes_block(html), "note", tag: "article")

  def note(html, title)
    note_cards(html).find { |candidate| text(candidate).include?(title) } || flunk("no note titled #{title.inspect}")
  end

  def badge_words(fragment) = all_with_class(fragment, "badge", tag: "span").map { |badge| text(badge).upcase }

  def desktop_links(html)
    nav = element(html, "nav", /aria-label="Contents"/) || flunk("no Contents nav")
    nav.sub(element(nav, "details").to_s, "").scan(/<a\b[^>]*\bhref="#([^"]+)"/).flatten
  end

  def eyebrows(html)
    elements(html, "section").filter_map { |candidate| text(with_class(candidate, "eyebrow").to_s) }.grep(/\A\d\d · /)
  end

  # The fail fixture with every screenshot removed, each journey keeping a written evidence note.
  def fail_without_screenshots(&extra)
    source_from(:fail) do |data|
      data["screenshots"] = []
      data["journeys"].each { |journey| journey.merge!("evidence" => [], "evidence_note_plain" => "Checked directly") }
      data["issues"].each { |issue| issue.delete("screenshot") }
      extra&.call(data)
    end
  end

  # AC: the fail fixture shows 8 cards in the computed order (C-R1).
  def test_issue_cards_follow_the_computed_order
    ids = issue_cards(client_html(:fail)).map { |candidate| text(candidate)[/\AIssue (D\d+)/, 1] }

    assert_equal %w[D2 D3 D4 D5 D1 D6 D7 D8], ids
  end

  # AC: D2 shows its eyebrow, a solid BLOCKER badge, title, what happens, numbered steps, expected and actual (C-R1).
  def test_an_issue_card_shows_every_part_in_order
    d2 = card(client_html(:fail), "D2")
    eyebrow = with_class(d2, "eyebrow") || flunk("D2 has no eyebrow")

    assert_equal "ISSUE D2", text(eyebrow).upcase
    severity = all_with_class(d2, "badge", tag: "span").first
    assert_includes classes(severity), "t-solid", "a BLOCKER badge is solid"
    assert_includes severity, "#g-octagon"
    assert_equal "BLOCKER", text(severity).upcase
    assert_equal "Creating a new proposal fails with an error when a diagram image is attached", text(element(d2, "h3"))
    words = text(d2)
    order = ["What happens", "Steps to reproduce", "Expected", "Actual"].map { |label| words.index(label) || flunk("D2 lacks #{label}") }
    assert_equal order.sort, order
    steps = elements(element(d2, "ol") || flunk("steps must be a numbered list"), "li")
    assert_equal 4, steps.size
    assert_equal "Open the New proposal screen.", text(steps.first)
    assert with_class(d2, "exp-act"), "Expected and Actual sit in one .exp-act block"
  end

  # C-R1: each severity has its own glyph and each card a status badge.
  def test_severity_badges_use_their_own_glyphs
    html = client_html(:fail)

    { "D3" => ["MAJOR", "#g-triangle"], "D7" => ["MINOR", "#g-circlebang"] }.each do |id, (word, glyph)|
      severity = all_with_class(card(html, id), "badge", tag: "span").first
      assert_equal word, text(severity).upcase
      assert_includes severity, glyph
    end
    source = source_from(:fail) { |data| find_by_id(data["issues"], "D7")["severity"] = "TRIVIAL" }
    trivial = all_with_class(card(client_html(source), "D7"), "badge", tag: "span").first
    assert_equal "TRIVIAL", text(trivial).upcase
    assert_includes trivial, "#g-dot"
    assert_equal ["MAJOR", "OPEN"], badge_words(card(html, "D3")).first(2)
  end

  # AC: the status line is computed from the status and its fields (C-R2).
  def test_status_lines_are_computed_from_the_status
    html = client_html(:fail)

    assert_equal "Open as of October 2, 2026.", status_line(card(html, "D3"))
    assert_equal "Fixed in PR #101; awaiting re-test.", status_line(card(html, "D1"))
    assert_equal "Fixed in PR #102 and PR #103; re-tested October 2, 2026.", status_line(card(html, "D2"))
    assert status_line(card(html, "D6")).start_with?("Deferred. Reason:"), status_line(card(html, "D6"))
    assert status_line(card(html, "D8")).start_with?("Won't fix. Reason:"), status_line(card(html, "D8"))
    assert_includes status_line(card(html, "D8")), "The field is meant for private notes"
  end

  # C-R2: the report date is status_as_of when set, else tested_on.
  def test_open_status_line_falls_back_to_the_tested_on_date
    source = source_from(:fail) { |data| data.delete("status_as_of") }

    assert_equal "Open as of October 1, 2026.", status_line(card(client_html(source), "D3"))
  end

  # C-R1: an issue's client screenshot is linked from its card; the image itself is embedded once, in 05.
  def test_an_issue_with_a_screenshot_links_to_it
    d4 = card(client_html(:fail), "D4")

    assert_match(/<a\b[^>]*href="#shot-2a"/, d4)
    refute_includes d4, "data:image/", "the issue card must reuse the screenshot in 05, not embed a second copy"
  end

  # AC: 0 issues keeps the heading and shows the success card (C-R3).
  def test_zero_issues_shows_the_no_issues_card
    issues = section(client_html(:pass_with_notes), ISSUES)

    assert_equal "Nothing needs fixing", text(element(issues, "h2"))
    zero = with_class(issues, "zero") || flunk("04 has no success card")
    assert_equal "No issues found", text(element(zero, "h3"))
    assert_includes text(zero), "We didn't find anything that needed fixing in this round of testing."
    assert_empty issue_cards(client_html(:pass_with_notes))
  end

  # C-R1: the H2 is the computed issues heading.
  def test_issues_heading_is_computed
    assert_equal "8 issues found, 4 still open", text(element(section(client_html(:fail), ISSUES), "h2"))
  end

  # B's print rules force breaks only through .pb; 04 earns it only when it has issue cards.
  def test_issues_section_breaks_the_page_only_when_issues_were_found
    assert_includes classes(section(internal_html(:fail), ISSUES)), "pb"
    refute_includes classes(section(internal_html(:pass_with_notes), ISSUES)), "pb"
  end

  # AC: client shows only client_facing notes; internal shows every note (C-R4).
  def test_notes_block_shows_client_facing_notes_in_the_client_file_and_every_note_internally
    client = note_cards(client_html(:pass_with_notes)).map { |candidate| text(candidate) }
    internal = note_cards(internal_html(:pass_with_notes)).map { |candidate| text(candidate) }

    assert_equal 2, client.size
    refute client.any? { |words| words.include?("paginates at 25 rows") }, "a client_facing: false note reached the client"
    assert_equal 3, internal.size
    assert internal.any? { |words| words.include?("paginates at 25 rows") }
  end

  # AC: a note tied to an all-NOT TESTED column reads NOT TESTED; any other note reads OBSERVED (C-R4).
  def test_note_badges_follow_the_coverage_column
    html = client_html(:pass_with_notes)

    assert_equal ["OBSERVED"], badge_words(note(html, "Older proposals may still show sections"))
    assert_equal ["NOT TESTED"], badge_words(note(html, "The dark theme was not covered"))
  end

  # C-R4: a column with even one tested cell does not make its note NOT TESTED.
  def test_a_note_tied_to_a_partly_tested_column_reads_observed
    source = source_from(:pass_with_notes) { |data| find_by_id(data["notes"], "N2")["coverage_column"] = "Light" }

    assert_equal ["OBSERVED"], badge_words(note(client_html(source), "The dark theme was not covered"))
  end

  # C-R4: a note's recommendation renders under it.
  def test_a_note_shows_its_recommendation
    assert_includes text(note(client_html(:pass_with_notes), "Older proposals")), "A one-time clean-up of existing proposals"
  end

  # AC: root cause and file references appear in neither file's 04, nor anywhere in the client file (C-R5).
  def test_root_cause_never_renders_in_section_04
    internal = internal_html(:fail)
    client = client_html(:fail)
    reference = "app/views/reports/show.pdf.erb:12"

    refute_includes section(internal, ISSUES), reference
    refute_includes section(client, ISSUES), reference
    refute_includes client, reference
    refute_includes client, "CANARY-INTERNAL-D"
  end

  # C-R5: the internal card links to its root cause in A3 inside a marked internal region.
  def test_internal_issue_card_links_to_its_root_cause
    d4 = card(internal_html(:fail), "D4")

    assert_match(%r{<!--int--><a class="int-link" href="#a3-d4"[^>]*>Root cause \(appendix\)</a><!--/int-->}, d4)
  end

  # AC: 06 How we tested shows the authored sentences in both files (C-R9).
  def test_how_we_tested_renders_the_authored_text_in_both_files
    expected = load_fixture(:pass_with_notes).data["how_we_tested_plain"].strip
    [client_html(:pass_with_notes), internal_html(:pass_with_notes)].each do |html|
      how = section(html, "06 · How we tested")

      assert_equal "How we tested", text(element(how, "h2"))
      assert_equal 4, expected.scan(/[^.]+\./).size, "the fixture authors 4 sentences"
      assert_includes text(how), expected
    end
  end

  # C-R9: blank lines start new paragraphs and authored markup is escaped.
  def test_how_we_tested_splits_paragraphs_and_escapes_markup
    source = source_from(:pass_with_notes) { |data| data["how_we_tested_plain"] = "First <b>part</b>.\n\nSecond part." }
    how = section(client_html(source), "06 · How we tested")

    assert_equal ["First <b>part</b>.", "Second part."], elements(how, "p").map { |paragraph| text(paragraph) }
    refute_includes how, "<b>part</b>"
  end

  # C-R17: with client screenshots the sections run 01 to 06 and Contents links 6 of them.
  def test_with_client_screenshots_the_sections_run_to_06
    [client_html(:pass_with_notes), internal_html(:pass_with_notes)].each do |html|
      assert_equal ["01 · Summary", "02 · What we checked", "03 · Journeys", "04 · Issues found", "05 · Screenshots",
                    "06 · How we tested"], eyebrows(html)
      assert_equal 6, desktop_links(html).size
    end
  end

  # AC: 0 client screenshots drops 05 from both files, How we tested is 05 and Contents has 5 links (C-R17).
  def test_no_screenshots_means_no_screenshots_section_and_how_we_tested_is_05
    source = fail_without_screenshots
    client = client_html(source)
    internal = internal_html(source)

    [client, internal].each do |html|
      assert_empty eyebrows(html).grep(/Screenshots/)
      assert_equal "05 · How we tested", eyebrows(html).last
      assert_equal 5, desktop_links(html).size
    end
    assert_equal desktop_links(client), desktop_links(internal)
  end

  # AC: only internal screenshots behaves like none in the body, and the bodies stay identical (C-R17, C-R6, C-R10).
  def test_internal_only_screenshots_keep_both_bodies_identical
    source = fail_without_screenshots do |data|
      data["screenshots"] = %w[1a 1b].map do |id|
        { "id" => id, "file" => "fail/screenshots/#{id}.png", "group_plain" => "Admin tools", "variant" => "Light",
          "caption" => "CANARY-CAPTION-#{id}", "focal" => "top", "visibility" => "internal",
          "internal_reason" => "CANARY-REASON-#{id} shows the staging admin." }
      end
    end
    client = client_html(source)
    internal = internal_html(source)

    [client, internal].each do |html|
      assert_empty eyebrows(html).grep(/Screenshots/)
      assert_equal "05 · How we tested", eyebrows(html).last
      assert_equal 5, desktop_links(html).size
    end
    assert strip_internal(internal) == client, "internal minus <!--int--> regions != client"
    a7 = text(section(internal, "A · Internal appendix"))
    %w[1a 1b].each do |id|
      assert_includes a7, "CANARY-CAPTION-#{id}"
      assert_includes a7, "CANARY-REASON-#{id}"
      refute_includes client, "CANARY-CAPTION-#{id}"
    end
  end
end
