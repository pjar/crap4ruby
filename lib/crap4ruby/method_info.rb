module Crap4Ruby
  # One reportable method (spec §5) with its complexity (§6) and the line
  # data attribution needs (§7).
  #
  # definition_line — where the `def` keyword or define_method call starts;
  #   used in the report and the (file, identity, line) row key.
  # span — [start_line, end_line] of the owning Prism node; for
  #   define_method/define_singleton_method, of the block or lambda body.
  # span_byte_start/span_byte_end — the same span in byte offsets. Line
  #   numbers alone cannot order nested or sibling definitions that share
  #   lines (`def outer; def inner; end; end`), so §7.0 ownership resolves
  #   containment on bytes.
  # declaration_lines — lines excluded from relevant_lines(m) (§7.1).
  # match_mode — :name_and_span for statically named methods,
  #   :span_only for @line pseudo-methods and (anon@…)/(singleton@…)
  #   identities (§7.2).
  # constant_receiver — true for `def <Constant>.name`; the entry scope
  #   reflects runtime constant resolution rather than the receiver as
  #   written, so §7.2 matches these by span and bare name alone.
  MethodInfo = Struct.new(
    :identity, :scope, :bare_name, :definition_line,
    :span_start, :span_end, :span_byte_start, :span_byte_end,
    :declaration_lines, :comp, :match_mode, :constant_receiver,
    keyword_init: true
  ) do
    def span_contains?(line)
      line >= span_start && line <= span_end
    end

    def inside?(other)
      span_byte_start >= other.span_byte_start && span_byte_end <= other.span_byte_end
    end

    # Strict containment: identical spans are siblings, not a nesting.
    def strictly_contains?(other)
      other.inside?(self) && !inside?(other)
    end
  end
end
