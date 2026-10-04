require_relative "test_helper"
require_relative "support/cli_harness"
require "shellwords"
require "stringio"
require "qa_report/build"

# bin/qa-report run as a subprocess against a scratch vault.
class CliTest < Minitest::Test
  include CliHarness

  COMMANDS = %w[new build approve pdf pending].freeze

  def test_no_command_lists_exactly_the_five_commands
    Dir.mktmpdir do |empty|
      refute File.exist?(File.join(empty, "Gemfile"))
      run = qa_report(chdir: empty)

      listed = run.out.lines.filter_map { |line| line[/\A {2}([a-z]+)\b/, 1] }
      assert_equal COMMANDS, listed, "usage must list one command per two-space-indented line:\n#{run.out}"
    end
  end

  def test_an_unknown_command_exits_non_zero_with_the_usage
    run = qa_report("render")
    refute run.status.success?
    assert_includes run.out, "pending"
  end

  def test_new_creates_the_skeleton_and_an_empty_screenshots_folder
    with_vault do |vault|
      project = make_project(vault)
      run = qa_report("new", "TRACKER-101", "composer-child-order", "--date", "2026-10-02", chdir: project)

      assert run.status.success?, run.out
      path = qa_file(project, "#{PASS_STEM}.qa.yml")
      assert File.file?(path), "new must write QA/#{PASS_STEM}.qa.yml"
      shots = qa_file(project, "#{PASS_STEM}/screenshots")
      assert File.directory?(shots), "new must create QA/#{PASS_STEM}/screenshots/"
      assert_empty Dir.children(shots)

      text = File.read(path)
      data = YAML.safe_load(text, permitted_classes: [Date])
      top = QaReport::Source::SCHEMA.fetch(:top)
      assert_equal top.keys.sort, data.keys.sort, "the skeleton must hold every top-level schema key"
      refute blank?(data["schema_version"]), "schema_version must be filled in"
      assert_equal "TRACKER-101", data["card"].to_s, "new fills card from its argument"
      (top.keys - %w[schema_version card]).each do |key|
        assert blank?(data[key]), "#{key} must start empty, got #{data[key].inspect}"
      end
      (top.keys - ["schema_version"]).each do |key|
        assert_match(/^#{key}:.*#.*\b#{top.fetch(key).klass}\b/, text, "#{key} needs a '# #{top.fetch(key).klass}' comment")
      end
    end
  end

  def test_new_defaults_the_date_to_today
    with_vault do |vault|
      project = make_project(vault)
      run = qa_report("new", "TRACKER-101", "composer-child-order", chdir: project)

      assert run.status.success?, run.out
      assert File.file?(qa_file(project, "#{Date.today.iso8601}-TRACKER-101-composer-child-order.qa.yml")), run.out
    end
  end

  def test_new_refuses_to_overwrite_an_existing_source
    with_vault do |vault|
      project = make_project(vault)
      args = ["new", "TRACKER-101", "composer-child-order", "--date", "2026-10-02"]
      assert qa_report(*args, chdir: project).status.success?
      path = qa_file(project, "#{PASS_STEM}.qa.yml")
      File.write(path, "# the agent's work so far\nschema_version: 1\n")
      before = File.binread(path)

      run = qa_report(*args, chdir: project)

      refute run.status.success?, "new must refuse when the source exists"
      assert_equal before, File.binread(path), "the existing source must be byte-identical"
    end
  end

  def test_build_on_an_unfilled_skeleton_exits_1
    with_vault do |vault|
      project = make_project(vault)
      qa_report("new", "TRACKER-101", "composer-child-order", "--date", "2026-10-02", chdir: project)

      run = qa_report("build", qa_file(project, "#{PASS_STEM}.qa.yml"))

      assert_equal 1, run.code, run.out
      assert_empty client_files(project)
    end
  end

  def test_a_fresh_skeleton_build_lists_only_fields_that_are_really_required
    with_vault do |vault|
      project = make_project(vault)
      qa_report("new", "TRACKER-101", "composer-child-order", "--date", "2026-10-02", chdir: project)

      run = qa_report("build", qa_file(project, "#{PASS_STEM}.qa.yml"))

      assert_equal 1, run.code, run.out
      assert_includes run.out, "summary.lead is required", "a real missing required field must still be listed"
      refute_includes run.out, "status_as_of must be a date",
        "the skeleton's blank optional status_as_of was reported as an invalid field:\n#{run.out}"
      refute_includes run.out, "verdict_override.verdict",
        "the skeleton's empty optional verdict_override was reported as a missing required field:\n#{run.out}"
    end
  end

  def test_an_invalid_deny_regex_is_named_in_the_error
    with_vault do |vault|
      project = make_project(vault, deny: [{ "pattern" => "(unclosed" }])
      source = place_source(project, :pass_with_notes)

      run = qa_report("build", source)

      assert_equal 1, run.code, run.out
      assert_includes run.out, "(unclosed", "the owner cannot tell which deny entry is broken:\n#{run.out}"
    end
  end

  def test_the_printed_approve_command_runs_as_shown
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)

      run = qa_report("build", source)

      line = run.out.lines.find { |text| text.match?(/\bapprove\s+\S*\.qa\.yml/) } or flunk("build printed no approve command:\n#{run.out}")
      words = Shellwords.split(line)
      bin = words.find { |word| File.basename(word) == "qa-report" } or flunk("the approve command names no qa-report executable: #{line}")
      assert File.absolute_path?(bin), "the printed command relies on qa-report being on PATH: #{line.strip}"
      assert File.file?(bin), "the printed command points at a qa-report that does not exist: #{bin}"
      assert_includes words, source

      # Run from elsewhere with no stdin, so a resolvable command reaches approve's terminal check.
      out, = Open3.capture2e(clean_env, *words, chdir: Dir.tmpdir, stdin_data: "")
      assert_match(/interactive terminal/i, out, "the printed approve command did not run as shown: #{line.strip}")
    end
  end

  # A bare `ruby` resolves through PATH, which may be a different Ruby than the one that printed the command.
  def test_the_printed_approve_command_starts_with_the_running_ruby_or_the_executable_tool
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)

      run = qa_report("build", source)

      line = run.out.lines.find { |text| text.match?(/\bapprove\s+\S*\.qa\.yml/) } or flunk("build printed no approve command:\n#{run.out}")
      first = Shellwords.split(line).first
      runs_tool = first == BIN && File.executable?(BIN)
      assert first == RbConfig.ruby || runs_tool,
        "the approve command starts with #{first.inspect}, not the running Ruby #{RbConfig.ruby} or an executable #{BIN}: #{line.strip}"
    end
  end

  def test_the_awaiting_message_names_the_internal_report_to_review
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)

      run = qa_report("build", source)

      assert_match(/awaiting approval/i, run.out, "precondition: build awaits approval")
      assert_includes run.out, "#{PASS_STEM}-internal.html", "the owner was not told which file to review before approving:\n#{run.out}"
      refute_match(/Review it\b/, run.out, "build asked the owner to review a client file that does not exist yet:\n#{run.out}")
    end
  end

  def test_build_without_approval_writes_internal_files_and_awaits_approval
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)

      run = qa_report("build", source)

      assert_equal 0, run.code, run.out
      assert File.file?(qa_file(project, "#{PASS_STEM}.md")), "build must write the .md"
      assert File.file?(qa_file(project, "#{PASS_STEM}-internal.html")), "build must write the internal HTML"
      assert_empty client_files(project), "no client file without an owner approval"
      assert_match(/awaiting approval/i, run.out)
      assert_includes run.out, "approve", "build must print the approve command for the owner"
      assert_includes run.out, "#{PASS_STEM}.qa.yml"
      refute File.exist?(qa_file(project, "#{PASS_STEM}.approval.yml")), "build must never write an approval"
    end
  end

  def test_build_with_a_current_approval_writes_the_client_file
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      forge_approval(source)

      run = qa_report("build", source)

      assert_equal 0, run.code, run.out
      assert_equal [PASS_CLIENT_FILE], client_files(project)
      html = File.read(qa_file(project, PASS_CLIENT_FILE))
      assert_includes html, "Proposal sections keep their order"
      refute_includes html, "CANARY", "the client file must hold no internal canary"
      assert_includes File.read(qa_file(project, "#{PASS_STEM}-internal.html")), "app.example.test",
        "the internal file keeps internal detail; the scan applies to the client file only"
    end
  end

  def test_an_unclassed_key_exits_1_and_writes_nothing
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes) { |data| data["mystery_key"] = "x" }

      run = qa_report("build", source)

      assert_equal 1, run.code, run.out
      assert_includes run.out, "mystery_key"
      refute File.exist?(qa_file(project, "#{PASS_STEM}-internal.html"))
      refute File.exist?(qa_file(project, "#{PASS_STEM}.md"))
    end
  end

  def test_a_leak_exits_2_writes_internal_and_deletes_the_earlier_client_file
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      forge_approval(source)
      assert_equal 0, qa_report("build", source).code
      assert_equal [PASS_CLIENT_FILE], client_files(project), "precondition: an earlier client file exists"

      edit_source(source) { |data| data["summary"]["found"] += " Details are on staging.example.test for now." }
      forge_approval(source)
      internal = qa_file(project, "#{PASS_STEM}-internal.html")
      File.delete(internal)

      run = qa_report("build", source)

      assert_equal 2, run.code, run.out
      assert File.file?(internal), "the internal file is still written on a leak"
      assert_empty client_files(project), "the earlier client file must be deleted on a leak"
      assert_includes run.out, "staging.example.test"
      assert_includes run.out, "Details are on", "the hit must show its surrounding text"
    end
  end

  def test_a_project_deny_entry_blocks_the_client_file
    with_vault do |vault|
      project = make_project(vault, deny: ["Example Co staging"])
      source = place_source(project, :fail) { |data| data["summary"]["lead"] += " Checked on Example Co staging." }
      forge_approval(source)

      run = qa_report("build", source)

      assert_equal 2, run.code, run.out
      assert_includes run.out, "Example Co staging"
      assert_empty client_files(project)
    end
  end

  def test_an_internal_value_in_a_client_field_goes_from_clean_to_blocked
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :fail) { |data| data["internal"]["process_notes"] << "Seeded CANARY-HOST.test." }
      forge_approval(source)
      clean = qa_report("build", source)
      assert_equal 0, clean.code, clean.out
      client = File.read(qa_file(project, client_files(project).fetch(0)))
      %w[CANARY-INT-FAIL CANARY-HOST.test app.example.test CANARY-INTERNAL].each { |value| refute_includes client, value }

      edit_source(source) { |data| data["journeys"][0]["description_plain"] += " Ran as CANARY-INT-FAIL." }
      forge_approval(source)
      run = qa_report("build", source)

      assert_equal 2, run.code, run.out
      assert_includes run.out, "CANARY-INT-FAIL"
      assert_empty client_files(project)
    end
  end

  def test_a_client_name_that_leaks_blocks_the_client_file
    with_vault do |vault|
      project = make_project(vault, client: "Fizzy Example")
      source = place_source(project, :pass_with_notes)
      forge_approval(source, client: "Fizzy Example")

      run = qa_report("build", source)

      assert_equal 2, run.code, run.out
      assert_empty Dir.glob(File.join(project, "QA", "fizzy-*"))
    end
  end

  def test_an_internal_only_project_never_gets_a_client_file_or_a_prompt
    with_vault do |vault|
      project = make_project(vault, variants: %w[internal], client: nil)
      source = place_source(project, :pass_with_notes)
      forge_approval(source)

      run = qa_report("build", source)

      assert_equal 0, run.code, run.out
      assert File.file?(qa_file(project, "#{PASS_STEM}.md"))
      assert File.file?(qa_file(project, "#{PASS_STEM}-internal.html"))
      assert_empty client_files(project), "variants: [internal] must never produce a client file"
      refute_match(/approv/i, run.out, "an internal-only project must never ask for approval")
    end
  end

  def test_config_is_found_by_walking_up_from_the_source
    with_vault do |vault|
      project = make_project(vault, client: "Example Studio")
      source = place_source(project, :pass_with_notes)
      forge_approval(source, client: "Example Studio")

      Dir.mktmpdir do |elsewhere|
        run = qa_report("build", source, chdir: elsewhere)
        assert_equal 0, run.code, run.out
      end
      assert_equal ["example-studio-qa-report-2026-10-02-proposal-sections-keep-their-order.html"], client_files(project),
        "the client name must come from the project's qa-report.yml"
    end
  end

  def test_a_missing_encoder_exits_4
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)

      run = qa_report("build", source, env: { "PATH" => "" })

      assert_equal 4, run.code, run.out
    end
  end

  def test_a_same_day_reapproval_overwrites_the_one_client_file
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      forge_approval(source)
      assert_equal 0, qa_report("build", source).code

      edit_source(source) { |data| data["summary"]["lead"] = "Everything we checked works, with a new lead." }
      forge_approval(source)
      run = qa_report("build", source)

      assert_equal 0, run.code, run.out
      assert_equal [PASS_CLIENT_FILE], client_files(project)
      assert_includes File.read(qa_file(project, PASS_CLIENT_FILE)), "with a new lead"
    end
  end

  def test_new_keeps_a_numeric_looking_card_id_as_written
    { "0123" => "some-slug", "1.10" => "other-slug" }.each do |card, slug|
      with_vault do |vault|
        project = make_project(vault)
        run = qa_report("new", card, slug, "--date", "2026-10-02", chdir: project)
        assert run.status.success?, run.out

        data = YAML.safe_load_file(qa_file(project, "2026-10-02-#{card}-#{slug}.qa.yml"), permitted_classes: [Date])
        assert_equal card, data["card"], "card #{card} must load back as the string the owner typed"
      end
    end
  end

  %w[build approve].each do |command|
    define_method("test_#{command}_refuses_a_source_without_the_qa_yml_suffix") do
      with_vault do |vault|
        project = make_project(vault)
        source = qa_file(project, "report.yml")
        FileUtils.cp(fixture_path(:pass_with_notes), source)
        FileUtils.cp_r(File.join(QaReportTestHelper::FIXTURES, "pass_with_notes"), File.join(project, "QA"))
        before = File.binread(source)

        run = qa_report(command, source, env: { "QA_REPORT_APPROVED_BY" => "Test Owner" })

        assert_equal 1, run.code, run.out
        assert_includes run.out, ".qa.yml", "the refusal must name the suffix a source needs"
        assert_equal before, File.binread(source)
        assert_equal ["pass_with_notes", "report.yml"], Dir.children(File.join(project, "QA")).sort, "nothing else may be written"
      end
    end
  end

  def test_a_second_source_cannot_take_another_reports_client_file
    with_vault do |vault|
      project = make_project(vault)
      first = place_source(project, :pass_with_notes)
      forge_approval(first)
      assert_equal 0, qa_report("build", first).code
      owned = File.binread(qa_file(project, PASS_CLIENT_FILE))

      second = place_source(project, :pass_with_notes, stem: "2026-10-02-TRACKER-109-composer-rerun") do |data|
        data["summary"]["lead"] = "A second run of the same feature."
      end
      forge_approval(second)
      run = qa_report("build", second)

      assert_equal 1, run.code, run.out
      assert_includes run.out, "#{PASS_STEM}.qa.yml", "the refusal must name the source that owns the client file"
      assert_equal owned, File.binread(qa_file(project, PASS_CLIENT_FILE)), "the first report's client file was overwritten"

      rebuild = qa_report("build", first)
      assert_equal 0, rebuild.code, rebuild.out
      assert_equal [PASS_CLIENT_FILE], client_files(project)
    end
  end

  { "O'Brien staging" => "an apostrophe", "R&D lab" => "an ampersand" }.each do |term, label|
    define_method("test_a_deny_term_with_#{label.split.last}_blocks_the_client_file") do
      with_vault do |vault|
        project = make_project(vault, deny: [term])
        source = place_source(project, :pass_with_notes) { |data| data["summary"]["lead"] += " Checked on the #{term}." }
        forge_approval(source)

        run = qa_report("build", source)

        assert_equal 2, run.code, "a deny term with #{label} reached the client file once HTML-escaped:\n#{run.out}"
        assert_empty client_files(project)
      end
    end
  end

  { "a newline" => "\n", "two spaces" => "  ", "a non-breaking space" => "\u00A0", "a single space" => " " }.each do |label, gap|
    define_method("test_a_deny_name_split_by_#{label.tr(" -", "__")}_blocks_the_client_file") do
      with_vault do |vault|
        project = make_project(vault, deny: ["Tom Smith"])
        source = place_source(project, :pass_with_notes) { |data| data["summary"]["lead"] += " Reviewed with Tom#{gap}Smith." }
        forge_approval(source)

        run = qa_report("build", source)

        assert_equal 2, run.code, "\"Tom Smith\" split by #{label} reached the client file:\n#{run.out}"
        assert_empty client_files(project), "no client file may be written when a deny name is split by #{label}"
      end
    end
  end

  def test_a_second_source_whose_client_name_is_taken_still_gets_its_note_and_internal_report
    with_vault do |vault|
      project = make_project(vault)
      first = place_source(project, :pass_with_notes)
      forge_approval(first)
      assert_equal 0, qa_report("build", first).code
      owned = File.binread(qa_file(project, PASS_CLIENT_FILE))

      second_stem = "2026-10-02-TRACKER-109-composer-rerun"
      second = place_source(project, :pass_with_notes, stem: second_stem) do |data|
        data["summary"]["lead"] = "A second run of the same feature."
      end
      forge_approval(second)
      run = qa_report("build", second)

      assert_equal 1, run.code, run.out
      assert_includes run.out, "already belongs to #{PASS_STEM}.qa.yml", "the refusal must name the owning source"
      note = qa_file(project, "#{second_stem}.md")
      assert File.file?(note), "the second report's .md must still be written when its client name is taken:\n#{run.out}"
      assert File.file?(qa_file(project, "#{second_stem}-internal.html")),
        "the second report's internal HTML must still be written when its client name is taken"
      assert_equal "blocked", front_matter(File.read(note))["client_status"], "the note must say the client file is blocked"
      assert_equal owned, File.binread(qa_file(project, PASS_CLIENT_FILE)), "the first report's client file was touched"
      assert_equal [PASS_CLIENT_FILE], client_files(project)
    end
  end

  def test_a_deny_pattern_that_matches_nothing_at_all_is_refused_before_anything_is_written
    with_vault do |vault|
      project = make_project(vault, deny: [{ "pattern" => "a*" }])
      source = place_source(project, :pass_with_notes)
      forge_approval(source)
      before = Dir.children(File.join(project, "QA")).sort

      run = qa_report("build", source)

      assert_equal 1, run.code, "a deny pattern that matches the empty string must be a config error:\n#{run.out}"
      assert_includes run.out, "a*", "the error must name the offending pattern"
      assert_equal before, Dir.children(File.join(project, "QA")).sort, "nothing may be written on a config error"
    end
  end

  ["\\b", "(?=x)"].each do |pattern|
    define_method("test_a_zero_width_deny_pattern_#{pattern.inspect}_is_refused_by_name_before_anything_is_written") do
      with_vault do |vault|
        project = make_project(vault, deny: [{ "pattern" => pattern }])
        source = place_source(project, :pass_with_notes)
        forge_approval(source)
        before = Dir.children(File.join(project, "QA")).sort

        run = qa_report("build", source)

        refute_equal 2, run.code, "a zero-width deny pattern flooded a clean approved build with empty hits:\n#{run.out[0, 500]}"
        assert_equal 1, run.code, "a deny pattern that only matches zero-width positions must be a config error like a*:\n#{run.out[0, 500]}"
        assert_includes run.out, pattern, "the error must name the offending pattern"
        assert_equal before, Dir.children(File.join(project, "QA")).sort, "nothing may be written on a config error"
      end
    end
  end

  def test_a_lookahead_deny_pattern_on_matching_client_text_fails_the_build_and_removes_the_client_file
    with_vault do |vault|
      pattern = "(?=Project Falcon)"
      project = make_project(vault, deny: [{ "pattern" => pattern }])
      source = place_source(project, :pass_with_notes)
      forge_approval(source)
      assert_equal 0, qa_report("build", source).code
      assert_equal [PASS_CLIENT_FILE], client_files(project), "precondition: an earlier client file exists"

      edit_source(source) { |data| data["summary"]["found"] += " Codename Project Falcon is on track." }
      forge_approval(source)

      run = qa_report("build", source)

      assert_equal 1, run.code, "a lookahead deny entry silently let 'Project Falcon' into the client file:\n#{run.out}"
      assert_includes run.out, pattern, "the error must name the deny pattern the operator wrote"
      assert_empty client_files(project), "no client file may be left once a deny entry cannot be enforced"
    end
  end

  # A crash between renames must never leave a client file the .md does not list.
  def test_the_note_is_renamed_into_place_before_the_client_file
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      forge_approval(source)
      renamed = []
      original = File.method(:rename)
      File.singleton_class.send(:define_method, :rename) do |from, to|
        renamed << File.basename(to)
        original.call(from, to)
      end
      begin
        assert_equal 0, QaReport::Build.new(source, out: StringIO.new).run
      ensure
        File.singleton_class.send(:define_method, :rename, original)
      end

      note = renamed.index("#{PASS_STEM}.md")
      client = renamed.index(PASS_CLIENT_FILE)
      refute_nil client, "precondition: an approved build renames the client file into place, got #{renamed.inspect}"
      assert note < client, "the client file was renamed before the .md that tracks it: #{renamed.inspect}"
    end
  end

  def test_an_internal_token_with_an_ampersand_blocks_the_client_file
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes) do |data|
        data["internal"]["process_notes"] << "Ran against Q&A-box-77 only."
        data["summary"]["lead"] += " Checked on Q&A-box-77."
      end
      forge_approval(source)

      run = qa_report("build", source)

      assert_equal 2, run.code, "an internal token with & reached the client file once HTML-escaped:\n#{run.out}"
      assert_empty client_files(project)
    end
  end

  def test_the_report_note_links_no_file_that_does_not_exist
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      forge_approval(source)
      assert_equal 0, qa_report("build", source).code

      links = File.read(qa_file(project, "#{PASS_STEM}.md")).scan(/\]\(([^)]+)\)/).flatten
      refute_empty links
      missing = links.reject { |link| File.exist?(qa_file(project, link)) }
      assert_empty missing, "the note links files that were never written"
    end
  end

  def test_the_tool_carries_no_house_brand
    needles = [%w[Oct ane].join, %w[oct ane labs].join]
    files = Dir.glob("**/*", base: CliHarness::TOOL).map { |path| File.join(CliHarness::TOOL, path) }.select { |path| File.file?(path) }
    hits = files.select { |path| needles.any? { |needle| File.binread(path).downcase.include?(needle.downcase) } }

    assert_empty hits.map { |path| path.delete_prefix("#{CliHarness::TOOL}/") }, "a public tool must not carry a house brand"
  end

  private

  def blank?(value)
    case value
    when nil then true
    when String then value.strip.empty?
    when Array then value.all? { |child| blank?(child) }
    when Hash then value.values.all? { |child| blank?(child) }
    else false
    end
  end
end
