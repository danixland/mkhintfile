# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-07-05

### Added
- Sourced config file `~/.config/mkhint/config` for all path constants
  (`REPO_DIR`, `HINT_DIR`, new `PACKAGES_DIR`, etc.); the completion script
  sources it too. Missing file keeps previous defaults.

### Changed
- `--check` and `--hintfile` now run `slackrepo build` for packages not yet
  built in `PACKAGES_DIR` and `slackrepo update` for existing ones, instead of
  always `update`.

## [1.0.0] - 2026-07-04

First tagged release. mkhint manages slackrepo hint files: create/update hints,
nvchecker-driven update checks, phantom-dep stripping for -current, and a
listing/review workflow.

### Changed
- **Breaking:** the hint-version flag is now `-V` / `--set-version`. `-v` /
  `--version` now prints the tool's own version and exits.

### Added
- `-v` / `--version` prints `mkhint X.Y.Z`.
- The `--help` header shows the version.
- `-l` colors the newer version cell green and adds a `DelReq` column.
