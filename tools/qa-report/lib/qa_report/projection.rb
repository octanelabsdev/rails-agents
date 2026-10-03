# frozen_string_literal: true

require "digest"
require "json"
require_relative "source"

module QaReport
  # The client view is built fresh from allowlisted keys, never by scrubbing a copy of the source.
  module Projection
    module_function

    def client(source)
      problems = blocking_problems(source)
      raise ClientBlocked, problems unless problems.empty?

      data = source.data
      shots = client_screenshots(source)
      shot_ids = shots.map { |shot| shot["id"] }
      pick(data, :top).merge(
        "summary" => pick(data["summary"], :summary),
        "coverage" => coverage_view(data["coverage"]),
        "requirements" => source.requirements.map { |item| pick(item, :requirement) },
        "journeys" => source.journeys.map { |item| journey_view(item, shot_ids) },
        "issues" => source.ordered_issues.map { |item| issue_view(item, shot_ids) },
        "notes" => source.notes.select { |note| note["client_facing"] == true }.map { |note| pick(note, :note) },
        "screenshots" => shots.map { |shot| screenshot_view(source, shot) },
        "verdict" => source.verdict
      )
    end

    def internal(source)
      copy(source.data).merge("verdict" => source.verdict, "issues" => copy(source.ordered_issues))
    end

    # The view's per-screenshot sha256 already pins the raw image bytes, so hashing the view covers them.
    def digest(source) = Digest::SHA256.hexdigest(JSON.generate(canonical(client(source))))

    def blocking_problems(source)
      client_ids = client_screenshots(source).map { |shot| shot["id"] }
      [note_problems(source), screenshot_problems(source), journey_problems(source, client_ids),
       override_problems(source)].flatten
    end

    def note_problems(source)
      source.notes.each_with_index.filter_map do |note, index|
        next if [true, false].include?(note["client_facing"])

        "#{Source.label("notes", note, index)}.client_facing must be true or false"
      end
    end

    def screenshot_problems(source)
      source.screenshots.each_with_index.flat_map do |shot, index|
        path = Source.label("screenshots", shot, index)
        next ["#{path}.visibility must be client or internal"] unless %w[client internal].include?(shot["visibility"])
        next [] unless shot["visibility"] == "client"

        [("#{path}.alt must not be empty" if blank?(shot["alt"])),
         ("#{path}.pixels_clean must be true for a client screenshot" unless shot["pixels_clean"] == true)].compact
      end
    end

    def journey_problems(source, client_ids)
      source.journeys.each_with_index.filter_map do |journey, index|
        next if (journey["evidence"] & client_ids).any? || !blank?(journey["evidence_note_plain"])

        "#{Source.label("journeys", journey, index)}.evidence needs a client-visible screenshot " \
          "or an evidence_note_plain"
      end
    end

    def override_problems(source)
      return [] unless source.override && blank?(source.override["reason"])

      ["verdict_override.reason is required when the verdict is overridden"]
    end

    def client_screenshots(source) = source.screenshots.select { |shot| shot["visibility"] == "client" }

    def coverage_view(coverage)
      pick(coverage, :coverage).merge("rows" => coverage["rows"].map { |row| pick(row, :coverage_row) })
    end

    def journey_view(journey, shot_ids)
      pick(journey, :journey).merge("evidence" => journey["evidence"] & shot_ids)
    end

    def issue_view(issue, shot_ids)
      pick(issue, :issue).tap { |view| view.delete("screenshot") unless shot_ids.include?(issue["screenshot"]) }
    end

    def screenshot_view(source, shot)
      pick(shot, :screenshot).merge("sha256" => Digest::SHA256.file(source.screenshot_path(shot)).hexdigest)
    end

    def pick(hash, kind) = copy(hash.slice(*Source.client_keys(kind)))

    def blank?(value) = value.to_s.strip.empty?

    def copy(value)
      case value
      when Hash then value.to_h { |key, child| [key, copy(child)] }
      when Array then value.map { |child| copy(child) }
      when String then value.dup
      else value
      end
    end

    def canonical(value)
      case value
      when Hash then value.sort_by { |key, _| key }.to_h { |key, child| [key, canonical(child)] }
      when Array then value.map { |child| canonical(child) }
      else value
      end
    end
  end
end
