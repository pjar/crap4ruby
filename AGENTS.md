# crap4ruby — project rules

## Development environment: devenv only

The entire stack must be built, run, tested, and packaged through
[devenv](https://devenv.sh).

- Run every Ruby, Bundler, gem, Rake, and test command inside the devenv shell:
  `devenv shell -- <command>` or an already activated `devenv shell`/direnv
  session. Never invoke the system Ruby or a version manager such as rbenv, asdf,
  or chruby directly.
- The toolchain belongs in `devenv.nix`. When scaffolding the gem, create
  `devenv.nix` and `devenv.yaml` before generating or building the Ruby stack.
  Add new development tools to `devenv.nix`; do not install them globally.
- CI must use the same devenv definition and execute project commands through
  `devenv shell -- <command>`.
- If `devenv.nix` is missing or the shell does not build, repair the devenv
  environment first. Do not fall back to whatever tools happen to be on `PATH`.
