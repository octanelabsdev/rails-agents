require_relative "test_helper"

# A-R1/A-R2: a client key's value must be the type the schema names, or nested content rides into the client view.
class ValueTypesTest < Minitest::Test
  def assert_rejected_without_leaking(path, secret, &block)
    error = assert_rejected(path, &block)
    refute_includes error.message, secret, "the rejection message must not echo the smuggled value"
  end

  def test_a_mapping_smuggled_into_summary_lead_rejects_the_source
    assert_rejected_without_leaking("summary.lead", "SECRET-ROOT") do
      source_from(:pass_with_notes) { |data| data["summary"]["lead"] = { "text" => "x", "root_cause" => "SECRET-ROOT" } }
    end
  end

  def test_a_mapping_inside_coverage_cells_rejects_the_source
    assert_rejected_without_leaking("coverage.rows[0].cells", "SECRET-ROOT") do
      source_from(:pass_with_notes) { |data| data["coverage"]["rows"][0]["cells"][1] = { "root_cause" => "SECRET-ROOT" } }
    end
  end

  def test_a_mapping_inside_issue_steps_rejects_the_source
    assert_rejected_without_leaking("issues[D7].steps_plain", "SECRET-ROOT") do
      source_from(:fail) { |data| find_by_id(data["issues"], "D7")["steps_plain"] << { "root_cause" => "SECRET-ROOT" } }
    end
  end

  # Mixed key types cannot be sorted, so the digest would crash instead of failing closed.
  def test_a_mapping_with_mixed_key_types_rejects_the_source_instead_of_crashing
    assert_rejected("summary.lead") do
      source_from(:pass_with_notes) { |data| data["summary"]["lead"] = { 1 => "a", "b" => "c" } }
    end
  end

  def test_a_list_where_text_is_expected_rejects_the_source
    assert_rejected("feature_title_plain") do
      source_from(:pass_with_notes) { |data| data["feature_title_plain"] = ["Proposal sections", "keep their order"] }
    end
  end

  def test_a_scalar_where_a_list_of_journey_ids_is_expected_rejects_the_source
    assert_rejected("requirements[R1].journeys") do
      source_from(:pass_with_notes) { |data| find_by_id(data["requirements"], "R1")["journeys"] = 1 }
    end
  end

  def test_a_mapping_where_coverage_columns_are_expected_rejects_the_source
    assert_rejected("coverage.columns") do
      source_from(:pass_with_notes) { |data| data["coverage"]["columns"] = { "Light" => "PASS" } }
    end
  end

  def test_a_tested_on_that_is_not_a_date_rejects_the_source
    assert_rejected("tested_on") do
      source_from(:pass_with_notes) { |data| data["tested_on"] = "yesterday" }
    end
  end

  def test_journey_evidence_as_a_single_id_rejects_the_source
    assert_rejected("journeys[3].evidence") do
      source_from(:pass_with_notes) { |data| find_by_id(data["journeys"], 3)["evidence"] = "1a" }
    end
  end

  def test_journey_evidence_as_null_rejects_the_source
    assert_rejected("journeys[1].evidence") do
      source_from(:pass_with_notes) { |data| find_by_id(data["journeys"], 1)["evidence"] = nil }
    end
  end

  # Array(false) is [false], so a lenient check would let false through as evidence.
  def test_journey_evidence_as_false_rejects_the_source
    assert_rejected("journeys[1].evidence") do
      source_from(:pass_with_notes) { |data| find_by_id(data["journeys"], 1)["evidence"] = false }
    end
  end
end
