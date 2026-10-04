require_relative "test_helper"
require_relative "support/cli_harness"
require_relative "support/pdf_probe"

# E-R1 and E-R5 through a Chrome stand-in, so where the PDFs land, PDF PENDING and the timeout are pinned on any machine.
class PdfCliTest < Minitest::Test
  include CliHarness

  PASS_INTERNAL_PDF = "#{PASS_STEM}-internal.pdf".freeze
  PASS_CLIENT_PDF = PASS_CLIENT_FILE.sub(/\.html\z/, ".pdf").freeze
  MISSING_CHROME = "/nonexistent/qa-report-test/Google Chrome"
  DENIED = "two things we want you to know"

  def teardown
    PdfProbe.reap(@standin_pids.to_a)
  end

  def pdf(source, chrome:, timeout: nil)
    qa_report("pdf", source, env: { "QA_REPORT_CHROME" => chrome, "QA_REPORT_PDF_TIMEOUT" => timeout&.to_s })
  end

  def standin(dir, **options)
    @standin_dir = dir
    PdfProbe.write_standin(dir, **options)
  end

  def standin_pids
    @standin_pids = PdfProbe.recorded_pids(@standin_dir)
  end

  def pending_line?(run) = run.out.lines.any? { |line| line.start_with?("PDF PENDING") }

  def qa_snapshot(project)
    Dir.glob("**/*", base: File.join(project, "QA")).sort.to_h do |name|
      path = qa_file(project, name)
      [name, File.file?(path) ? Digest::SHA256.file(path).hexdigest : :dir]
    end
  end

  def pdfs(project) = Dir.glob(File.join(project, "QA", "*.pdf")).map { |path| File.basename(path) }.sort

  # Includes half-written temp files, so a failed print is seen to leave nothing behind.
  def pdf_leftovers(project) = Dir.glob(File.join(project, "QA", "*.pdf*")).map { |path| File.basename(path) }.sort

  def printed_url(pdf_path) = File.binread(pdf_path)[/^% printed: (\S+)/, 1]

  def approved_project(vault)
    project = make_project(vault)
    source = place_source(project, :pass_with_notes)
    forge_approval(source)
    assert_equal 0, qa_report("build", source).code, "precondition: the approved build writes both HTML files"
    [project, source]
  end

  def internal_only_project(vault)
    project = make_project(vault, "example-studio", variants: %w[internal], client: nil)
    source = place_source(project, :pass_with_notes)
    assert_equal 0, qa_report("build", source).code, "precondition: the internal-only build writes the internal HTML"
    [project, source]
  end

  # AC1 (E-R1)
  def test_pdf_writes_the_internal_and_the_approved_client_pdf_next_to_their_html
    with_vault do |vault|
      project, source = approved_project(vault)

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin))

        assert_equal 0, run.code, "pdf did not finish for an approved client project:\n#{run.out}"
        assert_equal [PASS_CLIENT_PDF, PASS_INTERNAL_PDF].sort, pdfs(project),
          "the owner should find {stem}-internal.pdf and the client PDF beside their HTML files"
        assert_equal "file://#{qa_file(project, "#{PASS_STEM}-internal.html")}", printed_url(qa_file(project, PASS_INTERNAL_PDF)),
          "the internal PDF must be printed from the internal HTML"
        assert_equal "file://#{qa_file(project, PASS_CLIENT_FILE)}", printed_url(qa_file(project, PASS_CLIENT_PDF)),
          "the client PDF must be printed from the approved client HTML"
      end
    end
  end

  # AC1 (E-R1): no current approval, so no client HTML and no client PDF.
  def test_pdf_without_a_current_approval_writes_only_the_internal_pdf
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      assert_equal 0, qa_report("build", source).code
      assert_empty client_files(project), "precondition: the client file awaits approval"

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin))

        assert_equal 0, run.code, run.out
        assert_equal [PASS_INTERNAL_PDF], pdfs(project), "a client PDF was written for a client file nobody approved"
      end
    end
  end

  def test_an_internal_only_project_gets_only_the_internal_pdf
    with_vault do |vault|
      project, source = internal_only_project(vault)

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin))

        assert_equal 0, run.code, run.out
        assert_equal [PASS_INTERNAL_PDF], pdfs(project)
      end
    end
  end

  # AC7 (E-R5)
  def test_with_chrome_absent_pdf_is_pending_and_leaves_the_html_untouched
    with_vault do |vault|
      project, source = approved_project(vault)
      before = qa_snapshot(project)

      run = pdf(source, chrome: MISSING_CHROME)

      assert_equal 3, run.code, "a missing Chrome must exit 3:\n#{run.out}"
      assert pending_line?(run), "the agent needs a line starting 'PDF PENDING' to report:\n#{run.out}"
      assert_equal before, qa_snapshot(project), "pdf changed, added or removed files although Chrome never ran"
    end
  end

  # AC8 (E-R5): a stand-in that never prints is stopped at the timeout, with nothing of it left running.
  def test_a_chrome_that_never_finishes_is_stopped_at_the_timeout
    with_vault do |vault|
      project, source = approved_project(vault)
      before = qa_snapshot(project)

      Dir.mktmpdir("chrome") do |bin|
        started = Time.now
        run = pdf(source, chrome: standin(bin, finish: :hang), timeout: 2)
        elapsed = Time.now - started

        assert_equal 3, run.code, "a print that never finishes must exit 3:\n#{run.out}"
        assert pending_line?(run), "the agent needs a line starting 'PDF PENDING' to report:\n#{run.out}"
        assert_operator elapsed, :>=, 2, "pdf gave up before its 2-second timeout"
        assert_operator elapsed, :<, 6, "pdf kept waiting #{elapsed.round(1)} s on a 2-second timeout"
        refute_empty standin_pids, "precondition: the stand-in ran"
        assert_empty PdfProbe.surviving(standin_pids), "Chrome processes from the timed-out attempt are still running"
        assert_equal before, qa_snapshot(project), "a timed-out pdf must leave the HTML files as they were and no PDF"
      end
    end
  end

  # AC9 (E-R5): finishing just under the timeout is a success.
  def test_a_chrome_that_finishes_just_under_the_timeout_succeeds
    with_vault do |vault|
      project, source = internal_only_project(vault)

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin, delay: 3), timeout: 5)

        assert_equal 0, run.code, "a print finished before the 5-second timeout was treated as pending:\n#{run.out}"
        refute pending_line?(run), run.out
        assert_equal [PASS_INTERNAL_PDF], pdfs(project)
        assert_empty PdfProbe.surviving(standin_pids)
      end
    end
  end

  # Chrome 154 on macOS writes the PDF and then keeps running, so a finished file, not the process exit, ends the print.
  def test_a_chrome_that_keeps_running_after_writing_the_pdf_succeeds_and_is_ended
    with_vault do |vault|
      project, source = internal_only_project(vault)

      Dir.mktmpdir("chrome") do |bin|
        started = Time.now
        run = pdf(source, chrome: standin(bin, delay: 1, finish: :linger), timeout: 5)
        elapsed = Time.now - started

        assert_equal 0, run.code, "a PDF Chrome finished writing was reported as pending because Chrome stayed open:\n#{run.out}"
        assert_equal [PASS_INTERNAL_PDF], pdfs(project)
        assert_operator elapsed, :<, 5, "pdf waited out its whole timeout although the PDF was already written"
        refute_empty standin_pids, "precondition: the stand-in ran"
        assert_empty PdfProbe.surviving(standin_pids), "Chrome was left running after its PDF was written"
      end
    end
  end

  def test_with_no_timeout_set_a_print_of_a_few_seconds_is_not_cut_short
    with_vault do |vault|
      _, source = internal_only_project(vault)

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin, delay: 2.5))

        assert_equal 0, run.code, "pdf with no QA_REPORT_PDF_TIMEOUT cut a 2.5-second print short (the default is 30 s):\n#{run.out}"
      end
    end
  end

  def test_after_the_approved_content_changes_build_removes_the_client_pdf_and_pdf_does_not_bring_it_back
    with_vault do |vault|
      project, source = approved_project(vault)

      Dir.mktmpdir("chrome") do |bin|
        chrome = standin(bin)
        assert_equal 0, pdf(source, chrome: chrome).code
        assert_includes pdfs(project), PASS_CLIENT_PDF, "precondition: the approved client PDF was written"

        edit_source(source) { |data| data["summary"]["lead"] = "A changed lead the owner has not approved." }
        assert_equal 0, qa_report("build", source).code

        refute_includes client_files(project), PASS_CLIENT_FILE, "the client HTML outlived its approval"
        # The edited lead changed the internal HTML too, so its PDF is stale and goes as well.
        assert_equal [], pdfs(project),
          "the client PDF of the old approved content is still on disk, ready to be sent, after the approval went stale"

        run = pdf(source, chrome: chrome)

        assert_equal 0, run.code, run.out
        assert_equal [PASS_INTERNAL_PDF], pdfs(project), "pdf left a client PDF in place for content nobody approved"
      end
    end
  end

  def test_after_a_blocked_build_no_client_pdf_is_left_on_disk
    with_vault do |vault|
      project, source = approved_project(vault)

      Dir.mktmpdir("chrome") do |bin|
        chrome = standin(bin)
        assert_equal 0, pdf(source, chrome: chrome).code
        assert_includes pdfs(project), PASS_CLIENT_PDF, "precondition: the approved client PDF was written"

        write_config(project, deny: [DENIED])
        assert_equal 2, qa_report("build", source).code, "precondition: the deny term blocks the client file"

        assert_empty client_files(project), "the blocked client HTML is still on disk"
        # The blocked status changed the internal HTML too, so its PDF is stale and goes as well.
        assert_equal [], pdfs(project), "a client PDF holding a denied term survived the blocked build"

        pdf(source, chrome: chrome)

        assert_equal [PASS_INTERNAL_PDF], pdfs(project), "pdf left a client PDF holding a denied term in place"
      end
    end
  end

  def test_a_deny_term_added_after_the_build_stops_pdf_from_printing_the_client_file
    with_vault do |vault|
      project, source = approved_project(vault)
      write_config(project, deny: [DENIED])

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin))

        assert_equal 2, run.code, "pdf printed a client file the current deny list blocks:\n#{run.out}"
        assert_match(/#{DENIED}/i, run.out, "pdf must name the denied term so the owner can fix it")
        refute_includes pdf_leftovers(project), PASS_CLIENT_PDF, "a client PDF holding a denied term was written"
      end
    end
  end

  # Same contract as approve's built_from? check: refuse with exit 1 rather than rebuild behind the owner's back.
  def test_pdf_after_an_unbuilt_source_edit_refuses_and_asks_for_a_build
    with_vault do |vault|
      project, source = approved_project(vault)
      edit_source(source) { |data| data["summary"]["lead"] = "A changed lead that was never built." }

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin))

        assert_equal 1, run.code, "pdf printed HTML that no longer matches the source:\n#{run.out}"
        assert_match(/run build first/i, run.out, "the owner must be told to run build")
        assert_empty pdf_leftovers(project), "pdf wrote a PDF from stale HTML"
      end
    end
  end

  def test_pdf_on_an_internal_only_project_after_an_unbuilt_source_edit_refuses_and_asks_for_a_build
    with_vault do |vault|
      project, source = internal_only_project(vault)
      edit_source(source) { |data| data["summary"]["lead"] = "A changed lead that was never built." }

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin))

        assert_equal 1, run.code, "pdf printed an internal HTML that no longer matches the source:\n#{run.out}"
        assert_match(/run build first/i, run.out)
        assert_empty pdf_leftovers(project)
      end
    end
  end

  # In-process so the temp name's pid is this test's own, putting a killed run's complete leftover exactly where the print goes.
  def test_a_complete_leftover_from_a_killed_run_is_not_taken_as_the_new_print
    with_vault do |vault|
      project, source = internal_only_project(vault)
      File.binwrite(qa_file(project, "#{PASS_INTERNAL_PDF}.tmp#{Process.pid}"), PdfProbe.minimal_pdf("file:///an-earlier-run.html"))
      saved = ENV.to_h.slice("QA_REPORT_CHROME", "QA_REPORT_PDF_TIMEOUT")

      Dir.mktmpdir("chrome") do |bin|
        ENV["QA_REPORT_CHROME"] = standin(bin, delay: 0.5, finish: :silent)
        ENV["QA_REPORT_PDF_TIMEOUT"] = "3"
        error = assert_raises(QaReport::PdfPending, "an earlier run's leftover was accepted as this run's print") do
          QaReport::Pdf.new(source, out: StringIO.new).run
        end

        assert_equal 3, error.exit_code
        refute File.file?(qa_file(project, PASS_INTERNAL_PDF)), "the leftover was renamed into place as the internal PDF"
      ensure
        %w[QA_REPORT_CHROME QA_REPORT_PDF_TIMEOUT].each { |key| ENV[key] = saved[key] }
      end
    end
  end

  def test_a_chrome_that_exits_without_writing_is_pending_and_leaves_no_pdf
    with_vault do |vault|
      project, source = approved_project(vault)

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin, finish: :silent), timeout: 5)

        assert_equal 3, run.code, "a Chrome that wrote nothing was reported as printed:\n#{run.out}"
        assert pending_line?(run), run.out
        assert_empty pdf_leftovers(project)
      end
    end
  end

  def test_a_truncated_pdf_without_its_end_marker_is_pending_and_not_put_in_place
    with_vault do |vault|
      project, source = approved_project(vault)

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin, finish: :truncated), timeout: 5)

        assert_equal 3, run.code, "a half-written PDF was accepted:\n#{run.out}"
        assert pending_line?(run), run.out
        assert_empty pdf_leftovers(project), "a half-written PDF was put in place"
      end
    end
  end

  def test_when_the_client_print_hangs_neither_pdf_is_put_in_place
    with_vault do |vault|
      project, source = approved_project(vault)

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin, finish_for: ["-qa-report-", :hang]), timeout: 2)

        assert_equal 3, run.code, run.out
        assert pending_line?(run), run.out
        assert_empty pdf_leftovers(project), "the internal PDF went into place although the client print never finished"
        assert_empty PdfProbe.surviving(standin_pids)
      end
    end
  end

  def test_when_the_client_print_fails_neither_pdf_is_put_in_place
    with_vault do |vault|
      project, source = approved_project(vault)

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin, finish_for: ["-qa-report-", :silent]), timeout: 5)

        assert_equal 3, run.code, run.out
        assert pending_line?(run), run.out
        assert_empty pdf_leftovers(project), "the internal PDF went into place although the client print failed"
      end
    end
  end

  # U1: a PDF of an internal HTML that build has since replaced would be sent as if it were the current report.
  def test_a_rebuild_that_changes_the_internal_html_removes_the_stale_internal_pdf
    with_vault do |vault|
      project, source = internal_only_project(vault)
      html = qa_file(project, "#{PASS_STEM}-internal.html")

      Dir.mktmpdir("chrome") do |bin|
        assert_equal 0, pdf(source, chrome: standin(bin)).code
        assert_equal [PASS_INTERNAL_PDF], pdfs(project), "precondition: the internal PDF was written"
        printed = sha(html)

        edit_source(source) { |data| data["summary"]["lead"] = "A changed lead after the PDF was printed." }
        assert_equal 0, qa_report("build", source).code

        refute_equal printed, sha(html), "precondition: the rebuild changed the internal HTML"
        assert_empty pdf_leftovers(project), "build left #{PASS_INTERNAL_PDF} in place, still showing the old lead"
      end
    end
  end

  def test_a_rebuild_that_leaves_the_internal_html_unchanged_keeps_the_internal_pdf
    with_vault do |vault|
      project, source = internal_only_project(vault)
      html = qa_file(project, "#{PASS_STEM}-internal.html")

      Dir.mktmpdir("chrome") do |bin|
        assert_equal 0, pdf(source, chrome: standin(bin)).code
        printed = [sha(html), sha(qa_file(project, PASS_INTERNAL_PDF))]

        assert_equal 0, qa_report("build", source).code

        assert_equal printed.first, sha(html), "precondition: the same source rebuilt to the same internal HTML"
        assert_equal [PASS_INTERNAL_PDF], pdfs(project), "build removed an internal PDF that still matches its HTML"
        assert_equal printed.last, sha(qa_file(project, PASS_INTERNAL_PDF)), "build changed an internal PDF that still matches its HTML"
      end
    end
  end

  # U2: approve already writes the PDFs, so the owner only needs pdf after a build.
  def test_usage_says_approve_writes_the_pdfs_and_pdf_is_for_after_a_build
    usage = qa_report.out

    approve = usage.lines.find { |text| text.match?(/\A {2}approve\b/) } or flunk("usage lists no approve command:\n#{usage}")
    pdf = usage.lines.find { |text| text.match?(/\A {2}pdf\b/) } or flunk("usage lists no pdf command:\n#{usage}")
    assert_match(/\bPDFs?\b/, approve, "usage does not say approve also writes the PDFs")
    assert_match(/\bafter\b.*\bbuild\b/i, pdf, "usage does not say pdf is only needed after a build")
  end

  def test_usage_no_longer_calls_pdf_unimplemented
    run = qa_report

    line = run.out.lines.find { |text| text.match?(/\A {2}pdf\b/) } or flunk("usage lists no pdf command:\n#{run.out}")
    refute_match(/not yet implemented/i, line, "the usage still tells the owner pdf does nothing")
  end

  OTHER_STEM = "2026-10-02-TRACKER-999-rerun"
  SECRET = "SECRET-CODENAME"

  def sha(path) = Digest::SHA256.file(path).hexdigest

  # A shares its client, date and title with B, so both resolve to the same client file name.
  def project_with_printed_client_pdf_and_a_namesake(vault)
    project, first = approved_project(vault)
    chrome = standin(@chrome_dir)
    assert_equal 0, pdf(first, chrome: chrome).code, "precondition: A's client PDF is printed"
    namesake = place_source(project, :pass_with_notes, stem: OTHER_STEM)
    qa_report("build", namesake)
    [project, namesake, chrome, sha(qa_file(project, PASS_CLIENT_PDF))]
  end

  def client_pdf_line(run) = run.out.lines.find { |line| line.match?(/client PDF/i) && line.match?(/\bnot\b|n't/i) }

  # Critical: pdf B removed A's client PDF because both resolve to the same name.
  def test_pdf_for_an_unapproved_namesake_leaves_the_other_reports_client_pdf_untouched
    with_vault do |vault|
      Dir.mktmpdir("chrome") do |bin|
        @chrome_dir = bin
        project, namesake, chrome, before = project_with_printed_client_pdf_and_a_namesake(vault)

        run = pdf(namesake, chrome: chrome)

        assert_equal 0, run.code, run.out
        client_pdf = qa_file(project, PASS_CLIENT_PDF)
        assert File.file?(client_pdf), "printing an unapproved report deleted another report's approved client PDF:\n#{run.out}"
        assert_equal before, sha(client_pdf), "printing an unapproved report changed another report's client PDF"
      end
    end
  end

  def test_pdf_for_an_approved_namesake_refuses_and_leaves_the_other_reports_client_pdf_untouched
    with_vault do |vault|
      Dir.mktmpdir("chrome") do |bin|
        @chrome_dir = bin
        project, namesake, chrome, before = project_with_printed_client_pdf_and_a_namesake(vault)
        forge_approval(namesake)
        qa_report("build", namesake)

        run = pdf(namesake, chrome: chrome)

        assert_equal 1, run.code, "an approved report whose client file name is taken must refuse:\n#{run.out}"
        assert_match(/already taken|already belongs/i, run.out, "the owner must be told the client file name is taken")
        client_pdf = qa_file(project, PASS_CLIENT_PDF)
        assert File.file?(client_pdf), "a refused print deleted another report's approved client PDF"
        assert_equal before, sha(client_pdf), "a refused print changed another report's client PDF"
      end
    end
  end

  def test_pdf_awaiting_approval_says_why_no_client_pdf_was_written
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      assert_equal 0, qa_report("build", source).code

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin))

        assert_equal 0, run.code, run.out
        assert_equal [PASS_INTERNAL_PDF], pdfs(project)
        line = client_pdf_line(run) or flunk("pdf printed only the internal PDF without saying the client PDF was not written:\n#{run.out}")
        assert_match(/awaiting/i, line, "the owner must be told the client PDF waits on approval")
      end
    end
  end

  def test_pdf_with_a_stale_approval_says_why_no_client_pdf_was_written
    with_vault do |vault|
      project, source = approved_project(vault)
      edit_source(source) { |data| data["summary"]["lead"] = "A changed lead the owner has not approved." }
      assert_equal 0, qa_report("build", source).code

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin))

        assert_equal 0, run.code, run.out
        assert_equal [PASS_INTERNAL_PDF], pdfs(project)
        line = client_pdf_line(run) or flunk("pdf skipped the client PDF of a stale approval without saying so:\n#{run.out}")
        assert_match(/awaiting|stale/i, line, "the owner must be told the approval is stale")
      end
    end
  end

  def test_pdf_with_the_approved_client_html_missing_asks_for_a_build
    with_vault do |vault|
      project, source = approved_project(vault)
      File.delete(qa_file(project, PASS_CLIENT_FILE))

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin))

        assert_equal 1, run.code, "pdf finished quietly with the approved client HTML missing:\n#{run.out}"
        assert_match(/run build first/i, run.out)
        refute_includes pdf_leftovers(project), PASS_CLIENT_PDF
      end
    end
  end

  def test_build_records_the_sha256_of_each_html_it_wrote
    with_vault do |vault|
      project, = approved_project(vault)
      internal = "#{PASS_STEM}-internal.html"

      recorded = front_matter(File.read(qa_file(project, "#{PASS_STEM}.md")))["html_sha256"]

      assert_equal({ internal => sha(qa_file(project, internal)), PASS_CLIENT_FILE => sha(qa_file(project, PASS_CLIENT_FILE)) }, recorded,
        "the note must record the sha256 of the internal and the client HTML build wrote")
    end
  end

  def test_pdf_refuses_a_client_html_edited_after_build
    with_vault do |vault|
      project = make_project(vault, deny: [SECRET])
      source = place_source(project, :pass_with_notes)
      forge_approval(source)
      assert_equal 0, qa_report("build", source).code
      html = qa_file(project, PASS_CLIENT_FILE)
      File.write(html, File.read(html).sub("</body>", "<p>#{SECRET}</p></body>"))

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin))

        assert_equal 1, run.code, "pdf printed a client HTML that is not the one build wrote:\n#{run.out}"
        assert_match(/run build first/i, run.out)
        refute_includes pdf_leftovers(project), PASS_CLIENT_PDF, "a client PDF holding a denied term was printed from hand-edited HTML"
      end
    end
  end

  def test_pdf_refuses_an_internal_html_edited_after_build
    with_vault do |vault|
      project, source = internal_only_project(vault)
      html = qa_file(project, "#{PASS_STEM}-internal.html")
      File.write(html, File.read(html).sub("</body>", "<p>edited by hand</p></body>"))

      Dir.mktmpdir("chrome") do |bin|
        run = pdf(source, chrome: standin(bin))

        assert_equal 1, run.code, "pdf printed an internal HTML that is not the one build wrote:\n#{run.out}"
        assert_match(/run build first/i, run.out)
        assert_empty pdf_leftovers(project)
      end
    end
  end
end
