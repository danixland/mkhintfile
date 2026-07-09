# SHA-mode Bundle Reconcile + Submodule Inventory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a SHA-based bundle-reconcile mode to mkhint for packages (openvino) whose bundled deps are git submodules pinned by commit SHA, plus a full submodule-inventory roster that surfaces set drift across versions.

**Architecture:** The `BUNDLE_MANIFEST_FILE` gains an explicit `<pkg> <mode> <rest>` shape. `mode=url` keeps the existing neovim flat-manifest reconcile (renamed `reconcile_bundle_deps_url`). `mode=sha` compares each hint dep's 40-char SHA against the GitHub contents-API SHA for the named submodule path, rewriting drifted `DOWNLOAD` lines and recomputing md5 (`reconcile_bundle_deps_sha`). A separate Job B (`detect_set_drift`) fetches `.gitmodules` at the old and new refs and prints a full inventory roster tagging each submodule bundled/(ignored) with +/- change glyphs.

**Tech Stack:** Bash 4+, `wget` (mocked in tests), `jq` (contents-API `.sha`), `perl`/`sed` (existing rewrite machinery), the existing `tests/mkhint_test.sh` mock harness.

---

## File Structure

- `mkhint` — all production code. New helpers in the bundled-dep section (lines ~439-704), dispatch changes at the 3 call sites (~773, ~1557, ~1766), and `load_bundle_manifests` rewrite (~541).
- `tests/mkhint_test.sh` — new fixtures (openvino-style hint, sha-mode manifest, contents-API + `.gitmodules` wget-stub branches) and 14 new test cases.
- `docs/superpowers/specs/2026-07-09-sha-mode-bundle-reconcile-design.md` — the spec (already committed, reference only).
- `CLAUDE.md` — Key Behaviors update for the new mode (final task).

The mock `wget` stub (`tests/mkhint_test.sh:272`) currently branches on `*deps.txt*`. It must gain two branches: `*api.github.com*contents*` (serve canned JSON) and `*.gitmodules*` (serve canned gitmodules), each reading a fixture file so tests control the response.

---

## Task 1: Manifest 3-field parse (mode discriminator)

**Files:**
- Modify: `mkhint:539-565` (`load_bundle_manifests`, `manifest_url_for`, `pkg_has_manifest`)
- Test: `tests/mkhint_test.sh` (new T-BM-MODE cases near existing bundle tests)

The current `load_bundle_manifests` stores `BUNDLE_MANIFESTS[pkg]=url` (2-field). Migrate to 3-field: field 2 = mode, and store mode + the remainder in parallel maps. Existing neovim entries must be rewritten in the fixture to `neovim url <deps.txt-url>`.

- [ ] **Step 1: Write the failing test**

Add near the other bundle tests in `tests/mkhint_test.sh`. This test sources mkhint's functions in a subshell to check parsing directly:

```bash
# T-BM-MODE: 3-field manifest parse — url and sha modes coexist
cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
neovim url https://raw.githubusercontent.com/neovim/neovim/{VERSION}/deps.txt
openvino sha github:openvinotoolkit/openvino {VERSION} mlas=src/plugins/intel_cpu/thirdparty/mlas onnx=thirdparty/onnx/onnx
EOF
out=$(BUNDLE_MANIFEST_FILE="$MOCK_BASE/bundle-manifests" bash -c '
    source <(sed -n "/^declare -A BUNDLE_MANIFESTS/,/^}/p;/^bundle_mode(/,/^}/p" '"$MKHINT_SRC"')
    BUNDLE_MANIFEST_FILE="'"$MOCK_BASE"'/bundle-manifests"
    load_bundle_manifests
    echo "neovim=$(bundle_mode neovim)"
    echo "openvino=$(bundle_mode openvino)"
')
assert_contains "neovim mode is url"    <(echo "$out") "neovim=url"
assert_contains "openvino mode is sha"  <(echo "$out") "openvino=sha"
```

Note: `MKHINT_SRC` is the path to the mkhint script under test (already set by `run_mkhint`; if not exposed, define `MKHINT_SRC="$(dirname "$0")/../mkhint"` at the top of the test file). Prefer a simpler black-box test if sourcing is brittle — see Step 1b.

- [ ] **Step 1b: Simpler black-box alternative (use this if sourcing is awkward)**

Drive through `-n` on a sha-mode package and assert the reconcile header appears (proves the mode was parsed and dispatched). Defer until Task 4 provides the sha reconcile; for now assert the url mode still works via the existing neovim/bmnvim path with the migrated 3-field fixture:

```bash
# T-BM-MODE: existing url-mode reconcile still works after 3-field migration
cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
bmnvim url https://raw.githubusercontent.com/neovim/neovim/{VERSION}/deps.txt
EOF
printf 'utf8proc_URL https://github.com/juliastrings/utf8proc/archive/v2.9.0.tar.gz\n' > "$MOCK_BASE/manifest_fixture"
out=$(run_mkhint -n bmnvim 2>&1)
assert_contains "url-mode reconcile ran" <(echo "$out") "bundled-dep manifest check"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A2 BM-MODE`
Expected: FAIL — `load_bundle_manifests` still stores the whole remainder as the "url", `bundle_mode` undefined.

- [ ] **Step 3: Write minimal implementation**

Replace `mkhint:539-565` with:

