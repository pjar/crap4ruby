require_relative "../test_helper"

class CoverageReportTest < Minitest::Test
  include Crap4Ruby::SandboxHelper
  include Crap4Ruby::LocaleHelper

  SOURCE = "class A\n  def x = 1\nend\n"
  MULTIBYTE_SOURCE = "# Grüße — Kommentar\n#{SOURCE}"

  def test_loads_a_valid_report_and_resolves_relative_root_against_report_directory
    with_sandbox do |root|
      file = write_file(root, "lib/a.rb", SOURCE)
      path = write_report(root, valid_report)
      report = Crap4Ruby::CoverageReport.load(path, analyzed_files: [file])
      assert_equal [1, 1, nil], report.entry_for(file)["lines"]
    end
  end

  def test_absolute_root_is_used_as_is
    with_sandbox do |root|
      file = write_file(root, "lib/a.rb", SOURCE)
      data = valid_report
      data["meta"]["root"] = root
      path = write_file(root, "elsewhere/report.json", JSON.generate(data))
      report = Crap4Ruby::CoverageReport.load(path, analyzed_files: [file])
      assert report.entry_for(file)
    end
  end

  def test_missing_report_fails_with_exit_3
    with_sandbox do |root|
      assert_failure(3, "not found") do
        Crap4Ruby::CoverageReport.load(File.join(root, "coverage/coverage.json"), analyzed_files: [])
      end
    end
  end

  def test_malformed_json_fails
    with_sandbox do |root|
      path = write_file(root, "coverage/coverage.json", "{nope")
      assert_failure(3, "not valid JSON") { Crap4Ruby::CoverageReport.load(path, analyzed_files: []) }
    end
  end

  def test_rejects_schema_version_2
    assert_invalid("schema_version") { |data| data["meta"]["schema_version"] = "2.0" }
  end

  def test_accepts_later_1x_schema_versions
    with_sandbox do |root|
      file = write_file(root, "lib/a.rb", SOURCE)
      data = valid_report
      data["meta"]["schema_version"] = "1.7"
      path = write_report(root, data)
      assert Crap4Ruby::CoverageReport.load(path, analyzed_files: [file])
    end
  end

  def test_disabled_criteria_fail_with_the_remedial_snippet
    error = assert_invalid("criteria disabled") { |data| data["meta"]["method_coverage"] = false }
    assert_includes error.message, "enable_coverage :method"
    assert_includes error.message, "SimpleCov.configure"
  end

  def test_non_iso8601_timestamp_fails
    assert_invalid("timestamp") { |data| data["meta"]["timestamp"] = "yesterday" }
  end

  def test_analyzed_file_missing_from_coverage_fails
    with_sandbox do |root|
      file = write_file(root, "lib/a.rb", SOURCE)
      other = write_file(root, "lib/b.rb", SOURCE)
      path = write_report(root, valid_report)
      Crap4Ruby::CoverageReport.load(path, analyzed_files: [file])
      assert_failure(3, "not in the coverage report") do
        Crap4Ruby::CoverageReport.load(path, analyzed_files: [other])
      end
    end
  end

  def test_lines_length_mismatch_fails
    assert_invalid("stale report") { |data| entry(data)["lines"] = [1, 1] }
  end

  def test_invalid_line_entry_fails
    assert_invalid("lines[1]") { |data| entry(data)["lines"][1] = -2 }
  end

  def test_branch_report_line_out_of_bounds_fails
    assert_invalid("report_line") do |data|
      entry(data)["branches"] << { "start_line" => 2, "end_line" => 2, "report_line" => 99, "coverage" => 0 }
    end
  end

  def test_ignored_counters_are_valid
    with_sandbox do |root|
      file = write_file(root, "lib/a.rb", SOURCE)
      data = valid_report
      entry(data)["lines"][1] = "ignored"
      entry(data)["methods"] << { "name" => "A#x", "start_line" => 2, "end_line" => 2, "coverage" => "ignored" }
      path = write_report(root, data)
      assert Crap4Ruby::CoverageReport.load(path, analyzed_files: [file])
    end
  end

  def test_method_without_name_fails
    assert_invalid("methods[0].name") do |data|
      entry(data)["methods"] << { "start_line" => 2, "end_line" => 2, "coverage" => 1 }
    end
  end

  def test_source_length_mismatch_fails
    assert_invalid("source length") { |data| entry(data)["source"] = ["class A"] }
  end

  def test_inverted_method_span_fails
    assert_invalid("span is inverted") do |data|
      entry(data)["methods"] << { "name" => "A#x", "start_line" => 3, "end_line" => 2, "coverage" => 1 }
    end
  end

  def test_colliding_coverage_keys_fail
    assert_invalid("resolve to") do |data|
      data["coverage"]["./lib/a.rb"] = data["coverage"]["lib/a.rb"]
    end
  end

  def test_logical_lines
    assert_equal %w[a b], Crap4Ruby::CoverageReport.logical_lines("a\nb\n")
    assert_equal %w[a b], Crap4Ruby::CoverageReport.logical_lines("a\nb")
    assert_equal ["a", ""], Crap4Ruby::CoverageReport.logical_lines("a\n\n")
    assert_equal [], Crap4Ruby::CoverageReport.logical_lines("")
  end

  def test_validates_a_multibyte_analyzed_file_under_an_ascii_locale
    with_sandbox do |root|
      file = write_file(root, "lib/a.rb", MULTIBYTE_SOURCE)
      data = valid_report
      entry(data)["lines"] = [nil, 1, 1, nil]
      path = write_report(root, data)
      with_ascii_default_external do
        report = Crap4Ruby::CoverageReport.load(path, analyzed_files: [file])
        assert report.entry_for(file)
      end
    end
  end

  def test_parses_a_report_carrying_multibyte_source_content_under_an_ascii_locale
    with_sandbox do |root|
      file = write_file(root, "lib/a.rb", MULTIBYTE_SOURCE)
      data = valid_report
      entry(data)["lines"] = [nil, 1, 1, nil]
      entry(data)["source"] = ["# Grüße — Kommentar", "class A", "  def x = 1", "end"]
      path = write_report(root, data)
      with_ascii_default_external do
        report = Crap4Ruby::CoverageReport.load(path, analyzed_files: [file])
        assert_equal "# Grüße — Kommentar", report.entry_for(file)["source"].first
      end
    end
  end

  def test_invalid_utf8_analyzed_file_fails_with_exit_3
    with_sandbox do |root|
      file = File.join(root, "lib/a.rb")
      FileUtils.mkdir_p(File.dirname(file))
      File.binwrite(file, "class A\n  def x = 1\nend\n\xE9\n")
      data = valid_report
      entry(data)["lines"] = []
      path = write_report(root, data)
      error = assert_failure(3, "not valid UTF-8") do
        Crap4Ruby::CoverageReport.load(path, analyzed_files: [file])
      end
      assert_includes error.message, "a.rb"
    end
  end

  private

  def valid_report
    {
      "meta" => {
        "schema_version" => "1.0",
        "timestamp" => "2026-07-26T12:00:00+02:00",
        "root" => "..",
        "commit" => "0" * 40,
        "line_coverage" => true,
        "branch_coverage" => true,
        "method_coverage" => true
      },
      "coverage" => {
        "lib/a.rb" => { "lines" => [1, 1, nil], "branches" => [], "methods" => [] }
      }
    }
  end

  def entry(data)
    data["coverage"]["lib/a.rb"]
  end

  # Report sits in <root>/coverage/, meta.root ".." resolves back to root.
  def write_report(root, data)
    write_file(root, "coverage/coverage.json", JSON.generate(data))
  end

  def assert_invalid(message_part, &mutate)
    with_sandbox do |root|
      file = write_file(root, "lib/a.rb", SOURCE)
      data = valid_report
      mutate.call(data)
      path = write_report(root, data)
      return assert_failure(3, message_part) do
        Crap4Ruby::CoverageReport.load(path, analyzed_files: [file])
      end
    end
  end
end
