require_relative "test_helper"
require "open3"
require "rbconfig"

# B-R2 and B-R16: the same source renders the same self-contained bytes in any zone, locale or day.
class RenderDeterminismTest < Minitest::Test
  LIB = File.expand_path("../lib", __dir__)
  MONTHS = Date::MONTHNAMES.compact.join("|")

  PROBE = <<~RUBY
    require "qa_report/renderer"
    source = QaReport::Source.load(ARGV.fetch(0))
    renderer = QaReport::Renderer.new(source, brand: QaReport::Brand.load(ARGV.fetch(1)), client: "Example Outfitters",
                                      status: QaReport::ClientStatus.approved("example-outfitters-qa-report.html"))
    File.binwrite(File.join(ARGV.fetch(2), "client.html"), renderer.client_html)
    File.binwrite(File.join(ARGV.fetch(2), "internal.html"), renderer.internal_html)
    puts "bundler=\#{defined?(Bundler).inspect}"
    Gem.loaded_specs.each_value { |spec| puts "\#{spec.name}-\#{spec.version} default=\#{spec.default_gem?}" }
  RUBY

  ENVIRONMENTS = [
    { "TZ" => "UTC", "LANG" => "C", "LC_ALL" => "C" },
    { "TZ" => "Asia/Tokyo", "LANG" => "de_DE.UTF-8", "LC_ALL" => "de_DE.UTF-8" },
    { "TZ" => "Pacific/Auckland", "LANG" => "de_DE.UTF-8", "LC_ALL" => "de_DE.UTF-8" }
  ].freeze

  # An empty gem path keeps the probe on Ruby's default gems, as the real CLI runs outside Bundler.
  def render_in(env)
    Dir.mktmpdir do |out|
      Dir.mktmpdir do |gems|
        clean = { "BUNDLE_GEMFILE" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil, "GEM_HOME" => gems, "GEM_PATH" => gems }
        stdout, stderr, status = Open3.capture3(clean.merge(env), RbConfig.ruby, "-I", LIB, "-e", PROBE,
          fixture_path(:fail), QaReportTestHelper::BRAND, out, chdir: Dir.tmpdir)
        assert status.success?, "render failed under #{env.inspect}: #{stderr}"
        { client: File.binread(File.join(out, "client.html")), internal: File.binread(File.join(out, "internal.html")),
          gems: stdout.lines(chomp: true) }
      end
    end
  end

  # AC20 (B-R16)
  def test_bytes_are_identical_across_time_zones_and_locales
    first, *others = ENVIRONMENTS.map { |env| render_in(env) }

    others.each_with_index do |other, index|
      assert first[:client] == other[:client], "client bytes changed under #{ENVIRONMENTS[index + 1].inspect}"
      assert first[:internal] == other[:internal], "internal bytes changed under #{ENVIRONMENTS[index + 1].inspect}"
    end
  end

  # A-R11 carried to B: rendering outside Bundler loads only default gems.
  def test_rendering_loads_only_default_gems_without_bundler
    lines = render_in(ENVIRONMENTS.first)[:gems]

    assert_equal "bundler=nil", lines.shift
    assert_empty lines.reject { |line| line.end_with?("default=true") }, "renderer loaded non-default gems"
  end

  # B-R16: rendering twice in one process gives the same bytes.
  def test_rendering_twice_gives_the_same_bytes
    assert internal_html(:fail) == internal_html(:fail)
    assert client_html(:pass_with_notes) == client_html(:pass_with_notes)
  end

  # B-R16: every date in the output comes from the source, never from the clock.
  def test_no_wall_clock_date_reaches_the_output
    %i[pass_with_notes fail].each do |name|
      allowed = File.read(fixture_path(name)).scan(/\d{4}-\d{2}-\d{2}/).flat_map do |iso|
        date = Date.iso8601(iso)
        [iso, "#{Date::MONTHNAMES[date.month]} #{date.day}, #{date.year}"]
      end + File.read(fixture_path(name)).scan(/(?:#{MONTHS}) \d{1,2}, \d{4}/o)
      [client_html(name), internal_html(name)].each do |html|
        found = html.scan(/\d{4}-\d{2}-\d{2}|(?:#{MONTHS}) \d{1,2}, \d{4}/o).uniq

        assert_empty found - allowed, "#{name}: dates not taken from the source: #{(found - allowed).inspect}"
      end
    end
  end

  # B-R16: the clock does not move the output even when the date changes under the renderer.
  def test_output_does_not_depend_on_today
    source = load_fixture(:fail)
    before = renderer_for(source).internal_html
    Date.singleton_class.alias_method(:__real_today, :today)
    Date.define_singleton_method(:today) { |*| Date.new(2031, 1, 15) }
    Time.singleton_class.alias_method(:__real_now, :now)
    Time.define_singleton_method(:now) { |*args, **kw| __real_now(*args, **kw) + (86_400 * 3000) }
    begin
      assert before == renderer_for(source).internal_html, "the output moved with the clock"
    ensure
      Date.singleton_class.alias_method(:today, :__real_today)
      Time.singleton_class.alias_method(:now, :__real_now)
    end
  end

  # AC2 (B-R2): self-contained, so opening the file makes 0 network requests.
  def test_every_asset_is_inline
    %i[pass_with_notes fail].each do |name|
      [client_html(name), internal_html(name)].each do |html|
        refute_match(/<link\b/i, html, "#{name}: no linked stylesheets or fonts")
        refute_match(/@import\b/, html, "#{name}: no CSS imports")
        refute_match(/<script\b[^>]*\bsrc=/i, html, "#{name}: no external scripts")
        html.scan(/\bsrc="([^"]*)"/).flatten.each { |src| assert src.start_with?("data:"), "#{name}: src #{src[0, 40]}" }
        css(html).scan(/url\(\s*["']?([^"')]*)/).flatten.each do |url|
          assert url.start_with?("data:"), "#{name}: CSS url #{url[0, 40]}"
        end
      end
    end
  end

  # AC2 (B-R2): the brand font is embedded, not fetched.
  def test_brand_fonts_are_embedded_as_data_uris
    styles = css(client_html(:pass_with_notes))
    font = [File.binread(File.join(QaReportTestHelper::FIXTURES, "brand", "test-sans.woff2"))].pack("m0")

    assert_match(/@font-face\s*\{[^}]*font-family:\s*["']?Test Sans/m, styles)
    assert_includes styles, "data:font/woff2;base64,#{font}"
  end

  # Leak guard: no machine path reaches either file, so golden files stay portable and public-safe.
  def test_no_local_path_reaches_the_output
    [client_html(:fail), internal_html(:fail)].each do |html|
      refute_includes html, QaReportTestHelper::FIXTURES
      refute_match(%r{/Users/|/home/|file://}, html)
    end
  end
end
