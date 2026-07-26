require_relative "../test_helper"

class ProjectTest < Minitest::Test
  include Crap4Ruby::SandboxHelper

  def test_locate_walks_up_to_the_nearest_gemfile
    with_sandbox do |root|
      write_file(root, "Gemfile")
      nested = File.join(root, "app", "models")
      FileUtils.mkdir_p(nested)
      assert_equal root, Crap4Ruby::Project.locate(nested).root
    end
  end

  def test_locate_without_gemfile_is_a_usage_error
    with_sandbox do |root|
      assert_failure(1, "no Gemfile") { Crap4Ruby::Project.locate(root) }
    end
  end

  def test_default_selection_globs_app_and_lib
    with_sandbox do |root|
      write_file(root, "Gemfile")
      write_file(root, "app/models/user.rb")
      write_file(root, "lib/util/text.rb")
      write_file(root, "lib/readme.md")
      write_file(root, "script/other.rb")
      project = Crap4Ruby::Project.new(root)
      selected = project.select_files([], changed: false, cwd: root)
      assert_equal [File.join(root, "app/models/user.rb"), File.join(root, "lib/util/text.rb")], selected
    end
  end

  def test_explicit_directory_expands_and_explicit_file_is_kept
    with_sandbox do |root|
      write_file(root, "Gemfile")
      write_file(root, "src/a.rb")
      write_file(root, "src/deep/b.rb")
      write_file(root, "src/notes.txt")
      write_file(root, "one.rb")
      project = Crap4Ruby::Project.new(root)
      selected = project.select_files(["src", "one.rb", "one.rb"], changed: false, cwd: root)
      assert_equal [File.join(root, "one.rb"), File.join(root, "src/a.rb"), File.join(root, "src/deep/b.rb")],
                   selected
    end
  end

  def test_missing_explicit_path_is_a_usage_error
    with_sandbox do |root|
      write_file(root, "Gemfile")
      project = Crap4Ruby::Project.new(root)
      assert_failure(1, "does not exist") { project.select_files(["nope.rb"], changed: false, cwd: root) }
    end
  end

  def test_changed_selects_modified_added_untracked_and_rename_destinations
    with_sandbox do |root|
      write_file(root, "Gemfile")
      git(root, "init", "-q")
      write_file(root, "modified.rb", "old\n")
      write_file(root, "deleted.rb", "gone\n")
      write_file(root, "renamed_from.rb", "content that is long enough for rename detection\n")
      write_file(root, "ignored.txt", "x\n")
      git(root, "add", ".")
      git(root, "commit", "-qm", "base")

      write_file(root, "modified.rb", "new\n")
      File.delete(File.join(root, "deleted.rb"))
      git(root, "mv", "renamed_from.rb", "renamed to.rb") # space exercises -z parsing
      git(root, "add", "modified.rb")
      write_file(root, "untracked.rb", "u\n")
      write_file(root, "untracked.txt", "u\n")

      project = Crap4Ruby::Project.new(root)
      selected = project.select_files([], changed: true, cwd: root)
      assert_equal [File.join(root, "modified.rb"), File.join(root, "renamed to.rb"), File.join(root, "untracked.rb")],
                   selected
    end
  end

  def test_changed_intersects_with_explicit_paths
    with_sandbox do |root|
      write_file(root, "Gemfile")
      git(root, "init", "-q")
      git(root, "add", "Gemfile")
      git(root, "commit", "-qm", "base")
      write_file(root, "app/inside.rb")
      write_file(root, "lib/outside.rb")

      project = Crap4Ruby::Project.new(root)
      selected = project.select_files(["app"], changed: true, cwd: root)
      assert_equal [File.join(root, "app/inside.rb")], selected
    end
  end

  def test_changed_outside_a_git_repository_is_a_usage_error
    with_sandbox do |root|
      write_file(root, "Gemfile")
      project = Crap4Ruby::Project.new(root)
      assert_failure(1, "git") { project.select_files([], changed: true, cwd: root) }
    end
  end

  def test_tree_clean_and_head_sha
    with_sandbox do |root|
      write_file(root, "Gemfile")
      git(root, "init", "-q")
      git(root, "add", ".")
      git(root, "commit", "-qm", "base")
      project = Crap4Ruby::Project.new(root)
      assert project.tree_clean?
      assert_match(/\A[0-9a-f]{40}/, project.head_sha)
      write_file(root, "dirty.rb")
      refute project.tree_clean?
    end
  end
end
