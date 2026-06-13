# `--check` Populate Missing Sections Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `mkhint --check` offer to populate `nvchecker.toml` for hint files that have no `[pkg]` section, instead of silently skipping them.

**Architecture:** Add a small `_has_nvchecker_section` helper (DRY the existing section-presence grep), refactor `add_nvchecker_section` to use it, then extend `check_updates` to collect missing-section packages during its classify loop and, after the loop, batch-prompt to append sections via the existing `add_nvchecker_section` autodetect. On accept, the run stops with a "review and re-run" message.

**Tech Stack:** bash, grep, find, sort -V. Tests use the existing mock-based suite (`tests/mkhint_test.sh`).

---

## Background for the implementer

Read before starting:

- **Spec:** `docs/superpowers/specs/2026-06-13-check-populate-missing-sections-design.md` — this plan implements it exactly.
- **Main script:** `mkhint`. Relevant anchors (current line numbers):
  - `add_nvchecker_section()` starts at line 266. Its duplicate-guard grep is line 275:
    ```bash
    if grep -qE "^\[${pkg}\][[:space:]]*$" "$NVCHECKER_CONFIG"; then
    ```
  - `check_updates()` starts at line 606. The classify loop is lines 633-648. The "no result" skip is line 638:
    ```bash
    latest=$(nvchecker_latest "$pkg") || { echo "skip ${pkg}: no nvchecker source"; continue; }
    ```
    The "nothing outdated" check is lines 650-653.
  - `list_hint_files()` (earlier in the file) locates a package's `.info` with:
    ```bash
    find "$REPO_DIR" -mindepth 2 -name "${pkg}.info" 2>/dev/null | head -1
    ```
    Reuse this exact pattern.
- **`set -e`** is active. Command substitutions and `read` are safe; `add_nvchecker_section` returns 0. No new unguarded fallible calls are introduced.
- **Test harness:** `tests/mkhint_test.sh`.
  - `run_mkhint` sed-patches `REPO_DIR`/`HINT_DIR`/`TMP_DIR`/`NVCHECKER_CONFIG` to mock paths.
  - `setup()` creates fixtures including `ghpkg` (github `.info` under `$MOCK_REPO/development/ghpkg/ghpkg.info`) and a base `$MOCK_BASE/nvchecker.toml` containing only `[__config__]`, plus `$MOCK_BASE/new_ver.json` seeded with curl + clion versions.
  - Interactive prompts are fed via `< <(printf '...')`.
  - Assertions: `assert_contains`, `assert_not_contains`, `assert_file_exists`, `assert_file_not_exists`, `assert_exit_code`. Output-substring checks use the inline `grep -q` + `(( PASS++ ))` pattern (see T24/T27 in the file).
  - The current suite has 69 passing assertions (T1–T28).

## File Structure

- `mkhint` — `_has_nvchecker_section` helper; `add_nvchecker_section` refactor; `check_updates` missing-section collection + populate prompt.
- `tests/mkhint_test.sh` — T29–T31, plus one orphan fixture for T31.
- `CLAUDE.md` / `README.md` — document the populate prompt.

Single-file tool; keep everything in `mkhint`.

---

## Task 1: Add `_has_nvchecker_section` helper and refactor `add_nvchecker_section`

Pure refactor — no behaviour change. Establishes the helper that Task 2 reuses.

**Files:**
- Modify: `mkhint` (add helper just above `add_nvchecker_section` at line 266; change line 275-278)

- [ ] **Step 1: Add the helper above `add_nvchecker_section`**

Immediately before the `# Append an nvchecker [pkg] section...` comment (line 264), add:

```bash
# Return 0 if NVCHECKER_CONFIG already has a [pkg] section
_has_nvchecker_section() {
    local pkg="$1"
    [[ -f "$NVCHECKER_CONFIG" ]] || return 1
    grep -qE "^\[${pkg}\][[:space:]]*$" "$NVCHECKER_CONFIG"
}
```

- [ ] **Step 2: Use the helper inside `add_nvchecker_section`**

Replace the duplicate-guard block (currently lines 274-278):

```bash
    # Skip if section already present
    if grep -qE "^\[${pkg}\][[:space:]]*$" "$NVCHECKER_CONFIG"; then
        echo "nvchecker: [${pkg}] already present in $NVCHECKER_CONFIG"
        return 0
    fi
```

with:

