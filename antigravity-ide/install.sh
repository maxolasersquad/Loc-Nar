#!/bin/sh
# install.sh for Antigravity IDE
# Arguments: --location <path> --version <tag>

set -eu
LOCATION=""
VERSION=""

# Parse arguments
while [ "$#" -gt 0 ]; do
  case "$1" in
    --location=*) LOCATION="${1#*=}"; shift;;
    --location) LOCATION="$2"; shift 2;;
    --version=*) VERSION="${1#*=}"; shift;;
    --version) VERSION="$2"; shift 2;;
    *) echo "Unknown argument $1" >&2; exit 1;;
  esac
done

if [ -z "${LOCATION}" ] || [ -z "${VERSION}" ]; then
  echo "Missing required arguments" >&2; exit 2
fi

# Determine architecture
ARCH=$(uname -m)
case "${ARCH}" in
  x86_64) OS_ARCH="linux-x64";;
  aarch64|arm64) OS_ARCH="linux-arm";;
  *) echo "Unsupported architecture ${ARCH}" >&2; exit 2;;
esac

# Construct URL
# Note: Space in "Antigravity IDE.tar.gz" is URL-encoded as %20
BASE_URL="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${VERSION}/${OS_ARCH}/Antigravity%20IDE.tar.gz"
TMP_DIR=$(mktemp -d)

# shellcheck disable=SC2329
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT INT TERM

# Download
if ! command -v curl >/dev/null; then echo "curl missing" >&2; exit 6; fi
if ! curl -fsSL -o "${TMP_DIR}/antigravity-ide.tar.gz" "${BASE_URL}"; then
  echo "Download failed" >&2; exit 3
fi

# Extract
mkdir -p "${LOCATION}"
if ! tar -xzf "${TMP_DIR}/antigravity-ide.tar.gz" -C "${LOCATION}"; then
  echo "Extraction failed" >&2; exit 4
fi

# Locate the extracted subdirectory
EXTRACTED_DIR=""
for pattern in "Antigravity IDE" "antigravity-ide" "Antigravity"; do
  if [ -d "${LOCATION}/${pattern}" ]; then
    EXTRACTED_DIR="${LOCATION}/${pattern}"
    break
  fi
done

if [ -n "${EXTRACTED_DIR}" ]; then
  # Move all contents to parent LOCATION directory
  mv "${EXTRACTED_DIR}"/* "${LOCATION}/" 2>/dev/null || true
  mv "${EXTRACTED_DIR}"/.* "${LOCATION}/" 2>/dev/null || true
  rmdir "${EXTRACTED_DIR}" 2>/dev/null || true
fi

rm -rf "${TMP_DIR}"

echo "antigravity-ide"
exit 0
