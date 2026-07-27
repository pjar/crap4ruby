require_relative "../test_helper"

# Spec §6 makes Prism node types normative: every node type is counted
# (+1), free (+0), or a scope boundary. The prism pin admits future 1.x
# minors, and new Ruby grammar arrives as new node types — an unclassified
# node would silently undercount complexity. This canary fails on any node
# type the classification below has never seen: when it does, classify the
# new node in spec.md §6 first, then here.
class PrismNodeClassificationTest < Minitest::Test
  # +1 per occurrence — derived from the visitor so the two can never
  # drift apart (spec §6 table).
  COUNTED = Crap4Ruby::MethodExtractor::COUNTED
            .map { |type| type.to_s.split("_").map(&:capitalize).join.to_sym }.freeze

  # Bespoke handling in the visitor (spec §6): WhenNode counts one per
  # condition; CallNode counts only with safe_navigation?.
  SPECIAL = %i[WhenNode CallNode].freeze

  # Safe-navigation lvalues (spec §6, CRA-42): assignment fusion keeps the
  # &. flag on these; rows are additive — own row (||=/&&=) plus the flag;
  # operator-writes and targets contribute the flag alone. Derived from the
  # visitor so the two can never drift apart.
  FLAGGED = Crap4Ruby::MethodExtractor::SAFE_NAVIGATION_LVALUES.keys
            .map { |type| type.to_s.split("_").map(&:capitalize).join.to_sym }.freeze

  # Every node class that structurally carries safe_navigation?. The four
  # index forms hold the flag in their layout, but no valid syntax sets it
  # (`a&.[](i) ||= v` does not parse — verified on prism 1.9.0), so they
  # are deliberately not flag-counted (CRA-8 decision record). A new
  # flag-capable node type in a future prism fails this pin: classify it
  # in spec §6 first, then here.
  FLAG_CAPABLE = (%i[CallNode] + FLAGGED + %i[
    IndexOrWriteNode IndexAndWriteNode IndexOperatorWriteNode IndexTargetNode
  ]).freeze

  # Scope boundaries (spec §6): each starts a new counting scope.
  BOUNDARY = %i[DefNode ClassNode ModuleNode SingletonClassNode].freeze

  # Free (+0) under spec §6: structure, literals, reads, plain writes,
  # operator-writes other than ||=/&&=, pattern internals, else/ensure,
  # flow keywords, defined?, and flip-flops. Enumerated at prism 1.9.0.
  FREE = %i[
    AliasGlobalVariableNode AliasMethodNode ArgumentsNode ArrayNode
    ArrayPatternNode AssocNode AssocSplatNode BackReferenceReadNode
    BeginNode BlockLocalVariableNode BlockParameterNode BlockParametersNode
    BreakNode CapturePatternNode
    CaseMatchNode CaseNode ClassVariableOperatorWriteNode ClassVariableReadNode
    ClassVariableTargetNode ClassVariableWriteNode ConstantOperatorWriteNode ConstantPathNode
    ConstantPathOperatorWriteNode ConstantPathTargetNode ConstantPathWriteNode ConstantReadNode
    ConstantTargetNode ConstantWriteNode DefinedNode ElseNode
    EmbeddedStatementsNode EmbeddedVariableNode EnsureNode FalseNode
    FindPatternNode FlipFlopNode FloatNode ForwardingArgumentsNode
    ForwardingParameterNode ForwardingSuperNode GlobalVariableOperatorWriteNode GlobalVariableReadNode
    GlobalVariableTargetNode GlobalVariableWriteNode HashNode HashPatternNode
    ImaginaryNode ImplicitNode ImplicitRestNode IndexOperatorWriteNode
    IndexTargetNode InstanceVariableOperatorWriteNode InstanceVariableReadNode InstanceVariableTargetNode
    InstanceVariableWriteNode IntegerNode InterpolatedMatchLastLineNode InterpolatedRegularExpressionNode
    InterpolatedStringNode InterpolatedSymbolNode InterpolatedXStringNode ItLocalVariableReadNode
    ItParametersNode KeywordHashNode KeywordRestParameterNode LocalVariableOperatorWriteNode
    LocalVariableReadNode LocalVariableTargetNode LocalVariableWriteNode MatchLastLineNode
    MatchPredicateNode MatchRequiredNode MatchWriteNode MissingNode
    MultiTargetNode MultiWriteNode NextNode NilNode
    NoKeywordsParameterNode NumberedParametersNode NumberedReferenceReadNode OptionalKeywordParameterNode
    OptionalParameterNode ParametersNode ParenthesesNode PinnedExpressionNode
    PinnedVariableNode PostExecutionNode PreExecutionNode ProgramNode
    RangeNode RationalNode RedoNode RegularExpressionNode
    RequiredKeywordParameterNode RequiredParameterNode RestParameterNode RetryNode
    ReturnNode SelfNode ShareableConstantNode SourceEncodingNode
    SourceFileNode SourceLineNode SplatNode StatementsNode
    StringNode SuperNode SymbolNode TrueNode
    UndefNode XStringNode YieldNode
  ].freeze

  def test_every_prism_node_type_is_classified
    all = Prism.constants.select { |name| name.to_s.end_with?("Node") } - [:Node]
    classified = COUNTED + SPECIAL + FLAGGED + BOUNDARY + FREE

    unclassified = all - classified
    assert_empty unclassified,
                 "Prism node types this version introduces that spec §6 has never " \
                 "classified: #{unclassified.sort.join(", ")}. Classify them in " \
                 "spec.md §6 (counted, free, or boundary), then here."

    stale = classified - all
    assert_empty stale,
                 "classified node types that no longer exist in prism " \
                 "#{Prism::VERSION}: #{stale.sort.join(", ")} — spec §6 names a " \
                 "node this prism does not define."
  end

  def test_partitions_do_not_overlap
    partitions = { counted: COUNTED, special: SPECIAL, flagged: FLAGGED,
                   boundary: BOUNDARY, free: FREE }
    partitions.to_a.combination(2).each do |(name_a, a), (name_b, b)|
      assert_empty a & b, "#{name_a} and #{name_b} overlap"
    end
  end

  # Completeness against Prism itself: the flag classification above must
  # cover exactly the node classes that define safe_navigation?.
  def test_flag_capable_set_matches_prism
    capable = Prism.constants.select do |name|
      klass = Prism.const_get(name)
      klass.is_a?(Class) && klass < Prism::Node && klass.method_defined?(:safe_navigation?)
    end
    assert_equal FLAG_CAPABLE.sort, capable.sort,
                 "prism #{Prism::VERSION} changed which node types carry " \
                 "safe_navigation? — classify the difference in spec §6 " \
                 "(counted via the flag, or deliberately unreachable), then here."
  end
end
