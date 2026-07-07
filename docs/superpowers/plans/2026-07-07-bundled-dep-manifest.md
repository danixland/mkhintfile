# Bundled-dep Manifest Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reconcile a bundle package's extra `DOWNLOAD` lines against an upstream deps manifest (e.g. neovim's `cmake.deps/deps.txt`), opt-in per package, replacing the blind continuation-URL prompt for listed packages.

**Architecture:** New pure helpers in `mkhint` parse a `<pkg> <url-template>` config and a `NAME_URL/NAME_SHA256` manifest, match hint download lines to manifest entries (repo-path first, basename-stem fallback), and rewrite matched lines + recompute md5. A `--check` two-phase flow runs manifest reconcile after the primary bump, gated by `--force` when the primary is unchanged. `--new` reports only.

**Tech Stack:** bash, awk, perl (existing), pandoc for the man page. Tests via the existing mock harness in `tests/mkhint_test.sh` (mock dirs, fake `wget`, no network).

---

## Reference facts (read before starting)

- The spec is `docs/superpowers/specs/2026-07-07-bundled-dep-manifest-design.md`. Read it.
- The tool is a single bash file `mkhint`. Convention: single file, minimal deps, `set -e` at top (line 17).
- Phantom-dep block starts at `mkhint:338` (`# ── phantom-dep handling ──`). New helpers go **immediately after** the phantom-dep block (before `create_new_hint_file` at line ~423), in a `# ── bundled-dep manifest handling ──` block.
- `download_file <url>` (mkhint:319) downloads via `wget -O`, echoes the md5, deletes the temp. Non-zero on wget failure.
- `parse_multiline_var <var> <file>` (mkhint:595) prints one whitespace token per line for a `\`-continued hint variable. Reuse to read `DOWNLOAD` lines.
- `build_multiline_value <arrayname>` (mkhint:650) prints a quoted `\`-continued value from an array (nameref). Reuse to write `DOWNLOAD` back.
- The perl writeback idiom for a multiline var (mkhint:760):
  ```bash
  perl -i -0pe 'BEGIN{$v=shift} s|^DOWNLOAD="[^"]*(?:\\\n[^"]*)*"|DOWNLOAD="$v"|m' "$new_value" "$file"
  ```
- Test harness: `run_mkhint` (tests/mkhint_test.sh:193) sed-patches the path constants (`REPO_DIR`, `HINT_DIR`, `TMP_DIR`, `NVCHECKER_CONFIG`, `PHANTOM_DEPS_FILE`, `PACKAGES_DIR`, `MKHINT_CONFIG`) to mock dirs, then runs a copy. **It does NOT patch `BUNDLE_MANIFEST_FILE`** — a new sed line must be added (Task 1, Step included).
- Fake `wget` (tests/mkhint_test.sh:199) writes `FAKE_CONTENT_FOR_<url>` to the `-O` target. For manifest tests it must instead serve fixture `deps.txt` content when the URL is a manifest URL (Task 8 extends it).
- `_normalize_version` (mkhint:302) does `${1//-/_}`. Bug-1 dual-form sed lives in `update_hint_file` (mkhint:795) and `create_new_hint_file` (mkhint:~466).
- Colours/TTY: not relevant here; all reconcile output is plain text.
- Every commit is GPG-signed (`git commit -S`). Do not disable signing.
- After any `mkhint.1.md` edit, rebuild: `pandoc mkhint.1.md -s -t man -o mkhint.1 && gzip -9 -n -f mkhint.1`. Commit only `mkhint.1.gz` (the `.1` is gitignored).
- Run the whole suite with `bash tests/mkhint_test.sh`; it prints `Results: N passed, M failed` and exits non-zero on any failure.

---

## File structure

- **Modify `mkhint`:** add config var (Section 1), the manifest-handling helper block (Sections 2, 3, 4, 5), the `--force` flag in getopt + main, the `--new` hook, the `--check` Phase 2 wiring, the `--help` line.
- **Modify `mkhint.bash-completion`:** add `--force` to `all_flags`.
- **Modify `tests/mkhint_test.sh`:** extend fake wget for manifests, patch `BUNDLE_MANIFEST_FILE`, add unit + integration tests.
- **Create `bundle-manifests.example`** (repo root): commented sample config.
- **Modify docs:** `CLAUDE.md`, `mkhint.1.md` (+ rebuild `mkhint.1.gz`), `CHANGELOG.md`.

---

## Task 1: Config var + test-harness patch

**Files:**
- Modify: `mkhint` (after line 27, the `PHANTOM_DEPS_FILE` default)
- Modify: `tests/mkhint_test.sh:196-204` (the `run_mkhint` sed block)

- [ ] **Step 1: Add the config default in `mkhint`**

After the `PHANTOM_DEPS_FILE="$HOME/.config/mkhint/phantom-deps"` line (mkhint:27), add:

```bash
# Packages whose extra DOWNLOAD lines are driven by an upstream deps manifest
# (e.g. neovim's cmake.deps/deps.txt). One entry per line:
#   <pkgname> <deps-url-template-with-{VERSION}>
# Missing file = empty list = feature is a no-op.
BUNDLE_MANIFEST_FILE="$HOME/.config/mkhint/bundle-manifests"
```

- [ ] **Step 2: Patch `run_mkhint` so tests can point `BUNDLE_MANIFEST_FILE` at a mock file**

In `tests/mkhint_test.sh`, inside the `sed` in `run_mkhint` (after the `PHANTOM_DEPS_FILE` line, ~line 201), add another `-e`:

```bash
        -e "s|PHANTOM_DEPS_FILE=\".*\"|PHANTOM_DEPS_FILE=\"$MOCK_BASE/phantom-deps\"|" \
        -e "s|BUNDLE_MANIFEST_FILE=\".*\"|BUNDLE_MANIFEST_FILE=\"$MOCK_BASE/bundle-manifests\"|" \
```

- [ ] **Step 3: Verify syntax**

Run: `bash -n mkhint && echo OK`
Expected: `OK`

- [ ] **Step 4: Verify existing suite still green (no behavior change yet)**

Run: `bash tests/mkhint_test.sh 2>&1 | grep Results:`
Expected: `Results: 158 passed, 0 failed`

- [ ] **Step 5: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: add BUNDLE_MANIFEST_FILE config var

Opt-in per-package manifest for bundled-dep reconciliation. No behavior
yet; wires the config default and the test-harness path patch.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: `parse_manifest` helper

**Files:**
- Modify: `mkhint` (new `# ── bundled-dep manifest handling ──` block, inserted after the phantom-dep block, before `create_new_hint_file`)
- Modify: `tests/mkhint_test.sh` (before the SUMMARY block)

- [ ] **Step 1: Write the failing test**

Add before the `# ─── SUMMARY ───` block in `tests/mkhint_test.sh`:

```bash
# ── T-BM1: parse_manifest extracts URLs from NAME_URL/NAME_SHA256 pairs ──────
echo ""
echo "T-BM1: parse_manifest extracts URLs, ignores SHA256 lines"
cat > "$MOCK_BASE/deps.txt" << 'EOF'
LIBUV_URL https://github.com/libuv/libuv/archive/v1.52.1.tar.gz
LIBUV_SHA256 478baf2599bfbc
TREESITTER_URL https://github.com/tree-sitter/tree-sitter/archive/v0.26.7.tar.gz
TREESITTER_SHA256 4343107ad1097
EOF
bm_out=$(bash -c 'source <(sed -n "/# ── bundled-dep manifest handling/,/# ── end bundled-dep/p" '"$SCRIPT"'); parse_manifest '"$MOCK_BASE"'/deps.txt')
echo "$bm_out" | grep -qx 'https://github.com/libuv/libuv/archive/v1.52.1.tar.gz' \
    && echo "$bm_out" | grep -qx 'https://github.com/tree-sitter/tree-sitter/archive/v0.26.7.tar.gz' \
    && ! echo "$bm_out" | grep -q '478baf' \
    && { echo "  PASS: parse_manifest URLs only"; (( PASS++ )); } \
    || { echo "  FAIL: parse_manifest: $bm_out"; (( FAIL++ )); ERRORS+=("T-BM1"); }
```

Note: the test sources just the helper block (delimited by the block header and an `# ── end bundled-dep manifest handling ──` marker) so helpers can be exercised without running `main`. Task 2 Step 3 adds both markers.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM1|FAIL: parse'`
Expected: FAIL (block markers + `parse_manifest` don't exist yet)

- [ ] **Step 3: Add the block header, the helper, and the end marker in `mkhint`**

Insert immediately after the phantom-dep block ends (after `fix_current` closes at mkhint:~420, before `# Create new hint file`):

```bash
# ── bundled-dep manifest handling ─────────────────────────────────────────────
# Reconcile a bundle package's extra DOWNLOAD lines against an upstream deps
# manifest (opt-in via BUNDLE_MANIFEST_FILE). See docs spec 2026-07-07.

# parse_manifest <file> — print one download URL per line for each NAME_URL
# entry. SHA256 lines ignored (hints use MD5SUM; we re-download and md5).
parse_manifest() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    awk '/_URL[[:space:]]/ { print $2 }' "$file"
}
# ── end bundled-dep manifest handling ─────────────────────────────────────────
```

(Subsequent tasks insert their helpers **above** the end marker.)

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/mkhint_test.sh 2>&1 | grep 'T-BM1' -A1`
Expected: `PASS: parse_manifest URLs only`

- [ ] **Step 5: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: parse_manifest reads NAME_URL entries from a deps manifest

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `_url_stem` + `match_dep_url`

**Files:**
- Modify: `mkhint` (above the end marker)
- Modify: `tests/mkhint_test.sh` (before SUMMARY)

- [ ] **Step 1: Write the failing tests**

Add before SUMMARY:

```bash
# ── T-BM2: match_dep_url repo-path hit ───────────────────────────────────────
echo ""
echo "T-BM2: match_dep_url matches by owner/repo path"
BM_SRC='source <(sed -n "/# ── bundled-dep manifest handling/,/# ── end bundled-dep/p" '"$SCRIPT"')'
manifest_urls='https://github.com/tree-sitter/tree-sitter/archive/v0.26.8.tar.gz
https://github.com/luvit/luv/archive/1.53.0-0.tar.gz'
r=$(bash -c "$BM_SRC; match_dep_url 'https://github.com/tree-sitter/tree-sitter/archive/v0.26.7/tree-sitter-0.26.7.tar.gz' \"\$1\"" _ "$manifest_urls")
[[ "$r" == 'https://github.com/tree-sitter/tree-sitter/archive/v0.26.8.tar.gz' ]] \
    && { echo "  PASS: repo-path match"; (( PASS++ )); } \
    || { echo "  FAIL: repo-path match got '$r'"; (( FAIL++ )); ERRORS+=("T-BM2"); }

# ── T-BM3: match_dep_url stem fallback for blob host ─────────────────────────
echo ""
echo "T-BM3: match_dep_url stem fallback (neovim/deps/raw blob → lpeg)"
manifest_urls='https://github.com/neovim/deps/raw/deadbeef1234567/opt/lpeg-1.1.0.tar.gz'
r=$(bash -c "$BM_SRC; match_dep_url 'https://www.inf.puc-rio.br/~roberto/lpeg/lpeg-1.1.0.tar.gz' \"\$1\"" _ "$manifest_urls")
[[ "$r" == 'https://github.com/neovim/deps/raw/deadbeef1234567/opt/lpeg-1.1.0.tar.gz' ]] \
    && { echo "  PASS: stem fallback match"; (( PASS++ )); } \
    || { echo "  FAIL: stem fallback got '$r'"; (( FAIL++ )); ERRORS+=("T-BM3"); }

# ── T-BM4: match_dep_url no false prefix match ───────────────────────────────
echo ""
echo "T-BM4: match_dep_url does not match tree-sitter to tree-sitter-c"
manifest_urls='https://github.com/tree-sitter/tree-sitter-c/archive/v0.24.1.tar.gz'
r=$(bash -c "$BM_SRC; match_dep_url 'https://example.com/foo/tree-sitter-0.26.7.tar.gz' \"\$1\"" _ "$manifest_urls")
[[ -z "$r" ]] \
    && { echo "  PASS: no false prefix match"; (( PASS++ )); } \
    || { echo "  FAIL: false match got '$r'"; (( FAIL++ )); ERRORS+=("T-BM4"); }

# ── T-BM5: match_dep_url no match → empty ────────────────────────────────────
echo ""
echo "T-BM5: match_dep_url returns empty on no match"
manifest_urls='https://github.com/foo/bar/archive/v1.0.tar.gz'
r=$(bash -c "$BM_SRC; match_dep_url 'https://github.com/baz/qux/archive/v2.0.tar.gz' \"\$1\"" _ "$manifest_urls")
[[ -z "$r" ]] \
    && { echo "  PASS: empty on no match"; (( PASS++ )); } \
    || { echo "  FAIL: expected empty got '$r'"; (( FAIL++ )); ERRORS+=("T-BM5"); }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM[2345]'`
Expected: FAILs (`match_dep_url` undefined)

- [ ] **Step 3: Add `_url_stem` + `match_dep_url` above the end marker**

```bash
# _url_stem <url> — reduce a download URL's basename to a comparison stem:
# drop a trailing archive extension, then a trailing -<version> or the version
# is the whole tail after the name. Version = [vV]?[0-9]... or a 7+ hex sha.
_url_stem() {
    local base="${1##*/}"
    base="${base%.tar.gz}"; base="${base%.tar.xz}"; base="${base%.tar.bz2}"
    base="${base%.zip}"; base="${base%.tgz}"
    # strip a trailing -<version> (version starts with optional v then a digit,
    # or is a 7+ char hex sha)
    if [[ "$base" =~ ^(.+)-[vV]?[0-9].*$ ]]; then
        base="${BASH_REMATCH[1]}"
    elif [[ "$base" =~ ^(.+)-[0-9a-f]{7,}$ ]]; then
        base="${BASH_REMATCH[1]}"
    fi
    printf '%s\n' "$base"
}

# _url_repo <url> — echo owner/repo for a github URL, empty otherwise.
_url_repo() {
    [[ "$1" =~ github\.com/([^/]+)/([^/]+) ]] && printf '%s/%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
}

# match_dep_url <hint_url> <manifest_url_list> — echo the manifest URL that
# corresponds to hint_url, or nothing. Repo-path match first, then exact
# basename-stem fallback (for blob hosts where the repo path is ambiguous).
match_dep_url() {
    local hint_url="$1" list="$2"
    local hrepo; hrepo=$(_url_repo "$hint_url")
    local m mrepo
    # pass 1: repo-path (skip the shared-blob-host repo neovim/deps so a blob
    # URL never wins on repo path; it must match on stem instead)
    if [[ -n "$hrepo" && "$hrepo" != */deps ]]; then
        while IFS= read -r m; do
            [[ -z "$m" ]] && continue
            mrepo=$(_url_repo "$m")
            if [[ -n "$mrepo" && "$mrepo" != */deps && "$mrepo" == "$hrepo" ]]; then
                printf '%s\n' "$m"; return 0
            fi
        done <<< "$list"
    fi
    # pass 2: exact stem
    local hstem; hstem=$(_url_stem "$hint_url")
    while IFS= read -r m; do
        [[ -z "$m" ]] && continue
        [[ "$(_url_stem "$m")" == "$hstem" ]] && { printf '%s\n' "$m"; return 0; }
    done <<< "$list"
    return 1
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM[2345]' -A1 | grep -E 'PASS|FAIL'`
Expected: four `PASS` lines

- [ ] **Step 5: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: match_dep_url maps a hint download line to a manifest URL

Repo-path match first, exact basename-stem fallback for blob hosts. Blob
host repo (owner/deps) is excluded from repo-path matching so it resolves
by stem.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: config loader + URL templater

**Files:**
- Modify: `mkhint` (above the end marker)
- Modify: `tests/mkhint_test.sh` (before SUMMARY)

- [ ] **Step 1: Write the failing tests**

```bash
# ── T-BM6: load_bundle_manifests + manifest_url_for ──────────────────────────
echo ""
echo "T-BM6: manifest_url_for substitutes {VERSION}, unlisted pkg → non-zero"
cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
# comment
neovim  https://example.com/neovim/v{VERSION}/deps.txt
EOF
BM_SRC='source <(sed -n "/# ── bundled-dep manifest handling/,/# ── end bundled-dep/p" '"$SCRIPT"')'
r=$(bash -c "BUNDLE_MANIFEST_FILE='$MOCK_BASE/bundle-manifests'; $BM_SRC; load_bundle_manifests; manifest_url_for neovim 0.13.0")
[[ "$r" == 'https://example.com/neovim/v0.13.0/deps.txt' ]] \
    && { echo "  PASS: templated URL"; (( PASS++ )); } \
    || { echo "  FAIL: templated URL got '$r'"; (( FAIL++ )); ERRORS+=("T-BM6a"); }
bash -c "BUNDLE_MANIFEST_FILE='$MOCK_BASE/bundle-manifests'; $BM_SRC; load_bundle_manifests; manifest_url_for curl 8.0" >/dev/null 2>&1
[[ $? -ne 0 ]] \
    && { echo "  PASS: unlisted pkg non-zero"; (( PASS++ )); } \
    || { echo "  FAIL: unlisted pkg should be non-zero"; (( FAIL++ )); ERRORS+=("T-BM6b"); }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM6'`
Expected: FAIL (loader undefined)

- [ ] **Step 3: Add loader + templater above the end marker**

```bash
# Loaded map: pkg name -> URL template. Populated by load_bundle_manifests.
declare -A BUNDLE_MANIFESTS=()
load_bundle_manifests() {
    BUNDLE_MANIFESTS=()
    [[ -f "$BUNDLE_MANIFEST_FILE" ]] || return 0
    local line pkg url
    while IFS= read -r line; do
        line="${line%%#*}"
        [[ -z "${line// }" ]] && continue
        read -r pkg url <<< "$line"
        [[ -n "$pkg" && -n "$url" ]] && BUNDLE_MANIFESTS["$pkg"]="$url"
    done < "$BUNDLE_MANIFEST_FILE"
}

# manifest_url_for <pkg> <version> — echo the manifest URL for pkg with
# {VERSION} substituted. Non-zero if pkg is not listed.
manifest_url_for() {
    local pkg="$1" ver="$2"
    local tmpl="${BUNDLE_MANIFESTS[$pkg]:-}"
    [[ -z "$tmpl" ]] && return 1
    printf '%s\n' "${tmpl//\{VERSION\}/$ver}"
}

# True if pkg has a bundle manifest configured.
pkg_has_manifest() {
    [[ -n "${BUNDLE_MANIFESTS[$1]:-}" ]]
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM6' -A1 | grep -E 'PASS|FAIL'`
Expected: two `PASS`

- [ ] **Step 5: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: load_bundle_manifests + manifest_url_for

Parse the pkg->url-template config and substitute {VERSION}.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `fetch_manifest` with dual-form retry

**Files:**
- Modify: `mkhint` (above the end marker)
- Modify: `tests/mkhint_test.sh` (extend fake wget first — see note; then add test)

- [ ] **Step 1: Extend the fake wget to serve manifest fixtures**

In `tests/mkhint_test.sh` `mock_wget` (line 199), replace the body so a URL containing `deps.txt` serves the fixture file `$MOCK_BASE/manifest_fixture` (if it exists), else the old FAKE_CONTENT behavior:

```bash
    cat > "$MOCK_BASE/bin/wget" << EOF
#!/bin/bash
url=""
out=""
while [[ \$# -gt 0 ]]; do
    case "\$1" in
        -O) out="\$2"; shift 2 ;;
        *) url="\$1"; shift ;;
    esac
done
if [[ "\$url" == *deps.txt* && -f "$MOCK_BASE/manifest_fixture" ]]; then
    cat "$MOCK_BASE/manifest_fixture" > "\$out"
elif [[ "\$url" == *deps.txt* ]]; then
    exit 1   # simulate manifest fetch failure when no fixture set
else
    echo "FAKE_CONTENT_FOR_\${url}" > "\$out"
fi
exit 0
EOF
```

(Note: this is a `EOF` without quotes now so `$MOCK_BASE` expands; the inner `\$` escapes stay literal. Verify the heredoc still writes a valid script.)

- [ ] **Step 2: Write the failing test**

```bash
# ── T-BM7: fetch_manifest downloads to a temp file ───────────────────────────
echo ""
echo "T-BM7: fetch_manifest returns a path with the fixture content"
cat > "$MOCK_BASE/manifest_fixture" << 'EOF'
LIBUV_URL https://github.com/libuv/libuv/archive/v1.52.1.tar.gz
LIBUV_SHA256 abc
EOF
BM_SRC='source <(sed -n "/# ── bundled-dep manifest handling/,/# ── end bundled-dep/p" '"$SCRIPT"')'
mpath=$(bash -c "TMP_DIR='$MOCK_TMP'; PATH='$MOCK_BASE/bin:\$PATH'; $BM_SRC; fetch_manifest 'https://example.com/v1/deps.txt'")
[[ -f "$mpath" ]] && grep -q 'LIBUV_URL' "$mpath" \
    && { echo "  PASS: fetch_manifest content"; (( PASS++ )); } \
    || { echo "  FAIL: fetch_manifest path='$mpath'"; (( FAIL++ )); ERRORS+=("T-BM7"); }
rm -f "$MOCK_BASE/manifest_fixture"
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM7'`
Expected: FAIL (`fetch_manifest` undefined)

- [ ] **Step 4: Add `fetch_manifest` above the end marker**

```bash
# fetch_manifest <url> — download the manifest to a temp file, echo its path.
# Non-zero on wget failure. Caller cleans up (path is under TMP_DIR).
fetch_manifest() {
    local url="$1"
    local out="${TMP_DIR}/manifest"
    rm -f "$out"
    wget -O "$out" "$url" >&2 || return 1
    [[ -s "$out" ]] || return 1
    printf '%s\n' "$out"
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM7' -A1 | grep -E 'PASS|FAIL'`
Expected: `PASS`

- [ ] **Step 6: Verify full suite still green**

Run: `bash tests/mkhint_test.sh 2>&1 | grep Results:`
Expected: all passed, 0 failed (the fake-wget change must not break existing download tests — if any fail, the heredoc escaping is wrong)

- [ ] **Step 7: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: fetch_manifest + fake-wget manifest fixture support

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: `reconcile_bundle_deps` — the core

This helper reads a hint's `DOWNLOAD` lines, matches each against a manifest, and for a given mode either **reports** (no write) or **applies** (rewrite matched changed lines + recompute md5). It also prints the manifest-only-deps FYI.

**Files:**
- Modify: `mkhint` (above the end marker)
- Modify: `tests/mkhint_test.sh` (before SUMMARY)

- [ ] **Step 1: Write the failing tests**

```bash
# ── T-BM8: reconcile report mode leaves the hint unchanged ───────────────────
echo ""
echo "T-BM8: reconcile_bundle_deps report mode: prints, does not rewrite"
cat > "$MOCK_BASE/manifest_fixture" << 'EOF'
NVIM_URL https://github.com/neovim/neovim/archive/v0.13.0.tar.gz
NVIM_SHA256 a
TREESITTER_URL https://github.com/tree-sitter/tree-sitter/archive/v0.26.8.tar.gz
TREESITTER_SHA256 b
WASMTIME_URL https://github.com/bytecodealliance/wasmtime/archive/v36.0.6.tar.gz
WASMTIME_SHA256 c
EOF
cat > "$MOCK_HINT/nvim.hint" << 'EOF'
VERSION="0.13.0"
DOWNLOAD="https://github.com/neovim/neovim/archive/v0.13.0/neovim-0.13.0.tar.gz \
    https://github.com/tree-sitter/tree-sitter/archive/v0.26.7/tree-sitter-0.26.7.tar.gz"
MD5SUM="aaa \
    bbb"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
ARCH="x86_64"
EOF
cp "$MOCK_HINT/nvim.hint" "$MOCK_BASE/nvim.before"
BM_SRC='source <(sed -n "/# ── bundled-dep manifest handling/,/# ── end bundled-dep/p" '"$SCRIPT"')'
rep=$(bash -c "TMP_DIR='$MOCK_TMP'; PATH='$MOCK_BASE/bin:\$PATH'; source '$SCRIPT' 2>/dev/null; reconcile_bundle_deps nvim '$MOCK_HINT/nvim.hint' 'https://x/deps.txt' report" 2>&1) || true
# report mentions the changed dep and the wasmtime FYI, hint unchanged
echo "$rep" | grep -q 'tree-sitter' \
    && echo "$rep" | grep -q 'wasmtime' \
    && diff -q "$MOCK_HINT/nvim.hint" "$MOCK_BASE/nvim.before" >/dev/null \
    && { echo "  PASS: report mode no rewrite"; (( PASS++ )); } \
    || { echo "  FAIL: report mode. out=$rep"; (( FAIL++ )); ERRORS+=("T-BM8"); }

# ── T-BM9: reconcile apply mode rewrites the changed dep + recomputes md5 ─────
echo ""
echo "T-BM9: reconcile_bundle_deps apply mode rewrites tree-sitter to v0.26.8"
bash -c "TMP_DIR='$MOCK_TMP'; PATH='$MOCK_BASE/bin:\$PATH'; source '$SCRIPT' 2>/dev/null; reconcile_bundle_deps nvim '$MOCK_HINT/nvim.hint' 'https://x/deps.txt' apply" >/dev/null 2>&1
grep -q 'tree-sitter/archive/v0.26.8' "$MOCK_HINT/nvim.hint" \
    && ! grep -q 'v0.26.7' "$MOCK_HINT/nvim.hint" \
    && ! grep -q 'bbb' "$MOCK_HINT/nvim.hint" \
    && grep -q 'neovim-0.13.0' "$MOCK_HINT/nvim.hint" \
    && { echo "  PASS: apply rewrote dep + md5, primary line untouched"; (( PASS++ )); } \
    || { echo "  FAIL: apply mode:"; cat "$MOCK_HINT/nvim.hint"; (( FAIL++ )); ERRORS+=("T-BM9"); }
rm -f "$MOCK_BASE/manifest_fixture"
```

Note: these tests `source "$SCRIPT"` whole (guarded `2>/dev/null`); `main "$@"` runs at the bottom with no args, harmlessly (`getopt` with nothing → falls through, no command). If sourcing triggers unwanted output/exit, wrap the source: the tests already `|| true` and redirect. Confirm during Step 2.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM[89]'`
Expected: FAIL (`reconcile_bundle_deps` undefined)

- [ ] **Step 3: Implement `reconcile_bundle_deps` above the end marker**

```bash
# reconcile_bundle_deps <pkg> <hintfile> <manifest_url> <mode>
# mode = report (print only) | apply (rewrite matched changed lines + md5).
# Reconciles the DOWNLOAD line's extra URLs (index >= 1) against the manifest.
# The primary URL (index 0) is never touched here. Guarded for set -e.
reconcile_bundle_deps() {
    local pkg="$1" hint="$2" murl="$3" mode="$4"

    local mfile
    if ! mfile=$(fetch_manifest "$murl"); then
        echo "  $pkg: manifest unavailable ($murl) — bundled deps left as-is (retry with --force)"
        return 0
    fi
    local -a manifest_urls
    mapfile -t manifest_urls < <(parse_manifest "$mfile")
    rm -f "$mfile"
    if [[ ${#manifest_urls[@]} -eq 0 ]]; then
        echo "  $pkg: manifest empty/unrecognized — bundled deps left as-is"
        return 0
    fi
    local mlist; printf -v mlist '%s\n' "${manifest_urls[@]}"

    local -a urls
    mapfile -t urls < <(parse_multiline_var "DOWNLOAD" "$hint")
    (( ${#urls[@]} <= 1 )) && { echo "  $pkg: no bundled deps in DOWNLOAD"; return 0; }
    local -a md5s
    mapfile -t md5s < <(parse_multiline_var "MD5SUM" "$hint")

    # Track which manifest URLs got matched (for the FYI of unmatched ones).
    local -A matched_manifest=()
    local -a new_urls=("${urls[@]}")
    local -a changed_idx=() changed_from=() changed_to=()
    local i m
    for (( i=1; i<${#urls[@]}; i++ )); do
        m=$(match_dep_url "${urls[$i]}" "$mlist") || m=""
        if [[ -z "$m" ]]; then
            echo "  $pkg: $(_url_stem "${urls[$i]}") — no manifest match (left as-is)"
            continue
        fi
        matched_manifest["$m"]=1
        if [[ "$m" != "${urls[$i]}" ]]; then
            changed_idx+=("$i"); changed_from+=("${urls[$i]}"); changed_to+=("$m")
            new_urls[$i]="$m"
        fi
    done

    # Manifest-only deps FYI (manifest URLs never matched by any hint line).
    local -a extra=()
    for m in "${manifest_urls[@]}"; do
        [[ -z "${matched_manifest[$m]:-}" ]] && extra+=("$(_url_stem "$m")")
    done
    if [[ ${#extra[@]} -gt 0 ]]; then
        echo "$pkg: manifest has ${#extra[@]} deps not in hint:"
        printf '%s\n' "${extra[@]}"
    fi

    if [[ ${#changed_idx[@]} -eq 0 ]]; then
        echo "  $pkg: bundled deps all current"
        return 0
    fi

    echo ""
    echo "$pkg bundled deps changed upstream:"
    for (( i=0; i<${#changed_idx[@]}; i++ )); do
        printf '  %s  ->  %s\n' "$(_url_stem "${changed_from[$i]}")" "$(_url_stem "${changed_to[$i]}")"
    done

    [[ "$mode" == report ]] && return 0

    # apply mode: recompute md5 only for changed lines, rewrite DOWNLOAD+MD5SUM.
    local -a new_md5s=("${md5s[@]}")
    local idx md5
    for idx in "${changed_idx[@]}"; do
        echo "Downloading (bundled): ${new_urls[$idx]}"
        if md5=$(download_file "${new_urls[$idx]}"); then
            new_md5s[$idx]="$md5"
        else
            echo "  download failed for ${new_urls[$idx]} — left as-is"
            new_urls[$idx]="${urls[$idx]}"   # revert this line
        fi
    done

    local new_dl new_md5
    new_dl=$(build_multiline_value new_urls);  new_dl="${new_dl#\"}";  new_dl="${new_dl%\"}"
    new_md5=$(build_multiline_value new_md5s);  new_md5="${new_md5#\"}"; new_md5="${new_md5%\"}"
    perl -i -0pe 'BEGIN{$v=shift} s|^DOWNLOAD="[^"]*(?:\\\n[^"]*)*"|DOWNLOAD="$v"|m' "$new_dl" "$hint"
    perl -i -0pe 'BEGIN{$v=shift} s|^MD5SUM="[^"]*(?:\\\n[^"]*)*"|MD5SUM="$v"|m' "$new_md5" "$hint"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM[89]' -A1 | grep -E 'PASS|FAIL'`
Expected: two `PASS`

- [ ] **Step 5: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: reconcile_bundle_deps core (report/apply)

Match each extra DOWNLOAD line to the manifest, rewrite changed lines and
recompute their md5 in apply mode, report only in report mode, and print
the manifest-only-deps FYI. Primary line untouched.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: `--new` hook (report mode)

**Files:**
- Modify: `mkhint` `create_new_hint_file` (after the hint is generated, near mkhint:474 `echo "generated ..."`)
- Modify: `tests/mkhint_test.sh` (before SUMMARY)

- [ ] **Step 1: Write the failing tests**

Requires a `datedpkg`-style `.info` fixture for a listed package. Reuse a github `.info`. Add a `bmnvim` package fixture in `setup()` and list it. First, in `setup()` add the dir to the `mkdir -p` list: `"$MOCK_REPO/editors/bmnvim"`. Then add the `.info`:

```bash
    cat > "$MOCK_REPO/editors/bmnvim/bmnvim.info" << 'EOF'
PRGNAM="bmnvim"
VERSION="0.13.0"
HOMEPAGE="https://neovim.io"
DOWNLOAD="https://github.com/neovim/neovim/archive/v0.13.0/bmnvim-0.13.0.tar.gz \
          https://github.com/tree-sitter/tree-sitter/archive/v0.26.7/tree-sitter-0.26.7.tar.gz"
MD5SUM="aaa \
        bbb"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
REQUIRES=""
MAINTAINER="Test"
EMAIL="test@test.com"
EOF
```

Test:

```bash
# ── T-BM10: --new listed pkg prints reconcile report, does NOT rewrite ───────
echo ""
echo "T-BM10: --new listed pkg → manifest report, hint not rewritten by manifest"
cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
bmnvim  https://example.com/bmnvim/v{VERSION}/deps.txt
EOF
cat > "$MOCK_BASE/manifest_fixture" << 'EOF'
NVIM_URL https://github.com/neovim/neovim/archive/v0.13.0.tar.gz
NVIM_SHA256 a
TREESITTER_URL https://github.com/tree-sitter/tree-sitter/archive/v0.26.8.tar.gz
TREESITTER_SHA256 b
EOF
rm -f "$MOCK_HINT/bmnvim.hint"
out=$(run_mkhint -n bmnvim 2>&1)
echo "$out" | grep -qi 'tree-sitter' \
    && grep -q 'v0.26.7' "$MOCK_HINT/bmnvim.hint" \
    && { echo "  PASS: --new reported, kept .info dep version"; (( PASS++ )); } \
    || { echo "  FAIL: --new manifest report. out=$out"; (( FAIL++ )); ERRORS+=("T-BM10"); }

# ── T-BM11: --new non-listed pkg runs no manifest code ───────────────────────
echo ""
echo "T-BM11: --new non-listed pkg → no manifest output"
: > "$MOCK_BASE/bundle-manifests"
rm -f "$MOCK_HINT/curl.hint"
out=$(run_mkhint -n curl 2>&1)
echo "$out" | grep -qi 'manifest' \
    && { echo "  FAIL: unexpected manifest output for curl"; (( FAIL++ )); ERRORS+=("T-BM11"); } \
    || { echo "  PASS: no manifest code for non-listed"; (( PASS++ )); }
rm -f "$MOCK_BASE/manifest_fixture" "$MOCK_BASE/bundle-manifests"
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM1[01]'`
Expected: T-BM10 FAILs (no report yet); T-BM11 may pass already.

- [ ] **Step 3: Add the hook in `create_new_hint_file`**

After the `echo "Check variables before using."` / before `add_nvchecker_section` call (mkhint:~475), add:

```bash
            load_bundle_manifests
            if pkg_has_manifest "${normalized_file%.hint}"; then
                local _bm_ver; _bm_ver=$(grep '^VERSION=' "$normalized_file" | sed 's/VERSION="//;s/"$//')
                local _bm_url; _bm_url=$(manifest_url_for "${normalized_file%.hint}" "$_bm_ver")
                echo "$( "${normalized_file%.hint}" )" >/dev/null 2>&1 || true  # no-op guard
                echo "${normalized_file%.hint}: bundled-dep manifest check"
                reconcile_bundle_deps "${normalized_file%.hint}" "$normalized_file" "$_bm_url" report || true
            fi
```

Remove the stray no-op guard line if it complicates; the essential calls are `load_bundle_manifests`, `pkg_has_manifest`, `manifest_url_for`, `reconcile_bundle_deps ... report`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM1[01]' -A1 | grep -E 'PASS|FAIL'`
Expected: two `PASS`

- [ ] **Step 5: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: --new prints a manifest reconcile report for listed packages

Report-only at creation time; the .info version is kept, upstream
disagreement is flagged.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: `--force` flag plumbing

**Files:**
- Modify: `mkhint` main getopt (line 1028-1029), the option loop, the mutual-exclusion checks, and a `FORCE` var near the other flag vars (mkhint:44-55)
- Modify: `tests/mkhint_test.sh` (before SUMMARY)

- [ ] **Step 1: Write the failing test (mutual exclusion)**

```bash
# ── T-BM12: --force with --hintfile → exit 1 ─────────────────────────────────
echo ""
echo "T-BM12: --force is --check-only (errors with --hintfile/--new/--fix-current)"
set +e
run_mkhint --force -f curl -V 1.0 >/dev/null 2>&1; c1=$?
run_mkhint --force -n curl >/dev/null 2>&1; c2=$?
run_mkhint --force -F >/dev/null 2>&1; c3=$?
set -e
[[ $c1 -eq 1 && $c2 -eq 1 && $c3 -eq 1 ]] \
    && { echo "  PASS: --force mutually exclusive"; (( PASS++ )); } \
    || { echo "  FAIL: exits $c1 $c2 $c3"; (( FAIL++ )); ERRORS+=("T-BM12"); }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM12'`
Expected: FAIL (`--force` unknown option → getopt error, likely exit 1 already for wrong reason; the test still meaningfully drives the flag once added)

- [ ] **Step 3: Add `FORCE=0` var**

After `NO_DL=0` (mkhint:55), add:

```bash
FORCE=0
```

- [ ] **Step 4: Add `--force` to getopt and the option loop**

Change the getopt long list (mkhint:1029) to append `,force`:

```bash
    parsed=$(getopt -o vV:f:n:lcCdNhRF \
        --long version,set-version:,hintfile:,new:,list,clean,check,delete,no-dl,help,review,fix-current,force \
        -n 'mkhint' -- "$@") || { show_help; exit 1; }
```

Add a case in the option loop (after the `--no-dl|-N)` case, mkhint:~1065):

```bash
            --force)
                FORCE=1
                shift
                ;;
```

- [ ] **Step 5: Add mutual-exclusion check**

After the existing `--fix-current` mutual-exclusion block (mkhint:~1120), add:

```bash
    if [[ $FORCE -eq 1 && "$COMMAND" != "check" ]]; then
        echo "Error: --force is only valid with --check" >&2
        exit 1
    fi
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM12' -A1 | grep -E 'PASS|FAIL'`
Expected: `PASS`

- [ ] **Step 7: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: add --force flag (check-only, mutually exclusive elsewhere)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: `--check` Phase 2 wiring

Wire the reconcile into `check_updates`: after the primary-update loop, for each listed target run Phase 2 in **apply** mode when the primary bumped this run OR `--force`; else skip.

**Files:**
- Modify: `mkhint` `check_updates` (add a Phase 2 section after the `updated=()` slackrepo block, mkhint:~1012; and thread `FORCE` in)
- Modify: `tests/mkhint_test.sh` (before SUMMARY)

- [ ] **Step 1: Write the failing tests**

```bash
# ── T-BM13..17: --check Phase 2 behaviors ────────────────────────────────────
# Shared fixtures: bmnvim listed, hint present, nvchecker seeded.
setup_bmnvim_check() {
    cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
bmnvim  https://example.com/bmnvim/v{VERSION}/deps.txt
EOF
    cat > "$MOCK_BASE/manifest_fixture" << 'EOF'
NVIM_URL https://github.com/neovim/neovim/archive/v0.13.0.tar.gz
NVIM_SHA256 a
TREESITTER_URL https://github.com/tree-sitter/tree-sitter/archive/v0.26.8.tar.gz
TREESITTER_SHA256 b
EOF
    cat > "$MOCK_HINT/bmnvim.hint" << 'EOF'
VERSION="0.13.0"
DOWNLOAD="https://github.com/neovim/neovim/archive/v0.13.0/bmnvim-0.13.0.tar.gz \
    https://github.com/tree-sitter/tree-sitter/archive/v0.26.7/tree-sitter-0.26.7.tar.gz"
MD5SUM="aaa \
    bbb"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
ARCH="x86_64"
EOF
    # nvchecker keyfile says bmnvim latest == current (0.13.0) → primary unchanged
    cat > "$MOCK_BASE/nvchecker_keyfile.json" << 'EOF'
{"version":2,"data":{"bmnvim":{"version":"0.13.0"}}}
EOF
}

# T-BM13: primary unchanged, no --force → Phase 2 skipped (dep stays v0.26.7)
echo ""
echo "T-BM13: --check listed, primary current, no --force → deps untouched"
setup_bmnvim_check
run_mkhint -C bmnvim < <(printf 'n\n') >/dev/null 2>&1
grep -q 'v0.26.7' "$MOCK_HINT/bmnvim.hint" \
    && { echo "  PASS: Phase 2 skipped"; (( PASS++ )); } \
    || { echo "  FAIL: dep changed without --force"; (( FAIL++ )); ERRORS+=("T-BM13"); }

# T-BM14: primary unchanged, --force → Phase 2 runs, dep bumped on Y
echo ""
echo "T-BM14: --check --force listed, primary current → deps reconciled"
setup_bmnvim_check
run_mkhint -C --force bmnvim < <(printf 'Y\n') >/dev/null 2>&1
grep -q 'tree-sitter/archive/v0.26.8' "$MOCK_HINT/bmnvim.hint" \
    && { echo "  PASS: --force ran Phase 2"; (( PASS++ )); } \
    || { echo "  FAIL: --force did not bump dep"; cat "$MOCK_HINT/bmnvim.hint"; (( FAIL++ )); ERRORS+=("T-BM14"); }

# T-BM15: manifest fetch fails → primary stands, deps unchanged, retry msg
echo ""
echo "T-BM15: --check --force, manifest fetch fails → deps unchanged"
setup_bmnvim_check
rm -f "$MOCK_BASE/manifest_fixture"   # fake wget returns exit 1 for deps.txt
out=$(run_mkhint -C --force bmnvim < <(printf 'Y\n') 2>&1)
grep -q 'v0.26.7' "$MOCK_HINT/bmnvim.hint" && echo "$out" | grep -qi 'manifest unavailable' \
    && { echo "  PASS: fetch fail handled"; (( PASS++ )); } \
    || { echo "  FAIL: fetch fail. out=$out"; (( FAIL++ )); ERRORS+=("T-BM15"); }

# T-BM16: manifest-only deps FYI printed
echo ""
echo "T-BM16: --check --force prints manifest-only-deps FYI"
setup_bmnvim_check
cat > "$MOCK_BASE/manifest_fixture" << 'EOF'
NVIM_URL https://github.com/neovim/neovim/archive/v0.13.0.tar.gz
NVIM_SHA256 a
TREESITTER_URL https://github.com/tree-sitter/tree-sitter/archive/v0.26.7.tar.gz
TREESITTER_SHA256 b
WASMTIME_URL https://github.com/bytecodealliance/wasmtime/archive/v36.0.6.tar.gz
WASMTIME_SHA256 c
EOF
out=$(run_mkhint -C --force bmnvim < <(printf 'n\n') 2>&1)
echo "$out" | grep -q 'deps not in hint:' && echo "$out" | grep -q '^wasmtime' \
    && { echo "  PASS: FYI list printed"; (( PASS++ )); } \
    || { echo "  FAIL: FYI. out=$out"; (( FAIL++ )); ERRORS+=("T-BM16"); }
rm -f "$MOCK_BASE/manifest_fixture" "$MOCK_BASE/bundle-manifests" "$MOCK_HINT/bmnvim.hint"
```

Note on the nvchecker keyfile: `check_updates` reads the keyfile path from `NVCHECKER_CONFIG`'s `[__config__] newver`. The existing suite already seeds a mock `nvchecker.toml` + keyfile (see the `--check` tests near T23). Match that setup — reuse whatever the existing `--check` tests use to seed a keyfile/toml, adapting the JSON path to `$MOCK_BASE/nvchecker_keyfile.json`. If the existing tests use a different keyfile filename or a `newver` path, mirror that exactly instead of introducing a new file.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM1[3-6]'`
Expected: FAILs (Phase 2 not wired)

- [ ] **Step 3: Wire Phase 2 into `check_updates`**

`check_updates` (mkhint:901) currently ends after the slackrepo split (mkhint:~1012). It also needs to know which packages bumped their primary this run (the `updated` array already tracks that) and honor `FORCE`. Insert **before** the final `}` of `check_updates`, after the slackrepo block:

```bash
    # Phase 2: bundled-dep manifest reconcile for listed packages.
    load_bundle_manifests
    local was_updated
    for pkg in "${targets[@]}"; do
        pkg_has_manifest "$pkg" || continue
        local hintpath="${HINT_DIR%/}/${pkg}.hint"
        [[ -f "$hintpath" ]] || continue
        was_updated=0
        local u
        for u in "${updated[@]}"; do [[ "$u" == "$pkg" ]] && was_updated=1; done
        if [[ $was_updated -eq 0 && $FORCE -ne 1 ]]; then
            continue   # primary unchanged and not forced → skip Phase 2
        fi
        local cur; cur=$(grep '^VERSION=' "$hintpath" | sed 's/VERSION="//;s/"$//')
        local murl; murl=$(manifest_url_for "$pkg" "$cur") || continue
        echo ""
        echo "Bundled-dep reconcile: $pkg (manifest @ $cur)"
        # report first, then confirm apply
        reconcile_bundle_deps "$pkg" "$hintpath" "$murl" report || true
        local ans
        read -r -p "Apply bundled-dep updates for $pkg? [Y/n] " ans
        ans="${ans:-Y}"
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            reconcile_bundle_deps "$pkg" "$hintpath" "$murl" apply || true
        fi
    done
```

Note: `reconcile_bundle_deps` is called twice (report, then apply) — it fetches the manifest each time. That is one extra small GET; acceptable (ponytail: refetch, cache to a per-run temp if it ever matters). Alternatively fold report+confirm+apply into a single `interactive` mode. Keep the two-call form for now; it reuses the mode param cleanly.

`targets` and `updated` are already locals in `check_updates`; `FORCE` is a global set in `main`. `pkg` is reused as the loop var (already declared local earlier in the function — reuse is fine).

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM1[3-6]' -A1 | grep -E 'PASS|FAIL'`
Expected: four `PASS`

- [ ] **Step 5: Verify whole suite**

Run: `bash tests/mkhint_test.sh 2>&1 | grep Results:`
Expected: all passed, 0 failed

- [ ] **Step 6: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: --check Phase 2 reconciles bundled deps for listed packages

Runs after the primary bump; auto when the primary changed this run,
otherwise only with --force. Report then per-package apply confirm.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9b: `--hintfile -V` parity (reconcile on the update path)

The `update` command (mkhint:1166-1178) bumps a single hint via `update_hint_file` then `prompt_slackrepo`. For a **listed** package it must also run Phase 2 (apply) after the primary bump, so `mkhint -f neovim -V 0.13.0` reconciles bundled deps too. The old `prompt_continuation_urls` inside `update_hint_file` still fires for listed packages during the primary bump — that is acceptable: the extra lines it prompts for are then corrected by Phase 2. (Follow-up could suppress the prompt for listed packages; not required now.)

**Files:**
- Modify: `mkhint` `main` `update)` case (mkhint:1166-1178)
- Modify: `tests/mkhint_test.sh` (before SUMMARY)

- [ ] **Step 1: Write the failing test**

```bash
# ── T-BM18: --hintfile -V on a listed pkg reconciles bundled deps ────────────
echo ""
echo "T-BM18: -f listed pkg -V bumps primary AND reconciles bundled deps"
cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
bmnvim  https://example.com/bmnvim/v{VERSION}/deps.txt
EOF
cat > "$MOCK_BASE/manifest_fixture" << 'EOF'
NVIM_URL https://github.com/neovim/neovim/archive/v0.14.0.tar.gz
NVIM_SHA256 a
TREESITTER_URL https://github.com/tree-sitter/tree-sitter/archive/v0.26.8.tar.gz
TREESITTER_SHA256 b
EOF
cat > "$MOCK_HINT/bmnvim.hint" << 'EOF'
VERSION="0.13.0"
DOWNLOAD="https://github.com/neovim/neovim/archive/v0.13.0/bmnvim-0.13.0.tar.gz \
    https://github.com/tree-sitter/tree-sitter/archive/v0.26.7/tree-sitter-0.26.7.tar.gz"
MD5SUM="aaa \
    bbb"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
ARCH="x86_64"
EOF
# stdin: (continuation prompt for the primary bump: keep) then (apply Y) then (slackrepo n)
run_mkhint -f bmnvim -V 0.14.0 < <(printf '\nY\nn\n') >/dev/null 2>&1
grep -q 'VERSION="0.14.0"' "$MOCK_HINT/bmnvim.hint" \
    && grep -q 'tree-sitter/archive/v0.26.8' "$MOCK_HINT/bmnvim.hint" \
    && { echo "  PASS: -f -V bumped primary + reconciled deps"; (( PASS++ )); } \
    || { echo "  FAIL: -f -V parity:"; cat "$MOCK_HINT/bmnvim.hint"; (( FAIL++ )); ERRORS+=("T-BM18"); }
rm -f "$MOCK_BASE/manifest_fixture" "$MOCK_BASE/bundle-manifests" "$MOCK_HINT/bmnvim.hint"
```

Note: the exact stdin sequence depends on how many continuation URLs `update_hint_file`'s `prompt_continuation_urls` asks about (one extra line here → one blank "keep"). If the run consumes prompts differently, adjust the `printf` sequence so: blank-lines cover each continuation-URL keep, then `Y` for the reconcile apply, then `n` for slackrepo. Verify against the actual prompt order in Step 3.

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM18'`
Expected: FAIL (dep stays v0.26.7 — no Phase 2 on the update path)

- [ ] **Step 3: Add the reconcile block to the `update)` case**

In `main`, the `update)` case (mkhint:1166) currently ends with `prompt_slackrepo "$HINT_FILE"`. Insert **before** `prompt_slackrepo`, after the `update_hint_file` / `nvtake` lines:

```bash
            load_bundle_manifests
            _bm_pkg="${HINT_FILE%.hint}"
            if pkg_has_manifest "$_bm_pkg"; then
                _bm_hint="${HINT_DIR%/}/${_bm_pkg}.hint"
                _bm_cur=$(grep '^VERSION=' "$_bm_hint" | sed 's/VERSION="//;s/"$//')
                _bm_url=$(manifest_url_for "$_bm_pkg" "$_bm_cur")
                echo ""
                echo "Bundled-dep reconcile: $_bm_pkg (manifest @ $_bm_cur)"
                reconcile_bundle_deps "$_bm_pkg" "$_bm_hint" "$_bm_url" report || true
                read -r -p "Apply bundled-dep updates for $_bm_pkg? [Y/n] " _bm_ans
                _bm_ans="${_bm_ans:-Y}"
                if [[ "$_bm_ans" =~ ^[Yy]$ ]]; then
                    reconcile_bundle_deps "$_bm_pkg" "$_bm_hint" "$_bm_url" apply || true
                fi
            fi
```

(`HINT_FILE` may or may not carry a `.hint` suffix depending on how the user invoked it; `update_hint_file` normalizes internally. Here strip a trailing `.hint` for the pkg name and rebuild the path via `HINT_DIR`, matching `update_hint_file`'s normalization.)

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-BM18' -A1 | grep -E 'PASS|FAIL'`
Expected: `PASS`

- [ ] **Step 5: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: --hintfile -V reconciles bundled deps for listed packages

Parity with --check: the update path runs Phase 2 (report + apply) after
the primary bump.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: bash completion + example config

**Files:**
- Modify: `mkhint.bash-completion:17` (`all_flags`)
- Create: `bundle-manifests.example` (repo root)

- [ ] **Step 1: Add `--force` to completion flags**

In `mkhint.bash-completion` line 17, append `--force` to `all_flags`:

```bash
    local all_flags="--version -v --set-version -V --hintfile -f --new -n --list -l --review -R --clean -c --check -C --fix-current -F --delete -d --no-dl -N --force --help -h"
```

- [ ] **Step 2: Verify completion sources cleanly**

Run: `bash -n mkhint.bash-completion && echo OK`
Expected: `OK`

- [ ] **Step 3: Create `bundle-manifests.example`**

```
# mkhint bundle-manifests — packages whose extra DOWNLOAD lines are driven by an
# upstream deps manifest. Copy to ~/.config/mkhint/bundle-manifests and edit.
#
# Format: <pkgname> <deps-url-template>
# {VERSION} is replaced with the hint's version at check time (both '_' and '-'
# forms are tried). One entry per line; '#' comments and blank lines ignored.
#
# Example (neovim publishes cmake.deps/deps.txt with pinned dep URLs):
# neovim  https://raw.githubusercontent.com/neovim/neovim/v{VERSION}/cmake.deps/deps.txt
```

- [ ] **Step 4: Commit**

```bash
git add mkhint.bash-completion bundle-manifests.example
git commit -S -m "feat: --force completion + bundle-manifests.example

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 11: docs (help, man page, CLAUDE.md, changelog) + release v1.2.0

**Files:**
- Modify: `mkhint` `show_help` (mkhint:64-83), `MKHINT_VERSION` (mkhint:42)
- Modify: `mkhint.1.md` (OPTIONS + new section + title version), rebuild `mkhint.1.gz`
- Modify: `CLAUDE.md`, `CHANGELOG.md`

- [ ] **Step 1: Add `--force` to `--help` options list**

In `show_help` (after the `--no-dl` line, mkhint:75), add:

```bash
  --force                  With --check: reconcile bundled deps even if the primary version is unchanged
```

And add a line in the paths block (after the phantom-dep line, mkhint:81):

```bash
Bundle manifests (for --check bundled-dep reconcile): $BUNDLE_MANIFEST_FILE
```

- [ ] **Step 2: Bump `MKHINT_VERSION`**

Change mkhint:42 `readonly MKHINT_VERSION="1.1.3"` → `"1.2.0"`.

- [ ] **Step 3: Add `--force` + a BUNDLED DEPENDENCIES section to `mkhint.1.md`**

In `mkhint.1.md`, add to OPTIONS (option names `\--`-escaped for pandoc):

```
\--force
:   Only meaningful with \--check. Reconcile a bundle package's extra download
    lines against its upstream manifest even when the primary version has not
    changed. Use to retry after a previous manifest fetch failed.
```

Add a new section after BASH COMPLETION:

```
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
lines and recomputing their checksums. Bundled deps are never followed to their
own latest release; only the manifest's pinned URLs are used. Manifest entries
with no matching download line are reported but not added.
```

Update the title-line version: `% MKHINT(1) mkhint 1.2.0 | User Commands`.

- [ ] **Step 4: Rebuild the man page**

Run:
```bash
pandoc mkhint.1.md -s -t man -o mkhint.1 && gzip -9 -n -f mkhint.1
zcat mkhint.1.gz | groff -man -Tascii -ww >/dev/null && echo "groff clean"
```
Expected: `groff clean`, no warnings.

- [ ] **Step 5: Add a Key Behavior entry + config note to `CLAUDE.md`**

In the Configuration section, add `BUNDLE_MANIFEST_FILE` to the list of config-overridable vars. In Key Behaviors, add:

```markdown
- `--check` bundled-dep reconcile: for packages listed in `BUNDLE_MANIFEST_FILE`
  (`<pkg> <url-template-with-{VERSION}>`), after the primary bump mkhint fetches
  the upstream deps manifest (`NAME_URL`/`NAME_SHA256` pairs, e.g. neovim's
  `cmake.deps/deps.txt`), matches each extra `DOWNLOAD` line via
  `match_dep_url` (repo-path first, exact basename-stem fallback for blob
  hosts), and rewrites changed lines + recomputes their md5. Runs
  automatically when the primary changed this run, otherwise only with
  `--force` (check-only flag). `--new` on a listed package prints the reconcile
  report without changing the hint. Manifest deps with no hint line are listed
  as an FYI, never added (would need a SlackBuild change). Helpers:
  `load_bundle_manifests`, `manifest_url_for`, `fetch_manifest`,
  `parse_manifest`, `match_dep_url`, `reconcile_bundle_deps`.
```

- [ ] **Step 6: Move the CHANGELOG `[Unreleased]`/new section**

Add at the top of `CHANGELOG.md` (above `## [1.1.3]`):

```markdown
## [1.2.0] - 2026-07-07

### Added
- Manifest-driven bundled-dep updates. Packages listed in the new
  `BUNDLE_MANIFEST_FILE` (`<pkg> <deps-url-template>`) have their extra
  `DOWNLOAD` lines reconciled against an upstream deps manifest (e.g. neovim's
  `cmake.deps/deps.txt`) during `--check`: matched lines are rewritten to the
  manifest's pinned URLs and their checksums recomputed. `--new` reports the
  reconcile without changing the hint.
- `--force` flag (check-only): run the bundled-dep reconcile even when the
  primary version is unchanged (e.g. to retry after a failed manifest fetch).
```

- [ ] **Step 7: Verify version + whole suite**

Run:
```bash
./mkhint -v
bash tests/mkhint_test.sh 2>&1 | grep Results:
```
Expected: `mkhint 1.2.0`; all passed, 0 failed.

- [ ] **Step 8: Commit the docs + release bump**

```bash
git add mkhint mkhint.1.md mkhint.1.gz CLAUDE.md CHANGELOG.md
git commit -S -m "docs: document bundled-dep reconcile + --force; release v1.2.0

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 9: Tag the release**

```bash
git tag -s -m "mkhint 1.2.0" v1.2.0
git log --format='%h %G? %s' -1
git tag -v v1.2.0 2>&1 | grep -i 'good signature' || true
```
Expected: commit line shows `G`; tag verifies.

---

## Task 12: push both remotes + deploy to VM

**Files:** none (deployment).

- [ ] **Step 1: Push master + tag to both remotes**

```bash
git push origin master && git push origin v1.2.0
```
Expected: both `danix_git` and `slackware_forge` push URLs updated; new tag on both.

- [ ] **Step 2: Deploy binary + man page to the VM**

```bash
scp mkhint buildsystem:/usr/local/bin/mkhint
scp mkhint.1.gz buildsystem:/usr/local/man/man1/mkhint.1.gz
```

- [ ] **Step 3: Deploy the updated completion script (it changed this release)**

```bash
scp mkhint.bash-completion buildsystem:/etc/bash_completion.d/mkhint
```
(Note VM completion dir uses underscore: `/etc/bash_completion.d/`.)

- [ ] **Step 4: Verify md5 + version on the VM**

```bash
lb=$(md5sum mkhint | awk '{print $1}'); lm=$(md5sum mkhint.1.gz | awk '{print $1}')
ssh buildsystem "md5sum /usr/local/bin/mkhint /usr/local/man/man1/mkhint.1.gz; mkhint -v"
echo "local bin $lb  man $lm"
```
Expected: VM md5s match local; `mkhint -v` prints `mkhint 1.2.0`.

- [ ] **Step 5: (manual, optional) seed the real bundle-manifests on the VM**

Not automated. When ready, create `/root/.config/mkhint/bundle-manifests` on the VM with the neovim line from `bundle-manifests.example`, then `mkhint -C --force neovim` to reconcile.

---

## Self-review notes

- **Spec coverage:** Section 1 (config) → T1. Section 2 (parser/matcher) → T2, T3, T4, T5. Section 3 (--new) → T7. Section 4 (--check two-phase + --force gate) → T8, T9. Section 5 (errors, FYI, non-goals) → T6 (FYI + unmatched), T9 (fetch fail). Section 6 (tests) → distributed. Section 7 (layout/docs) → T10, T11, T12. All sections covered.
- **`--hintfile -V` on a listed package** (spec Section 4): covered by Task 9b, which mirrors the Phase 2 reconcile into the `update` case. Full spec parity.
- **Type/name consistency:** helper names match across tasks and the CLAUDE.md entry (`load_bundle_manifests`, `manifest_url_for`, `fetch_manifest`, `parse_manifest`, `match_dep_url`, `reconcile_bundle_deps`, plus internal `_url_stem`, `_url_repo`, `pkg_has_manifest`).
- **Sourcing helpers in unit tests:** relies on the block markers `# ── bundled-dep manifest handling ──` … `# ── end bundled-dep manifest handling ──` (added T2 Step 3). Later helper tests source between those markers; integration tests source the whole script.
