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

_log_msg "Running classicuo-razor switch script for version ${version} at location: ${location_path}"

executable_abs_path="${location_path}/classicuo-razor"

if [ ! -f "${executable_abs_path}" ]; then
  _error_msg "Executable not found at expected path: ${executable_abs_path}"
  return 1
fi

# Update link in installed ClassicUO versions
if command -v python3 >/dev/null 2>&1; then
  python3 -c '
import os, sys

razor_dir = sys.argv[1]
trk_apps = os.environ.get("TRK_LOCAL_APPS_DIR") or os.path.expanduser("~/.local/share/trk/apps")
cuo_apps_dir = os.path.join(trk_apps, "classicuo")
if os.path.isdir(cuo_apps_dir):
    for entry in os.listdir(cuo_apps_dir):
        p = os.path.join(cuo_apps_dir, entry)
        if os.path.isdir(p):
            plug_dir = os.path.join(p, "Data", "Plugins", "Assistant")
            try:
                os.makedirs(os.path.dirname(plug_dir), exist_ok=True)
                if os.path.islink(plug_dir) or os.path.isfile(plug_dir):
                    os.unlink(plug_dir)
                if not os.path.exists(plug_dir):
                    os.symlink(razor_dir, plug_dir)
            except Exception:
                pass
' "${location_path}" 2>/dev/null || true
fi

_log_msg "Expected executable path: ${executable_abs_path}"

printf '%s\n' "${executable_abs_path}"

_log_msg "classicuo-razor switch script finished successfully."
