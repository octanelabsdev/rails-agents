require_relative "test_helper"

# A source must be internally consistent before a verdict computed from it can be trusted (A-R3, A-R6).
class SourceIntegrityTest < Minitest::Test
  REQUIRED = {
    top: %w[schema_version card feature_title_plain project_plain tested_on environment_label build_plain summary
            how_we_tested_plain requirements coverage journeys issues notes screenshots internal],
    summary: %w[lead tested found means next],
    coverage: %w[columns rows],
    requirement: %w[id text_plain result journeys],
    journey: %w[id title_plain description_plain result evidence],
    issue: %w[id severity status title_plain impact_plain steps_plain expected_plain actual_plain],
    note: %w[id title_plain body_plain],
    screenshot: %w[id file group_plain variant caption]
  }.freeze

  # Where each kind lives in a fixture, its error-path label, and the list-position label used when its id is missing.
  LOCATIONS = {
    top: [:pass_with_notes, ->(data) { data }, ""],
    summary: [:pass_with_notes, ->(data) { data["summary"] }, "summary."],
    coverage: [:pass_with_notes, ->(data) { data["coverage"] }, "coverage."],
    requirement: [:pass_with_notes, ->(data) { data["requirements"][0] }, "requirements[R1].", "requirements[0]."],
    journey: [:pass_with_notes, ->(data) { data["journeys"][0] }, "journeys[1].", "journeys[0]."],
    issue: [:fail, ->(data) { find_by_id(data["issues"], "D7") }, "issues[D7].", "issues[6]."],
    note: [:pass_with_notes, ->(data) { data["notes"][0] }, "notes[N1].", "notes[0]."],
    screenshot: [:pass_with_notes, ->(data) { data["screenshots"][0] }, "screenshots[1a].", "screenshots[0]."]
  }.freeze

  REQUIRED.each do |kind, keys|
    fixture, locate, prefix, id_prefix = LOCATIONS.fetch(kind)
    keys.each do |key|
      define_method("test_a_missing_#{kind}_#{key}_rejects_the_source") do
        assert_rejected("#{key == "id" ? id_prefix : prefix}#{key}") do
          source_from(fixture) { |data| instance_exec(data, &locate).delete(key) }
        end
      end
    end
  end

  def test_an_open_issue_without_a_status_note_loads
    source = source_from(:pass_with_notes) do |data|
      data["issues"] = [issue_data("D1", "MINOR", "OPEN").tap { |issue| issue.delete("status_note_plain") }]
    end

    assert_kind_of QaReport::Source, source
  end

  def test_an_empty_requirements_list_rejects_the_source
    assert_rejected("requirements") do
      source_from(:pass_with_notes) { |data| data["requirements"] = [] }
    end
  end

  def test_a_failing_journey_no_unmet_requirement_points_to_rejects_the_source
    error = assert_rejected("journeys[2].result") do
      source_from(:pass_with_notes) { |data| find_by_id(data["journeys"], 2)["result"] = "FAIL" }
    end

    assert_match(/failing journey must trace to an unmet requirement/i, error.message)
  end

  def test_a_blocked_journey_no_unmet_requirement_points_to_rejects_the_source
    assert_rejected("journeys[5].result") do
      source_from(:pass_with_notes) { |data| find_by_id(data["journeys"], 5)["result"] = "BLOCKED" }
    end
  end

  def test_a_failing_journey_traced_to_an_unmet_requirement_loads_and_fails
    source = source_from(:pass_with_notes) do |data|
      find_by_id(data["journeys"], 2)["result"] = "FAIL"
      find_by_id(data["requirements"], "R1")["result"] = "NOT MET"
    end

    assert_equal "FAIL", source.verdict
  end

  def test_a_requirement_pointing_at_an_unknown_journey_rejects_the_source
    assert_rejected("requirements[R1].journeys") do
      source_from(:pass_with_notes) { |data| find_by_id(data["requirements"], "R1")["journeys"] = [1, 99] }
    end
  end

  def test_duplicate_requirement_ids_reject_the_source
    assert_rejected("requirements[R1]") do
      source_from(:pass_with_notes) { |data| data["requirements"] << data["requirements"][0].dup }
    end
  end

  def test_duplicate_journey_ids_reject_the_source
    assert_rejected("journeys[1]") do
      source_from(:pass_with_notes) { |data| data["journeys"] << data["journeys"][0].dup }
    end
  end

  def test_duplicate_issue_ids_reject_the_source
    assert_rejected("issues[D3]") do
      source_from(:fail) { |data| data["issues"] << find_by_id(data["issues"], "D3").dup }
    end
  end

  def test_duplicate_note_ids_reject_the_source
    assert_rejected("notes[N1]") do
      source_from(:pass_with_notes) { |data| data["notes"] << data["notes"][0].dup }
    end
  end

  # Ids are how evidence resolves, so a shared id could pull an internal capture into the client view.
  def test_a_client_and_an_internal_screenshot_sharing_an_id_reject_the_source
    assert_rejected("screenshots[1a]") do
      source_from(:pass_with_notes) do |data|
        data["screenshots"] << find_by_id(data["screenshots"], "2a").merge("id" => "1a", "visibility" => "internal")
      end
    end
  end
end
