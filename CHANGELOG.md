# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [1.1.3] - 2026-07-07

### Fixed
- Version bump now rewrites download URLs that use the upstream `-` form of a
  date/tag, not just the packaged `_` form. Previously a hint like exploitdb
  (`VERSION="2026_07_07"`, `DOWNLOAD=".../2026-07-07/..."`) kept its stale URL
  and md5 after `--hintfile -V` / `--new -V`. Both `_` and `-` variants of the
  old→new version are now substituted.

## [1.1.2] - 2026-07-05

### Fixed
- Man page: correct the `--new` description (it strips/comments `.info` fields
  rather than copying it as-is) and add a BASH COMPLETION section.

## [1.1.1] - 2026-07-05

### Added
- `mkhint.1` man page (gzipped, built from `mkhint.1.md` with pandoc) as the
  full reference.
- `--help` now reports whether `~/.config/mkhint/config` is present and sourced.

### Changed
- `--help` is now a compact summary; usage examples, the variable-order note,
  and the exit-code table moved to the man page.
- Reference the current slackrepo home at github.com/aclemons/slackrepo (Andrew
  Clemons), crediting David Spencer (idlemoor) as the original creator.

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
