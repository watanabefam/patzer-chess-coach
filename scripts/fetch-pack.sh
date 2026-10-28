#!/usr/bin/env bash
# Download and unpack a released voice pack into packs/<pack>/.
#
#   ./scripts/fetch-pack.sh                     # latest en-child
#   ./scripts/fetch-pack.sh en-child v1.0.0     # specific tag
#
# Clips are build outputs and are never committed (PLAN.md §11.7), so this step
# is required before Patzer can serve audio from a fresh clone.
#
# Note: GitHub release assets do not send CORS headers, so this must be run from
# the command line — a browser fetch() will fail. That is fine here: Patzer's own
# server serves the clips once they are on disk.
set -euo pipefail

PACK="${1:-en-child}"
VERSION="${2:-latest}"
REPO="${REPO:-watanabefam/patzer-chess-coach}"

DEST="packs/${PACK}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$DEST"

if [ "$VERSION" = "latest" ]; then
  echo "Fetching latest ${PACK} from ${REPO}…"
  TAG_ARGS=()
  URL="https://github.com/${REPO}/releases/latest/download/${PACK}-clips.tar.gz"
else
  echo "Fetching ${PACK} ${VERSION} from ${REPO}…"
  TAG_ARGS=("$VERSION")
  URL="https://github.com/${REPO}/releases/download/${VERSION}/${PACK}-clips.tar.gz"
fi

if command -v gh >/dev/null 2>&1; then
  gh release download "${TAG_ARGS[@]}" --repo "$REPO" \
     --pattern "${PACK}-clips.tar.gz" --dir "$TMP" --clobber
else
  curl -fSL "$URL" -o "$TMP/${PACK}-clips.tar.gz"
fi

ARCHIVE="$(find "$TMP" -name '*.tar.gz' | head -1)"
[ -n "$ARCHIVE" ] || { echo "error: no archive downloaded" >&2; exit 1; }

echo "Unpacking into ${DEST}/ …"
tar -xzf "$ARCHIVE" -C "$DEST"

COUNT="$(find "$DEST/clips" -type f -name '*.opus' | wc -l | tr -d ' ')"
echo "Done — ${COUNT} clips installed."

if command -v python3 >/dev/null 2>&1 && [ -f build/verify.py ]; then
  python3 build/verify.py --pack "$PACK"
fi
