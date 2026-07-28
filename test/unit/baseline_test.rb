require_relative "../test_helper"

# §11.2 unit coverage for the pieces the §9.3 corpus can only observe
# through the CLI: engagement stat semantics, the duplicate-member hook,
# canonical serialization escapes and ordering, and the atomic write.
class BaselineTest < Minitest::Test
  include Crap4Ruby::SandboxHelper

  Baseline = Crap4Ruby::Baseline

  def test_absent_file_does_not_engage
    with_sandbox { |root| assert_nil Baseline.read(File.join(root, Baseline::FILENAME)) }
  end

  def test_symlink_and_directory_are_refused_not_ignored
    with_sandbox do |root|
      write_file(root, "target.json", Baseline.serialize([]))
      link = File.join(root, Baseline::FILENAME)
      File.symlink("target.json", link)
      assert_failure(3, "not a regular file") { Baseline.read(link) }

      directory = File.join(root, "dir.json")
      Dir.mkdir(directory)
      assert_failure(3, "not a regular file") { Baseline.read(directory) }
    end
  end

  # Ruby's JSON keeps the last duplicate silently; §11.2 rejects the file.
  def test_duplicate_member_names_are_rejected_at_both_levels
    with_sandbox do |root|
      top = write_file(root, "top.json", '{"schema_version":"1.0","metric_version":1,"metric_version":1,"rows":[]}')
      assert_equal 3, assert_raises(Crap4Ruby::Failure) { Baseline.read(top) }.exit_code

      nested = write_file(root, "nested.json",
                          %({"schema_version":"1.0","metric_version":1,"rows":[) +
                          %({"path":"lib/a.rb","path":"lib/a.rb","identity":"A#a","line":1,) +
                          %("comp":3,"units":9,"hits":0,"called":false}]}))
      assert_equal 3, assert_raises(Crap4Ruby::Failure) { Baseline.read(nested) }.exit_code
    end
  end

  def test_empty_rows_serialize_inline
    assert_equal <<~JSON, Baseline.serialize([])
      {
        "schema_version": "1.0",
        "metric_version": 1,
        "rows": []
      }
    JSON
  end

  # §11.2's row order is (path, line, identity), byte-wise — so "A" sorts
  # before "a" and the ordering never depends on a locale collation.
  def test_rows_are_sorted_by_path_then_line_then_identity_bytewise
    rows = [
      row(path: "lib/b.rb", identity: "B#b", line: 1),
      row(path: "lib/a.rb", identity: "A#z", line: 2),
      row(path: "lib/a.rb", identity: "A#a", line: 2),
      row(path: "lib/a.rb", identity: "A#Z", line: 1)
    ]
    serialized = Baseline.serialize(rows)
    assert_equal ["A#Z", "A#a", "A#z", "B#b"], serialized.scan(/"identity": "([^"]+)"/).flatten
    assert_equal ["lib/a.rb", "lib/a.rb", "lib/a.rb", "lib/b.rb"], serialized.scan(/"path": "([^"]+)"/).flatten
    assert_equal [1, 2, 2, 1], serialized.scan(/"line": (\d+)/).flatten.map(&:to_i)
  end

  # RFC 8259 with §11.2's exact escape set: short escapes where they
  # exist, \u00XX lowercase hex for the other control bytes, everything
  # else — multibyte included — verbatim.
  def test_string_escapes_are_exactly_the_specified_set
    control = %w[22 5c 08 0c 0a 0d 09 01 1f].map { |byte| byte.hex.chr }.join
    identity = "Q##{control} Grüße"
    expected = '      "identity": "Q#' + '\\"\\\\\\b\\f\\n\\r\\t\\u0001\\u001f' + ' Grüße"'
    serialized = Baseline.serialize([row(path: "lib/a.rb", identity: identity, line: 1)])
    assert_includes serialized, expected
    assert_equal Encoding::UTF_8, serialized.encoding
  end

  def test_write_round_trips_through_validation_and_leaves_no_temp_file
    with_sandbox do |root|
      path = File.join(root, Baseline::FILENAME)
      rows = [row(path: "lib/a.rb", identity: "A#a", line: 2)]
      Baseline.write(path, rows)
      assert_equal Baseline.serialize(rows), File.read(path, encoding: Encoding::UTF_8)
      assert_equal [Baseline::FILENAME], Dir.children(root), "the temp file is renamed, never left behind"
      assert_equal rows.map(&:key), Baseline.read(path).rows.map(&:key)
    end
  end

  # §11.4: a written baseline must always re-validate, so the rows are
  # checked before anything reaches the disk.
  def test_write_refuses_rows_that_would_not_validate
    with_sandbox do |root|
      path = File.join(root, Baseline::FILENAME)
      passing = row(path: "lib/a.rb", identity: "A#a", line: 1, comp: 1, units: 1, hits: 1)
      assert_failure(3, "threshold") { Baseline.write(path, [passing]) }
      duplicated = Array.new(2) { row(path: "lib/a.rb", identity: "A#a", line: 1) }
      assert_failure(3, "duplicate row key") { Baseline.write(path, duplicated) }
      assert_empty Dir.children(root), "no write, and no temp file left behind"
    end
  end

  def test_stored_components_recompute_crap_in_exact_rational_arithmetic
    stored = row(path: "lib/a.rb", identity: "A#a", line: 1, comp: 8, units: 450, hits: 449)
    assert_equal Rational(8) + Rational(64, 91_125_000), stored.crap
    uncalled = row(path: "lib/a.rb", identity: "A#a", line: 1, comp: 3, units: 0, hits: 0)
    assert_equal Rational(12), uncalled.crap
    called = Baseline::Row.new(**uncalled.to_h.merge(called: true))
    assert_equal Rational(3), called.crap
  end

  private

  def row(path:, identity:, line:, comp: 3, units: 9, hits: 0, called: false)
    Baseline::Row.new(path: path, identity: identity, line: line,
                      comp: comp, units: units, hits: hits, called: called)
  end
end
