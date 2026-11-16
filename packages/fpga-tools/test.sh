#!/bin/sh
# Test de25-fpga and de25-flash off the board, against a made-up card and a file standing in
# for the flash (DE25_TEST_ROOT, see common.sh). Usage: packages/fpga-tools/test.sh
set -eu
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export DE25_TEST_ROOT=$t DE25_COMMON=$here/common.sh
fpga() { sh "$here/de25-fpga" "$@"; }
flash() { sh "$here/de25-flash" "$@"; }
n=0
ok() { n=$((n + 1)); echo "ok $n: $1"; }
bad() { echo "FAILED: $1" >&2; exit 1; }
expect() { # expect PATTERN DESCRIPTION -- COMMAND...
    pat=$1; what=$2; shift 3
    out=$("$@" 2>&1) || true
    echo "$out" | grep -q -- "$pat" || { echo "$out" >&2; bad "$what (wanted: $pat)"; }
    ok "$what"
}
refuse() { # refuse DESCRIPTION -- COMMAND...: it must fail
    what=$1; shift 2
    if "$@" >/dev/null 2>&1; then bad "$what"; fi
    ok "$what"
}
blob() { head -c "$2" /dev/urandom > "$1"; }
mkboot() { d=$t/usr/lib/de25-nano/boot/$1; mkdir -p "$d"; blob "$d/hps.rpd" 4096; blob "$d/u-boot.itb" 512; blob "$d/boot.scr" 128; }
mkcore() { d=$t/usr/lib/de25-nano/core/$1; mkdir -p "$d"; blob "$d/fpga.rbf" 2048; blob "$d/fpga.dtbo" 256; echo "$2" > "$d/boot"; }
running() { mkdir -p "$t/proc/device-tree/chosen"; printf '%s\0' "$1" > "$t/proc/device-tree/chosen/de25-nano,core"; printf '%s\0' "$2" > "$t/proc/device-tree/chosen/de25-nano,boot"; }
not_running() { rm -rf "$t/proc/device-tree"; }
reboot_() { echo "boot-$n" > "$t/proc/sys/kernel/random/boot_id"; }
mkdir -p "$t/boot/firmware" "$t/boot/dtbo" "$t/dev" "$t/proc/sys/kernel/random"
reboot_
mkboot base; mkcore base base; mkcore tic base; mkboot other; mkcore odd other
lib=$t/usr/lib/de25-nano; fat=$t/boot/firmware
blob "$fat/u-boot.itb" 512; blob "$fat/boot.scr" 128     # as an older image left them

echo "# A factory board: no /dev/mtd0"
expect "Selected core: none" "status with nothing selected" -- fpga status
expect "kept from the SoC" "flash status on a factory board" -- flash status
refuse "select is refused before the flash is written" -- fpga select base
[ ! -e "$fat/fpga.rbf" ] || bad "a refused select left fpga.rbf"
refuse "write needs a name when two boot packages are installed" -- flash write --force
expect "will be written at the next boot" "write leaves a request for U-Boot" -- flash write --force base
cmp -s "$lib/boot/base/hps.rpd" "$fat/write-on-boot.rpd" || bad "write-on-boot.rpd"
grep -q "^flash_new_crc=$(gzip -1 -c "$lib/boot/base/hps.rpd" | tail -c 8 | head -c 4 | od -An -tx4 | tr -d ' \n')\$" "$fat/write-on-boot.txt" || bad "crc32 in write-on-boot.txt"
cmp -s "$lib/boot/base/u-boot.itb" "$fat/u-boot.itb" || bad "u-boot.itb not put on the card"
[ -f "$fat/u-boot-previous.itb" ] || bad "the previous u-boot.itb was not kept"
expect "waiting for the next boot (de25-nano-boot-base)" "status shows the waiting write" -- flash status
expect "fits: a flash write" "select is accepted while the write waits" -- fpga select base
refuse "a core for another boot package is still refused" -- fpga select odd
expect "will be loaded at the next boot" "status before the reboot" -- fpga status

