# frozen_string_literal: true

require "cgi/escape"
require "open3"
require "rbconfig"

# Reads printed PDFs through poppler and stands in for Chrome, so pdf can be tested with and without a real browser.
module PdfProbe
  POPPLER = %w[pdfinfo pdftotext pdffonts pdftoppm pdftohtml].freeze
  MAC_CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  PATH_CHROMES = %w[google-chrome google-chrome-stable chromium chromium-browser].freeze
  INTERNAL_HEADER = "INTERNAL — NOT FOR CLIENT DISTRIBUTION"
  LETTER = [612.0, 792.0].freeze
  # US Letter margins in points: 0.6 in top, left and right; 0.75 in bottom.
  MARGIN = { top: 43.2, side: 43.2, bottom: 54.0 }.freeze

  module_function

  def on_path(name)
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, name) }
       .find { |path| File.file?(path) && File.executable?(path) }
  end

  # QA_REPORT_CHROME in the developer's environment wins, then the macOS app, then a Chrome on PATH.
  def real_chrome
    configured = ENV["QA_REPORT_CHROME"].to_s
    return configured if !configured.empty? && File.executable?(configured)
    return MAC_CHROME if File.executable?(MAC_CHROME)

    PATH_CHROMES.lazy.filter_map { |name| on_path(name) }.first
  end

  def missing_poppler = POPPLER.reject { |tool| on_path(tool) }

  # Why the real-PDF checks cannot run here, or nil when they can.
  def real_pdf_skip_reason
    return "headless Chrome not found (install Google Chrome or set QA_REPORT_CHROME); real-PDF checks skipped" unless real_chrome

    missing = missing_poppler
    "poppler tools missing (#{missing.join(", ")}); real-PDF checks skipped" unless missing.empty?
  end

  def capture(*command)
    out, status = Open3.capture2e(*command)
    raise "#{command.first} failed on #{command.last}: #{out}" unless status.success?

    out
  end

  def page_count(pdf) = capture("pdfinfo", pdf)[/^Pages:\s+(\d+)/, 1].to_i

  # [width, height] in points for every page.
  def page_sizes(pdf)
    capture("pdfinfo", "-f", "1", "-l", page_count(pdf).to_s, pdf)
      .scan(/^Page\s+\d+ size:\s+([\d.]+) x ([\d.]+) pts/).map { |pair| pair.map(&:to_f) }
  end

  # Each page as its non-empty lines, in reading layout, with runs of spaces collapsed.
  def pages(pdf)
    capture("pdftotext", "-layout", pdf, "-").split("\f")[0, page_count(pdf)].map do |page|
      page.lines.map { |line| line.gsub(/[[:space:]]+/, " ").strip }.reject(&:empty?)
    end
  end

  def footer_line?(line) = line.match?(/\bPage \d+ of \d+\z/)

  # A page's lines without the INTERNAL running header and the running footer.
  def body_lines(lines)
    body = lines.dup
    body.shift if body.first == INTERNAL_HEADER
    body.pop if body.last && footer_line?(body.last)
    body
  end

  # [{ name:, type:, embedded: }] from pdffonts; the right-hand columns are fixed, while long names push the rest along.
  def fonts(pdf)
    capture("pdffonts", pdf).lines.drop(2).filter_map do |line|
      match = line.match(/\A(?<name>.+?)\s+(?<type>(?:CID )?(?:Type 1C|Type 1|Type 3|TrueType|Type 0C|Type 0)(?: \(OT\))?)\s+\S+\s+(?<emb>yes|no)\s+(?:yes|no)\s+(?:yes|no)\s+\d+\s+\d+\s*\z/)
      match && { name: match[:name], type: match[:type], embedded: match[:emb] == "yes" }
    end
  end

  # Every word with its box in points, grouped by page.
  def words(pdf)
    capture("pdftotext", "-bbox", pdf, "-").split("<page ").drop(1).map do |page|
      page.scan(/<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">(.*?)<\/word>/m).map do |x_min, y_min, x_max, y_max, word|
        { x_min: x_min.to_f, y_min: y_min.to_f, x_max: x_max.to_f, y_max: y_max.to_f, text: CGI.unescapeHTML(word) }
      end
    end
  end

  # Each page as a greyscale raster: { width:, height:, pixels: [0..255] }.
  def gray_pages(pdf, dpi: 20)
    Dir.mktmpdir("qa-pdf-raster") do |dir|
      capture("pdftoppm", "-gray", "-r", dpi.to_s, pdf, File.join(dir, "page"))
      Dir.glob(File.join(dir, "page*.pgm")).sort.map { |path| read_pgm(File.binread(path)) }
    end
  end

  # Every "Screenshot <id>" cross-reference with the share of its first word's width that a line in the bottom of its box covers.
  # The word has no descenders, so only an underline darkens that strip: about 1.0 underlined, 0.0 plain.
  def screenshot_refs(pdf, dpi: 300)
    rasters = gray_pages(pdf, dpi: dpi)
    scale = dpi / 72.0
    words(pdf).each_with_index.flat_map do |page_words, index|
      raster = rasters[index]
      page_words.each_cons(2).filter_map do |word, id|
        next unless word[:text].casecmp?("screenshot") && id[:text].match?(/\A\d+[a-z]\z/)

        rows = ((word[:y_min] + 0.85 * (word[:y_max] - word[:y_min])) * scale).floor..(word[:y_max] * scale).ceil
        columns = (word[:x_min] * scale).ceil..(word[:x_max] * scale).floor
        cover = rows.map { |y| columns.count { |x| raster[:pixels][y * raster[:width] + x] < 220 } / columns.size.to_f }.max
        { page: index + 1, text: "#{word[:text]} #{id[:text]}", underline: cover }
      end
    end
  end

  # pdftohtml's text runs with the bold flag it reads from the font: [{ text:, bold: }].
  def text_runs(pdf)
    capture("pdftohtml", "-xml", "-i", "-stdout", pdf).scan(%r{<text [^>]*>(.*?)</text>}m).map do |(inner)|
      { text: CGI.unescapeHTML(inner.gsub(/<[^>]+>/, "")), bold: inner.include?("<b>") }
    end
  end

  def read_pgm(bytes)
    header = bytes.match(/\AP5\s+(\d+)\s+(\d+)\s+(\d+)\s/) or raise "not a binary PGM"
    { width: header[1].to_i, height: header[2].to_i, pixels: bytes.byteslice(header.end(0)..).bytes }
  end

  def alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  rescue Errno::EPERM
    true
  end

  # Pids recorded by stand-ins that are still running a moment after pdf returned.
  def surviving(pids, grace: 2)
    deadline = Time.now + grace
    loop do
      left = pids.select { |pid| alive?(pid) }
      return left if left.empty? || Time.now > deadline

      sleep 0.1
    end
  end

  # Ends whatever a failing test left behind, so one red run cannot leak processes into the next.
  def reap(pids)
    pids.each do |pid|
      Process.kill("KILL", pid)
    rescue SystemCallError
      nil
    end
  end

  # A one-page Letter PDF a stand-in can write, with the page it was asked to print kept as a comment.
  def minimal_pdf(printed_url)
    objects = ["<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
               "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>"]
    pdf = +"%PDF-1.4\n% printed: #{printed_url}\n"
    offsets = objects.each_with_index.map do |body, index|
      offset = pdf.bytesize
      pdf << "#{index + 1} 0 obj\n#{body}\nendobj\n"
      offset
    end
    xref = pdf.bytesize
    pdf << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
    offsets.each { |offset| pdf << format("%010d 00000 n \n", offset) }
    pdf << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
  end

  # Chrome stand-in (pids in dir/pids); finish is :exit, :linger, :hang, :silent or :truncated, and finish_for: [url_part, finish] overrides it per page.
  def write_standin(dir, delay: 0, finish: :exit, finish_for: nil)
    path = File.join(dir, "chrome-standin")
    url_part, override = finish_for
    File.write(path, <<~STANDIN)
      #!#{RbConfig.ruby}
      require #{__FILE__.inspect}
      url = ARGV.find { |arg| arg.start_with?("file:") }
      finish = #{finish.inspect}
      finish = #{override.inspect} if #{!url_part.nil?} && url.to_s.include?(#{url_part.to_s.inspect})
      stays = %i[linger hang].include?(finish)
      child = Process.spawn("sleep", "300") if stays
      File.open(#{File.join(dir, "pids").inspect}, "a") { |file| file.puts([Process.pid, child].compact) }
      Signal.trap("TERM", "IGNORE") if stays
      sleep #{delay}
      sleep if finish == :hang
      exit 0 if finish == :silent
      target = ARGV.find { |arg| arg.start_with?("--print-to-pdf=") } or exit 1
      pdf = PdfProbe.minimal_pdf(url)
      pdf = pdf.delete_suffix("%%EOF\\n") if finish == :truncated
      File.binwrite(target.delete_prefix("--print-to-pdf="), pdf)
      sleep if finish == :linger
    STANDIN
    File.chmod(0o755, path)
    path
  end

  def recorded_pids(dir)
    path = File.join(dir, "pids")
    File.file?(path) ? File.readlines(path).map(&:to_i) : []
  end
end