```bash
# Loaded maps: pkg -> mode ("url"|"sha"); pkg -> mode-specific remainder.
# url:  remainder = the {VERSION} manifest URL template.
# sha:  remainder = "<repo> <version-template> <name=path> <name=path>...".
declare -A BUNDLE_MODE=()
declare -A BUNDLE_REST=()
load_bundle_manifests() {
    BUNDLE_MODE=(); BUNDLE_REST=()
    [[ -f "$BUNDLE_MANIFEST_FILE" ]] || return 0
    local line pkg mode rest
    while IFS= read -r line; do
        line="${line%%#*}"
        [[ -z "${line// }" ]] && continue
        read -r pkg mode rest <<< "$line"
        [[ -n "$pkg" && -n "$mode" && -n "$rest" ]] || continue
        BUNDLE_MODE["$pkg"]="$mode"
        BUNDLE_REST["$pkg"]="$rest"
    done < "$BUNDLE_MANIFEST_FILE"
}

# bundle_mode <pkg> — echo the mode for pkg, empty if not listed.
bundle_mode() { printf '%s\n' "${BUNDLE_MODE[$1]:-}"; }

# manifest_url_for <pkg> <version> — echo the url-mode manifest URL for pkg with
# {VERSION} substituted. Non-zero if pkg is not a url-mode entry.
manifest_url_for() {
    local pkg="$1" ver="$2"
    [[ "${BUNDLE_MODE[$pkg]:-}" == "url" ]] || return 1
    local tmpl="${BUNDLE_REST[$pkg]}"
    printf '%s\n' "${tmpl//\{VERSION\}/$ver}"
}

# True if pkg has any bundle manifest configured (either mode).
pkg_has_manifest() {
    [[ -n "${BUNDLE_MODE[$1]:-}" ]]
}
```

Also update the `bmnvim` fixture in `setup()` and any existing bundle-manifest fixture writes to the new 3-field `url` shape (search `tests/mkhint_test.sh` for `bundle-manifests` heredocs and prefix the URL with `url `).

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/mkhint_test.sh 2>&1 | tail -5`
Expected: existing bundle tests (T-BM*) still pass, T-BM-MODE passes, total count up.

- [ ] **Step 5: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "refactor: 3-field bundle manifest (pkg mode rest); url mode explicit

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Rename existing reconcile to url-mode + dispatcher

**Files:**
- Modify: `mkhint:586-703` (rename `reconcile_bundle_deps` → `reconcile_bundle_deps_url`)
- Modify: `mkhint:586` area (add new dispatcher `reconcile_bundle_deps`)
- Test: existing T-BM* cases are the regression net (no new test)

Keep behavior identical; introduce a thin dispatcher so call sites are unchanged.

- [ ] **Step 1: Verify the regression net exists**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -c BM`
Expected: several T-BM lines. These guard the rename.

- [ ] **Step 2: Rename and add dispatcher**

Rename the function at `mkhint:586` from `reconcile_bundle_deps` to `reconcile_bundle_deps_url` (body unchanged). Immediately before it, add:

```bash
# reconcile_bundle_deps <pkg> <hintfile> <manifest_url_or_ignored> <mode-arg>
# Dispatch on the package's configured bundle mode. url-mode uses the manifest
# URL argument (as before); sha-mode ignores it and reads BUNDLE_REST. Keeps the
# three existing call sites unchanged. Returns whatever the mode handler returns.
reconcile_bundle_deps() {
    local pkg="$1"
    case "${BUNDLE_MODE[$pkg]:-url}" in
        sha) reconcile_bundle_deps_sha "$@" ;;
        *)   reconcile_bundle_deps_url "$@" ;;
    esac
}
```

`reconcile_bundle_deps_sha` is defined in Task 4; add a temporary stub so `bash -n` stays clean until then:

```bash
reconcile_bundle_deps_sha() { echo "  $1: sha-mode not yet implemented"; return 0; }
```

- [ ] **Step 3: Syntax + regression check**

Run: `bash -n mkhint && bash tests/mkhint_test.sh 2>&1 | tail -3`
Expected: no syntax error; all existing tests pass (url dispatch reaches the renamed function).

- [ ] **Step 4: Commit**

```bash
git add mkhint
git commit -S -m "refactor: split reconcile into url/sha dispatch, url logic unchanged

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: GitHub token + contents-API helpers

**Files:**
- Create (in `mkhint`, bundled-dep section): `_github_token`, `_fetch_submodule_sha`
- Modify: `tests/mkhint_test.sh:272` (mock_wget — add contents-API branch)
- Test: T-SHA6 (token header), plus a direct helper test

- [ ] **Step 1: Extend mock_wget for the contents API**

In `tests/mkhint_test.sh`, inside the `mock_wget` heredoc (after the `*deps.txt*` branch, before the `else`), add:

```bash
elif [[ "\$url" == *api.github.com*contents* ]]; then
    echo "wget-args: \$*" >> "$MOCK_BASE/api.log"
    # fixture keyed by submodule path tail; default fixture is api_fixture
    if [[ -f "$MOCK_BASE/api_fixture" ]]; then
        cat "$MOCK_BASE/api_fixture" > "\$out"
    else
        exit 1
    fi
