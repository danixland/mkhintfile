% MKHINT(1) mkhint 1.2.6 | User Commands
% Danilo M.
% July 2026

# NAME

mkhint - manage hint files for slackrepo scripts

# SYNOPSIS

**mkhint** \[**\--set-version** *VERSION*] **\--hintfile** *FILE*

**mkhint** \[**\--set-version** *VERSION*] **\--new** *FILE* \[**\--no-dl**]

**mkhint** **\--check** \[*FILE*...]

**mkhint** **\--fix-current**

**mkhint** **\--list** \[*FILE*...]

**mkhint** **\--review** \[*FILE*...]

**mkhint** **\--delete** *FILE*...

**mkhint** **\--info** *FILE*

**mkhint** **\--clean**

**mkhint** {**\--version** | **\--help**}

# DESCRIPTION

**mkhint** manages slackrepo hint
files. A hint file overrides build variables (version, download URL, checksum,
dependencies) for a SlackBuild. **mkhint** updates the version string and
download checksums of an existing hint, creates a new hint from a repository
`.info` file, checks upstream for newer versions via **nvchecker**, and manages
`DELREQUIRES` for Slackware -current phantom dependencies.

After a version-changing update, **mkhint** dispatches **slackrepo** for the
affected package: `slackrepo update` if the package is already built in the
package repository, `slackrepo build` if it is not.

# REQUIREMENTS

Required: **slackrepo**, **wget**, **nvchecker** (which also provides
**nvtake**), and **jq**. Optional: **git** (nicer side-by-side diffs, falls back
to `diff -y`), **less** (paging in **\--info**), and **tput** (color on a TTY).
Coreutils (**perl**, **awk**, **sed**, **grep**, **md5sum**) are assumed from a
base Slackware install.

# OPTIONS

**\--set-version**, **-V** *VERSION*
: New version string. Required with **\--hintfile**; optional with **\--new**.
Replaces the old version everywhere in the hint and recalculates MD5 checksums.

**\--hintfile**, **-f** *FILE*
: Update an existing hint file. Without **-V**, queries **nvchecker** for the
latest version and prompts to accept, override, or decline. Backs the hint up
to *FILE*.bak first.

**\--new**, **-n** *FILE*
: Create a new hint file from the package's `.info`. Strips `PRGNAM`,
`HOMEPAGE`, `MAINTAINER`, and `EMAIL`, comments out `REQUIRES`, and sets
`ARCH="x86_64"`, keeping only the variables a hint needs. `VERSION` is kept
from the `.info` unless **-V** is given. Appends an **nvchecker** section to the
config, autodetecting the upstream source (github, gitlab, bitbucket, gitea,
codeberg, pagure, pypi, npm, gems, crates.io, cpan, hackage, packagist, or
cran) or leaving a commented stub when nothing matches. Prints the managed
**nvchecker** stanza on stdout, whether it was just added or was already
present.

**\--check**, **-C** \[*FILE*...]
: Check all (or the named) hints for upstream updates via **nvchecker** and
apply them interactively. With one package, uses `nvchecker -e`; with two or
more, one full scan. Mutually exclusive with **-V**.

**\--fix-current**, **-F**
: Sweep the whole repository. For every package whose `REQUIRES` contains a
phantom dependency, ensure its hint carries the matching `DELREQUIRES`.
Idempotent. Mutually exclusive with **-V**, **-f**, **-n**.

**\--list**, **-l** \[*FILE*...]
: List all hint files with their hint version, `.info` version, a
`DelReq` marker (populated `DELREQUIRES`), and a `NoDL` marker
(`NODOWNLOAD=yes`). When `PACKAGES_DIR` holds at least one built package, an
extra `RepoVer` column is shown (auto opt-in) with the newest built version,
coloured magenta when it lags the newer of the hint/`.info` version. With
package names, show each hint side by side with its `.info` instead of the
table.

**\--review**, **-R** \[*FILE*...]
: Review hints. With no arguments, iterate the hints whose version matches the
`.info`. With names, review each named hint regardless of match. For each,
show a diff and prompt **[K]eep / [D]elete / [S]kip**.

**\--delete**, **-d** *FILE*...
: Delete a hint file and its `.bak`. Accepts multiple names.

