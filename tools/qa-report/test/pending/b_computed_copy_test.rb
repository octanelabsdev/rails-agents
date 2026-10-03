require_relative "../test_helper"

# Story B (B-R5 to B-R7) red step, parked here by the card A scope decision; bin/test skips test/pending/.
class ComputedCopyTest < Minitest::Test
  def test_pass_with_notes_fixture_explainer_reads_as_the_approved_mock
    assert_equal "All 3 requirements met. No issues found. 2 notes for you.", load_fixture(:pass_with_notes).explainer
  end

  def test_pass_with_notes_fixture_summary_heading_counts_its_notes
    assert_equal "Everything works, with 2 notes", load_fixture(:pass_with_notes).summary_heading
  end

  def test_pass_with_notes_fixture_stat_strip_counts
    stats = load_fixture(:pass_with_notes).stats

    assert_equal ["3 of 3", nil], stats[:requirements]
    assert_equal ["6 of 7", "1 observed"], stats[:journeys]
    assert_equal ["0", "0 found"], stats[:open_issues]
  end

  def test_fail_fixture_explainer_names_open_majors_and_the_fix_awaiting_re_test
    expected = "Not ready yet. 4 issues are still open, including 3 major ones. " \
      "1 major fix is waiting to be re-tested. 8 of 15 requirements are met."

    assert_equal expected, load_fixture(:fail).explainer
  end

  def test_fail_fixture_summary_heading
    assert_equal "Not ready yet, and here is why", load_fixture(:fail).summary_heading
  end

  def test_fail_fixture_stat_strip_matches_the_approved_mock
    stats = load_fixture(:fail).stats

    assert_equal ["8 of 15", "7 not met"], stats[:requirements]
    assert_equal ["4 of 10", "5 failed · 1 blocked"], stats[:journeys]
    assert_equal ["4", "8 found · 2 fixed"], stats[:open_issues]
    assert_equal ["Light · Dark · PDF", nil], stats[:tested_on]
  end

  def test_counted_nouns_and_verbs_follow_the_number
    source = source_from(:fail) do |data|
      data["requirements"] = data["requirements"].first(2)
      data["notes"] = []
      data["issues"] = data["issues"].values_at(0, 6).map(&:dup) # D1 MAJOR awaiting re-test, D7 MINOR OPEN
      data["issues"] << data["issues"].first.merge("id" => "D9")
    end

    expected = "Not ready yet. 1 issue is still open. 2 major fixes are waiting to be re-tested. " \
      "2 of 2 requirements are met."
    assert_equal expected, source.explainer
  end

  def test_a_single_open_major_reads_singular
    source = source_from(:fail) do |data|
      data["issues"] = data["issues"].select { |issue| %w[D2 D3].include?(issue["id"]) }
    end

    assert_equal "Not ready yet. 1 issue is still open, including 1 major one. 8 of 15 requirements are met.",
      source.explainer
  end
end
