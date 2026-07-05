# Config file + slackrepo update-vs-build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `mkhint --check`/`--hintfile` run `slackrepo build` for packages not yet in the repo and `update` for existing ones, and move path constants into a sourced `~/.config/mkhint/config` file (shared by mkhint and its completion script).

**Architecture:** A `pkg_in_repo` helper globs `PACKAGES_DIR/*/<pkg>/<pkg>-*.txz` to decide build-vs-update. A single `run_slackrepo <action> <pkgs...>` helper owns the confirm prompt and empty-list guard; both call sites partition updated packages by presence. Config is a plain bash file sourced after baked-in defaults, so an absent file reproduces current behavior byte-for-byte.

**Tech Stack:** Bash (single-file tool), bash-completion, existing hand-rolled test harness in `tests/mkhint_test.sh` (mock dirs + PATH-stubbed external commands).

---

## File Structure

- `mkhint` — add `PACKAGES_DIR` default + config-source block near lines 19–27; add `pkg_in_repo` and `run_slackrepo` helpers; rewrite `prompt_slackrepo`; rewrite the `--check` slackrepo prompt block (~998).
- `mkhint.bash-completion` — replace hardcoded `repo_dir`/`hint_dir` (lines 8–9) with default-then-source block.
- `tests/mkhint_test.sh` — add a `slackrepo` stub, a `PACKAGES_DIR` mock, patch `run_mkhint` sed to rewrite `PACKAGES_DIR=` and `MKHINT_CONFIG=`, add new test cases (T68 onward).
- `CLAUDE.md`, `README.md`, `CHANGELOG.md` — docs.

The whole feature is one cohesive change to one script + its completion + tests; no decomposition into sub-plans needed.

---

## Task 1: Test harness support for slackrepo + PACKAGES_DIR

**Files:**
- Modify: `tests/mkhint_test.sh` (near `MOCK_REPO`/`MOCK_HINT` defs ~line 5–7; `run_mkhint` sed ~179–185; mock setup ~193–238)

- [ ] **Step 1: Add mock path vars**

Near the top where `MOCK_REPO`/`MOCK_HINT` are defined (after line 7), add:

```bash
MOCK_PKGS="$MOCK_BASE/packages"
```

- [ ] **Step 2: Patch run_mkhint sed to rewrite the two new vars**

In `run_mkhint` (the `sed` invocation ~179–185), add two `-e` clauses so the mock
config path and packages dir are used:

```bash
        -e "s|PHANTOM_DEPS_FILE=\".*\"|PHANTOM_DEPS_FILE=\"$MOCK_BASE/phantom-deps\"|" \
        -e "s|PACKAGES_DIR=\".*\"|PACKAGES_DIR=\"$MOCK_PKGS\"|" \
        -e "s|MKHINT_CONFIG=\".*\"|MKHINT_CONFIG=\"$MOCK_BASE/config\"|" \
        "$SCRIPT" > "$tmp_script"
```

(The `MKHINT_CONFIG` rewrite points the source at a mock path that normally does
not exist, so sourcing is a no-op unless a test creates `$MOCK_BASE/config`.)

- [ ] **Step 3: Add a slackrepo stub and helper to seed built packages**

After `mock_nvchecker_tools` (~line 238), add:

```bash
# Stub slackrepo: log "<action> <args...>" to $MOCK_BASE/slackrepo.log
mock_slackrepo() {
    mkdir -p "$MOCK_BASE/bin"
    cat > "$MOCK_BASE/bin/slackrepo" << 'EOF'
#!/bin/bash
echo "$*" >> "$SLACKREPO_LOG"
exit 0
EOF
    chmod +x "$MOCK_BASE/bin/slackrepo"
    export SLACKREPO_LOG="$MOCK_BASE/slackrepo.log"
}

# Create a fake built package: $1=category $2=pkgname $3=version
seed_pkg() {
    local cat="$1" pkg="$2" ver="$3"
    mkdir -p "$MOCK_PKGS/$cat/$pkg"
    : > "$MOCK_PKGS/$cat/$pkg/${pkg}-${ver}-x86_64-1_danix.txz"
}
```

