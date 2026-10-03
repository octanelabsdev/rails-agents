require_relative "test_helper"

class StatsTest < Minitest::Test
  def test_pass_with_notes_fixture_counts
    counts = load_fixture(:pass_with_notes).counts

    assert_equal 3, counts[:requirements_met]
    assert_equal 3, counts[:requirements_total]
    assert_equal 6, counts[:journeys_passed]
    assert_equal 7, counts[:journeys_total]
    assert_equal 0, counts[:issues_open]
    assert_equal 0, counts[:issues_found]
    assert_equal 0, counts[:issues_fixed]
  end

  # Approved mock plus R15 for journey 3: "8 of 15", "4 of 10", "4 open · 8 found · 2 fixed".
  def test_fail_fixture_counts_match_the_approved_mock
    counts = load_fixture(:fail).counts

    assert_equal 8, counts[:requirements_met]
    assert_equal 15, counts[:requirements_total]
    assert_equal 4, counts[:journeys_passed]
    assert_equal 10, counts[:journeys_total]
    assert_equal 4, counts[:issues_open]
    assert_equal 8, counts[:issues_found]
    assert_equal 2, counts[:issues_fixed]
  end

  # A-R5: FIXED · NOT YET RE-TESTED is fixed, not open.
  def test_a_fix_awaiting_re_test_counts_as_fixed_not_open
    source = source_from(:pass_with_notes) do |data|
      data["issues"] = [issue_data("D1", "MAJOR", "FIXED · NOT YET RE-TESTED"), issue_data("D2", "MINOR", "OPEN")]
    end

    assert_equal 1, source.counts[:issues_open]
    assert_equal 1, source.counts[:issues_fixed]
    assert_equal 2, source.counts[:issues_found]
    assert_equal source.counts[:issues_open], source.open_issue_count
  end
end
