require "json"

module Crap4Ruby
  # The ratchet's policy artifact (spec §11.2): engagement, static
  # validation, canonical serialization, atomic write. It knows nothing
  # about the gate — Ratchet classifies rows, CLI orders the pipeline.
  class Baseline
    FILENAME = "crap4ruby-baseline.json".freeze
    SCHEMA_VERSION = "1.0".freeze
    SCHEMA_PATTERN = /\A1\.\d+\z/
    # The metric contract identifier (§11.2), deliberately independent of
    # spec.md's revision number: it moves only when scoring itself moves.
    METRIC_VERSION = 1
    TOP_LEVEL_KEYS = %w[schema_version metric_version rows].freeze
    ROW_KEYS = %w[path identity line comp units hits called].freeze
    # RFC 8259 with exactly §11.2's escape set: these short escapes,
    # \u00XX (lowercase hex) for the remaining control characters, and
    # every other character verbatim as UTF-8.
    SHORT_ESCAPES = {
      "\"" => "\\\"", "\\" => "\\\\", "\b" => "\\b", "\f" => "\\f",
      "\n" => "\\n", "\r" => "\\r", "\t" => "\\t"
    }.freeze

    # §11.2 rejects duplicate JSON member names, which every JSON parser
    # otherwise collapses to the last one silently. Two mechanisms, because
    # which of them can see the duplicate depends on the json version:
    # json >= 2.13 deduplicates inside the parser (so `[]=` is never called
    # twice) and reports duplicates only through `allow_duplicate_key:
    # false`, while older parsers ignore that unknown option and assign
    # every pair through `object_class#[]=`. Both land on exit 3.
    class StrictObject < Hash
      DuplicateMember = Class.new(StandardError)

      def []=(key, value)
        raise DuplicateMember, key.to_s if key?(key)
        super
      end
    end

    # One stored offender: components, never scores (§11.2). CRAP is
    # recomputed through Row's functions in exact Rational arithmetic.
    Row = Struct.new(:path, :identity, :line, :comp, :units, :hits, :called, keyword_init: true) do
      # §11.4 writes exactly the currently-failing rows, so the report's
      # own entries are the source of the stored components.
      def self.from_entry(entry)
        row = entry.row
        new(path: entry.path, identity: row.method.identity, line: row.method.definition_line,
            comp: row.method.comp, units: row.units, hits: row.hits, called: row.invoked?)
      end

      # §5/§8's report key, and §11.5's uniqueness rule.
      def key = [path, identity, line]

      def cov = Crap4Ruby::Row.cov_for(units: units, hits: hits, called: called)

      def crap = Crap4Ruby::Row.crap_for(comp: comp, cov: cov)

      def location = "#{path}:#{line}"
    end

    class << self
      # Engagement (§11.1): a regular file at the path engages the ratchet,
      # its absence returns nil, and a symlink or other non-regular file is
      # refused rather than ignored. lstat, never stat — File.file? follows
      # symlinks, and the refusal is the point.
      def read(path)
        stat = stat_for(path)
        return nil if stat.nil?
        refuse_irregular(path, stat)
        parse(read_bytes(path), path)
      end

      # §11.2's canonical form, byte for byte, plus §11.4's rule that a
      # written baseline must always re-validate. Atomic: write a temp file
      # beside the target and rename, so a failure leaves the previous file
      # byte-for-byte untouched.
      def write(path, rows)
        validate_rows!(rows, "rows to write")
        stat = stat_for(path)
        refuse_irregular(path, stat) if stat
        temp = File.join(File.dirname(path), ".#{File.basename(path)}.#{Process.pid}.#{rand(1 << 32).to_s(16)}.tmp")
        begin
          File.binwrite(temp, serialize(rows))
          File.rename(temp, path)
        rescue SystemCallError => error
          invalid "cannot write #{path}: #{error.message}"
        ensure
          File.delete(temp) if File.exist?(temp)
        end
      end

      def serialize(rows)
        ordered = rows.sort_by { |row| [row.path.b, row.line, row.identity.b] }
        out = +"{\n"
        out << %(  #{json_string("schema_version")}: #{json_string(SCHEMA_VERSION)},\n)
        out << %(  #{json_string("metric_version")}: #{METRIC_VERSION},\n)
        out << %(  #{json_string("rows")}: )
        out << (ordered.empty? ? "[]\n" : "[\n#{ordered.map { |row| serialize_row(row) }.join(",\n")}\n  ]\n")
        out << "}\n"
      end

      # Component invariants (§11.2), shared by the read and the write
      # paths: a baseline crap4ruby produces must be one crap4ruby accepts.
      def validate_rows!(rows, where)
        seen = {}
        rows.each do |row|
          validate_components!(row, where)
          if seen.key?(row.key)
            invalid "#{where}: duplicate row key #{row.identity} (#{row.location})"
          end
          seen[row.key] = true
        end
        rows
      end

      private

      def stat_for(path)
        File.lstat(path)
      rescue Errno::ENOENT, Errno::ENOTDIR
        nil
      rescue SystemCallError => error
        invalid "cannot read #{path}: #{error.message}"
      end

      # §11.2: every failure here is exit 3, an unreadable file included —
      # the engaged baseline is a validation input, and a permission error
      # must not escape as a raw Errno (same posture as stat_for).
      def read_bytes(path)
        File.read(path, encoding: Encoding::UTF_8)
      rescue SystemCallError => error
        invalid "cannot read #{path}: #{error.message}"
      end

      def refuse_irregular(path, stat)
        return if stat.file?
        invalid "#{path} is not a regular file — a symlink or special file there " \
                "neither engages the ratchet nor is ignored"
      end

      def parse(text, path)
        # The single boundary where undecodable input maps to exit 3
        # instead of an encoding error escaping from the JSON parser.
        invalid "#{path}: not valid UTF-8" unless text.valid_encoding?
        data = begin
          JSON.parse(text, object_class: StrictObject, allow_duplicate_key: false)
        rescue StrictObject::DuplicateMember => error
          invalid "#{path}: duplicate member name #{error.message.inspect}"
        rescue JSON::ParserError => error
          invalid "#{path}: not valid JSON (#{error.message})"
        end
        new(validate!(data, path), path)
      end

      def validate!(data, path)
        invalid "#{path}: the top level must be a JSON object" unless data.is_a?(Hash)
        check_keys(data.keys, TOP_LEVEL_KEYS, path)
        validate_schema_version(data["schema_version"], path)
        validate_metric_version(data["metric_version"], path)
        rows = data["rows"]
        invalid "#{path}: rows must be an array" unless rows.is_a?(Array)
        validate_rows!(rows.each_with_index.map { |row, index| build_row(row, "#{path}: rows[#{index}]") }, path)
      end

      def validate_schema_version(version, path)
        return if version.is_a?(String) && version.match?(SCHEMA_PATTERN)
        invalid "#{path}: unsupported schema_version #{version.inspect} (need 1.x)"
      end

      # Exact match, fail-closed: scores across metric versions are not
      # comparable, and the remedy is an Owner-reviewed regeneration
      # (delete, then re-create with --update-baseline).
      def validate_metric_version(version, path)
        return if version.is_a?(Integer) && version == METRIC_VERSION
        invalid "#{path}: metric_version #{version.inspect} is not #{METRIC_VERSION} — " \
                "scores are not comparable across metric versions; delete the baseline " \
                "and re-create it with --update-baseline on a green tree"
      end

      def build_row(row, where)
        invalid "#{where} must be a JSON object" unless row.is_a?(Hash)
        check_keys(row.keys, ROW_KEYS, where)
        string!(row["path"], "path", where)
        string!(row["identity"], "identity", where)
        integer!(row["line"], "line", where)
        integer!(row["comp"], "comp", where)
        integer!(row["units"], "units", where)
        integer!(row["hits"], "hits", where)
        unless row["called"] == true || row["called"] == false
          invalid "#{where}: called must be a boolean, got #{row["called"].inspect}"
        end
        Row.new(**ROW_KEYS.to_h { |key| [key.to_sym, row[key]] })
      end

      def validate_components!(row, where)
        validate_path!(row.path, where)
        validate_line!(row, where)
        validate_comp!(row, where)
        validate_units!(row, where)
        validate_hits!(row, where)
        validate_called!(row, where)
        validate_crap!(row, where)
      end

      def validate_line!(row, where)
        return if row.line >= 1
        invalid "#{where}: line must be >= 1 (#{row.identity} #{row.location})"
      end

      def validate_comp!(row, where)
        return if row.comp >= 1
        invalid "#{where}: comp must be >= 1 (#{row.identity} #{row.location})"
      end

      def validate_units!(row, where)
        return if row.units >= 0
        invalid "#{where}: units must be >= 0 (#{row.identity} #{row.location})"
      end

      def validate_hits!(row, where)
        return if row.hits >= 0 && row.hits <= row.units
        invalid "#{where}: hits must satisfy 0 <= hits <= units (#{row.identity} #{row.location})"
      end

      # §7.2: the invocation bit is never consulted when units exist, so
      # a stored `true` there would be a value the metric cannot mean.
      def validate_called!(row, where)
        return unless row.units.positive? && row.called
        invalid "#{where}: called must be false when units > 0 (#{row.identity} #{row.location})"
      end

      def validate_crap!(row, where)
        return if row.crap > THRESHOLD
        invalid "#{where}: #{row.identity} (#{row.location}) recomputes to CRAP " \
                "#{Report.decimal(row.crap, 2)} — a row at or under the threshold " \
                "has no business being grandfathered"
      end

      # §11.2: normalized, project-root-relative. §11.3's containment and
      # key matching are lexical byte comparisons, which only this form can
      # satisfy — hence no filesystem access here either.
      def validate_path!(path, where)
        segments = path.split("/", -1)
        return if !path.empty? && segments.none? { |segment| ["", ".", ".."].include?(segment) }
        invalid "#{where}: path #{path.inspect} is not a normalized project-root-relative path"
      end

      def check_keys(keys, expected, where)
        missing = expected - keys
        unknown = keys - expected
        return if missing.empty? && unknown.empty?
        details = []
        details << "missing #{missing.join(", ")}" unless missing.empty?
        details << "unknown #{unknown.join(", ")}" unless unknown.empty?
        invalid "#{where}: key set must be exactly #{expected.join(", ")} (#{details.join("; ")})"
      end

      def string!(value, field, where)
        invalid "#{where}: #{field} must be a string, got #{value.inspect}" unless value.is_a?(String)
      end

      def integer!(value, field, where)
        invalid "#{where}: #{field} must be an integer, got #{value.inspect}" unless value.is_a?(Integer)
      end

      def serialize_row(row)
        members = ROW_KEYS.map { |key| %(      #{json_string(key)}: #{json_value(row[key])}) }
        "    {\n#{members.join(",\n")}\n    }"
      end

      def json_value(value)
        value.is_a?(String) ? json_string(value) : value.to_s
      end

      def json_string(value)
        escaped = value.gsub(/[\x00-\x1f"\\]/) { |char| SHORT_ESCAPES[char] || format("\\u%04x", char.ord) }
        "\"#{escaped}\""
      end

      def invalid(message)
        raise Failure.new("invalid baseline: #{message}", 3)
      end
    end

    attr_reader :rows, :path

    def initialize(rows, path)
      @rows = rows
      @path = path
    end

    def row_for(key) = rows_by_key[key]

    private

    def rows_by_key
      @rows_by_key ||= rows.to_h { |row| [row.key, row] }
    end
  end
end