- [ ] **Step 4: Call mock_slackrepo in setup**

Where `mock_wget` and `mock_nvchecker_tools` are called (~310–311), add:

```bash
mock_slackrepo
```

- [ ] **Step 5: Run the suite to confirm nothing broke**

Run: `bash tests/mkhint_test.sh`
Expected: same pass count as before (140), no new failures. The stub is inert
until used.

- [ ] **Step 6: Commit**

```bash
git add tests/mkhint_test.sh
git commit -S -m "test: harness support for slackrepo stub and PACKAGES_DIR"
```

---

## Task 2: `pkg_in_repo` + `run_slackrepo` helpers and build-vs-update wiring

**Files:**
- Modify: `mkhint` (config block ~19–27; `prompt_slackrepo` ~824–832; `--check` prompt block ~998–1006; new helpers)
- Test: `tests/mkhint_test.sh`

- [ ] **Step 1: Write failing tests (T68–T71)**

Append after the last test in `tests/mkhint_test.sh` (before the final summary
print). These cover `--check` build-vs-update and the `--hintfile` single path.
Uses the existing pattern: seed a hint, mock an nvchecker result, feed answers on
stdin, assert the slackrepo log.

```bash
# ── T68: --check updated pkg already built → slackrepo UPDATE ─────────────────
echo ""
echo "T68: --check, package present in repo, offered 'update'"
rm -f "$SLACKREPO_LOG" "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
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
seed_pkg network curl 8.5.0
# answers: Y accept update, Y confirm slackrepo
run_mkhint -C curl < <(printf 'Y\nY\n')
assert_contains "slackrepo update called" "$SLACKREPO_LOG" '^update curl$'
assert_not_contains "no build called"     "$SLACKREPO_LOG" 'build'

# ── T69: --check updated pkg NOT built → slackrepo BUILD ──────────────────────
echo ""
echo "T69: --check, package absent from repo, offered 'build'"
rm -f "$SLACKREPO_LOG" "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
rm -rf "$MOCK_PKGS"
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
run_mkhint -C curl < <(printf 'Y\nY\n')
assert_contains "slackrepo build called" "$SLACKREPO_LOG" '^build curl$'
assert_not_contains "no update called"   "$SLACKREPO_LOG" 'update'

# ── T70: --check mixed → update for built, build for new ──────────────────────
echo ""
echo "T70: --check, one built + one new, both offered"
rm -f "$SLACKREPO_LOG" "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
rm -rf "$MOCK_PKGS"
cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": { "curl": { "version": "8.9.0" }, "wget": { "version": "1.25.0" } } }
EOF
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
cat > "$MOCK_HINT/wget.hint" << 'EOF'
VERSION="1.21.0"
ARCH="x86_64"
DOWNLOAD="https://ftp.gnu.org/gnu/wget/wget-1.21.0.tar.gz"
MD5SUM="beefbeefbeefbeefbeefbeefbeefbeef"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
seed_pkg network curl 8.5.0
# curl built, wget not. answers: Y update curl, Y update wget,
#   Y confirm slackrepo update, Y confirm slackrepo build
run_mkhint -C curl wget < <(printf 'Y\nY\nY\nY\n')
assert_contains "update for built curl" "$SLACKREPO_LOG" '^update curl$'
assert_contains "build for new wget"    "$SLACKREPO_LOG" '^build wget$'

# ── T71: --hintfile no -V, pkg built → update; not built → build ──────────────
echo ""
echo "T71: --hintfile single, build-vs-update by presence"
rm -f "$SLACKREPO_LOG" "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
rm -rf "$MOCK_PKGS"
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
# not built → build. answers: (accept suggested version) blank, Y confirm slackrepo
run_mkhint -f curl < <(printf '\nY\n')
assert_contains "hintfile new pkg → build" "$SLACKREPO_LOG" '^build curl$'
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E "T6[89]|T7[01]|FAIL"`
Expected: FAIL — `slackrepo` is still called as `update` unconditionally
(T69/T71 fail: `build` never logged; T70 fails: no `build wget`).

