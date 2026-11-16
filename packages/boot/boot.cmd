# U-Boot script for the DE25-Nano, kept as boot.scr on the FAT partition of the SD card.
#
# U-Boot's stock boot command scans the bootable partitions for a boot menu
# (extlinux/extlinux.conf) and for a script. It finds this script first (the FAT partition is
# partition 1 and has no menu), runs it, and goes on to the menu on the root partition.
# U-Boot prints "SCRIPT FAILED: continuing..." when a script returns; that is its normal wording.
# No apostrophes in the commands below, also not inside double quotes: this U-Boot's shell
# answers "syntax error" to the whole script.
#
# Wrap it after any change:
#   mkimage -A arm64 -T script -C none -n "DE25-Nano boot script" -d boot.cmd boot.scr

# The device tree: the boot menu's "fdtdir" line names the kernel package's device tree
# directory, and U-Boot loads this file from it.
setenv fdtfile intel/socfpga_agilex5_de25_nano.dtb

# Overlays named on the boot menu's "fdtoverlays" line are applied only if this variable, the
# address they are loaded to, is set. It is set below, when the core image has loaded.
setenv fdtoverlay_addr_r

# The kernel in a Debian kernel package is compressed. U-Boot unpacks it to this address
# before starting it; the size is the largest compressed kernel it will accept.
setenv kernel_comp_addr_r 0x90000000
setenv kernel_comp_size 0x2000000

# Whether the chip's Secure Device Manager (SDM) keeps the QSPI flash to itself. It does with
# the factory flash contents; with the HPS image built here it hands the flash to the SoC,
# and the SPL records the flash controller's clock rate, which U-Boot puts in
# qspi_clock. No rate means the SDM kept the flash.
setenv flash_sdm no
if test "${qspi_clock}" = "<0x00000000>"; then
    setenv flash_sdm yes
fi

