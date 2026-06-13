# nvchecker Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add nvchecker support to `mkhint` so it can discover the latest upstream version and use it when creating, updating, and bulk-checking hint files.

**Architecture:** `mkhint` is a single bash script. We add a config constant, a tool-availability check, and four helper functions, then hook them into the existing `--new` and `--hintfile` code paths and add a new `--check`/`-C` command. The hint file's `VERSION` field stays the source of truth; nvchecker's newver keyfile supplies the latest version; `nvtake` syncs nvchecker state after each update.

**Tech Stack:** bash, getopt, nvchecker + nvtake (Python tools), jq, sort -V. Tests use the existing mock-based suite in `tests/mkhint_test.sh` (fake binaries on PATH).

---

## Background for the implementer

Read these before starting:

- **Spec:** `docs/superpowers/specs/2026-06-13-nvchecker-integration-design.md` — the agreed design. This plan implements it exactly.
- **Main script:** `mkhint` (572 lines). Relevant anchors:
  - Config constants: lines 18-21 (`REPO_DIR`, `HINT_DIR`, `TMP_DIR`).
  - Variable defaults: lines 28-34 (`VERSION`, `HINT_FILE`, `NEW_HINT_FILE`, `COMMAND`, `NO_DL`).
  - `check_wget()`: lines 116-122 — model `check_nvchecker` on this (uses `exit 4`).
  - `create_new_hint_file()`: lines 144-211 — Feature 1 hook goes near the end of the "generated from .info" branch (after line 188-189 echoes) and in the empty-skeleton branch is **not** needed (no `.info` to detect from). Only hook the `.info` branch.
  - `update_checksums()` / `_process_download_var()`: lines 292-362 — reused as-is, no changes.
  - `update_hint_file()`: lines 364-405 — reused as-is. After it returns successfully in the `update` command path we call `nvtake`.
  - `prompt_slackrepo()`: lines 407-416 — reused; note it only takes a single pkg today. Feature 3 passes multiple pkg names; `slackrepo update "$pkg"` becomes `slackrepo update $pkgs` (word-split intentionally) — see Task 9.
  - `main()` getopt: lines 463-467. Short opts string `v:f:n:lcdNh`, long opts `version:,hintfile:,new:,list,clean,delete,no-dl,help`.
  - `case` arg loop: lines 470-514. Command dispatch: lines 538-569.
  - Default-command inference: lines 522-531.
- **Test harness:** `tests/mkhint_test.sh`. Key mechanics:
  - `run_mkhint()` (lines 70-82) copies `mkhint` to a temp file and `sed`-patches `REPO_DIR`/`HINT_DIR`/`TMP_DIR` to mock paths. We will add an `NVCHECKER_CONFIG` patch line.
  - `mock_wget()` (lines 85-104) writes a fake `wget` into `$MOCK_BASE/bin` and prepends to `PATH`. We add `mock_nvchecker_tools()` the same way for `nvchecker`, `nvtake`, `jq`.
  - Interactive prompts are driven by piping stdin, e.g. `echo "" | run_mkhint ...` (line 322).
  - Assertions: `assert_contains`, `assert_not_contains`, `assert_file_exists`, `assert_file_not_exists`, `assert_exit_code`.

**Important bash gotcha:** the script runs under `set -e` (line 16). Any helper that can "fail" as a normal outcome (e.g. `nvchecker_latest` when no version found) must be called in a context where a non-zero return does not kill the script — use it in an `if`, `||`, or capture with `local x; x=$(...) || true`. Each task notes this where relevant.

**nvchecker behaviour the mocks emulate:**
- `nvchecker -c CONFIG` runs all sources and writes results to the newver keyfile named in the `[__config__]` section's `newver = "..."` key. The keyfile is JSON: `{ "version": 2, "data": { "pkg": { "version": "X" } } }` (nvchecker 2.x format). We read it with `jq -r '.data["pkg"].version'`.
- `nvtake pkg` copies pkg's newver into the oldver keyfile. The mock just records the call.

---

## File Structure

- `mkhint` — all logic changes (new constant, `check_nvchecker`, `add_nvchecker_section`, `nvchecker_latest`, `suggest_version`, `check_updates`; getopt + dispatch wiring; `nvtake` after updates; help text).
- `mkhint.bash-completion` — add `--check -C` to flag list; complete package names after `--check`.
- `README.md` — document features + new dependencies.
- `tests/mkhint_test.sh` — `NVCHECKER_CONFIG` patch, `mock_nvchecker_tools()`, test cases T16–T26.

We keep everything in `mkhint` (single-file tool, established pattern — do not split).

---

## Task 1: Add NVCHECKER_CONFIG constant and help/exit-code text

**Files:**
- Modify: `mkhint:18-21` (constants), `mkhint:36-74` (help text)

- [ ] **Step 1: Add the config constant**

In `mkhint`, after the `TMP_DIR` line (line 21), add:

```bash
NVCHECKER_CONFIG="$HOME/.config/nvchecker/nvchecker.toml"
```

So the block reads:

```bash
REPO_DIR="/var/lib/sbopkg/SBo-danix/"
HINT_DIR="/etc/slackrepo/SBo-danix/hintfiles/"
TMP_DIR="/tmp/mkhint"
NVCHECKER_CONFIG="$HOME/.config/nvchecker/nvchecker.toml"
```

