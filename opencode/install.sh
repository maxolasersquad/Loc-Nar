#!/bin/sh

source_install=0
version=""
location_path=""
verbose=0
github_api_url="https://api.github.com/repos/anomalyco/opencode/releases"

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

# Detect if we should use Go or Bun based on the version number
# Versions <= v0.0.52 were Go-based.
# Versions >= v0.0.53 are Bun-based.
use_go=0
clean_version="${version#v}"
if [ "$(printf '%s\n%s' "0.0.52" "${clean_version}" | sort -V | tail -n1)" = "0.0.52" ]; then
  use_go=1
fi

# Detect if AVX2 is required (v1.1.52 and above)
if [ "$(printf '%s\n%s' "1.1.52" "${clean_version}" | sort -V | tail -n1)" = "${clean_version}" ]; then
  _log_msg "Checking for AVX2 support (required for v1.1.52+)…" >&2
  if ! grep -q avx2 /proc/cpuinfo; then
    _error_msg "Version ${version} and above requires a CPU with AVX2 support."
    _error_msg "v1.1.51 is the last version supported on your hardware."
    return 6
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

if [ "${use_go}" -eq 1 ]; then
  # Go-based dependencies
  if [ "${source_install}" -ne 1 ] && ! command -v tar >/dev/null 2>&1; then
    _error_msg "'tar' command not found. Cannot extract archives."
    return 6
  fi
  if [ "${source_install}" -eq 1 ] && ! command -v go >/dev/null 2>&1; then
    _error_msg "'go' command not found. Required for source install of version ${version}."
    return 6
  fi
else
  # Bun-based dependencies
  if [ "${source_install}" -ne 1 ] && ! command -v tar >/dev/null 2>&1 && ! command -v unzip >/dev/null 2>&1; then
    _error_msg "Archive extraction tool (tar or unzip) not found."
    return 6
  fi
  if [ "${source_install}" -eq 1 ] && ! command -v bun >/dev/null 2>&1; then
    _error_msg "'bun' command not found. Required for source install of version ${version}."
    return 6
  fi
  if [ "${source_install}" -eq 1 ]; then
    bun_version=$(bun --version | sed 's/bun //')
    if [ "$(printf '%s\n%s' "1.3.9" "${bun_version}" | sort -V | head -n1)" != "1.3.9" ]; then
      _error_msg "Source install requires bun >= 1.3.9, but found ${bun_version}."
      return 6
    fi
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

tmp_dir=$(mktemp -d /tmp/trk-opencode-install-XXXXXX) || {
  _error_msg "Failed to create temporary directory."
  return 1
}
trap 'rm -rf "$tmp_dir"' EXIT
_log_msg "Created temporary directory: ${tmp_dir}" >&2

get_specific_release_url() {
  query=""
  _log_msg "Fetching release info for version: ${version}" >&2

  if [ "${source_install}" -eq 1 ]; then
    query='.tarball_url'
  elif [ "${use_go}" -eq 1 ]; then
    # Go versions used tar.gz with "linux-x86_64" in the name
    query='.assets[] | select(.name | contains("linux-x86_64.tar.gz")) | .browser_download_url'
  else
    # Bun versions used zip/tar.gz with "linux-x64"
    clean_ver="${version#v}"
    use_tarball=0
    if [ "$(printf '%s\n%s' "1.0.91" "${clean_ver}" | sort -V | head -n1)" = "1.0.91" ]; then
      use_tarball=1
    fi

    if [ "${use_tarball}" -eq 1 ]; then
      query='.assets[] | select(.name | contains("linux-x64.tar.gz")) | .browser_download_url'
    else
      query='.assets[] | select(.name | contains("linux-x64.zip")) | .browser_download_url'
    fi
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
    download_url=$(printf '%s' "${release_json}" | jq -r "${query}")
    jq_status=$?
    if [ "${jq_status}" -ne 0 ]; then
      _log_msg "jq failed to parse release JSON (Status: ${jq_status})" >&2
      download_url=""
    fi
  else
    _log_msg "Failed to fetch release JSON from ${release_info_url}" >&2
  fi

  if [ -z "${download_url}" ] || [ "${download_url}" = "null" ]; then
    _error_msg "Could not find a suitable download URL for opencode version ${version} (source=${source_install}, go=${use_go})."
    _error_msg "Check if version exists and has the expected asset/tarball at GitHub."
    return 2
  fi

  printf '%s\n' "${download_url}"
}

