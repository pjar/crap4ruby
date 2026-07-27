require_relative "../test_helper"

# Cases the conformance corpus cannot express (harness limits: one row per
# annotated line, no failure paths).
class MethodExtractorTest < Minitest::Test
  include Crap4Ruby::FixtureHelper

  # §2: the grammar pin must actually reach Prism.parse. Pinned ("4.0") and
  # default parsing are behaviorally identical on prism 1.9.0, so the only
  # non-vacuous check is observing the call itself.
  def test_extract_parses_under_the_pinned_ruby_4_0_grammar
    captured = nil
    original = Prism.method(:parse)
    Prism.define_singleton_method(:parse) do |source, **options|
      captured = options
      original.call(source, **options)
    end
    begin
      Crap4Ruby::MethodExtractor.extract("x = 1\n")
    ensure
      Prism.define_singleton_method(:parse, original)
    end
    assert_equal "4.0", captured[:version]
    assert_equal Crap4Ruby::MethodExtractor::GRAMMAR_VERSION, captured[:version]
  end

  # §2: the boundary fixture's leading-operator continuation is 4.0-gated.
  # If a prism upgrade ever accepts it at "3.4", the fixture stops proving
  # the pin is live and this test fails loudly.
  def test_grammar_boundary_fixture_is_rejected_under_ruby_3_4_grammar
    source = File.read(fixture_path("complexity", "14_grammar_boundary.rb"),
                       encoding: Encoding::UTF_8)
    assert Prism.parse(source, version: "3.4").failure?,
           "the boundary probe must be rejected by pre-4.0 grammar"
    refute Prism.parse(source, version: Crap4Ruby::MethodExtractor::GRAMMAR_VERSION).failure?,
           "the boundary probe must parse under the pinned grammar"
  end

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

  def test_colon_colon_prefixed_anonymous_scope_constructor_gets_an_anon_segment
    source = <<~RUBY
      class C
        THING = ::Struct.new(:a) do
          def t = 1
        end
      end
    RUBY
    rows = Crap4Ruby::MethodExtractor.extract(source)
    assert_equal ["C::(anon@2)#t"], rows.map(&:identity)
    assert_equal :span_only, rows.first.match_mode
  end

  def test_qualified_constructor_path_stays_a_transparent_block
    source = <<~RUBY
      class C
        THING = Foo::Struct.new(:a) do
          def t = 1
        end
      end
    RUBY
    rows = Crap4Ruby::MethodExtractor.extract(source)
    assert_equal ["C#t"], rows.map(&:identity)
    assert_equal :name_and_span, rows.first.match_mode
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
