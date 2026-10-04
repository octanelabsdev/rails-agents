require_relative "test_helper"

# C-R11 against the real cwebp; skipped where it is not installed, so the fake-encoder tests stay the contract.
class CwebpIntegrationTest < Minitest::Test
  # A decodable 800x600 PNG carrying a text metadata chunk the encoder must drop.
  def real_png
    chunk = ->(type, data) { [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N") }
    rows = ("\0" + "\x80\x40\x20".b * 800) * 600
    "\x89PNG\r\n\x1A\n".b +
      chunk.call("IHDR", [800, 600, 8, 2, 0, 0, 0].pack("NNCCCCC")) +
      chunk.call("tEXt", "Comment\0CANARY-METADATA".b) +
      chunk.call("IDAT", Zlib::Deflate.deflate(rows)) +
      chunk.call("IEND", "")
  end

  # VP8 lossy: 14-bit width after the 3-byte frame tag and start code; VP8L: 14 bits after the signature byte.
  def webp_width(bytes)
    case bytes.byteslice(12, 4)
    when "VP8 " then bytes.byteslice(26, 2).unpack1("v") & 0x3FFF
    when "VP8L" then (bytes.byteslice(21, 4).unpack1("V") & 0x3FFF) + 1
    else flunk("unexpected WebP chunk #{bytes.byteslice(12, 4).inspect}")
    end
  end

  def test_real_cwebp_scales_by_dpr_and_strips_metadata
    encoder = QaReport::Images.encoder(path: ENV.fetch("PATH", ""))
    skip "cwebp is not installed" unless encoder.format == "webp"

    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "shots"))
      File.binwrite(File.join(dir, "shots", "wide.png"), real_png)
      data = fixture_data(:pass_with_notes)
      data["journeys"].each { |journey| journey.merge!("evidence" => [], "evidence_note_plain" => "Checked directly") }
      data["screenshots"] = [{ "id" => "wide", "file" => "shots/wide.png", "group_plain" => "Screens", "variant" => "Light",
                               "alt" => "A screen", "caption" => "A screen", "visibility" => "client",
                               "pixels_clean" => true, "dpr" => 2 }]
      image = QaReport::Images.new(QaReport::Source.new(data, root: dir), encoder: encoder).fetch("wide")

      assert_equal "RIFF", image.bytes.byteslice(0, 4)
      assert_equal "WEBP", image.bytes.byteslice(8, 4)
      assert_equal 400, webp_width(image.bytes)
      refute_includes image.bytes, "CANARY-METADATA"
      refute_match(/EXIF|XMP |ICCP/, image.bytes.byteslice(12, 4))
    end
  rescue QaReport::ToolchainMissing
    skip "no image encoder installed"
  end
end
