require_relative "../test_helper"

# Drift guard: every option flag and exit code the README's Usage section
# advertises must appear in the CLI's USAGE text, so README and CLI cannot
# silently diverge.
class ReadmeDriftTest < Minitest::Test
  README = File.read(File.expand_path("../../README.md", __dir__), encoding: Encoding::UTF_8)

  def test_every_readme_usage_flag_appears_in_cli_usage
    flags = usage_section.scan(/--[a-z][a-z-]*/).uniq
    refute_empty flags, "README Usage section lists no flags — parsing broke"
    flags.each do |flag|
      assert_includes Crap4Ruby::CLI::USAGE, flag,
                      "README advertises #{flag} but CLI USAGE does not mention it"
    end
  end

  def test_every_readme_exit_code_appears_in_cli_usage
    codes = usage_section.scan(/`(\d)`/).flatten.uniq
    assert_equal %w[0 1 2 3 4], codes.sort, "README exit-code list changed shape"
    usage_exit_line = Crap4Ruby::CLI::USAGE[/Exit codes:.*/]
    refute_nil usage_exit_line
    codes.each do |code|
      assert_match(/#{code} /, usage_exit_line,
                   "README advertises exit code #{code} but CLI USAGE does not")
    end
  end

  private

  def usage_section
    section = README[/^## Usage\n(.*?)(?=^## )/m, 1]
    refute_nil section, "README must have a Usage section"
    section
  end
end
