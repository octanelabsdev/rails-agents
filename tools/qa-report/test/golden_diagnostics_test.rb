require_relative "test_helper"

# A golden mismatch must point at the first differing line, including lines only one side has.
class GoldenDiagnosticsTest < Minitest::Test
  NAME = "zz-diagnostics-probe.html"

  # A scratch dir, so the probe never lands in the checked-in test/golden/ or fails on a read-only checkout.
  def setup
    skip "golden update mode rewrites files" if ENV["QA_REPORT_UPDATE_GOLDEN"] == "1"
    @dir = Dir.mktmpdir
    File.binwrite(File.join(@dir, NAME), "one\ntwo\n")
  end

  def teardown = @dir && FileUtils.rm_rf(@dir)

  def test_extra_trailing_lines_are_reported_at_the_first_extra_line
    error = assert_raises(Minitest::Assertion) { assert_golden(NAME, "one\ntwo\nthree\n", dir: @dir) }

    assert_includes error.message, "at line 3"
  end

  def test_missing_trailing_lines_are_reported_at_the_first_missing_line
    error = assert_raises(Minitest::Assertion) { assert_golden(NAME, "one\n", dir: @dir) }

    assert_includes error.message, "at line 2"
  end

  def test_a_changed_line_is_reported_at_that_line
    error = assert_raises(Minitest::Assertion) { assert_golden(NAME, "one\nTWO\n", dir: @dir) }

    assert_includes error.message, "at line 2"
  end
end
