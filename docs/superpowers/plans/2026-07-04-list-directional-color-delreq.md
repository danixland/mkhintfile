# `-l` directional color + DelReq column Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the `-l` table, color the newer version cell green (hint vs SBo `.info`), keep equal-version rows yellow, and add a `DelReq` boolean column before `Created`.

**Architecture:** All changes live in `list_hint_files` in `mkhint`. A green color pair is added next to the existing yellow. Per row, byte-equality keeps the yellow-row + `MATCHED_PKGS` path; on a difference `sort -V` picks the newer side and only that cell is wrapped green. Version cells are pre-padded to width 22 before wrapping so color bytes don't break alignment. A `DelReq` column (`✓` / blank) is derived from a `DELREQUIRES="..."` grep.

**Tech Stack:** bash, coreutils (`sort -V`), `tput`, existing `tests/mkhint_test.sh` harness.

---

## File structure

- Modify: `mkhint` — `list_hint_files` (lines ~97-158): color setup, header, per-row logic, legend.
- Modify: `tests/mkhint_test.sh` — append T60-T64 after T59 (~line 1145).
- Modify: `CLAUDE.md` — update the `--list` / `-l` behavior bullet and the test table.
- Modify: `README.md` — update `-l` description if it enumerates columns/colors.

No new files. No new dependencies.

---

## Task 1: Green color pair + directional cell coloring

**Files:**
- Modify: `mkhint` `list_hint_files` (color block ~104-111, header ~115, row loop ~118-147, legend ~155-157)
- Test: `tests/mkhint_test.sh` (append T60, T61, T62)

- [ ] **Step 1: Write failing tests T60, T61, T62**

Append after T59 in `tests/mkhint_test.sh`:

```bash
# ── T60: -l hint newer than SBo → HintVer cell green ─────────────────────────
echo ""
echo "T60: -l hint version newer than .info → HintVer green"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
# curl .info is 8.5.0; hint 8.6.0 is newer
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.6.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.6.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
EOF
out=$(MKHINT_FORCE_COLOR=1 run_mkhint -l 2>&1)
# green start code (ESC[32m) appears before the hint version 8.6.0 on the curl row
echo "$out" | grep curl.hint | grep -q $'\033\[32m.*8\.6\.0' \
    && { echo "  PASS: HintVer green when hint newer"; (( PASS++ )); } \
    || { echo "  FAIL: HintVer not green"; echo "$out" | grep curl.hint | cat -v | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T60 green"); }
# whole row must NOT be yellow (differing versions)
echo "$out" | grep curl.hint | grep -q $'\033\[33m' \
    && { echo "  FAIL: differing row wrongly yellow"; (( FAIL++ )); ERRORS+=("T60 yellow"); } \
    || { echo "  PASS: differing row not yellow"; (( PASS++ )); }

# ── T61: -l SBo newer than hint → SBOVer cell green ──────────────────────────
echo ""
echo "T61: -l .info version newer than hint → SBOVer green"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
# curl .info is 8.5.0; hint 8.4.0 is older
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.4.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.4.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
EOF
out=$(MKHINT_FORCE_COLOR=1 run_mkhint -l 2>&1)
# green start code appears before the SBo version 8.5.0 on the curl row
echo "$out" | grep curl.hint | grep -q $'\033\[32m.*8\.5\.0' \
    && { echo "  PASS: SBOVer green when .info newer"; (( PASS++ )); } \
    || { echo "  FAIL: SBOVer not green"; echo "$out" | grep curl.hint | cat -v | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T61 green"); }

# ── T62: -l equal versions → whole row yellow, no green ──────────────────────
echo ""
echo "T62: -l equal versions → yellow row, no green cell"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
EOF
out=$(MKHINT_FORCE_COLOR=1 run_mkhint -l 2>&1)
echo "$out" | grep curl.hint | grep -q $'\033\[33m' \
    && { echo "  PASS: equal row yellow"; (( PASS++ )); } \
    || { echo "  FAIL: equal row not yellow"; echo "$out" | grep curl.hint | cat -v | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T62 yellow"); }
echo "$out" | grep curl.hint | grep -q $'\033\[32m' \
    && { echo "  FAIL: equal row wrongly green"; (( FAIL++ )); ERRORS+=("T62 green"); } \
    || { echo "  PASS: equal row has no green"; (( PASS++ )); }
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A1 'T6[012]'`
Expected: FAIL lines for T60 green, T61 green (no green codes emitted yet). T62 yellow passes (existing behavior), T62 green passes.

- [ ] **Step 3: Add green color pair to the color setup block**

In `mkhint`, replace the color block (currently ~104-111):

