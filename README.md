# mkhint

Manage hint files for slackrepo scripts. Updates version strings and download checksums, or creates new hint files from repository .info files.

## Installation

### Script

```bash
sudo cp mkhint /usr/local/bin/mkhint
```

### Bash Completion

```bash
sudo cp mkhint.bash-completion /etc/bash-completion.d/mkhint
```

### Dependencies

- `wget` — for downloading archives and calculating checksums
- `nvchecker` — for checking upstream versions (provides `nvchecker` and `nvtake`)
- `jq` — for parsing version check results

### Configuration

Edit the paths at the top of mkhint to match your setup (lines 16–17):

```bash
REPO_DIR="/var/lib/sbopkg/SBo-danix/"      # Repository containing .info files
HINT_DIR="/etc/slackrepo/SBo-danix/hintfiles/"  # Directory where .hint files are stored
```

Keep the same paths in sync in `mkhint.bash-completion` (lines 8–9).

nvchecker reads its configuration from `~/.config/nvchecker/nvchecker.toml`. You must set up the `[__config__]` section with oldver and newver keyfile paths before using version-checking features:

```toml
[__config__]
oldver = "/var/lib/nvchecker/oldver"
newver = "/var/lib/nvchecker/newver"
```

mkhint only appends package-specific `[section]` entries to this file; the `[__config__]` section must be created manually once.

## Usage

### Update an existing hint file

Updates the package version, downloads the archive, and recalculates the MD5 checksums:

```bash
mkhint --hintfile mypackage --version 2.0.1
mkhint -f mypackage -v 2.0.1
```

Replaces the old version string with 2.0.1 everywhere in mypackage.hint, re-downloads the URLs from DOWNLOAD and DOWNLOAD_x86_64, and updates MD5SUM and MD5SUM_x86_64. Backs up the old file to mypackage.hint.bak first.

URLs set to `UNSUPPORTED` or `UNTESTED` are skipped.

### Update and add NODOWNLOAD

Downloads and recalculates checksums, then appends `NODOWNLOAD=yes` to tell slackrepo to skip checksum verification at build time:

```bash
mkhint -f mypackage -v 2.0.1 -N
mkhint --hintfile mypackage --version 2.0.1 --no-dl
```

### Create a new hint file from .info

Copies the corresponding .info file as a template, removes PRGNAM, HOMEPAGE, MAINTAINER, EMAIL, comments out REQUIRES, and sets ARCH to x86_64. If `-v` is given, the version string is updated and checksums are recalculated:

```bash
mkhint --new mypackage            # copy .info as-is, keep VERSION from .info
mkhint -n mypackage -v 1.2.3     # copy .info, update version + recalculate md5
mkhint -n mypackage -v 1.2.3 -N  # same, also add NODOWNLOAD=yes
mkhint -n mypackage -N           # copy .info, add NODOWNLOAD=yes, no downloads
```

If no .info file exists in REPO_DIR, a skeleton hint with empty variables is created instead.

If the hint file already exists it is backed up and a fresh empty skeleton is written.

### Multiline DOWNLOAD

Some packages have multiple download URLs on continuation lines:

```
DOWNLOAD="https://example.com/foo-1.0.tar.gz \
    https://example.com/extra-data.tar.gz"
MD5SUM="aabbcc... \
    ddeeff..."
```

When updating a hint with multiline DOWNLOAD, mkhint:

- Always re-downloads the first URL (version changed → new content)
- Prompts interactively for each continuation URL — enter a new URL or leave blank to keep the current one
- Only re-downloads continuation URLs that were changed; unchanged URLs keep their existing md5

### List hint files

Lists each hint file with its `HintVer` (version in the hint) and `SBOVer` (version in the repository `.info`). Rows where the two are byte-equal are highlighted, so you can see at a glance which hints are now redundant with the upstream SBo version. Color is used only on a TTY; piped output is plain. A legend is printed when any row matched.

```bash
mkhint --list
mkhint -l
```

### Review hint files

With no arguments, iterates only the matched (highlighted) hints from `--list` — those whose version equals the SBo `.info` version. With explicit package names (`-R foo bar`), reviews each named hint regardless of version match; a missing hint exits 2. For each, it shows the hint side by side with its `.info` (`git diff --no-index` if git is available, otherwise `diff -y`), then prompts `[K]eep / [D]elete / [S]kip` (default Keep). Delete removes the hint and its `.bak`. A summary counting the hints actually reviewed is printed at the end.

