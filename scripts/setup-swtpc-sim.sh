#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SIMH_REPO_URL="${SIMH_REPO_URL:-https://github.com/simh/simh.git}"
SIMH_DIR="${SIMH_DIR:-$REPO_ROOT/.tools/simh}"
SIMH_BIN_DIR="${SIMH_BIN_DIR:-$REPO_ROOT/.tools/bin}"

mkdir -p "$(dirname "$SIMH_DIR")" "$SIMH_BIN_DIR"

if [ ! -d "$SIMH_DIR/.git" ]; then
  echo "[setup] Cloning SIMH from $SIMH_REPO_URL"
  git clone --depth=1 "$SIMH_REPO_URL" "$SIMH_DIR"
else
  echo "[setup] SIMH already cloned: $SIMH_DIR"
fi

cd "$SIMH_DIR"

echo "[setup] Building SWTPC 6800 simulator target (swtp6800)"
make -j"$(nproc)" swtp6800

if [ ! -x "$SIMH_DIR/BIN/swtp6800" ]; then
  echo "[setup] ERROR: expected binary not found at $SIMH_DIR/BIN/swtp6800" >&2
  exit 1
fi

ln -sf "$SIMH_DIR/BIN/swtp6800" "$SIMH_BIN_DIR/swtp6800"

echo "[setup] SWTPC 6800 simulator ready: $SIMH_BIN_DIR/swtp6800"
"$SIMH_BIN_DIR/swtp6800" -V || true
