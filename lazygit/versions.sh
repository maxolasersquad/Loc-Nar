#!/bin/sh

github_api_url="https://api.github.com/repos/jesseduffield/lazygit/releases"
jq_filter='.[].tag_name' # Extract all tag names

if command -v curl >/dev/null 2>&1; then
  curl -sL "${github_api_url}" | jq -r "${jq_filter}"
elif command -v wget >/dev/null 2>&1; then
  wget -qO- "${github_api_url}" | jq -r "${jq_filter}"
else
  printf 'INSTALLER ERROR: Either curl or wget is required to list versions.\n' >&2
  exit 1
fi

exit 0
