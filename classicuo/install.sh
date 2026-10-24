#!/bin/sh

source_install=0
version=""
location_path=""
verbose=0
github_api_url="https://api.github.com/repos/ClassicUO/ClassicUO/releases"

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

case "${version}" in
  main|latest) version_tag="ClassicUO-main-release" ;;
  beta) version_tag="ClassicUO-beta-release" ;;
  dev) version_tag="ClassicUO-dev-release" ;;
  *) version_tag="${version}" ;;
esac

raw_os=$(uname -s)
os=$(printf '%s' "${raw_os}" | tr '[:upper:]' '[:lower:]')
case "${raw_os}" in
  Darwin*) os="osx" ;;
  Linux*) os="linux" ;;
  MINGW*|MSYS*|CYGWIN*) os="win" ;;
esac

arch=$(uname -m)
case "${arch}" in
  x86_64|amd64) arch="x64" ;;
  aarch64|arm64) arch="arm64" ;;
esac

if [ "${os}" = "osx" ] && [ "${arch}" = "arm64" ]; then
  arch="x64"
fi

_log_msg "Checking dependencies…" >&2
if [ "${source_install}" -eq 1 ]; then
  if ! command -v git >/dev/null 2>&1; then
    _error_msg "'git' command not found. Required to clone ClassicUO source."
    return 6
  fi
  if ! command -v dotnet >/dev/null 2>&1; then
    _error_msg "'dotnet' command not found. Required to build ClassicUO from source."
    return 6
  fi
else
  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    _error_msg "Neither curl nor wget found. Cannot download releases."
    return 6
  fi
  if ! command -v jq >/dev/null 2>&1; then
    _error_msg "'jq' command not found. Cannot parse release information."
    return 6
  fi
  if ! command -v unzip >/dev/null 2>&1; then
    _error_msg "'unzip' command not found. Required to extract zip archives."
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

tmp_dir=$(mktemp -d /tmp/trk-classicuo-install-XXXXXX) || {
  _error_msg "Failed to create temporary directory."
  return 1
}
trap 'rm -rf "${tmp_dir}"' EXIT INT TERM
_log_msg "Created temporary directory: ${tmp_dir}" >&2

get_release_download_url() {
  is_supported=0
  case "${os}" in
    osx|linux|win)
      case "${arch}" in
        x64) is_supported=1 ;;
      esac
      ;;
  esac

  if [ "${is_supported}" -eq 0 ]; then
    _error_msg "Unsupported OS/architecture combo: ${os}/${arch}"
    _error_msg "Pre-compiled binaries are only available for x64 on Linux, macOS, and Windows."
    _error_msg "You can attempt to build from source using the --source option."
    return 6
  fi

  asset_name="ClassicUO-${os}-${arch}-release.zip"
  release_info_url="${github_api_url}/tags/${version_tag}"
  download_url=""

  _log_msg "Fetching release info for tag ${version_tag} from GitHub API..." >&2
  if command -v curl >/dev/null 2>&1; then
    release_json=$(curl --fail -sL "${release_info_url}" 2>/dev/null) || true
  elif command -v wget >/dev/null 2>&1; then
    release_json=$(wget -qO- "${release_info_url}" 2>/dev/null) || true
  fi

  if [ -n "${release_json}" ]; then
    download_url=$(printf '%s' "${release_json}" | jq -r ".assets[] | select(.name == \"${asset_name}\") | .browser_download_url" 2>/dev/null | head -n 1)
  fi

  if [ -z "${download_url}" ] || [ "${download_url}" = "null" ]; then
    _log_msg "API resolution failed or rate limited; attempting standard release asset URL..." >&2
    download_url="https://github.com/ClassicUO/ClassicUO/releases/download/${version_tag}/${asset_name}"
  fi

  printf '%s\n' "${download_url}"
}

download_and_install_binary() {
  download_url="${1}"
  archive_file="${tmp_dir}/archive.zip"

  _log_msg "Downloading ClassicUO from: ${download_url}" >&2
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
  _log_msg "Download successful: ${archive_file}" >&2

  _log_msg "Extracting archive..." >&2
  extracted_dir="${tmp_dir}/extracted"
  mkdir -p "${extracted_dir}"
  if ! unzip -q "${archive_file}" -d "${extracted_dir}"; then
    _error_msg "Extraction failed for ${archive_file}."
    return 4
  fi
  _log_msg "Extraction successful." >&2

  _log_msg "Copying files to ${location_path}/..." >&2
  cp -R "${extracted_dir}/." "${location_path}/"

  resolve_and_print_executable
}

