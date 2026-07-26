require "minitest/autorun"
require "stringio"
require "tmpdir"
require "fileutils"
require "open3"
require "crap4ruby"

module Crap4Ruby
  module FixtureHelper
    FIXTURES = File.expand_path("fixtures", __dir__)

    def fixture_path(*parts)
      File.join(FIXTURES, *parts)
    end
  end

  module LocaleHelper
    # Simulates a bare environment without a locale (minimal CI runners),
    # where the default external encoding is US-ASCII.
    def with_ascii_default_external
      previous = Encoding.default_external
      set_default_external(Encoding::US_ASCII)
      yield
    ensure
      set_default_external(previous)
    end

    private

    def set_default_external(encoding)
      verbose, $VERBOSE = $VERBOSE, nil
      Encoding.default_external = encoding
    ensure
      $VERBOSE = verbose
    end
  end

  module SandboxHelper
    # realpath because Dir.mktmpdir lives under a symlink on macOS and the
    # code under test compares expanded paths.
    def with_sandbox
      Dir.mktmpdir("crap4ruby-test") do |dir|
        yield File.realpath(dir)
      end
    end

    def write_file(root, relative, content = "")
      path = File.join(root, relative)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      path
    end

    def git(dir, *args)
      out, err, status = Open3.capture3(
        "git", "-c", "user.email=test@example.com", "-c", "user.name=test",
        "-c", "commit.gpgsign=false", *args, chdir: dir
      )
      raise "git #{args.join(" ")} failed: #{err}" unless status.success?
      out
    end

    def assert_failure(exit_code, message_part = nil, &block)
      error = assert_raises(Crap4Ruby::Failure, &block)
      assert_equal exit_code, error.exit_code, "exit code for: #{error.message}"
      assert_includes error.message, message_part if message_part
      error
    end
  end
end
