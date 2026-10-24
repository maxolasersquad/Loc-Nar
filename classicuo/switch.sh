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
    _log_msg "Ignoring unknown argument: ${1}"
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

_log_msg "Running classicuo switch script for version ${version} at location: ${location_path}"

raw_os=$(uname -s)
case "${raw_os}" in
  MINGW*|MSYS*|CYGWIN*) is_windows=1 ;;
  *) is_windows=0 ;;
esac

if [ "${is_windows}" -eq 1 ] && [ -f "${location_path}/ClassicUO.exe" ]; then
  executable_abs_path="${location_path}/ClassicUO.exe"
elif [ -f "${location_path}/ClassicUO" ]; then
  executable_abs_path="${location_path}/ClassicUO"
elif [ -f "${location_path}/ClassicUO.exe" ]; then
  executable_abs_path="${location_path}/ClassicUO.exe"
elif [ -f "${location_path}/ClassicUO.bin.x86_64" ]; then
  executable_abs_path="${location_path}/ClassicUO.bin.x86_64"
else
  _error_msg "Executable not found at expected path in ${location_path}"
  return 1
fi

_log_msg "Expected executable path: ${executable_abs_path}"

printf '%s\n' "${executable_abs_path}"

_log_msg "classicuo switch script finished successfully."
