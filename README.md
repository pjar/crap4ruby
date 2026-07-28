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

- CRuby ≥ 3.3 (the analyzed project and crap4ruby itself); analyzed files
  are parsed as Ruby 4.0 grammar (spec §2) — the runtime floor and the
  syntax ceiling are independent bounds
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
crap4ruby --update-baseline      # rewrite the ratchet baseline (shrink-only)
```

Exit codes: `0` ok · `1` usage error · `2` CRAP threshold exceeded ·
`3` coverage unavailable or invalid · `4` test command failed.

```
Method                       CC    Cov%      CRAP  Location
Billing::Invoice#total        6    59.4      8.41  app/models/billing/invoice.rb:41
Billing::Invoice#finalize!    4   100.0      4.00  app/models/billing/invoice.rb:78
```

When the gate trips, `CRAP threshold exceeded: 8.41 > 8.0` is printed to
**stderr** and the exit status is 2.

## Adopting it on legacy code — the baseline ratchet

A `crap4ruby-baseline.json` committed in the project root engages the
ratchet: the offenders it lists are grandfathered, everything else still
faces the 8.0 gate. No flag turns it on — the committed file *is* the
opt-in, and its diffs are the audit trail.

```
crap4ruby --update-baseline   # full run, then rewrite the file
```

- A **new** offender, or a baselined one that got **worse**, fails: exit 2,
  one `baseline:` line per row on stderr.
- A baselined row that no longer fails — fixed, moved, deleted, renamed —
  is **stale**: exit 3, because the file now lies about the code. Re-run
  with `--update-baseline` in the same change.
- The file only ever **shrinks**. `--update-baseline` refuses (exit 2,
  file untouched) any write that would add or worsen a row; adopting new
  debt deliberately means deleting the baseline and re-creating it, which
  shows up as one reviewable diff.
- Row keys are `(path, identity, line)` — inserting a line above a
  grandfathered method surfaces as new + stale. That brittleness is the
  price of exact keys and a strictly shrinking file.

`--changed` runs cannot establish freshness (they only ever check the
rows they analyzed, plus git's deletions and rename origins), so an
authoritative full run belongs in CI. The full contract is spec.md §11.

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

## Where it sits in 2026

No other maintained Ruby tool combines per-method cyclomatic complexity
with per-method test coverage into a single deterministic pass/fail gate —
that exclusivity claim is scoped to exactly that: per-method CRAP gating.
Every neighboring tool does something different, and several do their
different thing better:

| Tool | Measures | Gates? |
|---|---|---|
| [flog](https://github.com/seattlerb/flog) | per-method ABC-style complexity score (not CC), no coverage term | no gate; low activity (last release Jan 2026) |
| [reek](https://github.com/troessner/reek) | code smells and design heuristics, no coverage | configurable smell failures, not a metric gate |
| [rubycritic](https://github.com/whitesmith/rubycritic) | file-level report card wrapping flog/reek/flay plus SimpleCov (5.0.0, Jan 2026) | score threshold on file grades, not per method |
| [skunk](https://github.com/fastruby/skunk) | file-level SkunkScore (complexity vs coverage) | no hard gate; semi-active |
| [undercover](https://github.com/grodowski/undercover) | coverage of *changed* code via git diff × SimpleCov, no complexity term (0.8.1, Sep 2025) | yes — per-diff, PR-native via UndercoverCI |
| [RuboCop Metrics cops](https://docs.rubocop.org/rubocop/cops_metrics.html) | complexity only, no coverage | yes, but configurable away per cop and per file |
| [SimpleCov](https://github.com/simplecov-ruby/simplecov) `minimum_coverage` | aggregate coverage only | yes, project-wide percentage |

When **not** to use crap4ruby: for diff-aware PR gating of new code, use
undercover — it is the closest neighbor and the best complement, not a
competitor; for smell and design feedback, reek; for trend dashboards,
rubycritic; for style enforcement, rubocop.

One honest qualifier on "zero-config": the analyzed project must run
SimpleCov ≥ 1.0 with branch and method coverage enabled (the `.simplecov`
snippet under Requirements) — the same class of prerequisite undercover
has. Given that, crap4ruby needs no configuration of its own: no config
file, no threshold tuning, no cop lists.

## The contract

[spec.md](spec.md) plus the conformance corpus under `test/fixtures/` is the
complete, testable specification. Where prose and fixtures disagree, that is
a bug in one of them — file it. Background and rationale live in the
repository's FINDINGS.md, and the implementation architecture in its
DESIGN.md (both are development documents and are not shipped in the gem).
Release history: [CHANGELOG.md](CHANGELOG.md).

## Development

Everything runs through [devenv](https://devenv.sh):

```
devenv shell -- bundle install
devenv shell -- bundle exec rake test   # conformance + unit + integration
devenv test                             # what CI runs
```

The CRuby 3.3 floor check CI runs can also be run locally (the lsp
override is required — the default language server does not build under
3.3 on the current pin):

```
devenv shell --option languages.ruby.lsp.enable:bool false \
  --option languages.ruby.version:string "3.3.9" \
  -- bash -c 'ruby -v && (bundle check || bundle install) && bundle exec rake test'
```

The Prism pin, upgrade policy, and where score determinism actually comes
from are documented in DESIGN.md §8.

## License

[MIT](LICENSE).
