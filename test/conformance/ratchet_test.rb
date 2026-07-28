require_relative "../test_helper"

# §9.3 conformance corpus — the baseline ratchet (spec §11, CRA-51).
#
# Every case drives the public CLI contract. Full-pipeline cases execute a
# sandbox project's real suite under `simplecov run` (the
# PipelineIntegrationTest pattern); validation and empty-selection cases run
# against bare sandboxes with a sentinel coverage artifact, pinning that they
# abort before cleanup and before any test execution.
#
# Seed baselines the CLI *reads* are compact JSON — valid but non-canonical —
# so "file untouched" assertions prove the file was not rewritten. Expected
# *written* baselines are literal heredocs, never produced by a serializer,
# so the canonical-serialization pins of §11.2 have no shared oracle with the
# implementation.
#
# Stored-row components recompute per §11.2 in exact arithmetic:
#   comp 3, units 10, hits 1    ->  9*(9/10)^3  + 3 = 9.561      displays 9.56
#   comp 4, units  9, hits 0    -> 16           + 4 = 20
#   comp 8, units 450, hits 449 -> 64/91125000  + 8 = 8.0000007  displays 8.00
# Current-row components come from the engineered sources below, verified
# against a real SimpleCov 1.0.3 report (never-loaded files carry simulated
# line AND branch entries, so an unloaded offender still owns its arms):
#   Mess#tangle   comp 3, units 9 (5 lines + 4 arms), hits 0 -> CRAP 12
#   Mess#tangle2  same shape at line 13 -> CRAP 12 (canonical row ordering)
#   Tie#tie       comp 4, units 73 (73 lines, 0 arms), hits 27
#                 -> 16*(46/73)^3 + 4 = 8.00336…, displaying 8.00 — the
#                 §9.3 "8.00 > 8.00 baselined" display-tie worsening
#   Weird#t\tb    comp 3, units 9, hits 0 -> CRAP 12 (tab inside the identity
#                 exercises §11.3's control-byte escaping)
#   DD#d (twice)  comp 3 each, units 0, uncalled -> CRAP 12, one shared full
#                 key — §11.5's duplicate-key analysis failure
class RatchetConformanceTest < Minitest::Test
  include Crap4Ruby::SandboxHelper

  BUNDLE_PATH = ENV.fetch("BUNDLE_PATH") { File.expand_path("../../.devenv/state/.bundle", __dir__) }
  BASELINE = "crap4ruby-baseline.json".freeze

  GEMFILE = <<~RUBY
    source "https://rubygems.org"
    gem "minitest"
    gem "rake"
    gem "simplecov", ">= 1.0"
  RUBY

  RAKEFILE = <<~RUBY
    require "rake/testtask"
    Rake::TestTask.new(:test) do |t|
      t.libs << "test" << "lib"
      t.test_files = FileList["test/**/*_test.rb"]
    end
    task default: :test
  RUBY

  SIMPLECOV = <<~RUBY
    SimpleCov.configure do
      enable_coverage :branch
      enable_coverage :method
      cover "lib/**/*.rb"
    end
  RUBY

  CALC = <<~RUBY
    class Calc
      def sign(x)
        if x > 0
          :pos
        else
          :neg
        end
      end
    end
  RUBY

  CALC_TEST = <<~RUBY
    require "minitest/autorun"
    require_relative "../lib/calc"

    class CalcTest < Minitest::Test
      def test_both_branches
        assert_equal :pos, Calc.new.sign(3)
        assert_equal :neg, Calc.new.sign(-1)
      end
    end
  RUBY

  CALC_TIE_TEST = <<~RUBY
    require "minitest/autorun"
    require_relative "../lib/calc"
    require_relative "../lib/tie"

    class CalcTest < Minitest::Test
      def test_both_branches
        assert_equal :pos, Calc.new.sign(3)
        assert_equal :neg, Calc.new.sign(-1)
      end

      def test_tie_raises_halfway
        assert_raises(RuntimeError) { Tie.new.tie(1) }
      end
    end
  RUBY

  MESS = <<~RUBY
    class Mess
      def tangle(a, b)
        if a
          if b
            :ab
          else
            :a
          end
        else
          :none
        end
      end
    end
  RUBY

  MESS_TWO = <<~RUBY
    class Mess
      def tangle(a, b)
        if a
          if b
            :ab
          else
            :a
          end
        else
          :none
        end
      end
      def tangle2(c, d)
        if c
          if d
            :cd
          else
            :c
          end
        else
          :none
        end
      end
    end
  RUBY

  # comp 4 (three ||), 73 owned relevant lines, no branch arms (§7.5); the
  # raise truncates execution after 27 of them.
  TIE = begin
    lines = ["class Tie", "  def tie(flag)"]
    lines += (0..2).map { |i| "    _s#{i} = flag || #{i}" }
    lines += (1..23).map { |i| "    _a#{i} = #{i}" }
    lines << '    raise "half"'
    lines += (1..46).map { |i| "    _b#{i} = #{i}" }
    (lines + ["  end", "end", ""]).join("\n")
  end

  DD = <<~RUBY
    class DD
      def d(x) = x || x || x; def d(x) = x || x || x
    end
  RUBY

  WEIRD = <<~'RUBY'
    class Weird
      define_method(:"t\tb") do |x|
        if x
          if x > 1
            1
          else
            2
          end
        else
          3
        end
      end
    end
  RUBY

  OTHER = <<~RUBY
    class Other
      def noop = nil
    end
  RUBY

  EXPECTED_EMPTY = <<~JSON
    {
      "schema_version": "1.0",
      "metric_version": 1,
      "rows": []
    }
  JSON

  EXPECTED_MESS_ONLY = <<~JSON
    {
      "schema_version": "1.0",
      "metric_version": 1,
      "rows": [
        {
          "path": "lib/mess.rb",
          "identity": "Mess#tangle",
          "line": 2,
          "comp": 3,
          "units": 9,
          "hits": 0,
          "called": false
        }
      ]
    }
  JSON

  # Single-quoted heredoc: the \t must land in the file as the two-byte JSON
  # escape, not a literal tab (§11.2's RFC 8259 short-escape pin).
  EXPECTED_TRIO = <<~'JSON'
    {
      "schema_version": "1.0",
      "metric_version": 1,
      "rows": [
        {
          "path": "lib/mess.rb",
          "identity": "Mess#tangle",
          "line": 2,
          "comp": 3,
          "units": 9,
          "hits": 0,
          "called": false
        },
        {
          "path": "lib/mess.rb",
          "identity": "Mess#tangle2",
          "line": 13,
          "comp": 3,
          "units": 9,
          "hits": 0,
          "called": false
        },
        {
          "path": "lib/weird.rb",
          "identity": "Weird#t\tb",
          "line": 2,
          "comp": 3,
          "units": 9,
          "hits": 0,
          "called": false
        }
      ]
    }
  JSON

  # --- §11.3 gate classification ------------------------------------------

  def test_new_offender
    with_full_project(files: { "lib/mess.rb" => MESS, "lib/weird.rb" => WEIRD }) do |root|
      write_baseline(root, seed([]))
      out, err, code = run_cli([], root)
      assert_includes out, "Mess#tangle"
      assert_includes out, "12.00"
      assert_equal "baseline: new offender Mess#tangle (lib/mess.rb:2) CRAP 12.00\n" \
                   "baseline: new offender Weird#t\\tb (lib/weird.rb:2) CRAP 12.00\n", err
      assert_equal 2, code
    end
  end

  def test_worsened_exact
    with_full_project(files: { "lib/mess.rb" => MESS }) do |root|
      write_baseline(root, seed([mess_lower_row]))
      out, err, code = run_cli([], root)
      assert_includes out, "Mess#tangle"
      assert_equal "baseline: worsened Mess#tangle (lib/mess.rb:2) CRAP 12.00 > 9.56 baselined\n", err
      assert_equal 2, code
    end
  end

  def test_worsened_exact_display_tie
    with_full_project(files: { "lib/tie.rb" => TIE }, test_body: CALC_TIE_TEST) do |root|
      write_baseline(root, seed([tie_stored_row]))
      out, err, code = run_cli([], root)
      assert_includes out, "Tie#tie"
      assert_includes out, "37.0"
      assert_equal "baseline: worsened Tie#tie (lib/tie.rb:2) CRAP 8.00 > 8.00 baselined\n", err
      assert_equal 2, code
    end
  end

  def test_grandfathered_exact_equal
    with_full_project(files: { "lib/mess.rb" => MESS }) do |root|
      write_baseline(root, seed([mess_current_row]))
      out, err, code = run_cli([], root)
      assert_includes out, "12.00", "grandfathered rows still appear in the report"
      assert_equal "", err
      assert_equal 0, code
    end
  end

  def test_improved_row
    with_full_project(files: { "lib/mess.rb" => MESS }) do |root|
      write_baseline(root, seed([mess_higher_row]))
      _out, err, code = run_cli([], root)
      assert_equal "", err
      assert_equal 0, code

      out, err, code = run_cli(["--update-baseline"], root)
      assert out.start_with?("Method"), "the report table is the only stdout, got: #{out.inspect}"
      assert_equal "", err
      assert_equal 0, code
      assert_equal EXPECTED_MESS_ONLY, read_baseline(root), "shrink rewrites the improved row canonically"
    end
  end

  def test_stale_row_full_run
    with_full_project do |root|
      write_baseline(root, seed([calc_gone_row]))
      out, err, code = run_cli([], root)
      assert_includes out, "Calc#sign"
      assert_equal "baseline: stale row Calc#gone (lib/calc.rb:99) — no longer failing here; run --update-baseline\n", err
      assert_equal 3, code
    end
  end

  def test_stale_via_deleted_file
    with_full_project do |root|
      write_baseline(root, seed([row(path: "lib/deleted.rb", identity: "Gone#gone", line: 2, comp: 3, units: 10, hits: 1)]))
      _out, err, code = run_cli([], root)
      assert_equal "baseline: stale row Gone#gone (lib/deleted.rb:2) — no longer failing here; run --update-baseline\n", err
      assert_equal 3, code
    end
  end

  def test_renamed_method_new_plus_stale
    with_full_project(files: { "lib/mess.rb" => MESS }) do |root|
      write_baseline(root, seed([row(path: "lib/mess.rb", identity: "Mess#twisted", line: 2, comp: 3, units: 10, hits: 1)]))
      _out, err, code = run_cli([], root)
      assert_equal "baseline: new offender Mess#tangle (lib/mess.rb:2) CRAP 12.00\n" \
                   "baseline: stale row Mess#twisted (lib/mess.rb:2) — no longer failing here; run --update-baseline\n", err
      assert_equal 3, code, "stale takes precedence over new/worsened"
    end
  end

  def test_changed_scoped_ratchet
    with_full_project(files: { "lib/other.rb" => OTHER }, git_init: true) do |root|
      write_baseline(root, seed([calc_gone_row]))
      write_file(root, "lib/other.rb", OTHER + "# touched\n")

      out, err, code = run_cli(["--changed"], root)
      assert_includes out, "Other#noop"
      assert_equal "", err, "rows outside the --changed freshness scope are unchecked"
      assert_equal 0, code

      _out, err, code = run_cli([], root)
      assert_equal "baseline: stale row Calc#gone (lib/calc.rb:99) — no longer failing here; run --update-baseline\n", err
      assert_equal 3, code, "the authoritative full run sees the staleness"
    end
  end

  def test_changed_dir_composition_keeps_unchanged_offender
    with_full_project(files: { "lib/mess.rb" => MESS, "lib/other.rb" => OTHER }, git_init: true) do |root|
      write_baseline(root, seed([mess_current_row]))
      write_file(root, "lib/other.rb", OTHER + "# touched\n")
      out, err, code = run_cli(["--changed", "lib"], root)
      assert_includes out, "Other#noop"
      refute_includes out, "Mess#tangle", "unchanged file is not analyzed"
      assert_equal "", err, "composition keeps the --changed scope — no directory sweep"
      assert_equal 0, code
    end
  end

  def test_duplicate_row_key_under_ratchet
    with_full_project(files: { "lib/dd.rb" => DD }) do |root|
      write_baseline(root, seed([]))
      _out, err, code = run_cli([], root)
      assert_equal 3, code, "duplicate full key among reportable rows is an analysis failure"
      refute_equal "", err
    end
  end

  # --- §11.4 --update-baseline --------------------------------------------

  def test_update_initial_creation
    with_full_project(files: { "lib/mess.rb" => MESS_TWO, "lib/weird.rb" => WEIRD }) do |root|
      out, err, code = run_cli(["--update-baseline"], root)
      assert out.start_with?("Method"), "the report table is the only stdout, got: #{out.inspect}"
      assert_equal "", err
      assert_equal 0, code
      assert_equal EXPECTED_TRIO, read_baseline(root)
    end
  end

  def test_update_writes_empty_rows
    with_full_project do |root|
      write_baseline(root, seed([calc_gone_row]))
      _out, err, code = run_cli(["--update-baseline"], root)
      assert_equal "", err
      assert_equal 0, code
      assert_equal EXPECTED_EMPTY, read_baseline(root), "stale rows are permitted removals; zero debt stays engaged"
    end
  end

  def test_update_refuses_growth_new_key
    with_full_project(files: { "lib/mess.rb" => MESS }) do |root|
      untouched = seed([])
      write_baseline(root, untouched)
      out, _err, code = run_cli(["--update-baseline"], root)
      assert_includes out, "Mess#tangle", "the full run happens before the refusal"
      assert_equal 2, code
      assert_equal untouched, read_baseline(root), "refused write leaves the file byte-for-byte untouched"
    end
  end

  def test_update_refuses_growth_worsened_key
    with_full_project(files: { "lib/mess.rb" => MESS }) do |root|
      untouched = seed([mess_lower_row])
      write_baseline(root, untouched)
      _out, _err, code = run_cli(["--update-baseline"], root)
      assert_equal 2, code
      assert_equal untouched, read_baseline(root)
    end
  end

  def test_update_initial_creation_rejects_invalid_rows
    with_full_project(files: { "lib/dd.rb" => DD }) do |root|
      _out, _err, code = run_cli(["--update-baseline"], root)
      assert_equal 3, code, "duplicate keys in the would-be-written rows abort"
      refute File.exist?(File.join(root, BASELINE)), "no write on validation failure"
    end
  end

  def test_update_composes_with_no_run
    with_full_project(files: { "lib/mess.rb" => MESS }, git_init: true) do |root|
      _out, _err, code = run_cli([], root)
      assert_equal 2, code, "plain v1 gate produces the trusted artifact"

      out, err, code = run_cli(["--update-baseline", "--no-run"], root)
      assert out.start_with?("Method")
      assert_equal "", err
      assert_equal 0, code
      assert_equal EXPECTED_MESS_ONLY, read_baseline(root)
      assert File.file?(File.join(root, "coverage/coverage.json")), "--no-run never deletes the report"
    end
  end

  def test_update_refuses_partial_selection
    # A malformed baseline proves option validation precedes baseline
    # validation (§4.1 step 1); "unknown option" would mean the flag itself
    # was not accepted (§11.1).
    untouched = seed([]).sub("]", "],\"notes\":[]")
    with_bare_project(files: { "lib/mess.rb" => MESS }) do |root|
      write_baseline(root, untouched)
      [["--update-baseline", "lib"], ["--update-baseline", "--changed"]].each do |argv|
        _out, err, code = run_cli(argv, root)
        assert_equal 1, code, "#{argv.join(" ")} is a usage error"
        refute_match(/unknown option/, err, "--update-baseline must be an accepted flag")
      end
      assert_equal untouched, read_baseline(root)
    end
  end

  # --- §11.1 / §11.2 engagement and validation ----------------------------

  def test_coverage_file_aliases_baseline
    with_bare_project(files: { "lib/mess.rb" => MESS }) do |root|
      untouched = seed([mess_lower_row])
      write_baseline(root, untouched)
      [BASELINE, "./#{BASELINE}", File.join(root, BASELINE)].each do |alias_path|
        _out, _err, code = run_cli(["--coverage-file", alias_path], root)
        assert_equal 1, code, "aliasing via #{alias_path.inspect} is a usage error"
        assert_equal untouched, read_baseline(root), "checked before cleanup — the baseline survives"
      end
    end

    with_bare_project(files: { "lib/mess.rb" => MESS }) do |root|
      _out, _err, code = run_cli(["--update-baseline", "--coverage-file", BASELINE], root)
      assert_equal 1, code, "the guard also fires with no baseline present under --update-baseline"
      refute File.exist?(File.join(root, BASELINE))
    end
  end

  def test_malformed_baseline
    variants = {
      "unknown top-level key" => JSON.generate({ "schema_version" => "1.0", "metric_version" => 1, "rows" => [], "notes" => [] }),
      "missing metric_version" => JSON.generate({ "schema_version" => "1.0", "rows" => [] }),
      "unknown row key" => seed([mess_lower_row.merge("extra" => 1)]),
      "missing row key" => seed([mess_lower_row.reject { |k, _| k == "hits" }]),
      "wrong line type" => seed([mess_lower_row.merge("line" => "2")]),
      "wrong called type" => seed([mess_lower_row.merge("called" => 0)]),
      "duplicate row keys" => seed([mess_lower_row, mess_lower_row]),
      "row at or under threshold" => seed([row(path: "lib/mess.rb", identity: "Mess#tangle", line: 2, comp: 2, units: 1, hits: 0)]),
      "duplicate member names" => '{"schema_version":"1.0","metric_version":1,"metric_version":1,"rows":[]}',
      "future major schema" => seed([], schema: "2.0"),
      "leading-dot path" => seed([mess_lower_row.merge("path" => "./lib/mess.rb")]),
      "absolute path" => seed([mess_lower_row.merge("path" => "/lib/mess.rb")]),
      "dot-dot segment" => seed([mess_lower_row.merge("path" => "lib/../lib/mess.rb")]),
      "empty segment" => seed([mess_lower_row.merge("path" => "lib//mess.rb")]),
      "called true with units" => seed([mess_lower_row.merge("called" => true)]),
      "hits above units" => seed([mess_lower_row.merge("hits" => 11)]),
      "comp zero" => seed([mess_lower_row.merge("comp" => 0)]),
      "line zero" => seed([mess_lower_row.merge("line" => 0)]),
      "units zero with hits" => seed([mess_lower_row.merge("units" => 0)]),
      "rows not an array" => '{"schema_version":"1.0","metric_version":1,"rows":{}}',
      "top level not an object" => "[]",
      "not JSON at all" => "nonsense {"
    }
    variants.each do |label, content|
      with_bare_project(files: { "lib/mess.rb" => MESS }) do |root|
        write_baseline(root, content)
        write_file(root, "coverage/coverage.json", "SENTINEL")
        _out, _err, code = run_cli([], root)
        assert_equal 3, code, "#{label}: exit 3"
        assert_equal "SENTINEL", File.read(File.join(root, "coverage/coverage.json")),
                     "#{label}: validated before cleanup — the stale artifact survives"
      end
    end
  end

  def test_malformed_baseline_beats_empty_selection
    with_bare_project do |root|
      write_baseline(root, JSON.generate({ "schema_version" => "1.0", "metric_version" => 1, "rows" => [], "notes" => [] }))
      out, _err, code = run_cli([], root)
      assert_equal 3, code
      refute_includes out, "nothing to analyze", "validation precedes the empty-selection check"
    end
  end

  def test_metric_version_mismatch
    with_bare_project(files: { "lib/mess.rb" => MESS }) do |root|
      untouched = seed([], metric: 2)
      write_baseline(root, untouched)
      _out, _err, code = run_cli([], root)
      assert_equal 3, code, "gate mode rejects the mismatch"
      _out, _err, code = run_cli(["--update-baseline"], root)
      assert_equal 3, code, "a metric-mismatched file is not initial creation"
      assert_equal untouched, read_baseline(root)
    end
  end

  def test_later_1x_schema_accepted
    with_full_project do |root|
      write_baseline(root, seed([], schema: "1.1"))
      _out, err, code = run_cli([], root)
      assert_equal "", err
      assert_equal 0, code
    end
  end

  def test_baseline_symlink_refused
    with_bare_project(files: { "lib/mess.rb" => MESS }) do |root|
      target = seed([])
      write_file(root, "elsewhere.json", target)
      File.symlink("elsewhere.json", File.join(root, BASELINE))
      _out, _err, code = run_cli([], root)
      assert_equal 3, code, "a symlink neither engages nor is ignored — read path refusal"
      _out, _err, code = run_cli(["--update-baseline"], root)
      assert_equal 3, code, "write path refusal"
      assert_equal target, File.read(File.join(root, "elsewhere.json")), "the symlink target survives"
      assert File.symlink?(File.join(root, BASELINE))
    end

    with_bare_project(files: { "lib/mess.rb" => MESS }) do |root|
      Dir.mkdir(File.join(root, BASELINE))
      _out, _err, code = run_cli([], root)
      assert_equal 3, code, "a non-regular file at the baseline path is refused"
    end
  end

  # --- §11.4 empty selections ---------------------------------------------

  def test_empty_full_selection_stales_all
    with_bare_project do |root|
      write_baseline(root, seed([mess_lower_row]))
      out, err, code = run_cli([], root)
      assert_equal "nothing to analyze\n", out
      assert_equal "baseline: stale row Mess#tangle (lib/mess.rb:2) — no longer failing here; run --update-baseline\n", err
      assert_equal 3, code
    end

    with_bare_project do |root|
      write_baseline(root, seed([]))
      out, err, code = run_cli([], root)
      assert_equal "nothing to analyze\n", out
      assert_equal "", err
      assert_equal 0, code
    end
  end

  def test_update_empty_full_selection_writes_empty_baseline
    with_bare_project do |root|
      out, err, code = run_cli(["--update-baseline"], root)
      assert_equal "nothing to analyze\n", out
      assert_equal "", err
      assert_equal 0, code
      assert_equal EXPECTED_EMPTY, read_baseline(root), "initial creation engages the ratchet at zero debt"
    end

    with_bare_project do |root|
      write_baseline(root, seed([mess_lower_row]))
      out, err, code = run_cli(["--update-baseline"], root)
      assert_equal "nothing to analyze\n", out
      assert_equal "", err
      assert_equal 0, code
      assert_equal EXPECTED_EMPTY, read_baseline(root), "stale rows are removals, not staleness failures, in update mode"
    end
  end

  def test_changed_empty_selection_deletion_goes_stale
    with_bare_project(files: { "lib/gone.rb" => OTHER }) do |root|
      git(root, "init", "-q")
      git(root, "add", "-A")
      git(root, "commit", "-qm", "init")
      write_baseline(root, seed([row(path: "lib/gone.rb", identity: "Gone#g", line: 2, comp: 3, units: 10, hits: 1)]))
      File.delete(File.join(root, "lib/gone.rb"))
      out, err, code = run_cli(["--changed"], root)
      assert_equal "nothing to analyze\n", out
      assert_equal "baseline: stale row Gone#g (lib/gone.rb:2) — no longer failing here; run --update-baseline\n", err
      assert_equal 3, code, "git-reported deletions stay in the --changed freshness scope"
    end
  end

  # --- surface ------------------------------------------------------------

  def test_help_mentions_update_baseline
    with_bare_project do |root|
      out, _err, code = run_cli(["--help"], root)
      assert_equal 0, code
      assert_includes out, "--update-baseline"
    end
  end

  private

  def run_cli(argv, root)
    stdout = StringIO.new
    stderr = StringIO.new
    code = Crap4Ruby::CLI.run(argv, stdout: stdout, stderr: stderr, cwd: root)
    [stdout.string, stderr.string, code]
  end

  def row(path:, identity:, line:, comp:, units:, hits:, called: false)
    { "path" => path, "identity" => identity, "line" => line,
      "comp" => comp, "units" => units, "hits" => hits, "called" => called }
  end

  def mess_current_row = row(path: "lib/mess.rb", identity: "Mess#tangle", line: 2, comp: 3, units: 9, hits: 0)
  def mess_lower_row = row(path: "lib/mess.rb", identity: "Mess#tangle", line: 2, comp: 3, units: 10, hits: 1)
  def mess_higher_row = row(path: "lib/mess.rb", identity: "Mess#tangle", line: 2, comp: 4, units: 9, hits: 0)
  def calc_gone_row = row(path: "lib/calc.rb", identity: "Calc#gone", line: 99, comp: 3, units: 10, hits: 1)
  def tie_stored_row = row(path: "lib/tie.rb", identity: "Tie#tie", line: 2, comp: 8, units: 450, hits: 449)

  def seed(rows, schema: "1.0", metric: 1)
    JSON.generate({ "schema_version" => schema, "metric_version" => metric, "rows" => rows })
  end

  def write_baseline(root, content)
    write_file(root, BASELINE, content)
  end

  def read_baseline(root)
    File.read(File.join(root, BASELINE), encoding: Encoding::UTF_8)
  end

  def with_full_project(files: {}, test_body: CALC_TEST, git_init: false)
    with_sandbox do |root|
      write_file(root, "Gemfile", GEMFILE)
      write_file(root, ".bundle/config", "---\nBUNDLE_PATH: \"#{BUNDLE_PATH}\"\n")
      write_file(root, "Rakefile", RAKEFILE)
      write_file(root, ".simplecov", SIMPLECOV)
      write_file(root, ".gitignore", "coverage/\n.bundle/\nGemfile.lock\n")
      write_file(root, "lib/calc.rb", CALC)
      write_file(root, "test/calc_test.rb", test_body)
      files.each { |rel, content| write_file(root, rel, content) }

      Bundler.with_unbundled_env do
        _out, err, status = Open3.capture3("bundle", "install", "--local", "--quiet", chdir: root)
        raise "sandbox bundle install failed: #{err}" unless status.success?
      end

      if git_init
        git(root, "init", "-q")
        git(root, "add", "-A")
        git(root, "commit", "-qm", "init")
      end
      yield root
    end
  end

  def with_bare_project(files: {})
    with_sandbox do |root|
      write_file(root, "Gemfile", GEMFILE)
      files.each { |rel, content| write_file(root, rel, content) }
      yield root
    end
  end
end