```

(The `api.log` captures the full arg list so T-SHA6 can assert on the `Authorization` header.)

- [ ] **Step 2: Write the failing test (token read)**

```bash
# T-SHA6a: _github_token reads github key from nvchecker keyfile
cat > "$MOCK_BASE/keys.toml" << 'EOF'
[keys]
github = "ghp_TESTTOKEN123"
EOF
# nvchecker.toml already has keyfile? add it for this test
cat > "$MOCK_BASE/nvchecker.toml" << EOF
[__config__]
oldver = "$MOCK_BASE/old_ver.json"
newver = "$MOCK_BASE/new_ver.json"
keyfile = "$MOCK_BASE/keys.toml"
EOF
tok=$(run_mkhint_fn '_github_token')
assert_contains "token parsed" <(echo "$tok") "ghp_TESTTOKEN123"
```

Add a `run_mkhint_fn` helper near `run_mkhint` that sources the patched mkhint and calls one function without running main:

```bash
# run_mkhint_fn <fn> [args...] — source the path-patched mkhint (guarded so main
# doesn't execute) and invoke a single function. Requires mkhint to guard its
# main call with: [[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
run_mkhint_fn() {
    local fn="$1"; shift
    MKHINT_NOMAIN=1 bash -c '
        source "'"$PATCHED_MKHINT"'"
        "'"$fn"'" "$@"
    ' _ "$@"
}
```

If mkhint does not already guard `main`, add the guard as part of this task (see Step 3). `PATCHED_MKHINT` is the temp path `run_mkhint` writes; expose it as a global in `run_mkhint`.

- [ ] **Step 3: Implement helpers + main guard**

If `mkhint`'s final line calls `main "$@"` unconditionally, change it to:

```bash
[[ -n "${MKHINT_NOMAIN:-}" ]] || main "$@"
```

Add to the bundled-dep section:

```bash
# _github_token — echo a GitHub token from nvchecker's keyfile, or nothing.
# nvchecker.toml has `keyfile = "<path>"`; that file has `github = "<token>"`.
_github_token() {
    local kf
    kf=$(grep -E '^[[:space:]]*keyfile[[:space:]]*=' "$NVCHECKER_CONFIG" 2>/dev/null \
         | head -1 | cut -d '"' -f2)
    [[ -n "$kf" ]] || return 0
    [[ "$kf" != /* ]] && kf="$(dirname "$NVCHECKER_CONFIG")/$kf"
    [[ -f "$kf" ]] || return 0
    grep -E '^[[:space:]]*github[[:space:]]*=' "$kf" 2>/dev/null \
        | head -1 | cut -d '"' -f2
}

# _fetch_submodule_sha <repo> <path> <ref> — GET the contents API for a submodule
# path at ref; echo "<sha>\t<submodule_owner/repo>". Non-zero on fetch/parse fail.
# Authed with _github_token when present (5000/h vs 60/h anon).
_fetch_submodule_sha() {
    local repo="$1" path="$2" ref="$3"
    repo="${repo#github:}"
    local url="https://api.github.com/repos/${repo}/contents/${path}?ref=${ref}"
    [[ -d "$TMP_DIR" ]] || mkdir -p "$TMP_DIR"
    local out="${TMP_DIR}/api_resp"
    rm -f "$out"
    local tok; tok=$(_github_token)
    local -a auth=()
    [[ -n "$tok" ]] && auth=(--header="Authorization: Bearer $tok")
    wget "${auth[@]}" -O "$out" "$url" >&2 || return 1
    [[ -s "$out" ]] || return 1
    local sha suburl
    sha=$(jq -r '.sha // empty' "$out")
    suburl=$(jq -r '.submodule_git_url // empty' "$out")
    [[ -n "$sha" ]] || return 1
    # normalize submodule_git_url (https://github.com/OWNER/REPO.git) -> owner/repo lc
    local sr=""
    if [[ "$suburl" =~ github\.com/([^/]+)/([^/]+) ]]; then
        printf -v sr '%s/%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]%.git}"
        sr="${sr,,}"
    fi
    printf '%s\t%s\n' "$sha" "$sr"
}
```

- [ ] **Step 4: Write failing test (fetch + auth header)**

```bash
# T-SHA6b: _fetch_submodule_sha sends Authorization header when token present,
# and returns sha + submodule repo
cat > "$MOCK_BASE/api_fixture" << 'EOF'
{"type":"submodule","sha":"d1bc25ec4660cddd87804fcf03b2411b5dfb2e94","submodule_git_url":"https://github.com/openvinotoolkit/mlas.git"}
EOF
rm -f "$MOCK_BASE/api.log"
res=$(run_mkhint_fn _fetch_submodule_sha github:openvinotoolkit/openvino src/plugins/intel_cpu/thirdparty/mlas 2024.4.1)
assert_contains "sha returned"   <(echo "$res") "d1bc25ec4660cddd87804fcf03b2411b5dfb2e94"
assert_contains "subrepo lc"     <(echo "$res") "openvinotoolkit/mlas"
assert_contains "auth header sent" "$MOCK_BASE/api.log" "Authorization: Bearer ghp_TESTTOKEN123"
```

- [ ] **Step 5: Run tests**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A1 SHA6`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: github token + contents-API submodule sha helpers

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: sha-mode reconcile (Job A)

**Files:**
- Replace: the `reconcile_bundle_deps_sha` stub from Task 2 with the real body
- Test: T-SHA1..T-SHA5, T-SHA7

The function parses `BUNDLE_REST[pkg]` (`<repo> <version-template> <name=path>...`), reads the hint's `DOWNLOAD` lines, and for each `name=path` fetches the upstream SHA, finds the matching hint line by submodule repo, and compares/rewrites. Signature matches the url handler: `<pkg> <hintfile> <ignored-url> <mode>`.

- [ ] **Step 1: Add the openvino fixtures + api dispatch by path**

The contents API is called once per submodule path, and each must return a different SHA. Extend the mock so the fixture is keyed by path tail. Replace the contents branch added in Task 3 with:

```bash
elif [[ "\$url" == *api.github.com*contents* ]]; then
    echo "wget-args: \$*" >> "$MOCK_BASE/api.log"
    # path is between /contents/ and ?ref= ; use its tail dir as the fixture key
    p="\${url#*/contents/}"; p="\${p%%\\?*}"
    key="\$(basename "\$p")"
    if [[ -f "$MOCK_BASE/api_\$key.json" ]]; then
        cat "$MOCK_BASE/api_\$key.json" > "\$out"
    elif [[ -f "$MOCK_BASE/api_fixture" ]]; then
        cat "$MOCK_BASE/api_fixture" > "\$out"
    else
        exit 1
    fi
```

Openvino hint fixture (full 40-char SHAs; two deps for the core test — mlas changed, onnx current):

```bash
# openvino-style hint fixture: sha-pinned bundled deps
cat > "$MOCK_HINT/openvino.hint" << 'EOF'
VERSION="2024.4.1"
ARCH="x86_64"
DOWNLOAD="UNSUPPORTED"
MD5SUM=""
DOWNLOAD_x86_64="https://github.com/openvinotoolkit/openvino/archive/2024.4.1/openvino-2024.4.1.tar.gz \
          https://github.com/openvinotoolkit/mlas/archive/d1bc25ec4660cddd87804fcf03b2411b5dfb2e94/mlas-d1bc25ec4660cddd87804fcf03b2411b5dfb2e94.tar.gz \
          https://github.com/onnx/onnx/archive/990217f043af7222348ca8f0301e17fa7b841781/onnx-990217f043af7222348ca8f0301e17fa7b841781.tar.gz"
MD5SUM_x86_64="aaa \
        bbb \
        ccc"
EOF
```

sha-mode manifest for openvino:

```bash
cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
openvino sha github:openvinotoolkit/openvino {VERSION} mlas=src/plugins/intel_cpu/thirdparty/mlas onnx=thirdparty/onnx/onnx
EOF
```

Per-path API fixtures (mlas moved to a new sha, onnx unchanged):

```bash
cat > "$MOCK_BASE/api_mlas.json" << 'EOF'
{"type":"submodule","sha":"a3f9c0177b21ffffffffffffffffffffffffffff","submodule_git_url":"https://github.com/openvinotoolkit/mlas.git"}
EOF
cat > "$MOCK_BASE/api_onnx.json" << 'EOF'
{"type":"submodule","sha":"990217f043af7222348ca8f0301e17fa7b841781","submodule_git_url":"https://github.com/onnx/onnx.git"}
EOF
```

Note the `path` key uses the basename of the submodule path (`mlas`, `onnx`), matching the manifest `name=path` tails. Ensure each manifest path's basename is unique (mlas, onnx, flatbuffers, ittapi, protobuf, onednn, onednn_gpu all differ). Good.

- [ ] **Step 2: Write the failing test (T-SHA1 + T-SHA2)**

Job A is reached through `--check --force` (verified: `--force` is a `--check`
companion flag, gated at `mkhint:1549`; there is no `-f -V` reconcile path).
`--check` needs an nvchecker result for the primary, but `--force` runs the
reconcile even when the primary is unchanged (`was_updated=0 && FORCE=1` still
proceeds). The mock nvchecker returns success/no-bump, so `--check --force`
exercises Job A at the current version. Because this test depends on the Task 6
`--check` wiring for the reconcile loop to invoke sha-mode, **write T-SHA1..5
here but run them after Task 6 is complete** (the dispatcher from Task 2 already
routes sha-mode; Task 6 only adds Job B). If the `--check` loop already calls
`reconcile_bundle_deps` (it does, at `mkhint:1557`), T-SHA1..5 pass as soon as
Task 4 lands — verify by running the suite after this task.

```bash
# T-SHA1/2: sha-mode reconcile — mlas sha drifted (rewrite), onnx current
echo "y" | run_mkhint -C --force openvino > "$MOCK_BASE/sha1.out" 2>&1 || true
assert_contains "report: mlas old->new" "$MOCK_BASE/sha1.out" "d1bc25e -> a3f9c01"
assert_contains "report: onnx current"  "$MOCK_BASE/sha1.out" "onnx"
assert_contains "hint: mlas sha rewritten (path)" "$MOCK_HINT/openvino.hint" "mlas/archive/a3f9c0177b21"
assert_contains "hint: mlas sha rewritten (file)" "$MOCK_HINT/openvino.hint" "mlas-a3f9c0177b21"
assert_contains "hint: onnx sha unchanged"        "$MOCK_HINT/openvino.hint" "onnx-990217f043af"
```

Note: `--check` requires the package to have an nvchecker section and a `.info`
in `REPO_DIR`. Seed a minimal `$MOCK_REPO/development/openvino/openvino.info`
(with `VERSION="2024.4.1"` and a `[openvino]` nvchecker section in the mock
config, or confirm `--check --force` reaches the reconcile loop for a package
whose primary is "current"). If `--check` skips openvino before reaching the
reconcile loop because it has no nvchecker section, add the section to the mock
`nvchecker.toml` and seed `new_ver.json`/`old_ver.json` with `openvino
2024.4.1`.

- [ ] **Step 3: Run test to verify it fails**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A1 SHA1`
Expected: FAIL — stub prints "not yet implemented".

- [ ] **Step 4: Implement `reconcile_bundle_deps_sha`**

Replace the Task-2 stub with:

```bash
# reconcile_bundle_deps_sha <pkg> <hintfile> <ignored> <mode>
# mode = report | apply. Compares each manifest name=path submodule's upstream
# SHA (contents API) against the matching hint DOWNLOAD line's sha, rewrites +
# re-md5s drifted lines. Reports all deps ((current) for unchanged). Returns 2 in
# report mode when there are changes to apply, else 0. apply mode returns 0.
reconcile_bundle_deps_sha() {
    local pkg="$1" hint="$2" _ignored="$3" mode="$4"
    local rest="${BUNDLE_REST[$pkg]}"
    local repo ver_tmpl
    read -r repo ver_tmpl rest <<< "$rest"
    local cur_ver; cur_ver=$(grep '^VERSION=' "$hint" | sed 's/VERSION="//;s/"$//')
    local ref="${ver_tmpl//\{VERSION\}/$cur_ver}"

    local -a urls md5s
    mapfile -t urls < <(parse_multiline_var "DOWNLOAD_x86_64" "$hint")
    (( ${#urls[@]} == 0 )) && mapfile -t urls < <(parse_multiline_var "DOWNLOAD" "$hint")
    mapfile -t md5s < <(parse_multiline_var "MD5SUM_x86_64" "$hint")
    (( ${#md5s[@]} == 0 )) && mapfile -t md5s < <(parse_multiline_var "MD5SUM" "$hint")

    local -a new_urls=("${urls[@]}")
    local -a changed_idx=()
    local -a report_lines=()
    local pair name path upstream_sha subrepo i
    for pair in $rest; do
        name="${pair%%=*}"; path="${pair#*=}"
        local resp; resp=$(_fetch_submodule_sha "$repo" "$path" "$ref") || {
            report_lines+=("  $name: submodule path not found at $ref"); continue; }
        upstream_sha="${resp%%$'\t'*}"; subrepo="${resp#*$'\t'}"
        # find the hint line whose github repo == subrepo
        local found=-1 hrepo
        for (( i=0; i<${#urls[@]}; i++ )); do
            hrepo=$(_url_repo "${urls[$i]}")
            [[ "$hrepo" == "$subrepo" ]] && { found=$i; break; }
        done
        if (( found < 0 )); then
            report_lines+=("  $name: no matching DOWNLOAD line (FYI)"); continue
        fi
        local cur_sha=""
        [[ "${urls[$found]}" =~ /archive/([0-9a-f]{40}) ]] && cur_sha="${BASH_REMATCH[1]}"
        if [[ "$cur_sha" == "$upstream_sha" ]]; then
            report_lines+=("  $name $(printf %.7s "$cur_sha") (current)")
        else
            new_urls[$found]="${urls[$found]//$cur_sha/$upstream_sha}"
            changed_idx+=("$found")
            report_lines+=("  $name $(printf %.7s "$cur_sha") -> $(printf %.7s "$upstream_sha")")
        fi
    done

    if [[ "$mode" == report ]]; then
        echo ""
        echo "$pkg bundled deps (sha):"
        printf '%s\n' "${report_lines[@]}"
        (( ${#changed_idx[@]} > 0 )) && return 2
        return 0
    fi

    # apply
    (( ${#changed_idx[@]} == 0 )) && return 0
    cp "$hint" "${hint}.bak"
    local -a new_md5s=("${md5s[@]}")
    local idx md5
    for idx in "${changed_idx[@]}"; do
        echo "Downloading (bundled): ${new_urls[$idx]}"
        if md5=$(download_file "${new_urls[$idx]}"); then
            new_md5s[$idx]="$md5"
        else
            echo "  download failed for ${new_urls[$idx]} — left as-is"
            new_urls[$idx]="${urls[$idx]}"
        fi
    done
    local var_dl var_md5
    if grep -q '^DOWNLOAD_x86_64=' "$hint"; then var_dl="DOWNLOAD_x86_64"; var_md5="MD5SUM_x86_64"
    else var_dl="DOWNLOAD"; var_md5="MD5SUM"; fi
    local new_dl new_md5v
    new_dl=$(build_multiline_value new_urls);  new_dl="${new_dl#\"}";  new_dl="${new_dl%\"}"
    new_md5v=$(build_multiline_value new_md5s); new_md5v="${new_md5v#\"}"; new_md5v="${new_md5v%\"}"
    perl -i -0pe 'BEGIN{$var=shift;$v=shift} s|^\Q$var\E="[^"]*(?:\\\n[^"]*)*"|$var."=\"".$v."\""|me' "$var_dl" "$new_dl" "$hint"
    perl -i -0pe 'BEGIN{$var=shift;$v=shift} s|^\Q$var\E="[^"]*(?:\\\n[^"]*)*"|$var."=\"".$v."\""|me' "$var_md5" "$new_md5v" "$hint"
    return 0
}
```

Note: this handler reconciles ALL sha-lines including index 0 only if a manifest path matches the primary repo — but no `name=path` names the openvino repo itself, so the primary tarball line (`openvinotoolkit/openvino`) is never matched and stays untouched. Good.

- [ ] **Step 5: Run tests**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A1 'SHA1\|SHA2'`
Expected: PASS. Verify md5 recomputed for the mlas line (changed) and onnx md5 unchanged.

- [ ] **Step 6: Add remaining Job A tests**

```bash
# T-SHA3: contents API 404 for a path — dep skipped, reported, others still processed
mv "$MOCK_BASE/api_mlas.json" "$MOCK_BASE/api_mlas.json.off"   # force 404 for mlas
# restore openvino.hint first (re-emit the fixture) then:
run_mkhint -C --force openvino > "$MOCK_BASE/sha3.out" 2>&1 || true
assert_contains "mlas not-found reported" "$MOCK_BASE/sha3.out" "mlas: submodule path not found"
assert_contains "onnx still current"      "$MOCK_BASE/sha3.out" "onnx"
mv "$MOCK_BASE/api_mlas.json.off" "$MOCK_BASE/api_mlas.json"

# T-SHA4: --new on a sha-mode package prints report, hint unchanged
# (openvino has no .info in mock repo -> --new path prints reconcile without writing;
#  if --new requires a .info, seed a minimal one, then assert hint DOWNLOAD unchanged)

# T-SHA5: two same-repo-different-path deps (onednn cpu vs onednn_gpu) — each
# rewritten against its own path's sha. Add onednn/onednn_gpu lines + fixtures with
# distinct owners (openvinotoolkit/oneDNN vs oneapi-src/oneDNN) and distinct shas;
# assert each line took its own path's upstream sha.

# T-SHA7: manifest name=path whose subrepo matches no DOWNLOAD line -> FYI, nothing added
# (add a bogus name=path to the manifest pointing at a repo absent from the hint;
#  assert "no matching DOWNLOAD line (FYI)" and the hint line count unchanged)
```

Flesh each of these out with the same fixture pattern as T-SHA1 (per-path `api_<name>.json`, restore the `openvino.hint` fixture before each run since apply rewrites it). Keep the color/grep guards using `(( FAIL++ )) || true`.

- [ ] **Step 7: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: sha-mode bundled-dep reconcile (Job A)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Submodule inventory roster (Job B)

**Files:**
- Create (in `mkhint`): `_fetch_gitmodules_paths`, `detect_set_drift`
- Modify: `tests/mkhint_test.sh:272` (mock_wget — add `.gitmodules` branch)
- Test: T-SET1..T-SET6

- [ ] **Step 1: Extend mock_wget for .gitmodules (keyed by ref)**

Add before the `else` in the mock_wget heredoc:

```bash
elif [[ "\$url" == *.gitmodules* ]]; then
    # ref is the path segment before /.gitmodules in a raw URL:
    # raw.githubusercontent.com/OWNER/REPO/<ref>/.gitmodules
    ref="\${url%%/.gitmodules*}"; ref="\${ref##*/}"
    if [[ -f "$MOCK_BASE/gitmodules_\$ref" ]]; then
        cat "$MOCK_BASE/gitmodules_\$ref" > "\$out"
    else
        exit 1
    fi
```

- [ ] **Step 2: Write the failing test (T-SET1..4)**

```bash
# .gitmodules fixtures: old has onnx+gtest+mlas; new drops onnx, adds newdep, keeps gtest+mlas
cat > "$MOCK_BASE/gitmodules_2024.4.1" << 'EOF'
[submodule "onnx"]
	path = thirdparty/onnx/onnx
	url = https://github.com/onnx/onnx.git
[submodule "mlas"]
	path = src/plugins/intel_cpu/thirdparty/mlas
	url = https://github.com/openvinotoolkit/mlas.git
[submodule "gtest"]
	path = thirdparty/gtest/gtest
	url = https://github.com/openvinotoolkit/googletest.git
EOF
cat > "$MOCK_BASE/gitmodules_2024.5.0" << 'EOF'
[submodule "newdep"]
	path = src/plugins/foo/thirdparty/newdep
	url = https://github.com/foo/newdep.git
[submodule "mlas"]
	path = src/plugins/intel_cpu/thirdparty/mlas
	url = https://github.com/openvinotoolkit/mlas.git
[submodule "gtest"]
	path = thirdparty/gtest/gtest
	url = https://github.com/openvinotoolkit/googletest.git
EOF
# manifest bundles mlas + onnx (onnx removal should raise ACTION)
cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
openvino sha github:openvinotoolkit/openvino {VERSION} mlas=src/plugins/intel_cpu/thirdparty/mlas onnx=thirdparty/onnx/onnx
EOF
out=$(run_mkhint_fn detect_set_drift openvino 2024.4.1 2024.5.0)
assert_contains "onnx removed ACTION"   <(echo "$out") "onnx"
assert_contains "onnx ACTION flag"      <(echo "$out") "ACTION"
assert_contains "newdep added review"   <(echo "$out") "newdep"
assert_contains "mlas bundled"          <(echo "$out") "mlas"
assert_contains "gtest ignored"         <(echo "$out") "(ignored)"
```

- [ ] **Step 3: Run test to verify it fails**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A1 SET1`
Expected: FAIL — `detect_set_drift` undefined.

- [ ] **Step 4: Implement Job B**

The manifest's tracked paths come from `BUNDLE_REST` (`name=path` pairs). Build a set of bundled paths, then roster.

```bash
# _fetch_gitmodules_paths <repo> <ref> — echo each submodule "path" line from the
# .gitmodules at ref (one per line). Non-zero on fetch fail.
_fetch_gitmodules_paths() {
    local repo="${1#github:}" ref="$2"
    local url="https://raw.githubusercontent.com/${repo}/${ref}/.gitmodules"
    [[ -d "$TMP_DIR" ]] || mkdir -p "$TMP_DIR"
    local out="${TMP_DIR}/gitmodules_${ref}"
    rm -f "$out"
    wget -O "$out" "$url" >&2 || return 1
    [[ -s "$out" ]] || return 1
    grep -E '^[[:space:]]*path[[:space:]]*=' "$out" | sed 's/.*=[[:space:]]*//'
}

# detect_set_drift <pkg> <old-ver> <new-ver> — print the full submodule inventory
# roster. Diffs .gitmodules@old vs @new; tags each submodule bundled/(ignored),
# with +/- change glyphs and ACTION (bundled removed) / review (new unbundled).
# FYI only, never edits. Skips with a notice if a fetch fails.
detect_set_drift() {
    local pkg="$1" oldv="$2" newv="$3"
    local rest="${BUNDLE_REST[$pkg]}"
    local repo; read -r repo _ rest <<< "$rest"
    # bundled paths set
    local -A bundled=()
    local pair
    for pair in $rest; do bundled["${pair#*=}"]=1; done

    local -a new_paths old_paths
    mapfile -t new_paths < <(_fetch_gitmodules_paths "$repo" "$newv") || {
        echo "  $pkg: .gitmodules@$newv unavailable — inventory skipped"; return 0; }
    if [[ "$oldv" == "$newv" ]]; then
        old_paths=("${new_paths[@]}")
    else
        mapfile -t old_paths < <(_fetch_gitmodules_paths "$repo" "$oldv") || {
            echo "  $pkg: .gitmodules@$oldv unavailable — inventory skipped"; return 0; }
    fi
    local -A in_old=() in_new=()
    local p; for p in "${old_paths[@]}"; do in_old["$p"]=1; done
    for p in "${new_paths[@]}"; do in_new["$p"]=1; done

    echo ""
    echo "$pkg submodule inventory $oldv -> $newv:"
    # rows for all @new paths (unchanged or added), then @old-only (removed)
    local glyph tag
    for p in "${new_paths[@]}"; do
        glyph=" "; [[ -z "${in_old[$p]:-}" ]] && glyph="+"
        if [[ -n "${bundled[$p]:-}" ]]; then
            tag="bundled"
        else
            tag="(ignored)"; [[ "$glyph" == "+" ]] && tag="review (new, not bundled)"
        fi
        printf '  %s %-46s %s\n' "$glyph" "$p" "$tag"
    done
    for p in "${old_paths[@]}"; do
        [[ -n "${in_new[$p]:-}" ]] && continue   # still present, already listed
        if [[ -n "${bundled[$p]:-}" ]]; then
            printf '  %s %-46s %s\n' "-" "$p" "ACTION (bundled, removed upstream)"
        else
            printf '  %s %-46s %s\n' "-" "$p" "(ignored, removed upstream)"
        fi
    done
}
```

- [ ] **Step 5: Run tests**

Run: `bash tests/mkhint_test.sh 2>&1 | grep -A1 'SET1\|SET2\|SET3\|SET4'`
Expected: PASS.

- [ ] **Step 6: Add T-SET5 (fetch fail) and T-SET6 (force no-bump single fetch)**

```bash
# T-SET5: .gitmodules fetch fails at old ref -> inventory skipped, no crash
out=$(run_mkhint_fn detect_set_drift openvino 1999.0.0 2024.5.0)   # no gitmodules_1999.0.0 fixture
assert_contains "fetch-fail skip notice" <(echo "$out") "inventory skipped"

# T-SET6: force no-bump (old==new) -> one ref, roster prints, all blank-change
out=$(run_mkhint_fn detect_set_drift openvino 2024.5.0 2024.5.0)
assert_contains "roster prints on force" <(echo "$out") "submodule inventory 2024.5.0 -> 2024.5.0"
assert_not_contains "no + glyph"         <(echo "$out") "+ src/plugins/foo"
```

(Add an `assert_not_contains` helper mirroring `assert_contains` if none exists — grep with `! grep -q`, `(( FAIL++ )) || true` on failure.)

- [ ] **Step 7: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: submodule inventory roster (Job B, set-drift)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Wire Job A + Job B into --check and --new

**Files:**
- Modify: `mkhint:1756-1775` (`--check`/`--hintfile` reconcile block) — call Job B
- Modify: `mkhint:765-774` (`--new` reconcile block) — dispatch handles sha via Task 2
- Modify: the `--check` bump path (where updated packages are reconciled, ~1557) — pass old/new versions to `detect_set_drift`
- Test: T-SHA1..5 rerun through `--check --force`, roster appears on bump

The dispatcher (Task 2) already routes sha-mode through `reconcile_bundle_deps`, so the existing call sites invoke Job A without change. Job B needs an explicit call with old+new versions.

- [ ] **Step 0: Fix the manifest_url_for guard that skips sha packages**

CRITICAL: the `--check` reconcile loop (`mkhint:1553`) and the `--hintfile` block
(`mkhint:1762`) resolve `murl` via `manifest_url_for` and `|| continue`/use it.
After Task 1, `manifest_url_for` returns non-zero for sha-mode packages, so those
sites would silently SKIP openvino. At each of the three reconcile call sites,
resolve `murl` only for url mode and pass an empty placeholder for sha:

```bash
        local murl=""
        if [[ "$(bundle_mode "$pkg")" == "url" ]]; then
            murl=$(manifest_url_for "$pkg" "$cur") || continue
        fi
        reconcile_bundle_deps "$pkg" "$hintpath" "$murl" report || rc=$?
```

Apply the same shape at `mkhint:765-774` (`--new`), `mkhint:1553-1557`
(`--check`), and `mkhint:1762-1766` (`--hintfile`). The dispatcher (Task 2) sends
sha packages to `reconcile_bundle_deps_sha`, which ignores `murl`.

- [ ] **Step 1: Find where --check holds old and new version**

Run: `grep -n 'updated\|old.*ver\|new.*ver\|VERSION' mkhint | sed -n '1,40p'`
Identify the `--check` loop that knows a package bumped from `cur` to `latest`. Job B is called there with `(pkg, old, new)`. Under `--force` with no bump, old==new==current.

- [ ] **Step 2: Add the Job B call at the reconcile site**

In the `--check` reconcile block (the loop near `mkhint:1540-1568` that already gates on `pkg_has_manifest` + `was_updated || FORCE`), after the Job A `reconcile_bundle_deps` report/apply, add for sha-mode packages:

```bash
        if [[ "$(bundle_mode "$pkg")" == "sha" ]]; then
            # Job B inventory: old = pre-bump version, new = bumped-to (equal under --force no-bump)
            local _old_ver="${prev_version[$pkg]:-$cur}" _new_ver="$cur"
            detect_set_drift "$pkg" "$_old_ver" "$_new_ver" || true
        fi
```

Adjust `prev_version`/`cur`/`latest` to the actual variable names found in Step 1 — the intent is: `_old_ver` = version before this run's bump, `_new_ver` = version after. If the code overwrites the hint VERSION before this point, capture the old value earlier in the loop.

- [ ] **Step 3: Write the integration test**

```bash
# T-SHA-CHECK: --check --force on openvino runs Job A reconcile + Job B roster
# (fixtures from Task 4 + Task 5 in place; api_*.json + gitmodules_* + manifest)
echo "y" | run_mkhint -C --force openvino > "$MOCK_BASE/chk.out" 2>&1 || true
assert_contains "Job A ran"  "$MOCK_BASE/chk.out" "bundled deps (sha)"
assert_contains "Job B ran"  "$MOCK_BASE/chk.out" "submodule inventory"
```

- [ ] **Step 4: Run tests**

Run: `bash tests/mkhint_test.sh 2>&1 | tail -3`
Expected: full suite green, new count reflects all T-SHA*/T-SET* cases.

- [ ] **Step 5: Commit**

```bash
git add mkhint tests/mkhint_test.sh
git commit -S -m "feat: wire sha reconcile + inventory into --check/--force

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Docs + full-suite verification

**Files:**
- Modify: `CLAUDE.md` (Key Behaviors — the `--check bundled-dep reconcile` bullet)
- Verify: full suite, `bash -n`, gitleaks

- [ ] **Step 1: Update CLAUDE.md**

Extend the existing `--check bundled-dep reconcile` bullet in `CLAUDE.md` Key Behaviors to note the two modes:

```markdown
- `--check` bundled-dep reconcile has two manifest modes (field 2 of each
  `BUNDLE_MANIFEST_FILE` line, `<pkg> <mode> <rest>`):
  - **url mode** (neovim): flat upstream `deps.txt`, reconcile by dep *version*
    (unchanged behavior, now spelled `reconcile_bundle_deps_url`).
  - **sha mode** (openvino): deps are github submodules pinned by full 40-char
    commit SHA in `archive/<sha>/` DOWNLOAD lines. `reconcile_bundle_deps_sha`
    reads `<repo> <version-template> <name=path>...` from the manifest, fetches
    each submodule's SHA via the GitHub contents API (`_fetch_submodule_sha`,
    authed from nvchecker's keyfile via `_github_token` when present, else anon),
    matches the hint DOWNLOAD line by `submodule_git_url` repo, and rewrites +
    re-md5s any line whose SHA drifted. Reports all deps, `(current)` for
    unchanged. Runs on a primary bump or under `--force`.
  - **Job B submodule inventory** (`detect_set_drift`): on a sha-mode bump or
    `--force`, diffs `.gitmodules` at the old and new refs and prints a full
    roster of every submodule tagged bundled/`(ignored)` with `+`/`-` change
    glyphs, raising `ACTION` on a bundled dep removed upstream and `review` on a
    new unbundled one. FYI only, never edits the bundle set.
```

- [ ] **Step 2: Full verification**

Run:
```bash
bash -n mkhint && echo "syntax OK"
bash tests/mkhint_test.sh 2>&1 | tail -5
git log --format='%h %G? %s' -8
```
Expected: syntax OK; `0 failed`; every new commit shows `G` (signed).

- [ ] **Step 3: gitleaks**

The commit hook already runs gitleaks. If running manually: `gitleaks detect --no-banner` → no leaks. (The `ghp_TESTTOKEN123` fixture is a fake test token; confirm gitleaks does not flag it — if it does, replace with a clearly-fake non-`ghp_` string in the test.)

- [ ] **Step 4: Commit docs**

```bash
git add CLAUDE.md
git commit -S -m "docs: sha-mode bundle reconcile + submodule inventory in CLAUDE.md

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Deployment (user-driven, after all tasks green)

Per the project release cadence (see HANDOFF/CLAUDE.md), do NOT release until the user tests live:

1. Deploy `mkhint` + `mkhint.bash-completion` to the `buildsystem` VM, md5-verify.
2. User adds the real openvino sha-mode entry to their `BUNDLE_MANIFEST_FILE`, rewrites `openvino.SlackBuild`/`.info` to full-SHA DOWNLOAD lines (user-owned prerequisite), and tests `mkhint -C --force openvino` live.
3. Only after live confirmation: bump `MKHINT_VERSION`, update `CHANGELOG.md`, commit signed, tag signed `vX.Y.Z`, push both remotes, redeploy to VM with md5 verification. Never overwrite a pushed tag.

Bundle-completion note: no completion change is needed (openvino is completed as an existing hint/package name), but verify `-C`/`--force` still complete.
```
