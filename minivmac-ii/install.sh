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
  FreeBSD*) os="freebsd" ;;
  NetBSD*) os="netbsd" ;;
  OpenBSD*) os="openbsd" ;;
  MINGW*|MSYS*|CYGWIN*) os="windows" ;;
esac

arch=$(uname -m)
case "${arch}" in
  aarch64|arm64) arch="arm64" ;;
  x86_64|amd64) arch="amd64" ;;
  i386|i486|i586|i686) arch="x86" ;;
esac

if [ "${os}" = "darwin" ] && [ "${arch}" = "amd64" ]; then
  if [ "$(sysctl -n sysctl.proc_translated 2>/dev/null)" = "1" ]; then
    arch="arm64"
  fi
fi

target=""
archive_ext=".bin.tgz"
case "${os}" in
  linux)
    case "${arch}" in
      amd64) target="lx64" ;;
      x86) target="lx86" ;;
      arm64) target="larm" ;;
      powerpc*) target="lppc" ;;
    esac
    ;;
  darwin)
    case "${arch}" in
      arm64)
        case "${version}" in
          37*) target="mcar" ;;
          *) target="mc64" ;;
        esac
        ;;
      amd64) target="mc64" ;;
      x86) target="imch" ;;
    esac
    ;;
  windows)
    archive_ext=".bin.zip"
    case "${arch}" in
      amd64) target="wx64" ;;
      x86) target="wx86" ;;
    esac
    ;;
  freebsd)
    case "${arch}" in
      amd64) target="fb64" ;;
      x86) target="fbsd" ;;
    esac
    ;;
  netbsd)
    case "${arch}" in
      amd64) target="nb64" ;;
      x86) target="nbsd" ;;
    esac
    ;;
esac

if [ -z "${target}" ]; then
  _error_msg "Unsupported OS/architecture combo: ${os}/${arch}."
  return 6
fi

# --- Dependency Verification ---
_log_msg "Checking required dependencies…"
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  _error_msg "Neither curl nor wget found. Cannot download packages."
  return 6
fi

if [ "${source_install}" -eq 1 ]; then
  c_compiler=""
  if command -v gcc >/dev/null 2>&1; then
    c_compiler="gcc"
  elif command -v clang >/dev/null 2>&1; then
    c_compiler="clang"
  elif command -v cc >/dev/null 2>&1; then
    c_compiler="cc"
  else
    _error_msg "No C compiler (gcc, clang, cc) found. Required for source install."
    return 6
  fi

  if ! command -v make >/dev/null 2>&1; then
    _error_msg "'make' command not found. Required for source install."
    return 6
  fi
else
  if [ "${archive_ext}" = ".bin.zip" ]; then
    if ! command -v unzip >/dev/null 2>&1; then
      _error_msg "'unzip' command not found. Required to extract zip archives."
      return 6
    fi
  else
    if ! command -v tar >/dev/null 2>&1; then
      _error_msg "'tar' command not found. Required to extract tar archives."
      return 6
    fi
  fi
fi

_log_msg "Ensuring installation directory exists: ${location_path}"
if ! mkdir -p "${location_path}"; then
  _error_msg "Failed to create installation directory: ${location_path}"
  return 7
fi
if [ ! -w "${location_path}" ]; then
  _error_msg "Installation directory is not writable: ${location_path}"
  return 7
fi

tmp_dir=$(mktemp -d /tmp/trk-minivmac-ii-install-XXXXXX) || {
  _error_msg "Failed to create temporary directory."
  return 1
}
trap 'rm -rf "${tmp_dir}"' EXIT INT TERM
_log_msg "Created temporary directory: ${tmp_dir}"

download_file() {
  url="${1}"
  output_file="${2}"
  _log_msg "Downloading: ${url}"
  if command -v curl >/dev/null 2>&1; then
    curl --fail -sSL "${url}" -o "${output_file}"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "${output_file}" "${url}"
  else
    return 1
  fi
}

extract_archive() {
  archive="${1}"
  dest_dir="${2}"
  mkdir -p "${dest_dir}"
  case "${archive}" in
    *.tgz|*.tar.gz)
      tar -xzf "${archive}" -C "${dest_dir}"
      ;;
    *.zip)
      unzip -q -o "${archive}" -d "${dest_dir}"
      ;;
    *)
      return 1
      ;;
  esac
}

