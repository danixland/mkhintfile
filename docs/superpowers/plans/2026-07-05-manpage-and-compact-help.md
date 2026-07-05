# Man page + compact --help Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a gzipped `mkhint.1` man page as the full reference and slim `--help` to a scannable summary that points at it.

**Architecture:** Man page authored in Markdown (`mkhint.1.md`), built with pandoc to roff, gzipped, and committed as `mkhint.1.gz` so the target VM needs no pandoc. The `show_help` heredoc in `mkhint` is trimmed to title + synopsis + options + runtime paths + man pointer. Install docs and the test suite are updated to match.

**Tech Stack:** bash, pandoc 3.9 (dev host only), gzip, groff/man for verification.

---

### Task 1: Author the man page source

**Files:**
- Create: `mkhint.1.md`

- [ ] **Step 1: Write `mkhint.1.md`**

Create `mkhint.1.md` with exactly this content:

````markdown
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
````

- [ ] **Step 2: Commit**

```bash
git add mkhint.1.md
git commit -S -m "docs: add mkhint.1 man page source"
```

---

### Task 2: Build and commit the gzipped man page

**Files:**
- Create: `mkhint.1.gz` (generated)
- Create: `.gitignore`

- [ ] **Step 1: Add `.gitignore` for the uncompressed intermediate**

Create `.gitignore` with:

```
mkhint.1
```

- [ ] **Step 2: Build the man page**

Run:

```bash
pandoc mkhint.1.md -s -t man -o mkhint.1 && gzip -9 -n -f mkhint.1
```

Expected: produces `mkhint.1.gz`, no `mkhint.1` left (gzip removes the source).

- [ ] **Step 3: Verify it renders**

Run: `man ./mkhint.1.gz`
Expected: the man page displays with NAME, SYNOPSIS, OPTIONS, etc. Quit with `q`. Check for no groff warnings on stderr:

```bash
zcat mkhint.1.gz | groff -man -Tascii -ww >/dev/null
```

Expected: no output (no warnings).

- [ ] **Step 4: Commit**

```bash
git add .gitignore mkhint.1.gz
git commit -S -m "docs: build gzipped mkhint.1 man page"
```

---

### Task 3: Compact the `--help` output (TDD)

**Files:**
- Modify: `mkhint` (the `show_help` heredoc, lines ~59-105)
- Test: `tests/mkhint_test.sh` (add T73)

- [ ] **Step 1: Write the failing test**

Add T73 at the end of the test file, immediately after the last existing test block (T72). Model it exactly on T65/T66: use the `run_mkhint` wrapper, wrap the call in `set +e`/`set -e`, check the exit code with the existing `assert_exit_code` helper, and grep the captured output. Note: the suite's `assert_contains` takes a **file** path, not a string, so it cannot be used for stdout — grep the captured `$out` directly, as T65/T66 do.

```bash
# ── T73: --help compact, exits 0, points at man page ─────────────────────────
echo ""
echo "T73: --help exits 0 and points at 'man mkhint'"
set +e
out=$(run_mkhint --help 2>&1); code=$?
set -e
assert_exit_code "--help exits 0" 0 "$code"
echo "$out" | grep -q 'man mkhint' \
    && { echo "  PASS: --help points at man page"; (( PASS++ )); } \
    || { echo "  FAIL: --help missing man pointer: $out"; (( FAIL++ )); ERRORS+=("T73 pointer"); }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -i t73`
Expected: FAIL — current help contains no `man mkhint` string.

- [ ] **Step 3: Rewrite `show_help`**

Replace the entire `show_help` function body (the `cat <<EOF ... EOF` block) with:

