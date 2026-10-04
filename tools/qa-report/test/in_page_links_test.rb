require_relative "test_helper"

# C-R19: every in-page link resolves in the file it sits in, so B's #shot-* and #a-j-* links land once C renders them.
class InPageLinksTest < Minitest::Test
  def dangling(html)
    ids = html.scan(/\bid="([^"]+)"/).flatten
    html.scan(/\bhref="#([^"]*)"/).flatten.uniq - ids
  end

  %i[pass_with_notes fail].each do |name|
    define_method("test_every_in_page_link_resolves_in_the_#{name}_client_file") do
      assert_empty dangling(client_html(name))
    end

    define_method("test_every_in_page_link_resolves_in_the_#{name}_internal_file") do
      html = internal_html(name)

      assert_match(/href="#shot-/, html, "the fixture should exercise screenshot links")
      assert_match(/href="#a-j-/, html, "the fixture should exercise technical detail links")
      assert_empty dangling(html)
    end
  end

  # AC: the checked-in golden files are what ships, so they must resolve too.
  def test_every_in_page_link_resolves_in_each_golden_file
    Dir[File.join(GOLDEN, "*.html")].sort.each do |path|
      assert_empty dangling(File.read(path, encoding: Encoding::UTF_8)), "#{File.basename(path)} has links with no target"
    end
  end
end
