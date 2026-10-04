# frozen_string_literal: true

require "date"
require "fileutils"
require "open3"
require "yaml"
require_relative "source"
require_relative "config"
require_relative "approval"
require_relative "build"
require_relative "skeleton"

module QaReport
  class CLI
    NAME_PART = /\A[\w.-]+\z/
    USAGE = <<~TEXT
      Usage: qa-report <command> [arguments]

      Commands:
        new <card> <slug> [--date YYYY-MM-DD]   start an empty QA source in ./QA
        build <source>                          write the .md, the internal HTML and, once approved, the client HTML
        approve <source>                        approve the client file, from a terminal only
        pdf <source>                            write the PDFs (not yet implemented)
        pending                                 list the sources awaiting approval

      Derived tokens catch identifiers (hosts, emails, ids, code names); list codenames and people's names in `deny` in qa-report.yml.
    TEXT

    def initialize(argv)
      @argv = argv.dup
    end

    def run
      command, *args = @argv
      case command
      when nil, "help", "-h", "--help" then usage
      when "new" then new_source(args)
      when "build" then with_source(args, "build <source>") { |path| Build.new(path).run }
      when "approve" then approve(args)
      when "pdf" then with_source(args, "pdf <source>") { refuse("pdf is not yet implemented") }
      when "pending" then pending
      else refuse("unknown command #{command.inspect}\n\n#{USAGE}")
      end
    rescue Error => e
      warn e.message
      e.exit_code
    end

    private

    def usage
      puts USAGE
      0
    end

    def new_source(args)
      date = args.index("--date") && args.slice!(args.index("--date"), 2).last
      card, slug, *extra = args
      return refuse("usage: qa-report new <card> <slug> [--date YYYY-MM-DD]") unless card && slug && extra.empty?
      return refuse("card and slug may only use letters, digits, dots, dashes and underscores") unless [card, slug].all? { |part| part.match?(NAME_PART) }

      stem = "#{date ? iso_date(date) : Date.today.iso8601}-#{card}-#{slug}"
      FileUtils.mkdir_p("QA")
      File.open(File.join("QA", "#{stem}.qa.yml"), File::WRONLY | File::CREAT | File::EXCL) { |file| file.write(Skeleton.to_yaml(card: card)) }
      FileUtils.mkdir_p(File.join("QA", stem, "screenshots"))
      puts "Created QA/#{stem}.qa.yml and QA/#{stem}/screenshots/"
      0
    rescue Errno::EEXIST
      refuse("QA/#{stem}.qa.yml already exists; not overwriting it")
    rescue Date::Error
      refuse("--date must be a real date in the form YYYY-MM-DD")
    end

    def iso_date(text)
      raise Date::Error unless text.match?(/\A\d{4}-\d{2}-\d{2}\z/)

      Date.iso8601(text).iso8601
    end

    def approve(args)
      with_source(args, "approve <source>") do |path|
        next refuse("approve needs an interactive terminal. Only the person approving should run this, at their own terminal.") unless $stdin.tty?

        approve_at_terminal(path)
      end
    end

    def approve_at_terminal(path)
      source = Source.load(path)
      config = Config.find(path)
      config.check_usable!
      return refuse("this project has no client variant, so there is nothing to approve") unless config.client_variant?

      return refuse("run build first: #{File.basename(path, ".qa.yml")}.md is missing or describes an older version of the source") unless built_from?(path, source)

      approver = approver_name
      return refuse("set QA_REPORT_APPROVED_BY or git config user.name so the approval names you") unless approver

      build = Build.new(path, source: source, config: config)
      build.check_client
      digest = Approval.digest(source, client: config.client, brand: config.brand)
      puts "Review: #{path.delete_suffix(".qa.yml")}-internal.html"
      puts "Client: #{config.client}", "Verdict: #{source.verdict}", "Lead: #{source.data["summary"]["lead"]}", "Digest: #{digest}"
      $stdout.print "Type approve to approve exactly this client file: "
      $stdout.flush
      return refuse("Not approved; nothing was written.") unless $stdin.gets.to_s.chomp == "approve"

      write_approval(path, approver, digest)
      code = build.run
      return code unless code.zero?

      puts "The approval and the client HTML were written. The PDF is not yet implemented, so it is still pending."
      3
    end

    # The owner reviews the internal report the last build wrote, so it must describe this exact source.
    def built_from?(path, source)
      note = path.sub(/\.qa\.yml\z/, ".md")
      File.file?(note) && YAML.safe_load(File.read(note)[/\A---\n(.*?)\n---\n/m, 1].to_s, permitted_classes: [Date]).then { |meta| meta.is_a?(Hash) && meta["source_sha256"] == source.sha256 }
    rescue Psych::Exception
      false
    end

    def write_approval(path, approver, digest)
      record = { "approved_by" => approver, "approved_on" => Date.today.iso8601, "client_digest" => digest, "renderer" => QaReport::RENDERER }
      target = Approval.path_for(path)
      Renderer.write_files(File.dirname(target), File.basename(target) => YAML.dump(record))
    end

    def approver_name
      name = ENV["QA_REPORT_APPROVED_BY"].to_s.strip
      return name unless name.empty?

      out, = Open3.capture2("git", "config", "user.name", err: File::NULL)
      out.strip.then { |git_name| git_name unless git_name.empty? }
    rescue SystemCallError
      nil
    end

    def pending
      config = Config.find(Dir.pwd)
      lines = config.client_variant? ? Dir.glob(File.join(config.dir, "QA", "*.qa.yml")).sort.filter_map { |path| pending_line(path, config) } : []
      puts(lines.empty? ? "Nothing is awaiting approval." : lines)
      0
    end

    def pending_line(path, config)
      source = Source.load(path)
      status = Approval.status(path, source, client: config.client, brand: config.brand)
      return if status.kind == :approved

      Build.new(path, source: source, config: config).check_client
      "QA/#{File.basename(path)}  #{status.kind == :stale ? "awaiting re-approval" : "awaiting approval"}"
    rescue InvalidSource
      nil
    rescue ToolchainMissing => e
      "QA/#{File.basename(path)}  cannot be checked: #{e.class::SUMMARY}"
    rescue Error
      "QA/#{File.basename(path)}  client view blocked"
    end

    def with_source(args, usage)
      return refuse("usage: qa-report #{usage}") unless args.size == 1

      path = File.expand_path(args.first)
      return refuse("a source file must end in .qa.yml, got #{File.basename(path)}") unless path.end_with?(".qa.yml")

      yield path
    end

    def refuse(message)
      warn "qa-report: #{message}"
      1
    end
  end
end
