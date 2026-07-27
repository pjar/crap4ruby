# Grammar boundary (spec §2): analyzed files parse as Ruby 4.0 grammar via
# Prism.parse's version option. The leading-operator continuation below is
# 4.0-gated — Prism.parse(<this file>, version: "3.4") fails, pinned by
# test/unit/method_extractor_test.rb so a prism upgrade cannot silently
# move the boundary. A 4.1-rejection fixture is deferred until a prism
# release actually gates grammar at 4.1; prism 1.9.0 gates nothing there.
class GrammarBoundary
  # cc: 2 id: GrammarBoundary#continued
  def continued(a)
    x = a
      && :both
    x
  end
end
