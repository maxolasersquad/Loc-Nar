#!/bin/sh

source_install=0
version=""
location_path=""
verbose=0
github_api_url="https://api.github.com/repos/AsamK/signal-cli/releases"

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
if ! command -v java >/dev/null 2>&1; then
  _error_msg "'java' (JRE) command not found. Signal-cli requires Java to run."
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

tmp_dir=$(mktemp -d /tmp/trk-signal-cli-install-XXXXXX) || {
  _error_msg "Failed to create temporary directory."
  return 1
}
trap 'rm -rf "$tmp_dir"' EXIT
_log_msg "Created temporary directory: ${tmp_dir}" >&2

get_release_url() {
  _log_msg "Fetching release info for version: ${version}" >&2
  
  # Prefer the standard distribution (requires Java) as it is most stable
  # It is usually named signal-cli-x.y.z.tar.gz
  query='.assets[] | select(.name | endswith(".tar.gz")) | select(.name | contains("native") | not) | .browser_download_url'
  
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
    # Fallback logic: check if the asset is named differently
    query_fallback='.assets[] | select(.name | endswith(".tar.gz")) | .browser_download_url'
    download_url=$(printf '%s' "${release_json}" | jq -r "${query_fallback}" | head -n 1)
  fi

  if [ -z "${download_url}" ] || [ "${download_url}" = "null" ]; then
    _error_msg "Could not find a suitable download URL for signal-cli version ${version}."
    return 2
  fi

  printf '%s\n' "${download_url}"
}

download_and_install() {
  download_url="${1}"
  download_file="${tmp_dir}/$(basename "${download_url}")"

  _log_msg "Downloading signal-cli from ${download_url}" >&2
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
  
  # Find the directory it extracted to (usually signal-cli-x.y.z)
  extracted_dir=$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -type d | head -n 1)
  
  if [ -z "${extracted_dir}" ]; then
    _error_msg "Extraction failed or empty archive."
    return 4
  fi

  _log_msg "Installing to ${location_path}..." >&2
  
  # signal-cli distribution contains bin/ and lib/ folders
  # We copy everything to the location_path
  cp -R "${extracted_dir}/"* "${location_path}/"
  
  # Ensure the binary is executable
  chmod +x "${location_path}/bin/signal-cli"

  _log_msg "Installation successful." >&2
  printf 'bin/signal-cli\n'
}

url=$(get_release_url) || return $?
download_and_install "${url}"
