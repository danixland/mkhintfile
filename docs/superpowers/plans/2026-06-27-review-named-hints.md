# Review Named Hints (`-R <pkg...>`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let `-R`/`--review` take explicit package names and review each named hint (diff + K/D/S) regardless of version match; no args keeps the matched-only batch loop.

**Architecture:** Factor the per-hint review body into `_review_one_hint`. Make `review_hint_files` iterate either named args (validated up front, no match filter) or the matched set. Route positional args to a review list when `-R` is active. Fix completion to suggest hint names repeatedly after `-R`.

**Tech Stack:** Bash, getopt, bash-completion. Tests in `tests/mkhint_test.sh` (mock dirs, no real downloads).

---

## File Structure

- `mkhint` — `review_hint_files` refactor + new `_review_one_hint`; new `REVIEW_PKGS` var; arg routing in option parser.
- `mkhint.bash-completion` — repeated hint-name completion after `-R`/`--review`.
- `tests/mkhint_test.sh` — T44–T47.
- `CLAUDE.md` — update `-R` behavior + test table.

---

## Task 1: Extract `_review_one_hint`, drive `review_hint_files` from a list

**Files:**
- Modify: `mkhint:35` (add `REVIEW_PKGS=()` near `MATCHED_PKGS=()`)
- Modify: `mkhint:148-192` (`review_hint_files` + new helper)

- [ ] **Step 1: Add `REVIEW_PKGS` global**

In `mkhint`, after line 35 (`MATCHED_PKGS=()`):

```bash
REVIEW_PKGS=()
```

- [ ] **Step 2: Replace `review_hint_files` (lines 148-192) with helper + list-driven loop**

```bash
# Diff one hint against its .info and prompt Keep/Delete/Skip.
# Echoes "deleted" or "kept" so the caller can tally. Diff to stderr-ish output.
_review_one_hint() {
    local pkg="$1"
    local hint="${HINT_DIR%/}/${pkg}.hint"
    local info
    info=$(find "$REPO_DIR" -mindepth 2 -name "${pkg}.info" 2>/dev/null | head -1)

    echo "" >&2
    echo "=== $pkg ===" >&2
    if command -v git &>/dev/null; then
        git diff --no-index --color=auto "$hint" "$info" >&2 || true
    else
        diff -y --width="${COLUMNS:-160}" "$hint" "$info" >&2 || true
    fi

    local ans
    read -r -p "Review $pkg: [K]eep / [D]elete / [S]kip (default Keep): " ans
    case "$ans" in
        [Dd])
            _remove_hint "$hint" >&2
            echo deleted
            ;;
        [Ss]|[Kk]|"")
            echo "Kept: $pkg" >&2
            echo kept
            ;;
        *)
            echo "Unrecognised answer; keeping $pkg" >&2
            echo kept
            ;;
    esac
}

# Review hints. With package args: review each named hint (any version), validating
# existence first (exit 2 on a missing hint). With no args: review MATCHED_PKGS.
review_hint_files() {
    local -a pkgs
    if [[ $# -gt 0 ]]; then
        pkgs=("$@")
        local p
        for p in "${pkgs[@]}"; do
            if [[ ! -f "${HINT_DIR%/}/${p}.hint" ]]; then
                echo "Error: hint file not found: ${HINT_DIR%/}/${p}.hint" >&2
                exit 2
            fi
        done
    else
        if [[ ${#MATCHED_PKGS[@]} -eq 0 ]]; then
            echo "No hints match their SBo version; nothing to review."
            return 0
        fi
        pkgs=("${MATCHED_PKGS[@]}")
    fi

    local deleted=0 kept=0 pkg result
    for pkg in "${pkgs[@]}"; do
        result=$(_review_one_hint "$pkg")
        case "$result" in
            deleted) deleted=$((deleted + 1)) ;;
            *)       kept=$((kept + 1)) ;;
        esac
    done

    echo ""
    echo "Reviewed ${#pkgs[@]} hint(s): deleted $deleted, kept $kept."
}
```

Note: `_review_one_hint` sends all human output to `>&2` and echoes only the
one-word result to stdout so the caller can capture it. The summary counts
`${#pkgs[@]}` (actually-reviewed), fixing the old `MATCHED_PKGS` miscount.

Note: the `_review_one_hint` `read` prompts on the terminal; with a captured
stdout it still reads from stdin normally (tests pipe answers via stdin).

- [ ] **Step 3: Syntax check**

Run: `bash -n mkhint`
Expected: no output, exit 0.