# A flash write asked for with "de25-flash write": the file write-on-boot.rpd beside this
# script holds the new flash contents, and write-on-boot.txt their crc32. It is done here,
# through the SDM, on a board whose flash the SDM keeps. The LED wired to the SoC (HPS_LED)
# shows how it is going:
#   one second on, one second off   working: leave the power alone
#   steady on                       written and verified: unplug the power
#   four times a second             failed
# Nothing is erased until the new contents have been checked against their crc32 and the
# contents the flash had before are safe on the card: they are saved beside this script as
# saved-<crc32>.rpd and read back from the card.
# Memory used: 0x90000000 the flash as it was; 0x92000000 the new contents; 0x94000000 what
# is read back from the card or the flash; 0x98000000 the small text files.
if test "${flash_sdm}" = yes && test -e mmc 0:1 write-on-boot.rpd; then
    led hps_led0 blink 2000
    echo "*** Flash write requested (de25-flash write). Do not unplug the power. ***"
    setenv flash_ok yes

    setenv flash_step "loading write-on-boot.rpd and write-on-boot.txt"
    echo "${flash_step}"
    setenv flash_new_crc
    load mmc 0:1 0x98000000 write-on-boot.txt || setenv flash_ok no
    if test "${flash_ok}" = yes; then
        env import -t 0x98000000 ${filesize} flash_new_crc || setenv flash_ok no
    fi
    if test "${flash_ok}" = yes; then
        load mmc 0:1 0x92000000 write-on-boot.rpd || setenv flash_ok no
        setenv flash_size ${filesize}
    fi
    if test "${flash_ok}" = yes; then
        setenv flash_step "checking write-on-boot.rpd"
        # Its size: a multiple of 4, more than 0 and no more than the flash, 0x1000000.
        setexpr flash_chk ${flash_size} % 4
        test "${flash_chk}" = 0 || setenv flash_ok no
        setexpr flash_chk ${flash_size} - 1
        setexpr flash_chk ${flash_chk} / 1000000
        test "${flash_chk}" = 0 || setenv flash_ok no
    fi
    if test "${flash_ok}" = yes; then
        hash crc32 0x92000000 ${flash_size} flash_chk || setenv flash_ok no
    fi
    if test "${flash_ok}" = yes; then
        test "${flash_chk}" = "${flash_new_crc}" || setenv flash_ok no
    fi

    # The request is used up before the flash is touched: whatever happens next, the write
    # is not tried again by itself.
    if fatrm mmc 0:1 write-on-boot.rpd; then
        fatrm mmc 0:1 write-on-boot.txt
    else
        if test "${flash_ok}" = yes; then
            setenv flash_step "removing write-on-boot.rpd"
        fi
        setenv flash_ok no
    fi

    if test "${flash_ok}" = yes; then
        setenv flash_step "reading the present flash contents"
        echo "${flash_step} (about 75 s)"
        sdmflash read 0 0x90000000 0x1000000 || setenv flash_ok no
    fi
    if test "${flash_ok}" = yes; then
        hash crc32 0x90000000 0x1000000 flash_crc || setenv flash_ok no
    fi
    if test "${flash_ok}" = yes; then
        setenv flash_step "saving the present flash contents as saved-${flash_crc}.rpd"
        echo "${flash_step}"
        setenv filesize
        size mmc 0:1 saved-${flash_crc}.rpd
        if test "${filesize}" = 1000000; then
            echo "saved-${flash_crc}.rpd is already on the card"
        else
            fatwrite mmc 0:1 0x90000000 saved-${flash_crc}.rpd 0x1000000 || setenv flash_ok no
        fi
    fi
    if test "${flash_ok}" = yes; then
        setenv flash_step "checking saved-${flash_crc}.rpd on the card"
        echo "${flash_step}"
        setenv filesize
        load mmc 0:1 0x94000000 saved-${flash_crc}.rpd || setenv flash_ok no
        test "${filesize}" = 1000000 || setenv flash_ok no
    fi
    if test "${flash_ok}" = yes; then
        hash crc32 0x94000000 0x1000000 flash_chk || setenv flash_ok no
    fi
    if test "${flash_ok}" = yes; then
        test "${flash_chk}" = "${flash_crc}" || setenv flash_ok no
    fi
    if test "${flash_ok}" = yes; then
        setenv flash_step "erasing the flash"
        echo "${flash_step} (about 8 s)"
        sdmflash erase 0 0x1000000 || setenv flash_ok no
    fi
    if test "${flash_ok}" = yes; then
        setenv flash_step "writing the flash"
        echo "${flash_step}"
        sdmflash write 0 0x92000000 ${flash_size} || setenv flash_ok no
    fi
    if test "${flash_ok}" = yes; then
        setenv flash_step "comparing the flash with what was written"
        echo "${flash_step}"
        sdmflash read 0 0x94000000 ${flash_size} || setenv flash_ok no
    fi
    if test "${flash_ok}" = yes; then
        cmp.b 0x92000000 0x94000000 ${flash_size} || setenv flash_ok no
    fi

    if test "${flash_ok}" = yes; then
        led hps_led0 on
        echo "*** The flash is written and verified. ***"
        echo "*** Unplug the power, then plug it in again. ***"
    else
        # A one-line text file for "de25-flash status": failed_while=<the step>. The export
        # ends with a zero byte, which is left out.
        setenv failed_while "${flash_step}"
        env export -t 0x98000000 failed_while
        setexpr flash_chk ${filesize} - 1
        fatwrite mmc 0:1 0x98000000 write-on-boot-failed.txt ${flash_chk}
        led hps_led0 blink 250
        echo "*** The flash write FAILED while ${flash_step}. ***"
        echo "*** After a power cycle, sudo de25-flash status says what the card recorded. ***"
    fi
    # Stay here: what the chip runs now and what the flash holds may no longer belong together.
    while true; do
        sleep 1
    done
fi

# The core image, fpga.rbf, beside this script. "de25-fpga select" puts it there. It is
# loaded only when the SDM has handed the flash over, that is, when the flash holds the
# HPS image the core was built for: a board with the factory flash contents refuses the
# core and then hangs at its next restart until it is power cycled.
if test -e mmc 0:1 fpga.rbf; then
    if test "${flash_sdm}" = yes; then
        echo "fpga.rbf is on the card but the flash is not written yet: booting without a core image"
    elif load mmc 0:1 ${kernel_addr_r} fpga.rbf && fpga load 0 ${kernel_addr_r} ${filesize}; then
        bridge enable
        setenv fdtoverlay_addr_r 0x87000000
    else
        echo "*** fpga.rbf was not accepted: booting without a core image ***"
        echo "*** The next restart will hang. Run: sudo de25-fpga disable, then power cycle the board ***"
    fi
else
    echo "No fpga.rbf on the card: booting without a core image"
fi
