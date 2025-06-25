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
  --version)
    if [ -n "${2}" ]; then
      version="${2}"
      shift
      shift
    else
      _error_msg "--version option requires a version string."
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
  _error_msg "--location argument is required."
  exit 1
fi
if [ -z "${version}" ]; then
  _error_msg "--version argument is required."
  exit 1
fi

_log_msg "Running lazygit switch script for version ${version} at location: ${location_path}"

executable_abs_path="${location_path}/lazygit"
_log_msg "Expected executable path: ${executable_abs_path}"

if [ ! -f "${executable_abs_path}" ]; then
  _error_msg "Executable not found at expected path: ${executable_abs_path}"
  exit 1
fi

printf '%s\n' "${executable_abs_path}"

_log_msg "lazygit switch script finished successfully."
exit 0