```bash
    # Color only on a TTY, or when forced for tests. tput optional.
    local c_on="" c_off="" g_on=""
    if [[ -n "$MKHINT_FORCE_COLOR" || -t 1 ]]; then
        if command -v tput &>/dev/null && tput setaf 3 &>/dev/null; then
            c_on=$(tput setaf 3); g_on=$(tput setaf 2); c_off=$(tput sgr0)
        else
            c_on=$'\033[33m'; g_on=$'\033[32m'; c_off=$'\033[0m'
        fi
    fi
```

`c_on` = yellow (row), `g_on` = green (cell), `c_off` = reset (shared).

- [ ] **Step 4: Rewrite the per-row loop for directional coloring**

Replace the row body (currently ~136-145, from `local row` through `count=$((count + 1))`) with:

```bash
            local hv sv
            hv=$(printf "%22s" "$VER")
            sv=$(printf "%22s" "$SBO_VER")
            if [[ -n "$SBO_VER" && "$VER" == "$SBO_VER" ]]; then
                # equal → whole row yellow
                local row
                row=$(printf "%-40s  %s  %s  %-20s" "$name" "$hv" "$sv" "$category")
                printf "%s%s%s\n" "$c_on" "$row" "$c_off"
                MATCHED_PKGS+=("$pkg")
                matched=$((matched + 1))
            else
                # differ (or no SBO_VER) → green the newer cell, row plain
                if [[ -n "$SBO_VER" ]]; then
                    local newer
                    newer=$(printf '%s\n%s\n' "$VER" "$SBO_VER" | sort -V | tail -1)
                    if [[ "$newer" == "$VER" ]]; then
                        hv="${g_on}${hv}${c_off}"
                    else
                        sv="${g_on}${sv}${c_off}"
                    fi
                fi
                printf "%-40s  %s  %s  %-20s\n" "$name" "$hv" "$sv" "$category"
            fi
            count=$((count + 1))
```

Note: the trailing `Category`/`Created` columns are handled in Task 2 (DelReq column insertion). For now this task drops `date` from the printf to keep the diff focused; Task 2 adds `DelReq` + `Created` back. If executing Task 1 standalone, append `  %s` and `"$date"` to both printf lines and their format strings.

- [ ] **Step 5: Update the legend**

Replace the matched-count legend (currently ~155-157):

```bash
    if [[ $matched -gt 0 && -n "$c_on" ]]; then
        echo "(yellow row = versions match; green = newer side)"
    fi
```

Keep grep-compatible text; T36 greps `"highlighted = hint version matches"` — update T36 in the same commit (see Step 6).

- [ ] **Step 6: Fix T36 legend grep**

T36 (line ~823) greps for the old legend string. Change:

```bash
echo "$out" | grep -q "yellow row = versions match" \
```

- [ ] **Step 7: Run tests, verify T60/T61/T62 and T36 pass**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T(36|6[012])|FAIL'`
Expected: all PASS, no FAIL.

- [ ] **Step 8: bash -n check**

Run: `bash -n mkhint && echo OK`
Expected: `OK`

