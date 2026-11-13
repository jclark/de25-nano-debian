#!/bin/sh
# Simulate the video block, src/hdmi_scanout.sv, with Icarus Verilog in a small container
# (sim/Dockerfile). About a minute. It needs no Quartus and no board.
#
# Usage: [IVFLAGS=-Ptb.FIFO_AW=7] [TERASIC_HDMI=DIR] fpga/sim/run.sh [PLUSARGS...]
#   PLUSARGS  +frames=3 +seed=3 +stress=1 +stall=600 +bstall=100 (see the top of tb_hdmi_scanout.sv)
#   TERASIC_HDMI  optional: the directory Demonstration/FPGA/HDMI_TX/V_HDMI of Terasic's resource
#             package for the board (their site asks for registration). With it, the test bench
#             also compares this block's syncs and data enable, clock by clock, with Terasic's
#             vga_generator.v. Without it that one comparison is skipped; the checks against
#             CEA-861 and of every pixel are made either way.
#
# A good run ends with:  RESULT: raster errors 0, memory errors 0, wrong pixels 0, ...
set -eu
here=$(cd "$(dirname "$0")" && pwd); top=$(dirname "$here")
docker build -q -t de25-nano-sim "$here" >/dev/null
terasic=; def=; mount=
if [ -n "${TERASIC_HDMI:-}" ]; then
    [ -f "$TERASIC_HDMI/vga_generator.v" ] || { echo "no vga_generator.v in $TERASIC_HDMI" >&2; exit 1; }
    mount="-v $TERASIC_HDMI:/terasic:ro"; terasic=/terasic/vga_generator.v; def=-DTERASIC
fi
# shellcheck disable=SC2086
exec docker run --rm --user "$(id -u):$(id -g)" -v "$top":/w $mount -w /w/sim \
    -e IVFLAGS="${IVFLAGS:-}" -e TB_DEF="$def" -e TB_EXTRA="$terasic" de25-nano-sim sh -c \
    'iverilog -g2012 ${IVFLAGS} ${TB_DEF} -o /tmp/tb.vvp tb_hdmi_scanout.sv ../src/hdmi_scanout.sv ${TB_EXTRA} && vvp -n /tmp/tb.vvp "$@"' sh "$@"
