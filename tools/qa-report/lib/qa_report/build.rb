# frozen_string_literal: true

require "fileutils"
require "rbconfig"
require "shellwords"
require_relative "source"
require_relative "config"
require_relative "renderer"
require_relative "approval"
require_relative "leak_check"
require_relative "markdown"

module QaReport
  # One build: the .md and internal HTML always, the client HTML only for a current approval, a free name and a clean leak scan.
  class Build
    class NameTaken < Error
      SUMMARY = "Client file name already taken."
    end

    Outcome = Struct.new(:status, :kind, :name, :html, :code, :messages)
    INTERNAL_ONLY = Outcome.new(nil, "internal-only", nil, nil, 0, []).freeze

    # A caller that already loaded the source and config passes them in, so what it approves is what gets scanned and built.
    def initialize(path, out: $stdout, source: nil, config: nil)
      @path = File.expand_path(path)
      @dir = File.dirname(@path)
      @stem = File.basename(@path, ".qa.yml")
      @out = out
      @source = source || Source.load(@path)
      @config = config || Config.find(@path)
    end

    def run
      @config.check_usable!
      client = @config.client if @config.client_variant?
      renderer = Renderer.new(@source, brand: @config.brand, client: client)
      outcome = @config.client_variant? ? client_outcome(renderer) : INTERNAL_ONLY
      internal_name = "#{@stem}-internal.html"
      note_name = "#{@stem}.md"
      listed = [internal_name, note_name, outcome.name].compact
      files = { internal_name => renderer.internal_html(status: outcome.status), note_name => markdown(outcome, listed) }
      files[outcome.name] = outcome.html if outcome.name
      write(files, outcome)
      report(files, outcome, renderer)
    end

    # Raises what would block the client file (toolchain, leak, taken name, unusable deny pattern); approve and pending ask this before an approval exists.
    def check_client
      @config.check_usable!
      Images.encoder
      vetted_client_name(Renderer.new(@source, brand: @config.brand, client: @config.client))
    end

    # The one place that spells out how to run approve, so the printed command works from any directory.
    def self.approve_command(path)
      Shellwords.join([RbConfig.ruby, File.expand_path("../../bin/qa-report", __dir__), "approve", path])
    end

    private

    def write(files, outcome)
      remove_earlier_client_files(outcome.name)
      Renderer.write_files(@dir, files)
    end

    def report(files, outcome, renderer)
      renderer.warnings.each { |warning| warn warning }
      files.each_key { |name| @out.puts "Wrote #{name}" }
      outcome.messages.each { |message| @out.puts message }
      outcome.code
    end

    def client_outcome(renderer)
      name = vetted_client_name(renderer)
      status = Approval.status(@path, @source, client: @config.client, brand: @config.brand)
      case status.kind
      when :awaiting then awaiting
      when :stale then stale(status)
      else Outcome.new(ClientStatus.approved(name), "approved", name, renderer.client_html, 0, [])
      end
    rescue NameTaken => e
      Outcome.new(ClientStatus.blocked("client file name already taken"), "blocked", nil, nil, 1, [e.message, "No client file was written."])
    rescue ClientBlocked => e
      blocked(e)
    rescue ConfigError => e
      Outcome.new(ClientStatus.blocked("a deny pattern cannot be enforced"), "blocked", nil, nil, 1, [e.message, "No client file was written."])
    end

    def awaiting
      command = self.class.approve_command(@path)
      Outcome.new(ClientStatus.awaiting(command: command), "awaiting", nil, nil, 0,
                  ["The client file is awaiting approval. Review the internal report #{@stem}-internal.html (the client file is the same page without the internal sections), then approve from a terminal:", "  #{command}"])
    end

    def stale(status)
      Outcome.new(ClientStatus.stale, "stale", nil, nil, 0, [*stale_reason(status), "  #{self.class.approve_command(@path)}"])
    end

    # Equal digests mean only the renderer differs, so the content did not change.
    def stale_reason(status)
      if status.approved_digest == status.current_digest
        ["The client file is awaiting re-approval: the renderer changed after it was approved.",
         "  approved renderer: #{status.approved_renderer.inspect}", "  current renderer:  #{RENDERER}"]
      else
        ["The client file is awaiting re-approval: its content changed after it was approved.",
         "  approved digest: #{status.approved_digest}", "  current digest:  #{status.current_digest}"]
      end
    end

    # The one place that decides the client outcome: the scan reads a payload-free rendering, and the written file is the real one.
    def vetted_client_name(renderer)
      name = "#{ClientFile.stem(client: @config.client, tested_on: @source.data["tested_on"], title: @source.data["feature_title_plain"])}.html"
      LeakCheck.new(@source, deny: @config.deny).check!(renderer.client_scan_html, file_name: name)
      refuse_taken_name(name)
      name
    end

    def refuse_taken_name(name)
      owner = Dir.glob(File.join(@dir, "*.md")).sort.find do |note|
        File.basename(note, ".md") != @stem && listed_files(note).include?(name)
      end
      raise NameTaken, ["#{name} already belongs to #{File.basename(owner, ".md")}.qa.yml; give this report a different title or date"] if owner
    end

    def blocked(error)
      count = error.problems.size
      Outcome.new(ClientStatus.blocked("#{count} blocking problem#{"s" unless count == 1}"), "blocked", nil, nil, 2,
                  [error.message, "No client file was written."])
    end

    def markdown(outcome, files)
      Markdown.new(@source, config: @config, stem: @stem, client_status: outcome.kind, files: files,
                           client_file: outcome.name).to_s
    end

    # Found through the previous .md, since a changed title or client name changes the file name.
    def remove_earlier_client_files(keep)
      earlier_files.each do |name|
        next if keep && File.basename(name, ".*") == File.basename(keep, ".*")

        FileUtils.rm_f(File.join(@dir, name))
      end
    end

    def earlier_files
      listed_files(File.join(@dir, "#{@stem}.md")).select do |name|
        name.include?("-qa-report-") && name.match?(/\.(?:html|pdf)\z/) && name != "#{@stem}-internal.html"
      end
    end

    def listed_files(note)
      return [] unless File.file?(note)

      meta = YAML.safe_load(File.read(note)[/\A---\n(.*?)\n---\n/m, 1].to_s, permitted_classes: [Date])
      meta.is_a?(Hash) ? Array(meta["files"]).map { |name| File.basename(name.to_s) } : []
    rescue Psych::Exception
      []
    end
  end
end
