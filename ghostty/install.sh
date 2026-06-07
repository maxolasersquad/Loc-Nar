#!/bin/sh

source_install=0
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

# Determine if we must build from source
must_build_source=0
if [ "${os}" = "linux" ] || [ "${source_install}" -eq 1 ]; then
  must_build_source=1
fi

_log_msg "Checking dependencies…" >&2
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  _error_msg "Neither curl nor wget found. Cannot download releases."
  return 6
fi
if [ "${must_build_source}" -eq 1 ]; then
  if ! command -v zig >/dev/null 2>&1; then
    _error_msg "'zig' command not found. Required to compile Ghostty from source."
    return 6
  fi
  if ! command -v tar >/dev/null 2>&1; then
    _error_msg "'tar' command not found. Required to extract source archive."
    return 6
  fi
else
  if ! command -v unzip >/dev/null 2>&1; then
    _error_msg "'unzip' command not found. Required to extract pre-compiled zip."
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

tmp_dir=$(mktemp -d /tmp/trk-ghostty-install-XXXXXX) || {
  _error_msg "Failed to create temporary directory."
  return 1
}
trap 'rm -rf "${tmp_dir}"' EXIT
_log_msg "Created temporary directory: ${tmp_dir}" >&2

get_download_url() {
  if [ "${os}" != "darwin" ] && [ "${os}" != "linux" ]; then
    _error_msg "Unsupported OS/architecture combo: ${os}/${arch}"
    _error_msg "You can build from source on Linux/macOS using the --source option, but other platforms are not supported."
    return 6
  fi

  stripped_version="${version#v}"
  if [ "${must_build_source}" -eq 1 ]; then
    if [ "${version}" = "tip" ]; then
      printf '%s\n' "https://github.com/ghostty-org/ghostty/releases/download/tip/ghostty-source.tar.gz"
    else
      printf '%s\n' "https://github.com/ghostty-org/ghostty/archive/refs/tags/${version}.tar.gz"
    fi
  else
    if [ "${version}" = "tip" ]; then
      printf '%s\n' "https://github.com/ghostty-org/ghostty/releases/download/tip/ghostty-macos-universal.zip"
    else
      printf '%s\n' "https://release.files.ghostty.org/${stripped_version}/ghostty-macos-universal.zip"
    fi
  fi
}

download_and_install() {
  download_url="${1}"
  download_file=""
  install_cmd_status=1

  case "${download_url}" in
    *.zip) download_file="${tmp_dir}/$(basename "${download_url}")" ;;
    *.tar.gz|*.tgz) download_file="${tmp_dir}/$(basename "${download_url}")" ;;
    *)
      if [ "${must_build_source}" -eq 1 ]; then
        download_file="${tmp_dir}/ghostty-source.tar.gz"
      else
        download_file="${tmp_dir}/ghostty-macos.zip"
      fi
      ;;
  esac

  _log_msg "Downloading Ghostty from ${download_url}" >&2
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
  _log_msg "Download successful: ${download_file}" >&2

  _log_msg "Extracting archive..." >&2
  case "${download_file}" in
    *.tar.gz|*.tgz)
      tar -xzf "${download_file}" -C "${tmp_dir}"
      extract_status=$?
      ;;
    *.zip)
      unzip -q "${download_file}" -d "${location_path}"
      extract_status=$?
      ;;
    *)
      _error_msg "Unknown download archive format."
      return 4
      ;;
  esac

  if [ "${extract_status}" -ne 0 ]; then
    _error_msg "Extraction failed (Exit code: ${extract_status})."
    return 4
  fi
  _log_msg "Extraction successful." >&2

  if [ "${must_build_source}" -eq 1 ]; then
    _log_msg "Building Ghostty from source using Zig…" >&2
    GHOSTTY_BUILD_DIR=$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)

    if [ -z "${GHOSTTY_BUILD_DIR}" ] || [ ! -d "${GHOSTTY_BUILD_DIR}" ]; then
      _error_msg "Could not find extracted source directory in ${tmp_dir}"
      return 4
    fi
    _log_msg "Found source directory: ${GHOSTTY_BUILD_DIR}" >&2

    _log_msg "Running zig build…" >&2
    build_ok=0
    if [ "${verbose}" -eq 1 ]; then
      (cd "${GHOSTTY_BUILD_DIR}" && zig build -Doptimize=ReleaseFast --prefix "${location_path}") && build_ok=1
    else
      (cd "${GHOSTTY_BUILD_DIR}" && zig build -Doptimize=ReleaseFast --prefix "${location_path}") >/dev/null 2>&1 && build_ok=1
    fi

    if [ "${build_ok}" -eq 1 ]; then
      _log_msg "Build and install successful." >&2
      install_cmd_status=0
    else
      _error_msg "zig build failed."
      return 5
    fi
  else
    _log_msg "Pre-compiled macOS zip extracted directly to ${location_path}." >&2
    install_cmd_status=0
  fi

  if [ "${install_cmd_status}" -ne 0 ]; then
    _error_msg "Failed to install Ghostty to ${location_path}/ (Exit code: ${install_cmd_status})."
    return 1
  fi

  _log_msg "Ghostty installed successfully to ${location_path}/" >&2
  
  if [ "${must_build_source}" -eq 1 ]; then
    printf '%s\n' "bin/ghostty"
  else
    printf '%s\n' "Ghostty.app/Contents/MacOS/ghostty"
  fi
}

url=$(get_download_url) || return "${?}"
download_and_install "${url}"
