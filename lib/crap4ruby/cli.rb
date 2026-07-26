module Crap4Ruby
  # Option parsing and pipeline orchestration (spec §3, §4). Every failure
  # path raises Failure; the only Kernel#exit lives in exe/crap4ruby.
  class CLI
    THRESHOLD = 8.0

    USAGE = <<~TEXT
      Usage: crap4ruby [options] [<path>...]

        crap4ruby                       analyze all .rb files under app/ and lib/
        crap4ruby <path>...             analyze explicit files; directories mean all .rb under them
        --changed                       analyze only changed .rb files (git)
        --no-run                        do not run tests; consume the existing coverage report
        --test-command "<cmd>"          run <cmd> under `simplecov run` instead of the detected command
        --coverage-file <path>          coverage report location (default: <project root>/coverage/coverage.json)
        --help                          print this help

      Exit codes: 0 ok · 1 usage error · 2 CRAP threshold exceeded · 3 coverage unavailable/invalid · 4 tests failed
    TEXT

    def self.run(argv, stdout: $stdout, stderr: $stderr, cwd: Dir.pwd)
      new(argv, stdout: stdout, stderr: stderr, cwd: cwd).run
    rescue Failure => failure
      stderr.puts failure.message
      failure.exit_code
    end

    def initialize(argv, stdout:, stderr:, cwd:)
      @argv = argv
      @stdout = stdout
      @stderr = stderr
      @cwd = cwd
      @paths = []
      @changed = false
      @no_run = false
      @test_command = nil
      @coverage_file = nil
      @help = false
    end

    def run
      parse!
      if @help
        @stdout.puts USAGE
        return 0
      end

      project = Project.locate(@cwd)
      files = project.select_files(@paths, changed: @changed, cwd: @cwd)
      if files.empty?
        @stdout.puts "nothing to analyze"
        return 0
      end

      coverage_path =
        if @coverage_file
          File.expand_path(@coverage_file, @cwd)
        else
          File.join(project.root, "coverage", "coverage.json")
        end

      if @no_run
        raise Failure.new("--no-run requires a clean working tree", 3) unless project.tree_clean?
      else
        runner = TestRunner.new(project.root)
        runner.clean(coverage_path)
        runner.run(@test_command)
      end

      coverage = CoverageReport.load(coverage_path, analyzed_files: files)
      verify_trusted_artifact(project, coverage, files) if @no_run

      entries, excluded_count = analyze(files, coverage, project)
      report = Report.new(entries, excluded_count: excluded_count)
      report.render(@stdout)
      gate(report)
    end

    private

    def parse!
      args = @argv.dup
      until args.empty?
        arg = args.shift
        case arg
        when "--help" then @help = true
        when "--changed" then @changed = true
        when "--no-run" then @no_run = true
        when "--test-command" then @test_command = option_value(arg, args)
        when /\A--test-command=(.+)\z/m then @test_command = Regexp.last_match(1)
        when "--coverage-file" then @coverage_file = option_value(arg, args)
        when /\A--coverage-file=(.+)\z/m then @coverage_file = Regexp.last_match(1)
        when /\A-/ then raise Failure.new("unknown option: #{arg}\n\n#{USAGE}", 1)
        else @paths << arg
        end
      end
      if @test_command && @no_run
        raise Failure.new("--test-command cannot be combined with --no-run", 1)
      end
    end

    def option_value(flag, args)
      value = args.shift
      raise Failure.new("missing value for #{flag}", 1) if value.nil?
      value
    end

    # §4.2: the report is a trusted artifact — bound that trust.
    def verify_trusted_artifact(project, coverage, files)
      commit = coverage.meta["commit"]
      raise Failure.new("coverage report has no commit — generated outside a git checkout?", 3) if commit.nil?
      head = project.head_sha
      unless commit == head
        raise Failure.new("coverage report commit #{commit} does not match HEAD #{head}", 3)
      end
      files.each do |file|
        recorded = coverage.entry_for(file)["source"]
        next if recorded.nil?
        on_disk = CoverageReport.logical_lines(File.read(file))
        unless recorded == on_disk
          raise Failure.new("#{project.relative(file)}: source in coverage report does not match the file on disk", 3)
        end
      end
    end

    def analyze(files, coverage, project)
      entries = []
      excluded_count = 0
      files.each do |file|
        relative = project.relative(file)
        raise Failure.new("analyzed file absent: #{relative}", 3) unless File.file?(file)
        methods = MethodExtractor.extract(File.read(file))
        result = begin
          Attribution.call(methods, coverage.entry_for(file))
        rescue Failure => failure
          raise Failure.new("#{relative}: #{failure.message}", failure.exit_code)
        end
        excluded_count += result.excluded.size
        result.rows.each { |row| entries << Report::Entry.new(row: row, path: relative) }
      end
      [entries, excluded_count]
    end

    def gate(report)
      max = report.max_crap
      return 0 unless max && max > THRESHOLD
      @stderr.puts "CRAP threshold exceeded: #{Report.decimal(max, 2)} > 8.0"
      2
    end
  end
end
