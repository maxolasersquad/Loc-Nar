#!/bin/sh

fetch_content() {
  url="${1}"
  if command -v curl >/dev/null 2>&1; then
    curl -sL "${url}"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "${url}"
  else
    return 1
  fi
}

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  printf 'INSTALLER ERROR: Either curl or wget is required to list versions.\n' >&2
  return 1
fi

raw_html=$(fetch_content "https://www.gryphel.com/c/minivmac/download.html" 2>/dev/null)
raw_html="${raw_html} $(fetch_content "https://www.gryphel.com/c/minivmac/beta.html" 2>/dev/null)"
raw_html="${raw_html} $(fetch_content "https://www.gryphel.com/c/minivmac/old.html" 2>/dev/null)"

versions=$(printf '%s\n' "${raw_html}" | grep -oE 'minivmac-[0-9]+(\.[0-9]+)+\.src' | sed 's/minivmac-//;s/\.src//' | sort -u -rV)

if [ -n "${versions}" ]; then
  printf '%s\n' "${versions}"
else
  # Fallback to known stable, beta, and legacy releases
  printf '%s\n' "37.03"
  printf '%s\n' "36.04"
  printf '%s\n' "3.5.8"
fi
