require_relative "../test_helper"

# End-to-end pipeline tests (spec §4): real `simplecov run` executions in a
# sandbox project. The sandbox reuses this repo's devenv bundle via
# BUNDLE_PATH, so no network is touched. These are the only tests that
# shell out to a test suite.
class PipelineIntegrationTest < Minitest::Test
  include Crap4Ruby::SandboxHelper

  # The active environment's bundle path first: the interactive devenv
  # shell and `devenv test` export BUNDLE_PATH but warm DIFFERENT state
  # directories (state/ vs test-state/), so a hardcoded path is cold on
  # every fresh runner. The state path remains a fallback for bare runs.
  BUNDLE_PATH = ENV.fetch("BUNDLE_PATH") { File.expand_path("../../.devenv/state/.bundle", __dir__) }

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

  MESS = <<~RUBY
    class Mess
      def tangle(a, b)
        if a
          if b
            :ab
          else
            :a
          end
        else
          :none
        end
      end
    end
  RUBY

  def test_green_project_passes_then_no_run_accepts_then_rejects_dirty_tree
    with_project do |root|
      out, err, code = run_cli([], root)
      assert_equal 0, code, "normal run failed: #{out}#{err}"
      assert_includes out, "Calc#sign"
      assert_includes out, "100.0"
      assert File.file?(File.join(root, "coverage/coverage.json"))

      out, _err, code = run_cli(["--no-run"], root)
      assert_equal 0, code
      assert_includes out, "Calc#sign"

      File.write(File.join(root, "lib/calc.rb"), CALC + "# drift\n")
      _out, err, code = run_cli(["--no-run"], root)
      assert_equal 3, code
      assert_includes err, "clean working tree"
    end
  end

  def test_uncovered_complex_method_fails_the_gate_with_exit_2
    with_project(extra_lib: { "lib/mess.rb" => MESS }) do |root|
      out, err, code = run_cli([], root)
      assert_equal 2, code
      assert_includes err, "CRAP threshold exceeded: 12.00 > 8.0"
      # Sorted by CRAP descending: the offender leads.
      first_row = out.lines[1]
      assert_includes first_row, "Mess#tangle"
      assert_includes first_row, "12.00"
    end
  end

  # §11.1 (v2 baseline ratchet): with no baseline file, behavior is
  # byte-for-byte identical to v1. These pins freeze that guarantee before
  # any implementation exists — a future ratchet ticket must keep them
  # green untouched. The child suite's own output goes to the process
  # streams, not the injected IO, so the captured bytes are deterministic.
  def test_no_baseline_passing_run_output_is_byte_frozen
    with_project do |root|
      out, err, code = run_cli([], root)
      assert_equal "Method      CC    Cov%      CRAP  Location\n" \
                   "Calc#sign    2   100.0      2.00  lib/calc.rb:2\n", out
      assert_equal "", err
      assert_equal 0, code
    end
  end

  def test_no_baseline_failing_run_output_is_byte_frozen
    with_project(extra_lib: { "lib/mess.rb" => MESS }) do |root|
      out, err, code = run_cli([], root)
      assert_equal "Method        CC    Cov%      CRAP  Location\n" \
                   "Mess#tangle    3     0.0     12.00  lib/mess.rb:2\n" \
                   "Calc#sign      2   100.0      2.00  lib/calc.rb:2\n", out
      assert_equal "CRAP threshold exceeded: 12.00 > 8.0\n", err
      assert_equal 2, code
    end
  end

  def test_failing_suite_stops_scoring_with_exit_4
    failing = CALC_TEST.sub("assert_equal :pos, Calc.new.sign(3)", "flunk")
    with_project(test_body: failing) do |root|
      out, err, code = run_cli([], root)
      assert_equal 4, code
      assert_includes err, "test command failed"
      refute_includes out, "Calc#sign", "must not score after a failed run"
    end
  end

  def test_changed_analyzes_only_the_modified_file
    other = "class Other\n  def noop = nil\nend\n"
    other_test = <<~RUBY
      require "minitest/autorun"
      require_relative "../lib/other"

      class OtherTest < Minitest::Test
        def test_noop = assert_nil(Other.new.noop)
      end
    RUBY
    with_project(extra_lib: { "lib/other.rb" => other, "test/other_test.rb" => other_test }) do |root|
      write_file(root, "lib/other.rb", other + "# touched\n")
      out, _err, code = run_cli(["--changed"], root)
      assert_equal 0, code, "changed run failed: #{out}"
      assert_includes out, "Other#noop"
      refute_includes out, "Calc#sign"
    end
  end

  private

  def run_cli(argv, root)
    stdout = StringIO.new
    stderr = StringIO.new
    code = Crap4Ruby::CLI.run(argv, stdout: stdout, stderr: stderr, cwd: root)
    [stdout.string, stderr.string, code]
  end

  def with_project(extra_lib: {}, test_body: CALC_TEST)
    with_sandbox do |root|
      write_file(root, "Gemfile", <<~RUBY)
        source "https://rubygems.org"
        gem "minitest"
        gem "rake"
        gem "simplecov", ">= 1.0"
      RUBY
      write_file(root, ".bundle/config", "---\nBUNDLE_PATH: \"#{BUNDLE_PATH}\"\n")
      write_file(root, "Rakefile", <<~RUBY)
        require "rake/testtask"
        Rake::TestTask.new(:test) do |t|
          t.libs << "test" << "lib"
          t.test_files = FileList["test/**/*_test.rb"]
        end
        task default: :test
      RUBY
      write_file(root, ".simplecov", <<~RUBY)
        SimpleCov.configure do
          enable_coverage :branch
          enable_coverage :method
          cover "lib/**/*.rb"
        end
      RUBY
      write_file(root, ".gitignore", "coverage/\n.bundle/\nGemfile.lock\n")
      write_file(root, "lib/calc.rb", CALC)
      write_file(root, "test/calc_test.rb", test_body)
      extra_lib.each { |rel, content| write_file(root, rel, content) }

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
end
