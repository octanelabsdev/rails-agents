require_relative "test_helper"

class VerdictTest < Minitest::Test
  # The pass-with-notes fixture with its requirements and journeys kept, and the issues and notes under test swapped in.
  def all_met_source(issues: [], notes: [])
    source_from(:pass_with_notes) do |data|
      data["issues"] = issues
      data["notes"] = notes
    end
  end

  # AC3 (A-R5, A-R6)
  def test_all_requirements_met_with_no_issues_and_no_notes_is_pass
    assert_equal "PASS", all_met_source.verdict
  end

  # AC4 (A-R4)
  def test_pass_with_notes_fixture_with_two_client_notes_is_pass_with_notes
    assert_equal "PASS WITH NOTES", load_fixture(:pass_with_notes).verdict
  end

  # AC4 (A-R4, owner decision 1): a client-facing note alone is enough.
  def test_a_single_client_facing_note_with_no_issues_is_pass_with_notes
    assert_equal "PASS WITH NOTES", all_met_source(notes: [note_data("N1")]).verdict
  end

  def test_a_note_that_is_not_client_facing_does_not_lower_pass
    note = note_data("N1").merge("client_facing" => false)

    assert_equal "PASS", all_met_source(notes: [note]).verdict
  end

  # AC5 (A-R4)
  def test_an_open_minor_issue_is_pass_with_notes
    assert_equal "PASS WITH NOTES", all_met_source(issues: [issue_data("D1", "MINOR", "OPEN")]).verdict
  end

  # A-R4
  def test_an_open_trivial_issue_is_pass_with_notes
    assert_equal "PASS WITH NOTES", all_met_source(issues: [issue_data("D1", "TRIVIAL", "OPEN")]).verdict
  end

  # AC6 (A-R4)
  def test_a_deferred_major_issue_is_pass_with_notes
    assert_equal "PASS WITH NOTES", all_met_source(issues: [issue_data("D1", "MAJOR", "DEFERRED")]).verdict
  end

  # AC7 (A-R3, A-R5): adjudication 1, owner-confirmed.
  def test_a_major_issue_fixed_but_not_yet_re_tested_is_fail_and_not_counted_open
    source = all_met_source(issues: [issue_data("D1", "MAJOR", "FIXED · NOT YET RE-TESTED")])

    assert_equal "FAIL", source.verdict
    assert_equal 0, source.open_issue_count
  end

  # A-R3
  def test_a_blocker_fixed_but_not_yet_re_tested_is_fail
    assert_equal "FAIL", all_met_source(issues: [issue_data("D1", "BLOCKER", "FIXED · NOT YET RE-TESTED")]).verdict
  end

  # AC8 (A-R4)
  def test_a_minor_issue_fixed_but_not_yet_re_tested_is_pass_with_notes
    source = all_met_source(issues: [issue_data("D1", "MINOR", "FIXED · NOT YET RE-TESTED")])

    assert_equal "PASS WITH NOTES", source.verdict
  end

  # AC9 (A-R5)
  def test_major_issues_that_are_wont_fix_or_fixed_and_verified_still_pass
    source = all_met_source(
      issues: [issue_data("D1", "MAJOR", "WON'T FIX"), issue_data("D2", "MAJOR", "FIXED & VERIFIED")]
    )

    assert_equal "PASS", source.verdict
  end

  # AC10 (A-R3, A-R6)
  def test_fail_fixture_with_unmet_requirements_and_open_majors_is_fail
    source = load_fixture(:fail)

    assert_equal "FAIL", source.verdict
    assert_equal 4, source.open_issue_count, "the approved mock shows 4 open of 8 found"
  end

  # A-R3
  def test_one_unmet_requirement_with_no_issues_is_fail
    source = source_from(:pass_with_notes) do |data|
      data["notes"] = []
      find_by_id(data["requirements"], "R2")["result"] = "NOT MET"
    end

    assert_equal "FAIL", source.verdict
  end

  # A-R3
  def test_one_blocked_requirement_with_no_issues_is_fail
    source = source_from(:pass_with_notes) do |data|
      data["notes"] = []
      find_by_id(data["requirements"], "R3")["result"] = "BLOCKED"
    end

    assert_equal "FAIL", source.verdict
  end

  # AC11 (A-R3, A-R6): FAIL outranks PASS WITH NOTES.
  def test_an_open_blocker_with_a_client_note_is_fail_not_pass_with_notes
    source = all_met_source(issues: [issue_data("D1", "BLOCKER", "OPEN")], notes: [note_data("N1")])

    assert_equal "FAIL", source.verdict
  end

  # AC12 (A-R7, A-R2)
  def test_an_owner_override_with_a_reason_shows_in_both_views_and_the_reason_stays_internal
    reason = "Note 2 accepted by owner on 2026-10-02"
    source = source_from(:pass_with_notes) { |data| data["verdict_override"] = { "verdict" => "PASS", "reason" => reason } }

    client = QaReport::Projection.client(source)
    internal = QaReport::Projection.internal(source)

    assert_equal "PASS", source.verdict
    assert_equal "PASS WITH NOTES", source.computed_verdict
    assert_equal "PASS", client["verdict"]
    assert_equal "PASS", internal["verdict"]
    assert_includes JSON.generate(internal), reason
    refute_includes JSON.generate(client), reason
  end

  def test_an_override_to_an_unknown_verdict_rejects_the_source
    assert_rejected("verdict_override.verdict") do
      source_from(:pass_with_notes) { |data| data["verdict_override"] = { "verdict" => "MOSTLY FINE", "reason" => "Owner call" } }
    end
  end
end
