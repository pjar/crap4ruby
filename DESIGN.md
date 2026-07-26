# crap4ruby — implementation design

Status: reviewed (2026-07-26; Codex gpt-5.6-sol, high effort — 6 blocking
findings and 10 gaps, all triaged into this revision and spec 0.3).
Contract lives in [spec.md](spec.md); this document describes *how* the
implementation meets it. Where this document and spec.md disagree, spec.md
wins.

## 1. Shape

A single gem, no runtime dependencies beyond `prism` (~> 1.9, declared
explicitly so CRuby 3.3's bundled 0.19 is never used — the node API is
normative in §6 and drifted before Prism 1.0) and `json`. One executable,
`exe/crap4ruby`, that does `exit Crap4Ruby::CLI.run(ARGV, stdout:, stderr:)`.

```
lib/crap4ruby.rb                  requires + VERSION
lib/crap4ruby/cli.rb              option parsing, orchestration, exit codes
lib/crap4ruby/project.rb          root discovery, file selection, --changed
lib/crap4ruby/test_runner.rb      §4.3 detection, preflight, execution, §4.1 cleanup
lib/crap4ruby/coverage_report.rb  §4.4 load + validate, meta.root resolution, per-file lookup
lib/crap4ruby/method_extractor.rb §5+§6 Prism visitor → MethodInfo list
lib/crap4ruby/method_info.rb      identity, span, comp, declaration lines (value object)
lib/crap4ruby/attribution.rb      §7 ownership, units, hits, invocation bit, ignores
lib/crap4ruby/row.rb              cov, CRAP, formatting-ready values
lib/crap4ruby/report.rb           §8 rendering, sort, footer, gate
```

### Error / exit-code strategy

One exception class, `Crap4Ruby::Failure(message, exit_code)`, raised from
anywhere in the pipeline; `CLI.run` rescues it, prints the message to stderr,
returns the code. Exit 2 (gate) and exit 0 are normal returns, not
exceptions. Exit 4 carries the child's status line. Every exit path is
therefore testable as a return value — no `Kernel#exit` outside `exe/`.

All I/O goes through injected `stdout`/`stderr` so tests never capture
globals.

## 2. Extraction — one Prism pass per file (§5, §6)

`MethodExtractor` subclasses `Prism::Visitor` and maintains two stacks:

- **Scope stack** — lexical constant path segments plus flags:
  `ClassNode`/`ModuleNode` push their constant path; `SingletonClassNode`
  pushes singleton-ness; `Class.new`/`Module.new`/`Struct.new`/`Data.define`
  blocks push `(anon@<line>)`. Identity is derived per §5 from this stack at
  the definition site.
- **Counting stack** — the `MethodInfo` currently accumulating complexity.
  `DefNode` and reportable `define_method` bodies push; `ClassNode`,
  `ModuleNode`, `SingletonClassNode` push a *null context* (class-body
  complexity is discarded but traversal continues, so nested defs are found).

Node handling:

- `visit_def_node`: build identity (receiver analysis per §5), record span =
  node start/end lines, declaration line = `def` keyword line, comp starts
  at 1; visit parameters (defaults count into this context — §6) and body.
- `define_method` / `define_singleton_method` `CallNode`s: receiver and
  argument expressions are visited in the *enclosing* context first; then,
  if the body is statically visible (block, or literal lambda as positional
  arg), a new `MethodInfo` is pushed and only the body's inner statements
  are visited inside it. The body's own `BlockNode`/`LambdaNode` is counted
  in **neither** context ("counts nowhere", §6 + fixture 09: `from_lambda`
  is cc 1).
- +1 dispatch is a flat `case node` over the §6 table. `WhenNode` adds
  `conditions.length`. `elsif` arrives as a nested `IfNode` in Prism, so
  chains count naturally. `CallNode` adds 1 when `safe_navigation?`.
- Blocks/lambdas: +1 to the current context, then traversal continues in the
  same context (blocks are transparent for identity and counting except the
  four anon-scope constructors and reportable bodies).
- Non-reportable definers (`attr_*`, `alias*`, string `*_eval`, dynamic-body
  `define_method`) produce no row; their argument expressions still count
  in the enclosing context (they execute there).

Outside any counting context (class bodies, top level), +1 nodes hit the
null context and are discarded.

## 3. Attribution (§7)

Per analyzed file, `Attribution` receives the `MethodInfo` list and the
file's coverage entry.

**Ownership** (§7.0): line numbers cannot order same-line nestings
(`def outer; def inner; 1; end; end`), so `MethodInfo` carries the span in
byte offsets too. Per unit (relevant line or branch arm): candidates are
the methods whose line span contains the unit's line; drop every candidate
that strictly byte-contains another candidate; one left → owner, several →
sibling ambiguity → `Failure` exit 3, zero → unowned. The check runs only
for lines that would actually become units — a line that is a declaration
line of every candidate is exempt (this is what lets same-line endless
sibling `def`s pass, per the mixed_forms fixture).

**Units** (§7.1): per method —
- relevant lines: owned lines whose `lines[i]` is Integer, minus the
  declaration-line set (def/call start line + body-opening `do`/`{`/`->`
  line when different);
- branch arms: `branches` entries whose `report_line` is owned by the
  method (no declaration exclusion);
