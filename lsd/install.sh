#!/bin/sh

source_install=0
version=""
location_path=""
verbose=0
github_api_url="https://api.github.com/repos/lsd-rs/lsd/releases"

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
    location_path="${1#--location=}"
    if [ -z "${location_path}" ]; then
      _error_msg "--location option requires a value after '='."
      exit 1
    fi
    shift
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
    _log_msg "Ignoring unknown argument: ${1}" >&2
    shift
    ;;
  esac
done

if [ -z "${location_path}" ]; then
  _error_msg "--location argument is required (was not parsed correctly)."
  exit 1
fi
if [ -z "${version}" ]; then
  _error_msg "--version argument is required (should be passed by trk)."
  exit 1
fi

_log_msg "Checking dependencies…" >&2
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  _error_msg "Neither curl nor wget found. Cannot download releases."
  exit 6
fi
if ! command -v jq >/dev/null 2>&1; then
  _error_msg "'jq' command not found. Cannot parse release information."
  exit 6
fi
if ! command -v tar >/dev/null 2>&1; then
  _error_msg "'tar' command not found. Cannot extract archives."
  exit 6
fi
if ! command -v install >/dev/null 2>&1; then
  _error_msg "'install' command not found."
  exit 6
fi
if [ "${source_install}" -eq 1 ] && ! command -v cargo >/dev/null 2>&1; then
  _error_msg "'cargo' command not found. Cannot build from source."
  exit 6
fi
_log_msg "Dependencies seem ok." >&2

_log_msg "Ensuring installation directory exists: ${location_path}" >&2
if ! mkdir -p "${location_path}"; then
  _error_msg "Failed to create installation directory: ${location_path}"
  exit 7
fi
if [ ! -w "${location_path}" ]; then
  _error_msg "Installation directory is not writable: ${location_path}"
  exit 7
fi

tmp_dir=$(mktemp -d /tmp/trk-lsd-install-XXXXXX) || {
  _error_msg "Failed to create temporary directory."
  exit 1
}
trap 'rm -rf "$tmp_dir"' EXIT
_log_msg "Created temporary directory: ${tmp_dir}" >&2

get_specific_release_url() {
  # Removed non-POSIX 'local' keyword
  query=""
  _log_msg "Fetching release info for version: ${version}" >&2

  if [ "${source_install}" -eq 1 ]; then
    query='.tarball_url'
  else
    # NOTE: This jq query is specific to lsd's naming convention!
    query='.assets[] | select(.name | contains("linux-gnu.tar.gz") and contains("x86_64")) | .browser_download_url'
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

  if [ -n "${release_json}" ]; then                                  # SC2250 Fix
    download_url=$(printf '%s' "${release_json}" | jq -r "${query}") # SC2250 Fix
    jq_status=$?
    if [ "${jq_status}" -ne 0 ]; then
      _log_msg "jq failed to parse release JSON (Status: ${jq_status})" >&2
      download_url=""
    fi
  else
    _log_msg "Failed to fetch release JSON from ${release_info_url}" >&2
  fi

  if [ -z "${download_url}" ] || [ "${download_url}" = "null" ]; then
    _error_msg "Could not find a suitable download URL for lsd version ${version} (source=${source_install})."
    _error_msg "Check if version exists and has the expected asset/tarball at GitHub."
    exit 2
  fi

  printf '%s\n' "${download_url}"
}

download_and_install() {
  download_url="${1}"
  download_file=""
  extracted_dir_basename=""
  install_cmd_status=1

  download_file="${tmp_dir}/$(basename "${download_url}")"
  extracted_dir_basename=$(basename "${download_file}" | sed -e 's/\.tar\.gz$//' -e 's/\.tgz$//')

  _log_msg "Downloading lsd from ${download_url}" >&2
  if command -v curl >/dev/null 2>&1; then
    curl --fail -sL -o "${download_file}" "${download_url}"
    download_status=$?
  elif command -v wget >/dev/null 2>&1; then
    wget --quiet -O "${download_file}" "${download_url}"
    download_status=$?
  else
    _error_msg "Neither curl nor wget available for download."
    exit 6
  fi

  if [ "${download_status}" -ne 0 ]; then
    _error_msg "Download failed from ${download_url} (Exit code: ${download_status})."
    exit 3
  fi
  _log_msg "Download successful: ${download_file}" >&2

  _log_msg "Extracting archive ${download_file} to ${tmp_dir}" >&2
  tar -xzf "${download_file}" -C "${tmp_dir}"
  extract_status=$?

  if [ "${extract_status}" -ne 0 ]; then
    _error_msg "Extraction failed for ${download_file} (Exit code: ${extract_status})."
    exit 4
  fi
  _log_msg "Extraction successful." >&2

  if [ "${source_install}" -eq 1 ]; then
    _log_msg "Building lsd from source…" >&2
    LSD_BUILD_DIR=$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -type d -name "lsd-rs-lsd-*" 2>/dev/null)

    if [ -z "${LSD_BUILD_DIR}" ] || [ ! -d "${LSD_BUILD_DIR}" ]; then
      _error_msg "Could not find extracted source directory in ${tmp_dir}"
      exit 4
    fi
    _log_msg "Found source directory: ${LSD_BUILD_DIR}" >&2

    _log_msg "Running cargo build…" >&2
    build_ok=0
    if [ "${verbose}" -eq 1 ]; then
      (cd "${LSD_BUILD_DIR}" && cargo build --release) && build_ok=1
    else
      (cd "${LSD_BUILD_DIR}" && cargo build --release) >/dev/null 2>&1 && build_ok=1
    fi

    if [ "${build_ok}" -eq 1 ]; then
      _log_msg "Build successful. Installing…" >&2
      install -m 755 "${LSD_BUILD_DIR}/target/release/lsd" "${location_path}/"
      install_cmd_status=$?
    else
      _error_msg "cargo build failed."
      exit 5
    fi

  else
    _log_msg "Installing pre-compiled lsd binary…" >&2
    lsd_binary=$(find "${tmp_dir}/${extracted_dir_basename}" -name lsd -type f -executable 2>/dev/null | head -n 1)

    if [ -z "${lsd_binary}" ]; then
      _error_msg "Could not find 'lsd' executable within extracted directory: ${tmp_dir}/${extracted_dir_basename}"
      exit 4
    fi
    _log_msg "Found binary: ${lsd_binary}" >&2

    install -m 755 "${lsd_binary}" "${location_path}/"
    install_cmd_status=$?
  fi

  if [ "${install_cmd_status}" -ne 0 ]; then
    _error_msg "Failed to install binary to ${location_path}/ (Exit code: ${install_cmd_status})."
    exit 1
  fi

  _log_msg "Binary installed successfully to ${location_path}/" >&2

  printf '%s\n' "lsd"

}

release_url=$(get_specific_release_url)

download_and_install "${release_url}"

exit 0