- [ ] **Step 3: Add `PACKAGES_DIR` default + config source block**

In `mkhint`, in the default-configuration block (after `PHANTOM_DEPS_FILE`, line
27), add:

```bash
# Built-package repository (slackrepo output tree: <cat>/<pkg>/<pkg>-*.txz).
PACKAGES_DIR="/repo/"

# ponytail: sourced config, defaults above win when file absent. A syntax-broken
# config aborts under `set -e` — acceptable for a single-user tool.
MKHINT_CONFIG="$HOME/.config/mkhint/config"
[[ -f "$MKHINT_CONFIG" ]] && source "$MKHINT_CONFIG"
```

Also add the `PACKAGES_DIR` comment inline on its default; keep `REPO_DIR`/
`HINT_DIR` where they are (the config file may override them, sourcing handles it).

- [ ] **Step 4: Add `pkg_in_repo` and `run_slackrepo` helpers**

Replace the existing `prompt_slackrepo` function (lines 823–832) with the two new
helpers plus a rewritten `prompt_slackrepo`:

```bash
# True if a built package (.txz) for <pkg> exists in the repo.
pkg_in_repo() {
    local pkg="$1"
    compgen -G "${PACKAGES_DIR%/}/*/${pkg}/${pkg}-*.txz" >/dev/null 2>&1
}

# Prompt to run `slackrepo <action> <pkgs...>`; no-op on empty list.
run_slackrepo() {
    local action="$1"; shift
    [[ $# -eq 0 ]] && return 0
    local answer
    read -r -p "Run 'slackrepo $action $*'? [Y/n] " answer
    answer="${answer:-Y}"
    [[ "$answer" =~ ^[Yy]$ ]] && slackrepo "$action" "$@"
}

# Single-package dispatch: update if already built, else build.
prompt_slackrepo() {
    local pkg="$1"
    if pkg_in_repo "$pkg"; then
        run_slackrepo update "$pkg"
    else
        run_slackrepo build "$pkg"
    fi
}
```

- [ ] **Step 5: Rewrite the `--check` slackrepo prompt block**

Replace the "Single slackrepo prompt for everything updated" block (lines
998–1006) with a partition + two calls:

```bash
    # Split updated packages: existing → update, new → build.
    if [[ ${#updated[@]} -gt 0 ]]; then
        local -a existing=() fresh=()
        local up
        for up in "${updated[@]}"; do
            if pkg_in_repo "$up"; then existing+=("$up"); else fresh+=("$up"); fi
        done
        run_slackrepo update "${existing[@]}"
        run_slackrepo build  "${fresh[@]}"
    fi
```

- [ ] **Step 6: Run the new tests to verify they pass**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E "T6[89]|T7[01]|FAIL"`
Expected: T68–T71 PASS, no FAIL lines.

- [ ] **Step 7: Run the full suite**

Run: `bash tests/mkhint_test.sh`
Expected: all pass (144 now). Also `bash -n mkhint` clean.

- [ ] **Step 8: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: slackrepo build for new packages, update for existing"
```

---

## Task 3: Config-override test + PACKAGES_DIR default assertion

**Files:**
- Test: `tests/mkhint_test.sh`

- [ ] **Step 1: Write failing test (T72)**

Append after T71. Writes a mock config that redirects `PACKAGES_DIR` to a second
tree, seeds a package only there, and confirms `pkg_in_repo` follows the override
(package seen as built → `update`).

