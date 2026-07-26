require_relative "../test_helper"

class AttributionTest < Minitest::Test
  def test_cov_and_crap_are_exact_rationals
    source = <<~RUBY
      class R
        def multi(a)
          if a > 0
            "pos"
          else
            "neg"
          end
        end
      end
    RUBY
    entry = {
      "lines" => [1, 1, 1, 1, nil, 0, nil, nil, nil],
      "branches" => [
        { "start_line" => 3, "end_line" => 7, "report_line" => 4, "coverage" => 1 },
        { "start_line" => 3, "end_line" => 7, "report_line" => 6, "coverage" => 0 }
      ],
      "methods" => [{ "name" => "R#multi", "start_line" => 2, "end_line" => 8, "coverage" => 1 }]
    }
    row = attribute(source, entry).rows.fetch(0)
    assert_equal 5, row.units
    assert_equal 3, row.hits
    assert_equal Rational(3, 5), row.cov
    assert_equal Rational(282, 125), row.crap # 2² × (2/5)³ + 2, exactly
  end

  def test_branch_arm_on_a_line_shared_by_siblings_is_ambiguous
    source = "class S\n  def a(x) = x ? 1 : 0; def b = 2\nend\n"
    entry = {
      "lines" => [1, 1, nil],
      "branches" => [
        { "start_line" => 2, "end_line" => 2, "report_line" => 2, "coverage" => 1 },
        { "start_line" => 2, "end_line" => 2, "report_line" => 2, "coverage" => 0 }
      ],
      "methods" => []
    }
    error = assert_raises(Crap4Ruby::Failure) { attribute(source, entry) }
    assert_equal 3, error.exit_code
    assert_includes error.message, "ambiguous same-line definitions"
  end

  def test_zero_units_with_no_matching_method_entry_scores_cov_zero_not_excluded
    source = "class V\n  def maybe\n    :x\n  end\nend\n"
    entry = { "lines" => [1, nil, nil, nil, nil], "branches" => [], "methods" => [] }
    result = attribute(source, entry)
    assert_empty result.excluded
    row = result.rows.fetch(0)
    assert_equal 0, row.units
    assert_equal Rational(0), row.cov
    assert_equal Rational(2), row.crap
  end

  def test_zero_unit_same_line_sibling_defs_join_invocation_bits_by_name
    source = "class Z\n  def one_a = 1; def one_b = 2\nend\n"
    entry = {
      "lines" => [1, 1, nil],
      "branches" => [],
      "methods" => [
        { "name" => "Z#one_a", "start_line" => 2, "end_line" => 2, "coverage" => 3 },
        { "name" => "Z#one_b", "start_line" => 2, "end_line" => 2, "coverage" => 0 }
      ]
    }
    rows = attribute(source, entry).rows.to_h { |r| [r.method.identity, r] }
    assert_equal Rational(1), rows.fetch("Z#one_a").cov
    assert_equal Rational(0), rows.fetch("Z#one_b").cov
  end

  # X#a spans 2..3 (decl 2), X#b spans 3..5 (decl 3): line 3 is shared and
  # is not a declaration line of every sibling.
  SHARED_LINE_SOURCE = "class X\n  def a = (1 +\n    2); def b\n    :y\n  end\nend\n"

  def test_ignored_line_shared_by_siblings_belongs_to_no_one
    entry = { "lines" => [1, 1, "ignored", 1, nil, nil], "branches" => [], "methods" => [] }
    result = attribute(SHARED_LINE_SOURCE, entry)
    assert_empty result.excluded
    rows = result.rows.to_h { |r| [r.method.identity, r] }
    assert_equal 0, rows.fetch("X#a").units # the shared ignored line counts for neither sibling
    assert_equal Rational(0), rows.fetch("X#a").cov
    assert_equal Rational(1), rows.fetch("X#b").cov
  end

  def test_integer_counter_on_a_shared_sibling_line_still_raises_ambiguity
    entry = { "lines" => [1, 1, 1, 1, nil, nil], "branches" => [], "methods" => [] }
    error = assert_raises(Crap4Ruby::Failure) { attribute(SHARED_LINE_SOURCE, entry) }
    assert_equal 3, error.exit_code
    assert_includes error.message, "ambiguous same-line definitions"
  end

  def test_single_owner_ignored_lines_still_drive_exclusion
    source = "class W\n  def only\n    :a\n    :b\n  end\nend\n"
    entry = { "lines" => [1, 1, "ignored", "ignored", nil, nil], "branches" => [], "methods" => [] }
    result = attribute(source, entry)
    assert_equal ["W#only"], result.excluded.map(&:identity)
    assert_empty result.rows
  end

  private

  def attribute(source, entry)
    Crap4Ruby::Attribution.call(Crap4Ruby::MethodExtractor.extract(source), entry)
  end
end
