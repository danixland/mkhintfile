# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `--list`/`-l`: new `NoDL` column showing `✓` when a hint carries
  `NODOWNLOAD=yes`, alongside the existing `DelReq` column.
- Bash completion: `-V`/`--set-version` now completes from the SBo `.info`
  VERSION when `-n`/`--new <pkg>` is on the line (previously only from the
  hint's VERSION via `-f`/`--hintfile`).

### Changed
- `nvtake` timing: nvchecker's `oldver` is now synced (via `nvtake`) only when
  you confirm the slackrepo prompt, per package, just before slackrepo runs —
  moved out of the hint-rewrite step in `--check` and out of the version-accept
  step in `--hintfile`. Confirming slackrepo acknowledges the versions; if
  slackrepo is then stopped or fails, rerun it without nvchecker re-reporting
  already-committed versions. Declining slackrepo leaves the hint bumped but the
  update re-reported next run. Fixes the stuck state where interrupting a run
  between hint-rewrite and slackrepo left `oldver` behind the hint, so nvchecker
  logged a phantom "updated" line every subsequent `--check`.

## [1.3.0] - 2026-07-10

### Added
- SHA-mode bundled-dep reconcile (`--check`/`-C`, `--force`, `--new`, `--hintfile`).
  Bundle manifests now carry a 3-field `<pkg> <mode> <rest>` format where mode is
  `url` (neovim-style flat `deps.txt`, version-based) or `sha` (openvino-style git
  submodules pinned by full 40-char commit SHA in `archive/<sha>/` DOWNLOAD lines).
  For sha mode mkhint fetches each submodule's pinned SHA from the GitHub contents
  API (`type=submodule` → `.sha`), matches the hint `DOWNLOAD` line by owner/repo,
  and rewrites + re-md5s any line whose SHA drifted. The report lists each dep as
  `<name> <sha7> (current)` or `<name> <old7> -> <new7>`. Token reused from
  nvchecker's keyfile when present (→ 5000/h), else anonymous.
- Job B submodule inventory (`detect_set_drift`): on a sha-mode bump or `--force`,
  diffs `.gitmodules` at the old and new refs and prints a full roster of every
  submodule tagged `bundled`/`(ignored)` with change glyphs, raising `ACTION` on a
  bundled dep removed upstream and `review` on a new unbundled one. FYI only, never
  edits the bundle set.

## [1.2.6] - 2026-07-09

### Added
- `--info` / `-i <pkg>`: adds a version-compare row between the header and the
  README, comparing the SBo `.info` VERSION against the hint's VERSION. Shows
  `SBo: x < Hint: y` (or `>`) greening the higher side, `SBo: x = Hint: y` in
  yellow when equal, or `SBo: x  (no hint)` when no hint carries a version.
  Skipped when the `.info` has no VERSION. Header stays pinned; the version row
  scrolls with the README.

### Fixed
- Bash completion: `--info`/`-i` now completes package names from the repo
  (previously fell through to flag completion). Package-name completion for
  `--new`/`-n` and `-i` no longer relies on a `-maxdepth 2` `.info` scan that
  matched nothing on the real `category/pkg/pkg.info` layout; it enumerates the
  `REPO_DIR/*/*/` package dirs with pure param-expansion (no per-dir `basename`
  fork), cutting completion time from ~7s to ~60ms on a full repo.

## [1.2.5] - 2026-07-09

### Added
- `--info` / `-i <pkg>`: shows a package's `category/program` path (green on a
  TTY) followed by its README, paged with a sticky header (`less --header=1`)
  only when the README is taller than the terminal. Missing package exits 2;
  missing README prints `(no README)` and exits 0. Mutually exclusive with
  `-V`/`-f`/`-n`.

### Changed
- `--new` / `-n` now prints the nvchecker stanza it manages on stdout, fenced,
  whether it was just added or was already present, so the effect of the
  autodetection is visible immediately instead of only living in the config
  file.
- Expanded nvchecker source autodetection (`_detect_nvchecker_source`) beyond
  github and pypi to also recognize gitlab, bitbucket, gitea, codeberg, and
  pagure owner/repo URLs, and the npm, gems, crates.io, cpan, hackage,
  packagist, and cran registries. Registry sources parse the package name from
  the URL where possible, falling back to `PRGNAM`.

