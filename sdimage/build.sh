#!/bin/sh
# Build Task I: the SD card image, from the outputs of the other tasks. See sdimage/README.md.
#
# Usage: sdimage/build.sh stage1|stage2
#   stage1  for a board with the factory flash contents: no FPGA design on the card
#   stage2  for a board whose flash holds out/fpga/de25-nano.hps.jic: with fpga.rbf and fpga.dtbo
# Output: out/sdimage/de25-nano-stage1.img or de25-nano-stage2.img
# Needs: out/u-boot and out/kernel (Tasks B and K); for stage2 also out/fpga (Task F).
#        Docker; on a host that is not arm64, qemu-user binfmt for aarch64.
#
# Settings, as environment variables:
#   SSH_KEYS   a file of ssh public keys for the user (default: none; then the user logs in with
#              the password and must change it at once)
#   MAC        a fixed Ethernet address, e.g. 02:de:25:00:00:01 (default: none; U-Boot then
#              invents a new one at every boot)
#   HOSTNAME_ (de25-nano)  USER_ (debian)  SUITE (trixie)  IMAGE_MB (3072)
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "sdimage/build.sh: $*" >&2; exit 1; }
stage=${1:-}
case $stage in stage1|stage2) ;; *) sed -n '2,16p' "$0"; exit 2 ;; esac

in=$top/work/sdimage-input; out=$top/out/sdimage
rm -rf "$in"; mkdir -p "$in/dtbs" "$out"
need() { [ -f "$1" ] || fail "no $1: build $2 first"; }
need "$top/out/u-boot/u-boot.itb" "Task B (u-boot/build.sh)"
need "$top/out/kernel/Image" "Task K (kernel/build.sh)"
need "$top/out/kernel/modules.tar.gz" "Task K (kernel/build.sh)"
need "$top/out/kernel/dtbs/socfpga_agilex5_de25_nano.dtb" "Task K (kernel/build.sh)"
cp "$top/out/u-boot/u-boot.itb" "$top/out/kernel/Image" "$top/out/kernel/modules.tar.gz" "$in/"
cp "$top/out/kernel/dtbs/socfpga_agilex5_de25_nano.dtb" "$in/dtbs/"
[ ! -f "$top/out/kernel/config" ] || cp "$top/out/kernel/config" "$in/"
if [ "$stage" = stage2 ]; then
    need "$top/out/fpga/fpga.rbf" "Task F (fpga/build.sh)"
    need "$top/out/fpga/fpga.dtbo" "Task F (fpga/build.sh)"
    cp "$top/out/fpga/fpga.rbf" "$top/out/fpga/fpga.dtbo" "$in/"
fi
if [ -n "${SSH_KEYS:-}" ]; then
    [ -s "$SSH_KEYS" ] || fail "SSH_KEYS=$SSH_KEYS is missing or empty"
    cp "$SSH_KEYS" "$in/authorized_keys"
fi
IMAGE_NAME=${IMAGE_NAME:-de25-nano-$stage.img}
export IMAGE_NAME
exec "$top/sdimage/build-image" "$in" "$out"
