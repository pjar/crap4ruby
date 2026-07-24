# crap4ruby specification

Version: 0.1 (draft, 2026-07-25). This document plus the fixture corpus under
`test/fixtures/` is the complete, testable specification, in the style of
crap4java's `spec.md`. Where prose and fixtures disagree, that is a bug in one
of them — file it; neither silently wins. Background and rationale live in
[FINDINGS.md](FINDINGS.md); this document states only the contract.

## 1. Overview

crap4ruby is a small, deterministic CLI quality gate. It runs the project's
test suite under SimpleCov, computes the CRAP score of every analyzed method,
prints a report, and fails when any method's score exceeds the threshold.

```
CRAP(m) = comp(m)² × (1 − cov(m))³ + comp(m)
```

- `comp(m)` — cyclomatic complexity of method `m` (§6)
- `cov(m)` — test coverage of `m` as a fraction 0.0–1.0 (§7)
- Threshold: **8.0**, not configurable.

## 2. Requirements

- CRuby ≥ 3.3 (Prism and `json` as default gems). JRuby/TruffleRuby are
  unsupported: the required branch and method coverage criteria are
  unavailable there.
- The analyzed project must use Bundler and SimpleCov ≥ 1.0.
- Runtime dependencies of crap4ruby itself: `prism`, `json`. Nothing else.

## 3. CLI

| Invocation | Meaning |
|---|---|
| `crap4ruby` | analyze all `.rb` files under `app/` and `lib/` |
| `crap4ruby <path...>` | analyze explicit files; a directory argument means all `.rb` under it |
| `crap4ruby --changed` | analyze only changed `.rb` files (`git status --porcelain`: modified, added, untracked) |
| `crap4ruby --no-run` | do not run tests; validate and consume the existing coverage report (§4.2) |
| `crap4ruby --test-command "<cmd>"` | run `<cmd>` under `simplecov run` instead of the detected test command |
| `crap4ruby --coverage-file <path>` | read the coverage report from `<path>` instead of `coverage/coverage.json` |
| `crap4ruby --help` | print usage, exit 0 |

`--changed` and explicit paths select *files to analyze*; they never narrow
the test run — coverage always comes from the full suite. Options compose
except: `--test-command` with `--no-run` is a usage error (exit 1). Unknown
options and non-existent explicit paths are usage errors (exit 1). Explicit
paths that contain no `.rb` files, or an empty `--changed` set, print
`nothing to analyze` and exit 0.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | OK — no method above threshold (including "nothing to analyze") |
| 1 | CLI usage error |
| 2 | CRAP threshold exceeded |
| 3 | coverage unavailable or invalid (missing report, schema mismatch, criteria disabled, stale, analyzed file absent from report) |
| 4 | test command failed |

## 4. Execution pipelines

### 4.1 Normal mode (default)

1. **Resolve** the coverage report path: `--coverage-file` if given, else
   `<project root>/coverage/coverage.json`.
2. **Clean**: delete only that file and a sibling `.resultset.json` if
   present. Never delete directories.
3. **Run**: `bundle exec simplecov run -- <test command>`. The test command
   is `--test-command` if given, else detected (§4.3). If the child exits
   non-zero or dies on a signal: print its status, **do not score**, exit 4.
4. **Read + validate** the report (§4.4).
5. Parse, score, report, gate (§5–§8).

### 4.2 `--no-run` mode

Never deletes or writes anything. Reads the resolved report and validates it
(§4.4) plus freshness:

- `meta.commit` must be non-null and equal to the current `HEAD` SHA. A null
  commit (report generated outside a git checkout) fails validation.
- When per-file `source` arrays are present: the array joined with newlines
  must byte-for-byte equal the file on disk for every analyzed file.
- When any analyzed file lacks a `source` array: the working tree must be
  clean for all analyzed files (`git status --porcelain` on those paths is
  empty). mtime comparison is never used.

Any failure: exit 3 with a message naming the failed check.

### 4.3 Test-command detection

Deterministic, no fallbacks:

| Layout | Command |
|---|---|
| `spec/` exists, `test/` does not | `bundle exec rspec` |
| `test/` exists and `bin/rails` exists | `bin/rails test` |
| `test/` exists, no `bin/rails`, `Rakefile` exists | `bundle exec rake test` |
| anything else (both dirs, neither, missing runner) | refuse: exit 1, ask for `--test-command` |

### 4.4 Report validation (both modes)

- File exists and parses as JSON; `meta.schema_version` is `1.0` (or a later
  1.x — reject 2.x and above).
- `meta.line_coverage`, `meta.branch_coverage`, `meta.method_coverage` are
  all `true`. If not, exit 3 and print the exact remedial snippet:

  ```ruby
  # .simplecov  (configuration only — SimpleCov.start belongs in the test helper)
  SimpleCov.configure do
    enable_coverage :branch
    enable_coverage :method
    cover "app/**/*.rb", "lib/**/*.rb"
  end
  ```

- Every analyzed file must appear as a key in `coverage`. File keys are
  resolved relative to `meta.root`; an analyzed file missing from the report
  is exit 3 (likely an unloaded file without a `cover` pattern, or a
  SimpleCov filter), never implicit zero coverage.

## 5. Method identity and reportability

A **reportable method** is:

1. Every `def` node (`DefNode`), wherever it appears — top level, class or
   module body, `class << self`, inside another method, inside a block.
2. Every `define_method` call with a block. With a literal `Symbol` or
   `String` name argument it is reported under that name. With a dynamic
   name it is reported once per call site as `define_method@<line>` (the
   line of the `define_method` call), regardless of how many runtime methods
   the surrounding code creates from it.

Identity format:

- Instance methods: `Scope#name`. Singleton methods (`def self.x`, or `def x`
  inside `class << self`): `Scope.name`.
- `Scope` is the lexical constant path of the nearest enclosing `class` /
  `module` / `class << self` node, joined with `::`. Empty at top level
  (identity is then `#name` / `.name`).
- A `def` whose nearest scope-creating ancestor is a block (e.g.
  `Class.new do … end`) uses `Scope::(anon@<line>)` where `<line>` is the
  block's first line and `Scope` the nearest named lexical scope.
- Rows are unique by (identity, definition line). Two definitions of the
  same name produce two rows.

Not reportable (no row, ever): `attr_reader` / `attr_writer` /
`attr_accessor`, `alias` / `alias_method`, and `class_eval` /
`module_eval` / `instance_eval` with string arguments (no static body).

Methods excluded by coverage ignore markers are removed from the report
(§7.4). Everything else that is reportable and analyzed must produce exactly
one row.

## 6. Cyclomatic complexity

`comp(m)` starts at **1** and adds **1** for each node below occurring in
`m`'s own body. Prism node types are normative:

| +1 per occurrence | Prism node | Notes |
|---|---|---|
| `if`, `elsif`, modifier `if`, ternary, pattern guard | `IfNode` | an `if/elsif/else` chain of k conditions counts k; `else` is free |
| `unless` (incl. modifier) | `UnlessNode` | |
| `while`, `until` (incl. modifiers), `for` | `WhileNode`, `UntilNode`, `ForNode` | |
| each `when` clause | `WhenNode` | the `case` itself is free |
| each `in` clause | `InNode` | a guard adds its own `IfNode`/`UnlessNode` |
| each `rescue` clause | `RescueNode` | `else`/`ensure` are free |
| modifier rescue (`x rescue y`) | `RescueModifierNode` | |
| `&&`, `and` | `AndNode` | |
| `\|\|`, `or` | `OrNode` | |
| `\|\|=` (all receivers) | `LocalVariableOrWriteNode`, `InstanceVariableOrWriteNode`, `ClassVariableOrWriteNode`, `GlobalVariableOrWriteNode`, `ConstantOrWriteNode`, `ConstantPathOrWriteNode`, `CallOrWriteNode`, `IndexOrWriteNode` | |
| `&&=` (all receivers) | the `…AndWriteNode` counterparts | |
| safe navigation `&.` | `CallNode` with `safe_navigation?` | +1 for **every** `&.` call; no chain discount (deviation from RuboCop, which discounts repeated chains) |
| any block (`do…end`, `{…}`, numbered params, `it`) | `BlockNode` | blocks are Ruby's loops; **no iterator-method whitelist** (deviation from RuboCop, which counts only recognized iterating methods) |
| block pass (`&blk`, `&:sym`) | `BlockArgumentNode` | |
| stabby lambda | `LambdaNode` | `proc {}` / `lambda {}` already count via `BlockNode` |

Explicitly **free** (+0): `else`, `ensure`, `begin`, `case`/`case-in` shells,
`break`, `next`, `redo`, `retry`, `return`, `defined?`, flip-flops
(`FlipFlopNode`), plain assignments, and pattern internals other than the
`in` clause and its guard.

**Scope boundaries.** `DefNode`, `ClassNode`, `ModuleNode`,
`SingletonClassNode`, and the block of a reportable `define_method` each
start a *new* counting scope. Nothing inside them contributes to the
enclosing method's complexity, and a nested `def` produces its own row
(§5). A `define_method` call inside a method contributes nothing to that
method (not even the `BlockNode` +1 — its block is a method body, not a
control-flow block).

## 7. Coverage attribution — `cov(m)`

