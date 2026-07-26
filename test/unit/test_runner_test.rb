require_relative "../test_helper"

class TestRunnerTest < Minitest::Test
  include Crap4Ruby::SandboxHelper

  LOCKFILE = <<~LOCK
    GEM
      remote: https://rubygems.org/
      specs:
        rake (13.0.0)
        rspec-core (3.13.0)

    DEPENDENCIES
      rake
      rspec-core
  LOCK

  def test_detects_rspec_when_only_spec_exists_and_lockfile_lists_rspec_core
    with_sandbox do |root|
      FileUtils.mkdir_p(File.join(root, "spec"))
      write_file(root, "Gemfile.lock", LOCKFILE)
      assert_equal %w[bundle exec rspec], runner(root).detect_command
    end
  end

  def test_refuses_rspec_without_lockfile_entry
    with_sandbox do |root|
      FileUtils.mkdir_p(File.join(root, "spec"))
      write_file(root, "Gemfile.lock", "GEM\n  specs:\n    rake (13.0.0)\n")
      assert_failure(1, "rspec-core") { runner(root).detect_command }
    end
  end

  def test_refuses_when_both_spec_and_test_exist
    with_sandbox do |root|
      FileUtils.mkdir_p(File.join(root, "spec"))
      FileUtils.mkdir_p(File.join(root, "test"))
      assert_failure(1, "both") { runner(root).detect_command }
    end
  end

  def test_detects_bin_rails_test_when_executable
    with_sandbox do |root|
      FileUtils.mkdir_p(File.join(root, "test"))
      rails = write_file(root, "bin/rails", "#!/bin/sh\n")
      File.chmod(0o755, rails)
      assert_equal ["bin/rails", "test"], runner(root).detect_command
    end
  end

  def test_refuses_non_executable_bin_rails
    with_sandbox do |root|
      FileUtils.mkdir_p(File.join(root, "test"))
      write_file(root, "bin/rails", "#!/bin/sh\n")
      File.chmod(0o644, File.join(root, "bin/rails"))
      assert_failure(1, "not executable") { runner(root).detect_command }
    end
  end

  def test_detects_rake_test_with_rakefile_and_lockfile_entry
    with_sandbox do |root|
      FileUtils.mkdir_p(File.join(root, "test"))
      write_file(root, "Rakefile", "")
      write_file(root, "Gemfile.lock", LOCKFILE)
      assert_equal %w[bundle exec rake test], runner(root).detect_command
    end
  end

  def test_refuses_rake_without_lockfile_entry
    with_sandbox do |root|
      FileUtils.mkdir_p(File.join(root, "test"))
      write_file(root, "Rakefile", "")
      assert_failure(1, "rake") { runner(root).detect_command }
    end
  end

  def test_refuses_when_neither_layout_matches
    with_sandbox do |root|
      assert_failure(1, "--test-command") { runner(root).detect_command }
    end
  end

  def test_clean_deletes_report_and_resultset_but_never_directories
    with_sandbox do |root|
      report = write_file(root, "coverage/coverage.json", "{}")
      resultset = write_file(root, "coverage/.resultset.json", "{}")
      FileUtils.mkdir_p(File.join(root, "coverage/subdir"))
      runner(root).clean(report)
      refute File.exist?(report)
      refute File.exist?(resultset)
      assert Dir.exist?(File.join(root, "coverage/subdir"))
    end
  end

  def test_clean_is_quiet_when_nothing_exists
    with_sandbox do |root|
      runner(root).clean(File.join(root, "coverage", "coverage.json"))
    end
  end

  def test_run_refuses_without_simplecov_1_in_lockfile
    with_sandbox do |root|
      write_file(root, "Gemfile.lock", "GEM\n  specs:\n    simplecov (0.22.0)\n")
      assert_failure(1, "simplecov >= 1.0") { runner(root).run(nil) }
    end
  end

  def test_run_refuses_without_any_lockfile
    with_sandbox do |root|
      assert_failure(1, "not in Gemfile.lock") { runner(root).run("true") }
    end
  end

  def test_simplecov_preflight_passes_at_1_x
    with_sandbox do |root|
      write_file(root, "Gemfile.lock", "GEM\n  specs:\n    simplecov (1.0.2)\n")
      runner(root).send(:verify_simplecov!)
    end
  end

  private

  def runner(root)
    Crap4Ruby::TestRunner.new(root)
  end
end
