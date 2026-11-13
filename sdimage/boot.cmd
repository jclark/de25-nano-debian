# U-Boot script for the DE25-Nano, kept as boot.scr on the FAT partition of the SD card.
#
# U-Boot's stock boot command scans the bootable partitions for a boot menu
# (extlinux/extlinux.conf) and for a script. It finds this script first (the FAT partition is
# partition 1 and has no menu), runs it, and goes on to the menu on the root partition.
# U-Boot prints "SCRIPT FAILED: continuing..." when a script returns; that is its normal wording.
#
# Wrap it after any change:
#   mkimage -A arm64 -T script -C none -n "DE25-Nano boot script" -d boot.cmd boot.scr

# The device tree: the boot menu's "fdtdir" line names the kernel package's device tree
# directory, and U-Boot loads this file from it.
setenv fdtfile intel/socfpga_agilex5_de25_nano.dtb

# Overlays named on the boot menu's "fdtoverlays" line are applied only if this variable, the
# address they are loaded to, is set. It is set below, when the FPGA design has loaded.
setenv fdtoverlay_addr_r

# The kernel in a Debian kernel package is compressed. U-Boot unpacks it to this address
# before starting it; the size is the largest compressed kernel it will accept.
setenv kernel_comp_addr_r 0x90000000
setenv kernel_comp_size 0x2000000

# The FPGA design, fpga.rbf, beside this script. It is there only after "de25-fpga enable" has
# been run on the board, which is done once the flash holds the matching first-stage image.
# It must not be there on a board with the factory flash contents: such a board refuses it,
# the boot carries on without the design and its device tree overlay, and the board then hangs
# at its next restart until it is power cycled.
if test -e mmc 0:1 fpga.rbf; then
    if load mmc 0:1 ${kernel_addr_r} fpga.rbf && fpga load 0 ${kernel_addr_r} ${filesize}; then
        bridge enable
        setenv fdtoverlay_addr_r 0x87000000
    else
        echo "*** fpga.rbf was not accepted: booting without the FPGA design ***"
        echo "*** The next restart will hang. Run: sudo de25-fpga disable, then power cycle the board ***"
    fi
else
    echo "No fpga.rbf on the card: booting without the FPGA design"
fi
