# nvchecker Autodetect Expansion + `-n` Stanza Output + `--info`/`-i` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Broaden nvchecker source autodetection in `add_nvchecker_section`, echo the managed stanza on `-n`, and add a `--info`/`-i <pkg>` README viewer.

**Architecture:** All three land in the single-file `mkhint` bash script. F0/F1 rewrite the one stanza emitter (`add_nvchecker_section`), so every caller (`--new`, `--check` populate) benefits with no duplicated logic. F2 adds a new `COMMAND="info"` with a `show_info` handler. Tests extend `tests/mkhint_test.sh` (mock dirs, no network); docs (man page, bash completion, `--help`, `CLAUDE.md`, `CHANGELOG.md`) update at the end.

**Tech Stack:** bash, awk/grep/sed, pandoc (man page), `tests/mkhint_test.sh` harness.

Spec: `docs/superpowers/specs/2026-07-09-new-stanza-output-and-info-command-design.md`

---

## File Structure

- **Modify** `mkhint`:
  - `add_nvchecker_section` (lines ~822–881): expand detection + echo stanza.
  - New helpers near it: `_detect_nvchecker_source`, `_registry_name_from_url`, `_extract_nvchecker_section`.
  - Globals block (~50–62): add `INFO_PKG=""`.
  - Arg parser case (~1391): add `--info|-i`.
  - Mutual-exclusion guards (~1473): add info guard.
  - `case "$COMMAND"` dispatch (~1516): add `info)` → `show_info`.
  - New `show_info` handler function.
  - `show_help` (~65): add `-i` line.
- **Modify** `tests/mkhint_test.sh`: fixtures + new test cases.
- **Modify** `mkhint.bash-completion`, `mkhint.1.md` (rebuild `mkhint.1.gz`), `CLAUDE.md`, `CHANGELOG.md`, `MKHINT_VERSION`.

A note on the harness: `run_mkhint "$@"` runs the patched script and returns its exit code but does not capture stdout. For stdout assertions, redirect: `run_mkhint -n foo > "$MOCK_BASE/out.txt" 2>&1` then `assert_contains desc "$MOCK_BASE/out.txt" pattern`. `assert_contains`/`assert_not_contains` grep a file; `assert_exit_code` compares two integers.

---

## Task 1: Registry name-from-URL helper

**Files:**
- Modify: `mkhint` (add helper just above `add_nvchecker_section`, ~line 821)
- Test: `tests/mkhint_test.sh`

- [ ] **Step 1: Write the failing test**

Add near the end of `tests/mkhint_test.sh`, before the summary block. This sources the patched script to call the helper directly. Add a helper to source it once:

```bash
# ── T-NV1: _registry_name_from_url extracts names per host ────────────────────
echo ""
echo "T-NV1: _registry_name_from_url host-specific parsing"
# Build a patched script we can source for unit-testing helpers
SRC_PATCHED=$(mktemp /tmp/mkhint_src_XXXXXX)
sed -e "s|REPO_DIR=\".*\"|REPO_DIR=\"$MOCK_REPO\"|" \
    -e "s|HINT_DIR=\".*\"|HINT_DIR=\"$MOCK_HINT\"|" \
    "$SCRIPT" > "$SRC_PATCHED"
# shellcheck disable=SC1090
source "$SRC_PATCHED"

nv_out="$MOCK_BASE/nv_helper.txt"
{
  echo "crates $(_registry_name_from_url 'https://crates.io/api/v1/crates/ripgrep/ripgrep-14.0.0.crate' ripgrep)"
  echo "gems $(_registry_name_from_url 'https://rubygems.org/downloads/rails-7.1.0.gem' rails)"
  echo "npm $(_registry_name_from_url 'https://registry.npmjs.org/left-pad/-/left-pad-1.3.0.tgz' left-pad)"
  echo "fallback $(_registry_name_from_url 'https://example.com/weird/path.tar.gz' mypkg)"
} > "$nv_out"

assert_contains "crates name parsed"   "$nv_out" '^crates ripgrep$'
assert_contains "gems name parsed"     "$nv_out" '^gems rails$'
assert_contains "npm name parsed"      "$nv_out" '^npm left-pad$'
assert_contains "fallback to PRGNAM"   "$nv_out" '^fallback mypkg$'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A1 'T-NV1'`
Expected: FAIL lines (function `_registry_name_from_url` not defined → empty output, patterns miss).

- [ ] **Step 3: Write the helper**

Insert into `mkhint` immediately above `add_nvchecker_section()` (before line ~822):