```bash
mkhint --review
mkhint -R
mkhint -R foo bar          # review the named hints, any version
mkhint --list --review     # show the highlighted table first, then review
mkhint -lR                 # same, combined
```

With no arguments and no hints matching, it prints "nothing to review" and exits 0.

### Delete a hint file

Removes the hint file and its .bak backup if present:

```bash
mkhint --delete mypackage
mkhint -d pkg1 pkg2 pkg3
```

### Clean backup files

Removes all .bak files from HINT_DIR:

```bash
mkhint --clean
mkhint -c
```

### Check for upstream updates

When creating a new hint file with `--new`, mkhint automatically appends an nvchecker configuration section, auto-detecting the source (github, pypi, etc.) or providing a commented template. A notice is printed so you can review and fill in any missing details:

```bash
mkhint --new mypackage            # adds [mypackage] section to nvchecker config
```

When updating an existing hint file with `--hintfile` but without `-v`, mkhint queries nvchecker for the latest version, shows you the current and latest versions, and prompts to accept the latest, type a different version, or decline. After accepting an update, it runs `nvtake` to sync nvchecker's keyfile:

```bash
mkhint --hintfile mypackage       # suggests latest version via nvchecker (no -v flag)
```

Check one or more packages for upstream updates with `--check`. mkhint runs nvchecker for all (or named) hint files, reports outdated packages, prompts per-package to update, applies updates with `nvtake`, and finishes with a single `slackrepo update` prompt for all updated packages:

```bash
mkhint --check                    # check all hints for upstream updates
mkhint --check pkg1 pkg2          # check specific packages
mkhint -C                         # short form
```

When exactly one package is given, mkhint runs `nvchecker -e <package>` so only that entry is scanned instead of the whole `nvchecker.toml`. With two or more packages, or no arguments, it does a single full scan. (`--hintfile` without `-v` likewise queries just its one entry via `-e`.)

If any scanned hint file has no nvchecker source configured, `--check` lists those packages and offers to populate `nvchecker.toml` for them in one prompt — auto-detecting github/pypi from the SBo `.info`, otherwise writing a commented stub to fill in. After populating, it asks you to review the file (fill any stubs) and re-run `mkhint -C`. Packages with no matching `.info` in the repository are skipped.

### Help

```bash
mkhint --help
mkhint -h
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Invalid arguments |
| 2 | File not found |
| 3 | File already exists (unused — backup logic replaces this) |
| 4 | Required tool not available (wget/nvchecker/nvtake/jq) |

## Hint File Variables

| Variable | Description |
|----------|-------------|
| VERSION | Package version |
| ARCH | Architecture (x86_64) |
| DOWNLOAD | Download URL for generic/32-bit build |
| MD5SUM | MD5 checksum of the generic archive |
| DOWNLOAD_x86_64 | Download URL for x86_64-specific build |
| MD5SUM_x86_64 | MD5 checksum of the x86_64 archive |
| NODOWNLOAD | Set to `yes` to skip download/checksum verification in slackrepo |

## Notes

- Hint files are backed up to `.bak` before any modification.
- If DOWNLOAD or DOWNLOAD_x86_64 is `UNSUPPORTED` or `UNTESTED`, that URL is skipped and its MD5SUM is left unchanged.
- `--no-dl` / `-N` does **not** skip downloads — it downloads and recalculates checksums as normal, then appends `NODOWNLOAD=yes` to the hint file.
- After a successful `--hintfile` update, mkhint prompts `Run 'slackrepo update <package>'? [Y/n]`. Enter or `y` runs slackrepo immediately; `n` skips.
- Bash completion for `-f`/`--hintfile`, `-n`/`--new`, `-d`/`--delete`, and `-C`/`--check` autocompletes package names from their respective directories. When `-f <package>` is already on the command line, `-v [TAB]` suggests the current `VERSION` from that package's hint file. If the hint file is absent, no version is suggested. Short flags (`-v`, `-f`, `-n`, `-l`, `-R`, `-c`, `-d`, `-C`, `-N`, `-h`) and their long forms (including `--review`) are also completed.
