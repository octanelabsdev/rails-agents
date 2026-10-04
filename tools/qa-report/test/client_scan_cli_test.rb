require_relative "test_helper"
require_relative "support/cli_harness"
require "cgi/escape"
require "shellwords"

# What the owner sees from build, approve's banner and pending when the client view is scanned or cannot be made.
class ClientScanCliTest < Minitest::Test
  include CliHarness

  IMITATIONS = {
    "Notes in url(data:x;base64,/Users/example/Fizzy" => [[], %w[/Users/ Fizzy]],
    "Card url(data:a;base64,Fizzy board" => [[], %w[Fizzy]],
    "url(data:x;base64,Brightwater" => [%w[Brightwater], %w[Brightwater]]
  }.freeze

  IMITATIONS.each_with_index do |(lead, (deny, terms)), index|
    define_method("test_an_approved_lead_imitating_an_embedded_payload_#{index + 1}_is_blocked") do
      with_vault do |vault|
        project = make_project(vault, deny: deny)
        source = place_source(project, :pass_with_notes) { |data| data["summary"]["lead"] = lead }
        forge_approval(source)

        run = qa_report("build", source)

        assert_equal 2, run.code, "#{lead.inspect} shipped in an approved client file:\n#{run.out}"
        assert terms.any? { |term| run.out.include?(term) }, "build must name one of #{terms.inspect}:\n#{run.out}"
        assert_empty client_files(project), "no client file may be written for #{lead.inspect}"
      end
    end
  end

  def test_a_deny_term_found_only_inside_a_real_screenshot_does_not_block_the_client_file
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      forge_approval(source)
      assert_equal 0, qa_report("build", source).code
      html = File.read(qa_file(project, PASS_CLIENT_FILE))
      term = payload_only_run(html) or flunk("precondition: no letters-only run found only inside an image payload")

      write_config(project, deny: [term])
      run = qa_report("build", source)

      assert_equal 0, run.code, "the deny term #{term.inspect} appears only inside screenshot bytes, yet blocked:\n#{run.out}"
      assert_equal [PASS_CLIENT_FILE], client_files(project)
    end
  end

  def test_build_on_an_unapproved_report_whose_client_name_is_taken_says_so_instead_of_awaiting_approval
    with_vault do |vault|
      project = make_project(vault)
      first = place_source(project, :pass_with_notes)
      forge_approval(first)
      assert_equal 0, qa_report("build", first).code

      stem = "2026-10-02-TRACKER-109-composer-rerun"
      second = place_source(project, :pass_with_notes, stem: stem) { |data| data["summary"]["lead"] = "A second run." }
      run = qa_report("build", second)

      assert_equal 1, run.code, "a taken client name was only discovered after approval:\n#{run.out}"
      assert_includes run.out, "already belongs to #{PASS_STEM}.qa.yml"
      refute_match(/awaiting approval/i, run.out, "the owner was invited to approve a report whose client name is taken")
      refute_match(/qa-report approve/, run.out, "build printed an approve command for a report that cannot get a client file")
      assert_equal "blocked", front_matter(File.read(qa_file(project, "#{stem}.md")))["client_status"]
    end
  end

  # Contract chosen: the banner shows the same runnable command build prints; the approved mock is a client view with no banner.
  def test_the_approve_command_in_the_internal_banner_runs_as_shown
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      assert_equal 0, qa_report("build", source).code

      banner = CGI.unescapeHTML(File.read(qa_file(project, "#{PASS_STEM}-internal.html"))[/Client version:[^<]*/].to_s)
      refute_empty banner, "precondition: the internal report has a client-version banner"
      next pass unless banner.match?(/\bapprove\s+\S+\.qa\.yml/)

      words = Shellwords.split(banner[/\S*ruby\s.*\.qa\.yml|\S*qa-report\s+approve\s+\S+/].to_s)
      bin = words.find { |word| File.basename(word) == "qa-report" } or flunk("the banner names no qa-report executable: #{banner}")
      assert File.absolute_path?(bin), "the banner's approve command relies on qa-report being on PATH: #{banner}"
      assert File.file?(bin), "the banner's approve command points at a qa-report that does not exist: #{banner}"
      assert_includes words, source, "the banner's approve command must name the source by its full path: #{banner}"

      out, = Open3.capture2e(clean_env, *words, chdir: Dir.tmpdir, stdin_data: "")
      assert_match(/interactive terminal/i, out, "the banner's approve command did not run as shown: #{banner}")
    end
  end

  def test_pending_reports_a_missing_encoder_as_a_toolchain_problem_not_a_blocked_client_view
    with_vault do |vault|
      project = make_project(vault)
      place_source(project, :pass_with_notes)

      run = qa_report("pending", chdir: project, env: { "PATH" => "" })

      line = run.out.lines.find { |text| text.include?("#{PASS_STEM}.qa.yml") }.to_s
      refute_match(/client view blocked/i, line, "a missing encoder was reported as a blocked client view:\n#{run.out}")
      assert_match(/cwebp|vips/i, run.out, "pending must name the missing toolchain:\n#{run.out}")
    end
  end

  INVISIBLE = {
    "a soft hyphen" => ["Fiz\u00ADzy board", [], "Fizzy"],
    "a zero-width space" => ["see /Users\u200B/qa", [], "/Users/"],
    "a word joiner" => ["Fizz\u2060y", [], "Fizzy"],
    "a zero-width joiner in a configured deny" => ["Bright\u200Dwater", ["Brightwater"], "Brightwater"],
    "a zero-width space in a derived token" => ["CANARY-\u200BINTERNAL-CLEANUP", [], "CANARY-INTERNAL-CLEANUP"]
  }.freeze

  INVISIBLE.each do |label, (lead, deny, term)|
    define_method("test_an_approved_lead_with_#{label.tr(" -", "__")}_inside_a_term_is_blocked") do
      with_vault do |vault|
        project = make_project(vault, deny: deny)
        source = place_source(project, :pass_with_notes) { |data| data["summary"]["lead"] = "Note #{lead} here." }
        forge_approval(source)

        run = qa_report("build", source)

        assert_equal 2, run.code, "#{lead.inspect} shipped in an approved client file:\n#{run.out}"
        assert_includes run.out, term, "build must name #{term.inspect}:\n#{run.out}"
        assert_empty client_files(project), "no client file may be written for #{lead.inspect}"
      end
    end
  end

  # The scan derives tokens from every internal-classed field, not just the internal block.
  INTERNAL_FIELD_LEAKS = {
    "the card" => ["ZORK-4821", ->(data, token) { data["card"] = token }],
    "a non-client note" => ["NOTE-TTL-8484", ->(data, token) { data["notes"].find { |note| note["id"] == "N3" }["title_plain"] = "Paging #{token} at 25" }]
  }.freeze

  INTERNAL_FIELD_LEAKS.each do |label, (token, seed)|
    define_method("test_an_approved_lead_repeating_a_token_from_#{label.tr(" -", "__")}_is_blocked") do
      with_vault do |vault|
        project = make_project(vault)
        source = place_source(project, :pass_with_notes) do |data|
          data["internal"] = { "environment" => "Staging only." }
          seed.call(data, token)
          data["summary"]["lead"] += " Tracked as #{token}."
        end
        forge_approval(source)

        run = qa_report("build", source)

        assert_equal 2, run.code, "#{token} from #{label} shipped in an approved client file:\n#{run.out}"
        assert_includes run.out, token, "build must name #{token.inspect}:\n#{run.out}"
        assert_empty client_files(project), "no client file may be written when the lead repeats #{label}"
      end
    end
  end

  # A deny regex that can never match the normalised scan text gives false confidence, so build refuses it by name.
  UNMATCHABLE = {
    "a start anchor" => "^Falcon",
    "an end anchor" => "Falcon$",
    "a newline escape" => "Project\\nFalcon",
    "a tab escape" => "Project\\tFalcon",
    "a carriage return escape" => "Project\\rFalcon",
    "a literal newline" => "Project\nFalcon",
    "a literal tab" => "Project\tFalcon",
    "a literal non-breaking space" => "Project Falcon",
    "a full-width letter" => "Ｆalcon"
  }.freeze

  UNMATCHABLE.each do |label, pattern|
    define_method("test_a_deny_pattern_with_#{label.tr(" -", "__")}_is_refused_by_name_before_anything_is_written") do
      with_vault do |vault|
        project = make_project(vault, deny: [{ "pattern" => pattern }])
        source = place_source(project, :pass_with_notes)
        forge_approval(source)
        before = Dir.children(File.join(project, "QA")).sort

        run = qa_report("build", source)

        assert_equal 1, run.code, "a deny pattern with #{label} can never match the scanned text, yet build ran:\n#{run.out[0, 500]}"
        assert [pattern, pattern.inspect[1...-1]].any? { |name| run.out.include?(name) },
          "the error must name the offending pattern:\n#{run.out[0, 500]}"
        assert_equal before, Dir.children(File.join(project, "QA")).sort, "nothing may be written on a config error"
      end
    end
  end

  ["acme\\s+corp", "\\d{4}-\\d{2}"].each do |pattern|
    define_method("test_an_ordinary_deny_pattern_#{pattern.inspect}_is_still_accepted") do
      with_vault do |vault|
        project = make_project(vault, deny: [{ "pattern" => pattern }])
        source = place_source(project, :pass_with_notes)
        forge_approval(source)

        run = qa_report("build", source)

        # The date pattern really hits the dated file name (exit 2); only a config refusal (exit 1) is wrong here.
        refute_equal 1, run.code, "an ordinary deny pattern #{pattern.inspect} was refused as unusable:\n#{run.out}"
        refute_match(/deny pattern/i, run.out, "an ordinary deny pattern #{pattern.inspect} was named as a config problem")
      end
    end
  end

  # Ruby regex escapes reach characters the scan has already folded away, so the pattern could never match.
  FOLDED_ESCAPES = {
    "a curly apostrophe escape" => "Acme\\u2019s roadmap",
    "an em dash escape" => "Bright\\u2014water",
    "a non-breaking space escape" => "Acme\\u00A0Corp",
    "a braced non-breaking space escape" => "Acme\\u{a0}Corp",
    "a byte escape for a curly apostrophe" => "Acme\\xE2\\x80\\x99s roadmap"
  }.freeze

  FOLDED_ESCAPES.each do |label, pattern|
    define_method("test_a_deny_pattern_with_#{label.tr(" -", "__")}_is_refused_by_name_before_anything_is_written") do
      with_vault do |vault|
        project = make_project(vault, deny: [{ "pattern" => pattern }])
        source = place_source(project, :pass_with_notes)
        forge_approval(source)
        before = Dir.children(File.join(project, "QA")).sort

        run = qa_report("build", source)

        assert_equal 1, run.code, "deny #{pattern.inspect} names a character the scan folds away, yet build ran:\n#{run.out[0, 500]}"
        assert [pattern, pattern.inspect[1...-1]].any? { |name| run.out.include?(name) },
          "the error must name the offending pattern:\n#{run.out[0, 500]}"
        assert_equal before, Dir.children(File.join(project, "QA")).sort, "nothing may be written on a config error"
      end
    end
  end

  def test_an_approved_lead_repeating_a_controller_action_from_the_process_notes_is_blocked
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes) do |data|
        data["internal"] = { "environment" => "Staging only.", "process_notes" => ["Traced to InvoicesController#create."] }
        data["summary"]["lead"] += " Fixed in InvoicesController#create."
      end
      forge_approval(source)

      run = qa_report("build", source)

      assert_equal 2, run.code, "InvoicesController#create from the process notes shipped in an approved client file:\n#{run.out}"
      assert_includes run.out, "InvoicesController#create", "build must name the leaked identifier:\n#{run.out}"
      assert_empty client_files(project), "no client file may be written when the lead repeats an internal identifier"
    end
  end

  def test_an_approved_report_whose_integer_card_appears_only_inside_longer_values_writes_the_client_file
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes) { |data| data["card"] = 1024 }
      forge_approval(source)

      run = qa_report("build", source)

      assert_equal 0, run.code, "card: 1024 blocked a clean approved client file:\n#{run.out}"
      assert_equal [PASS_CLIENT_FILE], client_files(project), "the approved client file was not written"
    end
  end

  private

  # A letters-only run that sits inside an image payload and nowhere a reader can see.
  def payload_only_run(html)
    payloads = html.scan(/src="data:image\/[^;"]+;base64,([A-Za-z0-9+\/=]+)/).flatten
    readable = html.gsub(/data:[^;"')\s]+;base64,[A-Za-z0-9+\/=]+/, "").downcase + PASS_CLIENT_FILE
    payloads.join(" ").scan(/[A-Za-z]{6,}/).map { |run| run[0, 6] }.find { |run| !readable.include?(run.downcase) }
  end
end
