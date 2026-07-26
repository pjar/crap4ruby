# crap4ruby

A small, deterministic CLI quality gate in the spirit of
[crap4java](https://github.com/unclebob/crap4java): it runs your test suite
under [SimpleCov](https://github.com/simplecov-ruby/simplecov), computes the
**CRAP score** of every method, prints a report, and fails when any method
crosses the threshold.

```
CRAP(m) = comp(m)² × (1 − cov(m))³ + comp(m)
```

- `comp(m)` — cyclomatic complexity (Prism-based, spec §6)
- `cov(m)` — line + branch coverage of the method, with a method-coverage
  fallback for bodiless one-liners (spec §7)
- Threshold: **8.0**. Not configurable — that is the point.

A complex method escapes the gate only by being tested; an untested method
escapes only by being simple.

## Requirements

- CRuby ≥ 3.3 (the analyzed project and crap4ruby itself)
- The analyzed project uses Bundler and locks `simplecov` ≥ 1.0
- Branch and method coverage enabled, e.g. in `.simplecov`:

```ruby
SimpleCov.configure do
  enable_coverage :branch
  enable_coverage :method
  cover "app/**/*.rb", "lib/**/*.rb"
end
```

## Usage

```
crap4ruby                        # analyze all .rb under app/ and lib/
crap4ruby lib/billing            # analyze explicit files/directories
crap4ruby --changed              # only changed .rb files (git)
crap4ruby --no-run               # trust the existing coverage report
crap4ruby --test-command "bin/ci" # custom test command under simplecov run
crap4ruby --coverage-file <path> # non-default report location
```

Exit codes: `0` ok · `1` usage error · `2` CRAP threshold exceeded ·
`3` coverage unavailable or invalid · `4` test command failed.

```
Method                    CC    Cov%      CRAP  Location
Billing::Invoice#total     6    61.9      8.41  app/models/billing/invoice.rb:41
CRAP threshold exceeded: 8.41 > 8.0
```

## The contract

[spec.md](spec.md) plus the conformance corpus under `test/fixtures/` is the
complete, testable specification. Where prose and fixtures disagree, that is
a bug in one of them — file it. Background and rationale live in
[FINDINGS.md](FINDINGS.md); the implementation architecture in
[DESIGN.md](DESIGN.md).

## Development

Everything runs through [devenv](https://devenv.sh):

```
devenv shell -- bundle install
devenv shell -- bundle exec rake test   # conformance + unit + integration
devenv test                             # what CI runs
```
