require_relative "../test_helper"

# Cases the conformance corpus cannot express (harness limits: one row per
# annotated line, no failure paths).
class MethodExtractorTest < Minitest::Test
  def test_unparseable_source_fails_with_exit_3
    error = assert_raises(Crap4Ruby::Failure) { Crap4Ruby::MethodExtractor.extract("def broken(") }
    assert_equal 3, error.exit_code
    assert_includes error.message, "parse"
  end

  def test_lambda_body_of_define_method_inside_a_method_counts_nowhere_in_the_outer_method
    source = <<~RUBY
      class C
        def outer(flag)
          define_method(flag ? :a : :b, ->(x) { x ? 1 : 2 })
        end
      end
    RUBY
    rows = Crap4Ruby::MethodExtractor.extract(source).to_h { |m| [m.identity, m] }
    # outer: 1 + ternary in the *name argument* only; the lambda node and
    # its body belong to the defined method (spec §6).
    assert_equal 2, rows.fetch("C#outer").comp
    assert_equal 2, rows.fetch("C#define_method@3").comp
  end

  def test_singleton_class_of_non_self_expression_gets_a_singleton_segment
    source = <<~RUBY
      class C
        class << Widget
          def reset
            :done
          end
        end
      end
    RUBY
    rows = Crap4Ruby::MethodExtractor.extract(source)
    assert_equal ["C::(singleton@2).reset"], rows.map(&:identity)
    assert_equal :span_only, rows.first.match_mode
  end

  def test_same_line_nested_defs_produce_two_rows_ordered_by_byte_containment
    rows = Crap4Ruby::MethodExtractor.extract("def outer = (def inner; 1; end)\n")
    by_id = rows.to_h { |m| [m.identity, m] }
    assert_equal %w[#inner #outer], by_id.keys.sort
    inner, outer = by_id.fetch("#inner"), by_id.fetch("#outer")
    assert_equal outer.definition_line, inner.definition_line
    assert inner.inside?(outer), "inner must be byte-contained in outer"
    refute outer.inside?(inner)
  end
end
