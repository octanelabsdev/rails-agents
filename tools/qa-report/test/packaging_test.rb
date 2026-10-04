require_relative "test_helper"
require "open3"

# QA on card B: a repo ignore rule swallowed lib/qa_report/templates, so a clean checkout could not render.
class PackagingTest < Minitest::Test
  TOOL = File.expand_path("..", __dir__)

  def test_no_file_the_renderer_needs_is_git_ignored
    _, status = Open3.capture2e("git", "-C", TOOL, "rev-parse", "--is-inside-work-tree")
    skip "not a git checkout" unless status.success?

    files = Dir.glob(%w[lib/**/* bin/**/*], base: TOOL).select { |path| File.file?(File.join(TOOL, path)) }
    refute_empty files
    ignored, = Open3.capture2("git", "-C", TOOL, "check-ignore", "--no-index", "--stdin", stdin_data: files.join("\n"))

    assert_empty ignored.split("\n"), "git ignores files the renderer needs, so a clean checkout cannot run it"
  end
end
