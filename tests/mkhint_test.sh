#!/bin/bash
# mkhint test suite - uses mock dirs, no real downloads

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/mkhint"
MOCK_BASE="/tmp/mkhint_test_$$"
MOCK_REPO="$MOCK_BASE/repo"
MOCK_HINT="$MOCK_BASE/hints"
MOCK_PKGS="$MOCK_BASE/packages"
MOCK_TMP="$MOCK_BASE/tmp"

PASS=0
FAIL=0
ERRORS=()

setup() {
    mkdir -p "$MOCK_REPO/network/curl" \
             "$MOCK_REPO/development/protoc-gen-go-grpc" \
             "$MOCK_REPO/development/clion" \
             "$MOCK_REPO/development/ghpkg" \
             "$MOCK_REPO/python/pypkg" \
             "$MOCK_REPO/development/glpkg" \
             "$MOCK_REPO/development/cbpkg" \
             "$MOCK_REPO/development/crpkg" \
             "$MOCK_REPO/multimedia/yt-dlp" \
             "$MOCK_REPO/development/gopkg" \
             "$MOCK_REPO/development/rustpkg" \
             "$MOCK_REPO/development/mixedpkg" \
             "$MOCK_REPO/system/datedpkg" \
             "$MOCK_REPO/editors/bmnvim" \
             "$MOCK_HINT" \
             "$MOCK_TMP"

    # Standard single-URL .info
    cat > "$MOCK_REPO/network/curl/curl.info" << 'EOF'
PRGNAM="curl"
VERSION="8.5.0"
HOMEPAGE="https://curl.se/"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
REQUIRES=""
MAINTAINER="Test"
EMAIL="test@test.com"
EOF

    # .info whose VERSION is underscore-dated but DOWNLOAD URL is dash-dated
    # (exploitdb pattern). --new -V must bump both forms.
    cat > "$MOCK_REPO/system/datedpkg/datedpkg.info" << 'EOF'
PRGNAM="datedpkg"
VERSION="2026_04_30"
HOMEPAGE="https://example.com/"
DOWNLOAD="https://example.com/archive/2026-04-30/datedpkg-2026-04-30.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
REQUIRES=""
MAINTAINER="Test"
EMAIL="test@test.com"
EOF

    # Multiline DOWNLOAD .info
    cat > "$MOCK_REPO/development/protoc-gen-go-grpc/protoc-gen-go-grpc.info" << 'EOF'
PRGNAM="protoc-gen-go-grpc"
VERSION="1.3.0"
HOMEPAGE="https://github.com/grpc/grpc-go"
DOWNLOAD="https://github.com/grpc/grpc-go/archive/refs/tags/cmd/protoc-gen-go-grpc/v1.3.0/grpc-go-cmd-protoc-gen-go-grpc-v1.3.0.tar.gz \
          https://github.com/protocolbuffers/protobuf-go/archive/v1.28.1/protobuf-go-1.28.1.tar.gz"
MD5SUM="9d3abc100f411a59907528e55e772a10 \
        e11cccd452bbf4296f72bf323d7b8690"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
REQUIRES="protoc-gen-go"
MAINTAINER="Test"
EMAIL="test@test.com"
EOF

    # DOWNLOAD=UNSUPPORTED, DOWNLOAD_x86_64 has URL
    cat > "$MOCK_REPO/development/clion/clion.info" << 'EOF'
PRGNAM="clion"
VERSION="2025.3"
HOMEPAGE="https://www.jetbrains.com/clion/"
DOWNLOAD="UNSUPPORTED"
MD5SUM=""
DOWNLOAD_x86_64="https://download.jetbrains.com/cpp/CLion-2025.3.tar.gz"
MD5SUM_x86_64="dff91fe793b8d3ee2446dd340288eef5"
REQUIRES=""
MAINTAINER="Test"
EMAIL="test@test.com"
EOF

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

    # github .info with a dash in the package name (needs TOML quoting)
    cat > "$MOCK_REPO/multimedia/yt-dlp/yt-dlp.info" << 'EOF'
PRGNAM="yt-dlp"
VERSION="2024.1.1"
HOMEPAGE="https://github.com/yt-dlp/yt-dlp"
DOWNLOAD="https://github.com/yt-dlp/yt-dlp/archive/2024.1.1/yt-dlp-2024.1.1.tar.gz"
MD5SUM="55555555555555555555555555555555"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
REQUIRES=""
MAINTAINER="Test"
EMAIL="test@test.com"
EOF

    # phantom-dep fixtures: packages requiring -current phantom deps
    cat > "$MOCK_REPO/development/gopkg/gopkg.info" << 'EOF'
PRGNAM="gopkg"
VERSION="1.0.0"
HOMEPAGE="https://example.com/gopkg"
DOWNLOAD="https://example.com/gopkg-1.0.0.tar.gz"
MD5SUM="33333333333333333333333333333333"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
REQUIRES="google-go-lang"
MAINTAINER="Test"
EMAIL="test@test.com"
EOF

    cat > "$MOCK_REPO/development/rustpkg/rustpkg.info" << 'EOF'
PRGNAM="rustpkg"
VERSION="1.0.0"
HOMEPAGE="https://example.com/rustpkg"
DOWNLOAD="https://example.com/rustpkg-1.0.0.tar.gz"
MD5SUM="44444444444444444444444444444444"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
REQUIRES="rust-opt other-dep"
MAINTAINER="Test"
EMAIL="test@test.com"
EOF

    # mixedpkg: real deps + a phantom dep, gets a manual hint in some tests
    cat > "$MOCK_REPO/development/mixedpkg/mixedpkg.info" << 'EOF'
PRGNAM="mixedpkg"
VERSION="3.2.1"
HOMEPAGE="https://example.com/mixedpkg"
DOWNLOAD="https://example.com/mixedpkg-3.2.1.tar.gz"
MD5SUM="66666666666666666666666666666666"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
REQUIRES="libfoo google-go-lang libbar"
MAINTAINER="Test"
EMAIL="test@test.com"
EOF

    # bundled-dep manifest fixture (T-BM10/11)
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

    # phantom-dep list consumed by --fix-current and --new
    cat > "$MOCK_BASE/phantom-deps" << 'EOF'
# deps unneeded on -current
rust-opt
google-go-lang
EOF

    # nvchecker config + keyfile for tests
    cat > "$MOCK_BASE/keys.toml" << 'EOF'
[keys]
github = "FAKE_TEST_TOKEN_123"
EOF
    cat > "$MOCK_BASE/nvchecker.toml" << EOF
[__config__]
oldver = "$MOCK_BASE/old_ver.json"
newver = "$MOCK_BASE/new_ver.json"
keyfile = "$MOCK_BASE/keys.toml"
EOF
    # keyfile pre-seeded with versions the mock nvchecker will "find"
    cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": { "curl": { "version": "8.9.0" }, "clion": { "version": "2025.4" } } }
EOF
    cp "$MOCK_BASE/new_ver.json" "$MOCK_BASE/old_ver.json"
}

teardown() {
    rm -rf "$MOCK_BASE"
}

# patch_mkhint — write a path-patched copy of mkhint (mock dirs baked in) to
# $PATCHED_MKHINT and echo that path. Shared by run_mkhint and run_mkhint_fn so
# both execute/source the identical patched script.
PATCHED_MKHINT="$MOCK_BASE/mkhint_patched"
patch_mkhint() {
    sed \
        -e "s|REPO_DIR=\".*\"|REPO_DIR=\"$MOCK_REPO\"|" \
        -e "s|HINT_DIR=\".*\"|HINT_DIR=\"$MOCK_HINT\"|" \
        -e "s|TMP_DIR=\".*\"|TMP_DIR=\"$MOCK_TMP\"|" \
        -e "s|NVCHECKER_CONFIG=\".*\"|NVCHECKER_CONFIG=\"$MOCK_BASE/nvchecker.toml\"|" \
        -e "s|PHANTOM_DEPS_FILE=\".*\"|PHANTOM_DEPS_FILE=\"$MOCK_BASE/phantom-deps\"|" \
        -e "s|BUNDLE_MANIFEST_FILE=\".*\"|BUNDLE_MANIFEST_FILE=\"$MOCK_BASE/bundle-manifests\"|" \
        -e "s|PACKAGES_DIR=\".*\"|PACKAGES_DIR=\"$MOCK_PKGS\"|" \
        -e "s|MKHINT_CONFIG=\".*\"|MKHINT_CONFIG=\"$MOCK_BASE/config\"|" \
        "$SCRIPT" > "$PATCHED_MKHINT"
}

run_mkhint() {
    patch_mkhint
    bash "$PATCHED_MKHINT" "$@"
    return $?
}

# run_mkhint_fn <fn> [args...] — source the path-patched mkhint (guarded so main
# doesn't execute) and invoke a single function.
run_mkhint_fn() {
    local fn="$1"; shift
    patch_mkhint
    MKHINT_NOMAIN=1 bash -c '
        source "'"$PATCHED_MKHINT"'"
        "'"$fn"'" "$@"
    ' _ "$@"
}

# run_sha_reconcile <pkg> <hint> <ignored> <mode> — source the patched mkhint,
# load the bundle manifests (so BUNDLE_REST/BUNDLE_MODE are populated), then call
# reconcile_bundle_deps_sha directly. Mirrors run_mkhint_fn but adds the manifest
# load the sha reconcile depends on.
run_sha_reconcile() {
    patch_mkhint
    MKHINT_NOMAIN=1 bash -c '
        source "'"$PATCHED_MKHINT"'"
        load_bundle_manifests
        reconcile_bundle_deps_sha "$@"
    ' _ "$@"
}

# run_set_drift <pkg> <old-ver> <new-ver> — source the patched mkhint, load the
# bundle manifests (so BUNDLE_REST is populated), then call detect_set_drift.
run_set_drift() {
    patch_mkhint
    MKHINT_NOMAIN=1 bash -c '
        source "'"$PATCHED_MKHINT"'"
        load_bundle_manifests
        detect_set_drift "$@"
    ' _ "$@"
}

# Mock wget — writes fake content, md5 will be deterministic. URLs containing
# deps.txt instead serve a manifest fixture ($MOCK_BASE/manifest_fixture) if
# present, so bundled-dep manifest tests can control fetch_manifest's input.
mock_wget() {
    # Replace wget in PATH with a fake that writes URL as content
    mkdir -p "$MOCK_BASE/bin"
    cat > "$MOCK_BASE/bin/wget" << EOF
#!/bin/bash
all_args="\$*"
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
elif [[ "\$url" == *api.github.com*contents* ]]; then
    echo "wget-args: \$all_args" >> "$MOCK_BASE/api.log"
    p="\${url#*/contents/}"; p="\${p%%\\?*}"
    key="\$(basename "\$p")"
    if [[ -f "$MOCK_BASE/api_\$key.json" ]]; then
        cat "$MOCK_BASE/api_\$key.json" > "\$out"
    elif [[ -f "$MOCK_BASE/api_fixture" ]]; then
        cat "$MOCK_BASE/api_fixture" > "\$out"
    else
        exit 1
    fi
elif [[ "\$url" == *.gitmodules* ]]; then
    ref="\${url%%/.gitmodules*}"; ref="\${ref##*/}"
    if [[ -f "$MOCK_BASE/gitmodules_\$ref" ]]; then
        cat "$MOCK_BASE/gitmodules_\$ref" > "\$out"
    else
        exit 1
    fi
else
    echo "FAKE_CONTENT_FOR_\${url}" > "\$out"
fi
exit 0
EOF
    chmod +x "$MOCK_BASE/bin/wget"
    export PATH="$MOCK_BASE/bin:$PATH"
}

