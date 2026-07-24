# crap4ruby — Research Findings

*Research date: 2026-07-24. Goal: evaluate what it would take to build a CRAP metric
tool for Ruby resembling Uncle Bob's [crap4java](https://github.com/unclebob/crap4java).*

*Revised same day after external review: coverage integration retargeted to
SimpleCov ≥ 1.0 and its public `coverage.json` contract (released 2026-07, after the
initial draft's assumptions), branch coverage moved from "later refinement" into the
v1 definition of `cov(m)`, missing coverage now fails the gate instead of passing it,
undercover's capabilities corrected, and the CC 4 threshold row fixed (37% → 38%).
A second review round tightened the coverage model further: `simplecov run` enables
no criteria (crap4ruby validates `meta.*_coverage` flags fail-closed), method
coverage joined the `cov(m)` formula as an invocation bit (fixing endless/one-line
definitions), the JaCoCo-equivalence claim was replaced with documented
Ruby-specific blind spots, `--no-run` requires a clean tree when `source` arrays
are absent, and dynamic `define_method` got a stable pseudo-identity. A third round
refined the details: all three coverage-criteria flags are validated (line included),
the invocation bit became a fallback used only when no line/branch unit exists (added
unconditionally it inflates every multi-line method's coverage), `"ignored"` counters
are specified, parallel CI's `merge` → `report` sequencing is spelled out, the
coverage path is resolved rather than hardcoded, and the floor is CRuby-specific. A
fourth pass closed the execution contract: declaration-time coverage is removed from
`define_method` as well as `def`, test failures stop scoring with a distinct exit,
cleanup is restricted to named SimpleCov artifacts, unloaded files must be covered
explicitly, test-command detection is deterministic, and the summary CLI now matches
the detailed design.*

---

## 1. Context — why this tool

In an X thread (2026-07-23), Uncle Bob Martin described his AI-agent workflow:

> "My current strategy is to not read any of the code written by my agents. […] What I
> do instead is to surround the agents with extreme constraints. Unit tests, gherkin
> tests, QA procedures, quality metrics, mutation testing, test coverage, and a
> plethora of others."

Key follow-ups from the thread:

- Asked *which deterministic tools* he uses for quality metrics, he linked
  **github.com/unclebob/crap4java**.
- "I have the agents write the tools that check the constraints. Those tools are
  deterministic. They are relatively small programs that check the quality of the code
  or check the coverage of the tests."
- "Messy code slows my agents down. […] So I don't let them create those tangles.
  I constrain the hell out [of them]."
- On agents gaming tests: "That's why we overload the tests with mutation testing, QA
  procedures, gherkin tests, and so on. It's not just one test they have to change.
  It's a lot of tests."

So the target is a **small, deterministic, zero-config CLI quality gate** that an agent
(or CI) runs after every change — not a dashboard tool for humans. crap4java was
created 2026-03-13, is modeled after his earlier
[crap4clj](https://github.com/unclebob/crap4clj), and its sources carry
`mutate4java-manifest` footers from his companion mutation-testing tool.

## 2. The CRAP metric

**C.R.A.P. = Change Risk Anti-Patterns**, introduced in 2007 by Alberto Savoia and Bob
Evans (crap4j). It combines cyclomatic complexity and test coverage into one number
that is high exactly when code is both hard to understand *and* poorly tested:

```
CRAP(m) = comp(m)² × (1 − cov(m))³ + comp(m)
```

- `comp(m)` — cyclomatic complexity of method `m` (decision points + 1)
- `cov(m)` — test coverage of `m` as a fraction 0.0–1.0

Properties worth internalizing:

- **Fully covered code:** CRAP = CC. Coverage can never push CRAP below the
  complexity itself.
- **Uncovered code:** CRAP = CC² + CC — complexity is punished quadratically.
- The original threshold was **30** ("crappy above 30"). Uncle Bob's crap4java uses a
  far stricter **8.0** as a hard gate (see §3).
- Granularity is **per method**, not per file — this matters (see skunk's own stated
  limitation in §4).

The metric has seen a revival as an AI-era guardrail: see Better Stack's
[CRAP metric guide](https://betterstack.com/community/guides/ai/crap-metric/) and
[cargo-crap](https://github.com/minikin/cargo-crap) for Rust, whose author frames it
explicitly as a check on "AI-generated complexity without tests"
([blog post](https://minikin.me/blog/cargo-crap)).

## 3. Anatomy of crap4java (the model to imitate)

Repo: [unclebob/crap4java](https://github.com/unclebob/crap4java) — Java 21, Maven,
~20 small classes, fully spec-driven (`spec.md` in the repo is a complete testable
specification; local copy saved during research). Key design points:

### Pipeline (per run)

1. Delete stale coverage artifacts (`target/site/jacoco/`, `target/jacoco.exec`).
2. Run the test suite with coverage:
   `mvn -q jacoco:prepare-agent test jacoco:report`.
3. Parse `target/site/jacoco/jacoco.xml`.
4. Parse selected Java sources into methods (JDK compiler tree API — a real parser,
   "not regex-only"), compute cyclomatic complexity per method.
5. Attribute coverage to each method from JaCoCo `INSTRUCTION` counters
   (covered / (covered + missed) within the method).
6. Print a table (method, class, CC, coverage %, CRAP) sorted by CRAP descending;
   `N/A` rows (no coverage data) at the bottom.
7. Gate: if max CRAP > **8.0**, print `CRAP threshold exceeded: <max> > 8.0` to stderr.

### CLI contract

| Invocation | Meaning |
|---|---|
| `crap4java` | analyze all `.java` under `src/` |
| `crap4java --changed` | analyze only changed files (`git status --porcelain`: modified + added + untracked) |
| `crap4java <path...>` | explicit files, or all `.java` under `<dir>/src/` |
| `crap4java --help` | usage |

Exit codes: `0` OK (including "nothing to analyze"), `1` CLI usage error,
`2` threshold exceeded. Multi-module Maven repos: files are grouped by nearest
`pom.xml` ancestor; coverage runs once per module.

### Complexity counting rules (from `JavaMethodParser.java`)

Start at 1, then +1 for each: `if`, `for`, enhanced-`for`, `while`, `do-while`,
`catch`, ternary `?:`, each `case` label, and each `&&` / `||`. Nested/anonymous
classes inside a method body are **skipped**. Constructors and abstract methods are
**excluded** entirely.

### The 8.0 threshold is really two rules in one

Since CRAP ≥ CC always, a max-CRAP gate of 8.0 means:

| CC | Lowest 0.01%-step that passes | Lowest whole % that passes |
|---|---|---|
| 1–2 | 0% | 0% (always passes) |
| 3 | 17.80% | 18% |
| 4 | 37.01% (exact minimum: 37.0039…%) | 38% — exactly 37% scores 8.0008 and fails |
| 5 | 50.68% | 51% |
| 6 | 61.85% | 62% |
| 7 | 72.68% | 73% |
| 8 | 100% | 100% |
| ≥ 9 | impossible — **CC itself must come down** | — |

So the single number enforces both a hard complexity cap (~8) and a coverage floor
that scales with complexity. Elegant, and worth preserving exactly in a Ruby port.

### Deliberate non-goals (per spec)

No configurable threshold via CLI, no machine-readable output, no mutation analysis,
no non-Maven builds. Small program, one job.

## 4. Ruby ecosystem survey — what already exists

**Bottom line: there is no maintained per-method CRAP tool for Ruby.** The pieces all
exist separately; nothing combines them the way crap4java does.

| Tool | What it does | CRAP-relevant? | Status (via [Ruby Toolbox](https://www.ruby-toolbox.com/categories/code_metrics)) |
|---|---|---|---|
| [rubycrap](https://github.com/ingojauch/rubycrap) | Actual CRAP port, but uses **Flog score instead of CC** + simplecov-json | Closest ancestor, wrong complexity metric | Dead (~2013, 0 stars, Ruby 1.9 era). Gem name `rubycrap` is taken by it |
| [skunk](https://github.com/fastruby/skunk) | SkunkScore = RubyCritic cost (Flog/Flay/Reek smells) × (100 − coverage) penalty | Same *idea* (quality × coverage), but **file-level** and not CRAP. Its README itself lists "should work at method level" as a known limitation | Semi-active (FastRuby) |
| [RubyCritic](https://github.com/whitehead-studio/rubycritic) | Churn × complexity graph, A–F file ratings, SimpleCov support since 4.2 | File-level, HTML-report oriented, many deps | Last release Jan 2026, slow |
| [undercover](https://github.com/grodowski/undercover) | Warns on changed methods/blocks lacking coverage (git diff × SimpleCov × AST) | **Best plumbing reference** — see §5.3 | Active, ~840 stars, GitHub App (UndercoverCI) |
| [SimpleCov](https://github.com/simplecov-ruby/simplecov) | Line, branch and (binary) method coverage. **1.0 (2026-07)** added a public, versioned `coverage.json` schema and a CLI (`simplecov run`, `merge`, `report`, `diff`…); `.resultset.json` is documented as internal | The coverage source — see §5.2 | Active, de-facto standard |
| Ruby stdlib `Coverage` | `lines:`, `branches:`, `methods:` modes | `methods:` mode only reports *called / not called* per method (binary), not a fraction | stdlib |
| [Flog](https://github.com/seattlerb/flog) | ABC-style weighted complexity per method | Per-method, maintained-ish, but scores are not CC — CRAP thresholds (8/30) would be meaningless | Last release Jan 2026, low activity |
| RuboCop `Metrics/CyclomaticComplexity` | True per-method CC | The reference definition of CC-for-Ruby (see §5.1), but it's a lint cop, not a data API — internal classes are private API | Very active |
| [Saikuro](https://github.com/metricfu/Saikuro), [Fukuzatsu](https://github.com/CoralineAda/fukuzatsu), metric_fu, cane | Older CC / metrics tools | — | All dead (no releases in 3+ years, Saikuro since 2009) |

Other ecosystems, for reference: [cargo-crap](https://github.com/minikin/cargo-crap)
(Rust, function-level, LCOV, baseline mode, `--format github`),
[crap4dotnet](https://github.com/7Factor/crap4dotnet),
[GMetrics CrapMetric](https://dx42.github.io/gmetrics/metrics/CrapMetric.html)
(Groovy), and a long-open [JaCoCo feature request](https://github.com/jacoco/jacoco/issues/196).

**Gem name check (2026-07-24): `crap4ruby` and `crap4r` are both free on
RubyGems.org.**

## 5. Building blocks for crap4ruby

### 5.1 Complexity: write a small Prism visitor (recommended)

Ruby ships the **Prism** parser as a default gem since 3.3 (default parser in 3.4).
A ~100-line visitor gives true per-method cyclomatic complexity with zero heavy
dependencies — matching Uncle Bob's "relatively small programs" philosophy.

Mapping crap4java's counting rules to Ruby, cross-checked against RuboCop's
`Metrics/CyclomaticComplexity` (`COUNTED_NODES = if while until for csend block
block_pass rescue when in_pattern and or or_asgn and_asgn`):

| crap4java counts | Ruby equivalent (+1 each) |
|---|---|
| `if` | `if` / `elsif` / `unless` / modifier forms / ternary |
| loops | `while`, `until`, `for` |
| `case` labels | each `when`, each `in` (pattern matching) |
| `catch` | each `rescue` clause |
| `&&` `\|\|` | `&&`, `\|\|`, `and`, `or`, and `\|\|=`, `&&=` |
| — (Java has no equivalent) | **iterating blocks** (`each`, `map`, `times`…) — RuboCop counts them because blocks are Ruby's loops; recommend following suit. RuboCop also counts `&.` (with a discount for repeated chains) |
| excluded: constructors, abstract methods | exclude `initialize`? (decide — see §7), no bodies to skip; skip nested `class`/`module`/`def` bodies inside a method just like crap4java skips nested classes |

Alternatives considered and rejected:
- **Flog** — per-method but ABC-weighted (penalizes metaprogramming); not CC, so the
  8.0/30 thresholds and the CC≥9 hard-cap property stop being meaningful.
- **RuboCop internals** — correct math, but private API and a huge dependency for a
  quality gate an agent runs constantly.
- **whitequark `parser` gem** — what undercover/imagen use; lags new Ruby syntax by
  design; Prism is the future-proof choice.

### 5.2 Coverage: SimpleCov ≥ 1.0 `coverage.json` + AST line ranges

**Target SimpleCov ≥ 1.0** (1.0.0 released 2026-07-12; 1.0.2 current as of this
research). Version 1.0 changes the integration story completely:

- `coverage.json` is now a **public, versioned contract**: a top-level `$schema`
  field points to an immutable JSON Schema
  ([`schemas/coverage-v1.0.schema.json`](https://github.com/simplecov-ruby/simplecov/blob/main/schemas/coverage-v1.0.schema.json)),
  with `meta.schema_version` for compatibility checks. The README explicitly says to
  build integrations on `coverage.json`; `.resultset.json` "is SimpleCov-internal and
  may change shape across releases". The JSON formatter is bundled and on by default.
- **`bundle exec simplecov run -- <command>`** preloads coverage around any test
  command — internally it just sets `RUBYOPT=-rsimplecov/autostart` for the child
  process and defers to an existing `.simplecov` config. **It does not enable any
  coverage criterion**: SimpleCov defaults to line coverage, and branch/method
  coverage require explicit `enable_coverage :branch` / `enable_coverage :method`
  in the project's `.simplecov` or test helper. The `run` CLI has no `--branch` or
  `--method` flags. Consequence for crap4ruby: it must **verify all three criteria
  flags** — `meta.line_coverage`, `meta.branch_coverage` and `meta.method_coverage`
  all true (SimpleCov permits disabling line coverage too, and the formula below
  consumes all three data sources) — and fail closed (exit 3, with the exact config
  snippet to add) when any is false. (Injecting a tool-controlled startup config
  instead is an open decision — §7.)
- **`simplecov merge`** merges multiple resultsets (parallel/matrix CI);
  `SimpleCov.collate` remains the programmatic API.
- The schema carries exactly what a freshness check needs: `meta.commit` (git SHA at
  report time), `meta.timestamp` (ISO 8601, ms precision), and an optional per-file
  `source` array (the source lines themselves) — see §5.4.
- Per-file data includes `lines`, `branches` **and `methods`** arrays (the latter
  present iff `meta.method_coverage` is true). Each method entry carries a qualified
  name (`Foo#bar`, `Foo.bar`), `start_line`/`end_line`, and an execution count from
  Ruby's method-coverage mode. That count is binary in spirit (called or not — it
  says nothing about paths inside), but it supplies the **invocation bit** the
  `cov(m)` formula needs for single-line methods, a fast path (never-called ⇒ low
  `cov`), and a cross-check for Prism-derived method boundaries.

**Defining `cov(m)` — line coverage alone is not enough.** Complexity counts
conditional *paths*, and Ruby packs paths onto single lines: a one-line ternary
reports 100% line coverage when only one arm ever ran. Pairing CC with line-only
coverage would systematically understate CRAP for exactly the constructs that raise
CC. So v1 defines `cov(m)` over **coverable units** within the method's
Prism-derived range:

```
units(m) = relevant_lines(m) + branch_arms(m)
cov(m)   = units(m) > 0 ? hits(m) / units(m)
                        : (called(m) ? 1.0 : 0.0)   # invocation-bit fallback
```

- `relevant_lines` — lines in `m`'s range with integer line counters, **excluding
  the declaration line**: the `def` line for an ordinary method, or the
  `define_method(...)` call line for a method defined from a block. Both execute
  while the class/module body is loaded, before the method itself is invoked, so
  counting either would manufacture coverage. For **endless methods
  (`def foo = expr`) and one-line `def`/`define_method` definitions**, the entire
  body shares the declaration line; this set is therefore empty and coverage falls
  through to branch arms when present, otherwise the invocation bit.
- `branch_arms` — every branch outcome SimpleCov records within the range
  (`enable_coverage :branch`).
- **Invocation-bit fallback** — from the `methods` array
  (`enable_coverage :method`): used **only when no line or branch unit exists**
  (branchless endless/one-line `def` or `define_method` definitions, empty methods).
  It must not be added unconditionally: any multi-line method with one covered line
  was necessarily called, so an always-covered extra unit inflates every ordinary
  method's coverage — e.g. a CC-5 method at 3/6 real units is CRAP 8.125 (fails),
  but with the redundant bit becomes 4/7 → CRAP 6.968 (passes).
- **`"ignored"` counters** — the schema allows `"ignored"` (from
  `simplecov:disable` regions) alongside integers and `null` in line, branch and
  method counters. Ignored units are excluded from both `units` and `hits` (like
  `null`); a method whose units are all ignored, or whose own method counter is
  `"ignored"`, is excluded from the report entirely — same semantics as `:nocov:`.
- Empty methods hit the fallback: called ⇒ `cov = 1.0` ⇒ CRAP = CC; never called ⇒
  `cov = 0` ⇒ CRAP = CC² + CC (= 2 at CC 1 — far below the gate).
- The alternative `min(line_cov, branch_cov)` is harsher and lumpier — decision
  recorded in §7.

Worked example: `def admin?(u) = u.role == :admin ? true : audit!` called only down
the `then` arm → no relevant lines (endless method), 2 branch arms of which 1 hit →
`cov` = 1/2 = 0.5, which is the honest number. Its branchless cousin
`def name = @name` has zero line and branch units, so the invocation bit decides:
called ⇒ 1.0, never ⇒ 0.0.

**This is a deliberately Ruby-specific metric, not a JaCoCo port.** JaCoCo keeps
instruction, branch, line, and method counters separate, and crap4java specifically
uses *instruction* counters — a granularity Ruby's `Coverage` does not expose. The
composite above is the closest honest substitute, and it has **documented blind
spots**: Ruby records branch arms for `if`/`unless`/ternary, `case/when`,
`case/in`, `while`/`until` and `&.` — but **not** for `&&`/`||`/`and`/`or`, for
`rescue` clauses, or for iterator blocks. All of those raise the proposed CC, so a
method can reach `cov = 1.0` while a short-circuit path, rescue path, or
never-iterated block was never executed, and same-line untested paths of those kinds
still score 100%. Mitigations: this is exactly the gap mutation testing covers in
Uncle Bob's constraint belt (§1), and the 8.0 threshold should be calibrated against
Ruby fixtures (§6) rather than justified by claimed JaCoCo equivalence.

### 5.3 undercover / imagen — the closest existing plumbing (user-suggested)

[undercover](https://github.com/grodowski/undercover) already implements, in a
maintained gem, most of crap4ruby's hard parts:

- consumes `coverage/coverage.json` produced by **its own formatter class**
  (`SimpleCov::Formatter::Undercover`, loaded via
  `require 'undercover/simplecov_formatter'`); LCOV input is deprecated. It does
  *not* read `.resultset.json`;
- **maps coverage onto methods, classes and blocks** via AST line ranges (through
  its companion gem [imagen](https://github.com/grodowski/imagen_rb), built on the
  whitequark parser);
- computes a **per-node coverage fraction** (its warnings even print "coverage: X%"
  per method/block), including **branch coverage with same-line ternary arms**
  (reported as e.g. `"? role == :admin → else"`) when `enable_coverage :branch` is
  on — so it already handles the §5.2 same-line-branch problem;
- scopes analysis to **git changes** (`--compare ref`) — a richer version of
  crap4java's `--changed`;
- handles practical edge cases: `:nocov:` markers, glob include/exclude, text + JSON
  output, exit code 1 for CI. Note: it does **not** merge parallel-suite results —
  its README requires results to be merged *before* undercover runs (with
  SimpleCov 1.0 that's now just `simplecov merge` / `SimpleCov.collate`).

What it does **not** do: any complexity measurement, and any scoring — its gate is
binary ("changed method has untested lines"), which is noisier than CRAP's
"complexity × uncoverage" ranking (a CC-1 one-liner without a dedicated test fails
undercover but is CRAP-harmless at 2.0).

Three ways to use it:

1. **Depend on it** (`Undercover::Report` + imagen node tree), add a complexity
   visitor on top, emit CRAP. Fastest path; costs: whitequark parser (syntax lag)
   and coupling to APIs not designed as public.
2. **Borrow its design, build on Prism** — reimplement the coverage-to-method join
   (it's small once Prism gives line ranges) and copy its battle-tested decisions
   (`:nocov:` handling, diff scoping, glob filters, same-line branch reporting).
   **Recommended** — keeps crap4ruby a small, dependency-light, spec-driven tool
   like crap4java, and lets it consume SimpleCov 1.0's standard `coverage.json`
   directly instead of a custom formatter.
3. **Complementary use** — run undercover as the "no new untested code in this diff"
   gate and crap4ruby as the "no complex untested code anywhere" gate; they compose
   nicely in the same guardrail belt.

### 5.4 Running the tests (the step crap4java owns)

crap4java runs `mvn … test` itself. Ruby test invocation is heterogeneous
(`bundle exec rspec`, `bin/rails test`, `rake`), and SimpleCov 1.0's CLI makes
wrapping trivial: `simplecov run -- <test command>` preloads coverage with no
`test_helper` changes. Two **separate pipelines** (they must not share a cleanup
step — deleting coverage first would contradict consuming existing coverage):

- **Normal mode: clean → run → read → verify.** Resolve the report path first. Remove
  only that `coverage.json` and its sibling `.resultset.json`; never recursively
  delete the resolved file's parent directory, which may contain unrelated reports.
  Run `bundle exec simplecov run -- <detected or --test-command test command>`.
  A non-zero child status (including termination by signal) stops immediately:
  print the child status, do not calculate CRAP from a partial report, and exit 4.
  On success, read the resolved `coverage.json`, then verify
  `meta.line_coverage`, `meta.branch_coverage` and `meta.method_coverage` are all
  true (§5.2) — exit 3 with the remedial `.simplecov` snippet if not.
- **Test-command detection is deterministic.** `spec/` alone means
  `bundle exec rspec`; `test/` plus `bin/rails` means `bin/rails test`; a non-Rails
  `test/` plus a `Rakefile` means `bundle exec rake test`. If both `spec/` and
  `test/` exist, neither exists, or the detected layout lacks its expected runner,
  automatic selection refuses to guess (exit 1) and requires
  `--test-command "<command>"`. This prevents a mixed suite from silently running
  only half its tests.
- **Coverage path and scope are explicit prerequisites.** The default is
  `coverage/coverage.json` with SimpleCov's bundled JSON formatter. Projects that
  configure `coverage_path`/`coverage_dir` or custom formatters pass
  `--coverage-file <path>` pointing to a file that conforms to the public schema.
  Every analyzed file must also be present, including files the suite never loads;
  the recommended default-scope configuration is:

  ```ruby
  SimpleCov.configure do
    enable_coverage :branch
    enable_coverage :method
    cover "app/**/*.rb", "lib/**/*.rb"
  end
  ```

  Explicit analysis paths outside `app/` and `lib/` need matching `cover` patterns.
  An analyzed file still absent after configuration is an operational error (exit
  3), not implicit zero coverage: absence can also mean a mismatched filter or root.
- **`--no-run` mode: preserve → validate → read.** Never delete anything. Validate
  the existing `coverage.json` before trusting it: `meta.schema_version` compatible;
  all three criteria enabled (line + branch + method, as above);
  `meta.commit` equals current `HEAD`; and source identity — when the optional
  per-file `source` arrays are present, compare source text exactly against the
  files on disk; **when they are absent, require the working tree to be clean for
  the analyzed files** (mtime-based checks are insufficient: dirty content can
  retain or acquire an older mtime, so HEAD-match plus mtimes can approve coverage
  for source that was never measured). `meta.timestamp` remains a sanity check
  only. Any validation failure is an operational error (exit 3, §6), not a warning.
- **Parallel/matrix CI:** two distinct paths produce the merged `coverage.json`.
  CLI: `simplecov merge` produces a merged `.resultset.json` **and does not emit
  `coverage.json` itself** — SimpleCov instructs users to run `simplecov report`
  afterward, so the sequence is `merge` → `report` → crap4ruby `--no-run`.
  Programmatic: `SimpleCov.collate` can run formatters directly, so `collate` →
  crap4ruby `--no-run`.

### 5.5 Prolog / Datalog potential: useful oracle, premature runtime

A logic-programming rules layer is attractive because crap4ruby talks about
"rules", but v1's rules are not primarily relational: Prism node types contribute
small integer increments, coverage counters are aggregated within one method, and
one formula produces the gate score. Prolog would not replace the difficult work —
Ruby would still parse source with Prism, validate SimpleCov JSON, assign coverage
to methods and serialize those facts across a language/runtime boundary.

**Recommendation for v1: keep the shipped evaluator in Ruby.** Express the simple
mapping declaratively where possible (for example, a frozen node-type → increment
table), use small explicit Ruby handlers for syntax-sensitive cases, and make the
fixture corpus the executable specification. Adding Prolog now would impose another
runtime and packaging/debugging vocabulary on every user without simplifying the
core algorithm; that conflicts with the small, dependency-light design goal.

Logic programming can still add value in two later roles:

1. **Development-time semantic oracle.** Export the fixture corpus as facts and
   implement an independent Prolog model of complexity/coverage rules. Comparing its
   results with the Ruby evaluator can catch semantic drift without making Prolog a
   production dependency.
2. **Future relational policy layer.** Reconsider it if crap4ruby grows beyond a
   per-method metric into questions involving several relationships at once: changed
   methods and their callers, namespace/package inheritance, policy exceptions,
   conflicting constraints, rule provenance ("why did this fail?"), or searches for
   combinations of remediations that satisfy multiple gates.

For a finite set of monotonic project facts, a Datalog-style engine would likely be
the smaller fit. Full Prolog becomes more compelling only if the product needs
general backtracking/search rather than deterministic rule evaluation. Either form
must remain behind a fact/query boundary so the Prism and SimpleCov adapters do not
depend on the chosen logic engine.

## 6. Proposed shape of crap4ruby (spec sketch)

Mirror `spec.md` of crap4java as closely as Ruby allows — same core CLI, formula and
report, with explicit additional exits for invalid coverage and failed test runs:

- **CLI:** `crap4ruby` (all `.rb` under `app/` and `lib/`),
  `crap4ruby --changed` (git status porcelain: modified/added/untracked),
  `crap4ruby <path...>`, `crap4ruby --no-run`,
  `crap4ruby --test-command "<command>"`,
  `crap4ruby --coverage-file <path>`, and `crap4ruby --help`. The mode/options
  compose with `--changed` or explicit paths where meaningful.
- **Pipeline:** two modes per §5.4 — normal (clean → `simplecov run` → read) and
  `--no-run` (preserve → validate → read); then Prism-parse selected files →
  per-method CC + `cov(m)` → CRAP.
- **Formula:** `CRAP = CC² × (1 − cov)³ + CC`, with `cov(m)` defined over combined
  line + branch units per §5.2; method coverage is only the fallback when there are
  zero such units, including endless/one-line definitions and empty methods.
- **Complexity:** the spec must pin the exact counting rules as a table of Prism
  node types (the §5.1 mapping is a starting point, not a spec) and ship **syntax
  fixtures as conformance tests** — one fixture file per construct with its expected
  CC. "Like RuboCop" is not implementable: RuboCop counts only recognized iterator
  blocks, discounts repeated `&.` chains, and has other syntax-specific behavior
  that a spec must either adopt explicitly or reject explicitly.
- **Report:** table `method | class/module | CC | coverage % | CRAP`, sorted CRAP
  descending.
- **Gate:** max CRAP > 8.0 → stderr message + exit 2.
- **Coverage failures fail the run** — a deliberate deviation from crap4java, which
  reports `N/A` rows and lets a run with *no* numeric scores pass (max treated as
  0.0). For an agent-facing gate that is a loophole: breaking coverage generation
  would green the build. In crap4ruby, missing, stale, unparseable, or
  schema-incompatible coverage, **required criteria not enabled**
  (`meta.line_coverage`, `meta.branch_coverage`, or `meta.method_coverage` false),
  or analyzed files absent from the report (e.g. unloaded without `cover`, or
  dropped by SimpleCov filters without a matching crap4ruby exclusion) — all of it
  is an **operational failure: exit 3**, distinct from the threshold failure.
- **Test failures fail before scoring.** A non-zero `simplecov run` child status
  cannot be replaced by a green CRAP result; report it and exit 4.
- **Exit codes:** `0` OK, `1` CLI usage error, `2` CRAP threshold exceeded,
  `3` coverage unavailable/invalid, `4` test command failed.
- **Non-goals (v1), per crap4java:** configurable threshold, machine-readable output,
  mutation analysis, non-Bundler projects, editor integration, and a runtime
  Prolog/Datalog rules engine (§5.5).
- **Dependencies:** `prism` and `json` (both stdlib on CRuby ≥ 3.3) at runtime;
  SimpleCov ≥ 1.0 required in the analyzed project as the coverage producer.
  **Development environment:** the entire crap4ruby stack is built, run, tested,
  and packaged through devenv. Bootstrap `devenv.nix` and `devenv.yaml` before
  scaffolding the gem; local development and CI must execute Ruby, Bundler, Rake,
  gem, and test commands through `devenv shell -- <command>`. A missing or broken
  devenv shell is a blocking environment failure, never permission to fall back to
  a system Ruby or a version manager.
  **CRuby only:** JRuby supports line coverage only, so the required branch and
  method criteria can never be satisfied there — documented as unsupported.

Method-identity note: reportable methods are `def` / `def self.` nodes (plus
`class << self` scope) **and `define_method(:literal_name) do … end` blocks** — the
latter have a static body with lines, branches and complexity, and silently skipping
them would let an agent hide arbitrary complexity from the gate. Dynamically named
definitions (`define_method(name) do … end`) get a **stable pseudo-identity**: a
report row named `<Enclosing::Scope>#define_method@<line>` (the line of the
`define_method` call), with CC and `cov` computed from the block body exactly like a
normal method. Its declaration/call line is excluded because it executes while the
class/module body loads; a one-line block therefore reaches the invocation-bit
fallback rather than receiving false coverage from definition alone. Ruby's method
coverage emits entries for dynamically defined methods too (runtime name + the
block's source range), so crap4ruby joins `methods`-array entries to the block by
source span. When several runtime names share one span (`define_method` in a loop),
the aggregation rule is *any called* ⇒ called. This keeps the identity stable across
runs and the complexity visible, without pretending a class/module scope is a
method. Skip only what has no static body: `attr_*`, `class_eval` with string
arguments. Ordinary blocks contribute CC to their enclosing method.

## 7. Open decisions

1. **Threshold 8.0 fixed vs configurable.** Uncle Bob hardcodes 8.0 (a deliberate
   constraint, see table in §3). For legacy Rails apps that's brutal on day one —
   cargo-crap solved this with a `--fail-regression` baseline mode. Suggest: hardcode
   8.0 like the original, add baseline mode only when real usage demands it.
2. **Count iterating blocks toward CC?** RuboCop says yes (they are Ruby's loops);
   crap4java has no analog. Counting them is more honest but yields higher CC than
   Java developers expect for equivalent code. Recommendation: count them — and
   whatever the choice, encode it in the spec's fixture suite (§6), including the
   edge behaviors RuboCop special-cases (which blocks count, `&.` chains, `||=`).
3. **`cov(m)` weighting.** Combined coverable units (lines + branch arms, with the
   invocation-bit fallback, §5.2) vs `min(line_cov, branch_cov)`. Recommendation:
   combined units — smoother; revisit if it proves too forgiving on branch-dense
   one-liners.
4. **`initialize`.** crap4java excludes constructors. Ruby `initialize` often carries
   real logic; recommend *including* it (deviation worth documenting).
5. **Declaration-line coverage inflation** (§5.2): exclude the `def` line or
   `define_method` call line from relevant lines. Endless and one-line definitions —
   whose only physical line cannot distinguish definition from invocation — are
   covered by branch arms when present, else the invocation-bit fallback.
6. **Enable coverage criteria by injection or by validation?** `simplecov run`
   cannot switch on branch/method coverage itself (§5.2). v1 recommendation:
   validate-only — fail closed (exit 3) with the exact `.simplecov` snippet the
   project needs. The alternative, injecting a tool-controlled startup config via
   `RUBYOPT`, guarantees the criteria but risks bypassing or double-starting the
   project's own SimpleCov configuration (filters, groups, merging) — revisit if
   validate-only proves annoying in practice.
7. **Floors:** CRuby ≥ 3.3 keeps Prism and `json` as stdlib (JRuby unsupported —
   line coverage only); SimpleCov ≥ 1.0 is required for the `coverage.json`
   contract and `simplecov run`/`merge`/`report` CLI.
8. **Logic-programming rules layer** (§5.5): keep Prolog/Datalog out of the v1
   runtime; an optional development-time oracle is safe to prototype independently.
   Revisit a production policy engine only when requirements become genuinely
   relational across methods/scopes or need rule provenance and remediation search.
9. **Rails specifics:** views/ERB and generated code are out of scope; `app/` +
   `lib/` discovery covers the common layout; engines/monorepos would need
   `Gemfile`-based module grouping (analog of crap4java's `pom.xml` walk) — defer.

## 8. Sources

- crap4java: [repo](https://github.com/unclebob/crap4java) — README, `spec.md`, and
  sources (local copies in scratchpad during research); created 2026-03-13, 86 stars
- crap4clj: [repo](https://github.com/unclebob/crap4clj)
- CRAP metric background: [Better Stack guide](https://betterstack.com/community/guides/ai/crap-metric/),
  [Software Testing Magazine](https://www.softwaretestingmagazine.com/knowledge/crap-change-risk-anti-patterns-code-metric/),
  [Artima — "The Code C.R.A.P. Metric Hits the Fan"](https://www.artima.com/weblogs/viewpost.jsp?thread=215899),
  [crap4j archive](https://research.tedneward.com/tools/crap4j/index.html),
  [GMetrics CrapMetric](https://dx42.github.io/gmetrics/metrics/CrapMetric.html),
  [JaCoCo issue #196](https://github.com/jacoco/jacoco/issues/196)
- Rust port + rationale: [cargo-crap](https://github.com/minikin/cargo-crap),
  [blog](https://minikin.me/blog/cargo-crap); .NET: [crap4dotnet](https://github.com/7Factor/crap4dotnet)
- Ruby ecosystem: [undercover](https://github.com/grodowski/undercover),
  [imagen](https://github.com/grodowski/imagen_rb),
  [skunk](https://github.com/fastruby/skunk)
  ([intro post](https://www.fastruby.io/blog/code-quality/introducing-skunk-stink-score-calculator.html),
  [churn vs complexity vs coverage](https://www.fastruby.io/blog/code-quality/churn-vs-complexity-vs-coverage.html)),
  [RubyCritic + SimpleCov](https://www.fastruby.io/blog/code-quality/code-coverage/rubycritic-4-2-0-simplecov-support.html),
  [rubycrap](https://github.com/ingojauch/rubycrap),
  [RuboCop CyclomaticComplexity](https://www.rubydoc.info/gems/rubocop/RuboCop/Cop/Metrics/CyclomaticComplexity)
  ([source](https://github.com/rubocop/rubocop/blob/master/lib/rubocop/cop/metrics/cyclomatic_complexity.rb)),
  [Saikuro](https://github.com/metricfu/Saikuro),
  [Fukuzatsu](https://github.com/CoralineAda/fukuzatsu),
  [Ruby Toolbox — Code Metrics](https://www.ruby-toolbox.com/categories/code_metrics)
- SimpleCov 1.0 (verified 2026-07-24): [README — CLI, formatters, integration
  guidance](https://github.com/simplecov-ruby/simplecov/blob/main/README.md),
  [CHANGELOG](https://github.com/simplecov-ruby/simplecov/blob/main/CHANGELOG.md),
  [coverage-v1.0 JSON Schema](https://github.com/simplecov-ruby/simplecov/blob/main/schemas/coverage-v1.0.schema.json);
  release dates via RubyGems API (1.0.0 → 2026-07-12, 1.0.2 → 2026-07-18)
- Ruby coverage semantics: [stdlib `Coverage` docs](https://docs.ruby-lang.org/en/master/Coverage.html)
  (branch-arm scope for `&&`/`rescue`/blocks additionally confirmed empirically by
  the external reviewer's Ruby 4.0.5 probe)
- Gem-name availability: RubyGems API, checked 2026-07-24 (`crap4ruby` 404 = free,
  `rubycrap` taken)
