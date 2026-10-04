# frozen_string_literal: true

require_relative "source"

module QaReport
  # Every count-bearing sentence and heading, computed from the source so the prose can never disagree with the data.
  class Copy
    BLOCKING = %w[BLOCKER MAJOR].freeze
    JOURNEY_NOTES = [["OBSERVED", "observed"], ["FAIL", "failed"], ["BLOCKED", "blocked"],
                     ["NOT TESTED", "not tested"]].freeze

    def initialize(source)
      @source = source
      @verdict = source.verdict
    end

    def explainer
      case @verdict
      when "FAIL" then fail_explainer
      else pass_explainer
      end
    end

    def summary_heading
      case @verdict
      when "FAIL" then "Not ready yet, and here is why"
      when "PASS" then "Everything works"
      else notes_heading
      end
    end

    def checked_heading
      total = requirements.size
      met == total ? "#{count(total, "requirement")}, all met" : "#{count(total, "requirement")}, #{met} met"
    end

    def journeys_heading
      return "#{count(journeys.size, "journey")}, all passed" if journey_count("PASS") == journeys.size

      did_not = journey_count("FAIL") + journey_count("BLOCKED")
      parts = ["#{journey_count("PASS")} passed"]
      parts << "#{journey_count("OBSERVED")} observed" if journey_count("OBSERVED").positive?
      parts << "#{did_not} did not" if did_not.positive?
      parts << "#{journey_count("NOT TESTED")} not tested" if journey_count("NOT TESTED").positive?
      "#{count(journeys.size, "journey")}, #{to_sentence(parts)}"
    end

    def issues_heading
      return "Nothing needs fixing" if found.zero?

      "#{count(found, "issue")} found, #{open_count.zero? ? "none" : open_count} still open"
    end

    def stats
      { requirements: [requirement_value, requirement_note], journeys: [journey_value, journey_note],
        open_issues: [open_count.to_s, issue_note], tested_on: [tested_columns, untested_note] }
    end

    private

    def requirements = @source.requirements

    def journeys = @source.journeys

    def issues = @source.issues

    def met = requirements.count { |item| item["result"] == "MET" }

    def found = issues.size

    def open_count = issues.count { |issue| issue["status"] == Source::OPEN }

    def fixed = issues.count { |issue| [Source::FIXED_VERIFIED, Source::FIXED_UNVERIFIED].include?(issue["status"]) }

    def known
      issues.count do |issue|
        issue["status"] == "DEFERRED" || (issue["status"] == Source::OPEN && !BLOCKING.include?(issue["severity"]))
      end
    end

    def notes = @source.notes.count { |note| note["client_facing"] == true }

    def journey_count(result) = journeys.count { |journey| journey["result"] == result }

    def pass_explainer
      total = requirements.size
      sentences = [total == 1 ? "The 1 requirement is met." : "All #{total} requirements met.", issues_sentence]
      sentences << "#{count(known, "known issue")} left to follow up." if known.positive?
      sentences << "#{count(notes, "note")} for you." if notes.positive?
      sentences.join(" ")
    end

    def issues_sentence
      return "No issues found." if found.zero?
      return "#{count(found, "issue")} found, none still open." if open_count.zero?

      "#{count(found, "issue")} found, #{open_count} still open."
    end

    def fail_explainer
      sentences = ["Not ready yet."]
      sentences << open_sentence if open_count.positive?
      sentences << retest_sentence if awaiting_retest.positive?
      sentences << met_sentence
      sentences.join(" ")
    end

    def retest_sentence
      blockers = issues.count { |issue| awaiting?(issue) && issue["severity"] == "BLOCKER" }
      noun = if blockers == awaiting_retest then "blocker fix"
             elsif blockers.zero? then "major fix"
             else "blocker or major fix"
             end
      "#{count(awaiting_retest, noun, noun.sub(/fix\z/, "fixes"))} #{verb(awaiting_retest)} waiting to be re-tested."
    end

    def met_sentence
      return "The 1 requirement is #{met == 1 ? "met" : "not met"}." if requirements.size == 1

      "#{met} of #{requirements.size} requirements #{verb(met)} met."
    end

    def named_open(severity)
      severity == "BLOCKER" ? count(open_count, "blocker") : count(open_count, "#{severity.downcase} issue")
    end

    def open_sentence
      severities = issues.select { |issue| issue["status"] == Source::OPEN }.map { |issue| issue["severity"] }.uniq
      return "#{named_open(severities.first)} #{verb(open_count)} still open." if severities.one? && BLOCKING.include?(severities.first)

      sentence = "#{count(open_count, "issue")} #{verb(open_count)} still open"
      including = [open_with("BLOCKER", "blocker", "blockers"), open_with("MAJOR", "major one", "major ones")].compact
      including.empty? ? "#{sentence}." : "#{sentence}, including #{to_sentence(including)}."
    end

    def open_with(severity, singular, plural)
      number = issues.count { |issue| issue["status"] == Source::OPEN && issue["severity"] == severity }
      count(number, singular, plural) if number.positive?
    end

    def awaiting?(issue) = issue["status"] == Source::FIXED_UNVERIFIED && BLOCKING.include?(issue["severity"])

    def awaiting_retest = issues.count { |issue| awaiting?(issue) }


    def notes_heading
      return "Everything works#{", with #{count(notes, "note")}" if notes.positive?}" if known.zero?

      heading = "Ready, with #{count(known, "known issue")}"
      notes.positive? ? "#{heading} and #{count(notes, "note")}" : heading
    end

    def requirement_value = "#{met} of #{requirements.size}"

    def requirement_note
      unmet = requirements.size - met
      return if unmet.zero?

      blocked = requirements.count { |item| item["result"] == "BLOCKED" }
      blocked.positive? ? "#{unmet} not met · #{blocked} blocked" : "#{unmet} not met"
    end

    def journey_value = "#{journey_count("PASS")} of #{journeys.size}"

    def journey_note
      parts = JOURNEY_NOTES.filter_map { |result, word| "#{journey_count(result)} #{word}" if journey_count(result).positive? }
      parts.join(" · ") unless parts.empty?
    end

    def issue_note = fixed.zero? ? "#{found} found" : "#{found} found · #{fixed} fixed"

    def coverage_columns
      coverage = @source.data["coverage"]
      coverage["columns"].each_with_index.map do |name, index|
        tested = coverage["rows"].any? { |row| row["cells"][index].to_s.upcase != "NOT TESTED" }
        [name.sub(/\s*\(.*\)\z/, ""), tested]
      end
    end

    def tested_columns
      names = coverage_columns.select(&:last).map(&:first)
      names.empty? ? "None" : names.join(" · ")
    end

    def untested_note
      names = coverage_columns.reject(&:last).map { |name, _| "#{name}: not tested" }
      names.join(" · ") unless names.empty?
    end

    def count(number, singular, plural = "#{singular}s") = "#{number} #{number == 1 ? singular : plural}"

    def verb(number) = number == 1 ? "is" : "are"

    def to_sentence(parts)
      parts.size < 2 ? parts.join : "#{parts[0...-1].join(", ")} and #{parts.last}"
    end
  end
end
