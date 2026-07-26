require_relative "../test_helper"

class ReportTest < Minitest::Test
  # Report only reads row.crap / row.cov / row.method — a stand-in keeps
  # this test independent of Attribution's Row.
  FakeMethod = Struct.new(:identity, :comp, :definition_line, keyword_init: true)
  FakeRow = Struct.new(:method, :cov, :crap, keyword_init: true)

  def test_sorts_by_crap_desc_then_comp_desc_then_location
    entries = [
      entry("B#low", comp: 2, line: 5, path: "b.rb", cov: 1.0, crap: 2.0),
      entry("A#high", comp: 3, line: 9, path: "a.rb", cov: 0.0, crap: 12.0),
      entry("A#tie_low_comp", comp: 1, line: 2, path: "a.rb", cov: 1.0, crap: 2.0),
      entry("A#tie_same", comp: 2, line: 1, path: "a.rb", cov: 1.0, crap: 2.0)
    ]
    report = Crap4Ruby::Report.new(entries, excluded_count: 0)
    assert_equal %w[A#high A#tie_same B#low A#tie_low_comp],
                 report.entries.map { |e| e.row.method.identity }
  end

  def test_render_prints_table_footer_and_location
    out = StringIO.new
    entries = [entry("A#a", comp: 6, line: 41, path: "app/a.rb", cov: 0.619, crap: 8.41)]
    Crap4Ruby::Report.new(entries, excluded_count: 2).render(out)
    lines = out.string.lines.map(&:chomp)
    assert_match(/\AMethod\s+CC\s+Cov%\s+CRAP\s+Location\z/, lines[0])
    assert_match(/\AA#a\s+6\s+61\.9\s+8\.41\s+app\/a\.rb:41\z/, lines[1])
    assert_equal "excluded by coverage markers: 2", lines[2]
  end

  def test_render_empty_prints_nothing_to_analyze
    out = StringIO.new
    Crap4Ruby::Report.new([], excluded_count: 0).render(out)
    assert_equal "nothing to analyze\n", out.string
  end

  def test_no_footer_when_nothing_excluded
    out = StringIO.new
    Crap4Ruby::Report.new([entry("A#a", comp: 1, line: 1, path: "a.rb", cov: 1.0, crap: 1.0)],
                          excluded_count: 0).render(out)
    refute_includes out.string, "excluded by coverage markers"
  end

  def test_decimal_rounds_half_up
    # 0.125 is exactly representable; half-even would print 0.12.
    assert_equal "0.13", Crap4Ruby::Report.decimal(0.125, 2)
    assert_equal "2.26", Crap4Ruby::Report.decimal(2.256, 2)
    assert_equal "61.9", Crap4Ruby::Report.decimal(61.9, 1)
    assert_equal "100.0", Crap4Ruby::Report.decimal(100.0, 1)
  end

  def test_decimal_is_exact_for_rational_ties
    # The 8.405 case: as a Float it sits below the tie and would print 8.40.
    assert_equal "8.41", Crap4Ruby::Report.decimal(Rational(8405, 1000), 2)
    assert_equal "33.3", Crap4Ruby::Report.decimal(Rational(100, 3), 1)
    assert_equal "0.5", Crap4Ruby::Report.decimal(Rational(1, 2), 1)
  end

  def test_sort_breaks_full_ties_by_identity
    entries = [
      entry("Z#b", comp: 1, line: 1, path: "a.rb", cov: 1.0, crap: 1.0),
      entry("A#a", comp: 1, line: 1, path: "a.rb", cov: 1.0, crap: 1.0)
    ]
    report = Crap4Ruby::Report.new(entries, excluded_count: 0)
    assert_equal %w[A#a Z#b], report.entries.map { |e| e.row.method.identity }
  end

  def test_max_crap
    assert_nil Crap4Ruby::Report.new([], excluded_count: 0).max_crap
    report = Crap4Ruby::Report.new(
      [entry("A#a", comp: 1, line: 1, path: "a.rb", cov: 0.5, crap: 8.125)],
      excluded_count: 0
    )
    assert_in_delta 8.125, report.max_crap
  end

  private

  def entry(identity, comp:, line:, path:, cov:, crap:)
    Crap4Ruby::Report::Entry.new(
      row: FakeRow.new(method: FakeMethod.new(identity: identity, comp: comp, definition_line: line),
                       cov: cov, crap: crap),
      path: path
    )
  end
end
