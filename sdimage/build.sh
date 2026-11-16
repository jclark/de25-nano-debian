#!/bin/sh
# Build Task I: the SD card image, from the outputs of the other tasks. See sdimage/README.md.
#
# Usage: sdimage/build.sh
# Output: out/sdimage/de25-nano.img          the complete image, for any board
#     or: out/sdimage/de25-nano-nofpga.img   when Task F has not been built: the same image
#                                            without the boot package and the base core
# Needs: out/kernel (Task K) and out/packages (Task P); for the image without Task F also
#        out/u-boot (Task B). Docker; on a host that is not arm64, qemu-user binfmt for aarch64.
#
# Settings, as environment variables, all optional. Without them the image is the same for
# everybody, and the first boot sets up what differs (see sdimage/README.md):
#   SSH_KEYS   a file of ssh public keys for the user
#   MAC        a fixed Ethernet address, e.g. 02:de:25:00:00:01 (default: made up at first boot)
#   HOSTNAME_ (de25-nano)  USER_ (debian)  SUITE (trixie)  IMAGE_MB (1024)
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "sdimage/build.sh: $*" >&2; exit 1; }
[ $# -eq 0 ] || { sed -n '2,15p' "$0"; exit 2; }

in=$top/work/sdimage-input; out=$top/out/sdimage
rm -rf "$in"; mkdir -p "$in" "$out"
need() { [ -f "$1" ] || fail "no $1: build $2 first"; }
deb=$(ls "$top"/out/kernel/linux-image-*_arm64.deb 2>/dev/null | head -n 1)
[ -n "$deb" ] || fail "no kernel package in $top/out/kernel: build Task K (kernel/build.sh) first"
tools=$(ls "$top"/out/packages/de25-nano-fpga-tools_*.deb 2>/dev/null | head -n 1)
[ -n "$tools" ] || fail "no de25-nano-fpga-tools package in $top/out/packages: build Task P (packages/build.sh) first"
cp "$deb" "$tools" "$in/"
name=de25-nano.img
boot=$(ls "$top"/out/packages/de25-nano-boot-*.deb 2>/dev/null | head -n 1)
core=$(ls "$top"/out/packages/de25-nano-core-base_*.deb 2>/dev/null | head -n 1)
if [ -n "$boot" ] && [ -n "$core" ]; then
    cp "$boot" "$core" "$in/"
else
    name=de25-nano-nofpga.img
    echo "sdimage/build.sh: no boot and core packages in out/packages (Tasks F and P): building $name"
    need "$top/out/u-boot/u-boot.itb" "Task B (u-boot/build.sh)"
    cp "$top/out/u-boot/u-boot.itb" "$top/packages/boot/boot.cmd" "$in/"
fi
if [ -n "${SSH_KEYS:-}" ]; then
    [ -s "$SSH_KEYS" ] || fail "SSH_KEYS=$SSH_KEYS is missing or empty"
    cp "$SSH_KEYS" "$in/authorized_keys"
fi
IMAGE_NAME=${IMAGE_NAME:-$name}
export IMAGE_NAME
exec "$top/sdimage/build-image" "$in" "$out"
