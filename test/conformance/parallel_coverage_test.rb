require_relative "../test_helper"

# §4.3 parallel-coverage mismatch warning and §11.4 --update-baseline
# refusal (CRA-49). Warning cases execute a real sandbox suite under
# `simplecov run` through a bin/rails shim that forwards to rake — the
# detection sees `bin/rails test`, the suite is ordinary minitest.
# Refusal cases run against bare sandboxes with a sentinel coverage
# artifact, pinning that they abort before cleanup, before any clean-tree
# check, and before any test execution. Expected stderr lines are
# literals, never read from the implementation — no shared oracle.
class ParallelCoverageConformanceTest < Minitest::Test
  include Crap4Ruby::SandboxHelper

  BUNDLE_PATH = ENV.fetch("BUNDLE_PATH") { File.expand_path("../../.devenv/state/.bundle", __dir__) }
  BASELINE = "crap4ruby-baseline.json".freeze

  WARNING = "warning: Rails test configuration declares `parallelize`, but " \
            ".simplecov does not declare `merge_subprocesses true`; " \
            "worker coverage may be missing\n".freeze
  REFUSAL = "--update-baseline refused: Rails test configuration declares " \
            "`parallelize`, but .simplecov does not declare " \
            "`merge_subprocesses true`; worker coverage may be missing\n".freeze

  GEMFILE = <<~RUBY
    source "https://rubygems.org"
    gem "minitest"
    gem "rake"
    gem "simplecov", ">= 1.0"
  RUBY

  RAKEFILE = <<~RUBY
    require "rake/testtask"
    Rake::TestTask.new(:test) do |t|
      t.libs << "test" << "lib"
      t.test_files = FileList["test/**/*_test.rb"]
    end
    task default: :test
  RUBY

  # Forwards `bin/rails test` to the sandbox's rake suite: §4.3 detection
  # sees a Rails layout while the child remains plain minitest.
  RAILS_SHIM = "#!/bin/sh\nexec bundle exec rake \"$@\"\n".freeze

  SIMPLECOV_BARE = <<~RUBY
    SimpleCov.configure do
      enable_coverage :branch
      enable_coverage :method
      cover "lib/**/*.rb"
    end
  RUBY

  SIMPLECOV_MERGED = SIMPLECOV_BARE.sub("end\n", "  merge_subprocesses true\nend\n")

  CALC = <<~RUBY
    class Calc
      def sign(x)
        if x > 0
          :pos
        else
          :neg
        end
      end
    end
  RUBY

  CALC_TEST = <<~RUBY
    require "minitest/autorun"
    require_relative "../lib/calc"

    class CalcTest < Minitest::Test
      def test_both_branches
        assert_equal :pos, Calc.new.sign(3)
        assert_equal :neg, Calc.new.sign(-1)
      end
    end
  RUBY

  # Matched by test/**/*.rb and parsed, but never loaded: the Rakefile
  # only loads *_test.rb, and the predicate reads *declares*.
  PARALLEL_HELPER = <<~RUBY
    class ParallelStandIn
      def self.declare = parallelize(workers: 2)
    end
  RUBY

  EXPECTED_EMPTY = <<~JSON
    {
      "schema_version": "1.0",
      "metric_version": 1,
      "rows": []
    }
  JSON

  # --- §4.3 warning (full pipeline) ---------------------------------------

  def test_warning_fires_and_stays_nonfatal_across_modes
    with_rails_project do |root|
      out, err, code = run_cli([], root)
      assert_equal 0, code, "normal run failed: #{out}#{err}"
      assert_includes out, "Calc#sign"
      assert_equal WARNING, err, "one warning line, nothing else, exit unchanged"

      out, err, code = run_cli(["--no-run"], root)
      assert_equal 0, code
      assert_includes out, "Calc#sign"
      assert_equal WARNING, err, "--no-run evaluates the predicate statically"

      write_file(root, "lib/extra.rb", "# dirt\n")
      _out, err, code = run_cli(["--no-run"], root)
      assert_equal 3, code
      assert_includes err, "clean working tree"
      refute_includes err, "warning:", "no warning on a run that dies before the clean-tree check passes"
      File.delete(File.join(root, "lib/extra.rb"))

      _out, err, code = run_cli(["--test-command", "bundle exec rake test"], root)
      assert_equal 0, code
      assert_equal "", err, "--test-command asserts the command's coverage behavior"

      write_file(root, ".simplecov", SIMPLECOV_MERGED)
      _out, err, code = run_cli([], root)
      assert_equal 0, code
      assert_equal "", err, "the canonical directive is positive proof"
    end
  end

  # --- §11.4 refusal (before cleanup, tree check, execution) --------------

  def test_update_baseline_refuses_before_cleanup
    with_bare_rails_project do |root|
      untouched = seed_baseline(root)
      out, err, code = run_cli(["--update-baseline"], root)
      assert_equal 3, code
      assert_equal REFUSAL, err
      assert_equal "", out, "no report — nothing ran"
      assert_equal untouched, read_baseline(root), "the baseline survives byte-for-byte"
      assert_equal "SENTINEL", read_sentinel(root), "refused before cleanup — the artifact survives"
    end
  end

  def test_refusal_covers_initial_creation
    with_bare_rails_project do |root|
      _out, err, code = run_cli(["--update-baseline"], root)
      assert_equal 3, code
      assert_equal REFUSAL, err
      refute File.exist?(File.join(root, BASELINE)), "no baseline is created from suspect coverage"
      assert_equal "SENTINEL", read_sentinel(root)
    end
  end

  def test_refusal_composes_with_no_run
    with_bare_rails_project do |root|
      untouched = seed_baseline(root)
      _out, err, code = run_cli(["--update-baseline", "--no-run"], root)
      assert_equal 3, code
      assert_equal REFUSAL, err, "refused before §4.2's checks — this sandbox is not even a git repository"
      assert_equal untouched, read_baseline(root)
    end
  end

  def test_test_command_suppresses_the_refusal
    with_bare_rails_project do |root|
      _out, err, code = run_cli(["--update-baseline", "--test-command", "true"], root)
      assert_equal 1, code, "past the refusal; the next check is the simplecov lock requirement"
      assert_includes err, "simplecov >= 1.0"
      refute_includes err, "refused"
    end
  end

  def test_canonical_simplecov_releases_the_refusal
    with_bare_rails_project do |root|
      write_file(root, ".simplecov", SIMPLECOV_MERGED)
      _out, err, code = run_cli(["--update-baseline"], root)
      assert_equal 1, code, "past the refusal; the next check is the simplecov lock requirement"
      assert_includes err, "simplecov >= 1.0"
      refute_includes err, "refused"
    end
  end

  def test_empty_selection_update_is_unaffected
    with_bare_rails_project(lib: false) do |root|
      out, err, code = run_cli(["--update-baseline"], root)
      assert_equal "nothing to analyze\n", out
      assert_equal "", err, "no coverage is consumed — the predicate's selection conjunct fails"
      assert_equal 0, code
      assert_equal EXPECTED_EMPTY, read_baseline(root)
    end
  end

  private

  def run_cli(argv, root)
    stdout = StringIO.new
    stderr = StringIO.new
    code = Crap4Ruby::CLI.run(argv, stdout: stdout, stderr: stderr, cwd: root)
    [stdout.string, stderr.string, code]
  end

  def seed_baseline(root)
    seed = JSON.generate({ "schema_version" => "1.0", "metric_version" => 1, "rows" => [] })
    write_file(root, BASELINE, seed)
    seed
  end

  def read_baseline(root)
    File.read(File.join(root, BASELINE), encoding: Encoding::UTF_8)
  end

  def read_sentinel(root)
    File.read(File.join(root, "coverage/coverage.json"), encoding: Encoding::UTF_8)
  end

  def with_rails_project
    with_sandbox do |root|
      write_file(root, "Gemfile", GEMFILE)
      write_file(root, ".bundle/config", "---\nBUNDLE_PATH: \"#{BUNDLE_PATH}\"\n")
      write_file(root, "Rakefile", RAKEFILE)
      write_file(root, "bin/rails", RAILS_SHIM)
      File.chmod(0o755, File.join(root, "bin/rails"))
      write_file(root, ".simplecov", SIMPLECOV_BARE)
      write_file(root, ".gitignore", "coverage/\n.bundle/\nGemfile.lock\n")
      write_file(root, "lib/calc.rb", CALC)
      write_file(root, "test/calc_test.rb", CALC_TEST)
      write_file(root, "test/parallel_helper.rb", PARALLEL_HELPER)

      Bundler.with_unbundled_env do
        _out, err, status = Open3.capture3("bundle", "install", "--local", "--quiet", chdir: root)
        raise "sandbox bundle install failed: #{err}" unless status.success?
      end

      git(root, "init", "-q")
      git(root, "add", "-A")
      git(root, "commit", "-qm", "init")
      yield root
    end
  end

  def with_bare_rails_project(lib: true)
    with_sandbox do |root|
      write_file(root, "Gemfile", GEMFILE)
      write_file(root, "bin/rails", RAILS_SHIM)
      File.chmod(0o755, File.join(root, "bin/rails"))
      write_file(root, "test/parallel_helper.rb", PARALLEL_HELPER)
      write_file(root, "lib/mess.rb", "class Mess\nend\n") if lib
      write_file(root, "coverage/coverage.json", "SENTINEL")
      yield root
    end
  end
end
