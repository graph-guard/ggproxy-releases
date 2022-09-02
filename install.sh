#!/bin/sh
set -e

usage() {
  this=$1
  cat <<EOF
$this: script for managing installation of ggproxy

Usage: $this [-r|-i] [-b] bindir [-d] [tag]
  -r remove current installation
  -b sets binary installation directory, defaults to /usr/local/bin
  -d turns on debug logging
   [tag] is a tag from
   https://github.com/graph-guard/ggproxy-releases/releases
   If tag is missing, then the latest will be used.

EOF
  exit 2
}

parse_args() {
  BINDIR=${BINDIR:-/usr/local/bin}
  while getopts "b:rdh?x" arg; do
    case "$arg" in
      b) BINDIR="$OPTARG" ;;
      r) OPERATION=remove ;;
      d) log_set_priority 10 ;;
      h | \?) usage "$0" ;;
      x) set -x ;;
    esac
  done
  shift $((OPTIND - 1))
  TAG=$1
}
define_binaries() {
  case "$PLATFORM" in
    darwin/amd64|darwin/arm64) BINARIES="ggproxy" ;;
    linux/386|linux/amd64|linux/arm64) BINARIES="ggproxy" ;;
    *)
      log_crit "platform $PLATFORM is not supported."
      exit 1
      ;;
  esac
}
tag_to_version() {
  if [ -z "${TAG}" ]; then
    log_info "checking GitHub for latest tag"
  else
    log_info "checking GitHub for tag '${TAG}'"
  fi
  REALTAG=$(github_release "$OWNER/$REPO" "${TAG}") && true
  if test -z "$REALTAG"; then
    log_crit "unable to find '${TAG}' - use 'latest' or see https://github.com/${PREFIX}/releases for details"
    exit 1
  fi
  # if version starts with 'v', remove it
  TAG="$REALTAG"
  VERSION=${TAG#v}
}
adjust_format() {
  # change format (tar.gz or zip) based on OS
  case ${OS} in
    windows) FORMAT=zip ;;
  esac
  true
}
adjust_os() {
  # adjust archive name based on OS
  true
}
adjust_arch() {
  # adjust archive name based on ARCH
  true
}

