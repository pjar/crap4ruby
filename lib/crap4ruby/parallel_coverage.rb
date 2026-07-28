module Crap4Ruby
  # §4.3's parallel-coverage mismatch predicate, conjuncts 2–4 — the CLI
  # owns conjunct 1 (--test-command) and conjunct 5 (empty selection). It is
  # entirely static: what the sources *declare*, never what a run executes.
  module ParallelCoverage
    WARNING = "warning: Rails test configuration declares `parallelize`, but " \
              ".simplecov does not declare `merge_subprocesses true`; " \
              "worker coverage may be missing".freeze
    REFUSAL = "--update-baseline refused: Rails test configuration declares " \
              "`parallelize`, but .simplecov does not declare " \
              "`merge_subprocesses true`; worker coverage may be missing".freeze

    class << self
      def mismatch?(root)
        rails_test_layout?(root) && declares_parallelize?(root) && !merge_subprocesses_proof?(root)
      end

      private

      # §4.3's detection row for `bin/rails test`, evaluated statically: under
      # --no-run nothing runs, and the same three conditions decide.
      def rails_test_layout?(root)
        return false unless Dir.exist?(File.join(root, "test"))
        return false if Dir.exist?(File.join(root, "spec"))
        bin_rails = File.join(root, "bin", "rails")
        File.exist?(bin_rails) && File.executable?(bin_rails)
      end

      # §3's glob semantics — sorted, dot-directories not entered — and
      # §4.3's *declares*: a receiverless call anywhere in the file counts,
      # dead or guarded code included.
      def declares_parallelize?(root)
        base = File.join(root, "test")
        Dir.glob("**/*.rb", base: base).sort.any? do |relative|
          node = parse(File.join(base, relative))
          node && parallelize?(node)
        end
      end

      def parallelize?(node)
        receiverless_call?(node, :parallelize) ||
          node.compact_child_nodes.any? { |child| parallelize?(child) }
      end

      # §4.3's positive syntactic proof: across every `SimpleCov.configure`
      # block body, in source order, the last receiverless
      # `merge_subprocesses` among the *direct* statements must carry the
      # literal `true` alone. A missing, unreadable, or unparseable
      # .simplecov proves nothing.
      def merge_subprocesses_proof?(root)
        node = parse(File.join(root, ".simplecov"))
        return false if node.nil?
        literal_true?(directives(node).last)
      end

      # Direct statements only: a call nested in an inner block or a
      # conditional is not one, and neither is one outside any configure
      # block.
      def directives(node)
        nodes(node).flat_map do |candidate|
          next [] unless configure_call?(candidate)
          body = candidate.block.body
          next [] unless body.is_a?(Prism::StatementsNode)
          body.body.select { |statement| receiverless_call?(statement, :merge_subprocesses) }
        end
      end

      def configure_call?(node)
        node.is_a?(Prism::CallNode) && node.name == :configure &&
          simplecov?(node.receiver) && node.block.is_a?(Prism::BlockNode)
      end

      # `SimpleCov` or `::SimpleCov`; a qualified path (`Foo::SimpleCov`)
      # names a different constant.
      def simplecov?(receiver)
        case receiver
        when Prism::ConstantReadNode then receiver.name == :SimpleCov
        when Prism::ConstantPathNode then receiver.parent.nil? && receiver.name == :SimpleCov
        else false
        end
      end

      # The canonical directive: exactly one positional argument, the literal
      # `true`, no block and no block argument.
      def literal_true?(call)
        return false if call.nil? || call.block
        arguments = call.arguments&.arguments || []
        arguments.length == 1 && arguments.first.is_a?(Prism::TrueNode)
      end

      def receiverless_call?(node, name)
        node.is_a?(Prism::CallNode) && node.receiver.nil? && node.name == name
      end

      # Pre-order, so siblings come in source order.
      def nodes(node)
        [node] + node.compact_child_nodes.flat_map { |child| nodes(child) }
      end

      # §2's grammar pin, the one extraction uses. Here a file that cannot be
      # read as UTF-8 or does not parse is skipped, never a failure: it can
      # neither declare parallelism nor prove the remedy.
      def parse(path)
        source = File.read(path, encoding: Encoding::UTF_8)
        return nil unless source.valid_encoding?
        result = Prism.parse(source, version: MethodExtractor::GRAMMAR_VERSION)
        result.failure? ? nil : result.value
      rescue SystemCallError
        nil
      end
    end
  end
end
