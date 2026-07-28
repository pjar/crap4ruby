require_relative "../test_helper"

# §11.3 unit coverage: the freshness scope's lexical containment rule, the
# classification/precedence table, and the diagnostic escaping that keeps a
# hostile path or identity on one line.
class RatchetTest < Minitest::Test
  Ratchet = Crap4Ruby::Ratchet
  Baseline = Crap4Ruby::Baseline

  def test_full_scope_covers_every_row_including_vanished_paths
    scope = Ratchet::Scope.full
    assert scope.include?("lib/gone.rb")
    assert scope.include?("anything")
  end

  # Containment is the directory plus "/" as a byte prefix — never a
  # filesystem question, and never a bare prefix match.
  def test_directory_containment_is_lexical_and_requires_the_separator
    scope = Ratchet::Scope.new(paths: ["lib/kept.rb"], directories: ["app/models"])
    assert scope.include?("lib/kept.rb")
    assert scope.include?("app/models/order.rb")
    assert scope.include?("app/models/deep/nested.rb")
    refute scope.include?("app/models_extra/order.rb")
    refute scope.include?("app/models")
    refute scope.include?("lib/other.rb")
  end

  def test_new_worsened_and_grandfathered_classification
    baseline = baseline_of([stored("lib/a.rb", "A#worse", 1, comp: 3, units: 10, hits: 1),
                            stored("lib/a.rb", "A#same", 2, comp: 3, units: 9, hits: 0)])
    current = [current_row("lib/a.rb", "A#worse", 1, comp: 3, units: 9, hits: 0),
               current_row("lib/a.rb", "A#same", 2, comp: 3, units: 9, hits: 0),
               current_row("lib/a.rb", "A#fresh", 3, comp: 3, units: 9, hits: 0)]
    ratchet = Ratchet.new(baseline: baseline, current_rows: current, scope: Ratchet::Scope.full)
    assert_equal ["baseline: worsened A#worse (lib/a.rb:1) CRAP 12.00 > 9.56 baselined",
                  "baseline: new offender A#fresh (lib/a.rb:3) CRAP 12.00"],
                 ratchet.diagnostics
    assert_equal 2, ratchet.exit_code
  end

  def test_stale_outranks_new_and_an_out_of_scope_row_is_never_checked
    baseline = baseline_of([stored("lib/gone.rb", "G#g", 1, comp: 3, units: 10, hits: 1),
                            stored("lib/unchecked.rb", "U#u", 1, comp: 3, units: 10, hits: 1)])
    current = [current_row("lib/a.rb", "A#fresh", 3, comp: 3, units: 9, hits: 0)]
    scope = Ratchet::Scope.new(paths: ["lib/a.rb", "lib/gone.rb"])
    ratchet = Ratchet.new(baseline: baseline, current_rows: current, scope: scope)
    assert_equal ["baseline: new offender A#fresh (lib/a.rb:3) CRAP 12.00",
                  "baseline: stale row G#g (lib/gone.rb:1) — no longer failing here; run --update-baseline"],
                 ratchet.diagnostics
    assert_equal 3, ratchet.exit_code
  end

  def test_no_findings_exits_zero
    baseline = baseline_of([stored("lib/a.rb", "A#a", 1, comp: 3, units: 9, hits: 0)])
    current = [current_row("lib/a.rb", "A#a", 1, comp: 3, units: 9, hits: 0)]
    ratchet = Ratchet.new(baseline: baseline, current_rows: current, scope: Ratchet::Scope.full)
    assert_empty ratchet.diagnostics
    assert_equal 0, ratchet.exit_code
  end

  # A hostile filename must not be able to break the one-line format.
  def test_control_bytes_and_backslashes_are_escaped_in_diagnostics
    identity = "A#" + %w[5c 09 0a 0d 01].map { |byte| byte.hex.chr }.join
    path = "lib/we#{1.chr}ird.rb"
    ratchet = Ratchet.new(baseline: baseline_of([]),
                          current_rows: [current_row(path, identity, 1, comp: 3, units: 9, hits: 0)],
                          scope: Ratchet::Scope.full)
    assert_equal ['baseline: new offender A#\\\\\t\n\r\x01 (lib/we\x01ird.rb:1) CRAP 12.00'],
                 ratchet.diagnostics
  end

  private

  def baseline_of(rows) = Baseline.new(rows, "crap4ruby-baseline.json")

  def stored(path, identity, line, comp:, units:, hits:, called: false)
    Baseline::Row.new(path: path, identity: identity, line: line,
                      comp: comp, units: units, hits: hits, called: called)
  end
  alias current_row stored
end
