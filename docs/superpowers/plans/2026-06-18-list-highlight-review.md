# `-l` highlight + `-R` review loop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Highlight hint rows whose version equals the SBo `.info` version in `mkhint -l`, and add a `-R`/`--review` flag that walks each matched hint with a side-by-side diff and a `[K]eep/[D]elete/[S]kip` prompt.

**Architecture:** Two independent flags (`SHOW_LIST`, `RUN_REVIEW`) replace the single `COMMAND="list"`. `list_hint_files` gains exact-match highlighting (TTY-only color, plus a test-only `MKHINT_FORCE_COLOR` knob) and collects matched packages into a global array `MATCHED_PKGS`. A new `review_hint_files` consumes that array. Removal is factored into `_remove_hint` shared with `delete_hint_file`.

**Tech Stack:** bash, getopt, tput, git/diff, existing `tests/mkhint_test.sh` harness.

---

## File Structure

- Modify `mkhint`:
  - `show_help` — document `--review`/`-R`.
  - `list_hint_files` — highlight matches, populate `MATCHED_PKGS`.
  - `delete_hint_file` — extract removal into `_remove_hint`.
  - new `review_hint_files`.
  - `main` — flag parsing + dispatch for `-l`/`-R`/`-lR`.
- Modify `mkhint.bash-completion` — add `--review -R` to `all_flags`.
- Modify `tests/mkhint_test.sh` — add T36–T41.
- Modify `CLAUDE.md` — docs.

Note on existing test IDs: T32–T35 already exist (nvchecker quoting/path). New tests are **T36–T41**.

---

## Task 1: Extract `_remove_hint` helper

**Files:**
- Modify: `mkhint` (`delete_hint_file`, ~lines 590–613)

- [ ] **Step 1: Add `_remove_hint` and call it from `delete_hint_file`**

Replace the body of `delete_hint_file` (lines 590–613) with:

```bash
# Remove a hint file and its .bak if present. No existence guard, no exit —
# safe to call inside loops. Echoes what was removed.
_remove_hint() {
    local full_path="$1"
    rm "$full_path"
    echo "Deleted: $full_path"
    local bak_path="${full_path}.bak"
    if [[ -f "$bak_path" ]]; then
        rm "$bak_path"
        echo "Deleted: $bak_path"
    fi
}

delete_hint_file() {
    local file="$1"
    local normalized_file="${file}"

    if [[ "$file" != *.hint ]]; then
        normalized_file="${file}.hint"
    fi

    local full_path="${HINT_DIR}/${normalized_file}"

    if [[ ! -f "$full_path" ]]; then
        echo "Error: Hint file does not exist: $full_path" >&2
        exit 2
    fi

    _remove_hint "$full_path"
}
```

- [ ] **Step 2: Run existing delete tests to confirm no regression**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E "T11|T12|hint deleted|bak deleted|delete missing"`
Expected: those PASS lines present, no new FAIL.

- [ ] **Step 3: Commit**

```bash
git add mkhint
git commit -m "refactor: extract _remove_hint helper for reuse in review loop"
```

---

## Task 2: Highlight matched rows in `list_hint_files`

**Files:**
- Modify: `mkhint` (`list_hint_files`, lines 82–119)
- Test: `tests/mkhint_test.sh`

- [ ] **Step 1: Write the failing test (T36)**

Insert before the `# ─── SUMMARY` block (after T35, ~line 746):

```bash
# ── T36: -l highlights rows where hint version == SBo version ─────────────────
echo ""
echo "T36: -l highlights matching version rows, plain row for mismatch"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
# curl matches its .info (8.5.0); clion differs (hint 9.9.9 vs .info 2025.3)
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
EOF
cat > "$MOCK_HINT/clion.hint" << 'EOF'
VERSION="9.9.9"
ARCH="x86_64"
DOWNLOAD="UNSUPPORTED"
MD5SUM=""
EOF
# force color so the highlight is observable through the $(...) pipe
out=$(MKHINT_FORCE_COLOR=1 run_mkhint -l 2>&1)
# matched curl row carries the color start code (ESC[33m); legend present
echo "$out" | grep -q $'\033\[33m.*curl.hint' \
    && { echo "  PASS: curl row highlighted"; (( PASS++ )); } \
    || { echo "  FAIL: curl row not highlighted"; echo "$out" | cat -v | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T36 highlight"); }
echo "$out" | grep -q "highlighted = hint version matches" \
    && { echo "  PASS: legend shown"; (( PASS++ )); } \
    || { echo "  FAIL: legend missing"; (( FAIL++ )); ERRORS+=("T36 legend"); }
# clion row must NOT carry the color start code
echo "$out" | grep "clion.hint" | grep -q $'\033\[33m' \
    && { echo "  FAIL: clion wrongly highlighted"; (( FAIL++ )); ERRORS+=("T36 false hl"); } \
    || { echo "  PASS: clion row plain"; (( PASS++ )); }
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A6 "^T36:"`
Expected: FAIL on "curl row highlighted" / "legend shown" (no color/legend yet).

