# SemVer adoption Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Adopt SemVer: `mkhint -v`/`--version` prints the tool version, the hint-version flag moves to `-V`/`--set-version`, add a CHANGELOG, and tag `v1.0.0` signed.

**Architecture:** A `readonly MKHINT_VERSION` constant drives `--help` and a new `-v`/`--version` handler that prints and exits. The `getopt` spec and case handlers swap `-v`/`--version` (was hint-version, now tool-version) for `-V`/`--set-version` (hint-version). Tests, completion, and docs follow the rename. Release tagged at the end.

**Tech Stack:** bash, `getopt`, existing `tests/mkhint_test.sh` harness, git signed tags.

---

## File structure

- Modify: `mkhint` — version constant, `getopt` line, case handlers, mutual-exclusion messages, `show_help` + header comments.
- Modify: `tests/mkhint_test.sh` — rename `-v`→`-V` in 9 hint-version calls + T26/T56; add T65-T67.
- Modify: `mkhint.bash-completion` — `all_flags`, move the version-suggest case to `--set-version|-V`.
- Modify: `README.md` — flag docs, examples, SemVer/Conventional-commits note.
- Modify: `CLAUDE.md` — flag references, test table (T65-T67).
- Create: `CHANGELOG.md`.

No new dependencies.

---

## Task 1: Version constant + `-v`/`--version` output, flag rename

**Files:**
- Modify: `mkhint` (const near line 35; `getopt` ~1009; case ~1016; mutual-excl ~1103/1108)
- Test: `tests/mkhint_test.sh` (T65, T66, T67; rename existing `-v`)

- [ ] **Step 1: Write failing tests T65, T66, T67**

Append after T64 (before the SUMMARY block) in `tests/mkhint_test.sh`:

```bash
# ── T65: mkhint -v prints tool version ───────────────────────────────────────
echo ""
echo "T65: -v prints 'mkhint <version>' and exits 0"
set +e
out=$(run_mkhint -v 2>&1); code=$?
set -e
assert_exit_code "-v exits 0" 0 "$code"
echo "$out" | grep -Eq '^mkhint [0-9]+\.[0-9]+\.[0-9]+$' \
    && { echo "  PASS: -v prints version"; (( PASS++ )); } \
    || { echo "  FAIL: -v output wrong: $out"; (( FAIL++ )); ERRORS+=("T65 output"); }

# ── T66: mkhint --version prints tool version ────────────────────────────────
echo ""
echo "T66: --version prints 'mkhint <version>' and exits 0"
set +e
out=$(run_mkhint --version 2>&1); code=$?
set -e
assert_exit_code "--version exits 0" 0 "$code"
echo "$out" | grep -Eq '^mkhint [0-9]+\.[0-9]+\.[0-9]+$' \
    && { echo "  PASS: --version prints version"; (( PASS++ )); } \
    || { echo "  FAIL: --version output wrong: $out"; (( FAIL++ )); ERRORS+=("T66 output"); }

# ── T67: -V still sets the hint version (rename works) ───────────────────────
echo ""
echo "T67: -V <ver> -n <pkg> sets hint VERSION"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
run_mkhint -n curl -V 8.6.0 >/dev/null 2>&1
assert_contains "hint VERSION set via -V" "$MOCK_HINT/curl.hint" 'VERSION="8.6.0"'
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T6[567]'`
Expected: T65/T66 FAIL (`-v` currently expects an argument → getopt error / wrong output), T67 FAIL (`-V` unknown flag).

- [ ] **Step 3: Add the version constant**

In `mkhint`, after the `VERSION=""` line (~35), add:

```bash
readonly MKHINT_VERSION="1.0.0"
```

- [ ] **Step 4: Update the getopt spec**

Replace the `getopt` invocation (~1009):

```bash
    parsed=$(getopt -o vV:f:n:lcCdNhRF \
        --long version,set-version:,hintfile:,new:,list,clean,check,delete,no-dl,help,review,fix-current \
        -n 'mkhint' -- "$@") || { show_help; exit 1; }
```

- [ ] **Step 5: Replace the case handler**

Replace the `--version|-v)` case (~1016):

```bash
            --version|-v)
                echo "mkhint $MKHINT_VERSION"
                exit 0
                ;;
            --set-version|-V)
                VERSION="$2"
                shift 2
                ;;
```

- [ ] **Step 6: Update mutual-exclusion messages**

Change both messages (~1103, ~1108) `--version` → `--set-version`:

```bash
        echo "Error: --check cannot be combined with --set-version/--hintfile/--new" >&2
```
```bash
        echo "Error: --fix-current cannot be combined with --set-version/--hintfile/--new" >&2
```

