#!/bin/sh
# Build the device tree overlay for the FPGA design: OUT (default out/fpga/fpga.dtbo at the
# top of the repository).
#
# The frame buffer's address and size are taken from src/hdmi_scanout.sv, the logic that reads
# it, so the overlay cannot disagree with the design.
#
# Needs dtc (Debian/Ubuntu package device-tree-compiler), sed and a POSIX shell. fpga/build.sh
# runs it in the Quartus container, which has dtc.
# Usage, from anywhere:  fpga/overlay/build.sh [OUT]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
top=$(dirname "$here")
sv=$top/src/hdmi_scanout.sv
out=${1:-$(dirname "$top")/out/fpga/fpga.dtbo}

fail() { echo "overlay/build.sh: $*" >&2; exit 1; }

# One value from the Verilog: the text after "NAME =" up to the next , ; or space.
sv_value() {
    v=$(sed -n "s/.*\\<$1[[:space:]]*=[[:space:]]*\\([^,; ]*\\).*/\\1/p" "$sv" | head -n 1)
    [ -n "$v" ] || fail "$1 not found in $sv"
    echo "$v"
}

# FB_BASE is written as 32'hBF00_0000.
base_sv=$(sv_value FB_BASE)
case $base_sv in
    "32'h"*) base_hex=$(echo "${base_sv#32\'h}" | tr -d _ | tr A-F a-f) ;;
    *) fail "FB_BASE in $sv is '$base_sv', expected the form 32'hXXXX_XXXX" ;;
esac
width=$(sv_value H_ACTIVE)
height=$(sv_value V_ACTIVE)
case $width$height in *[!0-9]*) fail "H_ACTIVE or V_ACTIVE is not a plain number" ;; esac

# The top level must use the module's default address, or this file is wrong. The top level's
# instance of the module is in top-level.patch.
if grep -q 'hdmi_scanout[[:space:]]*#' "$top/top-level.patch"; then
    fail "the top level overrides hdmi_scanout's parameters; teach this script to read them"
fi

bytes_per_pixel=4                               # x8r8g8b8, fixed in hdmi_scanout.sv
stride=$((width * bytes_per_pixel))
size=$((stride * height))
mb2=$((2 * 1024 * 1024))
reserved=$(( (size + mb2 - 1) / mb2 * mb2 ))    # whole 2 MiB blocks

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
sed -e "s/@FB_UNIT@/$base_hex/g" \
    -e "s/@FB_BASE@/0x$base_hex/g" \
    -e "s/@FB_SIZE@/$(printf '0x%x' "$size")/g" \
    -e "s/@FB_RESERVED@/$(printf '0x%x' "$reserved")/g" \
    -e "s/@FB_WIDTH@/$width/g" \
    -e "s/@FB_HEIGHT@/$height/g" \
    -e "s/@FB_STRIDE@/$stride/g" \
    "$here/de25-nano-fabric.dtso.in" > "$tmp"
if grep -n '@[A-Z_]*@' "$tmp" >&2; then fail "a name in the template was not filled in"; fi

mkdir -p "$(dirname "$out")"
# The two checks switched off cannot work in an overlay: dtc does not see the
# cell sizes of the nodes the fragments are applied to.
dtc -@ -W no-ranges_format -W no-avoid_default_addr_size -I dts -O dtb -o "$out" "$tmp"
echo "$out: frame buffer ${width}x${height} at 0x$base_hex, $size bytes, $reserved reserved"
