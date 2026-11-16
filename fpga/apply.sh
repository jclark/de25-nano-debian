#!/bin/sh
# Apply this repository's changes to a clean copy of Altera's reference design for the DE25-Nano,
# and then, when CORE_DIR is given, a derived design's additions.
#
# Usage: fpga/apply.sh DESIGN_DIR [CORE_DIR]
#
# DESIGN_DIR is the directory terasic-de25-nano-devkit/baseline-a55 of a checkout of
#   https://github.com/altera-fpga/agilex5-ed-hps-baseline   at the tag in fpga/ALTERA_TAG
# with nothing changed in it. With no CORE_DIR the result is the base design: commit it to the
# branch of the repository named in fpga/README.md, and do not edit that branch by hand.
#
# CORE_DIR is the directory of a design built on the base (fpga/README.md, "Building on this
# design"; fpga/example is one). It may be anywhere, as long as the container can see it.
#
# Run it where Quartus Pro's qsys-script and patch are on the PATH: fpga/q fpga/apply.sh ...
#
# What it does, in order:
#   1. Platform Designer, by script (tcl/): the SoC-to-FPGA connections, passed up the
#      three levels of the design; then the pixel clock and the memory port for HDMI.
#   2. Copies the added files in: the video block, its constraints, its test bench, the timing
#      report scripts, and the base's files for the three hooks (ext/).
#   3. Patches the three files of Altera's that are edited by hand: the top level, the pin and
#      project settings, the timing constraints (top-level.patch).
#   4. The derived design, if any: its Platform Designer scripts, its files for the hooks, its
#      sources, constraints and assignments. Nothing of the base's is edited.
#   5. Checks that the SoC settings are still those recorded in hps-settings.txt: a core image
#      loads only on an HPS image with the same settings.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
[ $# -eq 1 ] || [ $# -eq 2 ] || { sed -n '2,27p' "$0"; exit 2; }
design=$(cd "$1" && pwd)
core=
[ $# -eq 2 ] && core=$(cd "$2" && pwd)
fail() { echo "apply.sh: $*" >&2; exit 1; }

for f in top.qpf baseline_a55.sv baseline_a55.qsf baseline_top.qsys hps_subsys.qsys shell_subsys.qsys; do
    [ -f "$design/$f" ] || fail "$design does not look like the design directory: no $f"
done
[ ! -e "$design/src/hdmi_scanout.sv" ] || fail "$design already has the changes applied"
command -v qsys-script >/dev/null || fail "qsys-script is not on the PATH: run this with fpga/q"
command -v patch >/dev/null || fail "patch is not on the PATH"
if [ -n "$core" ]; then
    [ -f "$core/core.conf" ] || fail "no core.conf in $core"
    NAME=
    # shellcheck disable=SC1091
    . "$core/core.conf"
    case $NAME in ''|base|*[!a-z0-9-]*) fail "core.conf: NAME must be lower-case letters, digits and hyphens, and not base" ;; esac
fi

cd "$design"
qs() {   # qs SYSTEM.qsys SCRIPT [ARGS...]
    sys=$1; script=$2; shift 2
    echo "== $sys: $script $*"
    qsys-script --quartus-project=top.qpf --system-file="$sys" \
        --search-path='custom_ip/**/*,$' --script="$script" "$@"
}

# 1. Platform Designer.
# The SoC-to-FPGA connections: EMAC0 PTP, UART0, I2C0, I2C_EMAC0, SPI master 0, I2C_EMAC1,
# SPI master 1, EMAC1 and the timestamp hubs' counter input. They are part of the HPS image,
# so changing them means writing the flash again.
qs hps_subsys.qsys   "$here/tcl/hps_connections.tcl"
qs hps_subsys.qsys   "$here/tcl/export_connections.tcl" u_agilex_hps
qs shell_subsys.qsys "$here/tcl/export_connections.tcl" u_hps_subsys
qs baseline_top.qsys "$here/tcl/export_connections.tcl" u_shell_subsys
# HDMI: a 148.5 MHz pixel clock, and a port on system RAM for the video block.
qs baseline_top.qsys "$here/tcl/hdmi_base.tcl"
qs baseline_top.qsys "$here/tcl/hdmi_f2s.tcl"

# 2. The added files.
mkdir -p src sim ext
cp "$here/src/hdmi_scanout.sv" src/
cp "$here/constraints/hdmi_io.sdc" .
cp "$here/sim/tb_hdmi_scanout.sv" "$here/sim/run.sh" "$here/sim/Dockerfile" sim/
cp "$here/reports/io.tcl" "$here/reports/fp.tcl" "$here/reports/ds.tcl" .
cp "$here/ext/ports.svh" "$here/ext/connections.svh" "$here/ext/logic.svh" ext/

# 3. The hand-edited files.
# The patch is against the files as the scripts above leave them (they add lines to the .qsf).
patch -p1 --no-backup-if-mismatch < "$here/top-level.patch"
grep -q 'hdmi_scanout u_hdmi_scanout' baseline_a55.sv || fail "top-level.patch did not apply"

# Build outputs written to out/ stay out of git.
grep -qx 'out/' .gitignore 2>/dev/null || printf '\n# Build outputs\nout/\n' >> .gitignore

# 4. The derived design.
if [ -n "$core" ]; then
    echo "== derived design $NAME, from $core"
    # platform-designer.txt: one qsys-script run a line, "SYSTEM.qsys SCRIPT [ARGS...]", the
    # script's path relative to CORE_DIR.
    if [ -f "$core/platform-designer.txt" ]; then
        while read -r sys script args; do
            case $sys in ''|'#'*) continue ;; esac
            [ -f "$sys" ] || fail "platform-designer.txt: no $sys in the design"
            [ -f "$core/$script" ] || fail "platform-designer.txt: no $script in $core"
            # shellcheck disable=SC2086
            qs "$sys" "$core/$script" $args </dev/null
        done < "$core/platform-designer.txt"
    fi
    # The hooks: a file the derived design has replaces the base's.
    for f in ports.svh connections.svh logic.svh; do
        [ ! -f "$core/ext/$f" ] || cp "$core/ext/$f" ext/
    done
    [ ! -d "$core/src" ] || cp -r "$core/src/." src/
    for f in "$core"/constraints/*.sdc; do
        [ -f "$f" ] || continue
        [ ! -e "${f##*/}" ] || fail "constraints/${f##*/} has the name of a file of the base design"
        cp "$f" .
    done
    # assignments.qsf: pins, source files (SYSTEMVERILOG_FILE src/...), constraint files
    # (SDC_FILE ...), anything else for the project. Added after the base's.
    if [ -f "$core/assignments.qsf" ]; then
        { printf '\n# Derived design %s\n' "$NAME"; cat "$core/assignments.qsf"; } >> baseline_a55.qsf
    fi
    echo "$NAME" > core-name.txt
fi

# 5. The SoC settings. A design with other settings would need its own HPS image.
{
    echo "QUARTUS $(quartus_sh --version | sed -n 's/^Version //p')"
    qs hps_subsys.qsys "$here/tcl/hps_settings.tcl" | grep '^HPS '
} > hps-settings.txt
if ! cmp -s hps-settings.txt "$here/hps-settings.txt"; then
    diff "$here/hps-settings.txt" hps-settings.txt | head -n 40 >&2 || true
    fail "the SoC settings or the Quartus version differ from fpga/hps-settings.txt (above:
< recorded, > this design). A core image built from this would not load on the HPS image of
de25-nano-boot-$(cat "$here/BOOT_NAME"). In the base, a change of settings is a new HPS image:
see fpga/README.md, \"The SoC settings\". A derived design must not change them."
fi

echo "apply.sh: done. Next: generate and compile (fpga/README.md)."
