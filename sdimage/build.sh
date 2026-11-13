#!/bin/sh
# Build Task I: the SD card image, from the outputs of the other tasks. See sdimage/README.md.
#
# Usage: sdimage/build.sh
# Output: out/sdimage/de25-nano.img          the complete image, for any board
#     or: out/sdimage/de25-nano-nofpga.img   when Task F has not been built: the same image
#                                            without the FPGA design and its overlay
# Needs: out/u-boot and out/kernel (Tasks B and K), and out/fpga (Task F) for the complete image.
#        Docker; on a host that is not arm64, qemu-user binfmt for aarch64.
#
# Settings, as environment variables, all optional. Without them the image is the same for
# everybody, and the first boot sets up what differs (see sdimage/README.md):
#   SSH_KEYS   a file of ssh public keys for the user
#   MAC        a fixed Ethernet address, e.g. 02:de:25:00:00:01 (default: made up at first boot)
#   HOSTNAME_ (de25-nano)  USER_ (debian)  SUITE (trixie)  IMAGE_MB (3072)
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "sdimage/build.sh: $*" >&2; exit 1; }
[ $# -eq 0 ] || { sed -n '2,15p' "$0"; exit 2; }

in=$top/work/sdimage-input; out=$top/out/sdimage
rm -rf "$in"; mkdir -p "$in" "$out"
need() { [ -f "$1" ] || fail "no $1: build $2 first"; }
need "$top/out/u-boot/u-boot.itb" "Task B (u-boot/build.sh)"
deb=$(ls "$top"/out/kernel/linux-image-*_arm64.deb 2>/dev/null | head -n 1)
[ -n "$deb" ] || fail "no kernel package in $top/out/kernel: build Task K (kernel/build.sh) first"
cp "$top/out/u-boot/u-boot.itb" "$deb" "$in/"
name=de25-nano.img
if [ -f "$top/out/fpga/fpga.rbf" ] && [ -f "$top/out/fpga/fpga.dtbo" ]; then
    cp "$top/out/fpga/fpga.rbf" "$top/out/fpga/fpga.dtbo" "$in/"
else
    name=de25-nano-nofpga.img
    echo "sdimage/build.sh: no out/fpga/fpga.rbf and fpga.dtbo (Task F): building $name"
fi
if [ -n "${SSH_KEYS:-}" ]; then
    [ -s "$SSH_KEYS" ] || fail "SSH_KEYS=$SSH_KEYS is missing or empty"
    cp "$SSH_KEYS" "$in/authorized_keys"
fi
IMAGE_NAME=${IMAGE_NAME:-$name}
export IMAGE_NAME
exec "$top/sdimage/build-image" "$in" "$out"
