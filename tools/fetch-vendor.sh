#!/usr/bin/env bash
# Download and verify k3s + airgap images into core/config/includes.chroot/opt/ark-vendor.
# The only step of the build that needs the internet besides the Debian mirror.
#
# K3S_VERSION may be set explicitly (e.g. v1.33.5+k3s1). If not, the version
# pinned in tools/vendor.lock is used; if that is missing too, the current
# "stable" channel is resolved once and written to the lock file.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$ROOT/tools/vendor.lock"
DEST="$ROOT/core/config/includes.chroot/opt/ark-vendor"

if [ -z "${K3S_VERSION:-}" ] && [ -f "$LOCK" ]; then
    # shellcheck disable=SC1090
    . "$LOCK"
fi

if [ -z "${K3S_VERSION:-}" ]; then
    echo "Resolving k3s stable channel..."
    K3S_VERSION="$(curl -fsSL -o /dev/null -w '%{url_effective}' https://update.k3s.io/v1-release/channels/stable | sed 's|.*/||')"
    [ -n "$K3S_VERSION" ] || { echo "Could not resolve k3s version" >&2; exit 1; }
    echo "K3S_VERSION=$K3S_VERSION" > "$LOCK"
    echo "Pinned $K3S_VERSION in $LOCK"
fi

ENC="${K3S_VERSION//+/%2B}"
BASE="https://github.com/k3s-io/k3s/releases/download/$ENC"
mkdir -p "$DEST"
cd "$DEST"

fetch() { curl -fsSL --retry 3 -o "$1" "$BASE/$1"; }

fetch sha256sum-amd64.txt
fetch k3s
fetch k3s-airgap-images-amd64.tar.zst

# Verify against the release checksum file (it lists the amd64 assets by name).
grep -E ' (k3s|k3s-airgap-images-amd64\.tar\.zst)$' sha256sum-amd64.txt | sha256sum -c -
chmod 0755 k3s
rm -f sha256sum-amd64.txt
echo "Vendor files ready in $DEST (k3s $K3S_VERSION)"
