#!/usr/bin/env bash
# Build ARK-Core: fetch vendor files, run live-build, then assemble the 32 GB disk image.
# Needs root (chroot, loop devices). Intended for a Debian 13 host or container.
#
#   sudo ./core/build.sh            # ISO + disk image into ./out
#   SKIP_DISK=1 ./core/build.sh     # ISO only (no loop devices needed)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out"
WORK="$ROOT/core"
DISK_GB="${DISK_GB:-32}"

command -v lb >/dev/null || { echo "live-build not installed (apt install live-build)" >&2; exit 1; }

"$ROOT/tools/fetch-vendor.sh"

cd "$WORK"
lb clean >/dev/null 2>&1 || true
lb config
lb build

mkdir -p "$OUT"
ISO="$(ls -1 "$WORK"/*.iso 2>/dev/null | head -n1 || true)"
[ -n "$ISO" ] || { echo "live-build produced no ISO" >&2; exit 1; }
cp "$ISO" "$OUT/ark-core.iso"

if [ -z "${SKIP_DISK:-}" ]; then
    "$ROOT/tools/mkdisk.sh" "$WORK/binary/live" "$OUT/ark-core.img" "$DISK_GB"
fi

( cd "$OUT" && sha256sum ark-core.* > SHA256SUMS )
echo "Done. Artifacts in $OUT"
