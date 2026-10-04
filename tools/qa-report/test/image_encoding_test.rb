require_relative "test_helper"
require "timeout"

# C-R11 to C-R14 via an injected encoder; limits are embedded (base64) bytes, binary units: 200 KB = 204_800.
class ImageEncodingTest < Minitest::Test
  KB = 1024
  MB = 1024 * KB

  # A pass_with_notes source whose only screenshots are the given ones: { id => [width, height, dpr] }.
  def shots_source(dir, specs)
    FileUtils.mkdir_p(File.join(dir, "shots"))
    data = fixture_data(:pass_with_notes)
    data["journeys"].each { |journey| journey.merge!("evidence" => [], "evidence_note_plain" => "Checked directly") }
    data["screenshots"] = specs.map do |id, (width, height, dpr)|
      File.binwrite(File.join(dir, "shots", "#{id}.png"), QaReportTestHelper.sized_png(width, height))
      { "id" => id, "file" => "shots/#{id}.png", "group_plain" => "Screens", "variant" => "Light",
        "alt" => "Screen #{id}", "caption" => "Screen #{id}", "focal" => "top", "visibility" => "client",
        "pixels_clean" => true }.tap { |shot| shot["dpr"] = dpr if dpr }
    end
    QaReport::Source.new(data, root: dir)
  end

  def uniform_source(dir, count) = shots_source(dir, (1..count).to_h { |index| ["s#{index}", [400, 300, nil]] })

  def sizes(count, bytes) = (1..count).to_h { |index| ["s#{index}", bytes] }

  # Raw bytes whose base64 is exactly `embedded` bytes long.
  def raw(embedded) = embedded / 4 * 3

  def script(dir, name, body)
    File.join(dir, name).tap do |path|
      File.write(path, "#!/bin/sh\n#{body}\n")
      File.chmod(0o755, path)
    end
  end

  def png_file(dir, name = "shot.png")
    File.join(dir, name).tap { |path| File.binwrite(path, QaReportTestHelper.sized_png(40, 30)) }
  end

  # SOI, an APP0, a DHT (C4, not a frame header) and then the given segment.
  def jpeg(tail) = "\xFF\xD8".b + "\xFF\xE0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00".b +
                   "\xFF\xC4\x00\x05\x00\x00\x00".b + tail

  def total_warning?(images) = images.warnings.any? { |warning| warning.match?(/total/i) }

  def build(dir, renderer)
    QaReport::Renderer.write_files(dir, "#{STEM}-internal.html" => renderer.internal_html, CLIENT_FILE => renderer.client_html)
  end

  # AC: width = source px / dpr, capped at 1024 (C-R11).
  def test_width_is_source_pixels_over_device_pixel_ratio_capped_at_1024
    Dir.mktmpdir do |dir|
      source = shots_source(dir, "phone" => [780, 4510, 2], "desktop" => [2400, 1500, 1], "small" => [300, 200, nil],
                                 "triple" => [1170, 2532, 3])
      encoder = FakeEncoder.new
      images = QaReport::Images.new(source, encoder: encoder)

      assert_equal({ "phone" => 390, "desktop" => 1024, "small" => 300, "triple" => 390 },
        %w[phone desktop small triple].to_h { |id| [id, images.fetch(id).width] })
      assert_equal [["phone", 390, 80], ["desktop", 1024, 80], ["small", 300, 80], ["triple", 390, 80]], encoder.calls
    end
  end

  # C-R11: the data URI names whatever format the encoder produced.
  def test_data_uri_names_the_encoder_format
    Dir.mktmpdir do |dir|
      source = uniform_source(dir, 1)
      jpeg_encoder = Struct.new(:format) { def encode(*, **) = "\xFF\xD8\xFF\xE0jpeg".b }.new("jpeg")

      png = QaReport::Images.new(source, encoder: FakeEncoder.new).fetch("s1")
      assert png.data_uri.start_with?("data:image/png;base64,")
      assert_equal png.bytes, png.data_uri.split(",", 2).last.unpack1("m0")
      assert QaReport::Images.new(source, encoder: jpeg_encoder).fetch("s1").data_uri.start_with?("data:image/jpeg;base64,")
    end
  end

  # C-R11: the encoder lookup prefers cwebp and falls back to vips.
  def test_encoder_lookup_prefers_cwebp_then_vips
    Dir.mktmpdir do |bin|
      vips = File.join(bin, "vips")
      File.write(vips, "#!/bin/sh\n")
      File.chmod(0o755, vips)
      assert_equal "jpeg", QaReport::Images.encoder(path: bin).format

      cwebp = File.join(bin, "cwebp")
      File.write(cwebp, "#!/bin/sh\n")
      File.chmod(0o755, cwebp)
      assert_equal "webp", QaReport::Images.encoder(path: bin).format
    end
  end

  # AC: no encoder exits 4 with the named message and writes nothing (C-R11); the renderer finds its own encoder.
  def test_no_encoder_exits_4_and_writes_nothing
    Dir.mktmpdir do |bin|
      Dir.mktmpdir do |out|
        path = ENV.fetch("PATH", nil)
        ENV["PATH"] = bin
        error = begin
          assert_raises(QaReport::ToolchainMissing) { build(out, renderer_for(:pass_with_notes, encoder: nil)) }
        ensure
          ENV["PATH"] = path
        end

        assert_equal 4, error.exit_code
        assert_includes error.message, "renderer toolchain missing (cwebp or vips)"
        assert_empty Dir.children(out)
      end
    end
  end

  # AC: exactly 200 KB at q80 is embedded with no retry (C-R12).
  def test_an_image_of_exactly_200_kb_is_not_re_encoded
    Dir.mktmpdir do |dir|
      encoder = FakeEncoder.new(sizes: { "s1" => [raw(200 * KB), raw(50 * KB)] })
      image = QaReport::Images.new(uniform_source(dir, 1), encoder: encoder).fetch("s1")

      assert_equal [80], encoder.calls.map(&:last)
      assert_equal 80, image.quality
      assert_equal 200 * KB, image.data_uri.split(",", 2).last.bytesize
    end
  end

  # AC: 201 KB at q80 is re-encoded once at q65, and that result is embedded (C-R12).
  def test_an_image_over_200_kb_is_re_encoded_once_at_q65
    Dir.mktmpdir do |dir|
      encoder = FakeEncoder.new(sizes: { "s1" => [raw(201 * KB), raw(150 * KB)] })
      images = QaReport::Images.new(uniform_source(dir, 1), encoder: encoder)

      assert_equal [80, 65], encoder.calls.map(&:last), "201 KB embedded is over the limit even though the raw bytes are not"
      assert_equal 65, images.fetch("s1").quality
      assert_equal raw(150 * KB), images.fetch("s1").bytes.bytesize
      assert_empty images.warnings
    end
  end

  # AC: still over 200 KB at q65 is embedded with a warning naming it, and the build succeeds (C-R12).
  def test_an_image_still_over_200_kb_is_embedded_with_a_warning
    Dir.mktmpdir do |dir|
      encoder = FakeEncoder.new(sizes: { "s1" => [raw(260 * KB), raw(230 * KB)] })
      images = QaReport::Images.new(uniform_source(dir, 1), encoder: encoder)

      assert_equal [80, 65], encoder.calls.map(&:last)
      assert_equal raw(230 * KB), images.fetch("s1").bytes.bytesize
      assert images.warnings.any? { |warning| warning.include?("s1") }, images.warnings.inspect
    end
  end

  # AC: a total of exactly 1.5 MB prints no size warning (C-R13).
  def test_a_total_of_exactly_1_5_mb_does_not_warn
    Dir.mktmpdir do |dir|
      images = QaReport::Images.new(uniform_source(dir, 8), encoder: FakeEncoder.new(sizes: sizes(8, raw(192 * KB))))

      assert_equal 1_572_864, images.embedded_bytes
      assert_empty images.warnings
    end
  end

  # AC: more than 1.5 MB warns and still builds (C-R13).
  def test_a_total_over_1_5_mb_warns
    Dir.mktmpdir do |dir|
      images = QaReport::Images.new(uniform_source(dir, 9), encoder: FakeEncoder.new(sizes: sizes(9, raw(182 * KB))))

      assert_operator images.embedded_bytes, :>, 1_572_864
      assert total_warning?(images), images.warnings.inspect
    end
  end

  # AC: exactly 4 MB still builds (C-R13).
  def test_a_total_of_exactly_4_mb_builds
    Dir.mktmpdir do |dir|
      images = QaReport::Images.new(uniform_source(dir, 32), encoder: FakeEncoder.new(sizes: sizes(32, raw(128 * KB))))

      assert_equal 4_194_304, images.embedded_bytes
    end
  end

  # AC: more than 4 MB exits 1 (C-R13).
  def test_a_total_over_4_mb_exits_1
    Dir.mktmpdir do |dir|
      error = assert_raises(QaReport::ImagesTooLarge) do
        QaReport::Images.new(uniform_source(dir, 33), encoder: FakeEncoder.new(sizes: sizes(33, raw(128 * KB))))
      end

      assert_equal 1, error.exit_code
      assert_kind_of QaReport::Error, error
    end
  end

  # C-R13: the total is measured on the internal file, so internal-only captures count.
  def test_internal_only_captures_count_toward_the_total
    sizes = %w[1a 1b 1c 2a 2b 3a].to_h { |id| [id, raw(100 * KB)] }.merge("4a" => raw(3800 * KB))

    assert_raises(QaReport::ImagesTooLarge) { renderer_for(:pass_with_notes, encoder: FakeEncoder.new(sizes: sizes)).client_html }
  end

  # C-R12, C-R13: the renderer hands its warnings to the caller to print.
  def test_renderer_exposes_image_warnings
    sizes = { "1a" => [raw(260 * KB), raw(230 * KB)] }
    renderer = renderer_for(:pass_with_notes, encoder: FakeEncoder.new(sizes: sizes))
    renderer.internal_html

    assert renderer.warnings.any? { |warning| warning.include?("1a") }, renderer.warnings.inspect
  end

  # C-R8: each screenshot is encoded once per build, however many places reference it.
  def test_each_screenshot_is_encoded_once_per_build
    encoder = FakeEncoder.new
    renderer = renderer_for(:fail, encoder: encoder)
    renderer.internal_html
    renderer.client_html

    assert_equal %w[1a 1b 1c 2a 2b], encoder.calls.map(&:first).sort
  end

  # AC: an over-limit rebuild exits 1 and leaves the earlier files byte-identical with no temp files (C-R14, C-R13).
  def test_a_failed_rebuild_leaves_the_previous_files_untouched
    Dir.mktmpdir do |out|
      build(out, renderer_for(:pass_with_notes))
      before = Dir.children(out).sort.to_h { |name| [name, File.binread(File.join(out, name))] }
      assert_equal ["#{STEM}-internal.html", CLIENT_FILE].sort, before.keys

      huge = FakeEncoder.new(sizes: %w[1a 1b 1c 2a 2b 3a 4a].to_h { |id| [id, 620 * KB] })
      error = assert_raises(QaReport::ImagesTooLarge) { build(out, renderer_for(:pass_with_notes, encoder: huge)) }

      assert_equal 1, error.exit_code
      assert_equal before, Dir.children(out).sort.to_h { |name| [name, File.binread(File.join(out, name))] }
    end
  end

  # C-R14: files appear only once every temporary file is written, and no temporary file survives.
  def test_write_files_moves_into_place_only_after_every_file_is_written
    Dir.mktmpdir do |out|
      File.write(File.join(out, "a.html"), "old")

      assert_raises(SystemCallError) { QaReport::Renderer.write_files(out, "a.html" => "new", "missing/b.html" => "new") }
      assert_equal "old", File.read(File.join(out, "a.html"))
      assert_equal ["a.html"], Dir.children(out)

      QaReport::Renderer.write_files(out, "a.html" => "new", "b.html" => "also new")
      assert_equal "new", File.read(File.join(out, "a.html"))
      assert_equal %w[a.html b.html], Dir.children(out).sort
    end
  end

  # A hung encoder is killed at its deadline and reported, never left to hang the build.
  def test_a_hung_encoder_is_killed_at_its_deadline
    Dir.mktmpdir do |bin|
      script(bin, "cwebp", "sleep 30")
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      error = Timeout.timeout(10) do
        assert_raises(QaReport::ImageEncodingFailed) do
          QaReport::Images.encoder(path: bin, timeout: 0.5).encode(png_file(bin), width: 40, quality: 80)
        end
      end

      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 5
      assert_kind_of QaReport::Error, error
      assert_equal 1, error.exit_code
    end
  end

  # An encoder that succeeds without writing its output is an encoding error, not Errno::ENOENT.
  def test_an_encoder_that_writes_nothing_is_an_encoding_error
    Dir.mktmpdir do |bin|
      script(bin, "cwebp", "exit 0")

      assert_raises(QaReport::ImageEncodingFailed) do
        QaReport::Images.encoder(path: bin).encode(png_file(bin), width: 40, quality: 80)
      end
    end
  end

  # vips reads "[...]" after a file name as load options, so the input path ends with an empty "[]".
  def test_vips_input_path_cannot_be_read_as_options
    Dir.mktmpdir do |bin|
      log = File.join(bin, "argv.log")
      script(bin, "vips", %(printf '%s\\n' "$@" > "#{log}"))
      input = png_file(bin, "login[mobile].png")

      assert_raises(QaReport::ImageEncodingFailed) do
        QaReport::Images.encoder(path: bin).encode(input, width: 40, quality: 80)
      end
      assert_includes File.read(log).lines(chomp: true), "#{input}[]"
    end
  end

  # SOF3 is a frame header too; C4 (DHT) before it is not.
  def test_jpeg_width_comes_from_any_frame_header
    Dir.mktmpdir do |dir|
      path = File.join(dir, "lossless.jpg")
      File.binwrite(path, jpeg("\xFF\xC3\x00\x0B\x08\x02\x58\x03\x20\x01\x01\x11\x00".b))

      assert_equal 800, QaReport::Images.pixel_width(path)
    end
  end

  # A JPEG cut off inside a segment is a clean error, not a TypeError.
  def test_a_truncated_jpeg_is_a_clean_error
    Dir.mktmpdir do |dir|
      path = File.join(dir, "cut.jpg")
      File.binwrite(path, jpeg("\xFF\xC0\x00".b))

      error = assert_raises(QaReport::Error) { QaReport::Images.pixel_width(path) }
      assert_equal 1, error.exit_code
    end
  end

  # A PNG too short to hold its width is rejected cleanly, not a NoMethodError.
  def test_a_png_too_short_for_its_header_is_a_clean_error
    with_fixture_copy(:pass_with_notes) do |root|
      File.binwrite(File.join(root, "pass_with_notes/screenshots/1b.png"), "\x89PNG\r\n\x1A\n\x00\x00\x00\x0DIHDR".b)

      error = assert_raises(QaReport::Error) { renderer_for(source_from(:pass_with_notes, root: root)).internal_html }
      assert_equal 1, error.exit_code
      assert_includes error.message, "1b"
    end
  end

  # A reader left unjoined dies with IOError when the pipe closes; a child holding stdout open makes that certain.
  def test_an_encoder_whose_child_holds_its_output_open_leaves_nothing_on_stderr
    Dir.mktmpdir do |bin|
      script(bin, "cwebp", %(for arg; do out=$arg; done\nprintf x > "$out"\n(sleep 1) &\nexit 0))
      input = png_file(bin)

      errors = capture_thread_stderr { QaReport::Images.encoder(path: bin).encode(input, width: 40, quality: 80) }

      assert_empty errors, "the encoder's output reader was not joined on success"
    end
  end

  # Same on the timeout path; perl's setpgrp lets the holder outlive the group kill.
  def test_a_timed_out_encoder_whose_child_holds_its_output_open_leaves_nothing_on_stderr
    skip "perl is not installed" unless system("perl", "-e", "1")

    Dir.mktmpdir do |bin|
      script(bin, "cwebp", %(perl -e 'setpgrp(0, 0); sleep 1' &\nsleep 30))
      input = png_file(bin)

      errors = capture_thread_stderr do
        assert_raises(QaReport::ImageEncodingFailed) do
          QaReport::Images.encoder(path: bin, timeout: 0.3).encode(input, width: 40, quality: 80)
        end
      end

      assert_empty errors, "the encoder's output reader was not joined after the timeout"
    end
  end

  # Many quick encodes with more output than a pipe buffer holds, the everyday case.
  def test_a_chatty_encoder_leaves_nothing_on_stderr
    Dir.mktmpdir do |bin|
      script(bin, "cwebp", %(for arg; do out=$arg; done\nhead -c 200000 /dev/zero | tr '\\0' x\nprintf x > "$out"))
      input = png_file(bin)
      encoder = QaReport::Images.encoder(path: bin)

      assert_empty capture_thread_stderr { 50.times { encoder.encode(input, width: 40, quality: 80) } }
    end
  end

  # The kill reaches the whole process group, so a child the encoder started dies with it.
  def test_a_timeout_kills_the_encoders_children_too
    Dir.mktmpdir do |bin|
      marker = File.join(bin, "grandchild-survived")
      script(bin, "cwebp", %{(sleep 2; touch "#{marker}") &\nsleep 30})

      assert_raises(QaReport::ImageEncodingFailed) do
        QaReport::Images.encoder(path: bin, timeout: 0.3).encode(png_file(bin), width: 40, quality: 80)
      end
      sleep 3

      refute File.exist?(marker), "a child of the timed-out encoder was still running 3 s later"
    end
  end

  private

  # Thread death reports go to $stderr; extra threads are joined first so a late report is still caught.
  def capture_thread_stderr
    before = Thread.list
    original = $stderr
    $stderr = StringIO.new
    yield
    (Thread.list - before).each do |thread|
      thread.join(2)
    rescue StandardError
      nil
    end
    $stderr.string
  ensure
    $stderr = original
  end
end
