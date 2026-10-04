# frozen_string_literal: true

require "erb"
require_relative "source"
require_relative "projection"
require_relative "copy"
require_relative "brand"
require_relative "images"
require_relative "page_findings"

module QaReport
  # What the internal banner says about the client file; built only through the named constructors.
  class ClientStatus
    attr_reader :kind, :detail, :command

    def self.approved(file) = new(:approved, file)
    def self.awaiting(command:) = new(:awaiting, nil, command)
    def self.stale = new(:stale)
    def self.blocked(reason) = new(:blocked, reason)

    def initialize(kind, detail = nil, command = nil)
      @kind = kind
      @detail = detail
      @command = command
    end
  end

  # One source, two files: the internal file is the client file plus regions wrapped in <!--int-->…<!--/int-->.
  class Renderer
    TEMPLATES = File.join(__dir__, "templates")
    MONTHS = %w[January February March April May June July August September October November December].freeze
    SUMMARY_BLOCKS = [["tested", "What we tested"], ["found", "What we found"], ["means", "What it means for you"],
                      ["next", "What happens next"]].freeze
    VERDICTS = {
      "PASS" => ["v-pass", "check"], "PASS WITH NOTES" => ["v-notes", "notes"], "FAIL" => ["v-fail", "x"]
    }.freeze
    REQUIREMENT_STATUS = {
      "MET" => ["t-success", "check", "Met"], "NOT MET" => ["t-danger", "x", "Not met"],
      "BLOCKED" => ["t-blocked", "blocked", "Blocked"]
    }.freeze
    JOURNEY_STATUS = {
      "PASS" => ["t-success", "check", "Pass"], "FAIL" => ["t-danger", "x", "Fail"],
      "BLOCKED" => ["t-blocked", "blocked", "Blocked"], "OBSERVED" => ["t-info", "eye", "Observed"],
      "NOT TESTED" => ["t-neutral", "dash", "Not tested"]
    }.freeze
    SECTIONS = [["summary", "Summary"], ["checked", "What we checked"], ["journeys", "Journeys"],
                ["issues", "Issues found"], ["shots", "Screenshots"], ["how", "How we tested"]].freeze

    # Each file is replaced atomically by rename, but the set of files is not.
    def self.write_files(dir, files)
      temps = {}
      files.each do |name, content|
        path = File.join(dir, name)
        temp = "#{path}.tmp#{Process.pid}"
        temps[temp] = path
        File.binwrite(temp, content)
      end
      temps.each { |temp, path| File.rename(temp, path) }
    ensure
      temps&.each_key { |temp| File.delete(temp) if File.exist?(temp) }
    end

    def initialize(source, brand:, client:, status: nil, encoder: nil)
      @source = source
      @brand = brand
      @client = client
      @status = status
      @encoder = encoder
    end

    # The status is known only after the client file is decided, so a caller may pass the final one here.
    def internal_html(status: @status)
      Page.new(@source, Projection.internal(@source), @brand, @client, status, internal: true, images: images).to_html
    end

    def client_html = client_page(payloads: true)

    # The client file as the leak scan reads it: identical text, with every image and font payload replaced by a placeholder.
    def client_scan_html = client_page(payloads: false)

    def warnings = images.warnings

    # Built on first use and shared, so each screenshot is encoded once however many files embed it.
    def images = @images ||= Images.new(@source, encoder: @encoder || Images.encoder)

    private

    def client_page(payloads:)
      raise ClientBlocked, ["this is an internal-only project, so it has no client view"] unless @client

      page_images = payloads ? images : Images::Placeholders.new(@source)
      Page.new(@source, Projection.client(@source), @brand, @client, @status, internal: false, images: page_images, embed_fonts: payloads).to_html
    end

    # The ERB context: every method a template calls lives here, and the templates read only the view data.
    class Page
      include PageFindings

      attr_reader :data, :brand, :client, :copy, :images

      def initialize(source, data, brand, client, status, internal:, images:, embed_fonts: true)
        @source = source
        @data = data
        @brand = brand
        @client = client
        @status = status
        @internal = internal
        @images = images
        @embed_fonts = embed_fonts
        @copy = Copy.new(source)
      end

      def to_html = partial("report")

      def partial(name, **locals)
        file = name == "report" ? "report.html.erb" : "_#{name}.html.erb"
        context = binding
        locals.each { |key, value| context.local_variable_set(key, value) }
        ERB.new(template_text(file), trim_mode: "-").result(context)
      end

      def h(text) = ERB::Util.html_escape(text.to_s)

      def int(html) = @internal && !html.empty? ? "<!--int-->#{html}<!--/int-->" : ""

      def title = "QA report: #{data["feature_title_plain"]}"

      def verdict = data["verdict"]

      def verdict_tone = VERDICTS.fetch(verdict).first

      def verdict_glyph = VERDICTS.fetch(verdict).last

      def format_date(date) = "#{MONTHS[date.month - 1]} #{date.day}, #{date.year}"

      def glyph(name, style: nil)
        %(<svg class="g" viewBox="0 0 16 16" aria-hidden="true" focusable="false"#{%( style="#{style}") if style}>) +
          %(<use href="#g-#{name}"/></svg>)
      end

      def badge(map, result)
        tone, icon, word = map.fetch(result)
        %(<span class="badge #{tone}">#{glyph(icon)}<span>#{h(word)}</span></span>)
      end

      def coverage_cell(value)
        tone, icon, word = JOURNEY_STATUS.fetch(value.to_s.upcase) { ["t-neutral", "dash", value.to_s] }
        %(<span class="cell #{tone}">#{glyph(icon)}<span class="w">#{h(word)}</span></span>)
      end

      def stat_strip
        stats = copy.stats
        { "Requirements met" => stats[:requirements], "Journeys passed" => stats[:journeys],
          "Open issues" => stats[:open_issues], "Tested on" => stats[:tested_on] }
      end

      def paragraphs(text)
        text.to_s.strip.split(/\n\s*\n/).map { |paragraph| "<p>#{h(paragraph.strip)}</p>" }.join
      end

      def toc_items
        sections.each_with_index.map do |(id, name), index|
          %(<li><a href="##{id}"><span class="num">#{format("%02d", index + 1)}</span><span>#{name}</span></a></li>)
        end.join
      end

      def journey_dom_id(id) = "j-#{slug(id)}"

      def journey_links(ids)
        return "" if ids.empty?

        links = ids.map { |id| %(<a href="##{journey_dom_id(id)}">#{h(id)}</a>) }.join(", ")
        %(<span class="req-ref">#{ids.size == 1 ? "Journey" : "Journeys"} #{links}</span>)
      end

      def evidence(journey)
        shots = journey["evidence"] & client_shot_ids
        if shots.any?
          return %(<span class="ev-list">#{shots.map { |id| %(<a href="#shot-#{slug(id)}">Screenshot #{h(id)}</a>) }.join}</span>)
        end

        note = journey["evidence_note_plain"].to_s.strip
        return %(<span class="ev-none">#{h(note)}</span>) unless note.empty?

        %(<span class="ev-none" aria-hidden="true">—</span><span class="sr-only">No screenshot</span>)
      end

      def technical_detail_link(journey)
        %(<a class="int-link" href="#a-#{journey_dom_id(journey["id"])}" style="display:block">Technical detail ↓</a>)
      end

      def confidentiality
        return "Internal report — for #{brand.name} use only." unless client

        "Confidential — prepared for #{client} as part of our engagement. Please share only within your team."
      end

      def stamp
        "Internal build · source sha256 #{@source.sha256 || "not recorded"} · schema version #{data["schema_version"]}"
      end

      def client_status_html
        detail = h(@status&.detail)
        case @status&.kind
        when :approved then %(Client version: <a href="#{detail}">#{detail}</a>)
        when :awaiting then "Client version: awaiting owner approval — run #{h(@status.command)}"
        when :stale then "Client version: approval out of date — re-approve"
        when :blocked then "Client version: blocked — #{detail}; see build output"
        else "Client version: none (internal-only project)."
        end
      end

      def stylesheet
        [font_faces, ":root { --font-sans: #{font_stack}; }", print_font_rule, page_rules, template_text("report.css")].join("\n")
      end

      def internal_stylesheet = "#{template_text("internal.css")}#{internal_page_rule}"

      private

      def template_text(name) = File.read(File.join(TEMPLATES, name), encoding: Encoding::UTF_8)

      def slug(id) = Source.slug(id)

      def client_shot_ids = @source.screenshots.select { |shot| shot["visibility"] == "client" }.map { |shot| shot["id"] }

      def font_stack = [brand.font_family && %("#{brand.font_family}"), "system-ui", "sans-serif"].compact.join(", ")

      # Chrome prints system-ui as Type 3 glyphs, so print falls back to a named font it embeds as TrueType.
      def print_font_stack = [brand.font_family && %("#{brand.font_family}"), "Arial", "Helvetica", "sans-serif"].compact.join(", ")

      def internal_page_rule
        %(@page internal { @top-center { content: "INTERNAL \\2014  NOT FOR CLIENT DISTRIBUTION"; font: 800 8pt #{print_font_stack}; color: #92400E; } }\n)
      end

      def print_font_rule = "@media print { :root { --font-sans: #{print_font_stack}; } }"

      def report_label = @internal && !client ? "Internal QA report" : "QA report"

      def font_faces
        brand.fonts.map do |font|
          %(@font-face { font-family: "#{font.family}"; font-style: normal; font-weight: #{font.weight}; font-display: swap; ) +
            %(src: url(#{font_uri(font)}) format("woff2"); })
        end.join("\n")
      end

      def font_uri(font) = @embed_fonts ? "data:font/woff2;base64,#{font.data}" : Images::Placeholders::PLACEHOLDER_URI

      def page_rules
        label = [brand.name, report_label, client].compact.map { |part| css_string(part) }.join(" \\00B7  ")
        <<~CSS
          @page { size: Letter; margin: 0.6in 0.6in 0.75in; @bottom-center { content: "#{label} \\00B7  Page " counter(page) " of " counter(pages); font: 400 8pt #{print_font_stack}; color: #545966; } }
          @page :first { @bottom-center { content: none; } }
        CSS
      end

      def css_string(text) = text.gsub("\\") { "\\\\" }.gsub('"') { '\\"' }.gsub("<") { "\\3C " }.gsub(/\s+/, " ")
    end
  end
end