echo "# After U-Boot wrote the flash and the power cycle: the core runs"
rm "$fat/write-on-boot.rpd" "$fat/write-on-boot.txt"; blob "$fat/saved-0badcafe.rpd" 64
head -c 16777216 /dev/zero > "$t/dev/mtd0"; dd if="$lib/boot/base/hps.rpd" of="$t/dev/mtd0" conv=notrunc status=none
reboot_; running base base
expect "Running core: base, on the HPS image of de25-nano-boot-base" "status with the core running" -- fpga status
expect "base .*selected, running" "list" -- fpga list
expect "holds the HPS image of de25-nano-boot-base" "flash status" -- flash status
expect "nothing to do" "write when flash and card are current" -- flash write --force base
expect "fits: the core now running" "select another core for the same HPS image" -- fpga select tic
cmp -s "$lib/core/tic/fpga.rbf" "$fat/fpga.rbf" && cmp -s "$lib/core/tic/fpga.dtbo" "$t/boot/dtbo/fpga.dtbo" || bad "tic not put in place"

echo "# Upgrades"
blob "$lib/core/tic/fpga.rbf" 2048
expect "has been updated" "an upgrade of the selected core is put in place" -- fpga hook configure tic
cmp -s "$lib/core/tic/fpga.rbf" "$fat/fpga.rbf" || bad "upgraded tic not put in place"
blob "$lib/core/base/fpga.rbf" 2048
[ -z "$(fpga hook configure base)" ] || bad "an upgrade of an unselected core did something"
ok "an upgrade of an unselected core does nothing"
blob "$lib/boot/base/u-boot.itb" 512
expect "have been renewed" "a boot upgrade with the same HPS image renews the card" -- flash sync
cmp -s "$lib/boot/base/u-boot.itb" "$fat/u-boot.itb" || bad "u-boot.itb not renewed"
blob "$lib/boot/base/hps.rpd" 4096; blob "$lib/boot/base/u-boot.itb" 512; cp "$fat/u-boot.itb" "$t/itb-before"
expect "left as they are" "a boot upgrade with a new HPS image leaves the card alone" -- flash sync
cmp -s "$t/itb-before" "$fat/u-boot.itb" || bad "sync changed u-boot.itb although the flash differs"
expect "not the build now installed" "status: an older build of the same boot package" -- flash status
expect "fits: the core now running" "a core still fits an older build of its HPS image" -- fpga select base
expect "written and verified" "write from Linux" -- flash write --force base
cmp -s -n 4096 "$t/dev/mtd0" "$lib/boot/base/hps.rpd" || bad "the flash was not written"
cmp -s "$lib/boot/base/u-boot.itb" "$fat/u-boot.itb" || bad "u-boot.itb not renewed with the flash"

echo "# A mismatch"
expect "is selected without a check" "select --force" -- fpga select --force odd
reboot_; not_running
expect "selected but is not running" "status after a refused core" -- fpga status
expect "No core will be loaded" "disable" -- fpga disable
[ ! -e "$fat/fpga.rbf" ] && [ ! -e "$t/boot/dtbo/fpga.dtbo" ] || bad "disable left files"
refuse "nothing running, flash holds another image: select odd is refused" -- fpga select odd
expect "fits: the flash holds that HPS image" "nothing running: select by reading the flash" -- fpga select base
running base base
expect "being removed" "removing the selected core's package disables it" -- fpga hook remove base
[ ! -e "$fat/fpga.rbf" ] || bad "remove left fpga.rbf"

echo "# Restore"
refuse "restore refuses a file that is not what its name says" -- flash restore --force
head -c 16777216 /dev/urandom > "$t/factory"; crc=$(gzip -1 -c "$t/factory" | tail -c 8 | head -c 4 | od -An -tx4 | tr -d ' \n')
rm "$fat/saved-0badcafe.rpd"; cp "$t/factory" "$fat/saved-$crc.rpd"
fpga select base >/dev/null
expect "written and verified" "restore" -- flash restore --force
cmp -s "$t/factory" "$t/dev/mtd0" || bad "restore did not write the flash"
[ ! -e "$fat/fpga.rbf" ] || bad "restore left a core selected"
echo "all $n tests passed"
