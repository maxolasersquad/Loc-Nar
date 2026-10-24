#!/bin/sh

version=""
location_path=""
verbose=0

_log_msg() {
  if [ "${verbose}" -eq 1 ]; then
    printf 'INSTALLER VERBOSE: %s\n' "$*" >&2
  fi
}
_error_msg() { printf 'INSTALLER ERROR: %s\n' "$*" >&2; }

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

_log_msg "Checking dependencies…" >&2
if ! command -v python3 >/dev/null 2>&1; then
  _error_msg "'python3' command not found. Python 3.7+ is required to download client files."
  return 6
fi

if ! python3 -c "import sys; sys.exit(0 if sys.version_info >= (3, 7) else 1)" >/dev/null 2>&1; then
  _error_msg "Python version 3.7 or newer is required."
  return 6
fi

if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  _error_msg "Neither curl nor wget found."
  return 6
fi
_log_msg "Dependencies seem ok." >&2

_log_msg "Ensuring installation directory exists: ${location_path}" >&2
if ! mkdir -p "${location_path}"; then
  _error_msg "Failed to create installation directory: ${location_path}"
  return 7
fi
if [ ! -w "${location_path}" ]; then
  _error_msg "Installation directory is not writable: ${location_path}"
  return 7
fi

tmp_dir=$(mktemp -d /tmp/trk-classicuo-data-install-XXXXXX) || {
  _error_msg "Failed to create temporary directory."
  return 1
}
trap 'rm -rf "${tmp_dir}"' EXIT INT TERM
_log_msg "Created temporary directory: ${tmp_dir}" >&2

# Intelligent upgrade seeding:
# If upgrading from a previous version, hardlink existing data files so that
# the patcher only downloads changed delta files rather than re-downloading ~1.6 GB.
parent_dir="$(dirname "${location_path}")"
if [ -d "${parent_dir}" ]; then
  previous_dir=$(find "${parent_dir}" -mindepth 1 -maxdepth 1 -type d ! -path "${location_path}" 2>/dev/null | sort -V | tail -n 1)
  if [ -n "${previous_dir}" ] && [ -d "${previous_dir}" ]; then
    _log_msg "Seeding existing game files from previous version: ${previous_dir}..." >&2
    cp -al "${previous_dir}/." "${location_path}/" 2>/dev/null || true
  fi
fi

# Fetch uo_patcher.py
patcher_url="https://raw.githubusercontent.com/andrezaiats/uo-patcher/master/uo_patcher.py"
patcher_script="${tmp_dir}/uo_patcher.py"

_log_msg "Fetching EA client patcher tool..." >&2
if command -v curl >/dev/null 2>&1; then
  if ! curl --fail -sL -o "${patcher_script}" "${patcher_url}"; then
    _error_msg "Failed to download patcher tool from ${patcher_url}"
    return 3
  fi
elif command -v wget >/dev/null 2>&1; then
  if ! wget --quiet -O "${patcher_script}" "${patcher_url}"; then
    _error_msg "Failed to download patcher tool from ${patcher_url}"
    return 3
  fi
fi

_log_msg "Downloading/updating Ultima Online Classic Client files to ${location_path}..." >&2
if ! python3 "${patcher_script}" --output "${location_path}" --workers 8 >&2; then
  _error_msg "Failed to download or verify Ultima Online client files."
  return 3
fi

# Create launcher wrapper in installation directory
cat <<'EOF' > "${location_path}/classicuo-data"
#!/bin/sh
_CUO_DATA_DIR="$(cd -P "$(dirname "$0")" && pwd -P)"
if command -v classicuo >/dev/null 2>&1; then
  exec classicuo -uopath "${_CUO_DATA_DIR}" "$@"
else
  printf 'classicuo is not found in PATH. Please run: trk install classicuo\n' >&2
  exit 1
fi
EOF
chmod +x "${location_path}/classicuo-data" 2>/dev/null || true

# Non-destructively update ClassicUO configuration:
# Preserves all existing user settings (IP, port, username, password, sound, fps, etc.)
# and only updates `ultimaonlinedirectory` and missing `clientversion`.
python3 -c '
import json, os, sys

uo_dir = sys.argv[1]
client_ver = sys.argv[2]

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
    os.makedirs(cdir, exist_ok=True)
    cfg_file = os.path.join(cdir, "settings.json")
    data = {}
    if os.path.isfile(cfg_file):
        try:
            with open(cfg_file, "r", encoding="utf-8") as f:
                data = json.load(f)
        except Exception:
            data = {}

    data["ultimaonlinedirectory"] = uo_dir

    if not data.get("clientversion"):
        data["clientversion"] = client_ver

    if not data.get("ip"):
        data["ip"] = "login.uoalive.com"

    if not data.get("port"):
        data["port"] = 2593

    # Detect system language and map to supported Ultima Online language codes
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

    try:
        with open(cfg_file, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except Exception as err:
        sys.stderr.write(f"Warning: could not write {cfg_file}: {err}\n")
' "${location_path}" "${version}"

_log_msg "Ultima Online Classic Client files installed successfully." >&2
printf '%s\n' "classicuo-data"
