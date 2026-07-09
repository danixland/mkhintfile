# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

`mkhint` — bash utility for managing [slackrepo](https://github.com/aclemons/slackrepo) hint files. Hint files override build variables (version, download URL, checksum) for SlackBuilds.

## Configuration

The tool version is a `readonly MKHINT_VERSION` constant near the top of `mkhint`. `-v` / `--version` prints `mkhint <version>` and exits; the `--help` header shows it too. Setting a hint's version string uses `-V` / `--set-version` (renamed from the old `-v`). Project follows SemVer; releases tagged `vX.Y.Z`, bump `MKHINT_VERSION` in the tagging commit. See `CHANGELOG.md`.

Two paths hardcoded near top of `mkhint` (lines 16–17):

```bash
REPO_DIR="/var/lib/sbopkg/SBo-danix/"      # SBo repository with .info files
HINT_DIR="/etc/slackrepo/SBo-danix/hintfiles/"  # where .hint files live
```

Both `mkhint` and the bash completion script now source `~/.config/mkhint/config`, so their path constants no longer drift.

An optional sourced config file `~/.config/mkhint/config` (plain bash `KEY="value"`) is read right after the baked-in defaults, overriding any of: `REPO_DIR`, `HINT_DIR`, `PACKAGES_DIR` (default `/repo/`, the built-package repository holding `*.txz` files), `NVCHECKER_CONFIG`, `PHANTOM_DEPS_FILE`, `BUNDLE_MANIFEST_FILE`, `TMP_DIR`. A missing file leaves the previous defaults in place. Loaded via `MKHINT_CONFIG` / `[[ -f "$MKHINT_CONFIG" ]] && source`; the completion script sources the same file so the two stay in sync.

nvchecker config path is read from `$HOME/.config/nvchecker/nvchecker.toml` (not hardcoded):

```bash
NVCHECKER_CONFIG="$HOME/.config/nvchecker/nvchecker.toml"
```

User must set up the `[__config__]` section once before version-checking features work. Bash completion now also knows `--check`/`-C` and `--fix-current`/`-F`.

Phantom-dep list (deps needed on Slackware stable but not on -current, e.g. `rust-opt`,
`google-go-lang`) is read at runtime from a plain file, one dep per line, `#` comments allowed:

```bash
PHANTOM_DEPS_FILE="$HOME/.config/mkhint/phantom-deps"
```

Missing file = empty list = phantom-dep handling is a no-op. Consumed by `--fix-current` and `--new`.

## Running / Testing

No build step. Direct execution:

```bash
bash mkhint --help
bash mkhint --list                         # highlight hints whose version matches SBo .info
bash mkhint --list mypackage               # side-by-side hint vs .info (no table)
bash mkhint --review                       # review matched hints: diff + [K]eep/[D]elete/[S]kip
bash mkhint --list --review                # show highlighted table, then review
bash mkhint --set-version 2.0.1 --hintfile mypackage
bash mkhint --set-version 1.2.3 --new mypackage
bash mkhint --new mypackage            # keep VERSION from .info, no downloads
bash mkhint --set-version 2.0.1 --hintfile mypackage --no-dl   # downloads + md5 + NODOWNLOAD=yes
bash mkhint --new mypackage --no-dl    # create hint with NODOWNLOAD=yes
bash mkhint --delete mypackage
bash mkhint --clean
bash mkhint --hintfile mypackage          # suggest latest version via nvchecker (no -V)
bash mkhint --check                        # check all hints for upstream updates
bash mkhint --check pkg1 pkg2              # check specific packages
```

### Automated test suite

Uses mock `REPO_DIR`/`HINT_DIR` and a fake `wget` — no real downloads, no real directories needed. Requires `/var/lib/sbopkg/SBo-git/` for `.info` file fixtures (read-only).

```bash
bash tests/mkhint_test.sh
```

Test coverage:

| ID  | Scenario |
|-----|----------|
| T1  | `--new` from `.info`, no version — template copied, VERSION kept from .info |
| T2  | `--new -V` — version updated, md5 recalculated |
| T3  | `--new -N` no version — NODOWNLOAD=yes added, no downloads |
| T4  | `--new -V -N` — version + md5 + NODOWNLOAD=yes |
| T5  | `--new` when hint exists — backup + empty skeleton |
| T6  | `--hintfile -V` single URL — version + md5 updated, backup created |
| T7  | `--hintfile -V -N` — version + md5 + NODOWNLOAD=yes |
| T8  | `DOWNLOAD=UNSUPPORTED`, `DOWNLOAD_x86_64` has URL — 32-bit skipped, x86_64 md5 recalculated |
| T9  | `-N` alone — exits 1 |
| T10 | `--hintfile` on nonexistent file — exits 2 |
| T11 | `--delete` — removes hint and .bak |
| T12 | `--delete` nonexistent — exits 2 |
| T13 | `--new` multiline `.info`, no version — template copied, original md5s kept |
| T14 | `--new` multiline `.info` with `-V` — first URL+md5 updated, continuation md5 kept |
| T15 | `--clean` — removes all .bak files |
| T16 | `--new` github .info — [pkg] source=github appended to nvchecker config |
| T17 | `--new` pypi .info — [pkg] source=pypi appended to nvchecker config |
| T18 | `--new` unrecognised URL — commented stub [pkg] appended to nvchecker config |
| T19 | `--new` when [pkg] exists in config — not duplicated |
| T20 | `--hintfile` no -V, accept suggestion — VERSION=latest, nvtake called |
| T21 | `--hintfile` no -V, type override — VERSION=typed value |
| T22 | `--hintfile` no -V, no nvchecker result — graceful abort, hint unchanged |
| T23 | `--check` one outdated, confirm — updated, nvtake, slackrepo prompted |
| T24 | `--check` all current — "all up to date", no slackrepo |
| T25 | `--check` mixed — decline one / accept one |
| T26 | `--check` with -V — mutually-exclusive error, exit 1 |
| T27 | `--check` upstream older than hint — reported as `(?downgrade)` |
| T28 | `--check` no args — scans entire HINT_DIR |
| T29 | `--check` missing section, accept populate — github section appended, run stops, hint unchanged |
| T30 | `--check` missing section, decline populate — nothing added |
| T31 | `--check` missing section, no `.info` in repo — skipped, no section added |
| T36 | `-l` highlights rows where hint version == SBo version; mismatch plain |
| T37 | `-R` answer D — matched hint and .bak removed, summary reports deleted 1 |
| T38 | `-R` answer K — matched hint unchanged |
| T39 | `-R` empty answer — kept (default) |
| T40 | `-R` answer S — matched hint unchanged |
| T41 | `-R` no matched rows — "nothing to review", exit 0 |
| T42 | `--check` single pkg — nvchecker called with `-e <pkg>` |
| T43 | `--check` two pkgs — nvchecker full scan, no `-e` |
| T44 | `-R <pkg>` non-matched hint — diff shown, Keep leaves it |
| T45 | `-R <pkg>` answer D — named hint and .bak removed |
| T46 | `-R <pkg1> <pkg2>` — both reviewed, summary "Reviewed 2" |
| T47 | `-R <missing>` — exit 2 |
| T48 | `--check` upstream `2026-06-02` vs hint `2026_06_02` — treated as current |
| T49 | `--check` accept dashed upstream — hint VERSION stored as underscore form |
| T50 | `--new` on .info requiring a phantom dep — `DELREQUIRES` added |
| T51 | `--new` on .info with no phantom dep — no `DELREQUIRES` |
| T52 | `--fix-current` dependent with no hint — minimal hint created, only phantom dep stripped |
| T53 | `--fix-current` existing manual hint — `.bak` made, `DELREQUIRES` merged, other vars intact |
| T54 | `--fix-current` re-run — idempotent, no duplicate dep, no `.bak` churn |
| T55 | missing phantom-deps file — `--fix-current` and `--new` are no-ops |
| T56 | `--fix-current` with `-V` — mutually-exclusive error, exit 1 |
| T57 | `-l` skips hints with no `VERSION`; count excludes them |
| T58 | `-l <pkg>` shows side-by-side hint vs `.info`, not the table |
| T59 | `-l <missing>` — exit 2 |
| T60 | `-l` hint newer than `.info` — HintVer cell green, row not yellow |
| T61 | `-l` `.info` newer than hint — SBOVer cell green |
| T62 | `-l` equal versions — whole row yellow, no green |
| T63 | `-l` hint with populated `DELREQUIRES` — `✓` in DelReq column |
| T64 | `-l` hint without `DELREQUIRES` — DelReq blank |
| T65 | `mkhint -v` prints `mkhint <version>`, exit 0 |
| T66 | `mkhint --version` prints `mkhint <version>`, exit 0 |
| T67 | `mkhint -V <ver> -n <pkg>` sets hint VERSION (rename works) |

When adding new features, add a corresponding test case to `tests/mkhint_test.sh`.

## Key Behaviors

- `--hintfile` update: backs up to `.bak`, replaces old version string globally via `sed`, re-downloads both URLs to recalculate MD5 checksums. Skips download if value is `UNSUPPORTED` or `UNTESTED`. After a successful update it dispatches slackrepo for the single package via `prompt_slackrepo`, which uses `pkg_in_repo` (glob `PACKAGES_DIR/*/<pkg>/<pkg>-*.txz`) to choose `slackrepo update` for a built package or `slackrepo build` for an absent one, both run through `run_slackrepo`.
- `--new` with existing `.info`: copies `.info` as template, strips `PRGNAM`, `HOMEPAGE`, `MAINTAINER`, `EMAIL`, comments out `REQUIRES`, sets `ARCH="x86_64"`. Keeps `VERSION` from `.info`. If `-V` given, updates version string and recalculates checksums. Also appends an nvchecker `[section]` to the config via `add_nvchecker_section`.
- `add_nvchecker_section` autodetection: `_detect_nvchecker_source` recognizes github, gitlab, bitbucket, gitea, codeberg, and pagure owner/repo URLs plus the pypi, npm, gems, crates.io (`cratesio`), cpan, hackage, packagist, and cran registries, else leaves a commented stub. Github gets `use_latest_release = true` with commented `use_max_tag`/`prefix = "v"` fallbacks; the other forges get `use_max_tag = true` plus a commented `# prefix = "v"`; registries use the package name parsed from the URL via `_registry_name_from_url`, falling back to `PRGNAM` when no host-specific pattern matches. Either way, the managed stanza (freshly added or already present) is echoed fenced on stdout via `_extract_nvchecker_section`.
- `--new` when hint already exists: backs up old, creates empty skeleton.
- `--hintfile` with no `-V`: queries nvchecker for latest version, shows current vs. latest, prompts to accept/override/decline. After accepting, runs `nvtake` to sync nvchecker's keyfile.
- `--list` / `-l`: lists hints with `HintVer`/`SBOVer` plus a `DelReq` column (before `Created`) showing `✓` when the hint has a populated `DELREQUIRES` (detected via `grep '^DELREQUIRES="..*"'`, padded with `_pad_glyph` so the multibyte glyph stays aligned). Hints with no `VERSION` are skipped (and excluded from the total). Version columns are 22 wide to fit long version strings. Coloring: rows where the two versions are byte-equal get the whole row yellow (and populate `MATCHED_PKGS` for `-R`); when they differ, `sort -V` picks the newer side and only that version cell is green (version strings are pre-padded to 22 before the color wrap so the escape bytes don't break alignment); an absent/empty `SBOVer` leaves the row plain. Color only on a TTY (or `MKHINT_FORCE_COLOR`); plain when piped. Legend `(yellow row = versions match; green = newer side)` prints when any row matched. With package names (`-l foo bar`), the table is skipped and each named hint is shown side by side with its `.info` via `_show_hint_diff` (shared with `--review`); missing hint → exit 2.
- `--review` / `-R`: with no package args, iterates only the matched (highlighted) hints. With explicit package names (`-R foo bar`), reviews each named hint regardless of version match (existence required: missing hint → exit 2). For each, shows the hint side-by-side with its `.info` (`git diff --no-index` if git present, else `diff -y`), then prompts `[K]eep / [D]elete / [S]kip` (default Keep). Delete removes the hint and its `.bak` via `_remove_hint`. Prints a deleted/kept summary counting hints actually reviewed. `-l` and `-R` combine: `-lR` shows the table first, then reviews. Bare `-R` with no matches → "nothing to review", exit 0. Per-hint logic lives in `_review_one_hint`; `review_hint_files` drives it from either the named list or `MATCHED_PKGS`.
- `--check` / `-C`: runs nvchecker for all (or named) hints. With exactly one explicit package it uses `nvchecker -e <pkg>` to skip scanning the whole config; with two+ packages or no args it does one full scan. (`--hintfile` with no `-V` also queries via `nvchecker -e <pkg>`.) reports outdated packages with current → latest versions, prompts per-package to update, applies updates with `nvtake`, then prompts slackrepo for all updated packages. The slackrepo action is chosen per package by `pkg_in_repo` (glob `PACKAGES_DIR/*/<pkg>/<pkg>-*.txz`): a package already built in `PACKAGES_DIR` gets `slackrepo update`, an absent one gets `slackrepo build`. `--check` partitions its updated set into built vs. fresh and prompts `update` then `build` separately (each only if its list is non-empty), both dispatched through the shared `run_slackrepo` helper. Hints with no `[pkg]` section in `nvchecker.toml` are collected and, after the scan, a single prompt offers to populate the config via `add_nvchecker_section` (github/pypi autodetect, else stub); on accept it prints a "review and re-run" message and stops the run without applying updates. Packages whose `.info` is not found in `REPO_DIR` are skipped. Upstream versions are normalized via `_normalize_version` (`-` → `_`) before comparing and before storing, so a dashed upstream version like `2026-06-02` matches the packaged `2026_06_02` (SlackBuild versions cannot contain `-`) and updates are written in the underscore form. The same normalization applies to `--hintfile` with no `-V`. `nvtake` still uses nvchecker's own raw keyfile value.
- `--no-dl` / `-N`: downloads and recalculates checksums as normal, then appends `NODOWNLOAD=yes` after `MD5SUM_x86_64=`. Works with `--hintfile` or `--new`. Error if used alone.
- `--fix-current` / `-F`: bulk sweep. Loads `PHANTOM_DEPS_FILE`, scans every `.info` in `REPO_DIR`, and for each package whose REQUIRES contains a phantom dep, ensures its hint carries the matching `DELREQUIRES`. No existing hint → create a minimal `DELREQUIRES="..."` file. Existing hint → back up to `.bak` and union the phantom deps into its `DELREQUIRES` line (dedup), leaving all other content untouched. Idempotent: if the deps are already present, the file is left alone and no `.bak` is written. No per-package prompts, safe under `set -e`. Mutually exclusive with `-V`/`-f`/`-n` (exit 1). Empty/missing list → "Nothing to do", exit 0. Helpers: `load_phantom_deps`, `phantom_deps_in_info`, `merge_delrequires`, `fix_current`.
- `--new` phantom-dep hook: after commenting out REQUIRES, `create_new_hint_file` appends `DELREQUIRES="..."` for any phantom dep found in the `.info` REQUIRES. Same list as `--fix-current`.
- `--check` bundled-dep reconcile: `BUNDLE_MANIFEST_FILE` entries are 3-field,
  `<pkg> <mode> <rest>` (field 2 = `url` or `sha`; `bundle_mode <pkg>` reads it,
  the dispatcher `reconcile_bundle_deps` routes on it). `pkg_has_manifest` is true
  for either mode; `manifest_url_for` returns non-zero for non-`url` packages, so
  each of the three reconcile call sites (`--new`, `--check`, `--hintfile`)
  resolves `murl` only when `bundle_mode == url` and passes empty for `sha`.
- **url mode** (neovim, `<pkg> url <url-template-with-{VERSION}>`,
  `reconcile_bundle_deps_url`): after the primary bump mkhint fetches
  the upstream deps manifest (`NAME_URL`/`NAME_SHA256` pairs, e.g. neovim's
  `cmake.deps/deps.txt`), matches each extra `DOWNLOAD` line via
  `match_dep_url` (repo-path first, exact basename-stem fallback for blob
  hosts; `_url_repo` is lowercased so a `JuliaStrings/utf8proc` hint matches a
  `juliastrings/utf8proc` manifest — github repos are case-insensitive). A
  matched line is rewritten only when its upstream *version* differs
  (`_url_version`), not when only the URL path shape differs, so a manifest's
  bare-tag `archive/v0.26.7.tar.gz` and the hint's SBo-fetched
  `archive/v0.26.7/tree-sitter-0.26.7.tar.gz` at the same version are treated as
  current. `_url_version` derives the version by stripping the URL's own github
  repo name from the basename (so digit/dash-containing dep names like
  `lua-compat-5.3` parse), treats a bare-tag basename as the whole version
  (package-rev suffixes like `1.52.1-0`), and falls back to a
  trailing-version/sha heuristic for non-github and the shared `neovim/deps`
  blob host. Changed lines get their md5 recomputed; the report shows
  `name old-ver -> new-ver`. Runs automatically when the primary changed this
  run, otherwise only with `--force` (check-only flag). `--new` on a listed
  package prints the reconcile report without changing the hint. Manifest deps
  with no hint line are listed as an FYI, never added (would need a SlackBuild
  change). Helpers: `load_bundle_manifests`, `manifest_url_for`,
  `fetch_manifest`, `parse_manifest`, `match_dep_url`, `_url_version`,
  `reconcile_bundle_deps_url`.
- **sha mode** (openvino, `<pkg> sha <repo> <version-template> <name=path>...`,
  `reconcile_bundle_deps_sha`): the bundled deps are github git submodules pinned
  by full 40-char commit SHA in `archive/<sha>/` `DOWNLOAD_x86_64` lines (there is
  no upstream flat `deps.txt`, and some pins sit off-tag, so versions can't be
  derived — the SHA is the identity). For each manifest `name=path`, mkhint fetches
  the submodule's pinned SHA from the GitHub contents API
  (`_fetch_submodule_sha` → `.sha` + `submodule_git_url`, authed with a token from
  nvchecker's keyfile via `_github_token` when present → 5000/h, else anon),
  matches the hint `DOWNLOAD` line by that submodule's owner/repo, and rewrites +
  re-md5s any line whose 40-char SHA drifted (plain `==`, both path segment and
  filename). The report lists every dep, `<name> <sha7> (current)` or
  `<name> <old7> -> <new7>`; a 404 path → `submodule path not found`, a manifest
  dep matching no hint line → `no matching DOWNLOAD line (FYI)`. Runs on a primary
  bump or under `--force`, same as url mode. `--new`/`--hintfile` print the report
  too. The primary tarball line is never touched (no `name=path` names it).
- **Job B submodule inventory** (`detect_set_drift <pkg> <old> <new>`): on a
  sha-mode bump or `--force`, diffs `.gitmodules` at the old and new refs
  (`_fetch_gitmodules_paths`, plain `raw.githubusercontent.com`, no token needed)
  and prints a full roster of every submodule (all ~20, not just the diff) tagged
  `bundled`/`(ignored)` with `+`/`-` change glyphs, raising `ACTION` on a bundled
  dep removed upstream and `review` on a new unbundled one. FYI only, never edits
  the bundle set (add/remove a bundled dep is a SlackBuild + `.info` change the
  user owns). The pre-bump version is captured in `check_updates` before the hint
  is rewritten; under `--force` no-bump old==new and the roster prints with blank
  glyphs. A `.gitmodules` fetch failure skips Job B with a notice; Job A still runs.
- `--delete` / `-d`: removes hint file and `.bak` if present. Accepts multiple package names. Exits 2 on first missing file.
- `--info` / `-i <pkg>`: globs `REPO_DIR/*/pkg/` for the category, prints the green `category/program` header, then a version-compare row, then the README, paged with sticky header (`less --header=1`) only when the README is taller than the terminal (inline when it fits or when piped), missing package exits 2, missing README prints `(no README)` and exits 0. Mutually exclusive with `-V`/`-f`/`-n`. Handler `show_info`. The version row compares the SBo `.info` VERSION against the hint's (both via `grep "^VERSION" | cut -d '"' -f2` from `<dir>/<pkg>.info` and `HINT_DIR/<pkg>.hint`), normalized with `_normalize_version`: equal → whole row yellow with `=`; differ → `sort -V` greens the higher side with `<`/`>` pointing at it; hint absent/versionless → `SBo: x  (no hint)`; `.info` without VERSION → row skipped. Header stays pinned (`--header=1`); the version row is body line 1 and scrolls with the README.
- Downloads go to `/tmp/mkhint/download` (single shared temp file, deleted after md5 calculation).
- Multiline `DOWNLOAD`/`DOWNLOAD_x86_64`: parsed via `parse_multiline_var` (awk). First URL always re-downloaded. Continuation URLs (2+) prompt user interactively — changed URLs re-downloaded, unchanged URLs keep existing md5. Written back via `perl -i` with `\` continuation format preserved. Shared logic in `update_checksums` → `_process_download_var`.

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Invalid arguments |
| 2 | File not found |
| 3 | File already exists (unused — backup logic replaces this) |
| 4 | Required tool not available (wget/nvchecker/nvtake/jq) |

## Installation

```bash
sudo cp mkhint /usr/local/bin/mkhint
sudo cp mkhint.bash-completion /etc/bash-completion.d/mkhint
sudo cp mkhint.1.gz /usr/local/man/man1/mkhint.1.gz
```

Man page source is `mkhint.1.md`; the committed `mkhint.1.gz` is rebuilt with
`pandoc mkhint.1.md -s -t man -o mkhint.1 && gzip -9 -n -f mkhint.1`. Option
names are `\--`-escaped in the source so pandoc's man output renders the
double-dash flags. `--help` is a compact summary that points at `man mkhint`;
the full reference (usage examples, configuration, exit codes) lives in the
man page.
