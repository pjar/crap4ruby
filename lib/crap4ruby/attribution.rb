module Crap4Ruby
  # Coverage attribution for one analyzed file (spec §7): innermost-span
  # ownership, coverable units, the invocation-bit fallback, and
  # ignore-marker exclusion.
  class Attribution
    Result = Struct.new(:rows, :excluded, keyword_init: true)

    # units/hits count only non-ignored entries; `candidates` is the
    # pre-ignore unit count the §7.4 exclusion rule needs.
    Tally = Struct.new(:units, :hits, :candidates, :ignored)

    def self.call(methods, file_entry)
      new(methods, file_entry).call
    end

    def initialize(methods, file_entry)
      @methods = methods
      @lines = file_entry["lines"] || []
      @branches = file_entry["branches"] || []
      @entries = parse_entries(file_entry["methods"] || [])
      @tallies = Array.new(methods.size) { Tally.new(0, 0, 0, 0) }
    end

    def call
      accumulate_lines
      accumulate_branches

      rows = []
      excluded = []
      @methods.each_with_index do |method, index|
        if excluded?(method, @tallies[index])
          excluded << method
        else
          rows << build_row(method, @tallies[index])
        end
      end
      Result.new(rows: rows, excluded: excluded)
    end

    private

    def accumulate_lines
      @lines.each_with_index do |value, index|
        next unless unit?(value)
        line = index + 1
        owner = line_owner(line, ignored: value == "ignored")
        next if owner.nil?
        # §7.1: declaration lines execute at class-load time.
        next if @methods[owner].declaration_lines.include?(line)
        record(owner, value)
      end
    end

    # §7.1: arms increment only at call time, so no declaration exclusion.
    def accumulate_branches
      @branches.each do |branch|
        owner = branch_owner(branch["report_line"])
        next if owner.nil?
        record(owner, branch["coverage"])
      end
    end

    def record(index, value)
      tally = @tallies[index]
      tally.candidates += 1
      if value == "ignored"
        tally.ignored += 1 # §7.4: out of both units and hits
      else
        tally.units += 1
        tally.hits += 1 if value >= 1
      end
    end

    def unit?(value)
      value.is_a?(Integer) || value == "ignored"
    end

    def line_owner(line, ignored:)
      candidates = innermost(line)
      return nil if candidates.empty?
      return candidates.first if candidates.size == 1
      # §7.0: the failure triggers only when the shared line would actually
      # yield a unit — an "ignored" entry never does, so it belongs to no
      # sibling and enters no pre-ignore tally.
      return nil if ignored
      # §7.0: zero-unit same-line definitions are fine — a line every
      # candidate declares never becomes a unit for any of them.
      return nil if candidates.all? { |index| @methods[index].declaration_lines.include?(line) }
      raise ambiguity(line, candidates)
    end

    def branch_owner(line)
      candidates = innermost(line)
      return nil if candidates.empty?
      return candidates.first if candidates.size == 1
      raise ambiguity(line, candidates)
    end

    # §7.0: the innermost containing span owns the unit. Candidates are
    # selected by line, but containment is resolved on byte offsets —
    # `def outer; def inner; 1; end; end` nests on a single line. More than
    # one survivor means siblings sharing the line, never a nesting.
    def innermost(line)
      containing = @methods.each_index.select { |index| @methods[index].span_contains?(line) }
      containing.reject do |index|
        containing.any? { |other| other != index && @methods[index].strictly_contains?(@methods[other]) }
      end
    end

    def ambiguity(line, candidates)
      identities = candidates.map { |index| @methods[index].identity }.join(", ")
      Failure.new("ambiguous same-line definitions at line #{line}: #{identities}", 3)
    end

    # Exact arithmetic throughout: the gate compares unrounded values and
    # the report rounds half-up, both of which binary floats would skew.
    def build_row(method, tally)
      cov =
        if tally.units.positive?
          Rational(tally.hits, tally.units)
        else
          called?(method) ? Rational(1) : Rational(0) # §7.2: the bit, only at zero units
        end
      Row.new(method: method, units: tally.units, hits: tally.hits, cov: cov)
    end

    def called?(method)
      matching_entries(method).any? { |entry| entry[:coverage].is_a?(Integer) && entry[:coverage] >= 1 }
    end

    # §7.4. `entries.any?` is load-bearing: no matching entry at all means
    # the defining code never ran (§7.2, not called), never "ignored".
    def excluded?(method, tally)
      entries = matching_entries(method)
      return true if entries.any? && entries.all? { |entry| entry[:coverage] == "ignored" }
      tally.candidates.positive? && tally.candidates == tally.ignored
    end

    def matching_entries(method)
      @entries.select do |entry|
        next false unless entry[:start_line] == method.span_start && entry[:end_line] == method.span_end
        method.match_mode == :span_only ||
          (entry[:scope] == method.scope && entry[:name] == method.bare_name)
      end
    end

    # §7.2: SimpleCov collapses singleton methods into `Scope#name`, so the
    # separator carries no information — only scope and bare name do.
    def parse_entries(entries)
      entries.map do |entry|
        scope, name = split_name(entry["name"].to_s)
        {
          scope: scope,
          name: name,
          start_line: entry["start_line"],
          end_line: entry["end_line"],
          coverage: entry["coverage"]
        }
      end
    end

    def split_name(full)
      if (index = full.index("#"))
        [full[0, index], full[(index + 1)..]]
      elsif (index = full.rindex("."))
        [full[0, index], full[(index + 1)..]]
      else
        ["", full]
      end
    end
  end
end
