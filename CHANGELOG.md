# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-26

Initial release, implementing [spec.md](spec.md) 0.3. The spec plus the
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
  `--coverage-file`, `--help` (spec §3, §4).
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
