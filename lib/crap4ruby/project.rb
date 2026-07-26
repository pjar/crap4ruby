require "open3"
require "pathname"

module Crap4Ruby
  # Project root discovery and file selection (spec §2, §3).
  class Project
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

    # git status --porcelain=v1 -z (spec §3): NUL-delimited; rename/copy
    # entries carry a second token (the origin path), which is skipped —
    # the destination is selected. Porcelain paths are relative to the
    # repository toplevel, not the project root.
    def changed_files
      toplevel = run_git("rev-parse", "--show-toplevel", exit_code: 1).strip
      tokens = run_git("status", "--porcelain=v1", "-z", "--untracked-files=all", exit_code: 1).split("\0")
      files = []
      until tokens.empty?
        entry = tokens.shift
        next if entry.nil? || entry.length < 4
        x, y = entry[0], entry[1]
        path = entry[3..]
        tokens.shift if x == "R" || x == "C" || y == "R" || y == "C"
        next unless selected_status?(x, y) && path.end_with?(".rb")
        files << File.expand_path(path, toplevel)
      end
      files
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
