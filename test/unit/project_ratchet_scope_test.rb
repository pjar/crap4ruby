require_relative "../test_helper"

# §11.3 inputs Project owns: the paths git reports as gone (deletions and
# rename origins, which v1 discarded), and the normalized explicit
# arguments the freshness scope compares lexically.
class ProjectRatchetScopeTest < Minitest::Test
  include Crap4Ruby::SandboxHelper

  def test_changed_removals_carry_deletions_and_rename_origins
    with_sandbox do |root|
      write_file(root, "Gemfile")
      git(root, "init", "-q")
      write_file(root, "lib/deleted.rb", "class D\nend\n")
      write_file(root, "lib/notes.txt", "notes\n")
      write_file(root, "lib/renamed_from.rb", "content that is long enough for rename detection\n")
      write_file(root, "lib/kept.rb", "class K\nend\n")
      git(root, "add", "-A")
      git(root, "commit", "-qm", "base")

      File.delete(File.join(root, "lib/deleted.rb"))
      File.delete(File.join(root, "lib/notes.txt"))
      git(root, "mv", "lib/renamed_from.rb", "lib/renamed to.rb") # space exercises -z parsing
      write_file(root, "lib/kept.rb", "class K\n  def x = 1\nend\n")

      project = Crap4Ruby::Project.new(root)
      assert_equal ["lib/kept.rb", "lib/renamed to.rb"],
                   project.select_files([], changed: true, cwd: root).map { |file| project.relative(file) }
      # Not filtered by extension: the scope is only ever compared against
      # baseline row paths, and a deleted non-.rb path can match none.
      assert_equal ["lib/deleted.rb", "lib/notes.txt", "lib/renamed_from.rb"],
                   project.changed_removals.sort
    end
  end

  def test_removals_are_parsed_once_and_survive_a_tree_change_after_selection
    with_sandbox do |root|
      write_file(root, "Gemfile")
      git(root, "init", "-q")
      write_file(root, "lib/gone.rb", "class G\nend\n")
      git(root, "add", "-A")
      git(root, "commit", "-qm", "base")
      File.delete(File.join(root, "lib/gone.rb"))

      project = Crap4Ruby::Project.new(root)
      assert_empty project.select_files([], changed: true, cwd: root)
      write_file(root, "lib/appeared.rb", "class A\nend\n")
      assert_equal ["lib/gone.rb"], project.changed_removals,
                   "the freshness scope describes the tree the selection was taken from"
    end
  end

  def test_argument_paths_normalizes_and_splits_by_kind
    with_sandbox do |root|
      write_file(root, "Gemfile")
      write_file(root, "app/models/order.rb")
      write_file(root, "lib/one.rb")
      project = Crap4Ruby::Project.new(root)
      split = project.argument_paths(["./app/models", "lib/one.rb"], cwd: root)
      assert_equal ["app/models"], split[:directories]
      assert_equal ["lib/one.rb"], split[:files]
    end
  end
end
