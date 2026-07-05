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
             "$MOCK_REPO/multimedia/yt-dlp" \
             "$MOCK_REPO/development/gopkg" \
             "$MOCK_REPO/development/rustpkg" \
             "$MOCK_REPO/development/mixedpkg" \
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

    # phantom-dep list consumed by --fix-current and --new
    cat > "$MOCK_BASE/phantom-deps" << 'EOF'
# deps unneeded on -current
rust-opt
google-go-lang
EOF

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
}

teardown() {
    rm -rf "$MOCK_BASE"
}

run_mkhint() {
    local tmp_script
    tmp_script=$(mktemp /tmp/mkhint_patched_XXXXXX)
    sed \
        -e "s|REPO_DIR=\".*\"|REPO_DIR=\"$MOCK_REPO\"|" \
        -e "s|HINT_DIR=\".*\"|HINT_DIR=\"$MOCK_HINT\"|" \
        -e "s|TMP_DIR=\".*\"|TMP_DIR=\"$MOCK_TMP\"|" \
        -e "s|NVCHECKER_CONFIG=\".*\"|NVCHECKER_CONFIG=\"$MOCK_BASE/nvchecker.toml\"|" \
        -e "s|PHANTOM_DEPS_FILE=\".*\"|PHANTOM_DEPS_FILE=\"$MOCK_BASE/phantom-deps\"|" \
        -e "s|PACKAGES_DIR=\".*\"|PACKAGES_DIR=\"$MOCK_PKGS\"|" \
        -e "s|MKHINT_CONFIG=\".*\"|MKHINT_CONFIG=\"$MOCK_BASE/config\"|" \
        "$SCRIPT" > "$tmp_script"
    bash "$tmp_script" "$@"
    local rc=$?
    rm -f "$tmp_script"
    return $rc
}

# Mock wget — writes fake content, md5 will be deterministic
mock_wget() {
    # Replace wget in PATH with a fake that writes URL as content
    mkdir -p "$MOCK_BASE/bin"
    cat > "$MOCK_BASE/bin/wget" << 'EOF'
#!/bin/bash
# fake wget: write URL to -O target
url=""
out=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -O) out="$2"; shift 2 ;;
        *) url="$1"; shift ;;
    esac
done
echo "FAKE_CONTENT_FOR_${url}" > "$out"
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
# blank = accept latest (8.9.0 from keyfile); n = skip slackrepo
run_mkhint -f curl < <(printf '\nn\n')
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
run_mkhint -C curl < <(printf 'Y\nn\n')
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
