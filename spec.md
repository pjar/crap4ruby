# crap4ruby specification

Version: 0.3 (draft, 2026-07-26; revised during implementation after a second
external design review — Codex gpt-5.6-sol, high effort — and implementation
findings; 0.2 was 2026-07-25, 21 findings triaged, see git history). This document plus the fixture corpus under
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

### Roots and path resolution

- **Project root** — the nearest ancestor of the current working directory
  (inclusive) containing a `Gemfile`. No `Gemfile` found: exit 1. Test
  detection, test execution, default analysis paths (`app/`, `lib/`), and the
  default coverage path all resolve against the project root.
- **CLI paths** (`<path...>`, `--coverage-file`) resolve relative to the
  current working directory.
- **`meta.root`** in the coverage report: used as-is when absolute; when
  relative, resolved against the directory containing the report file.
  Coverage file keys resolve against the resolved `meta.root`.

## 3. CLI

| Invocation | Meaning |
|---|---|
| `crap4ruby` | analyze all `.rb` files under `app/` and `lib/` |
| `crap4ruby <path...>` | analyze explicit files; a directory argument means all `.rb` under it |
| `crap4ruby --changed` | analyze only changed `.rb` files (see below) |
| `crap4ruby --no-run` | do not run tests; validate and consume the existing coverage report (§4.2) |
| `crap4ruby --test-command "<cmd>"` | run `<cmd>` under `simplecov run` instead of the detected test command |
| `crap4ruby --coverage-file <path>` | read the coverage report from `<path>` instead of `<project root>/coverage/coverage.json` |
| `crap4ruby --help` | print usage, exit 0 |

**`--changed`** parses `git status --porcelain=v1 -z --untracked-files=all`
(NUL-delimited — robust to unusual filenames; `--untracked-files=all` so new
files inside untracked directories appear individually instead of as one
collapsed `dir/` entry). A path is selected when either status letter is `M`,
`A`, `T`, `R`, `C`, `?`, or any unmerged state (`U` on either side, `AA`,
`DD`); for renames/copies the **destination** path is used. Deletions are
ignored. Only `.rb` paths are kept.

**Composition:** `--changed` with explicit paths means the **intersection**
(changed `.rb` files that lie within the explicit files/directories),
duplicates removed. File selection never narrows the test run — coverage
always comes from the full suite. Directory expansion (the default
`app/`+`lib/` selection and directory arguments) uses `**/*.rb` glob
semantics: dot-directories are not entered, matching SimpleCov's `cover`
globs. `--test-command` with `--no-run` is a usage
error (exit 1). Unknown options and non-existent explicit paths are usage
errors (exit 1). An empty selection (no `.rb` in explicit paths, or an empty
`--changed` set) prints `nothing to analyze` and exits 0 — checked **before**
any cleanup or test run (§4.1).

### Exit codes

| Code | Meaning |
|---|---|
| 0 | OK — no method above threshold (including "nothing to analyze") |
| 1 | CLI usage error (also: no Gemfile, ambiguous/unavailable test runner) |
| 2 | CRAP threshold exceeded |
| 3 | coverage unavailable or invalid (missing/malformed report, schema mismatch, criteria disabled, stale, analyzed file absent or unparseable, ambiguous same-line definitions, cleanup failure) |
| 4 | test command ran and failed |

## 4. Execution pipelines

### 4.1 Normal mode (default)

Strictly in this order:

1. **Validate options**, resolve the project root, **select files**; empty
   selection → `nothing to analyze`, exit 0.
2. **Resolve** the coverage report path: `--coverage-file` if given, else
   `<project root>/coverage/coverage.json`.
3. **Clean**: delete only that file and a sibling `.resultset.json` if
   present. Never delete directories. A deletion failure aborts with exit 3
   (never proceed against a stale artifact).
4. **Run** the test command under coverage (§4.3). If the child exits
   non-zero or dies on a signal: print its status, **do not score**, exit 4.
