module Crap4Ruby
  # Rendering and ordering of the final table (spec §8). The gate itself
  # lives in CLI and compares unrounded values.
  class Report
    Entry = Struct.new(:row, :path, keyword_init: true)

    HEADERS = ["Method", "CC", "Cov%", "CRAP", "Location"].freeze

    # Exact half-up display rounding (spec §8). Values arrive as Rationals
    # from attribution; going through Rational keeps decimal ties like
    # 8.405 honest, where printf on a Float would round toward its binary
    # representation.
    def self.decimal(value, places)
      scale = 10**places
      whole, fraction = (Rational(value) * scale).round(half: :up).divmod(scale)
      format("%d.%0#{places}d", whole, fraction)
    end

    attr_reader :entries, :excluded_count

    def initialize(entries, excluded_count:)
      @entries = entries.sort_by do |entry|
        [-entry.row.crap, -entry.row.method.comp, entry.path,
         entry.row.method.definition_line, entry.row.method.identity]
      end
      @excluded_count = excluded_count
    end

    def render(stdout)
      if entries.empty?
        stdout.puts "nothing to analyze"
      else
        width = [entries.map { |e| e.row.method.identity.length }.max, HEADERS.first.length].max
        stdout.puts format_line(width, *HEADERS)
        entries.each do |entry|
          row = entry.row
          stdout.puts format_line(
            width,
            row.method.identity,
            row.method.comp.to_s,
            self.class.decimal(row.cov * 100, 1),
            self.class.decimal(row.crap, 2),
            "#{entry.path}:#{row.method.definition_line}"
          )
        end
      end
      stdout.puts "excluded by coverage markers: #{excluded_count}" if excluded_count.positive?
    end

    def max_crap
      entries.map { |entry| entry.row.crap }.max
    end

    private

    def format_line(width, method, cc, cov, crap, location)
      format("%-#{width}s  %3s  %6s  %8s  %s", method, cc, cov, crap, location)
    end
  end
end
