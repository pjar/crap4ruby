# crap4ruby — Research Findings

*Research date: 2026-07-24. Goal: evaluate what it would take to build a CRAP metric
tool for Ruby resembling Uncle Bob's [crap4java](https://github.com/unclebob/crap4java).*

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

| CC | Min. method coverage to pass |
|---|---|
| 1–2 | 0% (always passes) |
| 3 | ≥ 18% |
| 4 | ≥ 37% |
| 5 | ≥ 51% |
| 6 | ≥ 62% |
| 7 | ≥ 73% |
| 8 | 100% |
| ≥ 9 | **impossible — CC itself must come down** |

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
| [SimpleCov](https://github.com/simplecov-ruby/simplecov) | Line + branch coverage, `.resultset.json` | The coverage source | Active, de-facto standard |
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

### 5.2 Coverage: SimpleCov `.resultset.json` + AST line ranges

Ruby has no JaCoCo-style per-method instruction counters, so per-method coverage must
be **derived**: take each method's line range from Prism, intersect with SimpleCov's
per-file `lines` array (`null` = not relevant, `0` = missed, `n>0` = covered), and
compute `covered_relevant_lines / relevant_lines`. This is the closest analog of
crap4java's `INSTRUCTION`-counter fraction, and it's exactly the approach undercover
already validates in production. Branch coverage (`enable_coverage :branch`) can
refine this later; stdlib `Coverage`'s `methods:` mode is *not* sufficient (binary
called/not-called only).

Ruby quirk to handle: the `def` line itself executes at class-load time, so it's
covered by merely requiring the file. Either exclude the `def` line from the
method's relevant lines or accept slight inflation (undercover hit the same issue).

### 5.3 undercover / imagen — the closest existing plumbing (user-suggested)

[undercover](https://github.com/grodowski/undercover) already implements, in a
maintained gem, most of crap4ruby's hard parts:

- reads SimpleCov results (JSON; LCOV support deprecated) and **maps coverage onto
  methods, classes and blocks** via AST line ranges (through its companion gem
  [imagen](https://github.com/grodowski/imagen_rb), built on the whitequark parser);
- computes a **per-node coverage fraction** (its warnings even print "coverage: X%"
  per method/block);
- scopes analysis to **git changes** (`--compare ref`) — a richer version of
  crap4java's `--changed`;
- handles the practical edge cases: `:nocov:` markers, glob include/exclude,
  parallel-suite resultset merging, text + JSON output, exit code 1 for CI.

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
   (resultset discovery/staleness check, `:nocov:`, diff scoping). **Recommended** —
   keeps crap4ruby a small, dependency-light, spec-driven tool like crap4java.
3. **Complementary use** — run undercover as the "no new untested code in this diff"
   gate and crap4ruby as the "no complex untested code anywhere" gate; they compose
   nicely in the same guardrail belt.

### 5.4 Running the tests (the step crap4java owns)

crap4java runs `mvn … test` itself. Ruby test invocation is heterogeneous
(`bundle exec rspec`, `bin/rails test`, `rake`), so:

- default: auto-detect (`spec/` + rspec vs `test/` + minitest), run with
  `COVERAGE=1`-style env or an injected `simplecov` start via `RUBYOPT=-r./.crap4ruby_simplecov`;
- escape hatch: `--test-command "bin/rails test"`;
- `--no-run`: skip execution and consume an existing fresh `.resultset.json`
  (undercover's model; also what CI matrix builds need after merging parallel
  results). Staleness check: warn if resultset predates newest analyzed source file.

## 6. Proposed shape of crap4ruby (spec sketch)

Mirror `spec.md` of crap4java as closely as Ruby allows — same CLI, same formula,
same exit codes, same report:

- **CLI:** `crap4ruby` (all `.rb` under `app/` and `lib/`), `crap4ruby --changed`
  (git status porcelain: modified/added/untracked), `crap4ruby <path...>`,
  `crap4ruby --help`.
- **Pipeline:** delete stale `coverage/` artifacts → run tests with SimpleCov →
  parse `.resultset.json` → Prism-parse selected files → per-method CC + coverage →
  CRAP.
- **Formula:** `CRAP = CC² × (1 − coverage)³ + CC`, coverage from line counters
  (branch counters as a later refinement).
- **Report:** table `method | class/module | CC | coverage % | CRAP`, sorted CRAP
  descending, `N/A` rows last.
- **Gate:** max CRAP > 8.0 → stderr message + exit 2. Exit 0 success, 1 usage error.
- **Non-goals (v1), per crap4java:** configurable threshold, machine-readable output,
  mutation analysis, non-Bundler projects, editor integration.
- **Dependencies:** `prism` (stdlib on Ruby ≥ 3.3), `json` (stdlib). SimpleCov only
  as the coverage producer inside the analyzed project, not a hard runtime dep.

Method-identity note: Ruby methods worth reporting are `def` / `def self.` nodes
(plus `class << self` scope). Skip: `attr_*`/`define_method`/`class_eval`-generated
methods (no static body), blocks themselves (they contribute CC to their enclosing
method instead).

## 7. Open decisions

1. **Threshold 8.0 fixed vs configurable.** Uncle Bob hardcodes 8.0 (a deliberate
   constraint, see table in §3). For legacy Rails apps that's brutal on day one —
   cargo-crap solved this with a `--fail-regression` baseline mode. Suggest: hardcode
   8.0 like the original, add baseline mode only when real usage demands it.
2. **Count iterating blocks toward CC?** RuboCop says yes (they are Ruby's loops);
   crap4java has no analog. Counting them is more honest but yields higher CC than
   Java developers expect for equivalent code. Recommendation: count them.
3. **`initialize`.** crap4java excludes constructors. Ruby `initialize` often carries
   real logic; recommend *including* it (deviation worth documenting).
4. **`def`-line coverage inflation** (§5.2): exclude the `def` line from relevant
   lines.
5. **Ruby floor:** ≥ 3.3 keeps Prism as stdlib and the tool dependency-free.
6. **Rails specifics:** views/ERB and generated code are out of scope; `app/` +
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
- Gem-name availability: RubyGems API, checked 2026-07-24 (`crap4ruby` 404 = free,
  `rubycrap` taken)