```bash
    # Skip if section already present
    if _has_nvchecker_section "$pkg"; then
        echo "nvchecker: [${pkg}] already present in $NVCHECKER_CONFIG"
        return 0
    fi
```

Note: `add_nvchecker_section` still runs `mkdir -p`/`touch` on the config before this check, so `_has_nvchecker_section`'s `[[ -f ]]` guard is belt-and-suspenders here but matters for Task 2's caller (which checks before any touch).

- [ ] **Step 3: Syntax check + full suite (no regressions)**

Run: `bash -n mkhint && bash tests/mkhint_test.sh`
Expected: syntax clean; `Results: 69 passed, 0 failed` (refactor changes nothing observable; T16-T19/T29 not yet added).

- [ ] **Step 4: Commit**

```bash
git add mkhint
git commit -m "refactor: extract _has_nvchecker_section helper"
```

---

## Task 2: Collect missing sections and add the populate prompt in `check_updates`

**Files:**
- Modify: `mkhint` `check_updates` — classify loop (line 638) and after the loop (before line 650)

- [ ] **Step 1: Distinguish missing-section from no-result in the classify loop**

First, declare the `missing_sections` array alongside the other locals. Change line 631:

```bash
    local outdated_pkgs=() outdated_old=() outdated_new=() outdated_flag=()
```

to:

```bash
    local outdated_pkgs=() outdated_old=() outdated_new=() outdated_flag=()
    local missing_sections=()
```

Then replace the no-result skip (line 638):

```bash
        latest=$(nvchecker_latest "$pkg") || { echo "skip ${pkg}: no nvchecker source"; continue; }
```

with:

```bash
        if ! latest=$(nvchecker_latest "$pkg"); then
            if _has_nvchecker_section "$pkg"; then
                echo "skip ${pkg}: no nvchecker result"
            else
                echo "skip ${pkg}: no nvchecker section"
                missing_sections+=("$pkg")
            fi
            continue
        fi
```

(`set -e` note: `latest=$(...)` inside an `if !` is a guarded context — the non-zero return does not abort.)

- [ ] **Step 2: Add the populate prompt after the classify loop**

The classify loop ends at the `done` (line 648). Immediately after that `done`, and before the `if [[ ${#outdated_pkgs[@]} -eq 0 ]]; then` block (line 650), insert:

```bash
    # Offer to populate nvchecker.toml for packages with no section
    if [[ ${#missing_sections[@]} -gt 0 ]]; then
        echo ""
        echo "${#missing_sections[@]} package(s) have no nvchecker section: ${missing_sections[*]}"
        local answer
        read -r -p "Populate ${NVCHECKER_CONFIG} now? [Y/n] " answer
        answer="${answer:-Y}"
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            local mp info
            for mp in "${missing_sections[@]}"; do
                info=$(find "$REPO_DIR" -mindepth 2 -name "${mp}.info" 2>/dev/null | head -1)
                if [[ -z "$info" ]]; then
                    echo "skip ${mp}: no .info found in $REPO_DIR"
                    continue
                fi
                add_nvchecker_section "$mp" "$info"
            done
            echo ""
            echo "Sections added. Review $NVCHECKER_CONFIG (fill any stubs), then re-run 'mkhint -C'."
            return 0
        fi
    fi
```

- [ ] **Step 3: Syntax check + full suite (no regressions)**

