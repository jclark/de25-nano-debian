# Shared by de25-fpga and de25-flash; installed as /usr/lib/de25-nano/common.sh.
#
# Where things are:
#   /usr/lib/de25-nano/boot/<boot>/   a boot package (de25-nano-boot-<boot>): hps.rpd, the HPS
#                                     image for the flash, with the u-boot.itb and boot.scr
#                                     that go with it
#   /usr/lib/de25-nano/core/<core>/   a core package (de25-nano-core-<core>): fpga.rbf, the core
#                                     image; fpga.dtbo, its device tree overlay; boot, the name
#                                     of the boot package whose HPS image it loads on
#   /boot/firmware                    the FAT partition: what U-Boot uses (u-boot.itb, boot.scr,
#                                     fpga.rbf), and the files of a flash write
#   /boot/dtbo/fpga.dtbo              the selected core's overlay, where the boot menu finds it
#   /dev/mtd0                         the flash, when the chip has handed it to the SoC
#
# DE25_TEST_ROOT puts all of these under another directory, for testing off the board.
root=${DE25_TEST_ROOT:-}
lib=$root/usr/lib/de25-nano
fat=$root/boot/firmware
dtbo=$root/boot/dtbo
mtd=$root/dev/mtd0
chosen=$root/proc/device-tree/chosen
request=$fat/write-on-boot.rpd
request_txt=$fat/write-on-boot.txt
failed=$fat/write-on-boot-failed.txt
selected_txt=$fat/fpga-core.txt
flash_bytes=16777216
prog=${0##*/}
force=no

fail() { echo "$prog: $*" >&2; exit 1; }
need_root() { [ -n "$root" ] || [ "$(id -u)" = 0 ] || fail "run it as root (sudo $prog $*)"; }
fat_mounted() { [ -n "$root" ] || mountpoint -q "$fat"; }
need_fat() { fat_mounted || fail "$fat is not mounted"; }
menu_update() { [ -n "$root" ] || u-boot-update >/dev/null; }
crc32_of() {    # crc32_of FILE: 8 hex digits, from the trailer gzip writes
    gzip -1 -c "$1" | tail -c 8 | head -c 4 | od -An -tx4 | tr -d ' \n'
}
confirm() {     # confirm QUESTION: ask on the terminal, unless --force was given
    [ "$force" = yes ] && return 0
    printf '%s [y/N] ' "$1"
    read -r answer || answer=
    case $answer in y|Y|yes) ;; *) fail "nothing changed" ;; esac
}
put() {         # put FROM TO: copy, compare, and only then replace TO
    cp "$1" "$2.new"
    cmp -s "$1" "$2.new" || { rm -f "$2.new"; fail "copying $1 to ${2%/*} failed"; }
    mv "$2.new" "$2"
}
version_of() {  # version_of PACKAGE: its version, or nothing
    [ -n "$root" ] || dpkg-query -W -f='${Version}' "$1" 2>/dev/null || true
}

# The core that is running: its overlay, which U-Boot applies only when the core image has
# loaded, carries the core's name and the name of the boot package it loads on.
running_core() { [ ! -r "$chosen/de25-nano,core" ] || tr -d '\000' < "$chosen/de25-nano,core"; }
running_boot() { [ ! -r "$chosen/de25-nano,boot" ] || tr -d '\000' < "$chosen/de25-nano,boot"; }
# A core is also running when the frame buffer of an overlay without those names is there:
# that is the core of release 0.1, or one put on the card by hand.
unnamed_core_running() {
    [ -z "$(running_core)" ] && ls "$chosen" 2>/dev/null | grep -q '^framebuffer@'
}

# The core selected to load at boot: fpga.rbf on the FAT partition, with its name beside it.
selected_core() {
    [ -f "$fat/fpga.rbf" ] || return 0
    name=$(sed -n 's/^core=//p' "$selected_txt" 2>/dev/null) || name=
    echo "${name:-unknown}"
}

boot_names() { for d in "$lib"/boot/*/; do [ -f "$d/hps.rpd" ] && basename "$d"; done 2>/dev/null; true; }
core_names() { for d in "$lib"/core/*/; do [ -f "$d/fpga.rbf" ] && basename "$d"; done 2>/dev/null; true; }

flash_handed_over() { [ -e "$mtd" ]; }
flash_holds() {  # flash_holds FILE: the flash starts with exactly these bytes
    [ -r "$mtd" ] && cmp -s -n "$(stat -c %s "$1")" "$mtd" "$1"
}
# The boot package whose HPS image the flash holds exactly, or nothing.
flash_boot() {
    for b in $(boot_names); do
        if flash_holds "$lib/boot/$b/hps.rpd"; then echo "$b"; return; fi
    done
}
# The boot package a waiting flash write is for, or nothing.
pending_boot() {
    [ -f "$request" ] || return 0
    sed -n 's/^flash_new_boot=//p' "$request_txt" 2>/dev/null || true
}

# fits BOOT: can it be shown that a core for that boot package will load? Sets $why.
fits() {
    if [ "$(running_boot)" = "$1" ]; then
        why="the core now running loads on the same HPS image"; return 0
    fi
    if [ "$(pending_boot)" = "$1" ]; then
        why="a flash write of that HPS image is waiting for the next boot"; return 0
    fi
    if flash_holds "$lib/boot/$1/hps.rpd"; then
        why="the flash holds that HPS image"; return 0
    fi
    if ! flash_handed_over; then
        why="the flash holds the factory contents, or others that keep it from the SoC"
    elif [ ! -r "$mtd" ]; then
        why="the flash cannot be read (not root)"
    else
        why="the flash does not hold the HPS image of de25-nano-boot-$1 as installed, and no core that needs it is running"
    fi
    return 1
}