```bash
# ── T72: config file overrides PACKAGES_DIR ──────────────────────────────────
echo ""
echo "T72: ~/.config/mkhint/config overrides PACKAGES_DIR"
rm -f "$SLACKREPO_LOG" "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
rm -rf "$MOCK_PKGS" "$MOCK_BASE/altpkgs"
mkdir -p "$MOCK_BASE/altpkgs/network/curl"
: > "$MOCK_BASE/altpkgs/network/curl/curl-8.5.0-x86_64-1_danix.txz"
cat > "$MOCK_BASE/config" << EOF
PACKAGES_DIR="$MOCK_BASE/altpkgs"
EOF
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
# curl present only in override tree → update expected
run_mkhint -C curl < <(printf 'Y\nY\n')
assert_contains "override tree → update" "$SLACKREPO_LOG" '^update curl$'
rm -f "$MOCK_BASE/config"
```

- [ ] **Step 2: Run T72 to verify it passes**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E "T72|FAIL"`
Expected: T72 PASS. (Config sourcing already implemented in Task 2, so this
verifies the override path end-to-end.)

Note the trailing `rm -f "$MOCK_BASE/config"` so later reruns/tests are not
affected by the leftover config.

- [ ] **Step 3: Commit**

```bash
git add tests/mkhint_test.sh
git commit -S -m "test: config file overrides PACKAGES_DIR"
```

---

## Task 4: Completion script sources the config

**Files:**
- Modify: `mkhint.bash-completion:4-9`

- [ ] **Step 1: Replace hardcoded paths with default-then-source block**

Change the top of `_mkhintfile_completions` (lines 5–9). The current:

```bash
    local cur prev repo_dir hint_dir
    _init_completion || return

    repo_dir="/var/lib/sbopkg/SBo-danix"
    hint_dir="/etc/slackrepo/SBo-danix/hintfiles"
```

becomes:

```bash
    local cur prev repo_dir hint_dir mkhint_config
    _init_completion || return

    repo_dir="/var/lib/sbopkg/SBo-danix"
    hint_dir="/etc/slackrepo/SBo-danix/hintfiles"
    mkhint_config="$HOME/.config/mkhint/config"
    # shellcheck disable=SC1090
    [[ -f "$mkhint_config" ]] && source "$mkhint_config"
    repo_dir="${REPO_DIR:-$repo_dir}"
    hint_dir="${HINT_DIR:-$hint_dir}"
    repo_dir="${repo_dir%/}"; hint_dir="${hint_dir%/}"
```

- [ ] **Step 2: Syntax check**

Run: `bash -n mkhint.bash-completion`
Expected: no output (clean).

- [ ] **Step 3: Behavior check (defaults still work with no config)**

Run:
```bash
env -i HOME="$HOME" bash -c 'source mkhint.bash-completion 2>/dev/null; \
  echo ok' 2>&1 | tail -1
