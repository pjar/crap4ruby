require "time"

module Crap4Ruby
  # Loads and validates coverage.json (spec §4.4), resolves meta.root and
  # per-file keys (spec §2).
  class CoverageReport
    REMEDIAL_SNIPPET = <<~SNIPPET
      # .simplecov  (configuration only — SimpleCov.start belongs in the test helper)
      SimpleCov.configure do
        enable_coverage :branch
        enable_coverage :method
        cover "app/**/*.rb", "lib/**/*.rb"
      end
    SNIPPET

    attr_reader :meta, :path

    def self.load(path, analyzed_files:)
      raise Failure.new("coverage report not found: #{path}", 3) unless File.file?(path)
      data = begin
        # Explicit UTF-8: SimpleCov writes source arrays as raw UTF-8, which
        # a locale-less environment would otherwise read as US-ASCII.
        JSON.parse(File.read(path, encoding: Encoding::UTF_8))
      rescue JSON::ParserError => error
        raise Failure.new("coverage report is not valid JSON (#{error.message}): #{path}", 3)
      end
      report = new(data, path)
      report.validate!(analyzed_files)
      report
    end

    def initialize(data, path)
      @data = data
      @path = path
      @meta = data["meta"]
    end

    def entry_for(absolute_path)
      entries_by_absolute_path[absolute_path]
    end

    # Splits bytes into logical lines: one trailing empty element removed
    # if the content ends in a newline. The JSON `source` array cannot
    # represent a trailing newline, so this is the §4.2 comparison basis.
    def self.logical_lines(bytes)
      lines = bytes.split("\n", -1)
      lines.pop if bytes.end_with?("\n")
      lines
    end

    def validate!(analyzed_files)
      invalid "meta is missing or not an object" unless meta.is_a?(Hash)
      validate_schema_version
      validate_criteria
      validate_timestamp
      invalid "coverage is missing or not an object" unless @data["coverage"].is_a?(Hash)
      analyzed_files.each { |file| validate_file(file) }
    end

    private

    def validate_schema_version
      version = meta["schema_version"]
      return if version.is_a?(String) && version.match?(/\A1\.\d+\z/)
      invalid "unsupported schema_version #{version.inspect} (need 1.x)"
    end

    def validate_criteria
      flags = %w[line_coverage branch_coverage method_coverage]
      return if flags.all? { |flag| meta[flag] == true }
      disabled = flags.reject { |flag| meta[flag] == true }.join(", ")
      invalid "coverage criteria disabled in report (#{disabled}); enable them:\n\n#{REMEDIAL_SNIPPET}"
    end

    def validate_timestamp
      Time.iso8601(meta["timestamp"].to_s)
    rescue ArgumentError
      invalid "meta.timestamp is not ISO 8601: #{meta["timestamp"].inspect}"
    end

    def resolved_root
      @resolved_root ||= begin
        root = meta["root"]
        invalid "meta.root is missing or not a string" unless root.is_a?(String)
        File.absolute_path?(root) ? root : File.expand_path(root, File.dirname(path))
      end
    end

    def entries_by_absolute_path
      @entries_by_absolute_path ||= @data["coverage"].each_with_object({}) do |(key, entry), map|
        absolute = File.expand_path(key, resolved_root)
        invalid "two coverage keys resolve to #{absolute}" if map.key?(absolute)
        map[absolute] = entry
      end
    end

    # Structural checks on every consumed field of an analyzed file's
    # entry (spec §4.4). Only analyzed files are validated.
    def validate_file(file)
      entry = entry_for(file)
      validate_coverage_entry(file, entry)
      line_count = source_line_count(file)
      lines = validate_lines(file, entry["lines"], line_count)
      validate_branches(file, entry["branches"], line_count)
      validate_methods(file, entry["methods"], line_count)
      validate_source(file, entry["source"], lines)
    end

    def validate_coverage_entry(file, entry)
      return unless entry.nil?
      invalid "#{file} is not in the coverage report — likely an unloaded file " \
              "without a `cover` pattern, or excluded by a SimpleCov filter"
    end

    def source_line_count(file)
      raise Failure.new("analyzed file absent: #{file}", 3) unless File.file?(file)
      # Explicit UTF-8, matching the analyzed-file reads in CLI (no-locale
      # environments default to US-ASCII and would raise on multibyte).
      content = File.read(file, encoding: Encoding::UTF_8)
      # Every analyzed file passes through here in both modes, so this is
      # the single boundary where undecodable input maps to exit 3 instead
      # of an unhandled encoding error downstream.
      raise Failure.new("analyzed file is not valid UTF-8: #{file}", 3) unless content.valid_encoding?
      self.class.logical_lines(content).size
    end

    def validate_lines(file, lines, line_count)
      invalid "#{file}: lines is not an array" unless lines.is_a?(Array)
      unless lines.size == line_count
        invalid "#{file}: lines has #{lines.size} entries for #{line_count} lines (stale report?)"
      end
      lines.each_with_index { |value, index| validate_line_counter(file, value, index) }
      lines
    end

    def validate_line_counter(file, value, index)
      return if counter?(value) || value.nil?
      invalid "#{file}: lines[#{index}] is #{value.inspect}"
    end

    def validate_branches(file, branches, line_count)
      invalid "#{file}: branches is not an array" unless branches.is_a?(Array)
      branches.each_with_index do |branch, index|
        validate_branch(file, branch, index, line_count)
      end
    end

    def validate_branch(file, branch, index, line_count)
      validate_branch_lines(file, branch, index, line_count)
      if branch["start_line"] > branch["end_line"]
        invalid "#{file}: branches[#{index}] span is inverted"
      end
      validate_counter(file, "branches[#{index}].coverage", branch["coverage"])
    end

    def validate_branch_lines(file, branch, index, line_count)
      %w[start_line end_line report_line].each do |field|
        value = branch.is_a?(Hash) ? branch[field] : nil
        next if value.is_a?(Integer) && value.between?(1, line_count)
        invalid "#{file}: branches[#{index}].#{field} is #{value.inspect}"
      end
    end

    def validate_methods(file, methods, line_count)
      invalid "#{file}: methods is not an array" unless methods.is_a?(Array)
      methods.each_with_index do |method, index|
        validate_method(file, method, index, line_count)
      end
    end

    def validate_method(file, method, index, line_count)
      invalid "#{file}: methods[#{index}].name is not a string" unless method.is_a?(Hash) && method["name"].is_a?(String)
      validate_method_lines(file, method, index, line_count)
      if method["start_line"] > method["end_line"]
        invalid "#{file}: methods[#{index}] span is inverted"
      end
      validate_counter(file, "methods[#{index}].coverage", method["coverage"])
    end

    def validate_method_lines(file, method, index, line_count)
      %w[start_line end_line].each do |field|
        value = method[field]
        next if value.is_a?(Integer) && value.between?(1, line_count)
        invalid "#{file}: methods[#{index}].#{field} is #{value.inspect}"
      end
    end

    def validate_counter(file, field, value)
      return if counter?(value)
      invalid "#{file}: #{field} is #{value.inspect}"
    end

    def validate_source(file, source, lines)
      return if source.nil?
      return if source.is_a?(Array) && source.size == lines.size
      invalid "#{file}: source length does not match lines length"
    end

    def counter?(value)
      (value.is_a?(Integer) && value >= 0) || value == "ignored"
    end

    def invalid(message)
      raise Failure.new("invalid coverage report: #{message}", 3)
    end
  end
end
