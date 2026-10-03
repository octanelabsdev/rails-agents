require_relative "test_helper"

# Every way a source can fail to load ends as InvalidSource (exit 1), never a raw system error.
class LoadingTest < Minitest::Test
  def test_loading_a_directory_is_an_invalid_source
    Dir.mktmpdir do |dir|
      error = assert_raises(QaReport::InvalidSource) { QaReport::Source.load(dir) }

      assert_equal 1, error.exit_code
      assert_includes error.message, dir
    end
  end

  def test_loading_a_missing_path_is_an_invalid_source
    missing = File.join(QaReportTestHelper::FIXTURES, "no-such-report.qa.yml")
    error = assert_raises(QaReport::InvalidSource) { QaReport::Source.load(missing) }

    assert_equal 1, error.exit_code
    assert_includes error.message, missing
  end

  def test_the_base_error_can_be_constructed_and_lists_its_problems
    error = QaReport::Error.new(["summary.lead must be text"])

    assert_includes error.message, "summary.lead must be text"
    assert_equal ["summary.lead must be text"], error.problems
  end
end