```bash
# Extract a package name from a language-registry download URL.
# Args: <url> <prgnam-fallback>. Prints the parsed name, or the fallback
# (PRGNAM) when no host-specific pattern matches.
_registry_name_from_url() {
    local url="$1" fallback="$2"
    case "$url" in
        *crates.io/api/v1/crates/*)
            # .../crates/NAME/NAME-VER.crate  or  .../crates/NAME/VER/download
            printf '%s' "${url#*crates.io/api/v1/crates/}" | cut -d/ -f1
            return 0 ;;
        *rubygems.org/downloads/*)
            # /downloads/NAME-VER.gem
            local base="${url##*/downloads/}"; base="${base%.gem}"
            printf '%s' "${base%-*}"
            return 0 ;;
        *registry.npmjs.org/*)
            # /NAME/-/NAME-VER.tgz   (NAME may be @scope/pkg)
            printf '%s' "${url#*registry.npmjs.org/}" | sed 's|/-/.*||'
            return 0 ;;
        *hackage.haskell.org/package/*)
            printf '%s' "${url#*hackage.haskell.org/package/}" | cut -d/ -f1
            return 0 ;;
    esac
    printf '%s' "$fallback"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A4 'T-NV1'`
Expected: four PASS lines.

- [ ] **Step 5: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: _registry_name_from_url helper for nvchecker autodetect"
```

---

## Task 2: Source-detection helper

**Files:**
- Modify: `mkhint` (add `_detect_nvchecker_source` above `add_nvchecker_section`)
- Test: `tests/mkhint_test.sh`

`_detect_nvchecker_source <haystack> <pkg>` inspects the DOWNLOAD/HOMEPAGE
haystack and prints the full TOML body (fields only, no `[label]` header — the
caller adds that). Prints nothing (empty) when unrecognised, so the caller
emits the stub.

- [ ] **Step 1: Write the failing test**

Append to `tests/mkhint_test.sh` (after T-NV1; `$SRC_PATCHED` already sourced):

```bash
# ── T-NV2: _detect_nvchecker_source per host ──────────────────────────────────
echo ""
echo "T-NV2: _detect_nvchecker_source emits correct body per host"
d_out="$MOCK_BASE/nv_detect.txt"
: > "$d_out"
echo "### github" >> "$d_out"
_detect_nvchecker_source "DOWNLOAD=https://github.com/o/r/archive/v1.tar.gz" r >> "$d_out"
echo "### gitlab" >> "$d_out"
_detect_nvchecker_source "DOWNLOAD=https://gitlab.com/o/r/-/archive/1/r-1.tar.gz" r >> "$d_out"
echo "### bitbucket" >> "$d_out"
_detect_nvchecker_source "DOWNLOAD=https://bitbucket.org/o/r/get/1.tar.gz" r >> "$d_out"
echo "### gitea" >> "$d_out"
_detect_nvchecker_source "DOWNLOAD=https://gitea.com/o/r/archive/1.tar.gz" r >> "$d_out"
echo "### codeberg" >> "$d_out"
_detect_nvchecker_source "DOWNLOAD=https://codeberg.org/o/r/archive/1.tar.gz" r >> "$d_out"
echo "### pagure" >> "$d_out"
_detect_nvchecker_source "DOWNLOAD=https://pagure.io/r/archive/1/r-1.tar.gz" r >> "$d_out"
echo "### npm" >> "$d_out"
_detect_nvchecker_source "DOWNLOAD=https://registry.npmjs.org/lp/-/lp-1.tgz" lp >> "$d_out"
echo "### cran" >> "$d_out"
_detect_nvchecker_source "DOWNLOAD=https://cran.r-project.org/src/contrib/foo_1.tar.gz" foo >> "$d_out"
echo "### unknown" >> "$d_out"
_detect_nvchecker_source "DOWNLOAD=https://example.com/x.tar.gz" x >> "$d_out"
echo "### end" >> "$d_out"