bin_name="minivmac-ii"
if [ "${os}" = "windows" ]; then
  bin_name="minivmac-ii.exe"
fi

if [ "${source_install}" -eq 1 ]; then
  _log_msg "Performing source build for Mini vMac II ${version}…"
  src_ext=".src.tgz"
  if [ "${version}" = "3.5.8" ]; then
    src_ext=".src.zip"
  fi
  src_url="https://www.gryphel.com/d/minivmac/minivmac-${version}/minivmac-${version}${src_ext}"
  src_archive="${tmp_dir}/minivmac-src${src_ext}"

  if ! download_file "${src_url}" "${src_archive}"; then
    src_url="https://www.gryphel.com/d/minivmac/minivmac-${version}/minivmac-${version}.src.zip"
    src_archive="${tmp_dir}/minivmac-src.zip"
    if ! download_file "${src_url}" "${src_archive}"; then
      _error_msg "Failed to download Mini vMac source from ${src_url}"
      return 3
    fi
  fi

  _log_msg "Extracting source archive…"
  if ! extract_archive "${src_archive}" "${tmp_dir}/src"; then
    _error_msg "Failed to extract source archive."
    return 4
  fi

  setup_dir=$(find "${tmp_dir}/src" -name tool.c -exec dirname {} \; | head -n 1)
  if [ -z "${setup_dir}" ]; then
    _error_msg "Could not locate setup/tool.c in extracted source."
    return 4
  fi
  source_root=$(dirname -- "${setup_dir}")
  _log_msg "Source root identified: ${source_root}"

  _log_msg "Compiling Mini vMac setup tool…"
  if ! (cd "${source_root}" && "${c_compiler}" setup/tool.c -o setup_t); then
    _error_msg "Failed to compile setup tool setup/tool.c"
    return 5
  fi

  _log_msg "Configuring Mini vMac for target ${target} (Macintosh II)…"
  (
    cd "${source_root}" || exit 1
    rm -rf bld cfg setup.sh
    ./setup_t -t "${target}" -m II > setup.sh || exit 1
    sh setup.sh || exit 1
    make || exit 1
  ) >/dev/null 2>&1
  build_status=$?

  if [ "${build_status}" -ne 0 ] || [ ! -f "${source_root}/minivmac" ]; then
    _error_msg "Build failed for Mini vMac II (exit status ${build_status})."
    return 5
  fi

  cp "${source_root}/minivmac" "${location_path}/${bin_name}"
  chmod 755 "${location_path}/${bin_name}"
else
  _log_msg "Downloading precompiled Macintosh II binary for target: ${target}…"
  download_url="https://www.gryphel.com/d/minivmac/minivmac-${version}/mnvm0026-${version}-${target}${archive_ext}"
  dest_archive="${tmp_dir}/minivmac-ii-bin${archive_ext}"

  if ! download_file "${download_url}" "${dest_archive}"; then
    _error_msg "Failed to download Mini vMac II from ${download_url}"
    return 3
  fi

  _log_msg "Extracting precompiled binary…"
  if ! extract_archive "${dest_archive}" "${tmp_dir}/bin"; then
    _error_msg "Failed to extract binary archive."
    return 4
  fi

  if [ "${os}" = "darwin" ] && [ -d "${tmp_dir}/bin/Mini vMac 26.app" ]; then
    cp -R "${tmp_dir}/bin/Mini vMac 26.app" "${location_path}/Mini vMac 26.app"
    ln -sf "Mini vMac 26.app/Contents/MacOS/minivmac" "${location_path}/${bin_name}"
  else
    extracted_bin=$(find "${tmp_dir}/bin" \( -name "Mini vMac 26" -o -name "Mini vMac 26.exe" -o -name "minivmac" \) -type f | head -n 1)
    if [ -z "${extracted_bin}" ]; then
      _error_msg "Executable binary not found in extracted archive."
      return 4
    fi
    cp "${extracted_bin}" "${location_path}/${bin_name}"
    chmod 755 "${location_path}/${bin_name}"
  fi
fi

# Taarak contract: print ONLY relative path to main executable
printf '%s\n' "${bin_name}"
