#!/bin/sh
# Build Task F: the FPGA design for the DE25-Nano. See fpga/README.md.
#
# Usage: fpga/build.sh
# Output: out/fpga/fpga.rbf             the fabric, for the SD card
#         out/fpga/fpga.dtbo            its device tree overlay, for the SD card
#         out/fpga/de25-nano.hps.jic    the first-stage image, for the flash
# Needs: Docker, git, network access; out/u-boot/u-boot-spl-dtb.hex from Task B (for the
#        last step only). The first run pulls the Quartus image (17.5 GiB).
#
# The design is Altera's reference design at the tag in fpga/ALTERA_TAG with this repository's changes
# applied by fpga/apply.sh. It is fetched and prepared once in
# work/agilex5-ed-hps-baseline. To start again from clean, delete that directory.
# To build from a repository that already holds the applied design (jclark/agilex5-ed-hps-baseline), set
# DESIGN_REPO and DESIGN_REF.
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
work=$top/work; out=$top/out/fpga
q=$top/fpga/q
fail() { echo "fpga/build.sh: $*" >&2; exit 1; }
mkdir -p "$work" "$out"

DESIGN_REPO=${DESIGN_REPO:-https://github.com/altera-fpga/agilex5-ed-hps-baseline}
DESIGN_REF=${DESIGN_REF:-$(cat "$top/fpga/ALTERA_TAG")}
src=$work/agilex5-ed-hps-baseline
design=$src/terasic-de25-nano-devkit/baseline-a55

# 1. The design's source: Altera's, with the changes applied.
[ -d "$src/.git" ] || git clone --depth 1 -b "$DESIGN_REF" "$DESIGN_REPO" "$src"
[ -f "$design/top.qpf" ] || fail "no design in $design"
if [ ! -e "$design/src/hdmi_scanout.sv" ]; then
    (cd "$design" && "$q" "$top/fpga/apply.sh" .)
fi

# 2. Compile. Altera's Makefile generates the Platform Designer output, builds the firmware of
# the design's self-test processor, and runs synthesis, fitter, timing analysis and assembler.
# It stops with an error if timing is not met. It does not notice later source changes: after
# changing sources, start again from clean (see above).
(cd "$design" && "$q" make build)
sof=$design/output_files/baseline_a55.sof
[ -f "$sof" ] || fail "the compile did not produce $sof"

# 3. Overlay: independent of the compile; it reads the video block's source.
(cd "$top" && "$q" "$top/fpga/overlay/build.sh" "$out/fpga.dtbo")

# 4. Combine with the first-stage loader from Task B. One command gives both files:
#    de25-nano.hps.jic   first stage (the SoC's configuration and the loader), for the flash
#    de25-nano.core.rbf  the fabric, loaded by U-Boot from the SD card
# flash_loader names the FPGA as the programmer of Quartus 26.1.1 identifies this board's.
spl=$top/out/u-boot/u-boot-spl-dtb.hex
[ -f "$spl" ] || fail "no $spl: build Task B first (u-boot/build.sh)"
(cd "$design" && mkdir -p out && "$q" quartus_pfg -c output_files/baseline_a55.sof out/de25-nano.jic \
    -o device=MT25QU128 -o flash_loader=A5EB013BB23BCS -o hps_path="$spl" -o mode=ASX4 -o hps=1)
cp "$design/out/de25-nano.core.rbf" "$out/fpga.rbf"
cp "$design/out/de25-nano.hps.jic" "$out/de25-nano.hps.jic"
ls -l "$out"
