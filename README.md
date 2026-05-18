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

### Configuration

Edit the paths at the top of mkhint to match your setup (lines 16–17):

```bash
REPO_DIR="/var/lib/sbopkg/SBo-danix/"      # Repository containing .info files
HINT_DIR="/etc/slackrepo/SBo-danix/hintfiles/"  # Directory where .hint files are stored
```

Keep the same paths in sync in `mkhint.bash-completion` (lines 8–9).

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

```bash
mkhint --list
mkhint -l
```

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
| 4 | wget not available |

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
- Bash completion for `-f`/`--hintfile`, `-n`/`--new`, and `-d`/`--delete` autocompletes package names from their respective directories. Short flags (`-v`, `-f`, `-n`, `-l`, `-c`, `-d`, `-N`, `-h`) are also completed.