# Mock nvchecker, nvtake into $MOCK_BASE/bin (real jq used if present)
mock_nvchecker_tools() {
    mkdir -p "$MOCK_BASE/bin"

    # nvchecker: record invocations, no-op success (keyfile pre-seeded by setup/tests)
    cat > "$MOCK_BASE/bin/nvchecker" << EOF
#!/bin/bash
echo "nvchecker \$*" >> "$MOCK_BASE/nvchecker.log"
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

    if ! command -v jq &> /dev/null; then
        echo "WARNING: real jq not found; install jq to run nvchecker tests" >&2
    fi
}

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

assert_contains() {
    local desc="$1" file="$2" pattern="$3"
    if grep -q "$pattern" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        (( PASS++ ))
    else
        echo "  FAIL: $desc"
        echo "        expected pattern: $pattern"
        echo "        file contents:"
        cat "$file" 2>/dev/null | sed 's/^/          /'
        (( FAIL++ ))
        ERRORS+=("$desc")
    fi
}

assert_not_contains() {
    local desc="$1" file="$2" pattern="$3"
    if ! grep -q "$pattern" "$file" 2>/dev/null; then
        echo "  PASS: $desc"
        (( PASS++ ))
    else
        echo "  FAIL: $desc"
        echo "        unexpected pattern found: $pattern"
        (( FAIL++ ))
        ERRORS+=("$desc")
    fi
}

assert_file_exists() {
    local desc="$1" file="$2"
    if [[ -f "$file" ]]; then
        echo "  PASS: $desc"
        (( PASS++ ))
    else
        echo "  FAIL: $desc (file not found: $file)"
        (( FAIL++ ))
        ERRORS+=("$desc")
    fi
}

assert_file_not_exists() {
    local desc="$1" file="$2"
    if [[ ! -f "$file" ]]; then
        echo "  PASS: $desc"
        (( PASS++ ))
    else
        echo "  FAIL: $desc (file should not exist: $file)"
        (( FAIL++ ))
        ERRORS+=("$desc")
    fi
}

assert_exit_code() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" -eq "$expected" ]]; then
        echo "  PASS: $desc (exit $actual)"
        (( PASS++ ))
    else
        echo "  FAIL: $desc (expected exit $expected, got $actual)"
        (( FAIL++ ))
        ERRORS+=("$desc")
    fi
}

# ─── TESTS ────────────────────────────────────────────────────────────────────

echo "========================================"
echo " mkhint test suite"
echo "========================================"

setup
mock_wget
mock_nvchecker_tools
mock_slackrepo

# ── T1: --new from .info, no version ──────────────────────────────────────────
echo ""
echo "T1: --new from .info template, no version"
run_mkhint -n curl
assert_file_exists    "hint file created"        "$MOCK_HINT/curl.hint"
assert_contains       "VERSION from .info"       "$MOCK_HINT/curl.hint" 'VERSION="8.5.0"'
assert_not_contains   "no PRGNAM"                "$MOCK_HINT/curl.hint" '^PRGNAM='
assert_not_contains   "no HOMEPAGE"              "$MOCK_HINT/curl.hint" '^HOMEPAGE='
assert_not_contains   "no MAINTAINER"            "$MOCK_HINT/curl.hint" '^MAINTAINER='
assert_contains       "ARCH set x86_64"          "$MOCK_HINT/curl.hint" 'ARCH="x86_64"'
assert_contains       "REQUIRES commented out"   "$MOCK_HINT/curl.hint" '#REQUIRES='
assert_not_contains   "no NODOWNLOAD"            "$MOCK_HINT/curl.hint" 'NODOWNLOAD'

# ── T2: --new from .info with version → updates version + md5 ─────────────────
echo ""
echo "T2: --new from .info with -v → version set, md5 recalculated"
rm "$MOCK_HINT/curl.hint"
run_mkhint -n curl -V 8.6.0
assert_contains       "VERSION updated"          "$MOCK_HINT/curl.hint" 'VERSION="8.6.0"'
assert_contains       "URL has new version"      "$MOCK_HINT/curl.hint" 'curl-8.6.0'
# md5 should not be the original (was recalculated via mock wget)
assert_not_contains   "MD5SUM not original"      "$MOCK_HINT/curl.hint" 'MD5SUM="abc123def456'

# ── T3: --new with -N, no version → NODOWNLOAD added, no downloads ────────────
echo ""
echo "T3: --new -N no version → NODOWNLOAD=yes, no download"
rm "$MOCK_HINT/curl.hint"
run_mkhint -n curl -N
assert_contains       "NODOWNLOAD present"       "$MOCK_HINT/curl.hint" 'NODOWNLOAD=yes'

# ── T4: --new with -v -N → version set, downloads run, NODOWNLOAD added ───────
echo ""
echo "T4: --new -v -N → version + md5 updated + NODOWNLOAD=yes"
rm "$MOCK_HINT/curl.hint"
run_mkhint -n curl -V 8.7.0 -N
assert_contains       "VERSION updated"          "$MOCK_HINT/curl.hint" 'VERSION="8.7.0"'
assert_not_contains   "MD5SUM not original"      "$MOCK_HINT/curl.hint" 'MD5SUM="abc123def456'
assert_contains       "NODOWNLOAD present"       "$MOCK_HINT/curl.hint" 'NODOWNLOAD=yes'

# ── T5: --new when hint already exists → backup + empty skeleton ───────────────
echo ""
echo "T5: --new when hint exists → backup + empty skeleton"
run_mkhint -n curl  # creates again (hint already gone from T4 rm... wait, we didn't rm)
assert_file_exists    "backup created"           "$MOCK_HINT/curl.hint.bak"
assert_contains       "skeleton VERSION"         "$MOCK_HINT/curl.hint" 'VERSION='
assert_contains       "skeleton DOWNLOAD"        "$MOCK_HINT/curl.hint" 'DOWNLOAD=""'

# ── T6: --hintfile update single URL ──────────────────────────────────────────
echo ""
echo "T6: --hintfile -v update single URL → version + md5 updated"
# Prepare a hint to update
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
run_mkhint -f curl -V 8.9.0
assert_contains       "VERSION updated"          "$MOCK_HINT/curl.hint" 'VERSION="8.9.0"'
assert_contains       "URL updated"              "$MOCK_HINT/curl.hint" 'curl-8.9.0'
assert_not_contains   "MD5SUM updated"           "$MOCK_HINT/curl.hint" 'abc123def456'
assert_file_exists    "backup created"           "$MOCK_HINT/curl.hint.bak"

# ── T7: --hintfile -v -N → version + md5 updated + NODOWNLOAD ─────────────────
echo ""
echo "T7: --hintfile -v -N → version + md5 + NODOWNLOAD=yes"
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
run_mkhint -f curl -V 9.0.0 -N
assert_contains       "VERSION updated"          "$MOCK_HINT/curl.hint" 'VERSION="9.0.0"'
assert_not_contains   "MD5SUM recalculated"      "$MOCK_HINT/curl.hint" 'abc123def456'
assert_contains       "NODOWNLOAD present"       "$MOCK_HINT/curl.hint" 'NODOWNLOAD=yes'

# ── T8: DOWNLOAD=UNSUPPORTED, DOWNLOAD_x86_64 has URL ─────────────────────────
echo ""
echo "T8: DOWNLOAD=UNSUPPORTED → skip 32bit, recalc x86_64 md5"
run_mkhint -n clion
assert_contains       "DOWNLOAD UNSUPPORTED kept" "$MOCK_HINT/clion.hint" 'DOWNLOAD="UNSUPPORTED"'

# Update it
run_mkhint -f clion -V 2025.4
assert_contains       "VERSION updated"           "$MOCK_HINT/clion.hint" 'VERSION="2025.4"'
assert_contains       "DOWNLOAD still UNSUPPORTED" "$MOCK_HINT/clion.hint" 'DOWNLOAD="UNSUPPORTED"'
assert_not_contains   "x86_64 md5 updated"        "$MOCK_HINT/clion.hint" 'dff91fe793b8d3ee2446dd340288eef5'

# ── T9: --no-dl alone → error exit 1 ──────────────────────────────────────────
echo ""
echo "T9: --no-dl alone → exit 1"
set +e
run_mkhint -N 2>/dev/null
code=$?
set -e
assert_exit_code      "-N alone exits 1"         1 "$code"

# ── T10: --hintfile missing file → exit 2 ─────────────────────────────────────
echo ""
echo "T10: --hintfile on nonexistent file → exit 2"
set +e
run_mkhint -f nonexistent -V 1.0 2>/dev/null
code=$?
set -e
assert_exit_code      "missing hintfile exits 2" 2 "$code"

# ── T11: --delete existing hint ───────────────────────────────────────────────
echo ""
echo "T11: --delete removes hint and .bak"
touch "$MOCK_HINT/curl.hint" "$MOCK_HINT/curl.hint.bak"
run_mkhint -d curl
assert_file_not_exists "hint deleted"            "$MOCK_HINT/curl.hint"
assert_file_not_exists "bak deleted"             "$MOCK_HINT/curl.hint.bak"

# ── T12: --delete nonexistent → exit 2 ────────────────────────────────────────
echo ""
echo "T12: --delete nonexistent → exit 2"
set +e
run_mkhint -d ghost_package 2>/dev/null
code=$?
set -e
assert_exit_code      "delete missing exits 2"   2 "$code"

# ── T13: --new multiline hint, no version ─────────────────────────────────────
echo ""
echo "T13: --new multiline .info, no version → template copied, no md5 update"
run_mkhint -n protoc-gen-go-grpc
assert_file_exists    "hint created"             "$MOCK_HINT/protoc-gen-go-grpc.hint"
assert_contains       "first URL present"        "$MOCK_HINT/protoc-gen-go-grpc.hint" 'grpc-go-cmd'
assert_contains       "second URL present"       "$MOCK_HINT/protoc-gen-go-grpc.hint" 'protobuf-go'
# md5s should be original (no version → no download)
assert_contains       "original md5 kept"        "$MOCK_HINT/protoc-gen-go-grpc.hint" '9d3abc100f411a59907528e55e772a10'

# ── T14: --new multiline .info, with version → first md5 recalculated ─────────
echo ""
echo "T14: --new multiline .info -v → first URL+md5 updated, second md5 kept (no prompt in test)"
rm "$MOCK_HINT/protoc-gen-go-grpc.hint"
# Pipe empty input so read -r gets blank (keep continuation URL)
echo "" | run_mkhint -n protoc-gen-go-grpc -V 1.4.0
assert_contains       "VERSION updated"          "$MOCK_HINT/protoc-gen-go-grpc.hint" 'VERSION="1.4.0"'
assert_contains       "first URL has new ver"    "$MOCK_HINT/protoc-gen-go-grpc.hint" 'v1.4.0'
assert_not_contains   "first md5 recalculated"   "$MOCK_HINT/protoc-gen-go-grpc.hint" '9d3abc100f411a59907528e55e772a10'
assert_contains       "second md5 unchanged"     "$MOCK_HINT/protoc-gen-go-grpc.hint" 'e11cccd452bbf4296f72bf323d7b8690'

# ── T15: --clean removes .bak files ───────────────────────────────────────────
echo ""
echo "T15: --clean removes all .bak files"
touch "$MOCK_HINT/a.hint.bak" "$MOCK_HINT/b.hint.bak"
run_mkhint -c
assert_file_not_exists "a.bak removed"           "$MOCK_HINT/a.hint.bak"
assert_file_not_exists "b.bak removed"           "$MOCK_HINT/b.hint.bak"

