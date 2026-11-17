#!/bin/sh
# Build Task F: the FPGA design for the DE25-Nano, or a design built on it. See fpga/README.md.
#
# Usage: fpga/build.sh              the base design
#        fpga/build.sh CORE_DIR     a derived design (fpga/README.md, "Building on this
#                                   design"); CORE_DIR may be outside this repository
#
# Output, in out/fpga/<name>/ (<name> is base, or NAME from CORE_DIR/core.conf):
#         fpga.rbf     the core image (phase 2), which U-Boot loads from the SD card
#         fpga.dtbo    its device tree overlay
#   and for the base design only:
#         hps.rpd      the HPS image (phase 1), for the flash: raw bytes, as U-Boot and
#                      Linux write it
#         hps.jic      the same, as Altera's programmer writes it over JTAG
# A derived design has no HPS image of its own: its core image loads on the base's.
#
# Needs: Quartus Pro of the version in fpga/QUARTUS_VERSION (fpga/q finds it; fpga/README.md,
#        "Tools to download"), git, make, cmake, patch, dtc, network access;
#        out/u-boot/u-boot-spl-dtb.hex from Task B (for the last step only).
#
# Settings, as environment variables, all optional:
#   OUT          where the results go (default out/fpga/<name> in this repository)
#   WORK         where the design is fetched and built (default work/fpga/<name>)
#   DESIGN_REPO, DESIGN_REF
#                build the base from a repository that already holds the applied design
#                (jclark/agilex5-ed-hps-baseline) instead of applying the changes
#
# The design is Altera's reference design at the tag in fpga/ALTERA_TAG with this
# repository's changes applied by fpga/apply.sh, and then the derived design's. It is fetched
# and prepared once in WORK. To start again from clean, delete that directory.
set -eu
top=$(cd "$(dirname "$0")/.." && pwd)
q=$top/fpga/q
fail() { echo "fpga/build.sh: $*" >&2; exit 1; }
[ $# -le 1 ] || { sed -n '2,29p' "$0"; exit 2; }

name=base; core=
if [ $# -eq 1 ]; then
    core=$(cd "$1" && pwd) || fail "no directory $1"
    [ -f "$core/core.conf" ] || fail "no core.conf in $core"
    NAME=
    # shellcheck disable=SC1091
    . "$core/core.conf"
    [ -n "$NAME" ] || fail "core.conf does not set NAME"
    name=$NAME
fi
boot=$(cat "$top/fpga/BOOT_NAME")
work=${WORK:-$top/work/fpga/$name}; out=${OUT:-$top/out/fpga/$name}
mkdir -p "$work" "$out"
work=$(cd "$work" && pwd); out=$(cd "$out" && pwd)
# The container sees this repository; it must also see these.
DE25_Q_MOUNTS="$work $out $core"
export DE25_Q_MOUNTS

for t in git make cmake patch dtc; do
    command -v $t >/dev/null || fail "$t is not installed (fpga/README.md, \"Tools to download\")"
done
applied=${DESIGN_REPO:+yes}
DESIGN_REPO=${DESIGN_REPO:-https://github.com/altera-fpga/agilex5-ed-hps-baseline}
DESIGN_REF=${DESIGN_REF:-$(cat "$top/fpga/ALTERA_TAG")}
[ -z "$applied" ] || [ -z "$core" ] || fail "DESIGN_REPO is for the base design only"
src=$work/agilex5-ed-hps-baseline
design=$src/terasic-de25-nano-devkit/baseline-a55

# 1. The design's source: Altera's, with the changes applied.
[ -d "$src/.git" ] || git clone --depth 1 -b "$DESIGN_REF" "$DESIGN_REPO" "$src"
[ -f "$design/top.qpf" ] || fail "no design in $design"
if [ ! -e "$design/src/hdmi_scanout.sv" ]; then
    [ -z "$applied" ] || fail "$DESIGN_REPO at $DESIGN_REF does not hold the applied design"
    # shellcheck disable=SC2086
    (cd "$design" && "$q" "$top/fpga/apply.sh" . $core)
fi
# apply.sh ends by checking the SoC settings, and only then leaves apply-complete.txt. A
# design it gave up on part-way, or one from a repository of applied designs made for other
# settings, is not compiled: its core image would not load on the HPS image it is named for.
[ -f "$design/apply-complete.txt" ] ||
    fail "the changes were not applied completely to $design (apply.sh failed, or the design is from before this check): see the log, then delete $work"
cmp -s "$design/hps-settings.txt" "$top/fpga/hps-settings.txt" ||
    fail "the SoC settings of $design are not those of fpga/hps-settings.txt: delete $work"
have=base; [ ! -f "$design/core-name.txt" ] || have=$(cat "$design/core-name.txt")
[ "$have" = "$name" ] || fail "$design holds the design $have, not $name: delete $work"

# 2. Compile. Altera's Makefile generates the Platform Designer output, builds the firmware of
# the design's self-test processor, and runs synthesis, fitter, timing analysis and assembler.
# It stops with an error if timing is not met. It does not notice later source changes: after
# changing sources, start again from clean (see above).
(cd "$design" && "$q" make build)
sof=$design/output_files/baseline_a55.sof
[ -f "$sof" ] || fail "the compile did not produce $sof"

# 3. Overlay: independent of the compile. The base's, which reads the video block's source,
# then the derived design's fragments, then the names of the core and of the boot package
# whose HPS image it loads on.
# shellcheck disable=SC2046
(cd "$top" && "$top/fpga/overlay/build.sh" "$out/fpga.dtbo" "$name" "$boot" \
    $([ -z "$core" ] || ls "$core"/overlay/*.dtso 2>/dev/null))

# 4. Split the compiled design, with the SPL from Task B. One command gives the files:
#    de25-nano.hps.jic   the HPS image (the SoC's configuration and the SPL), for the flash,
#                        in the form Altera's programmer writes over JTAG
#    de25-nano.rpd       the same flash contents as raw bytes (Raw Programming Data), from the
#                        start of the flash to the end of the data; bitswap=on gives the
#                        bytes as the flash holds them
#    de25-nano.core.rbf  the core image, loaded by U-Boot from the SD card
# flash_loader names this board's FPGA as Quartus's programmer identifies it.
spl=$top/out/u-boot/u-boot-spl-dtb.hex
[ -f "$spl" ] || fail "no $spl: build Task B first (u-boot/build.sh)"
(cd "$design" && mkdir -p out && "$q" quartus_pfg -c output_files/baseline_a55.sof out/de25-nano.jic out/de25-nano.rpd \
    -o device=MT25QU128 -o flash_loader=A5EB013BB23BCS -o hps_path="$spl" -o mode=ASX4 -o hps=1 \
    -o bitswap=on)
cp "$design/out/de25-nano.core.rbf" "$out/fpga.rbf"
echo "$boot" > "$out/boot-name"
if [ -z "$core" ]; then
    cp "$design/out/de25-nano.hps.jic" "$out/hps.jic"
    cp "$design/out/de25-nano.rpd" "$out/hps.rpd"
    # U-Boot writes the flash in 4-byte words.
    [ $(( $(stat -c %s "$out/hps.rpd") % 4 )) -eq 0 ] || fail "the size of hps.rpd is not a multiple of 4"
fi
ls -l "$out"