## [1.2.4] - 2026-07-08

### Changed
- On a primary version bump of a manifest-listed package, the interactive
  continuation-URL prompt is now suppressed: those extra `DOWNLOAD` lines are
  owned by Phase 2 (`reconcile_bundle_deps`), so hand-editing them during the
  bump was a pointless double-touch. Non-listed packages still prompt as before.
  Threaded via a `skip_cont` flag through `update_hint_file` →
  `update_checksums` → `_process_download_var`.

### Fixed
- `update_hint_file` no longer aborts (`set -e`) right after backing up when the
  package has no bundle manifest: the manifest-lookup guard was written as
  `pkg_has_manifest ... && x=1`, whose false result killed the run. This would
  have broken every non-listed `--hintfile -V` update.

## [1.2.3] - 2026-07-08

### Fixed
- The bundled-dep reconcile no longer prompts `Apply bundled-dep updates?`
  when nothing changed. Report mode now signals whether there is anything to
  apply (exit 2 = changes, 0 = all current / no deps / fetch fail), and the
  `--check` and `--hintfile -V` callers only prompt when there is. Previously a
  `--force` run on an up-to-date bundle package always asked, with nothing to
  do.

## [1.2.2] - 2026-07-08

### Fixed
- Completes the 1.2.1 version-aware reconcile against real-world URL shapes.
  Verified against all 13 bundled deps of the live neovim 0.12.4 hint; 1.2.1's
  `_url_version` mis-parsed several of them and 1.2.1 was never correct in the
  field.
- `_url_version` now derives the version by stripping the URL's own github repo
  name from the basename, so dep names that themselves contain digits/dashes
  (e.g. `lua-compat-5.3`) parse correctly instead of splitting the name as a
  version. A bare-tag basename (no name prefix) is taken as the whole version,
  which fixes package-rev suffixes like `luv` `1.52.1-0` being truncated to `0`.
  Non-github hosts and the shared `neovim/deps` blob host fall back to the
  trailing-version/sha heuristic.
- `_url_repo` is now lowercased, so a dep that appears as `JuliaStrings/utf8proc`
  in the hint and `juliastrings/utf8proc` in the manifest matches (github
  owners/repos are case-insensitive) instead of being reported as unmatched and
  duplicated in the manifest-only FYI.

## [1.2.1] - 2026-07-08

### Fixed
- Bundled-dep reconcile detects change by upstream version, not raw URL string.
  Manifests serve bare-tag archive URLs (`.../archive/v0.26.7.tar.gz`) while
  hints use the SBo-fetched tree shape
  (`.../archive/v0.26.7/tree-sitter-0.26.7.tar.gz`); these are the same version
  in different path shapes, so the old string comparison flagged every dep as
  changed at a version that had not moved. Reconcile now extracts the version
  from each URL (`_url_version`) and only rewrites a line when the version
  actually differs. (URL-shape parsing was incomplete in this release; see
  1.2.2.)
- The changed-deps report now shows `name old-ver -> new-ver` from the parsed
  identity and version, instead of version-stripped URL basenames.

## [1.2.0] - 2026-07-07

### Added
- Manifest-driven bundled-dep updates. Packages listed in the new
  `BUNDLE_MANIFEST_FILE` (`<pkg> <deps-url-template>`) have their extra
  `DOWNLOAD` lines reconciled against an upstream deps manifest (e.g. neovim's
  `cmake.deps/deps.txt`) during `--check`: matched lines are rewritten to the
  manifest's pinned URLs and their checksums recomputed. `--new` reports the
  reconcile without changing the hint.
- `--force` flag (check-only): run the bundled-dep reconcile even when the
  primary version is unchanged (e.g. to retry after a failed manifest fetch).
- The bundled-dep reconcile writes a `.bak` before mutating a hint (parity with
  every other mutator, so a `--force` reconcile is recoverable), and its change
  report shows old and new URL basenames so version bumps are visible before you
  confirm.

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