# ── T16: --new github .info → github source section ───────────────────────────
echo ""
echo "T16: --new github .info → [pkg] source=github appended"
run_mkhint -n ghpkg > "$MOCK_BASE/t16.out" 2>&1
assert_contains "github section header"  "$MOCK_BASE/nvchecker.toml" '\[ghpkg\]'
assert_contains "github source"          "$MOCK_BASE/nvchecker.toml" 'source = "github"'
assert_contains "github owner/repo"      "$MOCK_BASE/nvchecker.toml" 'github = "someowner/ghpkg"'
assert_contains "github latest_release"  "$MOCK_BASE/nvchecker.toml" 'use_latest_release = true'
assert_contains "github max_tag comment" "$MOCK_BASE/nvchecker.toml" '# use_max_tag = true'
assert_contains "T16 stanza echoed"      "$MOCK_BASE/t16.out" 'source = "github"'
# closing fence must sit on its own line, not glued to the last body line
assert_contains "T16 closing fence on own line" "$MOCK_BASE/t16.out" '^────────────────────────────$'
assert_contains "T16 prefix line intact"        "$MOCK_BASE/t16.out" 'uncomment if tags are v-prefixed$'

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
rm -f "$MOCK_HINT/clion.hint" "$MOCK_HINT/clion.hint.bak"  # force fresh --new (T8 already created one)
run_mkhint -n clion > "$MOCK_BASE/t18.out" 2>&1
assert_contains "clion section header"    "$MOCK_BASE/nvchecker.toml" '\[clion\]'
assert_contains "stub TODO"               "$MOCK_BASE/nvchecker.toml" 'TODO: configure nvchecker source'
assert_contains "T18 stub echoed"         "$MOCK_BASE/t18.out" 'TODO: configure nvchecker source'

# ── T19: --new when [pkg] already present → no duplicate, dumps existing ───────
echo ""
echo "T19: --new when section exists → not duplicated, existing dumped"
rm -f "$MOCK_HINT/ghpkg.hint" "$MOCK_HINT/ghpkg.hint.bak"  # force fresh --new; nvchecker section stays from T16
run_mkhint -n ghpkg > "$MOCK_BASE/t19.out" 2>&1  # ghpkg section already added in T16
dup_count=$(grep -c '^\[ghpkg\]' "$MOCK_BASE/nvchecker.toml")
assert_exit_code "ghpkg section appears once" 1 "$dup_count"
assert_contains "T19 dumps existing"      "$MOCK_BASE/t19.out" 'github = "someowner/ghpkg"'

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
# blank = accept latest (8.9.0 from keyfile); Y = run slackrepo (nvtake fires on confirm)
run_mkhint -f curl < <(printf '\nY\n')
assert_contains "VERSION set to latest"   "$MOCK_HINT/curl.hint" 'VERSION="8.9.0"'
assert_contains "URL has latest version"  "$MOCK_HINT/curl.hint" 'curl-8.9.0'
assert_file_exists "nvtake was called"    "$MOCK_BASE/nvtake.log"

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
run_mkhint -f curl < <(printf '8.8.8\nn\n')
assert_contains "VERSION = typed value"   "$MOCK_HINT/curl.hint" 'VERSION="8.8.8"'
assert_contains "URL has typed version"   "$MOCK_HINT/curl.hint" 'curl-8.8.8'

# ── T22: --hintfile no -v, package absent from keyfile → graceful abort ────────
echo ""
echo "T22: --hintfile no -v, package absent from keyfile → error, hint untouched"
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
assert_exit_code "graceful abort on no result" 0 "$code"
assert_contains  "hint version unchanged"      "$MOCK_HINT/protoc-gen-go-grpc.hint" 'VERSION="1.3.0"'

