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

## Usage

### Update an existing hint file

Updates the package version, downloads the archive, and recalculates the MD5 checksums:

```bash
mkhint --version 2.0.1 --hintfile mypackage
```

Replaces the old version with 2.0.1 in mypackage.hint and re-downloads the URLs from DOWNLOAD and DOWNLOAD_x86_64 to update MD5SUM and MD5SUM_x86_64.

### Update without downloading

Updates the version string and adds `NODOWNLOAD=yes` to skip checksum verification in slackrepo:

```bash
mkhint --version 2.0.1 --hintfile mypackage --no-dl
```

### Create a new hint file from .info

Generates a new hint file from the corresponding repository .info file:

```bash
mkhint --version 1.2.3 --new mypackage
```

The .info file is copied as a template, unwanted variables (PRGNAM, HOMEPAGE, MAINTAINER, EMAIL) are removed, and ARCH is set to x86_64.

### Create a new hint file with NODOWNLOAD

```bash
mkhint --new mypackage --no-dl
```

### Create an empty hint file

Creates a fresh hint file with empty variables:

```bash
mkhint --new mypackage
```

### List hint files

```bash
mkhint --list
```

### Delete a hint file

Removes the hint file and its .bak backup if present:

```bash
mkhint --delete mypackage
mkhint --delete pkg1 pkg2 pkg3
```

### Clean backup files

Removes all .bak files from HINT_DIR:

```bash
mkhint --clean
```

### Help

```bash
mkhint --help
```

## Exit Codes

- 0 - Success
- 1 - Invalid arguments
- 2 - File not found
- 3 - File already exists
- 4 - wget not available

## Hint File Variables

- VERSION - Package version
- ARCH - Architecture
- DOWNLOAD - Download URL (generic/32-bit)
- MD5SUM - MD5 checksum of the generic archive
- DOWNLOAD_x86_64 - Download URL (x86_64 specific)
- MD5SUM_x86_64 - MD5 checksum of the x86_64 archive
- NODOWNLOAD - Set to `yes` to skip download/checksum verification in slackrepo

## Notes

- Old versions of hint files are backed up with a .bak extension before being modified.
- If a download URL is set to UNSUPPORTED or UNTESTED, the link is skipped during update.
- Bash completion for -f/--hintfile, -n/--new, and -d/--delete autocompletes package names from their respective directories.
