#!/usr/bin/env sh
# mdp standalone installer.
#
# Clones (or updates) the repo to $PREFIX/share/md-preview and symlinks
# $PREFIX/bin/mdp to scripts/mdp. The renderer self-bootstraps a Python
# venv on first run, so nothing else to install.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/aldevv/md-preview.nvim/main/install.sh | sh
#
# Override target prefix:
#   PREFIX=$HOME/.local sh install.sh   # default
#   PREFIX=/usr/local   sh install.sh   # system-wide (needs sudo)

set -eu

REPO_URL="${REPO_URL:-https://github.com/aldevv/md-preview.nvim.git}"
PREFIX="${PREFIX:-$HOME/.local}"
SHARE="$PREFIX/share/md-preview"
BIN="$PREFIX/bin"
LINK="$BIN/mdp"

command -v git >/dev/null 2>&1 || { echo "mdp install: git is required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "mdp install: python3 is required" >&2; exit 1; }

mkdir -p "$BIN"

if [ -d "$SHARE/.git" ]; then
    echo "[mdp] updating $SHARE"
    git -C "$SHARE" pull --ff-only --quiet
else
    echo "[mdp] cloning into $SHARE"
    mkdir -p "$(dirname "$SHARE")"
    git clone --depth 1 --quiet "$REPO_URL" "$SHARE"
fi

ln -sfn "$SHARE/scripts/mdp" "$LINK"
echo "[mdp] linked $LINK -> $SHARE/scripts/mdp"

case ":${PATH-}:" in
    *":$BIN:"*) ;;
    *) echo "[mdp] note: $BIN is not in PATH — add it to your shell rc:"
       echo "       export PATH=\"$BIN:\$PATH\"" ;;
esac

echo "[mdp] done. Try: mdp --help"