- [ ] **Step 2: Add help lines for the new behaviours**

In `show_help()`, in the `Usage:` block (after the `--new FILE ... (no version)` line, currently line 44), add:

```
  ./mkhint --hintfile FILE                      Update hint, suggest latest version via nvchecker
  ./mkhint --check [FILE...]                     Check all (or named) hints for upstream updates
```

In the `Options:` block, after the `--clean, -c` line (currently line 56), add:

```
  --check, -C [FILE...]    Check hints for upstream updates via nvchecker, update interactively
```

In the `Exit codes:` block, change the `4 - wget not available` line to:

```
  4 - required tool not available (wget / nvchecker / nvtake / jq)
```

- [ ] **Step 3: Verify the script still parses and help renders**

Run: `bash mkhint --help`
Expected: help text prints including the new `--check` and `--hintfile FILE` lines; exit 0.

- [ ] **Step 4: Commit**

```bash
git add mkhint
git commit -m "feat: add NVCHECKER_CONFIG constant and help text for nvchecker features"
```

---

## Task 2: Add check_nvchecker tool-availability function

**Files:**
- Modify: `mkhint` (add function after `check_wget`, around line 122)

- [ ] **Step 1: Add the function**

After `check_wget()` (after line 122), add:

```bash
# Validate nvchecker toolchain availability
check_nvchecker() {
    local missing=()
    command -v nvchecker &> /dev/null || missing+=("nvchecker")
    command -v nvtake   &> /dev/null || missing+=("nvtake")
    command -v jq       &> /dev/null || missing+=("jq")
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "Error: required tool(s) not installed: ${missing[*]}" >&2
        echo "Install nvchecker (provides nvchecker + nvtake) and jq." >&2
        exit 4
    fi
    if [[ ! -f "$NVCHECKER_CONFIG" ]]; then
        echo "Error: nvchecker config not found: $NVCHECKER_CONFIG" >&2
        exit 2
    fi
}
```

- [ ] **Step 2: Syntax check**

Run: `bash -n mkhint`
Expected: no output, exit 0 (syntax OK).

- [ ] **Step 3: Commit**

```bash
git add mkhint
git commit -m "feat: add check_nvchecker tool-availability guard"
```

---

## Task 3: Add nvchecker keyfile read helper

This reads the newver keyfile path from `[__config__]` and extracts a package's latest version.

**Files:**
- Modify: `mkhint` (add function after `check_nvchecker`)

- [ ] **Step 1: Add the helper**

After `check_nvchecker()`, add:

```bash
# Echo the newver-keyfile path declared in [__config__] of NVCHECKER_CONFIG
_nvchecker_newver_path() {
    # Grab the `newver = "..."` value; tolerate spaces around =
    local line
    line=$(grep -E '^[[:space:]]*newver[[:space:]]*=' "$NVCHECKER_CONFIG" | head -1)
    [[ -z "$line" ]] && return 1
    # extract the quoted path
    local path
    path=$(printf '%s\n' "$line" | sed -E 's/^[^"]*"([^"]*)".*/\1/')
    [[ -z "$path" ]] && return 1
    # expand a leading ~ to $HOME
    path="${path/#\~/$HOME}"
    printf '%s\n' "$path"
}

# Echo the latest version nvchecker found for a package, or return non-zero
# Usage: latest=$(nvchecker_latest pkg) || handle "no version"
nvchecker_latest() {
    local pkg="$1"
    local keyfile
    keyfile=$(_nvchecker_newver_path) || return 1
    [[ -f "$keyfile" ]] || return 1
    local ver
    ver=$(jq -r --arg p "$pkg" '.data[$p].version // empty' "$keyfile" 2>/dev/null)
    [[ -z "$ver" ]] && return 1
    printf '%s\n' "$ver"
}
```

Note (`set -e`): always call `nvchecker_latest` as `x=$(nvchecker_latest p) || ...` so its non-zero return is handled, not fatal.

- [ ] **Step 2: Syntax check**

Run: `bash -n mkhint`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add mkhint
git commit -m "feat: add nvchecker_latest keyfile reader"
```

---

## Task 4: Add add_nvchecker_section (Feature 1 core), with test

Writes a `[pkg]` section to the nvchecker config, auto-detecting GitHub/PyPI from the `.info`.

**Files:**
- Modify: `mkhint` (add function near `create_new_hint_file`, e.g. after line 211)
- Test: `tests/mkhint_test.sh` (T16–T19) — added in Task 8 after the mock exists. This task ships the function + a `bash -n` check; behavioural tests come in Task 8.

- [ ] **Step 1: Add the function**

After `create_new_hint_file()` (after line 211), add:

```bash
# Append an nvchecker [pkg] section to NVCHECKER_CONFIG, auto-detecting the
# source from the package's .info DOWNLOAD/HOMEPAGE. No-op if section exists.
add_nvchecker_section() {
    local pkg="$1"
    local info_file="$2"

    # Ensure config dir/file exist (do not create __config__; user owns that)
    mkdir -p "$(dirname "$NVCHECKER_CONFIG")"
    touch "$NVCHECKER_CONFIG"

    # Skip if section already present
    if grep -qE "^\[${pkg}\][[:space:]]*$" "$NVCHECKER_CONFIG"; then
        echo "nvchecker: [${pkg}] already present in $NVCHECKER_CONFIG"
        return 0
    fi

    local download="" homepage=""
    if [[ -f "$info_file" ]]; then
        download=$(grep -E '^(DOWNLOAD|DOWNLOAD_x86_64)=' "$info_file" | head -1)
        homepage=$(grep -E '^HOMEPAGE=' "$info_file" | head -1)
    fi
    local haystack="${download} ${homepage}"

    local section=""
    if [[ "$haystack" =~ github\.com/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+) ]]; then
        local owner="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]}"
        repo="${repo%.git}"
        section=$(cat <<EOF

[${pkg}]
source = "github"
github = "${owner}/${repo}"
use_max_tag = true
EOF
)
    elif [[ "$haystack" =~ (pypi\.org|files\.pythonhosted\.org) ]]; then
        section=$(cat <<EOF

[${pkg}]
source = "pypi"
pypi = "${pkg}"
EOF
)
    else
        section=$(cat <<EOF

[${pkg}]
# TODO: configure nvchecker source for "${pkg}"
# source = "regex"
# url = "..."
# regex = "..."
# see https://nvchecker.readthedocs.io/en/latest/usage.html
EOF
)
    fi

    printf '%s\n' "$section" >> "$NVCHECKER_CONFIG"
    echo "nvchecker: review/fill [${pkg}] section in $NVCHECKER_CONFIG"
}
```

- [ ] **Step 2: Syntax check**

Run: `bash -n mkhint`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add mkhint
git commit -m "feat: add add_nvchecker_section with github/pypi autodetect"
```

---

## Task 5: Hook add_nvchecker_section into the --new path

**Files:**
- Modify: `mkhint:188-190` (inside `create_new_hint_file`, the `.info` branch)

- [ ] **Step 1: Call it after the hint is generated from .info**

In `create_new_hint_file()`, in the branch that copies from `.info`, the current tail is:

```bash
            echo "generated $normalized_file from $(basename $info)."
            echo "Check variables before using."
        fi
```

Change to:

```bash
            echo "generated $normalized_file from $(basename $info)."
            echo "Check variables before using."
            add_nvchecker_section "${normalized_file%.hint}" "$info"
        fi
```

(`$info` is the resolved `.info` path from line 155; `${normalized_file%.hint}` is the bare package name.)

Do **not** add it to the empty-skeleton `else` branch — there is no `.info` to detect from.

- [ ] **Step 2: Syntax check**

Run: `bash -n mkhint`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add mkhint
git commit -m "feat: write nvchecker section on --new from .info"
```

---

## Task 6: Add suggest_version (Feature 2 core) and wire the no-version update path

**Files:**
- Modify: `mkhint` (add `suggest_version` after `nvchecker_latest`); `main()` default-command inference (lines 522-531) and `update` dispatch (lines 548-552)

- [ ] **Step 1: Add suggest_version**

After `nvchecker_latest()`, add:

```bash
# Query nvchecker for a package's latest version and let the user accept or
# override it. Echoes the chosen version on stdout. Returns non-zero if the
# user declines or no version is available (caller decides what to do).
suggest_version() {
    local pkg="$1"

    # Refresh nvchecker results (stderr only; keep stdout clean for the echo)
    nvchecker -c "$NVCHECKER_CONFIG" >&2 || true

    local latest
    latest=$(nvchecker_latest "$pkg") || {
        echo "Error: no nvchecker result for '$pkg'. Add/fix its [${pkg}] section in $NVCHECKER_CONFIG" >&2
        return 1
    }

    # Read current version from the hint file (best effort, for display)
    local hintpath="${HINT_DIR%/}/${pkg}.hint"
    local current=""
    [[ -f "$hintpath" ]] && current=$(grep '^VERSION=' "$hintpath" | sed 's/VERSION="//;s/"$//')

    local answer
    read -r -p "current ${current:-?}, latest ${latest}. Use ${latest}? [Y/n] (or type a version) " answer >&2
    answer="${answer:-Y}"
    case "$answer" in
        [Yy]) printf '%s\n' "$latest" ;;
        [Nn]) return 1 ;;
        *)    printf '%s\n' "$answer" ;;   # user typed an explicit version
    esac
}
```

Note: prompt and nvchecker noise go to stderr so the command-substitution capturing the chosen version (`VERSION=$(suggest_version ...)`) only receives the version string.

- [ ] **Step 2: Let `--hintfile` with no `-v` resolve to the update command**

In `main()`, the default-command inference block (lines 522-531) currently makes `update` require both `VERSION` and `HINT_FILE`:

```bash
        if [[ -n "$VERSION" && -n "$HINT_FILE" ]]; then
            COMMAND="update"
```

Change the first condition to allow `--hintfile` alone:

```bash
        if [[ -n "$HINT_FILE" ]]; then
            COMMAND="update"
```

(When `VERSION` is empty we'll fill it via `suggest_version` in the dispatch.)

- [ ] **Step 3: Fill VERSION in the `update` dispatch when empty**

The `update` case (lines 548-552) currently is:

```bash
        update)
            check_wget
            update_hint_file "$HINT_FILE" "$VERSION"
            prompt_slackrepo "$HINT_FILE"
            ;;