- [ ] **Step 9: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: -l colors newer version cell green, keeps equal rows yellow"
```

---

## Task 2: DelReq column

**Files:**
- Modify: `mkhint` `list_hint_files` (header ~115, row loop printf lines from Task 1)
- Test: `tests/mkhint_test.sh` (append T63, T64)

- [ ] **Step 1: Write failing tests T63, T64**

Append after T62 in `tests/mkhint_test.sh`:

```bash
# ── T63: -l shows ✓ in DelReq for hint with DELREQUIRES ──────────────────────
echo ""
echo "T63: -l DelReq column shows ✓ when DELREQUIRES populated"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DELREQUIRES="rust-opt"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
EOF
out=$(run_mkhint -l 2>&1)
echo "$out" | grep -q "DelReq" \
    && { echo "  PASS: DelReq header present"; (( PASS++ )); } \
    || { echo "  FAIL: DelReq header missing"; echo "$out" | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T63 header"); }
echo "$out" | grep curl.hint | grep -q "✓" \
    && { echo "  PASS: ✓ shown for DELREQUIRES hint"; (( PASS++ )); } \
    || { echo "  FAIL: ✓ missing"; echo "$out" | grep curl.hint | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T63 check"); }

# ── T64: -l DelReq blank when no DELREQUIRES ─────────────────────────────────
echo ""
echo "T64: -l DelReq column blank when no DELREQUIRES"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
EOF
out=$(run_mkhint -l 2>&1)
echo "$out" | grep curl.hint | grep -q "✓" \
    && { echo "  FAIL: ✓ shown without DELREQUIRES"; (( FAIL++ )); ERRORS+=("T64 check"); } \
    || { echo "  PASS: no ✓ without DELREQUIRES"; (( PASS++ )); }
```

- [ ] **Step 2: Run tests, verify they fail**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A2 'T6[34]'`
Expected: FAIL for T63 header (no DelReq column yet), T63 check. T64 passes vacuously.

- [ ] **Step 3: Add the DelReq header**

Replace the header printf (currently ~115):

```bash
    printf "%-40s  %22s  %22s  %-20s  %-6s  %s\n" "File" "HintVer" "SBOVer" "Category" "DelReq" "Created"
```

Column order: `File | HintVer | SBOVer | Category | DelReq | Created`.

- [ ] **Step 4: Compute the DelReq value in the row loop**

After the `VER` skip check in the loop (after line ~124), add:

```bash
            local delreq=""
            grep -q '^DELREQUIRES="..*"' "$file" && delreq="✓"
```

- [ ] **Step 5: Add a display-width pad helper and use it for DelReq + Created**

Add this helper just above `list_hint_files` (near line 96):

```bash
# Pad a possibly-multibyte glyph (0 or 1 display column) to a fixed width.
_pad_glyph() {
    local g="$1" w="$2"
    if [[ -n "$g" ]]; then printf "%s%*s" "$g" $((w - 1)) ""; else printf "%*s" "$w" ""; fi
}
```

In both row printf calls from Task 1, append the DelReq + Created columns.
Yellow (equal) branch:

```bash
                row=$(printf "%-40s  %s  %s  %-20s  %s  %s" "$name" "$hv" "$sv" "$category" "$(_pad_glyph "$delreq" 6)" "$date")
```

Plain (differ) branch:

```bash
                printf "%-40s  %s  %s  %-20s  %s  %s\n" "$name" "$hv" "$sv" "$category" "$(_pad_glyph "$delreq" 6)" "$date"
```

(`$date` is already computed at ~135; keep it.)

- [ ] **Step 6: Run tests, verify T63/T64 pass**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T6[34]|FAIL'`
Expected: all PASS, no FAIL.

- [ ] **Step 7: Full suite + bash -n**

Run: `bash -n mkhint && bash tests/mkhint_test.sh 2>&1 | tail -5`
Expected: `OK`, and the summary reports 0 failures.

- [ ] **Step 8: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: -l adds DelReq column showing populated DELREQUIRES"
```

---

## Task 3: Docs

**Files:**
- Modify: `CLAUDE.md` (the `--list` / `-l` behavior bullet, the test-coverage table)
- Modify: `README.md` (if the `-l` description enumerates columns)

- [ ] **Step 1: Update CLAUDE.md `--list` bullet**

Find the `- \`--list\` / \`-l\`:` bullet under "Key Behaviors". Update the color description: rows with equal versions are yellow; when versions differ the newer side's cell is green (via `sort -V`); a `DelReq` column (before `Created`) shows `✓` when the hint has a populated `DELREQUIRES`. Legend now reads `(yellow row = versions match; green = newer side)`.

- [ ] **Step 2: Add T60-T64 to the CLAUDE.md test table**

Append rows:

```
| T60 | `-l` hint newer than `.info` — HintVer cell green, row not yellow |
| T61 | `-l` `.info` newer than hint — SBOVer cell green |
| T62 | `-l` equal versions — whole row yellow, no green |
| T63 | `-l` hint with populated `DELREQUIRES` — `✓` in DelReq column |
| T64 | `-l` hint without `DELREQUIRES` — DelReq blank |
```

- [ ] **Step 3: Update README.md if needed**

Check the `-l` / `--list` section. If it describes the highlight behavior or columns, update it to mention directional green + the DelReq column. If README does not enumerate columns, no change.

Run: `grep -n 'list\|highlight\|HintVer' README.md`

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md README.md
git commit -S -m "docs: document -l directional color and DelReq column"
```

---

## Self-review notes

- Spec coverage: directional color (Task 1), equal→yellow kept (Task 1), DelReq column (Task 2), legend (Task 1), tests T60-T64 (Tasks 1-2), docs (Task 3). All covered.
- `MATCHED_PKGS` / `matched` only populated on the equal branch — preserves `-R` behavior.
- `sort -V` verified present and correct on target box (orders `1.10.0 > 1.2.3`, `2026_06_10 > 2026_06_02`).
- Color-byte alignment: version cells pre-padded to 22 before green wrap; DelReq via `_pad_glyph` for multibyte `✓`.
- Task 1 Step 4 note flags the date-column dependency between Task 1 and Task 2 so tasks stay runnable in order.
