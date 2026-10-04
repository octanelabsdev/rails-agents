require_relative "test_helper"

# B-R5 to B-R7: every count-bearing string on the cover and in the section headings is computed, never authored.
class ComputedCopyTest < Minitest::Test
  OPEN = "OPEN"
  VERIFIED = "FIXED & VERIFIED"
  AWAITING = "FIXED · NOT YET RE-TESTED"

  # AC5 (B-R5, B-R5b)
  def test_pass_with_notes_fixture_explainer_reads_as_the_approved_mock
    assert_equal "All 3 requirements met. No issues found. 2 notes for you.",
      copy_for(load_fixture(:pass_with_notes)).explainer
  end

  # AC5 (B-R5, B-R5c)
  def test_fail_fixture_explainer_names_open_majors_and_the_fix_awaiting_re_test
    expected = "Not ready yet. 4 issues are still open, including 3 major ones. " \
               "1 major fix is waiting to be re-tested. 8 of 15 requirements are met."

    assert_equal expected, copy_for(load_fixture(:fail)).explainer
  end

  # AC6 (B-R6)
  def test_pass_with_notes_fixture_stat_strip_leaves_the_untested_dark_column_out
    stats = copy_for(load_fixture(:pass_with_notes)).stats

    assert_equal ["3 of 3", nil], stats[:requirements]
    assert_equal ["6 of 7", "1 observed"], stats[:journeys]
    assert_equal ["0", "0 found"], stats[:open_issues]
    assert_equal ["Light · Phone", "Dark: not tested"], stats[:tested_on]
  end

  # AC7 (B-R6)
  def test_fail_fixture_stat_strip_matches_the_approved_mock
    stats = copy_for(load_fixture(:fail)).stats

    assert_equal ["8 of 15", "7 not met"], stats[:requirements]
    assert_equal ["4 of 10", "5 failed · 1 blocked"], stats[:journeys]
    assert_equal ["4", "8 found · 2 fixed"], stats[:open_issues]
    assert_equal ["Light · Dark · PDF", nil], stats[:tested_on]
  end

  # AC8 (B-R7)
  def test_pass_with_notes_fixture_section_headings
    copy = copy_for(load_fixture(:pass_with_notes))

    assert_equal "Everything works, with 2 notes", copy.summary_heading
    assert_equal "3 requirements, all met", copy.checked_heading
    assert_equal "7 journeys, 6 passed and 1 observed", copy.journeys_heading
    assert_equal "Nothing needs fixing", copy.issues_heading
  end

  # AC8 (B-R7)
  def test_fail_fixture_section_headings
    copy = copy_for(load_fixture(:fail))

    assert_equal "Not ready yet, and here is why", copy.summary_heading
    assert_equal "15 requirements, 8 met", copy.checked_heading
    assert_equal "10 journeys, 4 passed and 6 did not", copy.journeys_heading
    assert_equal "8 issues found, 4 still open", copy.issues_heading
  end

  # AC24 (B-R5a)
  def test_pass_with_no_issues_says_so
    assert_equal "All 3 requirements met. No issues found.", copy_for(counted_source(met: 3)).explainer
  end

  # AC24 (B-R5a)
  def test_pass_with_only_verified_fixes_counts_them_as_none_still_open
    source = counted_source(met: 4, issues: [["MINOR", VERIFIED], ["MAJOR", VERIFIED]])

    assert_equal "PASS", source.verdict
    assert_equal "All 4 requirements met. 2 issues found, none still open.", copy_for(source).explainer
  end

  # AC25 (B-R5, B-R5a), revised by review: "All 1 requirement" reads wrong, so one requirement is named directly.
  def test_a_single_requirement_and_issue_read_singular
    source = counted_source(met: 1, issues: [["MINOR", VERIFIED]])

    assert_equal "The 1 requirement is met. 1 issue found, none still open.", copy_for(source).explainer
  end

  # AC26 (B-R5b, B-R7)
  def test_a_deferred_issue_is_a_known_issue_to_follow_up
    source = counted_source(met: 5, issues: [["MAJOR", "DEFERRED"], ["MAJOR", VERIFIED]])
    copy = copy_for(source)

    assert_equal "PASS WITH NOTES", source.verdict
    assert_equal "All 5 requirements met. 2 issues found, none still open. 1 known issue left to follow up.",
      copy.explainer
    assert_equal "Ready, with 1 known issue", copy.summary_heading
  end

  # AC36 (B-R5b, B-R5)
  def test_open_minors_and_deferred_majors_are_both_known
    source = counted_source(met: 4, issues: [["MINOR", OPEN], ["MAJOR", "DEFERRED"], ["MAJOR", VERIFIED]])

    assert_equal "All 4 requirements met. 3 issues found, 1 still open. 2 known issues left to follow up.",
      copy_for(source).explainer
  end

  # AC37 (B-R5b, B-R5)
  def test_one_open_minor_reads_singular_throughout
    source = counted_source(met: 2, issues: [["MINOR", OPEN]])

    assert_equal "All 2 requirements met. 1 issue found, 1 still open. 1 known issue left to follow up.",
      copy_for(source).explainer
  end

  # B-R5b: the notes sentence follows the count.
  def test_pass_with_one_note_says_note_singular
    source = counted_source(met: 3, notes: 1)

    assert_equal "All 3 requirements met. No issues found. 1 note for you.", copy_for(source).explainer
  end

  # B-R5b: only client-facing notes are counted, so both files print the same sentence.
  def test_internal_only_notes_are_not_counted
    source = counted_source(met: 3, notes: 2)
    source.notes.last["client_facing"] = false

    assert_equal "All 3 requirements met. No issues found. 1 note for you.", copy_for(source).explainer
  end

  # AC27 (B-R5c)
  def test_fail_lists_open_blockers_and_majors
    source = counted_source(met: 6, not_met: 2, issues: [["BLOCKER", OPEN], ["BLOCKER", OPEN], ["MAJOR", OPEN]])

    assert_equal "Not ready yet. 3 issues are still open, including 2 blockers and 1 major one. " \
                 "6 of 8 requirements are met.", copy_for(source).explainer
  end

  # AC28 (B-R5c)
  def test_fail_with_no_issues_names_only_the_requirements
    assert_equal "Not ready yet. 7 of 8 requirements are met.",
      copy_for(counted_source(met: 7, not_met: 1)).explainer
  end

  # AC29 (B-R5c, B-R5)
  def test_counted_nouns_and_verbs_follow_the_number
    source = counted_source(met: 2, issues: [["MINOR", OPEN], ["MAJOR", AWAITING], ["MAJOR", AWAITING]])

    assert_equal "FAIL", source.verdict
    assert_equal "Not ready yet. 1 issue is still open. 2 major fixes are waiting to be re-tested. " \
                 "2 of 2 requirements are met.", copy_for(source).explainer
  end

  # B-R5 (review): "is" agrees with the 1 met, not with the 3 in total.
  def test_fail_with_one_requirement_met_agrees_with_the_met_count
    assert_equal "Not ready yet. 1 of 3 requirements is met.", copy_for(counted_source(met: 1, not_met: 2)).explainer
  end

  # B-R5c (review): when one severity is every open issue, the "including" clause would only repeat the count.
  def test_a_lone_open_blocker_is_named_without_an_including_clause
    source = counted_source(met: 2, issues: [["BLOCKER", OPEN]])

    assert_equal "Not ready yet. 1 blocker is still open. 2 of 2 requirements are met.", copy_for(source).explainer
  end

  # B-R5c (review): the plural form of the same rule.
  def test_open_issues_that_are_all_blockers_are_named_as_blockers
    source = counted_source(met: 2, issues: [["BLOCKER", OPEN], ["BLOCKER", OPEN]])

    assert_equal "Not ready yet. 2 blockers are still open. 2 of 2 requirements are met.", copy_for(source).explainer
  end

  # B-R5c (review): a strict subset keeps "including".
  def test_a_blocker_among_other_open_issues_keeps_the_including_clause
    source = counted_source(met: 2, issues: [["BLOCKER", OPEN], ["MINOR", OPEN]])

    assert_equal "Not ready yet. 2 issues are still open, including 1 blocker. 2 of 2 requirements are met.",
      copy_for(source).explainer
  end

  # B-R5c (review): re-test wording follows the single-severity rule, so a lone blocker fix is a blocker fix.
  def test_a_blocker_awaiting_re_test_is_a_blocker_fix
    source = counted_source(met: 2, issues: [["BLOCKER", AWAITING]])

    assert_equal "Not ready yet. 1 blocker fix is waiting to be re-tested. 2 of 2 requirements are met.",
      copy_for(source).explainer
  end

  def test_blockers_only_awaiting_re_test_are_blocker_fixes
    source = counted_source(met: 2, issues: [["BLOCKER", AWAITING], ["BLOCKER", AWAITING]])

    assert_equal "Not ready yet. 2 blocker fixes are waiting to be re-tested. 2 of 2 requirements are met.",
      copy_for(source).explainer
  end

  # B-R5c (review): only a mix of severities reads "blocker or major".
  def test_a_mix_awaiting_re_test_are_blocker_or_major_fixes
    source = counted_source(met: 2, issues: [["BLOCKER", AWAITING], ["MAJOR", AWAITING]])

    assert_equal "Not ready yet. 2 blocker or major fixes are waiting to be re-tested. 2 of 2 requirements are met.",
      copy_for(source).explainer
  end

  # B-R5c (review): only majors awaiting re-test keep "major fix".
  def test_majors_only_awaiting_re_test_keep_major_fix
    source = counted_source(met: 2, issues: [["MAJOR", AWAITING]])

    assert_equal "Not ready yet. 1 major fix is waiting to be re-tested. 2 of 2 requirements are met.",
      copy_for(source).explainer
  end

  # B-R5c (review): the single-severity rule applies to majors too; the verified blocker D2 is not open.
  def test_a_single_open_major_reads_singular
    source = source_from(:fail) do |data|
      data["issues"] = data["issues"].select { |issue| %w[D2 D3].include?(issue["id"]) }
    end

    assert_equal "Not ready yet. 1 major issue is still open. 8 of 15 requirements are met.", copy_for(source).explainer
  end

  # B-R5c (review): open issues that are all majors are named as majors, plural.
  def test_open_issues_that_are_all_majors_are_named_as_major_issues
    source = counted_source(met: 2, issues: [["MAJOR", OPEN], ["MAJOR", OPEN]])

    assert_equal "Not ready yet. 2 major issues are still open. 2 of 2 requirements are met.",
      copy_for(source).explainer
  end

  # B-R5 (review): mirrors "The 1 requirement is met." so a FAIL never reads "0 of 1 requirement are met".
  def test_fail_with_a_single_unmet_requirement_names_it_directly
    assert_equal "Not ready yet. The 1 requirement is not met.",
      copy_for(counted_source(met: 0, not_met: 1)).explainer
  end

  # AC30 (B-R6)
  def test_stat_notes_name_blocked_requirements_and_found_issues
    source = counted_source(met: 4, not_met: 1, blocked: 1, journeys: { "PASS" => 5 },
                            issues: [["MINOR", OPEN], ["MINOR", OPEN], ["TRIVIAL", OPEN]])
    stats = copy_for(source).stats

    assert_equal ["4 of 6", "2 not met · 1 blocked"], stats[:requirements]
    assert_equal ["5 of 5", nil], stats[:journeys]
    assert_equal ["3", "3 found"], stats[:open_issues]
  end

  # AC31 (B-R7)
  def test_journeys_heading_when_all_passed
    assert_equal "5 journeys, all passed",
      copy_for(counted_source(met: 1, journeys: { "PASS" => 5 })).journeys_heading
  end

  # AC31 (B-R7)
  def test_journeys_heading_joins_the_non_zero_parts_with_and_before_the_last
    source = counted_source(met: 1, not_met: 1,
                            journeys: { "PASS" => 6, "OBSERVED" => 1, "FAIL" => 1, "BLOCKED" => 1 })

    assert_equal "9 journeys, 6 passed, 1 observed and 2 did not", copy_for(source).journeys_heading
  end

  # AC32 (B-R7)
  def test_summary_heading_for_pass
    assert_equal "Everything works", copy_for(counted_source(met: 3)).summary_heading
  end

  # AC32 (B-R7)
  def test_summary_heading_for_one_note_and_no_known_issues
    assert_equal "Everything works, with 1 note", copy_for(counted_source(met: 3, notes: 1)).summary_heading
  end

  # AC32 (B-R7)
  def test_summary_heading_for_a_known_issue_and_notes
    source = counted_source(met: 3, notes: 2, issues: [["MINOR", OPEN]])

    assert_equal "Ready, with 1 known issue and 2 notes", copy_for(source).summary_heading
  end

  # AC33 (B-R7)
  def test_issues_heading_when_every_issue_is_fixed
    source = counted_source(met: 2, issues: [["MINOR", VERIFIED], ["MAJOR", VERIFIED]])

    assert_equal "2 issues found, none still open", copy_for(source).issues_heading
  end

  # B-R7: a single requirement reads singular in the 02 heading too.
  def test_checked_heading_for_one_requirement
    assert_equal "1 requirement, all met", copy_for(counted_source(met: 1)).checked_heading
  end
end
