#!/bin/sh

source_install=0
version=""
location_path=""
verbose=0
# obsidian-cli was renamed to notesmd-cli
github_api_url="https://api.github.com/repos/yakitrak/notesmd-cli/releases"

_log_msg() {
  if [ "${verbose}" -eq 1 ]; then
    printf 'INSTALLER VERBOSE: %s\n' "$*" >&2
  fi
}
_error_msg() { printf 'INSTALLER ERROR: %s\n' "$*" >&2; }

while [ $# -gt 0 ]; do
  case "${1}" in
  --source)
    source_install=1
    shift
    ;;
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

# --- Hardware & OS Detection ---
raw_os=$(uname -s)
os=$(printf '%s' "${raw_os}" | tr '[:upper:]' '[:lower:]')
case "${raw_os}" in
  Darwin*) os="darwin" ;;
  Linux*) os="linux" ;;
  MINGW*|MSYS*|CYGWIN*) os="windows" ;;
esac

arch=$(uname -m)
case "${arch}" in
  aarch64|arm64) arch="arm64" ;;
  x86_64|amd64) arch="amd64" ;;
esac

# Rosetta 2 detection on Darwin
if [ "${os}" = "darwin" ] && [ "${arch}" = "amd64" ]; then
  if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = "1" ]; then
    arch="arm64"
  fi
fi

_log_msg "Checking dependencies…" >&2
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  _error_msg "Neither curl nor wget found. Cannot download releases."
  return 6
fi
if ! command -v jq >/dev/null 2>&1; then
  _error_msg "'jq' command not found. Cannot parse release information."
  return 6
fi
if ! command -v tar >/dev/null 2>&1; then
  _error_msg "'tar' command not found. Cannot extract archives."
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

tmp_dir=$(mktemp -d /tmp/trk-obsidian-cli-install-XXXXXX) || {
  _error_msg "Failed to create temporary directory."
  return 1
}
trap 'rm -rf "$tmp_dir"' EXIT
_log_msg "Created temporary directory: ${tmp_dir}" >&2

get_release_url() {
  _log_msg "Fetching release info for version: ${version}" >&2

  if [ "${source_install}" -eq 1 ]; then
    _error_msg "This package does not support source installation."
    return 6
  fi

  # Supported binary OS/arch combinations
  is_supported=0
  case "${os}" in
    darwin)
      case "${arch}" in
        amd64|arm64) is_supported=1 ;;
      esac
      ;;
    linux|windows)
      case "${arch}" in
        amd64|arm64) is_supported=1 ;;
      esac
      ;;
  esac

  if [ "${is_supported}" -eq 0 ]; then
    _error_msg "Unsupported OS/architecture combo: ${os}/${arch}"
    _error_msg "This package does not support source installation."
    return 6
  fi
  
  if [ "${os}" = "darwin" ]; then
    query='.assets[] | select(.name | contains("darwin") and contains("all") and endswith(".tar.gz")) | .browser_download_url'
  else
    query=".assets[] | select(.name | contains(\"${os}\") and contains(\"${arch}\") and endswith(\".tar.gz\")) | .browser_download_url"
  fi
  
  release_info_url="${github_api_url}/tags/${version}"
  release_json=""
  download_url=""

  if command -v curl >/dev/null 2>&1; then
    release_json=$(curl --fail -sL "${release_info_url}")
  elif command -v wget >/dev/null 2>&1; then
    release_json=$(wget -qO- "${release_info_url}")
  fi

  if [ -n "${release_json}" ]; then
    download_url=$(printf '%s' "${release_json}" | jq -r "${query}" | head -n 1)
  fi

  if [ -z "${download_url}" ] || [ "${download_url}" = "null" ]; then
    _error_msg "Could not find a suitable download URL for obsidian-cli version ${version} (os=${os}, arch=${arch})."
    return 2
  fi

  printf '%s\n' "${download_url}"
}

download_and_install() {
  download_url="${1}"
  download_file="${tmp_dir}/$(basename "${download_url}")"

  _log_msg "Downloading obsidian-cli from ${download_url}" >&2
  if command -v curl >/dev/null 2>&1; then
    curl --fail -sL -o "${download_file}" "${download_url}"
    download_status=$?
  elif command -v wget >/dev/null 2>&1; then
    wget --quiet -O "${download_file}" "${download_url}"
    download_status=$?
  else
    _error_msg "Download tool missing."
    return 6
  fi

  if [ "${download_status}" -ne 0 ]; then
    _error_msg "Download failed from ${download_url} (Exit code: ${download_status})."
    return 3
  fi

  _log_msg "Extracting archive..." >&2
  tar -xzf "${download_file}" -C "${tmp_dir}"
  extract_status=$?

  if [ "${extract_status}" -ne 0 ]; then
    _error_msg "Extraction failed for ${download_file} (Exit code: ${extract_status})."
    return 4
  fi
  
  # Find the executable. It might be named 'obsidian-cli', 'notesmd-cli', or have a .exe suffix on Windows
  extracted_bin=$(find "${tmp_dir}" -maxdepth 2 -type f \( -name "obsidian-cli*" -o -name "notesmd-cli*" \) ! -name "checksums.txt" ! -name "*.sh" | head -n 1)
  
  if [ -z "${extracted_bin}" ]; then
    _error_msg "Could not find an executable within extracted directory."
    return 4
  fi
  
  bin_name=$(basename "${extracted_bin}")
  _log_msg "Found binary: ${bin_name}"

  _log_msg "Installing to ${location_path}..." >&2
  
  install -m 755 "${extracted_bin}" "${location_path}/${bin_name}"
  install_status=$?

  if [ "${install_status}" -ne 0 ]; then
    _error_msg "Failed to install binary to ${location_path}/ (Exit code: ${install_status})."
    return 1
  fi

  _log_msg "Installation successful." >&2
  printf '%s\n' "${bin_name}"
}

url=$(get_release_url) || return $?
download_and_install "${url}"