**\--info**, **-i** *FILE*
: Show a package's `category/program` path (green on a TTY), then a
version-compare row, then its `README`. The row compares the SBo `.info`
version against the hint's: `SBo: x < Hint: y` (or `>`) with the higher side
green, `SBo: x = Hint: y` in yellow when equal, or `SBo: x  (no hint)` when no
hint carries a version. Omitted when the `.info` has no version. Paged with a
sticky header (`less --header=1`) only when the `README` is taller than the
terminal; printed inline when it fits or when piped. Missing package exits 2;
missing `README` prints `(no README)` and exits 0. Mutually exclusive with
**-V**, **-f**, **-n**.

**\--clean**, **-c**
: Remove all `.bak` files from the hint directory.

**\--no-dl**, **-N**
: Download and recalculate checksums, then append `NODOWNLOAD=yes`. Use with
**\--hintfile** or **\--new**; an error on its own.

**\--force**
: Only meaningful with **\--check**. Reconcile a bundle package's extra download
lines against its upstream manifest even when the primary version has not
changed. Use to retry after a previous manifest fetch failed.

**\--version**, **-v**
: Print `mkhint <version>` and exit.

**\--help**, **-h**
: Print a short usage summary and exit.

# USAGE EXAMPLES

Update an existing hint to a new version (re-downloads, recalculates MD5,
backs up to `.bak`):

    mkhint --hintfile mypackage --set-version 2.0.1
    mkhint -f mypackage -V 2.0.1

Same, then append `NODOWNLOAD=yes`:

    mkhint -f mypackage -V 2.0.1 -N

Create a new hint from `.info`:

    mkhint --new mypackage            # from .info, keep its VERSION
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
    mkhint --info mypackage
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
Slackware stable but not on -current. A missing file makes **\--fix-current**
and the **\--new** phantom-dep hook no-ops.

`TMP_DIR` (`/tmp/mkhint`)
: Scratch directory for downloads.

`BUNDLE_MANIFEST_FILE` (`$HOME/.config/mkhint/bundle-manifests`)
: Packages whose extra download lines are reconciled against an upstream deps
manifest during **\--check**. See BUNDLED DEPENDENCIES.

# FILES

*~/.config/mkhint/config*
: Optional config overrides.

*~/.config/mkhint/phantom-deps*
: Phantom dependency list.

*~/.config/mkhint/bundle-manifests*
: Bundle manifest list.

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

# BASH COMPLETION

A bash completion script ships with **mkhint** (install to
*/etc/bash-completion.d/mkhint*). It completes long and short options and, for
**-f**, **-n**, **-d**, **-C**, **-R**, and **-l**, the package names from their
respective directories. With **-f** *package* already on the command line,
**-V** *TAB* suggests the current `VERSION` from that package's hint. The
completion script sources the same *~/.config/mkhint/config*, so its paths stay
in sync with **mkhint**.

# BUNDLED DEPENDENCIES

Some SlackBuilds bundle several tarballs in one DOWNLOAD line: a primary source
plus pinned dependencies (neovim is the canonical case). Such packages can be
listed in the file named by BUNDLE_MANIFEST_FILE
(default \~/.config/mkhint/bundle-manifests), one entry per line:

    neovim  https://raw.githubusercontent.com/neovim/neovim/v{VERSION}/cmake.deps/deps.txt

The URL is an upstream, machine-readable deps manifest (NAME_URL / NAME_SHA256
pairs); {VERSION} is substituted with the hint's version. For a listed package,
\--new prints a reconcile report (no changes), and \--check reconciles the extra
download lines against the manifest after the primary bump, rewriting changed
lines and recomputing their checksums. A dep counts as changed only when its
upstream version differs, not merely its URL path shape, so a manifest's
bare-tag archive URL and the hint's SBo-fetched tree URL at the same version
are treated as current. Bundled deps are never followed to their
own latest release; only the manifest's pinned URLs are used. Manifest entries
with no matching download line are reported but not added. During the primary
version bump of a listed package, **mkhint** does not prompt to edit the extra
download lines by hand, since the manifest reconcile owns them.

# SEE ALSO

**slackrepo**(8), **nvchecker**(1), **nvtake**(1)

# AUTHOR

Danilo M. <danix@danix.xyz>
