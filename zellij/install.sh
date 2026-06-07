#!/bin/sh

source_install=0
version=""
location_path=""
verbose=0
github_api_url="https://api.github.com/repos/zellij-org/zellij/releases"

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

# Map to Zellij asset naming targets
target_str=""
if [ "${os}" = "darwin" ]; then
  if [ "${arch}" = "arm64" ]; then
    target_str="aarch64-apple-darwin"
  elif [ "${arch}" = "amd64" ]; then
    target_str="x86_64-apple-darwin"
  fi
elif [ "${os}" = "linux" ]; then
  if [ "${arch}" = "arm64" ]; then
    target_str="aarch64-unknown-linux-musl"
  elif [ "${arch}" = "amd64" ]; then
    target_str="x86_64-unknown-linux-musl"
  fi
elif [ "${os}" = "windows" ]; then
  if [ "${arch}" = "amd64" ]; then
    target_str="x86_64-pc-windows-msvc"
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
if [ "${source_install}" -eq 1 ]; then
  if ! command -v cargo >/dev/null 2>&1; then
    _error_msg "'cargo' command not found. Required for source install."
    return 6
  fi
else
  if ! command -v tar >/dev/null 2>&1 && ! command -v unzip >/dev/null 2>&1; then
    _error_msg "Archive extraction tool (tar or unzip) not found."
    return 6
  fi
fi
if ! command -v install >/dev/null 2>&1; then
  _error_msg "'install' command not found."
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

tmp_dir=$(mktemp -d /tmp/trk-zellij-install-XXXXXX) || {
  _error_msg "Failed to create temporary directory."
  return 1
}
trap 'rm -rf "${tmp_dir}"' EXIT
_log_msg "Created temporary directory: ${tmp_dir}" >&2

get_specific_release_url() {
  query=""
  _log_msg "Fetching release info for version: ${version}" >&2

  if [ "${source_install}" -eq 1 ]; then
    query='.tarball_url'
  else
    if [ -z "${target_str}" ]; then
      _error_msg "Unsupported OS/architecture combo: ${os}/${arch}"
      _error_msg "You can build from source using the --source option if you have the required build tools (cargo)."
      return 6
    fi
    ext=".tar.gz"
    if [ "${os}" = "windows" ]; then
      ext=".zip"
    fi
    query=".assets[] | select(.name | contains(\"${target_str}\") and (contains(\"no-web\") | not) and endswith(\"${ext}\")) | .browser_download_url"
  fi

  release_info_url="${github_api_url}/tags/${version}"
  release_json=""
  download_url=""

  if command -v curl >/dev/null 2>&1; then
    release_json=$(curl --fail -sL "${release_info_url}")
    curl_status=$?
    if [ "${curl_status}" -ne 0 ]; then
      _log_msg "curl failed to get release info (Status: ${curl_status}) from ${release_info_url}" >&2
      release_json=""
    fi
  elif command -v wget >/dev/null 2>&1; then
    release_json=$(wget -qO- "${release_info_url}")
  fi

  if [ -n "${release_json}" ]; then
    download_url=$(printf '%s' "${release_json}" | jq -r "${query}" | head -n 1)
    jq_status=$?
    if [ "${jq_status}" -ne 0 ]; then
      _log_msg "jq failed to parse release JSON (Status: ${jq_status})" >&2
      download_url=""
    fi
  else
    _log_msg "Failed to fetch release JSON from ${release_info_url}" >&2
  fi

  if [ -z "${download_url}" ] || [ "${download_url}" = "null" ]; then
    _error_msg "Could not find a suitable download URL for zellij version ${version} (source=${source_install})."
    _error_msg "Check if version exists and has the expected asset/tarball at GitHub."
    return 2
  fi

  printf '%s\n' "${download_url}"
}

download_and_install() {
  download_url="${1}"
  download_file=""
  install_cmd_status=1

  download_file="${tmp_dir}/$(basename "${download_url}")"

  _log_msg "Downloading zellij from ${download_url}" >&2
  if command -v curl >/dev/null 2>&1; then
    curl --fail -sL -o "${download_file}" "${download_url}"
    download_status=$?
  elif command -v wget >/dev/null 2>&1; then
    wget --quiet -O "${download_file}" "${download_url}"
    download_status=$?
  else
    _error_msg "Neither curl nor wget available for download."
    return 6
  fi

  if [ "${download_status}" -ne 0 ]; then
    _error_msg "Download failed from ${download_url} (Exit code: ${download_status})."
    return 3
  fi
  _log_msg "Download successful: ${download_file}" >&2

  _log_msg "Extracting archive ${download_file} to ${tmp_dir}" >&2
  if [ "${os}" = "windows" ]; then
    unzip -q "${download_file}" -d "${tmp_dir}"
    extract_status=$?
  else
    tar -xzf "${download_file}" -C "${tmp_dir}"
    extract_status=$?
  fi

  if [ "${extract_status}" -ne 0 ]; then
    _error_msg "Extraction failed for ${download_file} (Exit code: ${extract_status})."
    return 4
  fi
  _log_msg "Extraction successful." >&2

  if [ "${source_install}" -eq 1 ]; then
    _log_msg "Building zellij from source…" >&2
    ZELLIJ_BUILD_DIR=$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -type d -name "*zellij-*" 2>/dev/null | head -n 1)

    if [ -z "${ZELLIJ_BUILD_DIR}" ] || [ ! -d "${ZELLIJ_BUILD_DIR}" ]; then
      _error_msg "Could not find extracted source directory in ${tmp_dir}"
      return 4
    fi
    _log_msg "Found source directory: ${ZELLIJ_BUILD_DIR}" >&2

    _log_msg "Running cargo build…" >&2
    build_ok=0
    if [ "${verbose}" -eq 1 ]; then
      (cd "${ZELLIJ_BUILD_DIR}" && cargo build --release --locked) && build_ok=1
    else
      (cd "${ZELLIJ_BUILD_DIR}" && cargo build --release --locked) >/dev/null 2>&1 && build_ok=1
    fi

    if [ "${build_ok}" -eq 1 ]; then
      _log_msg "Build successful. Installing…" >&2
      install -m 755 "${ZELLIJ_BUILD_DIR}/target/release/zellij" "${location_path}/"
      install_cmd_status=$?
    else
      _error_msg "cargo build failed."
      return 5
    fi
  else
    _log_msg "Installing pre-compiled binary…" >&2
    zellij_binary=$(find "${tmp_dir}" \( -name zellij -o -name zellij.exe \) -type f 2>/dev/null | head -n 1)
    if [ -z "${zellij_binary}" ]; then
      _error_msg "Could not find 'zellij' executable in extracted archive."
      return 4
    fi
    _log_msg "Found binary: ${zellij_binary}" >&2

    install -m 755 "${zellij_binary}" "${location_path}/"
    install_cmd_status=$?
  fi

  if [ "${install_cmd_status}" -ne 0 ]; then
    _error_msg "Failed to install binary to ${location_path}/ (Exit code: ${install_cmd_status})."
    return 1
  fi

  _log_msg "Binary installed successfully to ${location_path}/" >&2
  
  if [ -f "${location_path}/zellij.exe" ]; then
    printf '%s\n' "zellij.exe"
  else
    printf '%s\n' "zellij"
  fi
}

url=$(get_specific_release_url) || return "${?}"
download_and_install "${url}"