5. **Read + validate** the report (§4.4).
6. Parse, score, report, gate (§5–§8).

### 4.2 `--no-run` mode

Never deletes or writes anything. `--no-run` consumes a **trusted artifact**;
these checks bound, but cannot eliminate, that trust (coverage configuration
or test changes made after the run are detectable only via the tree/commit
checks below):

- The **entire working tree must be clean**: `git status --porcelain=v1`
  output is empty. Not in a git repository: exit 3.
- `meta.commit` must be non-null and equal to the current `HEAD` SHA. A null
  commit (report generated outside a git checkout) fails validation.
- When a per-file `source` array is present, it must equal the file on disk
  **compared as logical lines**: the file's bytes split on `"\n"`, with one
  trailing empty element removed if the file ends in a newline, must equal
  the array element-for-element. (The JSON array cannot represent a trailing
  newline, so byte-for-byte comparison is deliberately not required.)

Any failure: exit 3 with a message naming the failed check.

### 4.3 Test-command detection and execution

Detection is deterministic, with a preflight check — no fallbacks:

| Layout | Command | Preflight |
|---|---|---|
| `spec/` exists, `test/` does not | `bundle exec rspec` | `Gemfile.lock` lists `rspec-core` |
| `test/` exists and `bin/rails` exists | `bin/rails test` | `bin/rails` is executable |
| `test/` exists, no `bin/rails`, `Rakefile` exists | `bundle exec rake test` | `Gemfile.lock` lists `rake` |
| anything else (both dirs, neither, failed preflight) | refuse: exit 1, ask for `--test-command` | — |

Execution (always from the project root):

- Detected commands run as an argv vector:
  `bundle exec simplecov run -- <argv...>` — no shell interpretation.
- `--test-command "<cmd>"` runs through the system shell:
  `bundle exec simplecov run -- sh -c "<cmd>"` — pipelines, env assignments
  and quoting behave as in `sh`. No preflight (the user asserted the
  command); a failure is exit 4, not 1.
- Both modes first require the analyzed project's `Gemfile.lock` to list
  `simplecov` ≥ 1.0 — otherwise exit 1 before anything runs (the
  `simplecov run` wrapper would fail before the tests start, which would
  otherwise masquerade as exit 4).

### 4.4 Report validation (both modes)

Failures here are exit 3, before any scoring.

- File exists and parses as JSON; `meta.schema_version` is `1.0` (or a later
  1.x — reject 2.x and above).
- `meta.line_coverage`, `meta.branch_coverage`, `meta.method_coverage` are
  all `true`. If not, print the exact remedial snippet:

  ```ruby
  # .simplecov  (configuration only — SimpleCov.start belongs in the test helper)
  SimpleCov.configure do
    enable_coverage :branch
    enable_coverage :method
    cover "app/**/*.rb", "lib/**/*.rb"
  end
  ```

- `meta.timestamp` parses as ISO 8601 (sanity check only — no age gate).
- Structural checks on every consumed field of each analyzed file's entry:
  `lines` is an array of (integer ≥ 0 | `null` | `"ignored"`) whose length
  equals the file's line count; each `branches` entry has integer
  `start_line`/`end_line`/`report_line` within file bounds and `coverage`
  as integer ≥ 0 or `"ignored"`; each `methods` entry has a string `name`,
  integer span within file bounds, and `coverage` as integer ≥ 0 or
  `"ignored"`; when `source` is present its length equals the `lines`
  length.
- Every analyzed file must appear as a key in `coverage` (resolved per §2).
  An analyzed file missing from the report is exit 3 (likely an unloaded
  file without a `cover` pattern, or a SimpleCov filter), never implicit
  zero coverage.
- Every analyzed file's bytes must decode as UTF-8; an undecodable file
  fails here (exit 3), never as an unhandled error downstream.

## 5. Method identity and reportability

A **reportable method** is:

1. Every `def` node (`DefNode`), wherever it appears — top level, class or
   module body, `class << self`, inside another method, inside a block.
