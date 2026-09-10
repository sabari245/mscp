#!/usr/bin/env bash
#
# Install mscp from a GitHub release.
#
# Supported platforms: Ubuntu 22.04+/Debian 12+ (glibc >= 2.35) and Arch Linux (x86_64).
#
# Usage:
#   ./scripts/install.sh                 # install the latest release
#   ./scripts/install.sh -v v0.2.5       # install a specific release
#   ./scripts/install.sh -p ~/.local     # install to a custom prefix
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/sabari245/mscp/main/scripts/install.sh | bash

set -euo pipefail

REPO="${MSCP_REPO:-sabari245/mscp}"
VERSION="${MSCP_VERSION:-latest}"
PREFIX="${MSCP_PREFIX:-/usr/local}"

usage() {
	cat <<EOF
Usage: $0 [options]

Install mscp from a GitHub release.

Options:
  -v, --version VERSION  Release tag to install (default: ${VERSION})
  -p, --prefix PREFIX    Install prefix (default: ${PREFIX})
  -h, --help             Show this help

Environment:
  MSCP_REPO     GitHub repository (default: sabari245/mscp)
  MSCP_VERSION  Release tag (default: latest)
  MSCP_PREFIX   Install prefix (default: /usr/local)
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		-v|--version) VERSION="$2"; shift 2 ;;
		-p|--prefix)  PREFIX="$2";  shift 2 ;;
		-h|--help)    usage; exit 0 ;;
		*) echo "error: unknown option: $1" >&2; usage >&2; exit 1 ;;
	esac
done

for cmd in curl tar sha256sum; do
	command -v "$cmd" >/dev/null 2>&1 || {
		echo "error: '$cmd' is required but was not found in PATH" >&2
		exit 1
	}
done

# Detect architecture.
case "$(uname -m)" in
	x86_64|amd64) arch=x86_64 ;;
	*)
		echo "error: unsupported architecture: $(uname -m) (only x86_64 releases are published)" >&2
		exit 1 ;;
esac

# Detect distribution.
if [ -r /etc/os-release ]; then
	. /etc/os-release
fi
distro_id="${ID:-}"
distro_like="${ID_LIKE:-}"

platform=""
if [ "$distro_id" = ubuntu ] || [ "$distro_id" = debian ] \
	|| [[ "$distro_like" == *ubuntu* ]] || [[ "$distro_like" == *debian* ]]; then
	platform=linux-glibc
elif [ "$distro_id" = arch ] || [[ "$distro_like" == *arch* ]]; then
	platform=arch
else
	echo "error: unsupported distribution: ${distro_id:-unknown} (supported: Ubuntu 22.04+, Debian 12+, Arch Linux)" >&2
	exit 1
fi

# The glibc artifact is built on Ubuntu 22.04 (glibc 2.35) and relies on
# forward compatibility, so refuse older systems where it would not run.
if [ "$platform" = linux-glibc ]; then
	glibc_ver=$(getconf GNU_LIBC_VERSION 2>/dev/null | awk '{print $2}')
	if [ -n "$glibc_ver" ] && ! printf '%s\n%s\n' "2.35" "$glibc_ver" | sort -V -C; then
		echo "error: glibc ${glibc_ver} is too old (need >= 2.35, e.g. Ubuntu 22.04+ or Debian 12+)" >&2
		exit 1
	fi
fi

# Resolve the release tag.
if [ "$VERSION" = latest ]; then
	VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
		| sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n1)
	[ -n "$VERSION" ] || { echo "error: failed to determine the latest release" >&2; exit 1; }
fi

tag="${VERSION#v}"
name="mscp-${tag}-${platform}-${arch}"
url="https://github.com/${REPO}/releases/download/${VERSION}"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

echo "Downloading ${name}.tar.gz (${VERSION}) ..."
curl -fL --retry 3 --retry-delay 2 -o "$tmpdir/${name}.tar.gz" "$url/${name}.tar.gz"
curl -fL --retry 3 --retry-delay 2 -o "$tmpdir/${name}.tar.gz.sha256" "$url/${name}.tar.gz.sha256"

echo "Verifying checksum ..."
( cd "$tmpdir" && sha256sum -c "${name}.tar.gz.sha256" )

tar -xzf "$tmpdir/${name}.tar.gz" -C "$tmpdir"

srcdir="$tmpdir/${name}"
[ -x "$srcdir/mscp" ] || { echo "error: mscp binary not found in archive" >&2; exit 1; }

# Elevate only when the prefix is not writable.
sudo=""
if [ ! -d "$PREFIX" ] || [ ! -w "$PREFIX" ]; then
	if [ ! -w "$(dirname "$PREFIX")" ]; then
		sudo="sudo"
	fi
fi

$sudo install -d "$PREFIX/bin" "$PREFIX/share/man/man1"
$sudo install -m 0755 "$srcdir/mscp" "$PREFIX/bin/mscp"
if [ -f "$srcdir/mscp.1" ]; then
	$sudo install -m 0644 "$srcdir/mscp.1" "$PREFIX/share/man/man1/mscp.1"
fi

echo
echo "Installed mscp ${tag} to ${PREFIX}/bin/mscp"
case ":$PATH:" in
	*":$PREFIX/bin:"*) ;;
	*) echo "note: add ${PREFIX}/bin to your PATH" ;;
esac
