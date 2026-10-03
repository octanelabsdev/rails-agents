require "minitest/autorun"
require "date"
require "yaml"
require "json"
require "zlib"
require "fileutils"
require "tmpdir"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "qa_report/source"
require "qa_report/projection"

module QaReportTestHelper
  FIXTURES = File.expand_path("fixtures", __dir__)

  def fixture_path(name)
    File.join(FIXTURES, "#{name}.qa.yml")
  end

  def fixture_data(name)
    YAML.safe_load_file(fixture_path(name), permitted_classes: [Date])
  end

  def load_fixture(name)
    QaReport::Source.load(fixture_path(name))
  end

  # Fixture data with an in-memory edit, validated against the real fixture screenshots.
  def source_from(name, root: FIXTURES)
    data = fixture_data(name)
    yield data if block_given?
    QaReport::Source.new(data, root: root)
  end

  def issue_data(id, severity, status)
    {
      "id" => id, "severity" => severity, "status" => status,
      "title_plain" => "Issue #{id}", "impact_plain" => "Something happens.",
      "steps_plain" => ["Open the screen."], "expected_plain" => "It works.", "actual_plain" => "It does not.",
      "status_note_plain" => "As of October 2, 2026.", "root_cause" => "CANARY-INTERNAL-#{id}"
    }
  end

  def note_data(id)
    {
      "id" => id, "client_facing" => true, "title_plain" => "Note #{id}",
      "body_plain" => "Something to know.", "recommendation_plain" => "Nothing to do."
    }
  end

  def find_by_id(collection, id)
    collection.find { |item| item["id"] == id } || raise("no item #{id.inspect}")
  end

  # A scratch copy of a fixture's screenshots, so a test can break or change image files.
  def with_fixture_copy(name)
    Dir.mktmpdir do |dir|
      FileUtils.cp_r(File.join(FIXTURES, name.to_s), dir)
      yield dir
    end
  end

  def assert_rejected(path, &block)
    error = assert_raises(QaReport::InvalidSource, &block)
    assert_problem error, path
    assert_equal 1, error.exit_code, "an invalid source must exit 1 so neither variant is written"
    error
  end

  def assert_client_blocked(source, path)
    error = assert_raises(QaReport::ClientBlocked) { QaReport::Projection.client(source) }
    assert_problem error, path
    assert_equal 2, error.exit_code, "a blocked client view must exit 2 while the internal view is still written"
    assert_kind_of Hash, QaReport::Projection.internal(source), "the internal view must still be produced"
    error
  end

  def assert_problem(error, path)
    assert error.problems.any? { |problem| problem.start_with?(path) },
      "expected a problem at #{path}, got #{error.problems.inspect}"
    assert_includes error.message, path
  end

  # Smallest valid PNG: 1x1 RGB, so fixtures stay stdlib-generated and decodable.
  def self.png(red, green, blue)
    chunk = ->(type, data) { [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N") }
    "\x89PNG\r\n\x1A\n".b +
      chunk.call("IHDR", [1, 1, 8, 2, 0, 0, 0].pack("NNCCCCC")) +
      chunk.call("IDAT", Zlib::Deflate.deflate([0, red, green, blue].pack("C*"))) +
      chunk.call("IEND", "")
  end
end

class Minitest::Test
  include QaReportTestHelper
end