build_from_source() {
  _log_msg "Cloning ClassicUO repository for tag/version: ${version_tag}" >&2
  git_repo="https://github.com/ClassicUO/ClassicUO.git"
  src_dir="${tmp_dir}/src"

  if ! git clone --recursive --depth 1 --branch "${version_tag}" "${git_repo}" "${src_dir}" >/dev/null 2>&1; then
    _log_msg "Direct branch/tag clone failed. Falling back to default clone..." >&2
    if ! git clone --recursive --depth 1 "${git_repo}" "${src_dir}" >/dev/null 2>&1; then
      _error_msg "Failed to clone repository: ${git_repo}"
      return 3
    fi
  fi

  target_runtime="${os}-${arch}"
  if [ "${os}" = "win" ]; then
    target_runtime="win-x64"
  fi

  _log_msg "Building ClassicUO with dotnet for target ${target_runtime}..." >&2
  boot_csproj="${src_dir}/src/ClassicUO.Bootstrap/src/ClassicUO.Bootstrap.csproj"
  client_csproj="${src_dir}/src/ClassicUO.Client"

  if ! dotnet publish "${boot_csproj}" -c Release -o "${location_path}" >/dev/null 2>&1; then
    _error_msg "Failed to build ClassicUO.Bootstrap."
    return 5
  fi

  if ! dotnet publish "${client_csproj}" -c Release -p:NativeLib=Shared -p:OutputType=Library -r "${target_runtime}" -o "${location_path}" >/dev/null 2>&1; then
    _error_msg "Failed to build ClassicUO.Client."
    return 5
  fi

  resolve_and_print_executable
}

resolve_and_print_executable() {
  # Upstream ClassicUO launcher uses `cd "$(cd -P -- "$(dirname -- "$0")" && pwd -P)"`
  # which fails when invoked through symlinks like ~/.local/bin/classicuo.
  # Patch it so that symlinks are resolved to the real installation directory,
  # and automatically use ~/.config/classicuo/settings.json if present.
  if [ -f "${location_path}/ClassicUO" ]; then
    _tmp_patched="${tmp_dir}/ClassicUO.patched"
    awk '
    /cd "\$\(cd -P -- "\$\(dirname -- "\$0"\)" && pwd -P\)"/ {
      print "_CUO_SRC=\"${BASH_SOURCE[0]:-$0}\""
      print "while [ -L \"$_CUO_SRC\" ]; do"
      print "  _CUO_DIR=\"$(cd -P \"$(dirname \"$_CUO_SRC\")\" && pwd -P)\""
      print "  _CUO_SRC=\"$(readlink \"$_CUO_SRC\")\""
      print "  [ \"${_CUO_SRC#/}\" = \"$_CUO_SRC\" ] && _CUO_SRC=\"$_CUO_DIR/$_CUO_SRC\""
      print "done"
      print "cd -P \"$(dirname \"$_CUO_SRC\")\" && pwd -P >/dev/null || exit 1"
      print "_CONFIG_DIR=\"${XDG_CONFIG_HOME:-${HOME}/.config}/classicuo\""
      print "if [ -f \"${_CONFIG_DIR}/settings.json\" ]; then"
      print "  _HAS_SETTINGS=0"
      print "  for _arg in \"$@\"; do"
      print "    case \"$_arg\" in"
      print "      -settings) _HAS_SETTINGS=1 ;;"
      print "    esac"
      print "  done"
      print "  if [ \"$_HAS_SETTINGS\" -eq 0 ]; then"
      print "    set -- -settings \"${_CONFIG_DIR}/settings.json\" \"$@\""
      print "  fi"
      print "fi"
      next
    }
    { print }
    ' "${location_path}/ClassicUO" > "${_tmp_patched}" && cp -f "${_tmp_patched}" "${location_path}/ClassicUO"
    chmod +x "${location_path}/ClassicUO" 2>/dev/null || true
  fi

  if [ "${os}" = "win" ] && [ -f "${location_path}/ClassicUO.exe" ]; then
    chmod +x "${location_path}/ClassicUO.exe" 2>/dev/null || true
    executable_rel_path="ClassicUO.exe"
  elif [ -f "${location_path}/ClassicUO" ]; then
    chmod +x "${location_path}/ClassicUO" 2>/dev/null || true
    if [ -f "${location_path}/ClassicUO.bin.x86_64" ]; then
      chmod +x "${location_path}/ClassicUO.bin.x86_64" 2>/dev/null || true
    fi
    if [ -f "${location_path}/ClassicUO.bin.osx" ]; then
      chmod +x "${location_path}/ClassicUO.bin.osx" 2>/dev/null || true
    fi
    executable_rel_path="ClassicUO"
  elif [ -f "${location_path}/ClassicUO.exe" ]; then
    chmod +x "${location_path}/ClassicUO.exe" 2>/dev/null || true
    executable_rel_path="ClassicUO.exe"
  elif [ -f "${location_path}/ClassicUO.bin.x86_64" ]; then
    chmod +x "${location_path}/ClassicUO.bin.x86_64" 2>/dev/null || true
    executable_rel_path="ClassicUO.bin.x86_64"
  else
    _error_msg "Could not find 'ClassicUO' executable in ${location_path}."
    return 4
  fi

  # Create desktop entry for application menu integration
  mkdir -p "${location_path}/share/applications"
  cat <<'EOF' > "${location_path}/share/applications/classicuo.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=ClassicUO
Comment=Ultima Online Classic Client
Exec=classicuo %U
Icon=applications-games
Terminal=false
Categories=Game;RolePlaying;
EOF

  _log_msg "ClassicUO installed successfully to ${location_path}/" >&2
  printf '%s\n' "${executable_rel_path}"
}

if [ "${source_install}" -eq 1 ]; then
  build_from_source
else
  url=$(get_release_download_url) || return $?
  download_and_install_binary "${url}"
fi
