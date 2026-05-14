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
bash mkhint --new mypackage            # empty hint, no version
bash mkhint --version 2.0.1 --hintfile mypackage --no-dl   # skip downloads, add NODOWNLOAD=yes
bash mkhint --new mypackage --no-dl    # create hint with NODOWNLOAD=yes
bash mkhint --delete mypackage
bash mkhint --clean
```

No test suite exists. Test manually against real `REPO_DIR`/`HINT_DIR` or with mock directories.

## Key Behaviors

- `--hintfile` update: backs up to `.bak`, replaces old version string globally via `sed`, re-downloads both URLs to recalculate MD5 checksums. Skips download if value is `UNSUPPORTED` or `UNTESTED`.
- `--new` with existing `.info`: copies `.info` as template, strips `PRGNAM`, `HOMEPAGE`, `MAINTAINER`, `EMAIL`, comments out `REQUIRES`, sets `ARCH="x86_64"`.
- `--new` when hint already exists: backs up old, creates empty skeleton.
- `--no-dl` / `-N`: skips all downloads; inserts `NODOWNLOAD=yes` after `MD5SUM_x86_64=` line. Works with `--hintfile` or `--new`. Error if used alone.
- `--delete` / `-d`: removes hint file and `.bak` if present. Accepts multiple package names. Exits 2 on first missing file.
- Downloads go to `/tmp/mkhint/download` (single shared temp file, deleted after md5 calculation).

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
