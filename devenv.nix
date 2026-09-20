{ pkgs, ... }:

{
  # crap4ruby toolchain — all commands run through `devenv shell` (see AGENTS.md).
  # Development targets the latest stable CRuby; the supported floor is 3.3
  # (Prism + json as stdlib), exercised separately in CI.
  languages.ruby = {
    enable = true;
    version = "4.0.7";
  };

  packages = [ pkgs.git ];

  enterTest = ''
    ruby --version | grep --color=auto "4.0.7"
    bundle check || bundle install
    bundle exec rake test
  '';
}