assert_contains "github source"        "$d_out" 'source = "github"'
assert_contains "github latest_release" "$d_out" 'use_latest_release = true'
assert_contains "github max_tag comment" "$d_out" '# use_max_tag = true'
assert_contains "github prefix comment"  "$d_out" '# prefix = "v"'
assert_contains "gitlab source"        "$d_out" 'source = "gitlab"'
assert_contains "gitlab field"         "$d_out" 'gitlab = "o/r"'
assert_contains "bitbucket field"      "$d_out" 'bitbucket = "o/r"'
assert_contains "gitea field"          "$d_out" 'gitea = "o/r"'
assert_contains "codeberg host"        "$d_out" 'host = "codeberg.org"'
assert_contains "pagure field"         "$d_out" 'pagure = "r"'
assert_contains "npm field"            "$d_out" 'npm = "lp"'
assert_contains "cran field"           "$d_out" 'cran = "foo"'
# unknown host → empty body between ### unknown and ### end
unk=$(awk '/^### unknown/{f=1;next} /^### end/{f=0} f' "$d_out")
assert_exit_code "unknown host empty body" 0 "$( [[ -z "${unk//[[:space:]]/}" ]]; echo $? )"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A14 'T-NV2'`
Expected: FAILs (function undefined).

- [ ] **Step 3: Write the helper**

Insert above `add_nvchecker_section()` (below the Task 1 helper):

```bash
# Detect an nvchecker source from a package's DOWNLOAD/HOMEPAGE haystack.
# Args: <haystack> <prgnam>. Prints the TOML body (no [label] header). Empty
# output means "unrecognised" → caller emits the commented stub.
_detect_nvchecker_source() {
    local haystack="$1" pkg="$2"

    # ── owner/repo forges ─────────────────────────────────────────────────
    if [[ "$haystack" =~ (github\.com|gitlab\.com|bitbucket\.org|gitea\.com|codeberg\.org|pagure\.io)/([A-Za-z0-9._-]+)(/([A-Za-z0-9._-]+))? ]]; then
        local host="${BASH_REMATCH[1]}"
        local owner="${BASH_REMATCH[2]}"
        local repo="${BASH_REMATCH[4]}"
        repo="${repo%.git}"; owner="${owner%.git}"
        case "$host" in
            github.com)
                printf 'source = "github"\ngithub = "%s/%s"\nuse_latest_release = true\n# use_max_tag = true  # if the repo publishes no Releases\n# prefix = "v"  # uncomment if tags are v-prefixed\n' "$owner" "$repo"
                return 0 ;;
            gitlab.com)
                printf 'source = "gitlab"\ngitlab = "%s/%s"\nuse_max_tag = true\n# prefix = "v"  # uncomment if tags are v-prefixed\n' "$owner" "$repo"
                return 0 ;;
            bitbucket.org)
                printf 'source = "bitbucket"\nbitbucket = "%s/%s"\nuse_max_tag = true\n# prefix = "v"  # uncomment if tags are v-prefixed\n' "$owner" "$repo"
                return 0 ;;
            gitea.com)
                printf 'source = "gitea"\ngitea = "%s/%s"\nuse_max_tag = true\n# prefix = "v"  # uncomment if tags are v-prefixed\n' "$owner" "$repo"
                return 0 ;;
            codeberg.org)
                printf 'source = "gitea"\ngitea = "%s/%s"\nhost = "codeberg.org"\nuse_max_tag = true\n# prefix = "v"  # uncomment if tags are v-prefixed\n' "$owner" "$repo"
                return 0 ;;
            pagure.io)
                # pagure field is the repo only; on pagure.io the first path
                # segment IS the repo (no owner), so it lands in $owner.
                printf 'source = "pagure"\npagure = "%s"\nuse_max_tag = true\n# prefix = "v"  # uncomment if tags are v-prefixed\n' "$owner"
                return 0 ;;
        esac
    fi

    # ── language registries ───────────────────────────────────────────────
    local url; url=$(printf '%s' "$haystack" | grep -oE 'https?://[^ ]+' | head -1)
    local name
    case "$haystack" in
        *pypi.org*|*files.pythonhosted.org*)
            printf 'source = "pypi"\npypi = "%s"\n' "$pkg"; return 0 ;;
        *registry.npmjs.org*|*npmjs.com*)
            name=$(_registry_name_from_url "$url" "$pkg")
            printf 'source = "npm"\nnpm = "%s"\n' "$name"; return 0 ;;
        *rubygems.org*)
            name=$(_registry_name_from_url "$url" "$pkg")
            printf 'source = "gems"\ngems = "%s"\n' "$name"; return 0 ;;
        *crates.io*)
            name=$(_registry_name_from_url "$url" "$pkg")
            printf 'source = "cratesio"\ncratesio = "%s"\n' "$name"; return 0 ;;
        *metacpan.org*|*cpan.org*)
            printf 'source = "cpan"\ncpan = "%s"\n' "$pkg"; return 0 ;;
        *hackage.haskell.org*)
            name=$(_registry_name_from_url "$url" "$pkg")
            printf 'source = "hackage"\nhackage = "%s"\n' "$name"; return 0 ;;
        *packagist.org*)
            printf 'source = "packagist"\npackagist = "%s"\n' "$pkg"; return 0 ;;
        *cran.r-project.org*)
            printf 'source = "cran"\ncran = "%s"\n' "$pkg"; return 0 ;;
    esac

    return 0   # empty output → caller stubs
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A14 'T-NV2'`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: _detect_nvchecker_source maps forge+registry hosts"
```

---

## Task 3: Section-extract helper (for stanza echo of existing sections)

**Files:**
- Modify: `mkhint` (add `_extract_nvchecker_section` near `_has_nvchecker_section`, ~line 818)
- Test: `tests/mkhint_test.sh`

- [ ] **Step 1: Write the failing test**

Append to `tests/mkhint_test.sh`:

```bash
# ── T-NV3: _extract_nvchecker_section prints one section ──────────────────────
echo ""
echo "T-NV3: _extract_nvchecker_section returns the [pkg] block only"
NVCHECKER_CONFIG="$MOCK_BASE/nv_extract.toml"
cat > "$NVCHECKER_CONFIG" << 'EOF'
[alpha]
source = "github"
github = "a/alpha"

[beta]
source = "pypi"
pypi = "beta"

[gamma]
source = "cran"
cran = "gamma"
EOF
ex_out="$MOCK_BASE/nv_extract.txt"
_extract_nvchecker_section beta > "$ex_out"
assert_contains "beta header"      "$ex_out" '^\[beta\]$'
assert_contains "beta field"       "$ex_out" 'pypi = "beta"'
assert_not_contains "no alpha"     "$ex_out" 'alpha'
assert_not_contains "no gamma"     "$ex_out" 'gamma'
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A4 'T-NV3'`
Expected: FAIL (function undefined).

- [ ] **Step 3: Write the helper**

Insert into `mkhint` after `_has_nvchecker_section()` (~line 818):

```bash
# Print the [pkg] section (header + body) from NVCHECKER_CONFIG: from the label
# line until the next line starting with '[' or EOF. Empty if not found.
_extract_nvchecker_section() {
    local pkg="$1"
    [[ -f "$NVCHECKER_CONFIG" ]] || return 0
    local label; label=$(_nvchecker_label "$pkg")
    awk -v lbl="$label" '
        $0==lbl { grab=1; print; next }
        grab && /^\[/ { exit }
        grab { print }
    ' "$NVCHECKER_CONFIG"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A4 'T-NV3'`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: _extract_nvchecker_section reads one config block"
```

---

## Task 4: Rewire `add_nvchecker_section` to use detection + echo the stanza

**Files:**
- Modify: `mkhint` `add_nvchecker_section` (lines ~822–881)
- Test: `tests/mkhint_test.sh` (update T16–T19, add new-host cases)

- [ ] **Step 1: Update the existing T16/T18/T19 expectations and add host tests**

Replace the T16 assertions (lines ~537–540) and add capture of stdout. The T16
block becomes:

```bash
# ── T16: --new github .info → github source section ───────────────────────────
echo ""
echo "T16: --new github .info → [pkg] source=github appended"
run_mkhint -n ghpkg > "$MOCK_BASE/t16.out" 2>&1
assert_contains "github section header"  "$MOCK_BASE/nvchecker.toml" '\[ghpkg\]'
assert_contains "github source"          "$MOCK_BASE/nvchecker.toml" 'source = "github"'
assert_contains "github owner/repo"      "$MOCK_BASE/nvchecker.toml" 'github = "someowner/ghpkg"'
assert_contains "github latest_release"  "$MOCK_BASE/nvchecker.toml" 'use_latest_release = true'
assert_contains "github max_tag comment" "$MOCK_BASE/nvchecker.toml" '# use_max_tag = true'
# F1: stanza echoed to stdout
assert_contains "T16 stanza echoed"      "$MOCK_BASE/t16.out" 'source = "github"'
```

Update T18 (stub) — clion's `.info` uses a non-listed host, keep it stubbed —
and add stdout echo of the stub:

```bash
# ── T18: --new unrecognised URL → commented stub ──────────────────────────────
echo ""
echo "T18: --new unknown source → commented stub appended"
run_mkhint -n clion > "$MOCK_BASE/t18.out" 2>&1
assert_contains "clion section header"    "$MOCK_BASE/nvchecker.toml" '\[clion\]'
assert_contains "stub TODO"               "$MOCK_BASE/nvchecker.toml" 'TODO: configure nvchecker source'
assert_contains "T18 stub echoed"         "$MOCK_BASE/t18.out" 'TODO: configure nvchecker source'
```

Update T19 (already present) to assert the existing section is dumped:

```bash
# ── T19: --new when [pkg] already present → no duplicate, dumps existing ───────
echo ""
echo "T19: --new when section exists → not duplicated, existing dumped"
run_mkhint -n ghpkg > "$MOCK_BASE/t19.out" 2>&1  # ghpkg section already added in T16
dup_count=$(grep -c '^\[ghpkg\]' "$MOCK_BASE/nvchecker.toml")
assert_exit_code "ghpkg section appears once" 1 "$dup_count"
assert_contains "T19 dumps existing"      "$MOCK_BASE/t19.out" 'github = "someowner/ghpkg"'
```

Add new-host fixtures in `setup()` (extend the `mkdir -p` list and add
`.info` files). Add these dirs to the `mkdir -p` chain (line ~19):
`"$MOCK_REPO/development/glpkg" "$MOCK_REPO/development/cbpkg" "$MOCK_REPO/development/crpkg"`.
Then add `.info` files after the pypkg one (~line 108):

```bash
    cat > "$MOCK_REPO/development/glpkg/glpkg.info" << 'EOF'
PRGNAM="glpkg"
VERSION="1.0.0"
HOMEPAGE="https://gitlab.com/someowner/glpkg"
DOWNLOAD="https://gitlab.com/someowner/glpkg/-/archive/1.0.0/glpkg-1.0.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
REQUIRES=""
MAINTAINER="Test"
EMAIL="test@test.com"
EOF
    cat > "$MOCK_REPO/development/cbpkg/cbpkg.info" << 'EOF'
PRGNAM="cbpkg"
VERSION="1.0.0"
HOMEPAGE="https://codeberg.org/someowner/cbpkg"
DOWNLOAD="https://codeberg.org/someowner/cbpkg/archive/1.0.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
REQUIRES=""
MAINTAINER="Test"
EMAIL="test@test.com"
EOF
    cat > "$MOCK_REPO/development/crpkg/crpkg.info" << 'EOF'
PRGNAM="crpkg"
VERSION="1.0.0"
HOMEPAGE="https://cran.r-project.org/package=crpkg"
DOWNLOAD="https://cran.r-project.org/src/contrib/crpkg_1.0.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
REQUIRES=""
MAINTAINER="Test"
EMAIL="test@test.com"
EOF
```

Add the integration cases after T19:

```bash
# ── T-NV4: --new gitlab .info → gitlab section ────────────────────────────────
echo ""
echo "T-NV4: --new gitlab .info → source=gitlab"
run_mkhint -n glpkg > /dev/null 2>&1
assert_contains "gitlab source"  "$MOCK_BASE/nvchecker.toml" 'source = "gitlab"'
assert_contains "gitlab field"   "$MOCK_BASE/nvchecker.toml" 'gitlab = "someowner/glpkg"'

# ── T-NV5: --new codeberg .info → gitea source + host ─────────────────────────
echo ""
echo "T-NV5: --new codeberg .info → gitea + host"
run_mkhint -n cbpkg > /dev/null 2>&1
assert_contains "codeberg source" "$MOCK_BASE/nvchecker.toml" 'source = "gitea"'
assert_contains "codeberg host"   "$MOCK_BASE/nvchecker.toml" 'host = "codeberg.org"'

# ── T-NV6: --new cran .info → cran source ─────────────────────────────────────
echo ""
echo "T-NV6: --new cran .info → source=cran"
run_mkhint -n crpkg > /dev/null 2>&1
assert_contains "cran source" "$MOCK_BASE/nvchecker.toml" 'source = "cran"'
assert_contains "cran field"  "$MOCK_BASE/nvchecker.toml" 'cran = "crpkg"'
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'FAIL|T-NV[456]|T16 stanza|T18 stub|T19 dumps'`
Expected: the new assertions FAIL (old `add_nvchecker_section` emits `use_max_tag` for github, no stdout echo, no gitlab/cran support).

- [ ] **Step 3: Rewrite `add_nvchecker_section`**

Replace the whole function body (lines ~822–881) with:

```bash
add_nvchecker_section() {
    local pkg="$1"
    local info_file="$2"

    # Ensure config dir/file exist (do not create __config__; user owns that)
    mkdir -p "$(dirname "$NVCHECKER_CONFIG")"
    touch "$NVCHECKER_CONFIG"

    local label; label=$(_nvchecker_label "$pkg")

    # Already present: dump the existing section so the user sees what's set.
    if _has_nvchecker_section "$pkg"; then
        echo "nvchecker: ${label} already present in $NVCHECKER_CONFIG:"
        echo "────────────────────────────"
        _extract_nvchecker_section "$pkg"
        echo "────────────────────────────"
        return 0
    fi

    local download="" homepage=""
    if [[ -f "$info_file" ]]; then
        download=$(grep -E '^(DOWNLOAD|DOWNLOAD_x86_64)=' "$info_file" | head -1)
        homepage=$(grep -E '^HOMEPAGE=' "$info_file" | head -1)
    fi
    local haystack="${download} ${homepage}"

    local body; body=$(_detect_nvchecker_source "$haystack" "$pkg")
    local section
    if [[ -n "$body" ]]; then
        section=$(printf '\n%s\n%s' "$label" "$body")
    else
        section=$(cat <<EOF

${label}
# TODO: configure nvchecker source for "${pkg}"
# source = "regex"
# url = "..."
# regex = "..."
# see https://nvchecker.readthedocs.io/en/latest/usage.html
EOF
)
    fi

    printf '%s\n' "$section" >> "$NVCHECKER_CONFIG"
    echo "nvchecker: added ${label} section to $NVCHECKER_CONFIG:"
    echo "────────────────────────────"
    printf '%s\n' "$label"
    if [[ -n "$body" ]]; then
        printf '%s' "$body"
    else
        echo "# TODO: configure nvchecker source for \"${pkg}\""
    fi
    echo "────────────────────────────"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/mkhint_test.sh 2>&1 | tail -20`
Expected: all pass, failed count 0.

- [ ] **Step 5: Syntax check + commit**

```bash
bash -n mkhint && git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: expand nvchecker autodetect + echo stanza on -n/-C"
```

---

## Task 5: `--info`/`-i` — globals, arg parse, guard

**Files:**
- Modify: `mkhint` globals (~line 62), arg parser (~line 1391), guards (~line 1481)

- [ ] **Step 1: Add global**

In the Variables block (after line 62 `FORCE=0`):

```bash
INFO_PKG=""
```

- [ ] **Step 2: Add arg-parser case**

In the `case "$1"` block, after the `--new|-n` case (~line 1394):

```bash
            --info|-i)
                COMMAND="info"
                INFO_PKG="$2"
                shift 2
                ;;
```

- [ ] **Step 3: Add mutual-exclusion guard**

After the fix-current guard (~line 1481):

```bash
    if [[ "$COMMAND" == "info" && ( -n "$VERSION" || -n "$HINT_FILE" || -n "$NEW_HINT_FILE" ) ]]; then
        echo "Error: --info cannot be combined with --set-version/--hintfile/--new" >&2
        exit 1
    fi
```

- [ ] **Step 4: Syntax check**

Run: `bash -n mkhint`
Expected: no output (clean).

- [ ] **Step 5: Commit**

```bash
git add mkhint
git commit -S -m "feat: --info/-i arg parsing and mutual-exclusion guard"
```

---

## Task 6: `show_info` handler + dispatch

**Files:**
- Modify: `mkhint` (add `show_info` function; add `info)` to dispatch ~line 1519)
- Test: `tests/mkhint_test.sh`

- [ ] **Step 1: Write the failing tests**

Add to `tests/mkhint_test.sh`. Give one fixture a README:

```bash
# README fixture for --info tests (curl dir already exists in setup)
# (added inline here to keep the test self-contained)
cat > "$MOCK_REPO/network/curl/README" << 'EOF'
curl is a tool to transfer data from or to a server.
It supports many protocols.
EOF

# ── T-INFO1: --info existing pkg with README → header + README (non-TTY) ───────
echo ""
echo "T-INFO1: --info prints category/pkg header + README"
run_mkhint -i curl > "$MOCK_BASE/info1.out" 2>&1
assert_contains "info header path"  "$MOCK_BASE/info1.out" 'network/curl'
assert_contains "info README body"  "$MOCK_BASE/info1.out" 'transfer data from or to a server'

# ── T-INFO2: --info pkg without README → header + (no README) ──────────────────
echo ""
echo "T-INFO2: --info pkg with no README notes it"
# clion dir exists, no README written
run_mkhint -i clion > "$MOCK_BASE/info2.out" 2>&1
info2_rc=$?
assert_contains "info2 header"      "$MOCK_BASE/info2.out" 'development/clion'
assert_contains "info2 no README"   "$MOCK_BASE/info2.out" 'no README'
assert_exit_code "info2 exit 0"     0 "$info2_rc"

# ── T-INFO3: --info missing pkg → exit 2 ──────────────────────────────────────
echo ""
echo "T-INFO3: --info missing pkg exits 2"
run_mkhint -i doesnotexist > "$MOCK_BASE/info3.out" 2>&1
info3_rc=$?
assert_exit_code "info3 exit 2"     2 "$info3_rc"
assert_contains "info3 error msg"   "$MOCK_BASE/info3.out" 'not found'

# ── T-INFO4: --info combined with -V → mutually exclusive, exit 1 ──────────────
echo ""
echo "T-INFO4: --info + -V mutually exclusive"
run_mkhint -i curl -V 9.9.9 > "$MOCK_BASE/info4.out" 2>&1
info4_rc=$?
assert_exit_code "info4 exit 1"     1 "$info4_rc"
```

Note: `run_mkhint` runs the patched script (REPO_DIR → `$MOCK_REPO`), so
`show_info` globs the mock repo. Stdout is a pipe here (non-TTY) → inline path,
no pager, deterministic.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-INFO|FAIL'`
Expected: FAILs — `COMMAND="info"` reaches the dispatch `*)` "Unknown command"
branch (exit 1), so header/README asserts miss and T-INFO3 gets exit 1 not 2.

- [ ] **Step 3: Write `show_info` and wire dispatch**

Add the function above `main` (near other handlers, e.g. after `create_new_hint_file`, ~line 796):

```bash
# --info/-i: show a package's category/program path (green on a TTY) then its
# README, paged only when it doesn't fit the terminal.
show_info() {
    local pkg="$1"
    if [[ -z "$pkg" ]]; then
        echo "Error: --info requires a package name" >&2
        exit 1
    fi

    # Find the category dir(s): REPO_DIR/*/pkg/
    local -a matches=()
    local d
    for d in "${REPO_DIR%/}"/*/"$pkg"/; do
        [[ -d "$d" ]] && matches+=("$d")
    done
    if [[ ${#matches[@]} -eq 0 ]]; then
        echo "Error: package not found in ${REPO_DIR%/}: $pkg" >&2
        exit 2
    fi
    if [[ ${#matches[@]} -gt 1 ]]; then
        echo "Error: multiple matches for $pkg in ${REPO_DIR%/}:" >&2
        printf '  %s\n' "${matches[@]}" >&2
        exit 2
    fi

    local dir="${matches[0]%/}"
    local category; category=$(basename "$(dirname "$dir")")

    # Green header on a TTY (same gate as --list).
    local g_on="" g_off=""
    if [[ -n "$MKHINT_FORCE_COLOR" || -t 1 ]]; then
        if command -v tput &>/dev/null && tput setaf 2 &>/dev/null; then
            g_on=$(tput setaf 2); g_off=$(tput sgr0)
        else
            g_on=$'\033[32m'; g_off=$'\033[0m'
        fi
    fi
    local header="${g_on}${category}/${pkg}${g_off}"

    local readme="${dir}/README"
    if [[ ! -f "$readme" ]]; then
        printf '%s\n' "$header"
        echo "(no README)"
        exit 0
    fi

    # Non-TTY, or README fits: print inline. Else page with header pinned.
    local rows; rows="${LINES:-}"
    [[ -z "$rows" ]] && command -v tput &>/dev/null && rows=$(tput lines 2>/dev/null)
    [[ -z "$rows" ]] && rows=24
    local lines; lines=$(wc -l < "$readme")

    if [[ ! -t 1 || "$lines" -le "$rows" ]]; then
        printf '%s\n' "$header"
        cat "$readme"
        exit 0
    fi

    # Page: header as line 1 so it survives; pin it if pager is less.
    local pager="${PAGER:-less}"
    if [[ "$(basename "$pager")" == "less" ]]; then
        { printf '%s\n' "$header"; cat "$readme"; } | less -R --header=1
    else
        { printf '%s\n' "$header"; cat "$readme"; } | $pager
    fi
    exit 0
}
```

Add to the `case "$COMMAND"` dispatch, after `fix-current)` (~line 1528):

```bash
        info)
            show_info "$INFO_PKG"
            ;;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -E 'T-INFO'`
Expected: all PASS.

- [ ] **Step 5: Syntax check + commit**

```bash
bash -n mkhint && git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: --info/-i shows category/program header + README"
```

---

## Task 7: Full suite + docs + version bump

**Files:**
- Modify: `mkhint` (`MKHINT_VERSION`, `show_help`), `mkhint.bash-completion`, `mkhint.1.md`, `mkhint.1.gz`, `CLAUDE.md`, `CHANGELOG.md`

- [ ] **Step 1: Run the full suite**

Run: `bash tests/mkhint_test.sh 2>&1 | tail -5`
Expected: all pass, 0 failed. If any pre-existing test broke, fix before continuing.

- [ ] **Step 2: gitleaks + syntax**

Run: `bash -n mkhint && gitleaks detect --no-banner 2>&1 | tail -2`
Expected: clean, no leaks.

- [ ] **Step 3: Add `-i` to `show_help`**

In `show_help` (~line 65), add an `-i` line near the other options. Find the
`-n, --new` line and add after it:

```
  -i, --info FILE          Show category/program path and README for a package
```

- [ ] **Step 4: Update bash completion**

In `mkhint.bash-completion`, add `--info -i` to the options list (find the
existing `--check -C --fix-current -F` string and append `--info -i`).

- [ ] **Step 5: Update man page source + rebuild**

In `mkhint.1.md`, add a `\--info`, `\--i` entry in the options section (mirror
the `\--new` entry) and a one-line note that `-n` now prints the managed
nvchecker stanza and autodetects more sources. Then:

```bash
pandoc mkhint.1.md -s -t man -o mkhint.1 && gzip -9 -n -f mkhint.1
```

- [ ] **Step 6: Update CLAUDE.md Key Behaviors**

Add bullets: (a) `add_nvchecker_section` now autodetects gitlab/bitbucket/gitea/
codeberg/pagure/npm/gems/cratesio/cpan/hackage/packagist/cran in addition to
github/pypi, github uses `use_latest_release` with commented `use_max_tag`/
`prefix` fallbacks, others `use_max_tag` + commented `# prefix`, and it echoes
the stanza (added or existing) fenced on stdout; (b) `--info`/`-i <pkg>` prints
the green `category/program` path then the README, paged (sticky header via
`less --header=1`) only when taller than the terminal.

- [ ] **Step 7: Bump version + CHANGELOG**

Set `MKHINT_VERSION` to the next patch (`1.2.5`). Add a CHANGELOG entry
describing the three additions.

- [ ] **Step 8: Commit**

```bash
git add mkhint mkhint.bash-completion mkhint.1.md mkhint.1.gz CLAUDE.md CHANGELOG.md
git commit -S -m "feat: nvchecker autodetect expansion, -n stanza echo, --info/-i; release v1.2.5"
```

- [ ] **Step 9: Deploy to VM and hand off for testing (do NOT tag yet)**

Per the project's release cadence (`memory/deploy-to-vm-before-release.md`):
deploy to the buildsystem VM, let the user test live, and only after the user
confirms do you tag (`git tag -s v1.2.5`) and push both remotes, then redeploy
with md5 verification. Never retag a pushed tag.

```bash
scp mkhint buildsystem:/usr/local/bin/mkhint
scp mkhint.bash-completion buildsystem:/etc/bash_completion.d/mkhint
scp mkhint.1.gz buildsystem:/usr/local/man/man1/mkhint.1.gz
```

Then tell the user: deployed to VM, please test `-n` on a few packages
(github/gitlab/codeberg/unknown), `-C` populate, and `-i <pkg>` with and
without a README; tag+push after you confirm.

---

## Self-Review

- **Spec coverage:** F0 autodetect → Tasks 1,2,4. F0 registry name fallback →
  Task 1. F1 stanza echo (added + existing) → Tasks 3,4. F2 `--info` → Tasks
  5,6. Docs/version → Task 7. Global-by-construction (single emitter) → Task 4
  rewires the one function. All spec sections mapped.
- **Placeholders:** none; every code step shows full code.
- **Type/name consistency:** `_registry_name_from_url`, `_detect_nvchecker_source`,
  `_extract_nvchecker_section`, `show_info`, `INFO_PKG`, `COMMAND="info"` used
  consistently across tasks. `_detect_nvchecker_source` prints body-only; caller
  adds `[label]` — consistent in Tasks 2 and 4.
- **Test IDs:** T-NV1..6, T-INFO1..4 are new; T16/T18/T19 edited in place. No
  collision with existing T-numbers (existing go to T67 and T-BM*).
