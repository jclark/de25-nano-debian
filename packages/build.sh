#!/bin/sh
# Build Task P: the Debian packages for what is not in the Debian archive. See packages/README.md.
#
# Usage: packages/build.sh
# Output, in out/packages/:
#   de25-nano-fpga-tools_<version>_all.deb     de25-fpga, the fan and HDMI scripts
#   de25-nano-boot-base_<version>_arm64.deb    the HPS image for the flash, u-boot.itb, boot.scr
#   de25-nano-core-base_<version>_arm64.deb    the base core image and its overlay
#   de25-nano-boot-base_<version>.hps.jic      the boot package's HPS image, for writing over JTAG
# Needs: dpkg-deb and mkimage (Debian and Ubuntu: packages dpkg and u-boot-tools), or else
#        Docker; out/u-boot/u-boot.itb (Task B) and out/fpga/base (Task F) for the last two.
#        Without Task F only the first is made.
#
# The versions are in packages/VERSIONS. A boot package that is already in out/packages with
# the version named there is kept, not made again: a rebuild gives an HPS image that differs
# in a few bytes, and boards whose flash holds the old one would be told to write it again for
# nothing. Raise BOOT_VERSION when the SoC settings, U-Boot or the Quartus version change;
# REBUILD_BOOT=1 makes it again regardless.
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
out=$top/out/packages
fail() { echo "packages/build.sh: $*" >&2; exit 1; }
[ $# -eq 0 ] || { sed -n '2,19p' "$0"; exit 2; }
. "$top/packages/VERSIONS"
boot=$(cat "$top/fpga/BOOT_NAME")
mkdir -p "$out"
# With dpkg-deb and mkimage on this machine, run here; otherwise in Task I's container.
if command -v dpkg-deb >/dev/null && command -v mkimage >/dev/null; then
    inner() { sh "$top/packages/inner.sh" "$@"; }
else
    docker build -q -t de25-nano-sdimage "$top/sdimage" >/dev/null
    inner() {
        docker run --rm --user "$(id -u):$(id -g)" -v "$top":"$top" \
            de25-nano-sdimage sh "$top/packages/inner.sh" "$@"
    }
fi

rm -f "$out"/de25-nano-fpga-tools_*.deb
inner tools "$TOOLS_VERSION" "$out"

f=$top/out/fpga/base
if [ ! -f "$f/hps.rpd" ] || [ ! -f "$f/fpga.rbf" ] || [ ! -f "$f/fpga.dtbo" ]; then
    echo "packages/build.sh: no out/fpga/base (Task F): only de25-nano-fpga-tools is made"
    ls -l "$out"
    exit 0
fi
itb=$top/out/u-boot/u-boot.itb
[ -f "$itb" ] || fail "no $itb: build Task B first (u-boot/build.sh)"

deb=$out/de25-nano-boot-${boot}_${BOOT_VERSION}_arm64.deb
if [ -f "$deb" ] && [ -z "${REBUILD_BOOT:-}" ]; then
    echo "packages/build.sh: $deb is kept (see the top of this script)"
else
    rm -f "$out"/de25-nano-boot-"${boot}"_*.deb "$out"/de25-nano-boot-"${boot}"_*.hps.jic
    inner boot "$boot" "$BOOT_VERSION" "$itb" "$f/hps.rpd" "$out"
    # The same HPS image in the form Altera's programmer takes, kept beside the package it
    # belongs to; a release carries it (flash-jtag.md).
    cp "$f/hps.jic" "$out/de25-nano-boot-${boot}_$BOOT_VERSION.hps.jic"
fi

rm -f "$out"/de25-nano-core-base_*.deb
DESCRIPTION="The base core: the PTP clock's pulse-per-second input and output, a UART, two I2C
buses and two SPI masters on the GPIO headers, the fan controller, and HDMI output from a
frame buffer." "$top/packages/mkdeb-core" base "$CORE_BASE_VERSION" "$f" "$out"
ls -l "$out"
