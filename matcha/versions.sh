#!/bin/sh

github_api_url="https://api.github.com/repos/floatpane/matcha/releases"

if command -v curl >/dev/null 2>&1; then
  curl -sL "${github_api_url}" | jq -r 'map(select(.tag_name | startswith("v"))) | map(.tag_name) | sort_by(split(".") | map(ltrimstr("v") | try tonumber catch .)) | reverse | .[]'
elif command -v wget >/dev/null 2>&1; then
  wget -qO- "${github_api_url}" | jq -r 'map(select(.tag_name | startswith("v"))) | map(.tag_name) | sort_by(split(".") | map(ltrimstr("v") | try tonumber catch .)) | reverse | .[]'
else
  printf 'INSTALLER ERROR: Either curl or wget is required to list versions.\n' >&2
  return 1
fi