- [ ] **Step 4: Verify existing review tests still pass (regression)**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T37|T38|T39|T40|T41|FAIL'`
Expected: T37/T41 PASS lines, no `FAIL` lines from those.

- [ ] **Step 5: Commit**

```bash
git add mkhint
git commit -m "refactor: extract _review_one_hint, drive review loop from a list"
```

---

## Task 2: Route positional args to review when `-R` is active

**Files:**
- Modify: `mkhint:899-903` (positional collection)
- Modify: `mkhint:926-933` (review dispatch)

- [ ] **Step 1: Collect positionals into `REVIEW_PKGS` when reviewing**

Replace the positional loop at lines 899-903:

```bash
    # Collect remaining positional args.
    # When -R is active and no other command set, they are review targets;
    # otherwise they are delete targets.
    while [[ $# -gt 0 ]]; do
        if [[ -n "$RUN_REVIEW" && -z "$COMMAND" ]]; then
            REVIEW_PKGS+=("$1")
        else
            DELETE_HINT_FILES+=("$1")
        fi
        shift
    done
```

- [ ] **Step 2: Pass named pkgs to `review_hint_files`**

Replace the review dispatch block at lines 926-933:

```bash
    if [[ -n "$SHOW_LIST" || -n "$RUN_REVIEW" ]]; then
        [[ -n "$SHOW_LIST" ]] && list_hint_files
        if [[ -n "$RUN_REVIEW" ]]; then
            if [[ ${#REVIEW_PKGS[@]} -gt 0 ]]; then
                review_hint_files "${REVIEW_PKGS[@]}"
            else
                # ensure MATCHED_PKGS is populated even when -l was not given
                [[ -z "$SHOW_LIST" ]] && list_hint_files >/dev/null
                review_hint_files
            fi
        fi
        exit $?
    fi
```

- [ ] **Step 3: Syntax check**

Run: `bash -n mkhint`
Expected: no output, exit 0.

- [ ] **Step 4: Manual smoke (named, non-matched hint)**

Run: `printf 'K\n' | bash mkhint -R nonexistentpkg; echo "exit=$?"`
Expected: error "hint file not found" and `exit=2`.

- [ ] **Step 5: Commit**

```bash
git add mkhint
git commit -m "feat: review named hints via -R <pkg...> regardless of version match"
```

---

## Task 3: Tests T44–T47

**Files:**
- Modify: `tests/mkhint_test.sh` (after T43 block)

- [ ] **Step 1: Add the four test blocks**

Find the end of the T43 block in `tests/mkhint_test.sh` (the last `--check` test before the summary). Insert after it:

```bash
# ── T44: -R <pkg> reviews a non-matched hint, Keep leaves it ──────────────────
echo ""
echo "T44: -R <pkg> on a non-matched hint → diff shown, Keep leaves it"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
# clion hint version differs from its .info → not matched by bare -R
cat > "$MOCK_HINT/clion.hint" << 'EOF'
VERSION="9.9.9"
ARCH="x86_64"
DOWNLOAD="UNSUPPORTED"
MD5SUM=""
EOF
out=$(run_mkhint -R clion < <(printf 'K\n') 2>&1)
assert_file_exists "named non-matched hint kept" "$MOCK_HINT/clion.hint"
echo "$out" | grep -q "=== clion ===" \
    && { echo "  PASS: diff header shown for named hint"; (( PASS++ )); } \
    || { echo "  FAIL: diff header missing"; echo "$out" | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T44 header"); }

# ── T45: -R <pkg> answer D → named hint and .bak removed ──────────────────────
echo ""
echo "T45: -R <pkg> answer D → named hint and .bak removed"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
cat > "$MOCK_HINT/clion.hint" << 'EOF'
VERSION="9.9.9"
ARCH="x86_64"
DOWNLOAD="UNSUPPORTED"
MD5SUM=""
EOF
touch "$MOCK_HINT/clion.hint.bak"
out=$(run_mkhint -R clion < <(printf 'D\n') 2>&1)
assert_file_not_exists "named hint deleted"  "$MOCK_HINT/clion.hint"
assert_file_not_exists "named bak deleted"   "$MOCK_HINT/clion.hint.bak"
echo "$out" | grep -q "deleted 1" \
    && { echo "  PASS: summary reports deleted 1"; (( PASS++ )); } \
    || { echo "  FAIL: summary wrong"; echo "$out" | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T45 summary"); }

# ── T46: -R <pkg1> <pkg2> → both reviewed ────────────────────────────────────
echo ""
echo "T46: -R two packages → both reviewed, summary counts 2"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
cat > "$MOCK_HINT/clion.hint" << 'EOF'
VERSION="9.9.9"
ARCH="x86_64"
DOWNLOAD="UNSUPPORTED"
MD5SUM=""
EOF
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="9.9.9"
ARCH="x86_64"
DOWNLOAD="UNSUPPORTED"
MD5SUM=""
EOF
out=$(run_mkhint -R clion curl < <(printf 'K\nK\n') 2>&1)
echo "$out" | grep -q "Reviewed 2 hint" \
    && { echo "  PASS: summary reports 2 reviewed"; (( PASS++ )); } \
    || { echo "  FAIL: summary count wrong"; echo "$out" | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T46 count"); }

# ── T47: -R <missing> → exit 2 ───────────────────────────────────────────────
echo ""
echo "T47: -R missing package → exit 2"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
set +e
out=$(run_mkhint -R nope < <(printf 'K\n') 2>&1)
code=$?
set -e
assert_exit_code "missing named hint exits 2" 2 "$code"
```

