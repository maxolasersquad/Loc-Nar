#!/bin/sh
# install.sh for Antigravity Hub
# Arguments: --location <path> --version <tag>

set -eu

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
  echo "Missing required arguments" >&2
  exit 2
fi

# Determine architecture
ARCH=$(uname -m)
case "${ARCH}" in
  x86_64) OS_ARCH="linux-x64";;
  aarch64|arm64) OS_ARCH="linux-arm";;
  *) echo "Unsupported architecture ${ARCH}" >&2; exit 2;;
esac

BASE_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/${VERSION}/${OS_ARCH}/Antigravity.tar.gz"
TMP_DIR=$(mktemp -d)

# Download
if ! command -v curl >/dev/null; then echo "curl missing" >&2; exit 6; fi
if ! curl -L -o "${TMP_DIR}/antigravity.tar.gz" "${BASE_URL}"; then
  echo "Download failed" >&2
  exit 3
fi

# Extract
mkdir -p "${LOCATION}"
if ! tar -xzf "${TMP_DIR}/antigravity.tar.gz" -C "${LOCATION}"; then
  echo "Extraction failed" >&2
  exit 4
fi

# Locate the extracted subdirectory
EXTRACTED_DIR=""
for pattern in "Antigravity-x64" "Antigravity-arm" "Antigravity"; do
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

echo "antigravity"
exit 0
