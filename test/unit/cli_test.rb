require_relative "../test_helper"

class CLITest < Minitest::Test
  include Crap4Ruby::SandboxHelper
  include Crap4Ruby::LocaleHelper

  def test_help_prints_usage_and_exits_0
    out = StringIO.new
    assert_equal 0, run_cli(["--help"], stdout: out)
    assert_includes out.string, "Usage: crap4ruby"
  end

  def test_unknown_option_is_a_usage_error
    err = StringIO.new
    assert_equal 1, run_cli(["--bogus"], stderr: err)
    assert_includes err.string, "unknown option: --bogus"
  end

  def test_missing_option_value_is_a_usage_error
    err = StringIO.new
    assert_equal 1, run_cli(["--coverage-file"], stderr: err)
    assert_includes err.string, "missing value"
  end

  def test_test_command_with_no_run_is_a_usage_error
    err = StringIO.new
    assert_equal 1, run_cli(["--no-run", "--test-command", "true"], stderr: err)
    assert_includes err.string, "cannot be combined"
  end

  def test_no_gemfile_is_a_usage_error
    with_sandbox do |root|
      err = StringIO.new
      assert_equal 1, run_cli([], cwd: root, stderr: err)
      assert_includes err.string, "no Gemfile"
    end
  end

  def test_empty_selection_prints_nothing_to_analyze_before_any_run
    with_sandbox do |root|
      write_file(root, "Gemfile")
      stale = write_file(root, "coverage/coverage.json", "{stale")
      out = StringIO.new
      assert_equal 0, run_cli([], cwd: root, stdout: out)
      assert_equal "nothing to analyze\n", out.string
      assert File.exist?(stale), "empty selection must be checked before cleanup"
    end
  end

  def test_no_run_with_dirty_tree_fails_with_exit_3
    with_sandbox do |root|
      write_file(root, "Gemfile")
      write_file(root, "lib/a.rb", "class A\nend\n")
      git(root, "init", "-q")
      git(root, "add", ".")
      git(root, "commit", "-qm", "base")
      write_file(root, "untracked.txt")
      err = StringIO.new
      assert_equal 3, run_cli(["--no-run"], cwd: root, stderr: err)
      assert_includes err.string, "clean working tree"
    end
  end

  def test_no_run_outside_git_repository_fails_with_exit_3
    with_sandbox do |root|
      write_file(root, "Gemfile")
      write_file(root, "lib/a.rb", "class A\nend\n")
      err = StringIO.new
      assert_equal 3, run_cli(["--no-run"], cwd: root, stderr: err)
    end
  end

  FakeCoverage = Struct.new(:meta, :entry) do
    def entry_for(_file) = entry
  end

  def test_no_run_source_verification_handles_multibyte_sources_under_an_ascii_locale
    with_sandbox do |root|
      write_file(root, "Gemfile")
      file = write_file(root, "lib/a.rb", "# Grüße — Kommentar\nclass A\nend\n")
      git(root, "init", "-q")
      git(root, "add", "-A")
      git(root, "commit", "-qm", "init")
      project = Crap4Ruby::Project.locate(root)
      cli = Crap4Ruby::CLI.new([], stdout: StringIO.new, stderr: StringIO.new, cwd: root)
      matching = FakeCoverage.new({ "commit" => project.head_sha },
                                  { "source" => ["# Grüße — Kommentar", "class A", "end"] })
      mismatched = FakeCoverage.new({ "commit" => project.head_sha },
                                    { "source" => ["# anders", "class A", "end"] })
      with_ascii_default_external do
        cli.send(:verify_trusted_artifact, project, matching, [file])
        assert_failure(3, "does not match") do
          cli.send(:verify_trusted_artifact, project, mismatched, [file])
        end
      end
    end
  end

  def test_no_run_with_invalid_utf8_analyzed_file_exits_3
    with_sandbox do |root|
      write_file(root, "Gemfile")
      write_file(root, ".gitignore", "coverage/\n")
      file = File.join(root, "lib/a.rb")
      FileUtils.mkdir_p(File.dirname(file))
      File.binwrite(file, "class A\nend\n\xE9\n")
      git(root, "init", "-q")
      git(root, "add", "-A")
      git(root, "commit", "-qm", "init")
      head = Crap4Ruby::Project.locate(root).head_sha
      report = {
        "meta" => { "schema_version" => "1.0", "timestamp" => "2026-07-27T00:00:00+02:00",
                    "root" => root, "commit" => head, "line_coverage" => true,
                    "branch_coverage" => true, "method_coverage" => true },
        "coverage" => { "lib/a.rb" => { "lines" => [], "branches" => [], "methods" => [] } }
      }
      write_file(root, "coverage/coverage.json", JSON.generate(report))
      err = StringIO.new
      assert_equal 3, run_cli(["--no-run", "lib/a.rb"], cwd: root, stderr: err)
      assert_includes err.string, "not valid UTF-8"
    end
  end

  def test_unparseable_file_failure_names_the_file
    with_sandbox do |root|
      write_file(root, "Gemfile")
      bad = write_file(root, "lib/bad.rb", "def broken(\n")
      project = Crap4Ruby::Project.locate(root)
      cli = Crap4Ruby::CLI.new([], stdout: StringIO.new, stderr: StringIO.new, cwd: root)
      error = assert_raises(Crap4Ruby::Failure) { cli.send(:analyze, [bad], :never_reached, project) }
      assert_equal 3, error.exit_code
      assert_includes error.message, "lib/bad.rb"
    end
  end

  # §8: the gate compares unrounded values. A max exceeding 8 by less than
  # half a Float ulp still fails the gate — a Float threshold cannot see it.
  def test_gate_compares_the_unrounded_rational_max_exactly
    stderr = StringIO.new
    assert_equal 2, gate(Rational(8) + Rational(1, 10**30), stderr: stderr)
    assert_includes stderr.string, "CRAP threshold exceeded: 8.00 > 8.0"
  end

  def test_gate_passes_a_max_of_exactly_eight
    stderr = StringIO.new
    assert_equal 0, gate(Rational(8), stderr: stderr)
    assert_empty stderr.string
  end

  def test_gate_message_shows_the_rounded_max_to_two_decimals
    stderr = StringIO.new
    assert_equal 2, gate(Rational(841, 100), stderr: stderr)
    assert_equal "CRAP threshold exceeded: 8.41 > 8.0\n", stderr.string
  end

  private

  GateRow = Struct.new(:method, :crap, keyword_init: true)

  def gate(max_crap, stderr:)
    method = Crap4Ruby::MethodInfo.new(
      identity: "X#m", scope: "X", bare_name: "m", definition_line: 1,
      span_start: 1, span_end: 1, span_byte_start: 0, span_byte_end: 1,
      declaration_lines: [1], comp: 1, match_mode: :name_and_span
    )
    entry = Crap4Ruby::Report::Entry.new(row: GateRow.new(method: method, crap: max_crap), path: "x.rb")
    report = Crap4Ruby::Report.new([entry], excluded_count: 0)
    cli = Crap4Ruby::CLI.new([], stdout: StringIO.new, stderr: stderr, cwd: Dir.pwd)
    cli.send(:gate, report)
  end

  def run_cli(argv, cwd: Dir.pwd, stdout: StringIO.new, stderr: StringIO.new)
    Crap4Ruby::CLI.run(argv, stdout: stdout, stderr: stderr, cwd: cwd)
  end
end
