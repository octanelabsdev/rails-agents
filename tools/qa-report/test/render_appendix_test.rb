require_relative "test_helper"

# C-R5, C-R10: the internal appendix, A1 to A7, and its absence from the client file.
class RenderAppendixTest < Minitest::Test
  APPENDIX = "A · Internal appendix"
  HEADINGS = ["A1 · Environment & access", "A2 · Journey technical detail", "A3 · Issue root cause",
              "A4 · QA process & tooling notes", "A5 · Test data & cleanup", "A6 · Sources",
              "A7 · Internal-only captures"].freeze

  def appendix(html) = section(html, APPENDIX)

  def overridden
    source_from(:pass_with_notes) do |data|
      data["verdict_override"] = { "verdict" => "PASS WITH NOTES", "reason" => "Note 2 accepted by owner on 2026-10-02" }
    end
  end

  # The appendix text from one subsection heading up to the next.
  def subsection(html, number)
    words = text(appendix(html))
    start = words.index(HEADINGS[number - 1]) || flunk("appendix has no #{HEADINGS[number - 1]}")
    finish = HEADINGS[number] ? words.index(HEADINGS[number]) : words.size
    words[start...finish]
  end

  # AC: the internal file ends with appendix A, headed and subdivided A1 to A7 (C-R10).
  def test_internal_file_ends_with_the_appendix
    html = internal_html(:pass_with_notes)
    box = appendix(html)

    assert_equal "A · INTERNAL APPENDIX", text(with_class(box, "eyebrow")).upcase
    assert_equal "Internal appendix — not in the client version", text(element(box, "h2"))
    assert_equal HEADINGS, elements(box, "h3").map { |h3| text(h3) }
    main = element(html, "main") || flunk("no main")
    assert_equal box, elements(main, "section").last, "the appendix is the last section of main"
    assert_includes classes(box), "pb", "print starts the appendix on a new page through the pb marker"
    region = html.scan(%r{<!--int-->(.*?)<!--/int-->}m).flatten.find { |candidate| candidate.include?("Internal appendix") }
    assert region&.start_with?("<section") && region.rstrip.end_with?("</section>"),
      "the whole appendix sits in one marked internal region"
  end

  # AC: the client file has no appendix and no override reason (C-R10).
  def test_client_file_has_no_appendix
    client = client_html(overridden)

    refute_includes client, "Internal appendix"
    HEADINGS.each { |heading| refute_includes text(client), heading }
    refute_includes client, "Note 2 accepted by owner on 2026-10-02"
  end

  # AC: the verdict override reason renders in the appendix (C-R10, decision 1).
  def test_override_reason_renders_in_the_appendix
    assert_includes text(appendix(internal_html(overridden))), "Note 2 accepted by owner on 2026-10-02"
  end

  # C-R10: A1, A4, A5 and A6 carry the internal block's text under their own headings.
  def test_internal_block_fields_land_under_their_headings
    html = internal_html(:pass_with_notes)

    assert_includes subsection(html, 1), "CANARY-INTERNAL-ENV"
    assert_equal 2, subsection(html, 4).scan("CANARY-INTERNAL-PROCESS").size
    assert_includes subsection(html, 5), "CANARY-INTERNAL-CLEANUP"
    assert_includes subsection(html, 6), "CANARY-INTERNAL-SOURCES"
  end

  # AC: each A2 entry holds the journey's technical detail and links back to its journey (C-R10, C-R19).
  def test_a2_entries_link_back_to_their_journeys
    html = internal_html(:fail)
    box = appendix(html)

    load_fixture(:fail).journeys.each do |journey|
      id = QaReport::Source.slug(journey["id"])
      entry = box[/<\w+\b[^>]*\bid="a-j-#{id}"[^>]*>.*?(?=<h[34]\b|\z)/m] || flunk("A2 has no entry a-j-#{id}")
      assert_match(/<a\b[^>]*\bclass="backlink"[^>]*\bhref="#j-#{id}"|<a\b[^>]*\bhref="#j-#{id}"[^>]*\bclass="backlink"/, entry)
      assert_includes text(box), journey["technical_detail"].split.first
    end
  end

  # C-R19: a journey with no technical detail still gets the A2 entry its Technical detail link points to.
  def test_a2_has_an_entry_even_without_technical_detail
    source = source_from(:fail) { |data| find_by_id(data["journeys"], 3).delete("technical_detail") }

    assert_match(/\bid="a-j-3"/, appendix(internal_html(source)))
  end

  # AC: root cause text is in A3 only (C-R5).
  def test_root_cause_renders_in_a3
    html = internal_html(:fail)

    assert_includes subsection(html, 3), "app/views/reports/show.pdf.erb:12"
    assert_equal 1, html.scan("app/views/reports/show.pdf.erb:12").size
    assert_match(/\bid="a3-d4"/, appendix(html), "D4's card links to its A3 entry")
  end

  # AC: A7 lists each internal capture with its caption and its reason (C-R10).
  def test_a7_lists_internal_captures_with_caption_and_reason
    a7 = subsection(internal_html(:pass_with_notes), 7)

    assert_includes a7, "CANARY-INTERNAL-CAPTION API token list"
    assert_includes a7, "CANARY-INTERNAL-REASON Shows the staging API token list"
    refute_includes client_html(:pass_with_notes), "CANARY-INTERNAL-REASON"
  end

  # C-R10: appendix text is authored plain text, escaped like every other field.
  def test_appendix_text_is_escaped
    source = source_from(:fail) { |data| data["internal"]["cleanup"] = "Deleted <script>alert(1)</script> rows." }
    box = appendix(internal_html(source))

    refute_includes box, "<script>alert(1)</script>"
    assert_includes text(box), "Deleted <script>alert(1)</script> rows."
  end

  # C-R18: preformatted technical detail renders in a pre block the print rules can wrap.
  def test_multiline_technical_detail_renders_preformatted
    long = "x" * 300
    source = source_from(:fail) { |data| find_by_id(data["journeys"], 1)["technical_detail"] = "Ran it.\n#{long}" }

    assert_match(/<pre\b[^>]*>[^<]*#{long}/, appendix(internal_html(source)))
  end
end
