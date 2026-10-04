require_relative "test_helper"

# A-R12: a screenshot must be a real image file inside the source folder.
class ScreenshotFileTest < Minitest::Test
  JPEG_HEADER = "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00\x01\x01\x00\x00\x01".b
  # Through the VP8 frame's width and height (byte 30), the most the renderer reads from a WebP.
  WEBP_HEADER = "RIFF\x16\x00\x00\x00WEBPVP8 \x0A\x00\x00\x00\x00\x00\x00\x9D\x01\x2A\x90\x01\x2C\x01".b
  SHORT_WEBP = "RIFF\x1A\x00\x00\x00WEBPVP8 \x0E\x00\x00\x00".b

  def with_shot(bytes, name)
    with_fixture_copy(:pass_with_notes) do |root|
      File.binwrite(File.join(root, "pass_with_notes/screenshots", name), bytes)
      yield root
    end
  end

  def point_1b_at(file)
    ->(data) { find_by_id(data["screenshots"], "1b")["file"] = file }
  end

  def test_a_jpeg_header_is_accepted
    with_shot(JPEG_HEADER, "1b.jpg") do |root|
      assert_kind_of QaReport::Source, source_from(:pass_with_notes, root: root, &point_1b_at("pass_with_notes/screenshots/1b.jpg"))
    end
  end

  def test_a_webp_header_is_accepted
    with_shot(WEBP_HEADER, "1b.webp") do |root|
      assert_kind_of QaReport::Source, source_from(:pass_with_notes, root: root, &point_1b_at("pass_with_notes/screenshots/1b.webp"))
    end
  end

  # A WebP cut off before its width is a clean rejection, not a NoMethodError when it is encoded.
  def test_a_webp_too_short_to_hold_its_width_rejects_the_source
    with_shot(SHORT_WEBP, "1b.webp") do |root|
      assert_rejected("screenshots[1b].file") do
        source_from(:pass_with_notes, root: root, &point_1b_at("pass_with_notes/screenshots/1b.webp"))
      end
    end
  end

  # A bare 8-byte PNG signature has no image in it, so the header check needs a full 12 bytes.
  def test_a_file_shorter_than_twelve_bytes_rejects_the_source
    with_shot("\x89PNG\r\n\x1A\n".b, "1b.png") do |root|
      assert_rejected("screenshots[1b].file") { source_from(:pass_with_notes, root: root) }
    end
  end

  def test_a_path_that_climbs_out_of_the_source_folder_rejects_the_source
    Dir.mktmpdir do |outer|
      root = File.join(outer, "QA")
      FileUtils.mkdir_p(root)
      FileUtils.cp_r(File.join(QaReportTestHelper::FIXTURES, "pass_with_notes"), root)
      File.binwrite(File.join(outer, "outside.png"), QaReportTestHelper.png(1, 2, 3))

      assert_rejected("screenshots[1b].file") { source_from(:pass_with_notes, root: root, &point_1b_at("../outside.png")) }
    end
  end

  def test_an_absolute_path_rejects_the_source
    with_fixture_copy(:pass_with_notes) do |root|
      absolute = File.join(root, "pass_with_notes/screenshots/1b.png")

      assert_rejected("screenshots[1b].file") { source_from(:pass_with_notes, root: root, &point_1b_at(absolute)) }
    end
  end

  # File.expand_path raises ArgumentError on an unknown ~user, which must still fail closed as exit 1.
  def test_a_path_naming_an_unknown_home_directory_rejects_the_source
    assert_rejected("screenshots[1b].file") { source_from(:pass_with_notes, &point_1b_at("~nosuchuserxyz/1a.png")) }
  end

  def test_a_path_containing_a_nul_byte_rejects_the_source
    assert_rejected("screenshots[1b].file") { source_from(:pass_with_notes, &point_1b_at("pass_with_notes/screenshots/1b\0.png")) }
  end

  # The path text stays inside the folder, so only the resolved real path shows the escape.
  def test_a_symlink_pointing_outside_the_source_folder_rejects_the_source
    Dir.mktmpdir do |elsewhere|
      outside = File.join(elsewhere, "outside.png")
      File.binwrite(outside, QaReportTestHelper.png(1, 2, 3))

      with_fixture_copy(:pass_with_notes) do |root|
        link = File.join(root, "pass_with_notes/screenshots/1b.png")
        File.delete(link)
        File.symlink(outside, link)

        assert_rejected("screenshots[1b].file") { source_from(:pass_with_notes, root: root) }
      end
    end
  end
end
