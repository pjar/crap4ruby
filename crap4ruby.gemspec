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

  spec.files = Dir["lib/**/*.rb", "exe/*", "spec.md", "README.md"]
  spec.bindir = "exe"
  spec.executables = ["crap4ruby"]

  spec.add_dependency "json", ">= 2.7"
  spec.add_dependency "prism", "~> 1.9"
end
