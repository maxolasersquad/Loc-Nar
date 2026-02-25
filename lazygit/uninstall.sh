#!/bin/sh

location_path=""
verbose=0

_log_msg() {
  if [ "${verbose}" -eq 1 ]; then
    printf 'UNINSTALLER VERBOSE: %s\n' "$*" >&2
  fi
}
_error_msg() { printf 'UNINSTALLER ERROR: %s\n' "$*" >&2; }

while [ $# -gt 0 ]; do
  case "${1}" in
  --location=*)
    location_path="${1#*=}"
    shift
    ;;
  --location)
    location_path="${2}"
    shift 2
    ;;
  --verbose)
    verbose=1
    shift
    ;;
  *)
    _log_msg "Ignoring unknown argument: ${1}"
    shift
    ;;
  esac
done

if [ -z "${location_path}" ]; then
  _error_msg "--location argument is required."
  return 1
fi

_log_msg "Running lazygit uninstall script for location: ${location_path}"

_log_msg "No lazygit-specific external files to clean up."

_log_msg "lazygit uninstall script finished."
