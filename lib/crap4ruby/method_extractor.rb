module Crap4Ruby
  # One Prism parse + one visit per file: reportable methods (spec §5) with
  # their cyclomatic complexity (spec §6).
  class MethodExtractor
    def self.extract(source, description = "source")
      result = Prism.parse(source)
      if result.failure?
        error = result.errors.first
        raise Failure.new("cannot parse #{description}: #{error.message} (line #{error.location.start_line})", 3)
      end
      visitor = Visitor.new
      result.value.accept(visitor)
      visitor.methods
    end

    # The flat +1 table of §6. WhenNode (+1 per condition), `&.` calls,
    # definer calls and anonymous-scope calls need their own handlers.
    COUNTED = %i[
      if_node unless_node
      while_node until_node for_node
      in_node alternation_pattern_node
      rescue_node rescue_modifier_node
      and_node or_node
      block_node lambda_node block_argument_node
      local_variable_or_write_node instance_variable_or_write_node
      class_variable_or_write_node global_variable_or_write_node
      constant_or_write_node constant_path_or_write_node
      call_or_write_node index_or_write_node
      local_variable_and_write_node instance_variable_and_write_node
      class_variable_and_write_node global_variable_and_write_node
      constant_and_write_node constant_path_and_write_node
      call_and_write_node index_and_write_node
    ].freeze

    # §5: `define_method` reports instance methods, `define_singleton_method`
    # singleton ones — the value is the identity separator.
    DEFINERS = { define_method: "#", define_singleton_method: "." }.freeze

    # §5: blocks passed to these constructors are anonymous class/module
    # bodies, so identity gains an `(anon@<line>)` segment.
    ANONYMOUS_SCOPES = { Class: :new, Module: :new, Struct: :new, Data: :define }.freeze

    class Visitor < Prism::Visitor
      attr_reader :methods

      def initialize
        @methods = []
        # Lexical identity scope (§5): {path:} for class/module/anon bodies,
        # {singleton: true} for `class << …`.
        @scopes = []
        # Counting scope (§6): the MethodInfo accumulating complexity, or nil
        # for a null context (class bodies, top level) whose +1s are dropped.
        @contexts = [nil]
      end

      COUNTED.each do |type|
        define_method("visit_#{type}") do |node|
          bump
          super(node)
        end
      end

      def visit_when_node(node)
        bump(node.conditions.length) # §6: `when a, b, c` counts 3
        super
      end

      def visit_class_node(node)
        in_scope({ path: node.constant_path.slice }, boundary: true) { super }
      end

      def visit_module_node(node)
        in_scope({ path: node.constant_path.slice }, boundary: true) { super }
      end

      # §5: `class << self` only marks the current scope singleton. For any
      # other expression the runtime scope name is as unstable as it is for
      # `def <expr>.name`, so it gets its own `(singleton@<line>)` segment.
      def visit_singleton_class_node(node)
        entry = { singleton: true }
        unless node.expression.is_a?(Prism::SelfNode)
          entry[:path] = "(singleton@#{node.location.start_line})"
        end
        in_scope(entry, boundary: true) { super }
      end

      def visit_def_node(node)
        info = build_def(node)
        @methods << info
        @contexts.push(info)
        visit(node.parameters) # §6: defaults execute at invocation time
        visit(node.body)
        @contexts.pop
      end

      def visit_call_node(node)
        bump if node.safe_navigation? # §6: +1 per `&.`, no chain discount
        if DEFINERS.key?(node.name)
          visit_definer(node)
        elsif (segment = anonymous_scope(node))
          in_scope({ path: segment }, boundary: false) { super }
        else
          super
        end
      end

      private

      # The body is classified before anything is visited: it must not be
      # traversed in the enclosing context, and its own BlockNode/LambdaNode
      # must not be counted there either.
      def visit_definer(node)
        body = definer_body(node)
        # §6: receiver and argument expressions execute in the enclosing
        # method — only the body is carved out.
        visit(node.receiver)
        node.arguments&.arguments&.each { |argument| visit(argument) unless argument.equal?(body) }
        if body.nil?
          visit(node.block) # no static body (§5); a `&blk` pass still counts
          return
        end

        info = build_definer(node, body)
        @methods << info
        @contexts.push(info)
        # The body's own BlockNode/LambdaNode counts in neither context (§6).
        visit(body.parameters)
        visit(body.body)
        @contexts.pop
      end

      # §5: a block, or a literal lambda passed as a positional argument.
      # Anything else (a variable holding a proc, `&blk`) has no static body.
      def definer_body(node)
        block = node.block
        return block if block.is_a?(Prism::BlockNode)
        return nil unless block.nil?
        node.arguments&.arguments&.find { |argument| argument.is_a?(Prism::LambdaNode) }
      end

      def build_def(node)
        line = node.location.start_line
        name = node.name.to_s
        scope, separator = def_scope(node, line)
        MethodInfo.new(
          identity: "#{scope}#{separator}#{name}",
          scope: scope,
          bare_name: name,
          definition_line: line,
          span_start: line,
          span_end: node.location.end_line,
          span_byte_start: node.location.start_offset,
          span_byte_end: node.location.end_offset,
          declaration_lines: [line],
          comp: 1,
          match_mode: anonymous?(scope) ? :span_only : :name_and_span
        )
      end

      def def_scope(node, line)
        case node.receiver
        when nil then [scope_path, singleton_scope? ? "." : "#"]
        when Prism::SelfNode then [scope_path, "."]
        when Prism::ConstantReadNode, Prism::ConstantPathNode then [node.receiver.slice, "."]
        else [qualify("(singleton@#{line})"), "."]
        end
      end

      def build_definer(node, body)
        line = node.location.start_line
        scope = scope_path
        literal = literal_name(node.arguments&.arguments&.first)
        # §5: a dynamic name is reported once per call site, not per runtime
        # method the surrounding code creates.
        bare = literal || "#{node.name}@#{line}"
        MethodInfo.new(
          identity: "#{scope}#{DEFINERS.fetch(node.name)}#{bare}",
          scope: scope,
          bare_name: bare,
          definition_line: line,
          span_start: body.location.start_line,
          span_end: body.location.end_line,
          span_byte_start: body.location.start_offset,
          span_byte_end: body.location.end_offset,
          # §7.1: the call line, plus the body-opening do/{/-> when different.
          declaration_lines: [line, body.location.start_line].uniq,
          comp: 1,
          match_mode: (literal && !anonymous?(scope)) ? :name_and_span : :span_only
        )
      end

      def literal_name(node)
        case node
        when Prism::SymbolNode, Prism::StringNode then node.unescaped
        end
      end

      def anonymous_scope(node)
        block = node.block
        return nil unless block.is_a?(Prism::BlockNode)
        return nil unless node.receiver.is_a?(Prism::ConstantReadNode)
        return nil unless ANONYMOUS_SCOPES[node.receiver.name] == node.name
        "(anon@#{block.location.start_line})"
      end

      def in_scope(entry, boundary:)
        @scopes.push(entry)
        @contexts.push(nil) if boundary
        yield
        @contexts.pop if boundary
        @scopes.pop
      end

      def scope_path
        @scopes.filter_map { |entry| entry[:path] }.join("::")
      end

      # Nearest enclosing named scope only: a class reopened inside
      # `class << self` defines instance methods again.
      def singleton_scope?
        @scopes.last ? @scopes.last[:singleton] == true : false
      end

      def qualify(segment)
        scope_path.empty? ? segment : "#{scope_path}::#{segment}"
      end

      # §7.2: runtime scope names for anonymous classes and non-self
      # singletons are unstable, so those identities match by span only.
      def anonymous?(scope)
        scope.include?("(anon@") || scope.include?("(singleton@")
      end

      def bump(amount = 1)
        context = @contexts.last
        context.comp += amount if context
      end
    end
  end
end
