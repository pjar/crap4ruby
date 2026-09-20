# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-09-20

First public release, implementing [spec.md](spec.md) 0.4. The spec plus the
conformance fixture corpus under `test/fixtures/` is the normative contract.

### Added

- CRAP score gate: `CRAP(m) = comp(m)² × (1 − cov(m))³ + comp(m)` per method,
  failing the run when any method exceeds the fixed, non-configurable
  threshold of 8.0 (spec §1, §8).
- Cyclomatic complexity via a Prism visitor with normative node
  classification, including deliberate deviations from RuboCop counting:
  every safe-navigation call and every block counts (spec §6).
- Coverage attribution from SimpleCov ≥ 1.0 `coverage.json`: line and branch
  units with innermost-span ownership, declaration-line exclusion, an
  invocation-bit fallback for zero-unit methods, and ignore-marker exclusion
  surfaced in the report footer (spec §7).
- CLI: analyze `app/` and `lib/` by default or explicit paths;
  `--changed` (git-changed files), `--no-run` (trusted-artifact mode with
  clean-tree, commit, and source verification), `--test-command`,
  `--coverage-file`, `--help`, and `--version` (spec §3, §4).
- Analyzed-grammar pin: source is parsed as Ruby 4.0 grammar regardless of the
  running interpreter, with a normative upgrade policy (spec §2, CRA-46).
- Baseline ratchet for legacy adoption (spec §11, CRA-45, CRA-51): a
  `crap4ruby-baseline.json` in the project root grandfathers the offenders it
  lists, fails new and worsened ones (exit 2), and demands
  `--update-baseline` for rows that went stale (exit 3).
  `--update-baseline` performs a full run and rewrites the file in canonical
  bytes, shrink-only — a write that would add or worsen a row is refused
  (exit 2) with the file untouched. With no baseline present, behavior is
  byte-for-byte unchanged.
- Parallel-coverage mismatch detection (spec §4.3/§11.4, CRA-49): when the
  detected test command is `bin/rails test`, the test tree declares
  `parallelize`, and `.simplecov` does not literally set
  `merge_subprocesses true`, a pinned one-line stderr warning fires
  (non-fatal — SimpleCov silently drops worker coverage in that
  configuration, degrading the report to boot-only data). The same
  statically-evaluated predicate makes every coverage-consuming
  `--update-baseline` invocation refuse with exit 3 and the baseline
  untouched: a baseline built from garbage coverage is irreversible,
  reviewed damage.
- Deterministic report sorted by CRAP descending with total-order
  tie-breakers, rendered with exact Rational arithmetic and half-up rounding
  (spec §8).
- Exit codes: 0 ok, 1 usage error, 2 threshold exceeded, 3 coverage
  unavailable or invalid, 4 test command failed (spec §3).
- Test-command detection with preflight checks for RSpec, Rails, and Rake
  layouts, executing under `bundle exec simplecov run` (spec §4.3).
- Conformance corpus: annotated complexity fixtures and real-SimpleCov
  coverage cases as the executable half of the contract (spec §9).
- devenv-only development toolchain (see AGENTS.md).

### Changed

- Cyclomatic complexity: `def` receiver expressions now count in the
  enclosing method, mirroring the `define_method` scope-boundary rule
  (spec §6, CRA-43).
- Cyclomatic complexity: safe navigation fused into assignments (`a&.b ||= x`,
  `a&.b &&= x`, `a&.b += x`) and call targets now counts the `&.` flag on the
  write/target node, additively with the assignment's own contribution
  (spec §6, CRA-42).
- Report identity: `define_method` in lexical singleton scope (`class <<
  self` / `class << <expr>`) reports with a dot separator, matching sibling
  `def`s there; display-only, attribution unaffected (spec §5, CRA-43).

### Fixed

- Gemspec file list: an empty `git ls-files` result (tree sitting untracked
  inside an unrelated repository) now falls back to the glob list instead of
  packaging an empty gem (CRA-40).
- README: the documented `.simplecov` setup now includes
  `merge_subprocesses true` — without it, Rails' default process-parallel
  testing silently discards worker coverage and crap4ruby gates on boot-only
  data; a troubleshooting note names the symptom and warns off the serial
  `PARALLEL_WORKERS=1` workaround (docs only, CRA-48).
