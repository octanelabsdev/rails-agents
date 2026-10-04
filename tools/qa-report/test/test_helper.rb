require "minitest/autorun"
require "date"
require "yaml"
require "json"
require "zlib"
require "fileutils"
require "tmpdir"
require "digest"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "qa_report/source"
require "qa_report/projection"
require "qa_report/renderer"
require_relative "support/html_probe"

module QaReportTestHelper
  FIXTURES = File.expand_path("fixtures", __dir__)
  GOLDEN = File.expand_path("golden", __dir__)
  BRAND = File.join(FIXTURES, "brand", "brand.yml")
  CLIENT_NAME = "Example Outfitters"
  CLIENT_FILE = "example-outfitters-qa-report.html"
  STEM = "2026-10-02-TRACKER-101-composer-child-order"

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
      "fixed_in" => ["PR #1"], "retested_on" => Date.new(2026, 10, 2), "status_reason_plain" => "A reason.",
      "root_cause" => "CANARY-INTERNAL-#{id}"
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

  # A valid source with exactly these counts; every journey carries an evidence note so the client view never blocks.
  def counted_source(met:, not_met: 0, blocked: 0, journeys: { "PASS" => 1 }, issues: [], notes: 0)
    source_from(:pass_with_notes) do |data|
      data["journeys"] = journeys.flat_map { |result, count| [result] * count }.each_with_index.map do |result, index|
        { "id" => index + 1, "title_plain" => "Journey #{index + 1}", "description_plain" => "Did a thing.",
          "result" => result, "evidence" => [], "evidence_note_plain" => "Checked directly" }
      end
      failing = data["journeys"].select { |item| %w[FAIL BLOCKED].include?(item["result"]) }.map { |item| item["id"] }
      results = ["MET"] * met + ["NOT MET"] * not_met + ["BLOCKED"] * blocked
      data["requirements"] = results.each_with_index.map do |result, index|
        { "id" => "R#{index + 1}", "text_plain" => "Requirement #{index + 1}.", "result" => result,
          "journeys" => index == met ? failing : [] }
      end
      data["issues"] = issues.each_with_index.map { |(severity, status), index| issue_data("D#{index + 1}", severity, status) }
      data["notes"] = Array.new(notes) { |index| note_data("N#{index + 1}") }
    end
  end

  def copy_for(source) = QaReport::Copy.new(source)

  def neutral_brand = QaReport::Brand.load(BRAND)

  def approved = QaReport::ClientStatus.approved(CLIENT_FILE)

  def renderer_for(source, brand: neutral_brand, client: CLIENT_NAME, status: approved, encoder: FakeEncoder.new)
    source = load_fixture(source) if source.is_a?(Symbol)
    QaReport::Renderer.new(source, brand: brand, client: client, status: status, encoder: encoder)
  end

  def client_html(source, **options) = renderer_for(source, **options).client_html

  def internal_html(source, **options) = renderer_for(source, **options).internal_html

  # The documented delimiter for internal-only regions; removing them must leave the client file.
  def strip_internal(html) = html.gsub(%r{<!--int-->.*?<!--/int-->}m, "")

  # QA_REPORT_UPDATE_GOLDEN=1 rewrites and skips, so a regenerate run can never report itself green.
  def assert_golden(name, actual, dir: GOLDEN)
    path = File.join(dir, name)
    if ENV["QA_REPORT_UPDATE_GOLDEN"] == "1"
      FileUtils.mkdir_p(dir)
      File.binwrite(path, actual)
      skip "regenerated test/golden/#{name}; review the diff, then rerun without QA_REPORT_UPDATE_GOLDEN"
    end

    assert File.exist?(path),
      "test/golden/#{name} is missing; render it with QA_REPORT_UPDATE_GOLDEN=1 ruby bin/test and review it"
    expected = File.binread(path)
    return pass if expected == actual.b

    want_lines = expected.lines
    got_lines = actual.b.lines
    line = (0...[want_lines.size, got_lines.size].max).find { |index| want_lines[index] != got_lines[index] }
    flunk "#{name} differs from its golden file at line #{line.to_i + 1}; if the change is intended, " \
          "regenerate with QA_REPORT_UPDATE_GOLDEN=1 and review the diff"
  end

  # A decodable 1-bit palette PNG, stored (level 0) so bytes never vary by zlib build; a private chunk pads exact sizes.
  def self.sized_png(width, height, rgb = [208, 213, 221], size: nil)
    chunk = ->(type, data) { [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N") }
    row = "\0".b * (1 + (width + 7) / 8)
    head = "\x89PNG\r\n\x1A\n".b + chunk.call("IHDR", [width, height, 1, 3, 0, 0, 0].pack("NNCCCCC")) +
           chunk.call("PLTE", rgb.pack("C3")) + chunk.call("IDAT", Zlib::Deflate.deflate(row * height, Zlib::NO_COMPRESSION))
    pad = size ? size - head.bytesize - 24 : 0
    raise ArgumentError, "a #{width}x#{height} PNG is larger than #{size} bytes" if pad.negative?

    head + (size ? chunk.call("qaPd", "\0".b * pad) : "".b) + chunk.call("IEND", "")
  end

  def self.png_size(bytes) = bytes.byteslice(16, 8).unpack("NN")

  # Smallest valid PNG: 1x1 RGB, so fixtures stay stdlib-generated and decodable.
  def self.png(red, green, blue)
    chunk = ->(type, data) { [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N") }
    "\x89PNG\r\n\x1A\n".b +
      chunk.call("IHDR", [1, 1, 8, 2, 0, 0, 0].pack("NNCCCCC")) +
      chunk.call("IDAT", Zlib::Deflate.deflate([0, red, green, blue].pack("C*"))) +
      chunk.call("IEND", "")
  end
end

# Stands in for cwebp/vips: a real PNG at the requested width; sizes maps a file's basename to raw bytes, or [q80, q65].
class FakeEncoder
  attr_reader :calls

  def initialize(sizes: {})
    @sizes = sizes
    @calls = []
  end

  def format = "png"

  def encode(path, width:, quality:)
    name = File.basename(path, ".*")
    @calls << [name, width, quality]
    source_width, source_height = QaReportTestHelper.png_size(File.binread(path, 24).b)
    # A 48 px strip keeps golden files small; width stays real so data-w matches the image.
    height = (source_height.to_f * width / source_width).round.clamp(1, 48)
    rgb = Digest::SHA256.digest(name).bytes.first(3).map { |byte| 96 + byte / 2 }
    size = Array(@sizes[name]).then { |sizes| quality == 65 ? sizes.last : sizes.first }
    QaReportTestHelper.sized_png(width, height, rgb, size: size)
  end
end

class Minitest::Test
  include QaReportTestHelper
  include HtmlProbe
end