- [ ] **Step 2: Run the new tests**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T44|T45|T46|T47'`
Expected: PASS lines for each, no FAIL.

- [ ] **Step 3: Run full suite**

Run: `bash tests/mkhint_test.sh 2>&1 | tail -5`
Expected: all pass, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add tests/mkhint_test.sh
git commit -m "test: cover -R <pkg...> named-hint review (T44-T47)"
```

---

## Task 4: Bash completion — repeated hint names after `-R`

**Files:**
- Modify: `mkhint.bash-completion:13-48`

- [ ] **Step 1: Add an `-R` pre-check before the `case`**

The `case "$prev"` only fires one word after a flag. To complete multiple
package names after `-R`, detect `-R`/`--review` anywhere earlier in the line
(mirroring the existing `--version` lookback) and short-circuit.

Insert immediately after `_init_completion || return` and the dir/flag setup
(after line 11), before the `case` at line 13:

```bash
    # -R/--review takes any number of hint names; complete them repeatedly.
    local w in_review=""
    for w in "${COMP_WORDS[@]:1}"; do
        [[ "$w" == "-R" || "$w" == "--review" ]] && in_review=1
    done
    if [[ -n "$in_review" && "$cur" != -* ]]; then
        local -a rwords=()
        for f in "$hint_dir"/*.hint; do
            [[ -f "$f" ]] && rwords+=("$(basename "${f%.hint}")")
        done
        COMPREPLY=($(compgen -W "${rwords[*]}" -- "$cur"))
        return
    fi
```

- [ ] **Step 2: Verify syntax**

Run: `bash -n mkhint.bash-completion`
Expected: no output, exit 0.

- [ ] **Step 3: Manual completion check**

```bash
bash -c 'source mkhint.bash-completion 2>/dev/null; \
  COMP_WORDS=(mkhint -R ""); COMP_CWORD=2; cur=""; prev=-R; \
  declare -f _mkhintfile_completions >/dev/null && echo "loaded ok"'
```
Expected: `loaded ok` (sanity that the function parses/sources; real completion needs a live shell with bash-completion).

- [ ] **Step 4: Commit**

```bash
git add mkhint.bash-completion
git commit -m "feat: complete multiple hint names after -R/--review"
```

---

## Task 5: Docs

**Files:**
- Modify: `CLAUDE.md` (the `--review` / `-R` behavior bullet ~line 110; test table)

- [ ] **Step 1: Update the `-R` behavior bullet**

In `CLAUDE.md`, append to the `--review` / `-R` bullet that `-R <pkg...>` reviews
the named hints regardless of version match (existence required, exit 2 on
missing), while bare `-R` keeps the matched-only loop. Add T44–T47 rows to the
test table.

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document -R <pkg...> named-hint review"
```

---

## Self-Review

- Spec coverage: named review (T2/T44), no match filter (T44), missing → exit 2 (T47), multiple pkgs (T46), delete path (T45), `-lR foo` (arg routing handles `SHOW_LIST` independently), summary counts reviewed (Task 1 Step 2), completion repeat (Task 4). `.info` missing → diff against empty: `_review_one_hint` passes empty `$info` to git/diff exactly as today. Covered.
- Placeholder scan: none.
- Type consistency: `REVIEW_PKGS`, `_review_one_hint`, `review_hint_files "$@"` consistent across tasks.
