# frozen_string_literal: true

require_relative "source"

module QaReport
  # View helpers for issues, notes, screenshots, how-we-tested and the internal appendix; mixed into Renderer::Page.
  module PageFindings
    SEVERITY_BADGE = {
      "BLOCKER" => ["t-solid", "octagon", "Blocker"], "MAJOR" => ["t-danger", "triangle", "Major"],
      "MINOR" => ["t-notes", "circlebang", "Minor"], "TRIVIAL" => ["t-neutral", "dot", "Trivial"]
    }.freeze
    ISSUE_BADGE = {
      Source::OPEN => ["t-status", "open", "Open"],
      Source::FIXED_VERIFIED => ["t-status s-verified", "check", "Fixed & verified"],
      Source::FIXED_UNVERIFIED => ["t-status", "half", "Fixed, not yet re-tested"],
      Source::DEFERRED => ["t-status", "clock", "Deferred"],
      Source::WONT_FIX => ["t-status", "wontfix", "Won't fix"]
    }.freeze
    NOT_TESTED = "NOT TESTED"

    def sections = Renderer::SECTIONS.reject { |id, _| id == "shots" && client_shots.empty? }

    def section_label(id)
      index = sections.index { |section_id, _| section_id == id }
      "#{format("%02d", index + 1)} · #{sections[index].last}"
    end

    def issue_dom_id(id) = "issue-#{Source.slug(id)}"

    def shot_dom_id(id) = "shot-#{Source.slug(id)}"

    def root_cause_link(issue)
      return "" if issue["root_cause"].to_s.strip.empty?

      %(<a class="int-link" href="#a3-#{Source.slug(issue["id"])}">Root cause (appendix)</a>)
    end

    def report_date = format_date(data["status_as_of"] || data["tested_on"])

    def status_line(issue)
      glyph_name = ISSUE_BADGE.fetch(issue["status"])[1]
      [glyph_name, status_text(issue)]
    end

    def issue_screenshot_link(issue)
      return "" unless client_shot_ids.include?(issue["screenshot"])

      %(<p class="shot-ref"><a href="##{shot_dom_id(issue["screenshot"])}">View screenshot #{h(issue["screenshot"])}</a>#{print_ref(issue["screenshot"])}</p>)
    end

    # Paper cannot be clicked, so print swaps the link for a plain cross-reference to the screenshots section.
    def print_ref(id) = %(<span class="print-only">See screenshot #{h(id)}</span>)

    def client_shots = data["screenshots"].select { |shot| client_shot_ids.include?(shot["id"]) }

    def internal_shots = data["screenshots"].select { |shot| shot["visibility"] == "internal" }

    def shot_groups = client_shots.group_by { |shot| shot["group_plain"] }

    def figure(shot, reason: nil)
      phone = shot["variant"].to_s.downcase.start_with?("phone")
      %(<figure#{%( class="phone") if phone}>#{thumb(shot)}<figcaption><span class="vchip">#{h(shot["variant"])}</span>) +
        %(<span class="sid">#{h(shot["id"])}</span>#{h(shot["caption"])}</figcaption>) +
        "#{%(<p class="reason">Why internal: #{h(reason)}</p>) if reason}</figure>"
    end

    def thumb(shot)
      image = images.fetch(shot["id"])
      caption = h(shot["caption"])
      %(<button class="thumb" type="button" id="#{shot_dom_id(shot["id"])}" data-cap="#{caption}" data-w="#{image.width}">) +
        %(<img src="#{image.data_uri}" alt="#{h(shot["alt"])}">) +
        %(<span class="chip chip-x" aria-hidden="true">#{glyph("expand")}Expand</span>) +
        %(<span class="sr-only">View full size: #{caption}</span></button>)
    end

    # An internal-only note sits in its own marked region, so the client body stays identical to the internal one.
    def notes_block_html
      return "" if data["notes"].empty?

      shown = data["notes"].any? { |note| client_note?(note) }
      cards = data["notes"].map do |note|
        card = partial("note", note: note)
        shown && !client_note?(note) ? int(card) : card
      end.join
      block = partial("notes_block", cards: cards)
      shown ? block : int(block)
    end

    def note_status(note) = untested_column?(note["coverage_column"]) ? NOT_TESTED : "OBSERVED"

    def lightbox_html
      html = partial("lightbox")
      client_shots.empty? ? int(html) : html
    end

    def appendix_html = @internal ? int(partial("appendix").strip) : ""

    def technical_detail(journey)
      detail = journey["technical_detail"].to_s.strip
      return "<p>No technical detail recorded.</p>" if detail.empty?

      detail.include?("\n") ? %(<pre tabindex="0">#{h(detail)}</pre>) : "<p>#{h(detail)}</p>"
    end

    def appendix_text(value)
      value.to_s.strip.empty? ? "<p>Nothing recorded.</p>" : paragraphs(value)
    end

    def appendix_list(items)
      return appendix_text(nil) if items.nil? || items.empty?

      "<ul>#{items.map { |item| "<li>#{h(item)}</li>" }.join}</ul>"
    end

    def root_cause_issues = data["issues"].reject { |issue| issue["root_cause"].to_s.strip.empty? }

    private

    def client_note?(note) = !@internal || note["client_facing"] == true

    def untested_column?(name)
      coverage = data["coverage"]
      index = coverage["columns"].index(name)
      !index.nil? && coverage["rows"].all? { |row| row["cells"][index].to_s.upcase == NOT_TESTED }
    end

    def status_text(issue)
      reason = issue["status_reason_plain"].to_s.strip
      case issue["status"]
      when Source::OPEN then "Open as of #{report_date}."
      when Source::FIXED_UNVERIFIED then "Fixed#{fixed_in(issue)}; awaiting re-test."
      when Source::FIXED_VERIFIED then "Fixed#{fixed_in(issue)}; re-tested#{retested(issue)}."
      when Source::DEFERRED then reason.empty? ? "Deferred." : "Deferred. Reason: #{reason}"
      else "Won't fix. Reason: #{reason}"
      end
    end

    def fixed_in(issue)
      refs = Array(issue["fixed_in"])
      return "" if refs.empty?

      " in #{refs.size < 2 ? refs.first : "#{refs[0...-1].join(", ")} and #{refs.last}"}"
    end

    def retested(issue) = issue["retested_on"] ? " #{format_date(issue["retested_on"])}" : ""
  end
end
