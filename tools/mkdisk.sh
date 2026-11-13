#!/usr/bin/env bash
# Assemble the ARK-Core boot disk image (GPT, BIOS + UEFI, A/B system slots).
#
#   mkdisk.sh <live-dir> <out.img> [size_gb]
#
# <live-dir> is the live-build "binary/live" directory with vmlinuz*, initrd.img*
# and filesystem.squashfs. Needs root, losetup, sgdisk, mkfs.vfat, mkfs.ext4 and
# grub-install for both i386-pc and x86_64-efi (grub-pc-bin, grub-efi-amd64-bin).
#
# Layout (32 GB default):
#   1  BIOS boot   1 MiB    (EF02)
#   2  ARK-ESP     512 MiB  FAT32, GRUB for UEFI + BIOS, grub.cfg, grubenv
#   3  ARK-SYS-A   10 GiB   ext4, live/ (squashfs, kernel, initrd)
#   4  ARK-SYS-B   10 GiB   ext4, empty until the first update
#   5  ARK-CFG     rest     ext4, optional persistence / seed file
set -euo pipefail

LIVE="${1:?usage: mkdisk.sh <live-dir> <out.img> [size_gb]}"
IMG="${2:?usage: mkdisk.sh <live-dir> <out.img> [size_gb]}"
SIZE_GB="${3:-32}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "mkdisk.sh must run as root" >&2; exit 1; }
for t in losetup sgdisk mkfs.vfat mkfs.ext4 grub-install; do
    command -v "$t" >/dev/null || { echo "missing tool: $t" >&2; exit 1; }
done
ls "$LIVE"/vmlinuz* "$LIVE"/initrd.img* "$LIVE"/filesystem.squashfs >/dev/null

MNT="$(mktemp -d)"
LOOP=""
cleanup() {
    set +e
    mountpoint -q "$MNT/esp" && umount "$MNT/esp"
    mountpoint -q "$MNT/sysa" && umount "$MNT/sysa"
    [ -n "$LOOP" ] && losetup -d "$LOOP"
    rm -rf "$MNT"
}
trap cleanup EXIT

rm -f "$IMG"
truncate -s "${SIZE_GB}G" "$IMG"
LOOP="$(losetup --find --show --partscan "$IMG")"

sgdisk --zap-all "$LOOP" >/dev/null
sgdisk \
    -n 1:2048:+1M     -t 1:ef02 -c 1:bios-boot \
    -n 2:0:+512M      -t 2:ef00 -c 2:ARK-ESP \
    -n 3:0:+10G       -t 3:8300 -c 3:ARK-SYS-A \
    -n 4:0:+10G       -t 4:8300 -c 4:ARK-SYS-B \
    -n 5:0:0          -t 5:8300 -c 5:ARK-CFG \
    "$LOOP" >/dev/null
# Some legacy BIOSes only boot a GPT disk if a partition has the "legacy BIOS bootable" flag.
sgdisk -A 2:set:2 "$LOOP" >/dev/null
partprobe "$LOOP" 2>/dev/null || udevadm settle
sleep 1

mkfs.vfat -F 32 -n ARK-ESP "${LOOP}p2" >/dev/null
mkfs.ext4 -q -L ARK-SYS-A "${LOOP}p3"
mkfs.ext4 -q -L ARK-SYS-B "${LOOP}p4"
mkfs.ext4 -q -L ARK-CFG   "${LOOP}p5"

mkdir -p "$MNT/esp" "$MNT/sysa"
mount "${LOOP}p2" "$MNT/esp"
mount "${LOOP}p3" "$MNT/sysa"

# System slot A
mkdir -p "$MNT/sysa/live"
cp "$LIVE"/vmlinuz* "$LIVE"/initrd.img* "$LIVE"/filesystem.squashfs "$MNT/sysa/live/"

# GRUB: one boot directory on the ESP, both firmware targets
mkdir -p "$MNT/esp/boot/grub"
grub-install --target=i386-pc --boot-directory="$MNT/esp/boot" \
    --modules="part_gpt ext2 fat" "$LOOP" >/dev/null
grub-install --target=x86_64-efi --efi-directory="$MNT/esp" \
    --boot-directory="$MNT/esp/boot" --removable --no-nvram >/dev/null
cp "$ROOT/grub/grub.cfg" "$MNT/esp/boot/grub/grub.cfg"
grub-editenv "$MNT/esp/boot/grub/grubenv" create
grub-editenv "$MNT/esp/boot/grub/grubenv" set ark_slot=A

sync
echo "Disk image ready: $IMG"
