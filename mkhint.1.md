% MKHINT(1) mkhint 1.1.0 | User Commands
% Danilo M.
% July 2026

# NAME

mkhint - manage hint files for slackrepo scripts

# SYNOPSIS

**mkhint** \[**--set-version** *VERSION*] **--hintfile** *FILE*

**mkhint** \[**--set-version** *VERSION*] **--new** *FILE* \[**--no-dl**]

**mkhint** **--check** \[*FILE*...]

**mkhint** **--fix-current**

**mkhint** **--list** \[*FILE*...]

**mkhint** **--review** \[*FILE*...]

**mkhint** **--delete** *FILE*...

**mkhint** **--clean**

**mkhint** {**--version** | **--help**}

# DESCRIPTION

**mkhint** manages [slackrepo](https://idlemoor.github.io/slackrepo/) hint
files. A hint file overrides build variables (version, download URL, checksum,
dependencies) for a SlackBuild. **mkhint** updates the version string and
download checksums of an existing hint, creates a new hint from a repository
`.info` file, checks upstream for newer versions via **nvchecker**, and manages
`DELREQUIRES` for Slackware -current phantom dependencies.

After a version-changing update, **mkhint** dispatches **slackrepo** for the
affected package: `slackrepo update` if the package is already built in the
package repository, `slackrepo build` if it is not.

# OPTIONS

**--set-version**, **-V** *VERSION*
: New version string. Required with **--hintfile**; optional with **--new**.
Replaces the old version everywhere in the hint and recalculates MD5 checksums.

**--hintfile**, **-f** *FILE*
: Update an existing hint file. Without **-V**, queries **nvchecker** for the
latest version and prompts to accept, override, or decline. Backs the hint up
to *FILE*.bak first.

**--new**, **-n** *FILE*
: Create a new hint file from the package's `.info` template. Keeps `VERSION`
from the `.info` unless **-V** is given. Appends an **nvchecker** section to the
config, autodetecting a github or pypi source or leaving a commented stub.

**--check**, **-C** \[*FILE*...]
: Check all (or the named) hints for upstream updates via **nvchecker** and
apply them interactively. With one package, uses `nvchecker -e`; with two or
more, one full scan. Mutually exclusive with **-V**.

**--fix-current**, **-F**
: Sweep the whole repository. For every package whose `REQUIRES` contains a
phantom dependency, ensure its hint carries the matching `DELREQUIRES`.
Idempotent. Mutually exclusive with **-V**, **-f**, **-n**.

**--list**, **-l** \[*FILE*...]
: List all hint files with their hint version, `.info` version, and a
`DelReq` marker. With package names, show each hint side by side with its
`.info` instead of the table.

**--review**, **-R** \[*FILE*...]
: Review hints. With no arguments, iterate the hints whose version matches the
`.info`. With names, review each named hint regardless of match. For each,
show a diff and prompt **[K]eep / [D]elete / [S]kip**.

**--delete**, **-d** *FILE*...
: Delete a hint file and its `.bak`. Accepts multiple names.

**--clean**, **-c**
: Remove all `.bak` files from the hint directory.

**--no-dl**, **-N**
: Download and recalculate checksums, then append `NODOWNLOAD=yes`. Use with
**--hintfile** or **--new**; an error on its own.

**--version**, **-v**
: Print `mkhint <version>` and exit.

**--help**, **-h**
: Print a short usage summary and exit.

# USAGE EXAMPLES

Update an existing hint to a new version (re-downloads, recalculates MD5,
backs up to `.bak`):

    mkhint --hintfile mypackage --set-version 2.0.1
    mkhint -f mypackage -V 2.0.1

Same, then append `NODOWNLOAD=yes`:

    mkhint -f mypackage -V 2.0.1 -N

Create a new hint from `.info`:

    mkhint --new mypackage            # copy .info as-is, keep its VERSION
    mkhint -n mypackage -V 1.2.3      # update version + recalculate md5
    mkhint -n mypackage -V 1.2.3 -N   # same, add NODOWNLOAD=yes

Suggest the latest version for an existing hint via nvchecker (no **-V**):

    mkhint --hintfile mypackage

Check upstream for updates:

    mkhint --check                    # all hints
    mkhint --check pkg1 pkg2          # named hints

List, review, sweep, delete, clean:

    mkhint --list
    mkhint --list mypackage
    mkhint --review
    mkhint --fix-current
    mkhint --delete mypackage
    mkhint --clean

URLs set to `UNSUPPORTED` or `UNTESTED` are skipped during download.

# CONFIGURATION

**mkhint** reads an optional sourced config file, plain bash `KEY="value"`
pairs, right after its baked-in defaults. A missing file leaves the defaults in
place.

    ~/.config/mkhint/config

The overridable variables and their defaults:

`REPO_DIR` (`/var/lib/sbopkg/SBo-danix/`)
: SBo repository holding the `.info` files.

`HINT_DIR` (`/etc/slackrepo/SBo-danix/hintfiles/`)
: Where `.hint` files live.

`PACKAGES_DIR` (`/repo/`)
: Built-package repository holding `*.txz`. Used to decide `slackrepo update`
vs `slackrepo build`.

`NVCHECKER_CONFIG` (`$HOME/.config/nvchecker/nvchecker.toml`)
: nvchecker config. The `[__config__]` section must be created manually once
before version-checking works. **mkhint** only appends per-package sections.

`PHANTOM_DEPS_FILE` (`$HOME/.config/mkhint/phantom-deps`)
: One phantom dependency per line, `#` comments allowed. Deps needed on
Slackware stable but not on -current. A missing file makes **--fix-current**
and the **--new** phantom-dep hook no-ops.

`TMP_DIR` (`/tmp/mkhint`)
: Scratch directory for downloads.

# FILES

*~/.config/mkhint/config*
: Optional config overrides.

*~/.config/mkhint/phantom-deps*
: Phantom dependency list.

*~/.config/nvchecker/nvchecker.toml*
: nvchecker configuration.

# EXIT CODES

0
: Success.

1
: Invalid arguments or missing required options.

2
: File not found.

3
: File already exists.

4
: Required tool not available (wget / nvchecker / nvtake / jq).

# SEE ALSO

**slackrepo**(8), **nvchecker**(1), **nvtake**(1)

# AUTHOR

Danilo M. <danix@danix.xyz>
