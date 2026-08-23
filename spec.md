# crap4ruby specification

Version: 0.4 (final, 2026-08-23; adds the Ruby 4.0 analyzed-grammar pin (§2,
CRA-46), the `--version` flag (§3, CRA-47), def-receiver counting and
`define_method` singleton dot identity (§5/§6, CRA-43), safe-navigation
call-write counting (§6, CRA-42), and the v2 baseline-ratchet design (§11
plus satellite riders, CRA-45). The §11 implementation (CRA-51,
2026-07-28) added three review-driven clarifications: aliasing resolution
by filesystem identity as well as lexical expansion (§11.1), root/ancestor
directory-argument containment (§11.3), and the §4.2 empty-selection
carve-out. The parallel-coverage mismatch (CRA-49, 2026-07-28) added
§4.3's static preflight warning and §11.4's `--update-baseline` refusal.
0.3 was 2026-07-26, revised during implementation after a second external
design review — Codex gpt-5.6-sol, high effort — and implementation
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
- Threshold: **8.0**, not configurable. (v2: with an engaged baseline,
  gate outcomes follow §11.3; the threshold itself is unchanged.)

## 2. Requirements

- CRuby ≥ 3.3 (Prism and `json` as default gems). JRuby/TruffleRuby are
  unsupported: the required branch and method coverage criteria are
  unavailable there.
- Analyzed files are parsed **as Ruby 4.0 grammar**, via `Prism.parse`'s
  `version:` option (`"4.0"`). The two bounds are independent: CRuby ≥ 3.3
  is the *runtime* floor for running the tool, Ruby 4.0 is the *syntax*
  ceiling for analyzed files (a file the project's own runtime cannot
  execute still fails its tests before analysis matters). Syntax beyond
  the pin fails that file's analysis with exit 3 (§4.1). The pin is
  spec-owned: a grammar bump is an explicit revision of this document with
  boundary fixtures (§9.1, fixture 14), never a side effect of a prism
  upgrade. The pin fixes the grammar *mode*, not the parser — prism bug
  fixes within Ruby 4.0 mode still arrive with dependency upgrades, which
  the conformance corpus guards.
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
| `crap4ruby --version` | print exactly `crap4ruby <version>` and a newline to stdout, exit 0 |
| `crap4ruby --update-baseline` | **v2** (§11.4): full run, then rewrite the baseline, shrink-only |

**`--help` and `--version`** short-circuit before project location, so they
work outside a project. When both appear, the first one on the command line
wins. Unknown options remain usage errors even alongside a short-circuit
flag. `--version` has no `-v` alias.

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
any cleanup or test run (§4.1). **v2 (§11):** `--update-baseline` cannot
combine with `--changed` or explicit paths (exit 1) and composes with
`--no-run`; `--coverage-file` resolving to the baseline path is a usage
error (§11.1); an engaged baseline changes the empty-selection rule
(§11.4).

### Exit codes

| Code | Meaning |
|---|---|
| 0 | OK — no method above threshold (including "nothing to analyze"; v2: or every offender grandfathered by an engaged baseline §11.3, or a successful `--update-baseline` run §11.4) |
| 1 | CLI usage error (also: no Gemfile, ambiguous/unavailable test runner) |
| 2 | CRAP threshold exceeded (v2: or new/worsened offenders against an engaged baseline §11.3, or an `--update-baseline` write refused by the shrink rule §11.4) |
| 3 | coverage unavailable or invalid (missing/malformed report, schema mismatch, criteria disabled, stale, analyzed file absent or unparseable, ambiguous same-line definitions, cleanup failure; v2: also a malformed, stale, or metric-mismatched baseline, §11, and an `--update-baseline` refused under §4.3's parallel-coverage mismatch, §11.4) |
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
6. Parse (as Ruby 4.0 grammar, §2), score, report, gate (§5–§8).

**v2 (§11):** with a baseline present, its static validation (§11.2)
runs after file selection but **before step 1's empty-selection check**
(and therefore before cleanup): a malformed baseline fails with exit 3
even when there is nothing to analyze, never costs a test run, and never
deletes anything. §11.4 defines what an empty selection then means for
an engaged baseline.

### 4.2 `--no-run` mode

Never deletes or writes anything (v2 exception: `--update-baseline
--no-run` may write the baseline file — and only it — after every check
below passes, §11.4; with an **empty selection** no coverage artifact is
consumed and §11.4's empty-selection semantics govern alone — the checks
below, which exist to bound trust in the report, do not run).
`--no-run` consumes a **trusted artifact**;
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

**Parallel-coverage mismatch warning.** Rails' generated test helper
declares process-parallel testing (`parallelize`), which SimpleCov's
report only survives with `merge_subprocesses true`; without it the
workers' coverage is silently dropped and the report degrades to
boot-only data that still passes §4.4's structural checks. The mismatch
is detected statically — no runtime signal is consulted. The **mismatch
predicate** holds when all of:

1. no `--test-command` was given — a user asserting the command asserts
   its coverage behavior too;
2. detection selects `bin/rails test`: `test/` exists, `spec/` does
   not, and `bin/rails` exists and is executable. Under `--no-run`,
   where nothing executes, the same three conditions are evaluated
   statically;
3. at least one file matched by `test/**/*.rb` (§3's glob semantics —
   dot-directories are not entered) parses under §2's grammar pin and
   contains a **receiverless call** named `parallelize`. The predicate
   reads *declares*, not *executes*: a call in dead or guarded code
   counts, while comments, string contents, `def parallelize`, calls
   with an explicit receiver, and files that do not parse do not;
4. `<project root>/.simplecov` does not carry **positive syntactic
   proof** of the remedy. Positive proof: the file parses, and among
   the direct statements of the block body of its `SimpleCov.configure`
   call(s) — `configure` called on the constant `SimpleCov` (a leading
   `::` is allowed) with a block — taken in source order across all
   such calls, the **last** receiverless call named
   `merge_subprocesses` exists, has exactly one argument, the literal
   `true`, and no block. A missing, unreadable, or unparseable
   `.simplecov`, or a conditional, indirect, or non-literal setting, is
   not proof — the warning can fire on a project that configures the
   setting elsewhere; the accepted remedy is the canonical line in
   `.simplecov`;
5. the selection is non-empty (an empty selection consumes no coverage;
   §3's early return has already answered).

When the predicate holds, exactly this one line prints to stderr:

```
warning: Rails test configuration declares `parallelize`, but .simplecov does not declare `merge_subprocesses true`; worker coverage may be missing
```

— once per run: after this section's preflight and lockfile checks
succeed, before the child starts; under `--no-run`, after §4.2's
clean-tree check passes, before the report is read. It therefore
precedes any later gate, validation, or child-failure diagnostic, and
never prints on a run that dies in preflight. The warning is not fatal:
stdout, the score path, and every exit code are unchanged. False
negatives are accepted by design (parallelism declared outside
`test/**/*.rb` or via metaprogramming); the only fatal consequence is
§11.4's `--update-baseline` refusal, which shares this predicate.

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
  definitions of the same name produce two rows. v1 does not *enforce*
  uniqueness of the full key — same-line duplicate definitions with equal
  identities can collide, and both rows are kept; under an engaged v2
  baseline such a collision is an analysis failure (§11.5).

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
| safe navigation `&.` | `CallNode`, `CallOrWriteNode`, `CallAndWriteNode`, `CallOperatorWriteNode`, `CallTargetNode` — each with `safe_navigation?` | +1 for **every** `&.` call; no chain discount (deviation from RuboCop, which discounts repeated chains). Assignment fusion keeps the flag on the write/target node — see the additivity rule below |
| any block (`do…end`, `{…}`, numbered params, `it`) | `BlockNode` | blocks are Ruby's loops; **no iterator-method whitelist** (deviation from RuboCop, which counts only recognized iterating methods) |
| block pass (`&blk`, `&:sym`) | `BlockArgumentNode` | |
| stabby lambda | `LambdaNode` | `proc {}` / `lambda {}` already count via `BlockNode`; a literal lambda that **is** a reportable method's body (§5) counts nowhere as a node |

**Rows are additive.** A node matching several rows adds one per match:
`a&.b ||= 1` is a `CallOrWriteNode` with `safe_navigation?` — the `||=`
row plus the `&.` row, +2; `a&.c &&= 2` likewise +2; `a&.d += 3` adds
only the `&.` row (+1), operator-writes being free as their own
operation; `a&.b&.c ||= 1` adds +3 (two `&.` plus `||=`) — no chain
discount through fused nodes; `for a&.b in xs` and `rescue => a&.b`
preserve the flag on `CallTargetNode` (+1 on top of the loop/rescue
row) — the write is skipped when the receiver is nil. Plain `a&.b = 1`
is an ordinary safe `CallNode`, and `a&.b[i] ||= v` counts via its
nested safe `CallNode` plus `IndexOrWriteNode`. The index write/target
nodes also carry the flag structurally, but no valid Ruby sets it
(`a&.[](i) ||= v` does not parse), so they are deliberately not listed
in the `&.` row (CRA-8).

Explicitly **free** (+0): `else`, `ensure`, `begin`, `case`/`case-in` shells,
`break`, `next`, `redo`, `retry`, `return`, `defined?`, flip-flops
(`FlipFlopNode`), plain assignments and operator-writes as their own
operation (rows they independently match — including the `&.` flag —
still add), and pattern internals other than the
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
  (v2: with an engaged baseline, §11.3's classification replaces this
  plain max comparison; its diagnostics and exit precedence apply.)
- No rows (nothing to analyze): print `nothing to analyze`, exit 0.
  (v2: under an engaged baseline, §11.3/§11.4 govern — in-scope stale
  rows still exit 3.)

## 9. Conformance fixtures

The fixture corpus is the executable half of this spec. It covers §§1–10
(the v1 profile); §9.3 enumerates the §11 corpus, implemented in
`test/conformance/ratchet_test.rb`.

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

### 9.3 v2 corpus — baseline ratchet (§11)

*Implemented as `test/conformance/ratchet_test.rb` (CRA-51), keyed to
§11's rules. Listed here so the contract and its executable half stay
enumerated together.* Cases: `new_offender` → 2; `worsened_exact` → 2
(including an exact worsening whose 2-decimal display ties, `8.00 >
8.00 baselined`); `improved_row` → 0 with an `--update-baseline` shrink
follow-up; `stale_row_full_run` → 3; `stale_via_deleted_file` → 3;
`renamed_method_new_plus_stale` → 3 (precedence); `malformed_baseline`
(unknown key, wrong type, duplicate row keys, row recomputing ≤ 8) → 3;
`metric_version_mismatch` → 3; `changed_scoped_ratchet` (rows outside the
freshness scope unchecked); `update_refuses_partial_selection` → 1;
`update_refuses_growth` → 2, file untouched; `update_initial_creation`
→ 0; `update_writes_empty_rows` → 0; `coverage_file_aliases_baseline`
→ 1; `duplicate_row_key_under_ratchet` → 3;
`empty_full_selection_stales_all` → 3 (and → 0 with `rows: []`);
`update_initial_creation_rejects_invalid_rows` → 3;
`changed_dir_composition_keeps_unchanged_offender` → 0 (an unchanged,
still-failing grandfathered row under `--changed <dir>` is NOT stale);
`changed_empty_selection_deletion_goes_stale` → 3. The no-baseline byte-for-byte
guarantee (§11.1) is pinned by exact-output integration tests
(`test/integration/pipeline_test.rb`).

## 10. Non-goals (v1)

Configurable threshold, machine-readable output, baseline ratchet (a v1
non-goal — specified for v2 in §11), mutation analysis, non-Bundler
projects, editor integration, monorepo/engine module grouping,
Prolog/Datalog rules engine, JRuby/TruffleRuby.

## 11. Baseline ratchet (v2)

This section is the normative contract for the v2 baseline ratchet. **v1
implements §§1–10 only**; a conforming v1 build has no baseline behavior,
and §11.1's guarantee pins that. Conformance profiles: *v1* = §§1–10;
*v2* = §§1–10 plus this section. The crap4ruby implementation accompanying
this specification conforms to the v2 profile.

### 11.1 Engagement and the no-baseline guarantee

Ratchet mode engages exactly when `<project root>/crap4ruby-baseline.json`
exists **as a regular file**; a symlink or other non-regular file at
that path neither engages nor is ignored — it is refused, exit 3
(§11.2). No flag enables ratchet mode: the committed file is the
opt-in, and its diffs — creation, shrinkage, deletion — are ordinary
reviewable commits.

When the file is absent, every invocation **not using
`--update-baseline`** behaves **byte-for-byte identically** to a build
without §11: same stdout, same stderr, same exit codes. The surface
additions themselves are the only exceptions: `--help`/usage text
mentions the new flag, and `--update-baseline` itself is accepted (a
§11-less build rejects it as an unknown option, exit 1; with no baseline
present it performs initial creation, §11.4). The baseline is
trusted, reviewable **policy input**, not tamper-proof enforcement:
deleting or hand-editing it is visible in review, and review is the
enforcement boundary.

With an engaged baseline, or whenever `--update-baseline` is given,
resolving `--coverage-file` to the baseline path is a usage error
(exit 1), checked before any cleanup — §4.1's cleanup step must never
be able to delete the baseline. Resolution means lexical path
expansion **plus**, when the resolved path names an existing file,
filesystem identity with the baseline: a case-insensitive spelling or
a path through a symlinked directory must not slip past the guard. With no baseline present and no
`--update-baseline`, the invocation behaves as plain v1 per the
guarantee above.

### 11.2 Baseline file

JSON object:

```json
{
  "schema_version": "1.0",
  "metric_version": 1,
  "rows": [
    { "path": "app/models/order.rb", "identity": "Order#total",
      "line": 41, "comp": 9, "units": 12, "hits": 7, "called": false }
  ]
}
```

- `schema_version` — this file format; `1.0` (accept later `1.x`, reject
  anything else).
- `metric_version` — the **metric contract identifier**, deliberately
  independent of this document's revision number. It increments only when
  a spec change can affect row identity, reportability, `comp`, `units`,
  `hits`, `called`, exclusion, CRAP arithmetic, or the threshold;
  editorial, CLI, and report-format revisions do not move it. The current
  metric version is **1**. Scores across metric versions are not
  comparable: a mismatch is exit 3 in both gate and update modes, and
  the remedy is an Owner-reviewed regeneration in two explicit steps —
  **delete** the baseline, then re-create it with `--update-baseline`
  (initial creation) on a green tree — reviewed as one commit.
- `rows` — the grandfathered offenders. Stored values are the **exact §7
  integer components**, never displayed or rounded scores: CRAP is
  recomputed per §1/§7 in exact arithmetic
  (`cov = units > 0 ? hits/units : (called ? 1 : 0)`), with no Float and
  no decimal parsing anywhere.

Validation — every failure is exit 3, checked before cleanup or test
execution (§4.1): exact key sets (unknown or missing keys rejected;
duplicate JSON member names rejected); types as shown; `path` a
normalized project-root-relative path — no leading `/` and no empty,
`.`, or `..` segments (§11.3's containment and key matching are lexical
byte comparisons, which only the normalized form can satisfy); `comp >= 1`;
`units >= 0`; `0 <= hits <= units`; `units == 0` implies `hits == 0`;
`called` boolean, and `false` whenever `units > 0` (the invocation bit is
never consulted when units exist, §7.2); `line >= 1`; row keys
`(path, identity, line)` unique; every row's recomputed CRAP `> 8` — a
row at or under the threshold has no business being grandfathered.

Canonical serialization (what `--update-baseline` writes) is fully
byte-determined: UTF-8 with LF line endings; every object member and
array element on its own line; two-space indentation per nesting level;
`": "` between key and value; `,` immediately after a member/element
that has a successor; no trailing spaces; an empty array prints as
`[]` on the member's line; top-level keys in the order `schema_version`,
`metric_version`, `rows`; row keys in the order `path`, `identity`,
`line`, `comp`, `units`, `hits`, `called`; rows sorted by
`(path, line, identity)` with byte-wise string comparison; the
top-level `{` is the file's first byte and stands alone on the first
line; a row object's `{` stands alone on its array-element line, its
first member beginning on the next line; closing `]`/`}` on their own
line at the parent's indentation; no blank lines anywhere; integers
rendered as plain decimal digit runs (no sign,
no exponent, no leading zeros); booleans as `true`/`false`; strings
escaped per RFC 8259 using exactly the short escapes `\"` `\\` `\b`
`\f` `\n` `\r` `\t`, `\u00XX` (lowercase hex) for other control
characters, and all other characters emitted verbatim as UTF-8; one
trailing newline after the closing brace. Writes are atomic
(write-temp-then-rename within the project root); a baseline path that
is a symlink or not a regular file is refused with exit 3 in **both**
the read (engagement) and write paths — the artifact is unusable; on
any failure the existing file remains byte-for-byte untouched.

### 11.3 Gate semantics under ratchet

The run, report table, and footer are unchanged (§4, §8). After scoring,
each analyzed row with unrounded CRAP `> 8` is classified:

- **new** — key `(path, identity, line)` absent from the baseline;
- **worsened** — key present and current CRAP `>` the stored components'
  recomputed CRAP (exact comparison);
- **grandfathered** — key present, current CRAP `<=` stored. An
  improvement does not rewrite the baseline (§11.4 does).

Staleness is checked against a **freshness scope**, defined exactly:

- A **full run** (default selection; no `--changed`, no explicit paths)
  freshness-checks *every* baseline row, including rows whose `path` no
  longer exists — deleted and renamed files go stale loudly.
- A **partial run without `--changed`** (explicit paths only): the scope
  is the analyzed files' paths plus, for each explicit **directory**
  argument, every baseline row `path` under that directory — whether or
  not the file still exists. "Under" is decided lexically: the directory
  argument is normalized to a project-root-relative path, and a row is
  under it when its `path` begins with that path followed by `/` — a
  pure byte comparison, no filesystem access or symlink resolution.
  A directory argument that resolves to the project root itself, or to
  an ancestor of it, contains every row: the freshness scope is a full
  run's. (The prefix rule is degenerate there — no normalized row path
  begins with `./` or `../` — so the containment is stated explicitly.)
  This is sound because every existing `.rb` under such a directory *is*
  analyzed (rows inside dot-directories, which §3's glob never enters,
  go stale exactly as they would under a full run), so an in-scope row
  with no reported match is genuinely gone, moved, passing, or newly
  marker-excluded (§7.4). (An explicit *file* argument that does not
  exist is already a usage error, §3.)
- A **`--changed` run** (alone or composed with explicit paths): the
  scope is the analyzed files' paths plus every git-reported deleted
  path and rename origin (restricted to the explicit paths when
  composed) — and nothing else. An unchanged, unanalyzed file is
  **never** freshness-checked, so its grandfathered rows cannot go
  falsely stale under the §3 intersection semantics.

Rows outside the scope are not checked — so **changed-only CI cannot
establish baseline freshness, nor see worsening outside the analyzed
set** (a test-only change can reduce an unchanged method's coverage
without the ratchet examining it); an authoritative full run is
required for both.

A baseline row is **stale** when, within the freshness scope, it no
longer corresponds to a failing row: its file is gone, no reported row
carries its key, or the row at its key no longer exceeds the threshold.

Diagnostics: after the report, every finding prints to stderr, one line
per row, sorted `(path, line, identity)`. In these lines `<path>` and
`<identity>` are rendered with a literal backslash escaped as `\\` and
control bytes escaped (`\n`, `\r`, `\t`; other bytes below 0x20 as
`\xNN`, lowercase hex) so a hostile filename cannot break the one-line
format; all other characters print verbatim. `<2dp>` is §8's half-up
two-decimal rendering:

```
baseline: new offender <identity> (<path>:<line>) CRAP <2dp>
baseline: worsened <identity> (<path>:<line>) CRAP <2dp> > <2dp> baselined
baseline: stale row <identity> (<path>:<line>) — no longer failing here; run --update-baseline
```

Then exactly one exit code, by precedence: any stale → **exit 3**; else
any new/worsened → **exit 2**; else 0. A rename therefore surfaces as a
stale old key plus a new key and exits 3. Two-decimal display can render
an exact worsening as `8.00 > 8.00 baselined`; the comparison is exact,
as in §8's gate.

Rows not exceeding the threshold never consult the baseline: the 8.0
gate is untouched for everything not grandfathered. The ratchet
constrains only per-method scores — splitting an offender into several
sub-threshold methods legitimately clears it (the old row goes stale);
aggregate file or class complexity is out of scope.

### 11.4 `--update-baseline`

`crap4ruby --update-baseline` performs the normal **full** run (default
selection; combining with `--changed` or explicit paths is a usage error,
exit 1 — a partial analysis must never rewrite the baseline), then
rewrites the baseline to exactly the currently-failing rows in canonical
form. It composes with `--no-run` under §4.2's single-write exception.

**Shrink-only.** Against an existing valid baseline the write is refused
(exit 2, file untouched) unless the new row set is a **subset by key**
and every retained key's recomputed CRAP is `<=` its stored value. New
or worsened debt is never baselined — fix it, or the Owner reviews a
deliberate regeneration (§11.5). Stale rows are permitted removals —
that is the point. A consequence stated plainly: a *moved* offender (new
key + stale old key) cannot be migrated by `--update-baseline` alone —
the new key would violate the subset rule; §11.5 gives the remedies.
With no existing file, creation is unrestricted (initial adoption),
except that the rows to be written must satisfy §11.2's own validation —
duplicate keys or any other violation abort with exit 3 and no write; a
written baseline must always re-validate. A malformed or
metric-mismatched existing file is not "initial creation": exit 3.

**Parallel-coverage refusal.** When §4.3's mismatch predicate holds
(evaluated statically, including under `--no-run`), every
coverage-consuming `--update-baseline` invocation refuses — exit 3,
checked after file selection, §11.2's validation, and §11.1's aliasing
guard, before any cleanup, clean-tree check, or test execution, with
any existing baseline byte-for-byte untouched — printing exactly this
one line to stderr, *instead of* §4.3's warning:

```
--update-baseline refused: Rails test configuration declares `parallelize`, but .simplecov does not declare `merge_subprocesses true`; worker coverage may be missing
```

Exit 3, not 2: this is the untrustworthy-coverage-input category, not
new debt. The gate's warning is observational; §11 turns a measurement
into reviewed policy, and initial creation — which the shrink rule
cannot protect — is exactly where boot-only coverage would grandfather
offenders on falsely-measured components. The refusal is uniform across
initial creation and updates: one rule, one audit. The empty-selection
write (`"rows": []`, below) consumes no coverage and is unaffected. The
remedies are the warning's: declare `merge_subprocesses true` in
`.simplecov`, or pass `--test-command`, asserting the command's
coverage behavior.

A successful update exits **0** even though failing rows exist — the
requested outcome is the write; the gate question belongs to the next
ordinary run. It prints no confirmation of its own: the run's report
table is the only stdout, and stderr stays empty on success. An empty
result set writes `"rows": []` (an active ratchet at zero debt; delete
the file to disengage).

Empty selection under an engaged baseline: the run still validates the
baseline **and applies its §11.3 freshness scope** — staleness needs no
analysis, only the baseline and (for `--changed`) git status. An
ordinary run prints `nothing to analyze` to stdout, then exits 3 with
the stale diagnostics on stderr when any in-scope row is stale, else 0.
Consequently: an empty full selection with non-empty `rows` stales
everything (scope = every row); an empty `--changed` selection still
carries git-reported deletions and rename origins, so deleting a
baselined file goes stale even when nothing else changed — §11.3's
deletion clause is live in exactly its motivating scenario; an empty
explicit-directory selection sweeps that directory's rows. An empty
scope exits 0. `--update-baseline` with an empty full selection prints
`nothing to analyze` and writes the empty baseline, exit 0 — including
**initial creation**: with no baseline present it still writes
`"rows": []`, engaging the ratchet at zero debt. §3's untouched
empty-selection early return applies only to **non-update** invocations
without a baseline; there it is byte-for-byte unchanged.

### 11.5 Row keys and accepted brittleness

Keys are `(path, identity, line)` — §8's report key. They are **brittle
by design**: inserting a line above a grandfathered method changes its
key, surfacing as new + stale (exit 3 on a full run) although the code
did not change; renames and moves do the same. Because the shrink rule
is subset-by-key (§11.4), `--update-baseline` alone cannot migrate a
moved key. The accepted remedies are: get the method under the
threshold (always the better exit), or an Owner-reviewed
**regeneration** — delete the baseline and re-create it with
`--update-baseline` in the same change; the two-file diff shows the
migration plainly. This friction is the deliberate price of exact keys
and a strictly shrinking file; a similarity-matching scheme was
rejected as nondeterministic.

Duplicate keys: §5 keeps rows unique by key as a *modeling* rule, but v1
does not enforce it (same-line duplicate definitions can collide). Under
an engaged baseline a duplicate full key among reportable rows is an
analysis failure (exit 3) — the baseline cannot address either row
unambiguously. Zero-unit same-line siblings with distinct identities
remain fine (§7.0).
