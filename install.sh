#!/bin/bash
# install.sh — install (or uninstall) mkhint, its bash completion, and man page.
#
# Run as root for a system-wide install, or as a normal user for a user-only
# install under ~/.local. Usage:
#
#   ./install.sh              system install if root, else user install
#   ./install.sh uninstall    remove the files from wherever they were installed
#
# Copyright (C) 2026 Danilo M. <danix@danix.xyz>
# Licensed under the GNU GPL v2 (see LICENSE).

set -e

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

BIN_SRC="$SRC_DIR/mkhint"
COMP_SRC="$SRC_DIR/mkhint.bash-completion"
MAN_SRC="$SRC_DIR/mkhint.1.gz"

# Pick paths based on privilege.
if [[ $EUID -eq 0 ]]; then
    MODE="system"
    BIN_DIR="/usr/local/bin"
    MAN_DIR="/usr/local/man/man1"
    # Slackware ships /etc/bash_completion.d (underscore); some distros use the
    # hyphen. Install to whichever exists, defaulting to underscore.
    if [[ -d /etc/bash-completion.d ]]; then
        COMP_DIR="/etc/bash-completion.d"
    else
        COMP_DIR="/etc/bash_completion.d"
    fi
else
    MODE="user"
    BIN_DIR="$HOME/.local/bin"
    MAN_DIR="$HOME/.local/share/man/man1"
    COMP_DIR="$HOME/.local/share/bash-completion/completions"
fi

BIN_DST="$BIN_DIR/mkhint"
COMP_DST="$COMP_DIR/mkhint"
MAN_DST="$MAN_DIR/mkhint.1.gz"

if [[ "$1" == "uninstall" ]]; then
    echo "Uninstalling mkhint ($MODE)..."
    rm -fv "$BIN_DST" "$COMP_DST" "$MAN_DST"
    echo "Done."
    exit 0
fi

if [[ -n "$1" ]]; then
    echo "Unknown argument: $1" >&2
    echo "Usage: $0 [uninstall]" >&2
    exit 1
fi

# Sanity-check sources before touching the filesystem.
for f in "$BIN_SRC" "$COMP_SRC" "$MAN_SRC"; do
    if [[ ! -f "$f" ]]; then
        echo "Missing source file: $f" >&2
        exit 2
    fi
done

echo "Installing mkhint ($MODE)..."
install -Dm755 "$BIN_SRC"  "$BIN_DST"  && echo "  $BIN_DST"
install -Dm644 "$COMP_SRC" "$COMP_DST" && echo "  $COMP_DST"
install -Dm644 "$MAN_SRC"  "$MAN_DST"  && echo "  $MAN_DST"
echo "Done."

# On Slackware ~/.local/bin is not on PATH by default; warn if the bin dir is
# not reachable so the user knows to fix it.
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) echo
       echo "NOTE: $BIN_DIR is not on your PATH."
       echo "      Add it, e.g.:  export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac
