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

# --- Hardware & OS Detection (Logic from official installer) ---
raw_os=$(uname -s)
os=$(printf '%s' "${raw_os}" | tr '[:upper:]' '[:lower:]')
case "${raw_os}" in
  Darwin*) os="darwin" ;;
  Linux*) os="linux" ;;
  MINGW*|MSYS*|CYGWIN*) os="windows" ;;
esac

arch=$(uname -m)
case "${arch}" in
  aarch64) arch="arm64" ;;
  x86_64) arch="x64" ;;
esac

# Rosetta 2 detection on Darwin
if [ "${os}" = "darwin" ] && [ "${arch}" = "x64" ]; then
  if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = "1" ]; then
    arch="arm64"
  fi
fi

# Musl detection on Linux
is_musl=0
if [ "${os}" = "linux" ]; then
  if [ -f /etc/alpine-release ] || (ldd --version 2>&1 | grep -qi musl); then
    is_musl=1
  fi
fi

# AVX2 support detection
has_avx2=1
if [ "${arch}" = "x64" ]; then
  if [ "${os}" = "linux" ] && ! grep -qwi avx2 /proc/cpuinfo 2>/dev/null; then
    has_avx2=0
  elif [ "${os}" = "darwin" ] && [ "$(sysctl -n hw.optional.avx2_0 2>/dev/null)" != "1" ]; then
    has_avx2=0
  fi
fi

# Identify the target string for assets (os-arch[-baseline][-musl])
target_triple="${os}-${arch}"
[ "${has_avx2}" -eq 0 ] && target_triple="${target_triple}-baseline"
[ "${is_musl}" -eq 1 ] && target_triple="${target_triple}-musl"

# ----------------------------------------------------------------

# Detect if we should use Go or Bun based on the version number
# Versions <= v0.0.52 were Go-based.
# Versions >= v0.0.53 are Bun-based (with asset jump to v0.1.30).
use_go=0
clean_version="${version#v}"
# Use POSIX-compliant field-based sort for comparison
if [ "$(printf '%s\n%s' "0.0.52" "${clean_version}" | sort -t. -k1,1n -k2,2n -k3,3n | tail -n1)" = "0.0.52" ]; then
  use_go=1
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
  if [ "${source_install}" -ne 1 ] && ! command -v tar >/dev/null 2>&1; then
    _error_msg "'tar' command not found. Cannot extract archives."
    return 6
  fi
  if [ "${source_install}" -eq 1 ] && ! command -v go >/dev/null 2>&1; then
    _error_msg "'go' command not found. Required for source install of version ${version}."
    return 6
  fi
else
  if [ "${source_install}" -ne 1 ] && ! command -v tar >/dev/null 2>&1 && ! command -v unzip >/dev/null 2>&1; then
    _error_msg "Archive extraction tool (tar or unzip) not found."
    return 6
  fi
  if [ "${source_install}" -eq 1 ] && ! command -v bun >/dev/null 2>&1; then
    _error_msg "'bun' command not found. Required for source install of version ${version}."
    return 6
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
    # Legacy Go-based naming
    query='.assets[] | select(.name | contains("linux-x86_64.tar.gz")) | .browser_download_url'
  else
    # Bun-based naming using target_triple logic from official installer
    archive_ext=".zip"
    [ "${os}" = "linux" ] && archive_ext=".tar.gz"
    
    query=".assets[] | select(.name | contains(\"${target_triple}${archive_ext}\")) | .browser_download_url"
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
    # Fallback for older Bun versions that might not use the triple naming yet
    if [ "${use_go}" -eq 0 ]; then
       _log_msg "Triple match failed, trying fallback search..." >&2
       fallback_query='.assets[] | select(.name | contains("linux-x64")) | .browser_download_url'
       download_url=$(printf '%s' "${release_json}" | jq -r "${fallback_query}" | head -n 1)
    fi
  fi

  if [ -z "${download_url}" ] || [ "${download_url}" = "null" ]; then
    _error_msg "Could not find a suitable download URL for opencode version ${version} (target=${target_triple})."
    return 2
  fi

  printf '%s\n' "${download_url}"
}

download_and_install() {
  download_url="${1}"
  download_file=""
  install_cmd_status=1

  case "${download_url}" in
    *.zip) download_file="${tmp_dir}/$(basename "${download_url}")" ;;
    *.tar.gz|*.tgz) download_file="${tmp_dir}/$(basename "${download_url}")" ;;
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
    _error_msg "Neither curl nor wget available."
    return 6
  fi

  if [ "${download_status}" -ne 0 ]; then
    _error_msg "Download failed from ${download_url} (Exit code: ${download_status})."
    return 3
  fi

  _log_msg "Extracting archive..." >&2
  case "${download_file}" in
    *.tar.gz|*.tgz) tar -xzf "${download_file}" -C "${tmp_dir}" ;;
    *.zip) unzip -q "${download_file}" -d "${tmp_dir}" ;;
    *) _error_msg "Unknown format: ${download_file}"; return 4 ;;
  esac

  if [ "${source_install}" -eq 1 ]; then
    if [ "${use_go}" -eq 1 ]; then
      OPENCODE_BUILD_DIR=$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -type d -name "*-opencode-*" 2>/dev/null)
      [ -z "${OPENCODE_BUILD_DIR}" ] && return 4
      _log_msg "Running go build…" >&2
      ldflags="-s -w -X main.date=$(date -u +'%Y-%m-%dT%H:%M:%SZ') -X main.version=${version} -X main.buildSource=tarball"
      (cd "${OPENCODE_BUILD_DIR}" && go build -ldflags "${ldflags}" -o opencode) && \
      install -m 755 "${OPENCODE_BUILD_DIR}/opencode" "${location_path}/"
      install_cmd_status=$?
    else
      OPENCODE_BUILD_DIR=$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -type d -name "anomalyco-opencode-*" 2>/dev/null)
      [ -z "${OPENCODE_BUILD_DIR}" ] && return 4
      (cd "${OPENCODE_BUILD_DIR}" && bun install) >/dev/null 2>&1
      build_args="--single"
      [ "${has_avx2}" -eq 0 ] && build_args="${build_args} --baseline"
      
      _log_msg "Running bun build ${build_args}…" >&2
      if (cd "${OPENCODE_BUILD_DIR}/packages/opencode" && OPENCODE_VERSION="${version}" bun run build ${build_args}) >/dev/null 2>&1; then
        # Find exact binary based on triple
        bin_path=$(find "${OPENCODE_BUILD_DIR}/packages/opencode/dist" -path "*/opencode-${target_triple}/bin/opencode" -type f -executable 2>/dev/null | head -n 1)
        [ -z "${bin_path}" ] && bin_path=$(find "${OPENCODE_BUILD_DIR}/packages/opencode/dist" -name opencode -type f -executable 2>/dev/null | head -n 1)
        [ -z "${bin_path}" ] && bin_path="${OPENCODE_BUILD_DIR}/packages/opencode/bin/opencode"
        
        install -m 755 "${bin_path}" "${location_path}/"
        install_cmd_status=$?
      else
        return 5
      fi
    fi
  else
    _log_msg "Installing pre-compiled binary…" >&2
    opencode_binary=$(find "${tmp_dir}" -name opencode -type f -executable 2>/dev/null | head -n 1)
    if [ -z "${opencode_binary}" ]; then
      _error_msg "Could not find 'opencode' executable."
      return 4
    fi
    install -m 755 "${opencode_binary}" "${location_path}/"
    install_cmd_status=$?
  fi

  if [ "${install_cmd_status}" -eq 0 ]; then
    _log_msg "Successfully installed to ${location_path}/" >&2
    printf '%s\n' "opencode"
  fi
}

url=$(get_specific_release_url) || return $?
download_and_install "${url}"
