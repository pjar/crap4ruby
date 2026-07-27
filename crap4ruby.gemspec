require_relative "lib/crap4ruby/version"

Gem::Specification.new do |spec|
  spec.name = "crap4ruby"
  spec.version = Crap4Ruby::VERSION
  spec.authors = ["Jarek Plonski"]
  spec.summary = "Deterministic CRAP-metric quality gate for Ruby"
  spec.description = "Runs the test suite under SimpleCov, computes the CRAP score " \
                     "(comp² × (1 − cov)³ + comp) of every method, and fails when any " \
                     "score exceeds 8.0. See spec.md for the full contract."

  spec.required_ruby_version = ">= 3.3"
  spec.license = "MIT"
  spec.homepage = "https://github.com/pjar/crap4ruby"
  spec.metadata = {
    "rubygems_mfa_required" => "true",
    "source_code_uri" => "https://github.com/pjar/crap4ruby",
    "changelog_uri" => "https://github.com/pjar/crap4ruby/blob/main/CHANGELOG.md"
  }

  # Git-scoped so an untracked stray file can never ship; the plain globs
  # remain the fallback when git is unavailable at build time or lists
  # nothing (the tree sitting untracked inside an unrelated repository).
  candidates = Dir.glob(["lib/**/*.rb", "exe/*", "spec.md", "README.md", "CHANGELOG.md", "LICENSE"], base: __dir__)
  tracked = begin
    listed = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL, &:read).split("\x0")
    $?.success? && !listed.empty? ? listed : nil
  rescue SystemCallError
    nil
  end
  spec.files = tracked ? candidates & tracked : candidates
  spec.bindir = "exe"
  spec.executables = ["crap4ruby"]

  spec.add_dependency "json", ">= 2.7"
  spec.add_dependency "prism", "~> 1.9"
end