All data comes from the file's entry in `coverage.json`. A method's **span**
is `[start_line, end_line]` of its Prism node (for `define_method`, the
block's node).

### 7.1 Coverable units

```
units(m) = relevant_lines(m) + branch_arms(m)
cov(m)   = units(m) > 0 ? hits(m) / units(m)
                        : (called(m) ? 1.0 : 0.0)
```

- **relevant_lines(m)** — lines within the span whose entry in `lines` is an
  `Integer`, and which lie **strictly after the definition header**. The
  header ends at the last line of: the `def` keyword, the parameter list,
  the `=` of an endless method, or the `do` / `{` of a `define_method`
  block. Header lines execute at class-load time, so counting them would
  manufacture coverage. For endless methods, one-line `def x; …; end`, and
  one-line `define_method` blocks, the body shares the header line, so this
  set is empty.
- **branch_arms(m)** — every entry of `branches` whose `report_line` falls
  within the span. The header exclusion does **not** apply: arm counters
  increment only when the arm executes at call time (verified empirically),
  so same-line arms of an endless ternary are safe and required.
- **hits(m)** — relevant lines with counter ≥ 1, plus arms with
  `coverage ≥ 1`.

### 7.2 Invocation-bit fallback

`called(m)` is consulted **only when `units(m) = 0`**: true iff any entry of
`methods` whose `(start_line, end_line)` equals `m`'s span has
`coverage ≥ 1`. Several entries may share one span (dynamic `define_method`
in a loop): any called ⇒ called. No matching entry (e.g. the defining code
never executed) ⇒ not called. The bit is never added as an extra unit for
methods that have line or branch units — that would inflate every multi-line
method (any method with one covered line was necessarily called).

### 7.3 Consequences (normative examples)

- Empty method, called: `cov = 1.0`, CRAP = comp. Never called: `cov = 0`,
  CRAP = comp² + comp (= 2.0 at CC 1).
- `def admin?(u) = u == :admin ? true : audit!` called only via the then
  arm: 0 relevant lines, arms 1/2 ⇒ `cov = 0.5`; at CC 2, CRAP = 2.5.
- A CC-5 method with 3 of 6 units hit: `cov = 0.5`, CRAP = 8.125 — fails.

### 7.4 Ignored code

`lines` entries, `branches[].coverage`, and `methods[].coverage` may be the
string `"ignored"` (SimpleCov `# simplecov:disable` regions and `# :nocov:`
markers). Ignored units are excluded from both `units` and `hits`. A method
is **excluded from the report entirely** when its own `methods` entry has
`coverage == "ignored"`, or when its span has at least one line entry and
every line entry in it is `"ignored"`.

### 7.5 Blind spots (documented, accepted)

Ruby records no branch arms for `&&` / `||` / `and` / `or`, `rescue`
clauses, or iterator blocks — all of which add complexity in §6. A method
can therefore reach `cov = 1.0` with an untested short-circuit, rescue, or
never-iterated block. This is accepted for v1; mutation testing covers it.

## 8. Report and gate

Written to stdout, sorted by CRAP descending, ties by comp descending, then
identity ascending:

```
Method                                    CC     Cov%     CRAP
Billing::Invoice#total                     6     61.9     8.41
Billing::Invoice#finalize!                 4    100.0     4.00
```

- `Method` — the full identity (§5).
- `Cov%` — `cov(m) × 100`, one decimal, round half up.
- `CRAP` — two decimals, round half up.
- The gate compares **unrounded** values: if `max CRAP > 8.0`, print
  `CRAP threshold exceeded: <max to 2dp> > 8.0` to **stderr** and exit 2.
- No rows (nothing to analyze): print `nothing to analyze`, exit 0.

## 9. Conformance fixtures

The fixture corpus is the executable half of this spec.

### 9.1 Complexity fixtures — `test/fixtures/complexity/*.rb`

Valid Ruby files. Every reportable definition carries, on the comment line
immediately above it, an annotation:

```
# cc: <int> [id: <identity>]
```

The conformance harness parses each file and asserts that the set of
produced rows equals the set of annotations: same count, same `comp` per
definition, and — where `id:` is present — the exact identity string.
Definitions that must produce **no** row (§5) carry `# no-row` instead.
An unannotated reportable definition is a defect in the fixture itself.

### 9.2 Coverage fixtures — `test/fixtures/coverage/<case>/`

Each case contains:

- `source.rb` — the analyzed file;
- `coverage.json` — a **real** SimpleCov ≥ 1.0 report for that file
  (generated by running a real suite, then rewriting `meta.root` to `.`),
  never hand-written;
- `expected.json` — `{"rows": [{"id", "cc", "units", "hits", "cov",
  "crap"}...], "excluded": ["<id>"...]}`; `cov`/`crap` to 6 decimals,
  compared with tolerance 1e-6.

The harness resolves `meta.root` against the case directory, attributes
coverage per §7, and asserts rows and exclusions exactly. These cases
exercise §7 only; pipeline behavior (§4) is tested by integration tests,
not fixtures.

## 10. Non-goals (v1)

Configurable threshold, machine-readable output, baseline/regression mode,
mutation analysis, non-Bundler projects, editor integration, monorepo/engine
module grouping, Prolog/Datalog rules engine, JRuby/TruffleRuby.
