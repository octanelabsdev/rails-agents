require_relative "test_helper"
require_relative "support/cli_harness"

# {stem}.md is a deterministic Obsidian note with fixed front matter and a short body.
class MarkdownOutputTest < Minitest::Test
  include CliHarness

  KEYS = %w[title date card project verdict verdict_overridden client variants client_status source source_sha256
            schema_version files html_sha256 tags].freeze

  def build_markdown(fixture, **project_options)
    with_vault do |vault|
      project = make_project(vault, **project_options)
      source = place_source(project, fixture)
      yield project, source if block_given?
      run = qa_report("build", source)
      assert_includes [0, 2], run.code, run.out
      return [File.read(qa_file(project, "#{stem_of(source)}.md")), Digest::SHA256.file(source).hexdigest, run]
    end
  end

  def test_an_awaiting_client_report_has_the_documented_front_matter
    markdown, source_digest, = build_markdown(:pass_with_notes)
    meta = front_matter(markdown)

    assert_equal KEYS.sort, meta.keys.sort
    assert_equal "awaiting", meta["client_status"]
    assert_equal ["qa-report", "verdict/pass-with-notes"], meta["tags"]
    assert_equal "PASS WITH NOTES", meta["verdict"]
    assert_equal false, meta["verdict_overridden"]
    assert_equal CLIENT_NAME, meta["client"]
    assert_equal %w[internal client], meta["variants"]
    assert_equal "TRACKER-101", meta["card"].to_s
    assert_equal "2026-10-02", meta["date"].to_s
    assert_equal "#{PASS_STEM}.qa.yml", meta["source"]
    assert_equal source_digest, meta["source_sha256"]
    assert_equal 1, meta["schema_version"]
    assert_includes meta["files"], "#{PASS_STEM}-internal.html"
  end

  def test_the_note_has_no_timestamp
    markdown, = build_markdown(:pass_with_notes)

    refute_match(/\d{1,2}:\d{2}/, markdown, "a wall-clock time would make every rebuild a vault diff")
    refute_match(/\d{4}-\d{2}-\d{2}T\d/, markdown)
  end

  def test_the_body_summarises_the_report
    markdown, = build_markdown(:pass_with_notes)
    body = markdown.sub(/\A---\n.*?\n---\n/m, "")

    assert_match(/^# .*Proposal sections keep their order/, body, "the body opens with an H1")
    assert_includes body, "PASS WITH NOTES"
    assert_includes body, "All 3 requirements met. No issues found. 2 notes for you."
    assert_includes body, "3 of 3", "the stat line carries requirements met"
    assert_includes body, "6 of 7", "the stat line carries journeys passed"
    assert_includes body, "#{PASS_STEM}-internal.html"
    assert_includes body, "Older proposals may still show sections in an unpredictable order"
    assert_includes body, "The dark theme was not covered in this round"
  end

  def test_an_approved_report_is_marked_approved_and_lists_the_client_file
    markdown, = build_markdown(:pass_with_notes) { |_project, source| forge_approval(source) }
    meta = front_matter(markdown)

    assert_equal "approved", meta["client_status"]
    assert_includes meta["files"], PASS_CLIENT_FILE
  end

  def test_a_blocked_report_is_marked_blocked
    markdown, = build_markdown(:pass_with_notes) do |_project, source|
      edit_source(source) { |data| data["summary"]["lead"] += " See /Users/qa for the log." }
      forge_approval(source)
    end

    assert_equal "blocked", front_matter(markdown)["client_status"]
    refute_includes front_matter(markdown)["files"], PASS_CLIENT_FILE
  end

  def test_a_stale_report_is_marked_stale
    markdown, = build_markdown(:pass_with_notes) do |_project, source|
      forge_approval(source)
      edit_source(source) { |data| data["summary"]["lead"] = "Rewritten after approval." }
    end

    assert_equal "stale", front_matter(markdown)["client_status"]
  end

  def test_an_internal_only_fail_report_lists_open_and_known_issues
    markdown, = build_markdown(:fail, variants: %w[internal], client: nil)
    meta = front_matter(markdown)

    assert_nil meta["client"]
    assert_equal "internal-only", meta["client_status"]
    assert_equal ["qa-report", "verdict/fail"], meta["tags"]
    source = load_fixture(:fail)
    %w[D3 D4 D5 D6 D7].each do |id|
      issue = find_by_id(source.issues, id)
      assert_includes markdown, "#{id} · #{issue["severity"]} · #{issue["title_plain"]}", "#{id} is open or known"
    end
    %w[D1 D2 D8].each { |id| refute_match(/^\W*#{id} · /, markdown, "#{id} is neither open nor known") }
  end

  def test_rebuilding_gives_byte_identical_markdown
    with_vault do |vault|
      project = make_project(vault)
      source = place_source(project, :pass_with_notes)
      path = qa_file(project, "#{PASS_STEM}.md")
      qa_report("build", source, env: { "TZ" => "UTC" })
      first = File.binread(path)
      qa_report("build", source, env: { "TZ" => "Pacific/Auckland", "LANG" => "C" })

      assert_equal first, File.binread(path)
    end
  end
end
