require_relative "../test_helper"

# Spec §9.1: every reportable definition in test/fixtures/complexity/*.rb
# carries `# cc: <int> [id: <identity>]` on the line immediately above it;
# definitions that must produce no row carry `# no-row`. The produced row
# set must equal the annotation set.
class ComplexityConformanceTest < Minitest::Test
  include Crap4Ruby::FixtureHelper

  ANNOTATION = /\A\s*#\s*cc:\s*(\d+)(?:\s+id:\s*(\S+))?\s*\z/
  NO_ROW = /\A\s*#\s*no-row\s*\z/

  Dir[File.join(FIXTURES, "complexity", "*.rb")].sort.each do |file|
    name = File.basename(file, ".rb")

    define_method("test_#{name}") do
      # Explicit UTF-8: a bare CI runner may have no locale, making the
      # default external encoding US-ASCII and multibyte comments fatal.
      source = File.read(file, encoding: Encoding::UTF_8)
      expectations = parse_annotations(source)
      rows = Crap4Ruby::MethodExtractor.extract(source)
      by_line = rows.group_by(&:definition_line)

      expectations.each do |line, expected|
        found = by_line.delete(line) || []
        if expected == :no_row
          assert_empty found, "#{name}:#{line} must produce no row, got #{found.map(&:identity)}"
        else
          assert_equal 1, found.size, "#{name}:#{line} expected exactly one row, got #{found.map(&:identity)}"
          method = found.first
          assert_equal expected[:cc], method.comp, "#{name}:#{line} (#{method.identity}) complexity"
          if expected[:id]
            assert_equal expected[:id], method.identity, "#{name}:#{line} identity"
          end
        end
      end

      leftovers = by_line.values.flatten
      assert_empty leftovers.map { |m| "#{m.identity}@#{m.definition_line}" },
                   "#{name}: rows without an annotation (fixture defect per §9.1)"
    end
  end

  private

  # Maps definition line (annotation line + 1) to {cc:, id:} or :no_row.
  def parse_annotations(source)
    source.lines.each_with_index.with_object({}) do |(text, index), map|
      if (match = text.match(ANNOTATION))
        map[index + 2] = { cc: Integer(match[1]), id: match[2] }
      elsif text.match?(NO_ROW)
        map[index + 2] = :no_row
      end
    end
  end
end