2. Every `define_method` / `define_singleton_method` call whose body is
   statically visible: a block, or a literal lambda (`->`) passed as a
   positional argument. With a literal `Symbol` or `String` name it is
   reported under that name; with a dynamic name it is reported once per
   call site as `define_method@<line>` / `define_singleton_method@<line>`
   (the line where the call starts), regardless of how many runtime methods
   the surrounding code creates from it.

Identity format:

- Instance methods: `Scope#name`. Singleton methods: `Scope.name` — from
  `def self.x`, `define_singleton_method`, or a `def` or `define_method` in
  **lexical singleton scope**: the innermost enclosing identity scope at
  the definition site is a `class << …` body. Ordinary blocks and enclosing
  `def`s are transparent and preserve singleton context; a nested `class`/
  `module`/anonymous-constructor body resets to instance context.
- `def <receiver>.name` with a **constant** receiver: `<Receiver>.name`
  exactly as written (`def Widget.reset` → `Widget.reset`). With any other
  non-`self` receiver: `Scope::(singleton@<line>).name` where `<line>` is
  the `def` line.
- `Scope` is the lexical constant path of the nearest enclosing `class` /
  `module` / `class << self` node, joined with `::`. Empty at top level
  (identity is then `#name` / `.name`). `class << <expr>` with a non-`self`
  expression inserts a `(singleton@<line>)` segment (line of the `class <<`
  keyword) and singleton context — analogous to `def <receiver>.name` with
  a non-constant receiver.
- Blocks are transparent for identity except these, which insert a
  `(anon@<line>)` segment (line of the block opening): blocks passed to
  `Class.new`, `Module.new`, `Struct.new`, `Data.define` (bare or
  `::`-prefixed; a qualified path such as `Foo::Struct.new` names a
  different constant and stays transparent). A `def` inside
  any other block uses the nearest enclosing named scope unchanged.
- Rows are unique by **(file path, identity, definition line)**. Two
  definitions of the same name produce two rows.

Identity is lexical — recorded exactly as written, never resolved through
the runtime. Where SimpleCov's runtime naming diverges from it (a top-level
`def` reports under `Object`; a constant receiver reports under the class
the constant resolved to), the divergence is handled at matching time
(§7.2), not in the identity.

Not reportable (no row, ever): `attr_reader` / `attr_writer` /
`attr_accessor`, `alias` / `alias_method`, `class_eval` / `module_eval` /
`instance_eval` with string arguments, and `define_method` /
`define_singleton_method` whose body is not statically visible (a variable
holding a proc, a method reference) — no static body, nothing to count.

Methods excluded by coverage ignore markers are removed from the report and
counted in its footer (§7.4, §8). Everything else that is reportable and
analyzed must produce exactly one row.

## 6. Cyclomatic complexity

`comp(m)` starts at **1** and adds **1** for each node below occurring in
`m`'s own body **or parameter default-value expressions** (defaults execute
at invocation time, not load time). Prism node types are normative:

