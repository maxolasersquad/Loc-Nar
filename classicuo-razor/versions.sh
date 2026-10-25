#!/bin/sh

github_api_url="https://api.github.com/repos/markdwags/Razor/releases"

if command -v jq >/dev/null 2>&1; then
  if command -v curl >/dev/null 2>&1; then
    curl -sL "${github_api_url}" | jq -r 'map(select(.tag_name | startswith("v"))) | map(.tag_name) | sort_by(split(".") | map(ltrimstr("v") | try tonumber catch .)) | reverse | .[]'
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "${github_api_url}" | jq -r 'map(select(.tag_name | startswith("v"))) | map(.tag_name) | sort_by(split(".") | map(ltrimstr("v") | try tonumber catch .)) | reverse | .[]'
  else
    printf 'INSTALLER ERROR: Either curl or wget is required to list versions.\n' >&2
    exit 6
  fi
else
  # Fallback when jq is not available: filter tag names using grep/sed
  if command -v curl >/dev/null 2>&1; then
    curl -sL "${github_api_url}" | grep '"tag_name":' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' | grep '^v'
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "${github_api_url}" | grep '"tag_name":' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/' | grep '^v'
  else
    printf 'INSTALLER ERROR: Either curl or wget is required to list versions.\n' >&2
    exit 6
  fi
fi
