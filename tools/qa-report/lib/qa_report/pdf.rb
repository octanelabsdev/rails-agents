# frozen_string_literal: true

require "fileutils"
require "tmpdir"
require_relative "source"
require_relative "config"
require_relative "approval"
require_relative "build"
require_relative "client_file"

module QaReport
  class PdfPending < Error
    SUMMARY = "PDF PENDING: the PDFs were not written; the HTML files are in place."
    EXIT_CODE = 3
  end

  class BuildNeeded < Error
    SUMMARY = "Nothing was printed."
  end

  # Prints the HTML already on disk with headless Chrome, so the PDF is exactly the file the owner reviewed.
  class Pdf
    MAC_CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    DEFAULT_TIMEOUT = 30
    POLL = 0.1
    TAIL_BYTES = 1024

    def initialize(path, out: $stdout, source: nil, config: nil)
      @path = File.expand_path(path)
      @dir = File.dirname(@path)
      @stem = File.basename(@path, ".qa.yml")
      @out = out
      @source = source || Source.load(@path)
      @config = config || Config.find(@path)
      @build = Build.new(@path, out: @out, source: @source, config: @config)
    end

    def run
      raise BuildNeeded, ["run build first: #{@stem}.md is missing or describes an older version of the source"] unless Build.built_from?(@path, @source)

      client, refusal = vetted_client_html
      jobs = [File.join(@dir, "#{@stem}-internal.html"), client].compact.to_h { |html| [html, ClientFile.pdf_for(html)] }
      jobs.each_key { |html| require_built(html) }
      print_all(jobs)
      raise refusal if refusal

      0
    end

    private

    def require_built(html)
      return if Build.html_current?(@path, @source, html)

      raise BuildNeeded, ["run build first: #{File.basename(html)} is missing or is not the file build wrote"]
    end

    def print_all(jobs)
      deadline = monotonic + timeout
      chrome = chrome_binary
      temps = jobs.transform_values { |pdf| "#{pdf}.tmp#{Process.pid}" }
      jobs.each_key { |html| print_page(chrome, html, temps[html], deadline) }
      temps.each { |html, temp| File.rename(temp, jobs[html]) }
      jobs.each_value { |pdf| @out.puts "Wrote #{File.basename(pdf)}" }
    ensure
      temps&.each_value { |temp| FileUtils.rm_f(temp) }
    end

    # Returns the client HTML to print, or the reason it is withheld; the client scan itself stays in Build.
    def vetted_client_html
      return unless @config.client_variant?

      status = Approval.status(@path, @source, client: @config.client, brand: @config.brand)
      return withheld("awaiting approval") if status.kind == :awaiting
      return withheld("approval is stale") if status.kind == :stale

      @build.check_client
      [File.join(@dir, @build.client_name), nil]
    rescue ClientBlocked, Build::NameTaken, ConfigError => e
      [nil, e]
    end

    def withheld(reason)
      @out.puts "Client PDF #{ClientFile.pdf_for(@build.client_name)} was not written: #{reason}."
      [nil, nil]
    end

    def chrome_binary
      configured = ENV["QA_REPORT_CHROME"].to_s
      binary = configured.empty? ? MAC_CHROME : configured
      return binary if File.file?(binary) && File.executable?(binary)

      raise PdfPending, ["Chrome was not found at #{binary}; set QA_REPORT_CHROME to a Chrome binary"]
    end

    def timeout
      seconds = Float(ENV.fetch("QA_REPORT_PDF_TIMEOUT", ""), exception: false)
      seconds&.positive? ? seconds : DEFAULT_TIMEOUT
    end

    def print_page(chrome, html, target, deadline)
      FileUtils.rm_f(target) # a leftover from an earlier run must not pass for this print
      Dir.mktmpdir("qa-report-chrome") do |profile|
        pid = spawn_chrome(chrome, profile, target, html)
        begin
          wait_for_pdf(pid, target, deadline)
        ensure
          end_group(pid)
        end
      end
    end

    def spawn_chrome(chrome, profile, target, html)
      Process.spawn(chrome, "--headless", "--no-pdf-header-footer", "--user-data-dir=#{profile}", "--print-to-pdf=#{target}",
                    file_url(html), pgroup: true, in: File::NULL, out: File::NULL, err: File::NULL)
    rescue SystemCallError => e
      raise PdfPending, ["Chrome could not be started: #{e.message}"]
    end

    # Chrome can keep running after it prints, so a finished file that has stopped growing ends the wait.
    def wait_for_pdf(pid, target, deadline)
      last_size = nil
      loop do
        size = File.size?(target)
        return if size && size == last_size && complete?(target)

        last_size = size
        raise PdfPending, ["Chrome did not finish printing within #{format("%g", timeout)} seconds"] if monotonic > deadline
        raise PdfPending, ["Chrome exited without writing #{File.basename(target)}"] if reaped?(pid) && !(File.size?(target) && complete?(target))

        sleep POLL
      end
    end

    # Only the tail is read, because the end marker is all that shows the file is whole.
    def complete?(path)
      File.open(path, "rb") do |file|
        file.seek([file.size - TAIL_BYTES, 0].max)
        file.read.sub(/\s+\z/, "").end_with?("%%EOF")
      end
    end

    def file_url(path)
      "file://#{path.split("/").map { |part| part.b.gsub(/[^A-Za-z0-9\-._~]/) { |byte| format("%%%02X", byte.ord) } }.join("/")}"
    end

    # Chrome's helpers can outlive it, so the whole group gets a KILL even after Chrome itself is gone.
    def end_group(pid)
      signal_group("TERM", pid)
      stop = monotonic + 1
      sleep POLL until reaped?(pid) || monotonic > stop
      signal_group("KILL", pid)
      reaped?(pid) || Process.wait(pid)
    rescue Errno::ECHILD
      nil
    end

    def reaped?(pid)
      !Process.wait(pid, Process::WNOHANG).nil?
    rescue Errno::ECHILD
      true
    end

    def signal_group(name, pid)
      Process.kill(name, -pid)
    rescue SystemCallError
      nil
    end

    def monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
