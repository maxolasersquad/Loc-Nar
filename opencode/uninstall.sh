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

_log_msg "Running opencode uninstall script for location: ${location_path}"

config_file="${HOME}/.opencode.json"
if [ -f "${config_file}" ]; then
  rm "${config_file}" && _log_msg "Removed config file: ${config_file}"
fi

xdg_config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}"
xdg_config_file="${xdg_config_dir}/.opencode.json"
if [ -f "${xdg_config_file}" ]; then
  rm "${xdg_config_file}" && _log_msg "Removed config file: ${xdg_config_file}"
fi

_log_msg "opencode uninstall script finished."