cat /dev/null <<EOF
------------------------------------------------------------------------
https://github.com/client9/shlib - portable posix shell functions
Public domain - http://unlicense.org
https://github.com/client9/shlib/blob/master/LICENSE.md
but credit (and pull requests) appreciated.
------------------------------------------------------------------------
EOF
is_command() {
  command -v "$1" >/dev/null
}
echoerr() {
  echo "$@" 1>&2
}
log_prefix() {
  echo "$0"
}
_logp=6
log_set_priority() {
  _logp="$1"
}
log_priority() {
  if test -z "$1"; then
    echo "$_logp"
    return
  fi
  [ "$1" -le "$_logp" ]
}
log_tag() {
  case $1 in
    0) echo "[emerg]" ;;
    1) echo "[alert]" ;;
    2) echo "[crit]" ;;
    3) echo "[err]" ;;
    4) echo "[warning]" ;;
    5) echo "[notice]" ;;
    6) echo "[info]" ;;
    7) echo "[debug]" ;;
    *) echo "$1" ;;
  esac
}
log_debug() {
  log_priority 7 || return 0
  echoerr "$(log_prefix)" "$(log_tag 7)" "$@"
}
log_info() {
  log_priority 6 || return 0
  echoerr "$(log_prefix)" "$(log_tag 6)" "$@"
}
log_err() {
  log_priority 3 || return 0
  echoerr "$(log_prefix)" "$(log_tag 3)" "$@"
}
log_crit() {
  log_priority 2 || return 0
  echoerr "$(log_prefix)" "$(log_tag 2)" "$@"
}
uname_os() {
  os=$(uname -s | tr '[:upper:]' '[:lower:]')
  case "$os" in
    msys*) os="windows" ;;
    mingw*) os="windows" ;;
    cygwin*) os="windows" ;;
    win*) os="windows" ;;
  esac
  echo "$os"
}
uname_arch() {
  arch=$(uname -m)
  case $arch in
    x86_64) arch="amd64" ;;
    x86|i686|i386) arch="386" ;;
    aarch64) arch="arm64" ;;
    armv5*) arch="armv5" ;;
    armv6*) arch="armv6" ;;
    armv7*) arch="armv7" ;;
  esac
  echo ${arch}
}
uname_os_check() {
  os=$(uname_os)
  case "$os" in
    darwin|dragonfly|freebsd|linux|android|nacl|netbsd|openbsd|plan9|solaris|windows) return 0 ;;
  esac
  log_crit "uname_os_check '$(uname -s)' got converted to '$os' which is not a GOOS value. Please file bug at https://github.com/client9/shlib"
  return 1
}
uname_arch_check() {
  arch=$(uname_arch)
  case "$arch" in
    386|amd64|arm64|armv5|armv6|armv7|ppc64|ppc64le|mips|mipsle|mips64|mips64le|s390x|amd64p32) return 0 ;;
  esac
  log_crit "uname_arch_check '$(uname -m)' got converted to '$arch' which is not a GOARCH value. Please file bug report at https://github.com/client9/shlib"
  return 1
}
untar() {
  tarball=$1
  case "${tarball}" in
    *.tar.gz | *.tgz) tar --no-same-owner -xzf "${tarball}" ;;
    *.tar) tar --no-same-owner -xf "${tarball}" ;;
    *.zip) unzip "${tarball}" ;;
    *)
      log_err "untar unknown archive format for ${tarball}"
      return 1
      ;;
  esac
}
http_download_curl() {
  local_file=$1
  source_url=$2
  header=$3
  if [ -z "$header" ]; then
    code=$(curl -w '%{http_code}' -sL -o "$local_file" "$source_url")
  else
    code=$(curl -w '%{http_code}' -sL -H "$header" -o "$local_file" "$source_url")
  fi
  if [ "$code" != "200" ]; then
    log_debug "http_download_curl received HTTP status $code"
    return 1
  fi
  return 0
}
http_download_wget() {
  local_file=$1
  source_url=$2
  header=$3
  if [ -z "$header" ]; then
    wget -q -O "$local_file" "$source_url"
  else
    wget -q --header "$header" -O "$local_file" "$source_url"
  fi
}
http_download() {
  log_debug "http_download $2"
  if is_command curl; then
    http_download_curl "$@"
    return
  elif is_command wget; then
    http_download_wget "$@"
    return
  fi
  log_crit "http_download unable to find wget or curl"
  return 1
}
http_copy() {
  tmp=$(mktemp)
  http_download "${tmp}" "$1" "$2" || return 1
  body=$(cat "$tmp")
  rm -f "${tmp}"
  echo "$body"
}
github_release() {
  owner_repo=$1
  version=$2
  test -z "$version" && version="latest"
  giturl="https://github.com/${owner_repo}/releases/${version}"
  json=$(http_copy "$giturl" "Accept:application/json")
  test -z "$json" && return 1
  version=$(echo "$json" | tr -s '\n' ' ' | sed 's/.*"tag_name":"//' | sed 's/".*//')
  test -z "$version" && return 1
  echo "$version"
}
hash_sha256() {
  TARGET=${1:-/dev/stdin}
  if is_command gsha256sum; then
    hash=$(gsha256sum "$TARGET") || return 1
    echo "$hash" | cut -d ' ' -f 1
  elif is_command sha256sum; then
    hash=$(sha256sum "$TARGET") || return 1
    echo "$hash" | cut -d ' ' -f 1
  elif is_command shasum; then
    hash=$(shasum -a 256 "$TARGET" 2>/dev/null) || return 1
    echo "$hash" | cut -d ' ' -f 1
  elif is_command openssl; then
    hash=$(openssl -dst openssl dgst -sha256 "$TARGET") || return 1
    echo "$hash" | cut -d ' ' -f a
  else
    log_crit "hash_sha256 unable to find command to compute sha-256 hash"
    return 1
  fi
}
hash_sha256_verify() {
  TARGET=$1
  checksums=$2
  if [ -z "$checksums" ]; then
    log_err "hash_sha256_verify checksum file not specified in arg2"
    return 1
  fi
  BASENAME=${TARGET##*/}
  want=$(grep "${BASENAME}" "${checksums}" 2>/dev/null | tr '\t' ' ' | cut -d ' ' -f 1)
  if [ -z "$want" ]; then
    log_err "hash_sha256_verify unable to find checksum for '${TARGET}' in '${checksums}'"
    return 1
  fi
  got=$(hash_sha256 "$TARGET")
  if [ "$want" != "$got" ]; then
    log_err "hash_sha256_verify checksum for '$TARGET' did not verify ${want} vs $got"
    return 1
  fi
}
cat /dev/null <<EOF
------------------------------------------------------------------------
End of functions from https://github.com/client9/shlib
------------------------------------------------------------------------
EOF

check_supported_os() {
  case "$OS" in
    linux|darwin) ;;
    *)
      log_crit "operation system $OS is not supported"
      exit 1
      ;;
  esac
}

check_root() {
  if [ $(id -u) -ne 0 ]; then
    log_crit "please run as root"
    exit
  fi
}

