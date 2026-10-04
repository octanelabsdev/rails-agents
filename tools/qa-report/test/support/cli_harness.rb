# frozen_string_literal: true

require "open3"
require "rbconfig"
require "qa_report/approval"
require "qa_report/config"
require "qa_report/cli"

# Drives bin/qa-report as a subprocess against a scratch vault, the way the owner and the QA agent run it.
module CliHarness
  TOOL = File.expand_path("../..", __dir__)
  BIN = File.join(TOOL, "bin", "qa-report")
  PASS_STEM = "2026-10-02-TRACKER-101-composer-child-order"
  FAIL_STEM = "2026-10-01-TRACKER-102-layout-check"
  PASS_CLIENT_FILE = "example-outfitters-qa-report-2026-10-02-proposal-sections-keep-their-order.html"
  STEMS = { pass_with_notes: PASS_STEM, fail: FAIL_STEM }.freeze

  Run = Struct.new(:out, :status) do
    def code = status.exitstatus
  end

  # No Bundler, no gem paths and no git identity, so a run proves the stdlib-only CLI and never reads the developer's setup.
  def clean_env(extra = {})
    { "BUNDLE_GEMFILE" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil, "GIT_CONFIG_GLOBAL" => File::NULL,
      "GIT_CONFIG_NOSYSTEM" => "1", "QA_REPORT_APPROVED_BY" => nil }.merge(extra)
  end

  def qa_report(*args, chdir: Dir.tmpdir, env: {}, stdin: "")
    assert File.file?(BIN), "bin/qa-report does not exist yet"
    out, status = Open3.capture2e(clean_env(env), RbConfig.ruby, BIN, *args.map(&:to_s), chdir: chdir, stdin_data: stdin)
    Run.new(out, status)
  end

  # A scratch vault holding one project folder with its own qa-report.yml.
  def with_vault
    Dir.mktmpdir("qa-vault") { |vault| yield File.realpath(vault) }
  end

  def make_project(vault, name = "example-co", variants: %w[internal client], client: QaReportTestHelper::CLIENT_NAME,
                   deny: [])
    project = File.join(vault, name)
    FileUtils.mkdir_p(File.join(project, "QA"))
    write_config(project, variants: variants, client: client, deny: deny)
    project
  end

  def write_config(project, variants: %w[internal client], client: QaReportTestHelper::CLIENT_NAME, deny: [])
    config = { "brand" => QaReportTestHelper::BRAND, "variants" => variants, "paper" => "letter", "deny" => deny }
    config["client"] = client if client
    File.write(File.join(project, "qa-report.yml"), YAML.dump(config))
  end

  # Places a fixture as QA/<stem>.qa.yml with its screenshots; a block edits the data before it is written.
  def place_source(project, fixture, stem: STEMS.fetch(fixture))
    qa = File.join(project, "QA")
    shots = File.join(QaReportTestHelper::FIXTURES, fixture.to_s)
    FileUtils.cp_r(shots, qa) unless File.directory?(File.join(qa, fixture.to_s))
    path = File.join(qa, "#{stem}.qa.yml")
    if block_given?
      data = fixture_data(fixture)
      yield data
      File.write(path, YAML.dump(data))
    else
      FileUtils.cp(fixture_path(fixture), path)
    end
    path
  end

  def edit_source(path)
    data = YAML.safe_load_file(path, permitted_classes: [Date])
    yield data
    File.write(path, YAML.dump(data))
  end

  def qa_file(project, name) = File.join(project, "QA", name)

  def stem_of(source_path) = File.basename(source_path, ".qa.yml")

  # Test-only stand-in for an owner approval: the tool itself must never offer a way to write this file.
  def forge_approval(source_path, client: QaReportTestHelper::CLIENT_NAME, renderer: QaReport::RENDERER)
    brand = QaReport::Config.find(source_path).brand
    digest = QaReport::Approval.digest(QaReport::Source.load(source_path), client: client, brand: brand)
    approval = { "approved_by" => "Test Owner", "approved_on" => "2026-10-02", "client_digest" => digest,
                 "renderer" => renderer }
    File.write(File.join(File.dirname(source_path), "#{stem_of(source_path)}.approval.yml"), YAML.dump(approval))
    digest
  end

  def client_files(project) = Dir.glob(File.join(project, "QA", "*-qa-report-*.html")).map { |path| File.basename(path) }

  def front_matter(markdown)
    yaml = markdown[/\A---\n(.*?)\n---\n/m, 1] or flunk("no front matter in:\n#{markdown}")
    YAML.safe_load(yaml, permitted_classes: [Date])
  end
end
