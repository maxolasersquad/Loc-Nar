#!/bin/sh

github_api_url="https://api.github.com/repos/ClassicUO/ClassicUO/releases"

if ! command -v jq >/dev/null 2>&1; then
  printf 'INSTALLER ERROR: jq is required to list versions.\n' >&2
  return 6
fi

if command -v curl >/dev/null 2>&1; then
  curl -sL "${github_api_url}" | jq -r 'map(select(.assets | any(.name | startswith("ClassicUO-linux-x64")))) | .[].tag_name'
elif command -v wget >/dev/null 2>&1; then
  wget -qO- "${github_api_url}" | jq -r 'map(select(.assets | any(.name | startswith("ClassicUO-linux-x64")))) | .[].tag_name'
else
  printf 'INSTALLER ERROR: Either curl or wget is required to list versions.\n' >&2
  return 6
fi