prepare_user_linux() {
  id -u $SERVICE_USER >/dev/null 2>&1 || useradd -r $SERVICE_USER
  usermod -a -G $SERVICE_USER $SERVICE_USER
  usermod -a -G $SERVICE_USER $CURRENT_USER
  log_info "current user added to the $SERVICE_USER group, please relogin to changes take effect"
}

prepare_user() {
  case "$OS" in
    linux) prepare_user_linux ;;
  esac
}

remove() {
  if [ -f $BINDIR/ggproxy ] || [ -d $CONFDIR/ggproxy ]; then
    rm -rf $BINDIR/ggproxy $CONFDIR/ggproxy
    log_info "current installation of ggproxy was removed"
  else
    log_info "ggproxy is not installed"
  fi
}

install_linix() {
  for binexe in $BINARIES; do
    command install "${TMPDIR}/usr/local/bin/${binexe}" "${BINDIR}/"
    chown :${SERVICE_USER} ${BINDIR}/${binexe}
    chmod 775 "${BINDIR}/${binexe}"
    log_info "binary installed to ${BINDIR}/${binexe}"
  done
  cp -rn "${TMPDIR}/etc/"* "${CONFDIR}/"
  chown -R :${SERVICE_USER} ${CONFDIR}/ggproxy
  find ${CONFDIR}/ggproxy -type d -exec chmod 775 -- {} +
  find ${CONFDIR}/ggproxy -type f -exec chmod 664 -- {} +
  log_info "configs installed to ${CONFDIR}/ggproxy"
}

install_darwin() {
  for binexe in $BINARIES; do
    command install "${TMPDIR}/usr/local/bin/${binexe}" "${BINDIR}/"
    chmod 775 "${BINDIR}/${binexe}"
    log_info "binary installed to ${BINDIR}/${binexe}"
  done
  cp -rn "${TMPDIR}/etc/"* "${CONFDIR}/"
  find ${CONFDIR}/ggproxy -type d -exec chmod 775 {} +
  find ${CONFDIR}/ggproxy -type f -exec chmod 664 {} +
  log_info "configs installed to ${CONFDIR}/ggproxy"
}

install() {
  log_debug "downloading files into ${TMPDIR}"
  http_download "${TMPDIR}/${TARBALL}" "${TARBALL_URL}"
  http_download "${TMPDIR}/${CHECKSUM}" "${CHECKSUM_URL}"
  hash_sha256_verify "${TMPDIR}/${TARBALL}" "${TMPDIR}/${CHECKSUM}"
  (cd "${TMPDIR}" && untar "${TARBALL}")
  test ! -d "${BINDIR}" && command install -d "${BINDIR}"
  case "$OS" in
    linux) install_linix ;;
    darwin) install_darwin ;;
  esac
}

PROJECT_NAME=ggproxy
OWNER=graph-guard
REPO=ggproxy-releases
BINARY=ggproxy
FORMAT=tar.gz
OS=$(uname_os)
ARCH=$(uname_arch)
PREFIX="$OWNER/$REPO"
OPERATION=install

log_prefix() {
	echo "$PREFIX"
}
PLATFORM="${OS}/${ARCH}"
GITHUB_DOWNLOAD=https://github.com/${OWNER}/${REPO}/releases/download

uname_os_check "$OS"
uname_arch_check "$ARCH"

check_supported_os
check_root

CONFDIR=${CONFDIR:-/etc}
SERVICE_USER=${SERVICE_USER:-ggproxy}
if [ $SUDO_USER ]; then CURRENT_USER=$SUDO_USER; else CURRENT_USER=`whoami`; fi

parse_args "$@"
case "$OPERATION" in
  remove) remove; exit 0 ;;
esac

TMPDIR=$(mktemp -d)
log_debug "tmp directory created at ${TMPDIR}"
trap cleanup 1 2 3 6 9 EXIT

cleanup() {
  log_debug "cleaning up ${TMPDIR}"
  rm -rf "$TMPDIR"
  exit
}

define_binaries
tag_to_version
adjust_format
adjust_os
adjust_arch

log_info "found version: ${VERSION} for ${TAG}/${OS}/${ARCH}"

NAME=${BINARY}-${VERSION}-${OS}-${ARCH}
TARBALL=${NAME}.${FORMAT}
TARBALL_URL=${GITHUB_DOWNLOAD}/${TAG}/${TARBALL}
CHECKSUM=${PROJECT_NAME}-${VERSION}-checksums.txt
CHECKSUM_URL=${GITHUB_DOWNLOAD}/${TAG}/${CHECKSUM}

prepare_user
install 