```

Change to:

```bash
        update)
            check_wget
            if [[ -z "$VERSION" ]]; then
                check_nvchecker
                VERSION=$(suggest_version "$HINT_FILE") || { echo "Aborted." >&2; exit 0; }
                check_nvchecker_take=1
            fi
            update_hint_file "$HINT_FILE" "$VERSION"
            if [[ "${check_nvchecker_take:-0}" -eq 1 ]]; then
                nvtake -c "$NVCHECKER_CONFIG" "$HINT_FILE" >&2 || true
            fi
            prompt_slackrepo "$HINT_FILE"
            ;;
```

Rationale: `nvtake` runs only when the version came from nvchecker (so an explicit `-v` update does not touch nvchecker state). `>&2 || true` keeps `set -e` happy if nvtake has nothing to take.

- [ ] **Step 4: Syntax check**

Run: `bash -n mkhint`
Expected: no output, exit 0.

- [ ] **Step 5: Commit**

```bash
git add mkhint
git commit -m "feat: suggest nvchecker version on --hintfile without -v"
```

---

## Task 7: Add check_updates (Feature 3) and the --check/-C command

**Files:**
- Modify: `mkhint` (add `check_updates` after `clean_bak_files`, ~line 460); getopt (lines 465-467); arg `case` (add `--check|-C`); mutual-exclusion guard; dispatch.

- [ ] **Step 1: Add the bulk function**

After `clean_bak_files()` (after line 460), add:

```bash
# Bulk-check hint files for upstream updates and apply interactively.
# Usage: check_updates [pkg...]   (no args = all *.hint in HINT_DIR)
check_updates() {
    check_nvchecker

    if [[ ! -d "$HINT_DIR" ]]; then
        echo "Error: Hint directory does not exist: $HINT_DIR" >&2
        exit 2
    fi

    # Build the target package list
    local targets=()
    if [[ $# -gt 0 ]]; then
        targets=("$@")
    else
        local f
        for f in "$HINT_DIR"/*.hint; do
            [[ -f "$f" ]] || continue
            local b; b=$(basename "$f"); targets+=("${b%.hint}")
        done
    fi

    # Refresh nvchecker results once for everything
    echo "Running nvchecker..."
    nvchecker -c "$NVCHECKER_CONFIG" >&2 || true

    # Classify each target
    local outdated_pkgs=() outdated_old=() outdated_new=() outdated_flag=()
    local pkg
    for pkg in "${targets[@]}"; do
        local hintpath="${HINT_DIR%/}/${pkg}.hint"
        [[ -f "$hintpath" ]] || { echo "skip ${pkg}: no hint file"; continue; }
        local current; current=$(grep '^VERSION=' "$hintpath" | sed 's/VERSION="//;s/"$//')
        local latest
        latest=$(nvchecker_latest "$pkg") || { echo "skip ${pkg}: no nvchecker source"; continue; }
        [[ "$current" == "$latest" ]] && continue   # up to date
        # determine direction with sort -V
        local newest; newest=$(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -1)
        local flag="update"
        [[ "$newest" == "$current" ]] && flag="?downgrade"
        outdated_pkgs+=("$pkg")
        outdated_old+=("$current")
        outdated_new+=("$latest")
        outdated_flag+=("$flag")
    done

    if [[ ${#outdated_pkgs[@]} -eq 0 ]]; then
        echo "all up to date"
        return 0
    fi

    # Report
    echo ""
    echo "Updates available:"
    local i
    for (( i=0; i<${#outdated_pkgs[@]}; i++ )); do
        local note=""; [[ "${outdated_flag[$i]}" == "?downgrade" ]] && note=" (?downgrade)"
        printf "  %-30s %s -> %s%s\n" "${outdated_pkgs[$i]}" "${outdated_old[$i]}" "${outdated_new[$i]}" "$note"
    done
    echo ""

    # Per-package confirm + update
    local updated=()
    for (( i=0; i<${#outdated_pkgs[@]}; i++ )); do
        local p="${outdated_pkgs[$i]}"
        local note=""; [[ "${outdated_flag[$i]}" == "?downgrade" ]] && note=" (?downgrade)"
        local answer
        read -r -p "${p}  ${outdated_old[$i]} -> ${outdated_new[$i]}${note}. Update? [Y/n] " answer
        answer="${answer:-Y}"
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            update_hint_file "$p" "${outdated_new[$i]}"
            nvtake -c "$NVCHECKER_CONFIG" "$p" >&2 || true
            updated+=("$p")
        fi
    done

    # Single slackrepo prompt for everything updated
    if [[ ${#updated[@]} -gt 0 ]]; then
        local answer
        read -r -p "Run 'slackrepo update ${updated[*]}'? [Y/n] " answer
        answer="${answer:-Y}"
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            slackrepo update "${updated[@]}"
        fi
    fi
}
```

Note (`set -e`): `nvchecker_latest` is used in `latest=$(...) || { ...; continue; }`, and `nvchecker`/`nvtake` are `|| true` — all non-zero outcomes are handled.

- [ ] **Step 2: Add the getopt entries**

Change the getopt line (lines 465-467) short-opt string from `v:f:n:lcdNh` to `v:f:n:lcCdNh` (add `C`), and add `check` to the long options:

```bash
    parsed=$(getopt -o v:f:n:lcCdNh \
        --long version:,hintfile:,new:,list,clean,check,delete,no-dl,help \
        -n 'mkhint' -- "$@") || { show_help; exit 1; }
```

- [ ] **Step 3: Add the arg-loop case**

In the `while true; do case "$1" in` loop, after the `--clean|-c)` case (lines 488-490), add:

```bash
            --check|-C)
                COMMAND="check"
                shift
                ;;
```

- [ ] **Step 4: Add mutual-exclusion guard**

After the existing `--no-dl` guard block (lines 533-536), add:

```bash
    if [[ "$COMMAND" == "check" && ( -n "$VERSION" || -n "$HINT_FILE" || -n "$NEW_HINT_FILE" ) ]]; then
        echo "Error: --check cannot be combined with --version/--hintfile/--new" >&2
        exit 1
    fi
```

- [ ] **Step 5: Add the dispatch case**

In the final `case "$COMMAND" in`, after the `clean)` case (lines 545-547), add:

```bash
        check)
            check_updates "${DELETE_HINT_FILES[@]}"
            ;;
```

(`DELETE_HINT_FILES` holds leftover positional args — for `--check` these are the optional package names. The array may be empty, which `check_updates` treats as "all".)

- [ ] **Step 6: Syntax check + help smoke test**

Run: `bash -n mkhint && bash mkhint --help`
Expected: syntax OK; help prints with `--check` line; exit 0.

- [ ] **Step 7: Commit**

```bash
git add mkhint
git commit -m "feat: add --check/-C bulk update command"
```

---

## Task 8: Test infrastructure — NVCHECKER_CONFIG patch + mock tools

**Files:**
- Modify: `tests/mkhint_test.sh` (`run_mkhint` sed block ~lines 73-77; add `mock_nvchecker_tools` near `mock_wget`; call it after `mock_wget` ~line 177)

- [ ] **Step 1: Patch NVCHECKER_CONFIG in run_mkhint**

In `run_mkhint()`, the sed block currently patches three paths. Add a fourth `-e` to point the config at a mock file under `$MOCK_BASE`:

```bash
    sed \
        -e "s|REPO_DIR=\".*\"|REPO_DIR=\"$MOCK_REPO\"|" \
        -e "s|HINT_DIR=\".*\"|HINT_DIR=\"$MOCK_HINT\"|" \
        -e "s|TMP_DIR=\".*\"|TMP_DIR=\"$MOCK_TMP\"|" \
        -e "s|NVCHECKER_CONFIG=\".*\"|NVCHECKER_CONFIG=\"$MOCK_BASE/nvchecker.toml\"|" \
        "$SCRIPT" > "$tmp_script"
```

- [ ] **Step 2: Add a base nvchecker config + keyfile in setup**

In `setup()`, after the mock `.info` files are written (before the closing `}` at line 64), add a base nvchecker config with `[__config__]` and a keyfile the mock tools will read/write:

```bash
    # nvchecker config + keyfile for tests
    cat > "$MOCK_BASE/nvchecker.toml" << EOF
[__config__]
oldver = "$MOCK_BASE/old_ver.json"
newver = "$MOCK_BASE/new_ver.json"
EOF
    # keyfile pre-seeded with versions the mock nvchecker will "find"
    cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": { "curl": { "version": "8.9.0" }, "clion": { "version": "2025.4" } } }
EOF
    cp "$MOCK_BASE/new_ver.json" "$MOCK_BASE/old_ver.json"
```

Note: the keyfile is the contract between mock nvchecker and the script. Tests control "latest" by editing `new_ver.json`.

- [ ] **Step 3: Add mock_nvchecker_tools**

After `mock_wget()` (after line 104), add:

```bash
# Mock nvchecker, nvtake, jq into $MOCK_BASE/bin
mock_nvchecker_tools() {
    mkdir -p "$MOCK_BASE/bin"

    # nvchecker: no-op success (keyfile is pre-seeded by setup/tests)
    cat > "$MOCK_BASE/bin/nvchecker" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$MOCK_BASE/bin/nvchecker"

    # nvtake: record invocations, otherwise no-op
    cat > "$MOCK_BASE/bin/nvtake" << EOF
#!/bin/bash
echo "nvtake \$*" >> "$MOCK_BASE/nvtake.log"
exit 0
EOF
    chmod +x "$MOCK_BASE/bin/nvtake"

    # jq: only if real jq is absent — prefer the real one when available.
    if ! command -v jq &> /dev/null; then
        echo "WARNING: real jq not found; install jq to run nvchecker tests" >&2
    fi
}
```

Rationale: real `jq` is the cleanest way to honour the actual JSON contract. The mock provides `nvchecker`/`nvtake` only. If `jq` is genuinely unavailable on the dev machine, the warning makes the dependency obvious.

- [ ] **Step 4: Call the mock after mock_wget**

After the `mock_wget` call (line 177), add:

```bash
mock_nvchecker_tools
```

- [ ] **Step 5: Run the existing suite to confirm no regressions**

Run: `bash tests/mkhint_test.sh`
Expected: T1–T15 still report `PASS`; final line `Results: N passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add tests/mkhint_test.sh
git commit -m "test: add nvchecker config patch and mock tools to harness"
```

---

## Task 9: Add behavioural tests T16–T26

**Files:**
- Modify: `tests/mkhint_test.sh` (insert new test blocks before the `SUMMARY` section, after T15 ~line 334)

Add a GitHub `.info` and a PyPI `.info` to `setup()` first, then the tests.

- [ ] **Step 1: Add github + pypi fixtures to setup**

In `setup()`, add two repo dirs to the initial `mkdir -p` (line 15-19) — append `"$MOCK_REPO/development/ghpkg"` and `"$MOCK_REPO/python/pypkg"` to the list. Then add their `.info` files alongside the others:

```bash
    cat > "$MOCK_REPO/development/ghpkg/ghpkg.info" << 'EOF'
PRGNAM="ghpkg"
VERSION="1.0.0"
HOMEPAGE="https://github.com/someowner/ghpkg"
DOWNLOAD="https://github.com/someowner/ghpkg/archive/v1.0.0/ghpkg-1.0.0.tar.gz"
MD5SUM="11111111111111111111111111111111"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
REQUIRES=""
MAINTAINER="Test"
EMAIL="test@test.com"
EOF

    cat > "$MOCK_REPO/python/pypkg/pypkg.info" << 'EOF'
PRGNAM="pypkg"
VERSION="2.0.0"
HOMEPAGE="https://pypi.org/project/pypkg/"
DOWNLOAD="https://files.pythonhosted.org/packages/source/p/pypkg/pypkg-2.0.0.tar.gz"
MD5SUM="22222222222222222222222222222222"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
REQUIRES=""
MAINTAINER="Test"
EMAIL="test@test.com"
EOF
```

Also add `"$MOCK_REPO/python/pypkg"` and `"$MOCK_REPO/development/ghpkg"` into the `mkdir -p` argument list at the top of `setup()`.

- [ ] **Step 2: Add T16–T19 (Feature 1 — section writing)**

Insert after T15 (after line 334), before `teardown`:

```bash
# ── T16: --new github .info → github source section ───────────────────────────
echo ""
echo "T16: --new github .info → [pkg] source=github appended"
run_mkhint -n ghpkg
assert_contains "github section header"  "$MOCK_BASE/nvchecker.toml" '\[ghpkg\]'
assert_contains "github source"          "$MOCK_BASE/nvchecker.toml" 'source = "github"'
assert_contains "github owner/repo"      "$MOCK_BASE/nvchecker.toml" 'github = "someowner/ghpkg"'

# ── T17: --new pypi .info → pypi source section ───────────────────────────────
echo ""
echo "T17: --new pypi .info → [pkg] source=pypi appended"
run_mkhint -n pypkg
assert_contains "pypi section header"     "$MOCK_BASE/nvchecker.toml" '\[pypkg\]'
assert_contains "pypi source"             "$MOCK_BASE/nvchecker.toml" 'source = "pypi"'
assert_contains "pypi name"               "$MOCK_BASE/nvchecker.toml" 'pypi = "pypkg"'

# ── T18: --new unrecognised URL → commented stub ──────────────────────────────
echo ""
echo "T18: --new unknown source → commented stub appended"
run_mkhint -n clion
assert_contains "clion section header"    "$MOCK_BASE/nvchecker.toml" '\[clion\]'
assert_contains "stub TODO"               "$MOCK_BASE/nvchecker.toml" 'TODO: configure nvchecker source'

# ── T19: --new when [pkg] already present → no duplicate ───────────────────────
echo ""
echo "T19: --new when section exists → not duplicated"
run_mkhint -n ghpkg  # ghpkg section already added in T16
dup_count=$(grep -c '^\[ghpkg\]' "$MOCK_BASE/nvchecker.toml")
assert_exit_code "ghpkg section appears once" 1 "$dup_count"
```

Note on T18: `clion`'s DOWNLOAD is `UNSUPPORTED` and DOWNLOAD_x86_64 is a jetbrains URL (not github/pypi), and HOMEPAGE is jetbrains.com — so it falls through to the stub branch. Good coverage.

Note on T19: `assert_exit_code` compares integers; we reuse it to assert `dup_count == 1`.

- [ ] **Step 3: Add T20–T22 (Feature 2 — suggest version)**

```bash
# ── T20: --hintfile no -v, accept suggestion → VERSION=latest, nvtake called ───
echo ""
echo "T20: --hintfile no -v, accept suggestion"
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
rm -f "$MOCK_BASE/nvtake.log"
# new_ver.json says curl latest = 8.9.0; press Enter to accept
echo "" | run_mkhint -f curl < <(printf '\nn\n')
assert_contains "VERSION set to latest"   "$MOCK_HINT/curl.hint" 'VERSION="8.9.0"'
assert_contains "URL has latest version"  "$MOCK_HINT/curl.hint" 'curl-8.9.0'
assert_file_exists "nvtake was called"    "$MOCK_BASE/nvtake.log"
```

Note on stdin: `suggest_version` reads one line (accept), then `prompt_slackrepo` reads one line (we answer `n` to avoid invoking real slackrepo). `< <(printf '\nn\n')` supplies both: blank = accept latest, `n` = skip slackrepo. Remove the leading `echo "" |` — the process substitution provides stdin. Corrected command:

```bash
run_mkhint -f curl < <(printf '\nn\n')
```

- [ ] **Step 4: T21 — type an override version**

```bash
# ── T21: --hintfile no -v, type override version ──────────────────────────────
echo ""
echo "T21: --hintfile no -v, type override version"
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
# type "8.8.8" at suggest prompt, then "n" at slackrepo prompt
run_mkhint -f curl < <(printf '8.8.8\nn\n')
assert_contains "VERSION = typed value"   "$MOCK_HINT/curl.hint" 'VERSION="8.8.8"'
assert_contains "URL has typed version"   "$MOCK_HINT/curl.hint" 'curl-8.8.8'
```

- [ ] **Step 5: T22 — no section / no nvchecker result → error**

```bash
# ── T22: --hintfile no -v, no nvchecker result → error exit 2 ─────────────────
echo ""
echo "T22: --hintfile no -v, package absent from keyfile → error"
cat > "$MOCK_HINT/protoc-gen-go-grpc.hint" << 'EOF'
VERSION="1.3.0"
ARCH="x86_64"
DOWNLOAD="https://example.com/x-1.3.0.tar.gz"
MD5SUM="33333333333333333333333333333333"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
set +e
run_mkhint -f protoc-gen-go-grpc < <(printf '\n') >/dev/null 2>&1
code=$?
set -e
# suggest_version returns 1 → dispatch prints "Aborted." and exits 0,
# BUT no-result path prints error to stderr first; exit is 0 (graceful abort).
assert_exit_code "graceful abort on no result" 0 "$code"
assert_contains  "hint version unchanged"      "$MOCK_HINT/protoc-gen-go-grpc.hint" 'VERSION="1.3.0"'
```

Note: per the dispatch in Task 6 Step 3, `suggest_version` failure → `{ echo "Aborted." >&2; exit 0; }`. So exit code is 0 and the hint is untouched. The test asserts exactly that.

- [ ] **Step 6: T23–T25 (Feature 3 — bulk)**

```bash
# ── T23: --check one outdated, confirm → updated + nvtake + slackrepo prompt ───
echo ""
echo "T23: --check single outdated package, confirm update"
# fresh keyfile: only curl, latest 8.9.0
cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": { "curl": { "version": "8.9.0" } } }
EOF
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
# remove other hints so only curl is scanned
rm -f "$MOCK_HINT/clion.hint" "$MOCK_HINT/protoc-gen-go-grpc.hint" "$MOCK_HINT"/*.bak 2>/dev/null
rm -f "$MOCK_BASE/nvtake.log"
# answer: Y to update curl, n to slackrepo
run_mkhint -C curl < <(printf 'Y\nn\n')
assert_contains "curl updated to 8.9.0"   "$MOCK_HINT/curl.hint" 'VERSION="8.9.0"'
assert_file_exists "nvtake called"        "$MOCK_BASE/nvtake.log"

# ── T24: --check all current → 'all up to date', no slackrepo ──────────────────
echo ""
echo "T24: --check when everything current"
# curl.hint is now 8.9.0, keyfile latest is 8.9.0 → up to date
out=$(run_mkhint -C curl < <(printf '\n') 2>&1)
echo "$out" | grep -q "all up to date" \
    && { echo "  PASS: reports all up to date"; (( PASS++ )); } \
    || { echo "  FAIL: did not report all up to date"; (( FAIL++ )); ERRORS+=("T24 up to date"); }

# ── T25: --check mixed, decline one accept one ────────────────────────────────
echo ""
echo "T25: --check two outdated, decline first accept second"
cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": { "curl": { "version": "9.0.0" }, "clion": { "version": "2025.5" } } }
EOF
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.9.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.9.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
cat > "$MOCK_HINT/clion.hint" << 'EOF'
VERSION="2025.4"
ARCH="x86_64"
DOWNLOAD="UNSUPPORTED"
MD5SUM=""
DOWNLOAD_x86_64="https://download.jetbrains.com/cpp/CLion-2025.4.tar.gz"
MD5SUM_x86_64="dff91fe793b8d3ee2446dd340288eef5"
EOF
# report order is filesystem glob order; answer per-package prompts:
# decline curl (n), accept clion (Y), then n to slackrepo.
# To make order deterministic, target explicitly: curl then clion.
run_mkhint -C curl clion < <(printf 'n\nY\nn\n')
assert_contains     "curl declined (unchanged)"  "$MOCK_HINT/curl.hint"  'VERSION="8.9.0"'
assert_contains     "clion accepted (updated)"   "$MOCK_HINT/clion.hint" 'VERSION="2025.5"'
```

Note on T25: passing `-C curl clion` makes the target list explicit and ordered, so the two `read` answers (`n` then `Y`) map to curl then clion deterministically. The trailing `n` answers the single slackrepo prompt (clion was updated).

- [ ] **Step 7: T26 — mutual exclusion**

```bash
# ── T26: --check with -v → mutually-exclusive error exit 1 ─────────────────────
echo ""
echo "T26: --check combined with -v → exit 1"
set +e
run_mkhint -C -v 1.0 2>/dev/null
code=$?
set -e
assert_exit_code "check + -v exits 1" 1 "$code"
```

- [ ] **Step 8: Run the full suite**

Run: `bash tests/mkhint_test.sh`
Expected: all tests PASS, including T16–T26; final line `Results: N passed, 0 failed`.

If any fail, debug with superpowers:systematic-debugging before proceeding.

- [ ] **Step 9: Commit**

```bash
git add tests/mkhint_test.sh
git commit -m "test: add T16-T26 covering nvchecker section, suggest, and bulk check"
```

---

## Task 10: Update bash completion

**Files:**
- Modify: `mkhint.bash-completion`

- [ ] **Step 1: Read the current completion script**

Run: `cat mkhint.bash-completion`
Identify the `all_flags` line (around line 11) and the package-name completion logic used for `--hintfile`/`--delete`.

- [ ] **Step 2: Add the new flag**

In the `all_flags` string, add `--check -C`. For example change:

```bash
local all_flags="--version -v --hintfile -f --new -n --list -l --clean -c --delete -d --no-dl -N --help -h"
```

to:

```bash
local all_flags="--version -v --hintfile -f --new -n --list -l --clean -c --check -C --delete -d --no-dl -N --help -h"
```

- [ ] **Step 3: Complete package names after --check**

Find where the script completes hint-file/package names for `--delete` (or `--hintfile`). Add `--check` / `-C` to the same condition so that after `--check` the completion offers existing `.hint` package names (the same candidate set used for `--delete`). Mirror the existing pattern exactly — do not invent a new mechanism. If the current code is a `case "$prev" in` with `--delete|-d|--hintfile|-f)`, extend it to `--delete|-d|--hintfile|-f|--check|-C)`.

- [ ] **Step 4: Smoke test the completion sources cleanly**

Run: `bash -n mkhint.bash-completion`
Expected: no output, exit 0.

- [ ] **Step 5: Commit**

```bash
git add mkhint.bash-completion
git commit -m "feat(completion): add --check/-C flag and package-name completion"
```

---

## Task 11: Update README and CLAUDE.md

**Files:**
- Modify: `README.md`, `CLAUDE.md`

- [ ] **Step 1: Document in README**

Read `README.md`, then add:
- A **Dependencies** note: nvchecker (provides `nvchecker` + `nvtake`) and `jq` are required for the version-checking features; `wget` for downloads.
- A section describing the three features with example invocations:

```bash
mkhint --new mypackage                 # also writes an nvchecker [section]
mkhint --hintfile mypackage            # suggests latest version via nvchecker
mkhint --check                         # check all hints for updates
mkhint --check pkg1 pkg2               # check specific packages
```

- A note that the nvchecker config lives at `~/.config/nvchecker/nvchecker.toml` and the user must set up the `[__config__]` section (oldver/newver keyfiles) once.

- [ ] **Step 2: Update CLAUDE.md**

In `CLAUDE.md`:
- Add `NVCHECKER_CONFIG` to the Configuration section.
- Add the three features under "Key Behaviors".
- Add `--check`/`-C` to the running/testing examples.
- Add T16–T26 to the test-coverage table.
- Update exit-code 4 description to "required tool not available (wget/nvchecker/nvtake/jq)".

- [ ] **Step 3: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "docs: document nvchecker integration and --check command"
```

---

## Task 12: Final verification

- [ ] **Step 1: Full syntax check**

Run: `bash -n mkhint && bash -n mkhint.bash-completion && bash -n tests/mkhint_test.sh`
Expected: no output, exit 0 for all three.

- [ ] **Step 2: Full test suite**

Run: `bash tests/mkhint_test.sh`
Expected: `Results: N passed, 0 failed`.

- [ ] **Step 3: Manual smoke (help + bad combos)**

Run: `bash mkhint --help; echo "---"; bash mkhint -C -v 1.0; echo "exit=$?"`
Expected: help prints; second command prints the mutual-exclusion error and `exit=1`.

- [ ] **Step 4: Confirm no stray debug or leftover TODO in shipped code**

Run: `grep -n "TODO\|XXX\|DEBUG" mkhint`
Expected: only the intentional stub-template `# TODO: configure nvchecker source` string inside `add_nvchecker_section`. Nothing else.

- [ ] **Step 5: Verify the work meets the spec**

Use superpowers:requesting-code-review (or self-review) against the spec at
`docs/superpowers/specs/2026-06-13-nvchecker-integration-design.md`. Confirm all three features and all spec test cases are present and passing.

---

## Self-Review notes (author)

- **Spec coverage:** Feature 1 → Tasks 4,5 (+T16-T19). Feature 2 → Task 6 (+T20-T22). Feature 3 → Task 7 (+T23-T25, mutual-exclusion T26). Deps/`check_nvchecker` → Task 2. Config constant + help/exit codes → Task 1. Keyfile read + `sort -V` → Tasks 3,7. nvtake-after-update → Tasks 6,7. Completion → Task 10. Docs → Task 11.
- **`-c` clash:** resolved by using `-C` for `--check`; `-c` stays `--clean`. Captured in Task 7 Step 2.
- **set -e safety:** every fallible helper call is guarded (`|| true`, `|| { ... }`, or `if`). Noted inline.
- **stdout hygiene:** `suggest_version` sends prompt + nvchecker noise to stderr so command substitution captures only the version. Noted in Task 6 Step 1.
- **Type/name consistency:** `nvchecker_latest`, `suggest_version`, `add_nvchecker_section`, `check_nvchecker`, `check_updates`, `NVCHECKER_CONFIG` used identically across tasks. Keyfile JSON shape (`.data[pkg].version`) consistent between Task 3 reader and Task 8 mock.
