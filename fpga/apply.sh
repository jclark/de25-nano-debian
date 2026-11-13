#!/bin/sh
# Apply this repository's changes to a clean copy of Altera's reference design for the DE25-Nano.
#
# Usage: fpga/apply.sh DESIGN_DIR
#
# DESIGN_DIR is the directory terasic-de25-nano-devkit/baseline-a55 of a checkout of
#   https://github.com/altera-fpga/agilex5-ed-hps-baseline   at the tag in fpga/ALTERA_TAG
# with nothing changed in it. The result is the design that gets built: commit it to the branch
# of the repository named in fpga/README.md, and do not edit that branch by hand.
#
# Run it where Quartus Pro's qsys-script and patch are on the PATH (the Quartus container, fpga/q).
#
# What it does, in order:
#   1. Platform Designer, by script (tcl/): the SoC-to-FPGA connections, passed up the
#      three levels of the design; then the pixel clock and the memory port for HDMI.
#   2. Copies the added files in: the video block, its constraints, its test bench, the timing
#      report scripts.
#   3. Patches the three files of Altera's that are edited by hand: the top level, the pin and
#      project settings, the timing constraints (top-level.patch).
set -eu
here=$(cd "$(dirname "$0")" && pwd)
[ $# -eq 1 ] || { sed -n '2,19p' "$0"; exit 2; }
design=$(cd "$1" && pwd)
fail() { echo "apply.sh: $*" >&2; exit 1; }

for f in top.qpf baseline_a55.sv baseline_a55.qsf baseline_top.qsys hps_subsys.qsys shell_subsys.qsys; do
    [ -f "$design/$f" ] || fail "$design does not look like the design directory: no $f"
done
[ ! -e "$design/src/hdmi_scanout.sv" ] || fail "$design already has the changes applied"
command -v qsys-script >/dev/null || fail "qsys-script is not on the PATH: run this in the Quartus container"
command -v patch >/dev/null || fail "patch is not on the PATH"

cd "$design"
qs() {   # qs SYSTEM.qsys SCRIPT [ARGS...]
    sys=$1; script=$2; shift 2
    echo "== $sys: $script $*"
    qsys-script --quartus-project=top.qpf --system-file="$sys" \
        --search-path='custom_ip/**/*,$' --script="$here/tcl/$script" "$@"
}

# 1. Platform Designer.
# The SoC-to-FPGA connections: EMAC0 PTP, UART0, I2C0, I2C_EMAC0, SPI master 0. They are
# part of the first-stage image, so changing them means writing the flash again.
qs hps_subsys.qsys   hps_connections.tcl
qs hps_subsys.qsys   export_connections.tcl u_agilex_hps
qs shell_subsys.qsys export_connections.tcl u_hps_subsys
qs baseline_top.qsys export_connections.tcl u_shell_subsys
# HDMI: a 148.5 MHz pixel clock, and a port on system RAM for the video block.
qs baseline_top.qsys hdmi_base.tcl
qs baseline_top.qsys hdmi_f2s.tcl

# 2. The added files.
mkdir -p src sim
cp "$here/src/hdmi_scanout.sv" src/
cp "$here/constraints/hdmi_io.sdc" .
cp "$here/sim/tb_hdmi_scanout.sv" "$here/sim/run.sh" "$here/sim/Dockerfile" sim/
cp "$here/reports/io.tcl" "$here/reports/fp.tcl" "$here/reports/ds.tcl" .

# 3. The hand-edited files.
# The patch is against the files as the scripts above leave them (they add lines to the .qsf).
patch -p1 --no-backup-if-mismatch < "$here/top-level.patch"
grep -q 'hdmi_scanout u_hdmi_scanout' baseline_a55.sv || fail "top-level.patch did not apply"

# Build outputs written to out/ stay out of git.
grep -qx 'out/' .gitignore 2>/dev/null || printf '\n# Build outputs\nout/\n' >> .gitignore

echo "apply.sh: done. Next: generate and compile (fpga/README.md)."
