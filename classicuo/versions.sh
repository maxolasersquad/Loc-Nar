#!/bin/sh

github_api_url="https://api.github.com/repos/ClassicUO/ClassicUO/releases"

if command -v jq >/dev/null 2>&1; then
  if command -v curl >/dev/null 2>&1; then
    curl -sL "${github_api_url}" | jq -r 'map(select(.assets | any(.name | startswith("ClassicUO-linux-x64")))) | .[].tag_name'
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "${github_api_url}" | jq -r 'map(select(.assets | any(.name | startswith("ClassicUO-linux-x64")))) | .[].tag_name'
  else
    printf 'INSTALLER ERROR: Either curl or wget is required to list versions.\n' >&2
    exit 6
  fi
else
  # Fallback when jq is not installed: filter tags with ClassicUO Linux assets using awk
  if command -v curl >/dev/null 2>&1; then
    curl -sL "${github_api_url}" | awk '
      /"tag_name":/ {
        match($0, /"tag_name": *"([^"]+)"/, arr)
        tag = arr[1]
      }
      /"name": *"ClassicUO-linux-x64.*\.zip"/ {
        if (tag != "") {
          print tag
          tag = ""
        }
      }
    '
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "${github_api_url}" | awk '
      /"tag_name":/ {
        match($0, /"tag_name": *"([^"]+)"/, arr)
        tag = arr[1]
      }
      /"name": *"ClassicUO-linux-x64.*\.zip"/ {
        if (tag != "") {
          print tag
          tag = ""
        }
      }
    '
  else
    printf 'INSTALLER ERROR: Either curl or wget is required to list versions.\n' >&2
    exit 6
  fi
fi
