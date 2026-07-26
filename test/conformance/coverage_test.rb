require_relative "../test_helper"

# Spec §9.2: each test/fixtures/coverage/<case>/ holds source.rb, a real
# SimpleCov ≥ 1.0 coverage.json (meta.root rewritten to "."), and
# expected.json. The harness resolves meta.root against the case directory,
# attributes coverage per §7, and asserts rows and exclusions exactly
# (cov/crap at 1e-6).
class CoverageConformanceTest < Minitest::Test
  include Crap4Ruby::FixtureHelper

  TOLERANCE = 1e-6

  Dir[File.join(FIXTURES, "coverage", "*")].sort.select { |d| File.directory?(d) }.each do |dir|
    name = File.basename(dir)

    define_method("test_#{name}") do
      report = JSON.parse(File.read(File.join(dir, "coverage.json")))
      expected = JSON.parse(File.read(File.join(dir, "expected.json")))
      entry = file_entry(report, dir, File.join(dir, "source.rb"))

      methods = Crap4Ruby::MethodExtractor.extract(File.read(File.join(dir, "source.rb")))
      result = Crap4Ruby::Attribution.call(methods, entry)

      assert_equal expected["rows"].map { |r| r["id"] }.sort,
                   result.rows.map { |r| r.method.identity }.sort,
                   "#{name}: row identities"
      assert_equal expected["excluded"].sort,
                   result.excluded.map(&:identity).sort,
                   "#{name}: excluded identities"

      actual_by_id = result.rows.to_h { |r| [r.method.identity, r] }
      expected["rows"].each do |exp|
        row = actual_by_id.fetch(exp["id"])
        assert_equal exp["cc"], row.method.comp, "#{name}/#{exp["id"]}: cc"
        assert_equal exp["units"], row.units, "#{name}/#{exp["id"]}: units"
        assert_equal exp["hits"], row.hits, "#{name}/#{exp["id"]}: hits"
        assert_in_delta exp["cov"], row.cov, TOLERANCE, "#{name}/#{exp["id"]}: cov"
        assert_in_delta exp["crap"], row.crap, TOLERANCE, "#{name}/#{exp["id"]}: crap"
      end
    end
  end

  private

  # Coverage keys resolve against meta.root; a relative root resolves
  # against the directory containing the report (spec §2) — here, the case
  # directory.
  def file_entry(report, dir, source_path)
    root = File.expand_path(report.dig("meta", "root"), dir)
    entry = report["coverage"].find do |key, _|
      File.expand_path(key, root) == File.expand_path(source_path)
    end
    flunk "no coverage entry for #{source_path}" unless entry
    entry.last
  end
end
