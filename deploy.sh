#!/bin/bash
# deploy.sh — copy mkhint and its companion files to the buildsystem VM and
# verify each copy by md5sum. For pre-release hand-testing on real data.
#
# Usage:
#   ./deploy.sh                 # deploy to the default host "buildsystem"
#   ./deploy.sh myhost          # deploy to a different ssh alias
#   DEPLOY_HOST=myhost ./deploy.sh
#
# Destinations (see CLAUDE.md "Releasing", step 4):
#   mkhint                 -> /usr/local/bin/mkhint
#   mkhint.bash-completion -> /etc/bash_completion.d/mkhint
#   mkhint.1.gz            -> /usr/local/man/man1/mkhint.1.gz
#
# SSH runs as root (the "buildsystem" alias uses `User root`), so scp writes
# straight into the root-owned destinations. The completion dir is probed on
# the remote, preferring the hyphen variant, mirroring install.sh.

set -euo pipefail

HOST="${1:-${DEPLOY_HOST:-buildsystem}}"

cd "$(dirname "$0")"

# Fail fast on missing sources before touching the remote.
for f in mkhint mkhint.bash-completion mkhint.1.gz; do
    [[ -f "$f" ]] || { echo "ERROR: missing local file: $f" >&2; exit 2; }
done

echo "Deploying mkhint to ${HOST} …"
echo

# Probe the remote completion dir (hyphen form first, like install.sh).
if ! COMP_DIR="$(ssh -q "$HOST" 'if [ -d /etc/bash-completion.d ]; then printf /etc/bash-completion.d; else printf /etc/bash_completion.d; fi' 2>/dev/null)"; then
    echo "ERROR: cannot reach ${HOST} (is the ssh alias/key set up?)" >&2
    exit 1
fi

FILES=(
  "mkhint:/usr/local/bin/mkhint:755"
  "mkhint.bash-completion:${COMP_DIR}/mkhint:644"
  "mkhint.1.gz:/usr/local/man/man1/mkhint.1.gz:644"
)

# Make sure the destination dirs exist.
ssh -q "$HOST" "mkdir -p /usr/local/bin /usr/local/man/man1 '$COMP_DIR'" \
    || { echo "ERROR: cannot reach ${HOST} (is the ssh alias/key set up?)" >&2; exit 1; }

rc=0
for entry in "${FILES[@]}"; do
    IFS=: read -r src dst mode <<< "$entry"

    local_md5="$(md5sum "$src" | awk '{print $1}')"
    printf '→ %-26s %s:%s\n' "$src" "$HOST" "$dst"

    if ! scp -q "$src" "${HOST}:${dst}"; then
        echo "  ✗ scp failed" >&2; rc=1; continue
    fi
    ssh -q "$HOST" "chmod $mode '$dst'" || { echo "  ✗ chmod failed" >&2; rc=1; continue; }

    remote_md5="$(ssh -q "$HOST" "md5sum '$dst'" | awk '{print $1}')"
    if [[ "$local_md5" == "$remote_md5" ]]; then
        echo "  ✓ md5 $local_md5"
    else
        echo "  ✗ MD5 MISMATCH — local=$local_md5 remote=$remote_md5" >&2
        rc=1
    fi
done

echo

# Smoke test: the deployed binary should run and report the local version.
if remote_ver="$(ssh -q "$HOST" 'mkhint --version 2>/dev/null')"; then
    local_ver="$(bash ./mkhint --version 2>/dev/null || true)"
    echo "local : $local_ver"
    echo "remote: $remote_ver"
    [[ "$remote_ver" == "$local_ver" ]] || { echo "✗ version mismatch" >&2; rc=1; }
else
    echo "WARNING: 'mkhint --version' failed on ${HOST} (is /usr/local/bin on PATH?)" >&2
fi

echo
if [[ $rc -eq 0 ]]; then
    echo "✓ Deploy OK — hand-test away."
    echo "  Re-source completion in any open shell: source ${COMP_DIR}/mkhint"
else
    echo "✗ Deploy FAILED — see above." >&2
    exit 1
fi