```
Expected: `ok` (sourcing the file defines the function without error; the
`_init_completion` guard only runs when invoked as a completion).

- [ ] **Step 4: Commit**

```bash
git add mkhint.bash-completion
git commit -S -m "feat: completion sources ~/.config/mkhint/config"
```

---

## Task 5: Docs + CHANGELOG

**Files:**
- Modify: `CLAUDE.md`, `README.md`, `CHANGELOG.md`

- [ ] **Step 1: Update CLAUDE.md**

In the Configuration section, add a paragraph documenting the config file:

```markdown
All path constants have baked-in defaults and can be overridden by a sourced
config file at `$HOME/.config/mkhint/config` (plain bash `KEY="value"` lines).
Overridable: `REPO_DIR`, `HINT_DIR`, `PACKAGES_DIR` (built-package tree, default
`/repo/`), `NVCHECKER_CONFIG`, `PHANTOM_DEPS_FILE`, `TMP_DIR`. Missing file =
defaults. The bash completion script sources the same file, so the two no longer
drift.
```

In Key Behaviors, amend the `--check` and `--hintfile` bullets to note:
`slackrepo build` is used for packages with no built `.txz` under `PACKAGES_DIR`
(`pkg_in_repo` glob `PACKAGES_DIR/*/<pkg>/<pkg>-*.txz`), `update` otherwise;
`--check` partitions its updated set and prompts `update` then `build` separately.

Remove the now-stale line claiming the completion script keeps hardcoded copies
of REPO_DIR/HINT_DIR "keep in sync when changing defaults" — replace with a note
that both source the config file.

- [ ] **Step 2: Update README.md**

Add a short "Configuration" note (if not present) describing the config file and
`PACKAGES_DIR`, mirroring the CLAUDE.md wording in user-facing terms. Note the
build-vs-update behavior under the `--check` usage description.

- [ ] **Step 3: Update CHANGELOG.md**

Under a new `## [Unreleased]` (or next minor version) `### Added` / `### Changed`:

```markdown
### Added
- Sourced config file `~/.config/mkhint/config` for all path constants
  (`REPO_DIR`, `HINT_DIR`, new `PACKAGES_DIR`, etc.); completion script sources
  it too. Missing file keeps previous defaults.

### Changed
- `--check` and `--hintfile` now run `slackrepo build` for packages not yet
  built in `PACKAGES_DIR` and `slackrepo update` for existing ones, instead of
  always `update`.
```

- [ ] **Step 4: Verify docs reference nothing undefined**

Run: `grep -n "PACKAGES_DIR" mkhint CLAUDE.md README.md CHANGELOG.md`
Expected: appears in all four, consistent default `/repo/`.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md README.md CHANGELOG.md
git commit -S -m "docs: config file and slackrepo build-vs-update"
```

---

## Task 6: Full verification + deploy to VM

**Files:** none (verification only)

- [ ] **Step 1: Full test suite + syntax**

Run:
```bash
bash tests/mkhint_test.sh && bash -n mkhint && bash -n mkhint.bash-completion
```
Expected: all tests pass (145 total), no syntax errors.

- [ ] **Step 2: Confirm signed, clean commits**

Run: `git log --format='%h %G? %s' -6`
Expected: all `G` (GPG-signed).

- [ ] **Step 3: Push both remotes**

Run: `git push`
Expected: pushes to danix_git and slackware_forge via origin's two push URLs.

- [ ] **Step 4: Deploy to VM (confirm with user first — outward-facing)**

Inspect the live target, then copy:
```bash
scp mkhint buildsystem:/usr/local/bin/mkhint
scp mkhint.bash-completion buildsystem:/etc/bash_completion.d/mkhint
ssh buildsystem 'md5sum /usr/local/bin/mkhint'  # compare to local md5sum mkhint
```
Expected: md5 matches local.

- [ ] **Step 5: Live smoke test on VM**

Run: `ssh buildsystem 'mkhint -C somepkg'` on a package known absent from the repo
and confirm it offers `slackrepo build`, and one present offers `update`. Verify
`~/.config/mkhint/config` (root's `/root/.config/mkhint/config`) either absent
(defaults `/repo/`) or set correctly.

---

## Self-Review

**Spec coverage:**
- Config file, defaults baked in, sourced → Task 2 Step 3. ✓
- Completion sources config → Task 4. ✓
- `PACKAGES_DIR` new var, default `/repo/` → Task 2 Step 3. ✓
- `pkg_in_repo` via `.txz` glob → Task 2 Step 4. ✓
- `run_slackrepo` shared helper + empty guard → Task 2 Step 4. ✓
- `--check` partition update/build → Task 2 Step 5, tests T68–T70. ✓
- `--hintfile` single dispatch → Task 2 Step 4 (`prompt_slackrepo`), test T71. ✓
- Config override test → Task 3 (T72). ✓
- Docs (CLAUDE.md/README/CHANGELOG), feat/minor → Task 5. ✓
- Non-goals (no parser, no new dep) respected. ✓

**Placeholder scan:** No TBD/TODO; all code shown; test bodies complete.

**Type/name consistency:** `pkg_in_repo`, `run_slackrepo`, `prompt_slackrepo`,
`PACKAGES_DIR`, `MKHINT_CONFIG`, `MOCK_PKGS`, `seed_pkg`, `mock_slackrepo`,
`SLACKREPO_LOG` used consistently across tasks.
