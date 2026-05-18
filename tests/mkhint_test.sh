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
