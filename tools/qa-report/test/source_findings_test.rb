require_relative "test_helper"

# The source fields card C reads: issue status fields (C-R2), note coverage column (C-R4),
# screenshot dpr (C-R11) and the internal capture reason (C-R10).
class SourceFindingsTest < Minitest::Test
  # AC: a WON'T FIX issue with no reason rejects the source (C-R2).
  def test_wont_fix_without_a_reason_rejects_the_source
    error = assert_rejected("issues[D8].status_reason_plain") do
      source_from(:fail) { |data| find_by_id(data["issues"], "D8").delete("status_reason_plain") }
    end

    assert_match(/WON'T FIX/, error.message)
  end

  # C-R2: the status line is computed now, so the old authored note is not a schema key.
  def test_an_authored_status_note_is_no_longer_accepted
    assert_rejected("issues[D3].status_note_plain") do
      source_from(:fail) { |data| find_by_id(data["issues"], "D3")["status_note_plain"] = "Open as of October 2, 2026." }
    end
  end

  def test_fixed_in_must_be_a_list_of_text
    assert_rejected("issues[D1].fixed_in") { source_from(:fail) { |data| find_by_id(data["issues"], "D1")["fixed_in"] = "PR #101" } }
  end

  def test_retested_on_must_be_a_date
    assert_rejected("issues[D2].retested_on") do
      source_from(:fail) { |data| find_by_id(data["issues"], "D2")["retested_on"] = "October 2" }
    end
  end

  # C-R4: a note's coverage column must be one of the coverage columns.
  def test_a_note_tied_to_an_unknown_coverage_column_rejects_the_source
    assert_rejected("notes[N2].coverage_column") do
      source_from(:pass_with_notes) { |data| find_by_id(data["notes"], "N2")["coverage_column"] = "Sepia" }
    end
  end

  # C-R4: the column decides a client-visible badge, so it is client data.
  def test_coverage_column_is_in_the_client_view
    notes = QaReport::Projection.client(load_fixture(:pass_with_notes))["notes"]

    assert_equal "Dark", find_by_id(notes, "N2")["coverage_column"]
  end

  # C-R11: dpr is a positive whole number when present.
  def test_dpr_must_be_a_positive_whole_number
    [0, -1, "2", 1.5].each do |value|
      assert_rejected("screenshots[1a].dpr") do
        source_from(:pass_with_notes) { |data| find_by_id(data["screenshots"], "1a")["dpr"] = value }
      end
    end
    assert_kind_of QaReport::Source, source_from(:pass_with_notes) { |data| find_by_id(data["screenshots"], "1a")["dpr"] = 3 }
  end

  # C-R10: an internal capture must say why it is internal; the appendix shows the reason.
  def test_an_internal_screenshot_without_a_reason_rejects_the_source
    assert_rejected("screenshots[4a].internal_reason") do
      source_from(:pass_with_notes) { |data| find_by_id(data["screenshots"], "4a").delete("internal_reason") }
    end
  end

  # C-R10: the reason is internal, so the client view never carries it.
  def test_internal_reason_never_reaches_the_client_view
    client = QaReport::Projection.client(load_fixture(:pass_with_notes))

    refute_includes JSON.generate(client), "CANARY-INTERNAL-REASON"
    assert client["screenshots"].none? { |shot| shot.key?("internal_reason") }
  end

  # Every screenshot must say client or internal, or it would silently vanish from both 05 and A7.
  def test_a_screenshot_with_no_visibility_rejects_the_source
    error = assert_rejected("screenshots[1a].visibility") do
      source_from(:pass_with_notes) { |data| find_by_id(data["screenshots"], "1a").delete("visibility") }
    end

    assert_match(/client or internal/, error.message)
  end

  # The value is exact, so "Client" is a typo, not a visibility.
  def test_a_screenshot_with_an_unknown_visibility_rejects_the_source
    assert_rejected("screenshots[1a].visibility") do
      source_from(:pass_with_notes) { |data| find_by_id(data["screenshots"], "1a")["visibility"] = "Client" }
    end
  end

  # The rule holds on internal-only projects too, where no client view is ever built.
  def test_an_internal_only_project_still_rejects_a_screenshot_with_no_visibility
    error = assert_raises(QaReport::InvalidSource) do
      source = source_from(:pass_with_notes) { |data| find_by_id(data["screenshots"], "1a").delete("visibility") }
      renderer_for(source, client: nil).internal_html
    end

    assert_equal 1, error.exit_code
  end
end
