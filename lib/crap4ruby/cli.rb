module Crap4Ruby
  # Option parsing and pipeline orchestration (spec §3, §4). Every failure
  # path raises Failure; the only Kernel#exit lives in exe/crap4ruby.
  class CLI
    USAGE = <<~TEXT
      Usage: crap4ruby [options] [<path>...]

        crap4ruby                       analyze all .rb files under app/ and lib/
        crap4ruby <path>...             analyze explicit files; directories mean all .rb under them
        --changed                       analyze only changed .rb files (git)
        --no-run                        do not run tests; consume the existing coverage report
        --test-command "<cmd>"          run <cmd> under `simplecov run` instead of the detected command
        --coverage-file <path>          coverage report location (default: <project root>/coverage/coverage.json)
        --update-baseline               full run, then rewrite crap4ruby-baseline.json (shrink-only)
        --help                          print this help
        --version                       print the version

      A crap4ruby-baseline.json in the project root engages the ratchet: baselined
      offenders are grandfathered, new or worsened ones fail, stale rows demand
      --update-baseline.

      Exit codes: 0 ok · 1 usage error · 2 CRAP threshold exceeded · 3 coverage unavailable/invalid · 4 tests failed
    TEXT

    SHORT_CIRCUITS = {
      "--help" => :help,
      "--version" => :version
    }.freeze

    SWITCHES = {
      "--changed" => :@changed,
      "--no-run" => :@no_run,
      "--update-baseline" => :@update_baseline
    }.freeze

    VALUE_OPTIONS = {
      "--test-command" => :@test_command,
      "--coverage-file" => :@coverage_file
    }.freeze

    private_constant :SHORT_CIRCUITS, :SWITCHES, :VALUE_OPTIONS

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
      @update_baseline = false
      @short_circuit = nil
    end

    def run
      parse!
      return short_circuit_result if @short_circuit

      project = Project.locate(@cwd)
      files = project.select_files(@paths, changed: @changed, cwd: @cwd)
      baseline_path = File.join(project.root, Baseline::FILENAME)
      baseline = Baseline.read(baseline_path)
      coverage_path = resolve_coverage_path(project)
      guard_baseline_alias(coverage_path, baseline_path, baseline)
      arguments = sample_arguments(project, baseline)

      return empty_selection(project, baseline, baseline_path, arguments) if files.empty?

      mismatch = parallel_coverage_mismatch?(project)
      refuse_parallel_baseline_update(mismatch)
      coverage = acquire_coverage(project, coverage_path, files, mismatch)
      report, entries = analyze_and_report(files, coverage, project, baseline)
      conclude(project, baseline, baseline_path, entries, files, arguments, report)
    end

    private

    def short_circuit_result
      case @short_circuit
      when :help
        @stdout.puts USAGE
      when :version
        @stdout.puts "crap4ruby #{VERSION}"
      end
      0
    end

    def parallel_coverage_mismatch?(project)
      @test_command.nil? && ParallelCoverage.mismatch?(project.root)
    end

    def refuse_parallel_baseline_update(mismatch)
      raise Failure.new(ParallelCoverage::REFUSAL, 3) if mismatch && @update_baseline
    end

    def acquire_coverage(project, coverage_path, files, mismatch)
      if @no_run
        raise Failure.new("--no-run requires a clean working tree", 3) unless project.tree_clean?
        @stderr.puts ParallelCoverage::WARNING if mismatch
      else
        runner = TestRunner.new(project.root)
        runner.clean(coverage_path)
        runner.run(@test_command, warn_to: mismatch ? @stderr : nil)
      end

      coverage = CoverageReport.load(coverage_path, analyzed_files: files)
      verify_trusted_artifact(project, coverage, files) if @no_run
      coverage
    end

    def analyze_and_report(files, coverage, project, baseline)
      entries, excluded_count = analyze(files, coverage, project)
      check_unique_keys(entries) if baseline
      report = Report.new(entries, excluded_count: excluded_count)
      report.render(@stdout)
      [report, entries]
    end

    def conclude(project, baseline, baseline_path, entries, files, arguments, report)
      return update_baseline(baseline, baseline_path, failing_rows(entries)) if @update_baseline
      return ratchet_gate(project, baseline, failing_rows(entries), files, arguments) if baseline

      gate(report)
    end

    def parse!
      args = @argv.dup
      until args.empty?
        parse_argument(args.shift, args)
      end
      validate_option_composition
    end

    def parse_argument(arg, args)
      return parse_short_circuit(arg) if SHORT_CIRCUITS.key?(arg)
      return enable_switch(arg) if SWITCHES.key?(arg)

      parse_value_option_or_path(arg, args)
    end

    def parse_short_circuit(arg)
      @short_circuit ||= SHORT_CIRCUITS.fetch(arg)
    end

    def enable_switch(arg)
      instance_variable_set(SWITCHES.fetch(arg), true)
    end

    def parse_value_option_or_path(arg, args)
      field = VALUE_OPTIONS[arg]
      return instance_variable_set(field, option_value(arg, args)) if field

      option, value = arg.split("=", 2)
      field = VALUE_OPTIONS[option]
      return instance_variable_set(field, value) if field && value && !value.empty?

      parse_path_or_unknown_option(arg)
    end

    def parse_path_or_unknown_option(arg)
      raise Failure.new("unknown option: #{arg}\n\n#{USAGE}", 1) if arg.start_with?("-")

      @paths << arg
    end

    def validate_option_composition
      raise Failure.new("--test-command cannot be combined with --no-run", 1) if @test_command && @no_run
      # §11.4: a partial analysis must never rewrite the baseline.
      return unless @update_baseline && (@changed || @paths.any?)

      raise Failure.new("--update-baseline cannot be combined with --changed or explicit paths", 1)
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
        # Explicit UTF-8: without a locale (minimal CI/servers) the default
        # external encoding is US-ASCII and multibyte sources would raise.
        on_disk = CoverageReport.logical_lines(File.read(file, encoding: Encoding::UTF_8))
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
        methods = MethodExtractor.extract(File.read(file, encoding: Encoding::UTF_8), relative)
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

    def resolve_coverage_path(project)
      return File.expand_path(@coverage_file, @cwd) if @coverage_file
      File.join(project.root, "coverage", "coverage.json")
    end

    # §11.1: §4.1's cleanup step must never be able to delete the baseline,
    # so the aliasing check precedes it — and fires under --update-baseline
    # even before any baseline exists. Resolution is lexical expansion
    # *plus* filesystem identity for a path that already names a file: a
    # case-insensitive spelling or a route through a symlinked directory
    # is the same file to cleanup, and File.identical? is false for a path
    # that does not exist yet, which the lexical comparison still covers.
    def guard_baseline_alias(coverage_path, baseline_path, baseline)
      return unless baseline || @update_baseline
      return unless coverage_path == baseline_path || File.identical?(coverage_path, baseline_path)
      raise Failure.new("the coverage report path resolves to the baseline file " \
                        "#{baseline_path}; refusing — cleanup would delete it", 1)
    end

    # §11.3's scope inputs, sampled with the file selection so the scope
    # describes the tree the selection was taken from. Only a run that can
    # consult the baseline needs them, so the plain v1 path stats nothing.
    def sample_arguments(project, baseline)
      return Project::NO_ARGUMENTS unless (baseline || @update_baseline) && @paths.any?
      project.argument_paths(@paths, cwd: @cwd)
    end

    # §11.4: with a baseline engaged or being written, an empty selection
    # still means something — but never a cleanup, a test run, or a
    # coverage read (and so, per §4.2, none of --no-run's trust-bounding
    # checks either). Without one, §3's early return is byte-for-byte v1.
    def empty_selection(project, baseline, baseline_path, arguments)
      @stdout.puts "nothing to analyze"
      return 0 unless baseline || @update_baseline
      return update_baseline(baseline, baseline_path, []) if @update_baseline
      ratchet_gate(project, baseline, [], [], arguments)
    end

    # §11.3: only rows above the threshold consult the baseline. The stored
    # components are exactly these, so the same value object carries a row
    # into the classifier and into the file.
    def failing_rows(entries)
      entries.map { |entry| Baseline::Row.from_entry(entry) }.select { |row| row.crap > THRESHOLD }
    end

    def ratchet_gate(project, baseline, failing, files, arguments)
      ratchet = Ratchet.new(baseline: baseline, current_rows: failing,
                            scope: freshness_scope(project, files, arguments))
      ratchet.diagnostics.each { |line| @stderr.puts line }
      ratchet.exit_code
    end

    # §11.3's three freshness scopes, mode-split. A full run checks every
    # row; an explicit-paths run adds each directory argument's subtree
    # lexically — or every row, when an argument contains the project root;
    # a --changed run adds git's deletions and rename origins and nothing
    # else — never a directory sweep, or an unchanged file's grandfathered
    # rows would go falsely stale.
    def freshness_scope(project, files, arguments)
      return Ratchet::Scope.full if !@changed && (@paths.empty? || arguments[:root])
      analyzed = files.map { |file| project.relative(file) }
      return Ratchet::Scope.new(paths: analyzed, directories: arguments[:directories]) unless @changed
      Ratchet::Scope.new(paths: analyzed + removals_in_scope(project, arguments))
    end

    def removals_in_scope(project, arguments)
      removals = project.changed_removals
      # Composed with explicit paths, the removals are restricted to them —
      # same lexical containment, no filesystem access (the paths are gone).
      # An argument containing the project root restricts nothing.
      return removals if @paths.empty? || arguments[:root]
      restriction = Ratchet::Scope.new(paths: arguments[:files], directories: arguments[:directories])
      removals.select { |path| restriction.include?(path) }
    end

    # §11.5: under an engaged baseline a duplicate full key among
    # reportable rows is an analysis failure — the baseline cannot address
    # either row unambiguously.
    def check_unique_keys(entries)
      seen = {}
      entries.each do |entry|
        key = [entry.path, entry.row.method.identity, entry.row.method.definition_line]
        if seen.key?(key)
          raise Failure.new("duplicate row key under an engaged baseline: " \
                            "#{key[1]} (#{key[0]}:#{key[2]})", 3)
        end
        seen[key] = true
      end
    end

    # §11.4: the write is the requested outcome, so a successful update
    # exits 0 even with failing rows — the gate question belongs to the
    # next ordinary run.
    def update_baseline(baseline, baseline_path, rows)
      refuse_growth(baseline, rows) if baseline
      Baseline.write(baseline_path, rows)
      0
    end

    # Shrink-only (§11.4): subset by key, and no retained key may score
    # worse than it does in the file. New or worsened debt is fixed, never
    # baselined; a deliberate re-adoption is a reviewed delete-and-recreate.
    def refuse_growth(baseline, rows)
      violations = rows.filter_map do |row|
        stored = baseline.row_for(row.key)
        if stored.nil?
          "  new: #{row.identity} (#{row.location}) CRAP #{Report.decimal(row.crap, 2)}"
        elsif row.crap > stored.crap
          "  worsened: #{row.identity} (#{row.location}) CRAP #{Report.decimal(row.crap, 2)} > " \
            "#{Report.decimal(stored.crap, 2)} baselined"
        end
      end
      return if violations.empty?
      raise Failure.new("--update-baseline refused: the baseline may only shrink " \
                        "(#{violations.size} new or worsened row(s)); fix them or " \
                        "regenerate the baseline deliberately\n#{violations.join("\n")}", 2)
    end
  end
end
