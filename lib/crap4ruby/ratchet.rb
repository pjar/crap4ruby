module Crap4Ruby
  # §11.3's gate semantics: classify each failing row against the baseline,
  # decide which baseline rows this run may call stale, render the
  # diagnostics, and return the exit code. Pure computation over value
  # objects — no I/O, no filesystem, no git.
  class Ratchet
    Finding = Struct.new(:kind, :row, :baselined, keyword_init: true)

    # Which baseline rows a run is entitled to freshness-check (§11.3).
    # Containment is lexical: a normalized project-root-relative directory
    # plus "/" as a byte prefix, never a filesystem question — the rows
    # most in need of the check name files that no longer exist.
    class Scope
      def self.full = new(full: true)

      def initialize(paths: [], directories: [], full: false)
        @full = full
        @paths = paths.to_h { |path| [path, true] }
        @directories = directories
      end

      def include?(path)
        return true if @full
        @paths.key?(path) || @directories.any? { |directory| path.start_with?("#{directory}/") }
      end
    end

    def initialize(baseline:, current_rows:, scope:)
      @baseline = baseline
      @current = current_rows
      @scope = scope
    end

    # Sorted by (path, line, identity), byte-wise — one total order for all
    # three kinds, so a rename reads as its new row next to its stale one.
    def findings
      @findings ||= (classified + stale).sort_by { |finding| sort_key(finding.row) }
    end

    def diagnostics = findings.map { |finding| line_for(finding) }

    # §11.3's precedence: the artifact being wrong (3) outranks the code
    # being worse than policy (2).
    def exit_code
      return 3 if findings.any? { |finding| finding.kind == :stale }
      findings.empty? ? 0 : 2
    end

    private

    # Only rows above the threshold consult the baseline: everything else
    # is untouched by the ratchet, and an improvement is not a rewrite.
    def classified
      @current.filter_map do |row|
        baselined = @baseline.row_for(row.key)
        if baselined.nil?
          Finding.new(kind: :new, row: row)
        elsif row.crap > baselined.crap # exact Rationals, never the display value
          Finding.new(kind: :worsened, row: row, baselined: baselined)
        end
      end
    end

    # A baseline row is stale when, within the freshness scope, it no
    # longer corresponds to a failing row — file gone, key unreported, or
    # the row at its key no longer exceeding the threshold. All three
    # collapse into "no current failing row carries this key".
    def stale
      failing = @current.to_h { |row| [row.key, row] }
      @baseline.rows.filter_map do |row|
        next unless @scope.include?(row.path)
        Finding.new(kind: :stale, row: row) unless failing.key?(row.key)
      end
    end

    def line_for(finding)
      row = finding.row
      location = "(#{escape(row.path)}:#{row.line})"
      identity = escape(row.identity)
      case finding.kind
      when :new
        "baseline: new offender #{identity} #{location} CRAP #{Report.decimal(row.crap, 2)}"
      when :worsened
        "baseline: worsened #{identity} #{location} CRAP #{Report.decimal(row.crap, 2)} > " \
          "#{Report.decimal(finding.baselined.crap, 2)} baselined"
      else
        "baseline: stale row #{identity} #{location} — no longer failing here; run --update-baseline"
      end
    end

    def sort_key(row) = [row.path.b, row.line, row.identity.b]

    # §11.3: a hostile path or identity must not be able to break the
    # one-line format. Backslash and control bytes are escaped; everything
    # else — multibyte UTF-8 included — prints verbatim.
    def escape(value)
      value.b.gsub(/[\x00-\x1f\\]/n) do |byte|
        case byte
        when "\\" then "\\\\"
        when "\n" then "\\n"
        when "\r" then "\\r"
        when "\t" then "\\t"
        else format("\\x%02x", byte.ord)
        end
      end.force_encoding(Encoding::UTF_8)
    end
  end
end
