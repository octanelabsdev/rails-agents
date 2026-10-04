# frozen_string_literal: true

require "open3"
require "tmpdir"
require_relative "source"

module QaReport
  class ToolchainMissing < Error
    SUMMARY = "renderer toolchain missing (cwebp or vips)"
    EXIT_CODE = 4
  end

  class ImagesTooLarge < Error
    SUMMARY = "Embedded images are too large; nothing was produced."
  end

  class ImageEncodingFailed < Error
    SUMMARY = "An image could not be encoded; nothing was produced."
  end

  # Re-encodes every screenshot once, at a bounded width and size, so the report stays a single small file.
  class Images
    Image = Struct.new(:bytes, :width, :quality, :format) do
      def data_uri = "data:image/#{format};base64,#{[bytes].pack("m0")}"
    end

    MAX_WIDTH = 1024
    FIRST_QUALITY = 80
    RETRY_QUALITY = 65
    IMAGE_LIMIT = 200 * 1024
    WARN_TOTAL = 1_572_864
    MAX_TOTAL = 4_194_304
    DEFAULT_TIMEOUT = 60
    FRAME_MARKERS = (0xC0..0xCF).to_a - [0xC4, 0xC8, 0xCC]

    # Shells out with argument arrays only, so no screenshot path ever reaches a shell.
    class Cwebp
      def initialize(binary, timeout) = (@binary = binary; @timeout = timeout)

      def format = "webp"

      def encode(path, width:, quality:)
        Dir.mktmpdir("qa-report") do |dir|
          out = File.join(dir, "out.webp")
          Images.run([@binary, "-quiet", "-q", quality.to_s, "-metadata", "none", "-resize", width.to_s, "0", path, "-o", out],
                     path, out, @timeout)
        end
      end
    end

    class Vips
      def initialize(binary, timeout) = (@binary = binary; @timeout = timeout)

      def format = "jpeg"

      def encode(path, width:, quality:)
        Dir.mktmpdir("qa-report") do |dir|
          out = File.join(dir, "out.jpg")
          # A huge --height keeps tall phone captures from being fitted into a square.
          # The empty "[]" stops a "[" in the file name being read as load options.
          Images.run([@binary, "thumbnail", "#{path}[]", "#{out}[Q=#{quality},strip]", width.to_s, "--height", "1000000"],
                     path, out, @timeout)
        end
      end
    end

    # Stands in for the real images when the page is only scanned: fixed width, no bytes, a payload-free URI.
    class Placeholders
      PLACEHOLDER_URI = "data:,"
      Placeholder = Struct.new(:width) { def data_uri = PLACEHOLDER_URI }

      def initialize(source)
        @images = source.screenshots.to_h { |shot| [shot["id"], Placeholder.new(0)] }
      end

      def fetch(id) = @images.fetch(id)
    end

    attr_reader :warnings

    def self.display_width(source, shot)
      [(pixel_width(source.screenshot_path(shot)).to_f / (shot["dpr"] || 1)).round, MAX_WIDTH].min.clamp(1, MAX_WIDTH)
    end

    def self.encoder(path: ENV.fetch("PATH", ""), timeout: DEFAULT_TIMEOUT)
      dirs = path.split(File::PATH_SEPARATOR)
      { "cwebp" => Cwebp, "vips" => Vips }.each do |name, klass|
        found = dirs.map { |dir| File.join(dir, name) }.find { |candidate| File.file?(candidate) && File.executable?(candidate) }
        return klass.new(found, timeout) if found
      end
      raise ToolchainMissing, ["install cwebp (libwebp) or vips, then build again"]
    end

    # Runs in its own process group so a timeout can kill the encoder and anything it spawned.
    def self.run(command, path, out, timeout)
      name = File.basename(path)
      Open3.popen2e(*command, pgroup: true) do |stdin, output, thread|
        stdin.close
        reader = Thread.new { read_all(output) }
        finished = thread.join(timeout)
        unless finished
          kill_group(thread.pid)
          thread.join
        end
        text = drain(reader, output)
        raise ImageEncodingFailed, ["#{name} took longer than #{timeout} seconds to encode"] unless finished
        raise ImageEncodingFailed, ["#{name} could not be encoded: #{text.strip[0, 200]}"] unless thread.value.success?
      end
      raise ImageEncodingFailed, ["#{name} could not be encoded: the encoder wrote no output"] unless File.file?(out)

      File.binread(out)
    rescue SystemCallError => e
      raise ImageEncodingFailed, ["#{File.basename(path)} could not be encoded: #{e.message}"]
    end

    def self.read_all(io)
      io.read
    rescue IOError
      ""
    end

    # A detached child can keep the pipe open, so close our end rather than wait for it.
    def self.drain(reader, output)
      reader.join(1) || output.close
      reader.value
    end

    def self.kill_group(pid)
      Process.kill("KILL", -pid)
    rescue SystemCallError
      nil
    end

    def self.pixel_width(path)
      header = File.binread(path, 64).b
      if header.start_with?(Source::PNG_SIGNATURE) then header.byteslice(16, 4).unpack1("N")
      elsif header.start_with?(Source::JPEG_SIGNATURE) then jpeg_width(path)
      else webp_width(header)
      end
    end

    def self.jpeg_width(path)
      data = File.binread(path)
      position = 2
      while position + 4 <= data.bytesize
        marker = data.getbyte(position + 1)
        length = data.byteslice(position + 2, 2).unpack1("n")
        break if length < 2

        if FRAME_MARKERS.include?(marker)
          width = data.byteslice(position + 7, 2)
          break if width.nil? || width.bytesize < 2

          return width.unpack1("n")
        end
        position += 2 + length
      end
      raise ImageEncodingFailed, ["#{File.basename(path)} has no readable width"]
    end

    def self.webp_width(header)
      case header.byteslice(12, 4)
      when "VP8 " then header.byteslice(26, 2).unpack1("v") & 0x3FFF
      when "VP8L" then (header.byteslice(21, 4).unpack1("V") & 0x3FFF) + 1
      when "VP8X" then header.byteslice(24, 3).unpack("C3").each_with_index.sum { |byte, index| byte << (8 * index) } + 1
      else raise ImageEncodingFailed, ["an image has no readable width"]
      end
    end

    def initialize(source, encoder:)
      @warnings = []
      @images = source.screenshots.to_h { |shot| [shot["id"], encode(source, shot, encoder)] }
      check_total
    end

    def fetch(id) = @images.fetch(id)

    # The limits are on what lands in the HTML, which is base64 and a third bigger than the raw bytes.
    def embedded_bytes = @images.values.sum { |image| embedded_size(image.bytes) }

    private

    def encode(source, shot, encoder)
      path = source.screenshot_path(shot)
      width = self.class.display_width(source, shot)
      quality = FIRST_QUALITY
      bytes = encoder.encode(path, width: width, quality: quality)
      if embedded_size(bytes) > IMAGE_LIMIT
        quality = RETRY_QUALITY
        bytes = encoder.encode(path, width: width, quality: quality)
      end
      @warnings << "screenshot #{shot["id"]} is #{embedded_size(bytes) / 1024} KB after re-encoding (limit 200 KB)" if embedded_size(bytes) > IMAGE_LIMIT
      Image.new(bytes, width, quality, encoder.format)
    end

    def embedded_size(bytes) = (bytes.bytesize + 2) / 3 * 4

    def check_total
      megabytes = format("%.1f", embedded_bytes / 1_048_576.0)
      raise ImagesTooLarge, ["embedded images total #{megabytes} MB; the limit is 4 MB"] if embedded_bytes > MAX_TOTAL

      @warnings << "embedded images total #{megabytes} MB (over 1.5 MB); the report will be heavy to email" if embedded_bytes > WARN_TOTAL
    end
  end
end
