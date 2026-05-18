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

## Running / Testing

No build step. Direct execution:

```bash
bash mkhint --help
bash mkhint --list
bash mkhint --version 2.0.1 --hintfile mypackage
bash mkhint --version 1.2.3 --new mypackage
bash mkhint --new mypackage            # keep VERSION from .info, no downloads
bash mkhint --version 2.0.1 --hintfile mypackage --no-dl   # downloads + md5 + NODOWNLOAD=yes
bash mkhint --new mypackage --no-dl    # create hint with NODOWNLOAD=yes
bash mkhint --delete mypackage
bash mkhint --clean
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

When adding new features, add a corresponding test case to `tests/mkhint_test.sh`.

## Key Behaviors

- `--hintfile` update: backs up to `.bak`, replaces old version string globally via `sed`, re-downloads both URLs to recalculate MD5 checksums. Skips download if value is `UNSUPPORTED` or `UNTESTED`.
- `--new` with existing `.info`: copies `.info` as template, strips `PRGNAM`, `HOMEPAGE`, `MAINTAINER`, `EMAIL`, comments out `REQUIRES`, sets `ARCH="x86_64"`. Keeps `VERSION` from `.info`. If `-v` given, updates version string and recalculates checksums.
- `--new` when hint already exists: backs up old, creates empty skeleton.
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
| 4 | wget not available |

## Installation

```bash
sudo cp mkhint /usr/local/bin/mkhint
sudo cp mkhint.bash-completion /etc/bash-completion.d/mkhint
```