| +1 per occurrence | Prism node | Notes |
|---|---|---|
| `if`, `elsif`, modifier `if`, ternary, pattern guard | `IfNode` | an `if/elsif/else` chain of k conditions counts k; `else` is free |
| `unless` (incl. modifier) | `UnlessNode` | |
| `while`, `until` (incl. modifiers), `for` | `WhileNode`, `UntilNode`, `ForNode` | |
| each **condition** of a `when` clause | `WhenNode` | `when a, b, c` counts 3 — the conditions test sequentially, like short-circuit alternatives; the `case` itself is free |
| each `in` clause | `InNode` | a guard adds its own `IfNode`/`UnlessNode` |
| each pattern alternation | `AlternationPatternNode` | `in :a \| :b` counts the `in` plus one per `\|` |
| each `rescue` clause | `RescueNode` | `else`/`ensure` are free |
| modifier rescue (`x rescue y`) | `RescueModifierNode` | |
| `&&`, `and` | `AndNode` | |
| `\|\|`, `or` | `OrNode` | |
| `\|\|=` (all receivers) | `LocalVariableOrWriteNode`, `InstanceVariableOrWriteNode`, `ClassVariableOrWriteNode`, `GlobalVariableOrWriteNode`, `ConstantOrWriteNode`, `ConstantPathOrWriteNode`, `CallOrWriteNode`, `IndexOrWriteNode` | constant forms cannot appear inside method bodies (dynamic constant assignment is a SyntaxError) but are listed for class-body completeness |
| `&&=` (all receivers) | `LocalVariableAndWriteNode`, `InstanceVariableAndWriteNode`, `ClassVariableAndWriteNode`, `GlobalVariableAndWriteNode`, `ConstantAndWriteNode`, `ConstantPathAndWriteNode`, `CallAndWriteNode`, `IndexAndWriteNode` | |
| safe navigation `&.` | `CallNode` with `safe_navigation?` | +1 for **every** `&.` call; no chain discount (deviation from RuboCop, which discounts repeated chains) |
| any block (`do…end`, `{…}`, numbered params, `it`) | `BlockNode` | blocks are Ruby's loops; **no iterator-method whitelist** (deviation from RuboCop, which counts only recognized iterating methods) |
| block pass (`&blk`, `&:sym`) | `BlockArgumentNode` | |
| stabby lambda | `LambdaNode` | `proc {}` / `lambda {}` already count via `BlockNode`; a literal lambda that **is** a reportable method's body (§5) counts nowhere as a node |

Explicitly **free** (+0): `else`, `ensure`, `begin`, `case`/`case-in` shells,
`break`, `next`, `redo`, `retry`, `return`, `defined?`, flip-flops
(`FlipFlopNode`), plain assignments, and pattern internals other than the
`in` clause, its guard, and alternations.

**Scope boundaries.** `DefNode`, `ClassNode`, `ModuleNode`,
`SingletonClassNode`, and the statically visible body of a reportable
`define_method` / `define_singleton_method` each start a *new* counting
scope, and a nested `def` produces its own row (§5). For a `DefNode` the
boundary encloses its parameters and body — parameter defaults count in
the defined method because they execute at invocation time — but **not**
its receiver expression: the receiver belongs to the *current* counting
context, because it is evaluated when the `def` statement runs
(`def (target&.thing).name` inside a method adds the `&.`'s +1 to that
method; in a class body, with no enclosing method, the +1 is discarded).
This is a complexity rule only — §7's line/branch ownership stays
span-based, so a multi-line receiver's units remain owned by the defined
method (§7.0). For a `define_method` call
inside a method, **only the body block/lambda is excluded** — the receiver
and argument expressions execute in the enclosing method and count normally
(`define_method(flag ? :on : :off) do … end` adds the ternary's +1 to the
enclosing method). The four anonymous-scope constructor blocks (§5) are
identity boundaries but **not** counting boundaries: their non-`def`
contents execute when the enclosing code runs and count normally.

## 7. Coverage attribution — `cov(m)`

All data comes from the file's entry in `coverage.json`. A method's **span**
is `[start_line, end_line]` of its Prism node (for `define_method` /
`define_singleton_method`, of the block or lambda node itself — this is the
span SimpleCov records for such methods).

### 7.0 Ownership