- [ ] **Step 7: Rename existing `-v` hint-version calls in tests**

In `tests/mkhint_test.sh`, change `-v` to `-V` in these hint-version invocations
(the version-setting ones only — do NOT touch T65/T66 which use bare `-v`):

- line ~330: `run_mkhint -n curl -V 8.6.0`
- line ~347: `run_mkhint -n curl -V 8.7.0 -N`
- line ~372: `run_mkhint -f curl -V 8.9.0`
- line ~389: `run_mkhint -f curl -V 9.0.0 -N`
- line ~401: `run_mkhint -f clion -V 2025.4`
- line ~419: `run_mkhint -f nonexistent -V 1.0 2>/dev/null`
- line ~456: `echo "" | run_mkhint -n protoc-gen-go-grpc -V 1.4.0`
- line ~610 (T26): `run_mkhint -C -V 1.0 2>/dev/null`
- line ~1096 (T56): `run_mkhint -F -V 1.0.0 2>/dev/null`

Use grep to confirm none remain: `grep -n 'run_mkhint.* -v ' tests/mkhint_test.sh`
Expected: only the `-v` in T65 (bare, no value) — actually T65 uses `run_mkhint -v 2>&1`
with no trailing space-value, so this grep (`-v ` followed by a token) should
return nothing. Verify by eye.

- [ ] **Step 8: Run full suite**

Run: `bash -n mkhint && bash tests/mkhint_test.sh 2>&1 | tail -4`
Expected: `Results: 138 passed, 0 failed` (135 + T65/T66/T67).

- [ ] **Step 9: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat!: -v/--version prints tool version; hint version moves to -V/--set-version"
```

---

## Task 2: `--help` text + script header comments

**Files:**
- Modify: `mkhint` (header comments ~6-7; `show_help` ~50-78)

- [ ] **Step 1: Update the version-showing header line in show_help**

In `mkhint`, change the `show_help` title line (~50):

```bash
mkhint $MKHINT_VERSION - Manage hint files for slackrepo scripts
```

(The heredoc is `<<EOF` (unquoted), so `$MKHINT_VERSION` expands.)

- [ ] **Step 2: Update usage/synopsis lines in show_help**

Change the two `--version VERSION` usage lines (~53-54):

```bash
  ./mkhint --set-version VERSION --hintfile FILE    Update existing hint file
  ./mkhint --set-version VERSION --new FILE         Create new hint file
```

- [ ] **Step 3: Update the Options block in show_help**

Replace the `--version, -v VERSION` option line (~68) with two lines:

```bash
  --version, -v            Print version and exit
  --set-version, -V VER    New version string (required for --hintfile)
```

And update the `--new` line (~70) reference `--version` → `--set-version`:

```bash
  --new, -n FILE           Create new hint file (required with --set-version or standalone)
```

Also `--hintfile` line (~69): `required with --version` → `required with --set-version`.

- [ ] **Step 4: Update the script-header comments**

Change the two comment usage lines (~6-7):

```bash
#   ./mkhint --set-version VERSION --hintfile FILE    Update existing hint file
#   ./mkhint --set-version VERSION --new FILE         Create new hint file
```

- [ ] **Step 5: Verify help renders and syntax is clean**

Run: `bash -n mkhint && bash mkhint --help | head -3`
Expected: line 1 shows `mkhint 1.0.0 - Manage hint files for slackrepo scripts`.

- [ ] **Step 6: Commit**

```bash
git add mkhint
git commit -S -m "docs: show version in --help, rename version flag in help text"
```

---

## Task 3: Bash completion

**Files:**
- Modify: `mkhint.bash-completion` (`all_flags` line 11; case ~42)

- [ ] **Step 1: Update all_flags**

In `mkhint.bash-completion`, replace the `all_flags` line (11) to add `--set-version -V`
(keep `--version -v` in the list; it is terminal, no argument):

```bash
    local all_flags="--version -v --set-version -V --hintfile -f --new -n --list -l --review -R --clean -c --check -C --fix-current -F --delete -d --no-dl -N --help -h"
```

- [ ] **Step 2: Move the version-suggest case to --set-version|-V**

Change the case label (~42) from `--version|-v)` to:

```bash
        --set-version|-V)
```

The body (suggesting the current VERSION from the named hint file) is unchanged.
`--version`/`-v` need no case — they take no argument.

- [ ] **Step 3: Syntax check the completion**

Run: `bash -n mkhint.bash-completion && echo OK`
Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add mkhint.bash-completion
git commit -S -m "feat: completion knows -V/--set-version, -v/--version terminal"
```

