require_relative "test_helper"
require "open3"
require "rbconfig"

# AC21 (A-R11): loading the renderer outside Bundler pulls in nothing but Ruby's own default gems.
class StdlibOnlyTest < Minitest::Test
  LIB = File.expand_path("../lib", __dir__)

  PROBE = <<~RUBY
    require "qa_report/source"
    require "qa_report/projection"
    source = QaReport::Source.load(ARGV.fetch(0))
    QaReport::Projection.client(source)
    puts "bundler=\#{defined?(Bundler).inspect}"
    Gem.loaded_specs.each_value { |spec| puts "\#{spec.name}-\#{spec.version} default=\#{spec.default_gem?}" }
  RUBY

  # An empty gem path stops RubyGems activating newer regular installs of json or date over the defaults.
  def test_the_renderer_loads_only_default_gems_without_bundler
    Dir.mktmpdir do |empty_gem_path|
      env = { "BUNDLE_GEMFILE" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil,
              "GEM_HOME" => empty_gem_path, "GEM_PATH" => empty_gem_path }
      out, err, status = Open3.capture3(env, RbConfig.ruby, "-I", LIB, "-e", PROBE, fixture_path(:pass_with_notes),
        chdir: Dir.tmpdir)

      assert status.success?, "renderer failed to load outside Bundler on Ruby #{RUBY_VERSION}: #{err}"
      lines = out.lines(chomp: true)
      assert_equal "bundler=nil", lines.shift
      refute_empty lines
      assert_empty lines.reject { |line| line.end_with?("default=true") },
        "renderer loaded non-default gems on Ruby #{RUBY_VERSION}"
    end
  end
end