- [ ] **Step 3: Implement highlighting in `list_hint_files`**

Replace lines 82–119 (whole function) with:

```bash
list_hint_files() {
    if [[ ! -d "$HINT_DIR" ]]; then
        echo "Error: Hint directory does not exist: $HINT_DIR" >&2
        exit 2
    fi

    # Color only on a TTY, or when forced for tests. tput optional.
    local c_on="" c_off=""
    if [[ -n "$MKHINT_FORCE_COLOR" || -t 1 ]]; then
        if command -v tput &>/dev/null && tput setaf 3 &>/dev/null; then
            c_on=$(tput setaf 3); c_off=$(tput sgr0)
        else
            c_on=$'\033[33m'; c_off=$'\033[0m'
        fi
    fi

    echo "Hint files in: $HINT_DIR"
    echo "======================================================="
    printf "%-40s  %10s  %10s  %-20s  %s\n" "File" "HintVer" "SBOVer" "Category" "Created"
    echo "-------------------------------------------------------"

    MATCHED_PKGS=()
    local count=0 matched=0
    for file in "$HINT_DIR"/*.hint; do
        if [[ -f "$file" ]]; then
            local VER=$(grep "^VERSION" "$file" |cut -d '"' -f2)
            local name=$(basename "$file")
            local pkg="${name%.hint}"
            local info_file
            info_file=$(find "$REPO_DIR" -mindepth 2 -name "${pkg}.info" 2>/dev/null | head -1)
            local SBO_VER=""
            local category=""
            if [[ -f "$info_file" ]]; then
                SBO_VER=$(grep "^VERSION" "$info_file" | cut -d '"' -f2)
                category=$(basename "$(dirname "$(dirname "$info_file")")")
            fi
            local date=$(stat -c "%y" "$file" | cut -d'.' -f1)
            local row
            row=$(printf "%-40s  %10s  %10s  %-20s  %s" "$name" "$VER" "$SBO_VER" "$category" "$date")
            if [[ -n "$VER" && "$VER" == "$SBO_VER" ]]; then
                printf "%s%s%s\n" "$c_on" "$row" "$c_off"
                MATCHED_PKGS+=("$pkg")
                matched=$((matched + 1))
            else
                printf "%s\n" "$row"
            fi
            count=$((count + 1))
        fi
    done

    if [[ $count -eq 0 ]]; then
        echo "  (no hint files found)"
    fi

    echo "======================================================="
    echo "Total: $count file(s)"
    if [[ $matched -gt 0 && -n "$c_on" ]]; then
        echo "(highlighted = hint version matches SBo .info)"
    fi
}
```

- [ ] **Step 4: Run T36 to verify it passes**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A6 "^T36:"`
Expected: all T36 lines PASS.

- [ ] **Step 5: Declare `MATCHED_PKGS` global near other state**

Find the global declarations near the top (after the path config block) and add:

```bash
MATCHED_PKGS=()
```

(Search for an existing `DELETE_HINT_FILES=()` or similar array declaration and place it alongside. If none exists at top, the in-function reset is sufficient — skip this step.)

- [ ] **Step 6: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -m "feat: highlight hint rows whose version matches SBo .info in -l"
```

---

## Task 3: Add `review_hint_files` and `-R`/`--review` flag

**Files:**
- Modify: `mkhint` (new function; `main` parsing/dispatch lines 752–849; `show_help`)
- Test: `tests/mkhint_test.sh`

- [ ] **Step 1: Add `review_hint_files` function**

Insert immediately after `list_hint_files` (after its closing `}`):

```bash
# Show each matched hint side-by-side with its .info, prompt Keep/Delete/Skip.
# Relies on MATCHED_PKGS populated by list_hint_files.
review_hint_files() {
    if [[ ${#MATCHED_PKGS[@]} -eq 0 ]]; then
        echo "No hints match their SBo version; nothing to review."
        return 0
    fi

    local deleted=0 kept=0
    local pkg
    for pkg in "${MATCHED_PKGS[@]}"; do
        local hint="${HINT_DIR}/${pkg}.hint"
        local info
        info=$(find "$REPO_DIR" -mindepth 2 -name "${pkg}.info" 2>/dev/null | head -1)
        [[ -f "$hint" ]] || continue

        echo ""
        echo "=== $pkg ==="
        if command -v git &>/dev/null; then
            git diff --no-index --color=auto "$hint" "$info" || true
        else
            diff -y --width="${COLUMNS:-160}" "$hint" "$info" || true
        fi

        local ans
        read -r -p "Review $pkg: [K]eep / [D]elete / [S]kip (default Keep): " ans
        case "$ans" in
            [Dd])
                _remove_hint "$hint"
                deleted=$((deleted + 1))
                ;;
            [Ss]|[Kk]|"")
                echo "Kept: $pkg"
                kept=$((kept + 1))
                ;;
            *)
                echo "Unrecognised answer; keeping $pkg"
                kept=$((kept + 1))
                ;;
        esac
    done

    echo ""
    echo "Reviewed ${#MATCHED_PKGS[@]} hint(s): deleted $deleted, kept $kept."
}
```