```bash
show_help() {
    cat <<EOF
mkhint $MKHINT_VERSION - Manage hint files for slackrepo scripts

Usage: mkhint [OPTION] [FILE...]

Options:
  --version, -v            Print version and exit
  --set-version, -V VER    New version string (required for --hintfile)
  --hintfile, -f FILE      Path to existing hint file (required with --set-version)
  --new, -n FILE           Create new hint file (required with --set-version or standalone)
  --list, -l [FILE...]     List all hint files; FILE... = side-by-side hint vs .info
  --review, -R [FILE...]   Review hints; no args = matched only, FILE... = named hints (any version)
  --clean, -c              Remove all .bak files from HINT_DIR
  --check, -C [FILE...]    Check hints for upstream updates via nvchecker, update interactively
  --fix-current, -F        Add/merge DELREQUIRES for -current phantom deps across the whole repo
  --delete, -d FILE        Delete a hint file (and .bak if present)
  --no-dl, -N              Skip downloads; add NODOWNLOAD=yes to hint file (use with -f or -n)
  --help, -h               Show this help message

Config file: ${MKHINT_CONFIG}$([[ -f "$MKHINT_CONFIG" ]] && echo " (present, sourced)" || echo " (not present, using defaults)")
Hint files are stored in: $HINT_DIR
Temporary files are stored in: $TMP_DIR
Phantom-dep list (for --fix-current / --new): $PHANTOM_DEPS_FILE

See 'man mkhint' for usage examples, configuration, and exit codes.
EOF
}
```

This drops the 12 usage examples, the "Variables order in hint files" note, and the exit-code table, keeping the options list, the runtime-paths block (with the config-status line), and adding the man pointer.

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -i t73`
Expected: PASS.

- [ ] **Step 5: Run the full suite and syntax check**

Run:

```bash
bash -n mkhint && bash tests/mkhint_test.sh 2>&1 | tail -5
```

Expected: `bash -n` clean, full suite passes (T1..T73), no regressions.

- [ ] **Step 6: Eyeball the help**

Run: `bash mkhint --help`
Expected: ~20 lines, ends with the `man mkhint` pointer, config-status line present.

- [ ] **Step 7: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: compact --help, move reference to man page

Trim show_help to a usage synopsis, the options list, the runtime
paths, and a 'man mkhint' pointer. The usage examples, variable-order
note, and exit-code table now live in the man page. Add T73 asserting
--help exits 0 and points at the man page."
```

---

### Task 4: Update install docs

**Files:**
- Modify: `README.md` (Installation section, around lines 5-17)
- Modify: `CLAUDE.md` (Installation section near the bottom)

- [ ] **Step 1: Add man-page install to README.md**

In `README.md`, after the Bash Completion install block (the `mkhint.bash-completion` `sudo cp`, around line 17), add:

````markdown
### Man Page

```bash
sudo cp mkhint.1.gz /usr/local/man/man1/mkhint.1.gz
```

The man page is pre-built and committed. To regenerate it from source (requires
pandoc):

```bash
pandoc mkhint.1.md -s -t man -o mkhint.1 && gzip -9 -n -f mkhint.1
```
````

- [ ] **Step 2: Add man-page install to CLAUDE.md**

In `CLAUDE.md`, in the `## Installation` block, after the completion `sudo cp`
line, add:

```bash
sudo cp mkhint.1.gz /usr/local/man/man1/mkhint.1.gz
```

And add a sentence noting the man page source is `mkhint.1.md`, rebuilt with
`pandoc mkhint.1.md -s -t man -o mkhint.1 && gzip -9 -n -f mkhint.1`; `--help`
is a compact summary that points at `man mkhint`.

- [ ] **Step 3: Commit**

```bash
git add README.md CLAUDE.md
git commit -S -m "docs: document man page install and compact --help"
```

---

### Task 5: Update CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add an [Unreleased] entry**

At the top of `CHANGELOG.md`, above `## [1.1.0]`, add (create the
`## [Unreleased]` heading if absent, follow the existing Keep-a-Changelog
style already in the file):

```markdown
## [Unreleased]

### Added
- `mkhint.1` man page (gzipped, built from `mkhint.1.md` with pandoc) as the full reference.
- `--help` now reports whether `~/.config/mkhint/config` is present and sourced.

### Changed
- `--help` is now a compact summary; usage examples, the variable-order note, and the exit-code table moved to the man page.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -S -m "docs: changelog for man page and compact --help"
```

---

## Notes for the executor

- All commits are GPG-signed (`-S`); the environment signs without prompting.
- Do not release/tag in this plan; version bump and tagging happen in a
  separate release step chosen by the user.
- Do not deploy to the VM in this plan; deployment is a separate ship step.
- The config-status line in `show_help` was already added earlier (commit
  `a59ae6c`); Task 3 preserves it inside the rewritten heredoc.
