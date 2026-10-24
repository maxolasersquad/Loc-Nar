#!/bin/sh

version=""
location_path=""
verbose=0
github_api_url="https://api.github.com/repos/markdwags/Razor/releases"

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

case "${version}" in
  v*) version_tag="${version}" ;;
  *) version_tag="v${version}" ;;
esac

_log_msg "Checking dependencies…" >&2
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  _error_msg "Neither curl nor wget found."
  return 6
fi
if ! command -v jq >/dev/null 2>&1; then
  _error_msg "'jq' command not found."
  return 6
fi
if ! command -v unzip >/dev/null 2>&1; then
  _error_msg "'unzip' command not found."
  return 6
fi

raw_os=$(uname -s)
if [ "${raw_os}" = "Linux" ]; then
  if ! ldconfig -p 2>/dev/null | grep -q "libgdiplus.so.0" && ! [ -f /usr/lib/libgdiplus.so.0 ] && ! [ -f /usr/lib64/libgdiplus.so.0 ] && ! [ -f /usr/lib/x86_64-linux-gnu/libgdiplus.so.0 ]; then
    printf 'NOTE: Razor uses Windows Forms and requires libgdiplus on Linux.\n' >&2
    printf 'If Razor fails to open, install it with: sudo apt install libgdiplus (or sudo dnf install libgdiplus)\n' >&2
  fi
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

tmp_dir=$(mktemp -d /tmp/trk-classicuo-razor-install-XXXXXX) || {
  _error_msg "Failed to create temporary directory."
  return 1
}
trap 'rm -rf "${tmp_dir}"' EXIT INT TERM
_log_msg "Created temporary directory: ${tmp_dir}" >&2

# Resolve download URL from GitHub release
release_info_url="${github_api_url}/tags/${version_tag}"
download_url=""

if command -v curl >/dev/null 2>&1; then
  release_json=$(curl --fail -sL "${release_info_url}" 2>/dev/null) || true
elif command -v wget >/dev/null 2>&1; then
  release_json=$(wget -qO- "${release_info_url}" 2>/dev/null) || true
fi

if [ -n "${release_json}" ]; then
  download_url=$(printf '%s' "${release_json}" | jq -r '.assets[] | select(.name | contains("x64") and endswith(".zip")) | .browser_download_url' 2>/dev/null | head -n 1)
fi

if [ -z "${download_url}" ] || [ "${download_url}" = "null" ]; then
  clean_v="${version_tag#v}"
  download_url="https://github.com/markdwags/Razor/releases/download/${version_tag}/Razor-x64-${clean_v}.zip"
fi

archive_file="${tmp_dir}/razor.zip"
_log_msg "Downloading Razor from: ${download_url}" >&2
if command -v curl >/dev/null 2>&1; then
  if ! curl --fail -sL -o "${archive_file}" "${download_url}"; then
    _error_msg "Download failed from ${download_url}."
    return 3
  fi
elif command -v wget >/dev/null 2>&1; then
  if ! wget --quiet -O "${archive_file}" "${download_url}"; then
    _error_msg "Download failed from ${download_url}."
    return 3
  fi
fi

_log_msg "Extracting Razor archive..." >&2
if ! unzip -q -o "${archive_file}" -d "${location_path}"; then
  _error_msg "Extraction failed for ${archive_file}."
  return 4
fi

# Ensure Razor.dll exists alongside Razor.exe
if [ -f "${location_path}/Razor.exe" ] && [ ! -f "${location_path}/Razor.dll" ]; then
  cp -f "${location_path}/Razor.exe" "${location_path}/Razor.dll"
fi

# Create launcher wrapper
cat <<'EOF' > "${location_path}/classicuo-razor"
#!/bin/sh
_RAZOR_DIR="$(cd -P "$(dirname "$0")" && pwd -P)"
if command -v classicuo >/dev/null 2>&1; then
  exec classicuo -plugins "${_RAZOR_DIR}/Razor.dll" "$@"
else
  printf 'classicuo is not in PATH. Please run: trk install classicuo\n' >&2
  exit 1
fi
EOF
chmod +x "${location_path}/classicuo-razor" 2>/dev/null || true

# Link into installed ClassicUO versions and update settings non-destructively
if command -v python3 >/dev/null 2>&1; then
  python3 -c '
import json, os, sys

razor_dir = sys.argv[1]
razor_dll = os.path.join(razor_dir, "Razor.dll")

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
        if os.path.isdir(p):
            if p not in config_dirs:
                config_dirs.append(p)
            # Link Razor into Data/Plugins/Assistant
            plug_dir = os.path.join(p, "Data", "Plugins", "Assistant")
            try:
                os.makedirs(os.path.dirname(plug_dir), exist_ok=True)
                if os.path.islink(plug_dir) or os.path.isfile(plug_dir):
                    os.unlink(plug_dir)
                if not os.path.exists(plug_dir):
                    os.symlink(razor_dir, plug_dir)
            except Exception:
                pass

for cdir in config_dirs:
    cfg_file = os.path.join(cdir, "settings.json")
    if os.path.isfile(cfg_file):
        try:
            with open(cfg_file, "r", encoding="utf-8") as f:
                data = json.load(f)
            plugins = data.get("plugins") or []
            if razor_dll not in plugins and "./Assistant/Razor.dll" not in plugins:
                plugins.append(razor_dll)
            data["plugins"] = plugins
            with open(cfg_file, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
        except Exception:
            pass
' "${location_path}" 2>/dev/null || true
fi

_log_msg "Razor plugin installed successfully." >&2
printf '%s\n' "classicuo-razor"
