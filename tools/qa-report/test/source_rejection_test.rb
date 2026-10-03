require_relative "test_helper"

# Rejections that stop both variants: the source is invalid and nothing is produced (exit 1).
class SourceRejectionTest < Minitest::Test
  def test_both_fixtures_load_as_valid_sources
    assert_kind_of QaReport::Source, load_fixture(:pass_with_notes)
    assert_kind_of QaReport::Source, load_fixture(:fail)
  end

  # AC1 (A-R1)
  def test_an_unclassed_top_level_key_rejects_the_source
    assert_rejected("client_nickname") do
      source_from(:pass_with_notes) { |data| data["client_nickname"] = "Cedar" }
    end
  end

  def test_an_unclassed_key_inside_a_journey_rejects_the_source
    assert_rejected("journeys[1].nickname") do
      source_from(:pass_with_notes) { |data| find_by_id(data["journeys"], 1)["nickname"] = "the first one" }
    end
  end

  def test_an_unclassed_key_inside_the_internal_block_rejects_the_source
    assert_rejected("internal.favourite_colour") do
      source_from(:pass_with_notes) { |data| data["internal"]["favourite_colour"] = "CANARY-INTERNAL-COLOUR" }
    end
  end

  # A-R6: computed values have no authoring key, so writing one is an unclassed key.
  def test_hand_written_verdict_explainer_stats_headings_or_issue_order_reject_the_source
    %w[verdict explainer stats summary_heading issue_order].each do |key|
      assert_rejected(key) do
        source_from(:pass_with_notes) { |data| data[key] = "PASS" }
      end
    end
  end

  # AC15 (A-R9, A-R1)
  def test_a_placeholder_screenshot_rejects_the_source_and_points_to_owner_decision_6
    error = assert_rejected("screenshots[1b].placeholder") do
      source_from(:pass_with_notes) { |data| find_by_id(data["screenshots"], "1b")["placeholder"] = true }
    end

    assert_includes error.message, "owner decision 6"
    assert_match(/retake/i, error.message)
  end

  def test_a_placeholder_key_set_to_false_still_rejects_the_source
    assert_rejected("screenshots[1b].placeholder") do
      source_from(:pass_with_notes) { |data| find_by_id(data["screenshots"], "1b")["placeholder"] = false }
    end
  end

  # A-R9: architect resolution A1 dropped the attestation field.
  def test_a_capture_verified_key_rejects_the_source
    assert_rejected("screenshots[1a].capture_verified") do
      source_from(:pass_with_notes) { |data| find_by_id(data["screenshots"], "1a")["capture_verified"] = true }
    end
  end

  # AC16 (A-R12)
  def test_a_missing_screenshot_file_rejects_the_source
    with_fixture_copy(:pass_with_notes) do |root|
      File.delete(File.join(root, "pass_with_notes/screenshots/1b.png"))

      assert_rejected("screenshots[1b].file") { source_from(:pass_with_notes, root: root) }
    end
  end

  # AC16 (A-R12)
  def test_a_text_file_renamed_to_png_rejects_the_source
    with_fixture_copy(:pass_with_notes) do |root|
      File.write(File.join(root, "pass_with_notes/screenshots/1b.png"), "this is a text file, not a capture\n")

      assert_rejected("screenshots[1b].file") { source_from(:pass_with_notes, root: root) }
    end
  end
end