Run: `bash -n mkhint && bash tests/mkhint_test.sh`
Expected: syntax clean; `Results: 69 passed, 0 failed`. (Existing `-C` tests T23-T28 all use packages that already have sections or are explicitly named with seeded keyfile entries, so none trigger the new missing-section path. Verify they still pass — if T24's "all up to date" now prints a missing-section prompt instead, investigate: T24 uses `curl` which has a keyfile entry, so it should classify as up-to-date, not missing.)

- [ ] **Step 4: Commit**

```bash
git add mkhint
git commit -m "feat: --check offers to populate missing nvchecker sections"
```

---

## Task 3: Add tests T29–T31

**Files:**
- Modify: `tests/mkhint_test.sh` — orphan fixture in `setup()`; T29-T31 before the SUMMARY section

- [ ] **Step 1: Add an orphan hint fixture path note**

T31 needs a package that has a hint file but NO `.info` anywhere in `MOCK_REPO`. We create the hint file inline in the test (no `.info`), so no `setup()` change is strictly required. No fixture edit needed — proceed to the tests.

- [ ] **Step 2: Add T29 — accept populate, github section written, run stops, hint unchanged**

In `tests/mkhint_test.sh`, find the T28 block (the last test, `assert_contains "scan-all updated curl"`), which is immediately before:

```bash
# ─── SUMMARY ──────────────────────────────────────────────────────────────────
teardown
```

Insert the following three test blocks between the end of T28 and the `# ─── SUMMARY` line:

```bash
# ── T29: --check missing section, accept populate → section added, run stops ───
echo ""
echo "T29: --check missing section, accept populate → github section appended, no update"
# ghpkg has a github .info in MOCK_REPO but no [ghpkg] in toml and not in keyfile.
# Reset toml to only [__config__] so ghpkg is genuinely missing.
cat > "$MOCK_BASE/nvchecker.toml" << EOF
[__config__]
oldver = "$MOCK_BASE/old_ver.json"
newver = "$MOCK_BASE/new_ver.json"
EOF
cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": {} }
EOF
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
cat > "$MOCK_HINT/ghpkg.hint" << 'EOF'
VERSION="1.0.0"
ARCH="x86_64"
DOWNLOAD="https://github.com/someowner/ghpkg/archive/v1.0.0/ghpkg-1.0.0.tar.gz"
MD5SUM="11111111111111111111111111111111"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
out=$(run_mkhint -C ghpkg < <(printf 'Y\n') 2>&1)
assert_contains "ghpkg section appended"     "$MOCK_BASE/nvchecker.toml" '\[ghpkg\]'
assert_contains "github source detected"     "$MOCK_BASE/nvchecker.toml" 'source = "github"'
echo "$out" | grep -q "Review .*re-run" \
    && { echo "  PASS: review/re-run message shown"; (( PASS++ )); } \
    || { echo "  FAIL: review message missing"; echo "$out" | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T29 review msg"); }
assert_contains "ghpkg hint version unchanged" "$MOCK_HINT/ghpkg.hint" 'VERSION="1.0.0"'

# ── T30: --check missing section, decline populate → no section added ──────────
echo ""
echo "T30: --check missing section, decline populate → nothing added"
cat > "$MOCK_BASE/nvchecker.toml" << EOF
[__config__]
oldver = "$MOCK_BASE/old_ver.json"
newver = "$MOCK_BASE/new_ver.json"
EOF
cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": {} }
EOF
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
cat > "$MOCK_HINT/ghpkg.hint" << 'EOF'
VERSION="1.0.0"
ARCH="x86_64"
DOWNLOAD="https://github.com/someowner/ghpkg/archive/v1.0.0/ghpkg-1.0.0.tar.gz"
MD5SUM="11111111111111111111111111111111"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
run_mkhint -C ghpkg < <(printf 'n\n') >/dev/null 2>&1
assert_not_contains "no ghpkg section after decline" "$MOCK_BASE/nvchecker.toml" '\[ghpkg\]'

# ── T31: --check missing section, no .info in repo, accept → skipped, no section
echo ""
echo "T31: --check missing section but no .info → skipped, no section added"
cat > "$MOCK_BASE/nvchecker.toml" << EOF
[__config__]
oldver = "$MOCK_BASE/old_ver.json"
newver = "$MOCK_BASE/new_ver.json"
EOF
cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": {} }
EOF
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
# orphanpkg has NO .info anywhere in MOCK_REPO
cat > "$MOCK_HINT/orphanpkg.hint" << 'EOF'
VERSION="3.0.0"
ARCH="x86_64"
DOWNLOAD="https://example.com/orphanpkg-3.0.0.tar.gz"
MD5SUM="44444444444444444444444444444444"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
out=$(run_mkhint -C orphanpkg < <(printf 'Y\n') 2>&1)
echo "$out" | grep -q "no .info found" \
    && { echo "  PASS: no .info reported"; (( PASS++ )); } \
    || { echo "  FAIL: 'no .info found' not in output"; echo "$out" | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T31 no info"); }
assert_not_contains "no orphanpkg section added" "$MOCK_BASE/nvchecker.toml" '\[orphanpkg\]'
```

- [ ] **Step 3: Run the full suite**

Run: `bash tests/mkhint_test.sh`
Expected: all PASS including T29-T31; `Results: N passed, 0 failed` (N = 75: 69 + 6 new assertions).

If a test fails, debug with superpowers:systematic-debugging. Likely culprits: stdin line count (T29/T31 supply exactly one `Y`/one line — there is no slackrepo prompt because the run returns 0 right after populate), or the `grep -q "Review .*re-run"` pattern not matching the exact message string (the message is `Sections added. Review <path> (fill any stubs), then re-run 'mkhint -C'.`).

- [ ] **Step 4: Commit**

```bash
git add tests/mkhint_test.sh
git commit -m "test: add T29-T31 for --check populate missing sections"
```

---

## Task 4: Document the populate prompt

**Files:**
- Modify: `CLAUDE.md`, `README.md`

- [ ] **Step 1: Update CLAUDE.md**

In the "Key Behaviors" section, find the bullet describing `--check`/`-C`. Append a sentence (or a sub-bullet) stating: when `--check` encounters hint files with no `[pkg]` section in `nvchecker.toml`, it lists them and prompts once to populate the config; on accept it appends sections via `add_nvchecker_section` (github/pypi autodetect, else stub), prints a "review and re-run" message, and stops the run without applying updates. Packages whose `.info` cannot be found in `REPO_DIR` are skipped.

Add a test-coverage table row group:

```
| T29 | `--check` missing section, accept populate — github section appended, run stops, hint unchanged |
| T30 | `--check` missing section, decline populate — nothing added |
| T31 | `--check` missing section, no `.info` in repo — skipped, no section added |
```

- [ ] **Step 2: Update README.md**

In the `--check` documentation section, add a short paragraph: if any scanned hint has no nvchecker source configured, `mkhint --check` offers to populate `nvchecker.toml` for them (auto-detecting github/pypi from the SBo `.info`, otherwise writing a commented stub to fill in). After populating it asks you to review the file and re-run `mkhint -C`.

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: document --check populate-missing-sections prompt"
```

---

## Task 5: Final verification

- [ ] **Step 1: Syntax + full suite**

Run: `bash -n mkhint && bash tests/mkhint_test.sh`
Expected: clean; `Results: 75 passed, 0 failed`.

- [ ] **Step 2: Manual smoke — empty toml, decline**

Run:
```bash
tmpcfg=$(mktemp); printf '[__config__]\noldver="/tmp/o.json"\nnewver="/tmp/n.json"\n' > "$tmpcfg"
echo '{"version":2,"data":{}}' > /tmp/n.json
HOME=$HOME bash -c 'true'  # noop, just confirming environment
```
(The real manual path requires nvchecker/jq installed; the mock suite already covers behaviour. This step is optional if tools are absent — the suite is authoritative.)

- [ ] **Step 3: Confirm no stray TODO/debug**

Run: `grep -n "TODO\|XXX\|DEBUG" mkhint`
Expected: only the intentional stub-template `# TODO: configure nvchecker source` inside `add_nvchecker_section`.

- [ ] **Step 4: Spec compliance review**

Use superpowers:requesting-code-review (or self-review) against
`docs/superpowers/specs/2026-06-13-check-populate-missing-sections-design.md`.
Confirm: missing-section detection, batch prompt, `.info` lookup + skip on absent,
`add_nvchecker_section` reuse, `return 0` stop with review message, T29-T31 present and passing.

---

## Self-Review notes (author)

- **Spec coverage:** §"Detect missing sections" → Task 2 Step 1 + Task 1 helper. §"Offer to populate" → Task 2 Step 2. `.info` lookup + skip → Task 2 Step 2 (find + empty check). Reuse of `add_nvchecker_section` → Task 2 Step 2. `return 0` stop → Task 2 Step 2. Decline fall-through → preserved (no change to outdated path). Tests T29-T31 → Task 3. Docs → Task 4.
- **Placeholder scan:** none. T31 Step 1 explicitly states no fixture edit needed (not a deferred TODO).
- **Name consistency:** `_has_nvchecker_section`, `missing_sections`, `add_nvchecker_section`, `NVCHECKER_CONFIG`, `REPO_DIR` consistent across Tasks 1-3 and matching the existing codebase.
- **set -e:** the one new fallible call (`latest=$(nvchecker_latest ...)`) is wrapped in `if !`. `find` is in a command substitution. `add_nvchecker_section` returns 0. Safe.
- **Assertion count:** T29 = 4 (toml header, source, review msg, hint unchanged), T30 = 1, T31 = 2. 7 new... recount: T29 adds 4 PASS, T30 adds 1, T31 adds 2 → 7. Plan Step 3 says N=75 (69+6). CORRECTED: expected total is 76 (69 + 7). Implementer: assert on the actual printed total, not a hardcoded number — the suite prints `Results: <PASS> passed, <FAIL> failed`; the pass criterion is `0 failed`.
