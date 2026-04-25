#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SIMH_REPO_URL="${SIMH_REPO_URL:-https://github.com/simh/simh.git}"
SIMH_DIR="${SIMH_DIR:-$REPO_ROOT/.tools/simh}"
SIMH_BIN_DIR="${SIMH_BIN_DIR:-$REPO_ROOT/.tools/bin}"
SIMH_TARGET="${SIMH_TARGET:-swtp6800mp-a}"

mkdir -p "$(dirname "$SIMH_DIR")" "$SIMH_BIN_DIR"

if [ ! -d "$SIMH_DIR/.git" ]; then
  echo "[setup] Cloning SIMH from $SIMH_REPO_URL"
  git clone --depth=1 "$SIMH_REPO_URL" "$SIMH_DIR"
else
  echo "[setup] SIMH already cloned: $SIMH_DIR"
fi

cd "$SIMH_DIR"

echo "[setup] Building SWTPC 6800 simulator target ($SIMH_TARGET)"
# Keep CI/Codespaces builds non-interactive and aligned with SIMH guidance.
make -j"$(nproc)" "$SIMH_TARGET" BUILD_SEPARATE=1 QUIET=1

BIN_CANDIDATES=(
  "$SIMH_DIR/BIN/$SIMH_TARGET"
  "$SIMH_DIR/BIN/swtp6800"
  "$SIMH_DIR/BIN/swtp6800mp-a"
  "$SIMH_DIR/BIN/swtp6800mp-a2"
)

SIMH_BINARY=""
for candidate in "${BIN_CANDIDATES[@]}"; do
  if [ -x "$candidate" ]; then
    SIMH_BINARY="$candidate"
    break
  fi
done

if [ -z "$SIMH_BINARY" ]; then
  echo "[setup] ERROR: expected SWTPC binary not found in $SIMH_DIR/BIN" >&2
  echo "[setup] Looked for: ${BIN_CANDIDATES[*]}" >&2
  exit 1
fi

ln -sf "$SIMH_BINARY" "$SIMH_BIN_DIR/swtp6800"

echo "[setup] SWTPC 6800 simulator ready: $SIMH_BIN_DIR/swtp6800 (source: $SIMH_BINARY)"
"$SIMH_BIN_DIR/swtp6800" -V || true