---

## Task 4: CHANGELOG + docs + SemVer note

**Files:**
- Create: `CHANGELOG.md`
- Modify: `README.md` (flag refs, examples, SemVer note)
- Modify: `CLAUDE.md` (flag refs, test table)

- [ ] **Step 1: Create CHANGELOG.md**

Write `CHANGELOG.md`:

```markdown
# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-07-04

First tagged release. mkhint manages slackrepo hint files: create/update hints,
nvchecker-driven update checks, phantom-dep stripping for -current, and a
listing/review workflow.

### Changed
- **Breaking:** the hint-version flag is now `-V` / `--set-version`. `-v` /
  `--version` now prints the tool's own version and exits.

### Added
- `-v` / `--version` prints `mkhint X.Y.Z`.
- The `--help` header shows the version.
- `-l` colors the newer version cell green and adds a `DelReq` column.
```

- [ ] **Step 2: Update README flag references and examples**

In `README.md`, find every `-v` / `--version` that meant setting the hint version
and change to `-V` / `--set-version`. Run first to locate:

Run: `grep -n '\-v \|--version\|set-version' README.md`

Update each hint-version usage example and the options/flags description. Add a
short SemVer section near the top or bottom:

```markdown
## Versioning

This project follows [Semantic Versioning](https://semver.org/). Commits use
[Conventional Commits](https://www.conventionalcommits.org/): `feat:` bumps the
minor version, `fix:` the patch version, and a `!` / `BREAKING CHANGE` the major
version. Releases are tagged `vX.Y.Z`; the version is stored in `MKHINT_VERSION`
in the `mkhint` script. `mkhint -v` prints it.
```

- [ ] **Step 3: Update CLAUDE.md flag references**

In `CLAUDE.md`, update any `-v`/`--version` that means hint-version to
`-V`/`--set-version`. Run first: `grep -n '\-v \|--version\|set-version' CLAUDE.md`

Add a one-line note under Configuration or a new "Versioning" note: the tool
version lives in `MKHINT_VERSION`; `-v`/`--version` prints it; `-V`/`--set-version`
sets a hint's version.

- [ ] **Step 4: Add T65-T67 to the CLAUDE.md test table**

Append after T64:

```
| T65 | `mkhint -v` prints `mkhint <version>`, exit 0 |
| T66 | `mkhint --version` prints `mkhint <version>`, exit 0 |
| T67 | `mkhint -V <ver> -n <pkg>` sets hint VERSION (rename works) |
```

- [ ] **Step 5: Full suite + syntax, sanity re-read docs**

Run: `bash -n mkhint && bash tests/mkhint_test.sh 2>&1 | tail -3`
Expected: `138 passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add CHANGELOG.md README.md CLAUDE.md
git commit -S -m "docs: add CHANGELOG, document SemVer and -V/--set-version rename"
```

---

## Task 5: Tag the release

**Files:** none (git tag only)

- [ ] **Step 1: Confirm working tree is clean and tests pass**

Run: `git status --porcelain && bash tests/mkhint_test.sh 2>&1 | tail -2`
Expected: no output from status; `138 passed, 0 failed`.

- [ ] **Step 2: Create the signed annotated tag**

```bash
git tag -s v1.0.0 -m "mkhint 1.0.0"
git tag -v v1.0.0
```
Expected: `git tag -v` shows a good GPG signature.

- [ ] **Step 3: Push commits and tag to both remotes**

`origin` has two push URLs (danix_git, slackware_forge).

```bash
git push origin master
git push origin v1.0.0
```
Expected: both refs land on both remotes.

---

## Self-review notes

- Spec coverage: version constant + output (Task 1), flag rename (Task 1), mutual-excl messages (Task 1), help text (Task 2), completion (Task 3), CHANGELOG (Task 4), README/CLAUDE + SemVer/Conventional note (Task 4), git tag (Task 5), tests T65-T67 + renames (Task 1). All covered.
- Flag names consistent across tasks: `-V`/`--set-version` (hint version), `-v`/`--version` (tool version, no arg).
- getopt string `vV:f:n:lcCdNhRF` — `v` bare, `V:` takes arg. Verified against current `v:f:n:lcCdNhRF`.
- Test count: 135 → 138 (T65, T66, T67). Renamed calls do not change the count.
- T26/T56 assert exit code only (no message grep), so `-v`→`-V` is safe there.
- Breaking change flagged with `feat!:` commit and CHANGELOG "Breaking" entry.