- [ ] **Step 2: Add the failing tests (T37–T41)**

Insert after T36 in `tests/mkhint_test.sh`:

```bash
# ── T37: -R delete a matched hint ─────────────────────────────────────────────
echo ""
echo "T37: -R answer D → matched hint and .bak removed"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
EOF
touch "$MOCK_HINT/curl.hint.bak"
out=$(run_mkhint -R < <(printf 'D\n') 2>&1)
assert_file_not_exists "curl hint deleted"        "$MOCK_HINT/curl.hint"
assert_file_not_exists "curl bak deleted"         "$MOCK_HINT/curl.hint.bak"
echo "$out" | grep -q "deleted 1" \
    && { echo "  PASS: summary reports deleted 1"; (( PASS++ )); } \
    || { echo "  FAIL: summary wrong"; echo "$out" | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T37 summary"); }

# ── T38: -R keep a matched hint ───────────────────────────────────────────────
echo ""
echo "T38: -R answer K → matched hint unchanged"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
EOF
run_mkhint -R < <(printf 'K\n') >/dev/null 2>&1
assert_file_exists "curl hint kept" "$MOCK_HINT/curl.hint"

# ── T39: -R empty answer = keep ───────────────────────────────────────────────
echo ""
echo "T39: -R empty answer → kept (default)"
run_mkhint -R < <(printf '\n') >/dev/null 2>&1
assert_file_exists "curl hint kept on empty" "$MOCK_HINT/curl.hint"

# ── T40: -R skip a matched hint ───────────────────────────────────────────────
echo ""
echo "T40: -R answer S → matched hint unchanged"
run_mkhint -R < <(printf 'S\n') >/dev/null 2>&1
assert_file_exists "curl hint kept on skip" "$MOCK_HINT/curl.hint"

# ── T41: -R with no matches → nothing to review, exit 0 ───────────────────────
echo ""
echo "T41: -R no matched rows → nothing to review"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
# clion hint version differs from its .info → no match
cat > "$MOCK_HINT/clion.hint" << 'EOF'
VERSION="9.9.9"
ARCH="x86_64"
DOWNLOAD="UNSUPPORTED"
MD5SUM=""
EOF
set +e
out=$(run_mkhint -R < <(printf '\n') 2>&1)
code=$?
set -e
assert_exit_code "no-match review exits 0" 0 "$code"
echo "$out" | grep -q "nothing to review" \
    && { echo "  PASS: nothing-to-review message"; (( PASS++ )); } \
    || { echo "  FAIL: message missing"; echo "$out" | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T41 msg"); }
```

- [ ] **Step 3: Run tests to verify T37–T41 fail**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A3 -E "^T3[789]:|^T4[01]:"`
Expected: FAIL — `-R` not yet a known option (getopt error / unknown option).

- [ ] **Step 4: Wire up `-R`/`--review` in `main`**

In the getopt line (line 755), add `R` to short opts and `review` to long opts:

```bash
    parsed=$(getopt -o v:f:n:lcCdNhR \
        --long version:,hintfile:,new:,list,clean,check,delete,no-dl,help,review \
        -n 'mkhint' -- "$@") || { show_help; exit 1; }
```

Replace the `--list|-l` case (lines 774–777) with two independent toggles:

```bash
            --list|-l)
                SHOW_LIST=1
                shift
                ;;
            --review|-R)
                RUN_REVIEW=1
                shift
                ;;
```

- [ ] **Step 5: Add dispatch for the list/review flags**

In the `if [[ -z "$COMMAND" ]]` block (lines 816–825), the new flags are not `COMMAND`s — handle them after that block. Add, right before the `case "$COMMAND" in` (line 837):

```bash
    if [[ -n "$SHOW_LIST" || -n "$RUN_REVIEW" ]]; then
        [[ -n "$SHOW_LIST" ]] && list_hint_files
        if [[ -n "$RUN_REVIEW" ]]; then
            # ensure MATCHED_PKGS is populated even when -l was not given
            [[ -z "$SHOW_LIST" ]] && list_hint_files >/dev/null
            review_hint_files
        fi
        exit $?
    fi
