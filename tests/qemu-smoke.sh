#!/usr/bin/env bash
# Boot the ARK-Core ISO in QEMU and check that the wizard answers.
#
#   tests/qemu-smoke.sh out/ark-core.iso [bios|uefi]
#
# BIOS mode uses SeaBIOS (qemu default); UEFI mode needs OVMF (apt install ovmf).
# Pass KVM=0 to run without hardware acceleration (slow, but works in plain CI).
set -euo pipefail

ISO="${1:?usage: qemu-smoke.sh <iso> [bios|uefi]}"
MODE="${2:-bios}"
PORT="${PORT:-8080}"
TIMEOUT="${TIMEOUT:-300}"

ACCEL=()
if [ "${KVM:-1}" = "1" ] && [ -w /dev/kvm ]; then
    ACCEL=(-enable-kvm -cpu host)
else
    ACCEL=(-cpu max)
fi

FW=()
if [ "$MODE" = "uefi" ]; then
    OVMF="$(ls /usr/share/OVMF/OVMF_CODE*.fd /usr/share/ovmf/OVMF.fd 2>/dev/null | head -n1 || true)"
    [ -n "$OVMF" ] || { echo "OVMF not found" >&2; exit 1; }
    FW=(-bios "$OVMF")
fi

LOG="$(mktemp)"
qemu-system-x86_64 "${ACCEL[@]}" "${FW[@]}" -m 2048 -smp 2 \
    -cdrom "$ISO" -boot d \
    -netdev "user,id=n0,hostfwd=tcp::${PORT}-:80" -device virtio-net-pci,netdev=n0 \
    -display none -serial "file:$LOG" -no-reboot &
QPID=$!
trap 'kill "$QPID" 2>/dev/null || true; rm -f "$LOG"' EXIT

echo "Waiting up to ${TIMEOUT}s for wizard on :${PORT} ($MODE)..."
for _ in $(seq 1 "$TIMEOUT"); do
    if curl -fsS "http://127.0.0.1:${PORT}/healthz" 2>/dev/null | grep -q '^ok$'; then
        echo "PASS: wizard is up ($MODE)"
        curl -fsS "http://127.0.0.1:${PORT}/login" | grep -q "ARK" && echo "PASS: login page served"
        exit 0
    fi
    kill -0 "$QPID" 2>/dev/null || { echo "FAIL: QEMU exited early" >&2; tail -n 40 "$LOG" >&2; exit 1; }
    sleep 1
done
echo "FAIL: wizard did not come up in ${TIMEOUT}s" >&2
tail -n 60 "$LOG" >&2
exit 1
