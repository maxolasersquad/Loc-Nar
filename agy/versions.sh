#!/bin/sh
# versions.sh for Antigravity CLI
# Prints available versions (newest first)

set -eu
RELEASES_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/releases"

if command -v curl >/dev/null 2>&1; then
  curl -fsSL "${RELEASES_URL}" | jq -r '.[].version'
elif command -v wget >/dev/null 2>&1; then
  wget -qO- "${RELEASES_URL}" | jq -r '.[].version'
else
  echo "Either curl or wget is required to list versions." >&2
  exit 6
fi