download_and_install() {
  download_url="${1}"
  download_file=""
  install_cmd_status=1

  # Handle filename extension based on URL
  case "${download_url}" in
    *.zip) download_file="${tmp_dir}/$(basename "${download_url}")" ;;
    *.tar.gz) download_file="${tmp_dir}/$(basename "${download_url}")" ;;
    *) download_file="${tmp_dir}/$(basename "${download_url}").tar.gz" ;;
  esac

  _log_msg "Downloading opencode from ${download_url}" >&2
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
  case "${download_file}" in
    *.tar.gz|*.tgz)
      tar -xzf "${download_file}" -C "${tmp_dir}"
      extract_status=$?
      ;;
    *.zip)
      unzip -q "${download_file}" -d "${tmp_dir}"
      extract_status=$?
      ;;
    *)
      _error_msg "Unknown archive format: ${download_file}"
      extract_status=1
      ;;
  esac

  if [ "${extract_status}" -ne 0 ]; then
    _error_msg "Extraction failed for ${download_file} (Exit code: ${extract_status})."
    return 4
  fi
  _log_msg "Extraction successful." >&2

  if [ "${source_install}" -eq 1 ]; then
    _log_msg "Building opencode from source…" >&2
    
    if [ "${use_go}" -eq 1 ]; then
      # Go build logic
      OPENCODE_BUILD_DIR=$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -type d -name "*-opencode-*" 2>/dev/null)
      if [ -z "${OPENCODE_BUILD_DIR}" ] || [ ! -d "${OPENCODE_BUILD_DIR}" ]; then
        _error_msg "Could not find extracted source directory in ${tmp_dir}"
        return 4
      fi
      _log_msg "Found source directory: ${OPENCODE_BUILD_DIR}" >&2
      _log_msg "Running go build…" >&2
      build_ok=0
      ldflags="-s -w -X main.date=$(date -u +'%Y-%m-%dT%H:%M:%SZ') -X main.version=${version} -X main.buildSource=tarball"
      if [ "${verbose}" -eq 1 ]; then
        (cd "${OPENCODE_BUILD_DIR}" && go build -ldflags "${ldflags}" -o opencode) && build_ok=1
      else
        (cd "${OPENCODE_BUILD_DIR}" && go build -ldflags "${ldflags}" -o opencode) >/dev/null 2>&1 && build_ok=1
      fi

      if [ "${build_ok}" -eq 1 ]; then
        _log_msg "Build successful. Installing…" >&2
        install -m 755 "${OPENCODE_BUILD_DIR}/opencode" "${location_path}/"
        install_cmd_status=$?
      else
        _error_msg "go build failed."
        return 5
      fi
    else
      # Bun build logic
      OPENCODE_BUILD_DIR=$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -type d -name "anomalyco-opencode-*" 2>/dev/null)
      if [ -z "${OPENCODE_BUILD_DIR}" ] || [ ! -d "${OPENCODE_BUILD_DIR}" ]; then
        _error_msg "Could not find extracted source directory in ${tmp_dir}"
        return 4
      fi
      _log_msg "Found source directory: ${OPENCODE_BUILD_DIR}" >&2
      _log_msg "Installing dependencies with bun…" >&2
      (cd "${OPENCODE_BUILD_DIR}" && bun install) >/dev/null 2>&1
      _log_msg "Running bun build…" >&2
      build_ok=0
      if [ "${verbose}" -eq 1 ]; then
        (cd "${OPENCODE_BUILD_DIR}/packages/opencode" && OPENCODE_VERSION="${version}" bun run build) && build_ok=1
      else
        (cd "${OPENCODE_BUILD_DIR}/packages/opencode" && OPENCODE_VERSION="${version}" bun run build) >/dev/null 2>&1 && build_ok=1
      fi

      if [ "${build_ok}" -eq 1 ]; then
        _log_msg "Build successful. Installing…" >&2
        install -m 755 "${OPENCODE_BUILD_DIR}/packages/opencode/bin/opencode" "${location_path}/"
        install_cmd_status=$?
      else
        _error_msg "bun build failed."
        return 5
      fi
    fi

  else
    _log_msg "Installing pre-compiled opencode binary…" >&2
    opencode_binary=$(find "${tmp_dir}" -name opencode -type f -executable 2>/dev/null | head -n 1)

    if [ -z "${opencode_binary}" ]; then
      _error_msg "Could not find 'opencode' executable within extracted directory: ${tmp_dir}/"
      return 4
    fi
    _log_msg "Found binary: ${opencode_binary}" >&2

    install -m 755 "${opencode_binary}" "${location_path}/"
    install_cmd_status=$?
  fi

  if [ "${install_cmd_status}" -ne 0 ]; then
    _error_msg "Failed to install binary to ${location_path}/ (Exit code: ${install_cmd_status})."
    return 1
  fi

  _log_msg "Binary installed successfully to ${location_path}/" >&2

  printf '%s\n' "opencode"

}

release_url=$(get_specific_release_url) || return $?

download_and_install "${release_url}"
