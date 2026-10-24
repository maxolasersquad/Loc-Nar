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

_log_msg "Running classicuo-data switch script for version ${version} at location: ${location_path}"

executable_abs_path="${location_path}/classicuo-data"

if [ ! -f "${executable_abs_path}" ]; then
  _error_msg "Executable not found at expected path: ${executable_abs_path}"
  return 1
fi

# Update settings non-destructively to point to the active switched version
if command -v python3 >/dev/null 2>&1; then
  python3 -c '
import json, os, sys

uo_dir = sys.argv[1]
config_dirs = []
xdg_config = os.environ.get("XDG_CONFIG_HOME")
if xdg_config:
    config_dirs.append(os.path.join(xdg_config, "classicuo"))
config_dirs.append(os.path.expanduser("~/.config/classicuo"))

trk_apps = os.environ.get("TRK_LOCAL_APPS_DIR") or os.path.expanduser("~/.local/share/trk/apps")
cuo_apps_dir = os.path.join(trk_apps, "classicuo")
if os.path.isdir(cuo_apps_dir):
    for entry in os.listdir(cuo_apps_dir):
        p = os.path.join(cuo_apps_dir, entry)
        if os.path.isdir(p) and p not in config_dirs:
            config_dirs.append(p)

for cdir in config_dirs:
    cfg_file = os.path.join(cdir, "settings.json")
    if os.path.isfile(cfg_file):
        try:
            with open(cfg_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            data["ultimaonlinedirectory"] = uo_dir
            if not data.get("ip"):
                data["ip"] = "login.uoalive.com"
            if not data.get("port"):
                data["port"] = 2593
            loc = os.environ.get("LC_ALL") or os.environ.get("LC_MESSAGES") or os.environ.get("LANG") or ""
            lang_code = loc.split(".")[0].split("_")[0].lower()
            country = loc.split(".")[0].split("_")[1].lower() if "_" in loc.split(".")[0] else ""
            mapping = {
                "en": "ENU",
                "de": "DEU",
                "es": "ESP",
                "fr": "FRA",
                "ja": "JPN",
                "ko": "KOR",
                "zh": "CHT" if country in ["tw", "hk", "mo"] else "CHS"
            }
            detected_lang = mapping.get(lang_code, "ENU")

            if not data.get("lang") or data.get("lang") == "IVL":
                data["lang"] = detected_lang
            with open(cfg_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
        except Exception:
            pass
' "${location_path}" 2>/dev/null || true
fi

_log_msg "Expected executable path: ${executable_abs_path}"

printf '%s\n' "${executable_abs_path}"

_log_msg "classicuo-data switch script finished successfully."
