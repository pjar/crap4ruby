require "open3"
require "pathname"

module Crap4Ruby
  # Project root discovery and file selection (spec §2, §3).
  class Project
    # One `git status` parse: the .rb paths a --changed run selects, and
    # the paths git reports as gone (§11.3's freshness scope).
    Porcelain = Struct.new(:selected, :removed, keyword_init: true)

    attr_reader :root

    # Nearest ancestor of cwd (inclusive) containing a Gemfile.
    def self.locate(cwd)
      dir = File.expand_path(cwd)
      loop do
        return new(dir) if File.file?(File.join(dir, "Gemfile"))
        parent = File.dirname(dir)
        raise Failure.new("no Gemfile found in #{cwd} or any ancestor directory", 1) if parent == dir
        dir = parent
      end
    end

    def initialize(root)
      @root = root
    end

    # Absolute, sorted, deduplicated selection. --changed with explicit
    # paths means the intersection (spec §3); --changed alone is not
    # narrowed to app/ and lib/.
    def select_files(paths, changed:, cwd:)
      base = paths.any? ? explicit_selection(paths, cwd) : nil
      selected =
        if changed
          base ? changed_files & base : changed_files
        else
          base || default_selection
        end
      selected.uniq.sort
    end

    def relative(path)
      Pathname.new(path).relative_path_from(Pathname.new(root)).to_s
    rescue ArgumentError
      path
    end

    # §11.3: the explicit arguments as normalized, project-root-relative
    # paths, split by kind — directory arguments sweep their subtree
    # lexically, file arguments match exactly. Both exist by the time this
    # is called (a non-existent explicit path is a usage error, §3), so
    # this is the last place the filesystem is consulted about them.
    def argument_paths(paths, cwd:)
      paths.each_with_object({ directories: [], files: [] }) do |path, split|
        absolute = File.expand_path(path, cwd)
        split[File.directory?(absolute) ? :directories : :files] << relative(absolute)
      end
    end

    # §11.3: paths git reports as gone — deletions and rename origins,
    # project-root-relative. A copy's origin is still there, so it is not
    # one of them.
    def changed_removals = porcelain.removed

    def tree_clean?
      run_git("status", "--porcelain=v1", exit_code: 3).empty?
    end

    def head_sha
      run_git("rev-parse", "HEAD", exit_code: 3).strip
    end

    private

    def explicit_selection(paths, cwd)
      paths.flat_map do |path|
        absolute = File.expand_path(path, cwd)
        if File.directory?(absolute)
          Dir.glob("**/*.rb", base: absolute).sort.map { |f| File.join(absolute, f) }
        elsif File.file?(absolute)
          absolute.end_with?(".rb") ? [absolute] : []
        else
          raise Failure.new("path does not exist: #{path}", 1)
        end
      end
    end

    def default_selection
      %w[app lib].flat_map do |dir|
        base = File.join(root, dir)
        next [] unless File.directory?(base)
        Dir.glob("**/*.rb", base: base).sort.map { |f| File.join(base, f) }
      end
    end

    def changed_files = porcelain.selected

    # One `git status` per run, parsed once and memoized: the selection is
    # taken before the test suite runs, and the §11.3 freshness scope must
    # describe that same tree, not whatever the suite left behind.
    def porcelain
      @porcelain ||= parse_porcelain
    end

    # git status --porcelain=v1 -z (spec §3): NUL-delimited; rename/copy
    # entries carry a second token, the origin path — the destination is
    # what gets selected, while a *rename's* origin is a path that is gone
    # (§11.3). Porcelain paths are relative to the repository toplevel,
    # not the project root.
    def parse_porcelain
      toplevel = run_git("rev-parse", "--show-toplevel", exit_code: 1).strip
      tokens = run_git("status", "--porcelain=v1", "-z", "--untracked-files=all", exit_code: 1).split("\0")
      selected = []
      removed = []
      until tokens.empty?
        entry = tokens.shift
        next if entry.nil? || entry.length < 4
        x, y = entry[0], entry[1]
        path = entry[3..]
        origin = tokens.shift if renamed_or_copied?(x, y)
        removed << relative(File.expand_path(origin, toplevel)) if origin && (x == "R" || y == "R")
        removed << relative(File.expand_path(path, toplevel)) if x == "D" || y == "D"
        next unless selected_status?(x, y) && path.end_with?(".rb")
        selected << File.expand_path(path, toplevel)
      end
      Porcelain.new(selected: selected, removed: removed)
    end

    def renamed_or_copied?(x, y)
      %w[R C].include?(x) || %w[R C].include?(y)
    end

    def selected_status?(x, y)
      return true if x == "U" || y == "U" || (x == "A" && y == "A") || (x == "D" && y == "D")
      [x, y].any? { |s| %w[M A T R C ?].include?(s) }
    end

    def run_git(*args, exit_code:)
      out, _err, status = Open3.capture3("git", *args, chdir: root)
      raise Failure.new("git #{args.first} failed — not a git repository?", exit_code) unless status.success?
      out
    end
  end
end
