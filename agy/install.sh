#!/bin/sh
# install.sh for Antigravity CLI
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

# Fetch execution_id from releases API
RELEASES_URL="https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/releases"

if command -v curl >/dev/null 2>&1; then
  RELEASES_JSON=$(curl -fsSL "${RELEASES_URL}")
elif command -v wget >/dev/null 2>&1; then
  RELEASES_JSON=$(wget -qO- "${RELEASES_URL}")
else
  echo "Either curl or wget is required to retrieve release info" >&2; exit 6
fi

# Check for jq
if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to parse release information" >&2; exit 6
fi

EXECUTION_ID=$(echo "${RELEASES_JSON}" | jq -r --arg ver "${VERSION}" '.[] | select(.version == $ver) | .execution_id')

if [ -z "${EXECUTION_ID}" ] || [ "${EXECUTION_ID}" = "null" ]; then
  echo "Version ${VERSION} not found on release server" >&2; exit 2
fi

# Determine architecture
ARCH=$(uname -m)
case "${ARCH}" in
  x86_64) 
    OS_ARCH="linux-x64"
    OS_ARCH_UNDERSCORE="linux_x64"
    ;;
  aarch64|arm64) 
    OS_ARCH="linux-arm"
    OS_ARCH_UNDERSCORE="linux_arm"
    ;;
  *) 
    echo "Unsupported architecture ${ARCH}" >&2; exit 2
    ;;
esac

# Download package from Google Storage
BASE_URL="https://storage.googleapis.com/antigravity-public/antigravity-cli/${VERSION}-${EXECUTION_ID}/${OS_ARCH}/cli_${OS_ARCH_UNDERSCORE}.tar.gz"

TMP_DIR=$(mktemp -d)

# Cleanup trap
# shellcheck disable=SC2329
cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT INT TERM

if command -v curl >/dev/null 2>&1; then
  curl -fsSL -o "${TMP_DIR}/cli.tar.gz" "${BASE_URL}"
else
  wget -q -O "${TMP_DIR}/cli.tar.gz" "${BASE_URL}"
fi

# Extract
mkdir -p "${LOCATION}"
if ! tar -xzf "${TMP_DIR}/cli.tar.gz" -C "${TMP_DIR}" antigravity 2>/dev/null; then
  echo "Extraction failed" >&2; exit 4
fi

# Place binary as agy
cp "${TMP_DIR}/antigravity" "${LOCATION}/agy"
chmod +x "${LOCATION}/agy"

echo "agy"
exit 0