- hits: counters ≥ 1. `"ignored"` entries are dropped from both sides
  (§7.4) but remembered pre-ignore for the exclusion rule.

**Invocation bit** (§7.2): only when `units == 0`. `methods` entries are
parsed once into `(scope, bare_name, span)`; matching per §7.2 (static
name+span; span-only for `@line` pseudo-methods and `(anon@…)`/
`(singleton@…)` identities). SimpleCov collapses `.` to `#`, so comparison
uses scope + bare name, never the separator.

**Exclusion** (§7.4): a method is excluded (footer-counted) when all its
matching `methods` entries say `"ignored"`, or its non-empty pre-ignore
unit set is entirely `"ignored"`.

## 4. Pipeline (§2–§4)

`CLI.run` — parse options (hand-rolled loop over a five-flag surface;
OptionParser's error text and exit behavior are not worth adapting),
then:

1. `Project.root` — walk up from CWD to the nearest `Gemfile` (exit 1 if
   none). File selection: explicit paths (CWD-relative, exit 1 when
   missing), else `app/`+`lib/` globs; `--changed` intersects with
   `git status --porcelain=v1 -z` parsing per §3 (NUL tokenizer that
   consumes the extra origin-path token for `R`/`C`). Selection is sorted,
   deduped, absolute internally; reported relative to project root.
2. Empty selection → `nothing to analyze`, exit 0 — before cleanup/run.
3. Normal mode: delete report + sibling `.resultset.json` (files only;
   failure = exit 3), detect test command per §4.3 table (preflight via
   `Gemfile.lock` grep / executable bit), run
   `bundle exec simplecov run -- <argv|sh -c cmd>` from the project root
   with `Bundler.with_unbundled_env` so crap4ruby's own bundle never leaks
   into the analyzed project. Child failure → exit 4 with its status.
4. `--no-run`: clean-tree check, `meta.commit == HEAD`, logical-line
   `source` comparison — each failure names its check, exit 3.
5. `CoverageReport.load` — JSON parse, `schema_version` 1.x gate, the three
   criteria flags (fail-closed with the remedial snippet from §4.4),
   structural validation of only-consumed fields, ISO 8601 timestamp parse.
   Lookup: absolute analyzed path → key resolved against resolved
   `meta.root`. Missing analyzed file → exit 3.
6. Extract → attribute → rows → report on stdout → gate on unrounded max
   (message to stderr, exit 2).

## 5. Numbers and rendering (§8)

`cov`/`CRAP` are **Rationals** end to end — `Rational(hits, units)` and
`comp² × (1 − cov)³ + comp` are exact, so the gate comparison and half-up
display rounding have no binary-representation ties (`8.405` renders as
`8.41`, always). Display rounding scales by 10^places, rounds the Rational
half-up to an integer, and reassembles the decimal string.
Columns: Method padded to the longest identity (min: header width), CC/Cov%/
CRAP right-aligned, two spaces before Location (`<relpath>:<line>`). Sort:
CRAP desc, comp desc, path asc, line asc — total and deterministic.

## 6. Testing

- **Conformance (fixtures)** — `test/conformance/complexity_test.rb` parses
  `# cc:`/`# no-row` annotations (§9.1) and diffs against extractor output;
  `coverage_test.rb` runs each `test/fixtures/coverage/<case>` through
  attribution and compares `expected.json` at 1e-6 (§9.2).
- **Unit** — CLI parsing/exit codes, porcelain parsing (incl. renames,
  NUL names), report validation failures one by one, rounding edges,
  invocation-bit matching table.
- **Integration** — a minimal sample project fixture (Gemfile, minitest
  suite, SimpleCov config) exercised end-to-end inside the devenv shell:
  normal run, `--no-run` happy + dirty-tree, exit 2 and 4 paths. These are
  the only tests that shell out.
- Runner: minitest + rake (dev deps only), `devenv shell -- bundle exec
  rake` as the single entry point; enterTest in devenv.nix runs the same.

## 7. Review resolutions (Codex gpt-5.6-sol, high, 2026-07-26)

1. Ownership: AST nodes never partially overlap in byte space, but line
   projections do — ownership therefore resolves on byte extents (§3
   above). The greatest-start-line heuristic was rejected.
2. Declaration lines: call-start line + `->`/`do`/`{` token line when
   different is sufficient; parameter continuation and body lines stay
   honest units (they execute at invocation).
3. `--test-command`: no normalization — spawn the argv vector
   `["bundle","exec","simplecov","run","--","sh","-c",cmd]`, never
   re-concatenate into a shell string.
4. Option parsing: keep the hand-rolled loop; the five-flag surface does
   not justify OptionParser's behavior grafting. Equals-forms are accepted
   as a convenience.
5. Prism floor stays `~> 1.9` — the version actually validated by the
   corpus; CI must run the corpus on every supported CRuby.
6. Rounding: Rational, not Float or BigDecimal (see §5).

Further review outcomes: simplecov ≥ 1.0 preflight before running (exit 1);
Prism parse failure of an analyzed file → exit 3; `class << <non-self>` →
`(singleton@<line>)` scope segment; report sort gains an identity
tie-breaker; ignore-exclusion guards against vacuous `all?`; structural
validation rejects inverted spans and colliding coverage keys. All folded
into spec 0.3.
