require_relative "../test_helper"
require "rubygems/package"
require "bundler"

# Packaging regression net (spec §2's compatibility claim plus the files
# list, the one packaging property that silently rots): builds the gem in
# a tmpdir, pins the exact packaged file list, installs into a scratch
# GEM_HOME, and runs the installed exe.
class PackagingIntegrationTest < Minitest::Test
  include Crap4Ruby::SandboxHelper

  ROOT = File.expand_path("../..", __dir__)

  def test_gem_contents_metadata_and_installed_exe
    Dir.mktmpdir("crap4ruby-pkg") do |dir|
      # gem build validates spec.files against the working directory, so
      # the tracked tree is copied out and built there — never in the repo.
      copy_tracked_tree(dir)
      git(dir, "init", "-q")
      git(dir, "add", "-A")
      git(dir, "commit", "-qm", "packaging probe")
      gem_path = File.join(dir, "crap4ruby.gem")
      _out, err, status = Open3.capture3("gem", "build", "crap4ruby.gemspec",
                                         "--output", gem_path, chdir: dir)
      assert status.success?, "gem build failed: #{err}"

      package = Gem::Package.new(gem_path)
      expected = Dir.glob("lib/**/*.rb", base: ROOT).sort +
                 %w[CHANGELOG.md README.md exe/crap4ruby spec.md]
      assert_equal expected.sort, package.contents.sort, "packaged file list drifted"

      spec = package.spec
      assert_equal ["crap4ruby"], spec.executables
      assert_equal "exe", spec.bindir
      assert spec.required_ruby_version.satisfied_by?(Gem::Version.new("3.3.0")),
             "must support the CRuby 3.3 floor (spec §2)"
      refute spec.required_ruby_version.satisfied_by?(Gem::Version.new("3.2.9")),
             "must exclude CRuby 3.2"

      assert_installed_exe_runs(dir, gem_path)
    end
  end

  private

  def copy_tracked_tree(dir)
    IO.popen(%w[git ls-files -z], chdir: ROOT, &:read).split("\x0").each do |rel|
      dest = File.join(dir, rel)
      FileUtils.mkdir_p(File.dirname(dest))
      FileUtils.cp(File.join(ROOT, rel), dest)
    end
  end

  # A clean GEM_HOME cannot satisfy `prism ~> 1.9` offline (the default
  # prism is older), so the install skips dependency resolution and the
  # run resolves prism/json from the devenv bundle via GEM_PATH.
  def assert_installed_exe_runs(dir, gem_path)
    home = File.join(dir, "gem-home")
    bundle_gems = File.join(ENV.fetch("BUNDLE_PATH"), "ruby", Gem.ruby_api_version)
    Bundler.with_unbundled_env do
      _out, err, status = Open3.capture3(
        { "GEM_HOME" => home, "GEM_PATH" => home },
        "gem", "install", "--local", "--no-document", "--ignore-dependencies",
        "--install-dir", home, gem_path, chdir: dir
      )
      assert status.success?, "gem install failed: #{err}"

      out, err, status = Open3.capture3(
        { "GEM_HOME" => home, "GEM_PATH" => "#{home}#{File::PATH_SEPARATOR}#{bundle_gems}" },
        File.join(home, "bin", "crap4ruby"), "--help", chdir: dir
      )
      assert status.success?, "installed exe failed: #{err}"
      assert_includes out, "Usage: crap4ruby"
    end
  end
end
