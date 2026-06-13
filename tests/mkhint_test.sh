#!/bin/bash
# mkhint test suite - uses mock dirs, no real downloads

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/mkhint"
MOCK_BASE="/tmp/mkhint_test_$$"
MOCK_REPO="$MOCK_BASE/repo"
MOCK_HINT="$MOCK_BASE/hints"
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

    # nvchecker: no-op success (keyfile is pre-seeded by setup/tests)
    cat > "$MOCK_BASE/bin/nvchecker" << 'EOF'
#!/bin/bash
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
run_mkhint -n curl -v 8.6.0
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
run_mkhint -n curl -v 8.7.0 -N
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
run_mkhint -f curl -v 8.9.0
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
run_mkhint -f curl -v 9.0.0 -N
assert_contains       "VERSION updated"          "$MOCK_HINT/curl.hint" 'VERSION="9.0.0"'
assert_not_contains   "MD5SUM recalculated"      "$MOCK_HINT/curl.hint" 'abc123def456'
assert_contains       "NODOWNLOAD present"       "$MOCK_HINT/curl.hint" 'NODOWNLOAD=yes'

# ── T8: DOWNLOAD=UNSUPPORTED, DOWNLOAD_x86_64 has URL ─────────────────────────
echo ""
echo "T8: DOWNLOAD=UNSUPPORTED → skip 32bit, recalc x86_64 md5"
run_mkhint -n clion
assert_contains       "DOWNLOAD UNSUPPORTED kept" "$MOCK_HINT/clion.hint" 'DOWNLOAD="UNSUPPORTED"'

# Update it
run_mkhint -f clion -v 2025.4
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
run_mkhint -f nonexistent -v 1.0 2>/dev/null
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
echo "" | run_mkhint -n protoc-gen-go-grpc -v 1.4.0
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
run_mkhint -C -v 1.0 2>/dev/null
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
