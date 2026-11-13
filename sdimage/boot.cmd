# U-Boot script for the DE25-Nano, kept as boot.scr on the FAT partition of the SD card.
#
# U-Boot's stock boot command scans the bootable partitions for a boot menu
# (extlinux/extlinux.conf) and for a script. It finds this script first (the FAT partition is
# partition 1 and has no menu), runs it, and goes on to the menu on the root partition.
# U-Boot prints "SCRIPT FAILED: continuing..." when a script returns; that is its normal wording.
#
# Wrap it after any change:
#   mkimage -A arm64 -T script -C none -n "DE25-Nano boot script" -d boot.cmd boot.scr

# The device tree the menu's "fdtdir" line looks for, and where "fdtoverlays" loads overlays.
setenv fdtfile socfpga_agilex5_de25_nano.dtb
setenv fdtoverlay_addr_r 0x87000000

# Stage 2: load the FPGA design if there is one beside this script. This works only when the
# flash holds the matching first-stage image. The device tree overlay that goes with the design
# is named on the "fdtoverlays" line of the boot menu.
if test -e mmc 0:1 fpga.rbf; then
    if load mmc 0:1 ${kernel_addr_r} fpga.rbf && fpga load 0 ${kernel_addr_r} ${filesize}; then
        bridge enable
    else
        echo "*** FPGA design fpga.rbf did not load ***"
    fi
else
    echo "No fpga.rbf on the card: FPGA design left as it is"
fi