Every line and branch arm belongs to **at most one method: the innermost
reportable span containing it**. Lines and arms inside a nested reportable
definition never count toward the enclosing method (mirroring §6's scope
boundaries — otherwise tests of a nested `def` would inflate the outer
method's coverage). One deliberate asymmetry: a `def` receiver expression
counts toward the enclosing method's *complexity* (§6), while its lines
and branch arms — lying inside the `def` span — stay owned by the defined
method; ownership is purely span-based.
Nesting is decided by node containment (byte extent),
not line numbers — `def outer; def inner; 1; end; end` is a nesting, not a
sibling pair. If a relevant line or branch arm lies on a line shared by two
or more **sibling** (non-nested) reportable spans, analysis fails with
exit 3 (`ambiguous same-line definitions`). The failure triggers only when
the shared line would actually yield a unit: an Integer-counter line that
is not a declaration line of every sibling sharing it, or a branch arm
reported on it. Zero-unit same-line definitions are fine — their
invocation bits are joined by name (§7.2).

### 7.1 Coverable units

```
units(m) = relevant_lines(m) + branch_arms(m)
cov(m)   = units(m) > 0 ? hits(m) / units(m)
                        : (called(m) ? 1.0 : 0.0)
```

- **relevant_lines(m)** — lines owned by `m` (§7.0) whose entry in `lines`
  is an `Integer`, excluding the **declaration line(s)**: the line where the
  `def` keyword or the `define_method` / `define_singleton_method` call
  begins, plus the line of the body-opening `do` / `{` / `->` when
  different. Declaration lines execute at class-load time, so counting them
  would manufacture coverage. Parameter-list continuation lines are **not**
  declaration lines: default-value expressions execute at invocation time
  (verified empirically), so their counters are honest units. For endless
  methods, one-line `def x; …; end`, and one-line blocks, the body shares
  the declaration line, so this set is empty.
- **branch_arms(m)** — every entry of `branches` whose `report_line` is
  owned by `m` (§7.0). The declaration-line exclusion does **not** apply:
  arm counters increment only when the arm executes at call time (verified
  empirically), so same-line arms of an endless ternary — or of a
  conditional parameter default — are safe and required.
- **hits(m)** — relevant lines with counter ≥ 1, plus arms with
  `coverage ≥ 1`.

### 7.2 Invocation-bit fallback

`called(m)` is consulted **only when `units(m) = 0`**. Entries of `methods`
are parsed as `Scope#name`; SimpleCov **collapses singleton methods into the
same notation** (`def self.build` reports as `Scope#build` — verified
empirically), so the singleton/instance distinction comes from the span, not
the name:

- A method with a static name matches the entry whose parsed scope and bare
  name equal its own **and** whose `(start_line, end_line)` equals its span.
  Two narrow fallbacks bridge entry scopes that are runtime names rather
  than lexical ones (§5): an entry scope of `Object` matches an empty
  extractor scope (a top-level `def` defines an instance method of
  `Object`), and a `def` with a **constant** receiver (`ConstantReadNode` /
  `ConstantPathNode`) matches by exact span and bare name even when the
  scope strings differ (`def Widget.reset` inside `module Outer` reports as
  `Outer::Widget#reset` — verified empirically). The bare-name requirement
  stays load-bearing in both fallbacks: zero-unit same-line siblings share
  a span and are told apart only by name (§7.0). No other form matches on a
  scope mismatch — strict scope comparison remains the canary for extractor
  naming defects.
- A dynamic `define_method@<line>` / `define_singleton_method@<line>`
  pseudo-method matches **every** entry with exactly its body's span
  (several runtime names share one span when defined in a loop): any called
  ⇒ called.
- A method whose identity contains a `(anon@…)` or `(singleton@…)` segment
  matches by exact span only (runtime scope names for anonymous classes are
  unstable).
- No matching entry (e.g. the defining code never executed) ⇒ not called.

The bit is never added as an extra unit for methods that have line or branch
units — that would inflate every multi-line method (any method with one
covered line was necessarily called).

### 7.3 Consequences (normative examples)

- Empty method, called: `cov = 1.0`, CRAP = comp. Never called: `cov = 0`,
  CRAP = comp² + comp (= 2.0 at CC 1).
- `def admin?(u) = u == :admin ? true : audit!` called only via the then
  arm: 0 relevant lines, arms 1/2 ⇒ `cov = 0.5`; at CC 2, CRAP = 2.5.
- A CC-5 method with 3 of 6 units hit: `cov = 0.5`, CRAP = 8.125 — fails.

### 7.4 Ignored code

`lines` entries, `branches[].coverage`, and `methods[].coverage` may be the
string `"ignored"` (SimpleCov `# simplecov:disable` regions and `# :nocov:`
markers — both produce identical `"ignored"` values, verified empirically).

- Ignored units are excluded from both `units(m)` and `hits(m)`.
- A method is **excluded from the report** when every entry of `methods`
  matching it per §7.2 has `coverage == "ignored"`, or when its pre-ignore
  unit set is non-empty and every one of those line and branch units is
  `"ignored"`.
- Excluded methods are counted and surfaced in the report footer (§8) —
  exclusion is visible, never silent.

### 7.5 Blind spots (documented, accepted)

- Ruby records no branch arms for `&&` / `||` / `and` / `or`, `rescue`
  clauses, or iterator blocks — all of which add complexity in §6. A method
  can therefore reach `cov = 1.0` with an untested short-circuit, rescue, or
  never-iterated block. Mutation testing covers this.
- **Ignore markers are a bypass**: wrapping a method in `# :nocov:` /
  `# simplecov:disable` removes it from the gate (§7.4). This respects the
  project's own coverage configuration, as undercover and SimpleCov
  tooling conventionally do; the mitigations are the report footer count
  (a new marker is visible in output and in diff review) and mutation
  testing. Revisit fail-closed handling if abused in practice.
- Code outside reportable methods — class/module bodies, top-level scripts,
  DSL blocks — is not scored, mirroring crap4java's method-only scope. An
  agent could relocate complexity there; class-body code executes at load
  and is conventionally declarative, and review/mutation testing cover it.

## 8. Report and gate

Written to stdout, sorted by CRAP descending, ties by comp descending, then
location (file path, then line) ascending, then identity ascending (a total
order — same-line definitions exist):

```
Method                                    CC     Cov%     CRAP  Location
Billing::Invoice#total                     6     59.4     8.41  app/models/billing/invoice.rb:41
Billing::Invoice#finalize!                 4    100.0     4.00  app/models/billing/invoice.rb:78
```

- `Method` — the full identity (§5); rows are keyed by (file path, identity,
  definition line), so same-named definitions in reopened classes across
  files never merge.
- `Cov%` — `cov(m) × 100`, one decimal, round half up.
- `CRAP` — two decimals, round half up.
- Footer, only when methods were excluded via ignore markers (§7.4):
  `excluded by coverage markers: <N>`.
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
  (generated by running a real suite in the devenv shell, then rewriting
  `meta.root` to `.`), never hand-written;
- `expected.json` — `{"rows": [{"id", "cc", "units", "hits", "cov",
  "crap"}...], "excluded": ["<id>"...]}`; `cov`/`crap` to 6 decimals,
  compared with tolerance 1e-6.

Cases: `basic_attribution` (branches, endless methods, invocation bits,
declaration-line exclusion), `define_method_and_ignored` (literal and
loop-dynamic `define_method`, both ignore-marker forms), `mixed_forms`
(nested `def` ownership, singleton name collapse, same-line definitions,
conditional parameter defaults), `span_matching` (span-only invocation
matching for anon-class and `class << obj` methods against real runtime
names, the any-called rule for a loop-dynamic `define_method`, and the
two §7.4 exclusion clauses firing separately), `runtime_scope_fallbacks`
(the two §7.2 scope fallbacks: a called empty top-level `def` reported as
`Object#…` and a called zero-unit constant-receiver `def` reported under
its runtime class, both scoring cov 1.0 and CRAP = comp per §7.3). The harness resolves `meta.root` against
the case directory, attributes coverage per §7, and asserts rows and
exclusions exactly. These cases exercise §7 only; pipeline behavior (§4) is
tested by integration tests, not fixtures.

## 10. Non-goals (v1)

Configurable threshold, machine-readable output, baseline/regression mode,
mutation analysis, non-Bundler projects, editor integration, monorepo/engine
module grouping, Prolog/Datalog rules engine, JRuby/TruffleRuby.
