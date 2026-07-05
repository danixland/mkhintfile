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

Rather than editing the script, you can drop an optional config file at `~/.config/mkhint/config` (plain shell `KEY="value"` lines). It is sourced after the built-in defaults and can override any of these paths:

```bash
REPO_DIR="/var/lib/sbopkg/SBo-danix/"           # repository with .info files
HINT_DIR="/etc/slackrepo/SBo-danix/hintfiles/"  # where .hint files live
PACKAGES_DIR="/repo/"                            # built packages (*.txz) repository
NVCHECKER_CONFIG="$HOME/.config/nvchecker/nvchecker.toml"
PHANTOM_DEPS_FILE="$HOME/.config/mkhint/phantom-deps"
TMP_DIR="/tmp/mkhint"                            # download scratch directory
```

Set only the keys you want to change; a missing config file keeps the defaults. Both `mkhint` and `mkhint.bash-completion` read this file, so they stay in sync automatically.

nvchecker reads its configuration from `~/.config/nvchecker/nvchecker.toml`. You must set up the `[__config__]` section with oldver and newver keyfile paths before using version-checking features:

```toml
[__config__]
oldver = "/var/lib/nvchecker/oldver"
newver = "/var/lib/nvchecker/newver"
```

mkhint only appends package-specific `[section]` entries to this file; the `[__config__]` section must be created manually once.

The `--fix-current` / `--new` phantom-dependency list is read from `~/.config/mkhint/phantom-deps` (one dep per line, `#` comments allowed). See "Strip -current phantom dependencies" below. A missing file makes those features no-ops.

## Usage

### Update an existing hint file

Updates the package version, downloads the archive, and recalculates the MD5 checksums:

```bash
mkhint --hintfile mypackage --set-version 2.0.1
mkhint -f mypackage -V 2.0.1
```

Replaces the old version string with 2.0.1 everywhere in mypackage.hint, re-downloads the URLs from DOWNLOAD and DOWNLOAD_x86_64, and updates MD5SUM and MD5SUM_x86_64. Backs up the old file to mypackage.hint.bak first.

URLs set to `UNSUPPORTED` or `UNTESTED` are skipped.

### Update and add NODOWNLOAD

Downloads and recalculates checksums, then appends `NODOWNLOAD=yes` to tell slackrepo to skip checksum verification at build time:

```bash
mkhint -f mypackage -V 2.0.1 -N
mkhint --hintfile mypackage --set-version 2.0.1 --no-dl
```

### Create a new hint file from .info

Copies the corresponding .info file as a template, removes PRGNAM, HOMEPAGE, MAINTAINER, EMAIL, comments out REQUIRES, and sets ARCH to x86_64. If `-V` is given, the version string is updated and checksums are recalculated:

```bash
mkhint --new mypackage            # copy .info as-is, keep VERSION from .info
mkhint -n mypackage -V 1.2.3     # copy .info, update version + recalculate md5
mkhint -n mypackage -V 1.2.3 -N  # same, also add NODOWNLOAD=yes
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

Lists each hint file with its `HintVer` (version in the hint), `SBOVer` (version in the repository `.info`), and a `DelReq` column showing `✓` when the hint carries a populated `DELREQUIRES`. Hints with no `VERSION` set (e.g. pure `DELREQUIRES` hints) are skipped. Version columns are wide enough for long version strings. Rows where the two versions are equal are shown in yellow, so you can see at a glance which hints are now redundant with the upstream SBo version. When the versions differ, the newer of the two (decided with `sort -V`) is shown in green, so you can tell at a glance whether the hint or the repository is ahead. Color is used only on a TTY; piped output is plain. A legend is printed when any row matched.

With one or more package names (`-l foo bar`), the table is skipped; instead each named hint is shown side by side with its `.info` (`git diff --no-index` if git is available, otherwise `diff -y`). A missing hint exits 2.

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
mkhint --hintfile mypackage       # suggests latest version via nvchecker (no -V flag)
```

Check one or more packages for upstream updates with `--check`. mkhint runs nvchecker for all (or named) hint files, reports outdated packages, prompts per-package to update, applies updates with `nvtake`, and finishes by prompting slackrepo for all updated packages:

```bash
mkhint --check                    # check all hints for upstream updates
mkhint --check pkg1 pkg2          # check specific packages
mkhint -C                         # short form
```

When exactly one package is given, mkhint runs `nvchecker -e <package>` so only that entry is scanned instead of the whole `nvchecker.toml`. With two or more packages, or no arguments, it does a single full scan. (`--hintfile` without `-v` likewise queries just its one entry via `-e`.)

