require_relative "test_helper"
require_relative "support/cli_harness"
require_relative "support/pdf_probe"

# Real Chrome PDFs read back with poppler; skipped with the reason where either is missing (Chrome cannot start in a sandbox).
class PdfIntegrationTest < Minitest::Test
  include CliHarness

  BRAND_NAME = "Northwind Studio"
  SUMMARY_HEADINGS = ["What we tested", "What we found", "What it means for you", "What happens next"].freeze
  FOUR = [%i[pass_with_notes client], %i[pass_with_notes internal], %i[fail client], %i[fail internal]].freeze
  ALL = (FOUR + [%i[pass_with_notes internal_only]]).freeze

  Printed = Struct.new(:pdf, :html, :run, :project)

  class << self
    attr_accessor :printed, :root
  end

  Minitest.after_run { FileUtils.rm_rf(PdfIntegrationTest.root) if PdfIntegrationTest.root }

  def setup
    reason = PdfProbe.real_pdf_skip_reason
    skip reason if reason
  end

  # The vault sits under Users/someone/Obsidian Vault, so a leaked file:// header would carry all three markers.
  def vault_root
    self.class.root ||= Dir.mktmpdir("qa-pdf")
    File.join(File.realpath(self.class.root), "Users", "someone", "Obsidian Vault").tap { |dir| FileUtils.mkdir_p(dir) }
  end

  def chrome_env = { "QA_REPORT_CHROME" => PdfProbe.real_chrome, "QA_REPORT_PDF_TIMEOUT" => nil }

  # Built once per run: Chrome is the slow part, and every check reads the same PDFs.
  def printed
    self.class.printed ||= begin
      set = {}
      client_project = make_project(vault_root, "example-co")
      %i[pass_with_notes fail].each do |fixture|
        source = place_source(client_project, fixture)
        forge_approval(source)
        assert_equal 0, qa_report("build", source).code, "precondition: the approved #{fixture} build"
        run = qa_report("pdf", source, env: chrome_env)
        client_html = qa_file(client_project, client_files(client_project).find { |name| name.include?(client_slug(fixture)) })
        set[[fixture, :client]] = printed_pair(client_html, run, client_project)
        set[[fixture, :internal]] = printed_pair(qa_file(client_project, "#{STEMS.fetch(fixture)}-internal.html"), run, client_project)
      end

      internal_project = make_project(vault_root, "example-studio", variants: %w[internal], client: nil)
      source = place_source(internal_project, :pass_with_notes)
      assert_equal 0, qa_report("build", source).code, "precondition: the internal-only build"
      run = qa_report("pdf", source, env: chrome_env)
      set[%i[pass_with_notes internal_only]] = printed_pair(qa_file(internal_project, "#{PASS_STEM}-internal.html"), run, internal_project)
      set
    end
  end

  def client_slug(fixture) = File.basename(STEMS.fetch(fixture))[/\A\d{4}-\d{2}-\d{2}/]

  def printed_pair(html, run, project) = Printed.new(html.sub(/\.html\z/, ".pdf"), html, run, project)

  def pdf_for(fixture, variant)
    item = printed.fetch([fixture, variant])
    assert File.file?(item.pdf), "pdf wrote no #{File.basename(item.pdf)} (exit #{item.run.code}):\n#{item.run.out}"
    item.pdf
  end

  def html_for(fixture, variant) = File.read(printed.fetch([fixture, variant]).html)

  def label(fixture, variant) = "#{fixture} #{variant} PDF"

  def footer(variant, page, count)
    prefix = variant == :internal_only ? "#{BRAND_NAME} · Internal QA report" : "#{BRAND_NAME} · QA report · #{CLIENT_NAME}"
    "#{prefix} · Page #{page} of #{count}"
  end

  def eyebrows(html)
    (all_with_class(html, "eyebrow", tag: "p") + all_with_class(html, "eyebrow", tag: "span")).map { |node| text(node) }
  end

  def headings(html) = (elements(html, "h2") + elements(html, "h3")).map { |node| text(node) }.reject(&:empty?)

  # Records the edit's sha256 in the .md, as if build had written the edited HTML, so pdf prints it instead of refusing it.
  def rewrite_as_built(source, html)
    before = Digest::SHA256.file(html).hexdigest
    File.write(html, yield(File.read(html)))
    note = source.sub(/\.qa\.yml\z/, ".md")
    recorded = File.read(note)
    assert_includes recorded, before, "precondition: the .md records the sha256 of #{File.basename(html)}"
    File.write(note, recorded.sub(before, Digest::SHA256.file(html).hexdigest))
  end

  def first_page_holding(pages, label)
    pages.index { |lines| lines.any? { |line| line.downcase.start_with?(label.downcase) } }
  end

  # AC1 (E-R1)
  def test_pdf_exits_0_and_writes_each_pdf_next_to_its_html
    ALL.each do |fixture, variant|
      item = printed.fetch([fixture, variant])
      assert_equal 0, item.run.code, "pdf for #{fixture} (#{variant}) did not finish with Chrome installed:\n#{item.run.out}"
      assert File.file?(item.pdf), "no #{File.basename(item.pdf)} beside #{File.basename(item.html)}"
      assert_equal "%PDF-", File.binread(item.pdf, 5), "#{File.basename(item.pdf)} is not a PDF"
    end
  end

  # AC2 (E-R2)
  def test_pdf_text_has_no_file_url_local_path_or_browser_header_and_footer
    ALL.each do |fixture, variant|
      pdf = pdf_for(fixture, variant)
      text = PdfProbe.pages(pdf).flatten.join("\n")
      title = CGI.unescapeHTML(html_for(fixture, variant)[%r{<title>(.*?)</title>}m, 1].to_s)

      ["file://", "/Users/", "Obsidian Vault", "Obsidian%20", File.basename(printed.fetch([fixture, variant]).html)].each do |leak|
        refute text.include?(leak), "the #{label(fixture, variant)} leaks #{leak.inspect}, as a browser header or footer would"
      end
      refute text.match?(%r{\b\d{1,2}/\d{1,2}/\d{2,4},? +\d{1,2}:\d{2}}), "the #{label(fixture, variant)} carries a browser date header"
      refute text.include?(title), "the #{label(fixture, variant)} carries the page title as a browser header"
    end
  end

  # AC3 (E-R3)
  def test_every_page_is_us_letter
    ALL.each do |fixture, variant|
      sizes = PdfProbe.page_sizes(pdf_for(fixture, variant))

      refute_empty sizes
      sizes.each_with_index do |size, index|
        assert_in_delta 612, size[0], 0.5, "page #{index + 1} of the #{label(fixture, variant)} is not 8.5 in wide"
        assert_in_delta 792, size[1], 0.5, "page #{index + 1} of the #{label(fixture, variant)} is not 11 in tall"
      end
    end
  end

  # AC3 (E-R3): 0.6 in top, left and right, 0.75 in bottom; only the running header and footer sit in the margins.
  def test_body_text_stays_inside_the_margins_and_reaches_the_left_one
    ALL.each do |fixture, variant|
      pdf = pdf_for(fixture, variant)
      pages = PdfProbe.pages(pdf)
      lefts = []
      PdfProbe.words(pdf).each_with_index do |words, index|
        top, body = words.partition { |word| word[:y_max] <= PdfProbe::MARGIN[:top] + 0.5 }
        bottom, body = body.partition { |word| word[:y_min] >= 792 - PdfProbe::MARGIN[:bottom] - 0.5 }
        where = "page #{index + 1} of the #{label(fixture, variant)}"

        assert_includes ["", PdfProbe::INTERNAL_HEADER], top.map { |word| word[:text] }.join(" "), "#{where}: body text runs into the top margin"
        assert_includes ["", pages[index].last], bottom.map { |word| word[:text] }.join(" "), "#{where}: body text runs into the bottom margin"
        body.each do |word|
          assert_operator word[:x_min], :>=, PdfProbe::MARGIN[:side] - 1, "#{where}: #{word[:text].inspect} sits in the left margin"
          assert_operator word[:x_max], :<=, 612 - PdfProbe::MARGIN[:side] + 1, "#{where}: #{word[:text].inspect} sits in the right margin"
        end
        lefts.concat(body.map { |word| word[:x_min] })
      end
      assert_in_delta PdfProbe::MARGIN[:side], lefts.min, 1.5, "the left margin of the #{label(fixture, variant)} is not 0.6 in"
    end
  end

  # AC3, AC4 and AC17 (E-R3): Y is the page count pdfinfo reports.
  def test_page_1_has_no_running_footer_and_every_later_page_ends_with_it
    ALL.each do |fixture, variant|
      pdf = pdf_for(fixture, variant)
      pages = PdfProbe.pages(pdf)
      count = PdfProbe.page_count(pdf)

      assert_operator count, :>=, 2, "the #{label(fixture, variant)} needs 2 or more pages to show its running footer"
      refute pages.first.any? { |line| line.match?(/\bPage \d+ of \d+\b/) }, "page 1 of the #{label(fixture, variant)} has a running footer"
      pages.drop(1).each.with_index(2) do |lines, page|
        assert_equal footer(variant, page, count), lines.last, "page #{page} of the #{label(fixture, variant)} does not end with its running footer"
      end
    end
  end

  # AC13 (E-R3): an internal-only project's PDF names no client.
  def test_an_internal_only_pdf_names_no_client
    text = PdfProbe.pages(pdf_for(:pass_with_notes, :internal_only)).flatten.join("\n")

    refute text.include?(CLIENT_NAME), "the internal-only PDF names the client #{CLIENT_NAME}"
  end

  # AC3 and AC4 (E-R3)
  def test_internal_pdfs_carry_the_internal_header_on_every_page_and_client_pdfs_on_none
    [%i[pass_with_notes internal], %i[fail internal], %i[pass_with_notes internal_only]].each do |fixture, variant|
      PdfProbe.pages(pdf_for(fixture, variant)).each.with_index(1) do |lines, page|
        assert_equal PdfProbe::INTERNAL_HEADER, lines.first, "page #{page} of the #{label(fixture, variant)} does not start with the INTERNAL header"
      end
    end
    %i[pass_with_notes fail].each do |fixture|
      pages = PdfProbe.pages(pdf_for(fixture, :client))
      marked = pages.each_index.select { |index| pages[index].any? { |line| line.include?("NOT FOR CLIENT DISTRIBUTION") } }
      assert_empty marked.map(&:succ), "the #{fixture} client PDF carries the INTERNAL header"
    end
  end

  # AC14 (E-R3, E-R4)
  def test_page_1_holds_the_cover_and_the_whole_summary
    FOUR.each do |fixture, variant|
      pages = PdfProbe.pages(pdf_for(fixture, variant))
      first = pages.first.join("\n")

      assert_includes first, "Acceptance QA:", "page 1 of the #{label(fixture, variant)} lost the cover title"
      assert_includes first, load_fixture(fixture).verdict, "page 1 of the #{label(fixture, variant)} lost the verdict"
      assert_match(/^01 · SUMMARY$/i, first, "page 1 of the #{label(fixture, variant)} lost the Summary eyebrow")
      SUMMARY_HEADINGS.each { |heading| assert_includes first, heading, "page 1 of the #{label(fixture, variant)} lost #{heading.inspect}" }
      later = pages.drop(1).flatten
      SUMMARY_HEADINGS.each do |heading|
        refute later.any? { |line| line.include?(heading) }, "#{heading.inspect} spilled past page 1 of the #{label(fixture, variant)}"
      end
    end
  end

  # AC15 (E-R4)
  def test_no_page_ends_with_a_section_eyebrow_or_heading
    FOUR.each do |fixture, variant|
      html = html_for(fixture, variant)
      tags = eyebrows(html).map(&:downcase)
      titles = headings(html).map(&:downcase)
      PdfProbe.pages(pdf_for(fixture, variant)).each.with_index(1) do |lines, page|
        last = PdfProbe.body_lines(lines).last.to_s.downcase
        stranded = tags.find { |tag| last == tag || last.start_with?("#{tag} ") || last.end_with?(" #{tag}") } ||
                   titles.find { |title| last == title || (last.size >= 12 && title.start_with?(last)) }

        assert_nil stranded, "page #{page} of the #{label(fixture, variant)} ends with #{stranded.inspect}, cut off from what follows"
      end
    end
  end

  # AC16 (E-R4): no issue card spans 2 pages.
  def test_each_issue_eyebrow_is_on_the_same_page_as_its_status_line
    %i[client internal].each do |variant|
      html = html_for(:fail, variant)
      lines = PdfProbe.pages(pdf_for(:fail, variant)).each_with_index.flat_map { |page, index| page.map { |line| [index + 1, line] } }
      issues = elements(html, "article", /class="issue\b/)
      assert_equal 8, issues.size, "precondition: the fail fixture has 8 issues"

      issues.each do |issue|
        eyebrow = text(with_class(issue, "eyebrow")).upcase
        status = text(with_class(issue, "status-line"))
        at = lines.index { |_, line| line.match?(/\A#{Regexp.escape(eyebrow)}\b/) } or flunk("#{eyebrow} is missing from the fail #{variant} PDF")
        found = lines[at..].find { |_, line| line.start_with?(status[0, 24]) } or flunk("the status line of #{eyebrow} is missing: #{status.inspect}")

        assert_equal lines[at][0], found[0], "#{eyebrow} starts on page #{lines[at][0]} but its status line is on page #{found[0]}"
      end
    end
  end

  # AC5 (E-R4): 02, 03, A, and 04 with issues start a page.
  def test_02_03_appendix_and_04_with_issues_each_start_a_page
    FOUR.each do |fixture, variant|
      html = html_for(fixture, variant)
      pages = PdfProbe.pages(pdf_for(fixture, variant))
      starters = eyebrows(html).select { |tag| tag.match?(/\A0[23] · /) }
      starters += eyebrows(html).grep(/\A04 · /) if fixture == :fail
      starters += eyebrows(html).grep(/\AA · /) if variant == :internal
      assert_equal(fixture == :fail ? (variant == :internal ? 4 : 3) : (variant == :internal ? 3 : 2), starters.size,
                   "precondition: the #{label(fixture, variant)} HTML has the expected section eyebrows")

      starters.each do |tag|
        index = first_page_holding(pages, tag) or flunk("#{tag.inspect} is missing from the #{label(fixture, variant)}")
        assert_match(/\A#{Regexp.escape(tag)}\z/i, PdfProbe.body_lines(pages[index]).first.to_s,
                     "#{tag.inspect} does not start page #{index + 1} of the #{label(fixture, variant)}")
      end
    end
  end

  # AC6 (E-R4): with 0 issues, 04 follows on from the section before it.
  def test_04_with_no_issues_is_not_forced_onto_a_new_page
    %i[client internal].each do |variant|
      html = html_for(:pass_with_notes, variant)
      tag = eyebrows(html).grep(/\A04 · /).first or flunk("precondition: the pass_with_notes #{variant} HTML has a 04 section")
      pages = PdfProbe.pages(pdf_for(:pass_with_notes, variant))
      index = first_page_holding(pages, tag) or flunk("#{tag.inspect} is missing from the pass_with_notes #{variant} PDF")
      body = PdfProbe.body_lines(pages[index])

      refute_match(/\A#{Regexp.escape(tag)}\z/i, body.first.to_s, "#{tag.inspect} was forced onto a new page although there are 0 issues")
    end
  end

  # AC5 (E-R4)
  def test_contents_and_expand_labels_do_not_print
    FOUR.each do |fixture, variant|
      lines = PdfProbe.pages(pdf_for(fixture, variant)).flatten

      refute_includes lines, "Contents", "the #{label(fixture, variant)} prints the Contents block"
      refute lines.any? { |line| line.match?(/\bExpand\b/) }, "the #{label(fixture, variant)} prints Expand labels"
    end
  end

  # Paper cannot be clicked, so issue evidence reads as a cross-reference to 05 Screenshots.
  def test_issue_evidence_prints_as_see_screenshot_not_a_view_link
    %i[client internal].each do |variant|
      text = PdfProbe.pages(pdf_for(:fail, variant)).flatten.join(" ")

      assert text.include?("See screenshot 2a"), "the #{label(:fail, variant)} does not point the reader to screenshot 2a"
      refute text.include?("View screenshot"), "the #{label(:fail, variant)} prints a 'View screenshot' link nobody can click"
    end
  end

  # Journey evidence prints as a plain cross-reference like an issue card's "See screenshot 2a": no underline, no bold.
  def test_journey_evidence_prints_as_plain_screenshot_references
    %i[client internal].each do |variant|
      pdf = pdf_for(:fail, variant)
      refs = PdfProbe.screenshot_refs(pdf)
      journey = refs.select { |ref| ref[:text].start_with?("Screenshot ") }
      issue = refs.select { |ref| ref[:text].start_with?("screenshot ") }
      refute_empty journey, "precondition: the #{label(:fail, variant)} prints journey evidence as Screenshot <id>"
      refute_empty issue, "precondition: the #{label(:fail, variant)} prints issue evidence as See screenshot <id>"
      assert issue.all? { |ref| ref[:underline] < 0.2 }, "the probe reads the plain issue references as underlined: #{issue.inspect}"

      underlined = journey.select { |ref| ref[:underline] >= 0.5 }.map { |ref| "page #{ref[:page]} #{ref[:text]}" }
      assert_empty underlined, "the #{label(:fail, variant)} underlines journey evidence like a link nobody can click"
      bold = PdfProbe.text_runs(pdf).select { |run| run[:bold] && run[:text].match?(/\bScreenshot \d+[a-z]\b/) }.map { |run| run[:text] }
      assert_empty bold, "the #{label(:fail, variant)} prints journey evidence in bold, unlike the issue cards' plain reference"
    end
  end

  # AC5 (E-R4): sampled with pdftoppm. Every page has white margins and dark text; nothing prints light-on-dark.
  def test_every_page_prints_light_with_dark_text
    FOUR.each do |fixture, variant|
      PdfProbe.gray_pages(pdf_for(fixture, variant), dpi: 50).each.with_index(1) do |page, number|
        width, height, pixels = page.values_at(:width, :height, :pixels)
        corners = [[2, 2], [width - 3, 2], [2, height - 3], [width - 3, height - 3]].map { |x, y| pixels[y * width + x] }
        median = pixels.sort[pixels.size / 2]
        where = "page #{number} of the #{label(fixture, variant)}"

        assert corners.all? { |value| value >= 250 }, "#{where} has a non-white page background: corners #{corners.inspect}"
        assert_operator median, :>=, 245, "#{where} is mostly dark (median grey #{median})"
        assert_operator pixels.min, :<=, 96, "#{where} has no dark text"
      end
    end
  end

  # AC5 (E-R4): the screen dark palette, forced on for every medium, still prints exactly the light pages.
  # Headless Chrome 154 ignores the OS appearance and dark-mode flags when printing, so the palette is forced in the HTML.
  def test_a_forced_dark_palette_prints_the_same_light_pages
    light = PdfProbe.gray_pages(pdf_for(:fail, :internal))
    project = make_project(vault_root, "example-dark")
    source = place_source(project, :fail)
    forge_approval(source)
    assert_equal 0, qa_report("build", source).code, "precondition: the approved fail build"
    internal = qa_file(project, "#{FAIL_STEM}-internal.html")
    dark_query = "@media screen and (prefers-color-scheme: dark)"
    html = File.read(internal)
    assert_includes html, dark_query, "precondition: the report has a screen dark palette to force"
    rewrite_as_built(source, internal) { |text| text.gsub(dark_query, "@media all") }

    run = qa_report("pdf", source, env: chrome_env)

    assert_equal 0, run.code, run.out
    refute_includes File.read(internal), dark_query, "pdf rewrote the HTML it was asked to print, so the dark palette was never tested"
    dark = PdfProbe.gray_pages(internal.sub(/\.html\z/, ".pdf"))
    assert_equal light.size, dark.size, "forcing the dark palette changed the page count"
    differing = light.each_index.reject { |index| light[index] == dark[index] }.map(&:succ)
    assert_empty differing, "pages #{differing.inspect} print differently under the dark palette"
  end

  # AC18 (E-R10)
  def test_every_font_is_embedded_and_none_is_type_3
    ALL.each do |fixture, variant|
      fonts = PdfProbe.fonts(pdf_for(fixture, variant))

      refute_empty fonts, "pdffonts listed no fonts in the #{label(fixture, variant)}"
      not_embedded = fonts.reject { |font| font[:embedded] }.map { |font| font[:name] }.uniq
      type3 = fonts.select { |font| font[:type] == "Type 3" }.map { |font| font[:name] }.uniq
      assert_empty not_embedded, "the #{label(fixture, variant)} has fonts that are not embedded"
      assert_empty type3, "the #{label(fixture, variant)} has #{type3.size} Type 3 fonts, which print blurry and do not copy"
    end
  end

  # The default brand's wordmark draws its own text, so it must reach an embeddable font too.
  def test_a_project_with_no_brand_configured_prints_only_embedded_non_type_3_fonts
    project = File.join(vault_root, "example-unbranded")
    FileUtils.mkdir_p(File.join(project, "QA"))
    File.write(File.join(project, "qa-report.yml"), YAML.dump("variants" => %w[internal], "paper" => "letter", "deny" => []))
    source = place_source(project, :pass_with_notes)
    assert_equal 0, qa_report("build", source).code, "precondition: the unbranded internal-only build"

    run = qa_report("pdf", source, env: chrome_env)

    pdf = qa_file(project, "#{PASS_STEM}-internal.pdf")
    assert_equal 0, run.code, run.out
    fonts = PdfProbe.fonts(pdf)
    refute_empty fonts, "pdffonts listed no fonts in the unbranded PDF"
    assert_empty fonts.reject { |font| font[:embedded] }.map { |font| font[:name] }.uniq, "the unbranded PDF has fonts that are not embedded"
    type3 = fonts.select { |font| font[:type] == "Type 3" }.map { |font| font[:name] }
    assert_empty type3, "the unbranded PDF has #{type3.size} Type 3 fonts (#{type3.uniq.join(", ")}), which print blurry and do not copy"
  end

  # Chrome reads file:// URLs, so #, ? and % in the folder name must be escaped or Chrome prints a different file.
  def test_a_project_folder_named_with_hash_question_mark_or_percent_still_prints
    failures = ["C#-team", "q?x", "100%-done"].filter_map do |folder|
      project = make_project(File.join(vault_root, folder), "example-studio", variants: %w[internal], client: nil)
      source = place_source(project, :pass_with_notes)
      assert_equal 0, qa_report("build", source).code, "precondition: the internal-only build in #{folder}"

      run = qa_report("pdf", source, env: chrome_env)

      pdf = qa_file(project, "#{PASS_STEM}-internal.pdf")
      if run.code != 0 then "#{folder}: exit #{run.code}: #{run.out.strip}"
      elsif !File.file?(pdf) then "#{folder}: no internal PDF was written"
      elsif !PdfProbe.pages(pdf).flatten.join(" ").include?("Proposal sections keep their order") then "#{folder}: the PDF is not the QA report"
      end
    end

    assert_empty failures, "pdf failed for project folders with URL-special characters:\n#{failures.join("\n")}"
  end

  def test_pdf_finds_chrome_in_its_default_place_without_configuration
    skip "Google Chrome is not installed at #{PdfProbe::MAC_CHROME}" unless File.executable?(PdfProbe::MAC_CHROME)

    project = make_project(vault_root, "example-default", variants: %w[internal], client: nil)
    source = place_source(project, :pass_with_notes)
    assert_equal 0, qa_report("build", source).code

    run = qa_report("pdf", source, env: { "QA_REPORT_CHROME" => nil })

    assert_equal 0, run.code, "pdf did not find the installed Chrome on its own:\n#{run.out}"
    assert File.file?(qa_file(project, "#{PASS_STEM}-internal.pdf"))
  end
end
