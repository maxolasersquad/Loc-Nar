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
  --location)
    if [ -n "${2}" ]; then
      location_path="${2}"
      shift
      shift
    else
      _error_msg "--location option requires a path argument."
      exit 1
    fi
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
  _error_msg "--location argument is required (should be passed by trk)."
  exit 1
fi

_log_msg "Running lazygit uninstall script for location: ${location_path}"

_log_msg "No lazygit-specific external files to clean up."

_log_msg "lazygit uninstall script finished."
exit 0
