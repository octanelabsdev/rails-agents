require_relative "test_helper"

# Problems that stop only the client view (exit 2); the internal view is still produced.
class ClientBlockingTest < Minitest::Test
  def test_both_fixtures_build_a_client_view
    assert_kind_of Hash, QaReport::Projection.client(load_fixture(:pass_with_notes))
    assert_kind_of Hash, QaReport::Projection.client(load_fixture(:fail))
  end

  # AC17 (A-R10)
  def test_a_note_with_no_client_facing_value_blocks_the_client_view
    source = source_from(:pass_with_notes) { |data| find_by_id(data["notes"], "N2").delete("client_facing") }

    assert_client_blocked source, "notes[N2].client_facing"
  end

  # A-R10
  def test_a_screenshot_with_no_visibility_value_blocks_the_client_view
    source = source_from(:pass_with_notes) { |data| find_by_id(data["screenshots"], "1a").delete("visibility") }

    assert_client_blocked source, "screenshots[1a].visibility"
  end

  # AC18 (A-R10)
  def test_a_screenshot_with_empty_alt_text_blocks_the_client_view
    source = source_from(:pass_with_notes) { |data| find_by_id(data["screenshots"], "1a")["alt"] = "" }

    assert_client_blocked source, "screenshots[1a].alt"
  end

  # AC19 (A-R10, A-R12)
  def test_a_screenshot_with_pixels_clean_false_blocks_only_the_client_view
    source = source_from(:pass_with_notes) { |data| find_by_id(data["screenshots"], "1a")["pixels_clean"] = false }

    assert_client_blocked source, "screenshots[1a].pixels_clean"
  end

  # AC20 (A-R10)
  def test_a_journey_with_no_client_evidence_and_no_evidence_note_blocks_the_client_view
    source = source_from(:pass_with_notes) do |data|
      journey = find_by_id(data["journeys"], 1)
      journey["evidence"] = []
      journey.delete("evidence_note_plain")
    end

    assert_client_blocked source, "journeys[1].evidence"
  end

  # A-R10: evidence that only points at internal screenshots is not client-visible evidence.
  def test_a_journey_whose_only_evidence_is_internal_screenshots_blocks_the_client_view
    source = source_from(:pass_with_notes) do |data|
      find_by_id(data["screenshots"], "3a")["visibility"] = "internal"
    end

    assert_client_blocked source, "journeys[7].evidence"
  end

  # AC13 (A-R7, A-R10)
  def test_a_verdict_override_with_no_reason_blocks_the_client_view
    source = source_from(:pass_with_notes) { |data| data["verdict_override"] = { "verdict" => "PASS" } }

    assert_client_blocked source, "verdict_override.reason"
  end

  # A-R7
  def test_a_verdict_override_with_a_blank_reason_blocks_the_client_view
    source = source_from(:pass_with_notes) { |data| data["verdict_override"] = { "verdict" => "PASS", "reason" => "  " } }

    assert_client_blocked source, "verdict_override.reason"
  end

  def test_the_internal_view_of_a_blocked_source_still_carries_the_offending_note
    source = source_from(:pass_with_notes) { |data| find_by_id(data["notes"], "N2").delete("client_facing") }

    assert_includes JSON.generate(QaReport::Projection.internal(source)), "The dark theme was not covered in this round"
  end
end
