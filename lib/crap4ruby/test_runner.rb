module Crap4Ruby
  # Cleanup, test-command detection, and execution (spec §4.1, §4.3).
  class TestRunner
    def initialize(root)
      @root = root
    end

    # Deletes only the report file and a sibling .resultset.json — never
    # directories. A deletion failure aborts (never proceed against a
    # stale artifact).
    def clean(coverage_path)
      [coverage_path, File.join(File.dirname(coverage_path), ".resultset.json")].each do |file|
        next unless File.file?(file)
        begin
          File.delete(file)
        rescue SystemCallError => error
          raise Failure.new("cannot delete stale coverage artifact #{file}: #{error.message}", 3)
        end
      end
    end

    # §4.3's mismatch warning prints once the lockfile and preflight checks
    # have succeeded and before the child starts, so a run that dies in
    # preflight never prints it. The CLI owns the predicate and the stream
    # and passes the sink only when the predicate holds.
    def run(custom_command, warn_to: nil)
      verify_simplecov!
      inner = custom_command ? ["sh", "-c", custom_command] : detect_command
      warn_to&.puts(ParallelCoverage::WARNING)
      argv = ["bundle", "exec", "simplecov", "run", "--", *inner]
      status = execute(argv)
      return if status&.success?
      raise Failure.new(describe_failure(argv, status), 4)
    end

    # Deterministic detection with preflight — no fallbacks (spec §4.3).
    def detect_command
      spec_dir = Dir.exist?(File.join(@root, "spec"))
      test_dir = Dir.exist?(File.join(@root, "test"))

      if spec_dir && test_dir
        refuse "both spec/ and test/ exist"
      elsif spec_dir
        refuse "Gemfile.lock does not list rspec-core" unless lockfile_lists?("rspec-core")
        %w[bundle exec rspec]
      elsif test_dir
        bin_rails = File.join(@root, "bin", "rails")
        if File.exist?(bin_rails)
          refuse "bin/rails is not executable" unless File.executable?(bin_rails)
          ["bin/rails", "test"]
        elsif File.file?(File.join(@root, "Rakefile"))
          refuse "Gemfile.lock does not list rake" unless lockfile_lists?("rake")
          %w[bundle exec rake test]
        else
          refuse "test/ exists but neither bin/rails nor Rakefile found"
        end
      else
        refuse "neither spec/ nor test/ exists"
      end
    end

    private

    # The `simplecov run` wrapper needs SimpleCov ≥ 1.0 in the analyzed
    # project (spec §2, §4.3) — applies to detected and custom commands
    # alike; without it the wrapper fails before the tests even start.
    def verify_simplecov!
      lockfile = File.join(@root, "Gemfile.lock")
      version = File.file?(lockfile) &&
                File.foreach(lockfile).filter_map { |line| line[/\A\s{4}simplecov \((\d+)[^)]*\)/, 1] }.first
      return if version && Integer(version) >= 1
      raise Failure.new("the analyzed project must lock simplecov >= 1.0 " \
                        "(#{version ? "found #{version}.x" : "not in Gemfile.lock"})", 1)
    end

    def refuse(reason)
      raise Failure.new("cannot detect the test command (#{reason}); pass --test-command", 1)
    end

    def lockfile_lists?(gem_name)
      lockfile = File.join(@root, "Gemfile.lock")
      return false unless File.file?(lockfile)
      File.foreach(lockfile).any? { |line| line.match?(/\A\s{4}#{Regexp.escape(gem_name)} \(/) }
    end

    # The analyzed project's bundle, not crap4ruby's, must resolve
    # `bundle exec` — hence the unbundled environment.
    def execute(argv)
      with_clean_env do
        system(*argv, chdir: @root)
        $?
      end
    end

    def with_clean_env(&block)
      defined?(Bundler) ? Bundler.with_unbundled_env(&block) : yield
    end

    def describe_failure(argv, status)
      command = argv.join(" ")
      if status.nil?
        "test command could not be executed: #{command}"
      elsif status.signaled?
        "test command killed by signal #{status.termsig}: #{command}"
      else
        "test command failed with exit status #{status.exitstatus}: #{command}"
      end
    end
  end
end
