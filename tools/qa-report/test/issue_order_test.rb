require_relative "test_helper"

# A-R8: severity, then OPEN first, then authored order as the stable tiebreak.
class IssueOrderTest < Minitest::Test
  # AC14 (A-R8)
  def test_fail_fixture_issues_authored_d1_to_d8_are_ordered_as_the_approved_mock
    assert_equal %w[D2 D3 D4 D5 D1 D6 D7 D8], load_fixture(:fail).ordered_issues.map { |issue| issue["id"] }
  end

  def test_tied_issues_keep_their_authored_order
    source = source_from(:pass_with_notes) do |data|
      data["notes"] = []
      data["issues"] = [
        issue_data("M-closed-1", "MAJOR", "FIXED & VERIFIED"),
        issue_data("T-open", "TRIVIAL", "OPEN"),
        issue_data("M-open-1", "MAJOR", "OPEN"),
        issue_data("M-deferred", "MAJOR", "DEFERRED"),
        issue_data("B-closed", "BLOCKER", "WON'T FIX"),
        issue_data("M-open-2", "MAJOR", "OPEN"),
        issue_data("M-closed-2", "MAJOR", "FIXED · NOT YET RE-TESTED"),
        issue_data("N-open", "MINOR", "OPEN")
      ]
    end

    expected = %w[B-closed M-open-1 M-open-2 M-closed-1 M-deferred M-closed-2 N-open T-open]
    assert_equal expected, source.ordered_issues.map { |issue| issue["id"] }
  end

  def test_the_client_view_lists_issues_in_computed_order
    client = QaReport::Projection.client(load_fixture(:fail))

    assert_equal %w[D2 D3 D4 D5 D1 D6 D7 D8], client["issues"].map { |issue| issue["id"] }
  end

  def test_an_unknown_severity_or_status_rejects_the_source
    assert_rejected("issues[D7].severity") do
      source_from(:fail) { |data| find_by_id(data["issues"], "D7")["severity"] = "CRITICAL" }
    end
    assert_rejected("issues[D7].status") do
      source_from(:fail) { |data| find_by_id(data["issues"], "D7")["status"] = "DONE" }
    end
  end
end
