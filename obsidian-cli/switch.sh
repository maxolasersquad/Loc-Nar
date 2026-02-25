#!/bin/sh

location_path=""
version=""
verbose=0

_log_msg() {
  if [ "${verbose}" -eq 1 ]; then
    printf 'SWITCH VERBOSE: %s\n' "$*" >&2
  fi
}
_error_msg() { printf 'SWITCH ERROR: %s\n' "$*" >&2; }

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
  --version=*)
    version="${1#*=}"
    shift
    ;;
  --version)
    version="${2}"
    shift 2
    ;;
  --verbose)
    verbose=1
    shift
    ;;
  *)
    _log_msg "Ignoring unknown argument: ${1}" >&2
    shift
    ;;
  esac
done

if [ -z "${location_path}" ]; then
  _error_msg "--location argument is required."
  return 1
fi
if [ -z "${version}" ]; then
  _error_msg "--version argument is required."
  return 1
fi

_log_msg "Running obsidian-cli switch script for version ${version} at location: ${location_path}"

# The binary might be 'obsidian-cli' or 'notesmd-cli' at the root of the location
executable_abs_path=$(find "${location_path}" -maxdepth 1 -type f -executable ! -name "*.sh" | head -n 1)
_log_msg "Found executable path: ${executable_abs_path}"

if [ -z "${executable_abs_path}" ] || [ ! -f "${executable_abs_path}" ]; then
  _error_msg "Executable not found in: ${location_path}"
  return 1
fi

printf '%s\n' "${executable_abs_path}"

_log_msg "obsidian-cli switch script finished successfully."
