#!/bin/sh
# uninstall.sh for Antigravity Hub
# Arguments: --location <path>

set -eu
while [ "$#" -gt 0 ]; do
  case "$1" in
    --location=*) LOCATION="${1#*=}"; shift;;
    --location) LOCATION="$2"; shift 2;;
    *) echo "Unknown argument $1" >&2; exit 1;;
  esac
done

if [ -z "${LOCATION}" ]; then
  echo "Missing required --location argument" >&2; exit 2
fi

# Remove the installation directory
if [ -d "${LOCATION}" ]; then
  rm -rf "${LOCATION}"
  echo "Antigravity 2.0 uninstalled from ${LOCATION}"
else
  echo "Location ${LOCATION} does not exist" >&2; exit 7
fi

exit 0
