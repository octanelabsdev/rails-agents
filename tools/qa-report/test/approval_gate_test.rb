require_relative "test_helper"
require_relative "support/cli_harness"
require "pty"
require "timeout"

# approve requires an interactive terminal and a typed confirmation; any client change makes it stale.
class ApprovalGateTest < Minitest::Test
  include CliHarness

  APPROVER = "Test Owner"

  # Runs approve on a pseudo-terminal and types the answer at the prompt; skipped where no PTY can be opened.
  def approve_at_terminal(source, answer)
    output = +""
    status = nil
    begin
      PTY.spawn(clean_env("QA_REPORT_APPROVED_BY" => APPROVER), RbConfig.ruby, BIN, "approve", source,
                chdir: Dir.tmpdir) do |reader, writer, pid|
        Timeout.timeout(60) do
          output << read_until(reader, /type approve/i)
          writer.puts answer
          output << read_rest(reader)
          _, status = Process.wait2(pid)
        end
      end
    rescue RuntimeError => error
      raise unless error.message.include?("Master/Slave")

      skip "no pseudo-terminal available here (#{error.message}); run outside the sandbox"
    end
    [output, status]
  end

  def read_until(reader, pattern)
    seen = +""
    seen << reader.readpartial(4096) until seen.match?(pattern)
    seen
  rescue EOFError, Errno::EIO
    flunk "approve ended before prompting to type approve:\n#{seen}"
  end

  def read_rest(reader)
    rest = +""
    loop { rest << reader.readpartial(4096) }
  rescue EOFError, Errno::EIO
    rest
  end

  def approval_path(source) = File.join(File.dirname(source), "#{stem_of(source)}.approval.yml")

  def test_approve_refuses_when_stdin_is_a_pipe
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)

      run = qa_report("approve", source, stdin: "approve\n", env: { "QA_REPORT_APPROVED_BY" => APPROVER })

      refute run.status.success?, "approve must refuse without a terminal:\n#{run.out}"
      assert_match(/terminal/i, run.out, "the refusal must say a terminal is required")
      refute File.exist?(approval_path(source)), "no approval file may exist after a refused approve"
      assert_empty client_files(project)
    end
  end

  def test_approve_refuses_with_no_stdin_at_all
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      assert File.file?(BIN), "bin/qa-report does not exist yet"
      out, status = Open3.capture2e(clean_env, RbConfig.ruby, BIN, "approve", source, in: File::NULL)

      refute status.success?, out
      refute File.exist?(approval_path(source))
    end
  end

  def test_typing_approve_at_a_terminal_writes_the_approval_and_the_client_file
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      digest = QaReport::Approval.digest(QaReport::Source.load(source), client: CLIENT_NAME, brand: QaReport::Config.find(source).brand)
      qa_report("build", source)

      output, status = approve_at_terminal(source, "approve")

      assert_includes output, digest, "approve must print the digest the owner is approving"
      assert_includes output, "Everything we checked works.", "approve must print the client summary"
      assert_includes output, "PASS WITH NOTES"
      approval = YAML.safe_load_file(approval_path(source), permitted_classes: [Date])
      assert_equal %w[approved_by approved_on client_digest renderer], approval.keys.sort
      assert_equal APPROVER, approval["approved_by"]
      assert_equal Date.today.iso8601, approval["approved_on"].to_s
      assert_equal digest, approval["client_digest"]
      refute_empty approval["renderer"].to_s
      assert_equal [PASS_CLIENT_FILE], client_files(project), "approve must go on to build the client file"
      assert_includes [0, 3], status.exitstatus, "approve ends with build's result, or 3 while the PDF is pending"
    end
  end

  def test_the_approve_prompt_names_the_internal_report_to_review
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      qa_report("build", source)

      output, = approve_at_terminal(source, "no")
      prompt = output[/\A.*?type approve[^\n]*/im].to_s

      assert_includes prompt, "#{PASS_STEM}-internal.html", "the approver was not told which file to review:\n#{prompt}"
      refute_match(/Review it\b/, prompt, "the prompt asked the approver to review a client file that does not exist yet:\n#{prompt}")
      assert_empty client_files(project)
    end
  end

  def test_typing_anything_else_writes_nothing
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      qa_report("build", source)

      _, status = approve_at_terminal(source, "yes")

      refute status.success?
      refute File.exist?(approval_path(source)), "only the word approve may approve"
      assert_empty client_files(project)
    end
  end

  def test_build_never_writes_an_approval
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      qa_report("build", source, stdin: "approve\n")
      qa_report("pending", chdir: project, stdin: "approve\n")

      refute File.exist?(approval_path(source))
    end
  end

  STALE_CHANGES = {
    "summary lead" => ->(_project, source) { edit_source(source) { |data| data["summary"]["lead"] = "Rewritten after approval." } },
    "screenshot" => lambda { |_project, source|
      File.binwrite(File.join(File.dirname(source), "pass_with_notes/screenshots/1a.png"),
                    QaReportTestHelper.sized_png(800, 600, [12, 34, 56]))
    },
    "client name" => ->(project, _source) { write_config(project, client: "Example Studio") }
  }.freeze

  STALE_CHANGES.each do |label, change|
    define_method("test_a_changed_#{label.tr(" ", "_")}_makes_the_approval_stale") do
      with_vault do |vault|
        project = make_project(vault)
        source = place_source(project, :pass_with_notes)
        approved = forge_approval(source)
        assert_equal 0, qa_report("build", source).code
        assert_equal [PASS_CLIENT_FILE], client_files(project), "precondition: an approved client file exists"

        instance_exec(project, source, &change)
        client = label == "client name" ? "Example Studio" : CLIENT_NAME
        current = QaReport::Approval.digest(QaReport::Source.load(source), client: client, brand: QaReport::Config.find(source).brand)
        refute_equal approved, current, "a #{label} change must change the digest"

        run = qa_report("build", source)

        assert_equal 0, run.code, run.out
        assert_match(/awaiting re-approval/i, run.out)
        assert_includes run.out, approved, "a stale build prints the approved digest"
        assert_includes run.out, current, "and the current digest"
        assert_empty client_files(project), "the earlier client file must be deleted once its approval is stale"

        pending = qa_report("pending", chdir: project)
        assert_equal 0, pending.code, pending.out
        assert_includes pending.out, "#{PASS_STEM}.qa.yml"
      end
    end
  end

  def test_an_approval_made_with_a_different_renderer_version_awaits_re_approval
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      forge_approval(source)
      assert_equal 0, qa_report("build", source).code
      assert_equal [PASS_CLIENT_FILE], client_files(project), "precondition: the current-renderer approval writes the client file"

      forge_approval(source, renderer: "#{QaReport::RENDERER}-older")
      run = qa_report("build", source)

      assert_equal 0, run.code, run.out
      assert_match(/awaiting re-approval/i, run.out, "an approval from another renderer version must be stale")
      assert_empty client_files(project), "the client file must not be rendered under an approval from another renderer"
      assert_equal "stale", front_matter(File.read(qa_file(project, "#{PASS_STEM}.md")))["client_status"]

      pending = qa_report("pending", chdir: project)
      assert_includes pending.out, "#{PASS_STEM}.qa.yml  awaiting re-approval"
    end
  end

  def test_a_renderer_only_change_tells_the_owner_the_renderer_changed_not_the_content
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      forge_approval(source, renderer: "#{QaReport::RENDERER}-older")

      run = qa_report("build", source)

      assert_equal 0, run.code, run.out
      assert_match(/renderer/i, run.out, "a renderer-only re-approval must name the renderer as the reason")
      refute_includes run.out, "content changed", "nothing in the client content changed, so the owner must not be told it did"
    end
  end

  def test_pending_lists_only_unapproved_client_sources
    with_vault do |vault|
      client_project = make_project(vault, "example-co")
      approved = place_source(client_project, :pass_with_notes)
      forge_approval(approved)
      place_source(client_project, :fail)

      internal_project = make_project(vault, "example-studio", variants: %w[internal], client: nil)
      place_source(internal_project, :fail)

      run = qa_report("pending", chdir: client_project)
      assert_equal 0, run.code, run.out
      assert_includes run.out, "#{FAIL_STEM}.qa.yml"
      refute_includes run.out, "#{PASS_STEM}.qa.yml", "an approved source is not pending"

      run = qa_report("pending", chdir: internal_project)
      assert_equal 0, run.code, run.out
      refute_includes run.out, ".qa.yml", "an internal-only project has nothing to approve"
    end
  end

  def test_the_digest_covers_the_client_name_and_ignores_internal_detail
    source = load_fixture(:pass_with_notes)
    digest = QaReport::Approval.digest(source, client: CLIENT_NAME)

    assert_match(/\A\h{64}\z/, digest)
    refute_equal digest, QaReport::Approval.digest(source, client: "Example Studio")
    changed = source_from(:pass_with_notes) { |data| data["internal"]["cleanup"] = "CANARY-INTERNAL-CLEANUP different." }
    assert_equal digest, QaReport::Approval.digest(changed, client: CLIENT_NAME),
      "internal-only edits must not force the owner to re-approve"
  end

  def test_the_digest_covers_every_part_of_the_client_file_name
    digest = QaReport::Approval.digest(load_fixture(:pass_with_notes), client: CLIENT_NAME)
    retitled = source_from(:pass_with_notes) { |data| data["feature_title_plain"] = "Proposal sections stay in order" }
    redated = source_from(:pass_with_notes) { |data| data["tested_on"] = Date.new(2026, 10, 3) }

    refute_equal digest, QaReport::Approval.digest(retitled, client: CLIENT_NAME)
    refute_equal digest, QaReport::Approval.digest(redated, client: CLIENT_NAME)
  end

  # Types the answer up front, so a run that refuses before prompting still ends cleanly.
  def approve_on_pty(source, answer)
    output = +""
    PTY.spawn(clean_env("QA_REPORT_APPROVED_BY" => APPROVER), RbConfig.ruby, BIN, "approve", source,
              chdir: Dir.tmpdir) do |reader, writer, pid|
      Timeout.timeout(60) do
        writer.puts answer
        output << read_rest(reader)
        Process.wait2(pid)
      end
    end
    output
  rescue RuntimeError => error
    raise unless error.message.include?("Master/Slave")

    skip "no pseudo-terminal available here (#{error.message}); run outside the sandbox"
  end

  def test_approving_a_source_without_the_qa_yml_suffix_leaves_it_untouched
    with_vault do |vault|
      project = make_project(vault)
      source = qa_file(project, "report.yml")
      FileUtils.cp(fixture_path(:pass_with_notes), source)
      FileUtils.cp_r(File.join(QaReportTestHelper::FIXTURES, "pass_with_notes"), File.join(project, "QA"))
      before = File.binread(source)

      output = approve_on_pty(source, "approve")

      assert before == File.binread(source), "approve overwrote the owner's source with an approval record:\n#{output}"
      assert_includes output, ".qa.yml", "the refusal must name the suffix a source needs"
      assert_empty Dir.glob(File.join(project, "QA", "*approval*")), "no approval file may be written"
      assert_empty client_files(project)
    end
  end

  BRAND_CHANGES = { "name" => "Northwind Studio Two", "contact_email" => "studio@example.com" }.freeze

  BRAND_CHANGES.each do |key, value|
    define_method("test_a_changed_brand_#{key}_makes_the_approval_stale") do
      with_vault do |vault|
        project = make_project(vault)
        source = place_source(project, :pass_with_notes)
        forge_approval(source)
        assert_equal 0, qa_report("build", source).code
        assert_equal [PASS_CLIENT_FILE], client_files(project), "precondition: an approved client file exists"

        brand_dir = File.join(project, "brand")
        FileUtils.cp_r(File.dirname(QaReportTestHelper::BRAND), brand_dir)
        brand = File.join(brand_dir, "brand.yml")
        File.write(brand, YAML.dump(YAML.safe_load_file(brand).merge(key => value)))
        File.write(File.join(project, "qa-report.yml"),
                   YAML.dump("brand" => brand, "variants" => %w[internal client], "client" => CLIENT_NAME))

        run = qa_report("build", source)

        assert_equal 0, run.code, run.out
        assert_match(/awaiting re-approval/i, run.out, "a client file under a new brand #{key} went out on the old approval")
        assert_empty client_files(project), "the earlier client file must be deleted once its approval is stale"
      end
    end
  end

  # Like approve_on_pty, but hands back the exit status too.
  def approve_on_pty_with_status(source, answer)
    output = +""
    status = nil
    PTY.spawn(clean_env("QA_REPORT_APPROVED_BY" => APPROVER), RbConfig.ruby, BIN, "approve", source,
              chdir: Dir.tmpdir) do |reader, writer, pid|
      Timeout.timeout(60) do
        writer.puts answer
        output << read_rest(reader)
        _, status = Process.wait2(pid)
      end
    end
    [output, status]
  rescue RuntimeError => error
    raise unless error.message.include?("Master/Slave")

    skip "no pseudo-terminal available here (#{error.message}); run outside the sandbox"
  end

  LEAK = "Example Co staging"

  def unapproved_leaking_source(vault)
    project = make_project(vault, deny: [LEAK])
    [project, place_source(project, :pass_with_notes) { |data| data["summary"]["lead"] += " Checked on #{LEAK} first." }]
  end

  def test_build_shows_a_leak_before_the_owner_is_asked_to_approve
    with_vault do |vault|
      project, source = unapproved_leaking_source(vault)

      run = qa_report("build", source)

      assert_equal 2, run.code, "an unapproved leaking source was reported as merely awaiting approval:\n#{run.out}"
      assert_includes run.out, LEAK, "build must name the deny term"
      assert_includes run.out, "Checked on", "the hit must show the text around the term"
      assert_match(/blocked/i, run.out, "build must say the client file is blocked")
      refute_match(/awaiting approval/i, run.out, "the owner must not be invited to approve a file the scan already blocks")
      refute_match(/qa-report approve/, run.out, "build must not print the approve command for a blocked client file")
      assert_empty client_files(project)
    end
  end

  # Contract chosen: pending lists a leaking unapproved source as blocked, never as awaiting approval.
  def test_pending_lists_a_leaking_unapproved_source_as_blocked
    with_vault do |vault|
      project, = unapproved_leaking_source(vault)

      run = qa_report("pending", chdir: project)

      assert_equal 0, run.code, run.out
      line = run.out.lines.find { |text| text.include?("#{PASS_STEM}.qa.yml") }
      refute_nil line, "pending must still list the leaking source, as blocked:\n#{run.out}"
      assert_match(/blocked/i, line, "pending must say the leaking source is blocked")
      refute_match(/awaiting/i, line, "pending told the owner a leaking source is awaiting approval")
    end
  end

  def test_approve_refuses_a_leaking_source_before_prompting
    with_vault do |vault|
      project, source = unapproved_leaking_source(vault)
      qa_report("build", source)

      output, status = approve_on_pty_with_status(source, "approve")

      assert_equal 2, status.exitstatus, "approve on a leaking source must refuse with exit 2:\n#{output}"
      assert_includes output, LEAK, "the refusal must name the deny term"
      refute_match(/type approve/i, output, "the owner was prompted to approve a file the scan already blocks")
      refute File.exist?(approval_path(source)), "no approval file may be written for a leaking source"
      assert_empty client_files(project)
    end
  end

  def test_approve_on_a_taken_client_name_leaves_no_orphaned_approval
    with_vault do |vault|
      project = make_project(vault)
      first = place_source(project, :pass_with_notes)
      forge_approval(first)
      assert_equal 0, qa_report("build", first).code
      second = place_source(project, :pass_with_notes, stem: "2026-10-02-TRACKER-109-composer-rerun") do |data|
        data["summary"]["lead"] = "A second run of the same feature."
      end
      qa_report("build", second)

      output, status = approve_on_pty_with_status(second, "approve")

      assert_equal 1, status.exitstatus, output
      assert_includes output, "already belongs to #{PASS_STEM}.qa.yml", "the refusal must name the owning source"
      refute File.exist?(approval_path(second)), "approve left an approval file behind for a client file it could not write"
      assert_equal [PASS_CLIENT_FILE], client_files(project)
    end
  end

  # Approve must review the report the source produces now, so a source edited since the last build is refused.
  def test_approve_after_editing_the_source_since_the_last_build_tells_the_owner_to_build_first
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      assert_equal 0, qa_report("build", source).code
      edit_source(source) { |data| data["summary"]["lead"] = "Everything we checked works, after one more pass." }
      recorded = front_matter(File.read(qa_file(project, "#{PASS_STEM}.md")))["source_sha256"]
      refute_equal Digest::SHA256.file(source).hexdigest, recorded, "precondition: the .md describes an older source"

      output, status = approve_on_pty_with_status(source, "approve")

      assert_equal 1, status.exitstatus, "approve let the owner approve against a stale internal report:\n#{output}"
      assert_match(/\bbuild\b/i, output, "the refusal must tell the owner to run build first")
      refute_match(/type approve/i, output, "the owner was prompted to approve against a stale internal report")
      refute File.exist?(approval_path(source)), "no approval may be written against a stale internal report"
      assert_empty client_files(project)
    end
  end

  def test_approve_before_any_build_tells_the_owner_to_build_first
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      refute File.exist?(qa_file(project, "#{PASS_STEM}.md")), "precondition: no build has run"

      output, status = approve_on_pty_with_status(source, "approve")

      assert_equal 1, status.exitstatus, "approve prompted with no internal report to review:\n#{output}"
      assert_match(/\bbuild\b/i, output, "the refusal must tell the owner to run build first")
      refute_match(/type approve/i, output, "the owner was prompted with no internal report to review")
      refute File.exist?(approval_path(source)), "no approval may be written before a build"
      assert_empty client_files(project)
    end
  end

  def test_approve_right_after_build_still_prompts
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      assert_equal 0, qa_report("build", source).code

      output, = approve_at_terminal(source, "no")

      assert_match(/type approve/i, output, "a fresh internal report must still lead to the approve prompt")
      assert_empty client_files(project)
    end
  end

  def test_the_library_offers_no_way_to_write_an_approval
    writers = QaReport::Approval.singleton_methods(false) + QaReport::Approval.public_instance_methods(false)
    assert_empty writers.grep(/write|save|record|create|approve!?\z/),
      "an agent could call these; only the approve command, at a terminal, may write the approval file"
  end
end
