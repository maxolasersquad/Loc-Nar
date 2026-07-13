#!/bin/sh
# switch.sh for Antigravity Hub
# Arguments: --location <path> --version <tag>

set -eu
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

ABS_PATH="$(realpath "${LOCATION}/antigravity")"

echo "${ABS_PATH}"
exit 0