# ── T23: --check one outdated, confirm → updated + nvtake + slackrepo prompt ───
echo ""
echo "T23: --check single outdated package, confirm update"
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
rm -f "$MOCK_HINT/clion.hint" "$MOCK_HINT/protoc-gen-go-grpc.hint" "$MOCK_HINT"/*.bak 2>/dev/null
rm -f "$MOCK_BASE/nvtake.log"
# Y = confirm update; Y = run slackrepo (nvtake fires on slackrepo confirm)
run_mkhint -C curl < <(printf 'Y\nY\n')
assert_contains "curl updated to 8.9.0"   "$MOCK_HINT/curl.hint" 'VERSION="8.9.0"'
assert_file_exists "nvtake called"        "$MOCK_BASE/nvtake.log"

# ── T24: --check all current → 'all up to date', no slackrepo ──────────────────
echo ""
echo "T24: --check when everything current"
out=$(run_mkhint -C curl < <(printf '\n') 2>&1)
echo "$out" | grep -q "all up to date" \
    && { echo "  PASS: reports all up to date"; (( PASS++ )); } \
    || { echo "  FAIL: did not report all up to date"; (( FAIL++ )); ERRORS+=("T24 up to date"); }

# ── T25: --check two outdated, decline first accept second ─────────────────────
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
# explicit order curl clion → answers: n (decline curl), Y (accept clion), n (slackrepo)
run_mkhint -C curl clion < <(printf 'n\nY\nn\n')
assert_contains     "curl declined (unchanged)"  "$MOCK_HINT/curl.hint"  'VERSION="8.9.0"'
assert_contains     "clion accepted (updated)"   "$MOCK_HINT/clion.hint" 'VERSION="2025.5"'

# ── T26: --check with -v → mutually-exclusive error exit 1 ─────────────────────
echo ""
echo "T26: --check combined with -v → exit 1"
set +e
run_mkhint -C -V 1.0 2>/dev/null
code=$?
set -e
assert_exit_code "check + -v exits 1" 1 "$code"

# ── T27: --check upstream older than hint → (?downgrade) flag ──────────────────
echo ""
echo "T27: --check when upstream version is older → reported as (?downgrade)"
cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": { "curl": { "version": "8.0.0" } } }
EOF
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.9.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.9.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
# decline the update (n), so hint stays unchanged; capture report output
out=$(run_mkhint -C curl < <(printf 'n\n') 2>&1)
echo "$out" | grep -q "(?downgrade)" \
    && { echo "  PASS: downgrade flagged in report"; (( PASS++ )); } \
    || { echo "  FAIL: (?downgrade) not in report"; echo "$out" | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T27 downgrade flag"); }
assert_contains "curl unchanged after decline" "$MOCK_HINT/curl.hint" 'VERSION="8.9.0"'

# ── T28: --check with no args → scans all hints in HINT_DIR ────────────────────
echo ""
echo "T28: --check with no package args scans entire HINT_DIR"
# only curl present and outdated; new_ver has curl 8.9.0
cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": { "curl": { "version": "8.9.0" } } }
EOF
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
# no pkg args → scan-all; accept curl (Y), decline slackrepo (n)
run_mkhint -C < <(printf 'Y\nn\n')
assert_contains "scan-all updated curl" "$MOCK_HINT/curl.hint" 'VERSION="8.9.0"'

# ── T29: --check missing section, accept populate → section added, run stops ───
echo ""
echo "T29: --check missing section, accept populate → github section appended, no update"
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

# ── T32: --new with dash in name → section header is TOML-quoted ───────────────
echo ""
echo "T32: --new yt-dlp → [\"yt-dlp\"] quoted header written"
cat > "$MOCK_BASE/nvchecker.toml" << EOF
[__config__]
oldver = "$MOCK_BASE/old_ver.json"
newver = "$MOCK_BASE/new_ver.json"
EOF
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
run_mkhint -n yt-dlp
assert_contains     "quoted section header"   "$MOCK_BASE/nvchecker.toml" '^\["yt-dlp"\]'
assert_not_contains "no bare header"          "$MOCK_BASE/nvchecker.toml" '^\[yt-dlp\]'
assert_contains     "github source"           "$MOCK_BASE/nvchecker.toml" 'github = "yt-dlp/yt-dlp"'

# ── T33: _has_nvchecker_section matches quoted header → no duplicate on re---new
echo ""
echo "T33: --new yt-dlp again → quoted section not duplicated"
run_mkhint -n yt-dlp  # section already exists from T32 (quoted)
dup_count=$(grep -cE '^\["yt-dlp"\]' "$MOCK_BASE/nvchecker.toml")
assert_exit_code "quoted yt-dlp appears once" 1 "$dup_count"

# ── T34: --check sees quoted section as present, not "no section" ──────────────
echo ""
echo "T34: --check with existing quoted section → not flagged missing"
# yt-dlp quoted section present (from T32); not in keyfile → 'no nvchecker result', NOT 'no section'
cat > "$MOCK_HINT/yt-dlp.hint" << 'EOF'
VERSION="2024.1.1"
ARCH="x86_64"
DOWNLOAD="https://github.com/yt-dlp/yt-dlp/archive/2024.1.1/yt-dlp-2024.1.1.tar.gz"
MD5SUM="55555555555555555555555555555555"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
out=$(run_mkhint -C yt-dlp < <(printf 'n\n') 2>&1)
echo "$out" | grep -q "yt-dlp: no nvchecker result" \
    && { echo "  PASS: quoted section recognized (no result, not no section)"; (( PASS++ )); } \
    || { echo "  FAIL: quoted section not recognized"; echo "$out" | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T34 quoted recognized"); }
echo "$out" | grep -q "yt-dlp: no nvchecker section" \
    && { echo "  FAIL: quoted section wrongly flagged missing"; (( FAIL++ )); ERRORS+=("T34 false missing"); } \
    || { echo "  PASS: not flagged as missing section"; (( PASS++ )); }

# ── T35: relative newver path resolved against config dir, not CWD ─────────────
echo ""
echo "T35: relative newver path in config → resolved against config dir"
# config uses a RELATIVE newver path (as nvchecker writes by default).
# keyfile lives beside the config in $MOCK_BASE. The run happens with CWD
# elsewhere (the repo dir), so a CWD-relative read would fail to find it.
cat > "$MOCK_BASE/nvchecker.toml" << EOF
[__config__]
oldver = "old_ver.json"
newver = "new_ver.json"
EOF
cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": { "curl": { "version": "8.9.0" } } }
EOF
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
run_mkhint -C curl < <(printf 'Y\nn\n')
assert_contains "relative-path keyfile found → curl updated" "$MOCK_HINT/curl.hint" 'VERSION="8.9.0"'

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
echo "$out" | grep -q "yellow row = versions match" \
    && { echo "  PASS: legend shown"; (( PASS++ )); } \
    || { echo "  FAIL: legend missing"; (( FAIL++ )); ERRORS+=("T36 legend"); }
# clion row must NOT carry the color start code
echo "$out" | grep "clion.hint" | grep -q $'\033\[33m' \
    && { echo "  FAIL: clion wrongly highlighted"; (( FAIL++ )); ERRORS+=("T36 false hl"); } \
    || { echo "  PASS: clion row plain"; (( PASS++ )); }

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

# ── T42: --check single package → nvchecker called with -e <pkg> ──────────────
echo ""
echo "T42: --check one package runs nvchecker -e <pkg>"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak "$MOCK_BASE/nvchecker.log" 2>/dev/null
cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": { "curl": { "version": "8.5.0" } } }
EOF
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
EOF
run_mkhint -C curl < <(printf '\n') > /dev/null 2>&1
assert_contains     "nvchecker run with -e curl"  "$MOCK_BASE/nvchecker.log" '\-e curl'

# ── T43: --check two packages → nvchecker scans all (no -e) ───────────────────
echo ""
echo "T43: --check two packages runs nvchecker without -e (full scan)"
rm -f "$MOCK_BASE/nvchecker.log" 2>/dev/null
cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": { "curl": { "version": "8.5.0" }, "clion": { "version": "2025.4" } } }
EOF
cat > "$MOCK_HINT/clion.hint" << 'EOF'
VERSION="2025.4"
ARCH="x86_64"
DOWNLOAD="UNSUPPORTED"
MD5SUM=""
EOF
run_mkhint -C curl clion < <(printf '\n') > /dev/null 2>&1
assert_not_contains "two-pkg check has no -e"     "$MOCK_BASE/nvchecker.log" '\-e '

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

# ── T48: --check upstream dashed date == packaged underscore date → current ────
echo ""
echo "T48: --check upstream 2026-06-02 vs hint 2026_06_02 → treated as current"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": { "curl": { "version": "2026-06-02" } } }
EOF
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="2026_06_02"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-2026_06_02.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
out=$(run_mkhint -C curl < <(printf '\n') 2>&1)
echo "$out" | grep -q "all up to date" \
    && { echo "  PASS: dashed upstream == underscore packaged"; (( PASS++ )); } \
    || { echo "  FAIL: offered an update for equivalent version"; echo "$out" | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T48 dash/underscore equivalence"); }

# ── T49: --check accept dashed upstream update → hint stores underscore form ────
echo ""
echo "T49: --check accept 2026-07-01 → hint VERSION written as 2026_07_01"
cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": { "curl": { "version": "2026-07-01" } } }
EOF
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="2026_06_02"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-2026_06_02.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
# accept update (Y), decline slackrepo (n)
run_mkhint -C curl < <(printf 'Y\nn\n')
assert_contains "hint stores normalized version" "$MOCK_HINT/curl.hint" 'VERSION="2026_07_01"'

# ── T50: --new on .info requiring a phantom dep → DELREQUIRES added ───────────
echo ""
echo "T50: --new phantom dep → DELREQUIRES added"
rm -f "$MOCK_HINT/gopkg.hint"
run_mkhint -n gopkg
assert_contains     "DELREQUIRES added"      "$MOCK_HINT/gopkg.hint" 'DELREQUIRES="google-go-lang"'
assert_contains     "REQUIRES still commented" "$MOCK_HINT/gopkg.hint" '#REQUIRES='

# ── T51: --new on .info with no phantom dep → no DELREQUIRES ──────────────────
echo ""
echo "T51: --new no phantom dep → no DELREQUIRES"
rm -f "$MOCK_HINT/curl.hint" "$MOCK_HINT/curl.hint.bak"
run_mkhint -n curl
assert_not_contains "no DELREQUIRES"         "$MOCK_HINT/curl.hint" 'DELREQUIRES'

# ── T52: -F, dependent with no hint → minimal hint created ────────────────────
echo ""
echo "T52: --fix-current, no existing hint → minimal hint created"
rm -f "$MOCK_HINT/rustpkg.hint" "$MOCK_HINT/rustpkg.hint.bak"
run_mkhint -F
assert_file_exists  "rustpkg hint created"   "$MOCK_HINT/rustpkg.hint"
assert_contains     "rustpkg DELREQUIRES"    "$MOCK_HINT/rustpkg.hint" 'DELREQUIRES="rust-opt"'
assert_not_contains "only rust-opt stripped" "$MOCK_HINT/rustpkg.hint" 'other-dep'

# ── T53: -F, existing manual hint → .bak made, DELREQUIRES merged, rest intact ─
echo ""
echo "T53: --fix-current merges into existing hint, preserves content"
cat > "$MOCK_HINT/mixedpkg.hint" << 'EOF'
VERSION="3.2.1"
ARCH="x86_64"
DOWNLOAD="https://example.com/mixedpkg-3.2.1.tar.gz"
MD5SUM="66666666666666666666666666666666"
EOF
rm -f "$MOCK_HINT/mixedpkg.hint.bak"
run_mkhint -F
assert_file_exists  "backup made"            "$MOCK_HINT/mixedpkg.hint.bak"
assert_contains     "DELREQUIRES merged"     "$MOCK_HINT/mixedpkg.hint" 'DELREQUIRES="google-go-lang"'
assert_contains     "VERSION preserved"      "$MOCK_HINT/mixedpkg.hint" 'VERSION="3.2.1"'
assert_contains     "DOWNLOAD preserved"     "$MOCK_HINT/mixedpkg.hint" 'mixedpkg-3.2.1.tar.gz'

# ── T54: -F re-run → idempotent, no duplicate deps, no new .bak churn ─────────
echo ""
echo "T54: --fix-current idempotent on second run"
rm -f "$MOCK_HINT/mixedpkg.hint.bak"
run_mkhint -F
assert_not_contains "no duplicate dep"       "$MOCK_HINT/mixedpkg.hint" 'google-go-lang google-go-lang'
assert_file_not_exists "no churn .bak"       "$MOCK_HINT/mixedpkg.hint.bak"

# ── T55: empty/missing phantom-deps file → -F and --new are no-ops ────────────
echo ""
echo "T55: no phantom-deps file → --fix-current no-op"
mv "$MOCK_BASE/phantom-deps" "$MOCK_BASE/phantom-deps.off"
rm -f "$MOCK_HINT/gopkg.hint"
out=$(run_mkhint -F)
echo "$out" | grep -q "Nothing to do" \
    && { echo "  PASS: reports nothing to do"; (( PASS++ )); } \
    || { echo "  FAIL: reports nothing to do"; (( FAIL++ )); ERRORS+=("T55 message"); }
assert_file_not_exists "no hint created"     "$MOCK_HINT/gopkg.hint"
run_mkhint -n gopkg
assert_not_contains "new: no DELREQUIRES"    "$MOCK_HINT/gopkg.hint" 'DELREQUIRES'
mv "$MOCK_BASE/phantom-deps.off" "$MOCK_BASE/phantom-deps"

# ── T56: -F combined with -v → exit 1 ─────────────────────────────────────────
echo ""
echo "T56: --fix-current with -v → exit 1"
set +e
run_mkhint -F -V 1.0.0 2>/dev/null
code=$?
set -e
assert_exit_code    "mutually exclusive"     1 "$code"

# ── T57: -l skips hints with no VERSION ──────────────────────────────────────
echo ""
echo "T57: -l lists only hints that have a VERSION"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
EOF
# no VERSION line at all
cat > "$MOCK_HINT/novers.hint" << 'EOF'
ARCH="x86_64"
DELREQUIRES="rust-opt"
EOF
out=$(run_mkhint -l 2>&1)
echo "$out" | grep -q "curl.hint" \
    && { echo "  PASS: versioned hint shown"; (( PASS++ )); } \
    || { echo "  FAIL: versioned hint missing"; (( FAIL++ )); ERRORS+=("T57 shown"); }
echo "$out" | grep -q "novers.hint" \
    && { echo "  FAIL: versionless hint shown"; (( FAIL++ )); ERRORS+=("T57 skip"); } \
    || { echo "  PASS: versionless hint skipped"; (( PASS++ )); }
echo "$out" | grep -q "Total: 1 file" \
    && { echo "  PASS: count excludes versionless"; (( PASS++ )); } \
    || { echo "  FAIL: count wrong"; (( FAIL++ )); ERRORS+=("T57 count"); }

# ── T58: -l <pkg> shows side-by-side diff, not the table ─────────────────────
echo ""
echo "T58: -l <pkg> shows hint vs .info diff"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
EOF
out=$(run_mkhint -l curl 2>&1)
echo "$out" | grep -q "=== curl ===" \
    && { echo "  PASS: diff header shown"; (( PASS++ )); } \
    || { echo "  FAIL: diff header missing"; (( FAIL++ )); ERRORS+=("T58 header"); }
echo "$out" | grep -q "HintVer" \
    && { echo "  FAIL: table printed"; (( FAIL++ )); ERRORS+=("T58 table"); } \
    || { echo "  PASS: no table"; (( PASS++ )); }

# ── T59: -l <missing> → exit 2 ───────────────────────────────────────────────
echo ""
echo "T59: -l on nonexistent hint → exit 2"
set +e
run_mkhint -l nope 2>/dev/null
code=$?
set -e
assert_exit_code    "missing hint"     2 "$code"

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

# ── T68: -l shows ✓ in NoDL for hint with NODOWNLOAD=yes ─────────────────────
echo ""
echo "T68: -l NoDL column shows ✓ when NODOWNLOAD=yes"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
NODOWNLOAD=yes
EOF
out=$(run_mkhint -l 2>&1)
echo "$out" | grep -q "NoDL" \
    && { echo "  PASS: NoDL header present"; (( PASS++ )); } \
    || { echo "  FAIL: NoDL header missing"; echo "$out" | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T68 header"); }
echo "$out" | grep curl.hint | grep -q "✓" \
    && { echo "  PASS: ✓ shown for NODOWNLOAD hint"; (( PASS++ )); } \
    || { echo "  FAIL: ✓ missing"; echo "$out" | grep curl.hint | sed 's/^/        /'; (( FAIL++ )); ERRORS+=("T68 check"); }

# ── T69: -l NoDL blank when no NODOWNLOAD ────────────────────────────────────
echo ""
echo "T69: -l NoDL column blank when no NODOWNLOAD"
rm -f "$MOCK_HINT"/*.hint "$MOCK_HINT"/*.bak 2>/dev/null
cat > "$MOCK_HINT/curl.hint" << 'EOF'
VERSION="8.5.0"
ARCH="x86_64"
DOWNLOAD="https://curl.se/download/curl-8.5.0.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
EOF
out=$(run_mkhint -l 2>&1)
echo "$out" | grep curl.hint | grep -q "✓" \
    && { echo "  FAIL: ✓ shown without NODOWNLOAD"; (( FAIL++ )); ERRORS+=("T69 check"); } \
    || { echo "  PASS: no ✓ without NODOWNLOAD"; (( PASS++ )); }

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
run_mkhint -C curl wget < <(printf 'Y\nY\nY\nY\n')
assert_contains "update for built curl" "$SLACKREPO_LOG" '^update curl$'
assert_contains "build for new wget"    "$SLACKREPO_LOG" '^build wget$'

# ── T71: --hintfile no -V, pkg not built → build ──────────────────────────────
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
run_mkhint -f curl < <(printf '\nY\n')
assert_contains "hintfile new pkg → build" "$SLACKREPO_LOG" '^build curl$'

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
run_mkhint -C curl < <(printf 'Y\nY\n')
assert_contains "override tree → update" "$SLACKREPO_LOG" '^update curl$'
rm -f "$MOCK_BASE/config"

# ── T73: --help compact, exits 0, points at man page ─────────────────────────
echo ""
echo "T73: --help exits 0 and points at 'man mkhint'"
set +e
out=$(run_mkhint --help 2>&1); code=$?
set -e
assert_exit_code "--help exits 0" 0 "$code"
echo "$out" | grep -q 'man mkhint' \
    && { echo "  PASS: --help points at man page"; (( PASS++ )); } \
    || { echo "  FAIL: --help missing man pointer: $out"; (( FAIL++ )); ERRORS+=("T73 pointer"); }

# ── T74: --hintfile -V dash-dated URL → both '_' and '-' forms bumped ────────
echo ""
echo "T74: --hintfile -V dashed URL → underscore VERSION and dashed URL both bumped"
cat > "$MOCK_HINT/datedpkg.hint" << 'EOF'
VERSION="2026_04_30"
ARCH="x86_64"
DOWNLOAD="https://example.com/archive/2026-04-30/datedpkg-2026-04-30.tar.gz"
MD5SUM="abc123def456abc123def456abc123de"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
EOF
run_mkhint -f datedpkg -V 2026_07_07 < <(printf 'n\n')
assert_contains       "VERSION underscore bumped"  "$MOCK_HINT/datedpkg.hint" 'VERSION="2026_07_07"'
assert_contains       "URL dashed date bumped"     "$MOCK_HINT/datedpkg.hint" 'datedpkg-2026-07-07.tar.gz'
assert_not_contains   "no stale dashed date"       "$MOCK_HINT/datedpkg.hint" '2026-04-30'
assert_not_contains   "MD5SUM recalculated"        "$MOCK_HINT/datedpkg.hint" 'abc123def456'

# ── T75: --new -V dash-dated .info → both forms bumped ───────────────────────
echo ""
echo "T75: --new -V dashed .info URL → underscore VERSION and dashed URL both bumped"
rm -f "$MOCK_HINT/datedpkg.hint" "$MOCK_HINT/datedpkg.hint.bak"
run_mkhint -n datedpkg -V 2026_07_07
assert_contains       "VERSION underscore bumped"  "$MOCK_HINT/datedpkg.hint" 'VERSION="2026_07_07"'
assert_contains       "URL dashed date bumped"     "$MOCK_HINT/datedpkg.hint" 'datedpkg-2026-07-07.tar.gz'
assert_not_contains   "no stale dashed date"       "$MOCK_HINT/datedpkg.hint" '2026-04-30'
assert_not_contains   "MD5SUM recalculated"        "$MOCK_HINT/datedpkg.hint" 'abc123def456'

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
r=$(bash -c "$BM_SRC; match_dep_url 'https://example.com/foo/tree-sitter-0.26.7.tar.gz' \"\$1\"" _ "$manifest_urls") || true
[[ -z "$r" ]] \
    && { echo "  PASS: no false prefix match"; (( PASS++ )); } \
    || { echo "  FAIL: false match got '$r'"; (( FAIL++ )); ERRORS+=("T-BM4"); }

# ── T-BM5: match_dep_url no match → empty ────────────────────────────────────
echo ""
echo "T-BM5: match_dep_url returns empty on no match"
manifest_urls='https://github.com/foo/bar/archive/v1.0.tar.gz'
r=$(bash -c "$BM_SRC; match_dep_url 'https://github.com/baz/qux/archive/v2.0.tar.gz' \"\$1\"" _ "$manifest_urls") || true
[[ -z "$r" ]] \
    && { echo "  PASS: empty on no match"; (( PASS++ )); } \
    || { echo "  FAIL: expected empty got '$r'"; (( FAIL++ )); ERRORS+=("T-BM5"); }

# ── T-BM6: load_bundle_manifests + manifest_url_for ──────────────────────────
echo ""
echo "T-BM6: manifest_url_for substitutes {VERSION}, unlisted pkg → non-zero"
cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
# comment
neovim url https://example.com/neovim/v{VERSION}/deps.txt
EOF
BM_SRC='source <(sed -n "/# ── bundled-dep manifest handling/,/# ── end bundled-dep/p" '"$SCRIPT"')'
r=$(bash -c "BUNDLE_MANIFEST_FILE='$MOCK_BASE/bundle-manifests'; $BM_SRC; load_bundle_manifests; manifest_url_for neovim 0.13.0")
[[ "$r" == 'https://example.com/neovim/v0.13.0/deps.txt' ]] \
    && { echo "  PASS: templated URL"; (( PASS++ )); } \
    || { echo "  FAIL: templated URL got '$r'"; (( FAIL++ )); ERRORS+=("T-BM6a"); }
set +e
bash -c "BUNDLE_MANIFEST_FILE='$MOCK_BASE/bundle-manifests'; $BM_SRC; load_bundle_manifests; manifest_url_for curl 8.0" >/dev/null 2>&1
rc=$?
set -e
[[ $rc -ne 0 ]] \
    && { echo "  PASS: unlisted pkg non-zero"; (( PASS++ )); } \
    || { echo "  FAIL: unlisted pkg should be non-zero"; (( FAIL++ )); ERRORS+=("T-BM6b"); }

# ── T-BM7: fetch_manifest downloads to a temp file ───────────────────────────
echo ""
echo "T-BM7: fetch_manifest returns a path with the fixture content"
cat > "$MOCK_BASE/manifest_fixture" << 'EOF'
LIBUV_URL https://github.com/libuv/libuv/archive/v1.52.1.tar.gz
LIBUV_SHA256 abc
EOF
BM_SRC='source <(sed -n "/# ── bundled-dep manifest handling/,/# ── end bundled-dep/p" '"$SCRIPT"')'
mpath=$(bash -c "TMP_DIR='$MOCK_TMP'; PATH=\"$MOCK_BASE/bin:\$PATH\"; $BM_SRC; fetch_manifest 'https://example.com/v1/deps.txt'")
[[ -f "$mpath" ]] && grep -q 'LIBUV_URL' "$mpath" \
    && { echo "  PASS: fetch_manifest content"; (( PASS++ )); } \
    || { echo "  FAIL: fetch_manifest path='$mpath'"; (( FAIL++ )); ERRORS+=("T-BM7"); }
rm -f "$MOCK_BASE/manifest_fixture"

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
rep=$(bash -c "TMP_DIR='$MOCK_TMP'; PATH=\"$MOCK_BASE/bin:\$PATH\"; source '$SCRIPT' 2>/dev/null; reconcile_bundle_deps nvim '$MOCK_HINT/nvim.hint' 'https://x/deps.txt' report" 2>&1) || true
echo "$rep" | grep -q 'tree-sitter' \
    && echo "$rep" | grep -q 'wasmtime' \
    && diff -q "$MOCK_HINT/nvim.hint" "$MOCK_BASE/nvim.before" >/dev/null \
    && { echo "  PASS: report mode no rewrite"; (( PASS++ )); } \
    || { echo "  FAIL: report mode. out=$rep"; (( FAIL++ )); ERRORS+=("T-BM8"); }

# ── T-BM9: reconcile apply mode rewrites the changed dep + recomputes md5 ─────
echo ""
echo "T-BM9: reconcile_bundle_deps apply mode rewrites tree-sitter to v0.26.8"
bash -c "TMP_DIR='$MOCK_TMP'; PATH=\"$MOCK_BASE/bin:\$PATH\"; source '$SCRIPT' 2>/dev/null; reconcile_bundle_deps nvim '$MOCK_HINT/nvim.hint' 'https://x/deps.txt' apply" >/dev/null 2>&1 || true
grep -q 'tree-sitter/archive/v0.26.8' "$MOCK_HINT/nvim.hint" \
    && ! grep -q 'v0.26.7' "$MOCK_HINT/nvim.hint" \
    && ! grep -q 'bbb' "$MOCK_HINT/nvim.hint" \
    && grep -q 'neovim-0.13.0' "$MOCK_HINT/nvim.hint" \
    && { echo "  PASS: apply rewrote dep + md5, primary line untouched"; (( PASS++ )); } \
    || { echo "  FAIL: apply mode:"; cat "$MOCK_HINT/nvim.hint"; (( FAIL++ )); ERRORS+=("T-BM9"); }
rm -f "$MOCK_BASE/manifest_fixture"

# ── T-BM17: same version, different URL shape → NOT a change (v1.2.1 regr.) ───
# The manifest serves bare-tag archive URLs (.../archive/v0.26.7.tar.gz) while
# the hint uses the SBo-fetched tree shape (.../archive/v0.26.7/tree-sitter-
# 0.26.7.tar.gz). Same version → reconcile must report all current, no rewrite.
echo ""
echo "T-BM17: reconcile detects no change when only URL shape differs at same version"
cat > "$MOCK_BASE/manifest_fixture" << 'EOF'
NVIM_URL https://github.com/neovim/neovim/archive/v0.13.0.tar.gz
NVIM_SHA256 a
TREESITTER_URL https://github.com/tree-sitter/tree-sitter/archive/v0.26.7.tar.gz
TREESITTER_SHA256 b
EOF
cat > "$MOCK_HINT/nvim17.hint" << 'EOF'
VERSION="0.13.0"
DOWNLOAD="https://github.com/neovim/neovim/archive/v0.13.0/neovim-0.13.0.tar.gz \
    https://github.com/tree-sitter/tree-sitter/archive/v0.26.7/tree-sitter-0.26.7.tar.gz"
MD5SUM="aaa \
    bbb"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
ARCH="x86_64"
EOF
cp "$MOCK_HINT/nvim17.hint" "$MOCK_BASE/nvim17.before"
rep17=$(bash -c "TMP_DIR='$MOCK_TMP'; PATH=\"$MOCK_BASE/bin:\$PATH\"; source '$SCRIPT' 2>/dev/null; reconcile_bundle_deps nvim '$MOCK_HINT/nvim17.hint' 'https://x/deps.txt' report" 2>&1) || true
echo "$rep17" | grep -q 'all current' \
    && ! echo "$rep17" | grep -q 'changed upstream' \
    && diff -q "$MOCK_HINT/nvim17.hint" "$MOCK_BASE/nvim17.before" >/dev/null \
    && { echo "  PASS: same-version shape diff → no change"; (( PASS++ )); } \
    || { echo "  FAIL: T-BM17 falsely flagged change. out=$rep17"; (( FAIL++ )); ERRORS+=("T-BM17"); }
rm -f "$MOCK_BASE/manifest_fixture" "$MOCK_HINT/nvim17.hint" "$MOCK_BASE/nvim17.before"

# ── T-BM22: _url_version yields equal versions across URL-shape classes ───────
# One case per shape class, not per dep: name-carrying vs bare-tag; name with an
# embedded digit-dot (lua-compat-5.3); package-rev suffix (luv 1.52.1-0); sha
# pin (luajit); mixed-case repo (utf8proc); shared /deps blob (lpeg). Each pair
# is the same upstream version in two shapes → _url_version must match.
echo ""
echo "T-BM22: _url_version equal across shape classes (name/bare, digit-name, pkgrev, sha, case, /deps)"
declare -a UV_PAIRS=(
  # hint_url|manifest_url|label
  "https://github.com/tree-sitter/tree-sitter/archive/v0.26.7/tree-sitter-0.26.7.tar.gz|https://github.com/tree-sitter/tree-sitter/archive/v0.26.7.tar.gz|name-vs-bare"
  "https://github.com/lunarmodules/lua-compat-5.3/archive/v0.13/lua-compat-5.3-0.13.tar.gz|https://github.com/lunarmodules/lua-compat-5.3/archive/v0.13.tar.gz|digit-in-name"
  "https://github.com/luvit/luv/releases/download/1.52.1-0/luv-1.52.1-0.tar.gz|https://github.com/luvit/luv/archive/1.52.1-0.tar.gz|pkgrev-suffix"
  "https://github.com/luajit/luajit/archive/fbb36bb/LuaJIT-fbb36bb6bfa88716a47c58bcf9ce9f2ef752abac.tar.gz|https://github.com/luajit/luajit/archive/fbb36bb6bfa88716a47c58bcf9ce9f2ef752abac.tar.gz|sha-pin-mixedcase"
  "https://github.com/JuliaStrings/utf8proc/archive/v2.11.3/utf8proc-2.11.3.tar.gz|https://github.com/juliastrings/utf8proc/archive/v2.11.3.tar.gz|mixed-case-repo"
  "https://www.inf.puc-rio.br/~roberto/lpeg/lpeg-1.1.0.tar.gz|https://github.com/neovim/deps/raw/deadbeef1234567/opt/lpeg-1.1.0.tar.gz|deps-blob"
)
uv_fail=""
for pair in "${UV_PAIRS[@]}"; do
    IFS='|' read -r huv muv lbl <<< "$pair"
    hv=$(bash -c "source '$SCRIPT' 2>/dev/null; _url_version '$huv'")
    mv=$(bash -c "source '$SCRIPT' 2>/dev/null; _url_version '$muv'")
    [[ -n "$hv" && "$hv" == "$mv" ]] || uv_fail+=" $lbl($hv≠$mv)"
done
# and a real bump MUST differ
bump_h=$(bash -c "source '$SCRIPT' 2>/dev/null; _url_version 'https://github.com/tree-sitter/tree-sitter/archive/v0.26.7/tree-sitter-0.26.7.tar.gz'")
bump_m=$(bash -c "source '$SCRIPT' 2>/dev/null; _url_version 'https://github.com/tree-sitter/tree-sitter/archive/v0.26.8.tar.gz'")
[[ "$bump_h" != "$bump_m" ]] || uv_fail+=" real-bump-not-detected"
[[ -z "$uv_fail" ]] \
    && { echo "  PASS: all shape classes equal, real bump differs"; (( PASS++ )); } \
    || { echo "  FAIL: T-BM22:$uv_fail"; (( FAIL++ )); ERRORS+=("T-BM22"); }

# ── T-BM23: match_dep_url is case-insensitive on the repo slug ────────────────
echo ""
echo "T-BM23: match_dep_url matches JuliaStrings/utf8proc to juliastrings/utf8proc"
r=$(bash -c "$BM_SRC; match_dep_url 'https://github.com/JuliaStrings/utf8proc/archive/v2.11.3/utf8proc-2.11.3.tar.gz' \"\$1\"" _ 'https://github.com/juliastrings/utf8proc/archive/v2.11.3.tar.gz')
[[ "$r" == 'https://github.com/juliastrings/utf8proc/archive/v2.11.3.tar.gz' ]] \
    && { echo "  PASS: case-insensitive repo match"; (( PASS++ )); } \
    || { echo "  FAIL: case match got '$r'"; (( FAIL++ )); ERRORS+=("T-BM23"); }

# ── T-BM10: --new listed pkg prints reconcile report, does NOT rewrite ───────
echo ""
echo "T-BM10: --new listed pkg → manifest report, hint not rewritten by manifest"
cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
bmnvim url https://example.com/bmnvim/v{VERSION}/deps.txt
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

# ── T-BM-MODE: existing url-mode reconcile still works after 3-field migration ─
echo ""
echo "T-BM-MODE: url-mode reconcile still runs after 3-field manifest migration"
cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
bmnvim url https://raw.githubusercontent.com/neovim/neovim/{VERSION}/deps.txt
EOF
cat > "$MOCK_BASE/manifest_fixture" << 'EOF'
UTF8PROC_URL https://github.com/juliastrings/utf8proc/archive/v2.9.0.tar.gz
UTF8PROC_SHA256 a
EOF
rm -f "$MOCK_HINT/bmnvim.hint"
out=$(run_mkhint -n bmnvim 2>&1)
echo "$out" | grep -q 'bmnvim: bundled-dep manifest check' \
    && { echo "  PASS: url-mode reconcile ran"; (( PASS++ )); } \
    || { echo "  FAIL: url-mode reconcile did not run. out=$out"; (( FAIL++ )) || true; ERRORS+=("T-BM-MODE"); }
rm -f "$MOCK_BASE/manifest_fixture" "$MOCK_BASE/bundle-manifests" "$MOCK_HINT/bmnvim.hint"

# ── T-BM12: --force with --hintfile → exit 1 ─────────────────────────────────
echo ""
echo "T-BM12: --force is --check-only (errors with --hintfile/--new/--fix-current)"
set +e
o1=$(run_mkhint --force -f curl -V 1.0 2>&1); c1=$?
o2=$(run_mkhint --force -n curl 2>&1); c2=$?
o3=$(run_mkhint --force -F 2>&1); c3=$?
set -e
# grep the guard message too, so this pins our check rather than getopt's own rejection
[[ $c1 -eq 1 && $c2 -eq 1 && $c3 -eq 1 ]] \
    && echo "$o1" | grep -q 'only valid with --check' \
    && echo "$o2" | grep -q 'only valid with --check' \
    && echo "$o3" | grep -q 'only valid with --check' \
    && { echo "  PASS: --force mutually exclusive"; (( PASS++ )); } \
    || { echo "  FAIL: exits $c1 $c2 $c3"; (( FAIL++ )); ERRORS+=("T-BM12"); }

# ── T-BM13..16: --check Phase 2 bundled-dep reconcile for listed packages ────
setup_bmnvim_check() {
    cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
bmnvim url https://example.com/bmnvim/v{VERSION}/deps.txt
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
    # Seed nvchecker the same way T23/T25/etc do: an [bmnvim] section in the
    # toml (required by _has_nvchecker_section) and a keyfile entry reporting
    # latest == 0.13.0, so the primary version is unchanged this run.
    cat > "$MOCK_BASE/nvchecker.toml" << EOF
[__config__]
oldver = "$MOCK_BASE/old_ver.json"
newver = "$MOCK_BASE/new_ver.json"

[bmnvim]
source = "github"
github = "neovim/neovim"
EOF
    cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": { "bmnvim": { "version": "0.13.0" } } }
EOF
    cp "$MOCK_BASE/new_ver.json" "$MOCK_BASE/old_ver.json"
}

# T-BM13: primary unchanged, no --force → Phase 2 skipped (dep stays v0.26.7)
echo ""
echo "T-BM13: --check listed, primary current, no --force → deps untouched"
setup_bmnvim_check
run_mkhint -C bmnvim < <(printf '\n') >/dev/null 2>&1 || true
grep -q 'v0.26.7' "$MOCK_HINT/bmnvim.hint" \
    && { echo "  PASS: Phase 2 skipped"; (( PASS++ )); } \
    || { echo "  FAIL: dep changed without --force"; (( FAIL++ )); ERRORS+=("T-BM13"); }

# T-BM14: primary unchanged, --force → Phase 2 runs, dep bumped on Y
echo ""
echo "T-BM14: --check --force listed, primary current → deps reconciled"
setup_bmnvim_check
run_mkhint -C --force bmnvim < <(printf 'Y\n') >/dev/null 2>&1 || true
grep -q 'tree-sitter/archive/v0.26.8' "$MOCK_HINT/bmnvim.hint" \
    && { echo "  PASS: --force ran Phase 2"; (( PASS++ )); } \
    || { echo "  FAIL: --force did not bump dep"; cat "$MOCK_HINT/bmnvim.hint"; (( FAIL++ )); ERRORS+=("T-BM14"); }

# T-BM15: manifest fetch fails → deps unchanged, retry msg
echo ""
echo "T-BM15: --check --force, manifest fetch fails → deps unchanged"
setup_bmnvim_check
rm -f "$MOCK_BASE/manifest_fixture"
out=$(run_mkhint -C --force bmnvim < <(printf 'Y\n') 2>&1) || true
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
out=$(run_mkhint -C --force bmnvim < <(printf 'n\n') 2>&1) || true
# FYI block is the lines between "manifest has N deps not in hint:" and the
# next blank line. Only wasmtime (a true extra) should be listed; the
# primary's manifest counterpart (neovim) must not be flagged as missing.
fyi_block=$(echo "$out" | awk '/deps not in hint:/{f=1; next} f && /^$/{f=0} f')
echo "$out" | grep -q 'deps not in hint:' && echo "$out" | grep -qi 'wasmtime' \
    && ! echo "$fyi_block" | grep -qx 'neovim' \
    && { echo "  PASS: FYI list printed"; (( PASS++ )); } \
    || { echo "  FAIL: FYI. out=$out"; (( FAIL++ )); ERRORS+=("T-BM16"); }
rm -f "$MOCK_BASE/manifest_fixture" "$MOCK_BASE/bundle-manifests" "$MOCK_HINT/bmnvim.hint"

# ── T-BM24: all-current reconcile does NOT prompt to apply ───────────────────
# When the report finds no changed dep, the caller must skip the "Apply?"
# prompt entirely (report mode returns 0; a change returns 2).
echo ""
echo "T-BM24: --check --force, bundled deps all current → no apply prompt"
setup_bmnvim_check
# manifest tree-sitter at the SAME version as the hint (0.26.7), different shape
cat > "$MOCK_BASE/manifest_fixture" << 'EOF'
NVIM_URL https://github.com/neovim/neovim/archive/v0.13.0.tar.gz
NVIM_SHA256 a
TREESITTER_URL https://github.com/tree-sitter/tree-sitter/archive/v0.26.7.tar.gz
TREESITTER_SHA256 b
EOF
out=$(run_mkhint -C --force bmnvim < <(printf '\n') 2>&1) || true
echo "$out" | grep -q 'bundled deps all current' \
    && ! echo "$out" | grep -q 'Apply bundled-dep updates' \
    && grep -q 'v0.26.7' "$MOCK_HINT/bmnvim.hint" \
    && { echo "  PASS: no prompt when all current"; (( PASS++ )); } \
    || { echo "  FAIL: T-BM24 prompted on no-op. out=$out"; (( FAIL++ )); ERRORS+=("T-BM24"); }
rm -f "$MOCK_BASE/manifest_fixture" "$MOCK_BASE/bundle-manifests" "$MOCK_HINT/bmnvim.hint"

# ── T-BM18: --hintfile -V on a listed pkg reconciles bundled deps ────────────
echo ""
echo "T-BM18: -f listed pkg -V bumps primary AND reconciles bundled deps"
cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
bmnvim url https://example.com/bmnvim/v{VERSION}/deps.txt
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
# stdin: apply Y, then slackrepo n. NO continuation-URL prompt: bmnvim is
# manifest-listed, so the primary bump must NOT ask for the extra URLs.
out=$(run_mkhint -f bmnvim -V 0.14.0 < <(printf 'Y\nn\n') 2>&1) || true
grep -q 'VERSION="0.14.0"' "$MOCK_HINT/bmnvim.hint" \
    && grep -q 'tree-sitter/archive/v0.26.8' "$MOCK_HINT/bmnvim.hint" \
    && echo "$out" | grep -q 'left to bundled-dep reconcile' \
    && ! echo "$out" | grep -q 'line 2 (current)' \
    && { echo "  PASS: -f -V bumped primary + reconciled deps, no continuation prompt"; (( PASS++ )); } \
    || { echo "  FAIL: -f -V parity/suppression. out=$out"; cat "$MOCK_HINT/bmnvim.hint"; (( FAIL++ )); ERRORS+=("T-BM18"); }
rm -f "$MOCK_BASE/manifest_fixture" "$MOCK_BASE/bundle-manifests" "$MOCK_HINT/bmnvim.hint"

# ── T-BM25: NON-listed multiline pkg still prompts for continuation URLs ──────
# Guard against over-suppression: a package with no bundle manifest must keep
# the interactive continuation-URL prompt on a primary bump.
echo ""
echo "T-BM25: non-listed multiline pkg → continuation URL prompt still shown"
: > "$MOCK_BASE/bundle-manifests"   # nothing listed
cat > "$MOCK_HINT/plainml.hint" << 'EOF'
VERSION="1.0.0"
DOWNLOAD="https://example.com/plainml-1.0.0.tar.gz \
    https://example.com/extra-9.9.tar.gz"
MD5SUM="aaa \
    bbb"
DOWNLOAD_x86_64=""
MD5SUM_x86_64=""
ARCH="x86_64"
EOF
# stdin: blank (keep continuation URL), then slackrepo n. The read -p prompt is
# suppressed by bash when stdin is piped, so assert on the always-echoed
# "line N (current)" header instead.
out=$(run_mkhint -f plainml -V 1.1.0 < <(printf '\nn\n') 2>&1) || true
echo "$out" | grep -q 'line 2 (current)' \
    && ! echo "$out" | grep -q 'left to bundled-dep reconcile' \
    && { echo "  PASS: non-listed still prompts"; (( PASS++ )); } \
    || { echo "  FAIL: non-listed suppression leak. out=$out"; (( FAIL++ )); ERRORS+=("T-BM25"); }
rm -f "$MOCK_HINT/plainml.hint" "$MOCK_HINT/plainml.hint.bak" "$MOCK_BASE/bundle-manifests"

# ── T-BM19: --check --force apply writes a .bak before rewriting the hint ────
echo ""
echo "T-BM19: --check --force reconcile apply creates a .bak with original content"
setup_bmnvim_check
rm -f "$MOCK_HINT/bmnvim.hint.bak"
run_mkhint -C --force bmnvim < <(printf 'Y\n') >/dev/null 2>&1 || true
[[ -f "$MOCK_HINT/bmnvim.hint.bak" ]] && grep -q 'v0.26.7' "$MOCK_HINT/bmnvim.hint.bak" \
    && { echo "  PASS: .bak created with original (pre-bump) content"; (( PASS++ )); } \
    || { echo "  FAIL: .bak missing or wrong content"; ls "$MOCK_HINT"; (( FAIL++ )); ERRORS+=("T-BM19"); }
rm -f "$MOCK_BASE/manifest_fixture" "$MOCK_BASE/bundle-manifests" "$MOCK_HINT/bmnvim.hint" "$MOCK_HINT/bmnvim.hint.bak"

# ── T-BM20: --check --force with deps already current does NOT create a .bak ─
echo ""
echo "T-BM20: --check --force, bundled deps already current → no .bak churn"
setup_bmnvim_check
# Make the hint's tree-sitter dep URL byte-identical to the manifest's so
# reconcile finds no change (match_dep_url compares full URL strings, not
# just versions — the manifest fixture uses a bare archive/vX.Y.Z.tar.gz
# shape, so the hint line must match that exact shape here).
sed -i 's#tree-sitter/archive/v0.26.7/tree-sitter-0.26.7.tar.gz#tree-sitter/archive/v0.26.8.tar.gz#' "$MOCK_HINT/bmnvim.hint"
rm -f "$MOCK_HINT/bmnvim.hint.bak"
run_mkhint -C --force bmnvim < <(printf 'Y\n') >/dev/null 2>&1 || true
[[ ! -f "$MOCK_HINT/bmnvim.hint.bak" ]] \
    && { echo "  PASS: no .bak written on no-op reconcile"; (( PASS++ )); } \
    || { echo "  FAIL: .bak written despite no changes"; (( FAIL++ )); ERRORS+=("T-BM20"); }
rm -f "$MOCK_BASE/manifest_fixture" "$MOCK_BASE/bundle-manifests" "$MOCK_HINT/bmnvim.hint" "$MOCK_HINT/bmnvim.hint.bak"

# ── T-BM21: changed-deps report shows old and new versions, not bare names ───
echo ""
echo "T-BM21: reconcile changed-deps report shows versions on both sides"
cat > "$MOCK_BASE/manifest_fixture" << 'EOF'
NVIM_URL https://github.com/neovim/neovim/archive/v0.13.0.tar.gz
NVIM_SHA256 a
TREESITTER_URL https://github.com/tree-sitter/tree-sitter/archive/v0.26.8.tar.gz
TREESITTER_SHA256 b
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
rep=$(bash -c "TMP_DIR='$MOCK_TMP'; PATH=\"$MOCK_BASE/bin:\$PATH\"; source '$SCRIPT' 2>/dev/null; reconcile_bundle_deps nvim '$MOCK_HINT/nvim.hint' 'https://x/deps.txt' report" 2>&1) || true
arrow_line=$(echo "$rep" | grep -- '->')
echo "$arrow_line" | grep -q '0.26.7' && echo "$arrow_line" | grep -q '0.26.8' \
    && { echo "  PASS: report shows old and new versions"; (( PASS++ )); } \
    || { echo "  FAIL: report versions. out=$rep"; (( FAIL++ )); ERRORS+=("T-BM21"); }
rm -f "$MOCK_BASE/manifest_fixture" "$MOCK_HINT/nvim.hint"

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
NVCHECKER_CONFIG="$MOCK_BASE/nvchecker.toml"

# README fixture for --info tests (curl dir already exists in setup)
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
set +e
run_mkhint -i doesnotexist > "$MOCK_BASE/info3.out" 2>&1
info3_rc=$?
set -e
assert_exit_code "info3 exit 2"     2 "$info3_rc"
assert_contains "info3 error msg"   "$MOCK_BASE/info3.out" 'not found'

# ── T-INFO4: --info combined with -V → mutually exclusive, exit 1 ──────────────
echo ""
echo "T-INFO4: --info + -V mutually exclusive"
set +e
run_mkhint -i curl -V 9.9.9 > "$MOCK_BASE/info4.out" 2>&1
info4_rc=$?
set -e
assert_exit_code "info4 exit 1"     1 "$info4_rc"

# ── T-INFO5: --info version row, hint higher than SBo → '<', hint side green ──
echo ""
echo "T-INFO5: --info version row differ, hint newer green"
printf 'VERSION="9.0.0"\n' > "$MOCK_HINT/curl.hint"
out=$(MKHINT_FORCE_COLOR=1 run_mkhint -i curl 2>&1)
echo "$out" > "$MOCK_BASE/info5.out"
assert_contains "info5 SBo ver"     "$MOCK_BASE/info5.out" 'SBo: 8.5.0'
assert_contains "info5 hint label"  "$MOCK_BASE/info5.out" 'Hint:'
assert_contains "info5 hint ver"    "$MOCK_BASE/info5.out" '9.0.0'
assert_contains "info5 lt glyph"    "$MOCK_BASE/info5.out" '<'
# hint (9.0.0) is higher → green escape precedes 9.0.0
echo "$out" | grep -qE $'\033\[[0-9;]*m9\.0\.0' \
    && { echo "  PASS: info5 hint side greened"; (( PASS++ )); } \
    || { echo "  FAIL: info5 hint side not greened"; (( FAIL++ )) || true; ERRORS+=("T-INFO5 green"); }
rm -f "$MOCK_HINT/curl.hint"

# ── T-INFO6: --info version row equal → whole row yellow, '=' glyph ────────────
echo ""
echo "T-INFO6: --info version row equal, yellow"
printf 'VERSION="8.5.0"\n' > "$MOCK_HINT/curl.hint"
out=$(MKHINT_FORCE_COLOR=1 run_mkhint -i curl 2>&1)
echo "$out" > "$MOCK_BASE/info6.out"
assert_contains "info6 eq glyph"    "$MOCK_BASE/info6.out" '='
# yellow (tput setaf 3 / \033[33m) wraps the row
echo "$out" | grep -qE $'\033\[(33|[0-9;]*3)m' \
    && { echo "  PASS: info6 row yellow"; (( PASS++ )); } \
    || { echo "  FAIL: info6 row not yellow"; (( FAIL++ )) || true; ERRORS+=("T-INFO6 yellow"); }
rm -f "$MOCK_HINT/curl.hint"

# ── T-INFO7: --info no hint file → '(no hint)' row ────────────────────────────
echo ""
echo "T-INFO7: --info no hint, (no hint) row"
rm -f "$MOCK_HINT/curl.hint"
run_mkhint -i curl > "$MOCK_BASE/info7.out" 2>&1
assert_contains "info7 SBo ver"     "$MOCK_BASE/info7.out" 'SBo: 8.5.0'
assert_contains "info7 no hint"     "$MOCK_BASE/info7.out" 'no hint'

# ── T-INFO8: --info .info has no VERSION → no version row emitted ──────────────
echo ""
echo "T-INFO8: --info no .info VERSION, row skipped"
# strip curl's VERSION so the .info carries none; header prints, no SBo: row
printf 'PRGNAM="curl"\n' > "$MOCK_REPO/network/curl/curl.info"
run_mkhint -i curl > "$MOCK_BASE/info8.out" 2>&1
assert_not_contains "info8 no SBo row" "$MOCK_BASE/info8.out" 'SBo:'
# restore for T-INFO9
printf 'PRGNAM="curl"\nVERSION="8.5.0"\n' > "$MOCK_REPO/network/curl/curl.info"

# ── T-INFO9: --info dashed SBo vs underscore hint, same version → equal yellow ─
echo ""
echo "T-INFO9: --info dashed vs underscore treated equal"
printf 'VERSION="2026-06-02"\n' > "$MOCK_REPO/network/curl/curl.info"
printf 'VERSION="2026_06_02"\n' > "$MOCK_HINT/curl.hint"
out=$(MKHINT_FORCE_COLOR=1 run_mkhint -i curl 2>&1)
echo "$out" > "$MOCK_BASE/info9.out"
assert_contains "info9 eq glyph"    "$MOCK_BASE/info9.out" '='
rm -f "$MOCK_HINT/curl.hint"

# ── T-SHA6a: _github_token reads github key from nvchecker keyfile ─────────────
# Earlier nvchecker-section tests rewrite nvchecker.toml (dropping the keyfile
# line), so restore a keyfile-bearing config here before the token test.
echo ""
echo "T-SHA6a: _github_token reads github key from nvchecker keyfile"
cat > "$MOCK_BASE/keys.toml" << 'EOF'
[keys]
github = "FAKE_TEST_TOKEN_123"
EOF
cat > "$MOCK_BASE/nvchecker.toml" << EOF
[__config__]
oldver = "$MOCK_BASE/old_ver.json"
newver = "$MOCK_BASE/new_ver.json"
keyfile = "$MOCK_BASE/keys.toml"
EOF
tok=$(run_mkhint_fn _github_token)
assert_contains "token parsed" <(echo "$tok") "FAKE_TEST_TOKEN_123"

# ── T-SHA6b: _fetch_submodule_sha returns sha+subrepo, sends auth header ────────
echo ""
echo "T-SHA6b: _fetch_submodule_sha returns sha+subrepo and sends auth header"
cat > "$MOCK_BASE/api_fixture" << 'EOF'
{"type":"submodule","sha":"d1bc25ec4660cddd87804fcf03b2411b5dfb2e94","submodule_git_url":"https://github.com/openvinotoolkit/mlas.git"}
EOF
rm -f "$MOCK_BASE/api.log"
res=$(run_mkhint_fn _fetch_submodule_sha github:openvinotoolkit/openvino src/plugins/intel_cpu/thirdparty/mlas 2024.4.1)
assert_contains "sha returned"    <(echo "$res") "d1bc25ec4660cddd87804fcf03b2411b5dfb2e94"
assert_contains "subrepo lc"      <(echo "$res") "openvinotoolkit/mlas"
assert_contains "auth header sent" "$MOCK_BASE/api.log" "Authorization: Bearer FAKE_TEST_TOKEN_123"
rm -f "$MOCK_BASE/api_fixture"

# ── T-SHA1/2: sha-mode reconcile — drift rewritten, current left alone ─────────
# openvino has two submodule deps: mlas (moved upstream) and onnx (unchanged).
emit_openvino_fixtures() {
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
    cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
openvino sha github:openvinotoolkit/openvino {VERSION} mlas=src/plugins/intel_cpu/thirdparty/mlas onnx=thirdparty/onnx/onnx
EOF
    cat > "$MOCK_BASE/api_mlas.json" << 'EOF'
{"type":"submodule","sha":"a3f9c0177b21ffffffffffffffffffffffffffff","submodule_git_url":"https://github.com/openvinotoolkit/mlas.git"}
EOF
    cat > "$MOCK_BASE/api_onnx.json" << 'EOF'
{"type":"submodule","sha":"990217f043af7222348ca8f0301e17fa7b841781","submodule_git_url":"https://github.com/onnx/onnx.git"}
EOF
}
echo ""
echo "T-SHA1/2: sha-mode reconcile — drift rewritten (mlas), current left (onnx)"
emit_openvino_fixtures
run_sha_reconcile openvino "$MOCK_HINT/openvino.hint" "" apply > "$MOCK_BASE/sha1.out" 2>&1 || true
assert_contains "hint: mlas sha rewritten (path)" "$MOCK_HINT/openvino.hint" "mlas/archive/a3f9c0177b21"
assert_contains "hint: mlas sha rewritten (file)" "$MOCK_HINT/openvino.hint" "mlas-a3f9c0177b21"
assert_contains "hint: onnx sha unchanged"        "$MOCK_HINT/openvino.hint" "onnx-990217f043af"
# report mode shows old->new and (current)
emit_openvino_fixtures
out=$(run_sha_reconcile openvino "$MOCK_HINT/openvino.hint" "" report 2>&1) || true
assert_contains "report mlas old->new" <(echo "$out") "d1bc25e -> a3f9c01"
assert_contains "report onnx current"  <(echo "$out") "(current)"

# ── T-SHA3: 404 on one submodule path is reported and skipped ──────────────────
echo ""
echo "T-SHA3: submodule path 404 — reported skipped, other dep still processed"
emit_openvino_fixtures
rm -f "$MOCK_BASE/api_mlas.json"   # mlas now 404s (no per-path fixture, no fallback)
rm -f "$MOCK_BASE/api_fixture"
out=$(run_sha_reconcile openvino "$MOCK_HINT/openvino.hint" "" report 2>&1) || true
assert_contains "report mlas not found" <(echo "$out") "mlas: submodule path not found"
assert_contains "report onnx still current" <(echo "$out") "(current)"
emit_openvino_fixtures   # restore

# ── T-SHA5: two submodule paths sharing distinct basenames — no cross-contam ───
echo ""
echo "T-SHA5: two same-name-different-owner deps take their own path's sha"
cat > "$MOCK_HINT/openvino.hint" << 'EOF'
VERSION="2024.4.1"
ARCH="x86_64"
DOWNLOAD="UNSUPPORTED"
MD5SUM=""
DOWNLOAD_x86_64="https://github.com/openvinotoolkit/openvino/archive/2024.4.1/openvino-2024.4.1.tar.gz \
          https://github.com/openvinotoolkit/oneDNN/archive/1111111111111111111111111111111111111111/oneDNN-1111111111111111111111111111111111111111.tar.gz \
          https://github.com/oneapi-src/oneDNN/archive/2222222222222222222222222222222222222222/oneDNN-2222222222222222222222222222222222222222.tar.gz"
MD5SUM_x86_64="aaa \
        bbb \
        ccc"
EOF
cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
openvino sha github:openvinotoolkit/openvino {VERSION} onednn=src/plugins/intel_cpu/thirdparty/onednn onednn_gpu=src/plugins/intel_gpu/thirdparty/onednn_gpu
EOF
cat > "$MOCK_BASE/api_onednn.json" << 'EOF'
{"type":"submodule","sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","submodule_git_url":"https://github.com/openvinotoolkit/oneDNN.git"}
EOF
cat > "$MOCK_BASE/api_onednn_gpu.json" << 'EOF'
{"type":"submodule","sha":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","submodule_git_url":"https://github.com/oneapi-src/oneDNN.git"}
EOF
run_sha_reconcile openvino "$MOCK_HINT/openvino.hint" "" apply > /dev/null 2>&1 || true
# openvinotoolkit/oneDNN line must carry onednn path's sha (aaaa...)
grep -q "openvinotoolkit/oneDNN/archive/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$MOCK_HINT/openvino.hint" \
    && grep -q "oneapi-src/oneDNN/archive/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" "$MOCK_HINT/openvino.hint" \
    && { echo "  PASS: each dep took its own path's sha"; (( PASS++ )); } \
    || { echo "  FAIL: cross-contamination"; cat "$MOCK_HINT/openvino.hint"; (( FAIL++ )) || true; ERRORS+=("T-SHA5"); }
rm -f "$MOCK_BASE/api_onednn.json" "$MOCK_BASE/api_onednn_gpu.json"

# ── T-SHA7: manifest dep matching no DOWNLOAD line — FYI, hint unchanged ────────
echo ""
echo "T-SHA7: manifest dep with no matching hint line — FYI, no line added"
emit_openvino_fixtures
cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
openvino sha github:openvinotoolkit/openvino {VERSION} mlas=src/plugins/intel_cpu/thirdparty/mlas onnx=thirdparty/onnx/onnx foo=some/path/foo
EOF
cat > "$MOCK_BASE/api_foo.json" << 'EOF'
{"type":"submodule","sha":"cccccccccccccccccccccccccccccccccccccccc","submodule_git_url":"https://github.com/nobody/foo.git"}
EOF
before=$(grep -c 'archive/' "$MOCK_HINT/openvino.hint")
out=$(run_sha_reconcile openvino "$MOCK_HINT/openvino.hint" "" report 2>&1) || true
after=$(grep -c 'archive/' "$MOCK_HINT/openvino.hint")
assert_contains "report foo no matching line" <(echo "$out") "foo: no matching DOWNLOAD line"
[[ "$before" == "$after" ]] \
    && { echo "  PASS: hint DOWNLOAD line count unchanged"; (( PASS++ )); } \
    || { echo "  FAIL: line count changed $before -> $after"; (( FAIL++ )) || true; ERRORS+=("T-SHA7 count"); }
rm -f "$MOCK_BASE/api_foo.json" "$MOCK_HINT/openvino.hint"
# T-SHA4 (--new prints reconcile report) deferred: needs --new wiring (later task).

# ── T-SET1..6: submodule inventory roster (Job B, detect_set_drift) ─────────────
echo ""
echo "T-SET1..4: submodule inventory roster — added/removed/bundled/ignored tags"
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
cat > "$MOCK_BASE/bundle-manifests" << 'EOF'
openvino sha github:openvinotoolkit/openvino {VERSION} mlas=src/plugins/intel_cpu/thirdparty/mlas onnx=thirdparty/onnx/onnx
EOF
out=$(run_set_drift openvino 2024.4.1 2024.5.0)
assert_contains "onnx removed shown"  <(echo "$out") "thirdparty/onnx/onnx"
assert_contains "onnx ACTION"         <(echo "$out") "ACTION (bundled, removed upstream)"
assert_contains "newdep added review" <(echo "$out") "review (new, not bundled)"
assert_contains "mlas bundled"        <(echo "$out") "bundled"
assert_contains "gtest ignored"       <(echo "$out") "(ignored)"

# ── T-SET5: fetch fail at old ref (no fixture) — inventory skipped notice ───────
echo ""
echo "T-SET5: fetch failure at old ref — inventory skipped"
out=$(run_set_drift openvino 1999.0.0 2024.5.0)
assert_contains "fetch-fail skip notice" <(echo "$out") "inventory skipped"

# ── T-SET6: force no-bump old==new — roster prints, no + glyph ──────────────────
echo ""
echo "T-SET6: old==new (force) — roster prints, no + glyph"
out=$(run_set_drift openvino 2024.5.0 2024.5.0)
assert_contains "roster on force"  <(echo "$out") "submodule inventory 2024.5.0 -> 2024.5.0"
assert_not_contains "no + glyph"   <(echo "$out") "+ src/plugins/foo"
rm -f "$MOCK_BASE/gitmodules_2024.4.1" "$MOCK_BASE/gitmodules_2024.5.0"

# ── T-SHA-CHECK: --check --force openvino runs Job A reconcile + Job B roster ───
# End-to-end wiring test: with openvino sha-mode listed, current (no bump), and
# --force set, the --check reconcile loop must reach BOTH the sha reconcile
# (Job A) and the submodule inventory (Job B). Pre-Task-6 the sha package was
# skipped because manifest_url_for returns non-zero for sha mode.
echo ""
echo "T-SHA-CHECK: --check --force openvino runs Job A reconcile + Job B roster"
emit_openvino_fixtures   # openvino.hint, bundle-manifests (sha), api_mlas/onnx
# nvchecker "sees" openvino as current (2024.4.1) so no bump; --force drives the
# reconcile loop anyway.
cat > "$MOCK_BASE/new_ver.json" << 'EOF'
{ "version": 2, "data": { "openvino": { "version": "2024.4.1" } } }
EOF
cp "$MOCK_BASE/new_ver.json" "$MOCK_BASE/old_ver.json"
# openvino .info in the mock repo (so --check can look it up if needed)
mkdir -p "$MOCK_REPO/development/openvino"
cat > "$MOCK_REPO/development/openvino/openvino.info" << 'EOF'
PRGNAM="openvino"
VERSION="2024.4.1"
EOF
# nvchecker section so the scan recognizes openvino (avoids missing-section path)
printf '\n[openvino]\nsource = "github"\ngithub = "openvinotoolkit/openvino"\n' >> "$MOCK_BASE/nvchecker.toml"
# .gitmodules at the current ref for Job B (old==new==2024.4.1)
cat > "$MOCK_BASE/gitmodules_2024.4.1" << 'EOF'
[submodule "onnx"]
	path = thirdparty/onnx/onnx
	url = https://github.com/onnx/onnx.git
[submodule "mlas"]
	path = src/plugins/intel_cpu/thirdparty/mlas
	url = https://github.com/openvinotoolkit/mlas.git
EOF
echo "y" | run_mkhint -C --force openvino > "$MOCK_BASE/chk.out" 2>&1 || true
assert_contains "Job A ran (sha reconcile)"     "$MOCK_BASE/chk.out" "bundled deps (sha)"
assert_contains "Job B ran (submodule inventory)" "$MOCK_BASE/chk.out" "submodule inventory"
rm -f "$MOCK_HINT/openvino.hint" "$MOCK_HINT/openvino.hint.bak" \
      "$MOCK_BASE/bundle-manifests" "$MOCK_BASE/gitmodules_2024.4.1" \
      "$MOCK_BASE/api_mlas.json" "$MOCK_BASE/api_onnx.json"
rm -rf "$MOCK_REPO/development/openvino"

# ─── SUMMARY ──────────────────────────────────────────────────────────────────
teardown

echo ""
echo "========================================"
echo " Results: $PASS passed, $FAIL failed"
if [[ ${#ERRORS[@]} -gt 0 ]]; then
    echo " Failed tests:"
    for e in "${ERRORS[@]}"; do echo "   - $e"; done
fi
echo "========================================"
[[ $FAIL -eq 0 ]]