The slackrepo action is chosen per package: if the package is already built in `PACKAGES_DIR` (a matching `*.txz` exists), mkhint prompts `slackrepo update`; if it has never been built there, it prompts `slackrepo build`. `--check` groups its updated packages into "already built" and "not yet built" and prompts for `update` then `build` separately, running each only when its group is non-empty. `--hintfile` makes the same choice for its single package.

If any scanned hint file has no nvchecker source configured, `--check` lists those packages and offers to populate `nvchecker.toml` for them in one prompt — auto-detecting github/pypi from the SBo `.info`, otherwise writing a commented stub to fill in. After populating, it asks you to review the file (fill any stubs) and re-run `mkhint -C`. Packages with no matching `.info` in the repository are skipped.

Because a SlackBuild version string cannot contain `-` (it would break `PRGNAM` parsing), an upstream version such as `2026-06-02` is packaged as `2026_06_02`. mkhint normalizes upstream versions (`-` becomes `_`) before comparing them, so these are treated as the same version and no spurious upgrade or downgrade is offered. When you accept an update, the version is written to the hint file in the underscore form. The same normalization applies to `--hintfile` without `-v`. `nvtake` still records nvchecker's own raw upstream value.

### Strip -current phantom dependencies

SBo SlackBuilds target Slackware stable. Some of their build dependencies are unneeded on
slackware-current because it already ships them as system packages or newer versions, for example
`google-go-lang` (a system package on -current) and `rust-opt` (only needed on stable, where the
system rust is old). slackrepo strips such a dep from a package by putting `DELREQUIRES="dep"` in
that package's hint file.

List these "phantom" deps once, one per line (`#` comments allowed), in:

```
~/.config/mkhint/phantom-deps
```

Example:

```
# deps needed on stable but not on -current
rust-opt
google-go-lang
```

`--fix-current` (`-F`) then sweeps the whole repository: for every package whose `REQUIRES` contains
a listed dep, it ensures the hint carries the matching `DELREQUIRES`. Packages with no hint get a
minimal one; packages with an existing hint are backed up to `.bak` and have the dep merged into
their `DELREQUIRES` line, leaving everything else untouched. It is idempotent, so run it after each
weekly repository regeneration:

```bash
mkhint --fix-current
mkhint -F
```

`--new` also applies the list automatically: when it creates a hint from an `.info` whose `REQUIRES`
contains a phantom dep, it adds the matching `DELREQUIRES` for you.

If the list file is missing or empty, both features are no-ops.

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
| DELREQUIRES | Space-separated deps to strip from REQUIRES (e.g. -current phantom deps) |

## Notes

- Hint files are backed up to `.bak` before any modification.
- If DOWNLOAD or DOWNLOAD_x86_64 is `UNSUPPORTED` or `UNTESTED`, that URL is skipped and its MD5SUM is left unchanged.
- `--no-dl` / `-N` does **not** skip downloads — it downloads and recalculates checksums as normal, then appends `NODOWNLOAD=yes` to the hint file.
- After a successful `--hintfile` update, mkhint prompts to run slackrepo for the package, choosing `update` if it is already built in `PACKAGES_DIR` or `build` if it is not. Enter or `y` runs slackrepo immediately; `n` skips.
- Bash completion for `-f`/`--hintfile`, `-n`/`--new`, `-d`/`--delete`, `-C`/`--check`, `-R`/`--review`, and `-l`/`--list` autocompletes package names from their respective directories (`-l` and `-R` complete hint names repeatedly, for any number of packages). When `-f <package>` is already on the command line, `-V [TAB]` suggests the current `VERSION` from that package's hint file. If the hint file is absent, no version is suggested. Short flags (`-v`, `-V`, `-f`, `-n`, `-l`, `-R`, `-c`, `-d`, `-C`, `-N`, `-h`) and their long forms (including `--review`) are also completed.

## Versioning

This project follows [Semantic Versioning](https://semver.org/). Commits use [Conventional Commits](https://www.conventionalcommits.org/): `feat:` bumps the minor version, `fix:` the patch version, and a `!` / `BREAKING CHANGE` the major version. Releases are tagged `vX.Y.Z`; the version is stored in `MKHINT_VERSION` in the `mkhint` script. `mkhint -v` (or `--version`) prints it. See [CHANGELOG.md](CHANGELOG.md).

## Development Approach

This project is developed using AI-assisted tools. Code is generated with the help of AI based on human-provided specifications, design decisions, and iterative feedback.

All contributions are reviewed, tested, and curated by the maintainer before being included in the codebase. AI is used as a productivity and exploration tool, while human oversight remains central to all decisions.

The goal is to combine the flexibility of AI-assisted development with standard open-source practices such as transparency, review, and accountability.
