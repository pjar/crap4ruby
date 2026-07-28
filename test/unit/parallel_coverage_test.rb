require_relative "../test_helper"

# §4.3 parallel-coverage mismatch predicate (CRA-49), conjuncts 2–4: the
# Rails `bin/rails test` layout, a receiverless `parallelize` call under
# test/**/*.rb, and the absence of positive syntactic proof of
# `merge_subprocesses true` in .simplecov. Purely static — no runtime
# signal, and the CLI-side conjuncts (--test-command, empty selection)
# are pinned by the conformance tests.
class ParallelCoveragePredicateTest < Minitest::Test
  include Crap4Ruby::SandboxHelper

  PARALLEL_TEST = <<~RUBY
    class WidgetTest
      parallelize(workers: :number_of_processors)
    end
  RUBY

  PLAIN_TEST = <<~RUBY
    class WidgetTest
      def test_widget = nil
    end
  RUBY

  PROOF = <<~RUBY
    SimpleCov.configure do
      enable_coverage :method
      merge_subprocesses true
    end
  RUBY

  def test_fires_with_no_simplecov_file
    rails_root do |root|
      assert mismatch?(root)
    end
  end

  def test_fires_when_simplecov_lacks_the_directive
    rails_root(simplecov: "SimpleCov.configure do\n  enable_coverage :method\nend\n") do |root|
      assert mismatch?(root)
    end
  end

  def test_canonical_proof_clears_it
    rails_root(simplecov: PROOF) do |root|
      refute mismatch?(root)
    end
  end

  def test_cbase_simplecov_constant_is_proof
    rails_root(simplecov: PROOF.sub("SimpleCov", "::SimpleCov")) do |root|
      refute mismatch?(root)
    end
  end

  def test_guarded_directive_is_not_proof
    rails_root(simplecov: <<~RUBY) do |root|
      SimpleCov.configure do
        merge_subprocesses true if ENV["PARALLEL"]
      end
    RUBY
      assert mismatch?(root), "a conditional setting is not a direct statement"
    end
  end

  def test_non_literal_argument_is_not_proof
    rails_root(simplecov: <<~RUBY) do |root|
      SimpleCov.configure do
        flag = true
        merge_subprocesses flag
      end
    RUBY
      assert mismatch?(root)
    end
  end

  def test_last_directive_in_source_order_governs
    rails_root(simplecov: <<~RUBY) do |root|
      SimpleCov.configure do
        merge_subprocesses true
        merge_subprocesses false
      end
    RUBY
      assert mismatch?(root), "the last directive is `false`"
    end

    rails_root(simplecov: <<~RUBY) do |root|
      SimpleCov.configure do
        merge_subprocesses false
        merge_subprocesses true
      end
    RUBY
      refute mismatch?(root), "the last directive is the literal-true form"
    end
  end

  def test_last_directive_across_multiple_configure_blocks_governs
    rails_root(simplecov: PROOF + "SimpleCov.configure do\n  merge_subprocesses false\nend\n") do |root|
      assert mismatch?(root)
    end

    rails_root(simplecov: PROOF + "SimpleCov.configure do\n  enable_coverage :branch\nend\n") do |root|
      refute mismatch?(root), "a later block without the directive leaves the proof standing"
    end
  end

  def test_directive_outside_a_configure_block_is_not_proof
    rails_root(simplecov: "merge_subprocesses true\n") do |root|
      assert mismatch?(root)
    end
  end

  def test_directive_nested_inside_another_block_is_not_proof
    rails_root(simplecov: <<~RUBY) do |root|
      SimpleCov.configure do
        [1].each do
          merge_subprocesses true
        end
      end
    RUBY
      assert mismatch?(root)
    end
  end

  def test_directive_with_a_block_or_extra_argument_is_not_proof
    rails_root(simplecov: "SimpleCov.configure do\n  merge_subprocesses(true) { nil }\nend\n") do |root|
      assert mismatch?(root)
    end

    rails_root(simplecov: "SimpleCov.configure do\n  merge_subprocesses true, :also\nend\n") do |root|
      assert mismatch?(root)
    end
  end

  def test_unparseable_simplecov_is_not_proof
    rails_root(simplecov: "SimpleCov.configure do\n  merge_subprocesses true\n") do |root|
      assert mismatch?(root), "an unparseable .simplecov proves nothing"
    end
  end

  def test_guarded_parallelize_still_counts
    rails_root(test_files: { "test/widget_test.rb" => <<~RUBY }) do |root|
      class WidgetTest
        parallelize(workers: 2) if ENV["PARALLEL"]
      end
    RUBY
      assert mismatch?(root), "declares, not executes"
    end
  end

  def test_parallelize_inside_an_uncalled_def_counts
    rails_root(test_files: { "test/helper.rb" => <<~RUBY }) do |root|
      class Helper
        def self.declare = parallelize(workers: 2)
      end
    RUBY
      assert mismatch?(root)
    end
  end

  def test_def_parallelize_does_not_count
    rails_root(test_files: { "test/widget_test.rb" => "def parallelize(**)\nend\n" }) do |root|
      refute mismatch?(root)
    end
  end

  def test_comment_and_string_mentions_do_not_count
    rails_root(test_files: { "test/widget_test.rb" => <<~RUBY }) do |root|
      # parallelize(workers: 2)
      NOTE = "parallelize(workers: 2)"
    RUBY
      refute mismatch?(root)
    end
  end

  def test_receivered_call_does_not_count
    rails_root(test_files: { "test/widget_test.rb" => "config.parallelize(workers: 2)\n" }) do |root|
      refute mismatch?(root)
    end
  end

  def test_dot_directories_are_not_scanned
    rails_root(test_files: { "test/.generated/widget_test.rb" => PARALLEL_TEST,
                             "test/widget_test.rb" => PLAIN_TEST }) do |root|
      refute mismatch?(root)
    end
  end

  def test_unparseable_test_file_is_skipped
    rails_root(test_files: { "test/broken_test.rb" => "class parallelize(\n",
                             "test/widget_test.rb" => PLAIN_TEST }) do |root|
      refute mismatch?(root)
    end
  end

  def test_no_parallelize_anywhere
    rails_root(test_files: { "test/widget_test.rb" => PLAIN_TEST }) do |root|
      refute mismatch?(root)
    end
  end

  def test_rake_layout_without_bin_rails_never_fires
    rails_root(bin_rails: false) do |root|
      write_file(root, "Rakefile", "task :test\n")
      refute mismatch?(root)
    end
  end

  def test_non_executable_bin_rails_never_fires
    rails_root do |root|
      File.chmod(0o644, File.join(root, "bin/rails"))
      refute mismatch?(root)
    end
  end

  def test_spec_directory_alongside_test_never_fires
    rails_root do |root|
      write_file(root, "spec/widget_spec.rb", PLAIN_TEST)
      refute mismatch?(root)
    end
  end

  private

  def mismatch?(root)
    Crap4Ruby::ParallelCoverage.mismatch?(root)
  end

  def rails_root(simplecov: nil, bin_rails: true,
                 test_files: { "test/widget_test.rb" => PARALLEL_TEST })
    with_sandbox do |root|
      write_file(root, "Gemfile", "source \"https://rubygems.org\"\n")
      test_files.each { |rel, content| write_file(root, rel, content) }
      if bin_rails
        write_file(root, "bin/rails", "#!/bin/sh\n")
        File.chmod(0o755, File.join(root, "bin/rails"))
      end
      write_file(root, ".simplecov", simplecov) if simplecov
      yield root
    end
  end
end
