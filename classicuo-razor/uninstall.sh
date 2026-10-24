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

_log_msg "Running classicuo-razor uninstall script for location: ${location_path}"

# Remove plugin link from ClassicUO installations if pointing to this location
if command -v python3 >/dev/null 2>&1; then
  python3 -c '
import os, sys

razor_dir = sys.argv[1]
trk_apps = os.environ.get("TRK_LOCAL_APPS_DIR") or os.path.expanduser("~/.local/share/trk/apps")
cuo_apps_dir = os.path.join(trk_apps, "classicuo")
if os.path.isdir(cuo_apps_dir):
    for entry in os.listdir(cuo_apps_dir):
        p = os.path.join(cuo_apps_dir, entry)
        plug_dir = os.path.join(p, "Data", "Plugins", "Assistant")
        if os.path.islink(plug_dir):
            try:
                if os.path.realpath(plug_dir) == os.path.realpath(razor_dir):
                    os.unlink(plug_dir)
            except Exception:
                pass
' "${location_path}" 2>/dev/null || true
fi

_log_msg "classicuo-razor uninstall script finished."
