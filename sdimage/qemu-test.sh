#!/bin/sh
# Boot a copy of the card image in QEMU and check it from the kernel upwards.
#
# Usage: sdimage/qemu-test.sh [IMAGE]      (default out/sdimage/de25-nano.img)
#
# QEMU has no model of this board's SoC, so nothing before the kernel runs here: not the
# SPL, U-Boot, boot.scr, the flash or the FPGA, and none of the board's own hardware. What
# does run is the image's root file system on QEMU's generic arm64 machine ("virt"), started
# with the kernel from out/kernel, which is built from the standard arm64 configuration and
# so runs there too. That checks: the first boot's set-up, that nothing fails to start, that
# the packages are installed properly and install again on a running system, the man pages,
# and de25-flash and de25-fpga on a machine that looks like a board with the factory flash
# contents (no /dev/mtd0), up to the request for a flash write that U-Boot would carry out.
#
# Needs qemu-system-aarch64, mtools, dpkg-deb and ssh on this machine, or else Docker.
# About five minutes: the arm64 CPU is emulated.
# The image is not changed: the test runs on a copy.
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
img=${1:-$top/out/sdimage/de25-nano.img}
[ -f "$img" ] || { echo "qemu-test.sh: no $img" >&2; exit 1; }
img=$(readlink -f "$img")
# With QEMU and the other tools on this machine, run here; otherwise in a container.
if command -v qemu-system-aarch64 >/dev/null && command -v mcopy >/dev/null &&
   command -v dpkg-deb >/dev/null && command -v ssh >/dev/null; then
    exec sh "$top/sdimage/qemu/inner.sh" "$top" "$img"
fi
docker build -q -t de25-nano-qemu "$top/sdimage/qemu" >/dev/null
exec docker run --rm -v "$top":"$top":ro -v "$img":/image.img:ro \
    de25-nano-qemu sh "$top/sdimage/qemu/inner.sh" "$top" /image.img
