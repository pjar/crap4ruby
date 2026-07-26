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

## The metric, honestly

CRAP — Change Risk Anti-Patterns — was introduced by Alberto Savoia and Bob
Evans in 2007 ([the original Artima
post](https://www.artima.com/weblogs/viewpost.jsp?thread=215899)) with a
threshold of **30** and an explicit allowance of roughly 5% crappy methods
per project. crap4ruby does not inherit that calibration: it inherits the
far stricter hard gate of
[unclebob/crap4java](https://github.com/unclebob/crap4java) — **8.0, no
allowance, not configurable**.

Because `CRAP(m) ≥ comp(m)` always, the single 8.0 number is two rules in
one: a fully covered method passes only if CC ≤ 8, a fully uncovered method
passes only if CC ≤ 2 (an uncovered CC-2 method scores 6.0; CC 3 scores
12.0), and **any method with CC ≥ 9 fails at any coverage** — no test can
save it, the complexity itself must come down. In between, the gate is a
coverage floor that scales with complexity:

| CC | Minimum coverage to pass (whole %) |
|---|---|
| 1–2 | 0% (always passes) |
| 3 | 18% |
| 4 | 38% |
| 5 | 51% |
| 6 | 62% |
| 7 | 73% |
| 8 | 100% |
| ≥ 9 | impossible — CC itself must come down |

**CC here reads higher than RuboCop's.** Spec §6 deliberately deviates from
RuboCop `Metrics/CyclomaticComplexity` in two ways: every safe-navigation
call counts, with no discount for repeated `&.` chains — each `&.` is a real
branch on nil; and every block counts, with no whitelist of "iterating"
methods — blocks are Ruby's loops, and a method whitelist is nondeterministic
across DSLs. A method RuboCop scores at 7 can score well above 8 here, so
the 8.0 gate is stricter than a naive RuboCop-max-7 comparison suggests.

Known blind spots (spec §7.5, deliberate and documented): Ruby records no
branch-arm coverage for `&&`/`||`/`and`/`or`, `rescue` clauses, or iterator
blocks, so a method can reach 100% coverage with an untested short-circuit
or rescue path; `# :nocov:` / `# simplecov:disable` markers remove methods
from the gate entirely — the report footer counts every excluded method so
a new marker is visible in output and diff review; and only method bodies
are scored — class-body and top-level code is out of scope. Mutation
testing is the complement that covers all three.

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
