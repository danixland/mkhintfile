# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

`mkhint` — bash utility for managing [slackrepo](https://idlemoor.github.io/slackrepo/) hint files. Hint files override build variables (version, download URL, checksum) for SlackBuilds.

## Configuration

Two paths hardcoded near top of `mkhint` (lines 16–17):

```bash
REPO_DIR="/var/lib/sbopkg/SBo-danix/"      # SBo repository with .info files
HINT_DIR="/etc/slackrepo/SBo-danix/hintfiles/"  # where .hint files live
```

Bash completion script has its own hardcoded copies (lines 8–9) — keep in sync when changing defaults.

nvchecker config path is read from `$HOME/.config/nvchecker/nvchecker.toml` (not hardcoded):

```bash
NVCHECKER_CONFIG="$HOME/.config/nvchecker/nvchecker.toml"
```

User must set up the `[__config__]` section once before version-checking features work. Bash completion now also knows `--check`/`-C`.

## Running / Testing

No build step. Direct execution:

```bash
bash mkhint --help
bash mkhint --list                         # highlight hints whose version matches SBo .info
bash mkhint --review                       # review matched hints: diff + [K]eep/[D]elete/[S]kip
bash mkhint --list --review                # show highlighted table, then review
bash mkhint --version 2.0.1 --hintfile mypackage
bash mkhint --version 1.2.3 --new mypackage
bash mkhint --new mypackage            # keep VERSION from .info, no downloads
bash mkhint --version 2.0.1 --hintfile mypackage --no-dl   # downloads + md5 + NODOWNLOAD=yes
bash mkhint --new mypackage --no-dl    # create hint with NODOWNLOAD=yes
bash mkhint --delete mypackage
bash mkhint --clean
bash mkhint --hintfile mypackage          # suggest latest version via nvchecker (no -v)
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
| T2  | `--new -v` — version updated, md5 recalculated |
| T3  | `--new -N` no version — NODOWNLOAD=yes added, no downloads |
| T4  | `--new -v -N` — version + md5 + NODOWNLOAD=yes |
| T5  | `--new` when hint exists — backup + empty skeleton |
| T6  | `--hintfile -v` single URL — version + md5 updated, backup created |
| T7  | `--hintfile -v -N` — version + md5 + NODOWNLOAD=yes |
| T8  | `DOWNLOAD=UNSUPPORTED`, `DOWNLOAD_x86_64` has URL — 32-bit skipped, x86_64 md5 recalculated |
| T9  | `-N` alone — exits 1 |
| T10 | `--hintfile` on nonexistent file — exits 2 |
| T11 | `--delete` — removes hint and .bak |
| T12 | `--delete` nonexistent — exits 2 |
| T13 | `--new` multiline `.info`, no version — template copied, original md5s kept |
| T14 | `--new` multiline `.info` with `-v` — first URL+md5 updated, continuation md5 kept |
| T15 | `--clean` — removes all .bak files |
| T16 | `--new` github .info — [pkg] source=github appended to nvchecker config |
| T17 | `--new` pypi .info — [pkg] source=pypi appended to nvchecker config |
| T18 | `--new` unrecognised URL — commented stub [pkg] appended to nvchecker config |
| T19 | `--new` when [pkg] exists in config — not duplicated |
| T20 | `--hintfile` no -v, accept suggestion — VERSION=latest, nvtake called |
| T21 | `--hintfile` no -v, type override — VERSION=typed value |
| T22 | `--hintfile` no -v, no nvchecker result — graceful abort, hint unchanged |
| T23 | `--check` one outdated, confirm — updated, nvtake, slackrepo prompted |
| T24 | `--check` all current — "all up to date", no slackrepo |
| T25 | `--check` mixed — decline one / accept one |
| T26 | `--check` with -v — mutually-exclusive error, exit 1 |
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

When adding new features, add a corresponding test case to `tests/mkhint_test.sh`.

## Key Behaviors

- `--hintfile` update: backs up to `.bak`, replaces old version string globally via `sed`, re-downloads both URLs to recalculate MD5 checksums. Skips download if value is `UNSUPPORTED` or `UNTESTED`.
- `--new` with existing `.info`: copies `.info` as template, strips `PRGNAM`, `HOMEPAGE`, `MAINTAINER`, `EMAIL`, comments out `REQUIRES`, sets `ARCH="x86_64"`. Keeps `VERSION` from `.info`. If `-v` given, updates version string and recalculates checksums. Also appends an nvchecker `[section]` to the config, auto-detecting github/pypi source or providing a commented stub.
- `--new` when hint already exists: backs up old, creates empty skeleton.
- `--hintfile` with no `-v`: queries nvchecker for latest version, shows current vs. latest, prompts to accept/override/decline. After accepting, runs `nvtake` to sync nvchecker's keyfile.
- `--list` / `-l`: lists hints with `HintVer`/`SBOVer`; rows where the two are byte-equal are highlighted (color only on a TTY; plain when piped). Adds a legend when any row matched.
- `--review` / `-R`: with no package args, iterates only the matched (highlighted) hints. With explicit package names (`-R foo bar`), reviews each named hint regardless of version match (existence required: missing hint → exit 2). For each, shows the hint side-by-side with its `.info` (`git diff --no-index` if git present, else `diff -y`), then prompts `[K]eep / [D]elete / [S]kip` (default Keep). Delete removes the hint and its `.bak` via `_remove_hint`. Prints a deleted/kept summary counting hints actually reviewed. `-l` and `-R` combine: `-lR` shows the table first, then reviews. Bare `-R` with no matches → "nothing to review", exit 0. Per-hint logic lives in `_review_one_hint`; `review_hint_files` drives it from either the named list or `MATCHED_PKGS`.
- `--check` / `-C`: runs nvchecker for all (or named) hints. With exactly one explicit package it uses `nvchecker -e <pkg>` to skip scanning the whole config; with two+ packages or no args it does one full scan. (`--hintfile` with no `-v` also queries via `nvchecker -e <pkg>`.) reports outdated packages with current → latest versions, prompts per-package to update, applies updates with `nvtake`, then prompts single `slackrepo update` for all updated packages. Hints with no `[pkg]` section in `nvchecker.toml` are collected and, after the scan, a single prompt offers to populate the config via `add_nvchecker_section` (github/pypi autodetect, else stub); on accept it prints a "review and re-run" message and stops the run without applying updates. Packages whose `.info` is not found in `REPO_DIR` are skipped. Upstream versions are normalized via `_normalize_version` (`-` → `_`) before comparing and before storing, so a dashed upstream version like `2026-06-02` matches the packaged `2026_06_02` (SlackBuild versions cannot contain `-`) and updates are written in the underscore form. The same normalization applies to `--hintfile` with no `-v`. `nvtake` still uses nvchecker's own raw keyfile value.
- `--no-dl` / `-N`: downloads and recalculates checksums as normal, then appends `NODOWNLOAD=yes` after `MD5SUM_x86_64=`. Works with `--hintfile` or `--new`. Error if used alone.
- `--delete` / `-d`: removes hint file and `.bak` if present. Accepts multiple package names. Exits 2 on first missing file.
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
```
