require_relative "../test_helper"

class CLITest < Minitest::Test
  include Crap4Ruby::SandboxHelper

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

  private

  def run_cli(argv, cwd: Dir.pwd, stdout: StringIO.new, stderr: StringIO.new)
    Crap4Ruby::CLI.run(argv, stdout: stdout, stderr: stderr, cwd: cwd)
  end
end