```

Remove the now-dead `list)` case from the `case "$COMMAND"` block (lines 841–843), since `-l` no longer sets `COMMAND`. Leave the rest of the cases intact.

- [ ] **Step 6: Initialize the flag globals**

Near the top globals (where `NO_DL=0` / `DELETE_HINT_FILES=()` live), add:

```bash
SHOW_LIST=""
RUN_REVIEW=""
```

- [ ] **Step 7: Run the new tests to verify they pass**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A3 -E "^T3[6789]:|^T4[01]:"`
Expected: all T36–T41 lines PASS.

- [ ] **Step 8: Run the full suite**

Run: `bash tests/mkhint_test.sh 2>&1 | tail -5`
Expected: `Results: N passed, 0 failed`.

- [ ] **Step 9: Document `--review` in `show_help`**

Add to the Usage block (after the `--list` line, ~line 49):

```
  ./mkhint --review                             Review hints matching SBo version, keep/delete each
```

Add to the Options block (after `--list, -l`, ~line 59):

```
  --review, -R             Review hints whose version matches the SBo .info; diff + keep/delete
```

- [ ] **Step 10: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -m "feat: add -R/--review loop with side-by-side diff and keep/delete prompt"
```

---

## Task 4: Bash completion + CLAUDE.md docs

**Files:**
- Modify: `mkhint.bash-completion` (line 11)
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add `--review -R` to completion flags**

In `mkhint.bash-completion` line 11, append to `all_flags`:

```bash
    local all_flags="--version -v --hintfile -f --new -n --list -l --review -R --clean -c --check -C --delete -d --no-dl -N --help -h"
```

- [ ] **Step 2: Update CLAUDE.md — Running/Testing**

Add under the run examples (after the `--list` group / near line 42):

```bash
bash mkhint --list                         # highlight hints whose version matches SBo .info
bash mkhint --review                       # review matched hints: diff + [K]eep/[D]elete/[S]kip
bash mkhint --list --review                # show highlighted table, then review
```

- [ ] **Step 3: Update CLAUDE.md — test table**

Append rows to the coverage table:

```
| T36 | `-l` highlights rows where hint version == SBo version; mismatch plain |
| T37 | `-R` answer D — matched hint and .bak removed, summary reports deleted 1 |
| T38 | `-R` answer K — matched hint unchanged |
| T39 | `-R` empty answer — kept (default) |
| T40 | `-R` answer S — matched hint unchanged |
| T41 | `-R` no matched rows — "nothing to review", exit 0 |
```

- [ ] **Step 4: Update CLAUDE.md — Key Behaviors**

Add bullets:

```
- `--list` / `-l`: lists hints with `HintVer`/`SBOVer`; rows where the two are byte-equal are highlighted (color only on a TTY; plain when piped). Adds a legend when any row matched.
- `--review` / `-R`: iterates only the matched (highlighted) hints. For each, shows the hint side-by-side with its `.info` (`git diff --no-index` if git present, else `diff -y`), then prompts `[K]eep / [D]elete / [S]kip` (default Keep). Delete removes the hint and its `.bak` via `_remove_hint`. Prints a deleted/kept summary. `-l` and `-R` combine: `-lR` shows the table first, then reviews. No matches → "nothing to review", exit 0.
```

- [ ] **Step 5: Run full suite one final time**

Run: `bash tests/mkhint_test.sh 2>&1 | tail -3`
Expected: `Results: N passed, 0 failed`.

- [ ] **Step 6: Commit**

```bash
git add mkhint.bash-completion CLAUDE.md
git commit -m "docs: document -l highlight and -R review; add to bash completion"
```

---

## Self-Review Notes

- **Spec coverage:** flag table (Task 3 dispatch), exact match (Task 2 `==`), TTY-only color + non-TTY plain (Task 2 `c_on` guard), legend (Task 2), git/diff fallback (Task 3), Keep/Delete/Skip + default + re-prompt (Task 3 `case`), `_remove_hint` refactor preserving `--delete` exit-2 (Task 1), no-match exit 0 (Task 3 / T41), all docs (Task 4). All covered.
- **Type consistency:** `MATCHED_PKGS` populated in `list_hint_files`, consumed in `review_hint_files`; `SHOW_LIST`/`RUN_REVIEW` set in parsing, read in dispatch; `_remove_hint` defined Task 1, used Tasks 1 & 3.
- **Test IDs:** T36–T41 (T32–T35 already taken by nvchecker tests).
- **Note for executor:** `-t 1` is false under the `$(...)` test pipe, so T36 uses `MKHINT_FORCE_COLOR=1`. Real interactive use needs no env var.
